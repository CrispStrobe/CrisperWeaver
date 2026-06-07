import 'dart:math';
import 'dart:typed_data';
import 'dart:async';

import '../services/model_service.dart';
import '../services/transcription_service.dart' show AdvancedTranscribeOptions;
import 'transcription_engine.dart';

/// Mock transcription engine for testing and development
class MockEngine implements TranscriptionEngine {
  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _currentModelId;
  Map<String, dynamic> _config = {};

  static const List<String> _mockResponses = [
    "This is a mock transcription result. The audio quality appears to be good and the speech is clear.",
    "Welcome to the mock transcription engine. This demonstrates the interface without requiring actual models.",
    "The mock engine simulates realistic transcription behavior including processing delays and segment boundaries.",
    "For testing purposes, this engine generates predictable responses with timing information.",
    "Production engines will replace this mock with actual speech recognition capabilities.",
  ];

  static const List<String> _mockSpeakers = [
    "Speaker 1",
    "Speaker 2",
    "Speaker 3",
  ];

  @override
  String get engineId => 'mock';

  @override
  String get engineName => 'Mock Engine';

  @override
  String get version => '1.0.0-dev';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsLanguageDetection => true;

  @override
  bool get supportsWordTimestamps => true;

  @override
  bool get supportsSpeakerDiarization => true;

  @override
  List<String> get supportedLanguages =>
      ['en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'zh', 'ja', 'ko', 'ar'];

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isProcessing => _isProcessing;

  @override
  String? get currentModelId => _currentModelId;

  @override
  Map<String, dynamic> get currentConfig => Map.from(_config);

  @override
  Future<bool> initialize(
      {ModelService? modelService, Map<String, dynamic>? config}) async {
    await Future<void>.delayed(
        const Duration(milliseconds: 500)); // Simulate init time

    _config = config ?? {};
    _isInitialized = true;
    return true;
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    _isProcessing = false;
    _currentModelId = null;
    _config.clear();
  }

  @override
  Future<List<EngineModel>> getAvailableModels() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));

    return [
      const EngineModel(
        id: 'mock-tiny',
        name: 'Mock Tiny',
        description: 'Smallest mock model for testing',
        sizeBytes: 39 * 1024 * 1024,
        supportedLanguages: ['en', 'es', 'fr'],
        isDownloaded: true,
        localPath: '/mock/path/tiny.bin',
      ),
      const EngineModel(
        id: 'mock-base',
        name: 'Mock Base',
        description: 'Balanced mock model',
        sizeBytes: 74 * 1024 * 1024,
        supportedLanguages: ['en', 'es', 'fr', 'de', 'it'],
        isDownloaded: true,
        localPath: '/mock/path/base.bin',
      ),
      const EngineModel(
        id: 'mock-large',
        name: 'Mock Large',
        description: 'High-quality mock model',
        sizeBytes: 1550 * 1024 * 1024,
        supportedLanguages: [
          'en',
          'es',
          'fr',
          'de',
          'it',
          'pt',
          'ru',
          'zh',
          'ja',
          'ko'
        ],
        isDownloaded: false,
      ),
    ];
  }

  @override
  Future<bool> loadModel(String modelId,
      {void Function(double progress)? onProgress}) async {
    if (!_isInitialized) {
      throw EngineInitializationException(
        'Engine not initialized',
        engineId,
      );
    }

    // Simulate model loading with progress
    onProgress?.call(0.0);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    onProgress?.call(0.3);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    onProgress?.call(0.7);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    onProgress?.call(1.0);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    _currentModelId = modelId;
    return true;
  }

  @override
  Future<void> unloadModel() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _currentModelId = null;
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
    double temperature = 0.0,
    int bestOf = 1,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
    double startOffsetSec = 0.0,
    void Function(TranscriptionSegment segment)? onSegment,
    void Function(double progress)? onProgress,
  }) async {
    if (!_isInitialized) {
      throw EngineInitializationException(
        'Engine not initialized',
        engineId,
      );
    }

    if (_currentModelId == null) {
      throw ModelLoadException(
        'No model loaded',
        engineId,
        'none',
      );
    }

    _isProcessing = true;
    final startTime = DateTime.now();

    try {
      // Simulate processing time based on audio length
      final audioDurationMs = (audioData.length / 16.0); // Assume 16kHz
      final processingTimeMs =
          (audioDurationMs * 0.1).clamp(500, 5000); // 10% of audio duration

      final segments = <TranscriptionSegment>[];
      final numSegments = _calculateSegmentCount(audioData.length);

      for (int i = 0; i < numSegments; i++) {
        // Report progress
        onProgress?.call(i / numSegments);

        // Simulate processing delay
        await Future<void>.delayed(
            Duration(milliseconds: (processingTimeMs / numSegments).round()));

        final segment = _generateMockSegment(
          i,
          numSegments,
          enableSpeakerDiarization,
          enableWordTimestamps,
        );

        segments.add(segment);
        onSegment?.call(segment);
      }

      onProgress?.call(1.0);

      final endTime = DateTime.now();
      final processingTime = endTime.difference(startTime);

      final fullText = segments.map((s) => s.text).join(' ');

      return TranscriptionResult(
        fullText: fullText,
        segments: segments,
        processingTime: processingTime,
        detectedLanguage: language ?? 'en',
        confidence: 0.85 + (Random().nextDouble() * 0.1), // 0.85-0.95
        metadata: {
          'engine': engineId,
          'model': _currentModelId,
          'audioLength': audioData.length,
          'sampleRate': 16000,
        },
      );
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Stream<TranscriptionSegment>? transcribeStream(
    Stream<Float32List> audioStream, {
    String? language,
    bool enableWordTimestamps = false,
    bool liveDecode = true,
  }) {
    if (!supportsStreaming) return null;

    return audioStream.asyncMap((audioChunk) async {
      // Simulate streaming processing delay
      await Future<void>.delayed(Duration(milliseconds: 100 + Random().nextInt(200)));

      return _generateMockSegment(
        Random().nextInt(100),
        100,
        false, // Streaming typically doesn't do diarization
        enableWordTimestamps,
      );
    });
  }

  @override
  Future<void> cancel() async {
    _isProcessing = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> updateConfig(Map<String, dynamic> config) async {
    _config.addAll(config);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  // Helper methods for generating realistic mock data

  int _calculateSegmentCount(int audioLength) {
    // Assume segments of ~5 seconds at 16kHz
    const samplesPerSecond = 16000;
    const secondsPerSegment = 5;
    const samplesPerSegment = samplesPerSecond * secondsPerSegment;

    return (audioLength / samplesPerSegment).ceil().clamp(1, 20);
  }

  TranscriptionSegment _generateMockSegment(
    int index,
    int totalSegments,
    bool enableSpeakerDiarization,
    bool enableWordTimestamps,
  ) {
    const segmentDuration = 5.0; // 5 seconds per segment
    final startTime = index * segmentDuration;
    final endTime = startTime + segmentDuration;

    final responseIndex = index % _mockResponses.length;
    final text = _mockResponses[responseIndex];

    String? speaker;
    if (enableSpeakerDiarization) {
      final speakerIndex = index % _mockSpeakers.length;
      speaker = _mockSpeakers[speakerIndex];
    }

    List<TranscriptionWord>? words;
    if (enableWordTimestamps) {
      words = _generateMockWords(text, startTime, endTime);
    }

    return TranscriptionSegment(
      text: text,
      startTime: startTime,
      endTime: endTime,
      speaker: speaker,
      confidence: 0.8 + (Random().nextDouble() * 0.15), // 0.8-0.95
      words: words,
      metadata: {
        'segmentIndex': index,
        'totalSegments': totalSegments,
      },
    );
  }

  List<TranscriptionWord> _generateMockWords(
      String text, double startTime, double endTime) {
    final words = text.split(' ');
    final duration = endTime - startTime;
    final timePerWord = duration / words.length;

    return words.asMap().entries.map((entry) {
      final index = entry.key;
      final word = entry.value;

      final wordStart = startTime + (index * timePerWord);
      final wordEnd = wordStart + timePerWord;

      return TranscriptionWord(
        word: word,
        startTime: wordStart,
        endTime: wordEnd,
        confidence: 0.75 + (Random().nextDouble() * 0.2), // 0.75-0.95
      );
    }).toList();
  }
}
