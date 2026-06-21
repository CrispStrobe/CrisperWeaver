// CrispASR 0.7.x parity catalog — pins the 11 entries added in the June
// 2026 §10 sweep (canary-ctc-aligner + 10 wav2vec2 language variants) so
// a future refactor doesn't silently drop them from the model picker.
//
// See PLAN.md §10.1 for the gap analysis.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_service.dart';

void main() {
  group('CrispASR 0.7.x parity catalog (§10)', () {
    test('canary-ctc-aligner is in the catalog with correct backend', () {
      final def =
          ModelCatalog.crispasrBackendModels['canary-ctc-aligner-q4_k'];
      expect(def, isNotNull,
          reason: 'canary-ctc-aligner-q4_k missing from catalog');
      expect(def!.backend, 'canary-ctc-aligner');
      expect(def.kind, ModelKind.asr);
      expect(def.fileName, 'canary-ctc-aligner-q4_k.gguf');
    });

    test('canary-ctc-aligner has a BackendRepo', () {
      expect(ModelCatalog.backendRepos.containsKey('canary-ctc-aligner'),
          isTrue,
          reason: 'BackendRepo "canary-ctc-aligner" missing');
      expect(
          ModelCatalog.backendRepos['canary-ctc-aligner']!.backend,
          'canary-ctc-aligner');
    });

    test('canary-ctc-aligner is in recommendedDefaultModels', () {
      expect(
          ModelCatalog.recommendedDefaultModels
              .containsKey('canary-ctc-aligner'),
          isTrue,
          reason: 'canary-ctc-aligner missing from recommendedDefaultModels');
    });

    test('all 10 wav2vec2 language variants are in the catalog', () {
      const variants = {
        'wav2vec2-xlsr-fr-q4_k': 'fr',
        'wav2vec2-xlsr-es-q4_k': 'es',
        'wav2vec2-xlsr-it-q4_k': 'it',
        'wav2vec2-xlsr-ja-q4_k': 'ja',
        'wav2vec2-xlsr-zh-q4_k': 'zh',
        'wav2vec2-xlsr-nl-q4_k': 'nl',
        'wav2vec2-xlsr-pt-q4_k': 'pt',
        'wav2vec2-xlsr-ar-q4_k': 'ar',
        'wav2vec2-xlsr-cs-q4_k': 'cs',
        'wav2vec2-xlsr-uk-q4_k': 'uk',
      };

      for (final entry in variants.entries) {
        final def = ModelCatalog.crispasrBackendModels[entry.key];
        expect(def, isNotNull, reason: '${entry.key} missing from catalog');
        expect(def!.backend, 'wav2vec2',
            reason: '${entry.key} should use wav2vec2 backend');
        expect(def.kind, ModelKind.asr,
            reason: '${entry.key} should be ModelKind.asr');
        expect(def.languages, contains(entry.value),
            reason:
                '${entry.key} should have language ${entry.value}');
      }
    });

    test('all 10 wav2vec2 language BackendRepos exist', () {
      const repos = [
        'wav2vec2-fr',
        'wav2vec2-es',
        'wav2vec2-it',
        'wav2vec2-ja',
        'wav2vec2-zh',
        'wav2vec2-nl',
        'wav2vec2-pt',
        'wav2vec2-ar',
        'wav2vec2-cs',
        'wav2vec2-uk',
      ];
      for (final key in repos) {
        expect(ModelCatalog.backendRepos.containsKey(key), isTrue,
            reason: 'BackendRepo "$key" missing');
        expect(ModelCatalog.backendRepos[key]!.backend, 'wav2vec2',
            reason: 'BackendRepo "$key" should use wav2vec2 backend');
      }
    });

    test('wav2vec2 language variant URLs point at distinct repos', () {
      // Each language variant should have a unique HF repo (not all
      // pointing at the English repo).
      final urls = <String>{};
      const keys = [
        'wav2vec2-xlsr-fr-q4_k',
        'wav2vec2-xlsr-es-q4_k',
        'wav2vec2-xlsr-it-q4_k',
        'wav2vec2-xlsr-ja-q4_k',
        'wav2vec2-xlsr-zh-q4_k',
        'wav2vec2-xlsr-nl-q4_k',
        'wav2vec2-xlsr-pt-q4_k',
        'wav2vec2-xlsr-ar-q4_k',
        'wav2vec2-xlsr-cs-q4_k',
        'wav2vec2-xlsr-uk-q4_k',
      ];
      for (final key in keys) {
        final def = ModelCatalog.crispasrBackendModels[key]!;
        expect(urls.add(def.url), isTrue,
            reason: '${def.fileName} URL duplicates another variant');
      }
    });
  });
}
