// Live text-translation test (PLAN §9.1 exemplar / translation path).
//
// Exercises the exact call the app's TextTranslationService makes:
// CrispasrSession.open(<translation GGUF>) → session.translateText(
//   text, srcLang, tgtLang). This mirrors
// lib/services/text_translation_service.dart, which opens a session
// directly on the translation model and calls translateText — for
// translation the loaded model *is* the translation GGUF, so opening
// the session on madlad/m2m100 (rather than an auxiliary ASR model) is
// the correct, app-faithful shape. The session is closed in tearDown.
//
// Backend / return semantics (verified against CrispASR source,
// src/crispasr_c_api.cpp:6333 `crispasr_session_translate_text`):
//   - madlad (T5 path): the C side prepends a `<2{tgtLang}>` tag
//     (e.g. `<2de>`) and IGNORES srcLang — the encoder is language-
//     agnostic. So tgtLang must be the ISO 639-1 code ('de', 'fr').
//   - m2m100: both srcLang + tgtLang are looked up in the GGUF's
//     `m2m100.lang_codes` table, which is ISO 639-1 ('en'/'de'/'fr').
//   Both backends therefore take plain 'en'/'de'/'fr' — the same codes
//   TextTranslationService.supportedLanguages exposes. NO `eng_Latn`-
//   style NLLB codes here.
//   Return: the C function returns nullptr on failure / when no
//   translation-capable backend is loaded (the binding maps that to a
//   Dart `null`). So a non-null, non-empty result that DIFFERS from the
//   input is the real success signal — we assert output != input so a
//   silent no-op (echo / empty) fails loudly.
//
// Prefers madlad (q4_k, owner-preferred, already on disk); falls back
// to m2m100 (q8_0, ~502 MB) only when madlad is absent. Tagged `slow`
// and self-skips when neither model is on disk.
//
// RUNTIME RISK: madlad400-3b-mt-q4_k is ~1.9 GB — opening the session
// loads that into memory and the decode is a real beam search. This is
// a heavy, slow test; the owner runs live validation serially.
//
// Run:
//   scripts/run_live_tests.sh test/translation_live_test.dart

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;

  // Prefer madlad (q4_k); fall back to m2m100 only if madlad is absent.
  final madlad = CrispModels.model('madlad');
  final m2m100 = CrispModels.model('m2m100');
  final modelPath = madlad ?? m2m100;
  final modelLabel = madlad != null ? 'madlad (q4_k)' : 'm2m100 (q8_0)';

  final skip = CrispModels.skipReason() ??
      (modelPath == null
          ? 'no translation model on disk under ${CrispModels.modelsDir}: '
              'need madlad400-3b-mt-q4_k.gguf or m2m100-418m-q8_0.gguf '
              '(set CRISPASR_MODELS_DIR or CRISPASR_TEST_MADLAD_MODEL).'
          : null);

  group('Translation live', () {
    crispasr.CrispasrSession? session;

    setUp(() {
      if (skip != null) return;
      // Open the session directly on the translation GGUF — the model
      // IS the session's job here (translation), so this is the
      // app-faithful shape, not the VAD-class mistake of loading an
      // auxiliary model as the session's primary context.
      session = crispasr.CrispasrSession.open(modelPath!, libPath: lib);
    });

    tearDown(() {
      session?.close();
      session = null;
    });

    test('translates EN → DE ($modelLabel)', () {
      const input = 'The weather is nice today.';
      final out = session!.translateText(input, 'en', 'de');

      expect(out, isNotNull,
          reason: 'translateText returned null — the loaded model is not '
              'translation-capable, or the C side rejected the request.');
      final result = out!.trim();
      expect(result, isNotEmpty, reason: 'empty translation is a no-op');
      expect(result, isNot(equalsIgnoringCase(input)),
          reason: 'output equals the English input — translation no-op');

      // Lenient German signal: accept on any of these tokens, but the
      // hard gate above (non-empty, != input) is what really guards a
      // no-op. We do NOT pin an exact translation string.
      final lc = result.toLowerCase();
      final hasGermanSignal =
          ['wetter', 'heute', 'schön', 'schon'].any(lc.contains);
      // Soft expectation: log-only via reason; the assertion stays
      // lenient (non-empty + differs from input) so a valid but
      // unexpected paraphrase doesn't fail the live run.
      expect(result.isNotEmpty && lc != input.toLowerCase(), isTrue,
          reason: 'EN→DE produced "$result" (german-signal=$hasGermanSignal)');
    }, skip: skip);

    test('translates EN → FR ($modelLabel)', () {
      const input = 'The weather is nice today.';
      final out = session!.translateText(input, 'en', 'fr');

      expect(out, isNotNull, reason: 'translateText returned null for FR');
      final result = out!.trim();
      expect(result, isNotEmpty, reason: 'empty FR translation is a no-op');
      expect(result, isNot(equalsIgnoringCase(input)),
          reason: 'output equals the English input — FR translation no-op');
    }, skip: skip);
  });
}
