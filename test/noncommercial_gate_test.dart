// Non-commercial models exist only in development builds
// (--dart-define=CW_NONCOMMERCIAL_MODELS=true). `flutter test` runs without
// the define — as CI and every release build do — so these tests pin the
// store behaviour: such models are not listed, not resolvable and not
// usable from disk, and that holds for rows with no licence string.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/services/baked_catalog_loader.dart';
import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';

/// Hand-written catalogue rows from non-commercial repos, one per repo
/// family: the audit that built ModelCatalog.nonCommercialRepos.
const _knownNonCommercial = [
  'f5-tts-v1-base-f16',
  'outetts-0.3-1b-q8_0',
  'voxtral-4b-tts-q4_k',
  'posformer-crohme-q8_0',
  'qwen2.5-3b-instruct-q4_k_m',
  'breeze-tts-2-q4_k',
  'raon-opentts-0.3b-f16',
  'raon-opentts-1b-f16',
  'quds-v4-fa-q8_0',
];

void main() {
  test('this build does not allow non-commercial models', () {
    // If this fails, the test run (or CI) was started with
    // CW_NONCOMMERCIAL_MODELS — which a store build must never be.
    expect(ModelCatalog.allowNonCommercial, isFalse);
  });

  test('every audited non-commercial row is recognised and not offered', () {
    for (final name in _knownNonCommercial) {
      final def = ModelCatalog.crispasrBackendModels[name];
      expect(def, isNotNull, reason: name);
      expect(def!.isNonCommercial, isTrue, reason: name);
      expect(def.isOffered, isFalse, reason: name);
    }
  });

  test('a licence-less row from a non-commercial repo is still caught', () {
    // What the HF probe produces for a quant it discovers: no licence.
    const probed = ModelDefinition(
      name: 'outetts-0.3-1b-f16',
      displayName: 'OuteTTS 0.3 1B (f16)',
      fileName: 'outetts-0.3-1b-f16.gguf',
      url:
          'https://huggingface.co/cstr/outetts-0.3-1b-GGUF/resolve/main/outetts-0.3-1b-f16.gguf',
      sizeBytes: 1,
      checksum: '',
      description: '',
      quantization: 'f16',
      backend: 'outetts',
    );
    expect(probed.license, isNull);
    expect(probed.isNonCommercial, isTrue);
    expect(probed.isOffered, isFalse);
  });

  test('permissive models are unaffected', () {
    for (final name in [
      'supertonic3-f16',
      'basic-pitch-f16',
      'chatterbox-nano-t3-q8_0',
      'pocket-tts-german-q8_0',
    ]) {
      final def = ModelCatalog.crispasrBackendModels[name]!;
      expect(def.isNonCommercial, isFalse, reason: name);
      expect(def.isOffered, isTrue, reason: name);
    }
  });

  group('ModelService in a store build', () {
    late ModelService svc;
    late Directory tmp;
    late String modelsDir;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await BakedCatalogLoader.load();
    });
    tearDownAll(() => BakedCatalogLoader.reset());

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cw_nc_gate_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
      modelsDir = p.join(tmp.path, 'models');
      await Directory(modelsDir).create(recursive: true);
      SharedPreferences.setMockInitialValues({'custom_models_dir': modelsDir});
      svc = ModelService(SettingsService(await SharedPreferences.getInstance()));
    });

    tearDown(() => tmp.delete(recursive: true));

    test('lists no non-commercial model, including baked rows', () async {
      final listed = await svc.getWhisperCppModels();
      expect(listed, isNotEmpty);
      final names = listed.map((m) => m.name).toSet();
      for (final name in _knownNonCommercial) {
        expect(names, isNot(contains(name)));
      }
      // The baked moonshine-de-fidoriel rows carry the licence only via
      // their repo; they must be gone too.
      expect(names.where((n) => n.contains('fidoriel')), isEmpty);
    });

    test('does not resolve one by name, so it cannot be downloaded', () async {
      await svc.initialize();
      for (final name in _knownNonCommercial) {
        expect(svc.lookupDefinition(name), isNull, reason: name);
      }
      expect(svc.lookupDefinition('supertonic3-f16'), isNotNull);
      await expectLater(svc.downloadWhisperCppModel('outetts-0.3-1b-q8_0'),
          throwsA(isA<ModelException>()));
    });

    test('a leftover non-commercial file on disk is not usable', () async {
      await svc.initialize();
      expect(svc.isOfferedFile('posformer-crohme-q8_0.gguf'), isFalse);
      expect(svc.isOfferedFile('basic-pitch-f16.gguf'), isTrue);
      expect(svc.isOfferedFile('some-unknown-file.gguf'), isTrue);
    });
  });
}
