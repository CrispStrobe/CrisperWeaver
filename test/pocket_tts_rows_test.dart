// Pocket TTS rows from the baked catalogue and the HF probe carry no
// `requiresVoice`, and three of them are `-novc` builds that cannot speak at
// all. Without a reference, Pocket TTS produced audio with no recognisable
// words, and the Synthesize screen only blocks that when the row says
// requiresVoice. These tests run against the shipped baked catalogue, which
// is where the unflagged rows came from.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/services/baked_catalog_loader.dart';
import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';

void main() {
  late ModelService svc;
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await BakedCatalogLoader.load();
  });
  tearDownAll(() => BakedCatalogLoader.reset());

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cw_pocket_rows_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    final models = p.join(tmp.path, 'models');
    await Directory(models).create(recursive: true);
    SharedPreferences.setMockInitialValues({'custom_models_dir': models});
    svc = ModelService(SettingsService(await SharedPreferences.getInstance()));
    await svc.initialize();
  });
  tearDown(() => tmp.delete(recursive: true));

  test('the baked catalogue really does ship unflagged Pocket TTS rows', () {
    // Pins the premise: if a future bake adds the flag itself, the
    // normalisation below is redundant rather than wrong.
    final raw = BakedCatalogLoader.cached['pocket-tts-english-q8_0'];
    expect(raw, isNotNull);
    expect(raw!.requiresVoice, isFalse);
  });

  test('every resolvable Pocket TTS row requires a voice', () async {
    final names = (await svc.getWhisperCppModels())
        .where((m) => m.backend == 'pocket-tts')
        .map((m) => m.name)
        .toList();
    expect(names, isNotEmpty);
    for (final name in names) {
      expect(svc.lookupDefinition(name)!.requiresVoice, isTrue, reason: name);
    }
  });

  test('-novc builds are neither listed nor resolvable', () async {
    final listed = (await svc.getWhisperCppModels()).map((m) => m.name);
    expect(listed.where((n) => n.contains('-novc')), isEmpty);
    expect(svc.lookupDefinition('pocket-tts-english-novc-q8_0'), isNull);
  });

  test('other backends are untouched', () {
    expect(svc.lookupDefinition('supertonic3-f16')!.requiresVoice, isFalse);
    expect(ModelCatalog.isUnusableFile('supertonic3-f16.gguf'), isFalse);
  });
}
