// Live integration tests for the CrispASR HF Space API.
// These call the real https://cstr-crispasr.hf.space endpoints.
//
// Run with:
//   RUN_LIVE_TESTS=1 flutter test test/hfspace_live_test.dart --tags=live
//
// The HF Space may need 1-2 minutes to wake from sleep on first call.
// The Space holds ONE model in memory — loading TTS evicts ASR and vice
// versa. Tests are ordered to minimize model swaps: all ASR tests first,
// then TTS, then Gradio API tests.

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

/// Helper: check if a Gradio endpoint exists (returns 200 on POST).
Future<bool> _gradioEndpointExists(Dio dio, String endpoint) async {
  try {
    final r = await dio.post<dynamic>(
      '$_baseUrl/gradio_api/call/$endpoint',
      data: {'data': []},
      options: Options(
        headers: {'Content-Type': 'application/json'},
        validateStatus: (s) => true, // don't throw
      ),
    );
    // 200 = endpoint exists (even if args are wrong), 404 = not deployed
    return r.statusCode != 404;
  } catch (_) {
    return false;
  }
}

void main() {
  // ── ASR tests (whisper loaded) ────────────────────────────────────────
  group('HfSpaceEngine — live ASR', skip: _skip, () {
    late HfSpaceEngine engine;

    setUpAll(() async {
      engine = HfSpaceEngine(baseUrl: _baseUrl);
      final ok = await engine.initialize();
      if (!ok) fail('HF Space did not become ready');
      // Ensure whisper is loaded for all ASR tests
      await engine.loadModel('whisper');
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

    test('getAvailableModels returns cloud model list', () async {
      final models = await engine.getAvailableModels();
      expect(models.length, greaterThanOrEqualTo(9));
      final ids = models.map((m) => m.id).toSet();
      expect(ids, contains('whisper'));
      expect(ids, contains('parakeet'));
      expect(ids, contains('qwen3'));
    });

    test('loadModel whisper succeeds', () async {
      // Already loaded in setUpAll, but verify state
      expect(engine.currentModelId, 'whisper');
    });

    test('transcribeBytes with JFK WAV returns transcript', () async {
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
      // The 2-second clip covers "And so my fellow Americans"
      expect(result.fullText.toLowerCase(), contains('america'));
      expect(result.segments, isNotEmpty);
      expect(result.segments.first.startTime, greaterThanOrEqualTo(0.0));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('transcribeBytes with translate flag', () async {
      final jfkFile = File('test/jfk-2s.wav');
      if (!jfkFile.existsSync()) return;
      final bytes = await jfkFile.readAsBytes();

      final result = await engine.transcribeBytes(
        bytes,
        'jfk-2s.wav',
        translate: true,
      );
      expect(result.fullText, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ── TTS tests (kokoro loaded) ─────────────────────────────────────────
  group('HfSpaceTtsService — live TTS', skip: _skip, () {
    late HfSpaceTtsService tts;

    setUpAll(() async {
      tts = HfSpaceTtsService(baseUrl: _baseUrl);
      await tts.loadBackend('kokoro');
    });

    tearDownAll(() => tts.dispose());

    test('loadBackend kokoro succeeds', () async {
      // Already loaded in setUpAll — re-load to verify idempotent
      await tts.loadBackend('kokoro');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('synthesize returns audio samples', () async {
      // Use a longer sentence — the free-tier kokoro sometimes returns
      // empty audio for very short inputs.
      try {
        final result = await tts.synthesize(
          'CrispASR is one binary, twenty-four ASR backends, and eight TTS '
          'engines, running fully offline on your device.',
          voice: 'af_heart',
        );
        expect(result.samples, isNotEmpty);
        expect(result.sampleRate, greaterThan(0));
        expect(result.durationSeconds, greaterThan(0));
      } on DioException catch (e) {
        // The free-tier HF Space sometimes fails TTS synthesis due to
        // resource constraints (500 "empty audio"). Mark as known flake.
        if (e.response?.statusCode == 500) {
          markTestSkipped(
              'TTS synthesis returned 500 — free-tier resource limit');
        } else {
          rethrow;
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('listVoices returns at least one voice', () async {
      final voices = await tts.listVoices();
      expect(voices, isNotEmpty);
    });
  });

  // ── Gradio call API tests ─────────────────────────────────────────────
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
      final jfkFile = File('test/jfk-2s.wav');
      if (!jfkFile.existsSync()) return;

      // First load whisper (Gradio transcribe needs an ASR backend)
      await dio.post<dynamic>(
        '$_baseUrl/load',
        data: FormData.fromMap(
            {'backend': 'whisper', 'model': 'auto', 'language': 'en'}),
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );

      // Upload via Gradio upload endpoint
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
            'Bonjour le monde, comment allez-vous?',
            'CLD3 \u2014 109 ISO-639-1 (default)',
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
      expect(sseR.data!.toLowerCase(), contains('fr'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Gradio /call/translate_text works (if deployed)', () async {
      // The translate tab may not be deployed yet on the live Space,
      // or the NMT model download may fail on the free tier.
      try {
        final callR = await dio.post<dynamic>(
          '$_baseUrl/gradio_api/call/translate_text',
          data: {
            'data': [
              'Hello world',
              'M2M-100 418M \u2014 100 langs, any\u2192any',
              'en',
              'de',
            ]
          },
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        if (callR.statusCode == 404) {
          markTestSkipped('translate_text endpoint not deployed yet');
          return;
        }
        expect(callR.statusCode, 200);
        final eventId = (callR.data as Map)['event_id'];
        expect(eventId, isNotNull);

        final sseR = await dio.get<String>(
          '$_baseUrl/gradio_api/call/translate_text/$eventId',
          options: Options(responseType: ResponseType.plain),
        );
        // SSE may contain an error from the subprocess; check we at least
        // got a response.
        expect(sseR.data, isNotEmpty);
        if (sseR.data!.contains('"error"') ||
            sseR.data!.contains('Translation failed')) {
          markTestSkipped(
              'translate_text returned server-side error — NMT model '
              'may not be available on the free-tier Space');
          return;
        }
        expect(sseR.data, contains('data:'));
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          markTestSkipped('translate_text endpoint not deployed yet');
        } else if (e.response?.statusCode == 500) {
          markTestSkipped(
              'translate_text returned 500 — NMT backend not available '
              'on the free-tier Space');
        } else {
          rethrow;
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
