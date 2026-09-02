import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'; // §legacy: advancedOptionsProvider
// remains a StateProvider because it is a simple value holder mutated from 47+
// call sites via `.notifier).state =`. Riverpod 3's Notifier marks `state`
// @protected so external assignment would require an explicit setter method on
// every field — impractical for a 40-field options class.

import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider, transcriptionServiceProvider;
import '../services/model_service.dart';
import '../services/vad_service.dart';

/// Per-run state for the "Advanced decoding" block — translate flag,
/// beam-search strategy, initial prompt. Held as a Riverpod state
/// class so the transcribe path in `transcription_screen.dart` reads
/// the same values the user just edited.
class AdvancedOptions {
  final bool translate;
  final bool beamSearch;
  final String initialPrompt;

  /// Skip silent regions via whisper.cpp's built-in Silero VAD pipeline.
  /// The bundled asset at `assets/vad/silero-v6.2.0-ggml.bin` is extracted
  /// on first use; the engine sets `params.vad = true` +
  /// `params.vad_model_path` and whisper internally restricts decoding
  /// to voiced frames.
  final bool vad;

  /// Run FireRedPunc on the engine output to add capitalisation +
  /// punctuation. No-op when no `fireredpunc-*.gguf` is on disk; useful
  /// for CTC backends (wav2vec2 / fastconformer-ctc / firered-asr) whose
  /// raw output is unpunctuated lowercase.
  final bool restorePunctuation;

  /// Target language for translation backends (canary / voxtral /
  /// voxtral4b / qwen3 / cohere). When equal to source (or empty),
  /// the backend transcribes verbatim. When different, it translates
  /// from source → target. Whisper has its own boolean toggle
  /// ([translate]) that always targets English; this field only takes
  /// effect on session backends that advertise translation support.
  final String targetLanguage;

  /// Audio Q&A prompt for instruct-tuned audio-LLM backends (voxtral
  /// / voxtral4b / qwen3). When non-empty, the backend ANSWERS the
  /// prompt instead of producing a verbatim transcript ("Summarize",
  /// "What's the speaker's tone?", "What did they say about X?").
  /// Empty means "transcribe normally" — the historical default.
  final String askPrompt;

  /// Decoder temperature for sampling backends (canary, cohere,
  /// parakeet, moonshine — per CrispASR's `setTemperature` contract).
  /// 0.0 = greedy (the historical default; reproducible). > 0.0 =
  /// stochastic sampling, useful when the greedy decode is stuck on a
  /// hallucinated repetition or when paraphrasing is desired. Whisper
  /// has its own temperature fallback ladder inside whisper.cpp; this
  /// field doesn't reach Whisper. Backends that don't support runtime
  /// temperature silently no-op (the C ABI returns rc=-2).
  final double temperature;

  /// Explicit source-language override for translation backends.
  /// Empty means "use the global language dropdown / autodetect".
  /// Non-empty overrides `language:` on the engine call so the user
  /// can pin the source while picking a different target — useful
  /// when whisper's autodetect is unreliable on noisy audio.
  final String sourceLanguage;

  /// Best-of-N decoding. 1 = single decode (historical default).
  /// >1 runs N independent decodes and picks the highest-scoring
  /// result. For Whisper this is internal (`wparams.greedy.best_of`);
  /// for every other backend the CrispASR C side loops externally
  /// and picks the highest-mean-confidence result. Useful when
  /// greedy hallucinates a repetition or the audio is noisy.
  /// Cost: N× the per-call decode time.
  final int bestOf;

  // -------------------------------------------------------------------
  // VAD tunables (CrispASR 0.6 parity — exposed via SessionVadOptions
  // and whisper's TranscribeOptions).
  // -------------------------------------------------------------------

  /// Which VAD GGUF to run when [vad] is on. Silero is bundled (always
  /// available); FireRed / MarbleNet / Whisper-VAD-EncDec require an
  /// explicit download via Model Management.
  final VadBackend vadBackend;

  /// Silero VAD decision threshold (0..1). Higher = fewer / shorter
  /// speech regions. CrispASR ships 0.5.
  final double vadThreshold;

  /// Shortest run of voiced frames (ms) kept as a speech segment.
  final int vadMinSpeechMs;

  /// Shortest silence (ms) needed to split one segment from the next.
  final int vadMinSilenceMs;

  /// Extra context padding (ms) added on each side of every segment.
  final int vadSpeechPadMs;

  // -------------------------------------------------------------------
  // Diarisation method (CrispASR 0.4.5+ shared-lib `diarizeSegments`).
  // -------------------------------------------------------------------

  /// Which diarisation algorithm to run when the user enables
  /// diarisation. Defaults to `vadTurns` because it's mono-friendly
  /// and needs no extra model. Pyannote requires the
  /// `pyannote-v3-seg-*.gguf` GGUF to be on disk.
  final crispasr.DiarizeMethod diarizeMethod;

  /// §5.8.1 — Resolve diarised "Speaker N" labels to enrolled speaker
  /// names using TitaNet + SpeakerDB. Requires the TitaNet GGUF to be
  /// downloaded and at least one speaker enrolled via Settings →
  /// Speakers. No-op when [diarizeMethod] is `energy` (stereo channel
  /// IDs are already meaningful) or when no model / DB profiles are
  /// present.
  final bool enableSpeakerRecognition;

  // -------------------------------------------------------------------
  // LID method (CrispASR 0.4.6+ `crispasr_detect_language_pcm`).
  // -------------------------------------------------------------------

  /// Which LID classifier to run when the user picks Auto-detect on a
  /// session backend that doesn't have native language identification.
  /// Whisper reuses any multilingual ggml-*.bin already downloaded;
  /// Silero needs its own ~16 MB GGUF.
  final crispasr.LidMethod lidMethod;

  // -------------------------------------------------------------------
  // Whisper-only extras.
  // -------------------------------------------------------------------

  /// tinydiarize speaker-turn markers. Requires a whisper `.en.tdrz`
  /// finetune; output contains `[SPEAKER_TURN]` tokens callers can
  /// split segments on.
  final bool tdrz;

  /// Token-level timestamps (DTW-aligned). Adds per-token timing on
  /// top of per-segment timing; pairs well with `maxLen`.
  final bool tokenTimestamps;

  /// Punctuation post-processor preference: `"firered"` for FireRedPunc
  /// (ZH+EN), `"fullstop"` for fullstop-punc (EN/DE/FR/IT). Honoured
  /// by PuncService when both are downloaded.
  final String puncFamily;

  // -------------------------------------------------------------------
  // LID accelerator + threading. CrispASR's `detect_language_pcm`
  // exposes useGpu / flashAttn / nThreads directly; surface them so
  // users on Metal/CUDA can offload the LID encoder pass.
  // -------------------------------------------------------------------

  /// Route LID inference to the GPU when supported.
  final bool lidUseGpu;

  /// Enable flash-attention on the LID encoder.
  final bool lidFlashAttn;

  /// CPU thread count for LID and other helper passes.
  final int nThreads;

  /// Route the ASR session to the GPU at session-open time. Threaded
  /// through CrispASR 0.6.1's `crispasr_session_open_with_params`.
  /// Backends without a runtime `use_gpu` field keep their compile-
  /// time default; see `AdvancedTranscribeOptions.asrUseGpu`.
  final bool asrUseGpu;

  /// Flash-attention on the ASR session. Honoured by whisper today;
  /// other backends accept the toggle but their compute graphs aren't
  /// yet branched on it (lands per-backend incrementally).
  final bool asrFlashAttn;

  /// Cap on GPU-offloaded transformer layers for LLM-based backends.
  /// -1 = max, 0 = run LLM on CPU, >0 = explicit bound. Pre-0.6.2
  /// dylibs ignore the value.
  final int asrNGpuLayers;

  /// §5.8 — soft cap on tokens per whisper segment. 0 = no
  /// cap (whisper default). Pairs with [splitOnWord] for SRT-
  /// friendly short subtitle lines. Whisper-only.
  final int maxLen;

  /// §5.8 — split on word boundaries when [maxLen] is set.
  /// Whisper-only; no-op for CTC / LLM-session backends.
  final bool splitOnWord;

  /// §5.8 — split at sentence-ending punctuation (. ! ?).
  /// Dart-side post-processing applied to any backend's output.
  /// Creates natural subtitle lines even for long segments.
  final bool splitOnPunct;

  /// §5.8 — GBNF grammar source. Non-empty enables grammar-
  /// constrained sampling on whisper (forces beam search; auto-
  /// bumps beam_size to 5 when the user left it at default 1).
  /// Empty means "no constraint" (verbatim transcription).
  /// Whisper-only — every other backend ignores the field.
  ///
  /// Example forcing JSON output:
  /// ```gbnf
  /// root  ::= "{" key ":" value "}"
  /// key   ::= "\"" [a-zA-Z]+ "\""
  /// value ::= [0-9]+
  /// ```
  final String grammarText;

  /// §5.8 — Root rule symbol name for [grammarText]. The GBNF
  /// convention is "root"; users with a multi-section grammar
  /// can override to start parsing from a different rule.
  final String grammarRootRule;

  /// §5.8 — Whisper's `grammar_penalty` scalar (upstream default
  /// 100.0). Lower values make the grammar a "suggestion" rather
  /// than a hard constraint; the recommended range is 50..200.
  final double grammarPenalty;

  /// Whisper text-suppression + prompt-carry extras (whisper-only;
  /// other backends ignore). Defaults match whisper_full_default_params.
  ///
  /// * [suppressNonSpeechTokens] (false) — drop `[LAUGHTER]` /
  ///   `[MUSIC]` / `[NOISE]` markers from transcript output.
  /// * [suppressTokensRegex] ('') — Posix regex; tokens whose
  ///   text matches get dropped during decoding. Empty disables.
  /// * [carryInitialPrompt] (false) — prepend initial_prompt to
  ///   every decode window, not just the first. Strengthens
  ///   vocabulary biasing across long audio.
  final bool suppressNonSpeechTokens;
  final String suppressTokensRegex;
  final bool carryInitialPrompt;

  /// Whisper decoder-fallback thresholds. All four feed
  /// `whisper_full_params` on the whisper transcribe path
  /// (silently ignored by other backends — none have an analog).
  /// Defaults match whisper_full_default_params so unmodified
  /// sliders behave like stock whisper.cpp.
  ///
  /// * [entropyThold] (2.4) — per-token entropy that triggers
  ///   a fallback pass. Lower = stricter; raise on hard audio.
  /// * [logprobThold] (-1.0) — avg log-probability cutoff that
  ///   triggers a fallback pass. More negative = more
  ///   tolerant of noisy decoding.
  /// * [noSpeechThold] (0.6) — silence detector cutoff. Higher
  ///   = less aggressive silence gating.
  /// * [temperatureInc] (0.2) — temperature step per fallback
  ///   pass. 0.0 disables the fallback loop entirely
  ///   (the CLI's `--no-fallback`).
  /// Named bundle of the four thresholds below (CrispASR `--sensitivity`).
  /// Empty = manual, i.e. the individual sliders drive the decode. Set to a
  /// preset name and the preset is applied INSTEAD — the C side treats a
  /// later set_fallback_thresholds() as overriding it, so sending both
  /// would discard the preset every time.
  final String sensitivityPreset;

  final double entropyThold;
  final double logprobThold;
  final double noSpeechThold;
  final double temperatureInc;

  /// §5.1.10 — RNNoise audio enhancement pre-step. When true, the
  /// transcribe screen pipes the loaded 16 kHz PCM through
  /// `crispasr.enhanceAudioRnnoise(...)` before the §5.8 window
  /// slice / dispatch to whisper / parakeet / canary / etc.
  /// Backend-agnostic — every transcribe path sees the same
  /// denoised buffer.
  ///
  /// Costs ~1× realtime on a single CPU core; off by default so
  /// nothing changes for users with clean recordings. Pre-0.5.12
  /// libcrispasr builds raise UnsupportedError and the wiring
  /// silently falls through to the un-enhanced PCM.
  final bool enhanceAudio;

  /// Transcribe-window start (seconds). 0 = start of file.
  /// Pairs with [transcribeWindowDurationSec] — together they
  /// implement the equivalent of CrispASR CLI's `--offset-t` +
  /// `--duration`. Backend-agnostic — the screen slices the PCM
  /// before dispatch and the existing `startOffsetSec` shift
  /// brings segment timestamps back to absolute file time.
  final double transcribeWindowStartSec;

  /// Transcribe-window duration (seconds). 0 = no cap, transcribe
  /// to the end of the file from [transcribeWindowStartSec].
  /// Useful for "transcribe minute 5..10 of this 2-hour podcast"
  /// without round-tripping through the audio editor's trim flow.
  final double transcribeWindowDurationSec;

  /// §5.1.11 — Per-token top-N alternative-candidate capture
  /// (Whisper greedy decode only). 0 (default) = off. When > 0,
  /// every greedy-sampled token retains its top-N runner-up
  /// candidates, which the transcript editor surfaces as a
  /// tap-to-pick popover on ambiguous words.
  ///
  /// Useful for technical / proper-noun-heavy audio where the
  /// chosen token is plausible but wrong ("kubectl" → "cubicle")
  /// — pick the right candidate without retyping. UI caps at 5
  /// to keep memory tame at ~50 KB/min of audio; alts are most
  /// informative at 3.
  ///
  /// Beam search is excluded: its siblings are beam-conditional
  /// rather than greedy alternatives so showing them would
  /// mislead. Non-whisper backends ignore the field — none have
  /// an analog today.
  final int altN;

  /// §14.2d — Parakeet chunked transcription window (seconds).
  /// 0 = per-model default (typically 30 s). Setting a smaller value
  /// (e.g. 10–15 s) reduces peak memory on long files, at the cost
  /// of more segment-boundary artefacts. Only effective on Parakeet
  /// and other session backends via `transcribeChunked()`.
  final int chunkSeconds;

  /// §5.26.2 — Hotwords for contextual biasing. Comma-separated list
  /// of words/phrases the user expects in the audio. Delivered to
  /// LLM backends via setAsk() with "The following words may appear
  /// in the audio: …" phrasing (matching CrispASR CLI behavior).
  /// CTC backends: parakeet has native hotword support at the CLI
  /// level but not yet in the session C API — tracked upstream.
  final String hotwords;

  /// §11.2 — Hotwords boost factor for CTC/TDT backends. 0.0–5.0.
  /// Only effective when [hotwords] is non-empty.
  final double hotwordsBoost;

  /// §11.2 — Beam search width. Only effective when [beamSearch] is
  /// true. 0 = backend default (typically 5).
  final int beamSize;

  /// §10 — Preferred aligner model. Empty string means "auto" (the
  /// AlignerService picks the best available: language-matched wav2vec2
  /// first, then canary-ctc-aligner fallback). Non-empty values are
  /// catalog keys like 'canary-ctc-aligner-q4_k' or
  /// 'wav2vec2-xlsr-fr-q4_k' that resolve to an on-disk model path.
  final String alignerModel;

  /// §5.1.2 — Custom-vocabulary boost list. Persistent across runs;
  /// the user manages it in Advanced Options as removable chips
  /// (brand names, acronyms, technical jargon, people's names).
  ///
  /// How it biases decoding depends on the active backend class:
  ///   • Whisper / Moonshine → prepended to `initial_prompt` as
  ///     "Vocabulary: term1, term2, …. " before any user-supplied
  ///     prompt text, so the autoregressive decoder sees the
  ///     terms in its prefill context.
  ///   • LLM-backend (voxtral / qwen3 / granite / glm-asr / kyutai-
  ///     stt / gemma4-e2b / omniasr-llm / mimo-asr) → prepended to
  ///     `askPrompt` the same way; the LLM "knows" these terms
  ///     are likely to occur.
  ///   • CTC backends (parakeet / canary / cohere / firered /
  ///     wav2vec2 / fastconformer-ctc / omniasr-CTC) → ignored.
  ///     CTC has no token-prefill point; biasing would need an
  ///     external LM rescoring pass which we don't ship.
  ///
  /// The UI surfaces a "this backend can't bias vocabulary"
  /// note when the active model is CTC-class.
  final List<String> vocabulary;

  const AdvancedOptions({
    this.translate = false,
    this.beamSearch = false,
    this.initialPrompt = '',
    this.vad = false,
    this.restorePunctuation = false,
    this.targetLanguage = '',
    this.askPrompt = '',
    this.temperature = 0.0,
    this.sourceLanguage = '',
    this.bestOf = 1,
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
    this.vocabulary = const [],
    this.maxLen = 0,
    this.splitOnWord = false,
    this.splitOnPunct = false,
    this.grammarText = '',
    this.grammarRootRule = 'root',
    this.grammarPenalty = 100.0,
    this.sensitivityPreset = '',
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
    this.beamSize = 0,
    this.alignerModel = '',
    this.chunkSeconds = 0,
  });

  AdvancedOptions copyWith({
    bool? translate,
    bool? beamSearch,
    String? initialPrompt,
    bool? vad,
    bool? restorePunctuation,
    String? targetLanguage,
    String? askPrompt,
    double? temperature,
    String? sourceLanguage,
    int? bestOf,
    VadBackend? vadBackend,
    double? vadThreshold,
    int? vadMinSpeechMs,
    int? vadMinSilenceMs,
    int? vadSpeechPadMs,
    crispasr.DiarizeMethod? diarizeMethod,
    bool? enableSpeakerRecognition,
    crispasr.LidMethod? lidMethod,
    bool? tdrz,
    bool? tokenTimestamps,
    String? puncFamily,
    bool? lidUseGpu,
    bool? lidFlashAttn,
    int? nThreads,
    bool? asrUseGpu,
    bool? asrFlashAttn,
    int? asrNGpuLayers,
    List<String>? vocabulary,
    int? maxLen,
    bool? splitOnWord,
    bool? splitOnPunct,
    String? grammarText,
    String? grammarRootRule,
    double? grammarPenalty,
    String? sensitivityPreset,
    double? entropyThold,
    double? logprobThold,
    double? noSpeechThold,
    double? temperatureInc,
    bool? suppressNonSpeechTokens,
    String? suppressTokensRegex,
    bool? carryInitialPrompt,
    bool? enhanceAudio,
    double? transcribeWindowStartSec,
    double? transcribeWindowDurationSec,
    int? altN,
    String? hotwords,
    double? hotwordsBoost,
    int? beamSize,
    String? alignerModel,
    int? chunkSeconds,
  }) =>
      AdvancedOptions(
        translate: translate ?? this.translate,
        beamSearch: beamSearch ?? this.beamSearch,
        initialPrompt: initialPrompt ?? this.initialPrompt,
        vad: vad ?? this.vad,
        restorePunctuation: restorePunctuation ?? this.restorePunctuation,
        targetLanguage: targetLanguage ?? this.targetLanguage,
        askPrompt: askPrompt ?? this.askPrompt,
        temperature: temperature ?? this.temperature,
        sourceLanguage: sourceLanguage ?? this.sourceLanguage,
        bestOf: bestOf ?? this.bestOf,
        vadBackend: vadBackend ?? this.vadBackend,
        vadThreshold: vadThreshold ?? this.vadThreshold,
        vadMinSpeechMs: vadMinSpeechMs ?? this.vadMinSpeechMs,
        vadMinSilenceMs: vadMinSilenceMs ?? this.vadMinSilenceMs,
        vadSpeechPadMs: vadSpeechPadMs ?? this.vadSpeechPadMs,
        diarizeMethod: diarizeMethod ?? this.diarizeMethod,
        enableSpeakerRecognition:
            enableSpeakerRecognition ?? this.enableSpeakerRecognition,
        lidMethod: lidMethod ?? this.lidMethod,
        tdrz: tdrz ?? this.tdrz,
        tokenTimestamps: tokenTimestamps ?? this.tokenTimestamps,
        puncFamily: puncFamily ?? this.puncFamily,
        lidUseGpu: lidUseGpu ?? this.lidUseGpu,
        lidFlashAttn: lidFlashAttn ?? this.lidFlashAttn,
        nThreads: nThreads ?? this.nThreads,
        asrUseGpu: asrUseGpu ?? this.asrUseGpu,
        asrFlashAttn: asrFlashAttn ?? this.asrFlashAttn,
        asrNGpuLayers: asrNGpuLayers ?? this.asrNGpuLayers,
        vocabulary: vocabulary ?? this.vocabulary,
        maxLen: maxLen ?? this.maxLen,
        splitOnWord: splitOnWord ?? this.splitOnWord,
        splitOnPunct: splitOnPunct ?? this.splitOnPunct,
        grammarText: grammarText ?? this.grammarText,
        grammarRootRule: grammarRootRule ?? this.grammarRootRule,
        grammarPenalty: grammarPenalty ?? this.grammarPenalty,
        sensitivityPreset: sensitivityPreset ?? this.sensitivityPreset,
        entropyThold: entropyThold ?? this.entropyThold,
        logprobThold: logprobThold ?? this.logprobThold,
        noSpeechThold: noSpeechThold ?? this.noSpeechThold,
        temperatureInc: temperatureInc ?? this.temperatureInc,
        suppressNonSpeechTokens:
            suppressNonSpeechTokens ?? this.suppressNonSpeechTokens,
        suppressTokensRegex:
            suppressTokensRegex ?? this.suppressTokensRegex,
        carryInitialPrompt:
            carryInitialPrompt ?? this.carryInitialPrompt,
        enhanceAudio: enhanceAudio ?? this.enhanceAudio,
        transcribeWindowStartSec:
            transcribeWindowStartSec ?? this.transcribeWindowStartSec,
        transcribeWindowDurationSec:
            transcribeWindowDurationSec ?? this.transcribeWindowDurationSec,
        altN: altN ?? this.altN,
        hotwords: hotwords ?? this.hotwords,
        hotwordsBoost: hotwordsBoost ?? this.hotwordsBoost,
        beamSize: beamSize ?? this.beamSize,
        alignerModel: alignerModel ?? this.alignerModel,
        chunkSeconds: chunkSeconds ?? this.chunkSeconds,
      );

  /// Backends that accept a target-language hint different from the
  /// source — i.e. true speech-translation. Used by the UI to show /
  /// hide the target-lang dropdown.
  static const Set<String> translationCapableBackends = {
    'canary',
    'cohere',
    'voxtral',
    'voxtral4b',
    'qwen3',
    'whisper',
    // Granite Speech 4.1 family supports speech-translation too.
    'granite',
    'granite-4.1',
    'granite-4.1-plus',
    'granite-4.1-nar',
  };

  /// Backends that benefit from a sticky source-language override.
  /// Strict superset of [translationCapableBackends] — every backend
  /// that can translate also accepts a source-lang pin, plus the
  /// multilingual ASR backends that don't translate but auto-detect
  /// language and can be wrong on short / noisy clips.
  ///
  /// English-only backends are deliberately excluded (the dropdown
  /// would be useless): `wav2vec2-large-xlsr-53-english`,
  /// `fastconformer-ctc-en`, `parakeet-tdt-0.6b-v3` (English-only
  /// CTC head), kokoro / orpheus / vibevoice / chatterbox / indextts
  /// (TTS — no source-lang concept), `firered-punc` / `fullstop-punc`
  /// (post-processors), pyannote / silero-vad (non-ASR).
  static const Set<String> sourceLanguageCapableBackends = {
    // Translation-capable (already a superset entry).
    'canary',
    'cohere',
    'voxtral',
    'voxtral4b',
    'qwen3',
    'whisper',
    'granite',
    'granite-4.1',
    'granite-4.1-plus',
    'granite-4.1-nar',
    // Multilingual ASR — CLI accepts `-sl` and the per-call API
    // honours `language=`; pinning beats autodetect on short clips.
    'parakeet',
    'parakeet-ctc',
    'mimo-asr',
    'firered-asr',
    'kyutai-stt',
    'glm-asr',
    'gemma4-e2b',
    'omniasr-llm',
    'omniasr-llm-unlimited',
    'moonshine',
    'moss-audio',
    'moss-diarize',
    'sensevoice',
    'funasr',
    'paraformer',
    'vibevoice',
  };

  /// Backends that accept a free-form Q&A prompt (instruct-tuned
  /// audio-LLM). Used by the UI to show / hide the ask field.
  static const Set<String> askCapableBackends = {
    'voxtral',
    'voxtral4b',
    'qwen3',
    'granite',
    'granite-4.1',
    'granite-4.1-plus',
    'granite-4.1-nar',
    'glm-asr',
    'gemma4-e2b',
    'mimo-asr',
    'moss-audio',
    'moss-diarize',
  };

  /// Backends that honour `crispasr_session_set_temperature` per the
  /// CrispASR doc comment. Other session backends silently no-op
  /// (rc=-2) but the slider has nothing to offer them, so hide it.
  /// Whisper isn't in the list — it has its own temperature fallback
  /// inside whisper.cpp's TranscribeOptions.
  static const Set<String> temperatureCapableBackends = {
    'canary',
    'cohere',
    'parakeet',
    'moonshine',
    'kyutai-stt',
    // Granite + Voxtral + Qwen3 + GLM-ASR + Gemma4 all expose
    // `--temperature` in the CrispASR CLI.
    'granite',
    'granite-4.1',
    'granite-4.1-plus',
    'voxtral',
    'voxtral4b',
    'qwen3',
    'glm-asr',
    'gemma4-e2b',
    'omniasr-llm',
    'omniasr-llm-unlimited',
    'mimo-asr',
    'moss-audio',
  };

  /// §5.1.2 — Backends whose vocabulary bias is delivered via the
  /// whisper-style `initial_prompt` field (encoder-decoder
  /// autoregressive). Decoder sees the vocabulary terms as
  /// prefill context before any audio tokens.
  static const Set<String> vocabularyViaInitialPromptBackends = {
    'whisper',
    'moonshine',
  };

  /// §5.1.2 — Backends whose vocabulary bias is delivered via the
  /// LLM `askPrompt` (`setAsk`) field. These are audio-LLM
  /// backends — the prompt prefixes the user's actual question
  /// (or stands alone if no question was supplied) so the LLM
  /// knows which terms to expect.
  static const Set<String> vocabularyViaAskPromptBackends = {
    'voxtral',
    'voxtral4b',
    'qwen3',
    'granite',
    'granite-4.1',
    'granite-4.1-plus',
    'granite-4.1-nar',
    'glm-asr',
    'kyutai-stt',
    'gemma4-e2b',
    'omniasr-llm',
    'omniasr-llm-unlimited',
    'mimo-asr',
    'moss-audio',
  };

  /// Convenience union — every backend that supports vocabulary
  /// biasing via SOME mechanism. UI uses this to enable / disable
  /// the vocabulary chip-list. CTC-style backends (parakeet,
  /// canary, cohere, fastconformer-ctc, wav2vec2, firered-asr,
  /// omniasr-CTC) are deliberately excluded — no token-prefill
  /// point in greedy/beam CTC decoding.
  static Set<String> get vocabularyCapableBackends => {
        ...vocabularyViaInitialPromptBackends,
        ...vocabularyViaAskPromptBackends,
      };

  /// §5.1.2 prompt-merge: render the user-managed vocabulary list
  /// + an existing user prompt into a single string the active
  /// backend can consume. Returns `existing` unchanged when the
  /// vocabulary is empty OR the backend is CTC (caller should
  /// gate, but we double-check here so a stale capability set
  /// can't cause a stray prefix to leak through).
  ///
  /// Format: `"Vocabulary: term1, term2, …. <existing>"`
  ///   • Empty existing → just `"Vocabulary: …. "` (the trailing
  ///     space leaves room for the model's decode to continue
  ///     cleanly without running into the period).
  ///   • Empty vocabulary → existing unchanged.
  ///
  /// Pure function; trivially unit-testable.
  static String mergeVocabularyIntoPrompt({
    required String backend,
    required List<String> vocabulary,
    required String existing,
  }) {
    if (vocabulary.isEmpty) return existing;
    final trimmedTerms = vocabulary
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (trimmedTerms.isEmpty) return existing;
    if (!vocabularyCapableBackends.contains(backend)) return existing;
    final hint = 'Vocabulary: ${trimmedTerms.join(', ')}. ';
    return existing.isEmpty ? hint : '$hint$existing';
  }

  /// §5.26.2 — Backends that support hotword biasing. For LLM backends
  /// hotwords are injected into the ask prompt. Matches CrispASR CLI
  /// behavior where `--hotwords` prepends "The following words may
  /// appear in the audio: …" to the system prompt.
  static const Set<String> hotwordsCapableBackends = {
    // LLM backends — hotwords via ask-prompt injection
    'voxtral',
    'voxtral4b',
    'qwen3',
    'granite',
    'granite-4.1',
    'granite-4.1-plus',
    'granite-4.1-nar',
    'glm-asr',
    'gemma4-e2b',
    'omniasr-llm',
    'omniasr-llm-unlimited',
    'mimo-asr',
    'moss-audio',
    'lfm2-audio',
    'mini-omni2',
    // Encoder-decoder backends — hotwords via initial_prompt injection
    'whisper',
    'moonshine',
    'moonshine-streaming',
  };

  /// §5.26.2 — Merge hotwords into the ask/initial prompt so the
  /// decoder is biased toward these terms. Matches the CrispASR CLI
  /// phrasing: "The following words may appear in the audio: …"
  ///
  /// Pure function; trivially unit-testable.
  static String mergeHotwordsIntoPrompt({
    required String backend,
    required String hotwords,
    required String existing,
  }) {
    final trimmed = hotwords.trim();
    if (trimmed.isEmpty) return existing;
    if (!hotwordsCapableBackends.contains(backend)) return existing;
    final hint =
        'The following words may appear in the audio: $trimmed. ';
    return existing.isEmpty ? hint : '$hint$existing';
  }
}

final advancedOptionsProvider =
    StateProvider<AdvancedOptions>((_) => const AdvancedOptions());

/// Collapsible block shown inside Advanced Options on the transcription
/// screen. Visible only when the active engine is CrispASR (the only one
/// that can actually use these knobs).
/// Catalogue keys the forced-aligner picker offers, mapped to their
/// display labels. Keys must resolve through
/// `ModelService.lookupDefinition` — `aligner_override_test.dart`
/// guards that, because a key with no catalogue entry can never be
/// resolved to a file and would silently behave as "Auto".
const Map<String, String> alignerModelLabels = <String, String>{
  'canary-ctc-aligner-q4_k': 'Canary CTC Aligner',
  'wav2vec2-xlsr-fr-q4_k': 'Wav2Vec2 FR (French)',
  'wav2vec2-xlsr-es-q4_k': 'Wav2Vec2 ES (Spanish)',
  'wav2vec2-xlsr-it-q4_k': 'Wav2Vec2 IT (Italian)',
  'wav2vec2-xlsr-ja-q4_k': 'Wav2Vec2 JA (Japanese)',
  'wav2vec2-xlsr-zh-q4_k': 'Wav2Vec2 ZH (Chinese)',
  'wav2vec2-xlsr-nl-q4_k': 'Wav2Vec2 NL (Dutch)',
  'wav2vec2-xlsr-pt-q4_k': 'Wav2Vec2 PT (Portuguese)',
  'wav2vec2-xlsr-ar-q4_k': 'Wav2Vec2 AR (Arabic)',
  'wav2vec2-xlsr-cs-q4_k': 'Wav2Vec2 CS (Czech)',
  'wav2vec2-xlsr-uk-q4_k': 'Wav2Vec2 UK (Ukrainian)',
};

class AdvancedDecodingSection extends ConsumerStatefulWidget {
  const AdvancedDecodingSection({super.key});

  @override
  ConsumerState<AdvancedDecodingSection> createState() =>
      _AdvancedDecodingSectionState();
}

class _AdvancedDecodingSectionState
    extends ConsumerState<AdvancedDecodingSection> {
  bool _expanded = false;
  late final TextEditingController _promptController;
  late final TextEditingController _askController;
  late final TextEditingController _vocabAddController;

  /// Which aligner catalogue keys are actually on disk. Empty until
  /// [_scanAlignerAvailability] finishes; [_alignerScanDone] keeps the
  /// dropdown from claiming "not downloaded" before we've looked.
  Set<String> _downloadedAligners = const <String>{};
  bool _alignerScanDone = false;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(advancedOptionsProvider);
    _promptController = TextEditingController(text: initial.initialPrompt);
    _askController = TextEditingController(text: initial.askPrompt);
    _vocabAddController = TextEditingController();
    _scanAlignerAvailability();
  }

  /// Probe the models dir once for each aligner the picker offers so
  /// undownloaded entries can be marked. Availability is a hint, not a
  /// gate — a failed probe just leaves the labels unsuffixed.
  Future<void> _scanAlignerAvailability() async {
    try {
      final svc = ref.read(modelServiceProvider);
      await svc.initialize();
      final found = <String>{};
      for (final key in alignerModelLabels.keys) {
        final path = await svc.getWhisperCppModelPath(key);
        if (path != null) found.add(key);
      }
      if (!mounted) return;
      setState(() {
        _downloadedAligners = found;
        _alignerScanDone = true;
      });
    } catch (_) {
      // Leave _alignerScanDone false — no markers rather than wrong ones.
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _askController.dispose();
    _vocabAddController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final opts = ref.watch(advancedOptionsProvider);

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 0),
      initiallyExpanded: _expanded,
      onExpansionChanged: (v) => setState(() => _expanded = v),
      // §35 — the section header carries the "what am I even looking
      // at" explanation. Tooltip shows on hover (desktop) and on
      // long-press (touch), so the block is discoverable without
      // spending vertical space on a permanent paragraph.
      title: Tooltip(
        message: l.advancedSectionTooltip,
        child: Row(
          children: [
            const Icon(Icons.tune, size: 18),
            const SizedBox(width: 8),
            Text(l.advancedSection,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedVadTrim),
          subtitle: Text(l.advancedVadTrimSubtitle,
              style: const TextStyle(fontSize: 11)),
          value: opts.vad,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(vad: v),
        ),
        // VAD backend + threshold + duration sliders. Only meaningful
        // when VAD is enabled; collapse otherwise.
        if (opts.vad) _buildVadTuneRows(context, opts),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedTranslate),
          subtitle: Text(l.advancedTranslateSubtitle,
              style: const TextStyle(fontSize: 11)),
          value: opts.translate,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(translate: v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedBeamSearch),
          subtitle: Text(l.advancedBeamSearchSubtitle,
              style: const TextStyle(fontSize: 11)),
          value: opts.beamSearch,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(beamSearch: v),
        ),
        if (opts.beamSearch)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l.advancedBeamSize(opts.beamSize)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.advancedBeamSizeHelper,
                    style: const TextStyle(fontSize: 11)),
                Slider(
                  value: opts.beamSize.toDouble(),
                  min: 0,
                  max: 20,
                  divisions: 20,
                  label: opts.beamSize == 0
                      ? 'default'
                      : opts.beamSize.toString(),
                  onChanged: (v) =>
                      ref.read(advancedOptionsProvider.notifier).state =
                          opts.copyWith(beamSize: v.round()),
                ),
              ],
            ),
          ),
        // §14.2d — Chunked transcription window for Parakeet and other
        // session backends. 0 = per-model default. Smaller values reduce
        // peak memory on long files.
        _buildChunkSecondsRow(context, opts),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedRestorePunctuation),
          subtitle: Text(l.advancedRestorePunctuationSubtitle,
              style: const TextStyle(fontSize: 11)),
          value: opts.restorePunctuation,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(restorePunctuation: v),
        ),
        // Best-of-N slider. Works on every backend per CrispASR
        // §60o: Whisper consumes it as `wparams.greedy.best_of`;
        // other backends run N decodes externally and pick the
        // highest-mean-confidence result. Cost is N× per-call
        // decode time, so the slider is always visible but
        // defaults to 1 (single decode).
        _buildBestOfRow(context, opts),
        // Decoder temperature slider. Hidden on backends that don't
        // honour `setTemperature` (whisper, mimo-asr, wav2vec2, …) so
        // the panel stays uncluttered for the common case.
        _buildTemperatureRow(context, opts),
        // Source-language picker — shown for every multilingual
        // backend, not just translation-capable ones. Pinning a source
        // wins over the global language dropdown / native LID, useful
        // when autodetect is unreliable on short / noisy clips. Hidden
        // on English-only backends (wav2vec2 / fastconformer-ctc).
        _buildSourceLanguageRow(context, opts),
        // Target-language picker for translation. Only shown when the
        // currently-loaded model's backend advertises true speech
        // translation (canary, voxtral, qwen3, cohere, whisper). The
        // empty default means "no translation — transcribe verbatim".
        _buildTargetLanguageRow(context, opts),
        // Audio Q&A prompt. Only shown when the currently-loaded
        // model's backend is an instruct-tuned audio-LLM (voxtral,
        // voxtral4b, qwen3-asr). Non-empty answer-mode replaces the
        // verbatim transcription with the LLM's response to the prompt.
        _buildAskRow(context, opts),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextField(
            controller: _promptController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: l.advancedInitialPrompt,
              hintText: l.advancedInitialPromptHint,
              // The hint only shows an example; the helper says what
              // the field IS and which backends read it. helperMaxLines
              // is required — the default of 1 would ellipsise it.
              helperText: l.advancedInitialPromptHelper,
              helperMaxLines: 4,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
                opts.copyWith(initialPrompt: v),
          ),
        ),
        // §5.1.2 — Custom vocabulary chip list. Always visible;
        // the helper text changes to a "backend can't bias
        // vocabulary" note when the active backend is CTC-class.
        _buildVocabularyRow(context, opts),
        // §5.26.2 — Hotwords for contextual biasing.
        _buildHotwordsRow(context, opts),
        _buildHotwordsBoostRow(context, opts),
        // §5.1.10 — RNNoise audio enhancement pre-step.
        // Backend-agnostic; the transcribe screen pipes loaded
        // PCM through crispasr.enhanceAudioRnnoise(...) before
        // the §5.8 window slice / dispatch. Off by default;
        // pre-0.5.12 libcrispasr falls through silently.
        _buildEnhanceAudioRow(context, opts),
        // Everything past this point is behind one more tap.
        //
        // AdvancedOptions carries 111 fields. Every one of them earns its
        // place for someone, and showing all of them to a first-run tester
        // is how a usable app reads as an unusable one. The split is a
        // boundary rather than a reordering: nothing moved except the
        // denoise switch, which is a plain quality toggle and belongs with
        // the common set. Reorganising a working panel the week before a
        // beta is how you ship new bugs.
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Tooltip(
            message: l.advancedAllOptionsTooltip,
            child: Row(
              children: [
                const Icon(Icons.settings_suggest_outlined, size: 16),
                const SizedBox(width: 8),
                Text(l.advancedAllOptions,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          children: [
          // LID method picker — visible only when the global language
          // dropdown is "auto" + active backend lacks native LID. We
          // can't see those preconditions here, so always show it; the
          // engine ignores it on backends that already auto-detect.
          _buildLidMethodRow(context, opts),
          // Diarisation method picker — only meaningful when diarisation
          // is enabled (separate toggle on the screen above). Show it
          // unconditionally; the screen-level diarize flag gates whether
          // anything happens.
          _buildDiarizationMethodRow(context, opts),
          // §5.8.1 — Resolve diarised cluster labels to enrolled
          // speakers via TitaNet. Hidden when the diarisation method is
          // `energy` (stereo channel IDs already disambiguate speakers).
          _buildSpeakerRecognitionRow(context, opts),
          // Whisper-only tdrz toggle (tinydiarize). Hidden on session
          // backends because the model file format differs.
          _buildTdrzRow(context, opts),
          // Token-level timestamps (whisper DTW). Useful when subtitle
          // tooling consumes per-token timing instead of segments.
          _buildTokenTimestampsRow(context, opts),
          // §10 — Forced-aligner model picker. Auto selects a language-
          // matched wav2vec2 or canary-ctc-aligner; users can override.
          _buildAlignerModelRow(context, opts),
          // §5.1.11 — Top-N alternative-candidate capture (Whisper only).
          // Powers the transcript editor's tap-to-pick popover on
          // ambiguous words. Hidden on non-whisper backends.
          _buildAltNRow(context, opts),
          // §5.8 — whisper subtitle formatting (tokens-per-segment
          // cap + split-on-word). Pair is whisper-only; collapses
          // on session-style backends. SplitOnWord additionally
          // hides itself when maxLen == 0 to avoid a no-op toggle.
          _buildMaxLenRow(context, opts),
          _buildSplitOnWordRow(context, opts),
          _buildSplitOnPunctRow(context, opts),
          // §5.8 — GBNF grammar-constrained sampling (Whisper-only).
          // Multi-line TextField for the GBNF source plus a slider
          // for grammar_penalty. Empty text means "no constraint";
          // the transcription worker only calls setGrammar when text
          // is non-empty so other backends don't take an extra trip.
          _buildGrammarRows(context, opts),
          // Whisper decoder-fallback thresholds (Whisper-only).
          // Five-slider ExpansionTile — defaults reproduce
          // whisper_full_default_params exactly so leaving every
          // slider alone matches stock whisper.cpp. Power-user
          // knob; collapses when defaults are in effect.
          _buildFallbackThresholdsRow(context, opts),
          // Whisper text-suppression + prompt-carry extras
          // (Whisper-only). 3 controls — 2 switches + 1 regex
          // text field. Reproduces CLI's --suppress-nst /
          // --suppress-regex / --carry-initial-prompt.
          _buildWhisperDecodeExtrasRow(context, opts),
          // Punctuation family picker — only visible when "Restore
          // punctuation" is on AND the user has more than one family on
          // disk. Otherwise PuncService auto-picks whatever it finds.
          if (opts.restorePunctuation) _buildPuncFamilyRow(context, opts),
          // Transcribe window — CrispASR CLI's --offset-t / --duration
          // equivalent. Backend-agnostic; the screen slices the PCM
          // before dispatch and the existing startOffsetSec shift
          // brings segment timestamps back to absolute file time.
          _buildTranscribeWindowRow(context, opts),
          // Performance — LID accelerator + thread count. Honoured by
          // crispasr_detect_language_pcm directly. ASR-side perf flags
          // need to be set at session-open time and aren't runtime-
          // tunable, so they aren't surfaced here.
          _buildPerfRows(context, opts),
          ],
        ),
      ],
    );
  }

  Widget _buildPerfRows(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(l.advancedPerfHeader,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedAsrUseGpu),
          subtitle: Text(l.advancedAsrUseGpuSubtitle,
              style: const TextStyle(fontSize: 11)),
          value: opts.asrUseGpu,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(asrUseGpu: v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedAsrFlashAttn),
          subtitle: Text(l.advancedAsrFlashAttnSubtitle,
              style: const TextStyle(fontSize: 11)),
          value: opts.asrFlashAttn,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(asrFlashAttn: v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                opts.asrNGpuLayers < 0
                    ? l.advancedAsrNGpuLayersAuto
                    : l.advancedAsrNGpuLayers(opts.asrNGpuLayers),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Slider(
                // Slider doesn't support negative-as-sentinel cleanly,
                // so we map -1 → 0 on the slider and re-encode on
                // commit: 0 = "auto / max", 1..N = explicit bound.
                value: (opts.asrNGpuLayers < 0
                        ? 0
                        : opts.asrNGpuLayers.clamp(0, 128))
                    .toDouble(),
                min: 0,
                max: 128,
                divisions: 128,
                label: opts.asrNGpuLayers < 0
                    ? 'auto'
                    : opts.asrNGpuLayers.toString(),
                onChanged: (v) {
                  final n = v.round();
                  // Map slider 0 back to -1 (auto).
                  ref.read(advancedOptionsProvider.notifier).state =
                      opts.copyWith(asrNGpuLayers: n == 0 ? -1 : n);
                },
              ),
              Text(l.advancedAsrNGpuLayersHelper,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedLidUseGpu),
          subtitle: Text(l.advancedLidUseGpuSubtitle,
              style: const TextStyle(fontSize: 11)),
          value: opts.lidUseGpu,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(lidUseGpu: v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedLidFlashAttn),
          subtitle: Text(l.advancedLidFlashAttnSubtitle,
              style: const TextStyle(fontSize: 11)),
          value: opts.lidFlashAttn,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(lidFlashAttn: v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.advancedNThreads(opts.nThreads),
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              Slider(
                value: opts.nThreads.toDouble(),
                min: 1,
                max: 16,
                divisions: 15,
                label: opts.nThreads.toString(),
                onChanged: (v) =>
                    ref.read(advancedOptionsProvider.notifier).state =
                        opts.copyWith(nThreads: v.round()),
              ),
              Text(l.advancedNThreadsHelper,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVadTuneRows(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: DropdownButtonFormField<VadBackend>(
            decoration: InputDecoration(
              labelText: l.advancedVadBackend,
              helperText: l.advancedVadBackendHelper,
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            initialValue: opts.vadBackend,
            items: [
              DropdownMenuItem(
                  value: VadBackend.silero, child: Text(l.advancedVadBackendSilero)),
              DropdownMenuItem(
                  value: VadBackend.firered,
                  child: Text(l.advancedVadBackendFirered)),
              DropdownMenuItem(
                  value: VadBackend.marblenet,
                  child: Text(l.advancedVadBackendMarblenet)),
              DropdownMenuItem(
                  value: VadBackend.whisperEncDec,
                  child: Text(l.advancedVadBackendWhisperEncDec)),
            ],
            onChanged: (v) {
              if (v == null) return;
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(vadBackend: v);
            },
          ),
        ),
        _sliderRow(
          label: l.advancedVadThreshold(opts.vadThreshold.toStringAsFixed(2)),
          value: opts.vadThreshold,
          min: 0.05,
          max: 0.95,
          divisions: 18,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(vadThreshold: v),
          helper: l.advancedVadThresholdHelper,
        ),
        _sliderRow(
          label: l.advancedVadMinSpeech(opts.vadMinSpeechMs),
          value: opts.vadMinSpeechMs.toDouble(),
          min: 50,
          max: 2000,
          divisions: 39,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(vadMinSpeechMs: v.round()),
          helper: l.advancedVadMinSpeechHelper,
        ),
        _sliderRow(
          label: l.advancedVadMinSilence(opts.vadMinSilenceMs),
          value: opts.vadMinSilenceMs.toDouble(),
          min: 50,
          max: 2000,
          divisions: 39,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(vadMinSilenceMs: v.round()),
          helper: l.advancedVadMinSilenceHelper,
        ),
        _sliderRow(
          label: l.advancedVadSpeechPad(opts.vadSpeechPadMs),
          value: opts.vadSpeechPadMs.toDouble(),
          min: 0,
          max: 500,
          divisions: 50,
          onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(vadSpeechPadMs: v.round()),
          helper: l.advancedVadSpeechPadHelper,
        ),
      ],
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
          if (helper != null)
            Text(helper,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLidMethodRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<crispasr.LidMethod>(
        decoration: InputDecoration(
          labelText: l.advancedLidMethod,
          helperText: l.advancedLidMethodHelper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        initialValue: opts.lidMethod,
        items: [
          DropdownMenuItem(
              value: crispasr.LidMethod.whisper,
              child: Text(l.advancedLidMethodWhisper)),
          DropdownMenuItem(
              value: crispasr.LidMethod.silero,
              child: Text(l.advancedLidMethodSilero)),
          DropdownMenuItem(
              value: crispasr.LidMethod.ecapa,
              child: Text(l.advancedLidMethodEcapa)),
          DropdownMenuItem(
              value: crispasr.LidMethod.firered,
              child: Text(l.advancedLidMethodFirered)),
        ],
        onChanged: (v) {
          if (v == null) return;
          ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(lidMethod: v);
        },
      ),
    );
  }

  Widget _buildDiarizationMethodRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<crispasr.DiarizeMethod>(
        // Keyed so a change made in the diarisation card (same state)
        // is reflected here — FormField reads initialValue once.
        key: ValueKey<String>('adv-diarize-method-${opts.diarizeMethod.name}'),
        decoration: InputDecoration(
          labelText: l.advancedDiarizeMethod,
          helperText: l.advancedDiarizeMethodHelper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        initialValue: opts.diarizeMethod,
        items: [
          DropdownMenuItem(
              value: crispasr.DiarizeMethod.vadTurns,
              child: Text(l.advancedDiarizeVadTurns)),
          DropdownMenuItem(
              value: crispasr.DiarizeMethod.pyannote,
              child: Text(l.advancedDiarizePyannote)),
          // #324 / §35 — foxNose is the only method the library lets us
          // bound with min/max speakers, and the diarisation card can
          // select it; it has to be in this picker's value domain too,
          // or a card-picked value would have no matching item here.
          DropdownMenuItem(
              value: crispasr.DiarizeMethod.foxNose,
              child: Text(l.advancedDiarizeFoxnose)),
          DropdownMenuItem(
              value: crispasr.DiarizeMethod.energy,
              child: Text(l.advancedDiarizeEnergy)),
          DropdownMenuItem(
              value: crispasr.DiarizeMethod.xcorr,
              child: Text(l.advancedDiarizeXcorr)),
        ],
        onChanged: (v) {
          if (v == null) return;
          ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(diarizeMethod: v);
        },
      ),
    );
  }

  Widget _buildSpeakerRecognitionRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (opts.diarizeMethod == crispasr.DiarizeMethod.energy) {
      return const SizedBox.shrink();
    }
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.advancedSpeakerRecognition),
      subtitle: Text(l.advancedSpeakerRecognitionSubtitle,
          style: const TextStyle(fontSize: 11)),
      value: opts.enableSpeakerRecognition,
      onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
          opts.copyWith(enableSpeakerRecognition: v),
    );
  }

  Widget _buildTdrzRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (_activeBackend() != 'whisper') return const SizedBox.shrink();
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.advancedTdrz),
      subtitle: Text(l.advancedTdrzSubtitle,
          style: const TextStyle(fontSize: 11)),
      value: opts.tdrz,
      onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
          opts.copyWith(tdrz: v),
    );
  }

  /// §5.8 subtitle formatting — soft cap on tokens per
  /// segment + split-on-word toggle. Whisper-only; the entire
  /// pair collapses on non-whisper backends because the
  /// session-style decoders ignore the flags.
  Widget _buildMaxLenRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (_activeBackend() != 'whisper') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.advancedMaxLen(opts.maxLen),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: 200,
            divisions: 40,
            value: opts.maxLen.clamp(0, 200).toDouble(),
            label: opts.maxLen == 0
                ? l.advancedMaxLenOff
                : opts.maxLen.toString(),
            onChanged: (v) => ref
                .read(advancedOptionsProvider.notifier)
                .state = opts.copyWith(maxLen: v.round()),
          ),
          Text(l.advancedMaxLenSubtitle,
              style:
                  const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildSplitOnWordRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (_activeBackend() != 'whisper') return const SizedBox.shrink();
    // Pointless toggle when maxLen=0 — gate on it so the user
    // doesn't fiddle with a no-op switch.
    if (opts.maxLen == 0) return const SizedBox.shrink();
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.advancedSplitOnWord),
      subtitle: Text(l.advancedSplitOnWordSubtitle,
          style: const TextStyle(fontSize: 11)),
      value: opts.splitOnWord,
      onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
          opts.copyWith(splitOnWord: v),
    );
  }

  /// §5.8 — split at sentence-ending punctuation. Works on any
  /// backend (Dart-side post-processing, not a whisper wparams field).
  Widget _buildSplitOnPunctRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.advancedSplitOnPunct),
      subtitle: Text(l.advancedSplitOnPunctSubtitle,
          style: const TextStyle(fontSize: 11)),
      value: opts.splitOnPunct,
      onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
          opts.copyWith(splitOnPunct: v),
    );
  }

  /// §5.8 — GBNF grammar-constrained sampling. Whisper-only;
  /// renders as an ExpansionTile so the multi-line TextField + the
  /// penalty slider don't dominate the Advanced section for users
  /// who aren't doing structured output.
  Widget _buildGrammarRows(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (_activeBackend() != 'whisper') return const SizedBox.shrink();
    final hasGrammar = opts.grammarText.trim().isNotEmpty;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      // Initially expanded only when the user already has a grammar
      // typed in — otherwise the tile stays collapsed to keep the
      // Advanced section scannable.
      initiallyExpanded: hasGrammar,
      title: Text(l.advancedGrammarTitle),
      subtitle: Text(
        hasGrammar ? l.advancedGrammarSubtitleActive : l.advancedGrammarSubtitle,
        style: const TextStyle(fontSize: 11),
      ),
      children: [
        const SizedBox(height: 4),
        TextFormField(
          initialValue: opts.grammarText,
          minLines: 3,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            labelText: l.advancedGrammarTextLabel,
            hintText:
                'root ::= "{" key ":" value "}"\nkey   ::= "\\"" [a-zA-Z]+ "\\""\nvalue ::= [0-9]+',
            helperText: l.advancedGrammarTextHelper,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) {
            ref.read(advancedOptionsProvider.notifier).state =
                opts.copyWith(grammarText: v);
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: opts.grammarRootRule,
          decoration: InputDecoration(
            labelText: l.advancedGrammarRootRule,
            helperText: l.advancedGrammarRootRuleHelper,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) {
            ref.read(advancedOptionsProvider.notifier).state =
                opts.copyWith(
                    grammarRootRule: v.trim().isEmpty ? 'root' : v.trim());
          },
        ),
        const SizedBox(height: 8),
        Text(
            l.advancedGrammarPenalty(
                opts.grammarPenalty.toStringAsFixed(1)),
            style: Theme.of(context).textTheme.bodySmall),
        Slider(
          min: 0.0,
          max: 200.0,
          divisions: 40,
          value: opts.grammarPenalty.clamp(0.0, 200.0),
          label: opts.grammarPenalty.toStringAsFixed(1),
          onChanged: (v) =>
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(grammarPenalty: v),
        ),
        Text(l.advancedGrammarPenaltyHelper,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }

  /// Whisper text-suppression + prompt-carry extras. Reproduces
  /// the CLI's --suppress-nst / --suppress-regex /
  /// --carry-initial-prompt flags. Whisper-only.
  Widget _buildWhisperDecodeExtrasRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (_activeBackend() != 'whisper') return const SizedBox.shrink();
    final atDefaults = !opts.suppressNonSpeechTokens &&
        opts.suppressTokensRegex.isEmpty &&
        !opts.carryInitialPrompt;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: !atDefaults,
      title: Text(l.advancedWhisperDecodeExtrasTitle),
      subtitle: Text(
        atDefaults
            ? l.advancedWhisperDecodeExtrasSubtitle
            : l.advancedWhisperDecodeExtrasSubtitleActive,
        style: const TextStyle(fontSize: 11),
      ),
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedSuppressNonSpeechTokens),
          subtitle: Text(l.advancedSuppressNonSpeechTokensHelper,
              style: const TextStyle(fontSize: 11)),
          value: opts.suppressNonSpeechTokens,
          onChanged: (v) =>
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(suppressNonSpeechTokens: v),
        ),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: opts.suppressTokensRegex,
          decoration: InputDecoration(
            labelText: l.advancedSuppressTokensRegex,
            helperText: l.advancedSuppressTokensRegexHelper,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) =>
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(suppressTokensRegex: v),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.advancedCarryInitialPrompt),
          subtitle: Text(l.advancedCarryInitialPromptHelper,
              style: const TextStyle(fontSize: 11)),
          value: opts.carryInitialPrompt,
          onChanged: (v) =>
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(carryInitialPrompt: v),
        ),
      ],
    );
  }

  /// §5.1.10 — RNNoise audio enhancement pre-step. One switch,
  /// backend-agnostic. The transcribe paths run RNNoise on the
  /// loaded 16 kHz PCM before any window slicing / dispatch.
  /// Pre-0.5.12 libcrispasr builds raise UnsupportedError; the
  /// caller catches that and falls through to the un-enhanced
  /// PCM so toggling the switch never breaks transcription.
  Widget _buildEnhanceAudioRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.advancedEnhanceAudio),
      subtitle: Text(l.advancedEnhanceAudioHelper,
          style: const TextStyle(fontSize: 11)),
      value: opts.enhanceAudio,
      onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
          opts.copyWith(enhanceAudio: v),
    );
  }

  /// Whisper decoder-fallback thresholds. Five sliders mapped
  /// 1-to-1 onto wparams.*_thold + wparams.temperature_inc.
  /// Collapsed by default so the tile doesn't dominate the
  /// section for users who aren't tuning whisper.
  Widget _buildFallbackThresholdsRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (_activeBackend() != 'whisper') return const SizedBox.shrink();
    final atDefaults = opts.entropyThold == 2.4 &&
        opts.logprobThold == -1.0 &&
        opts.noSpeechThold == 0.6 &&
        opts.temperatureInc == 0.2;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      // Initially expanded when the user already overrode any
      // threshold — that signals they care; otherwise stay
      // collapsed to keep the section scannable.
      initiallyExpanded: !atDefaults,
      title: Text(l.advancedFallbackThresholdsTitle),
      subtitle: Text(
        atDefaults
            ? l.advancedFallbackThresholdsSubtitle
            : l.advancedFallbackThresholdsSubtitleActive,
        style: const TextStyle(fontSize: 11),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.advancedSensitivityPreset,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: '', label: Text(l.advancedSensitivityManual)),
                  ButtonSegment(
                      value: 'conservative',
                      label: Text(l.advancedSensitivityConservative)),
                  ButtonSegment(
                      value: 'balanced',
                      label: Text(l.advancedSensitivityBalanced)),
                  ButtonSegment(
                      value: 'aggressive',
                      label: Text(l.advancedSensitivityAggressive)),
                ],
                selected: {opts.sensitivityPreset},
                onSelectionChanged: (sel) =>
                    ref.read(advancedOptionsProvider.notifier).state =
                        opts.copyWith(sensitivityPreset: sel.first),
              ),
              const SizedBox(height: 4),
              Text(l.advancedSensitivityPresetHelper,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        _fallbackSlider(
          context: context,
          label: l.advancedEntropyThold(opts.entropyThold.toStringAsFixed(2)),
          helper: l.advancedEntropyTholdHelper,
          value: opts.entropyThold,
          min: 0.0,
          max: 5.0,
          divisions: 50,
          onChanged: (v) =>
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(entropyThold: v),
        ),
        _fallbackSlider(
          context: context,
          label: l.advancedLogprobThold(opts.logprobThold.toStringAsFixed(2)),
          helper: l.advancedLogprobTholdHelper,
          value: opts.logprobThold,
          min: -5.0,
          max: 0.0,
          divisions: 50,
          onChanged: (v) =>
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(logprobThold: v),
        ),
        _fallbackSlider(
          context: context,
          label: l.advancedNoSpeechThold(
              opts.noSpeechThold.toStringAsFixed(2)),
          helper: l.advancedNoSpeechTholdHelper,
          value: opts.noSpeechThold,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          onChanged: (v) =>
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(noSpeechThold: v),
        ),
        _fallbackSlider(
          context: context,
          label: opts.temperatureInc == 0.0
              ? l.advancedTemperatureIncDisabled
              : l.advancedTemperatureInc(
                  opts.temperatureInc.toStringAsFixed(2)),
          helper: l.advancedTemperatureIncHelper,
          value: opts.temperatureInc,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          onChanged: (v) =>
              ref.read(advancedOptionsProvider.notifier).state =
                  opts.copyWith(temperatureInc: v),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            icon: const Icon(Icons.restart_alt, size: 16),
            label: Text(l.advancedFallbackThresholdsReset),
            onPressed: () =>
                ref.read(advancedOptionsProvider.notifier).state =
                    opts.copyWith(
                        entropyThold: 2.4,
                        logprobThold: -1.0,
                        noSpeechThold: 0.6,
                        temperatureInc: 0.2),
          ),
        ),
      ],
    );
  }

  /// Internal builder for one threshold row — label + value +
  /// slider + helper text. Stripped-down version of the synth
  /// screen's `_buildSampleSlider` because we don't need the
  /// snapping / quantisation logic here (each threshold has its
  /// own native float resolution).
  Widget _fallbackSlider({
    required BuildContext context,
    required String label,
    required String helper,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value.clamp(min, max),
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
          Text(helper,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  /// CrispASR CLI `--offset-t` / `--duration` equivalent. Two
  /// seconds-input fields wrapped in an ExpansionTile so they
  /// don't clutter the section when unused. Backend-agnostic
  /// (the screen-level slicing applies to every engine path).
  Widget _buildTranscribeWindowRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    final hasWindow = opts.transcribeWindowStartSec > 0 ||
        opts.transcribeWindowDurationSec > 0;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: hasWindow,
      title: Text(l.advancedTranscribeWindowTitle),
      subtitle: Text(
        hasWindow
            ? l.advancedTranscribeWindowSubtitleActive(
                opts.transcribeWindowStartSec.toStringAsFixed(1),
                opts.transcribeWindowDurationSec == 0
                    ? l.advancedTranscribeWindowEndOfFile
                    : opts.transcribeWindowDurationSec.toStringAsFixed(1))
            : l.advancedTranscribeWindowSubtitle,
        style: const TextStyle(fontSize: 11),
      ),
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: opts.transcribeWindowStartSec == 0
                    ? ''
                    : opts.transcribeWindowStartSec.toStringAsFixed(1),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  labelText: l.advancedTranscribeWindowStart,
                  helperText: l.advancedTranscribeWindowStartHelper,
                  // Half-width (two fields share a Row), so even this
                  // short helper wraps — 33 chars in EN, 38 in DE.
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  final parsed = double.tryParse(v.trim());
                  ref.read(advancedOptionsProvider.notifier).state =
                      opts.copyWith(
                          transcribeWindowStartSec:
                              parsed == null || parsed < 0 ? 0.0 : parsed);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: opts.transcribeWindowDurationSec == 0
                    ? ''
                    : opts.transcribeWindowDurationSec.toStringAsFixed(1),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  labelText: l.advancedTranscribeWindowDuration,
                  helperText:
                      l.advancedTranscribeWindowDurationHelper,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  final parsed = double.tryParse(v.trim());
                  ref.read(advancedOptionsProvider.notifier).state =
                      opts.copyWith(
                          transcribeWindowDurationSec:
                              parsed == null || parsed < 0 ? 0.0 : parsed);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTokenTimestampsRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (_activeBackend() != 'whisper') return const SizedBox.shrink();
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.advancedTokenTimestamps),
      subtitle: Text(l.advancedTokenTimestampsSubtitle,
          style: const TextStyle(fontSize: 11)),
      value: opts.tokenTimestamps,
      onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
          opts.copyWith(tokenTimestamps: v),
    );
  }

  /// §5.1.11 — top-N alternative-candidate capture slider (Whisper
  /// only). 0 = off, 5 max — capped low because Whisper produces
  /// vanishingly-small probabilities past the top few candidates and
  /// memory grows linearly with N.
  Widget _buildAltNRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (_activeBackend() != 'whisper') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l.advancedAltN}: ${l.advancedAltNLabel(opts.altN)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: 5,
            divisions: 5,
            value: opts.altN.clamp(0, 5).toDouble(),
            label: l.advancedAltNLabel(opts.altN),
            onChanged: (v) => ref
                .read(advancedOptionsProvider.notifier)
                .state = opts.copyWith(altN: v.round()),
          ),
          Text(l.advancedAltNSubtitle,
              style:
                  const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildPuncFamilyRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: l.advancedPuncFamily,
          helperText: l.advancedPuncFamilyHelper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        initialValue: opts.puncFamily,
        items: [
          DropdownMenuItem(
              value: 'pcs',
              child: Text(l.advancedPuncFamilyPcs)),
          DropdownMenuItem(
              value: 'firered',
              child: Text(l.advancedPuncFamilyFirered)),
          DropdownMenuItem(
              value: 'fullstop',
              child: Text(l.advancedPuncFamilyFullstop)),
        ],
        onChanged: (v) {
          if (v == null) return;
          ref.read(advancedOptionsProvider.notifier).state =
              opts.copyWith(puncFamily: v);
        },
      ),
    );
  }

  String _activeBackend() {
    final svc = ref.read(transcriptionServiceProvider);
    final modelId = svc.currentEngine?.currentModelId;
    if (modelId == null) return '';
    final cached = ModelCatalog.whisperCppModels[modelId] ??
        ModelCatalog.crispasrBackendModels[modelId];
    return cached?.backend ?? '';
  }

  Widget _buildBestOfRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    final n = opts.bestOf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            n <= 1 ? l.advancedBestOfSingle : l.advancedBestOfCurrent(n),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Slider(
            value: n.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: n.toString(),
            onChanged: (v) =>
                ref.read(advancedOptionsProvider.notifier).state =
                    opts.copyWith(bestOf: v.round()),
          ),
          Text(l.advancedBestOfHelper,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTemperatureRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (!AdvancedOptions.temperatureCapableBackends
        .contains(_activeBackend())) {
      return const SizedBox.shrink();
    }
    final t = opts.temperature;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t == 0.0
                ? l.advancedTemperatureGreedy
                : l.advancedTemperatureCurrent(t.toStringAsFixed(2)),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Slider(
            value: t,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: t.toStringAsFixed(2),
            onChanged: (v) =>
                ref.read(advancedOptionsProvider.notifier).state =
                    opts.copyWith(temperature: v),
          ),
          Text(l.advancedTemperatureHelper,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildAskRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (!AdvancedOptions.askCapableBackends.contains(_activeBackend())) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: _askController,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: l.advancedAskPrompt,
          hintText: l.advancedAskPromptHint,
          helperText: l.advancedAskPromptHelper,
          helperMaxLines: 4,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
            opts.copyWith(askPrompt: v),
      ),
    );
  }

  /// §5.1.2 — Custom vocabulary chip list. Always visible; the
  /// helper text changes when the active backend is CTC-class
  /// (i.e. not in [AdvancedOptions.vocabularyCapableBackends]).
  /// The user types a term, hits Enter or the + button, the
  /// term becomes a removable chip in a Wrap above the input.
  Widget _buildVocabularyRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    final backend = _activeBackend();
    final supported =
        AdvancedOptions.vocabularyCapableBackends.contains(backend);
    final mechanism = AdvancedOptions
            .vocabularyViaInitialPromptBackends
            .contains(backend)
        ? l.advancedVocabularyHelperPrompt
        : AdvancedOptions.vocabularyViaAskPromptBackends.contains(backend)
            ? l.advancedVocabularyHelperAsk
            : l.advancedVocabularyHelperUnsupported;

    void addTerm(String raw) {
      final term = raw.trim();
      if (term.isEmpty) return;
      // Don't dedupe — users sometimes WANT case variants
      // ("API" + "Api") to bias the decoder both ways.
      final next = [...opts.vocabulary, term];
      ref.read(advancedOptionsProvider.notifier).state =
          opts.copyWith(vocabulary: next);
      _vocabAddController.clear();
    }

    void removeTerm(int index) {
      final next = [...opts.vocabulary]..removeAt(index);
      ref.read(advancedOptionsProvider.notifier).state =
          opts.copyWith(vocabulary: next);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vocabAddController,
                  decoration: InputDecoration(
                    labelText: l.advancedVocabulary,
                    hintText: l.advancedVocabularyHint,
                    helperText: mechanism,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                  enabled: supported,
                  onSubmitted: addTerm,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: l.advancedVocabularyAdd,
                icon: const Icon(Icons.add),
                onPressed: supported
                    ? () => addTerm(_vocabAddController.text)
                    : null,
              ),
            ],
          ),
          if (opts.vocabulary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < opts.vocabulary.length; i++)
                  InputChip(
                    label: Text(opts.vocabulary[i]),
                    onDeleted: supported ? () => removeTerm(i) : null,
                    isEnabled: supported,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// §5.26.2 — Hotwords text field for contextual biasing.
  /// Comma-separated words/phrases the user expects to hear.
  /// Visible for all hotword-capable backends; shows an info note
  /// for backends that don't support it.
  Widget _buildHotwordsRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    final backend = _activeBackend();
    final supported =
        AdvancedOptions.hotwordsCapableBackends.contains(backend);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: TextEditingController(text: opts.hotwords),
        decoration: InputDecoration(
          labelText: l.advancedHotwords,
          hintText: l.advancedHotwordsHint,
          helperText: supported
              ? l.advancedHotwordsHelper
              : l.advancedHotwordsUnsupported,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        enabled: supported,
        onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
            opts.copyWith(hotwords: v),
      ),
    );
  }

  Widget _buildHotwordsBoostRow(BuildContext context, AdvancedOptions opts) {
    if (opts.hotwords.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.advancedHotwordsBoost(
          opts.hotwordsBoost.toStringAsFixed(1))),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.advancedHotwordsBoostHelper,
              style: const TextStyle(fontSize: 11)),
          Slider(
            value: opts.hotwordsBoost,
            min: 0.0,
            max: 5.0,
            divisions: 50,
            label: opts.hotwordsBoost.toStringAsFixed(1),
            onChanged: (v) =>
                ref.read(advancedOptionsProvider.notifier).state =
                    opts.copyWith(hotwordsBoost: v),
          ),
        ],
      ),
    );
  }

  /// §14.2d — Chunked transcription window for session backends.
  Widget _buildChunkSecondsRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.advancedChunkSeconds(opts.chunkSeconds)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.advancedChunkSecondsHelper,
              style: const TextStyle(fontSize: 11)),
          Slider(
            value: opts.chunkSeconds.toDouble(),
            min: 0,
            max: 120,
            divisions: 12,
            label: opts.chunkSeconds == 0
                ? 'default'
                : '${opts.chunkSeconds}s',
            onChanged: (v) =>
                ref.read(advancedOptionsProvider.notifier).state =
                    opts.copyWith(chunkSeconds: v.round()),
          ),
        ],
      ),
    );
  }

  /// §10 — Forced-aligner model picker. Shows a dropdown with:
  ///   * Auto (language-matched wav2vec2 > canary-ctc fallback)
  ///   * Canary CTC Aligner
  ///   * Wav2Vec2 per-language variants (FR, ES, IT, JA, ZH, etc.)
  /// Only takes effect when word timestamps are enabled and the
  /// active ASR backend doesn't emit them natively.
  ///
  /// The values stored here are catalogue *keys*, not paths —
  /// `AlignerService.resolveAlignerOverride` turns them into the
  /// downloaded GGUF's path. Entries whose GGUF isn't on disk are
  /// suffixed "(Not downloaded)" so picking one isn't a silent no-op
  /// (issue #35: the override used to be dropped on the floor).
  Widget _buildAlignerModelRow(BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    final items = <String, String>{
      '': l.advancedAlignerModelAuto,
      for (final e in alignerModelLabels.entries) e.key: e.value,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<String>(
        initialValue:
            items.containsKey(opts.alignerModel) ? opts.alignerModel : '',
        decoration: InputDecoration(
          labelText: l.advancedAlignerModel,
          helperText: l.advancedAlignerModelHelper,
          helperMaxLines: 4,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: items.entries
            .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(
                    // Auto ('') is always available; the rest need a file.
                    e.key.isEmpty ||
                            !_alignerScanDone ||
                            _downloadedAligners.contains(e.key)
                        ? e.value
                        : '${e.value}  (${l.modelsNotDownloaded})',
                    style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: (v) => ref.read(advancedOptionsProvider.notifier).state =
            opts.copyWith(alignerModel: v ?? ''),
      ),
    );
  }

  /// Source-language picker — visible whenever the active backend is in
  /// [AdvancedOptions.sourceLanguageCapableBackends]. Independent of
  /// translation: a parakeet user pinning German still gets a German
  /// transcript, not a translation. The empty default "Auto-detect"
  /// hands control back to the global language dropdown / native LID.
  Widget _buildSourceLanguageRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (!AdvancedOptions.sourceLanguageCapableBackends
        .contains(_activeBackend())) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: l.advancedSourceLanguage,
          helperText: l.advancedSourceLanguageHelper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        initialValue: opts.sourceLanguage,
        items: [
          for (final e in _sourceLanguageOptions(context))
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) =>
            ref.read(advancedOptionsProvider.notifier).state =
                opts.copyWith(sourceLanguage: v ?? ''),
      ),
    );
  }

  /// Target-language picker — only visible for [translationCapableBackends].
  /// Empty default = "no translation, transcribe verbatim".
  Widget _buildTargetLanguageRow(
      BuildContext context, AdvancedOptions opts) {
    final l = AppLocalizations.of(context);
    if (!AdvancedOptions.translationCapableBackends
        .contains(_activeBackend())) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: l.advancedTargetLanguage,
          helperText: l.advancedTargetLanguageHelper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        initialValue: opts.targetLanguage,
        items: [
          for (final e in _targetLanguageOptions(context))
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) =>
            ref.read(advancedOptionsProvider.notifier).state =
                opts.copyWith(targetLanguage: v ?? ''),
      ),
    );
  }

  List<MapEntry<String, String>> _sourceLanguageOptions(
      BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      // Empty string = "use whatever the global language dropdown
      // says / let whisper autodetect". Pinning a source via this
      // override is only useful when autodetect is unreliable.
      MapEntry('', l.advancedSourceLanguageAuto),
      MapEntry('en', l.languageEn),
      MapEntry('de', l.languageDe),
      MapEntry('es', l.languageEs),
      MapEntry('fr', l.languageFr),
      MapEntry('it', l.languageIt),
      MapEntry('pt', l.languagePt),
      MapEntry('zh', l.languageZh),
      MapEntry('ja', l.languageJa),
      MapEntry('ko', l.languageKo),
    ];
  }

  List<MapEntry<String, String>> _targetLanguageOptions(
      BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      MapEntry('', l.advancedTargetLanguageNone),
      MapEntry('en', l.languageEn),
      MapEntry('de', l.languageDe),
      MapEntry('es', l.languageEs),
      MapEntry('fr', l.languageFr),
      MapEntry('it', l.languageIt),
      MapEntry('pt', l.languagePt),
      MapEntry('zh', l.languageZh),
      MapEntry('ja', l.languageJa),
      MapEntry('ko', l.languageKo),
      MapEntry('ru', l.languageRu),
    ];
  }
}
