// Covers the pure DSP / helper methods of AudioUtils that the existing
// audio_utils_test.dart does NOT exercise: getAudioFormat, applyPreEmphasis,
// resample (linear interpolation), reduceNoise (noise gate) and
// splitOnSilence (silence-based chunking). All are static, side-effect-free
// and depend only on dart:typed_data + dart:math, so they unit-test cleanly
// without any engine / native-model imports.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/utils/audio_utils.dart';

void main() {
  group('AudioUtils.getAudioFormat', () {
    test('maps known extensions to canonical format names', () {
      expect(AudioUtils.getAudioFormat('a.wav'), 'wav');
      expect(AudioUtils.getAudioFormat('a.mp3'), 'mp3');
      expect(AudioUtils.getAudioFormat('a.m4a'), 'm4a');
      expect(AudioUtils.getAudioFormat('a.mp4'), 'm4a'); // mp4 folds to m4a
      expect(AudioUtils.getAudioFormat('a.aac'), 'aac');
      expect(AudioUtils.getAudioFormat('a.ogg'), 'ogg');
      expect(AudioUtils.getAudioFormat('a.flac'), 'flac');
      expect(AudioUtils.getAudioFormat('a.opus'), 'opus');
      expect(AudioUtils.getAudioFormat('a.webm'), 'webm');
    });

    test('is case-insensitive', () {
      expect(AudioUtils.getAudioFormat('LOUD.WAV'), 'wav');
      expect(AudioUtils.getAudioFormat('Song.Mp3'), 'mp3');
    });

    test('returns "unknown" for unrecognised or extensionless paths', () {
      expect(AudioUtils.getAudioFormat('a.txt'), 'unknown');
      expect(AudioUtils.getAudioFormat('noext'), 'unknown');
    });
  });

  group('AudioUtils.isSupportedAudioFile', () {
    test('accepts a path with directories and mixed case', () {
      expect(AudioUtils.isSupportedAudioFile('/a/b/Clip.FLAC'), isTrue);
    });

    test('rejects unsupported and extensionless files', () {
      expect(AudioUtils.isSupportedAudioFile('/a/b/notes.txt'), isFalse);
      expect(AudioUtils.isSupportedAudioFile('/a/b/README'), isFalse);
    });
  });

  group('AudioUtils.applyPreEmphasis', () {
    test('short inputs (<= 1 sample) pass through unchanged', () {
      final one = Float32List.fromList([0.5]);
      expect(AudioUtils.applyPreEmphasis(one), same(one));
      final empty = Float32List(0);
      expect(AudioUtils.applyPreEmphasis(empty), same(empty));
    });

    test('first sample is preserved; rest follow y[i]=x[i]-a*x[i-1]', () {
      final x = Float32List.fromList([1.0, 1.0, 1.0]);
      final y = AudioUtils.applyPreEmphasis(x, 0.97);
      expect(y[0], closeTo(1.0, 1e-6));
      expect(y[1], closeTo(1.0 - 0.97 * 1.0, 1e-6));
      expect(y[2], closeTo(1.0 - 0.97 * 1.0, 1e-6));
    });

    test('a flat DC signal is attenuated (high-pass character)', () {
      final dc = Float32List.fromList(List.filled(8, 1.0));
      final y = AudioUtils.applyPreEmphasis(dc);
      // After the first sample, the filtered magnitude must drop well below
      // the original DC level.
      for (var i = 1; i < y.length; i++) {
        expect(y[i].abs(), lessThan(0.1));
      }
    });
  });

  group('AudioUtils.resample', () {
    test('identical rates return the input untouched', () {
      final x = Float32List.fromList([0.1, 0.2, 0.3]);
      expect(AudioUtils.resample(x, 16000, 16000), same(x));
    });

    test('downsampling halves the sample count (ratio 2:1)', () {
      final x = Float32List.fromList(List.generate(100, (i) => i.toDouble()));
      final y = AudioUtils.resample(x, 32000, 16000);
      expect(y.length, 50);
    });

    test('upsampling roughly doubles the sample count', () {
      final x = Float32List.fromList(List.generate(50, (i) => i.toDouble()));
      final y = AudioUtils.resample(x, 16000, 32000);
      expect(y.length, 100);
    });

    test('linear interpolation preserves a ramp monotonically', () {
      // A perfect ramp resampled by linear interpolation stays monotonic.
      final x = Float32List.fromList(List.generate(40, (i) => i.toDouble()));
      final y = AudioUtils.resample(x, 16000, 24000);
      for (var i = 1; i < y.length; i++) {
        expect(y[i], greaterThanOrEqualTo(y[i - 1] - 1e-6));
      }
      // Endpoints are anchored to the source extremes.
      expect(y.first, closeTo(0.0, 1e-6));
    });
  });

  group('AudioUtils.reduceNoise', () {
    test('very short buffers (< 1024 samples) are returned unchanged', () {
      final x = Float32List.fromList(List.filled(512, 0.5));
      expect(AudioUtils.reduceNoise(x), same(x));
    });

    test('gates low-amplitude tail below the estimated noise floor', () {
      // First 10% is quiet noise (floor estimate), the rest alternates a
      // loud tone with quiet samples. Quiet samples should be pulled toward
      // zero; loud samples should survive largely intact.
      const n = 2048;
      final x = Float32List(n);
      final noiseLen = (n * 0.1).round();
      for (var i = 0; i < noiseLen; i++) {
        x[i] = 0.01; // quiet noise floor
      }
      for (var i = noiseLen; i < n; i++) {
        x[i] = (i % 2 == 0) ? 0.9 : 0.005; // loud / very quiet
      }
      final y = AudioUtils.reduceNoise(x, noiseReduction: 0.5);
      expect(y.length, n);

      // A loud sample stays loud.
      final loudIdx = noiseLen + (((noiseLen) % 2 == 0) ? 0 : 1);
      expect(y[loudIdx].abs(), greaterThan(0.5));

      // A very-quiet sample is attenuated relative to the input.
      final quietIdx = loudIdx + 1;
      expect(y[quietIdx].abs(), lessThan(x[quietIdx].abs() + 1e-9));
      expect(y[quietIdx].abs(), lessThan(0.01));
    });
  });

  group('AudioUtils.splitOnSilence', () {
    test('a continuously loud signal with no gap yields one trailing chunk',
        () {
      const sr = 16000;
      // Constant 0.5 amplitude (well above the 0.01 silence threshold) with
      // no zero-crossings, so there is never a qualifying silence gap. The
      // method still emits the single end-of-stream chunk spanning it all.
      final samples = Float32List.fromList(
        List.generate(sr * 2, (_) => 0.5),
      );
      final chunks = AudioUtils.splitOnSilence(samples, sr);
      expect(chunks, hasLength(1));
      expect(chunks.single.startTime, closeTo(0.0, 1e-6));
      expect(chunks.single.endTime, closeTo(2.0, 1e-6));
    });

    test('a clear silence gap separates two loud segments into two chunks',
        () {
      const sr = 16000;
      final out = <double>[];
      // 2 s loud (constant 0.5), 1 s silence, 2 s loud — constant amplitude
      // avoids sine zero-crossings that would falsely register as silence.
      for (var i = 0; i < sr * 2; i++) {
        out.add(0.5);
      }
      for (var i = 0; i < sr; i++) {
        out.add(0.0);
      }
      for (var i = 0; i < sr * 2; i++) {
        out.add(0.5);
      }
      final samples = Float32List.fromList(out);

      final chunks = AudioUtils.splitOnSilence(samples, sr);
      // One chunk cut at the silence gap + the trailing end-of-stream chunk.
      expect(chunks, hasLength(2));
      // The first chunk spans the leading loud region up to the gap.
      final first = chunks.first;
      expect(first.startTime, closeTo(0.0, 1e-6));
      expect(first.endTime, closeTo(2.0, 0.05));
      expect(first.sampleRate, sr);
      // The second (trailing) chunk starts after the gap.
      expect(chunks.last.startTime, greaterThan(first.endTime));
    });
  });
}
