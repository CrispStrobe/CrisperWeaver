// Integration tests for BatchQueueNotifier — confirms the in-memory
// state and the on-disk persistence stay in sync after every mutation
// (§5.23 Q1 foundation). Uses a tempdir-backed
// BatchPersistenceService so the tests don't touch the real user
// docs dir and can run hermetically on every Dart platform.

import 'dart:io';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/batch_persistence_service.dart';
import 'package:crisper_weaver/services/batch_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BatchQueueNotifier persistence', () {
    late Directory tempDir;
    late BatchPersistenceService persistence;
    late BatchQueueNotifier queue;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('batch-queue-test-');
      persistence = BatchPersistenceService.withDirectory(tempDir);
      queue = BatchQueueNotifier(persistence: persistence);
    });

    tearDown(() async {
      // Drain in-flight fire-and-forget persist writes DETERMINISTICALLY
      // before deleting the temp dir — else the delete races them and
      // fails with FileSystemException (POSIX) / sharing-violation
      // (Windows). The old fixed 50 ms delay lost this race under
      // full-suite CPU/disk contention (the chronic flake).
      await queue.whenPersisted();
      queue.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> settle() async {
      // Deterministically await all in-flight persistence writes instead
      // of sleeping and hoping — every mutation fires _persist()
      // unawaited, and whenPersisted() drains them (incl. re-entrant
      // writes) so disk assertions never race.
      await queue.whenPersisted();
    }

    test('enqueue persists the new job to disk', () async {
      queue.enqueue('/tmp/foo.wav',
          backend: 'whisper', modelId: 'ggml-small.en', language: 'en');
      expect(queue.state, hasLength(1));
      await settle();

      final disk = await persistence.loadAllJobs();
      expect(disk, hasLength(1));
      expect(disk.single.filePath, '/tmp/foo.wav');
      expect(disk.single.backend, 'whisper');
      expect(disk.single.modelId, 'ggml-small.en');
      expect(disk.single.language, 'en');
      expect(disk.single.status, BatchJobStatus.queued);
    });

    test('enqueue dedups by path while non-terminal', () async {
      final firstId = queue.enqueue('/tmp/dup.wav');
      final secondId = queue.enqueue('/tmp/dup.wav');
      expect(firstId, secondId);
      expect(queue.state, hasLength(1));
    });

    test('setRunning / setProgress persist progress mid-job', () async {
      final id = queue.enqueue('/tmp/run.wav');
      queue.setRunning(id);
      queue.setProgress(id, 0.42);
      await settle();

      final disk = await persistence.loadAllJobs();
      expect(disk.single.status, BatchJobStatus.running);
      expect(disk.single.progress, closeTo(0.42, 1e-9));
    });

    test('setDone persists and clears any leftover checkpoint', () async {
      final id = queue.enqueue('/tmp/done.wav');
      queue.setRunning(id);
      // Plant a checkpoint to confirm setDone cleans it up.
      await persistence.appendSegmentToCheckpoint(
          id,
          const TranscriptionSegment(
            text: 'hello',
            startTime: 0.0,
            endTime: 1.0,
          ));
      expect(File('${tempDir.path}/job-$id.ckpt.jsonl').existsSync(), isTrue);

      queue.setDone(id, resultText: 'done text', historyEntryId: 'hist-1');
      await settle();

      final disk = await persistence.loadAllJobs();
      expect(disk.single.status, BatchJobStatus.done);
      expect(disk.single.resultText, 'done text');
      expect(disk.single.historyEntryId, 'hist-1');
      expect(disk.single.progress, 1.0);
      // Checkpoint should be gone — job finished, no resume needed.
      expect(File('${tempDir.path}/job-$id.ckpt.jsonl').existsSync(), isFalse);
    });

    test('setError persists the error message', () async {
      final id = queue.enqueue('/tmp/oops.wav');
      queue.setError(id, 'file not found');
      await settle();

      final disk = await persistence.loadAllJobs();
      expect(disk.single.status, BatchJobStatus.error);
      expect(disk.single.errorMessage, 'file not found');
    });

    test('remove deletes the disk record', () async {
      final id = queue.enqueue('/tmp/gone.wav');
      await settle();
      expect(await persistence.loadAllJobs(), hasLength(1));

      queue.remove(id);
      await settle();

      expect(await persistence.loadAllJobs(), isEmpty);
    });

    test('clearAll wipes the queue and the disk dir', () async {
      queue.enqueue('/tmp/a.wav');
      queue.enqueue('/tmp/b.wav');
      await settle();

      queue.clearAll();
      await settle();

      expect(queue.state, isEmpty);
      expect(await persistence.loadAllJobs(), isEmpty);
    });

    test('clearCompleted drops done + cancelled rows from disk too',
        () async {
      final a = queue.enqueue('/tmp/a.wav');
      final b = queue.enqueue('/tmp/b.wav');
      final c = queue.enqueue('/tmp/c.wav');
      queue.setDone(a, resultText: 'a');
      queue.setCancelled(b);
      // c stays queued
      await settle();
      expect(await persistence.loadAllJobs(), hasLength(3));

      queue.clearCompleted();
      await settle();

      expect(queue.state.map((j) => j.id), [c]);
      final disk = await persistence.loadAllJobs();
      expect(disk.map((j) => j.id), [c]);
    });

    test('load() hydrates from disk + demotes running → queued', () async {
      // First notifier: enqueue + crash mid-run.
      final id = queue.enqueue('/tmp/crash.wav', backend: 'whisper');
      queue.setRunning(id);
      queue.setProgress(id, 0.6);
      await settle();

      // Second notifier on the same dir simulates a fresh app start.
      final reborn = BatchQueueNotifier(persistence: persistence);
      await reborn.load();

      expect(reborn.state, hasLength(1));
      final j = reborn.state.single;
      expect(j.id, id);
      // Running was demoted; progress reset to 0 so the next drain
      // pass starts from the top of the file (whole-file restart;
      // mid-file resume is commit 2 of this slice).
      expect(j.status, BatchJobStatus.queued);
      expect(j.progress, 0.0);
      // Demotion was persisted too.
      final diskAfter = await persistence.loadAllJobs();
      expect(diskAfter.single.status, BatchJobStatus.queued);
      reborn.dispose();
    });

    test('load() is idempotent — second call does nothing', () async {
      queue.enqueue('/tmp/foo.wav');
      await settle();

      final reborn = BatchQueueNotifier(persistence: persistence);
      await reborn.load();
      final firstSnapshot = List.of(reborn.state);
      // Mutate post-load …
      reborn.enqueue('/tmp/bar.wav');
      // … then load again — must NOT clobber the new state with the
      // initial disk snapshot.
      await reborn.load();
      expect(reborn.state.length, firstSnapshot.length + 1);
      reborn.dispose();
    });

    test('load() on an empty dir keeps state empty', () async {
      final fresh = BatchQueueNotifier(persistence: persistence);
      await fresh.load();
      expect(fresh.state, isEmpty);
      fresh.dispose();
    });
  });
}

