// Live forced-alignment test (PLAN §9.1 exemplar pattern).
//
// Exercises crispasr.alignWords(...) — the free-function wrapper over the
// native `crispasr_align_words_abi` entrypoint that AlignerService relies
// on for per-word timestamp backfill. Given an aligner GGUF, a reference
// transcript, and 16 kHz mono PCM, it returns a List<AlignedWord> with
// per-word (start, end) timings in seconds. Tagged `slow`; self-skips when
// the dylib / canary-ctc-aligner model are absent.
//
// ENTRYPOINT NOTES (verified against CrispASR src — do NOT assume the
// obvious path):
//   * alignWords() is a FREE FUNCTION, not a CrispASR ctx method. The
//     native `crispasr_align_words_abi(aligner_model, transcript, samples,
//     n_samples, t_offset_cs, n_threads)` LOADS the aligner model itself
//     (crispasr_c_api.cpp:5135) — there is NO whisper ASR context to open
//     or dispose here. So, unlike the VAD exemplar, we pass the aligner
//     model directly as `alignerModel:` and never construct CrispASR().
//   * Return semantics (crispasr_c_api.cpp:5142-5147): the C API returns
//     nullptr when the aligner produces zero words; the Dart wrapper
//     (crispasr.dart:583) maps nullptr -> `const []`. It also returns []
//     on empty inputs. Timings come back in CENTISECONDS and the wrapper
//     divides by 100.0 -> seconds (crispasr.dart:585-589).
//   * This mirrors AlignerService.addWordTimestamps exactly (it calls the
//     same crispasr.alignWords(alignerModel:, transcript:, pcm:)).
//
// Run:
//   scripts/run_live_tests.sh test/aligner_live_test.dart

@Tags(['slow'])
library;

import 'dart:ffi';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  // canary-ctc-aligner-q4_k.gguf (~442 MB) is the only required model.
  final skip = CrispModels.skipReason(models: ['canary_aligner']);

  // Full transcript of the bundled 11 s jfk.wav. Same opening phrase the
  // existing tests use (backend_dispatch_test.dart:771), extended to the
  // complete line so the aligner has the whole clip's worth of words.
  const transcript = 'And so my fellow Americans, ask not what your country '
      'can do for you, ask what you can do for your country.';

  group('Aligner live (forced word timings)', () {
    late crispasr.DecodedAudio audio;

    setUp(() {
      if (skip != null) return;
      audio = crispasr.decodeAudioFile(
        CrispModels.fixture('jfk.wav'),
        libPath: lib,
      );
    });

    test('decodes the fixture to 16 kHz mono PCM', () {
      expect(audio.sampleRate, 16000);
      expect(audio.samples.length, greaterThan(16000)); // > 1 s of audio
    }, skip: skip);

    test('force-aligns the JFK line into monotonic per-word timings', () {
      final alignerModel = CrispModels.model('canary_aligner');
      if (alignerModel == null) {
        // Belt-and-braces self-skip (skipReason already covers this).
        markTestSkipped('canary-ctc-aligner-q4_k.gguf not under models dir');
        return;
      }

      // alignWords takes a `lib` DynamicLibrary (not a `libPath` string,
      // unlike decodeAudioFile / CrispASR). Open the harness-resolved
      // dylib so the test exercises the freshly-built CrispASR, not
      // whatever `defaultLibName()` happens to find on the loader path.
      final words = crispasr.alignWords(
        alignerModel: alignerModel,
        transcript: transcript,
        pcm: audio.samples,
        lib: lib != null ? DynamicLibrary.open(lib) : null,
      );

      // Non-empty: the aligner must place at least the bulk of the words.
      expect(words, isNotEmpty,
          reason: 'forced alignment of the JFK line must yield words');

      // Plausible word count for this sentence (~21 reference words). Be
      // robust to tokenisation differences and dropped/merged words —
      // don't hard-code an exact count.
      expect(words.length, greaterThanOrEqualTo(8),
          reason: 'at least a substantial fraction of the sentence');
      expect(words.length, lessThanOrEqualTo(40),
          reason: 'not wildly more tokens than words in the line');

      final clipEnd = audio.durationSeconds + 0.25; // small epsilon

      double prevStart = -1.0;
      for (final w in words) {
        // Each word: start <= end.
        expect(w.start, lessThanOrEqualTo(w.end),
            reason: 'word "${w.text}" start must not exceed end');
        // Within [0, clip duration + epsilon].
        expect(w.start, greaterThanOrEqualTo(0.0),
            reason: 'word "${w.text}" start must be non-negative');
        expect(w.end, lessThanOrEqualTo(clipEnd),
            reason: 'word "${w.text}" end must fall within the clip');
        // Monotonic non-decreasing starts across the sequence.
        expect(w.start, greaterThanOrEqualTo(prevStart),
            reason: 'word starts must be monotonic non-decreasing');
        prevStart = w.start;
      }

      // The aligned span should cover a meaningful chunk of the clip, not
      // collapse to a single instant at t=0.
      final span = words.last.end - words.first.start;
      expect(span, greaterThan(1.0),
          reason: 'aligned words should span more than a second of audio');
    }, skip: skip);
  });
}
