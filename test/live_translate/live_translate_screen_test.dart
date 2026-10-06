import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/screens/live_translate_screen.dart';
import 'package:crisper_weaver/services/live_translate/live_translate_config.dart';
import 'package:crisper_weaver/services/live_translate/live_translate_controller.dart';
import 'package:crisper_weaver/services/settings_service.dart';
import 'package:crisper_weaver/utils/ai_text_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A controller that never touches models or audio: it shows [initial].
class _FakeLive extends LiveTranslateController {
  _FakeLive(this.initial);
  final LiveTranslateState initial;

  @override
  LiveTranslateState build() {
    super.build();
    return initial;
  }

  @override
  Future<void> start({String? replayFile}) async {}

  @override
  Future<void> stop() async {}
}

Future<void> _pump(WidgetTester tester, LiveTranslateState state,
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(SettingsService(sp)),
      liveTranslateProvider.overrideWith(() => _FakeLive(state)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LiveTranslateScreen(),
    ),
  ));
  await tester.pump();
}

LiveUnit _unit(int key, String lang, String text, Map<String, String> tr) {
  final u = LiveUnit(
      key: key,
      lang: lang,
      text: text,
      targets: tr.keys.toList(),
      at: DateTime(2026));
  u.translations.addAll(tr);
  return u;
}

void main() {
  testWidgets('setup shows the routing table and a preset extends it',
      (tester) async {
    await _pump(tester, const LiveTranslateState());
    expect(find.text('Translation paths'), findsOneWidget);
    // de → en and en → de by default, as language badges.
    expect(find.text('Deutsch · DE'), findsOneWidget);
    expect(find.text('English · EN'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'de · en · fr'));
    await tester.pump();
    expect(find.text('Français · FR'), findsOneWidget,
        reason: 'the preset adds French as a spoken language');
  });

  testWidgets('board shows each sentence with its translations in colour',
      (tester) async {
    final state = LiveTranslateState(
      status: LiveStatus.running,
      startedAt: DateTime.now(),
      units: [
        _unit(0, 'de', 'Guten Morgen zusammen.', {'en': 'Good morning, everyone.'}),
        _unit(1, 'fr', 'Bonjour à tous.', {'de': 'Hallo zusammen.', 'en': 'Hello everyone.'}),
      ],
      tail: 'Wir beginnen',
      currentLang: 'de',
      drafts: const {'en': 'We begin'},
    );
    await _pump(tester, state, prefs: {
      'live_translate_config_v1':
          '{"routes":{"de":["en"],"en":["de"],"fr":["de","en"]},"fontSize":30}',
    });

    for (final t in [
      'Guten Morgen zusammen.',
      'Good morning, everyone.',
      'Bonjour à tous.',
      'Hallo zusammen.',
      'Hello everyone.',
      'Wir beginnen',
      'We begin',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // The English line is drawn in English's colour.
    final en = tester.widget<Text>(find.text('Good morning, everyone.'));
    expect(en.style?.color, LanguageColors.of('en', dark: true));
    expect(en.style?.fontSize, 30);
    // Art. 50(2): machine translations on screen carry the disclosure.
    expect(find.text(AiTextDisclosure.translation), findsOneWidget);
    // The sentence in progress is dimmed.
    final open = tester.widget<Text>(find.text('Wir beginnen'));
    expect(open.style?.fontStyle, FontStyle.italic);

    // L switches to columns: one header per language, same sentences.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(find.text('Français · FR'), findsWidgets);
    expect(find.text('Hello everyone.'), findsOneWidget);

    // + enlarges the text.
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pump();
    expect(tester.widget<Text>(find.text('Hello everyone.')).style?.fontSize, 34);

    // The language toggles sit dark on the dark bar, whatever the app's
    // (light) chip theme says — light chips made the colours unreadable.
    final chip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'English'));
    final fill = chip.color!.resolve({WidgetState.selected})!;
    expect(fill.computeLuminance(), lessThan(0.1));

    // Hiding French removes its column and its source lines.
    await tester.tap(find.widgetWithText(FilterChip, 'Français'));
    await tester.pump();
    expect(find.text('Bonjour à tous.'), findsNothing);
    expect(find.text('Hello everyone.'), findsOneWidget);
  });

  testWidgets('loading shows progress on the board', (tester) async {
    await _pump(tester, const LiveTranslateState(status: LiveStatus.loading));
    expect(find.text('Loading models…'), findsOneWidget);
  });

  testWidgets('a failed start is explained on the setup page',
      (tester) async {
    await _pump(
        tester,
        const LiveTranslateState(
            status: LiveStatus.error, message: 'No recogniser downloaded'));
    expect(find.text('No recogniser downloaded'), findsOneWidget);
    expect(find.text('Translation paths'), findsOneWidget);
  });
}
