import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// §5.25.11 — Audio fingerprint deduplication.
///
/// Computes a lightweight audio fingerprint from the first N seconds of
/// PCM data. Used to detect duplicate files in the batch queue before
/// spending compute on a re-transcription.
class AudioFingerprintService {
  AudioFingerprintService._();

  /// How many seconds of audio to use for the fingerprint.
  static const _fingerprintDurationSec = 30;

  /// Compute a fingerprint from raw PCM float32 samples.
  ///
  /// Uses SHA-256 over the first [_fingerprintDurationSec] seconds of
  /// audio, quantized to 8-bit (reduces sensitivity to minor
  /// floating-point differences from different decoders while still
  /// catching true duplicates).
  static String computeFingerprint(Float32List pcm, int sampleRate) {
    final samplesToUse =
        (sampleRate * _fingerprintDurationSec).clamp(0, pcm.length);

    // Quantize to 8-bit for noise-tolerant hashing
    final quantized = Uint8List(samplesToUse);
    for (var i = 0; i < samplesToUse; i++) {
      // Map [-1.0, 1.0] → [0, 255]
      final clamped = pcm[i].clamp(-1.0, 1.0);
      quantized[i] = ((clamped + 1.0) * 127.5).round().clamp(0, 255);
    }

    final digest = sha256.convert(quantized);
    return digest.toString();
  }

  /// Compute a "coarse" fingerprint that's more tolerant of minor
  /// differences (e.g., different MP3 decoders producing slightly
  /// different PCM). Uses 4-bit quantization + downsampling.
  static String computeCoarseFingerprint(Float32List pcm, int sampleRate) {
    final samplesToUse =
        (sampleRate * _fingerprintDurationSec).clamp(0, pcm.length);

    // Downsample to 4 kHz equivalent for coarse matching
    final step = (sampleRate / 4000).ceil();
    final downsampled = <int>[];
    for (var i = 0; i < samplesToUse; i += step) {
      // 4-bit quantization: [-1.0, 1.0] → [0, 15]
      final clamped = pcm[i].clamp(-1.0, 1.0);
      downsampled.add(((clamped + 1.0) * 7.5).round().clamp(0, 15));
    }

    // Pack pairs of 4-bit values into bytes
    final packed = Uint8List((downsampled.length + 1) ~/ 2);
    for (var i = 0; i < downsampled.length - 1; i += 2) {
      packed[i ~/ 2] = (downsampled[i] << 4) | downsampled[i + 1];
    }
    if (downsampled.length.isOdd) {
      packed[packed.length - 1] = downsampled.last << 4;
    }

    final digest = sha256.convert(packed);
    return digest.toString();
  }

  /// Check if two fingerprints match (exact match on the coarse
  /// fingerprint indicates very likely the same audio).
  static bool isLikelyDuplicate(String fp1, String fp2) {
    return fp1 == fp2;
  }
}
