// Web TTS service — routes synthesis through a remote CrispASR server
// via POST /v1/audio/speech (OpenAI-compatible).
//
// EU AI Act Art. 50(2). The on-device path gets its watermark from
// `crispasr_session_synthesize` inside the C API, and `TtsService.writeWav`
// probes the PCM to confirm it rather than assuming it. Neither applies
// here: the samples come off the wire from a server this app does not
// control, and until the audit of 2026-08-02 this service handed them back
// as ordinary audio — no watermark, no probe, no provenance. Nothing in
// `lib/` calls it yet, which is exactly the position `AudioEditService`
// `exportEncoded` was in when `AI_ACT_RISK.md` §7.4 recorded that an
// unreachable marking gap is a gap waiting for a caller. The shipped
// first-use notice already tells web users that "synthesis run[s] on a
// remote CrispASR server", so the route is documented ahead of being wired.
//
// So the service marks what it returns: a spread-spectrum watermark is
// embedded here unless the remote already applied one, and the result is
// verified by probing the PCM. Container-level marking (LIST/INFO, C2PA,
// the Art. 50(4) beep for cloned voices) still has to come from
// `TtsService.writeWav`, which is the only writer that has the model and
// voice identity to put in a manifest — [SynthesizedAudio] carries samples,
// not a file.

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import 'log_service.dart';
import 'spread_spectrum_watermark.dart';
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
  HfSpaceTtsService({required String baseUrl, Dio? dio})
      : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 300),
  ));

  final String _baseUrl;
  final Dio _dio;

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
      return _marked(_parseWav(wavBytes));
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
    } catch (e) {
      Log.instance.w('hfspace-tts', 'listVoices failed',
          fields: {'err': e.toString()});
      return const ['af_heart'];
    }
  }

  void dispose() => _dio.close(force: true);

  /// [audio] with a spread-spectrum watermark, unless one is already there.
  ///
  /// The remote is a CrispASR server and normally watermarks its own output,
  /// so this probes first rather than double-embedding — two overlaid
  /// sequences degrade the correlation the detector relies on. When neither
  /// the remote's mark nor ours can be confirmed afterwards, that is logged
  /// at error level with the same wording `TtsService` uses, because the
  /// alternative — silence — is what lets unmarked synthetic audio ship
  /// while everyone believes it was marked.
  static SynthesizedAudio _marked(SynthesizedAudio audio) {
    if (!AppConstants.enableAudioWatermark) return audio;
    if (audio.samples.isEmpty) return audio;
    final existing = SpreadSpectrumWatermark.detect(audio.samples);
    if (existing >= _watermarkConfidenceFloor) {
      Log.instance.d('hfspace-tts', 'remote output already watermarked',
          fields: {'confidence': existing.toStringAsFixed(3)});
      return audio;
    }
    final embedded = SpreadSpectrumWatermark.embed(audio.samples);
    final confidence = SpreadSpectrumWatermark.detect(embedded);
    if (confidence < _watermarkConfidenceFloor) {
      Log.instance.e(
          'hfspace-tts',
          '[MARKING] no robust mark on synthesised output — the remote did '
              'not watermark it and the local embed did not verify '
              '(EU AI Act Art. 50(2))',
          fields: {'confidence': confidence.toStringAsFixed(3)});
    } else {
      Log.instance.i('hfspace-tts', 'watermark embedded locally',
          fields: {'confidence': confidence.toStringAsFixed(3)});
    }
    return SynthesizedAudio(samples: embedded, sampleRate: audio.sampleRate);
  }

  static const double _watermarkConfidenceFloor =
      SpreadSpectrumWatermark.confidenceFloor;

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
