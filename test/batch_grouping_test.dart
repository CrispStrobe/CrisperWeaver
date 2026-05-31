// Tests for §5.23 Q1 sub-bullet — grouping reorder + duration
// probe stamping. Both layers are pure Dart so the tests stay
// hermetic via Directory.systemTemp + a fake probe closure.

import 'dart:io';

import 'package:crisper_weaver/services/batch_persistence_service.dart';
import 'package:crisper_weaver/services/batch_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BatchQueueNotifier.reorderByGrouping', () {
    late Directory tempDir;
    late BatchPersistenceService persistence;
    late BatchQueueNotifier queue;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('batch-group-test-');
      persistence = BatchPersistenceService.withDirectory(tempDir);
      queue = BatchQueueNotifier(persistence: persistence);
    });

    tearDown(() async {
      queue.dispose();
      // Drain in-flight unawaited persist writes — _persist is fired
      // fire-and-forget from every state mutation; without this
      // settle the tempDir delete races them and fails with errno 66
      // (Directory not empty) on POSIX or sharing-violation on
      // Windows.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('empty queue is a no-op', () {
      queue.reorderByGrouping();
      expect(queue.state, isEmpty);
    });

    test('queue without queued jobs is a no-op', () {
      final id = queue.enqueue('/tmp/done.wav', backend: 'whisper');
      queue.setDone(id, resultText: 'x');
      final before = List.of(queue.state);
      queue.reorderByGrouping();
      expect(queue.state, equals(before));
    });

    test('groups consecutive same-backend jobs together', () {
      // Enqueue order: whisper, parakeet, whisper, parakeet
      queue.enqueue('/a.wav', backend: 'whisper', modelId: 'tiny');
      queue.enqueue('/b.wav', backend: 'parakeet', modelId: 'p3');
      queue.enqueue('/c.wav', backend: 'whisper', modelId: 'tiny');
      queue.enqueue('/d.wav', backend: 'parakeet', modelId: 'p3');

      queue.reorderByGrouping();

      // Expected: both parakeets together, both whispers together
      // (parakeet < whisper lexicographically). Within each bundle
      // the original enqueue order is preserved.
      expect(
          queue.state.map((j) => j.filePath).toList(),
          ['/b.wav', '/d.wav', '/a.wav', '/c.wav']);
    });

    test('preserves order within each (backend, modelId, language) bundle',
        () {
      queue.enqueue('/x1.wav', backend: 'whisper', modelId: 'tiny');
      queue.enqueue('/x2.wav', backend: 'whisper', modelId: 'tiny');
      queue.enqueue('/x3.wav', backend: 'whisper', modelId: 'large');

      queue.reorderByGrouping();

      // 'large' < 'tiny' lex; x1/x2 stay in enqueue order
      expect(queue.state.map((j) => j.filePath).toList(),
          ['/x3.wav', '/x1.wav', '/x2.wav']);
    });

    test('groups by (backend, modelId, language) tuple, not just backend',
        () {
      queue.enqueue('/en1.wav',
          backend: 'whisper', modelId: 'tiny', language: 'en');
      queue.enqueue('/de1.wav',
          backend: 'whisper', modelId: 'tiny', language: 'de');
      queue.enqueue('/en2.wav',
          backend: 'whisper', modelId: 'tiny', language: 'en');

      queue.reorderByGrouping();

      // de < en lex; en1 / en2 stay in enqueue order within the en bundle
      expect(queue.state.map((j) => j.filePath).toList(),
          ['/de1.wav', '/en1.wav', '/en2.wav']);
    });

    test('jobs with null metadata sort to the end (defensive against '
        'pre-Q1 entries)', () {
      // First: typed jobs
      queue.enqueue('/typed.wav', backend: 'whisper');
      // Then: a job from a code path that forgot to pass backend
      queue.enqueue('/untyped.wav');

      queue.reorderByGrouping();

      // Untyped sorts after typed (null at end).
      expect(queue.state.map((j) => j.filePath).toList(),
          ['/typed.wav', '/untyped.wav']);
    });

    test('reorders only queued jobs — done / error / running stay in place',
        () {
      final done = queue.enqueue('/d.wav', backend: 'whisper');
      queue.setDone(done, resultText: '');
      final err = queue.enqueue('/e.wav', backend: 'parakeet');
      queue.setError(err, 'oops');
      // Two queued jobs that should reorder.
      queue.enqueue('/q1.wav', backend: 'parakeet');
      queue.enqueue('/q2.wav', backend: 'canary');

      queue.reorderByGrouping();

      // Non-queued rows keep their original positions; the reorder
      // shuffles only the queued tail.
      final paths = queue.state.map((j) => j.filePath).toList();
      // First two are the non-queued rows in original order.
      expect(paths[0], '/d.wav');
      expect(paths[1], '/e.wav');
      // Tail is the queued rows reordered (canary < parakeet).
      expect(paths[2], '/q2.wav');
      expect(paths[3], '/q1.wav');
    });
  });

  group('BatchQueueNotifier duration probe', () {
    late Directory tempDir;
    late BatchPersistenceService persistence;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('batch-probe-test-');
      persistence = BatchPersistenceService.withDirectory(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('stamps durationSec from the injected probe', () async {
      // Fake probe: returns 12.5 seconds for any path.
      final queue = BatchQueueNotifier(
        persistence: persistence,
        durationProbe: (_) async => const Duration(milliseconds: 12500),
      );

      queue.enqueue('/tmp/foo.wav');
      // Deterministically drain the fire-and-forget probe → stamp →
      // persist chain (whenPersisted tracks the probe too), instead of
      // racing a fixed sleep — the disk read below flaked under parallel
      // load when the persist hadn't flushed within a 50 ms settle.
      await queue.whenPersisted();

      expect(queue.state.single.durationSec, closeTo(12.5, 1e-9));
      // The stamp is also persisted (so a restart doesn't re-probe
      // every file).
      final disk = await persistence.loadAllJobs();
      expect(disk.single.durationSec, closeTo(12.5, 1e-9));

      queue.dispose();
    });

    test('null probe result leaves durationSec untouched', () async {
      final queue = BatchQueueNotifier(
        persistence: persistence,
        durationProbe: (_) async => null,
      );

      queue.enqueue('/tmp/unknown.wav');
      await queue.whenPersisted();

      expect(queue.state.single.durationSec, isNull);
      queue.dispose();
    });

    test('probe failure is swallowed; enqueue still succeeds', () async {
      final queue = BatchQueueNotifier(
        persistence: persistence,
        durationProbe: (_) async => throw StateError('boom'),
      );

      // Enqueue returns synchronously regardless of probe outcome.
      final id = queue.enqueue('/tmp/explody.wav');
      expect(id, isNotEmpty);
      expect(queue.state.single.filePath, '/tmp/explody.wav');
      await queue.whenPersisted();
      // Probe threw → no durationSec, but the job is still queued.
      expect(queue.state.single.durationSec, isNull);
      expect(queue.state.single.status, BatchJobStatus.queued);
      queue.dispose();
    });

    test('zero-duration probe result is treated as "unknown"', () async {
      // 0-duration files exist (empty WAV header, corrupt input). The
      // probe doesn't lie about that, but for ETA purposes "0" is
      // useless and would be confusing in the queue card.
      final queue = BatchQueueNotifier(
        persistence: persistence,
        durationProbe: (_) async => Duration.zero,
      );
      queue.enqueue('/tmp/empty.wav');
      await queue.whenPersisted();
      expect(queue.state.single.durationSec, isNull);
      queue.dispose();
    });

    test('no probe injected → no stamping, no logged warning', () async {
      // Default ctor: no durationProbe. enqueue() must not crash.
      final queue = BatchQueueNotifier(persistence: persistence);
      queue.enqueue('/tmp/foo.wav');
      await queue.whenPersisted();
      expect(queue.state.single.durationSec, isNull);
      queue.dispose();
    });
  });
}
