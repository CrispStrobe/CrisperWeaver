import 'dart:typed_data';

import '../constants/build_flavor.dart';
import '../services/browser_speech_client.dart';
import '../services/model_service.dart';
import '../services/transcription_service.dart' show AdvancedTranscribeOptions;
import 'transcription_engine.dart';

/// Local speech inference in a dedicated browser worker. Native builds retain
/// their existing FFI engine; no remote processing fallback is used here.
class BrowserSpeechEngine implements TranscriptionEngine {
  BrowserSpeechEngine(this.backend, {BrowserSpeechClient? client})
      : _client = client ??
            BrowserSpeechClient(backend,
                allowDownloads: BuildFlavor.allowModelDownloads);
  final String backend;
  final BrowserSpeechClient _client;
  bool _initialized = false, _processing = false;
  String? _model;
  Map<String, dynamic> _config = {};
  @override
  String get engineId => backend == 'onnx' ? 'onnxweb' : 'crispasr';
  @override
  String get engineName =>
      backend == 'onnx' ? 'ONNX Runtime Web (local)' : 'CrispASR WASM (local)';
  @override
  String get version =>
      backend == 'onnx' ? 'Transformers.js 3.8.1' : 'CrispASR WASM b33138b';
  @override
  bool get supportsStreaming => false;
  @override
  bool get supportsLanguageDetection => true;
  @override
  bool get supportsWordTimestamps => false;
  @override
  bool get supportsSpeakerDiarization => false;
  @override
  List<String> get supportedLanguages => ['en', 'de', 'zh', 'es', 'fr', 'ja'];
  @override
  bool get isInitialized => _initialized;
  @override
  bool get isProcessing => _processing;
  @override
  String? get currentModelId => _model;
  @override
  Map<String, dynamic> get currentConfig => Map.unmodifiable(_config);
  @override
  Future<bool> initialize(
      {ModelService? modelService, Map<String, dynamic>? config}) async {
    _config = config ?? {};
    _initialized = true;
    return true;
  }

  @override
  Future<List<EngineModel>> getAvailableModels() async {
    final models = await _client.request('models', {}) as List;
    return models.map((dynamic value) {
      final m = value as Map;
      return EngineModel(
          id: m['id'] as String,
          name: m['name'] as String,
          description:
              m['browserReason'] as String? ?? 'Runs locally in this browser.',
          sizeBytes: m['sizeBytes'] as int,
          supportedLanguages: List<String>.from(m['languages'] as List),
          isDownloaded: m['cached'] == true,
          metadata: {
            'backend': m['backend'] ?? 'whisper',
            'local': true,
            'experimental': m['experimental'] == true,
            'observedWasmBytes': m['observedWasmBytes'],
            'resumeBytes': m['resumeBytes'],
          });
    }).toList();
  }

  @override
  Future<bool> loadModel(String modelId,
      {void Function(double)? onProgress}) async {
    if (!_initialized) {
      throw StateError('Browser engine is not initialized');
    }
    if (_processing) {
      throw StateError('Stop transcription before switching models');
    }
    _model = null;
    await _client.request('load', {'model': modelId}, onProgress: onProgress);
    _model = modelId;
    return true;
  }

  Future<bool> importModel(String modelId, Uint8List bytes) async {
    await _client.request('import', {'model': modelId, 'bytes': bytes});
    _model = modelId;
    return true;
  }

  Future<TranscriptionResult> transcribeBytes(
    Uint8List bytes, {
    String? language,
    bool translate = false,
    bool diarize = false,
    void Function(TranscriptionSegment)? onSegment,
    void Function(double)? onProgress,
  }) async {
    final audio = await BrowserSpeechClient.decode(bytes);
    return transcribe(audio,
        language: language,
        translate: translate,
        enableSpeakerDiarization: diarize,
        onSegment: onSegment,
        onProgress: onProgress);
  }

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
    double temperature = 0,
    int bestOf = 1,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
    double startOffsetSec = 0,
    void Function(TranscriptionSegment)? onSegment,
    void Function(double)? onProgress,
  }) async {
    if (_processing) throw StateError('Browser engine is already transcribing');
    if (_model == null) throw StateError('Load a browser model first');
    if (enableSpeakerDiarization ||
        enableWordTimestamps ||
        askPrompt?.isNotEmpty == true) {
      throw UnsupportedError(
          'Browser speech supports segment timestamps; diarization, word timestamps and audio Q&A are unavailable.');
    }
    final started = DateTime.now();
    _processing = true;
    try {
      final offset =
          (startOffsetSec * 16000).round().clamp(0, audioData.length);
      final result = await _client.request(
          'transcribe',
          {
            'audio': Float32List.fromList(
                Float32List.sublistView(audioData, offset)),
            'transferAudio': true,
            'language': language,
            'translate': translate,
            'diarize': enableSpeakerDiarization,
          },
          onProgress: onProgress) as Map;
      var segments = (result['segments'] as List).map((dynamic item) {
        final m = item as Map;
        return TranscriptionSegment.fromModelText(
            rawText: m['text'] as String,
            startTime: (m['start'] as num).toDouble() + startOffsetSec,
            endTime: (m['end'] as num).toDouble() + startOffsetSec,
            metadata: {'local': true, 'engine': engineId});
      }).toList();
      segments = GeneratedKind.stamp(
          segments, GeneratedKind.forRequest(translate: translate));
      for (final segment in segments) {
        onSegment?.call(segment);
      }
      return TranscriptionResult(
          fullText: segments.map((s) => s.text).join(' ').trim(),
          segments: segments,
          processingTime: DateTime.now().difference(started),
          metadata: {
            'local': true,
            'engine': engineId,
            'model': _model,
            if (result['diagnostics'] != null)
              'diagnostics': result['diagnostics']
          });
    } finally {
      _processing = false;
    }
  }

  @override
  Stream<TranscriptionSegment>? transcribeStream(
    Stream<Float32List> audioStream, {
    String? language,
    bool enableWordTimestamps = false,
    bool liveDecode = true,
  }) =>
      null;
  @override
  Future<void> cancel() async {
    _client.cancel();
    _model = null;
    _processing = false;
  }

  @override
  Future<void> unloadModel() async {
    await _client.request('unload', {});
    _model = null;
  }

  Future<Map<String, dynamic>> browserStorage() async =>
      Map<String, dynamic>.from(await _client.request('storage', {}) as Map);

  Future<void> deleteCachedModel(String model) async {
    await unloadModel();
    await _client.request('delete', {'model': model});
  }

  Future<void> clearBrowserCache({bool incompleteOnly = false}) async {
    await unloadModel();
    await _client
        .request(incompleteOnly ? 'clearIncomplete' : 'clearCache', {});
  }

  @override
  Future<void> dispose() async {
    _client.dispose();
    _initialized = false;
    _model = null;
  }

  @override
  Future<void> updateConfig(Map<String, dynamic> config) async {
    _config = Map.from(config);
  }
}
