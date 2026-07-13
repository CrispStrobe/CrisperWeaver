import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../native/crispasr_import.dart' as crispasr;

import 'transcription_engine.dart';
import '../services/aligner_service.dart';
import '../services/lid_service.dart';
import '../services/log_service.dart';
import '../services/model_service.dart';
import '../services/transcription_service.dart' show AdvancedTranscribeOptions;
import '../services/transcription_worker_pool.dart';

/// Transcription engine backed by the CrispASR FFI package.
///
/// CrispASR is a ggml-based, pure-Dart FFI bridge to a unified ASR runtime
/// that supports Whisper, Parakeet, Canary, Qwen3-ASR, Voxtral, and
/// FastConformer models. This engine exposes the Whisper-compatible API
/// exported by `package:crispasr` through the app's `TranscriptionEngine`
/// abstraction.
class CrispASREngine implements TranscriptionEngine {
  crispasr.CrispASR? _model;
  crispasr.CrispasrSession? _session;
  // §9 Android UI freeze fix: keeps the synchronous FFI call off the
  // platform isolate by running it inside a worker isolate. Spawned
  // alongside the main `_session` whenever a session-backend model
  // with no companion files loads. Skipped when the backend needs
  // companions (codec / voice tables) because the pool worker has
  // no way to load them today. When null, transcribe falls back to
  // the direct main-isolate call — older behaviour, may ANR on
  // Android for long jobs.
  TranscriptionWorkerPool? _sessionPool;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _cancelRequested = false;
  String? _currentModelId;
  String? _currentModelPath;
  // §1 — the whisper main-isolate CrispASR handle is created lazily. Its
  // ~10 s FFI ctor used to block the platform isolate at loadModel time.
  // Since most whisper transcribes now run through `_sessionPool` (a
  // worker isolate), the main-isolate handle is only needed for the niche
  // paths with no session equivalent: whisper-only TranscribeOptions
  // (tdrz / maxLen / splitOnWord), streaming, and language detection.
  // Until one of those is hit, `_lazyModelPath` holds the path and
  // `_model` stays null; `_ensureWhisperModel()` opens it on first use.
  String? _lazyModelPath;
  // Backend id of the currently-loaded model. The whisper-vs-session
  // discriminator (`_isWhisper`) reads this so routing stays correct
  // while `_model` is still null (deferred). Null when nothing is loaded.
  String? _currentBackend;
  Map<String, dynamic> _config = {};
  ModelService? _modelService;
  AlignerService? _alignerService;
  LidService? _lidService;

  @override
  String get engineId => 'crispasr';

  @override
  String get engineName => 'CrispASR (ggml)';

  @override
  String get version => '0.8.7';

  @override
  // Whisper always supports streaming, so report true for a deferred
  // whisper model (`_model` still null) too — otherwise transcribeStream
  // callers would see false during the lazy window. Defer to the handle's
  // own value once it's open.
  bool get supportsStreaming =>
      _model?.supportsStreaming ?? (_isWhisper ? true : _session != null);

  bool get _isWhisper => _currentBackend == 'whisper';

  /// Returns the main-isolate whisper handle, opening it on first use.
  /// The ~10 s FFI ctor is deferred from loadModel (§1) to here. Callers
  /// are the niche whisper-only paths (direct transcribe fallback,
  /// streaming, LID). Caches after the first open; safe to call
  /// repeatedly. Throws [ModelLoadException] only when no whisper model
  /// is loaded at all.
  crispasr.CrispASR _ensureWhisperModel() {
    final existing = _model;
    if (existing != null) return existing;
    final path = _lazyModelPath ?? _currentModelPath;
    if (path == null) {
      throw const ModelLoadException(
          'No whisper model loaded', 'crispasr', 'none');
    }
    Log.instance.i('crispasr',
        'opening whisper model on first use (deferred from load)',
        fields: {'path': path});
    final m = crispasr.CrispASR(path);
    _model = m;
    return m;
  }

  @override
  bool get supportsLanguageDetection => true;

  @override
  bool get supportsWordTimestamps => true;

  @override
  bool get supportsSpeakerDiarization => false;

  @override
  List<String> get supportedLanguages => const [
        'auto',
        'en',
        'zh',
        'de',
        'es',
        'ru',
        'ko',
        'fr',
        'ja',
        'pt',
        'tr',
        'pl',
        'ca',
        'nl',
        'ar',
        'sv',
        'it',
        'id',
        'hi',
        'fi',
        'vi',
        'he',
        'uk',
        'el',
        'ms',
        'cs',
        'ro',
        'da',
        'hu',
        'ta',
        'no',
        'th',
        'ur',
        'hr',
        'bg',
        'lt',
        'la',
        'mi',
        'ml',
        'cy',
        'sk',
        'te',
        'fa',
        'lv',
        'bn',
        'sr',
        'az',
        'sl',
        'kn',
        'et',
        'mk',
        'br',
        'eu',
        'is',
        'hy',
        'ne',
        'mn',
        'bs',
        'kk',
        'sq',
        'sw',
        'gl',
        'mr',
        'pa',
        'si',
        'km',
        'sn',
        'yo',
        'so',
        'af',
        'oc',
        'ka',
        'be',
        'tg',
        'sd',
        'gu',
        'am',
        'yi',
        'lo',
        'uz',
        'fo',
        'ht',
        'ps',
        'tk',
        'nn',
        'mt',
        'sa',
        'lb',
        'my',
        'bo',
        'tl',
        'mg',
        'as',
        'tt',
        'haw',
        'ln',
        'ha',
        'ba',
        'jw',
        'su',
      ];

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isProcessing => _isProcessing;

  @override
  String? get currentModelId => _currentModelId;

  @override
  Map<String, dynamic> get currentConfig => Map.unmodifiable(_config);

  @override
  Future<bool> initialize(
      {ModelService? modelService, Map<String, dynamic>? config}) async {
    try {
      _config = Map<String, dynamic>.from(config ?? const {});
      _modelService = modelService;
      if (_modelService != null) {
        await _modelService!.initialize();
        _lidService = LidService(_modelService!);
        _alignerService = AlignerService(modelService: _modelService);
      }
      _alignerService ??= AlignerService();
      _isInitialized = true;
      final libName = crispasr.CrispASR.defaultLibName();
      final backends = crispasr.CrispasrSession.availableBackends();
      Log.instance.i('crispasr', 'engine initialised', fields: {
        'lib': libName,
        'backends': backends.join(','),
        'count': backends.length,
      });
      return true;
    } catch (e, st) {
      Log.instance.e('crispasr', 'Initialize failed', error: e, stack: st);
      throw EngineInitializationException(
        'Failed to initialize CrispASR engine: $e',
        engineId,
        e,
      );
    }
  }

  @override
  Future<void> dispose() async {
    await unloadModel();
    _isInitialized = false;
    _isProcessing = false;
    _config.clear();
  }

  @override
  Future<List<EngineModel>> getAvailableModels() async {
    if (!_isInitialized || _modelService == null) {
      throw const EngineInitializationException(
        'Engine not initialized',
        'crispasr',
      );
    }

    final whisperModels = await _modelService!.getWhisperCppModels();
    return whisperModels
        .map((m) => EngineModel(
              id: m.name,
              name: m.displayName,
              description: m.description,
              sizeBytes: m.sizeBytes,
              supportedLanguages: supportedLanguages,
              isDownloaded: m.isDownloaded,
              localPath: m.localPath,
              metadata: {
                'framework': 'crispasr',
                'runtime': 'ggml',
                'backend': m.backend,
              },
            ))
        .toList();
  }

  @override
  Future<bool> loadModel(
    String modelId, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_isInitialized || _modelService == null) {
      throw const EngineInitializationException(
        'Engine not initialized',
        'crispasr',
      );
    }
    if (_currentModelId == modelId &&
        (_model != null ||
            _session != null ||
            _sessionPool != null ||
            _lazyModelPath != null)) {
      onProgress?.call(1.0);
      return true;
    }

    final lookedUp = _modelService!.lookupDefinition(modelId);
    if (lookedUp == null) {
      throw ModelLoadException(
        'Model definition not found for $modelId',
        engineId,
        modelId,
      );
    }
    // Mutable so the #30 GGUF-metadata backend correction below can
    // replace it in place; all downstream uses read the resolved value.
    var def = lookedUp;

    // Backends linked into the bundled dylib. Empty means the build is
    // too old to expose `crispasr_session_available_backends` (or the
    // lib failed to open) — treat that as "unknown", not "nothing
    // linked", and skip the front-door gate below rather than rejecting
    // every model (#30).
    final available = crispasr.CrispasrSession.availableBackends();
    Log.instance.d('crispasr',
        'Available backends in libwhisper: ${available.join(", ")}');

    onProgress?.call(0.05);

    final modelPath = await _modelService!.getWhisperCppModelPath(modelId);
    if (modelPath == null) {
      // Diagnostic: surface why the path resolution failed so we can tell
      // "the catalog entry doesn't exist" apart from "the file isn't on
      // disk" apart from "wrong fileName vs what was actually downloaded".
      final dir = _modelService!.whisperCppDir();
      final expectedFile = def.fileName;
      final expectedPath = path.join(dir, expectedFile);
      final exists = await File(expectedPath).exists();
      Log.instance.w(
          'crispasr',
          'Model not found via getWhisperCppModelPath',
          fields: {
            'modelId': modelId,
            'expected_filename': expectedFile,
            'expected_path': expectedPath,
            'file_exists': exists,
            'backend': def.backend,
            'size_bytes': exists ? await File(expectedPath).length() : 0,
          });
      throw ModelLoadException(
        'Model $modelId is not downloaded yet.',
        engineId,
        modelId,
      );
    }

    if (!await File(modelPath).exists()) {
      throw ModelLoadException(
        'Model file missing on disk: $modelPath',
        engineId,
        modelId,
      );
    }

    // #30 — `auto`-probed and mislabelled GGUFs carry a placeholder
    // backend chosen before the file was on disk (the HF-repo dialog
    // falls back to `whisper` for the probe pass, and the corrective
    // auto-detect only ran on *download* — never for files already
    // present). Now that the GGUF is on disk, read its architecture
    // metadata to recover the real backend so e.g. a Cohere ASR model
    // isn't force-loaded through the whisper pipeline and crash. Only
    // kicks in when the stored backend is `auto`/empty or isn't linked
    // into this dylib — a correctly-tagged, runnable model is untouched.
    if (modelPath.endsWith('.gguf') &&
        (def.backend.isEmpty ||
            def.backend == 'auto' ||
            !available.contains(def.backend))) {
      try {
        final detected = crispasr.detectBackendFromGguf(modelPath);
        if (detected != null &&
            detected.isNotEmpty &&
            detected != def.backend) {
          Log.instance.i(
              'crispasr',
              'auto-detected backend "$detected" from GGUF for $modelId '
              '(was "${def.backend}")');
          _modelService!.overrideBackend(modelId, detected);
          def = def.copyWith(backend: detected);
        }
      } catch (e, st) {
        Log.instance.w('crispasr',
            'detectBackendFromGguf failed — using stored backend',
            error: e, stack: st);
      }
    }

    // Front-door backend gate — enforced only when the dylib actually
    // reported its linked backends. An empty list is "unknown" (see
    // above), so we let the session open surface the real native error
    // rather than pre-emptively rejecting a model that may well load.
    if (available.isNotEmpty && !available.contains(def.backend)) {
      throw ModelLoadException(
        'Model uses the ${def.backend} backend. The bundled libwhisper '
        'was built with {${available.join(", ")}}. Rebuild CrispASR '
        'with the ${def.backend} backend linked in.',
        engineId,
        modelId,
      );
    }

    onProgress?.call(0.4);

    // Free previous model before loading a new one.
    await unloadModel();

    int fileBytes = 0;
    try {
      fileBytes = await File(modelPath).length();
    } catch (e) {
      Log.instance.d('crispasr', 'model file size probe failed',
          fields: {'path': modelPath, 'err': e.toString()});
    }
    final done = Log.instance.stopwatch(
      'crispasr',
      msg: 'model loaded',
      fields: {
        'model': modelId,
        'backend': def.backend,
        'path': modelPath,
        'bytes': fileBytes,
        'quant': def.quantization,
      },
    );
    try {
      Log.instance.d('crispasr', 'loading model', fields: {
        'model': modelId,
        'backend': def.backend,
        'path': modelPath,
        'bytes': fileBytes
      });
      if (def.backend == 'whisper') {
        // §1 — defer the blocking CrispASR ctor. The worker pool below
        // loads the model off the platform isolate for the common
        // transcribe path; `_ensureWhisperModel()` opens the main-isolate
        // handle lazily only for the niche paths that still need it.
        _lazyModelPath = modelPath;
        // §15 — Spawn a 1-worker pool for whisper too so transcribe
        // calls don't block the UI isolate on Android. CrispASR's
        // session API can open whisper, so the same TranscriptionWorker
        // pattern works; the worker uses session.transcribe under the
        // hood. Whisper-only options that don't have a session-side
        // equivalent (tdrz / maxLen / splitOnWord — set via
        // TranscribeOptions on _model) fall back to the direct
        // _model.transcribePcm() path in _runTranscription.
        try {
          _sessionPool = await TranscriptionWorkerPool.spawn(
            count: 1,
            modelPath: modelPath,
            backend: 'whisper',
            useGpu: (_config['asrUseGpu'] as bool?) ?? true,
            flashAttn: (_config['asrFlashAttn'] as bool?) ?? true,
            nThreads: 4,
            nGpuLayers: (_config['asrNGpuLayers'] as int?) ?? -1,
          );
          Log.instance.i('crispasr', 'whisper worker pool spawned',
              fields: {'model': modelId});
        } catch (e, st) {
          Log.instance.w(
              'crispasr',
              'whisper worker pool spawn failed — UI may freeze '
                  'during long transcribes',
              error: e,
              stack: st);
          _sessionPool = null;
        }
      } else {
        // CrispASR 0.6.1+: prefer the params-aware open so the
        // user-controlled asrUseGpu toggle takes effect at session-
        // open time. Fall back to plain open() on older dylibs.
        // The flag is stashed in `_config['asrUseGpu']` by the
        // engine factory at load time; default to true.
        final useGpu = (_config['asrUseGpu'] as bool?) ?? true;
        final flashAttn = (_config['asrFlashAttn'] as bool?) ?? true;
        final nGpuLayers = (_config['asrNGpuLayers'] as int?) ?? -1;
        try {
          _session = crispasr.CrispasrSession.openWithParams(
            modelPath,
            backend: def.backend,
            nThreads: 4,
            useGpu: useGpu,
            flashAttn: flashAttn,
            nGpuLayers: nGpuLayers,
          );
        } on UnsupportedError {
          // libcrispasr < 0.6.1 — historical default (GPU on, n_threads 4).
          _session =
              crispasr.CrispasrSession.open(modelPath, backend: def.backend);
        }
        // Some backends need a companion file before they can run:
        //   * qwen3-tts → tokenizer GGUF via setCodecPath
        //   * orpheus    → SNAC codec GGUF via setCodecPath
        //   * mimo-asr   → mimo_tokenizer GGUF via setCodecPath
        //   * vibevoice-tts / kokoro → voicepack GGUF via setVoice
        // Walk the def.companions list in order; route by ModelKind so
        // codec entries go through setCodecPath and voice entries go
        // through setVoice. Missing companions fail loudly here rather
        // than at the first transcribe/synthesize call.
        for (final companion in def.companions) {
          final cdef = _modelService!.lookupDefinition(companion);
          if (cdef == null) {
            throw ModelLoadException(
                'Companion "$companion" not found in model catalog '
                '(required by ${def.backend})',
                engineId,
                modelId);
          }
          final cpath =
              await _modelService!.getWhisperCppModelPath(companion);
          if (cpath == null || !await File(cpath).exists()) {
            throw ModelLoadException(
                'Companion "${cdef.displayName}" not downloaded '
                '(required by ${def.backend} — open Models and download it first)',
                engineId,
                modelId);
          }
          if (cdef.kind == ModelKind.codec) {
            _session!.setCodecPath(cpath);
            Log.instance.d('crispasr', 'companion: codec loaded',
                fields: {'backend': def.backend, 'companion': companion});
          } else if (cdef.kind == ModelKind.voice) {
            _session!.setVoice(cpath);
            Log.instance.d('crispasr', 'companion: voice loaded',
                fields: {'backend': def.backend, 'companion': companion});
          }
        }
        // §9 — spawn a 1-worker pool alongside the main-isolate
        // session so single-file transcribe stays off the platform
        // isolate. Skip when the backend uses companions (the pool
        // can't currently re-apply setCodecPath / setVoice on the
        // worker side) and fall back to the direct call in that
        // case. Pool spawn failure is non-fatal — we log and the
        // user just gets the older behaviour.
        if (def.companions.isEmpty) {
          try {
            _sessionPool = await TranscriptionWorkerPool.spawn(
              count: 1,
              modelPath: modelPath,
              backend: def.backend,
              useGpu: useGpu,
              flashAttn: flashAttn,
              nThreads: 4,
              nGpuLayers: nGpuLayers,
            );
            Log.instance.i('crispasr', 'session worker pool spawned',
                fields: {'backend': def.backend});
          } catch (e, st) {
            Log.instance.w(
                'crispasr',
                'session worker pool spawn failed — UI may freeze '
                    'during long transcribes on this backend',
                error: e,
                stack: st);
            _sessionPool = null;
          }
        }
      }
      _currentModelId = modelId;
      _currentModelPath = modelPath;
      _currentBackend = def.backend;
      onProgress?.call(1.0);
      done();
      return true;
    } catch (e, st) {
      _model = null;
      _session = null;
      _lazyModelPath = null;
      _currentBackend = null;
      // Best-effort tear-down of any pool that managed to spawn
      // before the rest of init failed.
      final orphanedPool = _sessionPool;
      _sessionPool = null;
      if (orphanedPool != null) {
        unawaited(orphanedPool.shutdown());
      }
      _currentModelId = null;
      _currentModelPath = null;
      done(error: e);
      Log.instance.e('crispasr', 'Model load failed',
          error: e,
          stack: st,
          fields: {
            'model': modelId,
            'backend': def.backend,
            'path': modelPath
          });
      throw ModelLoadException(
        'CrispASR failed to load $modelId: $e',
        engineId,
        modelId,
        e,
      );
    }
  }

  @override
  Future<void> unloadModel() async {
    _model?.dispose();
    _model = null;
    _session?.close();
    _session = null;
    final pool = _sessionPool;
    _sessionPool = null;
    if (pool != null) {
      await pool.shutdown();
    }
    _lazyModelPath = null;
    _currentBackend = null;
    _currentModelId = null;
    _currentModelPath = null;
  }

  /// Detect the spoken language of a PCM buffer via CrispASR's
  /// `crispasr_detect_language` helper. Returns null when the loaded dylib
  /// is from the pre-0.2.0 era (or the detection fails internally) — the
  /// caller should treat "null" as "keep whatever language was configured".
  Future<String?> detectLanguage(Float32List audio) async {
    if (!_isWhisper) {
      return null; // Only the whisper class supports LID currently
    }
    final crispasr.CrispASR model;
    try {
      model = _ensureWhisperModel(); // §1 — lazy open if not yet created
    } catch (e) {
      Log.instance.w('crispasr', 'detectLanguage: whisper model not available',
          fields: {'err': e.toString()});
      return null;
    }
    if (!model.supportsExtended) return null;
    final det = model.detectLanguage(audio);
    if (!det.ok) {
      Log.instance.w('crispasr',
          'Language detection unavailable (probability=${det.probability})');
      return null;
    }
    Log.instance.i('crispasr',
        'Detected language: ${det.code} (${(det.probability * 100).toStringAsFixed(1)}%)');
    return det.code;
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
    // Push the LID-method preference into the service so the next
    // detectIfModelAvailable() call honours it. Sticky across calls
    // until the user changes it in Advanced Options.
    final lid = _lidService;
    if (lid != null) {
      lid.method = advanced.lidMethod;
      lid.useGpu = advanced.lidUseGpu;
      lid.flashAttn = advanced.lidFlashAttn;
      lid.nThreads = advanced.nThreads;
      lid.invalidate();
    }
    // Persist the ASR open-time toggles into _config so the next
    // loadModel call (= the next time the user picks a different
    // model) honours them. Flipping these does NOT reload the current
    // session — that's intentional, the session-open path is too
    // heavy to redo on every transcribe().
    _config['asrUseGpu'] = advanced.asrUseGpu;
    _config['asrFlashAttn'] = advanced.asrFlashAttn;
    _config['asrNGpuLayers'] = advanced.asrNGpuLayers;

    // Apply sticky session-state setters before dispatching transcribe.
    // Per-call args win when supplied, otherwise these are the fallback.
    //
    // Source-language: the `language:` per-call arg already covers the
    // common case (`transcribe(pcm, language: 'de')`). The sticky setter
    // is belt-and-braces — some session backends look at
    // `s->source_language` for token-prefill regardless of the per-call
    // arg, so always push the user-pinned source through. Empty string
    // = "no override, use per-call / autodetect", which the C-ABI
    // already treats as "clear the field".
    if (_session != null && language != null && language.isNotEmpty &&
        language != 'auto') {
      try {
        _session!.setSourceLanguage(language);
      } catch (e) {
        // Older libcrispasr without the symbol — silent skip.
        Log.instance.d('crispasr',
            'setSourceLanguage rejected by ${_session?.backend}: $e');
      }
    }
    if (_session != null && targetLanguage != null && targetLanguage.isNotEmpty) {
      try {
        _session!.setTargetLanguage(targetLanguage);
      } catch (e) {
        // Backend doesn't support translation — log and continue with
        // verbatim transcription rather than failing the whole call.
        Log.instance.d('crispasr',
            'setTargetLanguage rejected by ${_session?.backend}: $e');
      }
    }
    // Audio Q&A: when non-empty, voxtral / qwen3-asr answer the
    // prompt instead of producing a verbatim transcript. Always set
    // (including empty string) so a previous ask doesn't stick across
    // a switch back to normal mode.
    if (_session != null) {
      try {
        _session!.setAsk(askPrompt ?? '');
      } catch (e) {
        // Older libwhisper without the setAsk symbol — silent skip;
        // the field has zero effect on those builds anyway.
        Log.instance.d('crispasr',
            'setAsk rejected by ${_session?.backend}: $e');
      }
    }
    // §5.26.2 — Hotwords: set at session level for CTC/TDT backends
    // (parakeet trie) and as a prompt hint for LLM backends. The Dart
    // layer also merges hotwords into the askPrompt string, so LLM
    // backends get them both ways; CTC backends only get them here.
    if (_session != null && advanced.hotwords.isNotEmpty) {
      try {
        _session!.setHotwords(advanced.hotwords,
            boost: advanced.hotwordsBoost);
      } catch (e) {
        // Graceful: older dylibs without the symbol silently skip.
        Log.instance.d('crispasr',
            'setHotwords rejected by ${_session?.backend}: $e');
      }
    }
    // Native punctuation: Canary/Cohere/LLM backends can produce
    // punctuated + capitalized output natively (no extra model
    // needed). Always enable — the setter silently no-ops on
    // backends that don't support it (whisper, wav2vec2, etc.).
    if (_session != null) {
      try {
        _session!.setPunctuation(true);
      } catch (e) {
        Log.instance.d('crispasr',
            'setPunctuation rejected by ${_session?.backend}: $e');
      }
    }
    // Decoder temperature: 0.0 = greedy (the historical default).
    // Set on every dispatch so a previous non-zero value doesn't stick
    // when the user drags the slider back to 0. setTemperature returns
    // rc=-2 for backends without runtime support — the binding maps
    // that to a silent no-op already, so this is safe everywhere.
    if (_session != null) {
      try {
        _session!.setTemperature(temperature);
      } catch (e) {
        Log.instance.d('crispasr',
            'setTemperature rejected by ${_session?.backend}: $e');
      }
    }
    // Best-of-N: works on every session backend per the C ABI
    // (whisper consumes via `wparams.greedy.best_of`, others run N
    // decodes externally and pick the highest-mean-confidence
    // result). Always set so a previous non-1 value doesn't stick
    // when the user drags the slider back to 1.
    if (_session != null) {
      try {
        _session!.setBestOf(bestOf);
      } catch (e) {
        // Older libcrispasr without the symbol — silent skip.
        Log.instance.d('crispasr',
            'setBestOf rejected by ${_session?.backend}: $e');
      }
    }
    // Whisper text-suppression + carry-initial-prompt extras
    // (whisper-only). Pre-0.5.11 dylibs lack the symbol → swallow.
    if (_session != null) {
      try {
        _session!.setWhisperDecodeExtras(
          suppressNonSpeechTokens: advanced.suppressNonSpeechTokens,
          suppressRegex: advanced.suppressTokensRegex,
          carryInitialPrompt: advanced.carryInitialPrompt,
        );
      } on UnsupportedError catch (e) {
        Log.instance.d('crispasr',
            'setWhisperDecodeExtras unsupported on this dylib: $e');
      } catch (e) {
        Log.instance.d('crispasr',
            'setWhisperDecodeExtras rejected by ${_session?.backend}: $e');
      }
    }
    // Whisper decoder-fallback thresholds (whisper-only — other
    // backends silently no-op). Always fire so a slider tweak
    // takes effect on the next transcribe and a previous job's
    // override doesn't stick. Pre-0.5.10 dylibs lack the symbol;
    // we swallow UnsupportedError and continue with stock defaults.
    if (_session != null) {
      try {
        _session!.setFallbackThresholds(
          entropyThold: advanced.entropyThold,
          logprobThold: advanced.logprobThold,
          noSpeechThold: advanced.noSpeechThold,
          temperatureInc: advanced.temperatureInc,
        );
      } on UnsupportedError catch (e) {
        Log.instance.d('crispasr',
            'setFallbackThresholds unsupported on this dylib: $e');
      } catch (e) {
        Log.instance.d('crispasr',
            'setFallbackThresholds rejected by ${_session?.backend}: $e');
      }
    }
    // §5.1.11 — Whisper alt-token capture (whisper-only — other
    // backends silently no-op since none have an analog). Always
    // fire so a slider drag back to 0 actually disables capture
    // on the next dispatch. Pre-0.5.13 dylibs lack the symbol;
    // we swallow UnsupportedError so the rest of the run still
    // works (alts UI just stays hidden).
    if (_session != null) {
      try {
        _session!.setAltN(advanced.altN);
      } on UnsupportedError catch (e) {
        Log.instance.d('crispasr',
            'setAltN unsupported on this dylib: $e');
      } catch (e) {
        Log.instance.d('crispasr',
            'setAltN rejected by ${_session?.backend}: $e');
      }
    }
    // §5.8 — GBNF grammar (whisper-only). Always fire on every
    // dispatch (including empty text) so a previous job's grammar
    // doesn't carry over. Invalid GBNF surfaces as ArgumentError
    // and we re-throw so the user gets a user-actionable message;
    // UnsupportedError (pre-0.5.9 dylib) is silently ignored — the
    // C side wouldn't have honoured grammar anyway.
    if (_session != null) {
      try {
        _session!.setGrammar(advanced.grammarText,
            rootRule: advanced.grammarRootRule,
            penalty: advanced.grammarPenalty);
      } on UnsupportedError catch (e) {
        Log.instance.d('crispasr',
            'setGrammar unsupported on this dylib: $e');
      } on ArgumentError {
        // Re-throw so the caller can surface a snackbar — the
        // user typed an invalid GBNF and we want them to know.
        rethrow;
      } catch (e) {
        Log.instance.d('crispasr',
            'setGrammar rejected by ${_session?.backend}: $e');
      }
    }
    // Guard against runaway generation on LLM-style backends
    // (Qwen3-ASR, Granite, GLM-ASR, Voxtral). A sane cap prevents
    // token loops from burning CPU; the C side silently ignores this
    // on backends without an AR decode step.
    if (_session != null) {
      try {
        _session!.setMaxNewTokens(4096);
      } catch (e) {
        Log.instance.d('crispasr',
            'setMaxNewTokens rejected by ${_session?.backend}: $e');
      }
    }
    if (!_isInitialized) {
      throw const EngineInitializationException(
        'Engine not initialized',
        'crispasr',
      );
    }
    if (_model == null &&
        _session == null &&
        _lazyModelPath == null) {
      throw const ModelLoadException(
        'No model loaded — call loadModel() first',
        'crispasr',
        'none',
      );
    }
    if (audioData.isEmpty) {
      throw const TranscriptionException(
        'Empty audio data',
        'crispasr',
      );
    }

    _isProcessing = true;
    _cancelRequested = false;
    final started = DateTime.now();
    onProgress?.call(0.05);

    final audioSeconds0 = audioData.length / 16000.0;

    // Calculate RMS to see if we have actual signal
    double sumSq = 0.0;
    for (var i = 0; i < audioData.length; i++) {
      sumSq += audioData[i] * audioData[i];
    }
    final rms = sqrt(sumSq / audioData.length);

    Log.instance.i('crispasr', 'transcribe start', fields: {
      'model': _currentModelId,
      'backend': _isWhisper ? 'whisper' : 'session',
      'samples': audioData.length,
      'audio_s': audioSeconds0.toStringAsFixed(2),
      'rms': rms.toStringAsFixed(6),
      'lang': language ?? 'auto',
      'word_ts': enableWordTimestamps,
      'diarize': enableSpeakerDiarization,
      'translate': translate,
      'beam': beamSearch,
      'prompt_chars': initialPrompt?.length ?? 0,
      'vad': vad,
    });

    try {
      List<TranscriptionSegment> segments;

      if (_isWhisper) {
        // Whisper-specific path. For long audio (>60 s), slice into
        // 30 s chunks and dispatch each separately so segments stream
        // into the UI every ~10 s (assuming ~3× realtime decode on M1)
        // instead of arriving in one batch after the full file.
        // Cross-chunk decoder context is lost — fine for whisper, which
        // resets state between calls anyway.
        final audioSeconds = audioData.length / 16000.0;
        if (audioSeconds > 60.0 && !vad) {
          // VAD path stays single-call (it has its own slice/stitch
          // pipeline and benefits from cross-chunk silence detection).
          segments = await _runChunkedWhisper(
            audioData,
            language: language,
            wordTimestamps: enableWordTimestamps,
            translate: translate,
            beamSearch: beamSearch,
            initialPrompt: initialPrompt,
            bestOf: bestOf,
            advanced: advanced,
            startOffsetSec: startOffsetSec,
            onSegment: onSegment,
            onProgress: onProgress,
          );
        } else {
          // Non-chunked whisper path. For §5.23 Q3 resume: trim the
          // leading samples then shift the emitted segments so their
          // timestamps stay absolute. Short-file resume is rare (the
          // chunking path takes over above 60 s) so we do the simple
          // thing — sublist + per-segment shift.
          final trimmed = startOffsetSec <= 0
              ? audioData
              : _trimLeadingSamples(audioData, startOffsetSec);
          // §15 — route through the worker pool when (a) the pool is
          // up and (b) none of the whisper-only TranscribeOptions are
          // set (tdrz / maxLen / splitOnWord don't have CrispasrSession
          // equivalents and would be silently dropped if dispatched
          // through the pool). The pool path runs the FFI call on a
          // worker isolate, so the UI thread stays responsive and
          // Android's ANR detector doesn't kill the app mid-decode.
          // Falls through to the legacy _runTranscription +
          // _mapWhisperSegments path when any whisper-only option is
          // requested or the pool failed to spawn.
          final whisperOnlyOpts = advanced.tdrz ||
              advanced.maxLen > 0 ||
              advanced.splitOnWord;
          if (_sessionPool != null && !whisperOnlyOpts) {
            // C1 — poll CrispASR's atomic progress + streamed segments
            // while the worker isolate runs the FFI call. Timer fires
            // on the main isolate because the pool dispatches off-thread.
            crispasr.resetTranscriptionProgress();
            crispasr.resetStreamedSegments();
            Timer? progressTimer;
            if (onProgress != null || onSegment != null) {
              progressTimer = Timer.periodic(
                const Duration(milliseconds: 250),
                (_) {
                  if (onProgress != null) {
                    final p = crispasr.getTranscriptionProgress();
                    if (p >= 0) onProgress(p / 100.0);
                  }
                  // §12.8i — Poll streamed segments for real-time display.
                  if (onSegment != null) {
                    final streamed = crispasr.drainStreamedSegments();
                    for (final ss in streamed) {
                      onSegment(TranscriptionSegment(
                        text: ss.text,
                        startTime: ss.start,
                        endTime: ss.end,
                      ));
                    }
                  }
                },
              );
            }
            final mapped = await _runSessionTranscriptionViaPool(
              trimmed,
              language: language,
              translate: translate,
              initialPrompt: initialPrompt,
              bestOf: bestOf,
              vad: vad,
              vadModelPath: vadModelPath,
              advanced: advanced,
            );
            progressTimer?.cancel();
            crispasr.resetTranscriptionProgress();
            segments = startOffsetSec <= 0
                ? mapped
                : mapped
                    .map((s) => shiftSegmentForResume(s,
                        offsetSeconds: startOffsetSec))
                    .toList(growable: false);
            if (onSegment != null) {
              for (final s in segments) {
                onSegment(s);
              }
            }
            // Pool path done — skip the legacy direct call below by
            // dropping out of the `if (_sessionPool != null …)` branch
            // straight into the bottom of the outer `if (_model != null)`
            // arm (which then continues to the shared finalize block).
          } else {
            final nativeSegments = await _runTranscription(
              trimmed,
              language: language,
              wordTimestamps: enableWordTimestamps,
              translate: translate,
              beamSearch: beamSearch,
              initialPrompt: initialPrompt,
              vad: vad,
              vadModelPath: vadModelPath,
              bestOf: bestOf,
              advanced: advanced,
            );
            final mapped = _mapWhisperSegments(
                nativeSegments, enableWordTimestamps, null);
            segments = startOffsetSec <= 0
                ? mapped
                : mapped
                    .map((s) => shiftSegmentForResume(s,
                        offsetSeconds: startOffsetSec))
                    .toList(growable: false);
            // Re-fire onSegment with the post-shift timestamps so the
            // streamed-into-the-UI stamps stay monotonic with the
            // pre-loaded checkpoint segments.
            if (onSegment != null) {
              for (final s in segments) {
                onSegment(s);
              }
            }
          }
        }
      } else {
        // Unified session path (Parakeet, Canary, etc.). §5.23 Q3
        // resume: trim leading samples + shift the emitted segments.
        // Note: most session backends (voxtral, qwen3-asr, granite,
        // glm-asr) emit one big segment, so the resume granularity
        // for those is effectively whole-file. Callers should think
        // twice before resuming an LLM-style backend job —
        // BatchQueueNotifier still wires it through here so the
        // *transcript prefix the user already saw* is preserved
        // via the checkpoint-replay path in the UI.
        final trimmed = startOffsetSec <= 0
            ? audioData
            : _trimLeadingSamples(audioData, startOffsetSec);
        final List<TranscriptionSegment> mapped;
        if (_sessionPool != null) {
          // §9 — pool path keeps the synchronous FFI call off the
          // platform isolate; the worker mirrors the same session
          // setters _runSessionTranscription would have fired.
          mapped = await _runSessionTranscriptionViaPool(
            trimmed,
            language: language,
            translate: translate,
            initialPrompt: initialPrompt,
            bestOf: bestOf,
            vad: vad,
            vadModelPath: vadModelPath,
            advanced: advanced,
          );
        } else {
          final sessionSegments = await _runSessionTranscription(
            trimmed,
            language: language,
            vad: vad,
            vadModelPath: vadModelPath,
            advanced: advanced,
          );
          mapped = _mapSessionSegments(sessionSegments, null);
        }
        segments = startOffsetSec <= 0
            ? mapped
            : mapped
                .map((s) => shiftSegmentForResume(s,
                    offsetSeconds: startOffsetSec))
                .toList(growable: false);
        if (onSegment != null) {
          for (final s in segments) {
            onSegment(s);
          }
        }

        // Post-step: if word timestamps were requested and this session
        // backend didn't emit any (qwen3, voxtral, voxtral4b, granite,
        // cohere), run the CTC aligner. `AlignerService` silently no-ops
        // when no aligner GGUF is on disk, so the happy path for
        // parakeet/canary (which already emit word times) is unchanged.
        if (enableWordTimestamps && segments.isNotEmpty) {
          final anyMissing =
              segments.any((s) => s.words == null || s.words!.isEmpty);
          if (anyMissing) {
            segments = await _alignerService!.addWordTimestamps(
              segments,
              audioData,
              language: language,
              alignerModel: advanced.alignerModel,
            );
          }
        }
      }

      onProgress?.call(0.95);
      onProgress?.call(1.0);

      final fullText = segments.map((s) => s.text).join(' ').trim();
      final averageConfidence = segments.isEmpty
          ? null
          : segments.map((s) => s.confidence).reduce((a, b) => a + b) /
              segments.length;

      final elapsed = DateTime.now().difference(started);
      final audioSeconds = audioData.length / 16000.0;
      final wallSeconds =
          elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      final rtf = wallSeconds > 0 ? audioSeconds / wallSeconds : 0.0;
      final wordCount = fullText.isEmpty
          ? 0
          : fullText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final wps = wallSeconds > 0 ? wordCount / wallSeconds : 0.0;

      Log.instance.i('crispasr', 'transcribe done', fields: {
        'model': _currentModelId,
        'audio_s': audioSeconds.toStringAsFixed(2),
        'wall_s': wallSeconds.toStringAsFixed(3),
        'rtf': rtf.toStringAsFixed(2),
        'segments': segments.length,
        'words': wordCount,
        'wps': wps.toStringAsFixed(1),
        'avg_conf': averageConfidence?.toStringAsFixed(3) ?? 'n/a',
        'chars': fullText.length,
      });

      return TranscriptionResult(
        fullText: fullText,
        segments: segments,
        processingTime: elapsed,
        detectedLanguage: language ?? 'auto',
        confidence: averageConfidence,
        metadata: {
          'engine': engineId,
          'model': _currentModelId,
          'modelPath': _currentModelPath,
          'audioSamples': audioData.length,
          'sampleRate': 16000,
          'audioSeconds': audioSeconds,
          'wallSeconds': wallSeconds,
          'rtf': rtf,
          'wordCount': wordCount,
          'wordsPerSecond': wps,
        },
      );
    } catch (e, st) {
      if (e is EngineException) rethrow;
      Log.instance.e('crispasr', 'Transcription failed', error: e, stack: st);
      throw TranscriptionException(
          'CrispASR transcription failed: $e', engineId, e);
    } finally {
      _isProcessing = false;
    }
  }

  /// Chunked Whisper transcription for long audio. Slices into 30 s
  /// windows, dispatches each through `_runTranscription`, adjusts
  /// segment timestamps to absolute time, and fires `onSegment` per
  /// segment so the UI updates incrementally as each chunk completes
  /// instead of waiting for the whole file.
  ///
  /// Cross-chunk decoder context is intentionally not preserved —
  /// whisper resets state between `whisper_full` calls anyway, and
  /// 30 s windows keep the per-chunk encode cost bounded. Initial
  /// prompt is passed to every chunk so domain-vocabulary biasing
  /// still applies throughout.
  /// Apply a positive time offset to a segment's `startTime`,
  /// `endTime`, and per-word timings, then bake the chunk index +
  /// offset into the metadata. Pure data transform — extracted from
  /// the chunked-whisper inner loop so the timestamp arithmetic can
  /// be unit-tested without spinning up a CrispASR session.
  ///
  /// Public so `test/chunked_offset_test.dart` can call it directly;
  /// callers in production code go through `_runChunkedWhisper`.
  static TranscriptionSegment shiftSegmentByOffset(
    TranscriptionSegment raw, {
    required double offsetSeconds,
    required int chunkIndex,
  }) {
    return TranscriptionSegment(
      text: raw.text,
      startTime: raw.startTime + offsetSeconds,
      endTime: raw.endTime + offsetSeconds,
      speaker: raw.speaker,
      confidence: raw.confidence,
      words: raw.words
          ?.map((w) => TranscriptionWord(
                word: w.word,
                startTime: w.startTime + offsetSeconds,
                endTime: w.endTime + offsetSeconds,
                confidence: w.confidence,
              ))
          .toList(),
      metadata: {
        ...raw.metadata,
        'chunkIndex': chunkIndex,
        'chunkOffsetSeconds': offsetSeconds,
      },
    );
  }

  /// Trim the leading `offsetSeconds` worth of 16 kHz mono samples
  /// from `audio`. Returns a sublist view, no copy. If the offset
  /// exceeds the buffer length, returns an empty view (the caller
  /// will see a zero-segment result, which the drain loop treats as
  /// "job already complete" — the checkpoint must have covered the
  /// full file).
  static Float32List _trimLeadingSamples(
      Float32List audio, double offsetSeconds) {
    if (offsetSeconds <= 0) return audio;
    const sampleRate = 16000;
    final start = (offsetSeconds * sampleRate).round();
    if (start >= audio.length) return Float32List(0);
    return Float32List.sublistView(audio, start);
  }

  /// Shift a segment's timestamps by `offsetSeconds` for §5.23 Q3
  /// §5.8 — CrispASR CLI's `--offset-t` + `--duration` window
  /// slice. Returns the [start, start+duration) sample range of
  /// [samples] as a fresh Float32List. Empty / zero window
  /// (start == 0 AND duration == 0) returns the original buffer
  /// unchanged so the no-window case skips a copy.
  ///
  /// Bounds-safe: a start past end-of-buffer returns an empty
  /// view; a duration past end-of-buffer is clamped to end.
  /// Negative inputs are coerced to 0 (the AdvancedOptions UI
  /// already does this but the helper guards regardless).
  ///
  /// Public for `test/transcribe_window_test.dart`.
  static Float32List sliceTranscribeWindow(
    Float32List samples,
    int sampleRate,
    double startSec,
    double durationSec,
  ) {
    final cleanStart = startSec.isFinite && startSec > 0 ? startSec : 0.0;
    final cleanDur =
        durationSec.isFinite && durationSec > 0 ? durationSec : 0.0;
    if (cleanStart == 0.0 && cleanDur == 0.0) return samples;
    final startIdx = (cleanStart * sampleRate).round();
    if (startIdx >= samples.length) {
      return Float32List(0);
    }
    if (cleanDur == 0.0) {
      // Open-ended duration: from startIdx to end-of-buffer.
      return Float32List.sublistView(samples, startIdx);
    }
    final endIdx = (startIdx + cleanDur * sampleRate)
        .round()
        .clamp(startIdx, samples.length);
    return Float32List.sublistView(samples, startIdx, endIdx);
  }

  /// resume-from-checkpoint. Same arithmetic as [shiftSegmentByOffset]
  /// but skips the chunked-whisper metadata stamping — appropriate
  /// when the offset originates from a checkpoint replay (whisper
  /// non-chunked path + session path) rather than a chunk index.
  /// Public for `test/batch_resume_offset_test.dart`.
  static TranscriptionSegment shiftSegmentForResume(
    TranscriptionSegment raw, {
    required double offsetSeconds,
  }) {
    if (offsetSeconds == 0) return raw;
    return TranscriptionSegment(
      text: raw.text,
      startTime: raw.startTime + offsetSeconds,
      endTime: raw.endTime + offsetSeconds,
      speaker: raw.speaker,
      confidence: raw.confidence,
      words: raw.words
          ?.map((w) => TranscriptionWord(
                word: w.word,
                startTime: w.startTime + offsetSeconds,
                endTime: w.endTime + offsetSeconds,
                confidence: w.confidence,
              ))
          .toList(),
      metadata: {
        ...raw.metadata,
        'resumeOffsetSec': offsetSeconds,
      },
    );
  }

  Future<List<TranscriptionSegment>> _runChunkedWhisper(
    Float32List audioData, {
    String? language,
    bool wordTimestamps = false,
    bool translate = false,
    bool beamSearch = false,
    String? initialPrompt,
    int bestOf = 1,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
    double startOffsetSec = 0.0,
    void Function(TranscriptionSegment segment)? onSegment,
    void Function(double progress)? onProgress,
  }) async {
    const sampleRate = 16000;
    const chunkSeconds = 30;
    const chunkSamples = chunkSeconds * sampleRate;
    final totalSamples = audioData.length;
    final nChunks = (totalSamples / chunkSamples).ceil();
    // §5.23 Q3 resume: skip the chunks below the requested offset.
    // Chunk-aligned skip — leaves at most a `chunkSeconds`-sized
    // overlap of work the checkpoint may already cover, which is
    // tolerable (and the caller's pre-loaded segments stay visible
    // until the new ones land alongside). Equivalent shorter-but-
    // misleading: trimming the input PCM would force the chunk
    // timestamps onto a non-30-s grid, breaking the offset assumption
    // used by downstream callers.
    final firstChunk = startOffsetSec <= 0
        ? 0
        : (startOffsetSec * sampleRate / chunkSamples).floor();
    if (firstChunk > 0) {
      Log.instance.i('crispasr', 'resume: skipping first $firstChunk chunk(s)',
          fields: {
            'startOffsetSec': startOffsetSec.toStringAsFixed(3),
            'firstChunk': firstChunk,
            'nChunks': nChunks,
          });
    }

    // §2 — route each chunk through the worker pool (off the platform
    // isolate → no Android ANR on long jobs) when it's safe. Conservative
    // gate: mirrors the non-chunked branch's `!whisperOnlyOpts`, PLUS a
    // `!wordTimestamps` guard. The session/pool path's whisper word-timing
    // output isn't verified to match `transcribePcm`'s here, so word/SRT
    // jobs keep the proven direct path (no regression). When the pool is
    // down or either guard trips, we fall back to the per-chunk direct
    // call, which lazily opens `_model` via `_ensureWhisperModel()`.
    final whisperOnlyOpts =
        advanced.tdrz || advanced.maxLen > 0 || advanced.splitOnWord;
    final usePool =
        _sessionPool != null && !whisperOnlyOpts && !wordTimestamps;

    final allSegments = <TranscriptionSegment>[];
    for (var i = firstChunk; i < nChunks; i++) {
      if (_cancelRequested) break;
      final start = i * chunkSamples;
      final end =
          (start + chunkSamples) > totalSamples ? totalSamples : start + chunkSamples;
      final chunk = Float32List.sublistView(audioData, start, end);
      final offsetSeconds = start / sampleRate;

      Log.instance.d('crispasr', 'chunk dispatch', fields: {
        'i': i,
        'of': nChunks,
        't0': offsetSeconds.toStringAsFixed(1),
        'samples': chunk.length,
      });

      final List<TranscriptionSegment> chunkSegments;
      if (usePool) {
        // Pool path: worker-isolate FFI call, returns TranscriptionSegments
        // directly. Word timestamps are gated off above, so this matches
        // the non-chunked whisper pool branch's output shape.
        chunkSegments = await _runSessionTranscriptionViaPool(
          chunk,
          language: language,
          translate: translate,
          initialPrompt: initialPrompt,
          bestOf: bestOf,
          vad: false,
          vadModelPath: null,
          advanced: advanced,
        );
      } else {
        final nativeSegments = await _runTranscription(
          chunk,
          language: language,
          wordTimestamps: wordTimestamps,
          translate: translate,
          beamSearch: beamSearch,
          initialPrompt: initialPrompt,
          vad: false,
          vadModelPath: null,
          bestOf: bestOf,
          advanced: advanced,
        );
        // Re-map with the chunk's time offset baked into each segment +
        // word so absolute timestamps remain monotonic across chunks.
        // Reuses the same builder as the single-call path; we apply the
        // offset here rather than changing _mapWhisperSegments to keep
        // the canonical mapper offset-agnostic.
        chunkSegments = _mapWhisperSegments(
          nativeSegments,
          wordTimestamps,
          null, // we'll fire onSegment manually below with adjusted times
        );
      }
      for (final raw in chunkSegments) {
        final shifted = shiftSegmentByOffset(raw,
            offsetSeconds: offsetSeconds, chunkIndex: i);
        allSegments.add(shifted);
        onSegment?.call(shifted);
      }
      // Per-chunk progress: fraction of REMAINING audio dispatched
      // (post-resume the progress bar should walk 0→1 across the
      // unfinished tail, not jump to firstChunk/nChunks on tick 1).
      final remaining = nChunks - firstChunk;
      onProgress?.call(remaining <= 0 ? 1.0 : (i - firstChunk + 1) / remaining);
    }
    return allSegments;
  }

  Future<List<crispasr.Segment>> _runTranscription(
    Float32List pcm, {
    String? language,
    bool wordTimestamps = false,
    bool translate = false,
    bool beamSearch = false,
    String? initialPrompt,
    bool vad = false,
    String? vadModelPath,
    int bestOf = 1,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
  }) async {
    // Keep FFI call off the UI thread where possible. `Isolate.run` requires
    // sending the model handle across isolates which FFI can't do, so we
    // instead yield briefly to pump the event loop before the blocking call.
    await Future<void>.delayed(Duration.zero);
    // NOTE: whisper.cpp's `params.detect_language = true` is a detect-ONLY
    // mode — it returns as soon as the language is identified and never
    // runs transcription. For auto-detect we just leave `language = null`;
    // whisper then transcribes in auto-language mode, picking up the
    // detected language internally on the first window.
    final prompt = (initialPrompt == null || initialPrompt.trim().isEmpty)
        ? null
        : initialPrompt.trim();
    final useVad = vad && vadModelPath != null && vadModelPath.isNotEmpty;
    return _ensureWhisperModel().transcribePcm(
      pcm,
      options: crispasr.TranscribeOptions(
        language: (language == null || language == 'auto') ? null : language,
        detectLanguage: false,
        wordTimestamps: wordTimestamps,
        silent: false,
        translate: translate,
        strategy: beamSearch ? 1 : 0, // 0 = greedy, 1 = beam search
        initialPrompt: prompt,
        bestOf: bestOf,
        vad: useVad,
        vadModelPath: useVad ? vadModelPath : null,
        // CrispASR 0.6 VAD tunables — defaults match Silero ships.
        vadThreshold: advanced.vadThreshold,
        vadMinSpeechMs: advanced.vadMinSpeechMs,
        vadMinSilenceMs: advanced.vadMinSilenceMs,
        // Whisper tinydiarize speaker-turn markers (requires .tdrz finetune).
        tdrz: advanced.tdrz,
        // §5.8 — subtitle-friendly segment length cap. 0 keeps
        // whisper's default; >0 produces SRT-shaped short lines.
        maxLen: advanced.maxLen,
        splitOnWord: advanced.splitOnWord,
      ),
    );
  }

  Future<List<crispasr.SessionSegment>> _runSessionTranscription(
    Float32List pcm, {
    String? language,
    bool vad = false,
    String? vadModelPath,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
  }) async {
    // Yield once so the FFI call doesn't block the current microtask batch
    // in the UI thread (same pattern as `_runTranscription`).
    await Future<void>.delayed(Duration.zero);

    // Language resolution:
    //  * user picked a concrete ISO code ("en", "de", ...) → pass through
    //  * user picked "auto" (or left blank) and we have a multilingual
    //    whisper model on disk → run LID, use its result
    //  * otherwise → null, backends fall back to their historical
    //    defaults ("en" for canary/cohere/voxtral/voxtral4b, auto for
    //    parakeet/qwen3, no hint for granite/wav2vec2/ctc)
    String? langHint;
    if (language != null && language.isNotEmpty && language != 'auto') {
      langHint = language;
    } else if (_lidService != null) {
      langHint = await _lidService!.detectIfModelAvailable(pcm);
      if (langHint != null) {
        Log.instance.i('crispasr', 'session path: LID', fields: {
          'detected': langHint,
          'backend': _session?.backend,
        });
      }
    }

    // Non-whisper backends (parakeet, cohere, canary, voxtral, qwen3,
    // granite, wav2vec2, ...) all go through CrispasrSession. When the
    // user has VAD enabled and a Silero model path is available, route
    // through `transcribeVad` — it performs the same Silero-VAD slicing
    // + whisper.cpp-style stitching CrispASR's CLI uses internally. For
    // O(T²) encoders (parakeet/cohere/canary) that's a large win because
    // silence between utterances no longer multiplies encoder cost, and
    // one stitched call preserves cross-segment decoder context.
    final useVad = vad && vadModelPath != null && vadModelPath.isNotEmpty;
    if (useVad) {
      Log.instance.d('crispasr', 'session path: transcribeVad', fields: {
        'backend': _session?.backend,
        'vad_model': vadModelPath,
        'samples': pcm.length,
        'lang': langHint ?? 'default',
        'vad_threshold': advanced.vadThreshold,
      });
      return _session!.transcribeVad(
        pcm,
        vadModelPath,
        language: langHint,
        options: crispasr.SessionVadOptions(
          threshold: advanced.vadThreshold,
          minSpeechDurationMs: advanced.vadMinSpeechMs,
          minSilenceDurationMs: advanced.vadMinSilenceMs,
          speechPadMs: advanced.vadSpeechPadMs,
        ),
      );
    }
    return _session!.transcribeChunked(pcm, language: langHint);
  }

  /// §9 — session-backend transcription dispatched through the
  /// 1-worker pool. Mirrors [_runSessionTranscription]'s logic
  /// (LID, VAD branch, advanced VAD knobs) but the FFI call runs
  /// in the worker isolate so the UI thread stays responsive and
  /// Android's ANR detector doesn't kill the process.
  ///
  /// Returns segments enriched with engine/model/backend metadata
  /// — the pool's wire format drops those so we re-attach them
  /// here to keep parity with [_mapSessionSegments].
  Future<List<TranscriptionSegment>> _runSessionTranscriptionViaPool(
    Float32List pcm, {
    String? language,
    bool translate = false,
    String? initialPrompt,
    int bestOf = 1,
    bool vad = false,
    String? vadModelPath,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
  }) async {
    String? langHint;
    if (language != null && language.isNotEmpty && language != 'auto') {
      langHint = language;
    } else if (_lidService != null) {
      langHint = await _lidService!.detectIfModelAvailable(pcm);
      if (langHint != null) {
        Log.instance.i('crispasr', 'pool path: LID', fields: {
          'detected': langHint,
          'backend': _session?.backend,
        });
      }
    }

    final useVad = vad && vadModelPath != null && vadModelPath.isNotEmpty;
    final prompt = (initialPrompt == null || initialPrompt.trim().isEmpty)
        ? null
        : initialPrompt.trim();

    final raw = await _sessionPool!.dispatch(
      samples: pcm,
      language: langHint,
      translate: translate,
      askPrompt: prompt,
      bestOf: bestOf,
      beamSize: advanced.beamSize > 0 ? advanced.beamSize : 1,
      vadModelPath: useVad ? vadModelPath : null,
      vadThreshold: useVad ? advanced.vadThreshold : null,
      vadMinSpeechMs: useVad ? advanced.vadMinSpeechMs : null,
      vadMinSilenceMs: useVad ? advanced.vadMinSilenceMs : null,
      vadSpeechPadMs: useVad ? advanced.vadSpeechPadMs : null,
    );

    final backend = _session?.backend;
    return [
      for (var i = 0; i < raw.length; i++)
        TranscriptionSegment(
          text: raw[i].text,
          startTime: raw[i].startTime,
          endTime: raw[i].endTime,
          confidence: raw[i].confidence,
          speaker: raw[i].speaker,
          words: raw[i].words,
          metadata: {
            'engine': engineId,
            'model': _currentModelId,
            'segmentIndex': i,
            'backend': backend,
          },
        ),
    ];
  }

  List<TranscriptionSegment> _mapWhisperSegments(
    List<crispasr.Segment> nativeSegments,
    bool enableWordTimestamps,
    void Function(TranscriptionSegment segment)? onSegment,
  ) {
    Log.instance
        .d('crispasr', 'Mapping ${nativeSegments.length} native segments');
    final segments = <TranscriptionSegment>[];
    for (var i = 0; i < nativeSegments.length; i++) {
      if (_cancelRequested) break;
      final s = nativeSegments[i];
      Log.instance.d('crispasr',
          'Native segment $i text: "[${s.text}]" words: ${s.words.length}');
      if (s.text.trim().isEmpty) {
        Log.instance.d('crispasr', 'Segment $i is empty, skipping');
        continue;
      }
      final confidence = (1.0 - s.noSpeechProb).clamp(0.0, 1.0).toDouble();

      // Map CrispASR's per-token `Word` onto the app's `TranscriptionWord`
      // shape. Only populated when `enableWordTimestamps` was requested
      // and the loaded dylib is >= 0.2.0 (empty list otherwise).
      List<TranscriptionWord>? words;
      if (enableWordTimestamps && s.words.isNotEmpty) {
        words = s.words
            .map((w) => TranscriptionWord(
                  word: w.text,
                  startTime: w.start,
                  endTime: w.end,
                  confidence: w.p.clamp(0.0, 1.0).toDouble(),
                  // §5.1.11 — alt-token candidates (Whisper greedy
                  // decode only, 0.5.13+). Empty in the common
                  // off-by-default case so the editor renders the
                  // word as plain text without the tap affordance.
                  alts: w.alts
                      .map((a) => TranscriptionWordAlt(
                            text: a.text,
                            p: a.p.clamp(0.0, 1.0).toDouble(),
                          ))
                      .toList(growable: false),
                ))
            .toList();
      }

      final seg = TranscriptionSegment(
        text: s.text.trim(),
        startTime: s.start,
        endTime: s.end,
        confidence: confidence,
        words: words,
        metadata: {
          'engine': engineId,
          'model': _currentModelId,
          'segmentIndex': i,
          'noSpeechProb': s.noSpeechProb,
        },
      );
      segments.add(seg);
      onSegment?.call(seg);
    }
    return segments;
  }

  // §10 SenseVoice tag classification helpers.
  static bool _isEmotionTag(String t) =>
      const {'HAPPY', 'SAD', 'ANGRY', 'NEUTRAL', 'EMO_UNKNOWN', 'SURPRISED', 'FEARFUL', 'DISGUSTED'}
          .contains(t.toUpperCase());
  static bool _isEventTag(String t) =>
      const {'SPEECH', 'BGM', 'LAUGHTER', 'APPLAUSE', 'NOISE', 'MUSIC', 'SINGING'}
          .contains(t.toUpperCase());

  List<TranscriptionSegment> _mapSessionSegments(
    List<crispasr.SessionSegment> sessionSegments,
    void Function(TranscriptionSegment segment)? onSegment,
  ) {
    final segments = <TranscriptionSegment>[];
    for (var i = 0; i < sessionSegments.length; i++) {
      if (_cancelRequested) break;
      final s = sessionSegments[i];

      List<TranscriptionWord>? words;
      if (s.words.isNotEmpty) {
        words = s.words
            .map((w) => TranscriptionWord(
                  word: w.text,
                  startTime: w.start,
                  endTime: w.end,
                  // crispasr 0.5.5+ exposes per-word probability via
                  // crispasr_session_result_word_p; older builds (and
                  // backends that don't compute one) report -1, which
                  // the binding clamps to 1.0 so we render neutrally.
                  confidence: w.p.clamp(0.0, 1.0),
                  // §5.1.11 — alt-token candidates (Whisper greedy
                  // decode only, 0.5.13+). Carried through from the
                  // session-result word.alts list. Empty for other
                  // backends and old dylibs.
                  alts: w.alts
                      .map((a) => TranscriptionWordAlt(
                            text: a.text,
                            p: a.p.clamp(0.0, 1.0).toDouble(),
                          ))
                      .toList(growable: false),
                ))
            .toList();
      }

      // Segment-level confidence is the mean of its words' p when we
      // have them, otherwise 1.0. Lets the segment header badge agree
      // with the per-word colours instead of always showing "100%".
      final segConfidence = (words == null || words.isEmpty)
          ? 1.0
          : words.map((w) => w.confidence).reduce((a, b) => a + b) /
              words.length;

      // §10 — SenseVoice emits inline tags: <|HAPPY|>, <|Speech|>,
      // <|BGM|>, <|Laughter|>, etc. Strip them from display text and
      // surface in metadata so the UI can show emotion/event badges.
      var segText = s.text.trim();
      final svTags = <String>[];
      final tagPattern = RegExp(r'<\|([A-Za-z_]+)\|>');
      for (final m in tagPattern.allMatches(segText)) {
        svTags.add(m.group(1)!);
      }
      if (svTags.isNotEmpty) {
        segText = segText.replaceAll(tagPattern, '').trim();
      }

      final seg = TranscriptionSegment(
        text: segText,
        startTime: s.start,
        endTime: s.end,
        confidence: segConfidence,
        words: words,
        metadata: {
          'engine': engineId,
          'model': _currentModelId,
          'segmentIndex': i,
          'backend': _session?.backend,
          if (svTags.isNotEmpty) 'sensevoice_tags': svTags,
          if (svTags.any(_isEmotionTag)) 'emotion': svTags.firstWhere(_isEmotionTag),
          if (svTags.any(_isEventTag)) 'audio_event': svTags.firstWhere(_isEventTag),
        },
      );
      segments.add(seg);
      onSegment?.call(seg);
    }
    return segments;
  }

  @override
  Stream<TranscriptionSegment>? transcribeStream(
    Stream<Float32List> audioStream, {
    String? language,
    bool enableWordTimestamps = false,
    /// When false, the streaming session defers decoding until the
    /// window is full — saves battery on mobile at the cost of
    /// higher latency on partial results. Default true (immediate
    /// decode on every chunk).
    bool liveDecode = true,
  }) {
    // Two routes: (a) Whisper class with its native streaming API,
    // or (b) the unified `CrispasrSession.openStream()` added in
    // CrispASR 0.6 which dispatches to whichever backend the session
    // loaded (kyutai-stt / moonshine-streaming / voxtral4b — and
    // whisper too via its session arm). Falls back to null when
    // neither has anything streamable.
    final crispasr.StreamingSession session;
    final String streamRouteLabel;
    if (_isWhisper) {
      // §1 — lazily open the main-isolate whisper handle for streaming.
      final crispasr.CrispASR model;
      try {
        model = _ensureWhisperModel();
      } catch (e, st) {
        Log.instance.w('crispasr', 'whisper model open for streaming failed',
            error: e, stack: st);
        return null;
      }
      if (!model.supportsStreaming) return null;
      session = model.openStream(
        language: (language == null || language == 'auto') ? null : language,
        stepMs: 3000,
        lengthMs: 10000,
        keepMs: 200,
        nThreads: 4,
      );
      streamRouteLabel = 'whisper';
    } else if (_session != null) {
      try {
        session = _session!.openStream(
          language: (language == null || language == 'auto') ? null : language,
          stepMs: 3000,
          lengthMs: 10000,
          keepMs: 200,
          nThreads: 4,
        );
      } catch (e, st) {
        Log.instance.w('crispasr', 'session.openStream failed',
            error: e, stack: st, fields: {'backend': _session?.backend});
        return null;
      }
      streamRouteLabel = _session!.backend;
    } else {
      return null;
    }
    // Apply live-decode toggle before the first feed(). When disabled,
    // the session accumulates audio silently and only decodes when the
    // window is full — lower CPU/battery usage on mobile.
    if (!liveDecode) {
      try {
        session.setLiveDecode(false);
      } catch (_) {/* pre-0.6 dylib or unsupported backend */}
    }
    Log.instance.i('crispasr', 'Streaming session opened',
        fields: {'route': streamRouteLabel, 'liveDecode': liveDecode});

    final controller = StreamController<TranscriptionSegment>(
      onCancel: () {
        if (!session.isClosed) {
          final last = session.flush();
          if (last != null) {
            Log.instance
                .d('crispasr', 'Stream flush: ${last.text.length} chars');
          }
          session.close();
        }
        Log.instance.i('crispasr', 'Streaming session closed');
      },
    );

    // Subscribe to the incoming PCM, run feed() on the caller's audio
    // thread, and forward each commit as a TranscriptionSegment. We
    // synthesize a synthetic index so downstream UI can tell consecutive
    // commits apart even though the text grows monotonically.
    audioStream.listen(
      (chunk) {
        if (controller.isClosed || session.isClosed) return;
        try {
          final update = session.feed(chunk);
          if (update != null && update.text.isNotEmpty) {
            controller.add(TranscriptionSegment(
              text: update.text.trim(),
              startTime: update.start,
              endTime: update.end,
              confidence: 1.0,
              metadata: {
                'engine': engineId,
                'streaming': true,
                'decodeCounter': update.counter,
              },
            ));
          }
        } catch (e, st) {
          Log.instance.w('crispasr', 'stream.feed failed', error: e, stack: st);
          controller.addError(e, st);
        }
      },
      onDone: () {
        // Drain any final partial before closing.
        try {
          final last = session.flush();
          if (last != null && last.text.isNotEmpty) {
            controller.add(TranscriptionSegment(
              text: last.text.trim(),
              startTime: last.start,
              endTime: last.end,
              confidence: 1.0,
              metadata: {
                'engine': engineId,
                'streaming': true,
                'final': true,
                'decodeCounter': last.counter,
              },
            ));
          }
        } catch (e) {
          Log.instance.d('crispasr', 'stream flush at end failed',
              fields: {'err': e.toString()});
        }
        session.close();
        controller.close();
      },
      onError: controller.addError,
      cancelOnError: false,
    );

    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
  }

  @override
  Future<void> updateConfig(Map<String, dynamic> config) async {
    _config.addAll(config);
  }
}
