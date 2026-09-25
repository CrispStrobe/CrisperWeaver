import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_catalog.dart';

void main() {
  const expected = <String,
      ({String fileName, String url, int sizeBytes, String quantization})>{
    'canary-180m-flash-q4_k_m': (
      fileName: 'canary-180m-flash-Q4_K_M.gguf',
      url:
          'https://huggingface.co/handy-computer/canary-180m-flash-gguf/resolve/main/canary-180m-flash-Q4_K_M.gguf',
      sizeBytes: 139223744,
      quantization: 'q4_k_m',
    ),
    'canary-180m-flash-q5_k_m': (
      fileName: 'canary-180m-flash-Q5_K_M.gguf',
      url:
          'https://huggingface.co/handy-computer/canary-180m-flash-gguf/resolve/main/canary-180m-flash-Q5_K_M.gguf',
      sizeBytes: 158704320,
      quantization: 'q5_k_m',
    ),
  };

  group('Canary 180M Flash curated catalogue', () {
    test(
      'is visible from the cold-start static catalogue with exact metadata',
      () {
        for (final entry in expected.entries) {
          final model = ModelCatalog.crispasrBackendModels[entry.key];
          expect(model, isNotNull, reason: '${entry.key} must be static');
          expect(model!.name, entry.key);
          expect(model.fileName, entry.value.fileName);
          expect(model.url, entry.value.url);
          expect(model.sizeBytes, entry.value.sizeBytes);
          expect(model.quantization, entry.value.quantization);
          expect(model.backend, 'canary');
          expect(model.kind, ModelKind.asr);
          expect(
            model.checksum,
            isEmpty,
            reason: 'the upstream SHA-256 must not populate the SHA-1 field',
          );
        }
      },
    );

    test(
      'descriptions distinguish ASR-only and full-capability validation',
      () {
        final q4 =
            ModelCatalog.crispasrBackendModels['canary-180m-flash-q4_k_m']!;
        final q5 =
            ModelCatalog.crispasrBackendModels['canary-180m-flash-q5_k_m']!;

        expect(q4.description, contains('recommended for transcription'));
        expect(
          q4.description,
          contains('EN→DE translation emitted immediate EOS'),
        );
        expect(q4.description, contains('use Q5_K_M or higher'));
        expect(q5.description, contains('English-pivot translation'));
        expect(q5.description, contains('JFK gate'));
        expect(q5.description, contains('does not establish broad'));
      },
    );

    test('both rows filter to exactly the four supported languages', () {
      for (final name in expected.keys) {
        final model = ModelCatalog.crispasrBackendModels[name]!;
        expect(model.languages, ['en', 'de', 'es', 'fr']);
        for (final language in const ['en', 'de', 'es', 'fr']) {
          expect(
            model.matchesLanguage(language),
            isTrue,
            reason: '$name must match $language',
          );
        }
        expect(model.matchesLanguage('it'), isFalse);
      }
    });

    test('Canary 1B v2 remains the global canary recommendation', () {
      expect(
        ModelCatalog.recommendedDefaultModels['canary'],
        'canary-1b-v2-q5_0',
      );
      for (final name in expected.keys) {
        expect(ModelCatalog.isRecommendedDefault(name), isFalse);
      }
    });
  });

  group('Canary 180M Flash BackendRepo', () {
    test('is separately discoverable through the existing canary backend', () {
      final repo = ModelCatalog.backendRepos['canary-180m-flash'];
      expect(repo, isNotNull);
      expect(repo!.backend, 'canary');
      expect(repo.repoId, 'handy-computer/canary-180m-flash-gguf');
      expect(repo.baseName, 'canary-180m-flash');
      expect(repo.displayPrefix, 'Canary 180M Flash');
      expect(repo.kind, ModelKind.asr);
      expect(repo.lowercaseQuantLabels, isTrue);
      expect(repo.defaultLanguages, ['en', 'de', 'es', 'fr']);
    });

    test('uppercase probe suffixes cannot create rows beside curated entries',
        () {
      final discovered = <String, ModelDefinition>{
        for (final entry in expected.entries)
          'canary-180m-flash-${entry.value.fileName.split('-').last.replaceFirst('.gguf', '')}':
              ModelDefinition(
            name:
                'canary-180m-flash-${entry.value.fileName.split('-').last.replaceFirst('.gguf', '')}',
            displayName: 'Canary 180M Flash (probe)',
            fileName: entry.value.fileName,
            url: entry.value.url,
            sizeBytes: entry.value.sizeBytes,
            checksum: '',
            description: 'Live-probed row',
            quantization:
                entry.value.fileName.split('-').last.replaceFirst('.gguf', ''),
            backend: 'canary',
            languages: const ['en', 'de', 'es', 'fr'],
          ),
      };

      final suppressed = ModelCatalog.duplicateFileNameEntries(
        baked: const <String, ModelDefinition>{},
        discovered: discovered,
      );
      expect(suppressed, discovered.keys.toSet());
      expect(
        suppressed.intersection(expected.keys.toSet()),
        isEmpty,
        reason: 'case-insensitive filename dedup must retain curated rows',
      );
    });
  });

  test('official baked catalogue mirrors the repo with lowercase labels', () {
    final json =
        (jsonDecode(File('assets/models/catalog.json').readAsStringSync())
                as List<dynamic>)
            .cast<Map<String, dynamic>>();
    final baked = <String, Map<String, dynamic>>{
      for (final row in json)
        if ((row['name'] as String).startsWith('canary-180m-flash-'))
          row['name'] as String: row,
    };

    expect(baked.keys, containsAll(expected.keys));
    for (final entry in expected.entries) {
      final row = baked[entry.key]!;
      expect(row['fileName'], entry.value.fileName);
      expect(row['url'], entry.value.url);
      expect(row['sizeBytes'], entry.value.sizeBytes);
      expect(row['quantization'], entry.value.quantization);
      expect(row['backend'], 'canary');
      expect(row['kind'], 'asr');
      expect(row['languages'], ['en', 'de', 'es', 'fr']);
    }
    for (final row in baked.values) {
      expect(row['name'], (row['name'] as String).toLowerCase());
      expect(
        row['quantization'],
        (row['quantization'] as String).toLowerCase(),
      );
    }
  });
}
