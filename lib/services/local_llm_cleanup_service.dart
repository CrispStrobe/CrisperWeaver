// LocalLlmCleanupService — PLAN §5.1.6 v3 (local on-device path).
//
// On-device chat-LLM cleanup pass over each segment, backed by
// CrispASR's chat ABI (libcrispasr 0.7.0+). Mirrors
// CloudLlmCleanupService's surface — cleanupSegment /
// cleanupBatch / CleanupCancelToken — so the Tidy dialog can
// route to either path interchangeably.
//
// Why: this is the BYOK-but-without-the-K story. The user
// points at a GGUF chat model on disk, the service loads it
// once per app session (held warm in a dedicated worker
// isolate), and every Tidy / Summarize click reuses it. No
// network, no API keys, no per-segment latency cliff.
//
// Why a backend interface instead of just using the worker
// isolate directly: tests inject a `_StubLocalLlmBackend` that
// answers from a closure, so we get full coverage of the
// service logic (config gating, batch cancellation, per-segment
// error swallowing, config-change → reopen) without spawning
// real isolates or needing a libcrispasr build with the chat
// ABI on the test host. Production wires up
// `IsolateLocalLlmBackend` automatically via the Riverpod
// provider at the bottom of this file.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_llm_cleanup_service.dart' show CleanupCancelToken;
import 'local_llm_backend.dart';
import 'log_service.dart';

// Re-export so callers only import this file. The Tidy / Summarize
// surfaces already import `cloud_llm_cleanup_service.dart` for the
// cancel token; sharing the same token type keeps the call sites
// uniform across cloud / local modes.
export 'cloud_llm_cleanup_service.dart' show CleanupCancelToken;
export 'local_llm_backend.dart';

class LocalLlmDisabledException implements Exception {
  const LocalLlmDisabledException(this.reason);
  final String reason;
  @override
  String toString() => 'LocalLlmDisabledException: $reason';
}

class LocalLlmException implements Exception {
  const LocalLlmException(this.kind, this.message);
  final String kind; // 'unsupported' | 'open_failed' | 'generate_failed' | 'closed'
  final String message;
  @override
  String toString() => 'LocalLlmException($kind): $message';
}

/// Pure value config — same pattern as CloudLlmConfig. Callers
/// build it from SettingsService each pass so a settings change
/// (model swap, advanced-params nudge) takes effect on the
/// next pass without a restart.
class LocalLlmConfig {
  const LocalLlmConfig({
    required this.modelPath,
    this.nThreads,
    this.nThreadsBatch,
    this.nCtx,
    this.nBatch,
    this.nUbatch,
    this.nGpuLayers,
    this.useMmap = true,
    this.useMlock = false,
    this.chatTemplate,
    this.maxTokens = 512,
    this.temperature = 0.0,
    this.topK = 40,
    this.topP = 0.95,
    this.minP = 0.05,
    this.repeatPenalty = 1.1,
    this.stop = const [],
  });

  final String modelPath;
  final int? nThreads;
  final int? nThreadsBatch;
  final int? nCtx;
  final int? nBatch;
  final int? nUbatch;
  /// -1 = all layers on GPU (default), 0 = CPU only.
  final int? nGpuLayers;
  final bool useMmap;
  final bool useMlock;
  /// Override the chat template baked into the GGUF. `null` →
  /// upstream reads `tokenizer.chat_template`, falling back to chatml.
  final String? chatTemplate;
  final int maxTokens;
  final double temperature;
  final int topK;
  final double topP;
  final double minP;
  final double repeatPenalty;
  /// Stop substrings — generation halts when any of these appear
  /// in the output. Useful for preventing LLM runaway past the
  /// expected response boundary.
  final List<String> stop;

  bool get enabled => modelPath.isNotEmpty;

  /// Open-side fingerprint — only these fields force a session
  /// rebuild. Sampling params (temperature/topK/etc.) are passed
  /// per call so a tweak there doesn't unload the model.
  String get openFingerprint => [
        modelPath,
        nThreads,
        nThreadsBatch,
        nCtx,
        nBatch,
        nUbatch,
        nGpuLayers,
        useMmap,
        useMlock,
        chatTemplate ?? '',
      ].join('|');

  Map<String, Object?> toOpenParamsMap() => <String, Object?>{
        if (nThreads != null) 'nThreads': nThreads,
        if (nThreadsBatch != null) 'nThreadsBatch': nThreadsBatch,
        if (nCtx != null) 'nCtx': nCtx,
        if (nBatch != null) 'nBatch': nBatch,
        if (nUbatch != null) 'nUbatch': nUbatch,
        if (nGpuLayers != null) 'nGpuLayers': nGpuLayers,
        'useMmap': useMmap,
        'useMlock': useMlock,
        if (chatTemplate != null) 'chatTemplate': chatTemplate,
      };

  Map<String, Object?> toGenerateParamsMap() => <String, Object?>{
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topK': topK,
        'topP': topP,
        'minP': minP,
        'repeatPenalty': repeatPenalty,
        if (stop.isNotEmpty) 'stop': stop,
      };
}

class LocalLlmCleanupService {
  /// Test seam — pass a stub backend; production calls fall
  /// through to a fresh `IsolateLocalLlmBackend` per service
  /// instance (created lazily on first ensureOpen).
  LocalLlmCleanupService({LocalLlmBackend? backend})
      : _backend = backend ?? IsolateLocalLlmBackend();

  final LocalLlmBackend _backend;
  String? _openedFingerprint;

  /// Same wording as CloudLlmCleanupService's `_systemPrompt`.
  /// Local-LLM behaviour is more variable than a frontier
  /// cloud model — being explicit about "no rewording, no
  /// expansion" matters more here, not less.
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

  /// Open / reopen the underlying session if the config has
  /// changed since last call. No-op otherwise. Idempotent.
  Future<void> ensureOpen(LocalLlmConfig config) async {
    if (!config.enabled) {
      throw const LocalLlmDisabledException('modelPath is empty');
    }
    final fp = config.openFingerprint;
    if (_openedFingerprint == fp && _backend.isOpen) return;
    await _backend.open(config);
    _openedFingerprint = fp;
  }

  /// Clean one segment. Throws LocalLlmDisabledException if the
  /// config is empty (modelPath unset), LocalLlmException on
  /// any session / generation error.
  ///
  /// When [onToken] is non-null, token deltas are streamed as
  /// they arrive from the worker so the UI can show incremental
  /// output. The full cleaned text is still returned as the
  /// future's value.
  Future<String> cleanupSegment({
    required String text,
    required LocalLlmConfig config,
    String? contextHint,
    void Function(String delta)? onToken,
  }) async {
    if (!config.enabled) {
      throw const LocalLlmDisabledException('modelPath is empty');
    }
    if (text.trim().isEmpty) return text;

    await ensureOpen(config);
    // Reset the KV cache before each segment — every Tidy call
    // is independent of the previous segment's content, and
    // skipping reset would leak context across boundaries.
    await _backend.reset();

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt},
      if (contextHint != null && contextHint.isNotEmpty)
        {'role': 'system', 'content': 'Context: $contextHint'},
      {'role': 'user', 'content': text},
    ];

    if (onToken != null) {
      final buf = StringBuffer();
      await for (final delta in _backend.generateStream(
        messages: messages,
        generateParams: config.toGenerateParamsMap(),
      )) {
        buf.write(delta);
        onToken(delta);
      }
      return buf.toString().trim();
    }

    final out = await _backend.generate(
      messages: messages,
      generateParams: config.toGenerateParamsMap(),
    );
    return out.trim();
  }

  /// Cleanup a batch sequentially with a cancellation token.
  /// Calls [onProgress] after each segment so the UI can show
  /// "Cleaning 5 of 20…". Errors are logged + swallowed
  /// per-segment so one bad generation doesn't abort the whole
  /// pass; the offending segment falls through unchanged.
  Future<List<String>> cleanupBatch({
    required List<String> texts,
    required LocalLlmConfig config,
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
      } on LocalLlmDisabledException {
        // Disabled is not a per-segment problem; surface to the
        // caller so it can show a "configure first" snackbar.
        rethrow;
      } catch (e, st) {
        Log.instance.w('local-llm', 'segment cleanup failed',
            fields: {'index': i}, error: e, stack: st);
        out.add(texts[i]); // fall through unchanged
      }
      onProgress?.call(i + 1, texts.length);
    }
    return out;
  }

  Future<void> dispose() => _backend.dispose();
}

final localLlmCleanupServiceProvider =
    Provider<LocalLlmCleanupService>((ref) {
  final svc = LocalLlmCleanupService();
  ref.onDispose(svc.dispose);
  return svc;
});
