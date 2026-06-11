// TranscriptionWorker — §5.23 Q2 v2 worker isolate.
//
// Each spawned isolate holds its own DynamicLibrary + CrispasrSession
// against the same model file. Persistent — opens the session ONCE
// at spawn time then handles N transcribe requests over its
// lifetime, so the session-open cost (seconds for big models)
// amortizes over the whole batch instead of per-file.
//
// Wire-level protocol (all messages are JSON-serializable maps or
// `_FrozenSegment` records — kept simple so the cross-isolate
// boundary doesn't accidentally include closures or live FFI
// handles):
//
//   spawn(args)
//   ↓
//   Worker creates: ReceivePort for commands → sends `.sendPort`
//                   back to main as the first message on the main's
//                   ready ReceivePort. Then opens libcrispasr +
//                   session.
//   ↓
//   Worker sends: { 'type': 'ready', 'backend': '...' }
//                 OR { 'type': 'error', 'message': '...' }
//   ↓
//   Per dispatch, main sends:
//     { 'type': 'transcribe',
//       'jobId': '...',
//       'samples': Float32List (transferable),
//       'language': 'en'?, ..., 'replyPort': SendPort }
//   ↓
//   Worker streams back on replyPort:
//     { 'type': 'segment', 'segment': {...} }
//     ... repeat ...
//     { 'type': 'done', 'segments': [...] }
//   OR on failure:
//     { 'type': 'error', 'message': '...' }
//   ↓
//   To shut down, main sends:
//     { 'type': 'shutdown' }
//   The worker closes the session and the receive port, then exits.
//
// All FFI work happens on the worker isolate — the main isolate's
// CrispASREngine is untouched by this path.
//
// Cross-platform: pure dart:isolate + the existing CrispasrSession
// FFI binding, which lazy-opens libcrispasr per isolate. Identical
// behaviour on macOS / Linux / Windows / Android / iOS.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../native/crispasr_import.dart' as crispasr;

import '../engines/transcription_engine.dart';

class TranscriptionWorkerArgs {
  const TranscriptionWorkerArgs({
    required this.readySendPort,
    required this.modelPath,
    required this.backend,
    this.libName,
    this.useGpu = true,
    this.flashAttn = true,
    this.nThreads = 0,
    this.nGpuLayers = 0,
  });

  /// Port the worker uses to hand back its command-receive port
  /// (the "I'm alive, here's where to send work" handshake).
  final SendPort readySendPort;
  final String modelPath;
  final String backend;
  /// Override for the libcrispasr path. `null` (the default) lets
  /// the binding's `CrispASR.defaultLibName()` resolve per-platform
  /// (which is what every other call site does).
  final String? libName;
  final bool useGpu;
  final bool flashAttn;
  final int nThreads;
  final int nGpuLayers;
}

/// Top-level isolate entry — must be top-level (not a closure) so
/// `Isolate.spawn` can find it.
Future<void> transcriptionWorkerEntry(TranscriptionWorkerArgs args) async {
  final cmdReceive = ReceivePort();
  args.readySendPort.send(cmdReceive.sendPort);

  crispasr.CrispasrSession? session;
  try {
    // openWithParams (CrispASR 0.6.1+) is the right factory when we
    // want explicit useGpu / flashAttn / nGpuLayers — older runtimes
    // (without `crispasr_session_open_with_params`) fall back to the
    // legacy [open] factory which always uses GPU + flash-attn ON.
    try {
      session = crispasr.CrispasrSession.openWithParams(
        args.modelPath,
        nThreads: args.nThreads,
        useGpu: args.useGpu,
        flashAttn: args.flashAttn,
        nGpuLayers: args.nGpuLayers,
        backend: args.backend,
        libPath: args.libName,
      );
    } on UnsupportedError {
      session = crispasr.CrispasrSession.open(
        args.modelPath,
        nThreads: args.nThreads,
        backend: args.backend,
        libPath: args.libName,
      );
    }
    args.readySendPort.send(<String, Object?>{
      'type': 'ready',
      'backend': args.backend,
    });
  } catch (e, st) {
    args.readySendPort.send(<String, Object?>{
      'type': 'error',
      'message': 'session open failed: $e',
      'stack': st.toString(),
    });
    cmdReceive.close();
    return;
  }

  await for (final raw in cmdReceive) {
    if (raw is! Map) continue;
    final type = raw['type'];
    if (type == 'shutdown') {
      try {
        session.close();
      } catch (_) {} // FFI feature probe — silent
      cmdReceive.close();
      return;
    }
    if (type != 'transcribe') continue;

    final replyPort = raw['replyPort'] as SendPort?;
    if (replyPort == null) continue;
    final samples = raw['samples'] as Float32List?;
    if (samples == null) {
      replyPort.send(<String, Object?>{
        'type': 'error',
        'message': 'transcribe request missing samples',
      });
      continue;
    }
    final language = raw['language'] as String?;
    final targetLanguage = raw['targetLanguage'] as String?;
    final translate = raw['translate'] as bool? ?? false;
    final askPrompt = raw['askPrompt'] as String?;
    final temperature = (raw['temperature'] as num?)?.toDouble() ?? 0.0;
    final bestOf = (raw['bestOf'] as num?)?.toInt() ?? 1;
    final beamSize = (raw['beamSize'] as num?)?.toInt() ?? 1;
    final vadModelPath = raw['vadModelPath'] as String?;
    final vadThreshold = (raw['vadThreshold'] as num?)?.toDouble();
    final vadMinSpeechMs = (raw['vadMinSpeechMs'] as num?)?.toInt();
    final vadMinSilenceMs = (raw['vadMinSilenceMs'] as num?)?.toInt();
    final vadSpeechPadMs = (raw['vadSpeechPadMs'] as num?)?.toInt();
    // §5.8 — GBNF grammar-constrained sampling (whisper-only).
    // Empty string = clear any prior grammar; non-empty = parse +
    // bind + force beam search at whisper_full time.
    final grammarText = raw['grammarText'] as String? ?? '';
    final grammarRootRule = raw['grammarRootRule'] as String? ?? 'root';
    final grammarPenalty =
        (raw['grammarPenalty'] as num?)?.toDouble() ?? 100.0;
    // Whisper decoder-fallback thresholds (whisper-only; other
    // backends silently ignore).
    final entropyThold = (raw['entropyThold'] as num?)?.toDouble() ?? 2.4;
    final logprobThold = (raw['logprobThold'] as num?)?.toDouble() ?? -1.0;
    final noSpeechThold =
        (raw['noSpeechThold'] as num?)?.toDouble() ?? 0.6;
    final temperatureInc =
        (raw['temperatureInc'] as num?)?.toDouble() ?? 0.2;
    // Whisper text-suppression + prompt-carry extras (whisper-only;
    // pre-0.5.11 dylibs lack the symbol and the worker silently
    // falls through to stock whisper behaviour).
    final suppressNonSpeechTokens =
        (raw['suppressNonSpeechTokens'] as bool?) ?? false;
    final suppressTokensRegex =
        (raw['suppressTokensRegex'] as String?) ?? '';
    final carryInitialPrompt =
        (raw['carryInitialPrompt'] as bool?) ?? false;
    // §5.1.11 — Per-token alt-candidate capture (whisper greedy
    // decode only). 0 = off; pre-0.5.13 dylibs lack the setter and
    // the worker silently no-ops.
    final altN = (raw['altN'] as num?)?.toInt() ?? 0;

    try {
      // Apply sticky session-state setters before dispatch. Empty
      // strings clear; `null` / default skips so an unrelated job
      // doesn't carry over the previous one's bias. Errors from the
      // setters get swallowed because backends that don't honour a
      // particular field return rc=-2 ("not supported") which the
      // Dart binding maps to an UnsupportedError — we just continue
      // with the runtime defaults for those backends.
      if (language != null && language.isNotEmpty && language != 'auto') {
        try {
          session.setSourceLanguage(language);
        } on Object catch (_) {} // FFI feature probe — silent
      } else {
        try {
          session.setSourceLanguage('');
        } on Object catch (_) {} // FFI feature probe — silent
      }
      if (targetLanguage != null && targetLanguage.isNotEmpty) {
        try {
          session.setTargetLanguage(targetLanguage);
        } on Object catch (_) {} // FFI feature probe — silent
      } else {
        try {
          session.setTargetLanguage('');
        } on Object catch (_) {} // FFI feature probe — silent
      }
      try {
        session.setTranslate(translate);
      } on Object catch (_) {} // FFI feature probe — silent
      // setAsk always fires (even with empty string) so the
      // previous job's prompt doesn't stick across the boundary.
      try {
        session.setAsk(askPrompt ?? '');
      } on Object catch (_) {} // FFI feature probe — silent
      // Fire setTemperature on every dispatch — same reasoning as
      // setAsk; the slider's previous value mustn't leak forward.
      try {
        session.setTemperature(temperature);
      } on Object catch (_) {} // FFI feature probe — silent
      try {
        session.setBestOf(bestOf);
      } on Object catch (_) {} // FFI feature probe — silent
      // Beam search width (whisper today; other beam-capable backends
      // per the feature matrix have their session-API surface
      // tracked as a CrispASR follow-up). Older libcrispasr builds
      // without `crispasr_session_set_beam_size` raise an
      // UnsupportedError which we swallow — same pattern as the rest
      // of the sticky setters.
      try {
        session.setBeamSize(beamSize);
      } on Object catch (_) {} // FFI feature probe — silent
      // Whisper decoder-fallback thresholds. Pre-0.5.10 dylibs
      // lack the symbol — UnsupportedError gets swallowed.
      try {
        session.setFallbackThresholds(
          entropyThold: entropyThold,
          logprobThold: logprobThold,
          noSpeechThold: noSpeechThold,
          temperatureInc: temperatureInc,
        );
      } on Object catch (_) {/* old dylib or non-whisper backend */}
      // Whisper text-suppression + prompt-carry extras. Pre-0.5.11
      // dylibs lack the symbol.
      try {
        session.setWhisperDecodeExtras(
          suppressNonSpeechTokens: suppressNonSpeechTokens,
          suppressRegex: suppressTokensRegex,
          carryInitialPrompt: carryInitialPrompt,
        );
      } on Object catch (_) {/* old dylib or non-whisper backend */}
      // §5.1.11 — alt-token capture (whisper-only). Pre-0.5.13
      // dylibs lack the symbol.
      try {
        session.setAltN(altN);
      } on Object catch (_) {/* old dylib or non-whisper backend */}
      // GBNF grammar (whisper-only — the C side silently no-ops on
      // other backends because grammar_active never flips true for
      // them, but the setter itself is whisper-aware). Empty text
      // always fires too so a previous job's grammar doesn't stick.
      try {
        session.setGrammar(grammarText,
            rootRule: grammarRootRule, penalty: grammarPenalty);
      } on UnsupportedError {
        // Pre-0.5.9 dylib — log + carry on unconstrained. The C
        // side wouldn't have honoured grammar anyway.
      } on ArgumentError catch (e) {
        // Invalid GBNF / unknown root rule — surface up as an
        // error reply so the caller can show a user-actionable
        // snackbar. Other UnsupportedError / generic catches
        // continue to silently degrade.
        replyPort.send(<String, Object?>{
          'type': 'error',
          'message': 'invalid GBNF grammar: ${e.message}',
        });
        continue;
      } on Object catch (_) {/* old dylib / unsupported */}

      // VAD-on path uses transcribeVad; bare transcribe otherwise.
      // session.transcribe[Vad] are synchronous FFI calls.
      final List<crispasr.SessionSegment> segs;
      if (vadModelPath != null && vadModelPath.isNotEmpty) {
        segs = session.transcribeVad(
          samples,
          vadModelPath,
          language: language,
          options: crispasr.SessionVadOptions(
            threshold: vadThreshold ?? 0.5,
            minSpeechDurationMs: vadMinSpeechMs ?? 250,
            minSilenceDurationMs: vadMinSilenceMs ?? 100,
            speechPadMs: vadSpeechPadMs ?? 30,
          ),
        );
      } else {
        segs = session.transcribe(samples, language: language);
      }
      // Stream segments first (UI gets them as they arrive), then
      // signal done with the full list (drain loop uses it for
      // final dedupe / history save).
      final outSegs = <Map<String, Object?>>[];
      for (final s in segs) {
        final m = _segmentToMap(s);
        outSegs.add(m);
        replyPort.send(<String, Object?>{'type': 'segment', 'segment': m});
      }
      replyPort.send(<String, Object?>{'type': 'done', 'segments': outSegs});
    } catch (e, st) {
      replyPort.send(<String, Object?>{
        'type': 'error',
        'message': '$e',
        'stack': st.toString(),
      });
    }
  }
}

/// Serialise a SessionSegment for the cross-isolate hop. The
/// canonical SessionSegment lives in `package:crispasr` and is
/// already plain data, but to keep the wire format stable + small
/// we round-trip through a Map. Words are included when the
/// backend emits them natively (parakeet, canary, cohere); other
/// backends produce empty words lists and the main-side aligner
/// fills them in as a post-process.
Map<String, Object?> _segmentToMap(crispasr.SessionSegment s) {
  return <String, Object?>{
    'text': s.text,
    // session segments use `start`/`end`; flatten to the
    // TranscriptionSegment naming the main-isolate consumer expects.
    'startTime': s.start,
    'endTime': s.end,
    if (s.words.isNotEmpty)
      'words': [
        for (final w in s.words)
          <String, Object?>{
            'word': w.text,
            'startTime': w.start,
            'endTime': w.end,
            'confidence': w.p,
          },
      ],
  };
}

/// Main-side helper to rebuild a [TranscriptionSegment] from the
/// over-the-wire map. The drain loop calls this when it receives a
/// `segment` or `done` message from a worker.
TranscriptionSegment workerSegmentFromMap(Map<String, Object?> m) {
  final rawWords = m['words'] as List?;
  return TranscriptionSegment(
    text: m['text'] as String? ?? '',
    startTime: (m['startTime'] as num?)?.toDouble() ?? 0.0,
    endTime: (m['endTime'] as num?)?.toDouble() ?? 0.0,
    speaker: m['speaker'] as String?,
    confidence: (m['confidence'] as num?)?.toDouble() ?? 1.0,
    words: rawWords == null
        ? null
        : [
            for (final w in rawWords.cast<Map<dynamic, dynamic>>())
              TranscriptionWord(
                word: w['word'] as String? ?? '',
                startTime: (w['startTime'] as num?)?.toDouble() ?? 0.0,
                endTime: (w['endTime'] as num?)?.toDouble() ?? 0.0,
                confidence:
                    (w['confidence'] as num?)?.toDouble() ?? 1.0,
              ),
          ],
  );
}
