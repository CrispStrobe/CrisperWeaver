// Unit tests for HfSpaceTtsService — mock Dio, no network.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/hfspace_tts_service.dart';

// ---------------------------------------------------------------------------
// Canned Dio adapter
// ---------------------------------------------------------------------------

class _CannedAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function(RequestOptions)> handlers;
  final List<RequestOptions> requests = [];

  _CannedAdapter(this.handlers);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    for (final entry in handlers.entries) {
      if (options.path.contains(entry.key)) {
        return entry.value(options);
      }
    }
    return ResponseBody.fromString('not found', 404, headers: {
      'content-type': ['text/plain']
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Build a minimal valid 16-bit mono WAV with [nSamples] silent samples.
Uint8List _silentWav({int nSamples = 100, int sampleRate = 24000}) {
  final dataSize = nSamples * 2;
  final fileSize = 44 + dataSize;
  final buf = ByteData(fileSize);
  // RIFF header
  buf.setUint8(0, 0x52); buf.setUint8(1, 0x49);
  buf.setUint8(2, 0x46); buf.setUint8(3, 0x46);
  buf.setUint32(4, fileSize - 8, Endian.little);
  buf.setUint8(8, 0x57); buf.setUint8(9, 0x41);
  buf.setUint8(10, 0x56); buf.setUint8(11, 0x45);
  // fmt
  buf.setUint8(12, 0x66); buf.setUint8(13, 0x6D);
  buf.setUint8(14, 0x74); buf.setUint8(15, 0x20);
  buf.setUint32(16, 16, Endian.little);
  buf.setUint16(20, 1, Endian.little); // PCM
  buf.setUint16(22, 1, Endian.little); // mono
  buf.setUint32(24, sampleRate, Endian.little);
  buf.setUint32(28, sampleRate * 2, Endian.little);
  buf.setUint16(32, 2, Endian.little);
  buf.setUint16(34, 16, Endian.little);
  // data
  buf.setUint8(36, 0x64); buf.setUint8(37, 0x61);
  buf.setUint8(38, 0x74); buf.setUint8(39, 0x61);
  buf.setUint32(40, dataSize, Endian.little);
  // samples are zero (silence)
  return buf.buffer.asUint8List();
}

void main() {
  group('HfSpaceTtsService', () {
    late Dio dio;
    late _CannedAdapter adapter;
    late HfSpaceTtsService svc;

    setUp(() {
      final wavBytes = _silentWav();
      adapter = _CannedAdapter({
        '/load': (_) => ResponseBody.fromString(
            jsonEncode({'status': 'ok'}), 200,
            headers: {'content-type': ['application/json']}),
        '/v1/audio/speech': (_) => ResponseBody.fromBytes(
            wavBytes, 200,
            headers: {
              'content-type': ['audio/wav']
            }),
        '/v1/voices': (_) => ResponseBody.fromString(
            jsonEncode({
              'voices': [
                {'name': 'af_heart', 'format': 'kokoro'},
                {'name': 'am_michael', 'format': 'kokoro'},
              ]
            }),
            200,
            headers: {'content-type': ['application/json']}),
      });
      dio = Dio()..httpClientAdapter = adapter;
      svc = HfSpaceTtsService(baseUrl: 'http://localhost:9999', dio: dio);
    });

    tearDown(() => svc.dispose());

    test('loadBackend sends POST /load with backend name', () async {
      await svc.loadBackend('kokoro');
      final loadReqs =
          adapter.requests.where((r) => r.path.contains('/load'));
      expect(loadReqs, isNotEmpty);
    });

    test('synthesize sends POST /v1/audio/speech and returns audio', () async {
      final result = await svc.synthesize('Hello world', voice: 'af_heart');
      expect(result.samples, isNotEmpty);
      expect(result.sampleRate, 24000);

      final speechReqs =
          adapter.requests.where((r) => r.path.contains('/v1/audio/speech'));
      expect(speechReqs, isNotEmpty);
    });

    test('listVoices returns voice names', () async {
      final voices = await svc.listVoices();
      expect(voices, contains('af_heart'));
      expect(voices, contains('am_michael'));
    });

    test('listVoices returns default on error', () async {
      // Use a fresh service with a broken adapter
      final brokenDio = Dio()
        ..httpClientAdapter = _CannedAdapter({
          '/v1/voices': (_) => ResponseBody.fromString('error', 500,
              headers: {'content-type': ['text/plain']}),
        });
      final brokenSvc =
          HfSpaceTtsService(baseUrl: 'http://localhost:1', dio: brokenDio);
      final voices = await brokenSvc.listVoices();
      expect(voices, contains('af_heart'));
      brokenSvc.dispose();
    });

    test('_parseWav correctly extracts sample rate and samples', () async {
      final result = await svc.synthesize('test');
      // The canned adapter returns a 24kHz mono WAV with 100 silent samples
      expect(result.sampleRate, 24000);
      expect(result.samples.length, 100);
      // All samples should be 0.0 (silence)
      for (final s in result.samples) {
        expect(s, 0.0);
      }
    });
  });

  group('hfSpaceTtsBackends constant', () {
    test('contains kokoro as first backend', () {
      expect(hfSpaceTtsBackends.first.backend, 'kokoro');
    });

    test('all entries have non-empty fields', () {
      for (final b in hfSpaceTtsBackends) {
        expect(b.backend, isNotEmpty);
        expect(b.displayName, isNotEmpty);
        expect(b.defaultVoice, isNotEmpty);
      }
    });
  });
}
