// GlintCodecService — codec routing helpers + (when libglint is on the
// load path) a real encode→decode round-trip.
//
// The round-trip group is gated on [GlintCodecService.isAvailable] so the
// suite stays green on machines/CI without the native lib bundled. To run
// it locally, put libglint on the loader path, e.g.:
//   DYLD_LIBRARY_PATH=../glint/build flutter test test/glint_codec_test.dart
//   LD_LIBRARY_PATH=../glint/build   flutter test test/glint_codec_test.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisper_weaver/services/glint_codec_service.dart';

Float32List _sine({
  double seconds = 0.5,
  int sampleRate = 16000,
  double freq = 440,
}) {
  final n = (seconds * sampleRate).round();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.5 * sin(2 * pi * freq * i / sampleRate);
  }
  return out;
}

void main() {
  group('canDecodePath', () {
    test('accepts compressed extensions, case-insensitive', () {
      expect(GlintCodecService.canDecodePath('/a/b/song.mp3'), isTrue);
      expect(GlintCodecService.canDecodePath('clip.AAC'), isTrue);
      expect(GlintCodecService.canDecodePath('voice.Opus'), isTrue);
      expect(GlintCodecService.canDecodePath('x.ogg'), isTrue);
    });

    test('rejects non-compressed / extension-less paths', () {
      expect(GlintCodecService.canDecodePath('/a/b/audio.wav'), isFalse);
      expect(GlintCodecService.canDecodePath('notes.txt'), isFalse);
      expect(GlintCodecService.canDecodePath('no_extension'), isFalse);
      expect(GlintCodecService.canDecodePath(''), isFalse);
    });
  });

  group('GlintFormat', () {
    test('carries codec, extension and label', () {
      expect(GlintFormat.mp3.extension, 'mp3');
      expect(GlintFormat.aac.extension, 'aac');
      expect(GlintFormat.opus.extension, 'opus');
      expect(GlintFormat.all, hasLength(3));
      expect(GlintFormat.all.map((f) => f.label),
          containsAll(<String>['MP3', 'AAC', 'Opus']));
    });
  });

  group('encodePcm guards', () {
    test('throws on empty PCM when the codec is available', () {
      if (!GlintCodecService.isAvailable) return; // covered by round-trip gate
      expect(
        () => const GlintCodecService().encodePcm(
          Float32List(0),
          channels: 1,
          sampleRate: 16000,
          format: GlintFormat.mp3,
        ),
        throwsStateError,
      );
    });
  });

  group('encode → decode round-trip', () {
    test('libglint is loadable in this environment', () {
      if (!GlintCodecService.isAvailable) {
        // Not a failure: the native lib just isn't on the load path here.
        // ignore: avoid_print
        print('SKIP: libglint not available — round-trip not exercised');
      }
    }, skip: !GlintCodecService.isAvailable);

    test('MP3: encodes a sine and decodes back to comparable duration', () {
      final pcm = _sine();
      const svc = GlintCodecService();
      final mp3 = svc.encodePcm(
        pcm,
        channels: 1,
        sampleRate: 16000,
        format: GlintFormat.mp3,
      );
      expect(mp3, isNotEmpty);
      // MP3 frame sync word 0xFF 0xEx.
      expect(mp3[0], 0xFF);

      final decoded = svc.decodeBytes(mp3);
      expect(decoded.channels, 1);
      expect(decoded.sampleRate, greaterThan(0));
      final durIn = pcm.length / 16000;
      final durOut = decoded.pcm.length / decoded.channels / decoded.sampleRate;
      // Encoder/decoder delay + frame padding shifts duration a little.
      expect(durOut, greaterThan(durIn - 0.2));
      expect(durOut, lessThan(durIn + 0.3));
    }, skip: !GlintCodecService.isAvailable);

    test('Opus: encodes and decodes back', () {
      final pcm = _sine();
      const svc = GlintCodecService();
      final opus = svc.encodePcm(
        pcm,
        channels: 1,
        sampleRate: 16000,
        format: GlintFormat.opus,
      );
      expect(opus, isNotEmpty);
      // Ogg container magic "OggS".
      expect(String.fromCharCodes(opus.sublist(0, 4)), 'OggS');

      final decoded = svc.decodeBytes(opus);
      expect(decoded.pcm, isNotEmpty);
      expect(decoded.sampleRate, greaterThan(0));
    }, skip: !GlintCodecService.isAvailable);
  });
}
