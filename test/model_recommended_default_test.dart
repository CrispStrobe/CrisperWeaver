// PLAN §5.4 — guards for the per-backend "recommended default" model
// (CrispASR `-m auto` parity). Pure-data + cheap-instance checks; no
// CrispASR dylib, runs in <1 s on CI.
//
// What can rot here:
//   * a curated default name that doesn't resolve to any catalogue
//     entry (typo / renamed model) → [every default resolves …].
//   * a default catalogued under a different backend than its map key
//     → same test (backend mismatch).
//   * two defaults sneaking in for one backend → [at most one …].
//   * defaultForBackend / isRecommendedDefault drifting from the map.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';

void main() {
  // The hand-curated static catalogue the defaults must resolve
  // against. Live-probed (`_discoveredModels`) and baked HF-quant
  // entries are intentionally excluded — defaults only ever point at
  // the two maintained maps (see `recommendedDefaultModels` doc).
  final catalogue = <String, ModelDefinition>{
    ...ModelCatalog.whisperCppModels,
    ...ModelCatalog.crispasrBackendModels,
  };

  group('recommendedDefaultModels (PLAN §5.4)', () {
    test('every default resolves to a real entry whose backend matches',
        () {
      ModelCatalog.recommendedDefaultModels.forEach((backend, name) {
        final def = catalogue[name];
        expect(def, isNotNull,
            reason: 'default "$name" for backend "$backend" is not in the '
                'curated catalogue (whisperCppModels / crispasrBackendModels)');
        expect(def!.backend, backend,
            reason: 'default "$name" is catalogued under backend '
                '"${def.backend}", not the "$backend" it is mapped to');
      });
    });

    test('at most one recommended default per backend', () {
      // The Map keys are unique by construction; this asserts the
      // values can't resolve two different names to the same backend.
      final byBackend = <String, List<String>>{};
      ModelCatalog.recommendedDefaultModels.forEach((_, name) {
        final b = catalogue[name]!.backend;
        byBackend.putIfAbsent(b, () => <String>[]).add(name);
      });
      for (final entry in byBackend.entries) {
        expect(entry.value.length, 1,
            reason: 'backend "${entry.key}" has >1 recommended default: '
                '${entry.value}');
      }
    });

    test('isRecommendedDefault tracks the map values', () {
      expect(ModelCatalog.isRecommendedDefault('base'), isTrue);
      expect(ModelCatalog.isRecommendedDefault('kokoro-82m-q8_0'), isTrue);
      // real catalogue entries that are NOT defaults
      expect(ModelCatalog.isRecommendedDefault('large-v3'), isFalse);
      expect(ModelCatalog.isRecommendedDefault('tiny'), isFalse);
      // not a model at all
      expect(ModelCatalog.isRecommendedDefault('nope-xyz'), isFalse);
    });
  });

  group('defaultForBackend', () {
    late ModelService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      svc = ModelService(SettingsService(prefs));
    });

    test('returns the curated def for flagged backends', () {
      expect(svc.defaultForBackend('whisper')?.name, 'base');
      expect(svc.defaultForBackend('parakeet')?.name,
          'parakeet-tdt-0.6b-v3-q4_k');
      expect(svc.defaultForBackend('kokoro')?.name, 'kokoro-82m-q8_0');
      expect(svc.defaultForBackend('piper')?.name, 'piper-en-cori');
    });

    test('returns null for backends with no curated default', () {
      // companions / post-proc / vad / lid / diarisation / embedding
      for (final b in const [
        'vad',
        'pyannote',
        'titanet',
        'lid',
        'firered-punc',
        'totally-unknown-backend',
      ]) {
        expect(svc.defaultForBackend(b), isNull,
            reason: 'backend "$b" should have no recommended default');
      }
    });
  });
}
