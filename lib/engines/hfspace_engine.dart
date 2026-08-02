// HF Space engine — routes transcription through a remote CrispASR server
// (typically https://cstr-crispasr.hf.space) via the OpenAI-compatible HTTP API.
// Used automatically on web; optionally available on desktop via settings.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../services/log_service.dart';
import '../services/model_service.dart';
import '../services/transcription_service.dart' show AdvancedTranscribeOptions;
import '../utils/affective_prompt_guard.dart';
import '../utils/emotion_inference.dart';
import 'transcription_engine.dart';

/// ASR backends available on the HF Space (free-tier feasible).
const _asrModels = <_RemoteModel>[
  _RemoteModel('whisper', 'Whisper base', 'auto', 'auto', 147000000,
      'OpenAI Whisper. 99 langs. Native timestamps + speech translation.'),
  _RemoteModel('moonshine', 'Moonshine tiny', 'auto', 'en', 37000000,
      'Smallest model. ~16× realtime on CPU. English only.'),
  _RemoteModel('moonshine-de', 'Moonshine base DE', 'auto', 'de', 150000000,
      'fidoriel German fine-tune. 6.9% WER on CV22.'),
  _RemoteModel('parakeet', 'Parakeet TDT v3', 'auto', 'auto', 467000000,
      'NVIDIA Parakeet. 25 EU langs, word timestamps.'),
  _RemoteModel('wav2vec2', 'Wav2vec2 XLSR EN', 'auto', 'en', 212000000,
      'Lightweight CTC. No punctuation/casing.'),
  _RemoteModel('fastconformer-ctc', 'FastConformer CTC 0.6B', 'auto', 'en',
      250000000, 'NeMo FastConformer + CTC. Fastest reasonable EN backend.'),
  _RemoteModel('cohere', 'Cohere Transcribe', 'auto', 'auto', 550000000,
      'Cohere Labs. Punctuation + casing. 13 langs.'),
  _RemoteModel('qwen3', 'Qwen3 ASR 0.6B', 'auto', 'auto', 500000000,
      'Speech-LLM (Whisper enc + Qwen3 0.6B). 30 langs.'),
  _RemoteModel('canary', 'Canary 1B', 'auto', 'auto', 800000000,
      'NVIDIA Canary. Multilingual + speech translation.'),
  _RemoteModel('hubert', 'HuBERT CTC', 'auto', 'en', 380000000,
      'Self-supervised CTC encoder. English.'),
  _RemoteModel('data2vec', 'Data2Vec CTC', 'auto', 'en', 380000000,
      'Meta Data2Vec CTC encoder. English.'),
];

class _RemoteModel {
  final String backend;
  final String displayName;
  final String modelArg;
  final String defaultLang;
  final int approxBytes;
  final String blurb;
  const _RemoteModel(this.backend, this.displayName, this.modelArg,
      this.defaultLang, this.approxBytes, this.blurb);
}

/// How [HfSpaceEngine] talks to the Space.
///
/// * [openai] — the OpenAI-compatible REST API (`/v1/audio/transcriptions`,
///   `/health`, `/load`). Needs the Space to expose those routes; the
///   CrispASR space does, via its FastAPI `/v1` proxy. Clean + preferred.
/// * [gradio] — the Space's auto-generated Gradio call API
///   (`/gradio_api/upload` + `/gradio_api/call/<fn>`). Works against *any*
///   Gradio space, even one exposing only the UI, at the cost of being
///   coupled to the demo's function signature. Portable fallback for future
///   spaces that don't ship the `/v1` proxy.
enum HfSpaceApiMode { openai, gradio }

class HfSpaceEngine implements TranscriptionEngine {
  HfSpaceEngine({String? baseUrl, Dio? dio, HfSpaceApiMode apiMode = HfSpaceApiMode.openai})
      : _baseUrl = baseUrl ?? 'https://cstr-crispasr.hf.space',
        _apiMode = apiMode,
        _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 900),
  ));

  String _baseUrl;
  HfSpaceApiMode _apiMode;
  final Dio _dio;
  bool _initialized = false;
  bool _processing = false;
  String? _currentModelId;
  CancelToken? _cancelToken;

  void setBaseUrl(String url) => _baseUrl = url.replaceAll(RegExp(r'/+$'), '');

  /// Switch between the OpenAI `/v1` REST API and the raw Gradio call API.
  /// See [HfSpaceApiMode]. Defaults to [HfSpaceApiMode.openai].
  void setApiMode(HfSpaceApiMode mode) => _apiMode = mode;
  HfSpaceApiMode get apiMode => _apiMode;

  // -- Identity -----------------------------------------------------------

  @override
  String get engineId => 'hfspace';
  @override
  String get engineName => 'CrispASR Cloud';
  @override
  String get version => '1.0.0';

  // -- Capabilities -------------------------------------------------------

  @override
  bool get supportsStreaming => false;
  @override
  bool get supportsLanguageDetection => true;
  @override
  bool get supportsWordTimestamps => true;
  @override
  bool get supportsSpeakerDiarization => false;
  @override
  List<String> get supportedLanguages => const [
        'en', 'de', 'fr', 'es', 'it', 'pt', 'nl', 'pl', 'ru',
        'zh', 'ja', 'ko', 'ar', 'hi', 'auto',
      ];

  // -- Status -------------------------------------------------------------

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isProcessing => _processing;

  // -- Lifecycle ----------------------------------------------------------

  @override
  Future<bool> initialize(
      {ModelService? modelService, Map<String, dynamic>? config}) async {
    if (config != null && config['baseUrl'] is String) {
      setBaseUrl(config['baseUrl'] as String);
    }
    // Probe the server — HF Spaces sleep after inactivity so we may need
    // to wait for a cold-start. In gradio mode there is no /health, so probe
    // the always-present Gradio API descriptor instead.
    final healthPath =
        _apiMode == HfSpaceApiMode.gradio ? '/gradio_api/info' : '/health';
    for (var attempt = 0; attempt < 24; attempt++) {
      try {
        final r = await _dio.get<dynamic>('$_baseUrl$healthPath',
            options: Options(receiveTimeout: const Duration(seconds: 10)));
        if (r.statusCode == 200) {
          _initialized = true;
          Log.instance.i('hfspace', 'connected to $_baseUrl');
          return true;
        }
        if (r.statusCode == 503) {
          Log.instance.i('hfspace',
              'server loading (attempt ${attempt + 1}/24), retrying...');
        }
      } on DioException catch (e) {
        Log.instance.d('hfspace',
            'probe attempt ${attempt + 1}/24: ${e.type.name}');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    Log.instance.w('hfspace', 'server did not become ready after 120s');
    // Still mark initialized so the UI can show the engine with a warning
    // rather than falling back to mock.
    _initialized = true;
    return true;
  }

  @override
  Future<void> dispose() async {
    _cancelToken?.cancel('disposed');
    _dio.close(force: true);
  }

  // -- Model management ---------------------------------------------------

  @override
  Future<List<EngineModel>> getAvailableModels() async {
    return _asrModels
        .map((m) => EngineModel(
              id: m.backend,
              name: m.displayName,
              description: m.blurb,
              sizeBytes: m.approxBytes,
              supportedLanguages:
                  m.defaultLang == 'auto' ? supportedLanguages : [m.defaultLang],
              isDownloaded: true, // server-side, always "available"
              metadata: {
                'backend': m.backend,
                'modelArg': m.modelArg,
                'defaultLang': m.defaultLang,
              },
            ))
        .toList();
  }

  @override
  Future<bool> loadModel(String modelId,
      {void Function(double progress)? onProgress}) async {
    final spec = _asrModels.where((m) => m.backend == modelId).firstOrNull;
    if (spec == null) {
      throw ModelLoadException(
          'Unknown backend: $modelId', engineId, modelId);
    }
    onProgress?.call(0.1);
    try {
      final r = await _dio.post<dynamic>(
        '$_baseUrl/load',
        data: FormData.fromMap({
          'backend': spec.backend,
          'model': spec.modelArg,
          'language': spec.defaultLang,
        }),
        options: Options(receiveTimeout: const Duration(seconds: 300)),
      );
      if (r.statusCode != null && r.statusCode! >= 400) {
        throw ModelLoadException(
            '/load returned ${r.statusCode}', engineId, modelId);
      }
      _currentModelId = modelId;
      onProgress?.call(1.0);
      Log.instance.i('hfspace', 'loaded backend=$modelId');
      return true;
    } on DioException catch (e) {
      throw ModelLoadException(
          'Failed to load $modelId: ${e.message}', engineId, modelId, e);
    }
  }

  @override
  Future<void> unloadModel() async {
    _currentModelId = null;
  }

  @override
  String? get currentModelId => _currentModelId;

  // -- Transcription ------------------------------------------------------

  @override
  Future<TranscriptionResult> transcribe(
    Float32List audioData, {
    String? language,
    bool enableWordTimestamps = false,
    bool enableSpeakerDiarization = false,
    bool translate = false,
    bool beamSearch = false,
    String? initialPrompt,
    bool vad = false,
    String? vadModelPath,
    String? targetLanguage,
    String? askPrompt,
    double temperature = 0.0,
    int bestOf = 1,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
    double startOffsetSec = 0.0,
    void Function(TranscriptionSegment segment)? onSegment,
    void Function(double progress)? onProgress,
  }) async {
    // Art. 5(1)(f) / Annex III 1(c): the same screen `CrispasrEngine`
    // applies. This engine does not forward [askPrompt] to the server at
    // all, so nothing affective can reach a model through it today — but
    // the guard belongs at every engine's entry rather than at the one
    // where the feature was built, which is how the SenseVoice route
    // survived two audits. Refusing rather than ignoring also means a
    // caller learns the prompt was rejected instead of quietly receiving a
    // plain transcript.
    final affectiveTerm = AffectivePromptGuard.offendingTerm(askPrompt);
    if (affectiveTerm != null) {
      Log.instance.w('hfspace', 'audio Q&A prompt refused (affective)',
          fields: {'term': affectiveTerm});
      throw AffectivePromptException(
          AffectivePromptGuard.refusalMessage(affectiveTerm),
          engineId,
          affectiveTerm);
    }
    // Encode Float32List PCM as 16-bit WAV for upload.
    final wavBytes = _encodeWav(audioData, 16000);
    return transcribeBytes(
      wavBytes,
      'audio.wav',
      language: language,
      translate: translate,
      initialPrompt: initialPrompt,
      temperature: temperature,
      onSegment: onSegment,
      onProgress: onProgress,
    );
  }

  /// Transcribe raw audio file bytes (wav/mp3/flac/ogg) without needing
  /// to decode to PCM first. This is the primary path on web where we
  /// get bytes from the file picker, not a filesystem path.
  Future<TranscriptionResult> transcribeBytes(
    Uint8List fileBytes,
    String filename, {
    String? language,
    bool translate = false,
    bool vad = false,
    bool diarize = false,
    bool punctuation = true,
    String? initialPrompt,
    double temperature = 0.0,
    void Function(TranscriptionSegment segment)? onSegment,
    void Function(double progress)? onProgress,
  }) async {
    if (_apiMode == HfSpaceApiMode.gradio) {
      return _transcribeViaGradio(fileBytes, filename,
          language: language,
          initialPrompt: initialPrompt,
          temperature: temperature,
          onSegment: onSegment,
          onProgress: onProgress);
    }
    _processing = true;
    _cancelToken = CancelToken();
    final sw = Stopwatch()..start();
    onProgress?.call(0.05);

    try {
      final fields = <String, dynamic>{
        'model': 'loaded-model',
        'response_format': 'verbose_json',
        'temperature': temperature.toStringAsFixed(2),
      };
      if (language != null && language != 'auto') {
        fields['language'] = language;
      }
      if (initialPrompt != null && initialPrompt.isNotEmpty) {
        fields['prompt'] = initialPrompt;
      }
      if (translate) fields['translate'] = 'true';
      if (vad) fields['vad'] = 'true';
      if (diarize) fields['diarize'] = 'true';
      if (!punctuation) fields['punctuation'] = 'false';

      final formData = FormData.fromMap({
        ...fields,
        'file': MultipartFile.fromBytes(fileBytes, filename: filename),
      });

      onProgress?.call(0.2);

      final r = await _dio.post<dynamic>(
        '$_baseUrl/v1/audio/transcriptions',
        data: formData,
        cancelToken: _cancelToken,
      );

      onProgress?.call(0.8);

      if (r.statusCode != null && r.statusCode! >= 400) {
        throw TranscriptionException(
            'Server returned ${r.statusCode}: ${r.data}', engineId);
      }

      final json = r.data is Map<String, dynamic>
          ? r.data as Map<String, dynamic>
          : <String, dynamic>{};
      // Annex III 1(c): the remote server decides which backend runs, so
      // anything SenseVoice-shaped can come back with inline `<|HAPPY|>`
      // emotion tags. Strip them here, at this engine's parse boundary,
      // exactly as `CrispasrEngine` does at its own — the app performs no
      // emotion recognition regardless of which engine produced the text.
      final text = EmotionInference.strip((json['text'] as String?) ?? '').text;
      final rawSegments = json['segments'] as List<dynamic>? ?? [];
      final detectedLang = json['language'] as String?;

      final segments = <TranscriptionSegment>[];
      for (final s in rawSegments) {
        if (s is! Map<String, dynamic>) continue;
        final seg = TranscriptionSegment.fromModelText(
          rawText: (s['text'] as String?) ?? '',
          startTime: (s['start'] as num?)?.toDouble() ?? 0.0,
          endTime: (s['end'] as num?)?.toDouble() ?? 0.0,
          confidence: (s['avg_logprob'] as num?)?.toDouble() ?? 1.0,
          speaker: s['speaker'] as String?,
          metadata: {
            'engine': engineId,
            // Art. 50(2): the server also translates when asked, and this
            // engine's caller passes the flag through. Stamp it so the
            // exporters describe the result as a translation rather than as
            // a record of what was said.
            if (translate) 'generated': 'translation',
          },
        );
        segments.add(seg);
        onSegment?.call(seg);
      }

      sw.stop();
      onProgress?.call(1.0);

      final result = TranscriptionResult(
        fullText: text,
        segments: segments,
        processingTime: sw.elapsed,
        detectedLanguage: detectedLang,
        metadata: {'engine': engineId, 'baseUrl': _baseUrl},
      );
      return result;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw TranscriptionException('Cancelled', engineId);
      }
      throw TranscriptionException(
          'HTTP error: ${e.message}', engineId, e);
    } finally {
      _processing = false;
      _cancelToken = null;
    }
  }

  // -- Gradio call API (portable fallback, see [HfSpaceApiMode.gradio]) ----

  /// Transcribe via the Space's auto-generated Gradio API instead of the
  /// `/v1` REST proxy: upload the file, invoke the demo's `transcribe`
  /// function, then read the SSE result. Coupled to the demo's input order
  /// (audio, language, prompt, temperature, response_format) and outputs
  /// (transcript text, raw verbose_json string).
  Future<TranscriptionResult> _transcribeViaGradio(
    Uint8List fileBytes,
    String filename, {
    String? language,
    String? initialPrompt,
    double temperature = 0.0,
    void Function(TranscriptionSegment segment)? onSegment,
    void Function(double progress)? onProgress,
  }) async {
    _processing = true;
    _cancelToken = CancelToken();
    final sw = Stopwatch()..start();
    onProgress?.call(0.05);
    try {
      // 1. Upload the audio to the Gradio file store.
      final up = await _dio.post<dynamic>(
        '$_baseUrl/gradio_api/upload',
        data: FormData.fromMap({
          'files': MultipartFile.fromBytes(fileBytes, filename: filename),
        }),
        cancelToken: _cancelToken,
      );
      final uploaded = (up.data as List).first as String;
      onProgress?.call(0.2);

      // 2. Invoke `transcribe`; data order matches the demo's inputs.
      final call = await _dio.post<dynamic>(
        '$_baseUrl/gradio_api/call/transcribe',
        data: {
          'data': [
            {
              'path': uploaded,
              'meta': {'_type': 'gradio.FileData'},
            },
            (language == null || language == 'auto') ? null : language,
            initialPrompt ?? '',
            temperature,
            'verbose_json',
          ],
        },
        cancelToken: _cancelToken,
      );
      final eventId =
          (call.data as Map<String, dynamic>)['event_id'] as String;
      onProgress?.call(0.3);

      // 3. Drain the SSE result stream for that event.
      final res = await _dio.get<dynamic>(
        '$_baseUrl/gradio_api/call/transcribe/$eventId',
        options: Options(responseType: ResponseType.plain),
        cancelToken: _cancelToken,
      );
      onProgress?.call(0.85);

      final payload = _parseGradioSse(res.data as String);
      // Same Annex III 1(c) strip as the REST path — two routes into this
      // engine, one filter, applied on both.
      final text = EmotionInference.strip(
              payload.isNotEmpty ? (payload[0]?.toString() ?? '') : '')
          .text;
      Map<String, dynamic> raw = const {};
      if (payload.length > 1 && payload[1] is String) {
        try {
          final decoded = jsonDecode(payload[1] as String);
          if (decoded is Map<String, dynamic>) raw = decoded;
        } catch (e) {
          Log.instance.w('hfspace', 'failed to parse verbose_json from Gradio response',
              fields: {'err': e.toString()});
        }
      }

      final segments = <TranscriptionSegment>[];
      for (final s in (raw['segments'] as List<dynamic>? ?? const [])) {
        if (s is! Map<String, dynamic>) continue;
        final seg = TranscriptionSegment.fromModelText(
          rawText: (s['text'] as String?) ?? '',
          startTime: (s['start'] as num?)?.toDouble() ?? 0.0,
          endTime: (s['end'] as num?)?.toDouble() ?? 0.0,
          confidence: (s['avg_logprob'] as num?)?.toDouble() ?? 1.0,
          speaker: s['speaker'] as String?,
          metadata: {
            'engine': engineId,
          },
        );
        segments.add(seg);
        onSegment?.call(seg);
      }

      sw.stop();
      onProgress?.call(1.0);
      return TranscriptionResult(
        fullText: text,
        segments: segments,
        processingTime: sw.elapsed,
        detectedLanguage: raw['language'] as String?,
        metadata: {'engine': engineId, 'baseUrl': _baseUrl, 'api': 'gradio'},
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw TranscriptionException('Cancelled', engineId);
      }
      throw TranscriptionException('Gradio call failed: ${e.message}', engineId, e);
    } finally {
      _processing = false;
      _cancelToken = null;
    }
  }

  /// Extract the `data` array from a Gradio SSE response. Gradio streams:
  ///   event: complete
  ///   data: ["transcript", "{...verbose_json...}"]
  /// We keep the last well-formed `data:` JSON array (the completion).
  List<dynamic> _parseGradioSse(String body) {
    List<dynamic>? last;
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (!t.startsWith('data:')) continue;
      final jsonStr = t.substring(5).trim();
      if (jsonStr.isEmpty || jsonStr == 'null') continue;
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) last = decoded;
      } catch (e) {
        Log.instance.d('hfspace', 'SSE line parse failed',
            fields: {'err': e.toString()});
      }
    }
    return last ?? const [];
  }

  // -- Streaming (not supported) ------------------------------------------

  @override
  Stream<TranscriptionSegment>? transcribeStream(
    Stream<Float32List> audioStream, {
    String? language,
    bool enableWordTimestamps = false,
    bool liveDecode = true,
  }) =>
      null;

  // -- Cancel -------------------------------------------------------------

  @override
  Future<void> cancel() async {
    _cancelToken?.cancel('user cancelled');
  }

  // -- Config -------------------------------------------------------------

  @override
  Future<void> updateConfig(Map<String, dynamic> config) async {
    if (config['baseUrl'] is String) setBaseUrl(config['baseUrl'] as String);
  }

  @override
  Map<String, dynamic> get currentConfig => {'baseUrl': _baseUrl};

  // -- Text language detection (via Gradio API) ---------------------------

  /// Detect the language of [text] using the HF Space's `crispasr-lid` binary.
  /// Returns a list of `{language, confidence}` maps, or empty on failure.
  Future<List<Map<String, dynamic>>> detectTextLanguage(String text,
      {int topK = 3}) async {
    try {
      // Use the Gradio call API: POST /gradio_api/call/detect_text_language
      final r = await _dio.post<dynamic>(
        '$_baseUrl/gradio_api/call/detect_text_language',
        data: {'data': [text, 'CLD3 — 109 ISO-639-1 (default)', topK]},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final eventId = (r.data as Map<String, dynamic>?)?['event_id'];
      if (eventId == null) return [];

      // SSE result endpoint
      final sse = await _dio.get<String>(
        '$_baseUrl/gradio_api/call/detect_text_language/$eventId',
        options: Options(responseType: ResponseType.plain),
      );
      // Parse SSE: lines starting with "data: " contain the JSON result
      final lines = (sse.data ?? '').split('\n');
      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final json = line.substring(6);
        try {
          final parsed = _parseJson(json);
          if (parsed is List && parsed.isNotEmpty) {
            // First element is the table data [[lang, confidence], ...]
            final table = parsed[0];
            if (table is List) {
              return table
                  .whereType<List<dynamic>>()
                  .map((row) => {
                        'language': row[0]?.toString() ?? '',
                        'confidence': (row[1] is num)
                            ? (row[1] as num).toDouble()
                            : double.tryParse(row[1]?.toString() ?? '') ?? 0.0,
                      })
                  .toList();
            }
          }
        } catch (e) {
          Log.instance.d('hfspace', 'detectTextLanguage SSE line parse failed',
              fields: {'err': e.toString()});
          continue;
        }
      }
      return [];
    } catch (e) {
      Log.instance.w('hfspace', 'detectTextLanguage failed: $e');
      return [];
    }
  }

  static dynamic _parseJson(String s) {
    try {
      return Uri.decodeFull(s); // fallthrough
    } catch (_) {} // URI decode probe — silent
    // Simple JSON parse — use dart:convert
    return null;
  }

  // -- Helpers ------------------------------------------------------------

  /// Encode 16 kHz mono Float32 PCM as a minimal WAV (16-bit).
  static Uint8List _encodeWav(Float32List pcm, int sampleRate) {
    final numSamples = pcm.length;
    final dataSize = numSamples * 2;
    final fileSize = 44 + dataSize;
    final buf = ByteData(fileSize);

    // RIFF header
    buf.setUint8(0, 0x52); // R
    buf.setUint8(1, 0x49); // I
    buf.setUint8(2, 0x46); // F
    buf.setUint8(3, 0x46); // F
    buf.setUint32(4, fileSize - 8, Endian.little);
    buf.setUint8(8, 0x57); // W
    buf.setUint8(9, 0x41); // A
    buf.setUint8(10, 0x56); // V
    buf.setUint8(11, 0x45); // E

    // fmt chunk
    buf.setUint8(12, 0x66); // f
    buf.setUint8(13, 0x6D); // m
    buf.setUint8(14, 0x74); // t
    buf.setUint8(15, 0x20); // (space)
    buf.setUint32(16, 16, Endian.little); // chunk size
    buf.setUint16(20, 1, Endian.little); // PCM format
    buf.setUint16(22, 1, Endian.little); // mono
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buf.setUint16(32, 2, Endian.little); // block align
    buf.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk
    buf.setUint8(36, 0x64); // d
    buf.setUint8(37, 0x61); // a
    buf.setUint8(38, 0x74); // t
    buf.setUint8(39, 0x61); // a
    buf.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < numSamples; i++) {
      final clamped = pcm[i].clamp(-1.0, 1.0);
      final sample = (clamped * 32767).round().clamp(-32768, 32767);
      buf.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buf.buffer.asUint8List();
  }
}
