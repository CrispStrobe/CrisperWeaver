// TranscriptSummarizeService — PLAN §5.1.8.
//
// Meeting-style summarisation on top of the same BYOK cloud
// LLM endpoint §5.1.6 v2 uses. Pure-Dart HTTP, no FFI, no
// platform channels. Strictly opt-in: gated behind the same
// `CloudLlmConfig.enabled` check as the cleanup pass.
//
// Output shape: structured Markdown rather than JSON. Markdown
// is robust to small model-output deviations (one missing
// comma doesn't break the whole parse); we recover the
// sections by splitting on H2 headers. Each section is a list
// of bullet-point lines verbatim, which is what 99% of the
// downstream consumers (copy-to-clipboard, render in a
// dialog) actually want.
//
// Three output types:
//   - actionItems   — discrete next-steps with implicit / explicit
//                     owner where present
//   - keyTopics     — bullet list of topics discussed
//   - decisions     — bullet list of decisions made
//
// A composed "everything" mode runs all three sections in one
// LLM call to amortise prompt-overhead; the caller renders
// whichever sections it asked for.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'cloud_llm_cleanup_service.dart' show CloudLlmConfig, CloudLlmHttpException, CloudLlmDisabledException;
import 'local_llm_backend.dart';
import 'local_llm_cleanup_service.dart'
    show LocalLlmConfig, LocalLlmDisabledException;

/// What the caller wants out of one summarisation pass. The
/// service composes a single LLM call that asks for the union
/// of the requested sections; the response Markdown is split
/// back into the per-section bullet lists.
enum SummaryKind { actionItems, keyTopics, decisions }

/// Parsed result. Each list holds the raw bullet text per row,
/// stripped of the leading `- ` / `* ` marker. The order
/// matches what the model emitted.
class SummaryResult {
  const SummaryResult({
    this.actionItems = const [],
    this.keyTopics = const [],
    this.decisions = const [],
    this.rawMarkdown = '',
  });

  final List<String> actionItems;
  final List<String> keyTopics;
  final List<String> decisions;

  /// The original Markdown from the model — keep it so the UI
  /// can render verbatim when the user wants the full document
  /// rather than the dissected section lists.
  final String rawMarkdown;

  bool get isEmpty =>
      actionItems.isEmpty && keyTopics.isEmpty && decisions.isEmpty;
}

class TranscriptSummarizeService {
  /// [client] — test seam for the cloud (HTTP) path.
  /// [localBackend] — test seam for the local (FFI) path. In
  /// production this is null and the service lazily resolves
  /// one through the LocalLlmCleanupService provider chain;
  /// tests pass a stub LocalLlmBackend so they can exercise
  /// the local-summarise path without spawning real isolates
  /// or loading a GGUF.
  TranscriptSummarizeService({
    http.Client? client,
    LocalLlmBackend? localBackend,
  })  : _client = client ?? http.Client(),
        _injectedLocalBackend = localBackend;

  final http.Client _client;
  final LocalLlmBackend? _injectedLocalBackend;
  LocalLlmBackend? _ownedLocalBackend;
  String? _localOpenFingerprint;

  /// Returns the active local backend — the injected one when
  /// tests provided it, otherwise a lazily-created
  /// IsolateLocalLlmBackend owned by this service for the rest
  /// of its lifetime. We keep it warm across summarizeLocal
  /// calls so the model only loads once per app session;
  /// dispose() shuts it down on app teardown.
  LocalLlmBackend _localBackend() {
    if (_injectedLocalBackend != null) return _injectedLocalBackend;
    return _ownedLocalBackend ??= IsolateLocalLlmBackend();
  }

  /// Headers used to split the response. Same casing the
  /// prompt requests — the model is reliable enough at
  /// matching them given temperature=0 and explicit
  /// instructions, but we tolerate case differences during
  /// parsing too.
  static const String _h2Action = '## Action Items';
  static const String _h2Topics = '## Key Topics';
  static const String _h2Decisions = '## Decisions';

  /// Build a system prompt that asks for exactly the requested
  /// sections, in exactly the expected Markdown shape. The
  /// "no commentary" + "if a section has no content, write
  /// 'None'" rules make the output predictable; the parser
  /// then ignores 'None' rows by emptying the list.
  String _buildPrompt(Set<SummaryKind> kinds) {
    final wantsAction = kinds.contains(SummaryKind.actionItems);
    final wantsTopics = kinds.contains(SummaryKind.keyTopics);
    final wantsDecisions = kinds.contains(SummaryKind.decisions);
    final parts = <String>[];
    parts.add(
        'You are a meeting-notes assistant. Given a transcript, produce a '
        'concise structured summary in Markdown with the exact headers and '
        'bullet-point format below.');
    parts.add('Rules:');
    parts.add('- Use the exact H2 headers shown. Do not add any other '
        'sections, preamble, or trailing commentary.');
    parts.add('- Each item is a single bullet starting with "- ".');
    parts.add('- If a section has no content, write "None" as the only '
        'bullet under it.');
    parts.add('- Be concise. Preserve names, numbers, and concrete '
        'commitments. Do not invent information not present in the '
        'transcript.');
    parts.add('- Match the transcript\'s language.');
    parts.add('');
    parts.add('Required sections (in this exact order):');
    if (wantsAction) {
      parts.add(_h2Action);
      parts.add('- one bullet per concrete next-step. Include the owner in '
          'parentheses when stated, e.g. "Send the report (Alice)". One '
          'line each.');
    }
    if (wantsTopics) {
      parts.add(_h2Topics);
      parts.add(
          '- one bullet per high-level topic discussed. Keep each to a '
          'noun phrase.');
    }
    if (wantsDecisions) {
      parts.add(_h2Decisions);
      parts.add(
          '- one bullet per concrete decision made. Phrase as a complete '
          'sentence.');
    }
    return parts.join('\n');
  }

  /// One-shot summarise. Throws CloudLlmDisabledException when
  /// config is incomplete, CloudLlmHttpException on non-2xx,
  /// TimeoutException on slow server. Per-section parse never
  /// throws — when a header is missing the corresponding list
  /// is just empty.
  Future<SummaryResult> summarize({
    required String transcript,
    required Set<SummaryKind> kinds,
    required CloudLlmConfig config,
  }) async {
    if (!config.enabled) {
      throw const CloudLlmDisabledException(
          'apiUrl or apiKey is empty');
    }
    if (transcript.trim().isEmpty || kinds.isEmpty) {
      return const SummaryResult();
    }
    final body = jsonEncode(<String, dynamic>{
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': _buildPrompt(kinds)},
        {'role': 'user', 'content': transcript},
      ],
      'temperature': 0.0,
      // 4096 is enough headroom for a half-hour meeting summary
      // (~30 bullets across three sections) without blowing
      // through any common provider's max-out cap.
      'max_tokens': 4096,
    });
    final res = await _client
        .post(
          Uri.parse(config.apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: body,
        )
        .timeout(config.timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw CloudLlmHttpException(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw CloudLlmHttpException(res.statusCode,
          'response body is not a JSON object: ${res.body}');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw CloudLlmHttpException(
          res.statusCode, 'no choices in response: ${res.body}');
    }
    final first = choices[0];
    if (first is! Map) {
      throw CloudLlmHttpException(
          res.statusCode, 'first choice is not an object');
    }
    final message = first['message'];
    if (message is! Map) {
      throw CloudLlmHttpException(
          res.statusCode, 'choice has no message');
    }
    final content = message['content'];
    if (content is! String) {
      throw CloudLlmHttpException(
          res.statusCode, 'message content is not a string');
    }
    return parseMarkdown(content);
  }

  /// §5.1.6 v3 — local-LLM mirror of [summarize]. Same prompt,
  /// same Markdown shape, same parser; differs only in the
  /// transport (FFI worker isolate via LocalLlmBackend instead
  /// of HTTP).
  ///
  /// The local backend is created once and reused — the summary
  /// pass typically takes seconds to minutes against a 3B+
  /// GGUF, but every subsequent summary in the same session
  /// skips the model-load cost.
  ///
  /// When [onToken] is non-null, token deltas are streamed as
  /// they arrive so the UI can render the summary incrementally
  /// while generation continues.
  Future<SummaryResult> summarizeLocal({
    required String transcript,
    required Set<SummaryKind> kinds,
    required LocalLlmConfig config,
    void Function(String delta)? onToken,
  }) async {
    if (!config.enabled) {
      throw const LocalLlmDisabledException('modelPath is empty');
    }
    if (transcript.trim().isEmpty || kinds.isEmpty) {
      return const SummaryResult();
    }
    final backend = _localBackend();
    final fp = config.openFingerprint;
    if (_localOpenFingerprint != fp || !backend.isOpen) {
      await backend.open(config);
      _localOpenFingerprint = fp;
    }
    // Clear KV before the summary turn — each summarizeLocal
    // call is independent of any prior cleanup turn that may
    // have shared the session.
    await backend.reset();
    // Headroom for summary output. Local models often need
    // more tokens than the cloud path to produce a full
    // structured response; honour the user's per-call cap from
    // config, but floor at 1024 so a default config doesn't
    // truncate mid-bullet.
    final genParams = <String, Object?>{
      ...config.toGenerateParamsMap(),
      'maxTokens': config.maxTokens < 1024 ? 1024 : config.maxTokens,
    };
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _buildPrompt(kinds)},
      {'role': 'user', 'content': transcript},
    ];

    final String out;
    if (onToken != null) {
      final buf = StringBuffer();
      await for (final delta in backend.generateStream(
        messages: messages,
        generateParams: genParams,
      )) {
        buf.write(delta);
        onToken(delta);
      }
      out = buf.toString();
    } else {
      out = await backend.generate(
        messages: messages,
        generateParams: genParams,
      );
    }
    return parseMarkdown(out);
  }

  /// Pure parser — split structured-Markdown into sections.
  /// Exposed so tests can pin the parser behaviour without
  /// going through the HTTP path.
  SummaryResult parseMarkdown(String markdown) {
    final action = <String>[];
    final topics = <String>[];
    final decisions = <String>[];

    String? currentSection;
    for (final raw in const LineSplitter().convert(markdown)) {
      final line = raw.trimRight();
      final lower = line.trim().toLowerCase();
      if (lower.startsWith('## action item')) {
        currentSection = 'action';
        continue;
      }
      if (lower.startsWith('## key topic') ||
          lower.startsWith('## topics')) {
        currentSection = 'topics';
        continue;
      }
      if (lower.startsWith('## decision')) {
        currentSection = 'decisions';
        continue;
      }
      // Bullet rows
      String? bullet;
      final t = line.trimLeft();
      if (t.startsWith('- ')) {
        bullet = t.substring(2).trim();
      } else if (t.startsWith('* ')) {
        bullet = t.substring(2).trim();
      } else if (RegExp(r'^\d+\.\s').hasMatch(t)) {
        bullet = t.replaceFirst(RegExp(r'^\d+\.\s+'), '').trim();
      }
      if (bullet == null || bullet.isEmpty) continue;
      // "None" placeholder fed by our own prompt rule —
      // suppress so the result list is genuinely empty.
      if (bullet.toLowerCase() == 'none') continue;
      switch (currentSection) {
        case 'action':
          action.add(bullet);
          break;
        case 'topics':
          topics.add(bullet);
          break;
        case 'decisions':
          decisions.add(bullet);
          break;
        default:
          // Bullets before any H2 — ignored. Model is supposed
          // to not produce them, but be tolerant.
          break;
      }
    }
    return SummaryResult(
      actionItems: List.unmodifiable(action),
      keyTopics: List.unmodifiable(topics),
      decisions: List.unmodifiable(decisions),
      rawMarkdown: markdown,
    );
  }

  void dispose() {
    _client.close();
    // Tear down the locally-owned backend; an injected one is
    // the caller's responsibility (test fixtures clean up
    // their own).
    final owned = _ownedLocalBackend;
    if (owned != null) {
      // Fire-and-forget — disposal is async but the Riverpod
      // provider that owns us doesn't expose a Future-returning
      // dispose hook, and we don't want to block app shutdown.
      // The worker isolate will exit when it receives shutdown.
      // ignore: unawaited_futures
      owned.dispose();
      _ownedLocalBackend = null;
    }
  }
}

final transcriptSummarizeServiceProvider =
    Provider<TranscriptSummarizeService>((ref) {
  final svc = TranscriptSummarizeService();
  ref.onDispose(svc.dispose);
  return svc;
});
