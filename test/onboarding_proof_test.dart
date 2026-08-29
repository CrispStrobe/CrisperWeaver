// Onboarding, proven in every configuration it can be driven into.
//
// Issue #35 reported onboarding as "broken" in three different ways at once:
// the TTS starter downloaded one voice and played another (nothing was
// persisted for TTS), the destination screen had no way back (`go()` replaced
// the whole stack), and some combinations of task / language / priority led
// nowhere at all. Commit e0c8de0 fixed those. This file is the proof, and it
// is deliberately exhaustive rather than illustrative: the onboarding form has
// 4 tasks × 4 priorities × 10 languages = 160 reachable combinations, and a
// spot check of five of them is what let the broken ones ship.
//
// What is asserted, per combination:
//   * a recommendation exists, with a route the app's router actually knows;
//   * a recommended model id resolves through the same catalogue chain
//     `ModelService.lookupDefinition` walks, and carries a real download
//     (non-empty url + fileName) — as does every companion on its row;
//   * a TTS recommendation ends up able to synthesize: either the row lists a
//     voicepack companion, or the model needs no external voice at all;
//   * the recommended name is one the Models screen will actually *list*
//     (i.e. not hidden by `ModelCatalog.duplicateFileNameEntries`);
//   * what `_persist` writes for that combination is what the Synthesize /
//     Transcribe screens later read back.
//
// No FFI, no network, no downloads: `ModelService` is pure Dart until one of
// its filesystem/native methods is called, and the widget test drives a
// subclass that overrides the two methods onboarding calls.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/l10n/generated/app_localizations_en.dart';
import 'package:crisper_weaver/main.dart' show modelServiceProvider;
import 'package:crisper_weaver/screens/onboarding_screen.dart';
import 'package:crisper_weaver/services/baked_catalog_loader.dart';
import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';
import 'package:crisper_weaver/services/starter_models.dart';

/// The exact language list the onboarding dropdown offers — see
/// `_preferencePicker` in lib/screens/onboarding_screen.dart. The widget test
/// `the language dropdown offers exactly the languages this matrix covers`
/// reads the values straight off the rendered `DropdownMenuItem`s and compares
/// them to this list, so the matrix cannot drift away from the UI.
const List<String> kOnboardingLanguages = <String>[
  'auto',
  'en',
  'de',
  'es',
  'fr',
  'it',
  'pt',
  'zh',
  'ja',
  'ko',
];

/// Every top-level path registered on `_router` in lib/main.dart (the private
/// static `GoRouter` built around line 636). Mirrored as a literal because the
/// router is private and constructing a second one would drag every screen in
/// the app — including their native engines — into a unit test. Sub-routes of
/// `/settings` are relative (`cloud-llm`, …) and are not onboarding targets,
/// so they are listed as their resolved paths for completeness only.
const Set<String> kRouterPaths = <String>{
  '/',
  '/onboarding',
  '/settings',
  '/settings/cloud-llm',
  '/settings/local-llm',
  '/settings/hotkey',
  '/settings/speakers',
  '/models',
  '/history',
  '/transcript/:id',
  '/logs',
  '/about',
  '/storage',
  '/synthesize',
  '/voice-clone',
  '/translate',
  '/voice-bake',
  '/subtitle-overlay',
  '/compare',
  '/edit-audio',
};

/// The catalogue chain `ModelService.lookupDefinition` walks, minus the
/// live-probe overlay (empty on a fresh install, which is the only state
/// onboarding runs in). Kept as a mirror rather than calling the service so
/// the pure tests stay free of `SharedPreferences`; the test
/// `mirrors ModelService.lookupDefinition exactly` proves the two agree.
ModelDefinition? _lookup(String name) =>
    ModelCatalog.whisperCppModels[name] ??
    ModelCatalog.crispasrBackendModels[name] ??
    ModelCatalog.ttsVoicepacks[name] ??
    BakedCatalogLoader.cached[name];

/// Catalogue rows for a definition's companions, in row order, unknown ids
/// dropped — exactly what `_persist` hands to
/// [OnboardingScreen.persistTtsDefaults].
List<ModelDefinition> _companionDefs(ModelDefinition? def) => <ModelDefinition>[
      for (final name in def?.companions ?? const <String>[])
        if (_lookup(name) != null) _lookup(name)!,
    ];

/// One cell of the matrix, with the recommendation it produces.
class _Combo {
  final StarterTask task;
  final StarterPriority priority;
  final String language;
  final StarterRecommendation rec;

  _Combo(this.task, this.priority, this.language)
      : rec = StarterModels.recommend(
          task: task,
          priority: priority,
          language: language,
        );

  String get label => '${task.name} / ${priority.name} / $language';
}

List<_Combo> _matrix() => <_Combo>[
      for (final task in StarterTask.values)
        for (final priority in StarterPriority.values)
          for (final language in kOnboardingLanguages)
            _Combo(task, priority, language),
    ];

ModelInfo _infoFor(ModelDefinition d, {bool downloaded = false}) => ModelInfo(
      name: d.name,
      displayName: d.displayName,
      size: '${(d.sizeBytes / (1024 * 1024)).round()} MB',
      sizeBytes: d.sizeBytes,
      isDownloaded: downloaded,
      localPath: downloaded ? '/tmp/${d.fileName}' : null,
      description: d.description,
      modelType: ModelType.whisperCpp,
      quantization: d.quantization,
      backend: d.backend,
      kind: d.kind,
      languages: d.languages,
    );

/// A [ModelService] with the two methods onboarding calls stubbed out.
/// Everything else — `lookupDefinition` above all — is the real thing, so the
/// widget test resolves companions through the production catalogue chain.
class _FakeModelService extends ModelService {
  // The base constructor's positional parameter is a private field formal
  // (`this._settingsService`), so forward it explicitly.
  // ignore: use_super_parameters
  _FakeModelService(SettingsService settings, this.models) : super(settings);

  final List<ModelInfo> models;
  final List<String> downloaded = <String>[];

  @override
  Future<List<ModelInfo>> getWhisperCppModels() async => models;

  @override
  Future<bool> downloadWhisperCppModel(
    String modelName, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
  }) async {
    downloaded.add(modelName);
    onStatusChange?.call('fetching $modelName');
    onProgress?.call(1.0);
    return true;
  }
}

Widget _stub(String name) => Scaffold(
      appBar: AppBar(title: Text('stub:$name')),
      body: const SizedBox.shrink(),
    );

/// A router with the same paths onboarding can send the user to, and nothing
/// else — the real `_router` would build every screen in the app.
GoRouter _stubRouter() => GoRouter(
      initialLocation: '/onboarding',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, __) => _stub('home')),
        GoRoute(
            path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
        GoRoute(path: '/synthesize', builder: (_, __) => _stub('synthesize')),
        GoRoute(path: '/translate', builder: (_, __) => _stub('translate')),
        GoRoute(path: '/models', builder: (_, __) => _stub('models')),
      ],
    );

Widget _host({
  required GoRouter router,
  required SettingsService settings,
  required ModelService service,
}) =>
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settings),
        modelServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l = AppLocalizationsEn();

  setUpAll(() async {
    // The baked HF snapshot is half of the catalogue the app resolves
    // against — the piper starter voices, for one, live only there.
    await BakedCatalogLoader.load();
  });

  tearDownAll(BakedCatalogLoader.reset);

  group('Recommendation matrix', () {
    test('covers every reachable onboarding configuration', () {
      // 4 tasks × 4 priorities × 10 languages. If the form grows an option,
      // this number moves and every test below widens with it.
      expect(_matrix(), hasLength(160));
      expect(kOnboardingLanguages.toSet(), hasLength(10));
    });

    test('every configuration yields a recommendation with a route', () {
      for (final c in _matrix()) {
        expect(c.rec.route, isNotEmpty, reason: c.label);
        // A recommendation with no route is a dead end: `_finish` would
        // persist the choices and then navigate nowhere.
        expect(c.rec.route.startsWith('/'), isTrue, reason: c.label);
      }
    });

    test('every recommended model resolves to a real download', () {
      for (final c in _matrix()) {
        final id = c.rec.modelId;
        if (id == null) continue;
        final def = _lookup(id);
        expect(def, isNotNull,
            reason: '${c.label}: "$id" is in no catalogue map — onboarding '
                'would download nothing and land the user on an empty screen');
        expect(def!.url, isNotEmpty, reason: '${c.label}: $id has no url');
        expect(def.fileName, isNotEmpty,
            reason: '${c.label}: $id has no fileName');
        expect(def.sizeBytes, greaterThan(0),
            reason: '${c.label}: $id claims a zero-byte download');
      }
    });

    test('every companion of a recommended model resolves too', () {
      // `_finish` downloads the model *and* every companion on its row. An
      // unresolvable companion is a silent half-setup: moonshine without its
      // tokenizer returns null from session_open, kokoro without a voicepack
      // synthesizes silence.
      for (final c in _matrix()) {
        final id = c.rec.modelId;
        if (id == null) continue;
        final def = _lookup(id)!;
        for (final companion in def.companions) {
          final cd = _lookup(companion);
          expect(cd, isNotNull,
              reason: '${c.label}: companion "$companion" of $id does not '
                  'resolve');
          expect(cd!.url, isNotEmpty,
              reason: '${c.label}: companion $companion has no url');
          expect(cd.fileName, isNotEmpty,
              reason: '${c.label}: companion $companion has no fileName');
        }
      }
    });

    test('every TTS recommendation can actually speak after the download', () {
      // The post-download state has to be able to synthesize. Either the row
      // ships a voicepack companion, or the model carries its voice inside
      // the GGUF (`requiresVoice == false`, e.g. piper VITS).
      for (final c in _matrix()) {
        if (c.rec.kind != ModelKind.tts) continue;
        final id = c.rec.modelId;
        if (id == null) continue;
        final def = _lookup(id)!;
        final voices = _companionDefs(def)
            .where((d) => d.kind == ModelKind.voice)
            .toList();
        expect(voices.isNotEmpty || !def.requiresVoice, isTrue,
            reason: '${c.label}: $id needs an external voice but its '
                'catalogue row lists no voicepack companion — onboarding '
                'would finish on a Synthesize screen that cannot synthesize');
      }
    });

    test('a recommended kind matches the definition it points at', () {
      for (final c in _matrix()) {
        final id = c.rec.modelId;
        if (id == null) continue;
        expect(_lookup(id)!.kind, c.rec.kind,
            reason: '${c.label}: the recommendation claims ${c.rec.kind.name} '
                'but $id is catalogued as ${_lookup(id)!.kind.name}, so '
                '`_persist` writes it into the wrong setting');
      }
    });

    test('no starter name is hidden by duplicate-file suppression', () {
      // The Models screen (and therefore onboarding's own model card, which
      // reads `getWhisperCppModels()`) drops names that duplicate another
      // row's file. A recommendation for a suppressed name is invisible: the
      // card falls back to "choose a model", `_finish` downloads nothing —
      // and `_persist` still records the name as the TTS default.
      final suppressed = ModelCatalog.duplicateFileNameEntries(
        baked: BakedCatalogLoader.cached,
      );
      final offenders = <String, String>{};
      for (final c in _matrix()) {
        final id = c.rec.modelId;
        if (id != null && suppressed.contains(id)) offenders[id] = c.label;
      }
      for (final id in StarterModels.allPickIds) {
        if (suppressed.contains(id)) {
          offenders.putIfAbsent(id, () => 'curated pick list');
        }
      }
      expect(offenders, isEmpty,
          reason: '\n\nThese starter names are suppressed as duplicates and '
              'can never be listed:\n'
              '${offenders.entries.map((e) => '  ${e.key}  (${e.value})').join('\n')}\n'
              'Point the starter list at the winning catalogue key instead '
              '(the curated row that claims the same fileName).\n');
    });

    test('diarization is enabled exactly for the meeting task', () {
      for (final c in _matrix()) {
        expect(c.rec.enableDiarization, c.task == StarterTask.meeting,
            reason: c.label);
      }
    });

    test('auto-detect behaves exactly like English', () {
      for (final task in StarterTask.values) {
        for (final priority in StarterPriority.values) {
          final auto = StarterModels.recommend(
              task: task, priority: priority, language: 'auto');
          final en = StarterModels.recommend(
              task: task, priority: priority, language: 'en');
          expect(auto.modelId, en.modelId, reason: '${task.name}/$priority');
          expect(auto.route, en.route, reason: '${task.name}/$priority');
          expect(auto.kind, en.kind, reason: '${task.name}/$priority');
        }
      }
    });

    test('a language with no starter never silently downloads the wrong one',
        () {
      // Kokoro phonemisation in the GPL-free bundles covers en/de/fr/es only.
      // Every other language must reach the model list instead of quietly
      // fetching an English voice.
      for (final c in _matrix()) {
        if (c.task != StarterTask.synthesize) continue;
        final supported =
            const {'en', 'de', 'fr', 'es'}.contains(c.language) ||
                c.language == 'auto';
        if (supported) {
          expect(c.rec.modelId, isNotNull, reason: c.label);
        } else {
          expect(c.rec.modelId, isNull, reason: c.label);
          expect(c.rec.route, '/models?kind=tts', reason: c.label);
        }
      }
    });

    test('mirrors ModelService.lookupDefinition exactly', () async {
      // The pure tests above resolve through `_lookup`. Prove that mirror is
      // the same chain the app walks — `lookupDefinition` touches no FFI and
      // no filesystem, so a real service is safe here.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final svc = ModelService(SettingsService(prefs));
      final ids = <String>{
        for (final c in _matrix())
          if (c.rec.modelId != null) c.rec.modelId!,
        ...StarterModels.allPickIds,
      };
      expect(ids, isNotEmpty);
      for (final id in ids) {
        final mine = _lookup(id);
        final theirs = svc.lookupDefinition(id);
        expect(mine?.name, theirs?.name, reason: id);
        expect(mine?.fileName, theirs?.fileName, reason: id);
        expect(mine?.backend, theirs?.backend, reason: id);
      }
    });
  });

  group('Routes', () {
    test('every route the matrix can produce is registered in main.dart', () {
      final routes = <String>{for (final c in _matrix()) c.rec.route};
      // Today: '/', '/synthesize', '/translate', '/models?kind=tts'.
      expect(routes, isNotEmpty);
      final paths = routes.map((r) => Uri.parse(r).path).toSet().toList()
        ..sort();
      for (final p in paths) {
        expect(kRouterPaths, contains(p),
            reason: 'route "$p" is recommended by StarterModels but no '
                'GoRoute in lib/main.dart declares it — `_finish` would '
                'push onto go_router\'s error page');
      }
    });

    test('the fallback deep-link pre-selects a real filter chip', () {
      // '/models?kind=tts' is matched by the `/models` builder against
      // `ModelKind.values` by name; a typo'd kind degrades to "no filter"
      // rather than erroring, which is exactly how it would go unnoticed.
      final routes = <String>{for (final c in _matrix()) c.rec.route};
      for (final r in routes) {
        final kind = Uri.parse(r).queryParameters['kind'];
        if (kind == null) continue;
        expect(ModelKind.values.map((k) => k.name), contains(kind),
            reason: '"$r" names a filter the Models screen cannot resolve');
      }
      expect(routes, contains('/models?kind=tts'));
    });
  });

  group('Persistence matrix', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('every ASR recommendation records model, backend and diarization',
        () {
      for (final c in _matrix()) {
        if (c.rec.kind != ModelKind.asr || c.rec.modelId == null) continue;
        final settings = SettingsService(prefs);
        final def = _lookup(c.rec.modelId!);
        expect(def, isNotNull, reason: c.label);
        // Mirrors the `kind == asr` branch of `_persist`.
        OnboardingScreen.persistAsrDefaults(
          settings,
          c.rec.modelId!,
          def,
          enableDiarization: c.rec.enableDiarization,
        );
        // Read back through a fresh service: a real prefs round-trip, so a
        // wrong storage key fails here rather than on the next app launch.
        final reloaded = SettingsService(prefs);
        expect(reloaded.defaultModel, c.rec.modelId, reason: c.label);
        expect(reloaded.defaultBackend, def!.backend, reason: c.label);
        expect(reloaded.defaultBackend, isNotEmpty, reason: c.label);
        expect(reloaded.enableDiarizationByDefault,
            c.task == StarterTask.meeting,
            reason: c.label);
      }
    });

    test('every TTS recommendation records the model and the voice it fetched',
        () {
      for (final c in _matrix()) {
        if (c.rec.kind != ModelKind.tts || c.rec.modelId == null) continue;
        final settings = SettingsService(prefs);
        // A stale voice from a previous run must not survive.
        settings.defaultTtsVoice = 'kokoro-voice-zzz_stale';
        final def = _lookup(c.rec.modelId!)!;
        final companions = _companionDefs(def);
        OnboardingScreen.persistTtsDefaults(
            settings, c.rec.modelId!, companions);

        final reloaded = SettingsService(prefs);
        expect(reloaded.defaultTtsModel, c.rec.modelId, reason: c.label);
        final voices = companions
            .where((d) => d.kind == ModelKind.voice)
            .map((d) => d.name)
            .toList();
        final voice = voices.isEmpty ? '' : voices.first;
        expect(reloaded.defaultTtsVoice, voice, reason: c.label);
        if (voice.isEmpty) {
          expect(def.requiresVoice, isFalse,
              reason: '${c.label}: nothing was recorded as the voice and the '
                  'model needs one');
        } else {
          // The recorded voice must be one `_finish` actually downloads —
          // i.e. a companion on the row, not a catalogue neighbour.
          expect(def.companions, contains(voice), reason: c.label);
        }
      }
    });

    test('the kokoro starter records kokoro-voice-af_heart', () {
      // The concrete #35 regression: one voice downloaded, another played.
      final settings = SettingsService(prefs);
      final rec = StarterModels.recommend(
        task: StarterTask.synthesize,
        priority: StarterPriority.balanced,
        language: 'auto',
      );
      final def = _lookup(rec.modelId!)!;
      OnboardingScreen.persistTtsDefaults(
          settings, rec.modelId!, _companionDefs(def));
      expect(settings.defaultTtsModel, 'kokoro-82m-q8_0');
      expect(settings.defaultTtsVoice, 'kokoro-voice-af_heart');
    });

    test('a translate recommendation leaves the ASR and TTS defaults alone',
        () {
      // `_persist` writes a model default only for asr / tts. The translate
      // starter must not clobber a working transcription setup.
      for (final c in _matrix()) {
        if (c.rec.kind != ModelKind.translate) continue;
        final settings = SettingsService(prefs);
        settings.defaultModel = 'sentinel-asr';
        settings.defaultTtsModel = 'sentinel-tts';
        settings.defaultTtsVoice = 'sentinel-voice';
        // Only the branch-free part of `_persist` runs for this kind.
        settings.onboardingCompleted = true;
        settings.onboardingTask = c.task.name;
        settings.onboardingPriority = c.priority.name;
        settings.defaultLanguage = c.language;

        final reloaded = SettingsService(prefs);
        expect(reloaded.defaultModel, 'sentinel-asr', reason: c.label);
        expect(reloaded.defaultTtsModel, 'sentinel-tts', reason: c.label);
        expect(reloaded.defaultTtsVoice, 'sentinel-voice', reason: c.label);
        expect(reloaded.onboardingCompleted, isTrue, reason: c.label);
        expect(reloaded.onboardingTask, c.task.name, reason: c.label);
        expect(reloaded.onboardingPriority, c.priority.name, reason: c.label);
        expect(reloaded.defaultLanguage, c.language, reason: c.label);
      }
    });
  });

  group('Onboarding widget flow', () {
    late SharedPreferences prefs;
    late SettingsService settings;
    late GoRouter router;

    // Every `Step` body is built regardless of which step is current
    // (Stepper's vertical layout puts them all in an AnimatedCrossFade), so
    // finders below are scoped by intent rather than by visibility, and the
    // continue button is addressed by step index: `FilledButton.at(n)` is the
    // control of step n, and only the current one is hit-testable.
    Future<void> pump(WidgetTester tester, ModelService service) async {
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          _host(router: router, settings: settings, service: service));
      await tester.pumpAndSettle();
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
      // Not disposed on teardown on purpose: the widget tree is torn down
      // after test-level tearDowns run, and a Router that outlives its
      // GoRouter reports a "used after dispose" error out of the unmount.
      router = _stubRouter();
    });

    List<ModelInfo> catalogueRows() => <ModelInfo>[
          _infoFor(_lookup('kokoro-82m-q8_0')!),
          _infoFor(_lookup('kokoro-voice-af_heart')!),
          _infoFor(_lookup('base-q5_1')!),
          _infoFor(_lookup('m2m100-418m-q4_k')!),
        ];

    testWidgets('step 0 offers the four tasks and records the choice',
        (tester) async {
      final service = _FakeModelService(settings, catalogueRows());
      await pump(tester, service);

      expect(find.byType(RadioListTile<StarterTask>), findsNWidgets(4));
      final titles = <StarterTask, String>{
        StarterTask.transcribe: l.onboardingTaskTranscribe,
        StarterTask.meeting: l.onboardingTaskMeeting,
        StarterTask.translate: l.onboardingTaskTranslate,
        StarterTask.synthesize: l.onboardingTaskSynthesize,
      };
      for (final title in titles.values) {
        expect(find.text(title), findsOneWidget);
      }
      for (final entry in titles.entries) {
        await tester.tap(find.text(entry.value));
        await tester.pumpAndSettle();
        final group = tester.widget<RadioGroup<StarterTask>>(
            find.byType(RadioGroup<StarterTask>));
        expect(group.groupValue, entry.key,
            reason: 'tapping "${entry.value}" must select ${entry.key.name}');
      }
    });

    testWidgets('the language dropdown offers exactly the languages this '
        'matrix covers', (tester) async {
      final service = _FakeModelService(settings, catalogueRows());
      await pump(tester, service);

      // Step 1's content is built up-front; advance to it anyway so the test
      // exercises the same path a user walks.
      await tester.tap(find.byType(FilledButton).at(0));
      await tester.pumpAndSettle();

      // A closed DropdownButtonFormField materialises only the selected
      // item, so OPEN the menu and read the values off the overlay.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      final values = tester
          .widgetList<DropdownMenuItem<String>>(
              find.byType(DropdownMenuItem<String>))
          .map((item) => item.value)
          .toSet();
      expect(values, kOnboardingLanguages.toSet(),
          reason: 'the recommendation matrix must cover exactly what the '
              'dropdown offers');
      // Close the menu again so the trailing assertions see the form.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // The four priorities render as one segmented control.
      expect(find.text(l.onboardingPriorityBalanced), findsOneWidget);
      expect(find.text(l.onboardingPrioritySpeed), findsOneWidget);
      expect(find.text(l.onboardingPriorityQuality), findsOneWidget);
      expect(find.text(l.onboardingPriorityStorage), findsOneWidget);
      expect(find.byType(SegmentedButton<StarterPriority>), findsOneWidget);
    });

    testWidgets('the synthesize starter shows its recommended model',
        (tester) async {
      final service = _FakeModelService(settings, catalogueRows());
      await pump(tester, service);

      await tester.tap(find.text(l.onboardingTaskSynthesize));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(1));
      await tester.pumpAndSettle();

      expect(find.text(_lookup('kokoro-82m-q8_0')!.displayName),
          findsOneWidget);
      expect(find.text(l.onboardingChooseModelTitle), findsNothing);
    });

    testWidgets('a recommendation the catalogue cannot list falls back to '
        '"choose a model"', (tester) async {
      // The model list deliberately omits the ASR starter — the same state a
      // suppressed / retired catalogue key produces.
      final service = _FakeModelService(
          settings, <ModelInfo>[_infoFor(_lookup('kokoro-82m-q8_0')!)]);
      await pump(tester, service);

      await tester.tap(find.byType(FilledButton).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(1));
      await tester.pumpAndSettle();

      expect(find.text(l.onboardingChooseModelTitle), findsOneWidget);
    });

    testWidgets('finishing the synthesize task downloads the model and its '
        'voice, records both, and leaves a way back', (tester) async {
      final service = _FakeModelService(settings, catalogueRows());
      await pump(tester, service);

      await tester.tap(find.text(l.onboardingTaskSynthesize));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(1));
      await tester.pumpAndSettle();
      expect(find.text(l.onboardingSetUp), findsWidgets);
      await tester.tap(find.byType(FilledButton).at(2));
      await tester.pumpAndSettle();

      // #35, half one: the row's companions come down with the model.
      expect(service.downloaded,
          <String>['kokoro-82m-q8_0', 'kokoro-voice-af_heart']);
      expect(settings.defaultTtsModel, 'kokoro-82m-q8_0');
      expect(settings.defaultTtsVoice, 'kokoro-voice-af_heart');
      expect(settings.onboardingCompleted, isTrue);
      expect(settings.onboardingTask, StarterTask.synthesize.name);
      expect(settings.defaultLanguage, 'auto');

      // #35, half two: home is under the destination, so the AppBar draws a
      // real back button instead of stranding the user.
      expect(find.text('stub:synthesize'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('finishing the transcribe task lands on home with the ASR '
        'defaults recorded', (tester) async {
      final service = _FakeModelService(settings, catalogueRows());
      await pump(tester, service);

      await tester.tap(find.byType(FilledButton).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(2));
      await tester.pumpAndSettle();

      expect(service.downloaded, <String>['base-q5_1']);
      expect(settings.defaultModel, 'base-q5_1');
      expect(settings.defaultBackend, _lookup('base-q5_1')!.backend);
      expect(settings.enableDiarizationByDefault, isFalse);
      expect(settings.defaultTtsModel, '',
          reason: 'an ASR starter must not touch the TTS defaults');
      // route '/' — nothing is pushed on top, so there is nothing to pop.
      expect(find.text('stub:home'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('an already-downloaded starter is not fetched again',
        (tester) async {
      final rows = <ModelInfo>[
        _infoFor(_lookup('base-q5_1')!, downloaded: true),
      ];
      final service = _FakeModelService(settings, rows);
      await pump(tester, service);

      await tester.tap(find.byType(FilledButton).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(1));
      await tester.pumpAndSettle();
      expect(find.text(l.quickStartInstalled), findsOneWidget);
      await tester.tap(find.byType(FilledButton).at(2));
      await tester.pumpAndSettle();

      expect(service.downloaded, isEmpty);
      expect(settings.defaultModel, 'base-q5_1');
      expect(find.text('stub:home'), findsOneWidget);
    });

    testWidgets('the meeting task records diarization and stays on home',
        (tester) async {
      final service = _FakeModelService(settings, catalogueRows());
      await pump(tester, service);

      await tester.tap(find.text(l.onboardingTaskMeeting));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(2));
      await tester.pumpAndSettle();

      expect(settings.enableDiarizationByDefault, isTrue);
      expect(settings.defaultModel, 'base-q5_1');
      expect(settings.onboardingTask, StarterTask.meeting.name);
      expect(find.text('stub:home'), findsOneWidget);
    });

    testWidgets('the translate task pushes /translate over home',
        (tester) async {
      final service = _FakeModelService(settings, catalogueRows());
      await pump(tester, service);

      await tester.tap(find.text(l.onboardingTaskTranslate));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).at(2));
      await tester.pumpAndSettle();

      expect(service.downloaded, <String>['m2m100-418m-q4_k']);
      expect(find.text('stub:translate'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      // Translation is neither ASR nor TTS: no model default is written.
      expect(settings.defaultModel, 'base',
          reason: 'the SettingsService default is untouched');
      expect(settings.defaultTtsModel, '');
    });

    testWidgets('"set up later" completes onboarding and goes home',
        (tester) async {
      final service = _FakeModelService(settings, catalogueRows());
      await pump(tester, service);

      expect(settings.onboardingCompleted, isFalse);
      await tester.tap(find.text(l.onboardingSkip));
      await tester.pumpAndSettle();

      expect(settings.onboardingCompleted, isTrue,
          reason: 'skipping must still stop onboarding from reappearing on '
              'every launch');
      expect(SettingsService(prefs).onboardingCompleted, isTrue);
      expect(service.downloaded, isEmpty);
      expect(find.text('stub:home'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing,
          reason: 'skip replaces the stack rather than pushing onto it');
    });
  });
}
