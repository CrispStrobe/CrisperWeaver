// Upgrade path from <= 0.10.x: model *names* that were renamed in the
// catalogue must keep resolving, and the ones a user persisted in
// settings must get rewritten to the current name exactly once.
//
// v0.11.0 renamed tiny/base/small-q5_0 -> *-q5_1, corrected the two
// Piper starter ids to their curated keys, and re-keyed the VibeVoice
// Emma voicepack. It also *deleted* five whisper quants outright
// (base-q4_0, small-q4_0, large-v3-q4_0, large-v3-q2_k, large-v3-q8_0).
// Renames get an alias; deletions deliberately do not — those have to
// stay unresolvable so the picker's "default isn't downloaded ->
// auto-switch" fallback takes over instead of silently loading some
// other model.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/services/baked_catalog_loader.dart';
import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';

/// Names dropped in v0.11.0 with no successor. Must never gain an alias.
const _deletedWithoutSuccessor = <String>[
  'base-q4_0',
  'small-q4_0',
  'large-v3-q4_0',
  'large-v3-q2_k',
  'large-v3-q8_0',
];

void main() {
  late Directory tmpDir;
  late String modelsDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await BakedCatalogLoader.load();
  });

  tearDownAll(() => BakedCatalogLoader.reset());

  setUp(() async {
    tmpDir =
        await Directory.systemTemp.createTemp('crisper_legacy_name_migration_');
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
    modelsDir = p.join(tmpDir.path, 'models_root');
    await Directory(modelsDir).create(recursive: true);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  /// A ModelService over a fresh SettingsService seeded with [prefs]
  /// (plus the temp models dir), *not* yet initialized.
  Future<(ModelService, SettingsService)> makeService(
      [Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues({
      'custom_models_dir': modelsDir,
      ...prefs,
    });
    final sp = await SharedPreferences.getInstance();
    final settings = SettingsService(sp);
    return (ModelService(settings), settings);
  }

  // ---------------------------------------------------------------------
  // The alias table itself
  // ---------------------------------------------------------------------

  group('legacyModelNameAliases integrity', () {
    test('every alias target resolves in the current catalogue', () async {
      final (svc, _) = await makeService();
      expect(ModelCatalog.legacyModelNameAliases, isNotEmpty);
      for (final entry in ModelCatalog.legacyModelNameAliases.entries) {
        final def = svc.lookupDefinition(entry.value);
        expect(def, isNotNull,
            reason: 'alias ${entry.key} -> ${entry.value} points at a name '
                'that no longer exists');
        expect(def!.name, entry.value);
      }
    });

    test('no target is itself an alias key (migration is idempotent)', () {
      const aliases = ModelCatalog.legacyModelNameAliases;
      for (final target in aliases.values) {
        expect(aliases.containsKey(target), isFalse,
            reason: '$target is both an alias target and an alias key — the '
                'settings migration would need a second pass');
      }
    });

    test('deleted-without-successor names are not aliased', () {
      for (final name in _deletedWithoutSuccessor) {
        expect(ModelCatalog.legacyModelNameAliases.containsKey(name), isFalse,
            reason: '$name was removed, not renamed — aliasing it would '
                'silently swap the user onto a different model');
      }
    });
  });

  // ---------------------------------------------------------------------
  // lookupDefinition heals a stale name on read
  // ---------------------------------------------------------------------

  group('lookupDefinition healing', () {
    test('every alias key resolves to the target file', () async {
      final (svc, _) = await makeService();
      for (final entry in ModelCatalog.legacyModelNameAliases.entries) {
        final healed = svc.lookupDefinition(entry.key);
        final target = svc.lookupDefinition(entry.value)!;
        expect(healed, isNotNull,
            reason: 'a stored "${entry.key}" must still resolve');
        // The two Piper stems also exist as generic *baked* rows, so
        // they resolve directly and never reach the alias retry. Either
        // way the download that comes back has to be the same file.
        expect(healed!.fileName, target.fileName,
            reason: '${entry.key} must resolve to the same bytes as '
                '${entry.value}');
      }
    });

    test('the three whisper q5_0 names resolve to their q5_1 rows', () async {
      final (svc, _) = await makeService();
      for (final size in ['tiny', 'base', 'small']) {
        final def = svc.lookupDefinition('$size-q5_0');
        expect(def, isNotNull, reason: '$size-q5_0 must heal');
        expect(def!.name, '$size-q5_1');
        expect(def.backend, 'whisper');
      }
    });

    test('a live/catalogued entry wins over the alias', () async {
      final (svc, _) = await makeService();
      // 'medium-q5_0' is a real, current catalogue row whose name looks
      // exactly like the aliased ones — it must not be rewritten.
      final def = svc.lookupDefinition('medium-q5_0');
      expect(def, isNotNull);
      expect(def!.name, 'medium-q5_0');
    });

    test('deleted-without-successor names stay null', () async {
      final (svc, _) = await makeService();
      for (final name in _deletedWithoutSuccessor) {
        expect(svc.lookupDefinition(name), isNull,
            reason: '$name must not resolve to anything');
      }
    });

    test('an unrelated unknown name stays null', () async {
      final (svc, _) = await makeService();
      expect(svc.lookupDefinition('nonexistent-model-xyz'), isNull);
    });
  });

  // ---------------------------------------------------------------------
  // The one-time settings rewrite in initialize()
  // ---------------------------------------------------------------------

  group('settings migration', () {
    test('rewrites all three stored names', () async {
      final (svc, settings) = await makeService({
        'default_model': 'base-q5_0',
        'default_tts_model': 'piper-en_GB-cori-medium-f16',
        'default_tts_voice': 'vibevoice-voice-emma',
      });
      await svc.initialize();

      expect(settings.defaultModel, 'base-q5_1');
      expect(settings.defaultTtsModel, 'piper-en-cori');
      expect(settings.defaultTtsVoice, 'vibevoice-voice-en-Emma_woman');
    });

    test('covers every alias key on the ASR setting', () async {
      for (final entry in ModelCatalog.legacyModelNameAliases.entries) {
        final (svc, settings) =
            await makeService({'default_model': entry.key});
        await svc.initialize();
        expect(settings.defaultModel, entry.value,
            reason: 'defaultModel=${entry.key} should become ${entry.value}');
      }
    });

    test('is idempotent — a second run changes nothing', () async {
      final (svc, settings) = await makeService({
        'default_model': 'small-q5_0',
        'default_tts_model': 'piper-de_DE-thorsten-medium-f16',
        'default_tts_voice': 'vibevoice-voice-emma',
      });
      await svc.initialize();
      final afterFirst = [
        settings.defaultModel,
        settings.defaultTtsModel,
        settings.defaultTtsVoice,
      ];

      // Same prefs store, a fresh service (simulates the next launch).
      final sp = await SharedPreferences.getInstance();
      final settings2 = SettingsService(sp);
      final svc2 = ModelService(settings2);
      await svc2.initialize();

      expect([
        settings2.defaultModel,
        settings2.defaultTtsModel,
        settings2.defaultTtsVoice,
      ], afterFirst);
      expect(afterFirst, [
        'small-q5_1',
        'piper-de-thorsten-medium',
        'vibevoice-voice-en-Emma_woman',
      ]);

      // And within one service, a second initialize() is a no-op.
      await svc.initialize();
      expect(settings.defaultModel, 'small-q5_1');
    });

    test('leaves a non-alias name untouched', () async {
      final (svc, settings) = await makeService({
        'default_model': 'medium-q5_0',
        'default_tts_model': 'piper-de-thorsten-high',
        'default_tts_voice': 'vibevoice-voice-en-Emma_woman',
      });
      await svc.initialize();

      expect(settings.defaultModel, 'medium-q5_0');
      expect(settings.defaultTtsModel, 'piper-de-thorsten-high');
      expect(settings.defaultTtsVoice, 'vibevoice-voice-en-Emma_woman');
    });

    test('leaves a deleted-without-successor name untouched', () async {
      final (svc, settings) =
          await makeService({'default_model': 'large-v3-q2_k'});
      await svc.initialize();
      // Nothing to migrate to — the dangling name survives and the
      // picker fallback (below) is what rescues the user.
      expect(settings.defaultModel, 'large-v3-q2_k');
    });
  });

  // ---------------------------------------------------------------------
  // A dangling defaultModel must degrade gracefully. This pins the
  // service-level facts transcription_screen's auto-switch depends on
  // (screen: "if the persisted default isn't in the downloaded set,
  // switch to a downloaded whisper model") without pumping a widget.
  // ---------------------------------------------------------------------

  group('dangling defaultModel fallback', () {
    /// Drop a plausible-looking file so the model counts as downloaded.
    Future<String> placeFile(ModelService svc, String fileName) async {
      final dir = svc.whisperCppDir();
      await Directory(dir).create(recursive: true);
      final path = p.join(dir, fileName);
      await File(path).writeAsBytes(List.filled(1024, 0xAB));
      return path;
    }

    test('resolves to no path instead of throwing', () async {
      final (svc, _) = await makeService({'default_model': 'large-v3-q2_k'});
      await svc.initialize();
      expect(await svc.getWhisperCppModelPath('large-v3-q2_k'), isNull);
    });

    test('picker offers a downloaded alternative to switch to', () async {
      final (svc, settings) =
          await makeService({'default_model': 'large-v3-q2_k'});
      await svc.initialize();
      await placeFile(svc, svc.lookupDefinition('tiny')!.fileName);

      final models = await svc.getWhisperCppModels();
      final downloaded =
          models.where((m) => m.isDownloaded).toList(growable: false);

      // Precondition for the screen's auto-switch branch.
      expect(downloaded, isNotEmpty);
      expect(downloaded.any((m) => m.name == settings.defaultModel), isFalse,
          reason: 'the dangling default must not look downloaded');
      // And the model it would land on.
      final whisperFirst = downloaded.firstWhere((m) => m.backend == 'whisper',
          orElse: () => downloaded.first);
      expect(whisperFirst.name, 'tiny');
    });

    test('an explicit download of a dangling name fails loudly', () async {
      final (svc, _) = await makeService();
      await svc.initialize();
      await expectLater(
        svc.downloadWhisperCppModel('large-v3-q2_k'),
        throwsA(isA<ModelException>()),
      );
    });

    test('a healed alias does resolve to a path once its file is there',
        () async {
      final (svc, settings) = await makeService({'default_model': 'base-q5_0'});
      await svc.initialize();
      expect(settings.defaultModel, 'base-q5_1');
      await placeFile(svc, svc.lookupDefinition('base-q5_1')!.fileName);

      // Both the migrated name and the legacy one land on the same file.
      final viaNew = await svc.getWhisperCppModelPath('base-q5_1');
      final viaOld = await svc.getWhisperCppModelPath('base-q5_0');
      expect(viaNew, isNotNull);
      expect(viaOld, viaNew);
    });
  });

  // ---------------------------------------------------------------------
  // Orphaned on-disk files. A <= 0.10.x user may still have
  // ggml-base-q5_0.bin — perfectly loadable whisper weights whose
  // catalogue row is gone. It is NOT renamed (q5_0 bytes != q5_1 bytes),
  // and nothing scans the models dir into the picker, so it is invisible
  // there. The Storage screen must still see it.
  // ---------------------------------------------------------------------

  group('orphaned on-disk model file', () {
    test('is left alone by the file-rename migration', () async {
      final (svc, _) = await makeService();
      final orphan = p.join(modelsDir, 'ggml-base-q5_0.bin');
      await File(orphan).writeAsBytes(List.filled(1024, 0x01));
      await svc.initialize();

      expect(await File(orphan).exists(), isTrue,
          reason: 'q5_0 bytes are not q5_1 bytes — renaming would corrupt '
              'the entry');
      expect(
          await File(p.join(modelsDir, 'ggml-base-q5_1.bin')).exists(), isFalse);
    });

    test('is counted by the Storage screen under "(other)"', () async {
      final (svc, _) = await makeService();
      await svc.initialize();
      final orphan = p.join(svc.whisperCppDir(), 'ggml-base-q5_0.bin');
      await Directory(svc.whisperCppDir()).create(recursive: true);
      await File(orphan).writeAsBytes(List.filled(2048, 0x01));

      final buckets = await svc.getStorageByBackend();
      final other = buckets.where((b) => b.backend == '(other)').toList();
      expect(other, hasLength(1),
          reason: 'an uncatalogued file must land in the (other) bucket');
      expect(other.single.fileCount, 1);
      expect(other.single.bytes, 2048);

      final info = await svc.getStorageInfo();
      expect(info.totalBytes, greaterThanOrEqualTo(2048));
    });

    test('is NOT surfaced by the model picker (known gap)', () async {
      // Documented behaviour, not an endorsement: _discoveredModels is
      // only ever filled from the HF probe / the CrispASR registry —
      // there is no local-directory scan — so an orphaned file has no
      // picker row and cannot be loaded or deleted from Model
      // Management. If a local-file scan is ever added, this expectation
      // is the one to flip.
      final (svc, _) = await makeService();
      await svc.initialize();
      await Directory(svc.whisperCppDir()).create(recursive: true);
      await File(p.join(svc.whisperCppDir(), 'ggml-base-q5_0.bin'))
          .writeAsBytes(List.filled(1024, 0x01));

      final models = await svc.getWhisperCppModels();
      expect(models.any((m) => m.name == 'base-q5_0'), isFalse);
      expect(models.any((m) => m.isDownloaded), isFalse,
          reason: 'nothing catalogued matches ggml-base-q5_0.bin');
    });
  });
}
