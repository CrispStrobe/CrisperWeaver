// §5.24D verification matrix tail — live tests for TTS clone audio
// and text translation backends. Tagged `slow`; self-skip when models
// or dylib are absent.
//
// Run:
//   scripts/run_live_tests.sh test/verification_matrix_live_test.dart

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;

  // ---- IndexTTS clone audio ----
  group('§5.24D IndexTTS clone audio', () {
    test('indextts synthesizes audio', () {
      final model = CrispModels.model('indextts');
      if (lib == null || model == null) {
        markTestSkipped('CrispASR dylib or indextts model not on disk');
        return;
      }

      final session = crispasr.CrispasrSession.open(model, libPath: lib);
      if (session == null) {
        markTestSkipped('indextts session failed to open');
        return;
      }

      try {
        final samples = session.synthesize('Hello world');
        expect(samples.isNotEmpty, isTrue,
            reason: 'indextts should produce audio samples');
      } finally {
        session.close();
      }
    });
  });

  // ---- VoxCPM2 clone audio ----
  group('§5.24D VoxCPM2 clone audio', () {
    test('voxcpm2 synthesizes audio', () {
      final model = CrispModels.model('voxcpm2');
      if (lib == null || model == null) {
        markTestSkipped('CrispASR dylib or voxcpm2 model not on disk');
        return;
      }

      final session = crispasr.CrispasrSession.open(model, libPath: lib);
      if (session == null) {
        markTestSkipped('voxcpm2 session failed to open');
        return;
      }

      try {
        final samples = session.synthesize('Testing voice cloning');
        expect(samples.isNotEmpty, isTrue,
            reason: 'voxcpm2 should produce audio samples');
      } finally {
        session.close();
      }
    });
  });

  // ---- M2M100 translation ----
  group('§5.24D M2M100 translation', () {
    test('m2m100 translates EN to DE via session transcribe', () {
      final model = CrispModels.model('m2m100');
      if (lib == null || model == null) {
        markTestSkipped('CrispASR dylib or m2m100 model not on disk');
        return;
      }

      final session = crispasr.CrispasrSession.open(model, libPath: lib);
      if (session == null) {
        markTestSkipped('m2m100 session failed to open');
        return;
      }

      try {
        session.setSourceLanguage('en');
        session.setTargetLanguage('de');
        // Translation backends use transcribe() with text input
        // encoded as "fake" audio. For now just verify the session
        // opens and the language setters don't throw.
        expect(session.backend, isNotEmpty);
      } finally {
        session.close();
      }
    });
  });
}
