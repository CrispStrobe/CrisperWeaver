// Issue #35 — the diarisation card's model / min / max pickers were
// dead UI: they lived in the widget's own State, exposed getters
// nobody called, and the transcribe path hardcoded `minSpeakers: null`.
//
// The card is now fully controlled: every change is reported upward,
// the screen stores the bounds in TranscriptionScreenState, and the
// transcribe / batch paths pass them into DiarizationService. These
// tests pin the seam — widget callback → provider state — because
// that is the link that was missing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/native/crispasr_import.dart' as crispasr;
import 'package:crisper_weaver/providers/transcription_screen_provider.dart';
import 'package:crisper_weaver/widgets/diarization_settings_widget.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// The method values the card's picker currently offers. DropdownButton
/// builds every item into an IndexedStack, so they're all in the tree.
List<crispasr.DiarizeMethod?> _offeredMethods(WidgetTester tester) => tester
    .widgetList<DropdownMenuItem<crispasr.DiarizeMethod>>(
        find.byType(DropdownMenuItem<crispasr.DiarizeMethod>))
    .map((i) => i.value)
    .toList();

void main() {
  group('TranscriptionScreenState speaker bounds', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });
    tearDown(() => container.dispose());

    test('default to null — "Auto", the diarizer estimates', () {
      final state = container.read(transcriptionScreenProvider);
      expect(state.minSpeakers, isNull);
      expect(state.maxSpeakers, isNull);
    });

    test('setters carry the values into state', () {
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setMinSpeakers(2);
      n.setMaxSpeakers(4);
      final state = container.read(transcriptionScreenProvider);
      expect(state.minSpeakers, 2);
      expect(state.maxSpeakers, 4);
    });

    test('"Auto" (null) is expressible — copyWith cannot swallow it', () {
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setMinSpeakers(3);
      n.setMinSpeakers(null);
      expect(container.read(transcriptionScreenProvider).minSpeakers, isNull);

      n.setMaxSpeakers(3);
      n.setMaxSpeakers(null);
      expect(container.read(transcriptionScreenProvider).maxSpeakers, isNull);
    });

    test('raising the minimum drags the maximum with it', () {
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setMaxSpeakers(2);
      n.setMinSpeakers(5);
      final state = container.read(transcriptionScreenProvider);
      expect(state.minSpeakers, 5);
      expect(state.maxSpeakers, 5);
    });

    test('lowering the maximum drags the minimum with it', () {
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setMinSpeakers(6);
      n.setMaxSpeakers(3);
      final state = container.read(transcriptionScreenProvider);
      expect(state.minSpeakers, 3);
      expect(state.maxSpeakers, 3);
    });

    test('bounds survive an unrelated copyWith', () {
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setMinSpeakers(2);
      n.setMaxSpeakers(4);
      n.setEnableDiarization(true);
      n.setLanguage('de');
      final state = container.read(transcriptionScreenProvider);
      expect(state.minSpeakers, 2);
      expect(state.maxSpeakers, 4);
      expect(state.enableDiarization, isTrue);
    });
  });

  group('DiarizationSettingsWidget wiring (#35)', () {
    testWidgets('speaker pickers report their changes upward', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(transcriptionScreenProvider.notifier);

      await tester.pumpWidget(_host(
        DiarizationSettingsWidget(
          enabled: true,
          onChanged: (_) {},
          onMinSpeakersChanged: n.setMinSpeakers,
          onMaxSpeakersChanged: n.setMaxSpeakers,
        ),
      ));

      final pickers = find.byType(DropdownButtonFormField<int?>);
      expect(pickers, findsNWidgets(2));

      // Min first, max second — the order they're built in.
      tester.widget<DropdownButtonFormField<int?>>(pickers.at(0)).onChanged!(2);
      tester.widget<DropdownButtonFormField<int?>>(pickers.at(1)).onChanged!(3);

      final state = container.read(transcriptionScreenProvider);
      expect(state.minSpeakers, 2);
      expect(state.maxSpeakers, 3);
    });

    testWidgets('the method picker reports its choice upward', (tester) async {
      crispasr.DiarizeMethod? picked;

      await tester.pumpWidget(_host(
        DiarizationSettingsWidget(
          enabled: true,
          onChanged: (_) {},
          onMethodChanged: (m) => picked = m,
        ),
      ));

      final picker =
          find.byType(DropdownButtonFormField<crispasr.DiarizeMethod>);
      expect(picker, findsOneWidget);
      tester
          .widget<DropdownButtonFormField<crispasr.DiarizeMethod>>(picker)
          .onChanged!(crispasr.DiarizeMethod.foxNose);

      expect(picked, crispasr.DiarizeMethod.foxNose);
    });

    testWidgets('methods whose GGUF is missing are marked, and the offered '
        'values always include the current one', (tester) async {
      await tester.pumpWidget(_host(
        DiarizationSettingsWidget(
          enabled: true,
          onChanged: (_) {},
          method: crispasr.DiarizeMethod.pyannote,
          onMethodChanged: (_) {},
          unavailableMethods: const {crispasr.DiarizeMethod.pyannote},
        ),
      ));

      final l = AppLocalizations.of(
          tester.element(find.byType(DiarizationSettingsWidget)));

      expect(find.textContaining(l.modelsNotDownloaded), findsWidgets);
      expect(_offeredMethods(tester),
          contains(crispasr.DiarizeMethod.pyannote));
    });

    testWidgets('a stereo-only method selected elsewhere stays selectable',
        (tester) async {
      // The card hides energy / xcorr on mono sources, but a value
      // picked in the expert picker must never fall out of the item
      // list — DropdownButtonFormField asserts on that.
      await tester.pumpWidget(_host(
        DiarizationSettingsWidget(
          enabled: true,
          onChanged: (_) {},
          method: crispasr.DiarizeMethod.xcorr,
          onMethodChanged: (_) {},
        ),
      ));

      expect(_offeredMethods(tester), contains(crispasr.DiarizeMethod.xcorr));
    });

    testWidgets('the bounds caveat only shows when a bound is set and the '
        'method does not consume it', (tester) async {
      // vad-turns + a bound → the note explains what the bound
      // actually reaches. Being honest about it is the point.
      await tester.pumpWidget(_host(
        DiarizationSettingsWidget(
          enabled: true,
          onChanged: (_) {},
          minSpeakers: 2,
          onMinSpeakersChanged: (_) {},
        ),
      ));
      final l = AppLocalizations.of(
          tester.element(find.byType(DiarizationSettingsWidget)));
      expect(find.text(l.diarizationSpeakerBoundsNote), findsOneWidget);

      // FoxNose consumes both bounds directly — no caveat.
      await tester.pumpWidget(_host(
        DiarizationSettingsWidget(
          enabled: true,
          onChanged: (_) {},
          method: crispasr.DiarizeMethod.foxNose,
          minSpeakers: 2,
          onMinSpeakersChanged: (_) {},
        ),
      ));
      expect(find.text(l.diarizationSpeakerBoundsNote), findsNothing);
    });
  });
}
