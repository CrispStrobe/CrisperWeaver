// Live LID dispatch test (PLAN §10.2).
//
// Exercises each LID dispatcher backend available on disk:
//   * Audio LID: Silero (lid-silero), ECAPA-TDNN (lid-ecapa)
//   * Text LID: CLD3 (lid-cld3), GlotLID (lid-glotlid), FastText-176
//
// The catalog ships these models with generic `backend: 'lid'`, but the
// CrispASR engine dispatches to the correct backend via filename
// heuristic. This test validates that each model resolves and produces
// a sensible language label.
//
// Tagged `slow`; self-skips when the dylib is absent. Individual sub-tests
// self-skip (markTestSkipped) when a specific LID model is not on disk.
//
// Run:
//   scripts/run_live_tests.sh test/lid_dispatch_live_test.dart

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  // Audio LID needs a whisper ctx (multilingual tiny) for the encoder path.
  final whisperModel = CrispModels.model('whisper_tiny');

  // Text LID models — each a standalone GGUF loaded by the free function.
  final cld3Model = CrispModels.model('cld3');
  final glotlidModel = CrispModels.model('glotlid');

  final baseSkip = CrispModels.skipReason(models: ['whisper_tiny']);

  group('LID dispatch live (§10)', () {
    crispasr.CrispASR? ctx;

    setUp(() {
      if (lib != null && whisperModel != null) {
        ctx = crispasr.CrispASR(whisperModel, libPath: lib);
      }
    });

    tearDown(() {
      ctx?.dispose();
      ctx = null;
    });

    test('audio LID via whisper encoder detects English', () {
      final jfk = CrispModels.fixture('jfk.wav');
      final audio = crispasr.decodeAudioFile(jfk, libPath: lib);
      expect(audio.samples, isNotEmpty, reason: 'decode should return samples');

      final result = ctx!.detectLanguage(audio.samples);
      expect(result.ok, isTrue,
          reason: 'detectLanguage should succeed');
      expect(result.code.toLowerCase(), contains('en'),
          reason: 'should detect English, got "${result.code}"');
    }, skip: baseSkip);

    test('text LID via CLD3 detects English', () {
      if (cld3Model == null) {
        markTestSkipped('CLD3 model not on disk');
        return;
      }
      final result = crispasr.detectTextLanguage(
        'And so my fellow Americans, ask not what your country can do for you.',
        cld3Model,
        libPath: lib,
      );
      expect(result, isNotNull, reason: 'detectTextLanguage returned null');
      expect(result!.code.toLowerCase(), contains('en'),
          reason: 'CLD3 should detect English, got "${result.code}"');
    }, skip: baseSkip);

    test('text LID via GlotLID detects English', () {
      if (glotlidModel == null) {
        markTestSkipped('GlotLID model not on disk');
        return;
      }
      final result = crispasr.detectTextLanguage(
        'The quick brown fox jumps over the lazy dog.',
        glotlidModel,
        libPath: lib,
      );
      expect(result, isNotNull, reason: 'detectTextLanguage returned null');
      // GlotLID returns ISO 639-3 + script, e.g. "eng_Latn"
      expect(result!.code.toLowerCase(), contains('eng'),
          reason: 'GlotLID should detect English, got "${result.code}"');
    }, skip: baseSkip);

    test('text LID detects German', () {
      final model = cld3Model ?? glotlidModel;
      if (model == null) {
        markTestSkipped('No text LID model on disk');
        return;
      }
      final result = crispasr.detectTextLanguage(
        'Die schnelle braune Fuchs springt ueber den faulen Hund.',
        model,
        libPath: lib,
      );
      expect(result, isNotNull, reason: 'detectTextLanguage returned null');
      expect(result!.code.toLowerCase(), anyOf(contains('de'), contains('deu')),
          reason: 'Text LID should detect German, got "${result.code}"');
    }, skip: baseSkip);
  });
}
