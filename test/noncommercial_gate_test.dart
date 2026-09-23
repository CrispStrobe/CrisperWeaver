// Non-commercial models exist only in development builds
// (--dart-define=CW_NONCOMMERCIAL_MODELS=true). `flutter test` runs without
// the define — as CI and every release build do — so by default these tests
// pin the store behaviour: such models are not listed, not resolvable and
// not usable from disk, and that holds for rows with no licence string.
//
// Run with the define, the same tests check the development build instead:
// every audited model is listed, resolvable and usable.
//   flutter test --dart-define=CW_NONCOMMERCIAL_MODELS=true test/noncommercial_gate_test.dart

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
  // Which build this run models. CI runs plain `flutter test`, so the store
  // behaviour is what CI pins.
  const dev = ModelCatalog.allowNonCommercial;

  test('every audited non-commercial row is recognised, offered only in dev', () {
    for (final name in _knownNonCommercial) {
      final def = ModelCatalog.crispasrBackendModels[name];
      expect(def, isNotNull, reason: name);
      expect(def!.isNonCommercial, isTrue, reason: name);
      expect(def.isOffered, dev, reason: name);
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
    expect(probed.isOffered, dev);
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

  group('ModelService (${dev ? 'development' : 'store'} build)', () {
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

    test('lists non-commercial models only in a development build',
        () async {
      final listed = await svc.getWhisperCppModels();
      expect(listed, isNotEmpty);
      final names = listed.map((m) => m.name).toSet();
      for (final name in _knownNonCommercial) {
        expect(names.contains(name), dev, reason: name);
      }
      // The baked moonshine-de-fidoriel rows carry the licence only via
      // their repo.
      expect(names.any((n) => n.contains('fidoriel')), dev);
    });

    test('resolves one by name only in a development build', () async {
      await svc.initialize();
      for (final name in _knownNonCommercial) {
        expect(svc.lookupDefinition(name) != null, dev, reason: name);
      }
      expect(svc.lookupDefinition('supertonic3-f16'), isNotNull);
      if (!dev) {
        await expectLater(svc.downloadWhisperCppModel('outetts-0.3-1b-q8_0'),
            throwsA(isA<ModelException>()));
      }
    });

    test('a non-commercial file on disk is usable only in a development build',
        () async {
      await svc.initialize();
      expect(svc.isOfferedFile('posformer-crohme-q8_0.gguf'), dev);
      expect(svc.isOfferedFile('basic-pitch-f16.gguf'), isTrue);
      expect(svc.isOfferedFile('some-unknown-file.gguf'), isTrue);
    });
  });
}
