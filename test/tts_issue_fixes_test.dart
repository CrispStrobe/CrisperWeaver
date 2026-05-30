// Regression guards for the May 2026 TTS bug-fix batch (GitHub issues
// #16 / #17 / #18). These are pure-Dart unit tests — they don't load
// libcrispasr or any model, so they run on every CI host.
//
//  * #16 — piper (and any backend the bundled dylib can't dispatch
//    through the unified session API) must surface a clean, named
//    "unsupported" status instead of crashing the process. We can't
//    exercise the native gate without a dylib, but we lock the status
//    contract the UI relies on.
//  * #17 — the Synthesize speaker picker auto-selects a preset speaker so
//    qwen3-tts CustomVoice / orpheus never synthesise silence for want of
//    a setSpeakerName(). The picker's *rendering* lives behind a
//    synchronous FFI session open (SynthesizeScreen._loadSpeakers), which
//    needs a real libcrispasr to exercise; but the *selection decision* is
//    pure and lives in SynthesizeScreen.resolveSpeakerSelection — that's
//    what we lock here. The CustomVoice model it targets is also confirmed
//    catalogued (in the #18 group below).
//  * #18 — qwen3-tts CustomVoice and chatterbox turbo T3 must live in the
//    static catalogue so they appear in the Synthesize picker on a fresh
//    launch, without first triggering Model Management's HF deep-refresh.
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/screens/synthesize_screen.dart';
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

  group('#17 — preset-speaker auto-selection', () {
    String? resolve(List<String> speakers, String? current) =>
        SynthesizeScreen.resolveSpeakerSelection(speakers, current);

    test('empty speaker list clears any selection (no preset contract)', () {
      expect(resolve(const [], null), isNull);
      expect(resolve(const [], 'Ethan'), isNull);
    });

    test('auto-picks the first speaker when none is selected — the #17 fix',
        () {
      // This is the core of #17: CustomVoice synthesised silence because
      // _selectedSpeaker stayed null and no setSpeakerName() was issued.
      expect(resolve(const ['Ethan', 'Chelsie', 'Aiden'], null), 'Ethan');
    });

    test('preserves a still-valid prior choice across re-enumeration', () {
      expect(resolve(const ['Ethan', 'Chelsie'], 'Chelsie'), 'Chelsie');
    });

    test('falls back to the first when the prior choice is gone', () {
      // e.g. user switched from one speaker-capable model to another whose
      // baked speaker set doesn't include the previously-picked name.
      expect(resolve(const ['Ethan', 'Chelsie'], 'Ryan'), 'Ethan');
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
