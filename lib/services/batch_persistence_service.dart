// File-backed persistence for the batch queue. Each job is a separate
// JSON file so we can mutate one without rewriting the whole queue,
// each checkpoint is an append-only JSON-lines file so partial-progress
// segments hit disk in O(1) per segment regardless of how long the
// transcript grows (§5.23 Q1 + Q3).
//
// Layout (under `<app-docs>/batch/<queue-id>/`):
//   job-<id>.json           - the BatchJob record
//   job-<id>.ckpt.jsonl     - one TranscriptionSegment per line,
//                             append-only; deleted on job completion.
//   manifest.json           - lightweight index of `[id, status, ...]`
//                             pairs so the UI can render the queue
//                             without hydrating every job's full JSON
//                             (reserved for the future lazy-load path
//                             — not used today since we hydrate eagerly
//                             at load() time).
//
// Cross-platform: only uses `dart:io` File / Directory + path_provider.
// No platform-channel calls, works identically on macOS / Linux /
// Windows / Android / iOS. The directory is created on first write.
// HistoryService ships the exact same pattern in v0.4.x; if it works
// for finalised transcripts on every supported platform it works for
// in-flight batch checkpoints too.
//
// Known follow-up (tracked in PLAN §5.23): iOS files in
// `getApplicationDocumentsDirectory()` are iCloud-backed by default.
// Mid-batch checkpoints are ephemeral and useless after job
// completion, so they should be flagged
// `NSURLIsExcludedFromBackupKey` to avoid uploading the user's
// in-flight transcription JSON to Apple's servers. One-line addition
// at first directory create. Not blocking — worst case today is a
// few KB of brief iCloud noise.
//
// Test injection: BatchPersistenceService.withDirectory(d) skips
// path_provider so unit tests can hand it a `Directory.systemTemp`
// path. Same pattern as HistoryService.withDirectory.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../engines/transcription_engine.dart';
import 'batch_queue_service.dart';
import 'ios_helpers.dart';
import 'log_service.dart';

class BatchPersistenceService {
  static const _folder = 'batch';

  /// Single-queue convention for now — multi-queue is future work
  /// (§5.23 Q1 sub-bullet). Hardcoded `default` so the path layout
  /// stays stable when multi-queue lands.
  static const String defaultQueueId = 'default';

  final String _queueId;
  Directory? _dir;
  // Per-job write chain. BatchQueueNotifier fires saveJob() (and the
  // related delete* helpers) as unawaited futures on every state
  // mutation; without serialisation `setProgress` racing with the
  // preceding `setRunning` on the same job can leave disk lagging
  // the in-memory state, or worse — corrupt the JSON if both writes
  // are mid-flight. We chain ALL filesystem ops per-job (saves,
  // deletes, checkpoint appends) so order matches the caller's order.
  // Cross-job operations stay fully parallel.
  final Map<String, Future<void>> _jobLock = {};

  /// Default constructor — files land under
  /// `<app-docs>/batch/<queue-id>/`.
  BatchPersistenceService({String queueId = defaultQueueId})
      : _queueId = queueId;

  /// Test-only override — writes go to [dir] directly, skipping
  /// path_provider. Same shape as HistoryService.withDirectory.
  @visibleForTesting
  BatchPersistenceService.withDirectory(Directory dir,
      {String queueId = defaultQueueId})
      : _queueId = queueId,
        _dir = dir;

  Future<Directory> _ensureDir() async {
    if (_dir != null) {
      if (!await _dir!.exists()) {
        await _dir!.create(recursive: true);
      }
      return _dir!;
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _folder, _queueId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      // Flag the batch dir as not iCloud-backed (§5.23 Q3 polish).
      // Mid-batch checkpoints are ephemeral — deleted on setDone —
      // so uploading them to iCloud is wasted bandwidth and storage.
      // No-op on every platform except iOS; idempotent so subsequent
      // calls on an already-flagged dir are cheap.
      unawaited(excludeFromBackup(dir.path));
    }
    _dir = dir;
    return dir;
  }

  String _jobFilename(String id) => 'job-$id.json';
  String _checkpointFilename(String id) => 'job-$id.ckpt.jsonl';

  /// Per-job filesystem-op serializer. Wraps [body] so it runs only
  /// after the previous queued op on the same `id` resolves. A failure
  /// in one op doesn't poison the chain — the next caller gets a fresh
  /// resolved future to wait on. The chain entry is reaped when the
  /// last queued op finishes (slot-equality check), so the map doesn't
  /// leak IDs forever in long-lived sessions.
  Future<T> _serial<T>(String id, Future<T> Function() body) {
    final prev = _jobLock[id] ?? Future<void>.value();
    final completer = Completer<T>();
    final next = prev.then((_) async {
      try {
        completer.complete(await body());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    // Always replace the lock with a never-throwing future of the same
    // resolution timing — keeps subsequent serial() calls from being
    // poisoned by a prior failure.
    final guard = next.catchError((_) {});
    _jobLock[id] = guard;
    guard.whenComplete(() {
      if (identical(_jobLock[id], guard)) _jobLock.remove(id);
    });
    return completer.future;
  }

  /// Job-file write. Each call to a given `job.id` is serialised against
  /// every other filesystem op on the same id (delete, checkpoint
  /// append) so the disk state matches the caller's call-order. Direct
  /// write — `writeAsString` already opens/writes/closes atomically per
  /// the dart:io contract; the previous `.tmp` + `rename` dance racing
  /// itself was the bug, not what it was guarding against.
  Future<void> saveJob(BatchJob job) {
    return _serial(job.id, () async {
      final dir = await _ensureDir();
      final dst = File(p.join(dir.path, _jobFilename(job.id)));
      final encoded =
          const JsonEncoder.withIndent('  ').convert(job.toJson());
      await dst.writeAsString(encoded, flush: true);
    });
  }

  /// Read every persisted job, sorted by `createdAt` ascending so the
  /// queue order in memory matches the order jobs were originally
  /// enqueued in. Skips corrupt / half-written files rather than
  /// throwing — a single bad job shouldn't take down the whole queue.
  Future<List<BatchJob>> loadAllJobs() async {
    final dir = await _ensureDir();
    final jobs = <BatchJob>[];
    if (!await dir.exists()) return jobs;
    await for (final ent in dir.list()) {
      if (ent is! File) continue;
      final name = p.basename(ent.path);
      if (!name.startsWith('job-') || !name.endsWith('.json')) continue;
      // Skip the `.ckpt.jsonl` siblings (caught by extension check above)
      // and any half-written `.tmp` files (next condition).
      if (name.endsWith('.tmp')) continue;
      try {
        final raw = await ent.readAsString();
        if (raw.trim().isEmpty) continue;
        final json = jsonDecode(raw) as Map<String, dynamic>;
        jobs.add(BatchJob.fromJson(json));
      } catch (e, st) {
        Log.instance.w('batch-persist', 'skipping corrupt job file',
            fields: {'file': ent.path}, error: e, stack: st);
      }
    }
    jobs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return jobs;
  }

  /// Remove the job file AND any leftover checkpoint. Missing files
  /// are silently ignored (no-op) so callers can `deleteJob(id)`
  /// optimistically without first probing existence. Serialised with
  /// `saveJob(id)` so a delete can't race a pending save.
  Future<void> deleteJob(String id) {
    return _serial(id, () async {
      final dir = await _ensureDir();
      final job = File(p.join(dir.path, _jobFilename(id)));
      if (await job.exists()) await job.delete();
      final ckpt = File(p.join(dir.path, _checkpointFilename(id)));
      if (await ckpt.exists()) await ckpt.delete();
    });
  }

  /// Wipe every job + checkpoint in the queue's directory. Used by
  /// `BatchQueueNotifier.clearAll()` and by the test tear-down.
  Future<void> clearAll() async {
    final dir = await _ensureDir();
    if (!await dir.exists()) return;
    await for (final ent in dir.list()) {
      if (ent is File) {
        try {
          await ent.delete();
        } catch (e) {
          Log.instance.w('batch-persist', 'clearAll: could not delete file',
              fields: {'file': ent.path, 'err': e.toString()});
        }
      }
    }
  }

  /// Append one segment to the per-job checkpoint file. Append-only
  /// JSON Lines so a crash mid-write at most loses the last segment
  /// (file readers tolerate trailing garbage by `try { jsonDecode } }
  /// catch (_) { break }` in [loadCheckpoint]).
  ///
  /// Flushes after every write so a process-kill (`SIGKILL`,
  /// out-of-battery laptop, OS reboot) loses at most the current
  /// in-flight segment, not the previous ones. Cost: one fsync per
  /// segment, which is well below the inter-segment latency on every
  /// supported backend (whisper emits ~one segment per ~5 s wall;
  /// fsync on SSD is ~1 ms).
  Future<void> appendSegmentToCheckpoint(
      String jobId, TranscriptionSegment seg) {
    return _serial(jobId, () async {
      final dir = await _ensureDir();
      final file = File(p.join(dir.path, _checkpointFilename(jobId)));
      final line = jsonEncode(_segmentToJson(seg));
      await file.writeAsString('$line\n',
          mode: FileMode.append, flush: true);
    });
  }

  /// Replay every persisted segment from the checkpoint file.
  /// Stops at the first corrupt line (treating it as "the crash
  /// happened here") rather than throwing — partial recovery is
  /// always better than total loss.
  Future<List<TranscriptionSegment>> loadCheckpoint(String jobId) async {
    final dir = await _ensureDir();
    final file = File(p.join(dir.path, _checkpointFilename(jobId)));
    if (!await file.exists()) return const [];
    final segments = <TranscriptionSegment>[];
    final raw = await file.readAsString();
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        segments.add(_segmentFromJson(json));
      } catch (e) {
        // Last write was torn — stop and return what we have.
        Log.instance.d('batch-persist', 'checkpoint line corrupt — stopping replay',
            fields: {'jobId': jobId, 'err': e.toString()});
        break;
      }
    }
    return segments;
  }

  /// Drop the checkpoint file (job completed cleanly, no need for it
  /// any more). Missing file is a no-op. Serialised against pending
  /// checkpoint-append writes so `setDone()` immediately after a
  /// last-segment append can't race-delete the in-flight write.
  Future<void> deleteCheckpoint(String jobId) {
    return _serial(jobId, () async {
      final dir = await _ensureDir();
      final file = File(p.join(dir.path, _checkpointFilename(jobId)));
      if (await file.exists()) await file.delete();
    });
  }

  /// Find every job that has a leftover checkpoint file AND its
  /// matching job-record is in a non-terminal state. These are the
  /// jobs the §5.23 Q3 "Resume from crash" UI offers to restart.
  /// Returns the job IDs in deterministic createdAt order.
  Future<List<String>> findResumableJobs() async {
    final dir = await _ensureDir();
    if (!await dir.exists()) return const [];
    final jobs = await loadAllJobs();
    final result = <String>[];
    for (final job in jobs) {
      if (job.status == BatchJobStatus.done ||
          job.status == BatchJobStatus.cancelled) {
        continue;
      }
      final ckpt = File(p.join(dir.path, _checkpointFilename(job.id)));
      if (await ckpt.exists()) {
        result.add(job.id);
      }
    }
    return result;
  }

  // ---------------------------------------------------------------
  // TranscriptionSegment <-> JSON. Mirrors HistoryService's encoding
  // so a checkpoint and a finalised history entry round-trip the same
  // way — easy to dump a debugging mid-flight checkpoint into the
  // history viewer if needed.
  //
  // `words` and `metadata` are intentionally NOT persisted in the
  // checkpoint: words are usually massive (~100× the segment count)
  // and not needed for resume since we restart at the segment's
  // endTime; metadata is engine-internal scratchpad. On
  // resume-and-finalise the caller can re-derive both, or accept
  // their absence for the recovered prefix.
  // ---------------------------------------------------------------

  Map<String, dynamic> _segmentToJson(TranscriptionSegment seg) => {
        'text': seg.text,
        'startTime': seg.startTime,
        'endTime': seg.endTime,
        if (seg.speaker != null) 'speaker': seg.speaker,
        'confidence': seg.confidence,
      };

  TranscriptionSegment _segmentFromJson(Map<String, dynamic> json) =>
      TranscriptionSegment(
        text: json['text'] as String? ?? '',
        startTime: (json['startTime'] as num?)?.toDouble() ?? 0.0,
        endTime: (json['endTime'] as num?)?.toDouble() ?? 0.0,
        speaker: json['speaker'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      );
}
