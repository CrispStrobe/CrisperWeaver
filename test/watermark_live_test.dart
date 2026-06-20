// Live watermark round-trip test (PLAN §9.5 — the native spread-spectrum
// watermark's *detect* side, flagged ORPHANED because embed is wired into
// the TTS path but detect has no in-app caller).
//
// Exercises CrispasrWatermark.embed / .detect — the pure-DSP spread-
// spectrum watermark in the dylib. NO GGUF model is required: with no
// AudioSeal model loaded, embed/detect dispatch to the built-in
// frequency-domain spread-spectrum codec (see CrispASR
// examples/cli/crispasr_watermark.h). So this test only needs the dylib.
//
// Signatures (../CrispASR/flutter/crispasr/lib/src/crispasr.dart):
//   CrispasrWatermark.embed(Float32List pcm,
//       {double alpha = 0.005, DynamicLibrary? lib})  // ~line 4277
//     → returns a NEW Float32List with the watermark applied.
//   CrispasrWatermark.detect(Float32List pcm,
//       {DynamicLibrary? lib})                        // ~line 4295
//     → confidence in [0, 1]; the binding/header documents
//       > 0.65 = watermark present, < 0.40 = absent.
//
// Note the `embed`/`detect` arguments take a DynamicLibrary (opened via
// DynamicLibrary.open(CrispModels.lib!)), NOT a libPath string.
//
// The embed default alpha (0.005) is documented as "legacy / too faint
// for reliable detection on real speech"; the C impl's own default is
// 0.08. We pass a clearly-detectable alpha so the round-trip asserts the
// codec works, not that the legacy strength is enough.
//
// Self-skips when the dylib is missing or predates the watermark symbols.
//
// Run (no model needed):
//   CRISPASR_LIB=$(cd ../CrispASR/build/src && pwd)/libcrispasr.dylib \
//     TMPDIR=/Volumes/backups/code/tmp \
//     flutter test --tags slow test/watermark_live_test.dart

@Tags(['slow'])
library;

import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

/// Deterministic test signal: a 220 Hz sine at 16 kHz mono. Reproducible
/// (no RNG), and long enough (several seconds) to give the averaged-
/// spectrum detector many overlapping 1024-sample frames to integrate
/// over. Amplitude 0.5 keeps headroom so the watermark nudge never clips.
Float32List _sine220({int seconds = 4}) {
  const sr = 16000;
  const freq = 220.0;
  const amp = 0.5;
  final n = sr * seconds;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2.0 * math.pi * freq * i / sr);
  }
  return out;
}

void main() {
  // No model needed — gate on opt-in + the dylib (and the watermark symbols).
  final libPath = CrispModels.lib;
  String? skip = CrispModels.skipReason(); // opt-in / dylib-not-found
  DynamicLibrary? lib;
  if (skip != null) {
    // not enabled or no dylib — leave `skip` as-is
  } else if (libPath == null) {
    skip = 'libcrispasr dylib not found.';
  } else {
    try {
      lib = DynamicLibrary.open(libPath);
      if (!crispasr.CrispasrWatermark.isAvailable(lib: lib)) {
        skip = 'libcrispasr at $libPath predates the watermark API — '
            'rebuild CrispASR to run this test.';
        lib = null;
      }
    } on ArgumentError catch (e) {
      skip = 'failed to open $libPath: $e';
      lib = null;
    }
  }

  group('CrispasrWatermark spread-spectrum round-trip', () {
    // Header/binding threshold: >0.65 = present, <0.40 = absent. We assert
    // the watermarked signal clears 0.65 and that it beats the clean
    // signal by a clear margin (0.25) — robust to DSP/float variance
    // without leaning on a single magic absolute number.
    const presentThreshold = 0.65;
    const clearMargin = 0.25;
    // Use a clearly-detectable embed strength (the impl's own default is
    // 0.08; the binding default of 0.005 is documented as legacy/too faint).
    const alpha = 0.1;

    test('detect is low on clean audio and high after embed', () {
      final clean = _sine220();
      // Keep an independent copy to prove embed doesn't mutate our input
      // out from under us (it allocates + returns a new buffer).
      final cleanCopy = Float32List.fromList(clean);

      final cleanScore = crispasr.CrispasrWatermark.detect(clean, lib: lib);
      expect(cleanScore, inInclusiveRange(0.0, 1.0),
          reason: 'detect must return a confidence in [0, 1]');

      final marked =
          crispasr.CrispasrWatermark.embed(clean, alpha: alpha, lib: lib);
      expect(marked.length, clean.length,
          reason: 'embed returns a buffer of the same length');
      // embed returns a NEW buffer; our `clean` must be untouched.
      expect(clean, orderedEquals(cleanCopy),
          reason: 'embed must not mutate the caller-owned input buffer');

      final markedScore = crispasr.CrispasrWatermark.detect(marked, lib: lib);
      expect(markedScore, inInclusiveRange(0.0, 1.0));

      // Core assertions: watermarked is clearly above clean, and above the
      // documented "present" acceptance threshold.
      expect(markedScore, greaterThan(cleanScore + clearMargin),
          reason: 'watermarked confidence ($markedScore) must beat clean '
              '($cleanScore) by > $clearMargin');
      expect(markedScore, greaterThan(presentThreshold),
          reason: 'watermarked confidence ($markedScore) must clear the '
              'present threshold ($presentThreshold)');
    }, skip: skip);

    test('re-detecting the same watermarked buffer is stable', () {
      final marked = crispasr.CrispasrWatermark.embed(_sine220(),
          alpha: alpha, lib: lib);
      final a = crispasr.CrispasrWatermark.detect(marked, lib: lib);
      final b = crispasr.CrispasrWatermark.detect(marked, lib: lib);
      // detect is a pure function of its input — identical input,
      // identical score (no global state between calls).
      expect(a, b, reason: 'detect must be deterministic for fixed input');
      expect(a, greaterThan(presentThreshold));
    }, skip: skip);
  });
}
