// CloudLlmCleanupService — PLAN §5.1.6 v2 (BYOK cloud path).
//
// Calls an OpenAI-compatible /v1/chat/completions endpoint to
// run a context-aware cleanup pass over each segment. Pure-Dart
// HTTP, no FFI, no platform channels. Strictly opt-in: the
// service throws `CloudLlmDisabledException` when either URL
// or API key is empty, so callers can gate the UI affordance
// behind a single check.
//
// Why an OpenAI-compatible endpoint instead of a vendor-specific
// shape: it's the de-facto interop format. Same code path
// works against OpenAI directly, Anthropic via the official
// `messages.openai_compat` proxy, OpenRouter, Groq, Together,
// llama-server, vLLM, the OpenAI-compatible server CrisperWeaver
// itself will eventually grow for the local-LLM path (§5.1.6 v3).
//
// Scope of v1:
// - one-shot per-segment cleanup (no streaming, no batch packing)
// - cancellable via CancelToken
// - hard 30 s per-call timeout; failures bubble up so the caller
//   can decide whether to fall back to the cleaned-but-not-LLM-
//   passed text or skip that segment.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../constants/build_flavor.dart';
import 'ai_http_client.dart';
import 'log_service.dart';

class CloudLlmDisabledException implements Exception {
  const CloudLlmDisabledException(this.reason);
  final String reason;
  @override
  String toString() => 'CloudLlmDisabledException: $reason';
}

class CloudLlmHttpException implements Exception {
  CloudLlmHttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() =>
      'CloudLlmHttpException(status=$statusCode): $body';
}

/// Cancellation handle for batch cleanup. The UI flips
/// `cancelled = true` when the user dismisses; the service
/// checks the flag between segments and bails out.
class CleanupCancelToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// Pure value config — the service reads URL / key / model
/// from here rather than holding mutable state. Caller builds
/// it from SettingsService each time so a settings change
/// takes effect on the next cleanup pass without a restart.
class CloudLlmConfig {
  const CloudLlmConfig({
    required this.apiUrl,
    required this.apiKey,
    required this.model,
    this.timeout = const Duration(seconds: 30),
    this.maxOutputTokens = 1024,
    this.temperature = 0.0,
  });

  final String apiUrl;
  final String apiKey;
  final String model;
  final Duration timeout;
  final int maxOutputTokens;
  final double temperature;

  bool get enabled =>
      apiUrl.isNotEmpty &&
      BuildFlavor.allowsAiEndpoint(apiUrl) &&
      BuildFlavor.allowsHttpModel(model) &&
      (apiKey.isNotEmpty || BuildFlavor.isLite);
}

class CloudLlmCleanupService {
  /// Test seam — pass a mock client; production calls fall
  /// through to a fresh `http.Client()` per pass.
  CloudLlmCleanupService({http.Client? client})
      : _client = AiHttpClient(client: client);

  final http.Client _client;

  /// System prompt sent on every request. Asks for verbatim
  /// cleanup, no rewording, no expansion, preserving original
  /// language and meaning. Conservative on purpose — the
  /// LLM's role is to clean what the deterministic v1 missed
  /// (mis-heard named entities, broken sentence boundaries,
  /// terminology consistency), not to rewrite the user's words.
  static const String _systemPrompt =
      'You are a transcript editor. Clean up the following ASR '
      'output verbatim:\n'
      '- preserve the speaker\'s words, meaning, and language\n'
      '- fix obvious mishearings of named entities only when '
      'context makes the correct word certain\n'
      '- fix sentence boundaries (commas, periods, capitalisation)\n'
      '- remove filler words only when they\'re clearly fillers\n'
      '- never paraphrase, expand, or summarise\n'
      '- never add information not present in the input\n'
      '- respond with the cleaned text only, no commentary, no '
      'markdown, no quotation marks';

  /// Clean one segment. Throws CloudLlmDisabledException if
  /// the config is incomplete, CloudLlmHttpException on non-2xx,
  /// TimeoutException on slow server.
  Future<String> cleanupSegment({
    required String text,
    required CloudLlmConfig config,
    String? contextHint,
  }) async {
    if (!config.enabled) {
      throw const CloudLlmDisabledException(
          'HTTP LLM endpoint is unavailable or incomplete');
    }
    if (text.trim().isEmpty) return text;
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
      if (contextHint != null && contextHint.isNotEmpty)
        {'role': 'system', 'content': 'Context: $contextHint'},
      {'role': 'user', 'content': text},
    ];
    final body = jsonEncode(<String, dynamic>{
      'model': config.model,
      'messages': messages,
      'temperature': config.temperature,
      'max_tokens': config.maxOutputTokens,
    });
    final uri = Uri.parse(config.apiUrl);
    final res = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (config.apiKey.isNotEmpty)
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
          res.statusCode, 'choice has no message object');
    }
    final content = message['content'];
    if (content is! String) {
      throw CloudLlmHttpException(
          res.statusCode, 'message content is not a string');
    }
    return content.trim();
  }

  /// Cleanup a batch sequentially with a cancellation token.
  /// Calls [onProgress] after each segment so the UI can show
  /// "Cleaning 5 of 20…". Errors are logged + swallowed
  /// per-segment so one transient failure doesn't abort the
  /// whole pass; the offending segment falls through unchanged.
  Future<List<String>> cleanupBatch({
    required List<String> texts,
    required CloudLlmConfig config,
    required CleanupCancelToken cancel,
    void Function(int doneCount, int total)? onProgress,
  }) async {
    final out = <String>[];
    for (var i = 0; i < texts.length; i++) {
      if (cancel.cancelled) break;
      try {
        final cleaned = await cleanupSegment(
            text: texts[i], config: config);
        out.add(cleaned);
      } catch (e, st) {
        Log.instance.w('cloud-llm', 'segment cleanup failed',
            fields: {'index': i}, error: e, stack: st);
        out.add(texts[i]); // fall through unchanged
      }
      onProgress?.call(i + 1, texts.length);
    }
    return out;
  }

  void dispose() => _client.close();
}

final cloudLlmCleanupServiceProvider =
    Provider<CloudLlmCleanupService>((ref) {
  final svc = CloudLlmCleanupService();
  ref.onDispose(svc.dispose);
  return svc;
});
