import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../engines/transcription_engine.dart';
import '../main.dart' show transcriptionServiceProvider;
import 'audio_service.dart';
import 'log_service.dart';
import 'text_translation_service.dart';
import 'transcription_service.dart';
import 'tts_service.dart';

/// Local HTTP server exposing CrisperWeaver's services through an
/// OpenAI-compatible surface. Three endpoints:
///
/// * `POST /v1/audio/transcriptions` — multipart upload (`file` =
///   audio file, `model` ignored, `response_format` ∈ {json, text,
///   srt, vtt}). Routes through [TranscriptionService] using the
///   currently-loaded model. Mirrors the OpenAI Whisper API shape so
///   existing scripts that hit `https://api.openai.com/v1/audio/...`
///   work unchanged when pointed at `http://localhost:<port>/v1/...`.
///
/// * `POST /v1/audio/speech` — JSON body `{model, input, voice,
///   response_format, speed}`. Returns the synthesized WAV bytes.
///
/// * `POST /v1/translations` — JSON `{text, src, tgt, model}`.
///   Routes through [TextTranslationService].
///
/// Plus `GET /health` for liveness checks.
///
/// **Security**: `bind` defaults to `127.0.0.1`. Pass an explicit
/// listen address to expose on a LAN. No auth — trust boundary is
/// the local machine. Don't bind to 0.0.0.0 on a multi-tenant box.
class ServerService {
  final Ref ref;
  ServerService(this.ref);

  HttpServer? _server;
  String? _boundUrl;

  /// Bound URL when the server is running, e.g.
  /// `http://127.0.0.1:8765`. Null when stopped.
  String? get boundUrl => _boundUrl;

  bool get isRunning => _server != null;

  /// Start the HTTP server on `host:port`. Returns the URL it bound
  /// to. Throws [ServerStartException] when the bind fails (port in
  /// use, address invalid, etc.) — the caller can surface a snackbar.
  Future<String> start({
    String host = '127.0.0.1',
    int port = 8765,
  }) async {
    if (_server != null) {
      Log.instance.w('server', 'start() called while already running');
      return _boundUrl!;
    }
    final router = _buildRouter();
    final handler = const Pipeline()
        .addMiddleware(_logRequests())
        .addHandler(router.call);
    try {
      _server = await shelf_io.serve(handler, host, port);
      _boundUrl = 'http://${_server!.address.host}:${_server!.port}';
      Log.instance.i('server', 'started', fields: {
        'url': _boundUrl,
      });
      return _boundUrl!;
    } catch (e, st) {
      Log.instance.e('server', 'start failed', error: e, stack: st);
      throw ServerStartException(e.toString());
    }
  }

  Future<void> stop() async {
    final s = _server;
    if (s == null) return;
    await s.close(force: true);
    _server = null;
    _boundUrl = null;
    Log.instance.i('server', 'stopped');
  }

  /// Logs request method, path, status, and elapsed ms — same shape
  /// the in-app Log viewer uses for the rest of CrisperWeaver.
  Middleware _logRequests() {
    return (Handler inner) {
      return (Request request) async {
        final stopwatch = Stopwatch()..start();
        final response = await inner(request);
        stopwatch.stop();
        Log.instance.i('server', 'req', fields: {
          'method': request.method,
          'path': request.url.path,
          'status': response.statusCode,
          'ms': stopwatch.elapsedMilliseconds,
        });
        return response;
      };
    };
  }

  Router _buildRouter() {
    final router = Router()
      ..get('/health', _handleHealth)
      ..post('/v1/audio/transcriptions', _handleTranscriptions)
      ..post('/v1/audio/speech', _handleSpeech)
      ..post('/v1/translations', _handleTranslations);
    return router;
  }

  Response _handleHealth(Request _) {
    return Response.ok(
      jsonEncode({
        'ok': true,
        'service': 'CrisperWeaver',
        'engine': ref.read(transcriptionServiceProvider).currentEngine?.engineId,
        'model': ref
            .read(transcriptionServiceProvider)
            .currentEngine
            ?.currentModelId,
      }),
      headers: const {'content-type': 'application/json'},
    );
  }

  /// OpenAI-compatible transcription endpoint. Accepts a multipart
  /// upload with a `file` part (audio) plus optional form fields:
  ///
  /// * `model` — ignored; we use whichever ASR is currently loaded
  ///   (matches OpenAI's "the server picks" semantics for users who
  ///   pass `whisper-1`).
  /// * `language` — ISO 639-1 hint, optional.
  /// * `response_format` — `json` (default) | `text` | `srt` | `vtt`.
  Future<Response> _handleTranscriptions(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.startsWith('multipart/form-data')) {
      return Response.badRequest(
        body: 'expected multipart/form-data; got $contentType',
      );
    }
    // Parse the multipart payload manually — shelf doesn't ship a
    // multipart parser. We reuse Dart's `HttpServer` MIME-multipart
    // helper via `MimeMultipartTransformer` for that.
    final boundaryParam = _parseBoundary(contentType);
    if (boundaryParam == null) {
      return Response.badRequest(
          body: 'missing boundary in content-type');
    }
    Map<String, _MultipartField> fields;
    try {
      fields = await _parseMultipart(request.read(), boundaryParam);
    } catch (e) {
      return Response.badRequest(body: 'multipart parse error: $e');
    }
    final filePart = fields['file'];
    if (filePart == null || filePart.bytes == null) {
      return Response.badRequest(
          body: 'missing required field "file"');
    }

    // Save the upload to a temp file so AudioService.loadAudioFile
    // can decode it through CrispASR's miniaudio backend (handles
    // wav / mp3 / flac / ogg without an ffmpeg dep).
    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(filePart.filename ?? 'audio.wav');
    final tempFile = File(p.join(
        tempDir.path,
        'crispasr-server-${DateTime.now().millisecondsSinceEpoch}$ext'));
    await tempFile.writeAsBytes(filePart.bytes!);

    final language = fields['language']?.value;
    final responseFormat = fields['response_format']?.value ?? 'json';

    final tx = ref.read(transcriptionServiceProvider);
    if (tx.currentEngine == null) {
      return Response.internalServerError(
          body: 'no transcription engine loaded — open the app and pick '
              'a model first');
    }
    List<TranscriptionSegment> segments;
    try {
      segments = await tx.transcribeFile(
        tempFile,
        language: language,
      );
    } catch (e, st) {
      Log.instance
          .e('server', 'transcribe failed', error: e, stack: st);
      return Response.internalServerError(body: 'transcribe failed: $e');
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {/* best-effort */}
    }

    return _formatTranscriptionResponse(segments, responseFormat);
  }

  Response _formatTranscriptionResponse(
      List<TranscriptionSegment> segments, String fmt) {
    switch (fmt.toLowerCase()) {
      case 'text':
        final text = segments.map((s) => s.text).join(' ').trim();
        return Response.ok(text,
            headers: const {'content-type': 'text/plain; charset=utf-8'});
      case 'srt':
        return Response.ok(_renderSrt(segments),
            headers: const {'content-type': 'text/plain; charset=utf-8'});
      case 'vtt':
        return Response.ok(_renderVtt(segments),
            headers: const {'content-type': 'text/vtt; charset=utf-8'});
      case 'verbose_json':
      case 'json':
      default:
        // OpenAI's verbose_json includes per-segment timing; we always
        // return that shape — equivalent of `verbose_json` for
        // segments + `json` as the historical text-only field.
        final body = jsonEncode({
          'task': 'transcribe',
          'language': null,
          'duration': segments.isEmpty
              ? 0.0
              : segments.last.endTime - segments.first.startTime,
          'text': segments.map((s) => s.text).join(' ').trim(),
          'segments': [
            for (var i = 0; i < segments.length; i++)
              {
                'id': i,
                'start': segments[i].startTime,
                'end': segments[i].endTime,
                'text': segments[i].text,
                if (segments[i].speaker != null)
                  'speaker': segments[i].speaker,
              }
          ],
        });
        return Response.ok(body,
            headers: const {'content-type': 'application/json'});
    }
  }

  String _renderSrt(List<TranscriptionSegment> segs) {
    final buf = StringBuffer();
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      buf.writeln('${i + 1}');
      buf.writeln('${_srtTime(s.startTime)} --> ${_srtTime(s.endTime)}');
      buf.writeln('${s.speaker ?? ''}${s.speaker == null ? '' : ': '}${s.text}');
      buf.writeln();
    }
    return buf.toString();
  }

  String _renderVtt(List<TranscriptionSegment> segs) {
    final buf = StringBuffer()..writeln('WEBVTT')..writeln();
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      buf.writeln('${_vttTime(s.startTime)} --> ${_vttTime(s.endTime)}');
      buf.writeln('${s.speaker ?? ''}${s.speaker == null ? '' : ': '}${s.text}');
      buf.writeln();
    }
    return buf.toString();
  }

  String _srtTime(double t) {
    final h = (t / 3600).floor();
    final m = ((t % 3600) / 60).floor();
    final s = t % 60;
    final ms = ((s % 1) * 1000).round();
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.floor().toString().padLeft(2, '0')},'
        '${ms.toString().padLeft(3, '0')}';
  }

  String _vttTime(double t) => _srtTime(t).replaceFirst(',', '.');

  /// OpenAI-compatible TTS endpoint. JSON body — `{model, input,
  /// voice, response_format, speed}`. Returns audio bytes (WAV today;
  /// `response_format` only routes content-type, the underlying PCM
  /// is always 24 kHz mono float32 from CrispASR).
  Future<Response> _handleSpeech(Request request) async {
    final body = await request.readAsString();
    Map<String, dynamic> args;
    try {
      args = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: 'invalid JSON: $e');
    }
    final input = args['input'] as String?;
    final voice = args['voice'] as String?;
    final modelName = args['model'] as String?;
    final spokenDisclaimer = args['spoken_disclaimer'] as bool? ?? true;
    final speed =
        ((args['speed'] as num?)?.toDouble() ?? 1.0).clamp(0.25, 4.0).toDouble();
    if (input == null || input.trim().isEmpty || modelName == null) {
      return Response.badRequest(
        body: 'missing required fields: model + input',
      );
    }
    final tts = ref.read(ttsServiceProvider);
    final status = await tts.prepare(
      modelName: modelName,
      voiceName: voice,
    );
    if (!status.ready) {
      return Response.internalServerError(
        body: 'tts.prepare failed: '
            '${status.errorMessage ?? status.missingModelName ?? status.missingVoiceName ?? "unknown"}',
      );
    }
    SynthesizedAudio? audio;
    try {
      audio = await tts.synthesize(input, speed: speed);
    } catch (e) {
      return Response.internalServerError(body: 'synthesize failed: $e');
    }
    if (audio == null) {
      return Response.internalServerError(body: 'synthesize returned null');
    }
    final wav = await tts.writeWav(
      audio,
      voiceRefPath: voice,
      spokenDisclaimer: spokenDisclaimer,
    );
    final bytes = await wav.readAsBytes();
    return Response.ok(bytes, headers: const {
      'content-type': 'audio/wav',
      'x-content-ai-generated': 'true',
    });
  }

  /// Text-to-text translation. JSON `{model, text, src, tgt, max_tokens}`.
  Future<Response> _handleTranslations(Request request) async {
    final body = await request.readAsString();
    Map<String, dynamic> args;
    try {
      args = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: 'invalid JSON: $e');
    }
    final text = args['text'] as String?;
    final src = args['src'] as String? ?? args['source_language'] as String?;
    final tgt = args['tgt'] as String? ?? args['target_language'] as String?;
    final modelName = args['model'] as String?;
    final maxTokens = (args['max_tokens'] as num?)?.toInt() ?? 200;
    if (text == null ||
        text.trim().isEmpty ||
        src == null ||
        tgt == null ||
        modelName == null) {
      return Response.badRequest(
        body: 'missing required fields: model + text + src + tgt',
      );
    }
    try {
      final out = await ref.read(textTranslationServiceProvider).translate(
            modelName: modelName,
            text: text,
            srcLang: src,
            tgtLang: tgt,
            maxTokens: maxTokens,
          );
      return Response.ok(
        jsonEncode({'translation': out}),
        headers: const {'content-type': 'application/json'},
      );
    } on TextTranslationException catch (e) {
      return Response.internalServerError(body: e.message);
    }
  }

  // Minimal multipart parsing — shelf doesn't ship one. We slurp the
  // request body, split by the boundary, and pull out each part's
  // headers + payload.

  String? _parseBoundary(String contentType) {
    final m =
        RegExp(r'boundary=(?:"([^"]+)"|([^;]+))').firstMatch(contentType);
    if (m == null) return null;
    return m.group(1) ?? m.group(2)?.trim();
  }

  Future<Map<String, _MultipartField>> _parseMultipart(
      Stream<List<int>> body, String boundary) async {
    final raw = <int>[];
    await for (final chunk in body) {
      raw.addAll(chunk);
    }
    final delim = utf8.encode('--$boundary');
    final parts = _splitOnce(raw, delim);
    final fields = <String, _MultipartField>{};
    for (final part in parts) {
      // Each part starts with \r\n then headers, then \r\n\r\n then body.
      // Strip trailing \r\n-- (closing delimiter).
      var slice = part;
      if (slice.length >= 2 && slice[0] == 13 && slice[1] == 10) {
        slice = slice.sublist(2);
      }
      // Skip the closing "--" + the trailing \r\n it may carry.
      if (slice.length >= 2 && slice[0] == 0x2d && slice[1] == 0x2d) continue;
      final headerEnd = _indexOfSeq(slice, [13, 10, 13, 10]);
      if (headerEnd < 0) continue;
      final headerStr = utf8.decode(slice.sublist(0, headerEnd));
      var bodyBytes = slice.sublist(headerEnd + 4);
      // Strip the trailing CRLF before the next boundary.
      while (bodyBytes.isNotEmpty &&
          (bodyBytes.last == 13 || bodyBytes.last == 10)) {
        bodyBytes = bodyBytes.sublist(0, bodyBytes.length - 1);
      }
      final disposition = _extractHeader(headerStr, 'content-disposition');
      if (disposition == null) continue;
      final name = _extractParam(disposition, 'name');
      if (name == null) continue;
      final filename = _extractParam(disposition, 'filename');
      if (filename != null) {
        fields[name] =
            _MultipartField(filename: filename, bytes: bodyBytes);
      } else {
        fields[name] =
            _MultipartField(value: utf8.decode(bodyBytes, allowMalformed: true));
      }
    }
    return fields;
  }

  // Split `data` on every occurrence of `delim`. Returns the
  // segments BETWEEN delimiters; the very first (preamble) and last
  // (epilogue) are dropped if empty.
  List<List<int>> _splitOnce(List<int> data, List<int> delim) {
    final out = <List<int>>[];
    var i = 0;
    var start = 0;
    while (i + delim.length <= data.length) {
      var match = true;
      for (var j = 0; j < delim.length; j++) {
        if (data[i + j] != delim[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        if (start != i) out.add(data.sublist(start, i));
        i += delim.length;
        start = i;
      } else {
        i++;
      }
    }
    return out;
  }

  int _indexOfSeq(List<int> haystack, List<int> needle) {
    for (var i = 0; i + needle.length <= haystack.length; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  String? _extractHeader(String headers, String key) {
    final lower = headers.toLowerCase();
    final keyLower = key.toLowerCase();
    final idx = lower.indexOf('$keyLower:');
    if (idx < 0) return null;
    final end = headers.indexOf('\r\n', idx);
    final raw = end < 0
        ? headers.substring(idx + key.length + 1)
        : headers.substring(idx + key.length + 1, end);
    return raw.trim();
  }

  String? _extractParam(String header, String name) {
    final m =
        RegExp('$name=(?:"([^"]*)"|([^;]+))', caseSensitive: false)
            .firstMatch(header);
    if (m == null) return null;
    return m.group(1) ?? m.group(2)?.trim();
  }
}

/// Surfaced when [ServerService.start] fails — the message is the
/// original OS error verbatim (port in use, etc.).
class ServerStartException implements Exception {
  final String message;
  const ServerStartException(this.message);
  @override
  String toString() => 'ServerStartException: $message';
}

class _MultipartField {
  final String? value;
  final String? filename;
  final List<int>? bytes;
  const _MultipartField({this.value, this.filename, this.bytes});
}

// AudioService is imported only so the analyzer doesn't flag the
// import as unused — the server doesn't call it directly today, but
// transcribeFile() routes through it under the hood, and keeping the
// import here is the clearest signal of the dependency surface.
// ignore: unused_element
const _audioServiceImportSentinel = AudioService;

final serverServiceProvider = Provider<ServerService>((ref) {
  final svc = ServerService(ref);
  ref.onDispose(svc.stop);
  return svc;
});
