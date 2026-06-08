// lib/engines/transcription_engine.dart
import 'dart:typed_data';

import '../services/model_service.dart';
import '../services/transcription_service.dart' show AdvancedTranscribeOptions;

/// Abstract interface for all transcription engines
abstract class TranscriptionEngine {
  /// Engine identification
  String get engineId;
  String get engineName;
  String get version;

  /// Engine capabilities
  bool get supportsStreaming;
  bool get supportsLanguageDetection;
  bool get supportsWordTimestamps;
  bool get supportsSpeakerDiarization;
  List<String> get supportedLanguages;

  /// Engine status
  bool get isInitialized;
  bool get isProcessing;

  /// Lifecycle methods
  Future<bool> initialize(
      {ModelService? modelService, Map<String, dynamic>? config});
  Future<void> dispose();

  /// Model management
  Future<List<EngineModel>> getAvailableModels();
  Future<bool> loadModel(String modelId,
      {void Function(double progress)? onProgress});
  Future<void> unloadModel();
  String? get currentModelId;

  /// Transcription methods
  Future<TranscriptionResult> transcribe(
    Float32List audioData, {
    String? language,
    bool enableWordTimestamps = false,
    bool enableSpeakerDiarization = false,
    // "Advanced decoding" knobs — engines that don't support them
    // silently ignore.
    bool translate = false,
    bool beamSearch = false,
    String? initialPrompt,
    bool vad = false,
    String? vadModelPath,
    /// Target language for true speech-translation backends (canary,
    /// voxtral, voxtral4b, qwen3, cohere). When non-null and ≠ source,
    /// the backend translates instead of transcribing verbatim. Whisper
    /// uses the legacy [translate] boolean which always targets English.
    /// Engines that don't translate ignore this field.
    String? targetLanguage,
    /// Free-form Q&A prompt for instruct-tuned audio-LLM backends
    /// (voxtral, voxtral4b, qwen3-asr). When non-null + non-empty, the
    /// backend ANSWERS the prompt instead of producing a verbatim
    /// transcript. Other backends ignore.
    String? askPrompt,
    /// Decoder temperature for sampling backends (canary, cohere,
    /// parakeet, moonshine). 0.0 = greedy (default). > 0.0 = stochastic
    /// sampling. Backends without runtime temperature support silently
    /// no-op.
    double temperature = 0.0,
    /// Best-of-N decoding. 1 = single decode (default). >1 runs N
    /// independent decodes and picks the highest-scoring result.
    /// For Whisper this maps to `wparams.greedy.best_of`; for other
    /// backends CrispASR runs N transcribes externally and picks
    /// the highest-mean-confidence result.
    int bestOf = 1,
    /// CrispASR 0.6 parity knobs (VAD tuning, LID method, tdrz,
    /// token timestamps). Defaults mirror historical behaviour so
    /// existing call sites don't change.
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
    /// Resume offset for crash-recovery (§5.23 Q3). When > 0 the
    /// engine skips audio before this second mark and emits segments
    /// whose timestamps are absolute (i.e. start at the offset, not
    /// at 0). For whisper backends this is implemented by starting the
    /// chunked-whisper loop at the chunk containing the offset; for
    /// session backends by trimming leading PCM samples + shifting
    /// emitted timestamps. Defaults to 0.0 — single-file and fresh
    /// batch runs keep their existing behaviour.
    double startOffsetSec = 0.0,
    void Function(TranscriptionSegment segment)? onSegment,
    void Function(double progress)? onProgress,
  });

  /// Streaming transcription (if supported)
  Stream<TranscriptionSegment>? transcribeStream(
    Stream<Float32List> audioStream, {
    String? language,
    bool enableWordTimestamps = false,
    bool liveDecode = true,
  });

  /// Cancel ongoing operations
  Future<void> cancel();

  /// Engine-specific configuration
  Future<void> updateConfig(Map<String, dynamic> config);
  Map<String, dynamic> get currentConfig;
}

/// Engine model information
class EngineModel {
  final String id;
  final String name;
  final String description;
  final int sizeBytes;
  final List<String> supportedLanguages;
  final bool isDownloaded;
  final String? localPath;
  final Map<String, dynamic> metadata;

  const EngineModel({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeBytes,
    required this.supportedLanguages,
    this.isDownloaded = false,
    this.localPath,
    this.metadata = const {},
  });
}

/// Transcription result
class TranscriptionResult {
  final String fullText;
  final List<TranscriptionSegment> segments;
  final Duration processingTime;
  final String? detectedLanguage;
  final double? confidence;
  final Map<String, dynamic> metadata;

  const TranscriptionResult({
    required this.fullText,
    required this.segments,
    required this.processingTime,
    this.detectedLanguage,
    this.confidence,
    this.metadata = const {},
  });
}

/// Individual transcription segment
class TranscriptionSegment {
  final String text;
  final double startTime;
  final double endTime;
  final String? speaker;
  final double confidence;
  final List<TranscriptionWord>? words;
  final Map<String, dynamic> metadata;

  /// §5.25.10 — user-applied annotation tags (bookmark, action-item, …).
  /// Persisted in history JSON; empty by default.
  final List<String> tags;

  const TranscriptionSegment({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.speaker,
    this.confidence = 1.0,
    this.words,
    this.metadata = const {},
    this.tags = const [],
  });

  String get formattedTime {
    final start = _formatTime(startTime);
    final end = _formatTime(endTime);
    return '[$start -> $end]';
  }

  String _formatTime(double seconds) {
    final minutes = (seconds / 60).floor();
    final secs = (seconds % 60);
    return '${minutes.toString().padLeft(2, '0')}:${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }
}

/// One alternative-candidate suggestion for an ambiguous word. Surfaced
/// for Whisper greedy decode when the user enabled `altN` > 0 in
/// AdvancedOptions; the transcript editor reads this list to populate
/// a tap-to-pick popover so users can override an obvious mishear
/// (kubectl → cubicle) without retyping.
class TranscriptionWordAlt {
  /// Display text of the candidate. For Whisper sub-word BPE this may
  /// include a leading-space marker that the UI strips on render.
  final String text;

  /// Softmax probability at the same decode step in `[0, 1]`.
  final double p;

  const TranscriptionWordAlt({required this.text, required this.p});
}

/// Word-level transcription information
class TranscriptionWord {
  final String word;
  final double startTime;
  final double endTime;
  final double confidence;

  /// Optional top-N alternative candidates for this word's first
  /// content-bearing token (Whisper greedy decode only, when altN > 0
  /// AND the loaded libcrispasr is ≥ 0.5.13). Empty in the common
  /// off-by-default case. Ordered descending by probability.
  final List<TranscriptionWordAlt> alts;

  const TranscriptionWord({
    required this.word,
    required this.startTime,
    required this.endTime,
    required this.confidence,
    this.alts = const [],
  });
}

/// Engine-specific exceptions
abstract class EngineException implements Exception {
  final String message;
  final String engineId;
  final dynamic originalError;

  const EngineException(this.message, this.engineId, [this.originalError]);

  @override
  String toString() => 'EngineException($engineId): $message';
}

class EngineInitializationException extends EngineException {
  const EngineInitializationException(super.message, super.engineId,
      [super.originalError]);
}

class ModelLoadException extends EngineException {
  final String modelId;

  const ModelLoadException(String message, String engineId, this.modelId,
      [dynamic originalError])
      : super(message, engineId, originalError);
}

class TranscriptionException extends EngineException {
  const TranscriptionException(super.message, super.engineId,
      [super.originalError]);
}

/// A concrete fallback for engine errors that don't fit a more specific type.
class GenericEngineException extends EngineException {
  const GenericEngineException(super.message, super.engineId,
      [super.originalError]);
}
