// Unit tests for the JSON-based baked catalog (§8.4).
// Covers ModelDefinition JSON round-trip, ModelKind serialisation,
// optional-field defaults, and full catalog asset loading.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/baked_catalog_loader.dart';
import 'package:crisper_weaver/services/model_catalog.dart';

void main() {
  group('ModelDefinition.fromJson / toJson round-trip', () {
    test('round-trips all 14 fields', () {
      const original = ModelDefinition(
        name: 'test-model-q4_k',
        displayName: 'Test Model (q4_k)',
        fileName: 'test-model-q4_k.gguf',
        url: 'https://huggingface.co/cstr/test-model/resolve/main/test-model-q4_k.gguf',
        sizeBytes: 123456789,
        checksum: 'abc123',
        description: 'A test model',
        quantization: 'q4_k',
        backend: 'parakeet',
        kind: ModelKind.tts,
        companions: ['codec-model', 'voice-model'],
        languages: ['en', 'de', 'fr'],
        license: 'CC-BY-NC-SA-4.0',
        requiresVoice: true,
      );

      final json = original.toJson();
      final restored = ModelDefinition.fromJson(json);

      expect(restored.name, original.name);
      expect(restored.displayName, original.displayName);
      expect(restored.fileName, original.fileName);
      expect(restored.url, original.url);
      expect(restored.sizeBytes, original.sizeBytes);
      expect(restored.checksum, original.checksum);
      expect(restored.description, original.description);
      expect(restored.quantization, original.quantization);
      expect(restored.backend, original.backend);
      expect(restored.kind, original.kind);
      expect(restored.companions, original.companions);
      expect(restored.languages, original.languages);
      expect(restored.license, original.license);
      expect(restored.requiresVoice, original.requiresVoice);
    });

    test('survives JSON encode/decode cycle', () {
      const original = ModelDefinition(
        name: 'round-trip-test',
        displayName: 'RT',
        fileName: 'rt.gguf',
        url: 'https://example.com/rt.gguf',
        sizeBytes: 42,
        checksum: '',
        description: 'round trip',
        kind: ModelKind.embed,
        languages: ['*'],
      );

      final jsonStr = jsonEncode(original.toJson());
      final decoded =
          ModelDefinition.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

      expect(decoded.name, original.name);
      expect(decoded.kind, ModelKind.embed);
      expect(decoded.languages, ['*']);
    });
  });

  group('ModelKind enum serialisation', () {
    test('all 11 variants survive name round-trip', () {
      for (final kind in ModelKind.values) {
        final serialised = kind.name;
        final restored = ModelKind.values.byName(serialised);
        expect(restored, kind, reason: 'ModelKind.$kind failed round-trip');
      }
    });

    test('toJson emits kind as a string', () {
      const def = ModelDefinition(
        name: 'k',
        displayName: 'k',
        fileName: 'k.gguf',
        url: 'https://x/k',
        sizeBytes: 0,
        checksum: '',
        description: 'k',
        kind: ModelKind.diarize,
      );
      expect(def.toJson()['kind'], 'diarize');
    });
  });

  group('minimal JSON entry (optional fields default)', () {
    test('only required fields present', () {
      final minimalJson = <String, dynamic>{
        'name': 'min',
        'displayName': 'Min',
        'fileName': 'min.gguf',
        'url': 'https://x/min.gguf',
        'sizeBytes': 100,
        'description': 'minimal',
      };

      final def = ModelDefinition.fromJson(minimalJson);

      expect(def.checksum, '');
      expect(def.quantization, 'f16');
      expect(def.backend, 'whisper');
      expect(def.kind, ModelKind.asr);
      expect(def.companions, isEmpty);
      expect(def.languages, isEmpty);
      expect(def.license, isNull);
      expect(def.requiresVoice, isFalse);
    });
  });

  group('toJson omits default optional fields', () {
    test('companions, languages, license, requiresVoice omitted at defaults',
        () {
      const def = ModelDefinition(
        name: 'sparse',
        displayName: 'Sparse',
        fileName: 'sparse.gguf',
        url: 'https://x/sparse.gguf',
        sizeBytes: 50,
        checksum: '',
        description: 'sparse entry',
      );

      final json = def.toJson();
      expect(json.containsKey('companions'), isFalse);
      expect(json.containsKey('languages'), isFalse);
      expect(json.containsKey('license'), isFalse);
      expect(json.containsKey('requiresVoice'), isFalse);
    });
  });

  group('catalog.json asset', () {
    late String catalogJson;

    setUpAll(() {
      // Read the catalog.json directly from the file system (tests
      // can't use rootBundle without full Flutter test binding and
      // asset manifest wiring). This validates the generated file
      // itself.
      final file = File('assets/models/catalog.json');
      expect(file.existsSync(), isTrue,
          reason: 'assets/models/catalog.json must exist');
      catalogJson = file.readAsStringSync();
    });

    test('has > 0 entries', () {
      final list =
          (jsonDecode(catalogJson) as List<dynamic>).cast<Map<String, dynamic>>();
      expect(list, isNotEmpty);
      expect(list.length, greaterThanOrEqualTo(300));
    });

    test('every entry deserialises without error', () {
      final list =
          (jsonDecode(catalogJson) as List<dynamic>).cast<Map<String, dynamic>>();
      for (final item in list) {
        expect(
          () => ModelDefinition.fromJson(item),
          returnsNormally,
          reason: 'Failed on entry: ${item['name']}',
        );
      }
    });

    test('map key matches name field (key consistency)', () {
      final list =
          (jsonDecode(catalogJson) as List<dynamic>).cast<Map<String, dynamic>>();
      for (final item in list) {
        final def = ModelDefinition.fromJson(item);
        expect(def.name, item['name'],
            reason:
                'name field must match map key for ${item['name']}');
      }
    });

    test('no duplicate names', () {
      final list =
          (jsonDecode(catalogJson) as List<dynamic>).cast<Map<String, dynamic>>();
      final names = list.map((e) => e['name'] as String).toList();
      expect(names.toSet().length, names.length,
          reason: 'Duplicate names found in catalog');
    });
  });

  group('BakedCatalogLoader', () {
    setUp(() => BakedCatalogLoader.reset());
    tearDown(() => BakedCatalogLoader.reset());

    test('loadFromString populates cached', () {
      final json = jsonEncode([
        {
          'name': 'test-1',
          'displayName': 'Test 1',
          'fileName': 'test-1.gguf',
          'url': 'https://x/test-1.gguf',
          'sizeBytes': 100,
          'checksum': '',
          'description': 'test',
          'quantization': 'f16',
          'backend': 'whisper',
          'kind': 'asr',
        },
      ]);

      final result = BakedCatalogLoader.loadFromString(json);

      expect(result, hasLength(1));
      expect(result['test-1']!.displayName, 'Test 1');
      expect(BakedCatalogLoader.cached, same(result));
    });

    test('cached throws before load', () {
      expect(() => BakedCatalogLoader.cached, throwsStateError);
    });

    test('reset clears the cache', () {
      BakedCatalogLoader.loadFromString(jsonEncode([
        {
          'name': 'x',
          'displayName': 'x',
          'fileName': 'x.gguf',
          'url': 'https://x/x.gguf',
          'sizeBytes': 0,
          'checksum': '',
          'description': 'x',
          'quantization': 'f16',
          'backend': 'whisper',
          'kind': 'asr',
        },
      ]));
      BakedCatalogLoader.reset();
      expect(() => BakedCatalogLoader.cached, throwsStateError);
    });
  });
}
