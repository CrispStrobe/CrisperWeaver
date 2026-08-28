// TranscriptionWorkerPool — §5.23 Q2 v2 main-side dispatcher.
//
// Spawns N persistent worker isolates against the same model.
// Routes incoming transcribe jobs to free workers; blocks on a
// completer when every worker is busy. Each [dispatch] call streams
// segments back via the supplied `onSegment` callback so the UI
// sees text appear as the worker emits it (same UX as the serial
// path).
//
// Lifecycle:
//   var pool = await TranscriptionWorkerPool.spawn(...);
//   for (file in queue) {
//     await pool.dispatch(file: ..., samples: ..., onSegment: ...);
//   }
//   await pool.shutdown();
//
// Errors:
//   - spawn failures (session can't open) propagate from [spawn]
//   - per-dispatch errors throw [TranscriptionWorkerException]
//   - if a worker dies mid-dispatch the dispatch future
//     completes with the same exception and the worker is marked
//     dead; further dispatches fall back to the surviving workers.
//
// Cross-platform: pure dart:isolate. Same code path on every
// platform CrisperWeaver ships on.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'crash_breadcrumb_service.dart';
import 'log_service.dart';

import '../engines/transcription_engine.dart';
import '../utils/affective_prompt_guard.dart';
import '../widgets/advanced_options_widget.dart';
import 'batch_queue_service.dart';
import 'log_service.dart';
import 'transcription_worker.dart';

/// §5.23 Q2 v2 pool eligibility. The worker isolate now carries:
///   • sticky session-state setters (translate / targetLanguage /
///     askPrompt / temperature / bestOf / beamSize), applied
///     per-dispatch;
///   • VAD via `transcribeVad(samples, vadModelPath, options)`.
/// And the drain loop runs diarization + punctuation as a main-
/// isolate post-process after the worker returns segments.
///
/// Beam search opens up to the pool through the new
/// `crispasr_session_set_beam_size` C-ABI added in CrispASR 0.6.x:
/// whisper is wired to consume it today (switches sampling
/// strategy to BEAM_SEARCH with the supplied width); the other
/// beam-capable backends per the feature matrix (granite, voxtral,
/// qwen3, glm-asr, kyutai-stt, firered, moonshine, omniasr) need
/// per-backend high-level-transcribe API surface for beam_size
/// before they can honour the session-API setter — tracked as a
/// CrispASR follow-up. The Dart side sends beamSize unconditionally;
/// backends that don't consume it just see no behaviour change
/// (same outcome as today's serial path).
///
/// What remains pool-ineligible is genuinely worker-incompatible:
///   • [BatchJob.resumeOffsetSec] > 0 — the chunked-whisper offset
///     path lives in `CrispASREngine._runChunkedWhisper`, not in
///     the session API the worker uses.
///   • [AdvancedOptions.tdrz] — whisper-only tinydiarize marker
///     emission; needs the legacy whisper-context API path.
///
/// Pure function — no I/O, no state — so the drain-loop test
/// surface stays trivially testable. The `enableDiarization`
/// argument is the screen-level diarization toggle, not part of
/// AdvancedOptions; it's passed in so this function stays
/// self-contained.
bool poolEligible(
  BatchJob job,
  AdvancedOptions adv, {
  required bool enableDiarization,
}) {
  if ((job.resumeOffsetSec ?? 0) > 0) return false;
  if (adv.tdrz) return false;
  return true;
}

class TranscriptionWorkerException implements Exception {
  TranscriptionWorkerException(this.message, [this.stack]);
  final String message;
  final String? stack;
  @override
  String toString() => 'TranscriptionWorkerException: $message';
}

class _Worker {
  _Worker({
    required this.isolate,
    required this.sendPort,
  });
  final Isolate isolate;
  final SendPort sendPort;
  bool busy = false;
  bool dead = false;
}

class TranscriptionWorkerPool {
  TranscriptionWorkerPool._(this._workers);

  final List<_Worker> _workers;
  // FIFO of dispatchers waiting for a free worker. Resolved as
  // workers complete their current job.
  final List<Completer<_Worker>> _waiters = [];
  bool _shutdown = false;

  int get size => _workers.length;
  int get aliveCount => _workers.where((w) => !w.dead).length;
  bool get isShutdown => _shutdown;

  /// Spawn `count` workers against [modelPath]. Returns a pool that's
  /// ready to accept dispatches. Throws if every worker fails to
  /// open its session (e.g. malformed GGUF / missing file).
  static Future<TranscriptionWorkerPool> spawn({
    required int count,
    required String modelPath,
    required String backend,
    String? libName,
    bool useGpu = true,
    bool flashAttn = true,
    int nThreads = 0,
    int nGpuLayers = -1,
  }) async {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be >= 1');
    }
    final workers = <_Worker>[];
    final spawnFutures = <Future<_Worker?>>[];
    for (var i = 0; i < count; i++) {
      spawnFutures.add(_spawnOne(
        index: i,
        modelPath: modelPath,
        backend: backend,
        libName: libName,
        useGpu: useGpu,
        flashAttn: flashAttn,
        nThreads: nThreads,
        nGpuLayers: nGpuLayers,
      ));
    }
    final spawned = await Future.wait(spawnFutures);
    for (final w in spawned) {
      if (w != null) workers.add(w);
    }
    if (workers.isEmpty) {
      throw TranscriptionWorkerException(
          'every worker failed to spawn — see log for details');
    }
    Log.instance.i('worker-pool', 'spawned ${workers.length}/$count workers',
        fields: {'model': modelPath, 'backend': backend});
    return TranscriptionWorkerPool._(workers);
  }

  static Future<_Worker?> _spawnOne({
    required int index,
    required String modelPath,
    required String backend,
    required String? libName,
    required bool useGpu,
    required bool flashAttn,
    required int nThreads,
    required int nGpuLayers,
  }) async {
    final readyReceive = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<TranscriptionWorkerArgs>(
        transcriptionWorkerEntry,
        TranscriptionWorkerArgs(
          readySendPort: readyReceive.sendPort,
          modelPath: modelPath,
          backend: backend,
          libName: libName,
          useGpu: useGpu,
          flashAttn: flashAttn,
          nThreads: nThreads,
          nGpuLayers: nGpuLayers,
        ),
        debugName: 'crisperweaver-worker-$index',
        errorsAreFatal: false,
      );
    } catch (e, st) {
      Log.instance.w('worker-pool', 'spawn failed', error: e, stack: st);
      readyReceive.close();
      return null;
    }
    // Expect two messages on readyReceive:
    //   1. The worker's command SendPort
    //   2. A {type: 'ready'} or {type: 'error'} confirmation
    SendPort? cmdPort;
    final completer = Completer<_Worker?>();
    
    CrashBreadcrumb.record(NativeOperationRecord(
      phase: 'worker_spawn',
      startedAtUtc: DateTime.now().toUtc(),
      backend: backend,
      modelPath: modelPath,
    ));
    
    late StreamSubscription<dynamic> sub;
    final timeout = Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        CrashBreadcrumb.clear();
        Log.instance.w('worker-pool', 'spawn timeout for worker $index');
        sub.cancel();
        readyReceive.close();
        isolate?.kill(priority: Isolate.immediate);
        completer.complete(null);
      }
    });
    sub = readyReceive.listen((raw) {
      if (raw is SendPort) {
        cmdPort = raw;
        return;
      }
      if (raw is Map && raw['type'] == 'ready') {
        CrashBreadcrumb.clear();
        timeout.cancel();
        sub.cancel();
        readyReceive.close();
        completer.complete(_Worker(isolate: isolate!, sendPort: cmdPort!));
        return;
      }
      if (raw is Map && raw['type'] == 'error') {
        CrashBreadcrumb.clear();
        Log.instance.w('worker-pool',
            'worker $index init failed: ${raw['message']}');
        timeout.cancel();
        sub.cancel();
        readyReceive.close();
        isolate?.kill(priority: Isolate.immediate);
        completer.complete(null);
      }
    });
    return completer.future;
  }

  /// Acquire a free worker (blocks until one becomes available).
  /// Returns null if the pool is shutdown or every worker has died.
  Future<_Worker?> _acquire() async {
    if (_shutdown) return null;
    for (final w in _workers) {
      if (!w.busy && !w.dead) {
        w.busy = true;
        return w;
      }
    }
    if (_workers.every((w) => w.dead)) return null;
    final c = Completer<_Worker>();
    _waiters.add(c);
    return c.future;
  }

  void _release(_Worker w) {
    w.busy = false;
    while (_waiters.isNotEmpty) {
      final c = _waiters.removeAt(0);
      if (!w.busy && !w.dead) {
        w.busy = true;
        c.complete(w);
        return;
      }
    }
  }

  /// Send a transcribe job to a free worker and stream segments
  /// back via [onSegment]. Returns the full segment list when the
  /// worker reports `done`. Throws [TranscriptionWorkerException]
  /// on worker-side errors.
  ///
  /// Advanced knobs (translate / targetLanguage / askPrompt /
  /// temperature / bestOf) are wired through to the worker's
  /// sticky session-state setters — each is fired before every
  /// dispatch so the previous job's settings don't leak forward.
  /// Backends that don't honour a particular field silently no-op.
  ///
  /// When [vadModelPath] is non-null, the worker calls
  /// `session.transcribeVad(...)` with the Silero VAD model
  /// instead of bare `transcribe(...)`. The VAD options default
  /// to crispasr's reference values when not supplied.
  Future<List<TranscriptionSegment>> dispatch({
    required Float32List samples,
    String? language,
    String? targetLanguage,
    bool translate = false,
    String? askPrompt,
    double temperature = 0.0,
    int bestOf = 1,
    int beamSize = 1,
    String? vadModelPath,
    double? vadThreshold,
    int? vadMinSpeechMs,
    int? vadMinSilenceMs,
    int? vadSpeechPadMs,
    String grammarText = '',
    String grammarRootRule = 'root',
    double grammarPenalty = 100.0,
    String sensitivityPreset = '',
    double entropyThold = 2.4,
    double logprobThold = -1.0,
    double noSpeechThold = 0.6,
    double temperatureInc = 0.2,
    bool suppressNonSpeechTokens = false,
    String suppressTokensRegex = '',
    bool carryInitialPrompt = false,
    int altN = 0,
    String hotwords = '',
    int chunkSeconds = 0,
    void Function(TranscriptionSegment seg)? onSegment,
  }) async {
    // EU AI Act — the two duties `CrispasrEngine.transcribe` discharges
    // before it touches a session have to be discharged here too, because
    // this pool is reached *without* going through that method.
    // `transcription_screen` dispatches to it directly for parallel batch
    // jobs and for the A/B model comparison, so until 2026-08-03 those two
    // paths ran with neither control:
    //
    //   • an affective ask prompt reached the model unrefused
    //     (Art. 5(1)(f) / Annex III 1(c) — `AI_ACT_RISK.md` §2.9);
    //   • the resulting Q&A answer or machine translation carried no
    //     `generated` kind, so every export, history record, and the
    //     clipboard called it a transcript (Art. 50(2) — §5.2).
    //
    // Both controls are idempotent, so the engine applying them as well on
    // its own pool path is harmless. This is the choke point that covers
    // every caller; the engine's copies cover its non-pool paths.
    // Screened here so a refused job fails before a worker is acquired and
    // audio is copied across the isolate boundary. The worker screens again
    // on arrival — see `transcription_worker.dart` — because the wire format
    // is untyped and this object cannot cross it.
    final ScreenedAskPrompt screenedAsk;
    try {
      screenedAsk = ScreenedAskPrompt.screen(askPrompt);
    } on AffectivePromptRefused catch (e) {
      Log.instance.w('worker-pool', 'audio Q&A prompt refused (affective)',
          fields: {'term': e.term});
      throw AffectivePromptException(e.message, 'crispasr', e.term);
    }

    final worker = await _acquire();
    if (worker == null) {
      throw TranscriptionWorkerException(
          'pool unavailable (shutdown or all workers dead)');
    }

    final replyReceive = ReceivePort();
    final completer = Completer<List<TranscriptionSegment>>();
    late StreamSubscription<dynamic> sub;
    sub = replyReceive.listen((raw) {
      if (raw is! Map) return;
      switch (raw['type']) {
        case 'segment':
          if (onSegment != null) {
            onSegment(workerSegmentFromMap(
                (raw['segment'] as Map).cast<String, Object?>()));
          }
          break;
        case 'done':
          final list = (raw['segments'] as List)
              .map((m) =>
                  workerSegmentFromMap((m as Map).cast<String, Object?>()))
              .toList(growable: false);
          sub.cancel();
          replyReceive.close();
          if (!completer.isCompleted) completer.complete(list);
          break;
        case 'error':
          sub.cancel();
          replyReceive.close();
          if (!completer.isCompleted) {
            completer.completeError(TranscriptionWorkerException(
                raw['message'] as String? ?? 'unknown worker error',
                raw['stack'] as String?));
          }
          break;
      }
    });
    try {
      worker.sendPort.send(<String, Object?>{
        'type': 'transcribe',
        'samples': samples,
        'language': language,
        if (targetLanguage != null) 'targetLanguage': targetLanguage,
        'translate': translate,
        // Send the screened value, not the caller's raw string.
        if (screenedAsk.isNotEmpty) 'askPrompt': screenedAsk.value,
        'temperature': temperature,
        'bestOf': bestOf,
        'beamSize': beamSize,
        if (vadModelPath != null) 'vadModelPath': vadModelPath,
        if (vadThreshold != null) 'vadThreshold': vadThreshold,
        if (vadMinSpeechMs != null) 'vadMinSpeechMs': vadMinSpeechMs,
        if (vadMinSilenceMs != null) 'vadMinSilenceMs': vadMinSilenceMs,
        if (vadSpeechPadMs != null) 'vadSpeechPadMs': vadSpeechPadMs,
        if (chunkSeconds > 0) 'chunkSeconds': chunkSeconds,
        // §5.8 — always send the grammar fields. Empty text means
        // "clear" on the worker side, so a stale grammar from a
        // previous job can't carry over.
        'grammarText': grammarText,
        'grammarRootRule': grammarRootRule,
        'grammarPenalty': grammarPenalty,
        // Whisper decoder-fallback thresholds — always sent so a
        // slider tweak takes effect on the next job without a
        // worker restart. Pre-0.5.10 dylibs ignore.
        if (sensitivityPreset.isNotEmpty)
          'sensitivityPreset': sensitivityPreset,
        'entropyThold': entropyThold,
        'logprobThold': logprobThold,
        'noSpeechThold': noSpeechThold,
        'temperatureInc': temperatureInc,
        // Whisper text-suppression + prompt-carry extras (0.5.11+).
        // Pre-0.5.11 dylibs lack the symbol and the worker
        // swallows UnsupportedError.
        'suppressNonSpeechTokens': suppressNonSpeechTokens,
        'suppressTokensRegex': suppressTokensRegex,
        'carryInitialPrompt': carryInitialPrompt,
        // §5.1.11 alt-token capture (whisper greedy decode only,
        // 0.5.13+). Always sent so a slider drag back to 0 actually
        // disables capture on the next dispatch.
        'altN': altN,
        'hotwords': hotwords,
        'replyPort': replyReceive.sendPort,
      });
      // Art. 50(2) — see the note at the top of this method. One rule,
      // shared with `CrispasrEngine.transcribe`.
      return GeneratedKind.stamp(
          await completer.future,
          GeneratedKind.forRequest(
              askPrompt: askPrompt,
              translate: translate,
              targetLanguage: targetLanguage));
    } catch (e) {
      // Worker likely died mid-send — mark dead so the pool stops
      // routing to it. Re-throw so the drain loop knows the job
      // didn't land.
      worker.dead = true;
      rethrow;
    } finally {
      _release(worker);
    }
  }

  /// Shut down every worker. Idempotent. After this point new
  /// dispatches throw. In-flight dispatches are NOT cancelled — they
  /// run to completion against their worker, then the worker exits.
  Future<void> shutdown() async {
    if (_shutdown) return;
    _shutdown = true;
    for (final w in _workers) {
      if (w.dead) continue;
      try {
        w.sendPort.send(<String, Object?>{'type': 'shutdown'});
      } catch (e) {
        Log.instance.d('worker-pool', 'shutdown send failed (worker already gone)',
            fields: {'err': e.toString()});
      }
    }
    // Give workers a moment to close their sessions cleanly. We
    // can't await Isolate exit without a per-worker onExit port; a
    // short delay covers the typical path.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (final w in _workers) {
      try {
        w.isolate.kill(priority: Isolate.beforeNextEvent);
      } catch (e) {
        Log.instance.d('worker-pool', 'isolate kill failed',
            fields: {'err': e.toString()});
      }
    }
  }
}
