// Web TTS service — routes synthesis through a remote CrispASR server
// via POST /v1/audio/speech (OpenAI-compatible).

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'log_service.dart';
import 'tts_service.dart' show SynthesizedAudio;

/// TTS backends available on the HF Space.
class HfSpaceTtsBackend {
  final String backend;
  final String displayName;
  final String defaultVoice;
  const HfSpaceTtsBackend(this.backend, this.displayName, this.defaultVoice);
}

const hfSpaceTtsBackends = <HfSpaceTtsBackend>[
  HfSpaceTtsBackend('kokoro', 'Kokoro 82M', 'af_heart'),
  HfSpaceTtsBackend('vibevoice', 'VibeVoice 0.5B', 'default'),
  HfSpaceTtsBackend('orpheus', 'Orpheus 0.5B', 'tara'),
  HfSpaceTtsBackend('chatterbox', 'Chatterbox', 'default'),
  HfSpaceTtsBackend('chatterbox-turbo', 'Chatterbox Turbo', 'default'),
];

class HfSpaceTtsService {
  HfSpaceTtsService({required String baseUrl})
      : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  final String _baseUrl;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 300),
  ));

  /// Load a TTS backend on the remote server.
  Future<void> loadBackend(String backend) async {
    const lang = 'en';
    try {
      await _dio.post<dynamic>(
        '$_baseUrl/load',
        data: FormData.fromMap({
          'backend': backend,
          'model': 'auto',
          'language': lang,
        }),
        options: Options(receiveTimeout: const Duration(seconds: 300)),
      );
      Log.instance.i('hfspace-tts', 'loaded backend=$backend');
    } on DioException catch (e) {
      Log.instance.e('hfspace-tts', 'load failed: ${e.message}', error: e);
      rethrow;
    }
  }

  /// Synthesize text to audio.
  Future<SynthesizedAudio> synthesize(
    String text, {
    String? voice,
    double speed = 1.0,
  }) async {
    final payload = <String, dynamic>{
      'input': text,
      'speed': speed,
      'response_format': 'wav',
    };
    if (voice != null && voice.isNotEmpty) {
      payload['voice'] = voice;
    }

    try {
      final r = await _dio.post<dynamic>(
        '$_baseUrl/v1/audio/speech',
        data: payload,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          responseType: ResponseType.bytes,
        ),
      );

      if (r.statusCode != null && r.statusCode! >= 400) {
        throw Exception('TTS error ${r.statusCode}');
      }

      final wavBytes = Uint8List.fromList(r.data as List<int>);
      // Parse WAV to extract Float32List samples + sample rate.
      return _parseWav(wavBytes);
    } on DioException catch (e) {
      Log.instance.e('hfspace-tts', 'synthesize failed: ${e.message}',
          error: e);
      rethrow;
    }
  }

  /// List available voices from the server.
  Future<List<String>> listVoices() async {
    try {
      final r = await _dio.get<dynamic>('$_baseUrl/v1/voices');
      final voices = (r.data as Map<String, dynamic>?)?['voices'] as List?;
      if (voices == null || voices.isEmpty) return const ['af_heart'];
      return voices.map((v) {
        if (v is Map) return (v['name'] ?? v.toString()) as String;
        return v.toString();
      }).toList();
    } catch (_) {
      return const ['af_heart'];
    }
  }

  void dispose() => _dio.close(force: true);

  /// Parse a WAV file into Float32List samples and sample rate.
  static SynthesizedAudio _parseWav(Uint8List wav) {
    final data = ByteData.sublistView(wav);
    // Find 'fmt ' chunk
    final sampleRate = data.getUint32(24, Endian.little);
    final bitsPerSample = data.getUint16(34, Endian.little);
    final numChannels = data.getUint16(22, Endian.little);

    // Find 'data' chunk
    var offset = 12;
    while (offset + 8 < wav.length) {
      final chunkId = String.fromCharCodes(wav.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      if (chunkId == 'data') {
        offset += 8;
        break;
      }
      offset += 8 + chunkSize;
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    final numSamples = (wav.length - offset) ~/ (bytesPerSample * numChannels);
    final samples = Float32List(numSamples);

    for (var i = 0; i < numSamples; i++) {
      final pos = offset + i * bytesPerSample * numChannels;
      if (pos + bytesPerSample > wav.length) break;
      if (bitsPerSample == 16) {
        samples[i] = data.getInt16(pos, Endian.little) / 32768.0;
      } else if (bitsPerSample == 32) {
        samples[i] = data.getFloat32(pos, Endian.little);
      }
    }

    return SynthesizedAudio(samples: samples, sampleRate: sampleRate);
  }
}
