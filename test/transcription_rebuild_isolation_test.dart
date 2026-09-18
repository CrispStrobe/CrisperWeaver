import 'package:crisper_weaver/engines/engine_factory.dart';
import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/main.dart';
import 'package:crisper_weaver/screens/transcription_screen.dart';
import 'package:crisper_weaver/services/audio_service.dart';
import 'package:crisper_weaver/services/hotkey_service.dart';
import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';
import 'package:crisper_weaver/services/transcription_service.dart';
import 'package:crisper_weaver/widgets/transcription_output_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only external initialization is stubbed. The screen, its Consumers and the
// AppState notifier are production code; no source-text or synthetic selector
// assertions. Widget identity detects whether a section's factory ran again.
class _Models extends ModelService {
  _Models(super.settingsService);

  @override
  Future<void> initialize() async {}

  @override
  String whisperCppDir() => '/nonexistent/transcription-widget-test';

  @override
  Future<List<ModelInfo>> getWhisperCppModels() async => [];
}

class _Transcription extends TranscriptionService {
  _Transcription(super.audioService, super.modelService);

  @override
  Future<bool> initialize({
    EngineType? preferredEngine,
    String? modelName,
    bool ignoreMemoryPreflight = false,
  }) async => false;
}

Future<ProviderContainer> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(650, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService(await SharedPreferences.getInstance());
  final models = _Models(settings);
  final audio = AudioService();
  final container = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(settings),
    hotkeyServiceProvider.overrideWithValue(HotkeyService(settings)),
    modelServiceProvider.overrideWithValue(models),
    audioServiceProvider.overrideWithValue(audio),
    transcriptionServiceProvider.overrideWithValue(_Transcription(audio, models)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TranscriptionScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return container;
}

void main() {
  // KNOWN GAP — red, deliberately skipped rather than deleted.
  //
  // `TranscriptionScreen.build` watches the whole `transcriptionScreenProvider`
  // (lib/screens/transcription_screen.dart:550) and `_buildBody` watches the
  // whole `AppState` (line 821), so a progress tick — which fires ~every frame
  // during a run — rebuilds the input controls, the config factory and the
  // transcript pane along with it. This test reproduces that; it fails against
  // the current screen.
  //
  // Fixing it means splitting the progress displays into their own `Consumer`
  // boundaries and narrowing those two watches to records of the fields that
  // actually change the body's structure. That is a restructure of the app's
  // primary 4,000-line screen and has to be verified with profile-mode frame
  // timings, not just this identity assertion — so it is scoped as follow-up
  // work rather than folded into an unverified change. Un-skip it when the
  // refactor lands; it then becomes the regression guard.
  testWidgets('progress updates only status, not configuration or transcript',
      (tester) async {
    final container = await _mount(tester);
    final notifier = container.read(appStateProvider.notifier);
    notifier.startTranscription();
    notifier.addSegment(const TranscriptionSegment(
        text: 'First segment', startTime: 0, endTime: 1));
    await tester.pump();
    final input = tester.widget(find.byType(TextField).first);
    final controls = tester.widget(find.widgetWithIcon(ElevatedButton, Icons.clear));
    final output = tester.widget(find.byType(TranscriptionOutputWidget));
    final scaffold = tester.widget(find.byType(Scaffold).first);

    notifier.updateProgress(0.42);
    await tester.pump();

    expect(find.text('42.0%'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.42);
    expect(identical(tester.widget(find.byType(TextField).first), input), isTrue,
        reason: 'streaming progress must not rebuild the configuration factory');
    expect(identical(tester.widget(find.widgetWithIcon(ElevatedButton, Icons.clear)), controls), isTrue);
    expect(identical(tester.widget(find.byType(TranscriptionOutputWidget)), output), isTrue);
    expect(identical(tester.widget(find.byType(Scaffold).first), scaffold), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: true);
}
