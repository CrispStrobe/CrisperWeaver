import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crisper_weaver/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const prefix = String.fromEnvironment('SHOT_PREFIX', defaultValue: 'shot');
  const shotDir = String.fromEnvironment('SHOT_DIR');
  const shotRatio = int.fromEnvironment('SHOT_RATIO', defaultValue: 2);

  Future<void> hold(WidgetTester tester, {int ms = 2200}) async {
    for (var t = 0; t < ms; t += 150) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> writeLayerPng(WidgetTester tester, String file) async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
      view.paintBounds,
      pixelRatio: shotRatio.toDouble(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    
    Directory dir;
    try {
      dir = Directory(shotDir)..createSync(recursive: true);
    } on FileSystemException {
      dir = Directory('${Directory.systemTemp.path}/cw-shots')
        ..createSync(recursive: true);
    }
    final f = File('${dir.path}/$file.png');
    await f.writeAsBytes(data.buffer.asUint8List());
    debugPrint('SHOT ${f.path} ${image.width}x${image.height}');
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await hold(tester);
    if (shotDir.isNotEmpty) {
      await writeLayerPng(tester, '${prefix}_$name');
    } else {
      try {
        await writeLayerPng(tester, '${prefix}_$name');
      } catch (_) {
        await binding.takeScreenshot('${prefix}_$name');
      }
    }
  }

  testWidgets('capture store screenshots', (tester) async {
    app.main([]);
    await hold(tester, ms: 2500);

    // 1) Transcription/Home screen
    await shot(tester, '01_home');

    // 2) Synthesize screen
    final synthIcon = find.byIcon(Icons.record_voice_over);
    if (synthIcon.evaluate().isNotEmpty) {
      await tester.tap(synthIcon.first, warnIfMissed: false);
      await hold(tester, ms: 1500);
      await shot(tester, '02_synthesize');
    }
    
    // 3) History screen
    final historyIcon = find.byIcon(Icons.history);
    if (historyIcon.evaluate().isNotEmpty) {
      await tester.tap(historyIcon.first, warnIfMissed: false);
      await hold(tester, ms: 1500);
      await shot(tester, '03_history');
    }

    // 4) Settings screen
    final settingsIcon = find.byIcon(Icons.settings);
    if (settingsIcon.evaluate().isNotEmpty) {
      await tester.tap(settingsIcon.first, warnIfMissed: false);
      await hold(tester, ms: 1500);
      await shot(tester, '04_settings');
    }
  });
}
