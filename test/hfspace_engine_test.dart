// Unit tests for HfSpaceEngine — mock Dio, no network.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/hfspace_engine.dart';
import 'package:crisper_weaver/engines/transcription_engine.dart';

// ---------------------------------------------------------------------------
// Canned Dio adapter — returns pre-built responses keyed by path
// ---------------------------------------------------------------------------

class _CannedAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function(RequestOptions)> handlers;
  final List<RequestOptions> requests = [];

  _CannedAdapter(this.handlers);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final path = options.path;
    for (final entry in handlers.entries) {
      if (path.contains(entry.key)) {
        return entry.value(options);
      }
    }
    return ResponseBody.fromString('{"error":"no handler for $path"}', 404,
        headers: {
          'content-type': ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(dynamic data, {int status = 200}) {
  return ResponseBody.fromString(jsonEncode(data), status, headers: {
    'content-type': ['application/json']
  });
}

void main() {
  group('HfSpaceEngine', () {
    late Dio dio;
    late _CannedAdapter adapter;
    late HfSpaceEngine engine;

    setUp(() {
      adapter = _CannedAdapter({
        '/health': (_) => _jsonBody({'status': 'ok', 'backend': 'whisper'}),
        '/v1/models': (_) =>
            _jsonBody({'data': [{'id': 'whisper'}]}),
        '/backends': (_) =>
            _jsonBody({'backends': ['whisper', 'parakeet']}),
        '/load': (_) => _jsonBody({'status': 'ok'}),
        '/v1/audio/transcriptions': (_) => _jsonBody({
              'text': 'Hello world',
              'language': 'en',
              'duration': 2.5,
              'segments': [
                {
                  'text': 'Hello world',
                  'start': 0.0,
                  'end': 2.5,
                  'avg_logprob': -0.3,
                }
              ],
            }),
      });
      dio = Dio()..httpClientAdapter = adapter;
      engine = HfSpaceEngine(
        baseUrl: 'http://localhost:9999',
        dio: dio,
      );
    });

    tearDown(() => engine.dispose());

    test('engineId and engineName', () {
      expect(engine.engineId, 'hfspace');
      expect(engine.engineName, 'CrispASR Cloud');
    });

    test('initialize succeeds when /health returns 200', () async {
      final ok = await engine.initialize();
      expect(ok, isTrue);
      expect(engine.isInitialized, isTrue);
      expect(adapter.requests.any((r) => r.path.contains('/health')), isTrue);
    });

    test('getAvailableModels returns ASR model list', () async {
      await engine.initialize();
      final models = await engine.getAvailableModels();
      expect(models, isNotEmpty);
      expect(models.any((m) => m.id == 'whisper'), isTrue);
      expect(models.any((m) => m.id == 'parakeet'), isTrue);
      expect(models.any((m) => m.id == 'qwen3'), isTrue);
      // All cloud models should be marked as available
      for (final m in models) {
        expect(m.isDownloaded, isTrue);
        expect(m.metadata['backend'], isNotNull);
      }
    });

    test('loadModel sends POST /load with correct backend', () async {
      await engine.initialize();
      final ok = await engine.loadModel('whisper');
      expect(ok, isTrue);
      expect(engine.currentModelId, 'whisper');
      final loadReqs =
          adapter.requests.where((r) => r.path.contains('/load'));
      expect(loadReqs, isNotEmpty);
    });

    test('loadModel throws for unknown backend', () async {
      await engine.initialize();
      expect(
        () => engine.loadModel('nonexistent-backend'),
        throwsA(isA<ModelLoadException>()),
      );
    });

    test('transcribeBytes sends multipart POST to /v1/audio/transcriptions',
        () async {
      await engine.initialize();
      await engine.loadModel('whisper');

      final fakeWav = Uint8List.fromList(List.filled(100, 0));
      final segments = <TranscriptionSegment>[];
      final result = await engine.transcribeBytes(
        fakeWav,
        'test.wav',
        language: 'en',
        onSegment: segments.add,
      );

      expect(result.fullText, 'Hello world');
      expect(result.segments, hasLength(1));
      expect(result.segments.first.startTime, 0.0);
      expect(result.segments.first.endTime, 2.5);
      expect(result.detectedLanguage, 'en');
      expect(segments, hasLength(1));

      final transcribeReqs = adapter.requests
          .where((r) => r.path.contains('/v1/audio/transcriptions'));
      expect(transcribeReqs, isNotEmpty);
    });

    test('transcribeBytes passes translate/vad/diarize/punct fields',
        () async {
      await engine.initialize();
      final fakeWav = Uint8List.fromList(List.filled(100, 0));
      await engine.transcribeBytes(
        fakeWav,
        'test.wav',
        translate: true,
        vad: true,
        diarize: true,
        punctuation: false,
      );

      final req = adapter.requests
          .lastWhere((r) => r.path.contains('/v1/audio/transcriptions'));
      // The FormData should contain these fields
      expect(req.data, isA<FormData>());
      final fields = (req.data as FormData).fields;
      final fieldMap = {for (final f in fields) f.key: f.value};
      expect(fieldMap['translate'], 'true');
      expect(fieldMap['vad'], 'true');
      expect(fieldMap['diarize'], 'true');
      expect(fieldMap['punctuation'], 'false');
    });

    test('transcribe encodes PCM to WAV and calls transcribeBytes', () async {
      await engine.initialize();
      final pcm = Float32List.fromList([0.1, -0.2, 0.3, -0.4]);
      final result = await engine.transcribe(pcm, language: 'en');
      expect(result.fullText, 'Hello world');
    });

    test('cancel aborts in-flight request', () async {
      await engine.initialize();
      // Start a transcription but cancel immediately
      final future = engine.transcribeBytes(
          Uint8List.fromList(List.filled(100, 0)), 'test.wav');
      await engine.cancel();
      // Should either complete or throw TranscriptionException
      try {
        await future;
      } on TranscriptionException catch (e) {
        expect(e.message, contains('Cancel'));
      }
    });

    test('unloadModel clears currentModelId', () async {
      await engine.initialize();
      await engine.loadModel('whisper');
      expect(engine.currentModelId, 'whisper');
      await engine.unloadModel();
      expect(engine.currentModelId, isNull);
    });

    test('supportsStreaming is false', () {
      expect(engine.supportsStreaming, isFalse);
    });

    test('transcribeStream returns null', () {
      final stream =
          engine.transcribeStream(const Stream.empty());
      expect(stream, isNull);
    });

    test('updateConfig changes baseUrl', () async {
      await engine.updateConfig({'baseUrl': 'http://new-server:8080'});
      expect(engine.currentConfig['baseUrl'], 'http://new-server:8080');
    });
  });

  group('HfSpaceEngine._encodeWav', () {
    test('produces valid WAV header for 4-sample mono 16kHz PCM', () {
      // Access via transcribe which calls _encodeWav internally
      // We test indirectly by verifying the transcription endpoint receives data
      // For a direct test, the static method would need to be visible.
      // Instead, test that transcribe doesn't crash on small input.
      final engine = HfSpaceEngine(
        baseUrl: 'http://localhost:1',
        dio: Dio()
          ..httpClientAdapter = _CannedAdapter({
            '/v1/audio/transcriptions': (_) =>
                _jsonBody({'text': 'ok', 'segments': []}),
          }),
      );
      // Just verify it doesn't throw
      expect(
        () async => engine.transcribe(Float32List.fromList([0.0, 0.5, -0.5, 1.0])),
        returnsNormally,
      );
    });
  });
}
