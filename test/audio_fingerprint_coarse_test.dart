// Covers the AudioFingerprintService methods the existing
// audio_fingerprint_test.dart leaves untested:
//   * computeCoarseFingerprint — 4-bit-quantized, downsampled hash that must
//     stay stable under tiny PCM perturbations while still separating clearly
//     different audio, plus the odd-length nibble-packing path.
//   * computeFileFingerprint — size + first-64 KB SHA-256 over a real temp
//     file (dart:io only, no audio decoding / native models).
//
// The service is a leaf (only dart:io + dart:typed_data + crypto), so this
// stays independent of the engine graph.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/audio_fingerprint_service.dart';

Float32List sine(int n, {double amp = 0.5}) {
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * ((i % 100) / 100.0 * 2 - 1); // deterministic sawtooth
  }
  return out;
}

void main() {
  group('AudioFingerprintService.computeCoarseFingerprint', () {
    test('is deterministic for identical input', () {
      final pcm = sine(16000);
      final a = AudioFingerprintService.computeCoarseFingerprint(pcm, 16000);
      final b = AudioFingerprintService.computeCoarseFingerprint(pcm, 16000);
      expect(a, b);
      expect(a, isNotEmpty);
    });

    test('tolerates tiny perturbations below the 4-bit quantization step', () {
      final base = sine(16000);
      final nudged = Float32List.fromList(base);
      // 4-bit quantization step over [-1,1] is ~0.13; nudge by a hair so the
      // quantized bucket is unchanged.
      for (var i = 0; i < nudged.length; i++) {
        nudged[i] = (nudged[i] + 0.001).clamp(-1.0, 1.0);
      }
      final a = AudioFingerprintService.computeCoarseFingerprint(base, 16000);
      final b = AudioFingerprintService.computeCoarseFingerprint(nudged, 16000);
      expect(a, b, reason: 'sub-quantum noise must not change the coarse fp');
    });

    test('separates clearly different audio', () {
      final quiet = sine(16000, amp: 0.05);
      final loud = sine(16000, amp: 0.9);
      final a = AudioFingerprintService.computeCoarseFingerprint(quiet, 16000);
      final b = AudioFingerprintService.computeCoarseFingerprint(loud, 16000);
      expect(a, isNot(b));
    });

    test('handles odd-length downsampled streams (nibble packing path)', () {
      // Choose a length / rate that makes the downsampled list odd so the
      // trailing single-nibble branch executes.
      final pcm = sine(4001);
      // sampleRate=4000 → step=ceil(4000/4000)=1 → downsampled length 4001 (odd).
      final fp = AudioFingerprintService.computeCoarseFingerprint(pcm, 4000);
      expect(fp, isNotEmpty);
      // Stable across calls despite the odd-length tail handling.
      expect(
        fp,
        AudioFingerprintService.computeCoarseFingerprint(pcm, 4000),
      );
    });

    test('empty audio still produces a stable hash, not a crash', () {
      final fp =
          AudioFingerprintService.computeCoarseFingerprint(Float32List(0), 16000);
      expect(fp, isNotEmpty);
    });
  });

  group('AudioFingerprintService.computeFileFingerprint', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('fp_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('missing file returns empty string', () async {
      final fp = await AudioFingerprintService.computeFileFingerprint(
        '${tmp.path}/does_not_exist.bin',
      );
      expect(fp, '');
    });

    test('identical content yields identical fingerprint', () async {
      final a = File('${tmp.path}/a.bin')
        ..writeAsBytesSync(List.generate(2048, (i) => i % 256));
      final b = File('${tmp.path}/b.bin')
        ..writeAsBytesSync(List.generate(2048, (i) => i % 256));
      final fpA = await AudioFingerprintService.computeFileFingerprint(a.path);
      final fpB = await AudioFingerprintService.computeFileFingerprint(b.path);
      expect(fpA, isNotEmpty);
      expect(fpA, fpB);
    });

    test('different content yields different fingerprint', () async {
      final a = File('${tmp.path}/a.bin')..writeAsBytesSync([1, 2, 3, 4]);
      final b = File('${tmp.path}/b.bin')..writeAsBytesSync([9, 9, 9, 9]);
      final fpA = await AudioFingerprintService.computeFileFingerprint(a.path);
      final fpB = await AudioFingerprintService.computeFileFingerprint(b.path);
      expect(fpA, isNot(fpB));
    });

    test('size is part of the hash: same 64 KB head but different size differs',
        () async {
      // Both files share the same first 64 KB, but differ in total size.
      final head = List.generate(65536, (i) => i % 256);
      final a = File('${tmp.path}/a.bin')..writeAsBytesSync([...head]);
      final b = File('${tmp.path}/b.bin')
        ..writeAsBytesSync([...head, 0xFF, 0xFF]);
      final fpA = await AudioFingerprintService.computeFileFingerprint(a.path);
      final fpB = await AudioFingerprintService.computeFileFingerprint(b.path);
      expect(fpA, isNot(fpB),
          reason: 'size is mixed into the digest, so length must matter');
    });
  });
}
