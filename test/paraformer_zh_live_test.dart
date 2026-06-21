// Live Paraformer-zh test (PLAN §9.6 / §5.24D).
//
// Exercises the paraformer backend (NAR-ASR, 220M params, zh+en) through
// the unified session API. Paraformer is already in the catalog; this test
// validates the GGUF loads and produces a sensible English transcript on
// the bundled jfk.wav fixture.
//
// Tagged `slow`; self-skips when the dylib / paraformer model are absent.
//
// Run:
//   scripts/run_live_tests.sh test/paraformer_zh_live_test.dart

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  final baseSkip = CrispModels.skipReason();

  const jfkKeywords = ['country', 'ask', 'fellow', 'americans'];

  group('Paraformer-zh live (§9.6)', () {
    late crispasr.DecodedAudio audio;

    setUpAll(() {
      if (baseSkip != null) return;
      audio = crispasr.decodeAudioFile(
        CrispModels.fixture('jfk.wav'),
        libPath: lib,
      );
    });

    test('paraformer-zh transcribes English jfk.wav', () {
      final modelPath = CrispModels.model('paraformer_zh');
      if (modelPath == null) {
        markTestSkipped(
            'paraformer-zh model not under ${CrispModels.modelsDir}');
        return;
      }

      final session = crispasr.CrispasrSession.open(
        modelPath,
        backend: 'paraformer',
        libPath: lib,
      );
      addTearDown(session.close);

      expect(session.backend, 'paraformer');

      final segments = session.transcribe(audio.samples);
      final text =
          segments.map((s) => s.text).join(' ').trim().toLowerCase();

      expect(text, isNotEmpty,
          reason: 'paraformer: empty transcript on jfk.wav');
      expect(text.length, greaterThan(8),
          reason: 'paraformer: implausibly short transcript "$text"');

      printOnFailure('paraformer transcript: "$text"');
      final hit = jfkKeywords.any(text.contains);
      expect(hit, isTrue,
          reason: 'paraformer: transcript "$text" contains none of '
              '$jfkKeywords');
    }, skip: baseSkip);
  });
}
