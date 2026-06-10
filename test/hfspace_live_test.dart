// Live integration tests for the CrispASR HF Space API.
// These call the real https://cstr-crispasr.hf.space endpoints.
//
// Run with:
//   RUN_LIVE_TESTS=1 flutter test test/hfspace_live_test.dart --tags=live
//
// The HF Space holds ONE model in memory at a time — loading TTS evicts
// ASR and vice versa. Test groups are ordered to manage this:
//   1. ASR tests (whisper)
//   2. Gradio API tests (reload whisper explicitly)
//   3. TTS tests (kokoro — runs last so it doesn't evict whisper)

@Tags(['live'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/hfspace_engine.dart';
import 'package:crisper_weaver/services/hfspace_tts_service.dart';

const _baseUrl = 'https://cstr-crispasr.hf.space';
final _skip = Platform.environment['RUN_LIVE_TESTS'] != '1'
    ? 'Set RUN_LIVE_TESTS=1 to run live HF Space tests'
    : null;

void main() {
  // ── 1. ASR tests (whisper loaded) ─────────────────────────────────────
  group('1. HfSpaceEngine — live ASR', skip: _skip, () {
    late HfSpaceEngine engine;

    setUpAll(() async {
      engine = HfSpaceEngine(baseUrl: _baseUrl);
      final ok = await engine.initialize();
      if (!ok) fail('HF Space did not become ready');
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

    test('whisper is loaded', () {
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

  // ── 2. Gradio call API tests ──────────────────────────────────────────
  group('2. HF Space Gradio API — live', skip: _skip, () {
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

      // Ensure whisper is loaded (previous TTS group may have swapped)
      await dio.post<dynamic>(
        '$_baseUrl/load',
        data: FormData.fromMap(
            {'backend': 'whisper', 'model': 'auto', 'language': 'en'}),
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );

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

    test('Gradio /call/translate_text works', () async {
      // This endpoint requires the HF Space to be rebuilt with the
      // translate tab. If not deployed yet, skip gracefully.
      final probeR = await dio.post<dynamic>(
        '$_baseUrl/gradio_api/call/translate_text',
        data: {
          'data': [
            'Hello world',
            'M2M-100 418M \u2014 100 langs, any\u2192any',
            'en',
            'de',
          ]
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (s) => true,
        ),
      );
      if (probeR.statusCode == 404 || probeR.statusCode == 500) {
        // Check if it's a "function not found" error vs a real translate error
        final body = probeR.data?.toString() ?? '';
        if (body.contains('FnIndexInferError') ||
            body.contains('Could not infer')) {
          markTestSkipped(
              'translate_text not deployed on the live Space yet — '
              'rebuild the Space from CrispASR main');
          return;
        }
      }
      expect(probeR.statusCode, 200);
      final eventId = (probeR.data as Map)['event_id'];
      expect(eventId, isNotNull);

      final sseR = await dio.get<String>(
        '$_baseUrl/gradio_api/call/translate_text/$eventId',
        options: Options(responseType: ResponseType.plain),
      );
      expect(sseR.data, contains('data:'));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  // ── 3. TTS tests (kokoro — runs LAST) ─────────────────────────────────
  group('3. HfSpaceTtsService — live TTS', skip: _skip, () {
    late HfSpaceTtsService tts;

    setUpAll(() async {
      tts = HfSpaceTtsService(baseUrl: _baseUrl);
      // Load kokoro — this evicts the ASR backend
      await tts.loadBackend('kokoro');
      // Give the server a moment to finish model init
      await Future<void>.delayed(const Duration(seconds: 2));
    });

    tearDownAll(() => tts.dispose());

    test('loadBackend kokoro succeeds', () async {
      await tts.loadBackend('kokoro');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('synthesize returns audio samples', () async {
      // Kokoro's first synthesis after a cold load can fail while espeak-ng
      // data is being located. Retry once after a short delay.
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final result = await tts.synthesize(
            'CrispASR is one binary, twenty-four ASR backends, and eight TTS '
            'engines, running fully offline on your device.',
            voice: 'af_heart',
          );
          expect(result.samples, isNotEmpty);
          expect(result.sampleRate, greaterThan(0));
          expect(result.durationSeconds, greaterThan(0));
          return; // success
        } on DioException catch (e) {
          if (attempt == 0 && e.response?.statusCode == 500) {
            // Retry once — server may need warmup / model download
            await Future<void>.delayed(const Duration(seconds: 10));
            await tts.loadBackend('kokoro');
            await Future<void>.delayed(const Duration(seconds: 5));
            continue;
          }
          // Kokoro needs ~300MB model + voice downloads on first use.
          // On the free-tier Space this can fail silently with 500.
          if (e.response?.statusCode == 500) {
            markTestSkipped(
                'Kokoro TTS returned 500 — model files may not have '
                'downloaded yet on the free-tier Space (~300MB first use)');
            return;
          }
          rethrow;
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('listVoices returns at least one voice', () async {
      final voices = await tts.listVoices();
      expect(voices, isNotEmpty);
    });
  });
}
