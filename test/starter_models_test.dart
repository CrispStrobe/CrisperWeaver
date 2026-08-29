// Starter picks + device-fit gating.
//
// The point of the curated list is that a new install has somewhere to start.
// A pick that no longer resolves silently shortens that list, which is the
// failure mode this file exists to catch — in CI rather than on a tester's
// first launch.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/memory_estimator.dart';
import 'package:crisper_weaver/services/model_catalog.dart';
import 'package:crisper_weaver/services/starter_models.dart';

/// Every model id the app can offer: the baked HF catalogue plus the
/// compiled-in whisper.cpp map. The Models screen merges both, so a pick may
/// legitimately live in either.
Set<String> _allKnownModelIds() {
  // Mirror ModelService.lookupDefinition's full layering — a pick that only
  // exists in the baked snapshot under a duplicate-suppressed name (the two
  // piper starters, issue #35 follow-up) must NOT count as resolving.
  final ids = <String>{
    ...ModelCatalog.whisperCppModels.keys,
    ...ModelCatalog.crispasrBackendModels.keys,
    ...ModelCatalog.ttsVoicepacks.keys,
  };
  final file = File('assets/models/catalog.json');
  final baked = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  for (final e in baked) {
    ids.add((e as Map<String, dynamic>)['name'] as String);
  }
  return ids;
}

void main() {
  group('Curated starter picks', () {
    test('every pick resolves to a real model', () {
      final known = _allKnownModelIds();
      for (final id in StarterModels.allPickIds) {
        expect(known, contains(id),
            reason: '\n\nStarter pick "$id" is not in the catalogue.\n'
                'A pick that does not resolve is skipped silently at runtime, '
                'so a new install just gets a shorter Recommended list with no '
                'sign anything is wrong. Fix the id or drop it.\n');
      }
    });

    test('picks are small enough to be plausible on a phone', () {
      // The list exists to get someone to a first transcript. A 4 GB
      // recommendation defeats that regardless of quality.
      final baked =
          jsonDecode(File('assets/models/catalog.json').readAsStringSync())
              as List<dynamic>;
      final sizes = <String, int>{
        for (final e in baked.cast<Map<String, dynamic>>())
          e['name'] as String: (e['sizeBytes'] as num?)?.toInt() ?? 0,
      };
      for (final id in StarterModels.allPickIds) {
        final s = sizes[id];
        if (s == null) continue; // whisper.cpp map carries no size here
        expect(s, lessThan(700 * 1000 * 1000),
            reason: '$id is ${(s / 1e6).round()} MB — too big to recommend '
                'as a starting point');
      }
    });

    test('no non-commercial licence is recommended', () {
      // Recommending a research-only model from inside the app points users
      // at terms the project does not itself rely on. `piper lessac` is the
      // specific trap here — Blizzard-Challenge research-only, and adjacent
      // in the catalogue to the CC0 voices that ARE recommended.
      for (final id in StarterModels.allPickIds) {
        expect(id.contains('lessac'), isFalse,
            reason: '$id is research-only licensed');
      }
    });

    test('ASR has picks, and they are ordered', () {
      final asr = StarterModels.pickIdsFor(ModelKind.asr);
      expect(asr, isNotEmpty);
      expect(StarterModels.rankOf(ModelKind.asr, asr.first), 0);
      expect(StarterModels.rankOf(ModelKind.asr, 'not-a-model'), -1);
      expect(StarterModels.hasPicksFor(ModelKind.asr), isTrue);
      // Kinds without curation render no header rather than an empty one.
      expect(StarterModels.hasPicksFor(ModelKind.codec), isFalse);
    });
  });

  group('Task-first onboarding', () {
    test('every automatic recommendation resolves', () {
      final known = _allKnownModelIds();
      for (final task in StarterTask.values) {
        for (final priority in StarterPriority.values) {
          for (final language in ['en', 'de', 'fr', 'es', 'zh']) {
            final result = StarterModels.recommend(
              task: task,
              priority: priority,
              language: language,
            );
            if (result.modelId != null) {
              expect(known, contains(result.modelId),
                  reason: '$task / $priority / $language');
            }
          }
        }
      }
    });

    test('meeting enables diarization and multilingual ASR uses Whisper', () {
      final result = StarterModels.recommend(
        task: StarterTask.meeting,
        priority: StarterPriority.quality,
        language: 'de',
      );
      expect(result.enableDiarization, isTrue);
      expect(result.modelId, 'base-q5_1');
      expect(result.kind, ModelKind.asr);
    });

    test('unsupported synthesis language never auto-downloads a model', () {
      final result = StarterModels.recommend(
        task: StarterTask.synthesize,
        priority: StarterPriority.balanced,
        language: 'zh',
      );
      expect(result.modelId, isNull);
      expect(result.route, '/models?kind=tts');
    });
  });

  group('Device-fit gating', () {
    // 3 GB — the conservative iOS default MemoryEstimator assumes.
    MemoryEstimator phone() =>
        MemoryEstimator()..physicalMemoryBytesForTest = 3 * 1024 * 1024 * 1024;

    test('a 16 GB model is refused on a 3 GB phone', () {
      expect(StarterModels.fitFor(16 * 1000 * 1000 * 1000, phone()),
          DeviceFit.tooLarge);
    });

    test('a 47 MB starter is comfortable', () {
      expect(StarterModels.fitFor(47 * 1000 * 1000, phone()),
          DeviceFit.comfortable);
    });

    test('unknown RAM never blocks anything', () {
      // Refusing on an unknown is worse than allowing: it would make the app
      // undownloadable on any platform we cannot probe.
      final unknown = MemoryEstimator()..physicalMemoryBytesForTest = null;
      expect(StarterModels.fitFor(16 * 1000 * 1000 * 1000, unknown),
          DeviceFit.unknown);
      expect(StarterModels.fitFor(0, phone()), DeviceFit.unknown,
          reason: 'a catalogue entry with no size is not a claim about RAM');
    });

    test('the budget agrees with the worker pre-flight', () {
      // Both must derive from the same constants, or the app will mark a
      // model loadable and then refuse to run a single worker against it.
      final e = phone();
      final budget = StarterModels.budgetBytes(e)!;
      final expected =
          (3 * 1024 * 1024 * 1024 * MemoryEstimator.memoryHeadroomFraction)
                  .round() -
              MemoryEstimator.baseRssBytes;
      expect(budget, expected);
    });

    test('the tight band sits between comfortable and refused', () {
      final e = phone();
      final budget = StarterModels.budgetBytes(e)!;
      // Just under the budget once overhead is applied → tight, not refused.
      final tightBytes =
          (budget * 0.95 / MemoryEstimator.modelOverheadMultiplier).round();
      expect(StarterModels.fitFor(tightBytes, e), DeviceFit.tight);
    });
  });
}
