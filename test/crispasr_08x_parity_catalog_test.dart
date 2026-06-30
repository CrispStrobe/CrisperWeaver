// CrispASR 0.8.x parity catalog — pins the 7 new backends/variants added
// in the June 2026 §11 sweep (dots-tts, higgs-stt, ark-asr,
// moss-transcribe, gemma4-e4b, reazonspeech, parakeet-ctc-1.1b-ja) so a
// future refactor doesn't silently drop them from the model picker.
//
// See PLAN.md §11.1 for the gap analysis.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_service.dart';

void main() {
  group('CrispASR 0.8.x parity catalog (§11)', () {
    // ---- New ASR backends ----

    test('moss-transcribe is in the catalog with correct backend', () {
      final def =
          ModelCatalog.crispasrBackendModels['moss-transcribe-preview-2b-q4_k'];
      expect(def, isNotNull,
          reason: 'moss-transcribe-preview-2b-q4_k missing from catalog');
      expect(def!.backend, 'moss-transcribe');
      expect(def.kind, ModelKind.asr);
      expect(def.fileName, 'moss-transcribe-preview-2b-q4_k.gguf');
    });

    test('moss-transcribe has a BackendRepo', () {
      expect(
          ModelCatalog.backendRepos.containsKey('moss-transcribe'), isTrue,
          reason: 'BackendRepo "moss-transcribe" missing');
      expect(
          ModelCatalog.backendRepos['moss-transcribe']!.backend,
          'moss-transcribe');
    });

    test('moss-transcribe is in recommendedDefaultModels', () {
      expect(
          ModelCatalog.recommendedDefaultModels
              .containsKey('moss-transcribe'),
          isTrue,
          reason: 'moss-transcribe missing from recommendedDefaultModels');
    });

    test('higgs-stt is in the catalog with correct backend', () {
      final def = ModelCatalog.crispasrBackendModels['higgs-stt-q4_k'];
      expect(def, isNotNull,
          reason: 'higgs-stt-q4_k missing from catalog');
      expect(def!.backend, 'higgs-stt');
      expect(def.kind, ModelKind.asr);
      expect(def.fileName, 'higgs-stt-q4_k.gguf');
      expect(def.languages, isNotEmpty,
          reason: 'higgs-stt should have language list');
    });

    test('higgs-stt has a BackendRepo', () {
      expect(ModelCatalog.backendRepos.containsKey('higgs-stt'), isTrue,
          reason: 'BackendRepo "higgs-stt" missing');
      expect(ModelCatalog.backendRepos['higgs-stt']!.backend, 'higgs-stt');
    });

    test('higgs-stt is in recommendedDefaultModels', () {
      expect(
          ModelCatalog.recommendedDefaultModels.containsKey('higgs-stt'),
          isTrue);
    });

    test('ark-asr is in the catalog with correct backend', () {
      final def = ModelCatalog.crispasrBackendModels['ark-asr-3b-q4_k'];
      expect(def, isNotNull,
          reason: 'ark-asr-3b-q4_k missing from catalog');
      expect(def!.backend, 'ark-asr');
      expect(def.kind, ModelKind.asr);
      expect(def.fileName, 'ark-asr-3b-q4_k.gguf');
    });

    test('ark-asr has a BackendRepo', () {
      expect(ModelCatalog.backendRepos.containsKey('ark-asr'), isTrue,
          reason: 'BackendRepo "ark-asr" missing');
      expect(ModelCatalog.backendRepos['ark-asr']!.backend, 'ark-asr');
    });

    test('ark-asr is in recommendedDefaultModels', () {
      expect(
          ModelCatalog.recommendedDefaultModels.containsKey('ark-asr'),
          isTrue);
    });

    // ---- New model variants (existing backends) ----

    test('gemma4-e4b is in the catalog reusing gemma4-e2b backend', () {
      final def = ModelCatalog.crispasrBackendModels['gemma4-e4b-q4_k'];
      expect(def, isNotNull,
          reason: 'gemma4-e4b-q4_k missing from catalog');
      expect(def!.backend, 'gemma4-e2b',
          reason: 'gemma4-e4b should reuse gemma4-e2b backend');
      expect(def.kind, ModelKind.asr);
      expect(def.fileName, 'gemma4-e4b-it-q4_k.gguf');
    });

    test('gemma4-e4b has a BackendRepo', () {
      expect(ModelCatalog.backendRepos.containsKey('gemma4-e4b'), isTrue,
          reason: 'BackendRepo "gemma4-e4b" missing');
    });

    test('gemma4-e4b is NOT in recommendedDefaultModels (shares gemma4-e2b)',
        () {
      // Variants sharing a backend don't get their own recommended default
      // to maintain the one-default-per-backend invariant.
      expect(
          ModelCatalog.recommendedDefaultModels.containsKey('gemma4-e4b'),
          isFalse);
    });

    test('reazonspeech is in the catalog reusing parakeet backend', () {
      final def =
          ModelCatalog.crispasrBackendModels['reazonspeech-nemo-v2-q8_0'];
      expect(def, isNotNull,
          reason: 'reazonspeech-nemo-v2-q8_0 missing from catalog');
      expect(def!.backend, 'parakeet',
          reason: 'reazonspeech should reuse parakeet backend');
      expect(def.kind, ModelKind.asr);
      expect(def.quantization, 'q8_0',
          reason: 'Japanese models use q8_0 (quant-sensitive)');
      expect(def.languages, contains('ja'));
    });

    test('reazonspeech has a BackendRepo', () {
      expect(ModelCatalog.backendRepos.containsKey('reazonspeech'), isTrue,
          reason: 'BackendRepo "reazonspeech" missing');
      expect(ModelCatalog.backendRepos['reazonspeech']!.backend, 'parakeet');
    });

    test('parakeet-ctc-1.1b-ja is in the catalog reusing parakeet backend',
        () {
      final def =
          ModelCatalog.crispasrBackendModels['parakeet-ctc-1.1b-ja-q8_0'];
      expect(def, isNotNull,
          reason: 'parakeet-ctc-1.1b-ja-q8_0 missing from catalog');
      expect(def!.backend, 'parakeet',
          reason: 'parakeet-ctc-1.1b-ja should reuse parakeet backend');
      expect(def.quantization, 'q8_0');
      expect(def.languages, contains('ja'));
    });

    test('parakeet-ctc-1.1b-ja has a BackendRepo', () {
      expect(
          ModelCatalog.backendRepos.containsKey('parakeet-ctc-1.1b-ja'),
          isTrue,
          reason: 'BackendRepo "parakeet-ctc-1.1b-ja" missing');
    });

    test('shared-backend variants are NOT in recommendedDefaultModels', () {
      // reazonspeech and parakeet-ctc-1.1b-ja share the parakeet backend
      expect(
          ModelCatalog.recommendedDefaultModels.containsKey('reazonspeech'),
          isFalse);
      expect(
          ModelCatalog.recommendedDefaultModels
              .containsKey('parakeet-ctc-1.1b-ja'),
          isFalse);
    });

    // ---- New TTS backend ----

    test('dots-tts is in the catalog as TTS with companions', () {
      final def = ModelCatalog.crispasrBackendModels['dots-tts-soar-f16'];
      expect(def, isNotNull,
          reason: 'dots-tts-soar-f16 missing from catalog');
      expect(def!.backend, 'dots-tts');
      expect(def.kind, ModelKind.tts);
      expect(def.companions, isNotNull);
      expect(def.companions, contains('dots-tts-soar-vocoder-f16'));
      expect(def.companions, contains('dots-tts-soar-spk-f16'));
    });

    test('dots-tts vocoder companion is in the catalog', () {
      final def =
          ModelCatalog.crispasrBackendModels['dots-tts-soar-vocoder-f16'];
      expect(def, isNotNull,
          reason: 'dots-tts-soar-vocoder-f16 missing from catalog');
      expect(def!.kind, ModelKind.codec);
      expect(def.backend, 'dots-tts');
    });

    test('dots-tts speaker encoder companion is in the catalog', () {
      final def =
          ModelCatalog.crispasrBackendModels['dots-tts-soar-spk-f16'];
      expect(def, isNotNull,
          reason: 'dots-tts-soar-spk-f16 missing from catalog');
      expect(def!.kind, ModelKind.codec);
      expect(def.backend, 'dots-tts');
    });

    test('dots-tts has a BackendRepo', () {
      expect(ModelCatalog.backendRepos.containsKey('dots-tts'), isTrue,
          reason: 'BackendRepo "dots-tts" missing');
      expect(ModelCatalog.backendRepos['dots-tts']!.backend, 'dots-tts');
      expect(ModelCatalog.backendRepos['dots-tts']!.kind, ModelKind.tts);
    });

    test('dots-tts is in recommendedDefaultModels', () {
      expect(
          ModelCatalog.recommendedDefaultModels.containsKey('dots-tts'),
          isTrue);
    });

    test('kindForBackend returns tts for dots-tts', () {
      expect(ModelCatalog.kindForBackend('dots-tts'), ModelKind.tts);
    });

    // ---- Cross-checks ----

    test('all 7 new entries have non-empty URLs', () {
      const keys = [
        'moss-transcribe-preview-2b-q4_k',
        'higgs-stt-q4_k',
        'ark-asr-3b-q4_k',
        'gemma4-e4b-q4_k',
        'reazonspeech-nemo-v2-q8_0',
        'parakeet-ctc-1.1b-ja-q8_0',
        'dots-tts-soar-f16',
      ];
      for (final key in keys) {
        final def = ModelCatalog.crispasrBackendModels[key];
        expect(def, isNotNull, reason: '$key missing');
        expect(def!.url, isNotEmpty, reason: '$key has empty URL');
        expect(def.sizeBytes, greaterThan(0),
            reason: '$key has zero sizeBytes');
      }
    });

    test('all new BackendRepos have non-empty repoId', () {
      const keys = [
        'moss-transcribe',
        'higgs-stt',
        'ark-asr',
        'gemma4-e4b',
        'reazonspeech',
        'parakeet-ctc-1.1b-ja',
        'dots-tts',
      ];
      for (final key in keys) {
        final repo = ModelCatalog.backendRepos[key];
        expect(repo, isNotNull, reason: 'BackendRepo "$key" missing');
        expect(repo!.repoId, isNotEmpty,
            reason: 'BackendRepo "$key" has empty repoId');
      }
    });
  });
}
