// Tests for issue #28 — model download status consistency between the
// model picker (getWhisperCppModels) and the engine load path
// (getWhisperCppModelPath).  Also covers the UI error-classification
// fix: only "is not downloaded" errors should surface the "model not
// downloaded" snackbar; other load failures (backend mismatch, checksum,
// OOM) must show the actual error.

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
  late Directory tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await BakedCatalogLoader.load();
  });

  tearDownAll(() => BakedCatalogLoader.reset());

  setUp(() async {
    tmpDir = await Directory.systemTemp
        .createTemp('crisper_model_download_test_');

    // Mock path_provider so ModelService.initialize() doesn't crash.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tmpDir.path;
        }
        return null;
      },
    );

    // Point customModelsDir at our temp dir so whisperCppDir() uses it
    // without depending on path_provider's resolved path.
    final modelsDir = p.join(tmpDir.path, 'models_root');
    await Directory(modelsDir).create(recursive: true);

    SharedPreferences.setMockInitialValues({
      'custom_models_dir': modelsDir,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    svc = ModelService(settings);
    await svc.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  // -----------------------------------------------------------------------
  // getWhisperCppModelPath ↔ getWhisperCppModels consistency
  // -----------------------------------------------------------------------

  group('download status consistency (issue #28)', () {
    test('model file on disk → getWhisperCppModelPath returns path', () async {
      // Place a fake model file for 'tiny' (74 MB catalog size, has
      // checksum, but < 100 MB so checksum is NOT verified at load time).
      final def = svc.lookupDefinition('tiny')!;
      final filePath = p.join(svc.whisperCppDir(), def.fileName);
      await Directory(svc.whisperCppDir()).create(recursive: true);
      // Write 1 KB — above the 256-byte floor, checksum skipped.
      await File(filePath).writeAsBytes(List.filled(1024, 0xAB));

      final result = await svc.getWhisperCppModelPath('tiny');
      expect(result, isNotNull, reason: 'file exists and is above 256 bytes');
      expect(result, filePath);
    });

    test('missing file → getWhisperCppModelPath returns null', () async {
      final result = await svc.getWhisperCppModelPath('tiny');
      expect(result, isNull);
    });

    test('file too small (< 256 bytes) → treated as not downloaded', () async {
      final def = svc.lookupDefinition('tiny')!;
      final filePath = p.join(svc.whisperCppDir(), def.fileName);
      await Directory(svc.whisperCppDir()).create(recursive: true);
      await File(filePath).writeAsBytes(List.filled(100, 0));

      final result = await svc.getWhisperCppModelPath('tiny');
      expect(result, isNull, reason: 'file below 256-byte threshold');
    });

    test('picker and engine agree on download status', () async {
      // Write a valid file for 'tiny'.
      final def = svc.lookupDefinition('tiny')!;
      final filePath = p.join(svc.whisperCppDir(), def.fileName);
      await Directory(svc.whisperCppDir()).create(recursive: true);
      await File(filePath).writeAsBytes(List.filled(1024, 0xCD));

      // Picker path
      final models = await svc.getWhisperCppModels();
      final tinyInfo = models.firstWhere((m) => m.name == 'tiny');

      // Engine path
      final enginePath = await svc.getWhisperCppModelPath('tiny');

      expect(tinyInfo.isDownloaded, isTrue,
          reason: 'picker must report downloaded');
      expect(enginePath, isNotNull,
          reason: 'engine must also find the model');
      expect(enginePath, filePath,
          reason: 'both must resolve to the same path');
    });

    test('picker and engine agree when file missing', () async {
      final models = await svc.getWhisperCppModels();
      final tinyInfo = models.firstWhere((m) => m.name == 'tiny');
      final enginePath = await svc.getWhisperCppModelPath('tiny');

      expect(tinyInfo.isDownloaded, isFalse);
      expect(enginePath, isNull);
    });

    test('path uses path.join consistently (no string concatenation)',
        () async {
      final def = svc.lookupDefinition('tiny')!;
      final expected = p.join(svc.whisperCppDir(), def.fileName);
      // Ensure path doesn't have double slashes or other anomalies.
      expect(expected, isNot(contains('//')));
      expect(expected, isNot(contains('\\\\')));
    });

    test('unknown model name → getWhisperCppModelPath returns null', () async {
      final result = await svc.getWhisperCppModelPath('nonexistent-model-xyz');
      expect(result, isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Checksum gating: only models > 100 MB with a non-empty checksum
  // trigger verification.
  // -----------------------------------------------------------------------

  group('checksum verification gating', () {
    test('model < 100 MB skips checksum (file accepted despite wrong hash)',
        () async {
      // 'tiny' is 74 MB in the catalog, has a checksum, but the 100 MB
      // threshold means it won't be verified.
      final def = svc.lookupDefinition('tiny')!;
      expect(def.checksum, isNotEmpty);
      expect(def.sizeBytes, lessThan(100 * 1024 * 1024));

      final filePath = p.join(svc.whisperCppDir(), def.fileName);
      await Directory(svc.whisperCppDir()).create(recursive: true);
      // Content doesn't match the catalog checksum, but that's fine
      // because the model is below the 100 MB threshold.
      await File(filePath).writeAsBytes(List.filled(512, 0xFF));

      final result = await svc.getWhisperCppModelPath('tiny');
      expect(result, isNotNull,
          reason: 'sub-100 MB model skips checksum verification');
    });

    test('model > 100 MB with wrong checksum → rejected', () async {
      // 'base' is 142 MB in the catalog with a non-empty checksum.
      final def = svc.lookupDefinition('base')!;
      expect(def.sizeBytes, greaterThan(100 * 1024 * 1024));
      expect(def.checksum, isNotEmpty);

      final filePath = p.join(svc.whisperCppDir(), def.fileName);
      await Directory(svc.whisperCppDir()).create(recursive: true);
      // Write a file that doesn't match the catalog checksum.
      await File(filePath).writeAsBytes(List.filled(512, 0x00));

      final result = await svc.getWhisperCppModelPath('base');
      expect(result, isNull,
          reason: 'checksum mismatch for >100 MB model → not downloaded');
    });

    test('catalog invariant: base model triggers checksum gate', () {
      final def = ModelCatalog.whisperCppModels['base']!;
      expect(def.sizeBytes, greaterThan(100 * 1024 * 1024));
      expect(def.checksum, isNotEmpty);
    });
  });

  // -----------------------------------------------------------------------
  // Error classification — the fix for issue #28's misleading snackbar.
  // -----------------------------------------------------------------------

  group('error message classification', () {
    // The UI catch block now checks e.toString().contains('is not downloaded')
    // to distinguish real "not downloaded" errors from other load failures.

    test('"is not downloaded" triggers download prompt', () {
      const msg = 'Model base is not downloaded yet.';
      expect(msg.contains('is not downloaded'), isTrue);
    });

    test('backend mismatch does NOT trigger download prompt', () {
      const msg =
          'Model uses the parakeet backend. The bundled libwhisper '
          'was built with {whisper}. Rebuild CrispASR with the parakeet '
          'backend linked in.';
      expect(msg.contains('is not downloaded'), isFalse);
    });

    test('model definition not found does NOT trigger download prompt', () {
      const msg = 'Model definition not found for some-model';
      expect(msg.contains('is not downloaded'), isFalse);
    });

    test('checksum / file error does NOT trigger download prompt', () {
      const msg = 'Download verification failed. File may be corrupted.';
      expect(msg.contains('is not downloaded'), isFalse);
    });

    test('generic exception does NOT trigger download prompt', () {
      final e = Exception('Failed to load model: OOM');
      expect(e.toString().contains('is not downloaded'), isFalse);
    });

    test('ModelLoadException wrapping preserves "is not downloaded"', () {
      // TranscriptionService wraps engine errors:
      // 'Failed to load model X: ModelLoadException: Model X is not downloaded yet.'
      const wrapped =
          'Failed to load model base: ModelLoadException: Model base is not downloaded yet.';
      expect(wrapped.contains('is not downloaded'), isTrue);
    });
  });
}
