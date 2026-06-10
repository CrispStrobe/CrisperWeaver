// Live integration tests for the CrispASR HF Space API.
// These call the real https://cstr-crispasr.hf.space endpoints.
//
// Run with:
//   RUN_LIVE_TESTS=1 flutter test test/hfspace_live_test.dart --tags=live
//
// The HF Space may need 1-2 minutes to wake from sleep on first call.

@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/hfspace_engine.dart';
import 'package:crisper_weaver/services/hfspace_tts_service.dart';

const _baseUrl = 'https://cstr-crispasr.hf.space';
final _skip = Platform.environment['RUN_LIVE_TESTS'] != '1'
    ? 'Set RUN_LIVE_TESTS=1 to run live HF Space tests'
    : null;

void main() {
  group('HfSpaceEngine — live API', skip: _skip, () {
    late HfSpaceEngine engine;

    setUpAll(() async {
      engine = HfSpaceEngine(baseUrl: _baseUrl);
      // Allow up to 2 minutes for Space to wake
      final ok = await engine.initialize();
      if (!ok) fail('HF Space did not become ready');
    });

    tearDownAll(() => engine.dispose());

    test('GET /health returns ready', () async {
      final dio = Dio();
      final r = await dio.get('$_baseUrl/health');
      expect(r.statusCode, 200);
      expect(r.data['status'] ?? r.data['backend'], isNotNull);
      dio.close();
    });

    test('GET /backends returns non-empty list', () async {
      final dio = Dio();
      final r = await dio.get('$_baseUrl/backends');
      expect(r.statusCode, 200);
      final backends = r.data['backends'] as List?;
      expect(backends, isNotNull);
      expect(backends, isNotEmpty);
      dio.close();
    });

    test('GET /v1/models returns model data', () async {
      final dio = Dio();
      final r = await dio.get('$_baseUrl/v1/models');
      expect(r.statusCode, 200);
      expect(r.data['data'], isA<List>());
      dio.close();
    });

    test('loadModel whisper succeeds', () async {
      final ok = await engine.loadModel('whisper');
      expect(ok, isTrue);
      expect(engine.currentModelId, 'whisper');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('transcribeBytes with JFK WAV returns transcript', () async {
      // Load the 2-second JFK test clip
      final jfkFile = File('test/jfk-2s.wav');
      if (!jfkFile.existsSync()) {
        fail('test/jfk-2s.wav not found — run from repo root');
      }
      final bytes = await jfkFile.readAsBytes();

      final result = await engine.transcribeBytes(
        bytes,
        'jfk-2s.wav',
        language: 'en',
      );

      expect(result.fullText, isNotEmpty);
      expect(result.fullText.toLowerCase(), contains('american'));
      expect(result.segments, isNotEmpty);
      expect(result.segments.first.startTime, greaterThanOrEqualTo(0.0));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('transcribeBytes with translate flag', () async {
      final jfkFile = File('test/jfk-2s.wav');
      if (!jfkFile.existsSync()) return;
      final bytes = await jfkFile.readAsBytes();

      // Whisper translate → English (it's already English, so same text)
      final result = await engine.transcribeBytes(
        bytes,
        'jfk-2s.wav',
        translate: true,
      );
      expect(result.fullText, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('getAvailableModels returns cloud model list', () async {
      final models = await engine.getAvailableModels();
      expect(models.length, greaterThanOrEqualTo(9));
      final ids = models.map((m) => m.id).toSet();
      expect(ids, contains('whisper'));
      expect(ids, contains('parakeet'));
      expect(ids, contains('qwen3'));
    });
  });

  group('HfSpaceTtsService — live API', skip: _skip, () {
    late HfSpaceTtsService tts;

    setUpAll(() async {
      tts = HfSpaceTtsService(baseUrl: _baseUrl);
    });

    tearDownAll(() => tts.dispose());

    test('loadBackend kokoro succeeds', () async {
      await tts.loadBackend('kokoro');
      // If no exception, it worked
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('synthesize returns audio samples', () async {
      final result = await tts.synthesize('Hello world', voice: 'af_heart');
      expect(result.samples, isNotEmpty);
      expect(result.sampleRate, greaterThan(0));
      expect(result.durationSeconds, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('listVoices returns at least af_heart', () async {
      final voices = await tts.listVoices();
      expect(voices, isNotEmpty);
    });
  });

  group('HF Space Gradio API — live', skip: _skip, () {
    late Dio dio;

    setUp(() {
      dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 300),
      ));
    });

    tearDown(() => dio.close());

    test('Gradio /call/transcribe works', () async {
      // Upload a file first
      final jfkFile = File('test/jfk-2s.wav');
      if (!jfkFile.existsSync()) return;

      final uploadR = await dio.post<dynamic>(
        '$_baseUrl/gradio_api/upload',
        data: FormData.fromMap({
          'files': await MultipartFile.fromFile(jfkFile.path,
              filename: 'jfk-2s.wav'),
        }),
      );
      expect(uploadR.statusCode, 200);
      final uploadedFiles = uploadR.data as List;
      expect(uploadedFiles, isNotEmpty);
      final uploadedPath = uploadedFiles.first as String;

      // Call the transcribe function
      final callR = await dio.post<dynamic>(
        '$_baseUrl/gradio_api/call/transcribe',
        data: {
          'data': [
            {'path': uploadedPath},
            'en',
            '',
            0.0,
            'verbose_json',
          ]
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      expect(callR.statusCode, 200);
      final eventId = (callR.data as Map)['event_id'];
      expect(eventId, isNotNull);

      // Get SSE result
      final sseR = await dio.get<String>(
        '$_baseUrl/gradio_api/call/transcribe/$eventId',
        options: Options(responseType: ResponseType.plain),
      );
      expect(sseR.data, contains('data:'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Gradio /call/detect_text_language works', () async {
      final callR = await dio.post<dynamic>(
        '$_baseUrl/gradio_api/call/detect_text_language',
        data: {
          'data': [
            'Bonjour le monde',
            'CLD3 — 109 ISO-639-1 (default)',
            3,
          ]
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      expect(callR.statusCode, 200);
      final eventId = (callR.data as Map)['event_id'];
      expect(eventId, isNotNull);

      final sseR = await dio.get<String>(
        '$_baseUrl/gradio_api/call/detect_text_language/$eventId',
        options: Options(responseType: ResponseType.plain),
      );
      expect(sseR.data, contains('data:'));
      // Should detect French
      expect(sseR.data!.toLowerCase(), contains('fr'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Gradio /call/translate_text works', () async {
      final callR = await dio.post<dynamic>(
        '$_baseUrl/gradio_api/call/translate_text',
        data: {
          'data': [
            'Hello world',
            'M2M-100 418M — 100 langs, any→any',
            'en',
            'de',
          ]
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      expect(callR.statusCode, 200);
      final eventId = (callR.data as Map)['event_id'];
      expect(eventId, isNotNull);

      final sseR = await dio.get<String>(
        '$_baseUrl/gradio_api/call/translate_text/$eventId',
        options: Options(responseType: ResponseType.plain),
      );
      expect(sseR.data, contains('data:'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
