import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../engines/transcription_engine.dart';
import '../main.dart' show transcriptionServiceProvider, modelServiceProvider;
import 'aligner_service.dart';
import 'audio_service.dart';
import 'audio_watermark_service.dart';
import 'diarization_service.dart';
import 'lid_service.dart';
import 'log_service.dart';
import 'punc_service.dart';
import 'text_translation_service.dart';
import 'transcription_service.dart';
import 'tts_service.dart';
import 'vad_service.dart';
import '../native/crispasr_import.dart' as crispasr;

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
      // Bind the raw HttpServer ourselves so we can intercept WebSocket
      // upgrade requests before shelf sees them. Shelf doesn't natively
      // support WebSocket upgrades, so we handle /v1/audio/stream here
      // and forward everything else to the shelf handler.
      final rawServer = await HttpServer.bind(host, port);
      _server = rawServer;
      _boundUrl = 'http://${rawServer.address.host}:${rawServer.port}';

      rawServer.listen((HttpRequest request) async {
        final path = request.uri.path;
        // WebSocket streaming endpoint — intercept before shelf.
        if (path == '/v1/audio/stream' &&
            WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            final ws = await WebSocketTransformer.upgrade(request);
            _handleWebSocketStream(ws);
          } catch (e, st) {
            Log.instance.e('server', 'WebSocket upgrade failed',
                error: e, stack: st);
            request.response
              ..statusCode = 500
              ..write('WebSocket upgrade failed: $e')
              ..close();
          }
          return;
        }
        // Everything else → shelf handler.
        shelf_io.handleRequest(request, handler);
      });

      Log.instance.i('server', 'started', fields: {
        'url': _boundUrl,
        'ws': '${_boundUrl!.replaceFirst('http', 'ws')}/v1/audio/stream',
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
      ..get('/backends', _handleBackends)
      ..post('/v1/audio/transcriptions', _handleTranscriptions)
      ..post('/v1/audio/speech', _handleSpeech)
      ..post('/v1/translations', _handleTranslations)
      // Capability parity with the CLI (PLAN §9.4 / docs/PARITY.md):
      ..post('/v1/audio/vad', _handleVad)
      ..post('/v1/audio/language', _handleLanguage)
      ..post('/v1/text/punctuate', _handlePunctuate)
      ..post('/v1/audio/diarize', _handleDiarize)
      ..post('/v1/audio/watermark', _handleWatermark)
      ..post('/v1/audio/align', _handleAlign)
      ..post('/v1/text/language', _handleTextLanguage)
      ..post('/v1/audio/denoise', _handleDenoise)
      ..post('/v1/audio/s2s', _handleS2s);
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

  Response _handleBackends(Request _) {
    final backends = crispasr.CrispasrSession.availableBackends();
    return Response.ok(
      jsonEncode({'backends': backends}),
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
    final alignerModel = fields['aligner']?.value;
    final wordTimestamps =
        fields['word_timestamps']?.value?.toLowerCase() == 'true';
    final temperature =
        double.tryParse(fields['temperature']?.value ?? '') ?? 0.0;
    final bestOf =
        int.tryParse(fields['best_of']?.value ?? '') ?? 1;
    final initialPrompt = fields['prompt']?.value ?? fields['initial_prompt']?.value;
    final hotwords = fields['hotwords']?.value ?? '';
    final hotwordsBoost =
        double.tryParse(fields['hotwords_boost']?.value ?? '') ?? 1.5;
    final translate =
        fields['translate']?.value?.toLowerCase() == 'true';
    final vad = fields['vad']?.value?.toLowerCase() == 'true';
    final diarize = fields['diarize']?.value?.toLowerCase() == 'true';
    final restorePunctuation =
        fields['punctuation']?.value?.toLowerCase() == 'true';
    final askPrompt = fields['ask']?.value ?? fields['ask_prompt']?.value;
    final targetLanguage = fields['target_language']?.value;

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
        enableWordTimestamps: wordTimestamps,
        enableDiarization: diarize,
        translate: translate,
        initialPrompt: initialPrompt,
        vad: vad,
        restorePunctuation: restorePunctuation,
        temperature: temperature,
        bestOf: bestOf,
        askPrompt: askPrompt,
        targetLanguage: targetLanguage,
        advanced: AdvancedTranscribeOptions(
          alignerModel: alignerModel,
          hotwords: hotwords,
          hotwordsBoost: hotwordsBoost,
        ),
      );
    } catch (e, st) {
      Log.instance
          .e('server', 'transcribe failed', error: e, stack: st);
      return Response.internalServerError(body: 'transcribe failed: $e');
    } finally {
      try {
        await tempFile.delete();
      } catch (e) {
        Log.instance.d('server', 'temp file cleanup failed',
            fields: {'path': tempFile.path, 'err': e.toString()});
      }
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
      case 'diarized_json':
        // §11.4 — Groups segments by speaker, matching CrispASR CLI's
        // --output-format diarized_json (#206).
        final speakers = <String, List<Map<String, Object?>>>{};
        for (var i = 0; i < segments.length; i++) {
          final spk = segments[i].speaker ?? 'unknown';
          (speakers[spk] ??= []).add({
            'id': i,
            'start': segments[i].startTime,
            'end': segments[i].endTime,
            'text': segments[i].text,
          });
        }
        final diarBody = jsonEncode({
          'task': 'transcribe',
          'duration': segments.isEmpty
              ? 0.0
              : segments.last.endTime - segments.first.startTime,
          'speakers': speakers,
        });
        return Response.ok(diarBody,
            headers: const {'content-type': 'application/json'});
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

  /// OpenAI-compatible TTS endpoint.
  ///
  /// Accepts **either** a JSON body `{model, input, voice, speed}` or a
  /// **multipart/form-data** upload with the same fields plus an optional
  /// `voice_file` part (a WAV/FLAC/MP3 reference for voice cloning).
  /// When `voice_file` is present it's saved to a temp path and passed
  /// to `tts.prepare(voiceName: tempPath)`.
  ///
  /// Returns audio bytes (WAV); `response_format` only routes content-
  /// type — the underlying PCM is always 24 kHz mono float32 from
  /// CrispASR.
  Future<Response> _handleSpeech(Request request) async {
    final contentType = request.headers['content-type'] ?? '';

    String? input;
    String? voice;
    String? modelName;
    bool spokenDisclaimer = true;
    double speed = 1.0;
    File? voiceTempFile;

    if (contentType.startsWith('multipart/form-data')) {
      // Multipart: supports voice-clone file upload.
      final boundary = _parseBoundary(contentType);
      if (boundary == null) {
        return Response.badRequest(body: 'missing boundary in content-type');
      }
      final fields = await _parseMultipart(request.read(), boundary);
      input = fields['input']?.value;
      voice = fields['voice']?.value;
      modelName = fields['model']?.value;
      spokenDisclaimer =
          fields['spoken_disclaimer']?.value?.toLowerCase() != 'false';
      speed = (double.tryParse(fields['speed']?.value ?? '') ?? 1.0)
          .clamp(0.25, 4.0)
          .toDouble();
      // Voice-clone reference file.
      final voicePart = fields['voice_file'];
      if (voicePart != null && voicePart.bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final ext = p.extension(voicePart.filename ?? 'voice.wav');
        voiceTempFile = File(p.join(tempDir.path,
            'crispasr-server-voice-${DateTime.now().millisecondsSinceEpoch}$ext'));
        await voiceTempFile.writeAsBytes(voicePart.bytes!);
        // Use the temp file path as the voice reference.
        voice = voiceTempFile.path;
      }
    } else {
      // JSON body (original path).
      final body = await request.readAsString();
      Map<String, dynamic> args;
      try {
        args = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        return Response.badRequest(body: 'invalid JSON: $e');
      }
      input = args['input'] as String?;
      voice = args['voice'] as String?;
      modelName = args['model'] as String?;
      spokenDisclaimer = args['spoken_disclaimer'] as bool? ?? true;
      speed = ((args['speed'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.25, 4.0)
          .toDouble();
    }
    Log.instance.i('server', 'tts request', fields: {
      'model': modelName ?? '',
      'voice': voice ?? '',
      'text_len': input?.length ?? 0,
      'speed': speed,
    });
    if (input == null || input.trim().isEmpty || modelName == null) {
      if (voiceTempFile != null) {
        try { await voiceTempFile.delete(); } catch (_) {}
      }
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
      if (voiceTempFile != null) {
        try { await voiceTempFile.delete(); } catch (_) {}
      }
      return Response.internalServerError(
        body: 'tts.prepare failed: '
            '${status.errorMessage ?? status.missingModelName ?? status.missingVoiceName ?? "unknown"}',
      );
    }
    try {
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
    } finally {
      if (voiceTempFile != null) {
        try { await voiceTempFile.delete(); } catch (_) {}
      }
    }
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
    Log.instance.i('server', 'translate request', fields: {
      'model': modelName ?? '',
      'src': src ?? '',
      'tgt': tgt ?? '',
      'text_len': text?.length ?? 0,
    });
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

  /// Decode the `file` part of a multipart upload into 16 kHz mono PCM
  /// via the same AudioService path the GUI uses. Throws [FormatException]
  /// on a malformed request (the caller maps that to 400).
  Future<AudioData> _decodeUpload(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.startsWith('multipart/form-data')) {
      throw FormatException('expected multipart/form-data; got $contentType');
    }
    final boundary = _parseBoundary(contentType);
    if (boundary == null) {
      throw const FormatException('missing boundary in content-type');
    }
    final fields = await _parseMultipart(request.read(), boundary);
    final filePart = fields['file'];
    if (filePart == null || filePart.bytes == null) {
      throw const FormatException('missing required field "file"');
    }
    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(filePart.filename ?? 'audio.wav');
    final tempFile = File(p.join(tempDir.path,
        'crispasr-server-${DateTime.now().millisecondsSinceEpoch}$ext'));
    await tempFile.writeAsBytes(filePart.bytes!);
    try {
      return await ref.read(audioServiceProvider).loadAudioFile(tempFile);
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {/* best-effort cleanup */}
    }
  }

  /// VAD: multipart `file` → `{spans: [{start, end}]}` (seconds).
  Future<Response> _handleVad(Request request) async {
    AudioData audio;
    try {
      audio = await _decodeUpload(request);
    } on FormatException catch (e) {
      return Response.badRequest(body: e.message);
    } catch (e) {
      return Response.badRequest(body: 'audio decode failed: $e');
    }
    final spans =
        await ref.read(vadServiceProvider).detectSpeechSpans(audio.samples);
    return Response.ok(
      jsonEncode({
        'spans': [
          for (final s in spans) {'start': s.start, 'end': s.end}
        ]
      }),
      headers: const {'content-type': 'application/json'},
    );
  }

  /// Language ID: multipart `file` → `{language}` or 500 when no model.
  Future<Response> _handleLanguage(Request request) async {
    AudioData audio;
    try {
      audio = await _decodeUpload(request);
    } on FormatException catch (e) {
      return Response.badRequest(body: e.message);
    } catch (e) {
      return Response.badRequest(body: 'audio decode failed: $e');
    }
    final code =
        await ref.read(lidServiceProvider).detectIfModelAvailable(audio.samples);
    if (code == null) {
      return Response.internalServerError(
          body: 'no LID model available — download a multilingual ASR or '
              'LID model first');
    }
    return Response.ok(jsonEncode({'language': code}),
        headers: const {'content-type': 'application/json'});
  }

  /// Punctuation restoration: JSON `{text}` → `{text}`.
  Future<Response> _handlePunctuate(Request request) async {
    Map<String, dynamic> args;
    try {
      args = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: 'invalid JSON: $e');
    }
    final text = args['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      return Response.badRequest(body: 'missing required field: text');
    }
    final restored = await ref.read(puncServiceProvider).restore(
        [TranscriptionSegment(text: text, startTime: 0, endTime: 0)]);
    return Response.ok(
      jsonEncode({'text': restored.isEmpty ? text : restored.first.text}),
      headers: const {'content-type': 'application/json'},
    );
  }

  /// Pull the raw `file` part bytes from a multipart upload (no decode).
  /// Throws [FormatException] on a malformed request.
  Future<_MultipartField> _uploadFilePart(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.startsWith('multipart/form-data')) {
      throw FormatException('expected multipart/form-data; got $contentType');
    }
    final boundary = _parseBoundary(contentType);
    if (boundary == null) {
      throw const FormatException('missing boundary in content-type');
    }
    final fields = await _parseMultipart(request.read(), boundary);
    final filePart = fields['file'];
    if (filePart == null || filePart.bytes == null) {
      throw const FormatException('missing required field "file"');
    }
    return filePart;
  }

  /// Diarization: multipart `file` → transcribe (current engine) + label
  /// speakers via pyannote → `{segments: [{start, end, speaker, text}]}`.
  Future<Response> _handleDiarize(Request request) async {
    _MultipartField part;
    try {
      part = await _uploadFilePart(request);
    } on FormatException catch (e) {
      return Response.badRequest(body: e.message);
    }
    final tx = ref.read(transcriptionServiceProvider);
    if (tx.currentEngine == null) {
      return Response.internalServerError(
          body: 'no transcription engine loaded — pick a model in the app first');
    }
    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(part.filename ?? 'audio.wav');
    final tempFile = File(p.join(tempDir.path,
        'crispasr-server-diar-${DateTime.now().millisecondsSinceEpoch}$ext'));
    await tempFile.writeAsBytes(part.bytes!);
    try {
      final audio = await ref.read(audioServiceProvider).loadAudioFile(tempFile);
      final segments = await tx.transcribeFile(tempFile);
      final diar = DiarizationService(
          modelService: ref.read(modelServiceProvider));
      final labelled = await diar.diarizeSegments(
        audio,
        segments,
        method: crispasr.DiarizeMethod.pyannote,
      );
      return Response.ok(
        jsonEncode({
          'segments': [
            for (final s in labelled)
              {
                'start': s.startTime,
                'end': s.endTime,
                'speaker': s.speaker,
                'text': s.text,
              }
          ]
        }),
        headers: const {'content-type': 'application/json'},
      );
    } catch (e, st) {
      Log.instance.e('server', 'diarize failed', error: e, stack: st);
      return Response.internalServerError(body: 'diarize failed: $e');
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {/* best-effort */}
    }
  }

  /// Watermark detect or embed: multipart `file` (a WAV) + optional
  /// `mode` field (`detect` [default] or `embed`).
  ///
  /// Detect → `{watermarked, synthetic, timestamp}` JSON.
  /// Embed → watermarked WAV binary response.
  Future<Response> _handleWatermark(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.startsWith('multipart/form-data')) {
      return Response.badRequest(
          body: 'expected multipart/form-data; got $contentType');
    }
    final boundary = _parseBoundary(contentType);
    if (boundary == null) {
      return Response.badRequest(body: 'missing boundary in content-type');
    }
    final fields = await _parseMultipart(request.read(), boundary);
    final filePart = fields['file'];
    if (filePart == null || filePart.bytes == null) {
      return Response.badRequest(body: 'missing required field "file"');
    }
    final mode = fields['mode']?.value ?? 'detect';

    if (mode == 'embed') {
      // Decode audio to get PCM + sample rate.
      final tempDir = await getTemporaryDirectory();
      final ext = p.extension(filePart.filename ?? 'audio.wav');
      final tempFile = File(p.join(tempDir.path,
          'crispasr-server-wm-${DateTime.now().millisecondsSinceEpoch}$ext'));
      await tempFile.writeAsBytes(filePart.bytes!);
      AudioData audio;
      try {
        audio =
            await ref.read(audioServiceProvider).loadAudioFile(tempFile);
      } catch (e) {
        return Response.badRequest(body: 'audio decode failed: $e');
      } finally {
        try { await tempFile.delete(); } catch (_) {}
      }
      final wm = crispasr.CrispasrWatermark.embed(
          audio.samples, alpha: 0.1);
      return Response.ok(_wavBytes(wm, audio.sampleRate), headers: const {
        'content-type': 'audio/wav',
        'x-content-ai-generated': 'true',
      });
    }

    // Default: detect mode.
    final info = AudioWatermarkService.detectWatermark(
        Uint8List.fromList(filePart.bytes!));
    return Response.ok(
      jsonEncode({
        'watermarked': info != null,
        if (info != null) 'synthetic': info.synthetic,
        if (info != null)
          'timestamp': info.timestamp.toUtc().toIso8601String(),
      }),
      headers: const {'content-type': 'application/json'},
    );
  }

  /// Forced alignment: multipart `file` (audio) + `text` (transcript) →
  /// `{words: [{word, start, end}]}`. Optional `language` field picks a
  /// language-matched wav2vec2 aligner; optional `model` overrides.
  Future<Response> _handleAlign(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.startsWith('multipart/form-data')) {
      return Response.badRequest(
          body: 'expected multipart/form-data; got $contentType');
    }
    final boundary = _parseBoundary(contentType);
    if (boundary == null) {
      return Response.badRequest(body: 'missing boundary in content-type');
    }
    final fields = await _parseMultipart(request.read(), boundary);
    final filePart = fields['file'];
    if (filePart == null || filePart.bytes == null) {
      return Response.badRequest(body: 'missing required field "file"');
    }
    final text = fields['text']?.value;
    if (text == null || text.trim().isEmpty) {
      return Response.badRequest(body: 'missing required field "text"');
    }
    final language = fields['language']?.value;
    final modelOverride = fields['model']?.value;

    // Decode to 16 kHz mono PCM.
    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(filePart.filename ?? 'audio.wav');
    final tempFile = File(p.join(tempDir.path,
        'crispasr-server-align-${DateTime.now().millisecondsSinceEpoch}$ext'));
    await tempFile.writeAsBytes(filePart.bytes!);
    Float32List pcm;
    try {
      final audio =
          await ref.read(audioServiceProvider).loadAudioFile(tempFile);
      pcm = audio.samples;
    } catch (e) {
      return Response.badRequest(body: 'audio decode failed: $e');
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    // Find aligner.
    final aligner = ref.read(alignerServiceProvider);
    final alignerPath = await aligner.findAligner(
        language: language, explicit: modelOverride);
    if (alignerPath == null) {
      return Response.internalServerError(
          body: 'no aligner model available — download canary-ctc-aligner '
              'or a wav2vec2 aligner via Model Management');
    }

    List<crispasr.AlignedWord> words;
    try {
      words = crispasr.alignWords(
          alignerModel: alignerPath, transcript: text, pcm: pcm);
    } catch (e) {
      return Response.internalServerError(body: 'alignment failed: $e');
    }
    return Response.ok(
      jsonEncode({
        'words': words
            .map((w) => {
                  'word': w.text,
                  'start': w.start,
                  'end': w.end,
                })
            .toList(),
      }),
      headers: const {'content-type': 'application/json'},
    );
  }

  /// Text language identification: JSON `{text, model?}` → `{language}`.
  /// Uses the text-LID dispatcher (CLD3/GlotLID/FastText-176).
  Future<Response> _handleTextLanguage(Request request) async {
    Map<String, dynamic> args;
    try {
      args = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: 'invalid JSON: $e');
    }
    final text = args['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      return Response.badRequest(body: 'missing required field: text');
    }
    final modelPath = args['model'] as String?;

    // Try to find a text-LID model (CLD3 / GlotLID / FastText-176).
    final ms = ref.read(modelServiceProvider);
    await ms.initialize();
    final modelsDir = ms.whisperCppDir();

    // Scan for text-LID GGUFs in priority order.
    String? lidModel = modelPath;
    if (lidModel == null) {
      const candidates = [
        'cld3-f16.gguf',
        'cld3-f32.gguf',
        'glotlid-f16.gguf',
        'fasttext-lid176-f16.gguf',
      ];
      for (final c in candidates) {
        final f = File(p.join(modelsDir, c));
        if (f.existsSync()) {
          lidModel = f.path;
          break;
        }
      }
    }
    if (lidModel == null) {
      return Response.internalServerError(
          body: 'no text-LID model available — download CLD3, GlotLID, '
              'or FastText-176 via Model Management');
    }

    crispasr.TextLanguage? result;
    try {
      result = crispasr.detectTextLanguage(text, lidModel);
    } catch (e) {
      return Response.internalServerError(
          body: 'text language detection failed: $e');
    }
    if (result == null) {
      return Response.internalServerError(
          body: 'text-LID returned no result');
    }
    return Response.ok(
        jsonEncode({
          'language': result.code,
          'confidence': result.confidence,
        }),
        headers: const {'content-type': 'application/json'});
  }

  /// Denoise: multipart `file` → denoised WAV via RNNoise.
  Future<Response> _handleDenoise(Request request) async {
    AudioData audio;
    try {
      audio = await _decodeUpload(request);
    } on FormatException catch (e) {
      return Response.badRequest(body: e.message);
    } catch (e) {
      return Response.badRequest(body: 'audio decode failed: $e');
    }
    Float32List enhanced;
    try {
      enhanced = crispasr.enhanceAudioRnnoise(audio.samples);
    } catch (e) {
      return Response.internalServerError(body: 'denoise failed: $e');
    }
    return Response.ok(_wavBytes(enhanced, audio.sampleRate), headers: const {
      'content-type': 'audio/wav',
    });
  }

  /// Speech-to-speech: multipart `file` (input audio) + optional
  /// `model` (TTS backend) → synthesised WAV response.
  Future<Response> _handleS2s(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.startsWith('multipart/form-data')) {
      return Response.badRequest(
          body: 'expected multipart/form-data; got $contentType');
    }
    final boundary = _parseBoundary(contentType);
    if (boundary == null) {
      return Response.badRequest(body: 'missing boundary in content-type');
    }
    final fields = await _parseMultipart(request.read(), boundary);
    final filePart = fields['file'];
    if (filePart == null || filePart.bytes == null) {
      return Response.badRequest(body: 'missing required field "file"');
    }
    final modelName = fields['model']?.value;

    // Decode input audio to 16 kHz mono PCM.
    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(filePart.filename ?? 'audio.wav');
    final tempFile = File(p.join(tempDir.path,
        'crispasr-server-s2s-${DateTime.now().millisecondsSinceEpoch}$ext'));
    await tempFile.writeAsBytes(filePart.bytes!);
    Float32List pcm;
    try {
      final audio =
          await ref.read(audioServiceProvider).loadAudioFile(tempFile);
      pcm = audio.samples;
    } catch (e) {
      return Response.badRequest(body: 'audio decode failed: $e');
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    final tts = ref.read(ttsServiceProvider);
    if (modelName != null) {
      final status = await tts.prepare(modelName: modelName);
      if (!status.ready) {
        return Response.internalServerError(
            body: 'tts.prepare failed for s2s: '
                '${status.errorMessage ?? "unknown"}');
      }
    }
    SynthesizedAudio? result;
    try {
      result = await tts.speechToSpeech(pcm);
    } catch (e) {
      return Response.internalServerError(
          body: 'speech-to-speech failed: $e');
    }
    if (result == null) {
      return Response.internalServerError(
          body: 'speech-to-speech returned null — no S2S-capable model '
              'loaded (requires lfm2-audio or mini-omni2)');
    }
    final wav = await tts.writeWav(result);
    final bytes = await wav.readAsBytes();
    return Response.ok(bytes, headers: const {
      'content-type': 'audio/wav',
      'x-content-ai-generated': 'true',
    });
  }

  /// WebSocket streaming transcription handler.
  ///
  /// Protocol (mirrors CrispASR's `/ws` surface):
  ///  1. Client sends a JSON config message: `{"language":"en", ...}`.
  ///  2. Client sends binary PCM frames (16-bit LE mono 16 kHz).
  ///  3. Server pushes JSON `{"text":"...", "start":0.0, "end":1.5}`
  ///     for each committed segment.
  ///  4. Client closes the socket; server flushes and sends a final
  ///     `{"text":"...", "final":true}` before closing its end.
  void _handleWebSocketStream(WebSocket ws) {
    Log.instance.i('server', 'WebSocket stream opened');
    final tx = ref.read(transcriptionServiceProvider);
    if (tx.currentEngine == null) {
      ws.add(jsonEncode({'error': 'no transcription engine loaded'}));
      ws.close();
      return;
    }

    // The streaming session is opened lazily after the first config or
    // binary frame arrives. We accumulate audio in a StreamController
    // and pipe it through the engine's transcribeStream.
    StreamController<Float32List>? audioController;
    StreamSubscription<TranscriptionSegment>? transcriptSub;
    String? language;
    bool sessionStarted = false;

    void startSession() {
      if (sessionStarted) return;
      sessionStarted = true;
      audioController = StreamController<Float32List>();
      final stream = tx.transcribeStream(
        audioController!.stream,
        language: language,
      );
      if (stream == null) {
        ws.add(jsonEncode({'error': 'streaming not supported by current model'}));
        ws.close();
        return;
      }
      transcriptSub = stream.listen(
        (seg) {
          ws.add(jsonEncode({
            'text': seg.text,
            'start': seg.startTime,
            'end': seg.endTime,
            if (seg.metadata.containsKey('final'))
              'final': seg.metadata['final'],
          }));
        },
        onError: (Object e) {
          ws.add(jsonEncode({'error': e.toString()}));
        },
        onDone: () {
          ws.add(jsonEncode({'done': true}));
        },
      );
    }

    ws.listen(
      (data) {
        if (data is String) {
          // JSON config message.
          try {
            final config = jsonDecode(data) as Map<String, dynamic>;
            language = config['language'] as String?;
            // Start the session on config if not already started.
            if (!sessionStarted) startSession();
          } catch (e) {
            ws.add(jsonEncode({'error': 'invalid config JSON: $e'}));
          }
        } else if (data is List<int>) {
          // Binary PCM frame — 16-bit LE mono 16 kHz.
          if (!sessionStarted) startSession();
          // Convert 16-bit LE PCM to Float32List.
          final bytes = Uint8List.fromList(data);
          final bd = ByteData.view(bytes.buffer);
          final nSamples = bytes.length ~/ 2;
          final pcm = Float32List(nSamples);
          for (var i = 0; i < nSamples; i++) {
            pcm[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
          }
          audioController?.add(pcm);
        }
      },
      onDone: () {
        Log.instance.i('server', 'WebSocket stream closed by client');
        audioController?.close();
        transcriptSub?.cancel();
      },
      onError: (Object e) {
        Log.instance.w('server', 'WebSocket error', fields: {'err': '$e'});
        audioController?.close();
        transcriptSub?.cancel();
      },
    );
  }

  /// Encode Float32List PCM to a minimal 16-bit mono WAV in memory.
  Uint8List _wavBytes(Float32List pcm, int sampleRate) {
    final dataLen = pcm.length * 2;
    final fileLen = 36 + dataLen;
    final buf = ByteData(44 + pcm.length * 2);
    // RIFF header
    buf.setUint32(0, 0x52494646, Endian.big); // 'RIFF'
    buf.setUint32(4, fileLen, Endian.little);
    buf.setUint32(8, 0x57415645, Endian.big); // 'WAVE'
    // fmt chunk
    buf.setUint32(12, 0x666d7420, Endian.big); // 'fmt '
    buf.setUint32(16, 16, Endian.little); // chunk size
    buf.setUint16(20, 1, Endian.little); // PCM
    buf.setUint16(22, 1, Endian.little); // mono
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buf.setUint16(32, 2, Endian.little); // block align
    buf.setUint16(34, 16, Endian.little); // bits per sample
    // data chunk
    buf.setUint32(36, 0x64617461, Endian.big); // 'data'
    buf.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      final s = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
      buf.setInt16(44 + i * 2, s, Endian.little);
    }
    return buf.buffer.asUint8List();
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
