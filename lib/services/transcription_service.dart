// lib/services/transcription_service.dart (FIXED)
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import '../native/crispasr_import.dart' as crispasr;

import '../engines/crispasr_engine.dart' show CrispASREngine;
import '../engines/engine_factory.dart';
import '../engines/hfspace_engine.dart' show HfSpaceEngine;
import '../engines/transcription_engine.dart';
import 'audio_service.dart';
import 'log_service.dart';
import 'model_service.dart';
import 'diarization_service.dart';
import 'punc_service.dart';
import 'speaker_id_service.dart';
import 'vad_service.dart';

/// Bundles the CrispASR 0.6 parity decoder/diarisation/LID knobs that
/// don't fit cleanly as individual named args. Defaults match the
/// historical CrispASR behaviour, so callers that don't pass anything
/// see no change.
///
/// Why a class? Each new CrispASR cycle adds another optional tunable;
/// growing `transcribeFile`'s signature past 15 args every release is
/// painful for both us and call sites. Bundling new knobs here keeps
/// the public surface stable.
class AdvancedTranscribeOptions {
  /// Which VAD GGUF to use when VAD is enabled. Silero is bundled and
  /// always available; FireRed / MarbleNet / Whisper-VAD-EncDec
  /// require a Model Management download.
  final VadBackend vadBackend;

  /// Silero VAD decision threshold (0..1).
  final double vadThreshold;

  /// Shortest run of voiced frames (ms) kept as a speech segment.
  final int vadMinSpeechMs;

  /// Shortest silence (ms) needed to split one segment from the next.
  final int vadMinSilenceMs;

  /// Extra context padding (ms) added on each side of every segment.
  final int vadSpeechPadMs;

  /// Diarisation algorithm. `vadTurns` is mono-friendly and needs no
  /// extra model; `pyannote` requires `pyannote-v3-seg-*.gguf` to be on
  /// disk and falls back to `vadTurns` when missing.
  final crispasr.DiarizeMethod diarizeMethod;

  /// §5.8.1 — Resolve diarised cluster labels to enrolled speaker
  /// names via TitaNet. Requires the TitaNet GGUF + at least one
  /// enrolled speaker; silently passes through numeric labels when
  /// the prerequisites aren't met.
  final bool enableSpeakerRecognition;

  /// LID classifier. `whisper` reuses any multilingual ggml-*.bin
  /// already downloaded; `silero` needs its own ~16 MB GGUF.
  final crispasr.LidMethod lidMethod;

  /// Whisper tinydiarize speaker-turn markers.
  final bool tdrz;

  /// Whisper token-level DTW timestamps.
  final bool tokenTimestamps;

  /// Punctuation post-processor preference: `"firered"` for FireRedPunc,
  /// `"fullstop"` for fullstop-punc.
  final String puncFamily;

  /// Route LID inference to the GPU when supported (Metal/CUDA/Vulkan).
  /// `crispasr_detect_language_pcm` accepts this flag directly.
  final bool lidUseGpu;

  /// Enable flash-attention on the LID encoder pass.
  final bool lidFlashAttn;

  /// CPU thread count for LID and any other non-blocking helper passes.
  /// Defaults to 4 — matches CrispASR's historical n_threads.
  final int nThreads;

  /// Route the ASR session itself to the GPU at session-open time.
  /// True = use whichever GGML backend was compiled in (Metal / CUDA /
  /// Vulkan). False = force CPU, useful for debugging or low-memory
  /// laptops where keeping the GPU free for video / Slack matters
  /// more than ASR throughput. Threaded through CrispASR 0.6.1's
  /// `crispasr_session_open_with_params`; backends without a runtime
  /// `use_gpu` field keep their compile-time default.
  final bool asrUseGpu;

  /// Flash-attention on the ASR session's compute graph. Honoured by
  /// whisper natively; other backends accept the toggle but their
  /// graphs aren't yet branched on it (lands incrementally per
  /// backend). Default true — matches the ggml-side default.
  final bool asrFlashAttn;

  /// Cap on GPU-offloaded transformer layers for LLM-based backends
  /// (orpheus / voxtral / qwen3 / granite / chatterbox-T3). -1 means
  /// "as many as possible" (the C-side sentinel); 0 = run the LLM on
  /// CPU; >0 = explicit bound. Pre-0.6.2 dylibs ignore the value.
  final int asrNGpuLayers;

  /// §5.8 whisper subtitle formatting — soft cap on tokens per
  /// segment. 0 = whisper's default (no cap). Pairs with
  /// [splitOnWord] to produce SRT-friendly short lines instead
  /// of one-long-paragraph segments. Whisper-only; CTC / LLM
  /// session backends ignore the value.
  final int maxLen;

  /// §5.8 — when [maxLen] is set, split on word boundaries
  /// instead of mid-word. Yields readable subtitle lines.
  /// Whisper-only; no-op when [maxLen] = 0.
  final bool splitOnWord;

  /// §5.8 — split at sentence-ending punctuation (. ! ?).
  /// Dart-side post-processing applied to any backend's output.
  final bool splitOnPunct;

  /// §5.8 — GBNF grammar source. Non-empty enables grammar-
  /// constrained sampling on whisper (forces beam search; auto-
  /// bumps beam_size to 5 when the user left it at default 1).
  /// Empty means "no constraint". Whisper-only.
  final String grammarText;

  /// Root rule symbol name to start parsing from. Default "root".
  final String grammarRootRule;

  /// Whisper's `grammar_penalty` scalar (upstream default 100.0).
  final double grammarPenalty;

  /// Whisper decoder-fallback thresholds. See AdvancedOptions for
  /// per-field semantics. Whisper-only; other backends silently
  /// ignore because their wparams have no analog.
  final double entropyThold;
  final double logprobThold;
  final double noSpeechThold;
  final double temperatureInc;

  /// Whisper text-suppression + prompt-carry extras. See
  /// AdvancedOptions for per-field semantics.
  final bool suppressNonSpeechTokens;
  final String suppressTokensRegex;
  final bool carryInitialPrompt;

  /// §5.1.10 — RNNoise audio enhancement pre-step. When true, the
  /// transcribe paths run `crispasr.enhanceAudioRnnoise(...)` on
  /// the loaded PCM before the §5.8 window slice. Backend-
  /// agnostic. Pre-0.5.12 libcrispasr builds fall through silently
  /// (UnsupportedError → log + use original PCM).
  final bool enhanceAudio;

  /// §5.8 — `--offset-t` equivalent. Transcribe-window start
  /// (seconds). 0 = start of file. Backend-agnostic: the service
  /// slices the PCM before dispatch and shifts returned segment
  /// timestamps back to absolute file time.
  final double transcribeWindowStartSec;

  /// §5.8 — `--duration` equivalent. Transcribe-window duration
  /// (seconds). 0 = no cap, transcribe to end-of-file from
  /// [transcribeWindowStartSec].
  final double transcribeWindowDurationSec;

  /// §5.1.11 — Per-token top-N alternative-candidate capture
  /// (Whisper greedy decode only). 0 = off. See [AdvancedOptions.altN]
  /// for full semantics.
  final int altN;

  /// §5.26.2 — Hotwords for contextual biasing. Comma-separated.
  /// For CTC/TDT backends (parakeet), the C API applies the Aho-Corasick
  /// trie. For LLM backends, hotwords are injected into the ask prompt
  /// (done at the Dart level via mergeHotwordsIntoPrompt). Setting this
  /// here additionally calls session.setHotwords() at the FFI level,
  /// which gives CTC backends native hotword support.
  final String hotwords;

  /// Boost factor for CTC hotwords (default 1.5). Only used when
  /// [hotwords] is non-empty and the backend is CTC/TDT.
  final double hotwordsBoost;

  /// §10 — Explicit aligner model path or null for auto-discovery.
  /// When set, AlignerService uses this GGUF for forced alignment
  /// instead of auto-finding one on disk. Allows users to pick
  /// between canary-ctc-aligner and wav2vec2-aligner-<lang> variants.
  final String? alignerModel;

  const AdvancedTranscribeOptions({
    this.vadBackend = VadBackend.silero,
    this.vadThreshold = 0.5,
    this.vadMinSpeechMs = 250,
    this.vadMinSilenceMs = 100,
    this.vadSpeechPadMs = 30,
    this.diarizeMethod = crispasr.DiarizeMethod.vadTurns,
    this.enableSpeakerRecognition = false,
    this.lidMethod = crispasr.LidMethod.whisper,
    this.tdrz = false,
    this.tokenTimestamps = false,
    this.puncFamily = 'firered',
    this.lidUseGpu = false,
    this.lidFlashAttn = true,
    this.nThreads = 4,
    this.asrUseGpu = true,
    this.asrFlashAttn = true,
    this.asrNGpuLayers = -1,
    this.maxLen = 0,
    this.splitOnWord = false,
    this.splitOnPunct = false,
    this.grammarText = '',
    this.grammarRootRule = 'root',
    this.grammarPenalty = 100.0,
    this.entropyThold = 2.4,
    this.logprobThold = -1.0,
    this.noSpeechThold = 0.6,
    this.temperatureInc = 0.2,
    this.suppressNonSpeechTokens = false,
    this.suppressTokensRegex = '',
    this.carryInitialPrompt = false,
    this.enhanceAudio = false,
    this.transcribeWindowStartSec = 0.0,
    this.transcribeWindowDurationSec = 0.0,
    this.altN = 0,
    this.hotwords = '',
    this.hotwordsBoost = 1.5,
    this.alignerModel,
  });
}

/// §5.8 — Split segments at sentence-ending punctuation (. ! ?).
///
/// Mirrors CrispASR CLI's `--split-on-punct` but runs in Dart so it
/// works on any backend's output, not just whisper. When a segment's
/// text contains sentence-ending punctuation followed by a space and
/// more text, the segment is split at that boundary. Timestamps are
/// linearly interpolated based on character position.
List<TranscriptionSegment> splitSegmentsOnPunct(
    List<TranscriptionSegment> segments) {
  final result = <TranscriptionSegment>[];
  final re = RegExp(r'([.!?])\s+');

  for (final seg in segments) {
    final text = seg.text.trim();
    if (text.isEmpty) {
      result.add(seg);
      continue;
    }

    final matches = re.allMatches(text).toList();
    if (matches.isEmpty) {
      result.add(seg);
      continue;
    }

    final duration = seg.endTime - seg.startTime;
    var lastEnd = 0;
    var lastTime = seg.startTime;

    for (final m in matches) {
      final splitAt = m.end;
      final chunk = text.substring(lastEnd, splitAt).trim();
      if (chunk.isEmpty) continue;

      // Linearly interpolate the timestamp based on character position.
      final frac = splitAt / text.length;
      final chunkEnd = seg.startTime + duration * frac;

      result.add(TranscriptionSegment(
        text: chunk,
        startTime: lastTime,
        endTime: chunkEnd,
        speaker: seg.speaker,
        confidence: seg.confidence,
        metadata: Map<String, dynamic>.from(seg.metadata),
        tags: List<String>.from(seg.tags),
      ));
      lastEnd = splitAt;
      lastTime = chunkEnd;
    }

    // Trailing text after the last punctuation split.
    final tail = text.substring(lastEnd).trim();
    if (tail.isNotEmpty) {
      result.add(TranscriptionSegment(
        text: tail,
        startTime: lastTime,
        endTime: seg.endTime,
        speaker: seg.speaker,
        confidence: seg.confidence,
        metadata: Map<String, dynamic>.from(seg.metadata),
        tags: List<String>.from(seg.tags),
      ));
    }
  }

  return result;
}

/// Main transcription service that coordinates engines, audio processing, and diarization.
///
/// §5.26.5 — Long-form chunking note: CrisperWeaver sends the full audio
/// to the CrispASR session C API in one call. The C side handles internal
/// chunking per-backend (CrispASR #89/#114): parakeet/canary/fastconformer
/// use chunked-encode + single-decode; voxtral/cohere have streamed-encode
/// paths with boundary-overlap dedup. Since we don't do Dart-side 30s
/// chunking, there is no double-chunking risk. The `--offset-t/--duration`
/// window slice in the transcription screen is a user-driven trim, not a
/// chunking step.
class TranscriptionService {
  final AudioService _audioService;
  final ModelService _modelService;
  final SpeakerIdService? _speakerIdService;
  late final DiarizationService _diarizationService;
  final EngineManager _engineManager = EngineManager();
  late final VadService _vadService;
  late final PuncService _puncService;

  bool _isTranscribing = false;
  StreamSubscription<TranscriptionSegment>? _streamSubscription;

  /// The full result (including metadata) from the most recent successful
  /// transcription — populated after [transcribeFile] / [transcribeUrl]
  /// returns. Exposed so the UI can surface perf metrics and language
  /// detection without plumbing a new return type through every layer.
  TranscriptionResult? lastResult;

  /// §5.25.5 — Retained audio data from the most recent transcription
  /// so the multilingual tagging service can run LID post-transcription.
  /// Call [clearAudioBuffer] after tagging to free memory early.
  Float32List? lastAudioData;
  int lastSampleRate = 16000;

  /// Release the retained PCM buffer. Call after multilingual tagging
  /// (or any other post-transcription consumer) is done to avoid holding
  /// ~230 MB per hour of 16 kHz audio until the next transcription starts.
  void clearAudioBuffer() {
    lastAudioData = null;
  }

  TranscriptionService(
    this._audioService,
    this._modelService, {
    SpeakerIdService? speakerIdService,
  }) : _speakerIdService = speakerIdService {
    _puncService = PuncService(modelService: _modelService);
    _vadService = VadService(modelService: _modelService);
    _diarizationService = DiarizationService(
      modelService: _modelService,
      speakerIdService: _speakerIdService,
    );
  }

  bool get isTranscribing => _isTranscribing;
  TranscriptionEngine? get currentEngine => _engineManager.currentEngine;
  EngineType? get currentEngineType => _engineManager.currentEngineType;

  /// Initialize the transcription service
  Future<bool> initialize({
    EngineType? preferredEngine,
    String? modelName,
  }) async {
    try {
      await _modelService.initialize();

      // Initialize with preferred engine or use mock as safe fallback
      final engineType = preferredEngine ?? EngineType.mock;
      final success = await _engineManager.switchEngine(engineType,
          modelService: _modelService);

      if (!success) {
        Log.instance.w('service',
            'Failed to initialize $engineType engine, falling back to mock');
        return await _engineManager.initializeWithMock(
            modelService: _modelService);
      }

      // Load model if specified and engine supports it
      if (modelName != null && currentEngine != null) {
        try {
          await currentEngine!.loadModel(modelName);
        } catch (e, st) {
          Log.instance.w('service', 'Failed to load model $modelName',
              error: e, stack: st);
        }
      }

      return success;
    } catch (e, st) {
      Log.instance
          .e('service', 'init failed', error: e, stack: st);
      return await _engineManager.initializeWithMock();
    }
  }

  /// Transcribe an audio file
  Future<List<TranscriptionSegment>> transcribeFile(
    File audioFile, {
    String? language,
    bool enableDiarization = false,
    bool enableWordTimestamps = false,
    bool translate = false,
    bool beamSearch = false,
    String? initialPrompt,
    bool vad = false,
    bool restorePunctuation = false,
    String? targetLanguage,
    String? askPrompt,
    double temperature = 0.0,
    int bestOf = 1,
    int? minSpeakers,
    int? maxSpeakers,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
    /// §5.23 Q3 resume offset. When > 0 the engine skips audio
    /// before this second mark and emits segments with absolute
    /// timestamps. Caller (the batch drain loop) populates this
    /// from BatchJob.resumeOffsetSec after a crash-recovered job.
    double startOffsetSec = 0.0,
    void Function(double progress)? onProgress,
    void Function(TranscriptionSegment segment)? onSegment,
  }) async {
    if (_isTranscribing) {
      throw const TranscriptionServiceException(
          'Already transcribing. Stop current transcription first.');
    }

    if (currentEngine == null) {
      throw const TranscriptionServiceException(
          'No transcription engine available. Please initialize first.');
    }

    _isTranscribing = true;
    onProgress?.call(0.0);

    // If the user opted into VAD, make sure the chosen backend's GGUF
    // is on disk. VadService falls back to bundled silero when a
    // catalog VAD GGUF isn't downloaded yet.
    String? vadModelPath;
    if (vad) {
      vadModelPath = await _vadService.ensureModel(backend: advanced.vadBackend);
      if (vadModelPath == null) {
        Log.instance.w(
            'service',
            'VAD requested but model unavailable — '
                'transcribing without VAD');
      }
    }

    // Apply sticky service-level preferences before transcription so
    // each invocation sees the user's current picks.
    _puncService.preferredFamily = advanced.puncFamily;
    _puncService.preferredTruecaseLang = language;
    _puncService.invalidate();
    // LidService is owned by the engine, not us — engine.transcribe
    // reads `advanced.lidMethod` from the passed-through options.

    try {
      // Step 1: Load and process audio (10% of progress)
      onProgress?.call(0.05);
      lastAudioData = null; // Clear previous
      final audioData = await _audioService.loadAudioFile(audioFile);
      lastAudioData = audioData.samples;
      lastSampleRate = audioData.sampleRate;
      onProgress?.call(0.1);

      // §5.1.10 — RNNoise enhancement runs on the full loaded PCM
      // before the §5.8 window slice. Order matters: slicing first
      // would lose context the denoiser needs at the boundary
      // (RNNoise has ~10 ms of look-ahead state per frame).
      // Pre-0.5.12 libcrispasr builds raise UnsupportedError; we
      // log and fall through to the un-enhanced samples so toggling
      // the switch never breaks transcription.
      Float32List baseSamples = audioData.samples;
      if (advanced.enhanceAudio) {
        try {
          baseSamples = crispasr.enhanceAudioRnnoise(audioData.samples);
        } on UnsupportedError catch (e) {
          Log.instance.w(
              'service',
              'enhanceAudio requested but libcrispasr lacks the '
                  'symbol — using original PCM ($e)');
        }
      }

      // §5.8 — `--offset-t / --duration` window. When set, slice
      // here so the engine only sees the requested slice; we then
      // shift returned segment timestamps by the window start so
      // they're absolute in file time. A user-set window overrides
      // any resume offset (the explicit pick wins over a checkpoint).
      final hasWindow = advanced.transcribeWindowStartSec > 0 ||
          advanced.transcribeWindowDurationSec > 0;
      final samples = hasWindow
          ? CrispASREngine.sliceTranscribeWindow(
              baseSamples,
              audioData.sampleRate,
              advanced.transcribeWindowStartSec,
              advanced.transcribeWindowDurationSec)
          : baseSamples;
      // When windowing, pass startOffsetSec=0 to the engine (the
      // slice already done above means there's nothing for the
      // engine to trim) and shift returned segments here.
      // Otherwise honour the caller's resume offset.
      final engineStartOffset = hasWindow ? 0.0 : startOffsetSec;
      final segmentShift =
          hasWindow ? advanced.transcribeWindowStartSec : 0.0;
      void Function(TranscriptionSegment)? wrappedOnSegment;
      if (onSegment != null) {
        wrappedOnSegment = segmentShift > 0
            ? (seg) => onSegment(CrispASREngine.shiftSegmentForResume(seg,
                offsetSeconds: segmentShift))
            : onSegment;
      }

      // Step 2: Perform transcription (60% of progress)
      var engineSegments = await _performTranscription(
        samples,
        language: language,
        enableWordTimestamps: enableWordTimestamps,
        translate: translate,
        beamSearch: beamSearch,
        initialPrompt: initialPrompt,
        vad: vad && vadModelPath != null,
        vadModelPath: vadModelPath,
        targetLanguage: targetLanguage,
        askPrompt: askPrompt,
        temperature: temperature,
        bestOf: bestOf,
        advanced: advanced,
        startOffsetSec: engineStartOffset,
        onProgress: (progress) => onProgress?.call(0.1 + progress * 0.6),
        onSegment: wrappedOnSegment,
      );
      if (segmentShift > 0) {
        engineSegments = engineSegments
            .map((s) => CrispASREngine.shiftSegmentForResume(s,
                offsetSeconds: segmentShift))
            .toList(growable: false);
      }

      onProgress?.call(0.7);

      // Use segments directly from engine (they're already TranscriptionSegment)
      List<TranscriptionSegment> segments = engineSegments;
      Log.instance.d('service', 'Engine returned ${segments.length} segments');

      // Step 3: Speaker diarization if enabled (20% of progress)
      if (enableDiarization && segments.isNotEmpty) {
        onProgress?.call(0.75);

        segments = await _diarizationService.diarizeSegments(
          audioData,
          segments,
          minSpeakers: minSpeakers,
          maxSpeakers: maxSpeakers,
          method: advanced.diarizeMethod,
          enableSpeakerRecognition: advanced.enableSpeakerRecognition,
          onProgress: (progress) => onProgress?.call(0.75 + progress * 0.2),
        );
      }

      // Step 4: Punctuation + truecasing restoration (5% of progress) —
      // runs after diarization so the speaker-aware splits stay intact.
      // Routes by user-picked puncFamily: 'pcs' → all-in-one PcsModel,
      // 'firered'/'fullstop' → PuncModel + truecaser chain.
      if (restorePunctuation && segments.isNotEmpty) {
        onProgress?.call(0.95);
        if (advanced.puncFamily == 'pcs') {
          segments = await _puncService.restorePcs(segments);
        } else {
          segments = await _puncService.restore(segments);
          segments = await _puncService.restoreTruecase(segments);
        }
      }

      // §5.8 — Dart-side split at sentence-ending punctuation.
      // Applied after all other post-processing so it can split
      // punctuation-restored text cleanly.
      if (advanced.splitOnPunct && segments.isNotEmpty) {
        segments = splitSegmentsOnPunct(segments);
      }

      onProgress?.call(1.0);
      return segments;
    } catch (e) {
      throw TranscriptionServiceException('File transcription failed: $e');
    } finally {
      _isTranscribing = false;
    }
  }

  /// Transcribe raw audio bytes — the web path where we don't have a
  /// filesystem path. Delegates directly to the engine (HfSpaceEngine
  /// POSTs the bytes to the remote server). Skips local audio decoding,
  /// diarization, and punctuation restoration (those are server-side).
  Future<List<TranscriptionSegment>> transcribeBytes(
    Uint8List bytes,
    String filename, {
    String? language,
    bool translate = false,
    bool vad = false,
    bool diarize = false,
    bool punctuation = true,
    String? initialPrompt,
    double temperature = 0.0,
    void Function(double progress)? onProgress,
    void Function(TranscriptionSegment segment)? onSegment,
  }) async {
    if (_isTranscribing) {
      throw const TranscriptionServiceException(
          'Already transcribing. Stop current transcription first.');
    }
    if (currentEngine == null) {
      throw const TranscriptionServiceException(
          'No transcription engine available. Please initialize first.');
    }
    _isTranscribing = true;
    onProgress?.call(0.0);
    try {
      // For HfSpaceEngine, call transcribeBytes directly.
      final engine = currentEngine!;
      if (engine is HfSpaceEngine) {
        final result = await engine.transcribeBytes(
          bytes,
          filename,
          language: language,
          translate: translate,
          vad: vad,
          diarize: diarize,
          punctuation: punctuation,
          initialPrompt: initialPrompt,
          temperature: temperature,
          onSegment: onSegment,
          onProgress: onProgress,
        );
        lastResult = result;
        return result.segments;
      }
      // Fallback: for non-HfSpace engines, we can't decode on web.
      throw const TranscriptionServiceException(
          'Byte-based transcription requires the CrispASR Cloud engine.');
    } catch (e) {
      if (e is TranscriptionServiceException) rethrow;
      throw TranscriptionServiceException('Transcription failed: $e');
    } finally {
      _isTranscribing = false;
    }
  }

  /// Transcribe audio from URL
  Future<List<TranscriptionSegment>> transcribeUrl(
    String url, {
    String? language,
    bool enableDiarization = false,
    bool enableWordTimestamps = false,
    bool translate = false,
    bool beamSearch = false,
    String? initialPrompt,
    bool vad = false,
    bool restorePunctuation = false,
    String? targetLanguage,
    String? askPrompt,
    double temperature = 0.0,
    int bestOf = 1,
    int? minSpeakers,
    int? maxSpeakers,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
    void Function(double progress)? onProgress,
    void Function(TranscriptionSegment segment)? onSegment,
  }) async {
    if (_isTranscribing) {
      throw const TranscriptionServiceException(
          'Already transcribing. Stop current transcription first.');
    }

    try {
      // Step 1: Download audio (10% of progress)
      onProgress?.call(0.0);
      final audioFile = await _audioService.downloadAudioFromUrl(
        url,
        onProgress: (progress) => onProgress?.call(progress * 0.1),
      );

      // Step 2: Transcribe the downloaded file (90% of progress)
      return await transcribeFile(
        audioFile,
        language: language,
        enableDiarization: enableDiarization,
        enableWordTimestamps: enableWordTimestamps,
        translate: translate,
        beamSearch: beamSearch,
        initialPrompt: initialPrompt,
        vad: vad,
        restorePunctuation: restorePunctuation,
        targetLanguage: targetLanguage,
        askPrompt: askPrompt,
        temperature: temperature,
        bestOf: bestOf,
        minSpeakers: minSpeakers,
        maxSpeakers: maxSpeakers,
        advanced: advanced,
        onProgress: (progress) => onProgress?.call(0.1 + progress * 0.9),
        onSegment: onSegment,
      );
    } catch (e) {
      throw TranscriptionServiceException('URL transcription failed: $e');
    }
  }

  /// Start streaming transcription (if supported by current engine)
  Stream<TranscriptionSegment>? transcribeStream(
    Stream<Float32List> audioStream, {
    String? language,
    bool enableWordTimestamps = false,
  }) {
    final engine = currentEngine;
    if (engine == null) {
      throw const TranscriptionServiceException(
          'No transcription engine available');
    }

    if (!engine.supportsStreaming) {
      return null; // Engine doesn't support streaming
    }

    return engine.transcribeStream(
      audioStream,
      language: language,
      enableWordTimestamps: enableWordTimestamps,
    );
  }

  /// Stop ongoing transcription
  Future<void> stopTranscription() async {
    _isTranscribing = false;
    await _streamSubscription?.cancel();
    _streamSubscription = null;

    final engine = currentEngine;
    if (engine != null) {
      try {
        await engine.cancel();
      } catch (e, st) {
        Log.instance.w('service', 'Error stopping transcription',
            error: e, stack: st);
      }
    }
  }

  /// Switch to a different transcription engine
  Future<bool> switchEngine(EngineType engineType,
      {Map<String, dynamic>? config}) async {
    if (_isTranscribing) {
      throw const TranscriptionServiceException(
          'Cannot change engine while transcribing');
    }

    try {
      return await _engineManager.switchEngine(engineType,
          modelService: _modelService, config: config);
    } catch (e, st) {
      Log.instance.w('service', 'Error switching engine to $engineType',
          error: e, stack: st);
      return false;
    }
  }

  /// Get available models for the current engine
  Future<List<EngineModel>> getAvailableModels() async {
    final engine = currentEngine;
    if (engine == null) {
      throw const TranscriptionServiceException('No engine initialized');
    }

    try {
      return await engine.getAvailableModels();
    } catch (e) {
      throw TranscriptionServiceException('Failed to get available models: $e');
    }
  }

  /// Load a specific model for the current engine
  Future<bool> loadModel(String modelId,
      {void Function(double progress)? onProgress}) async {
    final engine = currentEngine;
    if (engine == null) {
      throw const TranscriptionServiceException('No engine initialized');
    }

    if (_isTranscribing) {
      throw const TranscriptionServiceException(
          'Cannot load model while transcribing');
    }

    try {
      return await engine.loadModel(modelId, onProgress: onProgress);
    } catch (e) {
      throw TranscriptionServiceException('Failed to load model $modelId: $e');
    }
  }

  /// Unload the current model
  Future<void> unloadModel() async {
    final engine = currentEngine;
    if (engine == null) return;

    if (_isTranscribing) {
      throw const TranscriptionServiceException(
          'Cannot unload model while transcribing');
    }

    try {
      await engine.unloadModel();
    } catch (e, st) {
      Log.instance.w('service', 'Error unloading model',
          error: e, stack: st);
    }
  }

  /// Update engine configuration
  Future<void> updateEngineConfig(Map<String, dynamic> config) async {
    final engine = currentEngine;
    if (engine == null) {
      throw const TranscriptionServiceException('No engine initialized');
    }

    try {
      await engine.updateConfig(config);
    } catch (e) {
      throw TranscriptionServiceException('Failed to update engine config: $e');
    }
  }

  /// Get current engine information
  EngineInfo? getCurrentEngineInfo() {
    if (currentEngineType == null) return null;

    final availableEngines = EngineFactory.getAvailableEngines();
    final engineType = currentEngineType!;

    return EngineInfo(
      type: engineType,
      isActive: true,
      isSupported: availableEngines.contains(engineType),
    );
  }

  /// Get all available engines for selection
  List<EngineInfo> getAvailableEngines() {
    return _engineManager.getAvailableEnginesInfo();
  }

  /// Get engine status information
  EngineStatus getEngineStatus() {
    final engine = currentEngine;

    return EngineStatus(
      engineType: currentEngineType,
      isInitialized: engine?.isInitialized ?? false,
      isProcessing: engine?.isProcessing ?? false,
      currentModelId: engine?.currentModelId,
      supportsStreaming: engine?.supportsStreaming ?? false,
      supportsSpeakerDiarization: engine?.supportsSpeakerDiarization ?? false,
      supportsWordTimestamps: engine?.supportsWordTimestamps ?? false,
      supportedLanguages: engine?.supportedLanguages ?? [],
    );
  }

  // Private helper methods

  /// Perform transcription using the current engine
  Future<List<TranscriptionSegment>> _performTranscription(
    Float32List audioSamples, {
    String? language,
    bool enableWordTimestamps = false,
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
    void Function(double progress)? onProgress,
    void Function(TranscriptionSegment segment)? onSegment,
  }) async {
    final engine = currentEngine;
    if (engine == null) {
      throw const TranscriptionServiceException(
          'No engine available for transcription');
    }

    try {
      final result = await engine.transcribe(
        audioSamples,
        language: language,
        enableWordTimestamps: enableWordTimestamps,
        enableSpeakerDiarization: false, // We handle diarization separately
        translate: translate,
        beamSearch: beamSearch,
        initialPrompt: initialPrompt,
        vad: vad,
        vadModelPath: vadModelPath,
        targetLanguage: targetLanguage,
        askPrompt: askPrompt,
        temperature: temperature,
        bestOf: bestOf,
        advanced: advanced,
        startOffsetSec: startOffsetSec,
        onSegment: onSegment,
        onProgress: onProgress,
      );
      lastResult = result;
      return result.segments;
    } catch (e) {
      throw TranscriptionServiceException('Engine transcription failed: $e');
    }
  }

  /// Run diarization as a standalone post-process on already-
  /// transcribed segments. Used by the §5.23 Q2 v2 pool path which
  /// has the worker emit raw segments first, then runs diarize on
  /// main thread sequentially per file. No-ops when no pyannote
  /// model is on disk. Mirrors what [transcribeFile] does
  /// internally, exposed here so the pool dispatcher can reuse it.
  Future<List<TranscriptionSegment>> diarize(
    AudioData audioData,
    List<TranscriptionSegment> segments, {
    int? minSpeakers,
    int? maxSpeakers,
    crispasr.DiarizeMethod method = crispasr.DiarizeMethod.vadTurns,
    bool enableSpeakerRecognition = false,
  }) {
    return _diarizationService.diarizeSegments(
      audioData,
      segments,
      minSpeakers: minSpeakers,
      maxSpeakers: maxSpeakers,
      method: method,
      enableSpeakerRecognition: enableSpeakerRecognition,
    );
  }

  /// Run punctuation + truecasing restoration on already-transcribed
  /// segments. Same use case as [diarize] — pool path calls this after
  /// the worker returns. Tries PCS first (all-in-one), falls back to
  /// FireRedPunc + truecaser chain.
  Future<List<TranscriptionSegment>> restorePunctuation(
      List<TranscriptionSegment> segments) async {
    // Try PCS first when available.
    final pcsResult = await _puncService.restorePcs(segments);
    if (!identical(pcsResult, segments)) return pcsResult;
    // Fall back to FireRedPunc/fullstop-punc + truecaser chain.
    var result = await _puncService.restore(segments);
    result = await _puncService.restoreTruecase(result);
    return result;
  }

  /// Resolve the VAD model path on disk for [backend]. The pool
  /// dispatcher reads this once per batch and passes the path to
  /// the worker so it can call `transcribeVad` directly inside the
  /// isolate. Returns null when no VAD GGUF is available.
  Future<String?> resolveVadModelPath(
      {VadBackend backend = VadBackend.silero}) {
    return _vadService.ensureModel(backend: backend);
  }

  /// Clean up resources
  void dispose() {
    stopTranscription();
    _engineManager.dispose();
    _puncService.dispose();
  }
}

/// Engine status information
class EngineStatus {
  final EngineType? engineType;
  final bool isInitialized;
  final bool isProcessing;
  final String? currentModelId;
  final bool supportsStreaming;
  final bool supportsSpeakerDiarization;
  final bool supportsWordTimestamps;
  final List<String> supportedLanguages;

  const EngineStatus({
    this.engineType,
    required this.isInitialized,
    required this.isProcessing,
    this.currentModelId,
    required this.supportsStreaming,
    required this.supportsSpeakerDiarization,
    required this.supportsWordTimestamps,
    required this.supportedLanguages,
  });

  bool get hasActiveEngine => engineType != null && isInitialized;
  bool get canTranscribe => hasActiveEngine && !isProcessing;
  bool get hasModelLoaded => currentModelId != null;

  String get statusDescription {
    if (!hasActiveEngine) return 'No engine initialized';
    if (isProcessing) return 'Processing...';
    if (!hasModelLoaded) return 'No model loaded';
    return 'Ready';
  }
}

/// Service-level transcription failure.
///
/// The per-engine [TranscriptionException] type from
/// `transcription_engine.dart` wraps engine-originated errors; this one is
/// thrown by the orchestrating service itself.
class TranscriptionServiceException implements Exception {
  final String message;
  final dynamic originalError;

  const TranscriptionServiceException(this.message, [this.originalError]);

  @override
  String toString() {
    if (originalError != null) {
      return 'TranscriptionServiceException: $message (caused by: $originalError)';
    }
    return 'TranscriptionServiceException: $message';
  }
}
