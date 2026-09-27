// Store screenshots, captured by .github/workflows/screenshots.yml.
//
// The app is seeded before it starts (onboarding done, locale chosen, a few
// realistic transcripts in History) so every shot shows the app in use rather
// than a fresh install. Each shot is rendered off the root layer at an exact
// App Store size, forced through `tester.view`, so the output does not depend
// on which simulator model the runner happens to have:
//
//   SHOT_DEVICE=iphone  1320 x 2868  (6.9" display, 440 x 956 @3x)
//   SHOT_DEVICE=ipad    2064 x 2752  (13" display, 1032 x 1376 @2x)
//   SHOT_DEVICE=mac     2880 x 1800  (1440 x 900 @2x)
//
// PNGs go to `~/cw-shots/` on the simulator's host, else `<system temp>/cw-shots/`.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisper_weaver/main.dart' as app;
import 'package:crisper_weaver/services/ios_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = String.fromEnvironment('SHOT_DEVICE', defaultValue: 'iphone');
const _locale = String.fromEnvironment('SHOT_LOCALE', defaultValue: 'en');
const _prefix = String.fromEnvironment('SHOT_PREFIX', defaultValue: 'shot');

({Size logical, double ratio}) get _target => switch (_device) {
      'ipad' => (logical: const Size(1032, 1376), ratio: 2.0),
      'mac' => (logical: const Size(1440, 900), ratio: 2.0),
      _ => (logical: const Size(440, 956), ratio: 3.0),
    };

bool get _de => _locale == 'de';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> hold(WidgetTester tester, {int ms = 2000}) async {
    for (var t = 0; t < ms; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await hold(tester);
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    // The root layer already carries the device-pixel-ratio transform, so
    // its bounds are physical pixels and it renders at ratio 1.
    final t = _target;
    final image = await tester.runAsync(() => layer.toImage(
          Offset.zero & (t.logical * t.ratio),
        ));
    final data = await tester
        .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    image!.dispose();
    // A simulator app can write to the host, which outlives the uninstall
    // `flutter test` does when it finishes (that wipes the app's container).
    final host = Platform.environment['SIMULATOR_HOST_HOME'];
    final dir = Directory(p.join(host ?? Directory.systemTemp.path, 'cw-shots'))
      ..createSync(recursive: true);
    final f = File(p.join(dir.path, '${_prefix}_$name.png'));
    f.writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('SHOT ${f.path} ${image.width}x${image.height}');
  }

  BuildContext routerContext(WidgetTester tester) =>
      tester.element(find.byType(Scaffold).first);

  Future<void> go(WidgetTester tester, String location) async {
    GoRouter.of(routerContext(tester)).go(location);
    await hold(tester, ms: 1500);
  }

  testWidgets('capture store screenshots', (tester) async {
    final t = _target;
    tester.view.physicalSize = t.logical * t.ratio;
    tester.view.devicePixelRatio = t.ratio;
    addTearDown(tester.view.reset);

    final ids = await _seed();

    // main() installs the app's own FlutterError.onError; the test binding
    // asserts that its handler is back in place when the test ends.
    final testOnError = FlutterError.onError;
    app.main([]);
    await hold(tester, ms: 6000);
    FlutterError.onError = testOnError;

    // 1 — a diarized interview, opened in the transcript workspace.
    await go(tester, '/transcript/${ids.first}');
    await shot(tester, '01_transcript');

    // 2 — History with several recordings.
    await go(tester, '/history');
    await shot(tester, '02_history');

    // 3 — the home / transcription screen.
    await go(tester, '/');
    await shot(tester, '03_transcribe');

    // 4 — text to speech, with a sentence ready to speak.
    await go(tester, '/synthesize');
    final field = find.byType(TextField);
    if (field.evaluate().isNotEmpty) {
      await tester.enterText(
        field.first,
        _de
            ? 'Willkommen bei CrisperWeaver. Alles läuft direkt auf deinem '
                'Gerät – privat, schnell und ohne Cloud.'
            : 'Welcome to CrisperWeaver. Everything runs right on your '
                'device — private, fast, and without the cloud.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
    }
    await shot(tester, '04_synthesize');

    // 5 — the model manager.
    await go(tester, '/models');
    await hold(tester, ms: 3000);
    await shot(tester, '05_models');

    // 6 — audio to MIDI.
    await go(tester, '/music');
    await shot(tester, '06_music');

    // 7 — translation.
    await go(tester, '/translate');
    final source = find.byType(TextField);
    if (source.evaluate().isNotEmpty) {
      await tester.enterText(
        source.first,
        _de
            ? 'Die Aufnahme bleibt auf deinem Gerät. Übersetzt wird lokal, '
                'ohne dass ein Wort das Telefon verlässt.'
            : 'The recording stays on your device. Translation runs '
                'locally, and not a single word leaves your phone.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
    }
    await shot(tester, '07_translate');

    // 8 — settings.
    await go(tester, '/settings');
    await shot(tester, '08_settings');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Seeds preferences and History; returns the history ids, hero entry first.
Future<List<String>> _seed() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding_completed', true);
  await prefs.setBool('ai_transparency_notice_seen', true);
  await prefs.setString('app_locale', _locale);

  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'history'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  // Placeholder weights so the model manager, Synthesize and Audio→MIDI show
  // a set-up app. Sparse files at the catalogue size: ModelService only checks
  // that a file of plausible size is present, and no shot runs inference.
  // Same base ModelService picks: the App Group container on iOS.
  final group = Platform.isIOS
      ? await appGroupContainerPath('group.com.crispstrobe.crisperweaver')
      : null;
  final base = (group != null && group.isNotEmpty) ? group : docs.path;
  final models = Directory(p.join(base, 'models', 'whisper_cpp'))
    ..createSync(recursive: true);
  for (final (file, bytes) in _seedModels) {
    final raf = File(p.join(models.path, file)).openSync(mode: FileMode.write);
    raf.setPositionSync(bytes - 1);
    raf.writeByteSync(0);
    raf.closeSync();
  }

  final now = DateTime.now();
  final entries = _de ? _entriesDe(now) : _entriesEn(now);
  for (final e in entries) {
    File(p.join(dir.path, '${e['id']}.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(e));
  }
  return [for (final e in entries) e['id'] as String];
}

const _seedModels = [
  ('parakeet-tdt-0.6b-v3-q4_k.gguf', 467 << 20),
  ('ggml-large-v3-turbo.bin', 1550 << 20),
  ('Nemotron-3-Diarization.q8_0.gguf', 107012128),
  ('kokoro-82m-q8_0.gguf', 100 << 20),
  ('kokoro-voice-af_heart.gguf', 1 << 20),
  ('basic-pitch-f16.gguf', 112160),
  ('ggml-base-q5_1.bin', 57 << 20),
  ('m2m100-418m-q4_k.gguf', 480 << 20),
];

Map<String, dynamic> _entry({
  required String id,
  required DateTime createdAt,
  required String file,
  required String modelId,
  required String language,
  required List<(String?, String)> lines,
  Map<String, String> speakerNames = const {},
  int processingMs = 9400,
}) {
  var t = 0.0;
  final segments = <Map<String, dynamic>>[];
  for (final (speaker, text) in lines) {
    final dur = 1.2 + text.split(' ').length * 0.34;
    segments.add({
      'text': text,
      'startTime': t,
      'endTime': t + dur,
      'speaker': speaker,
      'confidence': 0.96,
    });
    t += dur + 0.4;
  }
  return {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'sourcePath': '/demo/$file',
    'sourceUrl': null,
    'engineId': 'crispasr',
    'modelId': modelId,
    'language': language,
    'diarizationEnabled': speakerNames.isNotEmpty,
    'processingTimeMs': processingMs,
    'speakerNames': speakerNames,
    'segments': segments,
  };
}

List<Map<String, dynamic>> _entriesEn(DateTime now) => [
      _entry(
        id: 'demo-interview',
        createdAt: now.subtract(const Duration(minutes: 12)),
        file: 'Podcast – Episode 42.m4a',
        modelId: 'parakeet-tdt-0.6b-v3-q4_k',
        language: 'en',
        speakerNames: {'Speaker 1': 'Maya', 'Speaker 2': 'Jonas'},
        processingMs: 18200,
        lines: [
          ('Speaker 1', 'Welcome back to the show. Today we are talking about '
              'speech recognition that never leaves your device.'),
          ('Speaker 2', 'Thanks for having me. The big change is that the '
              'models are now small enough to run on a phone.'),
          ('Speaker 1', 'So when I record this conversation, nothing is '
              'uploaded anywhere?'),
          ('Speaker 2', 'Exactly. Transcription, speaker detection and even '
              'the summary all run locally.'),
          ('Speaker 1', 'And it tells our two voices apart on its own.'),
          ('Speaker 2', 'Right, the diarization model labels each turn, and '
              'you can rename the speakers afterwards.'),
          ('Speaker 1', 'What about other languages?'),
          ('Speaker 2', 'Whisper covers almost a hundred, and Parakeet handles '
              'the European ones very quickly.'),
          ('Speaker 1', 'Let us try German next week, then.'),
        ],
      ),
      _entry(
        id: 'demo-standup',
        createdAt: now.subtract(const Duration(hours: 3)),
        file: 'Team stand-up.wav',
        modelId: 'large-v3-turbo',
        language: 'en',
        lines: [
          (null, 'Quick update from the design team: the new onboarding '
              'flow is ready for review.'),
          (null, 'Engineering shipped the offline mode on Friday.'),
        ],
      ),
      _entry(
        id: 'demo-lecture',
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        file: 'Lecture – Neural Networks 101.mp3',
        modelId: 'large-v3-turbo',
        language: 'en',
        processingMs: 64100,
        lines: [
          (null, 'Today we look at how a neural network learns from '
              'examples, one small step at a time.'),
        ],
      ),
      _entry(
        id: 'demo-memo',
        createdAt: now.subtract(const Duration(days: 3)),
        file: 'Voice memo – grocery list.m4a',
        modelId: 'moonshine-base',
        language: 'en',
        processingMs: 900,
        lines: [
          (null, 'Oat milk, two lemons, fresh basil and the good coffee.'),
        ],
      ),
    ];

List<Map<String, dynamic>> _entriesDe(DateTime now) => [
      _entry(
        id: 'demo-interview',
        createdAt: now.subtract(const Duration(minutes: 12)),
        file: 'Podcast – Folge 42.m4a',
        modelId: 'parakeet-tdt-0.6b-v3-q4_k',
        language: 'de',
        speakerNames: {'Speaker 1': 'Maya', 'Speaker 2': 'Jonas'},
        processingMs: 18200,
        lines: [
          ('Speaker 1', 'Willkommen zurück! Heute geht es um Spracherkennung, '
              'die dein Gerät nie verlässt.'),
          ('Speaker 2', 'Danke für die Einladung. Die Modelle sind inzwischen '
              'klein genug für ein Smartphone.'),
          ('Speaker 1', 'Wenn ich dieses Gespräch aufnehme, wird also nichts '
              'hochgeladen?'),
          ('Speaker 2', 'Genau. Transkription, Sprechererkennung und sogar die '
              'Zusammenfassung laufen lokal.'),
          ('Speaker 1', 'Und unsere beiden Stimmen unterscheidet es von '
              'selbst.'),
          ('Speaker 2', 'Richtig, das Diarisierungsmodell ordnet jeden '
              'Beitrag zu, und die Namen kannst du danach ändern.'),
          ('Speaker 1', 'Und andere Sprachen?'),
          ('Speaker 2', 'Whisper kann fast hundert, Parakeet schafft die '
              'europäischen Sprachen besonders schnell.'),
        ],
      ),
      _entry(
        id: 'demo-standup',
        createdAt: now.subtract(const Duration(hours: 3)),
        file: 'Team-Meeting.wav',
        modelId: 'large-v3-turbo',
        language: 'de',
        lines: [
          (null, 'Kurzes Update aus dem Design-Team: Der neue Einstieg ist '
              'bereit zur Durchsicht.'),
        ],
      ),
      _entry(
        id: 'demo-lecture',
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        file: 'Vorlesung – Neuronale Netze.mp3',
        modelId: 'large-v3-turbo',
        language: 'de',
        processingMs: 64100,
        lines: [
          (null, 'Heute sehen wir uns an, wie ein neuronales Netz aus '
              'Beispielen lernt.'),
        ],
      ),
      _entry(
        id: 'demo-memo',
        createdAt: now.subtract(const Duration(days: 3)),
        file: 'Sprachnotiz – Einkauf.m4a',
        modelId: 'base-q5_1',
        language: 'de',
        processingMs: 900,
        lines: [
          (null, 'Hafermilch, zwei Zitronen, frisches Basilikum und der gute '
              'Kaffee.'),
        ],
      ),
    ];
