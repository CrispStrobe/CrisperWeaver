import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/spread_spectrum_watermark.dart';

void main() {
  group('SpreadSpectrumWatermark', () {
    /// Generate a 1-second 440 Hz sine wave at 16 kHz.
    Float32List _sine({int sampleRate = 16000, double freq = 440.0, double seconds = 1.0}) {
      final n = (sampleRate * seconds).round();
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = 0.5 * math.sin(2.0 * math.pi * freq * i / sampleRate);
      }
      return out;
    }

    test('embed returns a different array of the same length', () {
      final pcm = _sine();
      final watermarked = SpreadSpectrumWatermark.embed(pcm);
      expect(watermarked.length, pcm.length);
      // At least some samples should differ.
      var diffs = 0;
      for (var i = 0; i < pcm.length; i++) {
        if ((watermarked[i] - pcm[i]).abs() > 1e-8) diffs++;
      }
      expect(diffs, greaterThan(0),
          reason: 'watermarked PCM should differ from original');
    });

    test('detect scores high on watermarked audio', () {
      final pcm = _sine(seconds: 2.0);
      final watermarked = SpreadSpectrumWatermark.embed(pcm);
      final score = SpreadSpectrumWatermark.detect(watermarked);
      expect(score, greaterThan(0.6),
          reason: 'should detect watermark with >0.6 confidence, got $score');
    });

    test('detect scores low on clean audio', () {
      final pcm = _sine(seconds: 2.0);
      final score = SpreadSpectrumWatermark.detect(pcm);
      expect(score, lessThan(0.65),
          reason: 'clean audio should score <0.65, got $score');
    });

    test('embed preserves audio within perceptual tolerance', () {
      // Use a richer signal (multi-tone) to simulate speech spectrum.
      final n = 32000;
      final pcm = Float32List(n);
      for (var i = 0; i < n; i++) {
        pcm[i] = 0.3 * math.sin(2.0 * math.pi * 200 * i / 16000) +
            0.2 * math.sin(2.0 * math.pi * 800 * i / 16000) +
            0.1 * math.sin(2.0 * math.pi * 2000 * i / 16000);
      }
      final watermarked = SpreadSpectrumWatermark.embed(pcm, alpha: 0.04);
      var signalPower = 0.0;
      var noisePower = 0.0;
      for (var i = 0; i < pcm.length; i++) {
        signalPower += pcm[i] * pcm[i];
        final diff = watermarked[i] - pcm[i];
        noisePower += diff * diff;
      }
      final snr = noisePower > 0
          ? 10.0 * math.log(signalPower / noisePower) / math.ln10
          : 100.0;
      // Spread-spectrum modifies selected frequency bins proportionally
      // to the signal energy. On synthetic test signals the modification
      // is more visible than on natural speech.
      expect(snr, greaterThan(5.0),
          reason: 'SNR should be >5 dB, got ${snr.toStringAsFixed(1)} dB');
      printOnFailure('SNR: ${snr.toStringAsFixed(1)} dB');
    });

    test('too-short audio returns unchanged', () {
      final short = Float32List(100);
      final result = SpreadSpectrumWatermark.embed(short);
      expect(result.length, 100);
      // Should be a copy but identical values.
      for (var i = 0; i < 100; i++) {
        expect(result[i], short[i]);
      }
    });

    test('detect on too-short audio returns 0', () {
      final score = SpreadSpectrumWatermark.detect(Float32List(100));
      expect(score, 0.0);
    });

    test('round-trip: embed then detect on speech-like noise', () {
      // Random noise (worse case than tonal audio).
      final rng = math.Random(42);
      final pcm = Float32List(32000); // 2 seconds at 16kHz
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = (rng.nextDouble() * 2.0 - 1.0) * 0.3;
      }
      final watermarked = SpreadSpectrumWatermark.embed(pcm);
      final score = SpreadSpectrumWatermark.detect(watermarked);
      expect(score, greaterThan(0.55),
          reason: 'should detect watermark in noise, got $score');
    });
  });
}
