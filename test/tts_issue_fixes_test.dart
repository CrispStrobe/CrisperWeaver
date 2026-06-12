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

    test('single-speaker list always returns that speaker', () {
      expect(resolve(const ['Solo'], null), 'Solo');
      expect(resolve(const ['Solo'], 'Solo'), 'Solo');
      expect(resolve(const ['Solo'], 'Other'), 'Solo');
    });

    test('qwen3-tts CustomVoice has a companion codec declared', () {
      // Without the codec, the session can't open and speakers can't be
      // enumerated. Verify the catalog wires the dependency.
      final def = ModelService
          .crispasrBackendModels['qwen3-tts-12hz-0.6b-customvoice-q8_0'];
      expect(def, isNotNull);
      expect(def!.companions, isNotEmpty,
          reason: 'CustomVoice needs a codec companion');
      // The companion must itself be catalogued.
      for (final c in def.companions) {
        expect(ModelService.crispasrBackendModels.containsKey(c), isTrue,
            reason: 'companion "$c" must resolve in the catalog');
      }
    });
  });

  group('#16 — piper models are in catalog with correct backend', () {
    test('the model from the crash report is catalogued as piper', () {
      // Issue #16 specifically mentions "Piper en_US LibriTTS-R (medium)".
      final def =
          ModelService.crispasrBackendModels['piper-en-libritts-r-medium'];
      expect(def, isNotNull,
          reason: 'the exact model from the #16 crash report must be '
              'in the static catalog');
      expect(def!.backend, 'piper');
      expect(def.kind, ModelKind.tts);
    });

    test('all piper entries have backend=piper and kind=tts', () {
      final piperEntries = ModelService.crispasrBackendModels.entries
          .where((e) => e.value.backend == 'piper')
          .toList();
      expect(piperEntries, isNotEmpty,
          reason: 'at least one piper voice should be in the catalog');
      for (final e in piperEntries) {
        expect(e.value.kind, ModelKind.tts,
            reason: '${e.key} should be kind=tts');
        expect(e.value.companions, isEmpty,
            reason: 'piper GGUFs are self-contained, no companions');
      }
    });
  });

  group('#18 — TTS variants are statically catalogued', () {
    // Issue #18 lists three models that were missing on fresh launch:
    //   * Chatterbox turbo T3
    //   * Qwen3-TTS 0.6B base
    //   * Qwen3-TTS 0.6B custom-voice
    const expected = {
      'qwen3-tts-12hz-0.6b-base-q8_0': 'qwen3-tts',
      'qwen3-tts-12hz-0.6b-customvoice-q8_0': 'qwen3-tts',
      'qwen3-tts-12hz-1.7b-customvoice-q8_0': 'qwen3-tts',
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

  // ================================================================
  // June 2026 batch — issues #20 / #21 / #22 / #23
  // ================================================================

  group('#20 — pocket-tts catalog + Mimi CPU scheduler', () {
    test('pocket-tts f16 is catalogued with backend=pocket-tts', () {
      final def =
          ModelService.crispasrBackendModels['pocket-tts-english-f16'];
      expect(def, isNotNull);
      expect(def!.backend, 'pocket-tts');
      expect(def.kind, ModelKind.tts);
    });

    test('pocket-tts is self-contained (Mimi codec built into GGUF)', () {
      // The noise bug was caused by ggml_conv_transpose_1d on GPU, NOT
      // a missing codec. Verify no external companion is required.
      final def =
          ModelService.crispasrBackendModels['pocket-tts-english-f16'];
      expect(def, isNotNull);
      expect(def!.companions, isEmpty);
    });

    test('pocket-tts BackendRepo exists for HF probe', () {
      final repo = ModelService.backendRepos['pocket-tts'];
      expect(repo, isNotNull);
      expect(repo!.backend, 'pocket-tts');
    });
  });

  group('#21 — piper crash: ggml_conv_transpose_1d GPU corruption', () {
    test('TtsLoadStatus.unsupported carries piper backend', () {
      // The Dart-side gate and C-side hifigan_sched both protect piper.
      final s = TtsLoadStatus.unsupported('piper');
      expect(s.ready, isFalse);
      expect(s.unsupportedBackend, 'piper');
      expect(s.missingModelName, isNull);
    });

    test('all piper entries have backend=piper', () {
      final piperModels = ModelService.crispasrBackendModels.entries
          .where((e) => e.value.backend == 'piper')
          .toList();
      expect(piperModels, isNotEmpty);
      for (final e in piperModels) {
        expect(e.value.kind, ModelKind.tts);
      }
    });
  });

  group('#22 — qwen3-tts diagnostic hint for empty audio', () {
    test('qwen3-tts base has codec companion wired', () {
      final def =
          ModelService.crispasrBackendModels['qwen3-tts-12hz-0.6b-base-q8_0'];
      expect(def, isNotNull);
      expect(def!.backend, 'qwen3-tts');
      expect(def.companions, isNotEmpty,
          reason: 'codec companion needed for synthesis');
      for (final c in def.companions) {
        expect(ModelService.crispasrBackendModels.containsKey(c), isTrue);
      }
    });

    test('qwen3-tts Base models are tagged requiresVoice', () {
      // Base models need a voice pack or WAV clone — without one the
      // C-side returns "qwen3-tts Base requires a voice" and the
      // Synthesize button should be disabled.
      // Only q8_0 variants live in crispasrBackendModels; q4_k/f16 are
      // in baked_models_catalog (discovered at runtime via HF probe).
      const baseKeys = [
        'qwen3-tts-12hz-0.6b-base-q8_0',
        'qwen3-tts-12hz-1.7b-base-q8_0',
      ];
      for (final key in baseKeys) {
        final def = ModelService.crispasrBackendModels[key];
        expect(def, isNotNull, reason: '$key missing from catalog');
        expect(def!.requiresVoice, isTrue,
            reason: '$key must be tagged requiresVoice');
      }
    });

    test('qwen3-tts CustomVoice models are NOT tagged requiresVoice', () {
      final def = ModelService
          .crispasrBackendModels['qwen3-tts-12hz-0.6b-customvoice-q8_0'];
      expect(def, isNotNull);
      expect(def!.requiresVoice, isFalse,
          reason: 'CustomVoice has baked speakers, no external voice needed');
    });
  });

  group('#23 — orpheus ANR: background-isolate synthesis', () {
    test('orpheus 3B has codec companion for isolate replay', () {
      final def =
          ModelService.crispasrBackendModels['orpheus-3b-base-q8_0'];
      expect(def, isNotNull);
      expect(def!.backend, 'orpheus');
      expect(def.companions, contains('snac-24khz'));
    });

    test('SNAC codec catalogued', () {
      final codec = ModelService.crispasrBackendModels['snac-24khz'];
      expect(codec, isNotNull);
      expect(codec!.kind, ModelKind.codec);
      expect(codec.backend, 'orpheus');
    });
  });

  // ---- §5.26.3 S2S mode ----

  group('§5.26.3 — Speech-to-Speech backend support', () {
    test('S2S-capable backends are catalogued', () {
      // Every S2S backend must have at least one catalogue entry
      // so the Synthesize screen can show it.
      const allModels = ModelService.crispasrBackendModels;
      const allRepos = ModelService.backendRepos;
      for (final backend in ['lfm2-audio', 'mini-omni2']) {
        final hasModel =
            allModels.values.any((m) => m.backend == backend);
        final hasRepo =
            allRepos.values.any((r) => r.backend == backend);
        expect(hasModel || hasRepo, isTrue,
            reason: '$backend must be catalogued for S2S');
      }
    });

    test('mini-omni2 has SNAC codec companion', () {
      final def = ModelService.crispasrBackendModels['mini-omni2-q4_k'];
      expect(def, isNotNull);
      expect(def!.companions, contains('snac-24khz'));
    });

    test('lfm2-audio catalogued with ASR kind (not TTS)', () {
      final def =
          ModelService.crispasrBackendModels['lfm2-audio-1.5b-q5_k'];
      expect(def, isNotNull);
      // LFM2 is primarily ASR; TTS/S2S are secondary capabilities.
      expect(def!.kind, ModelKind.asr);
    });
  });
}
