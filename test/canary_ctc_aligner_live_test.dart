// Live canary-ctc-aligner test (PLAN §10.2).
//
// Validates the canary-ctc-aligner catalog entry works end-to-end:
// given a transcript + audio, alignWords returns per-word timestamps
// with monotonically increasing onsets. This mirrors the existing
// aligner_live_test.dart but is specifically pinned to the catalog
// entry added in §10 (canary-ctc-aligner-q4_k).
//
// Tagged `slow`; self-skips when the dylib / aligner model are absent.
//
// Run:
//   scripts/run_live_tests.sh test/canary_ctc_aligner_live_test.dart

@Tags(['slow'])
library;

import 'dart:ffi';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  final skip = CrispModels.skipReason(models: ['canary_aligner']);

  const transcript = 'And so my fellow Americans, ask not what your country '
      'can do for you, ask what you can do for your country.';

  group('Canary CTC aligner live (§10 catalog entry)', () {
    test('alignWords returns monotonic word timings', () {
      final alignerModel = CrispModels.model('canary_aligner')!;
      final jfk = CrispModels.fixture('jfk.wav');

      // Decode to 16 kHz mono PCM.
      final audio = crispasr.decodeAudioFile(jfk, libPath: lib);
      expect(audio.samples, isNotEmpty, reason: 'decode should return samples');

      // Run forced alignment.
      final words = crispasr.alignWords(
        alignerModel: alignerModel,
        transcript: transcript,
        pcm: audio.samples,
        lib: lib != null ? DynamicLibrary.open(lib) : null,
      );
      expect(words, isNotEmpty,
          reason: 'alignWords should return at least one word');

      // Verify monotonic onsets.
      for (var i = 1; i < words.length; i++) {
        expect(words[i].start, greaterThanOrEqualTo(words[i - 1].start),
            reason: 'word ${words[i].text} onset '
                '(${words[i].start}) < previous word '
                '${words[i - 1].text} onset (${words[i - 1].start})');
      }

      // Verify all timings are within a plausible range (0..30 seconds
      // for the 11 s JFK clip — generous to avoid flaky failures).
      for (final w in words) {
        expect(w.start, greaterThanOrEqualTo(0.0),
            reason: '${w.text} onset must be non-negative');
        expect(w.end, lessThanOrEqualTo(30.0),
            reason: '${w.text} end (${w.end}s) seems too large for 11s clip');
        expect(w.end, greaterThanOrEqualTo(w.start),
            reason: '${w.text} end < start');
      }

      // Check we got a reasonable number of words (transcript has ~22).
      expect(words.length, greaterThan(10),
          reason: 'expected at least 10 aligned words, got ${words.length}');
    }, skip: skip);
  });
}
