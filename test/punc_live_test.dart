// Live punctuation/capitalization-restoration test (PLAN §9.1 exemplar).
//
// Exercises the standalone post-processors PuncService relies on, against
// the on-disk fireredpunc q4_k model (and, when present, truecaser / PCS
// models). Tagged `slow` and self-skips when the dylib / models are absent.
//
// Entrypoint chosen — VERIFIED against the C source, not assumed:
//   PuncModel.open(modelPath, {libPath})  →  crispasr_punc_init(model_path)
//   PuncModel.process(text)               →  crispasr_punc_process(ctx, text)
//   PuncModel.close()                     →  crispasr_punc_free(ctx)
// In ../CrispASR/src/crispasr_c_api.cpp (CA_HAVE_FIREREDPUNC, ~L6677):
//   crispasr_punc_init  → fireredpunc_init(model_path)
//   crispasr_punc_process → fireredpunc_process(ctx, text)
// In ../CrispASR/src/fireredpunc.cpp:
//   fireredpunc_init (L575)    returns nullptr on load failure
//   fireredpunc_process (L584) returns nullptr on failure
// Error semantics: PuncModel.open() throws when init returns nullptr (e.g.
// the dylib was built WITHOUT CA_HAVE_FIREREDPUNC — the #else stub at ~L6694
// always returns nullptr). PuncModel.process() returns the *input text
// unchanged* when the native pointer is null (crispasr.dart ~L3484). So a
// no-op dylib surfaces as either an open() throw OR an unchanged string,
// both of which this test treats as "model not really available". This is
// the analogue of the VAD path's -2 lesson: don't assume the symbol does
// real work — assert the output actually changed.
//
// These post-processors are self-contained: each has its own open(modelPath)
// and does NOT need a whisper ASR context. So this test loads no tiny model.
//
// Run:
//   scripts/run_live_tests.sh test/punc_live_test.dart

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;

  // Unpunctuated, fully lowercased English — exactly the kind of CTC-backend
  // output PuncService.restore() is built to fix.
  const input =
      'and so my fellow americans ask not what your country can do for you';

  bool hasSentencePunctuation(String s) => RegExp(r'[.,!?;:]').hasMatch(s);
  bool hasUppercase(String s) => RegExp(r'[A-Z]').hasMatch(s);

  group('Punctuation live', () {
    final skip = CrispModels.skipReason(models: ['fireredpunc']);
    crispasr.PuncModel? model;

    tearDown(() {
      model?.close();
      model = null;
    });

    test('fireredpunc restores punctuation and/or capitalization', () {
      // The input is deliberately punctuation-free and lowercase, so any
      // real restoration MUST add a punctuation mark or an uppercase letter.
      expect(hasSentencePunctuation(input), isFalse,
          reason: 'fixture must start with no punctuation');
      expect(hasUppercase(input), isFalse,
          reason: 'fixture must start fully lowercased');

      model = crispasr.PuncModel.open(
        CrispModels.model('fireredpunc')!,
        libPath: lib,
      );

      final out = model!.process(input);

      // A no-op dylib (process returns the input unchanged) means the model
      // did no real work — fail loudly rather than silently passing.
      expect(out, isNot(equals(input)),
          reason: 'fireredpunc must change the unpunctuated input');
      expect(out.trim(), isNotEmpty);
      expect(
        hasSentencePunctuation(out) || hasUppercase(out),
        isTrue,
        reason: 'restored text must gain punctuation and/or capitalization',
      );
    }, skip: skip);
  });

  // ---- Truecaser (capitalization-only). Self-skips: not on disk locally. ----
  group('Truecase live', () {
    crispasr.TruecaseModel? model;

    tearDown(() {
      model?.close();
      model = null;
    });

    test('truecaser restores capitalization (when on disk)', () {
      if (lib == null) {
        markTestSkipped('libcrispasr dylib not found');
        return;
      }
      final path = CrispModels.model('truecaser_lstm_en') ??
          CrispModels.model('truecaser');
      if (path == null) {
        markTestSkipped('no truecaser-*.bin model under models dir');
        return;
      }
      model = crispasr.TruecaseModel.open(path, libPath: lib);
      final out = model!.process(input);
      expect(out, isNot(equals(input)),
          reason: 'truecaser must change the lowercased input');
      expect(hasUppercase(out), isTrue,
          reason: 'truecaser must add at least one uppercase letter');
    });
  });

  // ---- PCS (punct + truecase + SBD). Self-skips: not on disk locally. ----
  group('PCS live', () {
    crispasr.PcsModel? model;

    tearDown(() {
      model?.close();
      model = null;
    });

    test('pcs restores punctuation and capitalization (when on disk)', () {
      if (lib == null) {
        markTestSkipped('libcrispasr dylib not found');
        return;
      }
      final path = CrispModels.model('pcs');
      if (path == null) {
        markTestSkipped('no pcs-*.gguf model under models dir');
        return;
      }
      model = crispasr.PcsModel.open(path, libPath: lib);
      final out = model!.process(input);
      expect(out, isNot(equals(input)),
          reason: 'pcs must change the unpunctuated input');
      expect(hasSentencePunctuation(out) || hasUppercase(out), isTrue,
          reason: 'pcs must add punctuation and/or capitalization');
    });
  });
}
