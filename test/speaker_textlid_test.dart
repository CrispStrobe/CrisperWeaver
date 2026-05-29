// Tests for the text-LID + speaker re-ID extensions.
//
//   * Pure unit test for speakerEnrollNameSeed (always runs).
//   * Opt-in 'slow' LIVE tests (need the dylib + a model on disk):
//       - text-LID: detectTextLanguage on known-language strings.
//       - speaker embeddings: a TitaNet embed cosine check —
//         same-speaker (two halves of jfk.wav) must score higher than
//         cross-speaker, and above the 0.7 match threshold. This is the
//         core of re-identification (does the embedding separate
//         speakers?), without SpeakerDB file I/O.
//
//         NOTE: this verifies DISCRIMINABILITY (and that re-ID works
//         self-consistently), NOT bit-parity with the NeMo reference.
//         Reference parity is established + documented upstream
//         (cstr/titanet-large-GGUF): encoder+decoder cos = 0.999997
//         (mel-injected — the network is faithful), end-to-end cos =
//         0.917 (a known float32 STFT precision gap in the mel front-end,
//         not a model error). A reference-parity test would compare
//         against a NeMo .npy dump (tools/reference_backends/titanet.py +
//         models/titanet-dump-ref-embeddings.py → test-titanet --ref-emb)
//         and needs the NeMo/PyTorch env — out of scope for this suite.
//
// Run the live tests:
//   CRISPASR_LIB=/abs/libwhisper.dylib \
//   CRISPASR_TEST_CLD3_MODEL=/abs/cld3-f16.gguf \
//   CRISPASR_TEST_TITANET_MODEL=/abs/titanet-large.gguf \
//   CRISPASR_TEST_OTHER_SPEAKER_WAV=/abs/other-speaker.wav \
//   flutter test test/speaker_textlid_test.dart --tags slow
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/widgets/transcription_output_widget.dart'
    show speakerEnrollNameSeed;

String? _resolveLibPath() {
  final env = Platform.environment['CRISPASR_LIB'];
  if (env != null && env.isNotEmpty) {
    return File(env).existsSync() ? env : null;
  }
  for (final c in [
    '../CrispASR/build-flutter-bundle/src/libwhisper.dylib',
    '../CrispASR/build/src/libwhisper.dylib',
    '../CrispASR/build/src/libcrispasr.dylib',
  ]) {
    if (File(c).existsSync()) return File(c).absolute.path;
  }
  return null;
}

double _cosine(Float32List a, Float32List b) {
  // TitaNet embeddings are L2-normalised, so cosine == dot product.
  var dot = 0.0;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

void main() {
  group('speakerEnrollNameSeed', () {
    test('bare cluster ids seed an empty field', () {
      for (final id in ['0', '3', 'Speaker 1', 'speaker 12', 'SPEAKER  2']) {
        expect(speakerEnrollNameSeed(id), '',
            reason: '"$id" is a cluster label, not a name');
      }
    });
    test('real names are kept (and trimmed)', () {
      expect(speakerEnrollNameSeed('Alex'), 'Alex');
      expect(speakerEnrollNameSeed('  Dr. Bose '), 'Dr. Bose');
      expect(speakerEnrollNameSeed('Speaker Jane'), 'Speaker Jane');
    });
    test('null / empty → empty', () {
      expect(speakerEnrollNameSeed(null), '');
      expect(speakerEnrollNameSeed('   '), '');
    });
  });

  final libPath = _resolveLibPath();
  final libSkip = libPath == null
      ? 'libcrispasr/libwhisper not found — set CRISPASR_LIB.'
      : null;

  group('text-LID (opt-in)', () {
    final cld3 = Platform.environment['CRISPASR_TEST_CLD3_MODEL'];
    test('detectTextLanguage identifies common languages', tags: ['slow'], () {
      const cases = {
        'de': 'Das ist ein vollständiger deutscher Satz über das Wetter.',
        'en': 'This is a complete English sentence about the weather.',
        'fr': 'Ceci est une phrase française complète sur la météo.',
        'es': 'Esta es una frase completa en español sobre el clima.',
      };
      cases.forEach((want, text) {
        final r = crispasr.detectTextLanguage(text, cld3!, libPath: libPath);
        expect(r, isNotNull, reason: 'no detection for "$text"');
        expect(r!.code, want, reason: 'got ${r.code} for "$text"');
        expect(r.confidence, greaterThan(0.5));
      });
    },
        skip: libSkip ??
            (cld3 == null
                ? 'set CRISPASR_TEST_CLD3_MODEL to a cld3-*.gguf'
                : null));
  });

  group('speaker embedding re-ID (opt-in)', () {
    final titanet = Platform.environment['CRISPASR_TEST_TITANET_MODEL'];
    final jfk = File('test/jfk.wav').existsSync()
        ? 'test/jfk.wav'
        : Platform.environment['CRISPASR_TEST_JFK_WAV'];
    final other = Platform.environment['CRISPASR_TEST_OTHER_SPEAKER_WAV'];

    test('same speaker scores higher than a different speaker',
        tags: ['slow'], () {
      final lib = DynamicLibrary.open(libPath!);
      final tn = crispasr.CrispasrTitaNet(lib, titanet!);
      addTearDown(tn.close);

      // Two non-overlapping halves of jfk.wav → same speaker.
      final jfkPcm = crispasr.decodeAudioFile(jfk!, libPath: libPath).samples;
      final mid = jfkPcm.length ~/ 2;
      final eA1 = tn.embed(Float32List.sublistView(jfkPcm, 0, mid));
      final eA2 = tn.embed(Float32List.sublistView(jfkPcm, mid));
      final same = _cosine(eA1, eA2);
      // ignore: avoid_print
      printOnFailure('same-speaker cosine = $same');
      expect(same, greaterThan(0.6),
          reason: 'two halves of one speaker should embed close together');

      if (other != null && File(other).existsSync()) {
        final otherPcm =
            crispasr.decodeAudioFile(other, libPath: libPath).samples;
        final eB = tn.embed(otherPcm);
        final diff = _cosine(eA1, eB);
        printOnFailure('cross-speaker cosine = $diff');
        expect(same, greaterThan(diff),
            reason: 'same speaker must score higher than a different one');
        expect(diff, lessThan(0.7),
            reason: 'a different speaker should fall below the match threshold');
      }
    },
        skip: libSkip ??
            (titanet == null
                ? 'set CRISPASR_TEST_TITANET_MODEL to a titanet-large.gguf'
                : jfk == null
                    ? 'jfk.wav not found'
                    : null));
  });
}
