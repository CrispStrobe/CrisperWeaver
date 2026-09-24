// Unit tests for BatchPersistenceService — the §5.23 Q1 + Q3
// foundation. Exercises each entry-point through a tempdir so the
// tests are hermetic (no path_provider mock needed), and pin the
// behavioural contract the BatchQueueNotifier depends on:
//
//   • saveJob / loadAllJobs round-trip every BatchJob field
//   • createdAt order is preserved across save → load
//   • corrupt / half-written job files are skipped, not thrown
//   • deleteJob removes the job AND any leftover checkpoint
//   • checkpoints are append-only JSON Lines
//   • partial / torn last-line in a checkpoint truncates cleanly
//     instead of throwing
//   • findResumableJobs returns only jobs with both a non-terminal
//     status AND an existing .ckpt.jsonl
//
// Cross-platform: uses Directory.systemTemp.createTemp so the tests
// pass on macOS / Linux / Windows / Android / iOS without any path_
// provider mocking. Pattern mirrors history_service_test.dart.

import 'dart:io';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/batch_persistence_service.dart';
import 'package:crisper_weaver/services/batch_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BatchPersistenceService', () {
    late Directory tempDir;
    late BatchPersistenceService svc;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('batch-persist-test-');
      svc = BatchPersistenceService.withDirectory(tempDir);
    });

    tearDown(() async {
      // Settle in-flight unawaited writes (the service's per-id
      // serializer chain still has pending whenComplete callbacks
      // when a test ends mid-stream).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    BatchJob sampleJob({
      String id = 'job-1',
      String filePath = '/tmp/sample.wav',
      BatchJobStatus status = BatchJobStatus.queued,
      double progress = 0.0,
    }) =>
        BatchJob(
          id: id,
          filePath: filePath,
          createdAt: DateTime.utc(2026, 5, 11, 12, 0, 0),
          status: status,
          progress: progress,
          backend: 'whisper',
          modelId: 'ggml-small.en',
          language: 'en',
          durationSec: 123.45,
        );

    test('saveJob + loadAllJobs round-trips every field', () async {
      final original = sampleJob(
        status: BatchJobStatus.done,
        progress: 1.0,
      ).copyWith(
        resultText: 'hello world',
        historyEntryId: 'hist-xyz',
      );
      await svc.saveJob(original);

      final loaded = await svc.loadAllJobs();
      expect(loaded, hasLength(1));
      final j = loaded.single;
      expect(j.id, original.id);
      expect(j.filePath, original.filePath);
      expect(j.createdAt, original.createdAt);
      expect(j.status, BatchJobStatus.done);
      expect(j.progress, 1.0);
      expect(j.resultText, 'hello world');
      expect(j.historyEntryId, 'hist-xyz');
      expect(j.backend, 'whisper');
      expect(j.modelId, 'ggml-small.en');
      expect(j.language, 'en');
      expect(j.durationSec, 123.45);
    });

    test('loadAllJobs returns jobs sorted by createdAt ascending', () async {
      final older = BatchJob(
        id: 'a',
        filePath: '/tmp/a.wav',
        createdAt: DateTime.utc(2026, 5, 11, 10, 0, 0),
      );
      final newer = BatchJob(
        id: 'b',
        filePath: '/tmp/b.wav',
        createdAt: DateTime.utc(2026, 5, 11, 11, 0, 0),
      );
      // Save in reverse order on purpose.
      await svc.saveJob(newer);
      await svc.saveJob(older);

      final loaded = await svc.loadAllJobs();
      expect(loaded.map((j) => j.id).toList(), ['a', 'b']);
    });

    test('loadAllJobs skips corrupt JSON files instead of throwing', () async {
      await svc.saveJob(sampleJob(id: 'good-1'));
      // Manually plant a corrupt file alongside.
      final corrupt = File('${tempDir.path}/job-bad.json');
      await corrupt.writeAsString('{ this is not valid json');

      final loaded = await svc.loadAllJobs();
      expect(loaded.map((j) => j.id).toList(), ['good-1']);
    });

    test('loadAllJobs skips empty .tmp leftovers', () async {
      // Simulate a half-written file from a crash mid-saveJob.
      final tmp = File('${tempDir.path}/job-pending.json.tmp');
      await tmp.writeAsString('');

      final loaded = await svc.loadAllJobs();
      expect(loaded, isEmpty);
    });

    test('deleteJob removes the JSON AND any checkpoint', () async {
      final job = sampleJob(id: 'doomed');
      await svc.saveJob(job);
      await svc.appendSegmentToCheckpoint(
        job.id,
        const TranscriptionSegment(
          text: 'foo',
          startTime: 0.0,
          endTime: 1.0,
        ),
      );

      expect(File('${tempDir.path}/job-doomed.json').existsSync(), isTrue);
      expect(File('${tempDir.path}/job-doomed.ckpt.jsonl').existsSync(), isTrue);

      await svc.deleteJob('doomed');

      expect(File('${tempDir.path}/job-doomed.json').existsSync(), isFalse);
      expect(File('${tempDir.path}/job-doomed.ckpt.jsonl').existsSync(), isFalse);
    });

    test('deleteJob on a missing id is a no-op', () async {
      await svc.saveJob(sampleJob(id: 'kept'));
      await svc.deleteJob('does-not-exist');
      // Nothing else got nuked.
      final loaded = await svc.loadAllJobs();
      expect(loaded.map((j) => j.id).toList(), ['kept']);
    });

    test('clearAll wipes every file in the queue directory', () async {
      await svc.saveJob(sampleJob(id: 'a'));
      await svc.saveJob(sampleJob(id: 'b'));
      await svc.appendSegmentToCheckpoint(
        'a',
        const TranscriptionSegment(text: 'x', startTime: 0, endTime: 1),
      );

      await svc.clearAll();

      // Directory still exists (so subsequent saves don't have to
      // recreate it); content is gone.
      expect(tempDir.existsSync(), isTrue);
      final remaining = tempDir.listSync();
      expect(remaining, isEmpty);
    });

    test('appendSegmentToCheckpoint + loadCheckpoint round-trip', () async {
      const segs = [
        TranscriptionSegment(
          text: 'one',
          startTime: 0.0,
          endTime: 1.5,
          confidence: 0.92,
        ),
        TranscriptionSegment(
          text: 'two',
          startTime: 1.5,
          endTime: 3.0,
          speaker: 'spk1',
          confidence: 0.81,
        ),
      ];
      for (final s in segs) {
        await svc.appendSegmentToCheckpoint('job-1', s);
      }

      final loaded = await svc.loadCheckpoint('job-1');
      expect(loaded, hasLength(2));
      expect(loaded[0].text, 'one');
      expect(loaded[0].endTime, 1.5);
      expect(loaded[0].confidence, closeTo(0.92, 1e-9));
      expect(loaded[1].text, 'two');
      expect(loaded[1].speaker, 'spk1');
      expect(loaded[1].startTime, 1.5);
    });

    test('loadCheckpoint of a missing job returns empty list', () async {
      final loaded = await svc.loadCheckpoint('never-existed');
      expect(loaded, isEmpty);
    });

    test('loadCheckpoint stops at the first torn line (crash mid-write)',
        () async {
      // Two valid segments + one truncated last line — simulates
      // a crash that killed the process between fsync and newline.
      final file = File('${tempDir.path}/job-torn.ckpt.jsonl');
      await file.writeAsString(
        '{"text":"complete one","startTime":0.0,"endTime":1.0,"confidence":1.0}\n'
        '{"text":"complete two","startTime":1.0,"endTime":2.0,"confidence":1.0}\n'
        '{"text":"torn", "start',
      );

      final loaded = await svc.loadCheckpoint('torn');
      expect(loaded.map((s) => s.text).toList(), ['complete one', 'complete two']);
    });

    test('deleteCheckpoint removes the file', () async {
      // Service prefixes with `job-` internally — use a bare id so the
      // direct-existsSync probe lines up with the actual filename.
      await svc.appendSegmentToCheckpoint(
        '1',
        const TranscriptionSegment(text: 'x', startTime: 0, endTime: 1),
      );
      expect(File('${tempDir.path}/job-1.ckpt.jsonl').existsSync(), isTrue);

      await svc.deleteCheckpoint('1');

      expect(File('${tempDir.path}/job-1.ckpt.jsonl').existsSync(), isFalse);
    });

    test('findResumableJobs returns only non-terminal jobs with a checkpoint',
        () async {
      // Scenario:
      //   - 'running-with-ckpt'  → kept (has ckpt, non-terminal)
      //   - 'queued-no-ckpt'     → skipped (no ckpt)
      //   - 'done-with-ckpt'     → skipped (terminal status)
      //   - 'cancelled-with-ckpt'→ skipped (terminal status)
      await svc.saveJob(sampleJob(
        id: 'running-with-ckpt',
        status: BatchJobStatus.running,
      ));
      await svc.appendSegmentToCheckpoint(
        'running-with-ckpt',
        const TranscriptionSegment(text: 'mid', startTime: 0, endTime: 1),
      );

      await svc.saveJob(sampleJob(id: 'queued-no-ckpt'));

      await svc.saveJob(sampleJob(
        id: 'done-with-ckpt',
        status: BatchJobStatus.done,
      ));
      await svc.appendSegmentToCheckpoint(
        'done-with-ckpt',
        const TranscriptionSegment(text: 'old', startTime: 0, endTime: 1),
      );

      await svc.saveJob(sampleJob(
        id: 'cancelled-with-ckpt',
        status: BatchJobStatus.cancelled,
      ));
      await svc.appendSegmentToCheckpoint(
        'cancelled-with-ckpt',
        const TranscriptionSegment(text: 'old', startTime: 0, endTime: 1),
      );

      final resumable = await svc.findResumableJobs();
      expect(resumable, ['running-with-ckpt']);
    });

    test('a reader never sees a job file half-written (crash / concurrent read)',
        () async {
      // saveJob used writeAsString, which truncates the file and then
      // writes it. A concurrent loadAllJobs could read it empty and drop
      // the job (the CI flake in batch_queue_service_test), and a crash
      // between truncate and write would lose the queued job for good.
      final job = BatchJob(
        id: 'job-atomic',
        filePath: '/tmp/a.wav',
        status: BatchJobStatus.queued,
        createdAt: DateTime.utc(2026, 9, 24),
        // Large enough that a write is not over before a read can start.
        resultText: 'x' * 200000,
      );
      await svc.saveJob(job);

      var bad = 0;
      final writes = <Future<void>>[];
      for (var i = 0; i < 40; i++) {
        writes.add(svc.saveJob(job.copyWith(progress: i / 40)));
        final seen = await svc.loadAllJobs();
        if (seen.length != 1) bad++;
      }
      await Future.wait(writes);
      expect(bad, 0, reason: 'reads that saw no intact job file');
      expect(await svc.loadAllJobs(), hasLength(1));
    });
  });

  group('BatchJob JSON', () {
    test('toJson + fromJson round-trip every field', () {
      final original = BatchJob(
        id: 'abc',
        filePath: '/tmp/foo.wav',
        createdAt: DateTime.utc(2026, 5, 11, 9, 30),
        status: BatchJobStatus.error,
        progress: 0.42,
        errorMessage: 'oops',
        resultText: 'partial result',
        historyEntryId: 'hist-1',
        backend: 'parakeet',
        modelId: 'parakeet-tdt-0.6b-v3-q4_k',
        language: 'de',
        durationSec: 60.0,
        resumeOffsetSec: 12.5,
      );
      final roundtrip = BatchJob.fromJson(original.toJson());
      expect(roundtrip.id, original.id);
      expect(roundtrip.filePath, original.filePath);
      expect(roundtrip.createdAt, original.createdAt);
      expect(roundtrip.status, BatchJobStatus.error);
      expect(roundtrip.progress, closeTo(0.42, 1e-9));
      expect(roundtrip.errorMessage, 'oops');
      expect(roundtrip.resultText, 'partial result');
      expect(roundtrip.historyEntryId, 'hist-1');
      expect(roundtrip.backend, 'parakeet');
      expect(roundtrip.modelId, 'parakeet-tdt-0.6b-v3-q4_k');
      expect(roundtrip.language, 'de');
      expect(roundtrip.durationSec, 60.0);
      expect(roundtrip.resumeOffsetSec, 12.5);
    });

    test('fromJson tolerates a minimal record with only the required fields',
        () {
      final job = BatchJob.fromJson({
        'id': 'min',
        'filePath': '/p.wav',
        'createdAt': '2026-05-11T08:00:00Z',
      });
      expect(job.id, 'min');
      expect(job.filePath, '/p.wav');
      expect(job.status, BatchJobStatus.queued);
      expect(job.progress, 0.0);
      expect(job.errorMessage, isNull);
      expect(job.resultText, isNull);
      expect(job.backend, isNull);
    });
  });
}
