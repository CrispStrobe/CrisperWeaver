// Supertonic-3 (CrispASR 0.8.33+): preset voices go through setVoice, not
// setSpeakerName, and the spoken language comes from the session's target
// language rather than the text. Both are app-side routing decisions, so
// the pure parts are tested always and the routing is proven end to end
// against a real model when one is supplied.
//
// Opt-in live check:
//   CRISPASR_LIB=/path/libcrispasr.so \
//   CRISPASR_TEST_SUPERTONIC_MODEL=/path/supertonic3-f16.gguf \
//   flutter test --tags slow test/supertonic_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:crisper_weaver/screens/synthesize_screen.dart';
import 'package:crisper_weaver/services/model_catalog.dart';
import 'package:crisper_weaver/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveOutputLanguage', () {
    const langs = ModelCatalog.langsSupertonic;

    String? resolve(String? backend, String? chosen, String ui) =>
        SynthesizeScreen.resolveOutputLanguage(
            backend: backend, languages: langs, chosen: chosen, uiLanguage: ui);

    test('backends that infer their language get none', () {
      expect(resolve('kokoro', 'de', 'de'), isNull);
      expect(resolve(null, 'de', 'de'), isNull);
    });

    test('keeps a supported pick, else UI language, else first', () {
      expect(resolve('supertonic', 'fr', 'de'), 'fr');
      expect(resolve('supertonic', null, 'de'), 'de');
      // zh is not a Supertonic language, as a pick or as the UI locale.
      expect(resolve('supertonic', 'zh', 'zh'), 'en');
    });

    test('an empty language list yields none rather than a guess', () {
      expect(
          SynthesizeScreen.resolveOutputLanguage(
              backend: 'supertonic',
              languages: const [],
              chosen: 'de',
              uiLanguage: 'de'),
          isNull);
    });
  });

  test('catalogue entry matches the routing', () {
    final def = ModelCatalog.crispasrBackendModels['supertonic3-f16']!;
    expect(def.backend, 'supertonic');
    expect(def.kind, ModelKind.tts);
    expect(def.languages, ModelCatalog.langsSupertonic);
    expect(def.isNonCommercial, isFalse);
    expect(TtsService.outputLanguageBackends, contains(def.backend));
    // M1 first: the engine's default, so auto-pick changes nothing.
    expect(TtsService.supertonicVoices.first, 'M1');
    expect(TtsService.supertonicVoices, hasLength(10));
  });

  final libPath = Platform.environment['CRISPASR_LIB'];
  final model = Platform.environment['CRISPASR_TEST_SUPERTONIC_MODEL'];
  final skip = (libPath == null || model == null)
      ? 'set CRISPASR_LIB + CRISPASR_TEST_SUPERTONIC_MODEL'
      : null;

  group('Supertonic-3 end to end (opt-in)', () {
    Float32List synth(String voice, String lang, String text) {
      final s = crispasr.CrispasrSession.open(model!,
          backend: 'supertonic', libPath: libPath);
      try {
        TtsService.applyPresetSpeaker(s, s.backend, voice);
        s.setTargetLanguage(lang);
        s.setTtsSeed(42);
        return s.synthesize(text);
      } finally {
        s.close();
      }
    }

    bool same(Float32List a, Float32List b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    test('seeded output is reproducible (the control)', tags: ['slow'], () {
      final a = synth('M1', 'en', 'Good morning.');
      final b = synth('M1', 'en', 'Good morning.');
      expect(a.length, greaterThan(0));
      expect(same(a, b), isTrue);
    }, skip: skip);

    test('a preset voice reaches the engine', tags: ['slow'], () {
      final m1 = synth('M1', 'en', 'Good morning.');
      final f2 = synth('F2', 'en', 'Good morning.');
      expect(same(m1, f2), isFalse);
    }, skip: skip);

    test('the output language reaches the engine', tags: ['slow'], () {
      final en = synth('M1', 'en', 'Guten Morgen.');
      final de = synth('M1', 'de', 'Guten Morgen.');
      expect(same(en, de), isFalse);
    }, skip: skip);

    test('an unknown preset is refused, not ignored', tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(model!,
          backend: 'supertonic', libPath: libPath);
      addTearDown(s.close);
      expect(() => TtsService.applyPresetSpeaker(s, s.backend, 'Z9'),
          throwsA(anything));
    }, skip: skip);
  });
}
