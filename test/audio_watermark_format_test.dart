// Pure-byte / pure-math tests for AudioWatermarkService that the existing
// synthetic_compliance_test does NOT cover: the ID3v2.3 MP3 metadata
// injection and the beep-disclaimer PCM generator. Both are deterministic,
// dependency-free (only dart:math + dart:typed_data), so we assert the exact
// byte structure / sample layout rather than just round-tripping.
//
// This file imports ONLY the watermark service — a leaf module — so it stays
// independent of the heavier engine/service graph.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/audio_watermark_service.dart';

void main() {
  group('AudioWatermarkService.injectMp3Metadata', () {
    test('prepends a valid ID3v2.3 header in front of the original bytes', () {
      final mp3 = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00, 0x11, 0x22]);
      final out = AudioWatermarkService.injectMp3Metadata(mp3);

      // "ID3" magic + version 2.3 / revision 0.
      expect(out.sublist(0, 3), [0x49, 0x44, 0x33]);
      expect(out[3], 0x03); // major version 2.3
      expect(out[4], 0x00); // revision
      expect(out[5], 0x00); // flags

      // The original MP3 payload must be present, unmodified, at the tail.
      expect(out.sublist(out.length - mp3.length), mp3);
    });

    test('synchsafe size field equals the frames length and grows the buffer',
        () {
      final mp3 = Uint8List.fromList(List.filled(32, 0xAA));
      final out = AudioWatermarkService.injectMp3Metadata(mp3);

      // Decode the 4-byte synchsafe integer (7 bits per byte).
      final declaredSize = (out[6] << 21) | (out[7] << 14) | (out[8] << 7) | out[9];

      // Total = 10-byte header + declared frame bytes + original mp3.
      expect(out.length, 10 + declaredSize + mp3.length);
      // Every synchsafe byte must keep its high bit clear.
      for (final b in out.sublist(6, 10)) {
        expect(b & 0x80, 0, reason: 'synchsafe byte must be <= 0x7F');
      }
    });

    test('contains the AI-provenance TXXX frames with expected values',
        () {
      final out = AudioWatermarkService.injectMp3Metadata(
        Uint8List.fromList(List.filled(16, 0)),
      );
      final asString = String.fromCharCodes(out);

      // Each TXXX frame begins with the 4-char frame id "TXXX".
      // 4 mandatory frames: AI_GENERATED, GENERATOR, AI_CONTENT_NOTICE,
      // AI_TIMESTAMP. Optional frames (AI_MODEL, AI_VOICE) add more.
      expect('TXXX'.allMatches(asString).length, greaterThanOrEqualTo(4));
      expect(asString, contains('AI_GENERATED'));
      expect(asString, contains('true'));
      expect(asString, contains('GENERATOR'));
      expect(asString, contains('CrisperWeaver'));
      expect(asString, contains('AI_CONTENT_NOTICE'));
      expect(asString, contains('synthesized by an AI text-to-speech model'));
      expect(asString, contains('AI_TIMESTAMP'));
    });

    test('a single TXXX frame declares the correct big-endian payload size',
        () {
      final out = AudioWatermarkService.injectMp3Metadata(
        Uint8List.fromList(List.filled(16, 0)),
      );

      // Locate the first "TXXX" frame id.
      final idx = _indexOf(out, 'TXXX'.codeUnits);
      expect(idx, greaterThanOrEqualTo(10));

      // 4-byte big-endian size after the frame id.
      final size = (out[idx + 4] << 24) |
          (out[idx + 5] << 16) |
          (out[idx + 6] << 8) |
          out[idx + 7];

      // payload = encoding(1) + "AI_GENERATED" + NUL(1) + "true"
      const expected = 1 + 'AI_GENERATED'.length + 1 + 'true'.length;
      expect(size, expected);

      // Flags are two zero bytes, encoding byte is ISO-8859-1 (0x00),
      // description is NUL-terminated.
      expect(out[idx + 8], 0x00);
      expect(out[idx + 9], 0x00);
      expect(out[idx + 10], 0x00); // encoding marker
    });

    test('does not double-tag bytes that already start with an ID3 header', () {
      final already = Uint8List.fromList([0x49, 0x44, 0x33, 0x03, 0, 0, 1, 2, 3]);
      final out = AudioWatermarkService.injectMp3Metadata(already);
      expect(identical(out, already), isTrue);
    });

    test('tagging is idempotent: re-injecting returns the same bytes', () {
      final mp3 = Uint8List.fromList(List.filled(16, 0x55));
      final once = AudioWatermarkService.injectMp3Metadata(mp3);
      final twice = AudioWatermarkService.injectMp3Metadata(once);
      expect(twice, once);
    });
  });

  group('AudioWatermarkService.generateBeepDisclaimer', () {
    test('produces the documented total sample count at 24 kHz', () {
      const sr = 24000;
      final pcm = AudioWatermarkService.generateBeepDisclaimer(sampleRate: sr);

      final beep = (0.150 * sr).round();
      final gap = (0.080 * sr).round();
      final silence = (0.300 * sr).round();
      // 3 beeps + 2 gaps + trailing silence.
      final expected = 3 * beep + 2 * gap + silence;

      expect(pcm.length, expected);
    });

    test('sample count scales with the sample rate', () {
      final lo = AudioWatermarkService.generateBeepDisclaimer(sampleRate: 16000);
      final hi = AudioWatermarkService.generateBeepDisclaimer(sampleRate: 48000);
      expect(hi.length, greaterThan(lo.length));
    });

    test('all samples stay within the normalized [-1, 1] range', () {
      final pcm = AudioWatermarkService.generateBeepDisclaimer();
      for (final s in pcm) {
        expect(s, inInclusiveRange(-1.0, 1.0));
      }
    });

    test('ends with the trailing-silence region (last samples are zero)', () {
      const sr = 24000;
      final pcm = AudioWatermarkService.generateBeepDisclaimer(sampleRate: sr);
      final silence = (0.300 * sr).round();
      // The final `silence` samples should all be exactly 0.0.
      for (var i = pcm.length - silence; i < pcm.length; i++) {
        expect(pcm[i], 0.0);
      }
    });

    test('beep region actually contains audible (near-full-scale) energy', () {
      const sr = 24000;
      final pcm = AudioWatermarkService.generateBeepDisclaimer(sampleRate: sr);
      // Scan the first beep's steady-state region (past the 5 ms fade-in,
      // before the 5 ms fade-out) — the 880 Hz tone must reach near full
      // scale somewhere in there. We check the running peak rather than a
      // single sample to avoid landing on a sine zero-crossing.
      final fade = (0.005 * sr).round();
      final beep = (0.150 * sr).round();
      var peak = 0.0;
      for (var i = fade; i < beep - fade; i++) {
        if (pcm[i].abs() > peak) peak = pcm[i].abs();
      }
      expect(peak, greaterThan(0.9));
    });

    test('fade-in starts the very first beep near silence', () {
      final pcm = AudioWatermarkService.generateBeepDisclaimer();
      // First sample is at fade fraction 0/fadeSamples => exactly 0.0.
      expect(pcm.first, 0.0);
    });
  });
}

int _indexOf(Uint8List haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
