import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import '../main.dart' show modelServiceProvider;
import '../models/pronunciation_lexicon.dart';
import 'audio_watermark_service.dart';
import 'content_provenance_service.dart';
import 'log_service.dart';
import 'spread_spectrum_watermark.dart';
import 'model_service.dart';

/// Synthesised audio plus the sample rate the backend declares (kokoro:
/// 24 kHz, vibevoice: 24 kHz, qwen3-tts: 24 kHz, orpheus: 24 kHz).
class SynthesizedAudio {
  final Float32List samples;
  final int sampleRate;
  const SynthesizedAudio({required this.samples, required this.sampleRate});

  double get durationSeconds => samples.length / sampleRate;
}

/// Outcome of the EU AI Act Art. 50(2) marking pass for one synthesis.
///
/// Two marks are applied. The **watermark** is robust — it survives
/// re-encoding and trimming. The **container marking** (C2PA manifest,
/// WAV LIST/INFO, ID3v2) is machine-readable but strips on any
/// re-encode. A COSE-signed C2PA manifest is cryptographically
/// verifiable; the unsigned JSON-LD fallback is not.
///
/// [robustMarkPresent] is the one that matters: false means the output
/// is marked only by metadata a re-encode would remove.
class MarkingStatus {
  final bool watermarkVerified;
  final double watermarkConfidence;
  final bool c2paSigned;

  const MarkingStatus({
    required this.watermarkVerified,
    required this.watermarkConfidence,
    required this.c2paSigned,
  });

  bool get robustMarkPresent => watermarkVerified || c2paSigned;
}

/// Wraps `CrispasrSession` for the TTS backends (kokoro, vibevoice-tts,
/// qwen3-tts, orpheus). One session per (model, voice/codec) tuple is
/// cached and reused across synth calls — opening these models is the
/// slow part (mmap + first prefill); per-utterance synth is much cheaper.
///
/// Caller responsibilities:
/// * supply `modelDef` for a downloaded TTS GGUF (kind == ModelKind.tts);
/// * supply `voiceDef` for the matching voicepack (kokoro / vibevoice);
/// * supply `codecDef` for the matching codec/tokenizer (qwen3-tts /
///   orpheus). For kokoro / vibevoice the codec is None.
class TtsService {
  final ModelService modelService;
  TtsService(this.modelService);

  /// Marking outcome of the most recent [writeWav]. Null before the
  /// first synthesis. The synthesise screen reads this so the provenance
  /// card reports what was actually embedded rather than what was
  /// intended.
  MarkingStatus? lastMarking;

  /// Confidence floor for treating a spread-spectrum watermark as
  /// present.
  ///
  /// Measured against this detector (see the assertions in
  /// `test/synthetic_compliance_test.dart`): clean audio peaks at ~0.50,
  /// freshly watermarked audio sits at 0.78–0.91 from ~100 ms upward,
  /// and detection is level-invariant (0.78 at 0.01x amplitude). 0.65
  /// sits in that gap, so it neither passes unmarked audio nor rejects
  /// quiet-but-real output. A borderline read triggers the Dart
  /// fallback — double-marking is harmless, shipping unmarked is not.
  static const double _watermarkConfidenceFloor = 0.65;

  /// §5.25.9 — Pronunciation lexicon applied to text before synthesis.
  PronunciationLexicon? _lexicon;
  set lexicon(PronunciationLexicon? v) => _lexicon = v;

  // Cached session keyed by `<modelPath>|<voicePath>|<codecPath>` so
  // changing voice mid-session reopens.
  String? _key;
  crispasr.CrispasrSession? _session;
  String? _backend;

  // Resolved config from last prepare(), replayed in the background
  // isolate for synthesis (#23 — prevents ANR on large models).
  String? _modelPath;
  String? _voicePath;
  String? _codecPath;
  String? _prepSpeakerName;
  int? _prepSpeakerId;
  String? _prepInstructPrompt;
  String? _prepRefText;

  String _makeKey(String? m, String? v, String? c) =>
      '${m ?? ""}|${v ?? ""}|${c ?? ""}';

  // Cached snapshot of the backends the bundled libcrispasr can dispatch
  // through the unified session API. The list is fixed for the life of
  // the process (it's baked into the linked dylib), so probe once. Empty
  // when the dylib is missing or predates the
  // `crispasr_session_available_backends` symbol — callers treat empty
  // as "unknown, don't gate" so they degrade rather than block.
  static List<String>? _availBackendsCache;
  static List<String> _availableBackends() {
    return _availBackendsCache ??= () {
      try {
        return crispasr.CrispasrSession.availableBackends();
      } catch (_) {
        return const <String>[];
      }
    }();
  }

  Future<String?> _resolvePath(String modelName) async {
    final p = await modelService.getWhisperCppModelPath(modelName);
    if (p == null) return null;
    return await File(p).exists() ? p : null;
  }

  /// Prepare a session for the given combination, opening the model if
  /// needed. Returns the resolved on-disk paths so the UI can surface
  /// "needs download" hints when something is missing.
  ///
  /// [refText] is the transcript of `voiceName` for runtime voice
  /// cloning on backends that support it (qwen3-tts Base, vibevoice-1.5b).
  /// Ignored when null or when the backend does its own clone (orpheus,
  /// kokoro, chatterbox baked voices).
  ///
  /// [voiceWavPath] is an explicit on-disk path to a WAV file the user
  /// supplied via the Custom Voice picker — takes precedence over a
  /// catalog [voiceName] lookup. Used for one-off voice clones without
  /// having to bake a GGUF first.
  ///
  /// [speakerName] selects a baked preset speaker (orpheus, qwen3-tts
  /// CustomVoice). Ignored on backends without preset speakers.
  ///
  /// [instructPrompt] is the natural-language voice description for
  /// qwen3-tts VoiceDesign. Ignored on every other backend.
  Future<TtsLoadStatus> prepare({
    required String modelName,
    String? voiceName,
    String? codecName,
    String? refText,
    String? voiceWavPath,
    String? speakerName,
    int? speakerId,
    String? instructPrompt,
  }) async {
    final modelPath = await _resolvePath(modelName);
    if (modelPath == null) {
      return TtsLoadStatus.missing(modelName: modelName);
    }
    String? voicePath;
    if (voiceWavPath != null && voiceWavPath.isNotEmpty) {
      voicePath = voiceWavPath;
    } else if (voiceName != null) {
      voicePath = await _resolvePath(voiceName);
      if (voicePath == null) {
        return TtsLoadStatus.missing(voiceName: voiceName);
      }
    }
    final codecPath = codecName == null ? null : await _resolvePath(codecName);
    if (codecName != null && codecPath == null) {
      return TtsLoadStatus.missing(codecName: codecName);
    }

    final key = _makeKey(
        '$modelPath#${speakerName ?? ''}#${speakerId ?? ''}#${instructPrompt ?? ''}',
        voicePath, codecPath);
    if (_session != null && _key == key) {
      return TtsLoadStatus.ready(_backend!);
    }

    // Reopen.
    _session?.close();
    _session = null;
    _key = null;
    _backend = null;

    try {
      // Pass the backend explicitly so the C-side doesn't have to
      // auto-detect from GGUF metadata. The auto-detect path returned
      // null on kokoro / vibevoice-tts loads even though the dylib
      // reported the backend as available — `crispasr_session_open
      // returned null` surfaced as "fehlende Begleitdatei" up the
      // stack because the catch block degrades the error to "missing
      // companion".
      //
      // We pull the backend from the catalog. If we can't resolve
      // (probe entries from before the BackendRepo.kind fix may not
      // have it), fall through to the bare open and let auto-detect
      // try.
      final def = modelService.lookupDefinition(modelName);
      final backend = def?.backend;
      // #16 — guard against backends the bundled libcrispasr can't
      // dispatch through the unified session API. Piper TTS, for one,
      // ships as a separate standalone C-ABI upstream; the unified-
      // session dispatch arm + availableBackends() entry are wired
      // upstream but NOT on the bundled dylib yet (see PLAN §5.24-A).
      // Calling CrispasrSession.open(..., backend: 'piper') on such a
      // dylib crashes the process *natively* (segfault) rather than
      // throwing a catchable Dart error — so the app dies the instant
      // the user taps Synthesize (issue #16, Android + Windows). Refuse
      // here, before the native open, so the user gets a clear message
      // instead of a hard crash. Gated on availableBackends() so the
      // moment a rebuilt dylib lists the backend it starts working with
      // no further code change.
      if (backend != null && backend.isNotEmpty) {
        final available = _availableBackends();
        if (available.isNotEmpty && !available.contains(backend)) {
          Log.instance.w('tts', 'backend not dispatchable in this build',
              fields: {'backend': backend, 'available': available.length});
          return TtsLoadStatus.unsupported(backend);
        }
      }
      // Per-backend GPU pinning happens via env vars set in
      // main.dart (see `applyKokoroMetalWorkaround()`), not by
      // gating session-open here. Open kokoro normally with
      // GPU on — the bad stages auto-fall-back to CPU.
      final s = (backend == null || backend.isEmpty)
          ? crispasr.CrispasrSession.open(modelPath)
          : crispasr.CrispasrSession.open(modelPath, backend: backend);
      if (codecPath != null) s.setCodecPath(codecPath);
      // qwen3-tts VoiceDesign branch — takes priority because it
      // can't combine with setVoice / setSpeakerName.
      if (instructPrompt != null && instructPrompt.isNotEmpty) {
        try {
          s.setInstruct(instructPrompt);
        } catch (e) {
          Log.instance
              .d('tts', 'setInstruct rejected', fields: {'err': e.toString()});
        }
      } else if (speakerName != null && speakerName.isNotEmpty) {
        try {
          s.setSpeakerName(speakerName);
        } catch (e) {
          Log.instance.d('tts', 'setSpeakerName rejected',
              fields: {'name': speakerName, 'err': e.toString()});
        }
      } else if (speakerId != null) {
        try {
          s.setSpeakerID(speakerId);
        } catch (e) {
          Log.instance.d('tts', 'setSpeakerID rejected',
              fields: {'id': speakerId, 'err': e.toString()});
        }
      } else if (voicePath != null) {
        // refText pairs with WAV-cloning voices on qwen3-tts /
        // vibevoice-1.5b; baked GGUFs ignore it. The Dart binding
        // accepts a nullable refText, so passing null is safe.
        s.setVoice(voicePath, refText: refText);
      }
      _session = s;
      _key = key;
      _backend = s.backend;
      // Store resolved config for background-isolate replay (#23).
      _modelPath = modelPath;
      _voicePath = voicePath;
      _codecPath = codecPath;
      _prepSpeakerName = speakerName;
      _prepSpeakerId = speakerId;
      _prepInstructPrompt = instructPrompt;
      _prepRefText = refText;
      Log.instance.i('tts', 'session opened', fields: {
        'model': p.basename(modelPath),
        'voice': voicePath == null ? '' : p.basename(voicePath),
        'codec': codecPath == null ? '' : p.basename(codecPath),
        'speaker': speakerName ?? '',
        'instruct_len': instructPrompt?.length ?? 0,
        'ref_text_len': refText?.length ?? 0,
        'backend': _backend,
      });
      return TtsLoadStatus.ready(_backend!);
    } catch (e, st) {
      Log.instance.e('tts', 'session open failed', error: e, stack: st);
      return TtsLoadStatus.error(e.toString());
    }
  }

  /// The underlying session, for callers that need direct access
  /// (e.g. querying nSpeakers). Null when no model is loaded.
  crispasr.CrispasrSession? get session => _session;

  /// Whether the active session is a qwen3-tts CustomVoice variant.
  /// Surfaces the CrispASR FFI capability to the UI so the Synthesize
  /// screen knows whether to show the speaker-name picker.
  bool get isCustomVoice => _session?.isCustomVoice() ?? false;

  /// Whether the active session is a qwen3-tts VoiceDesign variant.
  bool get isVoiceDesign => _session?.isVoiceDesign() ?? false;

  /// Preset speaker names for the active backend (orpheus baked
  /// English speakers, qwen3-tts customvoice speakers, etc.). Empty
  /// list when the backend has no preset-speaker contract.
  List<String> get presetSpeakers => _session?.speakers() ?? const [];

  /// Synthesise [text] using the currently-prepared session.
  ///
  /// Post-processing knobs:
  /// * [trimSilence] strips leading + trailing silence (samples below
  ///   `1/4096` magnitude). Cheap and lossy; useful when the backend
  ///   leaves ~100 ms of dead air at the edges (kokoro, qwen3-tts).
  /// * [speed] is a multiplicative playback rate (1.0 = unchanged,
  ///   0.5 = half-speed, 2.0 = double-speed). Implemented as a nearest-
  ///   neighbour resample on the PCM buffer; no pitch correction. Clamped
  ///   to [0.25, 4.0] to mirror the OpenAI `speed` parameter range.
  Future<SynthesizedAudio?> synthesize(
    String text, {
    bool trimSilence = false,
    double speed = 1.0,
    /// CFM diffusion-step count for chatterbox (default 10). Higher
    /// is slower but smoother. Other backends silently ignore.
    int? ttsSteps,
    /// Sampling temperature shared across orpheus / chatterbox /
    /// canary-temperature-capable backends. Null = leave the C-side
    /// default (chatterbox 0.8, orpheus 0.6).
    double? temperature,
    /// Top-p nucleus threshold (chatterbox). Null = backend default.
    double? topP,
    /// Min-p threshold (chatterbox). Null = backend default.
    double? minP,
    /// CFG weight (chatterbox). Null = backend default 0.5.
    double? cfgWeight,
    /// Emotion-exaggeration scalar (chatterbox). Null = backend default.
    double? exaggeration,
    /// Repetition penalty (chatterbox). Null = backend default 1.0.
    double? repetitionPenalty,
    /// Upper bound on AR speech tokens (chatterbox). Null = default.
    int? maxSpeechTokens,
    /// TTS random seed for reproducible output (chatterbox, vibevoice,
    /// qwen3-tts, orpheus). Null = non-deterministic.
    int? seed,
    /// Frequency penalty for AR token repetition (autoregressive
    /// backends). Null = backend default.
    double? frequencyPenalty,
    /// Top-k sampling (qwen3-tts, chatterbox, orpheus, dots-tts,
    /// tada). Null = backend default.
    int? topK,
    /// Stochastic sampling toggle (TTS backends). Null = backend default.
    bool? doSample,
    /// Number of acoustic candidates for ranking (tada, chatterbox,
    /// kokoro). Null = backend default.
    int? ttsNumCandidates,
    /// Grapheme-to-phoneme dictionary source path (kokoro, vibevoice,
    /// speecht5). Null = no dictionary.
    String? g2pDict,
    /// Noise temperature for stochastic generation (kokoro, vibevoice).
    /// Null = backend default.
    double? noiseTemp,
  }) async {
    if (_session == null || text.trim().isEmpty) return null;
    final modelPath = _modelPath;
    if (modelPath == null) return null;
    try {
      // §5.25.9 — Apply pronunciation lexicon substitutions (Dart-side).
      final synthText = _lexicon?.apply(text) ?? text;
      final clampedSpeed = speed.clamp(0.25, 4.0).toDouble();

      // Capture config for the background isolate closure.
      final backend = _backend;
      final codecPath = _codecPath;
      final voicePath = _voicePath;
      final speakerName = _prepSpeakerName;
      final speakerId = _prepSpeakerId;
      final instructPrompt = _prepInstructPrompt;
      final refText = _prepRefText;

      Log.instance.i('tts', 'synth starting', fields: {
        'backend': backend ?? '',
        'model': p.basename(modelPath),
        'voice': voicePath == null ? '' : p.basename(voicePath),
        'codec': codecPath == null ? '' : p.basename(codecPath),
        'speaker': speakerName ?? '',
        'speaker_id': speakerId ?? -1,
        'text_len': synthText.length,
        'speed': clampedSpeed,
      });

      // #23 — Run synthesis in a background isolate so the UI thread
      // stays responsive. The model file is already mmap'd from
      // prepare(), so re-open in the isolate hits the OS page cache.
      Float32List pcm = await Isolate.run<Float32List>(() {
        late final crispasr.CrispasrSession s;
        if (backend != null) {
          s = crispasr.CrispasrSession.open(modelPath, backend: backend);
        } else {
          s = crispasr.CrispasrSession.open(modelPath);
        }
        try {
          if (codecPath != null) s.setCodecPath(codecPath);
          // Voice / speaker selection — these are critical; let errors
          // propagate so the caller sees the actual failure reason
          // instead of a generic "no audio produced".
          if (instructPrompt != null && instructPrompt.isNotEmpty) {
            s.setInstruct(instructPrompt);
          } else if (speakerName != null && speakerName.isNotEmpty) {
            s.setSpeakerName(speakerName);
          } else if (speakerId != null) {
            s.setSpeakerID(speakerId);
          } else if (voicePath != null) {
            s.setVoice(voicePath, refText: refText);
          }
          // Per-call sampling overrides. Setters no-op on backends
          // that don't honour the field — swallow safely.
          if (ttsSteps != null) {
            try { s.setTtsSteps(ttsSteps); } catch (_) {}
          }
          if (clampedSpeed != 1.0) {
            try { s.setLengthScale(1.0 / clampedSpeed); } catch (_) {}
          }
          if (temperature != null) {
            try { s.setTemperature(temperature); } catch (_) {}
          }
          if (topP != null) {
            try { s.setTopP(topP); } catch (_) {}
          }
          if (minP != null) {
            try { s.setMinP(minP); } catch (_) {}
          }
          if (cfgWeight != null) {
            try { s.setCfgWeight(cfgWeight); } catch (_) {}
          }
          if (exaggeration != null) {
            try { s.setExaggeration(exaggeration); } catch (_) {}
          }
          if (repetitionPenalty != null) {
            try { s.setRepetitionPenalty(repetitionPenalty); } catch (_) {}
          }
          if (maxSpeechTokens != null) {
            try { s.setMaxSpeechTokens(maxSpeechTokens); } catch (_) {}
          }
          if (seed != null) {
            try { s.setTtsSeed(seed); } catch (_) {}
          }
          if (frequencyPenalty != null) {
            try { s.setFrequencyPenalty(frequencyPenalty); } catch (_) {}
          }
          if (topK != null) {
            try { s.setTopK(topK); } catch (_) {}
          }
          if (doSample != null) {
            try { s.setDoSample(doSample); } catch (_) {}
          }
          if (ttsNumCandidates != null) {
            try { s.setTtsNumCandidates(ttsNumCandidates); } catch (_) {}
          }
          if (g2pDict != null && g2pDict.isNotEmpty) {
            try { s.setG2pDict(g2pDict); } catch (_) {}
          }
          if (noiseTemp != null) {
            try { s.setTtsNoiseTemp(noiseTemp); } catch (_) {}
          }
          return s.synthesize(synthText);
        } finally {
          s.close();
        }
      });
      // CrispASR's TTS backends all output 24 kHz mono float32.
      final int beforeSamples = pcm.length;
      // Diagnostic: capture min/max/mean + finite-count so a silent
      // WAV with non-zero `samples_out` is debuggable from logs
      // alone. Cheap (one pass over the buffer); only enabled in
      // debug builds via Log.d.
      if (pcm.isNotEmpty) {
        double mn = pcm[0];
        double mx = pcm[0];
        double sum = 0;
        int finite = 0;
        for (final s in pcm) {
          if (s.isFinite) {
            finite++;
            sum += s;
            if (s < mn) mn = s;
            if (s > mx) mx = s;
          }
        }
        Log.instance.d('tts', 'pcm stats', fields: {
          'n': pcm.length,
          'finite': finite,
          'min': mn.toStringAsFixed(4),
          'max': mx.toStringAsFixed(4),
          'mean': finite > 0
              ? (sum / finite).toStringAsFixed(4)
              : '—',
        });
      }
      if (trimSilence) pcm = _trimSilence(pcm);
      if ((clampedSpeed - 1.0).abs() > 1e-3) {
        pcm = _resampleSpeed(pcm, clampedSpeed);
      }
      Log.instance.i('tts', 'synth done', fields: {
        'samples_raw': beforeSamples,
        'samples_out': pcm.length,
        'seconds': (pcm.length / 24000.0).toStringAsFixed(2),
        'speed': clampedSpeed.toStringAsFixed(2),
        'trim_silence': trimSilence,
        'backend': _backend,
      });
      return SynthesizedAudio(samples: pcm, sampleRate: 24000);
    } catch (e, st) {
      // Diagnostic enrichment: the upstream C-side last_synth_error now
      // carries a specific reason (e.g. "qwen3-tts Base requires a
      // voice"). Surface that to the caller rather than swallowing it.
      final msg = e.toString();
      final hint = _diagnosticHint(_backend ?? '', msg);
      Log.instance.e('tts', 'synth failed', error: e, stack: st,
          fields: hint == null ? null : {'hint': hint});
      // Rethrow with the C-side error or a diagnostic hint so the UI
      // can show the specific reason instead of a generic "no audio".
      final reason = hint ?? msg;
      throw Exception(reason);
    }
  }

  /// Best-effort root-cause hint for a synth failure, keyed off the
  /// upstream exception text + the loaded backend. Surfaced in the
  /// log fields so a bug report includes the most likely cause
  /// without the user having to dig.
  String? _diagnosticHint(String backend, String exceptionText) {
    final isNoAudio = exceptionText.contains('returned no audio');
    if (!isNoAudio) return null;
    if (backend == 'kokoro') {
      return 'kokoro needs libespeak-ng + espeak-ng-data for phonemisation. '
          'Desktop releases bundle them next to the runtime; Android extracts '
          'the asset bundle on first launch. Check that '
          'CRISPASR_ESPEAK_DATA_PATH points at a populated dir or that '
          'espeak-ng is on PATH.';
    }
    // #22 — aggressive quantisation can cause qwen3-tts to produce
    // empty audio (codebook tokens become garbage → codec decodes silence).
    if (backend == 'qwen3-tts') {
      return 'qwen3-tts may produce no audio with aggressive quantisation '
          '(q4_k or below). Try the q8_0 variant for reliable output.';
    }
    if (backend == 'pocket-tts') {
      return 'pocket-tts Mimi decoder may fail on GPU backends. '
          'The engine now pins Mimi decode to CPU; if this persists, '
          'try a different TTS model.';
    }
    return null;
  }

  /// Strip leading + trailing samples whose magnitude is below the
  /// `1/4096` threshold (about -72 dBFS). Cheap pure-Dart audio gate.
  /// Returns the original buffer when no silence is found.
  static Float32List _trimSilence(Float32List pcm) {
    if (pcm.isEmpty) return pcm;
    const double threshold = 1.0 / 4096.0;
    int start = 0;
    while (start < pcm.length && pcm[start].abs() < threshold) {
      start++;
    }
    int end = pcm.length - 1;
    while (end > start && pcm[end].abs() < threshold) {
      end--;
    }
    if (start == 0 && end == pcm.length - 1) return pcm;
    return Float32List.sublistView(pcm, start, end + 1);
  }

  /// Nearest-neighbour resample for tempo change. Pitch is preserved
  /// by the player (the listener perceives a faster / slower talker
  /// at the same pitch). Higher-quality (phase-vocoder) resampling
  /// would need a separate audio dep — keep it simple for the GUI use
  /// case where users typically tweak by ±20%.
  static Float32List _resampleSpeed(Float32List pcm, double speed) {
    if (pcm.isEmpty || speed == 1.0) return pcm;
    // Guard against pathological slider values. A 0 / negative /
    // NaN speed makes the (pcm.length / speed) division produce
    // Infinity or NaN, and Dart's .floor() throws
    // "Unsupported operation: Infinity or NaN toInt" with no
    // recoverable context — surfaces to the user as
    // "Synthese fehlgeschlagen". The slider clamps to 0.25–4 in
    // the UI but a preset round-trip / stored 0.0 from an older
    // build can still slip through.
    if (!speed.isFinite || speed <= 0) return pcm;
    final int outLen = (pcm.length / speed).floor();
    if (outLen <= 0) return Float32List(0);
    final out = Float32List(outLen);
    for (int i = 0; i < outLen; i++) {
      final int srcIdx = (i * speed).floor();
      out[i] = srcIdx < pcm.length ? pcm[srcIdx] : 0.0;
    }
    return out;
  }

  /// §5.26.3 — Speech-to-Speech: audio in → audio out via a single
  /// model pass. Supported on lfm2-audio and mini-omni2 backends.
  ///
  /// [inputPcm] is 16 kHz mono float32 input audio. Returns a
  /// [SynthesizedAudio] with the output PCM and an optional
  /// intermediate transcript.
  Future<SynthesizedAudio?> speechToSpeech(
    Float32List inputPcm,
  ) async {
    if (_session == null) return null;
    final modelPath = _modelPath;
    if (modelPath == null) return null;
    final backend = _backend;
    final codecPath = _codecPath;

    Log.instance.i('tts', 's2s starting', fields: {
      'backend': backend ?? '',
      'model': modelPath.split('/').last,
      'input_samples': inputPcm.length,
    });

    try {
      final result =
          await Isolate.run<({Float32List pcm, String transcript})>(() {
        late final crispasr.CrispasrSession s;
        if (backend != null) {
          s = crispasr.CrispasrSession.open(modelPath, backend: backend);
        } else {
          s = crispasr.CrispasrSession.open(modelPath);
        }
        try {
          if (codecPath != null) s.setCodecPath(codecPath);
          // speechToSpeech() is available in CrispASR builds with the
          // feat/session-s2s-hotwords branch merged. Older builds
          // throw UnsupportedError.
          return s.speechToSpeech(inputPcm);
        } finally {
          s.close();
        }
      });

      Log.instance.i('tts', 's2s done', fields: {
        'output_samples': result.pcm.length,
        'transcript_len': result.transcript.length,
      });

      return SynthesizedAudio(
        samples: result.pcm,
        sampleRate: 24000,
      );
    } catch (e, st) {
      Log.instance.e('tts', 's2s failed', error: e, stack: st);
      return null;
    }
  }

  /// Write the synthesised PCM as a 16-bit WAV to a temp file. Returns
  /// the file path so the caller can hand it to the share sheet / save
  /// dialog.
  ///
  /// When [voiceRefPath] is non-null the output uses a cloned voice, and
  /// when [voiceConverted] is true the output is speech-to-speech voice
  /// conversion. Both are deep fakes for Art. 50(4) purposes, so both get
  /// a beep-based AI disclaimer prepended to the PCM.
  ///
  /// EU AI Act Art. 50(4): the beep disclaimer is **mandatory** for
  /// voice-cloned and voice-converted output. To suppress it, the caller
  /// must provide [disclaimerOverrideAttestation] — a non-empty string
  /// documenting the legal basis for suppression (e.g. "internal testing,
  /// not for distribution"). This shifts the compliance burden to the
  /// caller and is logged for audit. The watermark and C2PA signing
  /// remain regardless.
  ///
  /// Note: the spread-spectrum watermark is normally auto-applied by
  /// `crispasr_session_synthesize` at the C API level. We *probe the PCM*
  /// to confirm that rather than inferring it from symbol availability —
  /// see the marking block below.
  Future<File> writeWav(
    SynthesizedAudio audio, {
    String? basename,
    String? voiceRefPath,
    bool voiceConverted = false,
    String? disclaimerOverrideAttestation,
  }) async {
    final dir = await getTemporaryDirectory();
    // macOS with sandbox-app disabled returns
    // ~/Library/Caches/<bundle-id>/ from getTemporaryDirectory(),
    // and that path doesn't auto-exist on first use — we have to
    // create it. iOS / Android / Linux's temp dirs already exist
    // by the time the API hands us a path. Calling create() with
    // recursive:true is idempotent and cheap, so no platform gate.
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final now = DateTime.now();
    final stamp = now.millisecondsSinceEpoch;
    final name = basename ?? 'crisperweaver-synth-$stamp.wav';
    final out = File(p.join(dir.path, name));
    // Voice-clone disclaimer + consent audit logging.
    var samples = audio.samples;
    final bool isVoiceClone =
        (voiceRefPath != null && voiceRefPath.isNotEmpty) || voiceConverted;
    if (isVoiceClone) {
      final bool suppressDisclaimer =
          disclaimerOverrideAttestation != null &&
          disclaimerOverrideAttestation.trim().isNotEmpty;

      if (!suppressDisclaimer) {
        // EU AI Act Art. 50(4): mandatory beep disclaimer for deepfake audio.
        final beeps = AudioWatermarkService.generateBeepDisclaimer(
          sampleRate: audio.sampleRate,
        );
        final combined = Float32List(beeps.length + samples.length);
        combined.setRange(0, beeps.length, beeps);
        combined.setRange(beeps.length, combined.length, samples);
        samples = combined;
        Log.instance.d('tts', 'beep disclaimer prepended (mandatory)',
            fields: {'beep_samples': beeps.length});
      } else {
        // Caller has provided a legal attestation to suppress the beep.
        // Compliance burden shifts to the caller. Log for audit.
        Log.instance.w('tts',
            '[DISCLAIMER-OVERRIDE] beep disclaimer suppressed — '
            'burden shifted to caller',
            fields: {
              'attestation': disclaimerOverrideAttestation,
              'ts': DateTime.now().toUtc().toIso8601String(),
              'model': _backend ?? 'unknown',
              'voice': voiceRefPath,
            });
      }

      // Log consent attestation for audit trail.
      _logConsentAttestation(
        modelId: _backend ?? 'unknown',
        voiceId: voiceRefPath ?? '(speech-to-speech voice conversion)',
      );
    }

    // EU AI Act Art. 50(2) machine-readable marking.
    //
    // `crispasr_session_synthesize` normally auto-embeds the
    // spread-spectrum watermark at the C API level. We must NOT infer
    // that from `CrispasrWatermark.isAvailable()` — that only reports
    // whether the *symbol* exists, not whether embedding ran. If the
    // native auto-embed were ever conditional (backend without support,
    // env gate, old dylib), we would skip the fallback and ship unmarked
    // audio while believing it was marked. So: probe the PCM.
    //
    // Detection runs on `audio.samples` (pre-beep) because the native
    // watermark covers only the synthesised audio; a prepended beep
    // would dilute the frame-averaged correlation.
    var markedNatively = false;
    if (AppConstants.enableAudioWatermark) {
      final confidence = SpreadSpectrumWatermark.detect(audio.samples);
      markedNatively = confidence >= _watermarkConfidenceFloor;
      Log.instance.d('tts', 'native watermark probe',
          fields: {
            'confidence': confidence.toStringAsFixed(3),
            'floor': _watermarkConfidenceFloor,
            'marked': markedNatively,
          });
    }

    // The PCM that actually lands in the WAV — watermarked in the
    // fallback branch, passed through when the C API already marked it.
    var pcmForWav = samples;
    var appliedDartFallback = false;
    if (AppConstants.enableAudioWatermark && !markedNatively) {
      // Pure-Dart spread-spectrum watermark, cross-compatible with the
      // CrispASR / CrispTTS detectors.
      pcmForWav = SpreadSpectrumWatermark.embed(samples);
      appliedDartFallback = true;
    }
    var bytes = _floatPcmToWavBytes(
      pcmForWav,
      audio.sampleRate,
      modelName: _backend,
      voiceId: voiceRefPath != null
          ? p.basenameWithoutExtension(voiceRefPath)
          : null,
    );
    if (appliedDartFallback) {
      // Also apply LSB watermark for backward compat with older detectors.
      bytes = AudioWatermarkService.embedWatermark(
        bytes,
        timestamp: now,
        synthetic: true,
      );
      Log.instance
          .d('tts', 'dart spread-spectrum + LSB watermark applied (fallback)');
    }
    // Post-embed watermark verification: detect immediately after
    // embedding to catch silent failures (corrupted WAV, truncation).
    //
    // Measured on this detector: clean audio peaks at ~0.50 confidence,
    // freshly watermarked audio sits at 0.78–0.91 from ~100 ms upward,
    // and detection is level-invariant (0.78 at 0.01× amplitude). Audio
    // below one FFT frame (~100 ms) and digital silence both read 0.000
    // — they cannot carry a spectral watermark at all. The 0.65 floor
    // sits in the gap and does not reject quiet or short-but-real output.
    var watermarkVerified = false;
    var watermarkConfidence = 0.0;
    if (AppConstants.enableAudioWatermark) {
      // Verify with the detector matching whichever path actually ran.
      // The previous code always used the LSB detector, which the native
      // path never populates — so this warned on every single synthesis
      // while verifying nothing.
      watermarkConfidence = SpreadSpectrumWatermark.detect(pcmForWav);
      final ssOk = watermarkConfidence >= _watermarkConfidenceFloor;
      final lsbOk = !appliedDartFallback ||
          AudioWatermarkService.detectWatermark(bytes) != null;
      watermarkVerified = ssOk && lsbOk;
      if (!watermarkVerified) {
        // Escalated from warning: this is the robust mark failing. The
        // container metadata below still marks the file, but it strips
        // on any re-encode, so the user has to be told.
        Log.instance.e('tts',
            'post-embed watermark verification FAILED — output carries only '
            'strippable container marking, not the robust Art. 50(2) watermark',
            fields: {
              'ssConfidence': watermarkConfidence.toStringAsFixed(3),
              'floor': _watermarkConfidenceFloor,
              'ssOk': ssOk,
              'lsbOk': lsbOk,
              'path': appliedDartFallback ? 'dart-fallback' : 'native',
              'samples': audio.samples.length,
              'hint': audio.samples.length < 1600
                  ? 'audio shorter than ~100 ms cannot carry the watermark'
                  : 'near-silent audio cannot carry a spectral watermark',
            });
      } else {
        Log.instance.d('tts', 'post-embed watermark verified', fields: {
          'ssConfidence': watermarkConfidence.toStringAsFixed(3),
          'path': appliedDartFallback ? 'dart-fallback' : 'native',
        });
      }
    }
    // C2PA signing — EU AI Act Art. 50 machine-readable AI-content marking.
    // Try real COSE/X.509 signing via CrispASR's native c2pa-audio first;
    // fall back to the unsigned JSON-LD manifest when the native symbols
    // are unavailable (web builds, old dylibs).
    bool c2paSigned = false;
    if (crispasr.CrispasrC2pa.isAvailable()) {
      final signed = crispasr.CrispasrC2pa.sign(
        bytes,
        format: 'audio/wav',
      );
      if (signed != null) {
        bytes = signed;
        c2paSigned = true;
        Log.instance.d('tts', 'C2PA signed (COSE/X.509, native c2pa-audio)');
      } else {
        Log.instance.w('tts', 'C2PA native signing returned null — falling back to unsigned manifest');
      }
    }
    if (!c2paSigned) {
      // Unsigned JSON-LD fallback: still machine-readable, but not
      // cryptographically verifiable. Better than nothing.
      bytes = ContentProvenanceService.injectIntoWav(
        bytes,
        generator: 'CrisperWeaver',
        generatorVersion: AppConstants.appVersion,
        modelName: _backend,
        voiceId: voiceRefPath != null
            ? p.basenameWithoutExtension(voiceRefPath)
            : null,
        timestamp: now,
      );
      Log.instance.d('tts', 'C2PA unsigned JSON-LD manifest injected (fallback)');
    }
    lastMarking = MarkingStatus(
      watermarkVerified: watermarkVerified,
      watermarkConfidence: watermarkConfidence,
      c2paSigned: c2paSigned,
    );
    if (!lastMarking!.robustMarkPresent) {
      Log.instance.e('tts',
          '[MARKING] no robust mark on synthesised output — neither a verified '
          'watermark nor a COSE-signed C2PA manifest; only strippable '
          'container metadata (EU AI Act Art. 50(2))',
          fields: {'file': out.path});
    }
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  /// Log a consent attestation for voice-cloned TTS synthesis.
  ///
  /// Format matches CrispASR / CrispTTS audit trail:
  /// `[CONSENT] ts=ISO8601 model=X voice=Y attestation="user consent"`
  void _logConsentAttestation({
    required String modelId,
    required String voiceId,
  }) {
    final ts = DateTime.now().toUtc().toIso8601String().replaceAll('-', '-');
    final voiceStr = p.basename(voiceId);
    Log.instance.i('consent',
        '[CONSENT] ts=$ts model=$modelId voice=$voiceStr '
        'attestation="user consent"');
  }

  void dispose() {
    _session?.close();
    _session = null;
    _key = null;
    _backend = null;
    _modelPath = null;
    _voicePath = null;
    _codecPath = null;
  }

  /// Drop the open session's per-phoneme cache. Useful for long-
  /// running TTS daemons (and the synthesize screen's "Clear
  /// phoneme cache" button) cycling through many speakers on
  /// kokoro — without periodic clearing, the cache grows
  /// unboundedly.
  ///
  /// Returns false when no session is open OR the loaded dylib
  /// predates `crispasr_session_clear_phoneme_cache` (pre-0.6.x).
  /// Callers should surface that as a "feature unavailable on
  /// this build" hint rather than an error.
  Future<bool> clearPhonemeCache() async {
    final session = _session;
    if (session == null) return false;
    try {
      session.clearPhonemeCache();
      return true;
    } on UnsupportedError {
      return false;
    } catch (e, st) {
      Log.instance.w('tts',
          'clearPhonemeCache failed (treating as unavailable)',
          error: e, stack: st);
      return false;
    }
  }

  // 16-bit PCM WAV header + body + LIST INFO provenance metadata.
  // Mono. Float input is clamped to [-1, 1] then scaled to int16.
  // The LIST INFO chunk (synthetic-content provenance) is appended after
  // the data chunk so legacy parsers that stop at `data` still work.
  Uint8List _floatPcmToWavBytes(
    Float32List samples,
    int sampleRate, {
    String? modelName,
    String? voiceId,
  }) {
    final dataBytes = samples.length * 2; // int16 mono

    // --- Build LIST INFO chunk payload --------------------------------
    // Machine-readable provenance metadata. Encodes
    // the generator, model, voice identity, and creation timestamp so
    // downstream tools can verify the content's origin.
    final infoFields = <String, String>{
      'ISFT': 'CrisperWeaver ${AppConstants.appVersion}',
      'ICMT': 'AI-generated synthetic speech',
      'IART': '${modelName ?? "unknown"} TTS',
      'ICRD': DateTime.now().toUtc().toIso8601String(),
      if (voiceId != null) 'IGNR': 'voice:$voiceId',
    };
    // Each INFO sub-chunk: 4-byte ID + 4-byte size + null-terminated
    // string (padded to even length).
    final infoChunks = <int>[];
    for (final entry in infoFields.entries) {
      final id = entry.key.codeUnits; // always 4 ASCII chars
      final strBytes = [...entry.value.codeUnits, 0]; // null-terminated
      if (strBytes.length.isOdd) strBytes.add(0); // pad to even
      final size = strBytes.length;
      infoChunks.addAll(id);
      infoChunks.addAll([
        size & 0xFF,
        (size >> 8) & 0xFF,
        (size >> 16) & 0xFF,
        (size >> 24) & 0xFF,
      ]);
      infoChunks.addAll(strBytes);
    }
    // LIST chunk: 'LIST' + uint32 size + 'INFO' + sub-chunks
    final listPayloadSize = 4 + infoChunks.length; // 'INFO' + sub-chunks
    final listChunkSize = 8 + listPayloadSize; // 'LIST' + size field + payload

    final fileBytes = 44 + dataBytes + listChunkSize;
    final out = Uint8List(fileBytes);
    final bd = ByteData.view(out.buffer);

    // RIFF header — total file size includes everything after 'RIFF'+size.
    out.setRange(0, 4, 'RIFF'.codeUnits);
    bd.setUint32(4, fileBytes - 8, Endian.little);
    out.setRange(8, 12, 'WAVE'.codeUnits);
    // fmt
    out.setRange(12, 16, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little); // chunk size
    bd.setUint16(20, 1, Endian.little); // PCM format
    bd.setUint16(22, 1, Endian.little); // mono
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bd.setUint16(32, 2, Endian.little); // block align
    bd.setUint16(34, 16, Endian.little); // bits per sample
    // data
    out.setRange(36, 40, 'data'.codeUnits);
    bd.setUint32(40, dataBytes, Endian.little);

    var off = 44;
    for (var i = 0; i < samples.length; i++) {
      var s = samples[i];
      if (!s.isFinite) s = 0.0;
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      bd.setInt16(off, (s * 32767).round(), Endian.little);
      off += 2;
    }

    // LIST INFO chunk — appended after PCM data.
    out.setRange(off, off + 4, 'LIST'.codeUnits);
    bd.setUint32(off + 4, listPayloadSize, Endian.little);
    out.setRange(off + 8, off + 12, 'INFO'.codeUnits);
    out.setRange(off + 12, off + 12 + infoChunks.length, infoChunks);

    return out;
  }
}

class TtsLoadStatus {
  final bool ready;
  final String? backend;

  /// When non-null, the user needs to download this model name first.
  final String? missingModelName;

  /// When non-null, the user needs to download this voicepack first.
  final String? missingVoiceName;

  /// When non-null, the user needs to download this codec/tokenizer first.
  final String? missingCodecName;
  final String? errorMessage;

  /// When non-null, the selected model's backend isn't dispatchable through
  /// the unified session API on this build's bundled libcrispasr (e.g.
  /// piper — issue #16). Carries the backend id so the UI can name it.
  final String? unsupportedBackend;

  const TtsLoadStatus._({
    required this.ready,
    this.backend,
    this.missingModelName,
    this.missingVoiceName,
    this.missingCodecName,
    this.errorMessage,
    this.unsupportedBackend,
  });

  factory TtsLoadStatus.ready(String backend) =>
      TtsLoadStatus._(ready: true, backend: backend);
  factory TtsLoadStatus.missing(
          {String? modelName, String? voiceName, String? codecName}) =>
      TtsLoadStatus._(
        ready: false,
        missingModelName: modelName,
        missingVoiceName: voiceName,
        missingCodecName: codecName,
      );
  factory TtsLoadStatus.error(String msg) =>
      TtsLoadStatus._(ready: false, errorMessage: msg);
  factory TtsLoadStatus.unsupported(String backend) =>
      TtsLoadStatus._(ready: false, unsupportedBackend: backend);
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  final svc = TtsService(ref.watch(modelServiceProvider));
  ref.onDispose(svc.dispose);
  return svc;
});
