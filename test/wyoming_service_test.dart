// Unit tests for WyomingService (§12.8h).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/wyoming_service.dart';

void main() {
  group('WyomingEvent', () {
    test('fromJson parses describe event', () {
      final e = WyomingEvent.fromJson('{"type": "describe"}');
      expect(e.type, 'describe');
      expect(e.data, isEmpty);
    });

    test('fromJson parses transcribe with language', () {
      final e = WyomingEvent.fromJson(
          '{"type": "transcribe", "data": {"language": "de"}}');
      expect(e.type, 'transcribe');
      expect(e.data['language'], 'de');
    });

    test('fromJson parses audio-start with rate', () {
      final e = WyomingEvent.fromJson(
          '{"type": "audio-start", "data": {"rate": 16000, "width": 2, "channels": 1}}');
      expect(e.type, 'audio-start');
      expect(e.data['rate'], 16000);
      expect(e.data['width'], 2);
    });

    test('toJson round-trips', () {
      final e = WyomingEvent(type: 'transcript', data: {'text': 'hello'});
      final json = e.toJson();
      final parsed = WyomingEvent.fromJson(json);
      expect(parsed.type, 'transcript');
      expect(parsed.data['text'], 'hello');
    });

    test('toJson omits empty data', () {
      final e = WyomingEvent(type: 'describe');
      final json = e.toJson();
      expect(json, '{"type":"describe"}');
    });

    test('toString includes type', () {
      expect(WyomingEvent(type: 'test').toString(), 'WyomingEvent(test)');
    });
  });

  group('WyomingService._int16ToFloat32', () {
    test('converts silence (zeros)', () {
      final bytes = Uint8List(4); // 2 samples of zeros
      final pcm = WyomingService.int16ToFloat32(bytes, 2);
      expect(pcm.length, 2);
      expect(pcm[0], 0.0);
      expect(pcm[1], 0.0);
    });

    test('converts max positive int16', () {
      final bytes = Uint8List(2);
      final view = ByteData.view(bytes.buffer);
      view.setInt16(0, 32767, Endian.little);
      final pcm = WyomingService.int16ToFloat32(bytes, 2);
      expect(pcm.length, 1);
      expect(pcm[0], closeTo(1.0, 0.001));
    });

    test('converts max negative int16', () {
      final bytes = Uint8List(2);
      final view = ByteData.view(bytes.buffer);
      view.setInt16(0, -32768, Endian.little);
      final pcm = WyomingService.int16ToFloat32(bytes, 2);
      expect(pcm.length, 1);
      expect(pcm[0], closeTo(-1.0, 0.001));
    });

    test('returns empty for non-16bit width', () {
      final pcm = WyomingService.int16ToFloat32(Uint8List(4), 4);
      expect(pcm, isEmpty);
    });
  });

  group('WyomingService lifecycle', () {
    test('isRunning is false before start', () {
      final service = WyomingService(
        port: 0,
        onTranscribe: (pcm, lang) async => '',
      );
      expect(service.isRunning, isFalse);
    });
  });
}
