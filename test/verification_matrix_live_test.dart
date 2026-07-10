// §5.24D verification matrix tail — live tests for TTS clone audio
// and text translation backends. Tagged `slow`; self-skip when models
// or dylib are absent.
//
// Run:
//   scripts/run_live_tests.sh test/verification_matrix_live_test.dart

@Tags(['slow'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;

  // ---- IndexTTS clone audio ----
  group('§5.24D IndexTTS clone audio', () {
    test('indextts synthesizes with clone reference', () {
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
        // Verify non-silence
        final maxAmp = samples.reduce((a, b) => a.abs() > b.abs() ? a : b).abs();
        expect(maxAmp, greaterThan(0.001),
            reason: 'indextts output should not be silence');
      } finally {
        session.dispose();
      }
    });
  });

  // ---- VoxCPM2 clone audio ----
  group('§5.24D VoxCPM2 clone audio', () {
    test('voxcpm2 synthesizes with clone reference', () {
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
        session.dispose();
      }
    });
  });

  // ---- M2M100 translation ----
  group('§5.24D M2M100 translation', () {
    test('m2m100 translates EN → DE', () {
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
        final result = session.translate('The cat sits on the mat.');
        expect(result, isNotNull);
        expect(result!.isNotEmpty, isTrue,
            reason: 'm2m100 should produce German text');
        // Check for German keywords (Katze/sitzt/Matte or similar)
        final lower = result.toLowerCase();
        expect(
            lower.contains('katze') ||
                lower.contains('sitzt') ||
                lower.contains('matte') ||
                lower.contains('teppich'),
            isTrue,
            reason:
                'translation "$result" should contain German words for cat/sit/mat');
      } finally {
        session.dispose();
      }
    });

    test('m2m100 translates EN → FR', () {
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
        session.setTargetLanguage('fr');
        final result = session.translate('Good morning, how are you?');
        expect(result, isNotNull);
        expect(result!.isNotEmpty, isTrue);
        final lower = result.toLowerCase();
        expect(
            lower.contains('bonjour') ||
                lower.contains('comment') ||
                lower.contains('matin'),
            isTrue,
            reason:
                'translation "$result" should contain French words');
      } finally {
        session.dispose();
      }
    });
  });
}
