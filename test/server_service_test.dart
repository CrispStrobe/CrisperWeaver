// Integration test for the built-in HTTP server's request handling
// (PLAN §9.4). Starts ServerService on an ephemeral port and exercises
// the new capability endpoints' routing + input validation — the paths
// that return before touching any model, so no GGUF/dylib is needed.
// End-to-end behaviour (real VAD/LID/punctuation) is covered by the
// matching *_live_test.dart files.

import 'dart:convert';

import 'package:crisper_weaver/services/server_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late ProviderContainer container;
  late ServerService server;
  late String base;

  setUp(() async {
    container = ProviderContainer();
    server = container.read(serverServiceProvider);
    base = await server.start(port: 0); // ephemeral
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
  });

  group('server capability endpoints (parity with CLI)', () {
    test('punctuate rejects a body with no text (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/text/punctuate'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({}));
      expect(r.statusCode, 400);
      expect(r.body.toLowerCase(), contains('text'));
    });

    test('punctuate rejects invalid JSON (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/text/punctuate'),
          headers: {'content-type': 'application/json'}, body: 'not json');
      expect(r.statusCode, 400);
    });

    test('vad rejects a non-multipart request (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/audio/vad'),
          headers: {'content-type': 'application/json'}, body: '{}');
      expect(r.statusCode, 400);
      expect(r.body.toLowerCase(), contains('multipart'));
    });

    test('language (LID) rejects a non-multipart request (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/audio/language'),
          headers: {'content-type': 'application/json'}, body: '{}');
      expect(r.statusCode, 400);
      expect(r.body.toLowerCase(), contains('multipart'));
    });

    test('diarize rejects a non-multipart request (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/audio/diarize'),
          headers: {'content-type': 'application/json'}, body: '{}');
      expect(r.statusCode, 400);
      expect(r.body.toLowerCase(), contains('multipart'));
    });

    test('watermark rejects a non-multipart request (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/audio/watermark'),
          headers: {'content-type': 'application/json'}, body: '{}');
      expect(r.statusCode, 400);
    });

    test('watermark on a plain WAV reports watermarked:false (no model)',
        () async {
      final req =
          http.MultipartRequest('POST', Uri.parse('$base/v1/audio/watermark'))
            ..files
                .add(await http.MultipartFile.fromPath('file', 'test/jfk.wav'));
      final r = await http.Response.fromStream(await req.send());
      expect(r.statusCode, 200);
      expect(jsonDecode(r.body)['watermarked'], isFalse);
    });

    test('an unknown route is 404', () async {
      final r = await http.get(Uri.parse('$base/v1/nope'));
      expect(r.statusCode, 404);
    });

    // §10 — align endpoint
    test('align rejects a non-multipart request (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/audio/align'),
          headers: {'content-type': 'application/json'}, body: '{}');
      expect(r.statusCode, 400);
      expect(r.body.toLowerCase(), contains('multipart'));
    });

    // §10 — text-language endpoint
    test('text/language rejects a body with no text (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/text/language'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({}));
      expect(r.statusCode, 400);
      expect(r.body.toLowerCase(), contains('text'));
    });

    test('text/language rejects invalid JSON (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/text/language'),
          headers: {'content-type': 'application/json'},
          body: 'not json');
      expect(r.statusCode, 400);
    });

    // §10 — denoise endpoint
    test('denoise rejects a non-multipart request (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/audio/denoise'),
          headers: {'content-type': 'application/json'}, body: '{}');
      expect(r.statusCode, 400);
      expect(r.body.toLowerCase(), contains('multipart'));
    });

    // §10 — s2s endpoint
    test('s2s rejects a non-multipart request (400)', () async {
      final r = await http.post(Uri.parse('$base/v1/audio/s2s'),
          headers: {'content-type': 'application/json'}, body: '{}');
      expect(r.statusCode, 400);
      expect(r.body.toLowerCase(), contains('multipart'));
    });

    // watermark embed mode validation (mode=embed but no decode → still
    // checks the routing works)
    test('watermark detect mode on plain WAV still works', () async {
      final req =
          http.MultipartRequest('POST', Uri.parse('$base/v1/audio/watermark'))
            ..fields['mode'] = 'detect'
            ..files
                .add(await http.MultipartFile.fromPath('file', 'test/jfk.wav'));
      final r = await http.Response.fromStream(await req.send());
      expect(r.statusCode, 200);
      expect(jsonDecode(r.body)['watermarked'], isFalse);
    });
  });
}
