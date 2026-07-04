// §12.8h — Wyoming protocol server for Home Assistant STT integration.
//
// Wyoming is a simple TCP protocol used by Home Assistant for
// speech-to-text, text-to-speech, and wake-word services. This
// implementation exposes CrisperWeaver's loaded ASR engine as a
// Wyoming STT provider.
//
// Protocol: newline-delimited JSON events over TCP.
// See: https://github.com/rhasspy/wyoming
//
// Events:
//   Client → Server:
//     {"type": "describe"}
//     {"type": "transcribe", "data": {"language": "en"}}
//     {"type": "audio-start", "data": {"rate": 16000, "width": 2, "channels": 1}}
//     {"type": "audio-chunk", "data": {"audio": "<base64>"}}
//     {"type": "audio-stop"}
//
//   Server → Client:
//     {"type": "info", "data": {"asr": [{"name": "crispasr", ...}]}}
//     {"type": "transcript", "data": {"text": "the transcript"}}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'log_service.dart';

/// Wyoming protocol event.
class WyomingEvent {
  final String type;
  final Map<String, dynamic> data;

  const WyomingEvent({required this.type, this.data = const {}});

  factory WyomingEvent.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return WyomingEvent(
      type: map['type'] as String? ?? '',
      data: map['data'] as Map<String, dynamic>? ?? const {},
    );
  }

  String toJson() => jsonEncode({'type': type, if (data.isNotEmpty) 'data': data});

  @override
  String toString() => 'WyomingEvent($type)';
}

/// Callback that receives PCM audio and returns the transcript text.
typedef WyomingTranscribeCallback = Future<String> Function(
    Float32List pcm, String? language);

/// Wyoming STT server.
///
/// Listens on a TCP port and handles Wyoming protocol events.
/// Each connection is handled serially: audio-start → chunks → audio-stop
/// triggers a transcription via the provided callback.
class WyomingService {
  ServerSocket? _server;
  final int port;
  final String modelName;
  final WyomingTranscribeCallback onTranscribe;

  WyomingService({
    this.port = 10300,
    this.modelName = 'crispasr',
    required this.onTranscribe,
  });

  bool get isRunning => _server != null;

  /// Start the Wyoming server.
  Future<void> start() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    Log.instance.i('wyoming', 'listening on port $port');
    _server!.listen(_handleConnection);
  }

  /// Stop the Wyoming server.
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    Log.instance.i('wyoming', 'stopped');
  }

  void _handleConnection(Socket client) {
    Log.instance.d('wyoming', 'client connected: ${client.remoteAddress.address}');
    final buffer = StringBuffer();
    final audioChunks = <Uint8List>[];
    String? language;
    int sampleRate = 16000;
    int sampleWidth = 2;

    client.cast<List<int>>().transform(utf8.decoder).listen(
      (data) async {
        buffer.write(data);
        // Process complete lines.
        while (true) {
          final str = buffer.toString();
          final nlIdx = str.indexOf('\n');
          if (nlIdx < 0) break;
          final line = str.substring(0, nlIdx).trim();
          buffer.clear();
          buffer.write(str.substring(nlIdx + 1));

          if (line.isEmpty) continue;

          try {
            final event = WyomingEvent.fromJson(line);
            await _handleEvent(
                event, client, audioChunks, language, sampleRate, sampleWidth,
                setLanguage: (l) => language = l,
                setRate: (r) => sampleRate = r,
                setWidth: (w) => sampleWidth = w);
          } catch (e) {
            Log.instance.w('wyoming', 'event parse error: $e');
          }
        }
      },
      onDone: () {
        Log.instance.d('wyoming', 'client disconnected');
      },
      onError: (Object e) {
        Log.instance.w('wyoming', 'client error: $e');
      },
    );
  }

  Future<void> _handleEvent(
    WyomingEvent event,
    Socket client,
    List<Uint8List> audioChunks,
    String? language,
    int sampleRate,
    int sampleWidth, {
    required void Function(String?) setLanguage,
    required void Function(int) setRate,
    required void Function(int) setWidth,
  }) async {
    switch (event.type) {
      case 'describe':
        final info = WyomingEvent(type: 'info', data: {
          'asr': [
            {
              'name': modelName,
              'description': 'CrisperWeaver on-device ASR',
              'installed': true,
              'languages': ['en'],
            }
          ],
        });
        client.writeln(info.toJson());
        break;

      case 'transcribe':
        setLanguage(event.data['language'] as String?);
        break;

      case 'audio-start':
        audioChunks.clear();
        setRate((event.data['rate'] as num?)?.toInt() ?? 16000);
        setWidth((event.data['width'] as num?)?.toInt() ?? 2);
        break;

      case 'audio-chunk':
        final b64 = event.data['audio'] as String?;
        if (b64 != null) {
          audioChunks.add(base64Decode(b64));
        }
        break;

      case 'audio-stop':
        if (audioChunks.isEmpty) {
          client.writeln(
              WyomingEvent(type: 'transcript', data: {'text': ''}).toJson());
          break;
        }

        // Concatenate audio chunks.
        final totalLen = audioChunks.fold<int>(0, (s, c) => s + c.length);
        final allBytes = Uint8List(totalLen);
        var offset = 0;
        for (final chunk in audioChunks) {
          allBytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        audioChunks.clear();

        // Convert int16 PCM to float32.
        final pcm = int16ToFloat32(allBytes, sampleWidth);

        // Transcribe.
        try {
          final text = await onTranscribe(pcm, language);
          client.writeln(
              WyomingEvent(type: 'transcript', data: {'text': text}).toJson());
        } catch (e) {
          Log.instance.w('wyoming', 'transcribe failed: $e');
          client.writeln(WyomingEvent(
              type: 'error', data: {'text': e.toString()}).toJson());
        }
        break;
    }
  }

  /// Convert raw int16 PCM bytes to Float32List.
  static Float32List int16ToFloat32(Uint8List bytes, int sampleWidth) {
    if (sampleWidth != 2) {
      // Only 16-bit PCM is supported.
      return Float32List(0);
    }
    final nSamples = bytes.length ~/ 2;
    final pcm = Float32List(nSamples);
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    for (var i = 0; i < nSamples; i++) {
      pcm[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return pcm;
  }
}

final wyomingServiceProvider = Provider<WyomingService?>((ref) {
  // Wyoming service is lazily created — it's not started by default.
  // Call sites must configure and start it explicitly.
  return null;
});
