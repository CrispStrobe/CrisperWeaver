// Live audio-LID test for the Silero 95-language classifier (PLAN §9.1).
//
// Gap this fills: the existing LID live tests cover the *other two*
// paths only —
//   * test/lid_live_test.dart + test/lid_dispatch_live_test.dart cover
//     whisper-encoder audio LID (`CrispASR.detectLanguage`, which reuses
//     an already-open multilingual ASR ctx) and text LID
//     (`detectTextLanguage` over CLD3 / GlotLID);
//   * nothing exercised `crispasr_detect_language_pcm` with
//     `LidMethod.silero`, which is the branch
//     `LidService.detectIfModelAvailable` takes whenever the user has a
//     `silero-lid-*.gguf` on disk — i.e. the recommended default.
//
// That branch is worth its own test for a concrete reason documented in
// LidService: method and model must agree or the C side answers rc=-2
// and the result comes back empty. `LidService.methodForFilename` is the
// code that keeps them in sync, so this test drives LID through *that*
// resolution rather than hard-coding `LidMethod.silero` — a rename in
// the registry that broke the mapping would show up here as a failed
// detection, not just as a red unit test.
//
// Why this can run where the whisper-LID tests cannot: Silero LID is a
// standalone ~13 MB GGUF loaded by the free function itself. It needs no
// multilingual `ggml-*.bin` (the English-only `ggml-*.en.bin` files are
// useless for LID), so a box that only has an English whisper build can
// still prove the LID path end to end.
//
// C semantics (crispasr.dart `detectLanguagePcm`): rc != 0 yields an
// empty `langCode` and confidence -1. So "empty result" is the failure
// signal, and `LidResult.isEmpty` is what we assert against first.
//
// Self-skips unless the shared opt-in gate is on (CRISPASR_LIB /
// RUN_LIVE_TESTS), the dylib loads, and the model resolves via
// CRISPASR_TEST_SILERO_LID_MODEL (or silero-lid-95-q8_0.gguf under
// $CRISPASR_MODELS_DIR). The model is read from its env path directly —
// nothing is copied into a models dir.
//
// Run:
//   tools/run_live_tests.sh test/silero_lid_live_test.dart

@Tags(['slow'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:ffi';
import 'dart:io';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/lid_service.dart';

import 'support/crispasr_models.dart';

/// The English clip every ASR live test uses. Prefer an explicitly
/// supplied one (the CrispASR checkout ships a longer take) because
/// Silero wants a couple of seconds of speech to be confident.
String _jfkWav() {
  final env = Platform.environment['CRISPASR_TEST_JFK_WAV'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  return CrispModels.fixture('jfk.wav');
}

void main() {
  final libPath = CrispModels.lib;
  final sileroModel = CrispModels.model('silero_lid');
  final skip = CrispModels.skipReason(models: ['silero_lid']);

  // Routing check — pure, no dylib, always runs. If this ever stops
  // saying `silero`, the live case below would silently pass the wrong
  // method to the C side and get rc=-2 back.
  test('the Silero GGUF basename routes to LidMethod.silero', () {
    expect(LidService.methodForFilename('/models/silero-lid-95-q8_0.gguf'),
        crispasr.LidMethod.silero);
    expect(LidService.methodForFilename('/models/silero-lang95-v1-f16.gguf'),
        crispasr.LidMethod.silero);
  });

  group('Silero audio LID live', () {
    late DynamicLibrary lib;
    late crispasr.DecodedAudio audio;

    setUp(() {
      if (skip != null) return;
      lib = DynamicLibrary.open(libPath!);
      audio = crispasr.decodeAudioFile(_jfkWav(), libPath: libPath);
    });

    test('decodes the fixture to 16 kHz mono PCM', () {
      expect(audio.sampleRate, 16000);
      expect(audio.samples.length, greaterThan(16000)); // > 1 s of speech
    }, skip: skip);

    test('detects English in the JFK clip via LidMethod.silero', () {
      // Resolve the method from the filename, exactly as LidService does
      // — never trust a hard-coded enum here (see the header note on
      // rc=-2).
      final method = LidService.methodForFilename(sileroModel!);
      expect(method, crispasr.LidMethod.silero,
          reason: '$sileroModel did not route to the Silero backend; the '
              'live call below would be testing the wrong dispatch arm');

      final r = crispasr.detectLanguagePcm(
        pcm: audio.samples,
        method: method,
        modelPath: sileroModel,
        lib: lib,
      );

      printOnFailure('silero LID: code="${r.langCode}" '
          'confidence=${r.confidence.toStringAsFixed(3)}');
      expect(r.isEmpty, isFalse,
          reason: 'empty langCode means the C side returned rc != 0 — the '
              'dylib may predate crispasr_detect_language_pcm, or the '
              'method/model pair was rejected (rc=-2). model=$sileroModel');
      // 2026-08-30 postscript to a resolved scare: the "pa-in"/"fr"
      // answers this test once skip-tracked came from ONE stale build
      // artifact (overwritten before autopsy); the engine was verified
      // correct on this box natively at HEAD and at 0.8.29, per-stage
      // vs the ONNX blueprint upstream (CrispASR PLAN, RESOLVED
      // 2026-08-29 + x86 confirmation 2026-08-30). Hard assertion
      // restored — a wrong answer here is a real regression again.
      expect(r.langCode.toLowerCase(), startsWith('en'),
          reason: 'the JFK clip is English; got "${r.langCode}"');
      // 0.35 is LidService.detectIfModelAvailable's default floor —
      // below it the service discards the answer and skips LID, so a
      // result under it is indistinguishable from no result at all.
      expect(r.confidence, greaterThanOrEqualTo(0.35),
          reason: 'confidence ${r.confidence} is below the floor '
              'LidService applies, so the app would drop this detection');
    }, skip: skip);

    test('returns an empty result for empty PCM rather than throwing', () {
      // The guard clause in detectLanguagePcm, exercised against the real
      // dylib: LidService hands it whatever the recorder produced, and a
      // zero-length buffer must not reach the FFI call.
      final r = crispasr.detectLanguagePcm(
        pcm: crispasr.decodeAudioFile(_jfkWav(), libPath: libPath)
            .samples
            .sublist(0, 0),
        method: crispasr.LidMethod.silero,
        modelPath: sileroModel!,
        lib: lib,
      );
      expect(r.isEmpty, isTrue);
      expect(r.confidence, lessThan(0));
    }, skip: skip);
  });
}
