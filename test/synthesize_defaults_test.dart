// #35 — "it downloads 1 voice and plays another".
//
// Onboarding's synthesize starter fetches a TTS model *and* the companions
// its catalogue row lists (kokoro-82m-q8_0 + kokoro-voice-af_heart), but
// nothing was persisted for TTS: the Synthesize screen then auto-selected
// `ttsDownloaded.first` (catalogue order) and the first downloaded voicepack
// for that backend — which, with ~30 kokoro voicepacks in the catalogue, is
// not the one that was downloaded.
//
// These are the pure halves of the fix: what onboarding records
// (`OnboardingScreen.persistTtsDefaults`) and what the screen picks with it
// (`SynthesizeScreen.pickDefaultTtsModel` / `pickDefaultTtsVoice` /
// `pickDefaultTtsCodec`). No widget pumping, no FFI, no downloads.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/screens/onboarding_screen.dart';
import 'package:crisper_weaver/screens/synthesize_screen.dart';
import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';

ModelInfo _info(
  String name, {
  required ModelKind kind,
  String backend = 'kokoro',
  bool downloaded = true,
}) =>
    ModelInfo(
      name: name,
      displayName: name,
      size: '1 MB',
      sizeBytes: 1024 * 1024,
      isDownloaded: downloaded,
      description: name,
      modelType: ModelType.whisperCpp,
      backend: backend,
      kind: kind,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SynthesizeScreen.pickDefaultTtsModel', () {
    final kokoro = _info('kokoro-82m-q8_0', kind: ModelKind.tts);
    final vibe = _info('vibevoice-realtime-0.5b-tts-f16',
        kind: ModelKind.tts, backend: 'vibevoice-tts');

    test('nothing downloaded → null', () {
      expect(SynthesizeScreen.pickDefaultTtsModel(const [], 'kokoro-82m-q8_0'),
          isNull);
    });

    test('the preferred model wins when it is downloaded', () {
      // Catalogue order puts vibevoice first; onboarding downloaded kokoro.
      expect(
        SynthesizeScreen.pickDefaultTtsModel([vibe, kokoro], 'kokoro-82m-q8_0'),
        'kokoro-82m-q8_0',
      );
    });

    test('falls back to the first downloaded model when the preferred one is '
        'not on disk', () {
      expect(
        SynthesizeScreen.pickDefaultTtsModel([vibe, kokoro], 'qwen3-tts-12hz'),
        vibe.name,
      );
    });

    test('no preference → first downloaded (historical behaviour)', () {
      expect(SynthesizeScreen.pickDefaultTtsModel([vibe, kokoro], ''),
          vibe.name);
    });

    test('ignores rows that are catalogued but not downloaded', () {
      final notOnDisk =
          _info('kokoro-82m-q8_0', kind: ModelKind.tts, downloaded: false);
      expect(
        SynthesizeScreen.pickDefaultTtsModel(
            [notOnDisk, vibe], 'kokoro-82m-q8_0'),
        vibe.name,
      );
      expect(SynthesizeScreen.pickDefaultTtsModel([notOnDisk], ''), isNull);
    });

    test('ignores non-TTS rows', () {
      final voice = _info('kokoro-voice-af_heart', kind: ModelKind.voice);
      expect(SynthesizeScreen.pickDefaultTtsModel([voice], ''), isNull);
    });
  });

  group('SynthesizeScreen.pickDefaultTtsVoice', () {
    // Deliberately ordered so "first downloaded" is the *wrong* answer,
    // exactly as the real catalogue orders the kokoro voicepacks.
    final bella = _info('kokoro-voice-af_bella', kind: ModelKind.voice);
    final heart = _info('kokoro-voice-af_heart', kind: ModelKind.voice);
    final germanEva = _info('kokoro-voice-df_eva', kind: ModelKind.voice);
    final otherBackend = _info('vibevoice-voice-en-Emma_woman',
        kind: ModelKind.voice, backend: 'vibevoice-tts');

    test('the voice onboarding recorded wins', () {
      expect(
        SynthesizeScreen.pickDefaultTtsVoice(
          models: [bella, heart, germanEva, otherBackend],
          backend: 'kokoro',
          companions: const ['kokoro-voice-df_eva'],
          preferred: 'kokoro-voice-af_heart',
        ),
        'kokoro-voice-af_heart',
      );
    });

    test("falls through to the model's own companion when the preferred voice "
        'is not downloaded', () {
      final heartMissing = _info('kokoro-voice-af_heart',
          kind: ModelKind.voice, downloaded: false);
      expect(
        SynthesizeScreen.pickDefaultTtsVoice(
          models: [bella, heartMissing, germanEva],
          backend: 'kokoro',
          companions: const ['kokoro-voice-df_eva'],
          preferred: 'kokoro-voice-af_heart',
        ),
        'kokoro-voice-df_eva',
      );
    });

    test('a preferred voice from another backend is not used', () {
      expect(
        SynthesizeScreen.pickDefaultTtsVoice(
          models: [bella, heart, otherBackend],
          backend: 'vibevoice-tts',
          companions: const [],
          preferred: 'kokoro-voice-af_heart',
        ),
        otherBackend.name,
      );
    });

    test('companions are honoured in catalogue-row order', () {
      expect(
        SynthesizeScreen.pickDefaultTtsVoice(
          models: [bella, heart, germanEva],
          backend: 'kokoro',
          companions: const ['kokoro-voice-af_heart', 'kokoro-voice-df_eva'],
        ),
        'kokoro-voice-af_heart',
      );
    });

    test('falls back to the first downloaded voice for the backend', () {
      expect(
        SynthesizeScreen.pickDefaultTtsVoice(
          models: [bella, heart],
          backend: 'kokoro',
          companions: const ['kokoro-voice-df_eva'], // not downloaded
          preferred: 'kokoro-voice-df_eva',
        ),
        bella.name,
      );
    });

    test('null when the backend has no downloaded voicepack', () {
      expect(
        SynthesizeScreen.pickDefaultTtsVoice(
          models: [otherBackend],
          backend: 'kokoro',
          companions: const ['kokoro-voice-af_heart'],
          preferred: 'kokoro-voice-af_heart',
        ),
        isNull,
      );
    });
  });

  group('SynthesizeScreen.pickDefaultTtsCodec', () {
    final companionCodec = _info('qwen3-tts-codec-12hz',
        kind: ModelKind.codec, backend: 'qwen3-tts');
    final otherCodec = _info('qwen3-tts-codec-24hz',
        kind: ModelKind.codec, backend: 'qwen3-tts');

    test("the model's own codec companion beats catalogue order", () {
      expect(
        SynthesizeScreen.pickDefaultTtsCodec(
          models: [otherCodec, companionCodec],
          backend: 'qwen3-tts',
          companions: const ['qwen3-tts-codec-12hz'],
        ),
        'qwen3-tts-codec-12hz',
      );
    });

    test('falls back to the first downloaded codec for the backend', () {
      expect(
        SynthesizeScreen.pickDefaultTtsCodec(
          models: [otherCodec, companionCodec],
          backend: 'qwen3-tts',
          companions: const [],
        ),
        otherCodec.name,
      );
    });

    test('null when the backend has no downloaded codec', () {
      expect(
        SynthesizeScreen.pickDefaultTtsCodec(
          models: [_info('kokoro-82m-q8_0', kind: ModelKind.tts)],
          backend: 'kokoro',
          companions: const [],
        ),
        isNull,
      );
    });
  });

  group('OnboardingScreen.persistTtsDefaults', () {
    late SharedPreferences prefs;
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
    });

    test('defaults are empty before onboarding runs', () {
      expect(settings.defaultTtsModel, '');
      expect(settings.defaultTtsVoice, '');
    });

    test('records the model and its first voice companion', () {
      final model = ModelCatalog.crispasrBackendModels['kokoro-82m-q8_0']!;
      final companions = model.companions
          .map((n) => ModelCatalog.crispasrBackendModels[n])
          .whereType<ModelDefinition>()
          .toList();
      OnboardingScreen.persistTtsDefaults(settings, model.name, companions);

      // Read back through a fresh service: this is a real prefs round-trip,
      // so a typo'd storage key fails here rather than in the app.
      final reloaded = SettingsService(prefs);
      expect(reloaded.defaultTtsModel, 'kokoro-82m-q8_0');
      expect(reloaded.defaultTtsVoice, 'kokoro-voice-af_heart');
    });

    test('a codec companion is never stored as the voice', () {
      const codec = ModelDefinition(
        name: 'qwen3-tts-codec-12hz',
        displayName: 'codec',
        fileName: 'codec.gguf',
        url: '',
        sizeBytes: 1,
        checksum: '',
        description: '',
        backend: 'qwen3-tts',
        kind: ModelKind.codec,
      );
      const voice = ModelDefinition(
        name: 'qwen3-voice-x',
        displayName: 'voice',
        fileName: 'voice.gguf',
        url: '',
        sizeBytes: 1,
        checksum: '',
        description: '',
        backend: 'qwen3-tts',
        kind: ModelKind.voice,
      );
      OnboardingScreen.persistTtsDefaults(
          settings, 'qwen3-tts-12hz-0.6b-base-q8_0', [codec, voice]);
      expect(settings.defaultTtsModel, 'qwen3-tts-12hz-0.6b-base-q8_0');
      expect(settings.defaultTtsVoice, 'qwen3-voice-x');
    });

    test('a model with no voice companion clears any stale voice', () {
      settings.defaultTtsVoice = 'kokoro-voice-af_heart';
      OnboardingScreen.persistTtsDefaults(
          settings, 'vibevoice-realtime-0.5b-tts-f16', const []);
      expect(settings.defaultTtsModel, 'vibevoice-realtime-0.5b-tts-f16');
      expect(settings.defaultTtsVoice, '');
    });

    test('what onboarding records is what the screen selects', () {
      // End-to-end over the two pure halves, with the real catalogue rows:
      // record the starter pick, then ask the screen what it would choose
      // from a model list where catalogue order says something else.
      final model = ModelCatalog.crispasrBackendModels['kokoro-82m-q8_0']!;
      final companions = model.companions
          .map((n) => ModelCatalog.crispasrBackendModels[n])
          .whereType<ModelDefinition>()
          .toList();
      expect(companions.map((d) => d.kind), contains(ModelKind.voice),
          reason: 'the kokoro starter must still ship a voicepack companion');
      OnboardingScreen.persistTtsDefaults(settings, model.name, companions);

      final downloaded = <ModelInfo>[
        _info('vibevoice-realtime-0.5b-tts-f16',
            kind: ModelKind.tts, backend: 'vibevoice-tts'),
        _info(model.name, kind: ModelKind.tts),
        _info('kokoro-voice-af_bella', kind: ModelKind.voice),
        _info('kokoro-voice-af_heart', kind: ModelKind.voice),
      ];

      expect(
        SynthesizeScreen.pickDefaultTtsModel(
            downloaded, settings.defaultTtsModel),
        'kokoro-82m-q8_0',
      );
      expect(
        SynthesizeScreen.pickDefaultTtsVoice(
          models: downloaded,
          backend: model.backend,
          companions: model.companions,
          preferred: settings.defaultTtsVoice,
        ),
        'kokoro-voice-af_heart',
      );
    });
  });
}
