// Hermetic tests for LocalLlmCleanupService — exercises the
// service-layer behaviour (config gating, ensureOpen idempotency,
// reset-between-segments, batch cancellation, per-segment error
// swallowing, fingerprint cache invalidation) without spawning a
// real worker isolate or loading any GGUF.
//
// The seam is `LocalLlmBackend` — we inject a tiny stub that
// records every call and answers from a closure. Production
// wiring uses IsolateLocalLlmBackend; that path is covered by
// the upstream crispasr binding's own tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/local_llm_cleanup_service.dart';

void main() {
  LocalLlmConfig cfg({
    String modelPath = '/tmp/test.gguf',
    int? nGpuLayers = -1,
    int? nCtx,
    int maxTokens = 256,
    double temperature = 0.0,
  }) {
    return LocalLlmConfig(
      modelPath: modelPath,
      nGpuLayers: nGpuLayers,
      nCtx: nCtx,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  group('LocalLlmConfig.openFingerprint', () {
    test('stable for equal inputs', () {
      expect(cfg().openFingerprint, cfg().openFingerprint);
    });

    test('changes when modelPath changes', () {
      expect(cfg(modelPath: '/a.gguf').openFingerprint,
          isNot(cfg(modelPath: '/b.gguf').openFingerprint));
    });

    test('changes when nGpuLayers changes', () {
      expect(cfg(nGpuLayers: -1).openFingerprint,
          isNot(cfg(nGpuLayers: 0).openFingerprint));
    });

    test('unaffected by sampling params (temperature, maxTokens)', () {
      // Sampling params are passed per-generate-call; flipping
      // them must NOT force a session rebuild.
      expect(cfg(temperature: 0.0, maxTokens: 128).openFingerprint,
          cfg(temperature: 1.5, maxTokens: 999).openFingerprint);
    });
  });

  group('cleanupSegment', () {
    test('disabled config throws LocalLlmDisabledException', () async {
      final stub = _StubBackend(responder: (_) => 'unused');
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      await expectLater(
        svc.cleanupSegment(
            text: 'whatever',
            config: const LocalLlmConfig(modelPath: '')),
        throwsA(isA<LocalLlmDisabledException>()),
      );
      expect(stub.openCount, 0);
      expect(stub.generateCount, 0);
    });

    test('whitespace-only text short-circuits without opening', () async {
      final stub = _StubBackend(responder: (_) => 'unused');
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      final out = await svc.cleanupSegment(text: '   ', config: cfg());
      expect(out, '   ');
      expect(stub.openCount, 0);
      expect(stub.generateCount, 0);
    });

    test('happy path opens, resets, generates, returns trimmed reply',
        () async {
      final stub = _StubBackend(
          responder: (msgs) => '  cleaned text  ');
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      final out =
          await svc.cleanupSegment(text: 'um, the cat', config: cfg());
      expect(out, 'cleaned text');
      expect(stub.openCount, 1);
      expect(stub.resetCount, 1);
      expect(stub.generateCount, 1);
      // System prompt + user content land on the wire — pin the
      // contract so refactors don't silently drop the prompt.
      final lastMessages = stub.lastMessages!;
      expect(lastMessages.first['role'], 'system');
      expect(lastMessages.last['role'], 'user');
      expect(lastMessages.last['content'], 'um, the cat');
    });

    test('contextHint adds a second system message before the user turn',
        () async {
      final stub = _StubBackend(responder: (_) => 'ok');
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      await svc.cleanupSegment(
          text: 'hello', config: cfg(), contextHint: 'meeting on kubectl');
      final msgs = stub.lastMessages!;
      expect(msgs.length, 3);
      expect(msgs[0]['role'], 'system');
      expect(msgs[1]['role'], 'system');
      expect(msgs[1]['content'], contains('kubectl'));
      expect(msgs[2]['role'], 'user');
    });

    test('generate failure surfaces as LocalLlmException', () async {
      final stub = _StubBackend(
          responder: (_) =>
              throw const LocalLlmException('generate_failed', 'boom'));
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      await expectLater(
        svc.cleanupSegment(text: 'x', config: cfg()),
        throwsA(isA<LocalLlmException>()
            .having((e) => e.kind, 'kind', 'generate_failed')),
      );
    });
  });

  group('ensureOpen cache', () {
    test('idempotent for same fingerprint — second call skips open',
        () async {
      final stub = _StubBackend(responder: (_) => 'ok');
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      await svc.cleanupSegment(text: 'a', config: cfg());
      await svc.cleanupSegment(text: 'b', config: cfg());
      expect(stub.openCount, 1, reason: 'second call must reuse session');
      expect(stub.generateCount, 2);
    });

    test('reopens when openFingerprint changes (model swap)', () async {
      final stub = _StubBackend(responder: (_) => 'ok');
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      await svc.cleanupSegment(text: 'a', config: cfg(modelPath: '/x.gguf'));
      await svc.cleanupSegment(text: 'b', config: cfg(modelPath: '/y.gguf'));
      expect(stub.openCount, 2);
    });

    test('does not reopen when only sampling params change', () async {
      final stub = _StubBackend(responder: (_) => 'ok');
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      await svc.cleanupSegment(text: 'a', config: cfg(temperature: 0.0));
      await svc.cleanupSegment(text: 'b', config: cfg(temperature: 1.0));
      expect(stub.openCount, 1);
    });
  });

  group('cleanupBatch', () {
    test('runs every segment and reports progress', () async {
      final stub = _StubBackend(responder: (msgs) {
        // Echo back the user content uppercased so we can verify
        // ordering survives.
        final user = msgs.last['content'] as String;
        return user.toUpperCase();
      });
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);

      final progress = <List<int>>[];
      final out = await svc.cleanupBatch(
        texts: const ['hi', 'there', 'world'],
        config: cfg(),
        cancel: CleanupCancelToken(),
        onProgress: (d, t) => progress.add([d, t]),
      );
      expect(out, ['HI', 'THERE', 'WORLD']);
      expect(progress, [
        [1, 3],
        [2, 3],
        [3, 3]
      ]);
      // ensureOpen called once; reset called once per segment.
      expect(stub.openCount, 1);
      expect(stub.resetCount, 3);
      expect(stub.generateCount, 3);
    });

    test('cancellation bails between segments', () async {
      final cancel = CleanupCancelToken();
      var count = 0;
      final stub = _StubBackend(responder: (msgs) {
        count++;
        if (count == 2) cancel.cancel();
        return (msgs.last['content'] as String).toUpperCase();
      });
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      final out = await svc.cleanupBatch(
        texts: const ['a', 'b', 'c', 'd'],
        config: cfg(),
        cancel: cancel,
      );
      // First two segments processed; third + fourth skipped
      // because cancel flipped after the second response.
      expect(out, ['A', 'B']);
    });

    test('per-segment failure falls through with original text', () async {
      var i = 0;
      final stub = _StubBackend(responder: (msgs) {
        i++;
        if (i == 2) {
          throw const LocalLlmException('generate_failed', 'flake');
        }
        return (msgs.last['content'] as String).toUpperCase();
      });
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      final out = await svc.cleanupBatch(
        texts: const ['a', 'b', 'c'],
        config: cfg(),
        cancel: CleanupCancelToken(),
      );
      // Second segment falls through unchanged; first and third
      // are still LLM-cleaned. Critically the third runs at all
      // — one transient flake does not abort the whole batch.
      expect(out, ['A', 'b', 'C']);
    });

    test('disabled config rethrows on the first segment, not swallowed',
        () async {
      final stub = _StubBackend(responder: (_) => 'unused');
      final svc = LocalLlmCleanupService(backend: stub);
      addTearDown(svc.dispose);
      await expectLater(
        svc.cleanupBatch(
          texts: const ['a', 'b'],
          config: const LocalLlmConfig(modelPath: ''),
          cancel: CleanupCancelToken(),
        ),
        throwsA(isA<LocalLlmDisabledException>()),
      );
    });
  });
}

/// In-memory stub that satisfies the LocalLlmBackend contract
/// without any FFI, isolates, or libcrispasr. Records call
/// counts for assertion and the messages from the last generate
/// so tests can pin the prompt shape.
class _StubBackend implements LocalLlmBackend {
  _StubBackend({required this.responder});

  /// Build the canned reply from the messages passed to
  /// `generate`. Tests can throw to simulate a failing generate.
  final String Function(List<Map<String, String>> messages) responder;

  bool _open = false;
  int openCount = 0;
  int resetCount = 0;
  int generateCount = 0;
  List<Map<String, String>>? lastMessages;
  Map<String, Object?>? lastGenerateParams;

  @override
  bool get isOpen => _open;

  @override
  Future<void> open(LocalLlmConfig config) async {
    openCount++;
    _open = true;
  }

  @override
  Future<String> generate({
    required List<Map<String, String>> messages,
    required Map<String, Object?> generateParams,
  }) async {
    generateCount++;
    lastMessages = messages;
    lastGenerateParams = generateParams;
    return responder(messages);
  }

  @override
  Stream<String> generateStream({
    required List<Map<String, String>> messages,
    required Map<String, Object?> generateParams,
  }) async* {
    yield await generate(messages: messages, generateParams: generateParams);
  }

  @override
  Future<void> reset() async {
    resetCount++;
  }

  @override
  Future<void> dispose() async {
    _open = false;
  }
}
