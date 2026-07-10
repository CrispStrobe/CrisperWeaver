// Web stub for package:crispasr — provides the same public type surface
// but every FFI-backed operation throws UnsupportedError. Data-only classes
// (Segment, Word, etc.) are fully functional since they're used as containers.

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Data classes (fully functional — used as containers across the app)
// ---------------------------------------------------------------------------

class Segment {
  final String text;
  final double start;
  final double end;
  final double noSpeechProb;
  final List<Word> words;

  Segment({
    required this.text,
    required this.start,
    required this.end,
    this.noSpeechProb = 0.0,
    this.words = const [],
  });

  @override
  String toString() =>
      '[${start.toStringAsFixed(1)}s - ${end.toStringAsFixed(1)}s] $text';
}

class Word {
  final String text;
  final double start;
  final double end;
  final double p;
  final List<AltToken> alts;

  const Word({
    required this.text,
    required this.start,
    required this.end,
    required this.p,
    this.alts = const [],
  });

  @override
  String toString() =>
      '${start.toStringAsFixed(2)}-${end.toStringAsFixed(2)} $text';
}

class AltToken {
  final String text;
  final double p;

  const AltToken({required this.text, required this.p});

  @override
  String toString() => '$text(${(p * 100).toStringAsFixed(1)}%)';
}

class LanguageDetection {
  final String code;
  final double probability;

  const LanguageDetection({required this.code, required this.probability});

  bool get ok => code.isNotEmpty && probability >= 0.0;
  @override
  String toString() =>
      'LanguageDetection($code, ${(probability * 100).toStringAsFixed(1)}%)';
}

class DecodedAudio {
  final Float32List samples;
  final int sampleRate;
  const DecodedAudio({required this.samples, required this.sampleRate});

  double get durationSeconds => samples.length / sampleRate;
}

class DecodedAudioStereo {
  final Float32List left;
  final Float32List right;
  final int sampleRate;
  final int sourceChannels;

  const DecodedAudioStereo({
    required this.left,
    required this.right,
    required this.sampleRate,
    required this.sourceChannels,
  });

  bool get isStereo => sourceChannels >= 2;
}

class TextLanguage {
  final String code;
  final double confidence;
  const TextLanguage(this.code, this.confidence);
  @override
  String toString() => 'TextLanguage($code, ${confidence.toStringAsFixed(3)})';
}

class DiarizeSegment {
  final double t0;
  final double t1;
  int speaker;
  DiarizeSegment({required this.t0, required this.t1, this.speaker = -1});
}

enum DiarizeMethod {
  energy,
  xcorr,
  vadTurns,
  pyannote,
}

class RegistryEntry {
  final String filename;
  final String url;
  final String approxSize;
  const RegistryEntry({
    required this.filename,
    required this.url,
    required this.approxSize,
  });
}

class AlignedWord {
  final String text;
  final double start;
  final double end;
  const AlignedWord({required this.text, required this.start, required this.end});
}

class LidResult {
  final String langCode;
  final double confidence;
  const LidResult({required this.langCode, required this.confidence});
  bool get isEmpty => langCode.isEmpty;
}

enum LidMethod {
  whisper,
  silero,
  firered,
  ecapa,
}

class SessionVadOptions {
  final double threshold;
  final int minSpeechDurationMs;
  final int minSilenceDurationMs;
  final int speechPadMs;
  final int chunkSeconds;
  final int nThreads;

  const SessionVadOptions({
    this.threshold = 0.5,
    this.minSpeechDurationMs = 250,
    this.minSilenceDurationMs = 100,
    this.speechPadMs = 30,
    this.chunkSeconds = 30,
    this.nThreads = 4,
  });
}

class SessionSegment {
  final String text;
  final double start;
  final double end;
  final List<Word> words;
  const SessionSegment({
    required this.text,
    required this.start,
    required this.end,
    this.words = const [],
  });
  @override
  String toString() =>
      '[${start.toStringAsFixed(1)}-${end.toStringAsFixed(1)}s] $text';
}

class StreamingUpdate {
  final String text;
  final double start;
  final double end;
  final int counter;

  const StreamingUpdate({
    required this.text,
    required this.start,
    required this.end,
    required this.counter,
  });

  @override
  String toString() =>
      '[${start.toStringAsFixed(1)}-${end.toStringAsFixed(1)}s] $text';
}

class VadSpan {
  final double start;
  final double end;

  const VadSpan({required this.start, required this.end});

  double get duration => end - start;

  @override
  String toString() =>
      'VadSpan(${start.toStringAsFixed(2)}s -> ${end.toStringAsFixed(2)}s)';
}

class TranscribeOptions {
  final int strategy;
  final String? language;
  final bool translate;
  final bool detectLanguage;
  final bool wordTimestamps;
  final int maxLen;
  final bool splitOnWord;
  final int bestOf;
  final int nThreads;
  final String? initialPrompt;
  final bool silent;
  final bool vad;
  final String? vadModelPath;
  final double vadThreshold;
  final int vadMinSpeechMs;
  final int vadMinSilenceMs;
  final bool tdrz;
  final int altN;
  final int maxTokens;
  final bool noContext;
  final bool singleSegment;
  final bool suppressBlank;
  final double temperature;

  const TranscribeOptions({
    this.strategy = 0,
    this.language,
    this.translate = false,
    this.detectLanguage = false,
    this.wordTimestamps = false,
    this.maxLen = 0,
    this.splitOnWord = false,
    this.bestOf = 0,
    this.nThreads = 0,
    this.initialPrompt,
    this.silent = true,
    this.vad = false,
    this.vadModelPath,
    this.vadThreshold = 0.5,
    this.vadMinSpeechMs = 250,
    this.vadMinSilenceMs = 100,
    this.tdrz = false,
    this.altN = 0,
    this.maxTokens = 0,
    this.noContext = false,
    this.singleSegment = false,
    this.suppressBlank = true,
    this.temperature = 0.0,
  });
}

// ---------------------------------------------------------------------------
// Chat classes
// ---------------------------------------------------------------------------

class ChatOpenParams {
  final int? nThreads;
  final int? nThreadsBatch;
  final int? nCtx;
  final int? nBatch;
  final int? nUbatch;
  final int? nGpuLayers;
  final bool useMmap;
  final bool useMlock;
  final String? chatTemplate;

  const ChatOpenParams({
    this.nThreads,
    this.nThreadsBatch,
    this.nCtx,
    this.nBatch,
    this.nUbatch,
    this.nGpuLayers,
    this.useMmap = true,
    this.useMlock = false,
    this.chatTemplate,
  });
}

class ChatGenerateParams {
  final int maxTokens;
  final double temperature;
  final int topK;
  final double topP;
  final double minP;
  final double repeatPenalty;
  final int repeatLastN;
  final int seed;
  final List<String> stop;

  const ChatGenerateParams({
    this.maxTokens = 256,
    this.temperature = 0.8,
    this.topK = 40,
    this.topP = 0.95,
    this.minP = 0.05,
    this.repeatPenalty = 1.1,
    this.repeatLastN = 64,
    this.seed = 0,
    this.stop = const [],
  });
}

class ChatMessage {
  final String role;
  final String content;
  const ChatMessage({required this.role, required this.content});

  factory ChatMessage.system(String content) =>
      ChatMessage(role: 'system', content: content);
  factory ChatMessage.user(String content) =>
      ChatMessage(role: 'user', content: content);
  factory ChatMessage.assistant(String c) =>
      ChatMessage(role: 'assistant', content: c);
}

class ChatException implements Exception {
  final int code;
  final String message;
  const ChatException(this.code, this.message);
  @override
  String toString() => 'ChatException($code: $message)';
}

// ---------------------------------------------------------------------------
// FFI-backed classes — constructors throw UnsupportedError on web
// ---------------------------------------------------------------------------

class CrispASR {
  bool get supportsExtended => false;
  bool get supportsStreaming => false;

  CrispASR(String modelPath, {String? libPath}) {
    throw UnsupportedError('CrispASR is not available on web');
  }

  List<Segment> transcribePcm(Float32List pcm,
      {int strategy = 0, TranscribeOptions? options}) {
    throw UnsupportedError('CrispASR is not available on web');
  }

  LanguageDetection detectLanguage(Float32List pcm, {int nThreads = 4}) {
    throw UnsupportedError('CrispASR is not available on web');
  }

  List<VadSpan> vad(Float32List pcm,
      {required String modelPath,
      int sampleRate = 16000,
      double threshold = 0.5,
      int minSpeechMs = 250,
      int minSilenceMs = 100,
      int nThreads = 4,
      bool useGpu = false}) {
    throw UnsupportedError('CrispASR is not available on web');
  }

  List<VadSpan> vadSlices(Float32List pcm,
      {required String modelPath,
      int sampleRate = 16000,
      double threshold = 0.0,
      int minSpeechMs = 250,
      int minSilenceMs = 100,
      int speechPadMs = 30,
      double maxChunkDurationS = 30.0,
      int nThreads = 4}) {
    throw UnsupportedError('CrispASR is not available on web');
  }

  List<String> supportedLanguageCodes() => const [];

  StreamingSession openStream({
    int stepMs = 3000,
    int lengthMs = 10000,
    int keepMs = 200,
    int nThreads = 4,
    String? language,
    bool translate = false,
  }) {
    throw UnsupportedError('CrispASR is not available on web');
  }

  void dispose() {}

  static String defaultLibName() => '';
}

class StreamingSession {
  bool get isClosed => true;

  StreamingUpdate? feed(Float32List pcm) {
    throw UnsupportedError('StreamingSession is not available on web');
  }

  StreamingUpdate? flush() {
    throw UnsupportedError('StreamingSession is not available on web');
  }

  void setLiveDecode(bool enabled) {
    throw UnsupportedError('StreamingSession is not available on web');
  }

  void close() {}
}

class CrispasrSession {
  String get backend => '';
  bool get isClosed => true;

  factory CrispasrSession.open(String modelPath,
      {int nThreads = 4, String? libPath, String? backend}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  factory CrispasrSession.openWithParams(String modelPath,
      {int nThreads = 4,
      bool useGpu = true,
      int verbosity = 0,
      bool flashAttn = true,
      int nGpuLayers = -1,
      String? backend,
      String? libPath}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  static List<String> availableBackends({String? libPath}) => const [];

  List<SessionSegment> transcribe(Float32List pcm, {String? language}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  List<SessionSegment> transcribeChunked(Float32List pcm,
      {int chunkSeconds = 0,
      int overlapSeconds = -1,
      String? language}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  List<SessionSegment> transcribeVad(Float32List pcm, String vadModelPath,
      {int sampleRate = 16000,
      SessionVadOptions options = const SessionVadOptions(),
      String? language}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setCodecPath(String path) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void clearPhonemeCache() {}

  void setSourceLanguage(String lang) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setTargetLanguage(String lang) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setPunctuation(bool enable) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setTranslate(bool enable) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setAsk(String prompt) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setBestOf(int n) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setBeamSize(int n) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setGrammar(String text,
      {String rootRule = 'root', double penalty = 100.0}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void clearGrammar() {}

  void setWhisperDecodeExtras({
    bool suppressNonSpeechTokens = false,
    String suppressRegex = '',
    bool carryInitialPrompt = false,
  }) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setFallbackThresholds({
    double entropyThold = 2.4,
    double logprobThold = -1.0,
    double noSpeechThold = 0.6,
    double temperatureInc = 0.2,
  }) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setAltN(int n) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setTemperature(double temperature, {int seed = 0}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setTtsSteps(int steps) {}
  void setTopP(double topP) {}
  void setMinP(double minP) {}
  void setRepetitionPenalty(double r) {}
  void setCfgWeight(double cfg) {}
  void setExaggeration(double exaggeration) {}
  void setMaxSpeechTokens(int n) {}
  void setLengthScale(double scale) {}
  void setTtsSeed(int seed) {}
  void setTopK(int topK) {}
  void setDoSample(bool enable) {}
  void setTtsNumCandidates(int n) {}
  void setSpeakerId(int id) {}
  void setG2pDict(String source) {}
  void setTtsNoiseTemp(double noiseTemp) {}
  void setMaxNewTokens(int n) {}
  void setFrequencyPenalty(double penalty) {}

  String? translateText(String text, String srcLang, String tgtLang,
      {int maxTokens = 0}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  ({String lang, double confidence}) detectLanguage(
      Float32List pcm, String lidModelPath,
      {int method = 1}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setVoice(String path, {String? refText}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setSpeakerName(String name) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  List<String> speakers() => const [];

  void setSpeakerID(int id) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  int get nSpeakers => 0;

  void setInstruct(String instruct) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  bool isCustomVoice() => false;
  bool isVoiceDesign() => false;

  Float32List synthesize(String text) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  ({Float32List pcm, String transcript}) speechToSpeech(Float32List inputPcm) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void setHotwords(String hotwords, {double boost = 1.5}) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  StreamingSession openStream({
    int stepMs = 3000,
    int lengthMs = 10000,
    int keepMs = 200,
    int nThreads = 4,
    String? language,
    bool translate = false,
  }) {
    throw UnsupportedError('CrispasrSession is not available on web');
  }

  void close() {}
}

class CrispasrChatSession {
  String get templateName => '';
  int get nCtx => 0;

  factory CrispasrChatSession.open(String modelPath,
      {ChatOpenParams params = const ChatOpenParams(), String? libPath}) {
    throw UnsupportedError('CrispasrChatSession is not available on web');
  }

  void reset() {
    throw UnsupportedError('CrispasrChatSession is not available on web');
  }

  Future<String> generate(List<ChatMessage> messages,
      {ChatGenerateParams params = const ChatGenerateParams()}) {
    throw UnsupportedError('CrispasrChatSession is not available on web');
  }

  void close() {}
}

class CrispasrSpeakerDB {
  CrispasrSpeakerDB(dynamic lib, String dirPath) {
    throw UnsupportedError('CrispasrSpeakerDB is not available on web');
  }

  final String dirPath = '';

  int get count => 0;

  (String?, double) match(Float32List embedding, {double threshold = 0.7}) {
    throw UnsupportedError('CrispasrSpeakerDB is not available on web');
  }

  bool enroll(String name, Float32List embedding) {
    throw UnsupportedError('CrispasrSpeakerDB is not available on web');
  }

  void close() {}
}

class CrispasrSpeakerEmbedder {
  CrispasrSpeakerEmbedder(dynamic lib, String modelSpec,
      {int nThreads = 4, String cacheDir = ''}) {
    throw UnsupportedError('CrispasrSpeakerEmbedder is not available on web');
  }

  int get dim => 0;
  String get name => '';

  Float32List? embed(Float32List pcm16k) {
    throw UnsupportedError('CrispasrSpeakerEmbedder is not available on web');
  }

  void close() {}
}

class CrispasrPyannoteCache {
  CrispasrPyannoteCache(dynamic lib, Float32List pcm16k, String modelPath,
      {int nThreads = 4}) {
    throw UnsupportedError('CrispasrPyannoteCache is not available on web');
  }

  void apply(List<DiarizeSegment> segs, {double sliceT0 = 0.0}) {
    throw UnsupportedError('CrispasrPyannoteCache is not available on web');
  }

  void close() {}
}

class CrispasrWatermark {
  CrispasrWatermark._();

  static bool isAvailable({dynamic lib}) => false;

  static bool loadModel(String ggufPath, {dynamic lib}) => false;

  static Float32List embed(Float32List pcm,
      {double alpha = 0.005, dynamic lib}) {
    throw UnsupportedError('CrispasrWatermark is not available on web');
  }

  static double detect(Float32List pcm, {dynamic lib}) {
    throw UnsupportedError('CrispasrWatermark is not available on web');
  }
}

class PuncModel {
  PuncModel._();

  static PuncModel open(String modelPath, {String? libPath}) {
    throw UnsupportedError('PuncModel is not available on web');
  }

  String process(String text) {
    throw UnsupportedError('PuncModel is not available on web');
  }

  void close() {}
}

class TruecaseModel {
  TruecaseModel._();

  static TruecaseModel open(String modelPath, {String? libPath}) {
    throw UnsupportedError('TruecaseModel is not available on web');
  }

  String process(String text) {
    throw UnsupportedError('TruecaseModel is not available on web');
  }

  void close() {}
}

class PcsModel {
  PcsModel._();

  static PcsModel open(String modelPath, {String? libPath}) {
    throw UnsupportedError('PcsModel is not available on web');
  }

  String process(String text) {
    throw UnsupportedError('PcsModel is not available on web');
  }

  void close() {}
}

// ---------------------------------------------------------------------------
// Top-level functions — all throw on web
// ---------------------------------------------------------------------------

DecodedAudio decodeAudioFile(String path, {String? libPath}) {
  throw UnsupportedError('decodeAudioFile is not available on web');
}

DecodedAudioStereo decodeAudioFileStereo(String path, {String? libPath}) {
  throw UnsupportedError('decodeAudioFileStereo is not available on web');
}

TextLanguage? detectTextLanguage(String text, String modelPath,
    {int nThreads = 1, String? libPath}) {
  throw UnsupportedError('detectTextLanguage is not available on web');
}

bool diarizeSegments({
  required List<DiarizeSegment> segs,
  required Float32List left,
  Float32List? right,
  bool isStereo = false,
  DiarizeMethod method = DiarizeMethod.vadTurns,
  String? pyannoteModelPath,
  int nThreads = 4,
  double sliceT0 = 0.0,
  dynamic lib,
}) {
  throw UnsupportedError('diarizeSegments is not available on web');
}

RegistryEntry? registryLookup(String backend, {dynamic lib}) {
  throw UnsupportedError('registryLookup is not available on web');
}

List<AlignedWord> alignWords({
  required String alignerModel,
  required String transcript,
  required Float32List pcm,
  double tOffset = 0.0,
  int nThreads = 4,
  dynamic lib,
}) {
  throw UnsupportedError('alignWords is not available on web');
}

LidResult detectLanguagePcm({
  required Float32List pcm,
  required LidMethod method,
  required String modelPath,
  int nThreads = 4,
  bool useGpu = false,
  int gpuDevice = 0,
  bool flashAttn = true,
  dynamic lib,
}) {
  throw UnsupportedError('detectLanguagePcm is not available on web');
}

Float32List enhanceAudioRnnoise(Float32List pcm, {dynamic lib}) {
  throw UnsupportedError('enhanceAudioRnnoise is not available on web');
}

String? cacheEnsureFile(String filename, String url,
    {bool quiet = false, String? cacheDirOverride, dynamic lib}) {
  throw UnsupportedError('cacheEnsureFile is not available on web');
}

String? detectBackendFromGguf(String path, {String? libPath}) {
  throw UnsupportedError('detectBackendFromGguf is not available on web');
}

int getTranscriptionProgress({String? libPath}) => -1;

void resetTranscriptionProgress({String? libPath}) {}

int getStreamedSegmentCount({String? libPath}) => 0;

List<SessionSegment> drainStreamedSegments({String? libPath}) => const [];

void resetStreamedSegments({String? libPath}) {}

int getStreamedTokenCount({String? libPath}) => 0;

List<String> drainStreamedTokens({String? libPath}) => const [];

void resetStreamedTokens({String? libPath}) {}

List<int> crispasrAgglomerativeCluster(dynamic lib, Float32List embeddings,
    {required int n,
    required int dim,
    double mergeThreshold = 0.5,
    int maxSpeakers = 32}) {
  throw UnsupportedError(
      'crispasrAgglomerativeCluster is not available on web');
}
