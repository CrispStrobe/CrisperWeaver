import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisper_weaver/constants/build_flavor.dart';
import 'package:crisper_weaver/engines/engine_factory.dart';
import 'package:crisper_weaver/engines/hfspace_engine.dart';
import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/services/ai_http_client.dart';
import 'package:crisper_weaver/services/cloud_llm_cleanup_service.dart';
import 'package:crisper_weaver/services/hfspace_tts_service.dart';
import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/settings_service.dart';
import 'package:crisper_weaver/services/transcript_summarize_service.dart';
import 'package:crisper_weaver/widgets/cloud_llm_settings_form.dart';

// Run in both full and Lite builds; policy is a compile-time constant.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Lite rejects remote, LAN, hostname and credential-bearing endpoints',
      () {
    for (final url in [
      'https://api.example.com/v1/chat/completions',
      'http://192.168.1.2:11434/v1/chat/completions',
      'http://localhost:11434/v1/chat/completions',
      'http://127.0.0.1.example.com/v1/chat/completions',
      'http://user:secret@127.0.0.1:11434/v1/chat/completions',
      'file:///tmp/model',
    ]) {
      expect(BuildFlavor.allowsAiEndpoint(url), !BuildFlavor.isLite,
          reason: url);
    }
    expect(
        BuildFlavor.allowsAiEndpoint(
            'http://127.0.0.1:11434/v1/chat/completions'),
        isTrue);
    expect(
        BuildFlavor.allowsAiEndpoint('http://[::1]:11434/v1/chat/completions'),
        isTrue);
  });

  test('saved cloud engine and endpoint cannot bypass Lite policy', () async {
    SharedPreferences.setMockInitialValues({
      'preferred_engine': 'hfspace',
      'cloud_llm_api_url': 'https://api.example.com/v1/chat/completions',
      'cloud_llm_api_key': 'saved-key',
    });
    final settings = SettingsService(await SharedPreferences.getInstance());
    expect(settings.preferredEngine,
        BuildFlavor.isLite ? EngineType.crispasr : EngineType.hfspace);
    expect(settings.httpLlmConfigured, !BuildFlavor.isLite);
    expect(EngineFactory.getAvailableEngines().contains(EngineType.hfspace),
        !BuildFlavor.isLite);
  });

  test('cleanup and summary reject remote requests before sending data',
      () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Clean text'}
              }
            ]
          }),
          200);
    });
    final cleanup = CloudLlmCleanupService(client: client);
    final summary = TranscriptSummarizeService(client: client);
    addTearDown(cleanup.dispose);
    addTearDown(summary.dispose);
    const config = CloudLlmConfig(
      apiUrl: 'https://api.example.com/v1/chat/completions',
      apiKey: 'saved-key',
      model: 'test-model',
    );
    if (BuildFlavor.isLite) {
      await expectLater(
          cleanup.cleanupSegment(text: 'Private transcript', config: config),
          throwsA(isA<CloudLlmDisabledException>()));
      await expectLater(
          summary.summarize(
              transcript: 'Private transcript',
              kinds: {SummaryKind.decisions},
              config: config),
          throwsA(isA<CloudLlmDisabledException>()));
      expect(requests, 0);
    } else {
      expect(
          await cleanup.cleanupSegment(
              text: 'Private transcript', config: config),
          'Clean text');
      await summary.summarize(
          transcript: 'Private transcript',
          kinds: {SummaryKind.decisions},
          config: config);
      expect(requests, 2);
    }
  });

  test('Lite supports a keyless local model and disables redirects', () async {
    final client = MockClient((request) async {
      expect(request.followRedirects, !BuildFlavor.isLite);
      return http.Response(
          '{"choices":[{"message":{"content":"Local result"}}]}', 200);
    });
    final cleanup = CloudLlmCleanupService(client: client);
    addTearDown(cleanup.dispose);
    const config = CloudLlmConfig(
        apiUrl: 'http://127.0.0.1:11434/v1/chat/completions',
        apiKey: BuildFlavor.isLite ? '' : 'dummy',
        model: 'llama3.2');
    expect(
        await cleanup.cleanupSegment(
            text: 'Private transcript', config: config),
        'Local result');
    const cloudModel = CloudLlmConfig(
        apiUrl: 'http://127.0.0.1:11434/v1/chat/completions',
        apiKey: 'dummy',
        model: 'gpt-oss:120b-cloud');
    expect(cloudModel.enabled, !BuildFlavor.isLite);
  });

  test('Lite blocks direct cloud ASR and TTS construction', () {
    if (!BuildFlavor.isLite) return;
    expect(() => HfSpaceEngine(), throwsUnsupportedError);
    expect(() => HfSpaceTtsService(baseUrl: 'https://example.com'),
        throwsUnsupportedError);
    expect(
        () => EngineFactory.create(EngineType.hfspace), throwsUnsupportedError);
  });

  testWidgets('Lite endpoint form rejects a remote host and saves local Ollama',
      (tester) async {
    if (!BuildFlavor.isLite) return;
    final key = GlobalKey<CloudLlmSettingsFormState>();
    var committed = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: CloudLlmSettingsForm(
        key: key,
        initialApiUrl: 'https://example.com/v1/chat/completions',
        initialApiKey: '',
        initialModel: 'llama3.2',
        onCommit: (url, apiKey, model) => committed = true,
        onCleared: () {},
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('OpenAI'), findsNothing);
    expect(key.currentState!.save(), isFalse);
    await tester.pump();
    expect(committed, isFalse);
    await tester.enterText(find.byType(TextField).first,
        'http://127.0.0.1:11434/v1/chat/completions');
    expect(key.currentState!.save(), isTrue);
    await tester.pump();
    expect(committed, isTrue);
  });

  test('production local transport does not follow a redirect', () async {
    if (!BuildFlavor.isLite) return;
    // Flutter tests substitute HttpClient by default. Use the real IO client
    // with a loopback-only server; the redirect must never be followed.
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var received = 0;
      server.listen((request) async {
        received++;
        request.response.statusCode = 307;
        request.response.headers
            .set('location', 'https://example.com/never-send');
        await request.response.close();
      });
      final client = AiHttpClient();
      addTearDown(client.close);
      final response = await client.post(
          Uri.parse('http://127.0.0.1:${server.port}/chat'),
          body: 'Private transcript');
      expect(response.statusCode, 307);
      expect(received, 1);
    }, _RealHttpOverrides());
  });

  test('import-only Lite blocks model catalogue HTTP before transport',
      () async {
    if (BuildFlavor.allowModelDownloads) return;
    SharedPreferences.setMockInitialValues({});
    final dio = Dio();
    ModelService(SettingsService(await SharedPreferences.getInstance()),
        dio: dio);
    // Exercise the configured client directly so no filesystem setup is needed.
    await expectLater(
        dio.get<dynamic>('https://huggingface.co/api/models'),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'cause', isA<UnsupportedError>())));
    dio.close(force: true);
  });
}

// Bypass Flutter's fake network client, but configure a dead proxy. The Lite
// client's DIRECT policy must override it for the loopback request to succeed.
class _RealHttpOverrides extends HttpOverrides {
  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      'PROXY 127.0.0.1:1';
}
