import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_service.dart';
import 'batch_persistence_service.dart';
import 'log_service.dart';

enum BatchJobStatus { queued, running, done, error, cancelled }

extension BatchJobStatusX on BatchJobStatus {
  bool get isTerminal =>
      this == BatchJobStatus.done ||
      this == BatchJobStatus.error ||
      this == BatchJobStatus.cancelled;
}

/// Persisted-and-displayed record for one file in a batch queue.
///
/// `backend` / `modelId` / `language` are snapshotted at enqueue time
/// so the drain loop can group jobs by `(backend, modelId, language)`
/// without re-reading global settings (§5.23 Q1 grouping) and so a
/// resumed-from-crash job knows which model to load.
///
/// `resumeOffsetSec` is the float second offset into the audio at which
/// to restart transcription after a crash. Populated by the §5.23 Q3
/// resume-from-checkpoint flow; null for fresh jobs.
class BatchJob {
  final String id;
  final String filePath;
  final DateTime createdAt;
  final BatchJobStatus status;
  final double progress; // 0..1
  final String? errorMessage;
  final String? resultText;
  final String? historyEntryId;
  final String? backend;
  final String? modelId;
  final String? language;
  final double? durationSec;
  final double? resumeOffsetSec;

  const BatchJob({
    required this.id,
    required this.filePath,
    required this.createdAt,
    this.status = BatchJobStatus.queued,
    this.progress = 0.0,
    this.errorMessage,
    this.resultText,
    this.historyEntryId,
    this.backend,
    this.modelId,
    this.language,
    this.durationSec,
    this.resumeOffsetSec,
  });

  BatchJob copyWith({
    BatchJobStatus? status,
    double? progress,
    String? errorMessage,
    String? resultText,
    String? historyEntryId,
    String? backend,
    String? modelId,
    String? language,
    double? durationSec,
    double? resumeOffsetSec,
  }) {
    return BatchJob(
      id: id,
      filePath: filePath,
      createdAt: createdAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      resultText: resultText ?? this.resultText,
      historyEntryId: historyEntryId ?? this.historyEntryId,
      backend: backend ?? this.backend,
      modelId: modelId ?? this.modelId,
      language: language ?? this.language,
      durationSec: durationSec ?? this.durationSec,
      resumeOffsetSec: resumeOffsetSec ?? this.resumeOffsetSec,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'progress': progress,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (resultText != null) 'resultText': resultText,
        if (historyEntryId != null) 'historyEntryId': historyEntryId,
        if (backend != null) 'backend': backend,
        if (modelId != null) 'modelId': modelId,
        if (language != null) 'language': language,
        if (durationSec != null) 'durationSec': durationSec,
        if (resumeOffsetSec != null) 'resumeOffsetSec': resumeOffsetSec,
      };

  static BatchJob fromJson(Map<String, dynamic> json) => BatchJob(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        createdAt:
            DateTime.parse(json['createdAt'] as String? ?? '1970-01-01T00:00:00Z'),
        status: BatchJobStatus.values.firstWhere(
          (s) => s.name == (json['status'] as String? ?? 'queued'),
          orElse: () => BatchJobStatus.queued,
        ),
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        errorMessage: json['errorMessage'] as String?,
        resultText: json['resultText'] as String?,
        historyEntryId: json['historyEntryId'] as String?,
        backend: json['backend'] as String?,
        modelId: json['modelId'] as String?,
        language: json['language'] as String?,
        durationSec: (json['durationSec'] as num?)?.toDouble(),
        resumeOffsetSec: (json['resumeOffsetSec'] as num?)?.toDouble(),
      );
}

/// Riverpod-backed serial FIFO of transcription jobs.
///
/// Concurrent FFI calls into the same whisper_context are unsafe, so the
/// queue drains strictly one-at-a-time. The UI (transcription screen)
/// owns the runner — it drives the queue by calling `nextQueued()` in a
/// loop after each job finishes.
///
/// **Persistence (§5.23 Q1).** Every state mutation is mirrored to a
/// per-job JSON file on disk so the queue survives app restarts. The
/// writes are fire-and-forget (the on-disk copy can lag by one frame
/// behind the in-memory state); failures are logged but don't break
/// the in-memory queue. The persistence layer is injectable so unit
/// tests can hand in a `Directory.systemTemp` path.
class BatchQueueNotifier extends StateNotifier<List<BatchJob>> {
  BatchQueueNotifier({
    BatchPersistenceService? persistence,
    /// Optional duration probe — called async after enqueue to stamp
    /// `durationSec` on the job for ETA estimation (§5.23 Q1).
    /// Default `null` skips probing so unit tests stay hermetic (no
    /// just_audio platform binding). Production wiring in
    /// `main.dart` passes `audioService.probeDuration`.
    Future<Duration?> Function(String filePath)? durationProbe,
  })  : _persistence = persistence ?? BatchPersistenceService(),
        _durationProbe = durationProbe,
        super(const []);

  final BatchPersistenceService _persistence;
  final Future<Duration?> Function(String filePath)? _durationProbe;
  bool _loaded = false;
  int _lastLoadResumedCount = 0;

  // Persistence writes are fired unawaited so the UI never blocks on
  // disk. To let tests (and tearDown) know all writes have flushed
  // deterministically — instead of sleeping and hoping — track the
  // in-flight write futures and expose `whenPersisted()`.
  final Set<Future<void>> _pendingWrites = {};
  void _fireAndForget(Future<void> f) {
    _pendingWrites.add(f);
    f.whenComplete(() => _pendingWrites.remove(f));
  }

  /// Awaits all in-flight persistence writes (save / delete / clear).
  /// Test-only — production never blocks on disk. Drains re-entrant
  /// writes too, so callers can assert on-disk state without races.
  @visibleForTesting
  Future<void> whenPersisted() async {
    while (_pendingWrites.isNotEmpty) {
      await Future.wait(_pendingWrites.toList());
    }
  }

  /// How many resumable jobs (non-terminal + had a leftover
  /// `.ckpt.jsonl`) the most recent [load] call recovered. The UI
  /// reads this once after the first frame to show a one-shot
  /// "recovered N interrupted job(s)" snackbar, then calls
  /// [acknowledgeResumedJobsSnackbar] to clear the counter so a
  /// hot-reload doesn't show it again.
  int get lastLoadResumedCount => _lastLoadResumedCount;
  void acknowledgeResumedJobsSnackbar() {
    _lastLoadResumedCount = 0;
  }

  /// Hydrate in-memory state from the on-disk queue. Idempotent —
  /// safe to call multiple times. Used by the app-startup wiring in
  /// `main.dart`.
  ///
  /// Two repair passes (§5.23 Q1 + Q3):
  ///   1. Running-when-killed jobs are demoted back to `queued` so the
  ///      next drain pass picks them up.
  ///   2. For each job whose `.ckpt.jsonl` survived, we stamp
  ///      `resumeOffsetSec` = endTime of the last checkpointed
  ///      segment. The drain loop reads that field and starts
  ///      transcription past the already-completed prefix (whisper
  ///      via chunked-whisper offset routing; session backends trim
  ///      leading PCM samples + shift emitted timestamps).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final loaded = await _persistence.loadAllJobs();
      // Pass 1: demote running → queued.
      final repaired = <BatchJob>[];
      final dirtyIds = <String>{};
      for (final j in loaded) {
        if (j.status == BatchJobStatus.running) {
          repaired.add(j.copyWith(
            status: BatchJobStatus.queued,
            progress: 0.0,
          ));
          dirtyIds.add(j.id);
        } else {
          repaired.add(j);
        }
      }

      // Pass 2: stamp resumeOffsetSec from each leftover checkpoint.
      // findResumableJobs only returns IDs whose job is non-terminal
      // AND has a .ckpt.jsonl, so we just probe each match here.
      final resumableIds =
          (await _persistence.findResumableJobs()).toSet();
      int resumeCount = 0;
      for (var i = 0; i < repaired.length; i++) {
        final j = repaired[i];
        if (!resumableIds.contains(j.id)) continue;
        final segs = await _persistence.loadCheckpoint(j.id);
        if (segs.isEmpty) continue;
        final lastEnd = segs.last.endTime;
        if (lastEnd <= 0) continue;
        repaired[i] = j.copyWith(resumeOffsetSec: lastEnd);
        dirtyIds.add(j.id);
        resumeCount++;
      }

      state = List<BatchJob>.unmodifiable(repaired);
      _lastLoadResumedCount = resumeCount;
      // Push only the mutated jobs back to disk — saves I/O on the
      // common case where every job round-trips unchanged.
      for (final j in repaired) {
        if (dirtyIds.contains(j.id)) _fireAndForget(_persist(j));
      }
      Log.instance.i('batch-queue',
          'hydrated ${repaired.length} job(s) from disk', fields: {
        'queued':
            repaired.where((j) => j.status == BatchJobStatus.queued).length,
        'done':
            repaired.where((j) => j.status == BatchJobStatus.done).length,
        'resumable': resumeCount,
      });
    } catch (e, st) {
      Log.instance.w('batch-queue', 'load failed; starting empty',
          error: e, stack: st);
    }
  }

  Future<void> _persist(BatchJob job) async {
    try {
      await _persistence.saveJob(job);
    } catch (e, st) {
      Log.instance.w('batch-queue', 'saveJob failed for ${job.id}',
          error: e, stack: st);
    }
  }

  String enqueue(String filePath,
      {String? backend, String? modelId, String? language}) {
    // Dedup by path — already-queued or in-flight jobs stay in place.
    for (final j in state) {
      if (j.filePath == filePath && !j.status.isTerminal) return j.id;
    }

    final job = BatchJob(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      filePath: filePath,
      createdAt: DateTime.now(),
      backend: backend,
      modelId: modelId,
      language: language,
    );
    state = [...state, job];
    _fireAndForget(_persist(job));
    // §5.23 Q1 ETA probe — fire-and-forget. The job is queued
    // regardless of probe outcome; the durationSec field stays null
    // when the probe fails or returns null and the UI just doesn't
    // show an ETA badge for that one.
    if (_durationProbe != null) {
      unawaited(_probeAndStamp(job.id, filePath));
    }
    return job.id;
  }

  Future<void> _probeAndStamp(String jobId, String filePath) async {
    try {
      final d = await _durationProbe!(filePath);
      final secs = d?.inMilliseconds == null ? null : d!.inMilliseconds / 1000.0;
      if (secs == null || secs <= 0) return;
      _update(jobId, (j) => j.copyWith(durationSec: secs));
    } catch (e) {
      // Intentionally caught — probe failure means "we don't know
      // the duration", not "the job is broken". Logged without the
      // stack trace so concurrent flutter test runs don't attribute
      // the stack-frame chatter to whatever unrelated test is
      // happening to run at that moment.
      Log.instance
          .d('batch-queue', 'duration probe failed (swallowed): $e',
              fields: {'id': jobId});
    }
  }

  /// Reorder non-terminal jobs into `(backend, modelId, language)`
  /// bundles so consecutive same-bundle jobs reuse the loaded
  /// session. Stable within each bundle (preserves enqueue order).
  /// Done / error / cancelled / running jobs stay in place — only
  /// queued jobs are reordered, and they get appended after any
  /// in-place rows so the drain loop's next pick still respects the
  /// "currently running first" invariant.
  ///
  /// Called by the drain loop at `_startBatchRun` start when
  /// `settings.groupBatchByBackend` is true. Cheap — O(n log n).
  /// §5.23 Q1 grouping sub-bullet.
  void reorderByGrouping() {
    final keep = <BatchJob>[]; // non-queued: order untouched
    final queued = <BatchJob>[];
    for (final j in state) {
      if (j.status == BatchJobStatus.queued) {
        queued.add(j);
      } else {
        keep.add(j);
      }
    }
    if (queued.isEmpty) return;
    // Composite sort key. nulls collate to the END (jobs without
    // captured metadata batch after the typed ones).
    int cmp(String? a, String? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }
    queued.sort((a, b) {
      var c = cmp(a.backend, b.backend);
      if (c != 0) return c;
      c = cmp(a.modelId, b.modelId);
      if (c != 0) return c;
      c = cmp(a.language, b.language);
      if (c != 0) return c;
      // Tiebreak by enqueue order (createdAt) so the sort is stable.
      return a.createdAt.compareTo(b.createdAt);
    });
    state = List<BatchJob>.unmodifiable([...keep, ...queued]);
    Log.instance.i('batch-queue',
        'reordered ${queued.length} queued job(s) by grouping');
  }

  void remove(String id) {
    state = state.where((j) => j.id != id).toList(growable: false);
    _fireAndForget(_persistence.deleteJob(id));
  }

  void clearCompleted() {
    final toRemove = state
        .where((j) =>
            j.status == BatchJobStatus.done ||
            j.status == BatchJobStatus.cancelled)
        .map((j) => j.id)
        .toList();
    state = state
        .where((j) =>
            j.status != BatchJobStatus.done &&
            j.status != BatchJobStatus.cancelled)
        .toList(growable: false);
    for (final id in toRemove) {
      _fireAndForget(_persistence.deleteJob(id));
    }
  }

  void clearAll() {
    state = const [];
    _fireAndForget(_persistence.clearAll());
  }

  void _update(String id, BatchJob Function(BatchJob) fn) {
    BatchJob? updated;
    state = state.map((j) {
      if (j.id != id) return j;
      updated = fn(j);
      return updated!;
    }).toList(growable: false);
    if (updated != null) _fireAndForget(_persist(updated!));
  }

  void setRunning(String id) => _update(
      id, (j) => j.copyWith(status: BatchJobStatus.running, progress: 0));

  void setProgress(String id, double p) =>
      _update(id, (j) => j.copyWith(progress: p));

  void setDone(String id, {String? resultText, String? historyEntryId}) {
    _update(
        id,
        (j) => j.copyWith(
              status: BatchJobStatus.done,
              progress: 1.0,
              resultText: resultText,
              historyEntryId: historyEntryId,
            ));
    // Clean up any leftover checkpoint file — the job finished cleanly
    // and the result is in the history entry now.
    _fireAndForget(_persistence.deleteCheckpoint(id));
  }

  void setError(String id, String message) => _update(
      id,
      (j) => j.copyWith(
            status: BatchJobStatus.error,
            errorMessage: message,
          ));

  void setCancelled(String id) {
    _update(id, (j) => j.copyWith(status: BatchJobStatus.cancelled));
    _fireAndForget(_persistence.deleteCheckpoint(id));
  }

  /// Next still-queued job (or null if queue is empty / all terminal).
  BatchJob? nextQueued() {
    for (final j in state) {
      if (j.status == BatchJobStatus.queued) return j;
    }
    return null;
  }

  bool get hasQueued => state.any((j) => j.status == BatchJobStatus.queued);
  bool get hasRunning => state.any((j) => j.status == BatchJobStatus.running);
  int get queuedCount =>
      state.where((j) => j.status == BatchJobStatus.queued).length;
  int get doneCount =>
      state.where((j) => j.status == BatchJobStatus.done).length;

  /// Expose the persistence service for the §5.23 Q3 resume flow
  /// (transcription_screen reads/writes checkpoint segments directly
  /// during the drain loop).
  BatchPersistenceService get persistence => _persistence;

  // desktop_drop DropTargets fire even when nested. When the batch card's
  // own DropTarget consumes a drop, it calls markDropReceived(); the outer
  // page-level DropTarget peeks at `recentlyConsumedDrop` to avoid
  // re-handling the same event.
  DateTime? _lastDropAt;
  void markDropReceived() {
    _lastDropAt = DateTime.now();
  }

  bool get recentlyConsumedDrop {
    final t = _lastDropAt;
    if (t == null) return false;
    return DateTime.now().difference(t) < const Duration(milliseconds: 400);
  }
}

final batchQueueProvider =
    StateNotifierProvider<BatchQueueNotifier, List<BatchJob>>((ref) {
  final audio = ref.read(audioServiceProvider);
  return BatchQueueNotifier(
    // Wire the §5.23 Q1 duration probe — fires async after enqueue,
    // stamps `durationSec` on the job so the queue card can show a
    // real ETA. AudioService is grabbed eagerly here (the provider
    // is already created by the time the queue is touched).
    durationProbe: (filePath) => audio.probeDuration(File(filePath)),
  );
});
