import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/audio_fingerprint_service.dart';

void main() {
  group('AudioFingerprintService', () {
    test('identical PCM produces identical fingerprint', () {
      final pcm = Float32List.fromList(
        List.generate(16000 * 5, (i) => (i % 100) / 100.0 - 0.5),
      );
      final fp1 = AudioFingerprintService.computeFingerprint(pcm, 16000);
      final fp2 = AudioFingerprintService.computeFingerprint(pcm, 16000);
      expect(fp1, equals(fp2));
    });

    test('different PCM produces different fingerprint', () {
      final pcm1 = Float32List.fromList(
        List.generate(16000 * 5, (i) => (i % 100) / 100.0 - 0.5),
      );
      final pcm2 = Float32List.fromList(
        List.generate(16000 * 5, (i) => (i % 73) / 73.0 - 0.5),
      );
      final fp1 = AudioFingerprintService.computeFingerprint(pcm1, 16000);
      final fp2 = AudioFingerprintService.computeFingerprint(pcm2, 16000);
      expect(fp1, isNot(equals(fp2)));
    });

    test('coarse fingerprint is deterministic', () {
      final pcm = Float32List.fromList(
        List.generate(16000 * 5, (i) => (i % 100) / 100.0 - 0.5),
      );
      final fp1 = AudioFingerprintService.computeCoarseFingerprint(pcm, 16000);
      final fp2 = AudioFingerprintService.computeCoarseFingerprint(pcm, 16000);
      expect(fp1, equals(fp2));
    });

    test('handles short audio (< 30s) without crash', () {
      final short = Float32List.fromList([0.1, -0.2, 0.3]);
      final fp = AudioFingerprintService.computeFingerprint(short, 16000);
      expect(fp, isNotEmpty);
    });

    test('handles empty audio', () {
      final empty = Float32List(0);
      final fp = AudioFingerprintService.computeFingerprint(empty, 16000);
      expect(fp, isNotEmpty);
    });

    test('isLikelyDuplicate matches identical fingerprints', () {
      final pcm = Float32List.fromList(
        List.generate(16000 * 5, (i) => (i % 100) / 100.0),
      );
      final fp = AudioFingerprintService.computeCoarseFingerprint(pcm, 16000);
      expect(AudioFingerprintService.isLikelyDuplicate(fp, fp), isTrue);
    });
  });
}
