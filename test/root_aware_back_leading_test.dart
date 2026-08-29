// #35 — "There is no back button, anywhere! - you have to restart app."
//
// Arriving on a destination screen through `context.go(...)` replaces the
// whole navigation stack, so nothing is left to pop and the AppBar draws no
// leading widget at all. `rootAwareBackLeading` is the fallback: it hands the
// AppBar a "back to home" button exactly when Flutter would not have drawn a
// back button of its own, and `null` otherwise (a non-null `leading`
// *suppresses* the automatic back button, so returning null is what lets the
// normal behaviour through).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/l10n/generated/app_localizations_en.dart';
import 'package:crisper_weaver/widgets/root_aware_back_leading.dart';

void main() {
  // A Scaffold whose AppBar takes its leading straight from the helper, so
  // the AppBar really does see `null` and can supply its own back button.
  // The Builder puts the helper's context below the enclosing route.
  Widget screen(String title) => Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: rootAwareBackLeading(context),
            title: Text(title),
          ),
          body: const SizedBox.shrink(),
        ),
      );

  Future<GlobalKey<NavigatorState>> pumpApp(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: screen('Synthesize'),
    ));
    await tester.pumpAndSettle();
    return navigatorKey;
  }

  testWidgets('shows a home button when there is nothing to pop',
      (tester) async {
    await pumpApp(tester);

    expect(find.byType(RootHomeButton), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('yields to the normal back button on a pushed route',
      (tester) async {
    final navigatorKey = await pumpApp(tester);

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => screen('Pushed')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pushed'), findsOneWidget);
    // The helper returned null, so the AppBar supplied its own BackButton.
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(RootHomeButton), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
  });

  testWidgets('the home button carries a localized tooltip', (tester) async {
    await pumpApp(tester);

    final button = tester.widget<IconButton>(
      find.descendant(
        of: find.byType(RootHomeButton),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.tooltip, AppLocalizationsEn().navBackToHome);
    expect(button.tooltip, isNotEmpty);
  });

  testWidgets('the home button runs the supplied action', (tester) async {
    // The production default is `context.go('/')`; the override keeps this
    // test free of a GoRouter.
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: rootAwareBackLeading(
              context,
              onGoHome: () => pressed++,
            ),
            title: const Text('Synthesize'),
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump();
    expect(pressed, 1);
  });
}
