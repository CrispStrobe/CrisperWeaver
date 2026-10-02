import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisper_weaver/services/settings_service.dart';
import 'package:crisper_weaver/widgets/browser_model_safety_settings.dart';

void main() {
  testWidgets('GPU selection requires acknowledgement and rejection keeps CPU',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(await SharedPreferences.getInstance());
    await tester.pumpWidget(ProviderScope(
        overrides: [settingsServiceProvider.overrideWithValue(settings)],
        child: const MaterialApp(
            home: Scaffold(body: BrowserModelSafetySettings()))));
    expect(settings.browserExecutionProvider, 'wasm');
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try GPU (WebGPU)').last);
    await tester.pumpAndSettle();
    expect(find.text('GPU processing may crash or fail'), findsOneWidget);
    await tester.tap(find.text('Keep CPU processing'));
    await tester.pumpAndSettle();
    expect(settings.browserExecutionProvider, 'wasm');
    expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'wasm');
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try GPU (WebGPU)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand; try GPU'));
    await tester.pumpAndSettle();
    expect(settings.browserExecutionProvider, 'webgpu');
    expect(settings.browserGpuWarningAccepted, true);
    expect(settings.browserAllowExperimentalModels, false);
  });

  testWidgets('browser override requires its own acknowledged warning',
      (tester) async {
    SharedPreferences.setMockInitialValues({'experimental_features': true});
    final settings = SettingsService(await SharedPreferences.getInstance());
    await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(settings),
        ],
        child: const MaterialApp(
            home: Scaffold(body: BrowserModelSafetySettings()))));
    expect(settings.browserAllowExperimentalModels, false);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Browser models may crash or fail'), findsOneWidget);
    expect(settings.browserAllowExperimentalModels, false);
    await tester.tap(find.text('Keep filtering'));
    await tester.pumpAndSettle();
    expect(settings.browserAllowExperimentalModels, false);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand; show models'));
    await tester.pumpAndSettle();
    expect(settings.browserAllowExperimentalModels, true);
    expect(
        SettingsService(await SharedPreferences.getInstance())
            .browserAllowExperimentalModels,
        true);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(settings.browserAllowExperimentalModels, false);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
