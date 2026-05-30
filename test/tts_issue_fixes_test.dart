// Regression guards for the May 2026 TTS bug-fix batch (GitHub issues
// #16 / #17 / #18). These are pure-Dart unit tests — they don't load
// libcrispasr or any model, so they run on every CI host.
//
//  * #16 — piper (and any backend the bundled dylib can't dispatch
//    through the unified session API) must surface a clean, named
//    "unsupported" status instead of crashing the process. We can't
//    exercise the native gate without a dylib, but we lock the status
//    contract the UI relies on.
//  * #18 — qwen3-tts CustomVoice and chatterbox turbo T3 must live in the
//    static catalogue so they appear in the Synthesize picker on a fresh
//    launch, without first triggering Model Management's HF deep-refresh.
//    (#17's speaker picker is exercised at the widget layer; here we just
//    make sure the CustomVoice model it targets is actually catalogued.)
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/tts_service.dart';

void main() {
  group('#16 — unsupported-backend status', () {
    test('TtsLoadStatus.unsupported carries the backend and is not ready', () {
      final s = TtsLoadStatus.unsupported('piper');
      expect(s.ready, isFalse);
      expect(s.unsupportedBackend, 'piper');
      // Must not masquerade as a missing-companion case — the UI branches
      // on these to choose which message to show.
      expect(s.missingModelName, isNull);
      expect(s.missingVoiceName, isNull);
      expect(s.missingCodecName, isNull);
      expect(s.errorMessage, isNull);
    });
  });

  group('#18 — TTS variants are statically catalogued', () {
    const expected = {
      'qwen3-tts-12hz-0.6b-customvoice-q8_0': 'qwen3-tts',
      'chatterbox-turbo-t3-q8_0': 'chatterbox',
    };

    test('each model is present in the hardcoded catalogue as a TTS entry',
        () {
      for (final entry in expected.entries) {
        final def = ModelService.crispasrBackendModels[entry.key];
        expect(def, isNotNull,
            reason: '${entry.key} missing from crispasrBackendModels — it '
                'would only appear after a Model-Management deep refresh '
                '(issue #18).');
        expect(def!.backend, entry.value);
        expect(def.kind, ModelKind.tts);
        expect(def.fileName, endsWith('.gguf'));
        expect(def.url, contains('huggingface.co'));
        expect(def.companions, isNotEmpty,
            reason: '${entry.key} needs a vocoder/codec companion');
      }
    });

    test('their companions resolve to real catalogue entries', () {
      for (final key in expected.keys) {
        final def = ModelService.crispasrBackendModels[key]!;
        for (final companion in def.companions) {
          expect(ModelService.crispasrBackendModels.containsKey(companion),
              isTrue,
              reason: '$key → "$companion" does not resolve');
        }
      }
    });
  });
}
