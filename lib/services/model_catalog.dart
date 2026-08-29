// lib/services/model_catalog.dart — static model definitions, data classes,
// language lists, backend repo entries, and all catalog-only helpers.
// Extracted from model_service.dart to keep the service focused on
// operational logic (download, verify, delete, probe).

// No external imports needed — pure data definitions.

// ─── Data classes, enums, and exceptions ───

// Enhanced data classes and exceptions

/// What this catalog row represents. The Model Management UI groups by
/// kind; the engine layer dispatches based on kind + backend.
enum ModelKind {
  /// Speech recognition main model (whisper / parakeet / canary / …).
  asr,

  /// Text-to-speech main model (kokoro / vibevoice-tts / qwen3-tts / …).
  tts,

  /// Voice pack — paired with a TTS model via `CrispasrSession.setVoice`.
  voice,

  /// Codec / tokenizer GGUF — paired with a TTS model via
  /// `CrispasrSession.setCodecPath` (qwen3-tts only).
  codec,

  /// Post-processor — punctuation restoration (FireRedPunc, fullstop-punc).
  punc,

  /// VAD GGUF — paired with `TranscribeOptions.vadModelPath` /
  /// `transcribeVad`. Silero is bundled as a Flutter asset; FireRed /
  /// MarbleNet / Whisper-VAD-EncDec live in the model catalog so users
  /// can opt into the higher-accuracy variants.
  vad,

  /// Language identification GGUF — paired with
  /// `crispasr.detectLanguagePcm(method: LidMethod.silero)`. The Whisper
  /// encoder LID path doesn't need a dedicated GGUF (it reuses any
  /// multilingual ggml-*.bin already on disk).
  lid,

  /// Diarisation GGUF — Pyannote v3 segmentation, paired with
  /// `DiarizeMethod.pyannote`.
  diarize,

  /// Text-to-text translation model (m2m100, madlad). Distinct from
  /// the speech-translation backends (canary, voxtral, …) — those are
  /// `ModelKind.asr` because they consume audio.
  translate,

  /// §5.1.6 v3.1 — local chat-LLM GGUF (Qwen2.5-Instruct,
  /// Llama-3.2-Instruct, Phi-3-mini, Gemma-2, …). Loaded via the
  /// CrispASR chat ABI (`CrispasrChatSession`) for the Tidy /
  /// Summarize Local-LLM-cleanup path. Distinct from `asr` —
  /// these are text-only models, not speech models.
  chatLlm,

  /// §5.25.2 — Text embedding GGUF for semantic transcript search.
  /// Loaded via CrispEmbed. Distinct from `asr` — these are
  /// encoder-only text models, not speech models.
  embed,

  /// §12.3a — Cross-encoder reranker GGUF for search result re-scoring.
  /// Loaded via CrispEmbed's `rerank(query, doc)` API. Distinct from
  /// `embed` — these score (query, doc) pairs, not produce vectors.
  reranker,

  /// §12.6b — OCR GGUF for document and math formula recognition.
  /// Loaded via CrispEmbed OCR classes (CrispEmbedOcr, CrispEmbedHmerOcr).
  /// Includes math OCR (pix2tex, HMER, BTTR, PosFormer), scene text
  /// (ParseQ, TrOCR), and document VLM OCR (DeepSeek-OCR2, Granite Vision).
  ocr,

  /// §14.3i — Optical Music Recognition (OMR) GGUF for sheet music
  /// recognition. Loaded via CrispEmbed OCR dispatch (arch auto-detected).
  /// Includes SMT++ (bekern), TrOMR (polyphonic MIDI), Flova (LilyPond),
  /// and Transcoda (Humdrum **kern).
  omr,
}

class ModelDefinition {
  final String name;
  final String displayName;
  final String fileName;
  final String url;
  final int sizeBytes;
  final String checksum;
  final String description;
  final String quantization; // 'f16', 'q4_0', 'q5_0', 'q8_0', ''
  /// The CrispASR backend id that owns this model — see
  /// `crispasr --list-backends`. Default 'whisper' for the vanilla GGML
  /// Whisper models we ship.
  final String backend;

  /// Which UI bucket this row belongs to. Defaults to [ModelKind.asr] so
  /// existing call sites stay correct.
  final ModelKind kind;

  /// Names of companion models this entry needs alongside it (codec
  /// tokenizer for qwen3-tts, voicepacks for kokoro / vibevoice-tts).
  /// Pure metadata used by the Synthesize screen to suggest extra
  /// downloads — engine code looks them up by filename, not name.
  final List<String> companions;

  /// ISO 639-1 language codes the model supports. Two special values:
  ///   * `[]` (default) — language metadata unknown; the Model Manager
  ///     language filter treats these as "no opinion" and shows them
  ///     under every filter (so untagged-but-actually-good entries
  ///     don't disappear). New rows should aim to fill this in.
  ///   * `['*']` — multilingual (Whisper-style 99-lang; M2M-100;
  ///     SenseVoice's built-in LID, etc.). Matches any specific
  ///     language filter.
  /// Anything else is a concrete list of ISO 639-1 codes ("en", "de",
  /// "zh", ...) and matches a filter when the picked code is in the
  /// list. Codec / voice / VAD / LID / diarisation / punctuation
  /// entries can leave this empty — the language filter only fires for
  /// kind = asr / tts / translate.
  final List<String> languages;

  /// Upstream weight license string, mirrored from the CrispASR registry
  /// (`crispasr_model_registry.cpp`). `null` = permissive (MIT/Apache/etc.).
  /// A non-null value is shown in the Model Manager; non-commercial licenses
  /// additionally gate downloads behind a confirmation dialog — see
  /// [isNonCommercial] (EU AI Act / licence-compliance surfacing).
  final String? license;

  /// True for TTS models that need an external voice reference (voice
  /// pack, WAV clone, or custom voice) before synthesis can produce
  /// audio. The Synthesize screen uses this to block the Synthesize
  /// button and show a hint when no voice is selected. Examples:
  /// qwen3-tts Base, vibevoice-1.5b Base.
  final bool requiresVoice;

  const ModelDefinition({
    required this.name,
    required this.displayName,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    required this.checksum,
    required this.description,
    this.quantization = 'f16',
    this.backend = 'whisper',
    this.kind = ModelKind.asr,
    this.companions = const [],
    this.languages = const [],
    this.license,
    this.requiresVoice = false,
  });

  /// Deserialise from a JSON map (e.g. from the baked catalog asset).
  factory ModelDefinition.fromJson(Map<String, dynamic> json) =>
      ModelDefinition(
        name: json['name'] as String,
        displayName: json['displayName'] as String,
        fileName: json['fileName'] as String,
        url: json['url'] as String,
        sizeBytes: json['sizeBytes'] as int,
        checksum: json['checksum'] as String? ?? '',
        description: json['description'] as String,
        quantization: json['quantization'] as String? ?? 'f16',
        backend: json['backend'] as String? ?? 'whisper',
        kind: ModelKind.values.byName(json['kind'] as String? ?? 'asr'),
        companions:
            (json['companions'] as List<dynamic>?)?.cast<String>() ?? const [],
        languages:
            (json['languages'] as List<dynamic>?)?.cast<String>() ?? const [],
        license: json['license'] as String?,
        requiresVoice: json['requiresVoice'] as bool? ?? false,
      );

  /// Serialise to a JSON-encodable map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'displayName': displayName,
        'fileName': fileName,
        'url': url,
        'sizeBytes': sizeBytes,
        'checksum': checksum,
        'description': description,
        'quantization': quantization,
        'backend': backend,
        'kind': kind.name,
        if (companions.isNotEmpty) 'companions': companions,
        if (languages.isNotEmpty) 'languages': languages,
        if (license != null) 'license': license,
        if (requiresVoice) 'requiresVoice': true,
      };

  /// True when [license] denotes a non-commercial / research-only grant
  /// (CC-BY-NC, "non-commercial", "research only"). Used to warn before
  /// download/use so users don't unknowingly take on NC terms.
  bool get isNonCommercial {
    final l = license;
    if (l == null) return false;
    final s = l.toLowerCase();
    return s.contains('-nc') ||
        s.contains('non-commercial') ||
        s.contains('noncommercial') ||
        s.contains('research only') ||
        s.contains('research-only');
  }

  /// True when this row should appear under the given language
  /// filter. `''` (the "Any" sentinel) always passes; `['*']`
  /// (multilingual) passes any picked code.
  ///
  /// Untagged rows (`languages == []`) still pass every filter for the
  /// *model* kinds, where the catalogue is not yet fully tagged and
  /// hiding an untagged-but-good entry would be worse than showing it.
  /// Voicepacks are the exception (issue #35): every voice row carries
  /// a concrete ISO 639-1 tag now, so an untagged voice is a catalogue
  /// bug rather than missing metadata — and letting it through is what
  /// made "English" list the German and French voices.
  bool matchesLanguage(String code) {
    if (code.isEmpty) return true;
    if (languages.contains('*')) return true;
    if (languages.isEmpty) return kind != ModelKind.voice;
    return languages.contains(code.toLowerCase());
  }

  /// Shallow copy with selective field overrides.
  ModelDefinition copyWith({
    String? name,
    String? displayName,
    String? fileName,
    String? url,
    int? sizeBytes,
    String? checksum,
    String? description,
    String? quantization,
    String? backend,
    ModelKind? kind,
    List<String>? companions,
    List<String>? languages,
    String? license,
    bool? requiresVoice,
  }) =>
      ModelDefinition(
        name: name ?? this.name,
        displayName: displayName ?? this.displayName,
        fileName: fileName ?? this.fileName,
        url: url ?? this.url,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        checksum: checksum ?? this.checksum,
        description: description ?? this.description,
        quantization: quantization ?? this.quantization,
        backend: backend ?? this.backend,
        kind: kind ?? this.kind,
        companions: companions ?? this.companions,
        languages: languages ?? this.languages,
        license: license ?? this.license,
        // Was silently dropped before: `overrideBackend` copies a
        // definition to stamp a resolved backend, and a qwen3-tts /
        // vibevoice Base row came back claiming it needed no voice.
        requiresVoice: requiresVoice ?? this.requiresVoice,
      );
}

/// Points at a HuggingFace repo that the model service can enumerate to
/// discover every available quantisation variant.
class BackendRepo {
  final String backend; // CrispASR backend id
  final String repoId; // e.g. "cstr/parakeet-tdt-0.6b-v3-GGUF"
  final String
      baseName; // filename stem without -quant; e.g. "parakeet-tdt-0.6b-v3"
  final String displayPrefix; // UI-friendly name; e.g. "Parakeet TDT 0.6B v3"
  final String description;
  final String extension; // typically ".gguf", Whisper uses ".bin"
  // What ModelKind newly-discovered variants belong to. Without this the
  // probe stamped every quant as ModelKind.asr (the ModelDefinition
  // default), and merging _discoveredModels last overwrote the hardcoded
  // catalogue's correct kind — TTS / translate / voice entries
  // disappeared from their filter chips. ASR is still the default since
  // most backends are speech recognition.
  final ModelKind kind;
  // Optional secondary file-name stem inside this same repo for
  // voicepack files (e.g. `vibevoice-voice` inside the
  // `cstr/vibevoice-realtime-0.5b-GGUF` repo, which holds both the
  // main TTS quants AND 20+ voicepack `.gguf` files). When non-null,
  // the probe ALSO enumerates files starting with
  // `<voicepackBaseName>-` and stamps them as `ModelKind.voice`
  // entries with the same `backend` as this repo. Leaving
  // `baseName` empty + setting only `voicepackBaseName` is the way
  // to register a voicepack-only repo (e.g.
  // `cstr/kokoro-voices-GGUF`).
  final String? voicepackBaseName;

  /// Names of ModelDefinitions every auto-discovered variant from
  /// this repo must download alongside the main GGUF. Mirrors the
  /// `companions:` field on hardcoded ModelDefinitions — without this,
  /// the HF-refresh button would surface new quants of mimo-asr /
  /// moonshine / kokoro / orpheus / chatterbox / qwen3-tts /
  /// vibevoice-tts without their required tokenizer / codec / voice
  /// companion, and the user would hit "session_open returned null"
  /// (moonshine) or runtime codec errors (the rest) on first load.
  /// Each entry must point at a ModelDefinition that ALSO exists in
  /// the catalogue (typically a hardcoded codec / voice entry, since
  /// companion files usually don't follow the `baseName-quant` naming
  /// convention the probe matches against).
  final List<String> defaultCompanions;

  /// ISO 639-1 language codes auto-discovered ModelDefinitions inherit.
  /// Mirrors `defaultCompanions`: same shape as `ModelDefinition.languages`
  /// — `[]` = unknown, `['*']` = multilingual, otherwise a concrete
  /// language list. Lets the Models-screen language filter find quants
  /// the HF probe surfaced even though they weren't in the baked
  /// catalogue.
  final List<String> defaultLanguages;

  const BackendRepo({
    required this.backend,
    required this.repoId,
    required this.baseName,
    required this.displayPrefix,
    required this.description,
    this.extension = '.gguf',
    this.kind = ModelKind.asr,
    this.voicepackBaseName,
    this.defaultCompanions = const [],
    this.defaultLanguages = const [],
  });
}

/// Result envelope from `ModelService.refreshAvailableQuants()`.
/// `added` is the count of newly-discovered quant variants merged into
/// the catalogue. `failedRepos` lists repo ids whose probe threw —
/// most commonly because the upstream HF repo is gated and returns
/// 401 to anonymous requests. The UI uses this to differentiate "all
/// probes succeeded but nothing new was found" from "some probes
/// quietly failed".
class QuantProbeResult {
  final int added;
  final List<String> failedRepos;
  const QuantProbeResult({required this.added, required this.failedRepos});

  bool get hasFailures => failedRepos.isNotEmpty;
}

class ModelInfo {
  final String name;
  final String displayName;
  final String size;
  final int sizeBytes;
  final bool isDownloaded;
  final String? localPath;
  final String description;
  final ModelType modelType;
  final String quantization;
  final String backend;

  /// Bucket discriminator — filtered by Model Management chips so users
  /// can see TTS voicepacks separately from main ASR models.
  final ModelKind kind;

  /// ISO 639-1 language codes the underlying ModelDefinition advertises.
  /// `[]` = unknown (filter shows under any language), `['*']` =
  /// multilingual, otherwise the list of supported codes. Drives the
  /// Models screen language-filter dropdown.
  final List<String> languages;

  /// Human-readable runtime status — "Ready" when the bundled libwhisper
  /// can execute this model today, or an explanation of what's missing.
  /// Filled in by the UI based on engine capability probing.
  final String? runtimeStatus;

  /// PLAN §5.4 — true when this is the recommended "start here" model
  /// for its backend (see [ModelCatalog.recommendedDefaultModels]).
  /// Drives the "Recommended" badge in the model pickers.
  final bool recommendedDefault;

  const ModelInfo({
    required this.name,
    required this.displayName,
    required this.size,
    required this.sizeBytes,
    required this.isDownloaded,
    this.localPath,
    required this.description,
    required this.modelType,
    this.quantization = 'f16',
    this.backend = 'whisper',
    this.kind = ModelKind.asr,
    this.languages = const [],
    this.runtimeStatus,
    this.recommendedDefault = false,
  });

  /// Same filter helper as [ModelDefinition.matchesLanguage] — kept on
  /// the UI-facing type so the Model Manager doesn't have to round-trip
  /// to the ModelService just to filter a list it already holds. Keep
  /// the two implementations in step —
  /// `test/model_catalog_language_filter_test.dart` cross-checks every
  /// (kind, languages, probe) combination against
  /// [ModelDefinition.matchesLanguage].
  bool matchesLanguage(String code) {
    if (code.isEmpty) return true;
    if (languages.contains('*')) return true;
    if (languages.isEmpty) return kind != ModelKind.voice;
    return languages.contains(code.toLowerCase());
  }
}

enum ModelType {
  whisperCpp,
}

class StorageInfo {
  final int whisperCppBytes;
  final int totalBytes;

  const StorageInfo({
    required this.whisperCppBytes,
    required this.totalBytes,
  });

  String get formattedWhisperCpp => _formatSize(whisperCppBytes);
  String get formattedTotal => _formatSize(totalBytes);

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class BackendStorage {
  final String backend;
  final int bytes;
  final int fileCount;

  const BackendStorage({
    required this.backend,
    required this.bytes,
    required this.fileCount,
  });

  String get formattedSize {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class ModelStorageHealth {
  final String directory;
  final int usedBytes;

  /// `-1` when the platform cannot report free space.
  final int freeBytes;
  final bool isCustomDirectory;

  const ModelStorageHealth({
    required this.directory,
    required this.usedBytes,
    required this.freeBytes,
    required this.isCustomDirectory,
  });

  bool get isLowSpace => freeBytes >= 0 && freeBytes < 2 * 1024 * 1024 * 1024;
}

class ModelMoveResult {
  final String sourceDirectory;
  final String targetDirectory;
  final int fileCount;
  final int bytes;

  const ModelMoveResult({
    required this.sourceDirectory,
    required this.targetDirectory,
    required this.fileCount,
    required this.bytes,
  });
}

class ModelException implements Exception {
  final String message;
  const ModelException(this.message);

  @override
  String toString() => 'ModelException: $message';
}

// ─── Static catalog container ───

abstract final class ModelCatalog {
  /// Upstream ggerganov repo — the canonical source for F16 GGML Whisper models.
  static const String whisperCppBaseUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  /// A general-purpose cstr GGUF repo (CrispASR-compatible backends:
  /// Parakeet, Canary, Cohere, Voxtral, Qwen3-ASR, Granite, FastConformer-CTC,
  /// Wav2Vec2). Each backend has its own filename convention — see
  /// `crispasrBackendModels` below.
  static const String cstrCrispBaseUrl =
      'https://huggingface.co/cstr/crispasr-gguf/resolve/main';

  // Common language-code sets used across the catalogue + BackendRepo
  // tables. Kept as top-level constants so the `static const` model
  // maps can reference them directly. `['*']` is the multilingual
  // sentinel — `ModelDefinition.matchesLanguage` treats it as "matches
  // any picked language."
  static const List<String> langsAll = <String>['*'];

  /// Repo-local language tags that are *not* ISO 639-1, mapped to the
  /// code the rest of the app speaks (issue #35). The VibeVoice
  /// voicepack repo names its files `jp-…`, `kr-…`, `sp-…` and `in-…`;
  /// the Model Manager's language dropdown is built from
  /// `AppConstants.supportedLanguages`, which is ISO 639-1. Without
  /// this mapping the voice chips said "jp" while the dropdown said
  /// "ja" and the two filters could never agree.
  ///
  /// `in` is Indian *English* in that repo — deliberately mapped to
  /// `en`, not to Indonesian (`id`).
  static const Map<String, String> languageCodeAliases = <String, String>{
    'jp': 'ja',
    'kr': 'ko',
    'sp': 'es',
    'in': 'en',
    'cn': 'zh',
    'gr': 'el',
  };

  /// Fold a repo-local language tag to ISO 639-1. Unknown codes pass
  /// through lower-cased so a new repo convention degrades to "shows
  /// under its own chip" rather than vanishing.
  static String normalizeLanguageCode(String code) {
    final c = code.trim().toLowerCase();
    return languageCodeAliases[c] ?? c;
  }

  /// Derive ISO 639-1 codes for a voicepack from its file naming
  /// convention. Shared by the live HF probe
  /// (`ModelService.voicepackLanguages`) and the offline bake script so
  /// a probed voice and a baked voice are tagged identically.
  ///
  ///   * VibeVoice — the voice id starts with the language:
  ///     `de-Spk1_woman`, `en-Emma_woman`. Folded through
  ///     [normalizeLanguageCode] because the repo writes `jp` / `kr` /
  ///     `sp` / `in` where ISO wants `ja` / `ko` / `es` / `en`.
  ///   * Kokoro — the first character of the voice id is the language
  ///     (`af_heart` → English, `df_eva` → German); the second is the
  ///     speaker's gender, not a language hint.
  ///
  /// Returns `[]` when the id doesn't match a known scheme — callers
  /// fall back to the repo's `defaultLanguages`.
  static List<String> voicepackLanguages(String backend, String voiceId) {
    if (voiceId.isEmpty) return const <String>[];
    if (backend == 'vibevoice-tts' || backend == 'vibevoice-1.5b') {
      final m = RegExp(r'^([a-z]{2})-').firstMatch(voiceId);
      if (m != null) return <String>[normalizeLanguageCode(m.group(1)!)];
    }
    if (backend == 'kokoro') {
      const kokoroLang = <String, String>{
        'a': 'en', // American English
        'b': 'en', // British English
        'd': 'de', // German
        'e': 'es', // Spanish
        'f': 'fr', // French
        'i': 'it', // Italian
        'j': 'ja', // Japanese
        'p': 'pt', // Portuguese
        'z': 'zh', // Mandarin Chinese
        'h': 'hi', // Hindi
      };
      final code = kokoroLang[voiceId[0].toLowerCase()];
      if (code != null) return <String>[code];
    }
    return const <String>[];
  }

  /// Issue #35 — catalogue keys to hide from the Models screen because
  /// a higher-priority row already offers the exact same download.
  ///
  /// The baked snapshot keys entries off the HF filename
  /// (`chatterbox-t3-q8_0`) while the curated catalogue gives the same
  /// file a friendlier key (`chatterbox-en-q8_0`), so roughly thirty
  /// downloads were listed twice under different names — the same
  /// complaint as the two VibeVoice Emma rows, spread across the whole
  /// catalogue. Priority: hand-curated (readable display names,
  /// language tags, and the keys `recommendedDefaultModels` /
  /// `companions` point at) beats a live HF probe beats the baked
  /// snapshot. Ties break on the name so the result is deterministic.
  ///
  /// Only the duplicate *listing* is suppressed — every name stays
  /// resolvable through `ModelService.lookupDefinition`, so an old
  /// download or a saved model preference keeps working.
  static Set<String> duplicateFileNameEntries({
    required Map<String, ModelDefinition> baked,
    Map<String, ModelDefinition> discovered = const <String, ModelDefinition>{},
  }) {
    int rank(String name) {
      if (whisperCppModels.containsKey(name) ||
          crispasrBackendModels.containsKey(name) ||
          ttsVoicepacks.containsKey(name)) {
        return 0; // hand-curated
      }
      if (discovered.containsKey(name)) return 1; // live HF probe
      return 2; // baked snapshot
    }

    final all = <String, ModelDefinition>{
      ...baked,
      ...crispasrBackendModels,
      ...ttsVoicepacks,
      ...discovered,
      ...whisperCppModels,
    };
    final names = all.keys.toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.compareTo(b);
      });
    final claimed = <String, String>{}; // lowercased fileName -> winning name
    final suppressed = <String>{};
    for (final name in names) {
      final file = all[name]!.fileName.toLowerCase();
      if (file.isEmpty) continue;
      if (claimed.putIfAbsent(file, () => name) != name) suppressed.add(name);
    }
    return suppressed;
  }

  /// Files that shipped under one name and now live under another.
  /// Key = the legacy on-disk filename, value = the current one.
  /// `ModelService.initialize` renames these in place on first run so a
  /// user who already downloaded the old file doesn't fetch the same
  /// bytes twice (issue #35 — VibeVoice's Emma voice is published under
  /// both names in `cstr/vibevoice-realtime-0.5b-GGUF`).
  static const Map<String, String> legacyModelFileRenames = <String, String>{
    'vibevoice-voice-emma.gguf': 'vibevoice-voice-en-Emma_woman.gguf',
  };

  static const List<String> langsEn = <String>['en'];
  static const List<String> langsDe = <String>['de'];
  static const List<String> langsZh = <String>['zh'];
  static const List<String> langsFr = <String>['fr'];
  static const List<String> langsEs = <String>['es'];
  static const List<String> langsIt = <String>['it'];
  static const List<String> langsPt = <String>['pt'];
  static const List<String> langsNl = <String>['nl'];
  static const List<String> langsRu = <String>['ru'];
  static const List<String> langsJa = <String>['ja'];
  static const List<String> langsAr = <String>['ar'];
  static const List<String> langsUk = <String>['uk'];
  static const List<String> langsCs = <String>['cs'];
  static const List<String> langsEnZh = <String>['en', 'zh'];
  static const List<String> langsJaEn = <String>['ja', 'en'];
  static const List<String> langsRuEn = <String>['ru', 'en'];
  // The 25-language EU set Canary 1B-v2 + Parakeet TDT v3 advertise.
  // Per the upstream HF model cards: includes Maltese (mt), excludes
  // Norwegian (the EU25 ASR set uses Swedish for Scandinavia and
  // omits no).
  static const List<String> langsEU25 = <String>[
    'en',
    'de',
    'fr',
    'es',
    'it',
    'pt',
    'nl',
    'pl',
    'ru',
    'uk',
    'cs',
    'da',
    'sv',
    'mt',
    'fi',
    'el',
    'bg',
    'ro',
    'sk',
    'sl',
    'lt',
    'lv',
    'et',
    'hr',
    'hu',
  ];
  // 14-language set Cohere transcribe-03-2026 advertises (added
  // Greek / Dutch / Polish / Vietnamese, dropped Hindi / Russian /
  // Turkish vs the older 13-lang variant).
  static const List<String> langsCohere14 = <String>[
    'en',
    'es',
    'fr',
    'de',
    'it',
    'pt',
    'zh',
    'ja',
    'ko',
    'ar',
    'el',
    'nl',
    'pl',
    'vi',
  ];
  // Kept under the old name for any catalogue rows still referring
  // to it — alias to the corrected list so the diff stays consistent.
  static const List<String> langsCohere13 = langsCohere14;
  // 8-language set Voxtral Mini 3B 2507 advertises on HF. The
  // 9th-language addition (Arabic) the user-facing card showed
  // earlier was a card edit; the actual HF API tags list 8.
  static const List<String> langsVoxtral9 = <String>[
    'en',
    'fr',
    'es',
    'pt',
    'it',
    'nl',
    'de',
    'hi',
  ];
  // Legacy alias retained for older catalogue rows that referred to
  // the earlier 8-language voxtral set. Same list now points at the
  // 9-language one — the 8-lang card was stale.
  static const List<String> langsVoxtral8 = langsVoxtral9;
  // 6-language set used by Granite Speech 3.x and 4.0 / 4.1 base.
  static const List<String> langsGranite6 = <String>[
    'en',
    'fr',
    'de',
    'es',
    'pt',
    'ja',
  ];
  // 5-language set used by Granite Speech 4.1-plus / -nar (dropped
  // Japanese vs the 6-lang base).
  static const List<String> langsGranite5 = <String>[
    'en',
    'fr',
    'de',
    'es',
    'pt',
  ];
  // 29-language set used by the Qwen3-ASR family + Mega-ASR. From
  // the upstream HF cards.
  static const List<String> langsQwen3Asr29 = <String>[
    'ar',
    'cs',
    'da',
    'de',
    'el',
    'en',
    'es',
    'fa',
    'fi',
    'fr',
    'hi',
    'hu',
    'id',
    'it',
    'ja',
    'ko',
    'mk',
    'ms',
    'nl',
    'pl',
    'pt',
    'ro',
    'ru',
    'sv',
    'th',
    'tl',
    'tr',
    'vi',
    'zh',
  ];
  // 10-language set used by the qwen3-tts base + voicedesign + codec
  // repos. customvoice variants use the 9-language subset below (no
  // Russian).
  static const List<String> langsQwen3Tts10 = <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'pt',
    'ru',
    'zh',
  ];
  static const List<String> langsQwen3TtsCustom9 = <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'pt',
    'zh',
  ];
  // 8-language set the WMT21 Dense translators advertise.
  static const List<String> langsWmt21_8 = <String>[
    'cs',
    'de',
    'en',
    'ha',
    'is',
    'ja',
    'ru',
    'zh',
  ];
  // 10-language set Vibevoice TTS lists (jp/kr/sp are non-standard
  // 2-letter codes mapped to ja/ko/es by the runtime).
  static const List<String> langsVibevoiceTts10 = <String>[
    'de',
    'en',
    'fr',
    'it',
    'ja',
    'ko',
    'nl',
    'pl',
    'pt',
    'es',
  ];
  // SenseVoice supports zh/en/ja/ko/yue; we surface yue under zh.
  static const List<String> langsSensevoice = <String>['zh', 'en', 'ja', 'ko'];
  // Fullstop-punc multilingual checkpoint.
  static const List<String> langsFullstopPunc = <String>[
    'en',
    'de',
    'fr',
    'it'
  ];
  // Chatterbox base (ResembleAI) advertises 23 langs.
  static const List<String> langsChatterbox23 = <String>[
    'ar',
    'da',
    'de',
    'el',
    'en',
    'es',
    'fi',
    'fr',
    'he',
    'hi',
    'it',
    'ja',
    'ko',
    'ms',
    'nl',
    'no',
    'pl',
    'pt',
    'ru',
    'sv',
    'sw',
    'tr',
    'zh',
  ];
  // VoxCPM2 (openbmb/VoxCPM2) advertises 29 langs per cstr/voxcpm2-GGUF's
  // cardData. Diffusion AR TTS, 48 kHz native (decimated to 24 kHz in the
  // C API to match the host's fixed-rate playback path).
  static const List<String> langsVoxcpm2_29 = <String>[
    'en',
    'zh',
    'ja',
    'ko',
    'de',
    'fr',
    'es',
    'pt',
    'it',
    'nl',
    'ru',
    'ar',
    'hi',
    'vi',
    'th',
    'id',
    'ms',
    'tl',
    'tr',
    'pl',
    'cs',
    'sv',
    'da',
    'no',
    'fi',
    'el',
    'he',
    'uk',
    'ro',
  ];
  // CosyVoice3 0.5B-2512 (FunAudioLLM). cardData also lists 'yue'
  // (Cantonese) but we surface it under 'zh' — same convention as
  // funasr / sensevoice — so the language-parity check stays clean.
  static const List<String> langsCosyvoice10 = <String>[
    'zh',
    'en',
    'ja',
    'ko',
    'fr',
    'de',
    'es',
    'pt',
    'it',
    'ru',
  ];
  // The 99 languages whisper.cpp supports — from the whisper.cpp
  // source's lang_id table. Codes are ISO 639-1 where one exists;
  // a handful are 3-letter aliases (haw / yue) that the runtime
  // recognises. ggerganov/whisper.cpp's HF cardData doesn't list
  // them so we hardcode rather than read from the API.
  static const List<String> langsWhisper99 = <String>[
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
    'yue',
  ];
  // VibeVoice ASR's 48-language list (per cstr/vibevoice-asr-GGUF's
  // cardData on HF).
  static const List<String> langsVibevoice48 = <String>[
    'en',
    'zh',
    'es',
    'pt',
    'de',
    'ja',
    'ko',
    'fr',
    'ru',
    'id',
    'sv',
    'it',
    'he',
    'nl',
    'pl',
    'no',
    'tr',
    'th',
    'ar',
    'hu',
    'ca',
    'cs',
    'da',
    'fa',
    'af',
    'hi',
    'fi',
    'et',
    'el',
    'ro',
    'vi',
    'bg',
    'is',
    'sl',
    'sk',
    'lt',
    'sw',
    'uk',
    'lv',
    'hr',
    'ne',
    'sr',
    'tl',
    'ms',
    'ur',
    'mn',
    'hy',
    'jv',
  ];
  // FunASR MLT Nano's 31-language list (per cstr/funasr-mlt-nano-GGUF
  // cardData). The 'yue' (Cantonese) entry maps to 'zh' for the
  // picker since users picking Chinese expect both varieties.
  static const List<String> langsFunasrMlt31 = <String>[
    'zh',
    'en',
    'ja',
    'ko',
    'vi',
    'th',
    'id',
    'ms',
    'tl',
    'ar',
    'hi',
    'bg',
    'ru',
    'de',
    'fr',
    'es',
    'it',
    'pt',
    'nl',
    'pl',
    'cs',
    'ro',
    'el',
    'fi',
    'sv',
    'tr',
    'fa',
    'da',
    'hu',
    'mk',
  ];

  // Enhanced model definitions with proper URLs and checksums
  static const Map<String, ModelDefinition> whisperCppModels = {
    'tiny': ModelDefinition(
      name: 'tiny',
      displayName: 'Whisper Tiny',
      fileName: 'ggml-tiny.bin',
      url: '$whisperCppBaseUrl/ggml-tiny.bin',
      sizeBytes: 74 * 1024 * 1024,
      checksum: 'bd577a113a864445d4c299885e0cb97d4ba92b5f',
      description: 'Fastest model, lower accuracy (~74 MB)',
    ),
    'tiny.en': ModelDefinition(
      name: 'tiny.en',
      displayName: 'Whisper Tiny English',
      fileName: 'ggml-tiny.en.bin',
      url: '$whisperCppBaseUrl/ggml-tiny.en.bin',
      sizeBytes: 74 * 1024 * 1024,
      checksum: 'c78c86eb1a8faa21b369bcd33207cc90d64ae9df',
      description: 'Fastest model for English only (~74 MB)',
    ),
    'base': ModelDefinition(
      name: 'base',
      displayName: 'Whisper Base',
      fileName: 'ggml-base.bin',
      url: '$whisperCppBaseUrl/ggml-base.bin',
      sizeBytes: 142 * 1024 * 1024,
      checksum: '465707469ff3a37a2b9b8d8f89f2f99de7299dac',
      description: 'Balanced speed and accuracy (~142 MB)',
    ),
    'base.en': ModelDefinition(
      name: 'base.en',
      displayName: 'Whisper Base English',
      fileName: 'ggml-base.en.bin',
      url: '$whisperCppBaseUrl/ggml-base.en.bin',
      sizeBytes: 142 * 1024 * 1024,
      checksum: '137c40403d78fd54d454da0f9bd998f78703390c',
      description: 'Balanced model for English only (~142 MB)',
    ),
    'small': ModelDefinition(
      name: 'small',
      displayName: 'Whisper Small',
      fileName: 'ggml-small.bin',
      url: '$whisperCppBaseUrl/ggml-small.bin',
      sizeBytes: 466 * 1024 * 1024,
      checksum: '55356645c2b361a969dfd0ef2c5a50d530afd8d5',
      description: 'Good accuracy with moderate speed (~466 MB)',
    ),
    'small.en': ModelDefinition(
      name: 'small.en',
      displayName: 'Whisper Small English',
      fileName: 'ggml-small.en.bin',
      url: '$whisperCppBaseUrl/ggml-small.en.bin',
      sizeBytes: 466 * 1024 * 1024,
      checksum: 'db8a495a91d927739e50b3fc1cc4c6b8f6c2d022',
      description: 'Good accuracy for English only (~466 MB)',
    ),
    'medium': ModelDefinition(
      name: 'medium',
      displayName: 'Whisper Medium',
      fileName: 'ggml-medium.bin',
      url: '$whisperCppBaseUrl/ggml-medium.bin',
      sizeBytes: 1500 * 1024 * 1024,
      checksum: 'fd9727b6e1217c2f614f9b698455c4ffd82463b4',
      description: 'High accuracy with slower processing (~1.5 GB)',
    ),
    'medium.en': ModelDefinition(
      name: 'medium.en',
      displayName: 'Whisper Medium English',
      fileName: 'ggml-medium.en.bin',
      url: '$whisperCppBaseUrl/ggml-medium.en.bin',
      sizeBytes: 1500 * 1024 * 1024,
      checksum: 'd7440d1dc186f76616787fcdd0b295ef60e88766',
      description: 'High accuracy for English only (~1.5 GB)',
    ),
    'large': ModelDefinition(
      name: 'large',
      displayName: 'Whisper Large',
      fileName: 'ggml-large.bin',
      url: '$whisperCppBaseUrl/ggml-large.bin',
      sizeBytes: 3000 * 1024 * 1024,
      checksum: 'b1caaf735c4cc1429223d5a74f0f4d0b9b59a299',
      description: 'Best accuracy with slowest processing (~3 GB)',
    ),
    'large-v2': ModelDefinition(
      name: 'large-v2',
      displayName: 'Whisper Large v2',
      fileName: 'ggml-large-v2.bin',
      url: '$whisperCppBaseUrl/ggml-large-v2.bin',
      sizeBytes: 3000 * 1024 * 1024,
      checksum: '0f4c8e34f21cf1a914c59d8b3ce882345ad349d6',
      description: 'Improved large model (~3 GB)',
    ),
    'large-v3': ModelDefinition(
      name: 'large-v3',
      displayName: 'Whisper Large v3',
      fileName: 'ggml-large-v3.bin',
      url: '$whisperCppBaseUrl/ggml-large-v3.bin',
      sizeBytes: 3000 * 1024 * 1024,
      checksum: 'ad82bf6a9043ceed055076d0fd39f5f186ff8062',
      description: 'Latest large model with enhanced performance (~3 GB)',
    ),
    'large-v3-turbo': ModelDefinition(
      name: 'large-v3-turbo',
      displayName: 'Whisper Large v3 Turbo',
      fileName: 'ggml-large-v3-turbo.bin',
      url:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin',
      sizeBytes: 1550 * 1024 * 1024,
      checksum: '',
      description: 'Faster large-v3 variant — ~1.5 GB',
    ),
    // Distil-Whisper Large v3 — 6× faster + ~50% smaller than large-v3.
    // cstr/distil-large-v3-GGUF mirrors the upstream weights as plain
    // .bin (whisper.cpp loader expects that, not .gguf). The same repo
    // ships f16 / q8_0 / q5_0 / q4_k / iq2_xs etc. — refreshAvailableQuants()
    // auto-discovers the rest via the matching BackendRepo entry below.
    'distil-large-v3': ModelDefinition(
      name: 'distil-large-v3',
      displayName: 'Distil-Whisper Large v3',
      fileName: 'distil-large-v3.bin',
      url:
          'https://huggingface.co/cstr/distil-large-v3-GGUF/resolve/main/distil-large-v3.bin',
      sizeBytes: 1530 * 1024 * 1024,
      checksum: '',
      description:
          'Distilled Whisper Large v3 (English) — ~1.5 GB, faster decode',
      languages: langsEn,
    ),
    'distil-large-v3-q5_0': ModelDefinition(
      name: 'distil-large-v3-q5_0',
      displayName: 'Distil-Whisper Large v3 (q5_0)',
      fileName: 'distil-large-v3-q5_0.bin',
      url:
          'https://huggingface.co/cstr/distil-large-v3-GGUF/resolve/main/distil-large-v3-q5_0.bin',
      sizeBytes: 590 * 1024 * 1024,
      checksum: '',
      description: 'Distil-Whisper Large v3 (English), q5_0 — ~590 MB',
      quantization: 'q5_0',
      languages: langsEn,
    ),

    // ----- Quantized variants (public ggerganov/whisper.cpp files) -----
    // Every URL here is verified against the PUBLIC repo listing. The
    // historical cstr/whisper-ggml-quants mirror turned private and
    // answered 401 to unauthenticated users, which broke the default
    // onboarding download (issue #35 follow-up, 2026-08-29). ggerganov
    // publishes q5_1 (not q5_0) for tiny/base/small, so those entries
    // carry the quant that actually exists; q4_0 / q2_k / large-v3-q8_0
    // have no public source and were dropped. Checksums intentionally
    // empty — size-only validation until we have authoritative SHAs.
    'tiny-q5_1': ModelDefinition(
      name: 'tiny-q5_1',
      displayName: 'Whisper Tiny (q5_1)',
      fileName: 'ggml-tiny-q5_1.bin',
      url: '$whisperCppBaseUrl/ggml-tiny-q5_1.bin',
      sizeBytes: 32152673,
      checksum: '',
      description: '5-bit quantized tiny — smaller, ~same accuracy',
      quantization: 'q5_1',
    ),
    'base-q5_1': ModelDefinition(
      name: 'base-q5_1',
      displayName: 'Whisper Base (q5_1)',
      fileName: 'ggml-base-q5_1.bin',
      url: '$whisperCppBaseUrl/ggml-base-q5_1.bin',
      sizeBytes: 59707625,
      checksum: '',
      description: '5-bit quantized base — ~60 MB',
      quantization: 'q5_1',
    ),
    'small-q5_1': ModelDefinition(
      name: 'small-q5_1',
      displayName: 'Whisper Small (q5_1)',
      fileName: 'ggml-small-q5_1.bin',
      url: '$whisperCppBaseUrl/ggml-small-q5_1.bin',
      sizeBytes: 190085487,
      checksum: '',
      description: '5-bit quantized small — ~190 MB',
      quantization: 'q5_1',
    ),
    'medium-q5_0': ModelDefinition(
      name: 'medium-q5_0',
      displayName: 'Whisper Medium (q5_0)',
      fileName: 'ggml-medium-q5_0.bin',
      url: '$whisperCppBaseUrl/ggml-medium-q5_0.bin',
      sizeBytes: 539212467,
      checksum: '',
      description: '5-bit quantized medium — ~540 MB',
      quantization: 'q5_0',
    ),
    'large-v3-q5_0': ModelDefinition(
      name: 'large-v3-q5_0',
      displayName: 'Whisper Large v3 (q5_0)',
      fileName: 'ggml-large-v3-q5_0.bin',
      url: '$whisperCppBaseUrl/ggml-large-v3-q5_0.bin',
      sizeBytes: 1081140203,
      checksum: '',
      description: '5-bit quantized large-v3 — ~1.1 GB',
      quantization: 'q5_0',
    ),
    'base-q8_0': ModelDefinition(
      name: 'base-q8_0',
      displayName: 'Whisper Base (q8_0)',
      fileName: 'ggml-base-q8_0.bin',
      url: '$whisperCppBaseUrl/ggml-base-q8_0.bin',
      sizeBytes: 81768585,
      checksum: '',
      description: '8-bit quantized base — ~78 MB',
      quantization: 'q8_0',
    ),
    'large-v3-turbo-german': ModelDefinition(
      name: 'large-v3-turbo-german',
      displayName: 'Whisper Large v3 Turbo (German)',
      fileName: 'ggml-large-v3-turbo-german.bin',
      url:
          'https://huggingface.co/cstr/whisper-large-v3-turbo-german-ggml/resolve/main/ggml-model.bin',
      sizeBytes: 1550 * 1024 * 1024,
      checksum: '',
      description: 'Fine-tuned German turbo model — ~1.5 GB',
    ),
  };

  /// Non-Whisper ASR backends CrispASR supports. These download + show up in
  /// the model manager today; full FFI runtime for every one of them is
  /// still being rolled out (tracked in `docs/crispasr-dart-gaps.md`).
  /// The `backend` field names the CrispASR backend id — matches
  /// `crispasr --list-backends`.
  static const Map<String, ModelDefinition> crispasrBackendModels = {
    // Parakeet — NVIDIA TDT, very fast English ASR with word timestamps.
    'parakeet-tdt-0.6b-v3-q4_k': ModelDefinition(
      name: 'parakeet-tdt-0.6b-v3-q4_k',
      displayName: 'Parakeet TDT 0.6B v3 (q4_k)',
      fileName: 'parakeet-tdt-0.6b-v3-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-tdt-0.6b-v3-GGUF/resolve/main/parakeet-tdt-0.6b-v3-q4_k.gguf',
      sizeBytes: 467 * 1024 * 1024,
      checksum: '',
      description: 'Fast English ASR (NVIDIA Parakeet) — ~467 MB',
      quantization: 'q4_k',
      backend: 'parakeet',
    ),
    'parakeet-tdt-0.6b-v2-q4_k': ModelDefinition(
      name: 'parakeet-tdt-0.6b-v2-q4_k',
      displayName: 'Parakeet TDT 0.6B v2 (q4_k)',
      fileName: 'parakeet-tdt-0.6b-v2-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-tdt-0.6b-v2-GGUF/resolve/main/parakeet-tdt-0.6b-v2-q4_k.gguf',
      sizeBytes: 467 * 1024 * 1024,
      checksum: '',
      description: 'Parakeet TDT v2 (earlier vocab) — ~467 MB',
      quantization: 'q4_k',
      backend: 'parakeet',
    ),
    'parakeet-tdt-1.1b-q4_k': ModelDefinition(
      name: 'parakeet-tdt-1.1b-q4_k',
      displayName: 'Parakeet TDT 1.1B (q4_k)',
      fileName: 'parakeet-tdt-1.1b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-tdt-1.1b-GGUF/resolve/main/parakeet-tdt-1.1b-q4_k.gguf',
      sizeBytes: 850 * 1024 * 1024,
      checksum: '',
      description: 'Larger Parakeet TDT, 42-layer encoder — ~850 MB',
      quantization: 'q4_k',
      backend: 'parakeet',
    ),
    // Canary — NVIDIA, translation-capable (X→en, en→X).
    'canary-1b-v2-q5_0': ModelDefinition(
      name: 'canary-1b-v2-q5_0',
      displayName: 'Canary 1B v2 (q5_0)',
      fileName: 'canary-1b-v2-q5_0.gguf',
      url:
          'https://huggingface.co/cstr/canary-1b-v2-GGUF/resolve/main/canary-1b-v2-q5_0.gguf',
      sizeBytes: 600 * 1024 * 1024,
      checksum: '',
      description: 'Multilingual ASR with speech-translation — ~600 MB',
      quantization: 'q5_0',
      backend: 'canary',
    ),
    // Cohere / Granite / FastConformer-CTC / Wav2Vec2 have the widest
    // naming drift between our guess and the actual HF layouts, so they
    // are populated lazily via refreshAvailableQuants() (auto-probed on
    // model-manager open). No hardcoded entries here — the probe builds
    // them with real sizes + correct URLs at runtime.
    // Voxtral — speech translation (Mistral family).
    'voxtral-mini-3b-2507-q4_k': ModelDefinition(
      name: 'voxtral-mini-3b-2507-q4_k',
      displayName: 'Voxtral Mini 3B 2507 (q4_k)',
      fileName: 'voxtral-mini-3b-2507-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/voxtral-mini-3b-2507-GGUF/resolve/main/voxtral-mini-3b-2507-q4_k.gguf',
      sizeBytes: 2500 * 1024 * 1024,
      checksum: '',
      description: 'Speech translation + ASR — ~2.5 GB',
      quantization: 'q4_k',
      backend: 'voxtral',
    ),
    // Voxtral 4B — realtime variant.
    'voxtral-mini-4b-realtime-q4_k': ModelDefinition(
      name: 'voxtral-mini-4b-realtime-q4_k',
      displayName: 'Voxtral Mini 4B realtime (q4_k)',
      fileName: 'voxtral-mini-4b-realtime-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/voxtral-mini-4b-realtime-GGUF/resolve/main/voxtral-mini-4b-realtime-q4_k.gguf',
      sizeBytes: 3300 * 1024 * 1024,
      checksum: '',
      description: 'Voxtral realtime tuning — ~3.3 GB',
      quantization: 'q4_k',
      backend: 'voxtral4b',
    ),
    // Qwen3-ASR — 30+ languages incl. Chinese dialects.
    'qwen3-asr-0.6b-q4_k': ModelDefinition(
      name: 'qwen3-asr-0.6b-q4_k',
      displayName: 'Qwen3-ASR 0.6B (q4_k)',
      fileName: 'qwen3-asr-0.6b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-asr-0.6b-GGUF/resolve/main/qwen3-asr-0.6b-q4_k.gguf',
      sizeBytes: 380 * 1024 * 1024,
      checksum: '',
      description: 'Multilingual (30+ langs, incl. Chinese dialects) — ~380 MB',
      quantization: 'q4_k',
      backend: 'qwen3',
    ),
    'qwen3-asr-1.7b-q4_k': ModelDefinition(
      name: 'qwen3-asr-1.7b-q4_k',
      displayName: 'Qwen3-ASR 1.7B (q4_k)',
      fileName: 'qwen3-asr-1.7b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-asr-1.7b-GGUF/resolve/main/qwen3-asr-1.7b-q4_k.gguf',
      sizeBytes: 1100 * 1024 * 1024,
      checksum: '',
      description: 'Qwen3-ASR 1.7B, multilingual (30+ langs) — ~1.1 GB',
      quantization: 'q4_k',
      backend: 'qwen3',
    ),
    // Qwen3-ASR-1.7B-JA — Japanese anime/galgame speech fine-tune
    // (Apache-2.0). Same arch as qwen3-1.7b; uses the standard qwen3 backend.
    'qwen3-asr-1.7b-ja-anime-q4_k': ModelDefinition(
      name: 'qwen3-asr-1.7b-ja-anime-q4_k',
      displayName: 'Qwen3-ASR 1.7B JA Anime (q4_k)',
      fileName: 'qwen3-asr-1.7b-ja-anime-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-asr-1.7b-ja-anime-GGUF/resolve/main/qwen3-asr-1.7b-ja-anime-q4_k.gguf',
      sizeBytes: 1100 * 1024 * 1024,
      checksum: '',
      description:
          'Japanese anime/galgame speech fine-tune of Qwen3-ASR 1.7B — ~1.1 GB',
      quantization: 'q4_k',
      backend: 'qwen3',
      languages: const ['ja'],
    ),
    // Mega-ASR — Qwen3-ASR-1.7B with the upstream robustness LoRA merged
    // offline. Dispatches through the qwen3 code path in
    // crispasr_session_open_explicit but is advertised separately so
    // the front-door availableBackends() check accepts the alias and
    // the Models screen groups it under its own backend filter.
    'mega-asr-1.7b-q4_k': ModelDefinition(
      name: 'mega-asr-1.7b-q4_k',
      displayName: 'Mega-ASR 1.7B (q4_k)',
      fileName: 'mega-asr-1.7b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/mega-asr-GGUF/resolve/main/mega-asr-1.7b-q4_k.gguf',
      sizeBytes: 1300 * 1024 * 1024,
      checksum: '',
      description: 'Qwen3-ASR 1.7B + robustness LoRA — multilingual, ~1.3 GB',
      quantization: 'q4_k',
      backend: 'mega-asr',
    ),
    // Granite / FastConformer-CTC / Wav2Vec2 — populated by HF probe.
    'canary-1b-v2-f16': ModelDefinition(
      name: 'canary-1b-v2-f16',
      displayName: 'Canary 1B v2 (f16)',
      fileName: 'canary-1b-v2.gguf',
      url:
          'https://huggingface.co/cstr/canary-1b-v2-GGUF/resolve/main/canary-1b-v2.gguf',
      sizeBytes: 1965244512,
      checksum: '',
      description: 'High-precision Canary 1B — ~1.9 GB',
      quantization: 'f16',
      backend: 'canary',
    ),
    // OmniASR (LLM variant) — multilingual via lang= hint.
    'omniasr-llm-300m-v2-q4_k': ModelDefinition(
      name: 'omniasr-llm-300m-v2-q4_k',
      displayName: 'OmniASR LLM 300M v2 (q4_k)',
      fileName: 'omniasr-llm-300m-v2-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/omniasr-llm-300m-v2-GGUF/resolve/main/omniasr-llm-300m-v2-q4_k.gguf',
      sizeBytes: 580 * 1024 * 1024,
      checksum: '',
      description: 'OmniASR LLM 300M (multilingual) — ~580 MB',
      quantization: 'q4_k',
      backend: 'omniasr-llm',
    ),
    'omniasr-llm-1b-q4_k': ModelDefinition(
      name: 'omniasr-llm-1b-q4_k',
      displayName: 'OmniASR LLM 1B (q4_k)',
      fileName: 'omniasr-llm-1b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/omniasr-llm-1b-GGUF/resolve/main/omniasr-llm-1b-q4_k.gguf',
      sizeBytes: 1300 * 1024 * 1024,
      checksum: '',
      description: 'OmniASR LLM 1B (multilingual) — ~1.3 GB',
      quantization: 'q4_k',
      backend: 'omniasr-llm',
    ),
    // Nemotron 3.5 — NVIDIA streaming ASR (cache-aware, 4 presets).
    'nemotron-3.5-asr-streaming-0.6b-q4_k': ModelDefinition(
      name: 'nemotron-3.5-asr-streaming-0.6b-q4_k',
      displayName: 'Nemotron 3.5 ASR Streaming 0.6B (q4_k)',
      fileName: 'nemotron-3.5-asr-streaming-0.6b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/nemotron-3.5-asr-streaming-0.6b-GGUF/resolve/main/nemotron-3.5-asr-streaming-0.6b-q4_k.gguf',
      sizeBytes: 458 * 1024 * 1024,
      checksum: '',
      description: 'Nemotron 3.5 streaming ASR — ~458 MB',
      quantization: 'q4_k',
      backend: 'nemotron',
      languages: langsAll,
    ),
    // FunASR — Alibaba's compact ASR (Chinese + English). cstr/funasr-nano-GGUF
    // ships f16 + q4_k + q8_0; the BackendRepo below makes the HF probe
    // auto-discover any future iq2_xs sibling.
    'funasr-nano-2512-q4_k': ModelDefinition(
      name: 'funasr-nano-2512-q4_k',
      displayName: 'FunASR Nano 2512 (q4_k)',
      fileName: 'funasr-nano-2512-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/funasr-nano-GGUF/resolve/main/funasr-nano-2512-q4_k.gguf',
      sizeBytes: 896875328,
      checksum: '',
      description: 'FunASR Nano (Mandarin + English), q4_k — ~897 MB',
      quantization: 'q4_k',
      backend: 'funasr',
    ),
    'funasr-nano-2512-f16': ModelDefinition(
      name: 'funasr-nano-2512-f16',
      displayName: 'FunASR Nano 2512 (f16)',
      fileName: 'funasr-nano-2512-f16.gguf',
      url:
          'https://huggingface.co/cstr/funasr-nano-GGUF/resolve/main/funasr-nano-2512-f16.gguf',
      sizeBytes: 200 * 1024 * 1024,
      checksum: '',
      description: 'FunASR Nano (Mandarin + English) — ~200 MB',
      quantization: 'f16',
      backend: 'funasr',
    ),
    'funasr-mlt-nano-2512-q4_k': ModelDefinition(
      name: 'funasr-mlt-nano-2512-q4_k',
      displayName: 'FunASR MLT Nano 2512 (q4_k)',
      fileName: 'funasr-mlt-nano-2512-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/funasr-mlt-nano-GGUF/resolve/main/funasr-mlt-nano-2512-q4_k.gguf',
      sizeBytes: 896875328,
      checksum: '',
      description: 'FunASR multilingual Nano, q4_k — ~897 MB',
      quantization: 'q4_k',
      backend: 'funasr',
    ),
    'funasr-mlt-nano-2512-f16': ModelDefinition(
      name: 'funasr-mlt-nano-2512-f16',
      displayName: 'FunASR MLT Nano 2512 (f16)',
      fileName: 'funasr-mlt-nano-2512-f16.gguf',
      url:
          'https://huggingface.co/cstr/funasr-mlt-nano-GGUF/resolve/main/funasr-mlt-nano-2512-f16.gguf',
      sizeBytes: 220 * 1024 * 1024,
      checksum: '',
      description: 'FunASR multilingual Nano — ~220 MB',
      quantization: 'f16',
      backend: 'funasr',
    ),
    // Paraformer — FunASR family, Mandarin-focused NAR ASR.
    'paraformer-zh-q4_k': ModelDefinition(
      name: 'paraformer-zh-q4_k',
      displayName: 'Paraformer ZH (q4_k)',
      fileName: 'paraformer-zh-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/paraformer-zh-GGUF/resolve/main/paraformer-zh-q4_k.gguf',
      sizeBytes: 180 * 1024 * 1024,
      checksum: '',
      description: 'Paraformer Mandarin NAR-ASR — ~180 MB',
      quantization: 'q4_k',
      backend: 'paraformer',
    ),
    // SenseVoice — multi-lingual + LID-tagged.
    'sensevoice-small-q4_k': ModelDefinition(
      name: 'sensevoice-small-q4_k',
      displayName: 'SenseVoice Small (q4_k)',
      fileName: 'sensevoice-small-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/sensevoice-small-GGUF/resolve/main/sensevoice-small-q4_k.gguf',
      sizeBytes: 250 * 1024 * 1024,
      checksum: '',
      description:
          'SenseVoice Small (ZH/EN/JA/KO/YUE) with built-in lang-id — ~250 MB',
      quantization: 'q4_k',
      backend: 'sensevoice',
    ),
    // FireRed ASR2 — AED Mandarin/English ASR.
    'firered-asr2-aed-q4_k': ModelDefinition(
      name: 'firered-asr2-aed-q4_k',
      displayName: 'FireRed ASR2 AED (q4_k)',
      fileName: 'firered-asr2-aed-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/firered-asr2-aed-GGUF/resolve/main/firered-asr2-aed-q4_k.gguf',
      sizeBytes: 918 * 1024 * 1024,
      checksum: '',
      description: 'FireRed ASR2 AED (zh/en) — ~918 MB',
      quantization: 'q4_k',
      backend: 'firered-asr',
    ),
    // Kyutai STT 1B.
    'kyutai-stt-1b-q4_k': ModelDefinition(
      name: 'kyutai-stt-1b-q4_k',
      displayName: 'Kyutai STT 1B (q4_k)',
      fileName: 'kyutai-stt-1b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/kyutai-stt-1b-GGUF/resolve/main/kyutai-stt-1b-q4_k.gguf',
      sizeBytes: 636 * 1024 * 1024,
      checksum: '',
      description: 'Kyutai streaming-style STT 1B — ~636 MB',
      quantization: 'q4_k',
      backend: 'kyutai-stt',
    ),
    // GLM-ASR Nano.
    'glm-asr-nano-q4_k': ModelDefinition(
      name: 'glm-asr-nano-q4_k',
      displayName: 'GLM-ASR Nano (q4_k)',
      fileName: 'glm-asr-nano-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/glm-asr-nano-GGUF/resolve/main/glm-asr-nano-q4_k.gguf',
      sizeBytes: 1200 * 1024 * 1024,
      checksum: '',
      description: 'GLM-family multilingual ASR — ~1.2 GB',
      quantization: 'q4_k',
      backend: 'glm-asr',
    ),
    // Moonshine — UsefulSensors lightweight ASR. Tiny + base variants
    // ship q4_k and q8_0 quants; the LM-streaming siblings live in
    // their own repos under `moonshine-streaming-tiny-GGUF`.
    'moonshine-tiny-q4_k': ModelDefinition(
      name: 'moonshine-tiny-q4_k',
      displayName: 'Moonshine tiny (q4_k)',
      fileName: 'moonshine-tiny-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/moonshine-tiny-GGUF/resolve/main/moonshine-tiny-q4_k.gguf',
      sizeBytes: 21199840,
      checksum: '',
      description: 'Moonshine tiny ASR (English, lightweight) — ~21 MB',
      quantization: 'q4_k',
      backend: 'moonshine',
      // moonshine_init() in CrispASR reads the BPE tokenizer from
      // `dir_of(model_path) + "/tokenizer.bin"` at session-open time.
      // Without this companion the open call returns null and the
      // load looks like "GGUF backend isn't supported" even though the
      // backend IS in availableBackends(). (Reported on #7 second wave
      // after the buffer-truncation fix made the error string honest.)
      companions: ['moonshine-tokenizer'],
    ),
    'moonshine-base-q4_k': ModelDefinition(
      name: 'moonshine-base-q4_k',
      displayName: 'Moonshine base (q4_k)',
      fileName: 'moonshine-base-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/moonshine-base-GGUF/resolve/main/moonshine-base-q4_k.gguf',
      sizeBytes: 46923872,
      checksum: '',
      description: 'Moonshine base ASR (English, lightweight) — ~47 MB',
      quantization: 'q4_k',
      backend: 'moonshine',
      companions: ['moonshine-tokenizer'],
    ),
    'moonshine-streaming-tiny-q4_k': ModelDefinition(
      name: 'moonshine-streaming-tiny-q4_k',
      displayName: 'Moonshine streaming tiny (q4_k)',
      fileName: 'moonshine-streaming-tiny-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/moonshine-streaming-tiny-GGUF/resolve/main/moonshine-streaming-tiny-q4_k.gguf',
      sizeBytes: 32052896,
      checksum: '',
      description: 'Moonshine streaming tiny — for live mic streaming, ~32 MB',
      quantization: 'q4_k',
      backend: 'moonshine-streaming',
      companions: ['moonshine-tokenizer'],
    ),
    // Shared BPE tokenizer for the moonshine family. CrispASR's
    // moonshine_init resolves `dir_of(model_path) + "/tokenizer.bin"`
    // at session-open time so this just needs to land alongside the
    // GGUF — the engine's setCodecPath call is a no-op for moonshine,
    // it's the filesystem co-location that matters. tiny + base share
    // the English BPE; moonshine-streaming uses the same English vocab
    // so reusing one tokenizer is correct.
    'moonshine-tokenizer': ModelDefinition(
      name: 'moonshine-tokenizer',
      displayName: 'Moonshine BPE tokenizer',
      fileName: 'tokenizer.bin',
      url:
          'https://huggingface.co/cstr/moonshine-tiny-GGUF/resolve/main/tokenizer.bin',
      // Tokenizer.bin is small (~few hundred KB). Hardcoded estimate
      // avoids a HEAD request just for the size — accuracy isn't
      // load-bearing for a sub-MB file.
      sizeBytes: 500 * 1024,
      checksum: '',
      description:
          'BPE tokenizer for the moonshine family (English) — required companion',
      backend: 'moonshine',
      // kind=codec so the catalogue-invariants test doesn't flag
      // this entry as "moonshine ASR without a tokenizer companion"
      // — it IS the tokenizer companion. Same shape as
      // mimo-tokenizer-q4_k / snac-24khz / qwen3-tts-tokenizer-12hz.
      kind: ModelKind.codec,
    ),
    // VibeVoice ASR (the ASR variant; the TTS sibling is vibevoice-tts).
    'vibevoice-asr-q4_k': ModelDefinition(
      name: 'vibevoice-asr-q4_k',
      displayName: 'VibeVoice ASR (q4_k)',
      fileName: 'vibevoice-asr-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/vibevoice-asr-GGUF/resolve/main/vibevoice-asr-q4_k.gguf',
      sizeBytes: 4500 * 1024 * 1024,
      checksum: '',
      description: 'VibeVoice large multilingual ASR — ~4.5 GB',
      quantization: 'q4_k',
      backend: 'vibevoice',
    ),
    // MiMo ASR — XiaomiMiMo MiMo-V2.5 ASR (input_local_transformer + Qwen2 LLM).
    // Needs the mimo-tokenizer-*.gguf companion alongside; load via
    // setCodecPath after open.
    'mimo-asr-q4_k': ModelDefinition(
      name: 'mimo-asr-q4_k',
      displayName: 'MiMo ASR (q4_k)',
      fileName: 'mimo-asr-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/mimo-asr-GGUF/resolve/main/mimo-asr-q4_k.gguf',
      sizeBytes: 4500 * 1024 * 1024,
      checksum: '',
      description: 'XiaomiMiMo MiMo-Audio ASR — ~4.5 GB '
          '(needs mimo-tokenizer-*.gguf companion)',
      quantization: 'q4_k',
      backend: 'mimo-asr',
      companions: ['mimo-tokenizer-q4_k'],
    ),
    'mimo-tokenizer-q4_k': ModelDefinition(
      name: 'mimo-tokenizer-q4_k',
      displayName: 'MiMo audio tokenizer (q4_k)',
      fileName: 'mimo-tokenizer-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/mimo-tokenizer-GGUF/resolve/main/mimo-tokenizer-q4_k.gguf',
      sizeBytes: 395594656,
      checksum: '',
      description:
          'MiMo audio tokenizer — companion to mimo-asr (PCM → 8-channel codes)',
      quantization: 'q4_k',
      backend: 'mimo-asr',
      kind: ModelKind.codec,
    ),
    // FireRedPunc — punctuation-restoration POST-PROCESSOR. Not a stand-
    // alone ASR backend; loaded via crispasr.PuncModel and applied to
    // segment text after the chosen ASR backend produces output. Useful
    // for CTC backends (wav2vec2 / fastconformer-ctc / firered-asr) that
    // emit unpunctuated lowercase text.
    'fireredpunc-q8_0': ModelDefinition(
      name: 'fireredpunc-q8_0',
      displayName: 'FireRedPunc (q8_0) — punctuation post-processor',
      fileName: 'fireredpunc-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/fireredpunc-GGUF/resolve/main/fireredpunc-q8_0.gguf',
      sizeBytes: 100 * 1024 * 1024,
      checksum: '',
      description:
          'BERT-based punctuation restoration. Enable "Restore punctuation" '
          'in Advanced decoding once downloaded.',
      quantization: 'q8_0',
      backend: 'firered-punc',
      kind: ModelKind.punc,
    ),
    // ---------------------- TTS main models ----------------------
    'kokoro-82m-q8_0': ModelDefinition(
      name: 'kokoro-82m-q8_0',
      displayName: 'Kokoro 82M (q8_0)',
      fileName: 'kokoro-82m-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/kokoro-82m-GGUF/resolve/main/kokoro-82m-q8_0.gguf',
      sizeBytes: 100 * 1024 * 1024,
      checksum: '',
      description: 'Kokoro TTS (EN/DE/FR/ES in GPL-free builds) — '
          'needs a kokoro-voice-*.gguf',
      quantization: 'q8_0',
      backend: 'kokoro',
      kind: ModelKind.tts,
      companions: ['kokoro-voice-af_heart'],
      languages: <String>['en', 'de', 'fr', 'es'],
    ),
    // VibeVoice realtime 0.5B — the `-tts-` infix marks the variant that
    // bundles the Tekken tokenizer (the plain `-q4_k` / `-q8_0` variants
    // are tokenizer-less and fail at first synth). Use the f16 tokenizer
    // variant as the single-file shippable.
    'vibevoice-realtime-0.5b-tts-f16': ModelDefinition(
      name: 'vibevoice-realtime-0.5b-tts-f16',
      displayName: 'VibeVoice TTS realtime 0.5B (f16 + tokenizer)',
      fileName: 'vibevoice-realtime-0.5b-tts-f16.gguf',
      url:
          'https://huggingface.co/cstr/vibevoice-realtime-0.5b-GGUF/resolve/main/vibevoice-realtime-0.5b-tts-f16.gguf',
      sizeBytes: 2100 * 1024 * 1024,
      checksum: '',
      description: 'VibeVoice realtime TTS with bundled Tekken tokenizer — '
          'needs a vibevoice-voice-*.gguf voicepack',
      quantization: 'f16',
      backend: 'vibevoice-tts',
      kind: ModelKind.tts,
      companions: ['vibevoice-voice-en-Emma_woman'],
    ),
    // VibeVoice 1.5B — the larger TTS variant (distinct backend string
    // from the realtime 0.5B `vibevoice-tts` above). Needs a voicepack.
    'vibevoice-1.5b-tts-q4_k': ModelDefinition(
      name: 'vibevoice-1.5b-tts-q4_k',
      displayName: 'VibeVoice 1.5B TTS (q4_k)',
      fileName: 'vibevoice-1.5b-tts-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/vibevoice-1.5b-GGUF/resolve/main/vibevoice-1.5b-tts-q4_k.gguf',
      sizeBytes: 1638 * 1024 * 1024,
      checksum: '',
      description:
          'VibeVoice 1.5B TTS — needs a vibevoice-voice-*.gguf voicepack',
      quantization: 'q4_k',
      backend: 'vibevoice-1.5b',
      kind: ModelKind.tts,
      languages: langsVibevoiceTts10,
      companions: ['vibevoice-voice-en-Emma_woman'],
    ),
    // TADA-3B-ML (HumeAI) — Llama-3.2-3B + flow matching + TADA codec.
    // Heavy (f16 only): ~6.6 GB main + ~1 GB codec companion.
    'tada-tts-3b-ml-f16': ModelDefinition(
      name: 'tada-tts-3b-ml-f16',
      displayName: 'TADA TTS 3B ML (f16)',
      fileName: 'tada-tts-3b-ml-f16.gguf',
      url:
          'https://huggingface.co/cstr/tada-tts-3b-ml-GGUF/resolve/main/tada-tts-3b-ml-f16.gguf',
      sizeBytes: 6758 * 1024 * 1024,
      checksum: '',
      description: 'TADA 3B multilingual TTS — needs the tada-codec-f16 codec',
      quantization: 'f16',
      backend: 'tada',
      kind: ModelKind.tts,
      languages: langsAll,
      companions: ['tada-codec-f16'],
    ),
    'tada-codec-f16': ModelDefinition(
      name: 'tada-codec-f16',
      displayName: 'TADA codec (f16)',
      fileName: 'tada-codec-f16.gguf',
      url:
          'https://huggingface.co/cstr/tada-tts-3b-ml-GGUF/resolve/main/tada-codec-f16.gguf',
      sizeBytes: 1024 * 1024 * 1024,
      checksum: '',
      description: 'TADA TTS codec (load via setCodecPath)',
      quantization: 'f16',
      backend: 'tada',
      kind: ModelKind.codec,
    ),
    'qwen3-tts-12hz-0.6b-base-q8_0': ModelDefinition(
      name: 'qwen3-tts-12hz-0.6b-base-q8_0',
      displayName: 'Qwen3-TTS 0.6B base 12 Hz (q8_0)',
      fileName: 'qwen3-tts-12hz-0.6b-base-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-tts-0.6b-base-GGUF/resolve/main/qwen3-tts-12hz-0.6b-base-q8_0.gguf',
      sizeBytes: 700 * 1024 * 1024,
      checksum: '',
      description:
          'Qwen3-TTS base — needs the qwen3-tts-tokenizer-12hz codec GGUF + voice',
      quantization: 'q8_0',
      backend: 'qwen3-tts',
      kind: ModelKind.tts,
      companions: ['qwen3-tts-tokenizer-12hz'],
      requiresVoice: true,
    ),
    // #18 — qwen3-tts CustomVoice has no BackendRepo (the deep HF probe
    // can't surface it), so without a hardcoded entry it never appears in
    // the Synthesize picker on a fresh launch. Mirrors the base entry; the
    // 9 baked preset speakers are selected via the Synthesize speaker
    // dropdown (#17). 0.6B q8_0 = ~923 MB (HF blob size).
    'qwen3-tts-12hz-0.6b-customvoice-q8_0': ModelDefinition(
      name: 'qwen3-tts-12hz-0.6b-customvoice-q8_0',
      displayName: 'Qwen3-TTS 0.6B CustomVoice 12 Hz (q8_0)',
      fileName: 'qwen3-tts-12hz-0.6b-customvoice-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-tts-0.6b-customvoice-GGUF/resolve/main/qwen3-tts-12hz-0.6b-customvoice-q8_0.gguf',
      sizeBytes: 967980192,
      checksum: '',
      description: 'Qwen3-TTS CustomVoice (9 preset speakers) — needs the '
          'qwen3-tts-tokenizer-12hz codec GGUF; pick a speaker in Synthesize',
      quantization: 'q8_0',
      backend: 'qwen3-tts',
      kind: ModelKind.tts,
      companions: ['qwen3-tts-tokenizer-12hz'],
      languages: langsQwen3TtsCustom9,
    ),
    'orpheus-3b-base-q8_0': ModelDefinition(
      name: 'orpheus-3b-base-q8_0',
      displayName: 'Orpheus 3B base (q8_0)',
      fileName: 'orpheus-3b-base-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/orpheus-3b-base-GGUF/resolve/main/orpheus-3b-base-q8_0.gguf',
      sizeBytes: 3500 * 1024 * 1024,
      checksum: '',
      description: 'Orpheus 3B TTS — needs the snac-24khz codec GGUF',
      quantization: 'q8_0',
      backend: 'orpheus',
      kind: ModelKind.tts,
      companions: ['snac-24khz'],
    ),
    // VoxCPM2 — openbmb/VoxCPM2 tokenizer-free diffusion AR TTS, 29 langs,
    // zero-shot (no codec companion needed). Q4_K is the practical default;
    // F16 reference sits in the same repo.
    // GigaAM v3 — Russian ASR. The e2e revisions carry punctuation,
    // casing and inverse text normalisation in the vocabulary; RNN-T is
    // the accuracy pick (8.4% avg WER), CTC the faster one.
    'gigaam-v3-e2e-rnnt-q8_0': ModelDefinition(
      name: 'gigaam-v3-e2e-rnnt-q8_0',
      displayName: 'GigaAM v3 e2e-RNNT (q8_0)',
      fileName: 'gigaam-v3-e2e-rnnt-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/gigaam-v3-GGUF/resolve/main/gigaam-v3-e2e-rnnt-q8_0.gguf',
      sizeBytes: 248765312,
      checksum: '',
      description:
          'GigaAM v3 Russian ASR (RNN-T) — punctuation + casing + ITN, 8.4% avg WER',
      quantization: 'q8_0',
      backend: 'gigaam',
      kind: ModelKind.asr,
      languages: langsRuEn,
    ),
    'gigaam-v3-e2e-rnnt-q4_k': ModelDefinition(
      name: 'gigaam-v3-e2e-rnnt-q4_k',
      displayName: 'GigaAM v3 e2e-RNNT (q4_k)',
      fileName: 'gigaam-v3-e2e-rnnt-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/gigaam-v3-GGUF/resolve/main/gigaam-v3-e2e-rnnt-q4_k.gguf',
      sizeBytes: 154393472,
      checksum: '',
      description:
          'GigaAM v3 Russian ASR (RNN-T, small) — punctuation + casing + ITN',
      quantization: 'q4_k',
      backend: 'gigaam',
      kind: ModelKind.asr,
      languages: langsRuEn,
    ),
    'gigaam-v3-e2e-ctc-q8_0': ModelDefinition(
      name: 'gigaam-v3-e2e-ctc-q8_0',
      displayName: 'GigaAM v3 e2e-CTC (q8_0)',
      fileName: 'gigaam-v3-e2e-ctc-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/gigaam-v3-GGUF/resolve/main/gigaam-v3-e2e-ctc-q8_0.gguf',
      sizeBytes: 245483264,
      checksum: '',
      description:
          'GigaAM v3 Russian ASR (CTC, faster) — punctuation + casing + ITN',
      quantization: 'q8_0',
      backend: 'gigaam',
      kind: ModelKind.asr,
      languages: langsRuEn,
    ),
    // MioTTS 0.6B — Qwen3 + MioCodec-v2 FSQ, 44.1 kHz. Self-contained
    // (codec baked in); ja/en only.
    'miotts-0.6b-q4_k': ModelDefinition(
      name: 'miotts-0.6b-q4_k',
      displayName: 'MioTTS 0.6B (q4_k)',
      fileName: 'miotts-0.6b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/miotts-0.6b-GGUF/resolve/main/miotts-0.6b-q4_k.gguf',
      sizeBytes: 526181408,
      checksum: '',
      description: 'MioTTS 0.6B — Qwen3 + MioCodec-v2 FSQ TTS, 44.1 kHz',
      quantization: 'q4_k',
      backend: 'miotts',
      kind: ModelKind.tts,
      languages: langsJaEn,
    ),
    'miotts-0.6b-q8_0': ModelDefinition(
      name: 'miotts-0.6b-q8_0',
      displayName: 'MioTTS 0.6B (q8_0)',
      fileName: 'miotts-0.6b-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/miotts-0.6b-GGUF/resolve/main/miotts-0.6b-q8_0.gguf',
      sizeBytes: 830596128,
      checksum: '',
      description:
          'MioTTS 0.6B — Qwen3 + MioCodec-v2 FSQ TTS, 44.1 kHz (recommended)',
      quantization: 'q8_0',
      backend: 'miotts',
      kind: ModelKind.tts,
      languages: langsJaEn,
    ),
    // MOSS-TTS-Local v1.5 — Qwen3-4B backbone; the codec is a separate
    // 2.1 GB GGUF passed via --codec-model, so every quant carries it as
    // a companion.
    'moss-tts-local-v1.5-q4_k': ModelDefinition(
      name: 'moss-tts-local-v1.5-q4_k',
      displayName: 'MOSS-TTS-Local v1.5 (q4_k)',
      fileName: 'moss-tts-local-v1.5-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/moss-tts-local-v1.5-GGUF/resolve/main/moss-tts-local-v1.5-q4_k.gguf',
      sizeBytes: 3883732480,
      checksum: '',
      description:
          'MOSS-TTS-Local v1.5 — Qwen3-4B RQ-Transformer TTS, 48 kHz, multilingual',
      quantization: 'q4_k',
      backend: 'moss-tts-local',
      kind: ModelKind.tts,
      languages: langsAll,
      companions: ['moss-tts-local-v1.5-codec'],
    ),
    'moss-tts-local-v1.5-q8_0': ModelDefinition(
      name: 'moss-tts-local-v1.5-q8_0',
      displayName: 'MOSS-TTS-Local v1.5 (q8_0)',
      fileName: 'moss-tts-local-v1.5-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/moss-tts-local-v1.5-GGUF/resolve/main/moss-tts-local-v1.5-q8_0.gguf',
      sizeBytes: 5700390400,
      checksum: '',
      description:
          'MOSS-TTS-Local v1.5 — Qwen3-4B RQ-Transformer TTS, 48 kHz (recommended)',
      quantization: 'q8_0',
      backend: 'moss-tts-local',
      kind: ModelKind.tts,
      languages: langsAll,
      companions: ['moss-tts-local-v1.5-codec'],
    ),
    'moss-tts-local-v1.5-codec': ModelDefinition(
      name: 'moss-tts-local-v1.5-codec',
      displayName: 'MOSS-Audio-Tokenizer v2 (codec)',
      fileName: 'moss-tts-local-v1.5-codec.gguf',
      url:
          'https://huggingface.co/cstr/moss-tts-local-v1.5-GGUF/resolve/main/moss-tts-local-v1.5-codec.gguf',
      sizeBytes: 2125483072,
      checksum: '',
      description:
          'MOSS-Audio-Tokenizer-v2 RVQ decoder — required companion for moss-tts-local',
      backend: 'moss-tts-local',
      kind: ModelKind.codec,
    ),
    'voxcpm2-q4_k': ModelDefinition(
      name: 'voxcpm2-q4_k',
      displayName: 'VoxCPM2 (q4_k)',
      fileName: 'voxcpm2-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/voxcpm2-GGUF/resolve/main/voxcpm2-q4_k.gguf',
      sizeBytes: 1689498432,
      checksum: '',
      description: 'VoxCPM2 diffusion TTS — zero-shot, 29 languages, 48 kHz',
      quantization: 'q4_k',
      backend: 'voxcpm2-tts',
      kind: ModelKind.tts,
      languages: langsVoxcpm2_29,
    ),
    'voxcpm2-f16': ModelDefinition(
      name: 'voxcpm2-f16',
      displayName: 'VoxCPM2 (f16)',
      fileName: 'voxcpm2-f16.gguf',
      url:
          'https://huggingface.co/cstr/voxcpm2-GGUF/resolve/main/voxcpm2-f16.gguf',
      sizeBytes: 4972550208,
      checksum: '',
      description:
          'VoxCPM2 diffusion TTS (f16 reference) — 29 languages, 48 kHz',
      quantization: 'f16',
      backend: 'voxcpm2-tts',
      kind: ModelKind.tts,
      languages: langsVoxcpm2_29,
    ),
    // F5-TTS v1 Base (cstr/f5-tts-GGUF) — DiT flow-matching TTS with a
    // baked-in Vocos vocoder, so it ships as a single self-contained GGUF
    // (no codec/vocoder companion). 24 kHz, character-level tokenizer,
    // zero-shot voice cloning from a reference WAV + its transcript.
    // English. Audio-verified 2026-05-31 (TTS→ASR roundtrip, words survive
    // cleanly) — but the DiT synth is VERY slow on the current CPU/Metal
    // build (~tens of minutes per sentence), so the description warns users.
    'f5-tts-v1-base-f16': ModelDefinition(
      name: 'f5-tts-v1-base-f16',
      displayName: 'F5-TTS v1 Base (f16)',
      fileName: 'f5-tts-v1-base-f16.gguf',
      url:
          'https://huggingface.co/cstr/f5-tts-GGUF/resolve/main/f5-tts-v1-base-f16.gguf',
      sizeBytes: 999097152,
      checksum: '',
      description:
          'F5-TTS DiT flow-matching TTS — zero-shot voice clone from a reference WAV (English, 24 kHz). Note: synthesis is very slow.',
      quantization: 'f16',
      backend: 'f5-tts',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    // Piper (rhasspy/piper) — tiny single-file VITS voices (~15-60 MB),
    // 22.05 kHz (the engine resamples to the host's 24 kHz), 30+ langs.
    // No companion: the phoneme map + espeak voice are baked into the GGUF.
    // Only permissively-licensed voices are catalogued: the German
    // Thorsten-Voice set is CC0, en_GB-cori is public domain. (Restrictive
    // upstream voices like en_US-lessac (Blizzard 2013, research-only) are
    // deliberately excluded — see cstr/piper-voices-GGUF's model card.)
    'piper-de-thorsten-medium': ModelDefinition(
      name: 'piper-de-thorsten-medium',
      displayName: 'Piper de Thorsten (medium)',
      fileName: 'piper-de_DE-thorsten-medium-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-de_DE-thorsten-medium-f16.gguf',
      sizeBytes: 31418528,
      checksum: '',
      description: 'Piper VITS TTS — German (Thorsten, medium). Tiny '
          '(~30 MB), fast on CPU. CC0.',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    'piper-de-thorsten-high': ModelDefinition(
      name: 'piper-de-thorsten-high',
      displayName: 'Piper de Thorsten (high)',
      fileName: 'piper-de_DE-thorsten-high-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-de_DE-thorsten-high-f16.gguf',
      sizeBytes: 56770752,
      checksum: '',
      description: 'Piper VITS TTS — German (Thorsten, high quality, '
          '~54 MB). CC0.',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    'piper-de-thorsten-emotional': ModelDefinition(
      name: 'piper-de-thorsten-emotional',
      displayName: 'Piper de Thorsten (emotional)',
      fileName: 'piper-de_DE-thorsten_emotional-medium-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-de_DE-thorsten_emotional-medium-f16.gguf',
      sizeBytes: 18048768,
      checksum: '',
      description: 'Piper VITS TTS — German (Thorsten emotional, ~17 MB). '
          'CC0.',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    'piper-en-cori': ModelDefinition(
      name: 'piper-en-cori',
      displayName: 'Piper en_GB Cori (medium)',
      fileName: 'piper-en_GB-cori-medium-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-en_GB-cori-medium-f16.gguf',
      sizeBytes: 31418496,
      checksum: '',
      description: 'Piper VITS TTS — English (GB, Cori, medium, ~30 MB). '
          'Public domain.',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    'piper-de-kerstin-low': ModelDefinition(
      name: 'piper-de-kerstin-low',
      displayName: 'Piper de Kerstin (low)',
      fileName: 'piper-de_DE-kerstin-low-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-de_DE-kerstin-low-f16.gguf',
      sizeBytes: 31369856,
      checksum: '',
      description: 'Piper VITS TTS — German (Kerstin, low, ~30 MB). CC0.',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    // mls + libritts_r are CC-BY 4.0 — attribution required when shipping
    // their audio (MLS / LibriTTS-R). See cstr/piper-voices-GGUF model card.
    'piper-de-mls-medium': ModelDefinition(
      name: 'piper-de-mls-medium',
      displayName: 'Piper de MLS (medium)',
      fileName: 'piper-de_DE-mls-medium-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-de_DE-mls-medium-f16.gguf',
      sizeBytes: 18282208,
      checksum: '',
      description: 'Piper VITS TTS — German (MLS, medium, ~17 MB). '
          'CC-BY 4.0 (attribution).',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    'piper-en-libritts-r-medium': ModelDefinition(
      name: 'piper-en-libritts-r-medium',
      displayName: 'Piper en_US LibriTTS-R (medium)',
      fileName: 'piper-en_US-libritts_r-medium-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-en_US-libritts_r-medium-f16.gguf',
      sizeBytes: 18966336,
      checksum: '',
      description: 'Piper VITS TTS — English (US, LibriTTS-R, medium, '
          '~18 MB). CC-BY 4.0 (attribution).',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    // M-AILABS German voices — BSD-style license (commercial + redistribution
    // OK if the copyright notice is retained; derived from LibriVox/Gutenberg
    // public-domain sources). See cstr/piper-voices-GGUF model card.
    'piper-de-eva_k-xlow': ModelDefinition(
      name: 'piper-de-eva_k-xlow',
      displayName: 'Piper de Eva K (x-low)',
      fileName: 'piper-de_DE-eva_k-x_low-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-de_DE-eva_k-x_low-f16.gguf',
      sizeBytes: 10089344,
      checksum: '',
      description: 'Piper VITS TTS — German (Eva K, x-low, ~10 MB). '
          'M-AILABS (BSD-style).',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    'piper-de-karlsson-low': ModelDefinition(
      name: 'piper-de-karlsson-low',
      displayName: 'Piper de Karlsson (low)',
      fileName: 'piper-de_DE-karlsson-low-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-de_DE-karlsson-low-f16.gguf',
      sizeBytes: 31369856,
      checksum: '',
      description: 'Piper VITS TTS — German (Karlsson, low, ~30 MB). '
          'M-AILABS (BSD-style).',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    'piper-de-ramona-low': ModelDefinition(
      name: 'piper-de-ramona-low',
      displayName: 'Piper de Ramona (low)',
      fileName: 'piper-de_DE-ramona-low-f16.gguf',
      url:
          'https://huggingface.co/cstr/piper-voices-GGUF/resolve/main/piper-de_DE-ramona-low-f16.gguf',
      sizeBytes: 31369856,
      checksum: '',
      description: 'Piper VITS TTS — German (Ramona, low, ~30 MB). '
          'M-AILABS (BSD-style).',
      quantization: 'f16',
      backend: 'piper',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    // CosyVoice3 0.5B-2512 (FunAudioLLM) — three-stage TTS (LLM AR → flow
    // Euler → HiFT vocoder), 24 kHz, zero-shot voice cloning via a baked
    // voices.gguf. The engine AUTO-DISCOVERS its flow/hift/voices (+
    // s3tok/campplus) siblings by filename next to the LLM GGUF, so we
    // list them all as companions — downloading the LLM pulls them into
    // the same models dir, which is what the engine needs. (setCodecPath
    // is a harmless no-op for cosyvoice3.)
    'cosyvoice3-llm-rl-q4_k': ModelDefinition(
      name: 'cosyvoice3-llm-rl-q4_k',
      displayName: 'CosyVoice3 0.5B RL (q4_k)',
      fileName: 'cosyvoice3-llm-rl-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/cosyvoice3-0.5b-2512-GGUF/resolve/main/cosyvoice3-llm-rl-q4_k.gguf',
      sizeBytes: 383891200,
      checksum: '',
      description: 'CosyVoice3 reinforcement-learning-tuned talker — '
          'optimized for speech quality, pronunciation, and stability',
      quantization: 'q4_k',
      backend: 'cosyvoice3-tts-rl',
      kind: ModelKind.tts,
      companions: [
        'cosyvoice3-flow-q8_0',
        'cosyvoice3-hift-f16',
        'cosyvoice3-voices',
        'cosyvoice3-s3tok-q4_k',
        'cosyvoice3-campplus-f16',
      ],
      languages: langsCosyvoice10,
    ),
    'cosyvoice3-llm-q4_k': ModelDefinition(
      name: 'cosyvoice3-llm-q4_k',
      displayName: 'CosyVoice3 0.5B (q4_k)',
      fileName: 'cosyvoice3-llm-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/cosyvoice3-0.5b-2512-GGUF/resolve/main/cosyvoice3-llm-q4_k.gguf',
      sizeBytes: 383891200,
      checksum: '',
      description:
          'CosyVoice3 streaming multilingual TTS — pulls flow/hift/voices companions',
      quantization: 'q4_k',
      backend: 'cosyvoice3-tts',
      kind: ModelKind.tts,
      companions: [
        'cosyvoice3-flow-q8_0',
        'cosyvoice3-hift-f16',
        'cosyvoice3-voices',
        'cosyvoice3-s3tok-q4_k',
        'cosyvoice3-campplus-f16',
      ],
      languages: langsCosyvoice10,
    ),
    'cosyvoice3-flow-q8_0': ModelDefinition(
      name: 'cosyvoice3-flow-q8_0',
      displayName: 'CosyVoice3 flow (q8_0)',
      fileName: 'cosyvoice3-flow-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/cosyvoice3-0.5b-2512-GGUF/resolve/main/cosyvoice3-flow-q8_0.gguf',
      sizeBytes: 360751936,
      checksum: '',
      description: 'CosyVoice3 flow-matching companion (auto-discovered)',
      quantization: 'q8_0',
      backend: 'cosyvoice3-tts',
      kind: ModelKind.codec,
    ),
    'cosyvoice3-hift-f16': ModelDefinition(
      name: 'cosyvoice3-hift-f16',
      displayName: 'CosyVoice3 HiFT vocoder (f16)',
      fileName: 'cosyvoice3-hift-f16.gguf',
      url:
          'https://huggingface.co/cstr/cosyvoice3-0.5b-2512-GGUF/resolve/main/cosyvoice3-hift-f16.gguf',
      sizeBytes: 41601888,
      checksum: '',
      description: 'CosyVoice3 HiFT vocoder companion (auto-discovered)',
      quantization: 'f16',
      backend: 'cosyvoice3-tts',
      kind: ModelKind.codec,
    ),
    'cosyvoice3-voices': ModelDefinition(
      name: 'cosyvoice3-voices',
      displayName: 'CosyVoice3 voice bank',
      fileName: 'cosyvoice3-voices.gguf',
      url:
          'https://huggingface.co/cstr/cosyvoice3-0.5b-2512-GGUF/resolve/main/cosyvoice3-voices.gguf',
      sizeBytes: 665472,
      checksum: '',
      description: 'CosyVoice3 baked voice bank (auto-discovered)',
      quantization: 'f16',
      backend: 'cosyvoice3-tts',
      kind: ModelKind.codec,
    ),
    'cosyvoice3-s3tok-q4_k': ModelDefinition(
      name: 'cosyvoice3-s3tok-q4_k',
      displayName: 'CosyVoice3 S3 tokenizer (q4_k)',
      fileName: 'cosyvoice3-s3tok-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/cosyvoice3-0.5b-2512-GGUF/resolve/main/cosyvoice3-s3tok-q4_k.gguf',
      sizeBytes: 145258240,
      checksum: '',
      description: 'CosyVoice3 S3 speech tokenizer companion (auto-discovered)',
      quantization: 'q4_k',
      backend: 'cosyvoice3-tts',
      kind: ModelKind.codec,
    ),
    'cosyvoice3-campplus-f16': ModelDefinition(
      name: 'cosyvoice3-campplus-f16',
      displayName: 'CosyVoice3 CAMPPlus speaker (f16)',
      fileName: 'cosyvoice3-campplus-f16.gguf',
      url:
          'https://huggingface.co/cstr/cosyvoice3-0.5b-2512-GGUF/resolve/main/cosyvoice3-campplus-f16.gguf',
      sizeBytes: 14153600,
      checksum: '',
      description:
          'CosyVoice3 CAMPPlus speaker-embedding companion (auto-discovered)',
      quantization: 'f16',
      backend: 'cosyvoice3-tts',
      kind: ModelKind.codec,
    ),
    // ---------------------- TTS voicepacks -----------------------
    'kokoro-voice-af_heart': ModelDefinition(
      name: 'kokoro-voice-af_heart',
      displayName: 'Kokoro voice — af_heart',
      fileName: 'kokoro-voice-af_heart.gguf',
      url:
          'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main/kokoro-voice-af_heart.gguf',
      sizeBytes: 1 * 1024 * 1024,
      checksum: '',
      description: 'Kokoro voicepack — English (af_heart) [lang=en]',
      quantization: 'f16',
      backend: 'kokoro',
      kind: ModelKind.voice,
      languages: langsEn,
    ),
    // NOTE (issue #35): the hand-written `vibevoice-voice-emma` row that
    // used to live here was removed. `cstr/vibevoice-realtime-0.5b-GGUF`
    // ships the same 2 740 832-byte voice under two filenames
    // (`vibevoice-voice-emma.gguf` and
    // `vibevoice-voice-en-Emma_woman.gguf`), so the Model Manager listed
    // Emma twice. The generated `vibevoice-voice-en-Emma_woman` entry in
    // [ttsVoicepacks] is the survivor — it matches the naming scheme of
    // the other 24 VibeVoice voices. `ModelService` renames an
    // already-downloaded legacy file on first run.
    // ---------------------- TTS codec / tokenizer ----------------
    'qwen3-tts-tokenizer-12hz': ModelDefinition(
      name: 'qwen3-tts-tokenizer-12hz',
      displayName: 'Qwen3-TTS tokenizer 12 Hz',
      fileName: 'qwen3-tts-tokenizer-12hz.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-tts-tokenizer-12hz-GGUF/resolve/main/qwen3-tts-tokenizer-12hz.gguf',
      sizeBytes: 80 * 1024 * 1024,
      checksum: '',
      description: 'Qwen3-TTS codec/tokenizer (load via setCodecPath)',
      quantization: 'f16',
      backend: 'qwen3-tts',
      kind: ModelKind.codec,
    ),
    'snac-24khz': ModelDefinition(
      name: 'snac-24khz',
      displayName: 'SNAC 24 kHz codec',
      fileName: 'snac-24khz.gguf',
      url:
          'https://huggingface.co/cstr/snac-24khz-GGUF/resolve/main/snac-24khz.gguf',
      sizeBytes: 50 * 1024 * 1024,
      checksum: '',
      description:
          'SNAC 24 kHz codec for Orpheus / Mini-Omni2 (load via setCodecPath)',
      quantization: 'f16',
      backend: 'orpheus',
      kind: ModelKind.codec,
    ),
    // ============================================================
    // CrispASR 0.6.x parity additions (May 2026)
    // ============================================================
    //
    // gemma4-e2b — USM Conformer + Gemma-4 35L; 140+ languages.
    // Newest top-tier multilingual ASR; works with `lang=auto` + LID.
    'gemma4-e2b-q4_k': ModelDefinition(
      name: 'gemma4-e2b-q4_k',
      displayName: 'Gemma4-E2B-it (q4_k)',
      fileName: 'gemma4-e2b-it-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/gemma4-e2b-it-GGUF/resolve/main/gemma4-e2b-it-q4_k.gguf',
      sizeBytes: 2793146016,
      checksum: '',
      description:
          'Multilingual ASR (140+ languages, instruction-tuned) — ~2.8 GB',
      quantization: 'q4_k',
      backend: 'gemma4-e2b',
    ),
    // MOSS-Audio-4B-Instruct — Whisper encoder + Qwen3 LLM (audio
    // understanding: ASR + audio QA + scene description). ~3.8 GB Q4_K.
    'moss-audio-4b-instruct-q4_k': ModelDefinition(
      name: 'moss-audio-4b-instruct-q4_k',
      displayName: 'MOSS-Audio 4B Instruct (q4_k)',
      fileName: 'moss-audio-4b-instruct-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/MOSS-Audio-4B-Instruct-GGUF/resolve/main/moss-audio-4b-instruct-q4_k.gguf',
      sizeBytes: 3800 * 1024 * 1024,
      checksum: '',
      description:
          'MOSS-Audio 4B — ASR + audio QA + scene description (Whisper encoder + Qwen3 LLM), ~3.8 GB',
      quantization: 'q4_k',
      backend: 'moss-audio',
    ),
    // ============================================================
    // CrispASR 0.8.x parity (June 2026) — PLAN §11.1
    // ============================================================
    //
    // MOSS-Transcribe-preview-2B — Qwen3-Omni audio encoder + GatedMLP
    // adapter + Qwen3-1.7B decoder. ASR-only (distinct from moss-audio).
    // Native punctuation, beam search, streaming. ~1.6 GB Q4_K.
    'moss-transcribe-preview-2b-q4_k': ModelDefinition(
      name: 'moss-transcribe-preview-2b-q4_k',
      displayName: 'MOSS-Transcribe 2B (q4_k)',
      fileName: 'moss-transcribe-preview-2b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/MOSS-Transcribe-preview-2B-GGUF/resolve/main/moss-transcribe-preview-2b-q4_k.gguf',
      sizeBytes: 1600 * 1024 * 1024,
      checksum: '',
      description:
          'MOSS-Transcribe 2B — ASR with native punctuation + streaming (Qwen3-Omni enc + Qwen3 dec), ~1.6 GB',
      quantization: 'q4_k',
      backend: 'moss-transcribe',
    ),
    // MOSS-Transcribe-Diarize 0.9B — joint ASR + native speaker
    // diarization + timestamps in one model (Whisper enc + Qwen3-0.6B dec).
    // Surfaces as an ASR model; speaker labels come back inline.
    'moss-transcribe-diarize-0.9b-q4_k': ModelDefinition(
      name: 'moss-transcribe-diarize-0.9b-q4_k',
      displayName: 'MOSS-Diarize 0.9B (q4_k)',
      fileName: 'moss-transcribe-diarize-0.9b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/MOSS-Transcribe-Diarize-GGUF/resolve/main/moss-transcribe-diarize-0.9b-q4_k.gguf',
      sizeBytes: 1200 * 1024 * 1024,
      checksum: '',
      description: 'MOSS-Transcribe-Diarize 0.9B — single-pass ASR + speaker '
          'diarization + timestamps (Whisper enc + Qwen3-0.6B dec), ~1.2 GB',
      quantization: 'q4_k',
      backend: 'moss-diarize',
    ),
    // MOSS-TTS v1.5 — Qwen3-8B backbone + 32-RVQ codec, voice cloning from
    // a reference WAV (no preset voicepack). Desktop-class (~5 GB backbone
    // + ~3.4 GB codec). Needs the codec GGUF via setCodecPath (companion).
    'moss-tts-v1.5-q4_k': ModelDefinition(
      name: 'moss-tts-v1.5-q4_k',
      displayName: 'MOSS-TTS v1.5 (q4_k)',
      fileName: 'moss-tts-v1.5-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/moss-tts-v1.5-GGUF/resolve/main/moss-tts-v1.5-q4_k.gguf',
      sizeBytes: 5 * 1024 * 1024 * 1024,
      checksum: '',
      description:
          'MOSS-TTS v1.5 — voice-cloning TTS (Qwen3-8B backbone); needs the '
          'moss-tts-v1.5-codec GGUF + a reference voice WAV. ~5 GB',
      quantization: 'q4_k',
      backend: 'moss-tts',
      kind: ModelKind.tts,
      companions: ['moss-tts-v1.5-codec'],
      requiresVoice: true,
    ),
    'moss-tts-v1.5-codec': ModelDefinition(
      name: 'moss-tts-v1.5-codec',
      displayName: 'MOSS-TTS v1.5 codec',
      fileName: 'moss-tts-v1.5-codec.gguf',
      url:
          'https://huggingface.co/cstr/moss-tts-v1.5-GGUF/resolve/main/moss-tts-v1.5-codec.gguf',
      sizeBytes: 3400 * 1024 * 1024,
      checksum: '',
      description: 'MOSS-TTS v1.5 RVQ codec (load via setCodecPath)',
      quantization: 'f16',
      backend: 'moss-tts',
      kind: ModelKind.codec,
    ),
    // --- v0.8.10 backend catch-up (2026-07): backends the engine
    // dispatches but the catalog didn't surface yet. ---
    // OmniVoice — Qwen3-0.6B masked multi-codebook TTS; needs its
    // HiggsAudioV2 audio-tokenizer companion (setCodecPath).
    'omnivoice-f16': ModelDefinition(
      name: 'omnivoice-f16',
      displayName: 'OmniVoice (f16)',
      fileName: 'omnivoice-f16.gguf',
      url:
          'https://huggingface.co/cstr/omnivoice-GGUF/resolve/main/omnivoice-f16.gguf',
      sizeBytes: 1230625280,
      checksum: '',
      description:
          'OmniVoice masked multi-codebook TTS (600+ langs) — pulls the '
          'audio-tokenizer companion',
      quantization: 'f16',
      backend: 'omnivoice',
      kind: ModelKind.tts,
      companions: ['omnivoice-tokenizer-f16'],
      languages: langsAll,
    ),
    'omnivoice-tokenizer-f16': ModelDefinition(
      name: 'omnivoice-tokenizer-f16',
      displayName: 'OmniVoice tokenizer (f16)',
      fileName: 'omnivoice-tokenizer-f16.gguf',
      url:
          'https://huggingface.co/cstr/omnivoice-GGUF/resolve/main/omnivoice-tokenizer-f16.gguf',
      sizeBytes: 403183616,
      checksum: '',
      description: 'OmniVoice audio tokenizer (load via setCodecPath)',
      quantization: 'f16',
      backend: 'omnivoice',
      kind: ModelKind.codec,
    ),
    // Irodori-TTS — Japanese 500M TTS; needs the DAC-VAE codec companion.
    'irodori-tts-500m-v3-q4_k': ModelDefinition(
      name: 'irodori-tts-500m-v3-q4_k',
      displayName: 'Irodori-TTS 500M v3 (q4_k)',
      fileName: 'irodori-tts-500m-v3-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/irodori-tts-GGUF/resolve/main/irodori-tts-500m-v3-q4_k.gguf',
      sizeBytes: 852 * 1024 * 1024,
      checksum: '',
      description: 'Irodori-TTS 500M (Japanese) — pulls the DAC-VAE codec',
      quantization: 'q4_k',
      backend: 'irodori-tts',
      kind: ModelKind.tts,
      companions: ['dacvae-ja-32dim-f16'],
      languages: ['ja'],
    ),
    'dacvae-ja-32dim-f16': ModelDefinition(
      name: 'dacvae-ja-32dim-f16',
      displayName: 'Irodori DAC-VAE codec (f16)',
      fileName: 'dacvae-ja-32dim-f16.gguf',
      url:
          'https://huggingface.co/cstr/irodori-tts-GGUF/resolve/main/dacvae-ja-32dim-f16.gguf',
      sizeBytes: 410 * 1024 * 1024,
      checksum: '',
      description: 'Irodori-TTS DAC-VAE codec (load via setCodecPath)',
      quantization: 'f16',
      backend: 'irodori-tts',
      kind: ModelKind.codec,
    ),
    // Voxtral-4B-TTS — Mistral. NON-COMMERCIAL (CC-BY-NC-4.0).
    'voxtral-4b-tts-q4_k': ModelDefinition(
      name: 'voxtral-4b-tts-q4_k',
      displayName: 'Voxtral 4B TTS (q4_k)',
      fileName: 'voxtral-4b-tts-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/voxtral-4b-tts-GGUF/resolve/main/voxtral-4b-tts-q4_k.gguf',
      sizeBytes: 2500 * 1024 * 1024,
      checksum: '',
      description:
          'Voxtral 4B TTS (Mistral) — non-commercial use only, ~2.5 GB',
      quantization: 'q4_k',
      backend: 'voxtral-tts',
      kind: ModelKind.tts,
      license: 'cc-by-nc-4.0',
      languages: langsAll,
    ),
    // (ReazonSpeech is already catalogued under the `parakeet` backend —
    // the engine's bare `reazonspeech` dispatch string is a parakeet-path
    // alias, handled in the dispatch guard's engineOnly set.)
    // Canary-Qwen 2.5B — NVIDIA Canary encoder + Qwen LLM decoder.
    'canary-qwen-2.5b-q8_0': ModelDefinition(
      name: 'canary-qwen-2.5b-q8_0',
      displayName: 'Canary-Qwen 2.5B (q8_0)',
      fileName: 'canary-qwen-2.5b-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/canary-qwen-2.5b-GGUF/resolve/main/canary-qwen-2.5b-q8_0.gguf',
      sizeBytes: 4100 * 1024 * 1024,
      checksum: '',
      description:
          'Canary-Qwen 2.5B — Canary encoder + Qwen decoder ASR, ~4.1 GB',
      quantization: 'q8_0',
      backend: 'canary-qwen',
      languages: langsAll,
    ),
    // Higgs-Audio-v3-STT — bosonai Whisper-large-v3 encoder + Qwen3-1.7B
    // decoder. Internal chunking, beam search, --ask prompt. ~2.3 GB Q4_K.
    'higgs-stt-q4_k': ModelDefinition(
      name: 'higgs-stt-q4_k',
      displayName: 'Higgs-STT (q4_k)',
      fileName: 'higgs-stt-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/higgs-audio-v3-stt-GGUF/resolve/main/higgs-stt-q4_k.gguf',
      sizeBytes: 2300 * 1024 * 1024,
      checksum: '',
      description:
          'Higgs-Audio-v3-STT — Whisper-v3 enc + Qwen3-1.7B dec, internal chunking + beam search, ~2.3 GB',
      quantization: 'q4_k',
      backend: 'higgs-stt',
      languages: langsAll,
    ),
    // ARK-ASR-3B — AutoArk-AI Whisper-RoPE encoder + Qwen2.5-3B decoder.
    // 19 languages, cross-chunk language conditioning. ~2.2 GB Q4_K.
    // NB: registry notes HF URL as placeholder — may need update.
    'ark-asr-3b-q4_k': ModelDefinition(
      name: 'ark-asr-3b-q4_k',
      displayName: 'ARK-ASR 3B (q4_k)',
      fileName: 'ark-asr-3b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/ark-asr-3b-GGUF/resolve/main/ark-asr-3b-q4_k.gguf',
      sizeBytes: 2200 * 1024 * 1024,
      checksum: '',
      description:
          'ARK-ASR 3B — Whisper-RoPE enc + Qwen2.5-3B dec, 19 languages, ~2.2 GB',
      quantization: 'q4_k',
      backend: 'ark-asr',
      languages: langsAll,
    ),
    // Gemma4-E4B — larger decoder variant (42L×2560) of the Gemma4 ASR
    // family. Same architecture and backend as E2B, just bigger. ~4.1 GB.
    'gemma4-e4b-q4_k': ModelDefinition(
      name: 'gemma4-e4b-q4_k',
      displayName: 'Gemma4-E4B-it (q4_k)',
      fileName: 'gemma4-e4b-it-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/gemma4-e4b-it-GGUF/resolve/main/gemma4-e4b-it-q4_k.gguf',
      sizeBytes: 4100 * 1024 * 1024,
      checksum: '',
      description:
          'Gemma4-E4B 4B — larger decoder variant of Gemma4 ASR (140+ langs), ~4.1 GB',
      quantization: 'q4_k',
      backend: 'gemma4-e2b',
      languages: langsAll,
    ),
    // ReazonSpeech NeMo v2 — Japanese FastConformer-RNNT (619M params).
    // Reuses parakeet backend. Q8_0 (quant-sensitive for Japanese). ~704 MB.
    'reazonspeech-nemo-v2-q8_0': ModelDefinition(
      name: 'reazonspeech-nemo-v2-q8_0',
      displayName: 'ReazonSpeech NeMo v2 (q8_0)',
      fileName: 'reazonspeech-nemo-v2-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/reazonspeech-nemo-v2-GGUF/resolve/main/reazonspeech-nemo-v2-q8_0.gguf',
      sizeBytes: 704 * 1024 * 1024,
      checksum: '',
      description:
          'ReazonSpeech NeMo v2 — Japanese RNNT ASR (619M params), ~704 MB',
      quantization: 'q8_0',
      backend: 'parakeet',
      languages: langsJa,
    ),
    // Parakeet-CTC 1.1B Japanese — FastConformer-CTC 42L, fine-tuned on
    // Japanese data (GAL checkpoint). Reuses parakeet backend. Q8_0. ~1.2 GB.
    'parakeet-ctc-1.1b-ja-q8_0': ModelDefinition(
      name: 'parakeet-ctc-1.1b-ja-q8_0',
      displayName: 'Parakeet-CTC 1.1B JA (q8_0)',
      fileName: 'parakeet-ctc-1.1b-ja-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-ctc-1.1b-ja-GGUF/resolve/main/parakeet-ctc-1.1b-ja-q8_0.gguf',
      sizeBytes: 1200 * 1024 * 1024,
      checksum: '',
      description: 'Parakeet-CTC 1.1B Japanese — FastConformer-CTC, ~1.2 GB',
      quantization: 'q8_0',
      backend: 'parakeet',
      languages: langsJa,
    ),
    // DoTs-TTS — rednote-hilab 2B continuous AR + DiT flow-matching +
    // BigVGAN vocoder. 48 kHz. CAM++ voice cloning via --voice ref.wav.
    // Three GGUFs: core (~4.4 GB), vocoder (~345 MB), spk encoder (~15 MB).
    'dots-tts-soar-f16': ModelDefinition(
      name: 'dots-tts-soar-f16',
      displayName: 'DoTs-TTS SOAR (f16)',
      fileName: 'dots-tts-soar-f16.gguf',
      url:
          'https://huggingface.co/cstr/dots-tts-soar-GGUF/resolve/main/dots-tts-soar-f16.gguf',
      sizeBytes: 4400 * 1024 * 1024,
      checksum: '',
      description:
          'DoTs-TTS 2B — continuous AR + flow-matching + BigVGAN, 48 kHz, voice cloning, ~4.4 GB',
      quantization: 'f16',
      backend: 'dots-tts',
      kind: ModelKind.tts,
      languages: langsEnZh,
      companions: ['dots-tts-soar-vocoder-f16', 'dots-tts-soar-spk-f16'],
    ),
    'dots-tts-soar-vocoder-f16': ModelDefinition(
      name: 'dots-tts-soar-vocoder-f16',
      displayName: 'DoTs-TTS vocoder (f16)',
      fileName: 'dots-tts-soar-vocoder-f16.gguf',
      url:
          'https://huggingface.co/cstr/dots-tts-soar-GGUF/resolve/main/dots-tts-soar-vocoder-f16.gguf',
      sizeBytes: 345 * 1024 * 1024,
      checksum: '',
      description: 'DoTs-TTS BigVGAN vocoder (load via setCodecPath)',
      quantization: 'f16',
      backend: 'dots-tts',
      kind: ModelKind.codec,
    ),
    'dots-tts-soar-spk-f16': ModelDefinition(
      name: 'dots-tts-soar-spk-f16',
      displayName: 'DoTs-TTS speaker encoder (f16)',
      fileName: 'dots-tts-soar-spk-f16.gguf',
      url:
          'https://huggingface.co/cstr/dots-tts-soar-GGUF/resolve/main/dots-tts-soar-spk-f16.gguf',
      sizeBytes: 15 * 1024 * 1024,
      checksum: '',
      description: 'DoTs-TTS CAM++ speaker encoder for voice cloning',
      quantization: 'f16',
      backend: 'dots-tts',
      kind: ModelKind.codec,
    ),
    // ============================================================
    // CrispASR mid-2026 catch-up (June 2026) — PLAN §5.26
    // ============================================================
    //
    // LFM2-Audio 1.5B — LiquidAI hybrid conv+attention ASR (+TTS, +S2S).
    // English base model; Q5_K recommended (Q4_K too aggressive for EN).
    // LFM Open License v1.0 (commercial OK <$10M revenue).
    'lfm2-audio-1.5b-q5_k': ModelDefinition(
      name: 'lfm2-audio-1.5b-q5_k',
      displayName: 'LFM2-Audio 1.5B (q5_k)',
      fileName: 'lfm2-audio-1.5b-q5_k.gguf',
      url:
          'https://huggingface.co/cstr/lfm2-audio-1.5b-GGUF/resolve/main/lfm2-audio-1.5b-q5_k.gguf',
      sizeBytes: 1600 * 1024 * 1024,
      checksum: '',
      description:
          'LiquidAI LFM2-Audio 1.5B — ASR + TTS + S2S, English, ~1.6 GB',
      quantization: 'q5_k',
      backend: 'lfm2-audio',
      languages: langsEn,
    ),
    // LFM2-Audio 1.5B Japanese variant — Q4_K is safe for Japanese.
    'lfm2-audio-1.5b-jp-q4_k': ModelDefinition(
      name: 'lfm2-audio-1.5b-jp-q4_k',
      displayName: 'LFM2-Audio 1.5B JP (q4_k)',
      fileName: 'lfm2-audio-1.5b-jp-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/lfm2-audio-1.5b-jp-GGUF/resolve/main/lfm2-audio-1.5b-jp-q4_k.gguf',
      sizeBytes: 1500 * 1024 * 1024,
      checksum: '',
      description:
          'LiquidAI LFM2-Audio 1.5B — ASR + TTS + S2S, Japanese, ~1.5 GB',
      quantization: 'q4_k',
      backend: 'lfm2-audio',
      languages: langsJa,
    ),
    // Mini-Omni2 — Whisper-small encoder + Qwen2-0.5B LLM (ASR+TTS+S2S).
    // Q4_K safe — identical ASR transcript to F16 on JFK 11s.
    // Needs snac-24khz.gguf codec companion for TTS/S2S output.
    'mini-omni2-q4_k': ModelDefinition(
      name: 'mini-omni2-q4_k',
      displayName: 'Mini-Omni2 (q4_k)',
      fileName: 'mini-omni2-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/mini-omni2-GGUF/resolve/main/mini-omni2-q4_k.gguf',
      sizeBytes: 1000 * 1024 * 1024,
      checksum: '',
      description:
          'Mini-Omni2 — Whisper + Qwen2 0.5B, ASR + TTS + S2S, ~1.0 GB',
      quantization: 'q4_k',
      backend: 'mini-omni2',
      companions: ['snac-24khz'],
      languages: langsEn,
    ),
    // Parakeet-RNNT 0.6B/1.1B — standard RNN-Transducers. Already in
    // baked_models_catalog.dart with all quant variants; BackendRepo
    // entries added in backendRepos below for HF probe.
    //
    // OmniASR LLM unlimited — streaming variant, 15 s protocol.
    'omniasr-llm-unlimited-q4_k': ModelDefinition(
      name: 'omniasr-llm-unlimited-q4_k',
      displayName: 'OmniASR LLM unlimited 300M v2 (q4_k)',
      fileName: 'omniasr-llm-unlimited-300m-v2-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/omniasr-llm-unlimited-300m-v2-GGUF/resolve/main/omniasr-llm-unlimited-300m-v2-q4_k.gguf',
      sizeBytes: 1075436320,
      checksum: '',
      description:
          'Streaming OmniASR LLM (unlimited audio, 1600+ langs) — ~1.0 GB',
      quantization: 'q4_k',
      backend: 'omniasr-llm-unlimited',
    ),
    // ---------- Granite Speech variants ----------
    // Granite 4.1 2B — newer NAR-capable Granite.
    'granite-speech-4.1-2b-q4_k': ModelDefinition(
      name: 'granite-speech-4.1-2b-q4_k',
      displayName: 'Granite Speech 4.1 2B (q4_k)',
      fileName: 'granite-speech-4.1-2b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/granite-speech-4.1-2b-GGUF/resolve/main/granite-speech-4.1-2b-q4_k.gguf',
      sizeBytes: 1400 * 1024 * 1024,
      checksum: '',
      description: 'IBM Granite Speech 4.1 (2B) — ~1.4 GB',
      quantization: 'q4_k',
      backend: 'granite-4.1',
    ),
    // Granite 4.1 plus — instruction-tuned 4.1 variant.
    'granite-speech-4.1-plus-q4_k': ModelDefinition(
      name: 'granite-speech-4.1-plus-q4_k',
      displayName: 'Granite Speech 4.1 2B+ (q4_k)',
      fileName: 'granite-speech-4.1-2b-plus-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/granite-speech-4.1-2b-plus-GGUF/resolve/main/granite-speech-4.1-2b-plus-q4_k.gguf',
      sizeBytes: 2957822752,
      checksum: '',
      description: 'IBM Granite Speech 4.1 2B+ (instruction-tuned) — ~2.9 GB',
      quantization: 'q4_k',
      backend: 'granite-4.1-plus',
    ),
    // Granite 4.1 NAR — non-autoregressive variant.
    'granite-speech-4.1-nar-q4_k': ModelDefinition(
      name: 'granite-speech-4.1-nar-q4_k',
      displayName: 'Granite Speech 4.1 2B NAR (q4_k)',
      fileName: 'granite-speech-4.1-2b-nar-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/granite-speech-4.1-2b-nar-GGUF/resolve/main/granite-speech-4.1-2b-nar-q4_k.gguf',
      sizeBytes: 3413252640,
      checksum: '',
      description: 'Granite Speech 4.1 2B NAR (parallel-decode) — ~3.4 GB',
      quantization: 'q4_k',
      backend: 'granite-4.1-nar',
    ),
    // ---------- Additional TTS families (Chatterbox, IndexTTS, etc.) ----------
    // Chatterbox is split into two GGUFs in cstr/chatterbox-GGUF:
    //   * chatterbox-t3-*.gguf — Llama-style AR (the "main" model)
    //   * chatterbox-s3gen-*.gguf — S3Gen flow-matching vocoder
    // Both halves are required at synth time. The T3 entry below is the
    // primary; its `companions` link pulls in the S3Gen sibling.
    'chatterbox-en-q8_0': ModelDefinition(
      name: 'chatterbox-en-q8_0',
      displayName: 'Chatterbox T3 (q8_0)',
      fileName: 'chatterbox-t3-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/chatterbox-GGUF/resolve/main/chatterbox-t3-q8_0.gguf',
      sizeBytes: 630177120,
      checksum: '',
      description:
          'Chatterbox TTS T3 (AR transformer, 23 langs) — needs chatterbox-s3gen-* companion',
      quantization: 'q8_0',
      backend: 'chatterbox',
      kind: ModelKind.tts,
      companions: ['chatterbox-s3gen-q8_0'],
      languages: langsChatterbox23,
    ),
    // #18 — the chatterbox-turbo-t3 BackendRepo lets the deep HF probe
    // discover this, but it's absent from the baked snapshot, so it only
    // showed up after a manual Model-Management refresh. Hardcode it so it
    // lists on a fresh launch like the standard chatterbox T3 above. Same
    // backend + companion as the BackendRepo defaults (so a probe-found
    // entry of the same name reconciles cleanly); turbo-t3 q8_0 = ~628 MB.
    'chatterbox-turbo-t3-q8_0': ModelDefinition(
      name: 'chatterbox-turbo-t3-q8_0',
      displayName: 'Chatterbox turbo T3 (q8_0)',
      fileName: 'chatterbox-turbo-t3-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/chatterbox-turbo-GGUF/resolve/main/chatterbox-turbo-t3-q8_0.gguf',
      sizeBytes: 658897152,
      checksum: '',
      description: 'Chatterbox turbo TTS T3 (faster AR transformer) — needs a '
          'chatterbox-s3gen-* companion',
      quantization: 'q8_0',
      backend: 'chatterbox',
      kind: ModelKind.tts,
      companions: ['chatterbox-s3gen-q8_0'],
      languages: langsEn,
    ),
    // Chatterbox S3Gen flow-matching vocoder — companion of chatterbox-t3.
    'chatterbox-s3gen-q8_0': ModelDefinition(
      name: 'chatterbox-s3gen-q8_0',
      displayName: 'Chatterbox S3Gen (q8_0)',
      fileName: 'chatterbox-s3gen-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/chatterbox-GGUF/resolve/main/chatterbox-s3gen-q8_0.gguf',
      sizeBytes: 358278528,
      checksum: '',
      description:
          'Chatterbox S3Gen flow-matching vocoder — companion to chatterbox-t3',
      quantization: 'q8_0',
      backend: 'chatterbox',
      kind: ModelKind.codec,
    ),
    // Kartoffel-Orpheus 3B (DE) — Orpheus base + German fine-tune.
    // Two flavours under separate HF repos (natural-voice + synthetic);
    // both share the standard snac-24khz codec. Adding explicit
    // catalogue entries so they show up under the "German" language
    // filter even before the user hits Refresh-from-HF.
    'kartoffel-orpheus-3b-natural-q8_0': ModelDefinition(
      name: 'kartoffel-orpheus-3b-natural-q8_0',
      displayName: 'Kartoffel-Orpheus 3B natural (DE, q8_0)',
      fileName: 'kartoffel-orpheus-3b-german-natural-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/kartoffel-orpheus-3b-german-natural-GGUF/resolve/main/kartoffel-orpheus-3b-german-natural-q8_0.gguf',
      sizeBytes: 3500 * 1024 * 1024,
      checksum: '',
      description:
          'Orpheus 3B German fine-tune (natural voices) — pair with snac-24khz',
      quantization: 'q8_0',
      backend: 'orpheus',
      kind: ModelKind.tts,
      companions: ['snac-24khz'],
      languages: langsDe,
    ),
    'kartoffel-orpheus-3b-synthetic-q8_0': ModelDefinition(
      name: 'kartoffel-orpheus-3b-synthetic-q8_0',
      displayName: 'Kartoffel-Orpheus 3B synthetic (DE, q8_0)',
      fileName: 'kartoffel-orpheus-3b-german-synthetic-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/kartoffel-orpheus-3b-german-synthetic-GGUF/resolve/main/kartoffel-orpheus-3b-german-synthetic-q8_0.gguf',
      sizeBytes: 3500 * 1024 * 1024,
      checksum: '',
      description:
          'Orpheus 3B German fine-tune (synthetic voices) — pair with snac-24khz',
      quantization: 'q8_0',
      backend: 'orpheus',
      kind: ModelKind.tts,
      companions: ['snac-24khz'],
      languages: langsDe,
    ),
    // Kartoffelbox — Chatterbox German finetune (turbo). T3 only on HF;
    // pair with the matching English S3Gen vocoder at synth time.
    'kartoffelbox-de-q8_0': ModelDefinition(
      name: 'kartoffelbox-de-q8_0',
      displayName: 'Kartoffelbox turbo T3 DE (q8_0)',
      fileName: 'kartoffelbox-turbo-t3-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/kartoffelbox-turbo-GGUF/resolve/main/kartoffelbox-turbo-t3-q8_0.gguf',
      sizeBytes: 653201696,
      checksum: '',
      description:
          'Kartoffelbox-turbo German T3 (Chatterbox finetune) — pair with a chatterbox-s3gen companion',
      quantization: 'q8_0',
      backend: 'chatterbox',
      kind: ModelKind.tts,
      companions: ['chatterbox-s3gen-q8_0'],
      languages: langsDe,
    ),
    // IndexTTS 1.5 is split into two GGUFs in cstr/indextts-1.5-GGUF:
    //   * indextts-gpt-*.gguf — GPT-2 style AR
    //   * indextts-bigvgan.gguf — BigVGAN vocoder (no quants)
    'indextts-q8_0': ModelDefinition(
      name: 'indextts-q8_0',
      displayName: 'IndexTTS 1.5 GPT (q8_0)',
      fileName: 'indextts-gpt-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/indextts-1.5-GGUF/resolve/main/indextts-gpt-q8_0.gguf',
      sizeBytes: 641977344,
      checksum: '',
      description:
          'IndexTTS 1.5 GPT (ZH+EN, zero-shot voice cloning) — needs indextts-bigvgan companion',
      quantization: 'q8_0',
      backend: 'indextts',
      kind: ModelKind.tts,
      companions: ['indextts-bigvgan'],
    ),
    'indextts-bigvgan': ModelDefinition(
      name: 'indextts-bigvgan',
      displayName: 'IndexTTS BigVGAN vocoder',
      fileName: 'indextts-bigvgan.gguf',
      url:
          'https://huggingface.co/cstr/indextts-1.5-GGUF/resolve/main/indextts-bigvgan.gguf',
      sizeBytes: 268168960,
      checksum: '',
      description: 'IndexTTS BigVGAN vocoder — companion to indextts-gpt-*',
      quantization: 'f16',
      backend: 'indextts',
      kind: ModelKind.codec,
    ),
    // Qwen3-TTS 1.7B CustomVoice — same #18 pattern as the 0.6B variant.
    // Without this entry, the 1.7B CustomVoice only surfaces after the HF
    // deep refresh in Model Management. Approximate size from HF blob.
    'qwen3-tts-12hz-1.7b-customvoice-q8_0': ModelDefinition(
      name: 'qwen3-tts-12hz-1.7b-customvoice-q8_0',
      displayName: 'Qwen3-TTS 1.7B CustomVoice 12 Hz (q8_0)',
      fileName: 'qwen3-tts-12hz-1.7b-customvoice-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-tts-1.7b-customvoice-GGUF/resolve/main/qwen3-tts-12hz-1.7b-customvoice-q8_0.gguf',
      sizeBytes: 1900 * 1024 * 1024,
      checksum: '',
      description: 'Qwen3-TTS 1.7B CustomVoice (9 preset speakers) — needs the '
          'qwen3-tts-tokenizer-12hz codec GGUF; pick a speaker in Synthesize',
      quantization: 'q8_0',
      backend: 'qwen3-tts',
      kind: ModelKind.tts,
      companions: ['qwen3-tts-tokenizer-12hz'],
      languages: langsQwen3TtsCustom9,
    ),
    // Qwen3-TTS VoiceDesign — natural-language voice description.
    'qwen3-tts-12hz-1.7b-voicedesign-q8_0': ModelDefinition(
      name: 'qwen3-tts-12hz-1.7b-voicedesign-q8_0',
      displayName: 'Qwen3-TTS VoiceDesign 1.7B (q8_0)',
      fileName: 'qwen3-tts-12hz-1.7b-voicedesign-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-tts-1.7b-voicedesign-GGUF/resolve/main/qwen3-tts-12hz-1.7b-voicedesign-q8_0.gguf',
      sizeBytes: 1900 * 1024 * 1024,
      checksum: '',
      description:
          'Qwen3-TTS VoiceDesign — describe the voice in natural language via --instruct',
      quantization: 'q8_0',
      backend: 'qwen3-tts',
      kind: ModelKind.tts,
      companions: ['qwen3-tts-tokenizer-12hz'],
    ),
    // VibeVoice 1.5B — base model with runtime WAV cloning (no GGUF
    // voicepack). The `-tts-` infix marks the variant with the bundled
    // Tekken tokenizer; choose f16 for the high-quality shippable.
    'vibevoice-1.5b-tts-f16': ModelDefinition(
      name: 'vibevoice-1.5b-tts-f16',
      displayName: 'VibeVoice 1.5B TTS (f16 + tokenizer)',
      fileName: 'vibevoice-1.5b-tts-f16.gguf',
      url:
          'https://huggingface.co/cstr/vibevoice-1.5b-GGUF/resolve/main/vibevoice-1.5b-tts-f16.gguf',
      sizeBytes: 5412393280,
      checksum: '',
      description:
          'VibeVoice 1.5B base — runtime WAV cloning via setVoice(wav, refText: …)',
      quantization: 'f16',
      backend: 'vibevoice-tts',
      kind: ModelKind.tts,
    ),
    // ---------- Multilingual punctuation (fullstop-punc) ----------
    // CrispASR's text-only punctuation restorer for EN/DE/FR/IT.
    'fullstop-punc-multilang-q8_0': ModelDefinition(
      name: 'fullstop-punc-multilang-q8_0',
      displayName: 'Fullstop-punc multilang (q8_0)',
      fileName: 'fullstop-punc-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/fullstop-punc-multilang-GGUF/resolve/main/fullstop-punc-q8_0.gguf',
      sizeBytes: 599331488,
      checksum: '',
      description:
          'Multilingual punctuation + casing restoration (EN/DE/FR/IT). Pair with CTC backends.',
      quantization: 'q8_0',
      backend: 'fullstop-punc',
      kind: ModelKind.punc,
    ),
    // ---------- Pyannote diarisation ----------
    // ML-based diarization GGUF; up to 3 speakers per slice. Pairs with
    // DiarizeMethod.pyannote — enabled in the diarisation method picker.
    'pyannote-v3-seg-q8_0': ModelDefinition(
      name: 'pyannote-v3-seg-q8_0',
      displayName: 'Pyannote v3 segmentation',
      fileName: 'pyannote-seg-3.0.gguf',
      url:
          'https://huggingface.co/cstr/pyannote-v3-segmentation-GGUF/resolve/main/pyannote-seg-3.0.gguf',
      sizeBytes: 5976512,
      checksum: '',
      description:
          'Pyannote v3 segmentation for diarisation (up to 3 speakers per slice) — ~5.7 MB',
      quantization: 'f16',
      backend: 'pyannote',
      kind: ModelKind.diarize,
    ),
    // WeSpeaker ResNet34-LM speaker embedder. Pairs with
    // DiarizeMethod.foxNose (CrispASR #324): embeddings + spectral
    // clustering, which unlike the stereo energy/xcorr methods works on
    // mono, and unlike pyannote can be told how many speakers to find.
    'wespeaker-resnet34-lm': ModelDefinition(
      name: 'wespeaker-resnet34-lm',
      displayName: 'WeSpeaker ResNet34-LM',
      fileName: 'wespeaker-resnet34-lm.gguf',
      url:
          'https://huggingface.co/cstr/wespeaker-resnet34-lm-GGUF/resolve/main/wespeaker-resnet34-lm.gguf',
      sizeBytes: 23904352,
      checksum: '',
      description:
          'WeSpeaker embedder for FoxNose diarisation (mono, speaker-count hints) — ~23 MB',
      quantization: 'f16',
      backend: 'wespeaker',
      kind: ModelKind.diarize,
    ),
    // ---------- Alternative VAD backends ----------
    // CrispASR ships four VAD options; silero is bundled as a Flutter
    // asset (no download needed). The other three live in the catalog
    // so the VAD method picker can offer them.
    'firered-vad-q4_k': ModelDefinition(
      name: 'firered-vad-q4_k',
      displayName: 'FireRed VAD',
      fileName: 'firered-vad.gguf',
      url:
          'https://huggingface.co/cstr/firered-vad-GGUF/resolve/main/firered-vad.gguf',
      sizeBytes: 2357952,
      checksum: '',
      description: 'FireRed VAD (F1 97.57%, recommended) — ~2.3 MB',
      quantization: 'f16',
      backend: 'vad',
      kind: ModelKind.vad,
    ),
    'marblenet-vad': ModelDefinition(
      name: 'marblenet-vad',
      displayName: 'MarbleNet VAD',
      fileName: 'marblenet-vad.gguf',
      url:
          'https://huggingface.co/cstr/marblenet-vad-GGUF/resolve/main/marblenet-vad.gguf',
      sizeBytes: 449824,
      checksum: '',
      description: 'MarbleNet VAD (EN/DE/FR/ES/RU/ZH) — ~440 KB',
      quantization: 'f16',
      backend: 'vad',
      kind: ModelKind.vad,
    ),
    'whisper-vad-encdec-q4_k': ModelDefinition(
      name: 'whisper-vad-encdec-q4_k',
      displayName: 'Whisper-VAD ASMR (q4_k, experimental)',
      fileName: 'whisper-vad-asmr-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/whisper-vad-encdec-asmr-GGUF/resolve/main/whisper-vad-asmr-q4_k.gguf',
      sizeBytes: 22778080,
      checksum: '',
      description:
          'Whisper-VAD-EncDec (English ASMR-trained, experimental) — ~22 MB',
      quantization: 'q4_k',
      backend: 'vad',
      kind: ModelKind.vad,
    ),
    // ---------- Text translation (m2m100) ----------
    // M2M-100 is CrispASR's primary text-to-text translator: 100
    // languages, any-to-any. Loaded via CrispasrSession with backend
    // = "m2m100"; consumed by TextTranslationService + the Translate
    // screen.
    'm2m100-418m-q4_k': ModelDefinition(
      name: 'm2m100-418m-q4_k',
      displayName: 'M2M-100 418M (q4_k)',
      fileName: 'm2m100-418m-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/m2m100-418m-GGUF/resolve/main/m2m100-418m-q4_k.gguf',
      sizeBytes: 480 * 1024 * 1024,
      checksum: '',
      description:
          'M2M-100 418M text-to-text translation (100 languages, any-to-any) — ~480 MB',
      quantization: 'q4_k',
      backend: 'm2m100',
      kind: ModelKind.translate,
    ),
    // M2M-100 1.2B is not currently published — `cstr/m2m100-1.2b-GGUF`
    // returns 401. Use m2m100-418m-q4_k as the smaller default; revisit
    // if a 1.2B GGUF lands publicly.
    // WMT21 — Facebook's News-competition winner. Two separate
    // checkpoints, each 4.7B / ~2.5 GB Q4_K: en-x for English-source,
    // x-en for English-target. Routes through the same m2m100 runtime
    // (backend "m2m100-wmt21" on the C side).
    'wmt21-dense-24-wide-en-x-q4_k': ModelDefinition(
      name: 'wmt21-dense-24-wide-en-x-q4_k',
      displayName: 'WMT21 Dense 24-wide en→X (q4_k)',
      fileName: 'wmt21-dense-24-wide-en-x-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wmt21-dense-24-wide-en-x-GGUF/resolve/main/wmt21-dense-24-wide-en-x-q4_k.gguf',
      sizeBytes: 2500 * 1024 * 1024,
      checksum: '',
      description:
          'WMT21 Dense (en→X direction) — English to 7 target languages, ~2.5 GB',
      quantization: 'q4_k',
      backend: 'm2m100-wmt21',
      kind: ModelKind.translate,
    ),
    'wmt21-dense-24-wide-x-en-q4_k': ModelDefinition(
      name: 'wmt21-dense-24-wide-x-en-q4_k',
      displayName: 'WMT21 Dense 24-wide X→en (q4_k)',
      fileName: 'wmt21-dense-24-wide-x-en-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wmt21-dense-24-wide-x-en-GGUF/resolve/main/wmt21-dense-24-wide-x-en-q4_k.gguf',
      sizeBytes: 2500 * 1024 * 1024,
      checksum: '',
      description:
          'WMT21 Dense (X→en direction) — 7 source languages to English, ~2.5 GB',
      quantization: 'q4_k',
      backend: 'm2m100-wmt21',
      kind: ModelKind.translate,
    ),
    // MADLAD-400 — Google's 419-language T5 translator.
    'madlad400-3b-mt-q4_k': ModelDefinition(
      name: 'madlad400-3b-mt-q4_k',
      displayName: 'MADLAD-400 3B-MT (q4_k)',
      fileName: 'madlad400-3b-mt-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/madlad400-3b-mt-GGUF/resolve/main/madlad400-3b-mt-q4_k.gguf',
      sizeBytes: 1900 * 1024 * 1024,
      checksum: '',
      description:
          'MADLAD-400 3B — 419 languages, T5 enc-dec, bit-token-identical to Python — ~1.9 GB',
      quantization: 'q4_k',
      backend: 'madlad',
      kind: ModelKind.translate,
    ),
    // ---------- Silero LID GGUF ----------
    // CrispASR exposes a Silero 95-language LID classifier; pair with
    // LidMethod.silero in the LID picker for a smaller / faster
    // alternative to the whisper encoder LID path.
    'silero-lang95-v1-f16': ModelDefinition(
      name: 'silero-lang95-v1-f16',
      displayName: 'Silero LID 95-langs (f32)',
      fileName: 'silero-lid-lang95-f32.gguf',
      url:
          'https://huggingface.co/cstr/silero-lid-lang95-GGUF/resolve/main/silero-lid-lang95-f32.gguf',
      sizeBytes: 16900416,
      checksum: '',
      description:
          'Silero language identification (95 languages) — faster + smaller than the Whisper-encoder LID',
      quantization: 'f32',
      backend: 'lid',
      kind: ModelKind.lid,
    ),
    // ECAPA-TDNN LID — speechbrain/lang-id-voxlingua107-ecapa,
    // Apache-2.0, 107 languages, attentive statistical pooling.
    // Stronger on noisy / accented speech than Silero; ~42 MB F16.
    'ecapa-lid-107-f16': ModelDefinition(
      name: 'ecapa-lid-107-f16',
      displayName: 'ECAPA-TDNN LID 107-langs (f16)',
      fileName: 'ecapa-lid-107-f16.gguf',
      url:
          'https://huggingface.co/cstr/ecapa-lid-107-GGUF/resolve/main/ecapa-lid-107-f16.gguf',
      sizeBytes: 42 * 1024 * 1024,
      checksum: '',
      description: 'ECAPA-TDNN language identification (107 languages) — '
          'speechbrain/lang-id-voxlingua107, strong on noisy / accented speech',
      quantization: 'f16',
      backend: 'lid',
      kind: ModelKind.lid,
    ),
    // FireRed LID — FireRedTeam/FireRedLID, 6-layer Transformer LID
    // head, 120 languages. Higher coverage than Silero/ECAPA at a
    // ~10× model-size cost; pick this when low-resource languages
    // are in scope.
    'firered-lid-f16': ModelDefinition(
      name: 'firered-lid-f16',
      displayName: 'FireRed LID 120-langs (f16)',
      fileName: 'firered-lid-f16.gguf',
      url:
          'https://huggingface.co/cstr/firered-lid-GGUF/resolve/main/firered-lid-f16.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'FireRed language identification (120 languages) — '
          'highest coverage among bundled LID GGUFs, especially on low-resource languages',
      quantization: 'f16',
      backend: 'lid',
      kind: ModelKind.lid,
    ),
    // CLD3 — Google Compact Language Detector v3 (cstr/cld3-GGUF).
    // Unlike the audio LID models above, this is TEXT LID: it powers the
    // Translate screen's source-language auto-detect via
    // `detectTextLanguage` (the crispasr_text_detect_language C-ABI), not
    // the audio LidService. Tiny (~430 KB).
    'cld3-f16': ModelDefinition(
      name: 'cld3-f16',
      displayName: 'CLD3 text language-ID',
      fileName: 'cld3-f16.gguf',
      url: 'https://huggingface.co/cstr/cld3-GGUF/resolve/main/cld3-f16.gguf',
      sizeBytes: 439712,
      checksum: '',
      description:
          'Google CLD3 text language identification (100+ languages) — '
          'powers Translate source-language auto-detect',
      quantization: 'f16',
      backend: 'lid',
      kind: ModelKind.lid,
    ),
    // TitaNet-Large speaker embedding — Nvidia NeMo TitaNet-Large
    // ported to GGUF, 192-d L2-normalised embeddings. Pairs with
    // `CrispasrTitaNet` + `CrispasrSpeakerDB` to resolve diarised
    // speaker clusters to enrolled names. Lives in the LID bucket
    // (speech-encoder GGUF) so Model Management groups it alongside
    // the other auxiliary speech models rather than the ASR mains.
    'titanet-large-f16': ModelDefinition(
      name: 'titanet-large-f16',
      displayName: 'TitaNet-Large speaker embedding (f16)',
      fileName: 'titanet-large.gguf',
      url:
          'https://huggingface.co/cstr/titanet-large-GGUF/resolve/main/titanet-large.gguf',
      sizeBytes: 44612960,
      checksum: '',
      description:
          'TitaNet-Large 192-d speaker embedding extractor — pair with '
          'enrolled speakers in Settings → Speakers to resolve diarised '
          '"Speaker 0 / Speaker 1" labels to real names',
      quantization: 'f16',
      backend: 'titanet',
      kind: ModelKind.lid,
    ),
    // ---------- New TTS backends (Phase 2: full CrispASR parity) ----------
    // Bark — suno/bark 3-stage hierarchical TTS. 24 kHz, 10 German
    // speakers (v2/de_speaker_0..9). Single GGUF packs all 3 sub-models.
    'bark-small-q8_0': ModelDefinition(
      name: 'bark-small-q8_0',
      displayName: 'Bark small (q8_0)',
      fileName: 'bark-small-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/bark-small-GGUF/resolve/main/bark-small-q8_0.gguf',
      sizeBytes: 500 * 1024 * 1024,
      checksum: '',
      description:
          'Bark 3-stage GPT-2 TTS — multilingual, 10 DE speakers, ~500 MB',
      quantization: 'q8_0',
      backend: 'bark',
      kind: ModelKind.tts,
      languages: <String>[
        'de',
        'en',
        'es',
        'fr',
        'hi',
        'it',
        'ja',
        'ko',
        'pl',
        'pt',
        'ru',
        'tr',
        'zh'
      ],
    ),
    // CSM-1B — sesame/csm-1b conversational TTS (Apache 2.0). Llama-3.2 1B
    // backbone + depth decoder + Mimi codec, single built-in EN voice.
    'csm-1b-q4_k': ModelDefinition(
      name: 'csm-1b-q4_k',
      displayName: 'CSM 1B (q4_k)',
      fileName: 'csm-1b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/csm-1b-GGUF/resolve/main/csm-1b-q4_k.gguf',
      sizeBytes: 1400 * 1024 * 1024,
      checksum: '',
      description:
          'Sesame CSM-1B conversational TTS — single EN voice, ~1.4 GB',
      quantization: 'q4_k',
      backend: 'csm',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    // Dia-1.6B — nari-labs/Dia-1.6B dialogue TTS. Byte-level text encoder
    // + AR audio decoder + 44.1 kHz DAC codec companion.
    'dia-1.6b-f16': ModelDefinition(
      name: 'dia-1.6b-f16',
      displayName: 'Dia 1.6B (f16)',
      fileName: 'dia-1.6b-f16.gguf',
      url:
          'https://huggingface.co/cstr/dia-1.6b-GGUF/resolve/main/dia-1.6b-f16.gguf',
      sizeBytes: 3000 * 1024 * 1024,
      checksum: '',
      description:
          'Dia 1.6B dialogue TTS — use [S1]/[S2] tags for speakers, ~3 GB',
      quantization: 'f16',
      backend: 'dia',
      kind: ModelKind.tts,
      companions: ['dac-44khz'],
      languages: langsEn,
    ),
    'dac-44khz': ModelDefinition(
      name: 'dac-44khz',
      displayName: 'DAC 44.1 kHz codec',
      fileName: 'dac-44khz.gguf',
      url:
          'https://huggingface.co/cstr/dia-1.6b-GGUF/resolve/main/dac-44khz.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'DAC 44.1 kHz codec companion for Dia TTS',
      quantization: 'f16',
      backend: 'dia',
      kind: ModelKind.codec,
    ),
    // BananaMind-TTS V2.1 — Tacotron-lite + HiFi-GAN, 13M params, 22 kHz.
    // Character-level encoder, no phonemizer needed. Fixed voice per locale.
    // Apache-2.0. ~38 MB Q8_0 per locale.
    'bananamind-tts-en-q8_0': ModelDefinition(
      name: 'bananamind-tts-en-q8_0',
      displayName: 'BananaMind TTS EN (q8_0)',
      fileName: 'bananamind-tts-en-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/bananamind-tts-GGUF/resolve/main/bananamind-tts-en-q8_0.gguf',
      sizeBytes: 40110656,
      checksum: '',
      description:
          'BananaMind-TTS V2.1 — Tacotron-lite + HiFi-GAN (English, 13M params), ~38 MB',
      quantization: 'q8_0',
      backend: 'bananamind-tts',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    'bananamind-tts-de-q8_0': ModelDefinition(
      name: 'bananamind-tts-de-q8_0',
      displayName: 'BananaMind TTS DE (q8_0)',
      fileName: 'bananamind-tts-de-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/bananamind-tts-GGUF/resolve/main/bananamind-tts-de-q8_0.gguf',
      sizeBytes: 40111776,
      checksum: '',
      description:
          'BananaMind-TTS V2.1 — Tacotron-lite + HiFi-GAN (German, 13M params), ~38 MB',
      quantization: 'q8_0',
      backend: 'bananamind-tts',
      kind: ModelKind.tts,
      languages: langsDe,
    ),
    // FastPitch — NVIDIA non-autoregressive parallel TTS. Deterministic,
    // single EN speaker, 22 kHz. ~120 MB.
    'fastpitch-en-q8_0': ModelDefinition(
      name: 'fastpitch-en-q8_0',
      displayName: 'FastPitch EN (q8_0)',
      fileName: 'fastpitch-en-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/fastpitch-en-GGUF/resolve/main/fastpitch-en-q8_0.gguf',
      sizeBytes: 120 * 1024 * 1024,
      checksum: '',
      description:
          'NVIDIA FastPitch — deterministic parallel TTS (English, 60M params), ~120 MB',
      quantization: 'q8_0',
      backend: 'fastpitch',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    // MeloTTS v2 — VITS2 52M, 44.1 kHz, 4 EN speakers, MIT.
    // Needs bert-base-uncased BERT companion.
    'melotts-en-v2-f16': ModelDefinition(
      name: 'melotts-en-v2-f16',
      displayName: 'MeloTTS EN v2 (f16)',
      fileName: 'melotts-en-v2-f16.gguf',
      url:
          'https://huggingface.co/cstr/melotts-en-v2-GGUF/resolve/main/melotts-en-v2-f16.gguf',
      sizeBytes: 102 * 1024 * 1024,
      checksum: '',
      description:
          'MeloTTS v2 VITS2 TTS (4 EN speakers, 44.1 kHz) — needs BERT companion, ~102 MB',
      quantization: 'f16',
      backend: 'melotts',
      kind: ModelKind.tts,
      companions: ['bert-base-uncased-q4k'],
      languages: langsEn,
    ),
    'bert-base-uncased-q4k': ModelDefinition(
      name: 'bert-base-uncased-q4k',
      displayName: 'BERT base uncased (q4_k)',
      fileName: 'bert-base-uncased-q4k.gguf',
      url:
          'https://huggingface.co/cstr/melotts-en-v2-GGUF/resolve/main/bert-base-uncased-q4k.gguf',
      sizeBytes: 52 * 1024 * 1024,
      checksum: '',
      description: 'BERT conditioning companion for MeloTTS',
      quantization: 'q4_k',
      backend: 'melotts',
      kind: ModelKind.codec,
    ),
    // MeloTTS v3 — newest checkpoint, 1 EN speaker, MIT.
    // Shares bert-base-uncased BERT companion with v2.
    'melotts-en-v3-f16': ModelDefinition(
      name: 'melotts-en-v3-f16',
      displayName: 'MeloTTS EN v3 (f16)',
      fileName: 'melotts-en-v3-f16.gguf',
      url:
          'https://huggingface.co/cstr/melotts-en-v3-GGUF/resolve/main/melotts-en-v3-f16.gguf',
      sizeBytes: 97259520,
      checksum: '',
      description:
          'MeloTTS v3 newest checkpoint (1 EN speaker) — needs BERT companion, ~93 MB',
      quantization: 'f16',
      backend: 'melotts',
      kind: ModelKind.tts,
      companions: ['bert-base-uncased-q4k'],
      languages: langsEn,
    ),
    // OuteTTS 0.3 1B — OLMo-1B LLM + WavTokenizer VQ-GAN, 24 kHz, CC BY 4.0.
    'outetts-0.3-1b-q8_0': ModelDefinition(
      name: 'outetts-0.3-1b-q8_0',
      displayName: 'OuteTTS 0.3 1B (q8_0)',
      fileName: 'outetts-0.3-1b-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/outetts-0.3-1b-GGUF/resolve/main/outetts-0.3-1b-q8_0.gguf',
      sizeBytes: 1270 * 1024 * 1024,
      checksum: '',
      description:
          'OuteTTS 0.3 1B — OLMo + WavTokenizer, voice clone via JSON, ~1.3 GB',
      quantization: 'q8_0',
      backend: 'outetts',
      kind: ModelKind.tts,
      companions: ['wavtokenizer-decoder-f16'],
      languages: langsEn,
    ),
    'wavtokenizer-decoder-f16': ModelDefinition(
      name: 'wavtokenizer-decoder-f16',
      displayName: 'WavTokenizer decoder (f16)',
      fileName: 'wavtokenizer-decoder-f16.gguf',
      url:
          'https://huggingface.co/cstr/outetts-0.3-1b-GGUF/resolve/main/wavtokenizer-decoder-f16.gguf',
      sizeBytes: 130 * 1024 * 1024,
      checksum: '',
      description: 'WavTokenizer VQ-GAN decoder companion for OuteTTS',
      quantization: 'f16',
      backend: 'outetts',
      kind: ModelKind.codec,
    ),
    // Parler-TTS Mini v1.1 — prompt-conditioned TTS (~900M). T5 encoder +
    // MusicGen decoder + DAC 44.1 kHz. Describe voice via setInstruct().
    'parler-mini-v1.1-q8_0': ModelDefinition(
      name: 'parler-mini-v1.1-q8_0',
      displayName: 'Parler-TTS Mini v1.1 (q8_0)',
      fileName: 'parler-mini-v1.1-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/parler-tts-mini-v1.1-GGUF/resolve/main/parler-mini-v1.1-q8_0.gguf',
      sizeBytes: 900 * 1024 * 1024,
      checksum: '',
      description:
          'Parler-TTS — describe the voice in text (setInstruct), ~900 MB',
      quantization: 'q8_0',
      backend: 'parler-tts',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    // Pocket TTS — Kyutai 100M continuous-latent AR TTS, 24 kHz, MIT.
    // Voice cloning via reference WAV (needs F16 variant).
    'pocket-tts-english-f16': ModelDefinition(
      name: 'pocket-tts-english-f16',
      displayName: 'Pocket TTS English (f16)',
      fileName: 'pocket-tts-english-f16.gguf',
      url:
          'https://huggingface.co/cstr/pocket-tts-GGUF/resolve/main/pocket-tts-english-f16.gguf',
      sizeBytes: 220 * 1024 * 1024,
      checksum: '',
      description: 'Kyutai Pocket TTS 100M — voice clone from WAV, ~220 MB',
      quantization: 'f16',
      backend: 'pocket-tts',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    // SpeechT5 — Microsoft 80M AR mel decoder + HiFi-GAN vocoder.
    'speecht5-tts-f16': ModelDefinition(
      name: 'speecht5-tts-f16',
      displayName: 'SpeechT5 TTS (f16)',
      fileName: 'speecht5-tts-f16.gguf',
      url:
          'https://huggingface.co/cstr/speecht5-tts-GGUF/resolve/main/speecht5-tts-f16.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Microsoft SpeechT5 80M TTS (English), ~300 MB',
      quantization: 'f16',
      backend: 'speecht5',
      kind: ModelKind.tts,
      languages: langsEn,
    ),
    // KugelAudio — large TTS model (~14 GB F16). Single GGUF.
    'kugelaudio-0-open-f16': ModelDefinition(
      name: 'kugelaudio-0-open-f16',
      displayName: 'KugelAudio 0 Open (f16)',
      fileName: 'kugelaudio-0-open-f16.gguf',
      url:
          'https://huggingface.co/cstr/kugelaudio-0-open-GGUF/resolve/main/kugelaudio-0-open-f16.gguf',
      sizeBytes: 14 * 1024 * 1024 * 1024,
      checksum: '',
      description: 'KugelAudio 0 Open TTS — large model, ~14 GB',
      quantization: 'f16',
      backend: 'kugelaudio',
      kind: ModelKind.tts,
    ),
    // Zonos v0.1 — Zyphra 500M-param transformer TTS with emotion/pitch/rate
    // control, speaker cloning, 44.1 kHz native via DAC codec. Apache 2.0.
    'zonos-v0.1-transformer-q4_k': ModelDefinition(
      name: 'zonos-v0.1-transformer-q4_k',
      displayName: 'Zonos v0.1 (q4_k)',
      fileName: 'zonos-v0.1-transformer-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/zonos-v0.1-transformer-GGUF/resolve/main/zonos-v0.1-transformer-q4_k.gguf',
      sizeBytes: 872 * 1024 * 1024,
      checksum: '',
      description:
          'Zonos v0.1 TTS — emotion/pitch/rate control, speaker clone, 44.1 kHz, ~872 MB',
      quantization: 'q4_k',
      backend: 'zonos',
      kind: ModelKind.tts,
      companions: ['dac-44khz'],
      languages: langsAll,
    ),
    'zonos-v0.1-transformer-f16': ModelDefinition(
      name: 'zonos-v0.1-transformer-f16',
      displayName: 'Zonos v0.1 (f16)',
      fileName: 'zonos-v0.1-transformer-f16.gguf',
      url:
          'https://huggingface.co/cstr/zonos-v0.1-transformer-GGUF/resolve/main/zonos-v0.1-transformer-f16.gguf',
      sizeBytes: 3100 * 1024 * 1024,
      checksum: '',
      description:
          'Zonos v0.1 TTS reference quality — emotion/pitch/rate control, ~3.1 GB',
      quantization: 'f16',
      backend: 'zonos',
      kind: ModelKind.tts,
      companions: ['dac-44khz'],
      languages: langsAll,
    ),
    // Qwen3-TTS 1.7B Base — larger variant, same ICL voice-clone path.
    'qwen3-tts-12hz-1.7b-base-q8_0': ModelDefinition(
      name: 'qwen3-tts-12hz-1.7b-base-q8_0',
      displayName: 'Qwen3-TTS 1.7B base 12 Hz (q8_0)',
      fileName: 'qwen3-tts-12hz-1.7b-base-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-tts-1.7b-base-GGUF/resolve/main/qwen3-tts-12hz-1.7b-base-q8_0.gguf',
      sizeBytes: 1900 * 1024 * 1024,
      checksum: '',
      description:
          'Qwen3-TTS 1.7B base — higher quality, needs qwen3-tts-tokenizer-12hz codec + voice',
      quantization: 'q8_0',
      backend: 'qwen3-tts',
      kind: ModelKind.tts,
      companions: ['qwen3-tts-tokenizer-12hz'],
      requiresVoice: true,
      languages: langsQwen3Tts10,
    ),
    // Gwen-TTS — Vietnamese-optimised Qwen3-TTS-0.6B-Base finetune (MIT).
    'gwen-tts-0.6b-q8_0': ModelDefinition(
      name: 'gwen-tts-0.6b-q8_0',
      displayName: 'Gwen-TTS 0.6B Vietnamese (q8_0)',
      fileName: 'gwen-tts-0.6b-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/gwen-tts-0.6b-GGUF/resolve/main/gwen-tts-0.6b-q8_0.gguf',
      sizeBytes: 968 * 1024 * 1024,
      checksum: '',
      description:
          'Gwen-TTS — Vietnamese-optimised Qwen3-TTS finetune, needs tokenizer codec',
      quantization: 'q8_0',
      backend: 'qwen3-tts',
      kind: ModelKind.tts,
      companions: ['qwen3-tts-tokenizer-12hz'],
      languages: <String>[
        'vi',
        'en',
        'zh',
        'ja',
        'ko',
        'de',
        'fr',
        'es',
        'it',
        'pt'
      ],
    ),
    // Lahgtna Chatterbox — Arabic T3 finetune of ResembleAI/chatterbox.
    'lahgtna-chatterbox-t3-f16': ModelDefinition(
      name: 'lahgtna-chatterbox-t3-f16',
      displayName: 'Lahgtna Chatterbox Arabic (f16)',
      fileName: 'chatterbox-t3-f16.gguf',
      url:
          'https://huggingface.co/cstr/lahgtna-chatterbox-v1-GGUF/resolve/main/chatterbox-t3-f16.gguf',
      sizeBytes: 1400 * 1024 * 1024,
      checksum: '',
      description:
          'Arabic Chatterbox TTS — needs chatterbox-s3gen companion, ~1.4 GB',
      quantization: 'f16',
      backend: 'chatterbox',
      kind: ModelKind.tts,
      companions: ['chatterbox-s3gen-q8_0'],
      languages: langsAr,
    ),
    // lex-au Orpheus German — German fine-tune of Orpheus-3B.
    'lex-au-orpheus-de-q8_0': ModelDefinition(
      name: 'lex-au-orpheus-de-q8_0',
      displayName: 'Orpheus 3B German lex-au (q8_0)',
      fileName: 'Orpheus-3b-German-FT-Q8_0.gguf',
      url:
          'https://huggingface.co/lex-au/Orpheus-3b-German-FT-Q8_0.gguf/resolve/main/Orpheus-3b-German-FT-Q8_0.gguf',
      sizeBytes: 3500 * 1024 * 1024,
      checksum: '',
      description:
          'German Orpheus-3B fine-tune — needs snac-24khz codec, ~3.5 GB',
      quantization: 'q8_0',
      backend: 'orpheus',
      kind: ModelKind.tts,
      companions: ['snac-24khz'],
      languages: langsDe,
    ),
    // ---------- New ASR models ----------
    // Moonshine German variants (fidoriel fine-tunes, CC-BY-NC-SA-4.0).
    'moonshine-base-de-q4_k': ModelDefinition(
      name: 'moonshine-base-de-q4_k',
      displayName: 'Moonshine base DE (q4_k)',
      fileName: 'moonshine-base-de-fidoriel-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/moonshine-base-de-fidoriel-GGUF/resolve/main/moonshine-base-de-fidoriel-q4_k.gguf',
      sizeBytes: 39 * 1024 * 1024,
      checksum: '',
      description:
          'Moonshine base German (6.9% WER CV22, CC-BY-NC-SA) — ~39 MB',
      quantization: 'q4_k',
      backend: 'moonshine',
      kind: ModelKind.asr,
      companions: ['moonshine-tokenizer'],
      languages: langsDe,
    ),
    'moonshine-tiny-de-q4_k': ModelDefinition(
      name: 'moonshine-tiny-de-q4_k',
      displayName: 'Moonshine tiny DE (q4_k)',
      fileName: 'moonshine-tiny-de-fidoriel-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/moonshine-tiny-de-fidoriel-GGUF/resolve/main/moonshine-tiny-de-fidoriel-q4_k.gguf',
      sizeBytes: 17 * 1024 * 1024,
      checksum: '',
      description:
          'Moonshine tiny German (11.4% WER CV22, CC-BY-NC-SA) — ~17 MB',
      quantization: 'q4_k',
      backend: 'moonshine',
      kind: ModelKind.asr,
      companions: ['moonshine-tokenizer'],
      languages: langsDe,
    ),
    // HuBERT Large (wav2vec2 family) — English ASR, 212 MB Q4_K.
    'hubert-large-ls960-ft-q4_k': ModelDefinition(
      name: 'hubert-large-ls960-ft-q4_k',
      displayName: 'HuBERT Large LS960 (q4_k)',
      fileName: 'hubert-large-ls960-ft-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/hubert-large-ls960-ft-GGUF/resolve/main/hubert-large-ls960-ft-q4_k.gguf',
      sizeBytes: 200 * 1024 * 1024,
      checksum: '',
      description: 'HuBERT Large fine-tuned LS960 (English CTC) — ~200 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsEn,
    ),
    // Wav2Vec2 German — XLSR-53 German variant.
    'wav2vec2-xlsr-de-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-de-q4_k',
      displayName: 'Wav2Vec2 XLSR DE (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-german-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-german-GGUF/resolve/main/wav2vec2-large-xlsr-53-german-q4_k.gguf',
      sizeBytes: 222 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 German CTC — ~222 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsDe,
    ),
    // §10 — CTC forced aligner (canary-ctc architecture). Used by
    // AlignerService to attach word-level timestamps to any backend's
    // output. The aligner GGUF is loaded by the free function
    // crispasr_align_words_abi (no whisper ctx needed).
    'canary-ctc-aligner-q4_k': ModelDefinition(
      name: 'canary-ctc-aligner-q4_k',
      displayName: 'Canary CTC Aligner (q4_k)',
      fileName: 'canary-ctc-aligner-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/canary-ctc-aligner-GGUF/resolve/main/canary-ctc-aligner-q4_k.gguf',
      sizeBytes: 442 * 1024 * 1024,
      checksum: '',
      description:
          'Canary CTC forced aligner — attaches word-level timestamps to '
          'any ASR backend\'s output, ~442 MB',
      quantization: 'q4_k',
      backend: 'canary-ctc-aligner',
      kind: ModelKind.asr,
      languages: langsAll,
    ),
    // §10 — Wav2Vec2 XLSR-53 language variants for CTC ASR + forced
    // alignment. Each reuses the same wav2vec2 backend; the engine
    // also accepts these as `wav2vec2-aligner-<lang>` dispatch aliases.
    'wav2vec2-xlsr-fr-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-fr-q4_k',
      displayName: 'Wav2Vec2 XLSR FR (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-french-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-french-GGUF/resolve/main/wav2vec2-large-xlsr-53-french-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 French CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsFr,
    ),
    'wav2vec2-xlsr-es-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-es-q4_k',
      displayName: 'Wav2Vec2 XLSR ES (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-spanish-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-spanish-GGUF/resolve/main/wav2vec2-large-xlsr-53-spanish-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 Spanish CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsEs,
    ),
    'wav2vec2-xlsr-it-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-it-q4_k',
      displayName: 'Wav2Vec2 XLSR IT (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-italian-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-italian-GGUF/resolve/main/wav2vec2-large-xlsr-53-italian-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 Italian CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsIt,
    ),
    'wav2vec2-xlsr-ja-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-ja-q4_k',
      displayName: 'Wav2Vec2 XLSR JA (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-japanese-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-japanese-GGUF/resolve/main/wav2vec2-large-xlsr-53-japanese-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 Japanese CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsJa,
    ),
    'wav2vec2-xlsr-zh-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-zh-q4_k',
      displayName: 'Wav2Vec2 XLSR ZH (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-chinese-zh-cn-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-chinese-zh-cn-GGUF/resolve/main/wav2vec2-large-xlsr-53-chinese-zh-cn-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 Chinese (zh-CN) CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsZh,
    ),
    'wav2vec2-xlsr-nl-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-nl-q4_k',
      displayName: 'Wav2Vec2 XLSR NL (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-dutch-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-dutch-GGUF/resolve/main/wav2vec2-large-xlsr-53-dutch-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 Dutch CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsNl,
    ),
    'wav2vec2-xlsr-pt-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-pt-q4_k',
      displayName: 'Wav2Vec2 XLSR PT (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-portuguese-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-portuguese-GGUF/resolve/main/wav2vec2-large-xlsr-53-portuguese-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 Portuguese CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsPt,
    ),
    'wav2vec2-xlsr-ar-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-ar-q4_k',
      displayName: 'Wav2Vec2 XLSR AR (q4_k)',
      fileName: 'wav2vec2-large-xlsr-53-arabic-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-large-xlsr-53-arabic-GGUF/resolve/main/wav2vec2-large-xlsr-53-arabic-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLSR-53 Arabic CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsAr,
    ),
    'wav2vec2-xlsr-cs-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-cs-q4_k',
      displayName: 'Wav2Vec2 XLS-R CS (q4_k)',
      fileName: 'wav2vec2-xls-r-300m-cs-250-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-xls-r-300m-cs-250-GGUF/resolve/main/wav2vec2-xls-r-300m-cs-250-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLS-R 300M Czech CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsCs,
    ),
    'wav2vec2-xlsr-uk-q4_k': ModelDefinition(
      name: 'wav2vec2-xlsr-uk-q4_k',
      displayName: 'Wav2Vec2 XLS-R UK (q4_k)',
      fileName: 'wav2vec2-xls-r-300m-uk-with-small-lm-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/wav2vec2-xls-r-300m-uk-with-small-lm-GGUF/resolve/main/wav2vec2-xls-r-300m-uk-with-small-lm-q4_k.gguf',
      sizeBytes: 300 * 1024 * 1024,
      checksum: '',
      description: 'Wav2Vec2 XLS-R 300M Ukrainian CTC — ~300 MB',
      quantization: 'q4_k',
      backend: 'wav2vec2',
      kind: ModelKind.asr,
      languages: langsUk,
    ),
    // OmniASR CTC 300M — tiny 1600+ language CTC model.
    'omniasr-ctc-300m-v2-q4_k': ModelDefinition(
      name: 'omniasr-ctc-300m-v2-q4_k',
      displayName: 'OmniASR CTC 300M v2 (q4_k)',
      fileName: 'omniasr-ctc-300m-v2-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/omniASR-CTC-300M-v2-GGUF/resolve/main/omniasr-ctc-300m-v2-q4_k.gguf',
      sizeBytes: 194 * 1024 * 1024,
      checksum: '',
      description: 'OmniASR CTC 300M — 1600+ languages, ~194 MB',
      quantization: 'q4_k',
      // Backend stays `omniasr` (matches the omniasr-ctc BackendRepo). The
      // engine also advertises a dispatch alias `omniasr-300m` for this
      // model — that alias sits on the parity test's engineOnly set.
      backend: 'omniasr',
      kind: ModelKind.asr,
      languages: langsAll,
    ),
    // Parakeet Japanese — TDT 0.6B JA fine-tune (F16 default — Q4_K is
    // quant-sensitive and loops).
    'parakeet-tdt-0.6b-ja-f16': ModelDefinition(
      name: 'parakeet-tdt-0.6b-ja-f16',
      displayName: 'Parakeet TDT 0.6B JA (f16)',
      fileName: 'parakeet-tdt-0.6b-ja.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-tdt-0.6b-ja-GGUF/resolve/main/parakeet-tdt-0.6b-ja.gguf',
      sizeBytes: 1240 * 1024 * 1024,
      checksum: '',
      description: 'Parakeet TDT 0.6B Japanese — F16 recommended, ~1.24 GB',
      quantization: 'f16',
      backend: 'parakeet',
      kind: ModelKind.asr,
      languages: langsJa,
    ),
    // Parakeet CTC 0.6B — CTC-only English model.
    'parakeet-ctc-0.6b-q4_k': ModelDefinition(
      name: 'parakeet-ctc-0.6b-q4_k',
      displayName: 'Parakeet CTC 0.6B (q4_k)',
      fileName: 'parakeet-ctc-0.6b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-ctc-0.6b-GGUF/resolve/main/parakeet-ctc-0.6b-q4_k.gguf',
      sizeBytes: 455 * 1024 * 1024,
      checksum: '',
      description: 'Parakeet CTC-only 0.6B English — ~455 MB',
      quantization: 'q4_k',
      backend: 'fastconformer-ctc',
      kind: ModelKind.asr,
      languages: langsEn,
    ),
    // Parakeet CTC 1.1B — larger CTC-only English model.
    'parakeet-ctc-1.1b-q4_k': ModelDefinition(
      name: 'parakeet-ctc-1.1b-q4_k',
      displayName: 'Parakeet CTC 1.1B (q4_k)',
      fileName: 'parakeet-ctc-1.1b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-ctc-1.1b-GGUF/resolve/main/parakeet-ctc-1.1b-q4_k.gguf',
      sizeBytes: 795 * 1024 * 1024,
      checksum: '',
      description: 'Parakeet CTC-only 1.1B English — ~795 MB',
      quantization: 'q4_k',
      backend: 'fastconformer-ctc',
      kind: ModelKind.asr,
      languages: langsEn,
    ),
    // Parakeet TDT+CTC hybrid 110M — tiny, auto-flips to CTC.
    'parakeet-tdt_ctc-110m-q4_k': ModelDefinition(
      name: 'parakeet-tdt_ctc-110m-q4_k',
      displayName: 'Parakeet TDT+CTC 110M (q4_k)',
      fileName: 'parakeet-tdt_ctc-110m-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-tdt_ctc-110m-GGUF/resolve/main/parakeet-tdt_ctc-110m-q4_k.gguf',
      sizeBytes: 91 * 1024 * 1024,
      checksum: '',
      description: 'Parakeet TDT+CTC 110M English — tiny hybrid, ~91 MB',
      quantization: 'q4_k',
      backend: 'parakeet',
      kind: ModelKind.asr,
      languages: langsEn,
    ),
    // Parakeet TDT+CTC 1.1B — large hybrid, multilingual.
    'parakeet-tdt_ctc-1.1b-q4_k': ModelDefinition(
      name: 'parakeet-tdt_ctc-1.1b-q4_k',
      displayName: 'Parakeet TDT+CTC 1.1B (q4_k)',
      fileName: 'parakeet-tdt_ctc-1.1b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-tdt_ctc-1.1b-GGUF/resolve/main/parakeet-tdt_ctc-1.1b-q4_k.gguf',
      sizeBytes: 810 * 1024 * 1024,
      checksum: '',
      description:
          'Parakeet TDT+CTC 1.1B — large hybrid, multilingual, ~810 MB',
      quantization: 'q4_k',
      backend: 'parakeet',
      kind: ModelKind.asr,
      languages: langsEU25,
    ),
    // Parakeet RNNT 0.6B — standard RNN-Transducer, English-only.
    'parakeet-rnnt-0.6b-q4_k': ModelDefinition(
      name: 'parakeet-rnnt-0.6b-q4_k',
      displayName: 'Parakeet RNNT 0.6B (q4_k)',
      fileName: 'parakeet-rnnt-0.6b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-rnnt-0.6b-GGUF/resolve/main/parakeet-rnnt-0.6b-q4_k.gguf',
      sizeBytes: 447 * 1024 * 1024,
      checksum: '',
      description: 'Parakeet RNNT 0.6B English — RNN-Transducer, ~447 MB',
      quantization: 'q4_k',
      backend: 'parakeet',
      kind: ModelKind.asr,
      languages: langsEn,
    ),
    // Parakeet RNNT 1.1B — larger RNN-Transducer, English-only.
    'parakeet-rnnt-1.1b-q4_k': ModelDefinition(
      name: 'parakeet-rnnt-1.1b-q4_k',
      displayName: 'Parakeet RNNT 1.1B (q4_k)',
      fileName: 'parakeet-rnnt-1.1b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/parakeet-rnnt-1.1b-GGUF/resolve/main/parakeet-rnnt-1.1b-q4_k.gguf',
      sizeBytes: 770 * 1024 * 1024,
      checksum: '',
      description:
          'Parakeet RNNT 1.1B English — larger RNN-Transducer, ~770 MB',
      quantization: 'q4_k',
      backend: 'parakeet',
      kind: ModelKind.asr,
      languages: langsEn,
    ),
    // ---------- Text LID models ----------
    // GlotLID-V3 — fastText supervised, 2102 ISO 639-3 + script labels.
    'glotlid-f16': ModelDefinition(
      name: 'glotlid-f16',
      displayName: 'GlotLID v3 (f16)',
      fileName: 'glotlid-f16.gguf',
      url:
          'https://huggingface.co/cstr/glotlid-GGUF/resolve/main/glotlid-f16.gguf',
      sizeBytes: 250 * 1024 * 1024,
      checksum: '',
      description:
          'GlotLID v3 text language ID — 2102 languages (ISO 639-3), ~250 MB',
      quantization: 'f16',
      backend: 'lid',
      kind: ModelKind.lid,
    ),
    // LID-176 — Facebook fastText hierarchical, 176 languages. CC-BY-SA-3.0.
    'fasttext-lid176-f16': ModelDefinition(
      name: 'fasttext-lid176-f16',
      displayName: 'FastText LID-176 (f16)',
      fileName: 'fasttext-lid176-f16.gguf',
      url:
          'https://huggingface.co/cstr/fasttext-lid176-GGUF/resolve/main/fasttext-lid176-f16.gguf',
      sizeBytes: 63 * 1024 * 1024,
      checksum: '',
      description:
          'Facebook LID-176 text language ID — 176 languages (CC-BY-SA-3.0), ~63 MB',
      quantization: 'f16',
      backend: 'lid',
      kind: ModelKind.lid,
    ),
    // ---------- Truecaser models (cstr/truecaser-de) ----------
    // BiLSTM character-level truecaser — restores capitalization on
    // lowercased text. .bin format, loaded via TruecaseModel.
    'truecaser-lstm-de': ModelDefinition(
      name: 'truecaser-lstm-de',
      displayName: 'Truecaser BiLSTM German',
      fileName: 'truecaser-lstm-de.bin',
      url:
          'https://huggingface.co/cstr/truecaser-de/resolve/main/truecaser-lstm-de.bin',
      sizeBytes: 3182823,
      checksum: '',
      description:
          'BiLSTM truecaser for German (97.9% F1) — ~3 MB. Best quality.',
      quantization: '',
      backend: 'truecaser',
      kind: ModelKind.punc,
      languages: langsDe,
    ),
    'truecaser-lstm-en': ModelDefinition(
      name: 'truecaser-lstm-en',
      displayName: 'Truecaser BiLSTM English',
      fileName: 'truecaser-lstm-en.bin',
      url:
          'https://huggingface.co/cstr/truecaser-de/resolve/main/truecaser-lstm-en.bin',
      sizeBytes: 3243382,
      checksum: '',
      description: 'BiLSTM truecaser for English — ~3 MB',
      quantization: '',
      backend: 'truecaser',
      kind: ModelKind.punc,
      languages: langsEn,
    ),
    'truecaser-lstm-es': ModelDefinition(
      name: 'truecaser-lstm-es',
      displayName: 'Truecaser BiLSTM Spanish',
      fileName: 'truecaser-lstm-es.bin',
      url:
          'https://huggingface.co/cstr/truecaser-de/resolve/main/truecaser-lstm-es.bin',
      sizeBytes: 3180167,
      checksum: '',
      description: 'BiLSTM truecaser for Spanish — ~3 MB',
      quantization: '',
      backend: 'truecaser',
      kind: ModelKind.punc,
      languages: langsEs,
    ),
    'truecaser-lstm-ru': ModelDefinition(
      name: 'truecaser-lstm-ru',
      displayName: 'Truecaser BiLSTM Russian',
      fileName: 'truecaser-lstm-ru.bin',
      url:
          'https://huggingface.co/cstr/truecaser-de/resolve/main/truecaser-lstm-ru.bin',
      sizeBytes: 4095045,
      checksum: '',
      description: 'BiLSTM truecaser for Russian — ~4 MB',
      quantization: '',
      backend: 'truecaser',
      kind: ModelKind.punc,
      languages: langsRu,
    ),
    'truecaser-crf-de': ModelDefinition(
      name: 'truecaser-crf-de',
      displayName: 'Truecaser CRF German',
      fileName: 'truecaser-crf-de.bin',
      url:
          'https://huggingface.co/cstr/truecaser-de/resolve/main/truecaser-crf-de.bin',
      sizeBytes: 8520626,
      checksum: '',
      description: 'CRF truecaser for German — ~8 MB',
      quantization: '',
      backend: 'truecaser',
      kind: ModelKind.punc,
      languages: langsDe,
    ),
    // ---------- PCS (Punctuation + Capitalization + Segmentation) ----------
    // XLM-RoBERTa-base + 4 classification heads. 47 languages, MIT license.
    // All-in-one: punctuation + truecasing + sentence boundary detection.
    'pcs-xlmr-base-q4_k': ModelDefinition(
      name: 'pcs-xlmr-base-q4_k',
      displayName: 'PCS XLM-R base (q4_k)',
      fileName: 'pcs-xlmr-base-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/pcs-xlmr-base-GGUF/resolve/main/pcs-xlmr-base-q4_k.gguf',
      sizeBytes: 155 * 1024 * 1024,
      checksum: '',
      description:
          'PCS — punctuation + truecasing + sentence boundaries in one pass (47 languages), ~155 MB',
      quantization: 'q4_k',
      backend: 'pcs',
      kind: ModelKind.punc,
      languages: langsAll,
    ),
    'pcs-xlmr-base-f16': ModelDefinition(
      name: 'pcs-xlmr-base-f16',
      displayName: 'PCS XLM-R base (f16)',
      fileName: 'pcs-xlmr-base.gguf',
      url:
          'https://huggingface.co/cstr/pcs-xlmr-base-GGUF/resolve/main/pcs-xlmr-base.gguf',
      sizeBytes: 903 * 1024 * 1024,
      checksum: '',
      description:
          'PCS — punctuation + truecasing + sentence boundaries, reference quality, ~903 MB',
      quantization: 'f16',
      backend: 'pcs',
      kind: ModelKind.punc,
      languages: langsAll,
    ),
    // ─────────────────────────────────────────────────────────────
    // §5.1.6 v3.1 — Curated chat-LLM catalogue.
    //
    // Pointed at bartowski's GGUF repos for stability — bartowski
    // re-publishes new model releases promptly + keeps the layout
    // consistent across families. Quantization picked is Q4_K_M
    // throughout: the smallest variant that still keeps quality
    // close to FP16 on these instruction-tuned models, and the
    // industry default for "small enough to run on a laptop, big
    // enough to be useful".
    //
    // Recommended nCtx / nGpuLayers per model live in the model
    // description text — the user always gets sensible session
    // defaults from `ChatOpenParams()`, and the Settings → Local
    // LLM advanced section's sliders let them override
    // per-machine. We don't materialise the recommended values
    // into ModelDefinition because the Tidy / Summarize call
    // sites don't reach into the registry — they read whatever
    // is on disk and let the user tune via Settings.
    // ─────────────────────────────────────────────────────────────
    'smollm2-360m-instruct-q4_k_m': ModelDefinition(
      name: 'smollm2-360m-instruct-q4_k_m',
      displayName: 'SmolLM2 360M Instruct (Q4_K_M)',
      fileName: 'SmolLM2-360M-Instruct-Q4_K_M.gguf',
      url:
          'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf',
      sizeBytes: 270 * 1024 * 1024,
      checksum: '',
      description:
          'Tiny chat model (~270 MB) for low-resource hosts. Recommended nCtx 2048. Good for short Tidy passes; under-powered for long-form summarisation.',
      quantization: 'q4_k_m',
      backend: 'chat',
      kind: ModelKind.chatLlm,
    ),
    'qwen2.5-0.5b-instruct-q4_k_m': ModelDefinition(
      name: 'qwen2.5-0.5b-instruct-q4_k_m',
      displayName: 'Qwen2.5 0.5B Instruct (Q4_K_M)',
      fileName: 'Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
      url:
          'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
      sizeBytes: 400 * 1024 * 1024,
      checksum: '',
      description:
          'Small multilingual chat model (~400 MB). Recommended nCtx 4096. Solid choice when memory or CPU is tight; reasonable Tidy + short-summary quality.',
      quantization: 'q4_k_m',
      backend: 'chat',
      kind: ModelKind.chatLlm,
    ),
    'llama-3.2-1b-instruct-q4_k_m': ModelDefinition(
      name: 'llama-3.2-1b-instruct-q4_k_m',
      displayName: 'Llama 3.2 1B Instruct (Q4_K_M)',
      fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      sizeBytes: 770 * 1024 * 1024,
      checksum: '',
      description:
          'Balanced English-first chat model (~770 MB). Recommended nCtx 4096. Good Tidy quality, usable long-form summarisation; Meta Llama 3 community license.',
      quantization: 'q4_k_m',
      backend: 'chat',
      kind: ModelKind.chatLlm,
    ),
    'qwen2.5-3b-instruct-q4_k_m': ModelDefinition(
      name: 'qwen2.5-3b-instruct-q4_k_m',
      displayName: 'Qwen2.5 3B Instruct (Q4_K_M)',
      fileName: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      url:
          'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2 * 1024 * 1024 * 1024,
      checksum: '',
      description:
          'Strong multilingual chat model (~2 GB). Recommended nCtx 8192. Excellent for both Tidy and Summarize; Apache-2.0 license. Recommended default on machines with ≥8 GB RAM.',
      quantization: 'q4_k_m',
      backend: 'chat',
      kind: ModelKind.chatLlm,
    ),
    'llama-3.2-3b-instruct-q4_k_m': ModelDefinition(
      name: 'llama-3.2-3b-instruct-q4_k_m',
      displayName: 'Llama 3.2 3B Instruct (Q4_K_M)',
      fileName: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2 * 1024 * 1024 * 1024,
      checksum: '',
      description:
          'English-first chat model (~2 GB). Recommended nCtx 8192. Strong Tidy + Summarize quality; Meta Llama 3 community license. Alternative to Qwen2.5-3B with different stylistic biases.',
      quantization: 'q4_k_m',
      backend: 'chat',
      kind: ModelKind.chatLlm,
    ),

    // §5.25.2 — Embedding models for semantic transcript search
    // §12.4 — IQ4_XS+imatrix is now the recommended default: smaller
    // (~19 MB vs 23 MB) and higher cosine fidelity than plain Q8_0
    // thanks to activation-weighted importance-matrix quantization.
    'all-minilm-l6-v2-iq4_xs': ModelDefinition(
      name: 'all-minilm-l6-v2-iq4_xs',
      displayName: 'all-MiniLM-L6-v2 (IQ4_XS+imatrix)',
      fileName: 'all-MiniLM-L6-v2-iq4_xs.gguf',
      url:
          'https://huggingface.co/cstr/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2-iq4_xs.gguf',
      sizeBytes: 19 * 1024 * 1024,
      checksum: '',
      description:
          'Compact 384-dim text embedding model (~19 MB IQ4_XS+imatrix). Higher cosine fidelity than Q8_0. Fast semantic search. Apache 2.0 license.',
      quantization: 'iq4_xs',
      backend: 'embed',
      kind: ModelKind.embed,
      languages: ['*'],
    ),
    // Legacy Q8_0 variant — kept for users who already downloaded it.
    'all-minilm-l6-v2-q8_0': ModelDefinition(
      name: 'all-minilm-l6-v2-q8_0',
      displayName: 'all-MiniLM-L6-v2 (Q8_0)',
      fileName: 'all-MiniLM-L6-v2-Q8_0.gguf',
      url:
          'https://huggingface.co/cstr/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2-Q8_0.gguf',
      sizeBytes: 23 * 1024 * 1024,
      checksum: '',
      description:
          'Compact 384-dim text embedding model (~23 MB Q8_0). Fast semantic search over transcript history. Apache 2.0 license.',
      quantization: 'q8_0',
      backend: 'embed',
      kind: ModelKind.embed,
      languages: ['*'],
    ),
    // §5.25.2 — Omnimodal embedding model: text + audio + vision → shared
    // 2048-d vector space. Enables cross-modal search (type text query,
    // match against audio embeddings). Requires CrispEmbed build with
    // crisp_audio support compiled in.
    'bidirlm-omni-2.5b-q4_k': ModelDefinition(
      name: 'bidirlm-omni-2.5b-q4_k',
      displayName: 'BidirLM-Omni 2.5B (Q4_K)',
      fileName: 'bidirlm-omni-2.5b-Q4_K.gguf',
      url:
          'https://huggingface.co/cstr/bidirlm-omni-2.5b-GGUF/resolve/main/bidirlm-omni-2.5b-Q4_K.gguf',
      sizeBytes: 1700 * 1024 * 1024,
      checksum: '',
      description:
          'Omnimodal 2048-dim embedding model (~1.7 GB Q4_K). Text + audio + vision in a shared vector space — enables cross-modal transcript search. Apache 2.0 license.',
      quantization: 'q4_k',
      backend: 'embed',
      kind: ModelKind.embed,
      languages: ['*'],
    ),

    // §12.6b — OCR models (via CrispEmbed)
    'pix2tex-mfr-q4_k': ModelDefinition(
      name: 'pix2tex-mfr-q4_k',
      displayName: 'pix2tex Math OCR (Q4_K)',
      fileName: 'pix2tex-mfr-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/pix2tex-mfr-gguf/resolve/main/pix2tex-mfr-q4_k.gguf',
      sizeBytes: 17 * 1024 * 1024,
      checksum: '',
      description:
          'DeiT+TrOCR math formula recognition (~17 MB Q4_K). Converts images of equations to LaTeX. MIT license.',
      quantization: 'q4_k',
      backend: 'ocr',
      kind: ModelKind.ocr,
    ),
    'hmer-hw-q4_k': ModelDefinition(
      name: 'hmer-hw-q4_k',
      displayName: 'HMER Handwritten Math (Q4_K)',
      fileName: 'hmer-hw-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/hmer-handwritten-math-gguf/resolve/main/hmer-hw-q4_k.gguf',
      sizeBytes: 5 * 1024 * 1024,
      checksum: '',
      description:
          'DenseNet+Transformer handwritten math OCR (~5 MB Q4_K). MIT license.',
      quantization: 'q4_k',
      backend: 'ocr',
      kind: ModelKind.ocr,
    ),
    'bttr-hw-q4_k': ModelDefinition(
      name: 'bttr-hw-q4_k',
      displayName: 'BTTR Handwritten Math (Q4_K)',
      fileName: 'bttr-hw-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/bttr-handwritten-math-gguf/resolve/main/bttr-hw-q4_k.gguf',
      sizeBytes: 5 * 1024 * 1024,
      checksum: '',
      description:
          'Bidirectional Transformer handwritten math OCR (~5 MB Q4_K). MIT license.',
      quantization: 'q4_k',
      backend: 'ocr',
      kind: ModelKind.ocr,
    ),
    'posformer-crohme-q8_0': ModelDefinition(
      name: 'posformer-crohme-q8_0',
      displayName: 'PosFormer CROHME (Q8_0)',
      fileName: 'posformer-crohme-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/posformer-crohme-GGUF/resolve/main/posformer-crohme-q8_0.gguf',
      sizeBytes: 12 * 1024 * 1024,
      checksum: '',
      description:
          'DenseNet+Transformer+ARM handwritten math OCR (~12 MB Q8_0). CROHME benchmark. CC-BY-NC-SA-3.0 license.',
      quantization: 'q8_0',
      backend: 'ocr',
      kind: ModelKind.ocr,
      license: 'cc-by-nc-sa-3.0',
    ),
    'granite-vision-3.3-2b-q4_k': ModelDefinition(
      name: 'granite-vision-3.3-2b-q4_k',
      displayName: 'Granite Vision 3.3 2B (Q4_K)',
      fileName: 'granite-vision-3.3-2b-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/granite-vision-crispembed-GGUF/resolve/main/granite-vision-3.3-2b-q4_k.gguf',
      sizeBytes: 1913 * 1024 * 1024,
      checksum: '',
      description:
          'SigLIP ViT + Granite 2B VLM document OCR (~1.9 GB Q4_K). Batched prefill, per-token confidences. Apache 2.0 license.',
      quantization: 'q4_k',
      backend: 'ocr',
      kind: ModelKind.ocr,
    ),
    'deepseek-ocr2-f16': ModelDefinition(
      name: 'deepseek-ocr2-f16',
      displayName: 'DeepSeek-OCR2 (F16)',
      fileName: 'deepseek-ocr2-f16.gguf',
      url:
          'https://huggingface.co/cstr/deepseek-ocr2-crispembed-GGUF/resolve/main/deepseek-ocr2-f16.gguf',
      sizeBytes: 6500 * 1024 * 1024,
      checksum: '',
      description:
          'SAM vision + Qwen2 encoder + MoE decoder document OCR (~6.5 GB F16). Metal-accelerated. Apache 2.0 license.',
      quantization: 'f16',
      backend: 'ocr',
      kind: ModelKind.ocr,
    ),

    // §14.3i — Optical Music Recognition (OMR) engines from CrispEmbed 0.15.x
    'smt-grandstaff-q8_0': ModelDefinition(
      name: 'smt-grandstaff-q8_0',
      displayName: 'SMT++ Grandstaff OMR (Q8_0)',
      fileName: 'smt-grandstaff-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/smt-grandstaff-GGUF/resolve/main/smt-grandstaff-q8_0.gguf',
      sizeBytes: 24 * 1024 * 1024,
      checksum: '',
      description:
          'Sheet Music Transformer: staff notation → bekern (21.4M, pianoform). MIT license.',
      quantization: 'q8_0',
      backend: 'ocr',
      kind: ModelKind.omr,
    ),
    'smt-fp-grandstaff-q8_0': ModelDefinition(
      name: 'smt-fp-grandstaff-q8_0',
      displayName: 'SMT++ Full-Page OMR (Q8_0)',
      fileName: 'smt-fp-grandstaff-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/smt-fp-grandstaff-GGUF/resolve/main/smt-fp-grandstaff-q8_0.gguf',
      sizeBytes: 16 * 1024 * 1024,
      checksum: '',
      description:
          'SMT++ full-page OMR: whole pianoform page → bekern (10.9M). MIT license.',
      quantization: 'q8_0',
      backend: 'ocr',
      kind: ModelKind.omr,
    ),
    'tromr-q8_0': ModelDefinition(
      name: 'tromr-q8_0',
      displayName: 'Polyphonic-TrOMR (Q8_0)',
      fileName: 'tromr-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/tromr-GGUF/resolve/main/tromr-q8_0.gguf',
      sizeBytes: 31 * 1024 * 1024,
      checksum: '',
      description:
          'Polyphonic TrOMR: ResNetV2 + ViT encoder, 3-stream AR decoder for rhythm/pitch/lift (22M). Apache 2.0.',
      quantization: 'q8_0',
      backend: 'ocr',
      kind: ModelKind.omr,
    ),
    'flova-omr-q4_k': ModelDefinition(
      name: 'flova-omr-q4_k',
      displayName: 'Flova OMR (Q4_K)',
      fileName: 'flova-q4_k.gguf',
      url:
          'https://huggingface.co/cstr/flova-omr-GGUF/resolve/main/flova-q4_k.gguf',
      sizeBytes: 88 * 1024 * 1024,
      checksum: '',
      description:
          'Flova: DonutSwin + mBART decoder for handwritten/whiteboard music → LilyPond (143M). Apache 2.0.',
      quantization: 'q4_k',
      backend: 'ocr',
      kind: ModelKind.omr,
    ),
    'transcoda-omr-q8_0': ModelDefinition(
      name: 'transcoda-omr-q8_0',
      displayName: 'Transcoda-59M OMR (Q8_0)',
      fileName: 'transcoda-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/transcoda-omr-GGUF/resolve/main/transcoda-q8_0.gguf',
      sizeBytes: 120 * 1024 * 1024,
      checksum: '',
      description:
          'Transcoda: ConvNeXt-V2 + RoPE cross-attn decoder for full-page score → Humdrum **kern (59M). CC-BY-4.0.',
      quantization: 'q8_0',
      backend: 'ocr',
      kind: ModelKind.omr,
      license: 'cc-by-4.0',
    ),

    // §12.3a — Cross-encoder rerankers for search result re-scoring
    'ms-marco-minilm-l-6-v2-iq4_xs': ModelDefinition(
      name: 'ms-marco-minilm-l-6-v2-iq4_xs',
      displayName: 'MS MARCO MiniLM-L6 Reranker (IQ4_XS)',
      fileName: 'ms-marco-MiniLM-L-6-v2-iq4_xs.gguf',
      url:
          'https://huggingface.co/cstr/ms-marco-MiniLM-L-6-v2-GGUF/resolve/main/ms-marco-MiniLM-L-6-v2-iq4_xs.gguf',
      sizeBytes: 19 * 1024 * 1024,
      checksum: '',
      description:
          'Compact cross-encoder reranker (~19 MB IQ4_XS). Boosts search precision on top-k cosine results. Apache 2.0.',
      quantization: 'iq4_xs',
      backend: 'reranker',
      kind: ModelKind.reranker,
      languages: const ['en'],
    ),
    'mxbai-rerank-xsmall-v1-q8_0': ModelDefinition(
      name: 'mxbai-rerank-xsmall-v1-q8_0',
      displayName: 'mxbai Rerank XSmall (Q8_0)',
      fileName: 'mxbai-rerank-xsmall-v1-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/mxbai-rerank-xsmall-v1-GGUF/resolve/main/mxbai-rerank-xsmall-v1-q8_0.gguf',
      sizeBytes: 78 * 1024 * 1024,
      checksum: '',
      description:
          'Cross-encoder reranker (~78 MB Q8_0). Higher accuracy than MS MARCO MiniLM. Apache 2.0.',
      quantization: 'q8_0',
      backend: 'reranker',
      kind: ModelKind.reranker,
      languages: const ['en'],
    ),
    'bge-reranker-v2-m3-q8_0': ModelDefinition(
      name: 'bge-reranker-v2-m3-q8_0',
      displayName: 'BGE Reranker v2 M3 (Q8_0)',
      fileName: 'bge-reranker-v2-m3-q8_0.gguf',
      url:
          'https://huggingface.co/cstr/bge-reranker-v2-m3-GGUF/resolve/main/bge-reranker-v2-m3-q8_0.gguf',
      sizeBytes: 613 * 1024 * 1024,
      checksum: '',
      description:
          'Multilingual cross-encoder reranker (~613 MB Q8_0). Supports 100+ languages. Apache 2.0.',
      quantization: 'q8_0',
      backend: 'reranker',
      kind: ModelKind.reranker,
      languages: const ['*'],
    ),

    // §12.4 — Larger embedding models for higher-quality search
    'nomic-embed-text-v1.5-q4_k': ModelDefinition(
      name: 'nomic-embed-text-v1.5-q4_k',
      displayName: 'Nomic Embed v1.5 (Q4_K+imatrix)',
      fileName: 'nomic-embed-text-v1.5-q4_k-imatrix.gguf',
      url:
          'https://huggingface.co/cstr/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5-q4_k-imatrix.gguf',
      sizeBytes: 89 * 1024 * 1024,
      checksum: '',
      description:
          '768-dim text embedding (~89 MB Q4_K+imatrix). Nomic BERT with 8192 context. Apache 2.0.',
      quantization: 'q4_k',
      backend: 'embed',
      kind: ModelKind.embed,
      languages: const ['en'],
    ),
    'multilingual-e5-small-iq4_xs': ModelDefinition(
      name: 'multilingual-e5-small-iq4_xs',
      displayName: 'Multilingual E5 Small (IQ4_XS)',
      fileName: 'multilingual-e5-small-iq4_xs.gguf',
      url:
          'https://huggingface.co/cstr/multilingual-e5-small-GGUF/resolve/main/multilingual-e5-small-iq4_xs.gguf',
      sizeBytes: 121 * 1024 * 1024,
      checksum: '',
      description:
          '384-dim multilingual embedding (~121 MB IQ4_XS). 100+ languages. MIT license.',
      quantization: 'iq4_xs',
      backend: 'embed',
      kind: ModelKind.embed,
      languages: const ['*'],
    ),
    'qwen3-embed-0.6b-q4_k': ModelDefinition(
      name: 'qwen3-embed-0.6b-q4_k',
      displayName: 'Qwen3 Embedding 0.6B (Q4_K+imatrix)',
      fileName: 'qwen3-embed-0.6b-q4_k-imatrix.gguf',
      url:
          'https://huggingface.co/cstr/qwen3-embed-0.6b-GGUF/resolve/main/qwen3-embed-0.6b-q4_k-imatrix.gguf',
      sizeBytes: 419 * 1024 * 1024,
      checksum: '',
      description:
          '1024-dim decoder embedding (~419 MB Q4_K+imatrix). Multilingual, Matryoshka-capable. Apache 2.0.',
      quantization: 'q4_k',
      backend: 'embed',
      kind: ModelKind.embed,
      languages: const ['*'],
    ),
  };

  /// PLAN §5.4 — the "smallest functional default" model per backend
  /// (CrispASR's `-m auto` parity). Keyed by backend id → the catalogue
  /// `name` of the entry that backend should start from. A Map keeps the
  /// "at most one default per backend" invariant *structural* — keys are
  /// unique, so two defaults can't slip in for the same backend.
  ///
  /// Only the user-facing ASR / TTS / chat entry points are flagged —
  /// the model a fresh user actually picks first. Pure companions
  /// (codecs, tokenizers, voicepacks, BigVGAN), post-processors,
  /// VAD / LID / diarisation / translation helpers are deliberately
  /// absent: [defaultForBackend] returns `null` for them and every
  /// caller degrades gracefully. Each referenced name must resolve via
  /// [lookupDefinition] to a def whose `backend` equals the key — the
  /// `model_recommended_default_test.dart` guard enforces both.
  static const Map<String, String> recommendedDefaultModels = {
    // ASR
    'whisper': 'base',
    'parakeet': 'parakeet-tdt-0.6b-v3-q4_k',
    'canary': 'canary-1b-v2-q5_0',
    'voxtral': 'voxtral-mini-3b-2507-q4_k',
    'voxtral4b': 'voxtral-mini-4b-realtime-q4_k',
    'qwen3': 'qwen3-asr-0.6b-q4_k',
    'mega-asr': 'mega-asr-1.7b-q4_k',
    'omniasr-llm': 'omniasr-llm-300m-v2-q4_k',
    'omniasr-llm-unlimited': 'omniasr-llm-unlimited-q4_k',
    'funasr': 'funasr-nano-2512-q4_k',
    'paraformer': 'paraformer-zh-q4_k',
    'sensevoice': 'sensevoice-small-q4_k',
    'firered-asr': 'firered-asr2-aed-q4_k',
    'kyutai-stt': 'kyutai-stt-1b-q4_k',
    'glm-asr': 'glm-asr-nano-q4_k',
    'moonshine': 'moonshine-tiny-q4_k',
    'moonshine-streaming': 'moonshine-streaming-tiny-q4_k',
    'vibevoice': 'vibevoice-asr-q4_k',
    'mimo-asr': 'mimo-asr-q4_k',
    'granite-4.1': 'granite-speech-4.1-2b-q4_k',
    'granite-4.1-plus': 'granite-speech-4.1-plus-q4_k',
    'granite-4.1-nar': 'granite-speech-4.1-nar-q4_k',
    'gemma4-e2b': 'gemma4-e2b-q4_k',
    'canary-ctc-aligner': 'canary-ctc-aligner-q4_k',
    'moss-audio': 'moss-audio-4b-instruct-q4_k',
    'moss-transcribe': 'moss-transcribe-preview-2b-q4_k',
    'moss-diarize': 'moss-transcribe-diarize-0.9b-q4_k',
    'nemotron': 'nemotron-3.5-asr-streaming-0.6b-q4_k',
    'canary-qwen': 'canary-qwen-2.5b-q8_0',
    'higgs-stt': 'higgs-stt-q4_k',
    'ark-asr': 'ark-asr-3b-q4_k',
    // gemma4-e4b, reazonspeech, parakeet-ctc-1.1b-ja share backends
    // (gemma4-e2b, parakeet) that already have entries above — not
    // listed here to keep the one-default-per-backend invariant.
    // Users discover these variants via BackendRepo HF probe.
    'lfm2-audio': 'lfm2-audio-1.5b-q5_k',
    'mini-omni2': 'mini-omni2-q4_k',
    // TTS
    'dots-tts': 'dots-tts-soar-f16',
    'kokoro': 'kokoro-82m-q8_0',
    'vibevoice-tts': 'vibevoice-realtime-0.5b-tts-f16',
    'qwen3-tts': 'qwen3-tts-12hz-0.6b-base-q8_0',
    'moss-tts': 'moss-tts-v1.5-q4_k',
    'omnivoice': 'omnivoice-f16',
    'irodori-tts': 'irodori-tts-500m-v3-q4_k',
    'voxtral-tts': 'voxtral-4b-tts-q4_k',
    'orpheus': 'orpheus-3b-base-q8_0',
    'voxcpm2-tts': 'voxcpm2-q4_k',
    'piper': 'piper-en-cori',
    'cosyvoice3-tts': 'cosyvoice3-llm-q4_k',
    'cosyvoice3-tts-rl': 'cosyvoice3-llm-rl-q4_k',
    'chatterbox': 'chatterbox-en-q8_0',
    'indextts': 'indextts-q8_0',
    'f5-tts': 'f5-tts-v1-base-f16',
    'bananamind-tts': 'bananamind-tts-en-q8_0',
    'bark': 'bark-small-q8_0',
    'csm': 'csm-1b-q4_k',
    'dia': 'dia-1.6b-f16',
    'fastpitch': 'fastpitch-en-q8_0',
    'melotts': 'melotts-en-v2-f16',
    'outetts': 'outetts-0.3-1b-q8_0',
    'parler-tts': 'parler-mini-v1.1-q8_0',
    'pocket-tts': 'pocket-tts-english-f16',
    'speecht5': 'speecht5-tts-f16',
    'kugelaudio': 'kugelaudio-0-open-f16',
    'zonos': 'zonos-v0.1-transformer-q4_k',
    // Text translation (Translate screen entry points)
    'm2m100': 'm2m100-418m-q4_k',
    // Chat LLM (Tidy / Summarize)
    'chat': 'smollm2-360m-instruct-q4_k_m',
  };

  /// Multilingual TTS voicepack catalog. Generated from the HF repos
  /// `cstr/vibevoice-realtime-0.5b-GGUF` (26 voices: en/de/fr/it/jp/kr/
  /// nl/pl/pt/sp/in) and `cstr/kokoro-voices-GGUF` (7 voices: en/de/es/
  /// fr) as of 2026-05. Tagged `kind: voice` so the Voices filter chip
  /// in Model Management surfaces them grouped from the main TTS
  /// models. Every entry carries its language twice: in `languages:`
  /// (what the Model Manager's dropdown filters on) and as a
  /// `[lang=xx]` tag in the description (the fallback the Voices chip
  /// row reads). The two must always agree — see issue #35, where the
  /// entries had only the tag and the dropdown had nothing to match.
  ///
  /// Computed lazily (not `const`) because the entries are constructed
  /// from a list comprehension. Merged into `lookupDefinition` and
  /// `getWhisperCppModels` alongside the static catalogs above.
  ///
  /// The middle column is an **ISO 639-1** code, not the code the repo
  /// happens to use in the filename. Upstream names four of them the
  /// non-standard way (`jp-`, `kr-`, `sp-`, and `in-` for Indian
  /// English); mapping them here is what keeps the voice chips and the
  /// language dropdown talking about the same alphabet — see
  /// [normalizeLanguageCode] and issue #35.
  static final Map<String, ModelDefinition> ttsVoicepacks = () {
    const vibevoiceVoices = <List<String>>[
      // [filename-leaf, ISO 639-1 language code, display name]
      ['de-Spk0_man', 'de', 'German (Spk0, m)'],
      ['de-Spk1_woman', 'de', 'German (Spk1, w)'],
      ['en-Carter_man', 'en', 'English — Carter (m)'],
      ['en-Davis_man', 'en', 'English — Davis (m)'],
      ['en-Emma_woman', 'en', 'English — Emma (w)'],
      ['en-Frank_man', 'en', 'English — Frank (m)'],
      ['en-Grace_woman', 'en', 'English — Grace (w)'],
      ['en-Mike_man', 'en', 'English — Mike (m)'],
      ['fr-Spk0_man', 'fr', 'French (Spk0, m)'],
      ['fr-Spk1_woman', 'fr', 'French (Spk1, w)'],
      // `in-` is the repo's tag for Indian English, not Indonesian.
      ['in-Samuel_man', 'en', 'Indian English — Samuel (m)'],
      ['it-Spk0_woman', 'it', 'Italian (Spk0, w)'],
      ['it-Spk1_man', 'it', 'Italian (Spk1, m)'],
      ['jp-Spk0_man', 'ja', 'Japanese (Spk0, m)'],
      ['jp-Spk1_woman', 'ja', 'Japanese (Spk1, w)'],
      ['kr-Spk0_woman', 'ko', 'Korean (Spk0, w)'],
      ['kr-Spk1_man', 'ko', 'Korean (Spk1, m)'],
      ['nl-Spk0_man', 'nl', 'Dutch (Spk0, m)'],
      ['nl-Spk1_woman', 'nl', 'Dutch (Spk1, w)'],
      ['pl-Spk0_man', 'pl', 'Polish (Spk0, m)'],
      ['pl-Spk1_woman', 'pl', 'Polish (Spk1, w)'],
      ['pt-Spk0_woman', 'pt', 'Portuguese (Spk0, w)'],
      ['pt-Spk1_man', 'pt', 'Portuguese (Spk1, m)'],
      ['sp-Spk0_woman', 'es', 'Spanish (Spk0, w)'],
      ['sp-Spk1_man', 'es', 'Spanish (Spk1, m)'],
    ];
    const kokoroVoices = <List<String>>[
      // [filename-leaf, language code, display name]
      ['df_eva', 'de', 'German — Eva (w)'],
      ['df_victoria', 'de', 'German — Victoria (w)'],
      ['dm_bernd', 'de', 'German — Bernd (m)'],
      ['dm_martin', 'de', 'German — Martin (m)'],
      ['ef_dora', 'es', 'Spanish — Dora (w)'],
      ['ff_siwis', 'fr', 'French — Siwis (w)'],
    ];
    final out = <String, ModelDefinition>{};
    for (final v in vibevoiceVoices) {
      final leaf = v[0];
      final lang = v[1];
      final display = v[2];
      out['vibevoice-voice-$leaf'] = ModelDefinition(
        name: 'vibevoice-voice-$leaf',
        displayName: 'VibeVoice voice — $display',
        fileName: 'vibevoice-voice-$leaf.gguf',
        url:
            'https://huggingface.co/cstr/vibevoice-realtime-0.5b-GGUF/resolve/main/vibevoice-voice-$leaf.gguf',
        sizeBytes: 5 * 1024 * 1024,
        checksum: '',
        description: 'VibeVoice voicepack — $display [lang=$lang]',
        quantization: 'f16',
        backend: 'vibevoice-tts',
        kind: ModelKind.voice,
        languages: <String>[lang],
      );
    }
    for (final v in kokoroVoices) {
      final leaf = v[0];
      final lang = v[1];
      final display = v[2];
      out['kokoro-voice-$leaf'] = ModelDefinition(
        name: 'kokoro-voice-$leaf',
        displayName: 'Kokoro voice — $display',
        fileName: 'kokoro-voice-$leaf.gguf',
        url:
            'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main/kokoro-voice-$leaf.gguf',
        sizeBytes: 1 * 1024 * 1024,
        checksum: '',
        description: 'Kokoro voicepack — $display [lang=$lang]',
        quantization: 'f16',
        backend: 'kokoro',
        kind: ModelKind.voice,
        languages: <String>[lang],
      );
    }
    return out;
  }();

  /// HuggingFace repos we probe dynamically to discover every available
  /// quantisation (q4_0, q4_k, q5_0, q5_k, q8_0, f16, …). The static
  /// catalogs above are the offline default; on first open of the model
  /// manager the app calls `refreshAvailableQuants()` and merges new
  /// entries discovered via the HF API.
  static const Map<String, BackendRepo> backendRepos = {
    'whisper': BackendRepo(
      backend: 'whisper',
      // Public, hosted by ggerganov — 33+ quant variants
      // (tiny / base / small / medium / large in f16, q5_0, q5_1,
      // q8_0 + .en monolingual variants). The historical
      // cstr/whisper-ggml-quants repo was gated and silently
      // returned 401 from the HF API, leaving the model picker
      // with only the hardcoded q5_0 entries.
      repoId: 'ggerganov/whisper.cpp',
      baseName: 'ggml-',
      displayPrefix: 'Whisper',
      description: 'Whisper (quantised GGML, 99 languages)',
      extension: '.bin',
      defaultLanguages: langsWhisper99,
    ),
    // GigaAM v3 — 16-layer rotary Conformer (220M) + CTC or RNN-T head,
    // the strongest open Russian ASR. Four revisions: the `e2e-*` pair
    // emits punctuation + casing + ITN from its SentencePiece vocab, the
    // bare `ctc`/`rnnt` pair emits lowercase Cyrillic with none of that.
    // Prefer e2e — CrispASR suppresses auto-punctuation for the charwise
    // revisions anyway (the auto-enabled FireRedPunc is a CN/EN model and
    // injects full-width CJK punctuation into Russian).
    'gigaam': BackendRepo(
      backend: 'gigaam',
      repoId: 'cstr/gigaam-v3-GGUF',
      baseName: 'gigaam-v3',
      displayPrefix: 'GigaAM v3',
      description:
          'Russian ASR (Conformer 220M) — 8.4% avg WER, punctuation + ITN',
      defaultLanguages: langsRuEn,
    ),
    'parakeet': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-tdt-0.6b-v3-GGUF',
      baseName: 'parakeet-tdt-0.6b-v3',
      displayPrefix: 'Parakeet TDT 0.6B v3',
      description: 'Fast multilingual ASR (NVIDIA Parakeet, 25 EU langs)',
      defaultLanguages: langsEU25,
    ),
    'canary': BackendRepo(
      backend: 'canary',
      repoId: 'cstr/canary-1b-v2-GGUF',
      baseName: 'canary-1b-v2',
      displayPrefix: 'Canary 1B v2',
      description:
          'NVIDIA Canary — multilingual speech translation (25 EU langs)',
      defaultLanguages: langsEU25,
    ),
    'cohere': BackendRepo(
      backend: 'cohere',
      repoId: 'cstr/cohere-transcribe-03-2026-GGUF',
      baseName: 'cohere-transcribe',
      displayPrefix: 'Cohere Transcribe',
      description: 'Cohere high-accuracy ASR',
      defaultLanguages: langsCohere13,
    ),
    'voxtral': BackendRepo(
      backend: 'voxtral',
      repoId: 'cstr/voxtral-mini-3b-2507-GGUF',
      baseName: 'voxtral-mini-3b-2507',
      displayPrefix: 'Voxtral Mini 3B 2507',
      description: 'Mistral Voxtral — speech translation + ASR (9 langs)',
      defaultLanguages: langsVoxtral9,
    ),
    'voxtral4b': BackendRepo(
      backend: 'voxtral4b',
      repoId: 'cstr/voxtral-mini-4b-realtime-GGUF',
      baseName: 'voxtral-mini-4b-realtime',
      displayPrefix: 'Voxtral Mini 4B realtime',
      description:
          'Voxtral realtime variant (en/es/fr/de/it/pt/ru/zh/ja/ko/ar/hi/nl)',
      defaultLanguages: <String>[
        'en',
        'es',
        'fr',
        'de',
        'it',
        'pt',
        'ru',
        'zh',
        'ja',
        'ko',
        'ar',
        'hi',
        'nl',
      ],
    ),
    'qwen3': BackendRepo(
      backend: 'qwen3',
      repoId: 'cstr/qwen3-asr-0.6b-GGUF',
      baseName: 'qwen3-asr-0.6b',
      displayPrefix: 'Qwen3-ASR 0.6B',
      description: 'Multilingual (29 langs incl. Chinese dialects)',
      defaultLanguages: langsQwen3Asr29,
    ),
    'granite': BackendRepo(
      backend: 'granite',
      repoId: 'cstr/granite-speech-4.0-1b-GGUF',
      baseName: 'granite-speech-4.0-1b',
      displayPrefix: 'Granite 4.0 1B Speech',
      description: 'IBM Granite speech (instruction-tuned)',
      defaultLanguages: langsGranite6,
    ),
    'fastconformer-ctc': BackendRepo(
      backend: 'fastconformer-ctc',
      repoId: 'cstr/stt-en-fastconformer-ctc-large-GGUF',
      baseName: 'stt-en-fastconformer-ctc-large',
      displayPrefix: 'FastConformer CTC (en)',
      description: 'Low-latency CTC ASR (English)',
      defaultLanguages: langsEn,
    ),
    'wav2vec2': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-english-GGUF',
      baseName: 'wav2vec2-xlsr-en',
      displayPrefix: 'Wav2Vec2 base (en)',
      description: 'Self-supervised (facebook/wav2vec2)',
      defaultLanguages: langsEn,
    ),
    // Data2Vec-Audio (facebook) — wav2vec2-style CNN + transformer + CTC.
    // GGUFs carry arch="wav2vec2" and load through the same wav2vec2
    // backend (the C-side open accepts "wav2vec2"/"hubert"/"data2vec"),
    // so it's a separate HF repo on the shared backend rather than a new
    // engine arm. English (LibriSpeech 960h).
    'data2vec-audio': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/data2vec-audio-960h-GGUF',
      baseName: 'data2vec-audio-base-960h',
      displayPrefix: 'Data2Vec-Audio base 960h (en)',
      description: 'Data2Vec-Audio CTC ASR (facebook, en)',
      defaultLanguages: langsEn,
    ),
    // OmniASR — multilingual LLM-based ASR. The CTC variant is omitted on
    // purpose: it has no language conditioning and degrades to gibberish on
    // simple inputs (jfk.wav). The LLM variant accepts a `lang=` hint.
    'omniasr-llm': BackendRepo(
      backend: 'omniasr-llm',
      repoId: 'cstr/omniasr-llm-300m-v2-GGUF',
      baseName: 'omniasr-llm-300m-v2',
      displayPrefix: 'OmniASR LLM 300M v2',
      description: 'Multilingual LLM-based ASR (300M)',
      defaultLanguages: langsAll,
    ),
    'firered-asr': BackendRepo(
      backend: 'firered-asr',
      repoId: 'cstr/firered-asr2-aed-GGUF',
      baseName: 'firered-asr2-aed',
      displayPrefix: 'FireRed ASR2 AED',
      description: 'AED-style Mandarin/English ASR',
      defaultLanguages: langsEnZh,
    ),
    'kyutai-stt': BackendRepo(
      backend: 'kyutai-stt',
      repoId: 'cstr/kyutai-stt-1b-GGUF',
      baseName: 'kyutai-stt-1b',
      displayPrefix: 'Kyutai STT 1B',
      description: 'Kyutai streaming-style STT (en/fr)',
      defaultLanguages: <String>['en', 'fr'],
    ),
    'glm-asr': BackendRepo(
      backend: 'glm-asr',
      repoId: 'cstr/glm-asr-nano-GGUF',
      baseName: 'glm-asr-nano',
      displayPrefix: 'GLM-ASR Nano',
      description: 'GLM-family multilingual ASR',
      defaultLanguages: langsAll,
    ),
    'vibevoice': BackendRepo(
      backend: 'vibevoice',
      repoId: 'cstr/vibevoice-asr-GGUF',
      baseName: 'vibevoice-asr',
      displayPrefix: 'VibeVoice ASR',
      description: 'Multilingual large ASR (48 langs, ~4.5 GB)',
      defaultLanguages: langsVibevoice48,
    ),
    // VibeVoice TTS — shares its HF repo with 20+ voicepack files,
    // hence `voicepackBaseName`. Main quants: q4_k / q8_0 /
    // tts-f16 / tts-f32-tokenizer (the latter two have the `-tts-`
    // tag indicating the bundled Tekken tokenizer — required for
    // chatterbox-style synth).
    'vibevoice-tts': BackendRepo(
      backend: 'vibevoice-tts',
      repoId: 'cstr/vibevoice-realtime-0.5b-GGUF',
      baseName: 'vibevoice-realtime-0.5b',
      displayPrefix: 'VibeVoice Realtime 0.5B',
      description: 'VibeVoice realtime TTS (10 langs)',
      kind: ModelKind.tts,
      voicepackBaseName: 'vibevoice-voice',
      defaultCompanions: ['vibevoice-voice-en-Emma_woman'],
      defaultLanguages: langsVibevoiceTts10,
    ),
    'mimo-asr': BackendRepo(
      backend: 'mimo-asr',
      repoId: 'cstr/mimo-asr-GGUF',
      baseName: 'mimo-asr',
      displayPrefix: 'MiMo ASR',
      description: 'XiaomiMiMo MiMo-Audio ASR',
      defaultCompanions: ['mimo-tokenizer-q4_k'],
      defaultLanguages: langsEnZh,
    ),
    // Newer additions wired up so refreshAvailableQuants() picks up
    // every f16 / q4_k / q5_0 / q8_0 / iq2_xs sibling in each repo
    // without a code change per quant. The "Refresh from HuggingFace"
    // button on the Models screen walks every entry here.
    'parakeet-tdt-0.6b-v2': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-tdt-0.6b-v2-GGUF',
      baseName: 'parakeet-tdt-0.6b-v2',
      displayPrefix: 'Parakeet TDT 0.6B v2',
      description: 'Parakeet TDT 0.6B v2 (earlier vocab)',
      defaultLanguages: langsEn,
    ),
    'parakeet-tdt-1.1b': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-tdt-1.1b-GGUF',
      baseName: 'parakeet-tdt-1.1b',
      displayPrefix: 'Parakeet TDT 1.1B',
      description: 'Larger Parakeet TDT, 42-layer encoder',
      defaultLanguages: langsEn,
    ),
    'qwen3-1.7b': BackendRepo(
      backend: 'qwen3',
      repoId: 'cstr/qwen3-asr-1.7b-GGUF',
      baseName: 'qwen3-asr-1.7b',
      displayPrefix: 'Qwen3-ASR 1.7B',
      description: 'Qwen3-ASR 1.7B (29 langs)',
      defaultLanguages: langsQwen3Asr29,
    ),
    'qwen3-ja-anime': BackendRepo(
      backend: 'qwen3',
      repoId: 'cstr/qwen3-asr-1.7b-ja-anime-GGUF',
      baseName: 'qwen3-asr-1.7b-ja-anime',
      displayPrefix: 'Qwen3-ASR 1.7B JA Anime',
      description: 'Japanese anime/galgame speech fine-tune',
      defaultLanguages: ['ja'],
    ),
    'mega-asr': BackendRepo(
      backend: 'mega-asr',
      repoId: 'cstr/mega-asr-GGUF',
      baseName: 'mega-asr-1.7b',
      displayPrefix: 'Mega-ASR 1.7B',
      description: 'Qwen3-ASR 1.7B + robustness LoRA (29 langs)',
      defaultLanguages: langsQwen3Asr29,
    ),
    'omniasr-llm-1b': BackendRepo(
      backend: 'omniasr-llm',
      repoId: 'cstr/omniasr-llm-1b-GGUF',
      baseName: 'omniasr-llm-1b',
      displayPrefix: 'OmniASR LLM 1B',
      description: 'OmniASR LLM 1B (multilingual)',
      defaultLanguages: langsAll,
    ),
    'funasr': BackendRepo(
      backend: 'funasr',
      repoId: 'cstr/funasr-nano-GGUF',
      baseName: 'funasr-nano-2512',
      displayPrefix: 'FunASR Nano 2512',
      description: 'FunASR Nano (zh/en/ja/ko/yue)',
      defaultLanguages: langsSensevoice,
    ),
    'funasr-mlt': BackendRepo(
      backend: 'funasr',
      repoId: 'cstr/funasr-mlt-nano-GGUF',
      baseName: 'funasr-mlt-nano-2512',
      displayPrefix: 'FunASR MLT Nano 2512',
      description: 'FunASR multilingual Nano (30 langs)',
      defaultLanguages: langsFunasrMlt31,
    ),
    'paraformer': BackendRepo(
      backend: 'paraformer',
      repoId: 'cstr/paraformer-zh-GGUF',
      baseName: 'paraformer-zh',
      displayPrefix: 'Paraformer ZH',
      description: 'Paraformer Mandarin + English NAR-ASR',
      defaultLanguages: langsEnZh,
    ),
    'sensevoice': BackendRepo(
      backend: 'sensevoice',
      repoId: 'cstr/sensevoice-small-GGUF',
      baseName: 'sensevoice-small',
      displayPrefix: 'SenseVoice Small',
      description: 'SenseVoice Small (zh/en/ja/ko/yue) with built-in LID',
      defaultLanguages: langsSensevoice,
    ),
    // Distil-Whisper Large v3 — .bin (not .gguf), uses the whisper
    // runtime. cstr/distil-large-v3-GGUF ships f16/q5_0/q4_k/q8_0/etc.
    // Distil-Whisper Large v3 is English-only — the upstream
    // distil-whisper/distil-large-v3 was trained on English data
    // only despite being derived from multilingual large-v3.
    'distil-large-v3': BackendRepo(
      backend: 'whisper',
      repoId: 'cstr/distil-large-v3-GGUF',
      baseName: 'distil-large-v3',
      displayPrefix: 'Distil-Whisper Large v3',
      description: 'Distilled Whisper Large v3 (English) — ~6× faster',
      extension: '.bin',
      defaultLanguages: langsEn,
    ),
    // Kokoro — GPL-free app bundles have built-in G2P for EN/DE/FR/ES.
    'kokoro': BackendRepo(
      backend: 'kokoro',
      repoId: 'cstr/kokoro-82m-GGUF',
      baseName: 'kokoro-82m',
      displayPrefix: 'Kokoro 82M TTS',
      description: 'Kokoro TTS, EN/DE/FR/ES in GPL-free builds (~100 MB)',
      kind: ModelKind.tts,
      defaultCompanions: ['kokoro-voice-af_heart'],
      defaultLanguages: <String>['en', 'de', 'fr', 'es'],
    ),
    // Kokoro voicepacks — separate HF repo, voicepack-only. Empty
    // baseName means the main-quant probe skips this repo; the
    // voicepack probe runs against the `kokoro-voice-*` files.
    'kokoro-voices': BackendRepo(
      backend: 'kokoro',
      repoId: 'cstr/kokoro-voices-GGUF',
      baseName: '',
      displayPrefix: 'Kokoro 82M TTS',
      description: 'Kokoro voicepacks (de/en/es/fr)',
      kind: ModelKind.voice,
      voicepackBaseName: 'kokoro-voice',
      defaultLanguages: <String>['de', 'en', 'es', 'fr'],
    ),
    // Orpheus — Llama-3.2-3B + SNAC codec TTS (needs codec via setCodecPath).
    'orpheus': BackendRepo(
      backend: 'orpheus',
      repoId: 'cstr/orpheus-3b-base-GGUF',
      baseName: 'orpheus-3b-base',
      displayPrefix: 'Orpheus 3B TTS',
      description: 'Orpheus Llama-3.2-3B TTS (~3.5 GB)',
      kind: ModelKind.tts,
      defaultCompanions: ['snac-24khz'],
      defaultLanguages: langsEn,
    ),
    // Moonshine — three sibling repos (tiny / base / streaming-tiny).
    // moonshine_init reads tokenizer.bin from the model's directory at
    // session-open time, so the tokenizer companion isn't optional — see
    // the explicit moonshine-tokenizer ModelDefinition in
    // [crispasrBackendModels].
    'moonshine-tiny': BackendRepo(
      backend: 'moonshine',
      repoId: 'cstr/moonshine-tiny-GGUF',
      baseName: 'moonshine-tiny',
      displayPrefix: 'Moonshine tiny',
      description: 'Moonshine tiny ASR (English, lightweight)',
      defaultCompanions: ['moonshine-tokenizer'],
      defaultLanguages: langsEn,
    ),
    'moonshine-base': BackendRepo(
      backend: 'moonshine',
      repoId: 'cstr/moonshine-base-GGUF',
      baseName: 'moonshine-base',
      displayPrefix: 'Moonshine base',
      description: 'Moonshine base ASR (English, lightweight)',
      defaultCompanions: ['moonshine-tokenizer'],
      defaultLanguages: langsEn,
    ),
    'moonshine-streaming-tiny': BackendRepo(
      backend: 'moonshine-streaming',
      repoId: 'cstr/moonshine-streaming-tiny-GGUF',
      baseName: 'moonshine-streaming-tiny',
      displayPrefix: 'Moonshine streaming tiny',
      description: 'Moonshine streaming ASR for live mic input',
      defaultCompanions: ['moonshine-tokenizer'],
      defaultLanguages: langsEn,
    ),
    // Chatterbox turbo + Kartoffelbox: same `chatterbox` backend, but the
    // turbo + German variants live in separate repos so refresh-from-HF
    // doesn't probe them otherwise. (The base chatterbox + chatterbox-s3gen
    // BackendRepos already exist further down — just adding the missing
    // siblings here.)
    'chatterbox-turbo-t3': BackendRepo(
      backend: 'chatterbox',
      repoId: 'cstr/chatterbox-turbo-GGUF',
      baseName: 'chatterbox-turbo-t3',
      displayPrefix: 'Chatterbox turbo T3',
      description: 'Chatterbox turbo TTS T3 — pair with chatterbox-turbo-s3gen',
      kind: ModelKind.tts,
      defaultCompanions: ['chatterbox-s3gen-q8_0'],
      defaultLanguages: langsEn,
    ),
    'chatterbox-turbo-s3gen': BackendRepo(
      backend: 'chatterbox',
      repoId: 'cstr/chatterbox-turbo-GGUF',
      baseName: 'chatterbox-turbo-s3gen',
      displayPrefix: 'Chatterbox turbo S3Gen',
      description: 'Chatterbox turbo S3Gen vocoder (English)',
      kind: ModelKind.codec,
      defaultLanguages: langsEn,
    ),
    // Kartoffelbox — German Chatterbox finetune. Only T3 weights ship on
    // HF; pair with the English Chatterbox S3Gen at synth time.
    'kartoffelbox': BackendRepo(
      backend: 'chatterbox',
      repoId: 'cstr/kartoffelbox-turbo-GGUF',
      baseName: 'kartoffelbox-turbo-t3',
      displayPrefix: 'Kartoffelbox turbo T3 (DE)',
      description: 'Kartoffelbox-turbo German T3 — pair with chatterbox-s3gen',
      kind: ModelKind.tts,
      defaultCompanions: ['chatterbox-s3gen-q8_0'],
      defaultLanguages: <String>['de', 'en'],
    ),
    // Kartoffel-Orpheus — German Orpheus finetunes (natural / synthetic
    // voice families) sharing the same SNAC codec as the English base.
    'kartoffel-orpheus-natural': BackendRepo(
      backend: 'orpheus',
      repoId: 'cstr/kartoffel-orpheus-3b-german-natural-GGUF',
      baseName: 'kartoffel-orpheus-3b-german-natural',
      displayPrefix: 'Kartoffel-Orpheus 3B natural (DE)',
      description: 'Orpheus 3B German finetune (natural voices)',
      kind: ModelKind.tts,
      defaultCompanions: ['snac-24khz'],
      defaultLanguages: langsDe,
    ),
    'kartoffel-orpheus-synthetic': BackendRepo(
      backend: 'orpheus',
      repoId: 'cstr/kartoffel-orpheus-3b-german-synthetic-GGUF',
      baseName: 'kartoffel-orpheus-3b-german-synthetic',
      displayPrefix: 'Kartoffel-Orpheus 3B synthetic (DE)',
      description: 'Orpheus 3B German finetune (synthetic voices)',
      kind: ModelKind.tts,
      defaultCompanions: ['snac-24khz'],
      defaultLanguages: langsDe,
    ),
    // Qwen3-TTS — 12 Hz codec talker + shared tokenizer. Multiple base /
    // customvoice / voicedesign variants ship under separate HF repos but
    // all share the qwen3-tts-tokenizer-12hz codec.
    'qwen3-tts-0.6b-base': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/qwen3-tts-0.6b-base-GGUF',
      baseName: 'qwen3-tts-12hz-0.6b-base',
      displayPrefix: 'Qwen3-TTS 0.6B base',
      description:
          'Qwen3-TTS base talker — needs qwen3-tts-tokenizer-12hz codec',
      kind: ModelKind.tts,
      defaultCompanions: ['qwen3-tts-tokenizer-12hz'],
      defaultLanguages: langsQwen3Tts10,
    ),
    'qwen3-tts-0.6b-customvoice': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/qwen3-tts-0.6b-customvoice-GGUF',
      baseName: 'qwen3-tts-12hz-0.6b-customvoice',
      displayPrefix: 'Qwen3-TTS 0.6B custom-voice',
      description:
          'Qwen3-TTS 0.6B with ICL voice cloning (9 langs, no Russian)',
      kind: ModelKind.tts,
      defaultCompanions: ['qwen3-tts-tokenizer-12hz'],
      defaultLanguages: langsQwen3TtsCustom9,
    ),
    'qwen3-tts-1.7b-customvoice': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/qwen3-tts-1.7b-customvoice-GGUF',
      baseName: 'qwen3-tts-12hz-1.7b-customvoice',
      displayPrefix: 'Qwen3-TTS 1.7B custom-voice',
      description:
          'Qwen3-TTS 1.7B with ICL voice cloning (9 langs, no Russian)',
      kind: ModelKind.tts,
      defaultCompanions: ['qwen3-tts-tokenizer-12hz'],
      defaultLanguages: langsQwen3TtsCustom9,
    ),
    'qwen3-tts-1.7b-voicedesign': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/qwen3-tts-1.7b-voicedesign-GGUF',
      baseName: 'qwen3-tts-12hz-1.7b-voicedesign',
      displayPrefix: 'Qwen3-TTS 1.7B voice-design',
      description: 'Qwen3-TTS 1.7B — natural-language voice description',
      kind: ModelKind.tts,
      defaultCompanions: ['qwen3-tts-tokenizer-12hz'],
      defaultLanguages: langsQwen3Tts10,
    ),
    // The qwen3-tts codec lives in its own repo — registered separately
    // so refresh picks up new tokenizer quants when they're published.
    'qwen3-tts-tokenizer-12hz': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/qwen3-tts-tokenizer-12hz-GGUF',
      baseName: 'qwen3-tts-tokenizer-12hz',
      displayPrefix: 'Qwen3-TTS codec',
      description:
          'Qwen3-TTS 12 Hz audio codec — companion to every Qwen3-TTS talker',
      kind: ModelKind.codec,
      defaultLanguages: langsQwen3Tts10,
    ),
    // FireRedPunc — POST-PROCESSOR (not an ASR backend). Catalogued so
    // users can fetch it via Model Management; consumed by `PuncService`.
    'firered-punc': BackendRepo(
      backend: 'firered-punc',
      repoId: 'cstr/fireredpunc-GGUF',
      baseName: 'fireredpunc',
      displayPrefix: 'FireRedPunc (post-processor)',
      description: 'Punctuation restoration for CTC ASR output',
      kind: ModelKind.punc,
      defaultLanguages: langsEnZh,
    ),
    // ----------------- CrispASR 0.6.x parity additions -----------------
    // Gemma4-E2B — Conformer + Gemma-4 LLM, 140+ languages.
    'gemma4-e2b': BackendRepo(
      backend: 'gemma4-e2b',
      repoId: 'cstr/gemma4-e2b-it-GGUF',
      baseName: 'gemma4-e2b-it',
      displayPrefix: 'Gemma4-E2B-it',
      description: 'Multilingual ASR (140+ languages, instruction-tuned)',
      defaultLanguages: langsAll,
    ),
    'moss-audio': BackendRepo(
      backend: 'moss-audio',
      repoId: 'cstr/MOSS-Audio-4B-Instruct-GGUF',
      baseName: 'moss-audio-4b-instruct',
      displayPrefix: 'MOSS-Audio 4B',
      description:
          'ASR + audio QA + scene description (Whisper enc + Qwen3 LLM)',
      defaultLanguages: langsAll,
    ),
    // LFM2-Audio — LiquidAI hybrid conv+attention (ASR + TTS + S2S).
    'lfm2-audio': BackendRepo(
      backend: 'lfm2-audio',
      repoId: 'cstr/lfm2-audio-1.5b-GGUF',
      baseName: 'lfm2-audio-1.5b',
      displayPrefix: 'LFM2-Audio 1.5B',
      description: 'LiquidAI LFM2-Audio 1.5B — ASR + TTS + S2S (English)',
      defaultLanguages: langsEn,
    ),
    'lfm2-audio-jp': BackendRepo(
      backend: 'lfm2-audio',
      repoId: 'cstr/lfm2-audio-1.5b-jp-GGUF',
      baseName: 'lfm2-audio-1.5b-jp',
      displayPrefix: 'LFM2-Audio 1.5B JP',
      description: 'LiquidAI LFM2-Audio 1.5B — ASR + TTS + S2S (Japanese)',
      defaultLanguages: langsJa,
    ),
    // Mini-Omni2 — Whisper-small + Qwen2-0.5B (ASR + TTS + S2S).
    // Needs SNAC 24 kHz codec companion for TTS/S2S.
    'mini-omni2': BackendRepo(
      backend: 'mini-omni2',
      repoId: 'cstr/mini-omni2-GGUF',
      baseName: 'mini-omni2',
      displayPrefix: 'Mini-Omni2',
      description: 'Whisper + Qwen2 0.5B multimodal (ASR + TTS + S2S)',
      defaultCompanions: ['snac-24khz'],
      defaultLanguages: langsEn,
    ),
    // Parakeet-RNNT 0.6B/1.1B BackendRepo entries are in the baked
    // catalog section below (generated by scripts/bake_models_catalog.dart).
    //
    // OmniASR LLM unlimited streaming variant.
    'omniasr-llm-unlimited': BackendRepo(
      backend: 'omniasr-llm-unlimited',
      repoId: 'cstr/omniasr-llm-unlimited-300m-v2-GGUF',
      baseName: 'omniasr-llm-unlimited-300m-v2',
      displayPrefix: 'OmniASR LLM unlimited 300M v2',
      description: 'Streaming OmniASR (unlimited audio)',
      defaultLanguages: langsAll,
    ),
    // Granite Speech 4.1 family.
    'granite-4.1': BackendRepo(
      backend: 'granite-4.1',
      repoId: 'cstr/granite-speech-4.1-2b-GGUF',
      baseName: 'granite-speech-4.1-2b',
      displayPrefix: 'Granite Speech 4.1 2B',
      description: 'IBM Granite Speech 4.1 (2B)',
      defaultLanguages: langsGranite6,
    ),
    'granite-4.1-plus': BackendRepo(
      backend: 'granite-4.1-plus',
      repoId: 'cstr/granite-speech-4.1-2b-plus-GGUF',
      baseName: 'granite-speech-4.1-2b-plus',
      displayPrefix: 'Granite Speech 4.1 2B+',
      description: 'Granite Speech 4.1+ (en/fr/de/es/pt)',
      defaultLanguages: langsGranite5,
    ),
    'granite-4.1-nar': BackendRepo(
      backend: 'granite-4.1-nar',
      repoId: 'cstr/granite-speech-4.1-2b-nar-GGUF',
      baseName: 'granite-speech-4.1-2b-nar',
      displayPrefix: 'Granite Speech 4.1 2B NAR',
      description: 'Granite Speech 4.1 NAR (en/fr/de/es/pt)',
      defaultLanguages: langsGranite5,
    ),
    // ----- CrispASR 0.8.x parity (PLAN §11.1) -----
    // MOSS-Transcribe — Qwen3-Omni enc + Qwen3-1.7B dec. ASR only.
    'moss-transcribe': BackendRepo(
      backend: 'moss-transcribe',
      repoId: 'cstr/MOSS-Transcribe-preview-2B-GGUF',
      baseName: 'moss-transcribe-preview-2b',
      displayPrefix: 'MOSS-Transcribe 2B',
      description: 'ASR with native punctuation + streaming (Qwen3-Omni)',
      defaultLanguages: langsAll,
    ),
    'moss-diarize': BackendRepo(
      backend: 'moss-diarize',
      repoId: 'cstr/MOSS-Transcribe-Diarize-GGUF',
      baseName: 'moss-transcribe-diarize-0.9b',
      displayPrefix: 'MOSS-Diarize 0.9B',
      description: 'Single-pass ASR + speaker diarization + timestamps',
      defaultLanguages: langsAll,
    ),
    'moss-tts': BackendRepo(
      backend: 'moss-tts',
      repoId: 'cstr/moss-tts-v1.5-GGUF',
      baseName: 'moss-tts-v1.5',
      displayPrefix: 'MOSS-TTS v1.5',
      description:
          'Voice-cloning TTS (Qwen3-8B) — needs the moss-tts-v1.5-codec',
      kind: ModelKind.tts,
      defaultCompanions: ['moss-tts-v1.5-codec'],
      defaultLanguages: langsAll,
    ),
    'nemotron': BackendRepo(
      backend: 'nemotron',
      repoId: 'cstr/nemotron-3.5-asr-streaming-0.6b-GGUF',
      baseName: 'nemotron-3.5-asr-streaming-0.6b',
      displayPrefix: 'Nemotron 3.5 ASR Streaming 0.6B',
      description: 'NVIDIA Nemotron 3.5 streaming ASR (0.6B)',
      defaultLanguages: langsAll,
    ),
    'canary-qwen': BackendRepo(
      backend: 'canary-qwen',
      repoId: 'cstr/canary-qwen-2.5b-GGUF',
      baseName: 'canary-qwen-2.5b',
      displayPrefix: 'Canary-Qwen 2.5B',
      description: 'NVIDIA Canary encoder + Qwen LLM decoder ASR',
      defaultLanguages: langsAll,
    ),
    'omnivoice': BackendRepo(
      backend: 'omnivoice',
      repoId: 'cstr/omnivoice-GGUF',
      baseName: 'omnivoice',
      displayPrefix: 'OmniVoice',
      description: 'OmniVoice — Qwen3-0.6B multi-codebook TTS (600+ langs)',
      kind: ModelKind.tts,
      defaultCompanions: ['omnivoice-tokenizer-f16'],
      defaultLanguages: langsAll,
    ),
    'irodori-tts': BackendRepo(
      backend: 'irodori-tts',
      repoId: 'cstr/irodori-tts-GGUF',
      baseName: 'irodori-tts-500m-v3',
      displayPrefix: 'Irodori-TTS 500M v3',
      description: 'Japanese TTS — needs the DAC-VAE codec companion',
      kind: ModelKind.tts,
      defaultCompanions: ['dacvae-ja-32dim-f16'],
      defaultLanguages: ['ja'],
    ),
    'voxtral-tts': BackendRepo(
      backend: 'voxtral-tts',
      repoId: 'cstr/voxtral-4b-tts-GGUF',
      baseName: 'voxtral-4b-tts',
      displayPrefix: 'Voxtral 4B TTS',
      description: 'Mistral Voxtral TTS — non-commercial (CC-BY-NC-4.0)',
      kind: ModelKind.tts,
      defaultLanguages: langsAll,
    ),
    // Higgs-Audio-v3-STT — Whisper-v3 enc + Qwen3-1.7B dec.
    'higgs-stt': BackendRepo(
      backend: 'higgs-stt',
      repoId: 'cstr/higgs-audio-v3-stt-GGUF',
      baseName: 'higgs-stt',
      displayPrefix: 'Higgs-STT',
      description:
          'Whisper-v3 + Qwen3-1.7B decoder, internal chunking + beam search',
      defaultLanguages: langsAll,
    ),
    // ARK-ASR-3B — Whisper-RoPE enc + Qwen2.5-3B dec, 19 languages.
    'ark-asr': BackendRepo(
      backend: 'ark-asr',
      repoId: 'cstr/ark-asr-3b-GGUF',
      baseName: 'ark-asr-3b',
      displayPrefix: 'ARK-ASR 3B',
      description: 'Whisper-RoPE + Qwen2.5-3B decoder, 19 languages',
      defaultLanguages: langsAll,
    ),
    // Gemma4-E4B — larger variant, shares gemma4-e2b backend.
    'gemma4-e4b': BackendRepo(
      backend: 'gemma4-e2b',
      repoId: 'cstr/gemma4-e4b-it-GGUF',
      baseName: 'gemma4-e4b-it',
      displayPrefix: 'Gemma4-E4B-it',
      description: 'Gemma4 4B decoder variant (140+ languages)',
      defaultLanguages: langsAll,
    ),
    // ReazonSpeech — Japanese RNNT, shares parakeet backend.
    'reazonspeech': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/reazonspeech-nemo-v2-GGUF',
      baseName: 'reazonspeech-nemo-v2',
      displayPrefix: 'ReazonSpeech NeMo v2',
      description: 'Japanese RNNT ASR (619M params)',
      defaultLanguages: langsJa,
    ),
    // Parakeet-CTC 1.1B Japanese — shares parakeet backend.
    'parakeet-ctc-1.1b-ja': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-ctc-1.1b-ja-GGUF',
      baseName: 'parakeet-ctc-1.1b-ja',
      displayPrefix: 'Parakeet-CTC 1.1B JA',
      description: 'Japanese FastConformer-CTC 1.1B',
      defaultLanguages: langsJa,
    ),
    // DoTs-TTS — 2B continuous AR + flow-matching + BigVGAN, voice cloning.
    'dots-tts': BackendRepo(
      backend: 'dots-tts',
      repoId: 'cstr/dots-tts-soar-GGUF',
      baseName: 'dots-tts-soar',
      displayPrefix: 'DoTs-TTS SOAR',
      description: 'Continuous AR + flow-matching TTS, 48 kHz, voice cloning',
      kind: ModelKind.tts,
      defaultCompanions: ['dots-tts-soar-vocoder-f16', 'dots-tts-soar-spk-f16'],
      defaultLanguages: langsEnZh,
    ),
    // Chatterbox — repo holds two file families: chatterbox-t3-*.gguf
    // (AR transformer) + chatterbox-s3gen-*.gguf (flow-matching
    // vocoder). The probe walks against the T3 baseName; the S3Gen
    // companion is registered separately so the model picker can offer
    // both.
    // Chatterbox base = ResembleAI/chatterbox — 23 languages per the
    // upstream card (ar/da/de/el/en/es/fi/fr/he/hi/it/ja/ko/ms/nl/no/
    // pl/pt/ru/sv/sw/tr/zh). Only chatterbox-turbo is English-only.
    'chatterbox': BackendRepo(
      backend: 'chatterbox',
      repoId: 'cstr/chatterbox-GGUF',
      baseName: 'chatterbox-t3',
      displayPrefix: 'Chatterbox T3',
      description: 'Chatterbox TTS T3 (AR transformer, 23 languages)',
      kind: ModelKind.tts,
      defaultCompanions: ['chatterbox-s3gen-q8_0'],
      defaultLanguages: langsChatterbox23,
    ),
    'chatterbox-s3gen': BackendRepo(
      backend: 'chatterbox',
      repoId: 'cstr/chatterbox-GGUF',
      baseName: 'chatterbox-s3gen',
      displayPrefix: 'Chatterbox S3Gen',
      description: 'Chatterbox S3Gen flow-matching vocoder',
      kind: ModelKind.codec,
      // The vocoder is the same physical model used across all
      // 23 Chatterbox languages — it's language-agnostic but the
      // language filter surfaces it under each of the families
      // that need it, same as the T3 talker.
      defaultLanguages: langsChatterbox23,
    ),
    // IndexTTS 1.5 — repo split into GPT-AR + BigVGAN vocoder files.
    'indextts': BackendRepo(
      backend: 'indextts',
      repoId: 'cstr/indextts-1.5-GGUF',
      baseName: 'indextts-gpt',
      displayPrefix: 'IndexTTS 1.5 GPT',
      description: 'IndexTTS 1.5 GPT (zh/en/ja/ko)',
      kind: ModelKind.tts,
      defaultCompanions: ['indextts-bigvgan'],
      defaultLanguages: langsSensevoice,
    ),
    // Fullstop-punc — multilingual punctuation post-processor.
    'fullstop-punc': BackendRepo(
      backend: 'fullstop-punc',
      repoId: 'cstr/fullstop-punc-multilang-GGUF',
      baseName: 'fullstop-punc-multilang',
      displayPrefix: 'Fullstop-punc multilang',
      description: 'Punctuation restoration (EN/DE/FR/IT)',
      kind: ModelKind.punc,
      defaultLanguages: langsFullstopPunc,
    ),
    // Pyannote v3 segmentation — ML diarisation.
    'pyannote': BackendRepo(
      backend: 'pyannote',
      repoId: 'cstr/pyannote-v3-segmentation-GGUF',
      baseName: 'pyannote-seg-3.0',
      displayPrefix: 'Pyannote v3 segmentation',
      description: 'Pyannote ML diarisation model',
      kind: ModelKind.diarize,
    ),
    // WeSpeaker ResNet34-LM — speaker embedder for FoxNose diarisation.
    'wespeaker': BackendRepo(
      backend: 'wespeaker',
      repoId: 'cstr/wespeaker-resnet34-lm-GGUF',
      baseName: 'wespeaker-resnet34-lm',
      displayPrefix: 'WeSpeaker ResNet34-LM',
      description: 'Speaker embedder for FoxNose (spectral) diarisation',
      kind: ModelKind.diarize,
    ),
    // M2M-100 — text-to-text translation, 100 languages, any-to-any.
    'm2m100': BackendRepo(
      backend: 'm2m100',
      repoId: 'cstr/m2m100-418m-GGUF',
      baseName: 'm2m100-418m',
      displayPrefix: 'M2M-100 418M',
      description: 'Text-to-text translation (100 languages, any-to-any)',
      kind: ModelKind.translate,
      defaultLanguages: langsAll,
    ),
    // WMT21 Dense — Facebook's News-competition winner. Two
    // directional checkpoints, each in its own HF repo. Both ship
    // under the same C-side backend `m2m100-wmt21`; CrispASR picks
    // the direction from the model's pre/suffix at session-open
    // time. Keep both BackendRepo rows so the live HF probe
    // surfaces quants from both repos — without the x-en entry
    // users see only en-x quants in the auto-discovered list.
    //
    // The canonical key `m2m100-wmt21` (en-x) is required by the
    // parity catalog test; the `-x-en` sibling key is iteration-
    // only (probe walks `.values`, so the key doesn't have to
    // match the backend id).
    'm2m100-wmt21': BackendRepo(
      backend: 'm2m100-wmt21',
      repoId: 'cstr/wmt21-dense-24-wide-en-x-GGUF',
      baseName: 'wmt21-dense-24-wide-en-x',
      displayPrefix: 'WMT21 Dense 24-wide en→X',
      description: 'WMT21 News winner — English to 7 target languages',
      kind: ModelKind.translate,
      defaultLanguages: langsWmt21_8,
    ),
    'm2m100-wmt21-x-en': BackendRepo(
      backend: 'm2m100-wmt21',
      repoId: 'cstr/wmt21-dense-24-wide-x-en-GGUF',
      baseName: 'wmt21-dense-24-wide-x-en',
      displayPrefix: 'WMT21 Dense 24-wide X→en',
      description: 'WMT21 News winner — 7 source languages to English',
      kind: ModelKind.translate,
      defaultLanguages: langsWmt21_8,
    ),
    // MADLAD-400 — Google's 419-language T5 translator.
    'madlad': BackendRepo(
      backend: 'madlad',
      repoId: 'cstr/madlad400-3b-mt-GGUF',
      baseName: 'madlad400-3b-mt',
      displayPrefix: 'MADLAD-400 3B-MT',
      description: 'T5 translator, 419 languages',
      kind: ModelKind.translate,
      defaultLanguages: langsAll,
    ),
    // MioTTS 0.6B — Qwen3 LLM + MioCodec-v2 FSQ codec (25 Hz, 44.1 kHz
    // out). Codec is baked into the model file; the repo's four
    // `*.emb.gguf` speaker embeddings are the preset voices.
    'miotts': BackendRepo(
      backend: 'miotts',
      repoId: 'cstr/miotts-0.6b-GGUF',
      baseName: 'miotts-0.6b',
      displayPrefix: 'MioTTS 0.6B',
      description: 'Qwen3 + MioCodec-v2 FSQ TTS — Japanese/English, 44.1 kHz',
      kind: ModelKind.tts,
      defaultLanguages: langsJaEn,
    ),
    // MOSS-TTS-Local v1.5 — Qwen3-4B backbone + 1-layer RQ-Transformer
    // emitting 12 RVQ codebooks/frame, decoded to 48 kHz by
    // MOSS-Audio-Tokenizer-v2. Needs the separate codec GGUF
    // (`--codec-model`), hence the companion wiring on each quant.
    'moss-tts-local': BackendRepo(
      backend: 'moss-tts-local',
      repoId: 'cstr/moss-tts-local-v1.5-GGUF',
      baseName: 'moss-tts-local-v1.5',
      displayPrefix: 'MOSS-TTS-Local v1.5',
      description: 'Qwen3-4B RQ-Transformer TTS — multilingual, 48 kHz',
      kind: ModelKind.tts,
      defaultLanguages: langsAll,
    ),
    // VoxCPM2 — single-file diffusion AR TTS. Zero-shot synthesis (no codec
    // companion); voxcpm2-ref.gguf in the same repo is a baked reference
    // voice for the not-yet-wired cloning path.
    'voxcpm2-tts': BackendRepo(
      backend: 'voxcpm2-tts',
      repoId: 'cstr/voxcpm2-GGUF',
      baseName: 'voxcpm2',
      displayPrefix: 'VoxCPM2',
      description: 'VoxCPM2 diffusion TTS (29 languages, zero-shot)',
      kind: ModelKind.tts,
      defaultLanguages: langsVoxcpm2_29,
    ),
    // F5-TTS — single self-contained GGUF (DiT + baked-in Vocos vocoder),
    // zero-shot voice clone from a reference WAV + transcript. No companion.
    // Audio-verified end-to-end in v0.6.49.
    'f5-tts': BackendRepo(
      backend: 'f5-tts',
      repoId: 'cstr/f5-tts-GGUF',
      baseName: 'f5-tts-v1-base',
      displayPrefix: 'F5-TTS',
      description:
          'F5-TTS DiT flow-matching TTS — zero-shot voice clone (English)',
      kind: ModelKind.tts,
      defaultLanguages: langsEn,
    ),
    // CosyVoice3 — LLM + flow/hift/voices companions auto-discovered by
    // the engine; the probe walks the cosyvoice3-llm baseName and the
    // companions ride along via defaultCompanions.
    'cosyvoice3-tts-rl': BackendRepo(
      backend: 'cosyvoice3-tts-rl',
      repoId: 'cstr/cosyvoice3-0.5b-2512-GGUF',
      baseName: 'cosyvoice3-llm-rl',
      displayPrefix: 'CosyVoice3 0.5B RL',
      description: 'CosyVoice3 RL-tuned multilingual TTS (11 languages)',
      kind: ModelKind.tts,
      defaultCompanions: [
        'cosyvoice3-flow-q8_0',
        'cosyvoice3-hift-f16',
        'cosyvoice3-voices',
        'cosyvoice3-s3tok-q4_k',
        'cosyvoice3-campplus-f16',
      ],
      defaultLanguages: langsCosyvoice10,
    ),
    'cosyvoice3-tts': BackendRepo(
      backend: 'cosyvoice3-tts',
      repoId: 'cstr/cosyvoice3-0.5b-2512-GGUF',
      baseName: 'cosyvoice3-llm',
      displayPrefix: 'CosyVoice3 0.5B',
      description: 'CosyVoice3 streaming multilingual TTS (11 languages)',
      kind: ModelKind.tts,
      defaultCompanions: [
        'cosyvoice3-flow-q8_0',
        'cosyvoice3-hift-f16',
        'cosyvoice3-voices',
        'cosyvoice3-s3tok-q4_k',
        'cosyvoice3-campplus-f16',
      ],
      defaultLanguages: langsCosyvoice10,
    ),
    // Piper — single-file VITS voices, no companion. baseName 'piper' lets
    // the HF-repo probe pick up sibling piper-*.gguf voices once hosted.
    'piper': BackendRepo(
      backend: 'piper',
      repoId: 'cstr/piper-voices-GGUF',
      baseName: 'piper',
      displayPrefix: 'Piper',
      description: 'Piper VITS TTS — tiny (~15-60 MB) single-file voices '
          '(German Thorsten CC0, en_GB Cori public domain)',
      kind: ModelKind.tts,
      defaultLanguages: <String>['de', 'en'],
    ),
    // ----- New TTS BackendRepos (Phase 2: full CrispASR parity) -----
    'bark': BackendRepo(
      backend: 'bark',
      repoId: 'cstr/bark-small-GGUF',
      baseName: 'bark-small',
      displayPrefix: 'Bark',
      description: 'Bark 3-stage GPT-2 TTS — multilingual, DE speakers',
      kind: ModelKind.tts,
      defaultLanguages: <String>['de', 'en', 'es', 'fr', 'ja', 'ko', 'zh'],
    ),
    'csm': BackendRepo(
      backend: 'csm',
      repoId: 'cstr/csm-1b-GGUF',
      baseName: 'csm-1b',
      displayPrefix: 'CSM',
      description: 'Sesame CSM-1B conversational TTS (English)',
      kind: ModelKind.tts,
      defaultLanguages: langsEn,
    ),
    'dia': BackendRepo(
      backend: 'dia',
      repoId: 'cstr/dia-1.6b-GGUF',
      baseName: 'dia-1.6b',
      displayPrefix: 'Dia',
      description: 'Dia 1.6B dialogue TTS — [S1]/[S2] speaker tags (English)',
      kind: ModelKind.tts,
      defaultCompanions: ['dac-44khz'],
      defaultLanguages: langsEn,
    ),
    'bananamind-tts': BackendRepo(
      backend: 'bananamind-tts',
      repoId: 'cstr/bananamind-tts-GGUF',
      baseName: 'bananamind-tts',
      displayPrefix: 'BananaMind TTS',
      description:
          'BananaMind-TTS V2.1 — Tacotron-lite + HiFi-GAN (English, German)',
      kind: ModelKind.tts,
      defaultLanguages: [...langsEn, ...langsDe],
    ),
    'fastpitch': BackendRepo(
      backend: 'fastpitch',
      repoId: 'cstr/fastpitch-en-GGUF',
      baseName: 'fastpitch-en',
      displayPrefix: 'FastPitch',
      description: 'NVIDIA FastPitch — deterministic parallel TTS (English)',
      kind: ModelKind.tts,
      defaultLanguages: langsEn,
    ),
    'melotts': BackendRepo(
      backend: 'melotts',
      repoId: 'cstr/melotts-en-v2-GGUF',
      baseName: 'melotts-en-v2',
      displayPrefix: 'MeloTTS v2',
      description: 'MeloTTS VITS2 TTS (4 EN speakers, 44.1 kHz)',
      kind: ModelKind.tts,
      defaultCompanions: ['bert-base-uncased-q4k'],
      defaultLanguages: langsEn,
    ),
    'melotts-v3': BackendRepo(
      backend: 'melotts',
      repoId: 'cstr/melotts-en-v3-GGUF',
      baseName: 'melotts-en-v3',
      displayPrefix: 'MeloTTS v3',
      description: 'MeloTTS v3 newest checkpoint (1 EN speaker)',
      kind: ModelKind.tts,
      defaultCompanions: ['bert-base-uncased-q4k'],
      defaultLanguages: langsEn,
    ),
    'outetts': BackendRepo(
      backend: 'outetts',
      repoId: 'cstr/outetts-0.3-1b-GGUF',
      baseName: 'outetts-0.3-1b',
      displayPrefix: 'OuteTTS',
      description:
          'OuteTTS 0.3 1B — OLMo + WavTokenizer, voice clone (English)',
      kind: ModelKind.tts,
      defaultCompanions: ['wavtokenizer-decoder-f16'],
      defaultLanguages: langsEn,
    ),
    'parler-tts': BackendRepo(
      backend: 'parler-tts',
      repoId: 'cstr/parler-tts-mini-v1.1-GGUF',
      baseName: 'parler-mini-v1.1',
      displayPrefix: 'Parler-TTS',
      description: 'Parler-TTS Mini — describe the voice in text (English)',
      kind: ModelKind.tts,
      defaultLanguages: langsEn,
    ),
    'pocket-tts': BackendRepo(
      backend: 'pocket-tts',
      repoId: 'cstr/pocket-tts-GGUF',
      baseName: 'pocket-tts-english',
      displayPrefix: 'Pocket TTS',
      description: 'Kyutai Pocket TTS 100M — voice clone from WAV (English)',
      kind: ModelKind.tts,
      defaultLanguages: langsEn,
    ),
    'speecht5': BackendRepo(
      backend: 'speecht5',
      repoId: 'cstr/speecht5-tts-GGUF',
      baseName: 'speecht5-tts',
      displayPrefix: 'SpeechT5',
      description: 'Microsoft SpeechT5 80M TTS (English)',
      kind: ModelKind.tts,
      defaultLanguages: langsEn,
    ),
    'kugelaudio': BackendRepo(
      backend: 'kugelaudio',
      repoId: 'cstr/kugelaudio-0-open-GGUF',
      baseName: 'kugelaudio-0-open',
      displayPrefix: 'KugelAudio',
      description: 'KugelAudio 0 Open — large TTS model',
      kind: ModelKind.tts,
    ),
    'zonos': BackendRepo(
      backend: 'zonos',
      repoId: 'cstr/zonos-v0.1-transformer-GGUF',
      baseName: 'zonos-v0.1-transformer',
      displayPrefix: 'Zonos',
      description:
          'Zonos v0.1 TTS — emotion/pitch/rate control, voice cloning, 44.1 kHz',
      kind: ModelKind.tts,
      defaultCompanions: ['dac-44khz'],
      defaultLanguages: langsAll,
    ),
    // ----- New TTS variant BackendRepos -----
    'lahgtna-chatterbox': BackendRepo(
      backend: 'chatterbox',
      repoId: 'cstr/lahgtna-chatterbox-v1-GGUF',
      baseName: 'chatterbox-t3',
      displayPrefix: 'Lahgtna Chatterbox',
      description: 'Arabic Chatterbox TTS finetune',
      kind: ModelKind.tts,
      defaultCompanions: ['chatterbox-s3gen-q8_0'],
      defaultLanguages: langsAr,
    ),
    'lex-au-orpheus-de': BackendRepo(
      backend: 'orpheus',
      repoId: 'lex-au/Orpheus-3b-German-FT-Q8_0.gguf',
      baseName: 'Orpheus-3b-German-FT',
      displayPrefix: 'Orpheus DE (lex-au)',
      description: 'German Orpheus-3B fine-tune',
      kind: ModelKind.tts,
      defaultCompanions: ['snac-24khz'],
      defaultLanguages: langsDe,
    ),
    'gwen-tts': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/gwen-tts-0.6b-GGUF',
      baseName: 'gwen-tts-0.6b',
      displayPrefix: 'Gwen-TTS',
      description: 'Vietnamese-optimised Qwen3-TTS finetune',
      kind: ModelKind.tts,
      defaultCompanions: ['qwen3-tts-tokenizer-12hz'],
      defaultLanguages: <String>['vi', 'en', 'zh'],
    ),
    'qwen3-tts-1.7b-base': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/qwen3-tts-1.7b-base-GGUF',
      baseName: 'qwen3-tts-12hz-1.7b-base',
      displayPrefix: 'Qwen3-TTS 1.7B base',
      description: 'Qwen3-TTS 1.7B base — higher quality voice clone',
      kind: ModelKind.tts,
      defaultCompanions: ['qwen3-tts-tokenizer-12hz'],
      defaultLanguages: langsQwen3Tts10,
    ),
    'vibevoice-1.5b': BackendRepo(
      backend: 'vibevoice-tts',
      repoId: 'cstr/vibevoice-1.5b-GGUF',
      baseName: 'vibevoice-1.5b-tts',
      displayPrefix: 'VibeVoice 1.5B',
      description: 'VibeVoice 1.5B TTS — larger, higher quality',
      kind: ModelKind.tts,
      defaultLanguages: langsVibevoiceTts10,
    ),
    // ----- New ASR BackendRepos -----
    'moonshine-de': BackendRepo(
      backend: 'moonshine',
      repoId: 'cstr/moonshine-base-de-fidoriel-GGUF',
      baseName: 'moonshine-base-de-fidoriel',
      displayPrefix: 'Moonshine DE',
      description: 'Moonshine base German (6.9% WER CV22)',
      defaultCompanions: ['moonshine-tokenizer'],
      defaultLanguages: langsDe,
    ),
    'moonshine-tiny-de': BackendRepo(
      backend: 'moonshine',
      repoId: 'cstr/moonshine-tiny-de-fidoriel-GGUF',
      baseName: 'moonshine-tiny-de-fidoriel',
      displayPrefix: 'Moonshine tiny DE',
      description: 'Moonshine tiny German (11.4% WER CV22)',
      defaultCompanions: ['moonshine-tokenizer'],
      defaultLanguages: langsDe,
    ),
    'hubert': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/hubert-large-ls960-ft-GGUF',
      baseName: 'hubert-large-ls960-ft',
      displayPrefix: 'HuBERT Large',
      description: 'HuBERT Large LS960 fine-tuned (English CTC)',
      defaultLanguages: langsEn,
    ),
    'wav2vec2-de': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-german-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-german',
      displayPrefix: 'Wav2Vec2 DE',
      description: 'Wav2Vec2 XLSR-53 German CTC',
      defaultLanguages: langsDe,
    ),
    // §10 — wav2vec2 language variants (CTC ASR + forced alignment)
    'wav2vec2-fr': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-french-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-french',
      displayPrefix: 'Wav2Vec2 FR',
      description: 'Wav2Vec2 XLSR-53 French CTC',
      defaultLanguages: langsFr,
    ),
    'wav2vec2-es': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-spanish-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-spanish',
      displayPrefix: 'Wav2Vec2 ES',
      description: 'Wav2Vec2 XLSR-53 Spanish CTC',
      defaultLanguages: langsEs,
    ),
    'wav2vec2-it': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-italian-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-italian',
      displayPrefix: 'Wav2Vec2 IT',
      description: 'Wav2Vec2 XLSR-53 Italian CTC',
      defaultLanguages: langsIt,
    ),
    'wav2vec2-ja': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-japanese-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-japanese',
      displayPrefix: 'Wav2Vec2 JA',
      description: 'Wav2Vec2 XLSR-53 Japanese CTC',
      defaultLanguages: langsJa,
    ),
    'wav2vec2-zh': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-chinese-zh-cn-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-chinese-zh-cn',
      displayPrefix: 'Wav2Vec2 ZH',
      description: 'Wav2Vec2 XLSR-53 Chinese (zh-CN) CTC',
      defaultLanguages: langsZh,
    ),
    'wav2vec2-nl': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-dutch-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-dutch',
      displayPrefix: 'Wav2Vec2 NL',
      description: 'Wav2Vec2 XLSR-53 Dutch CTC',
      defaultLanguages: langsNl,
    ),
    'wav2vec2-pt': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-portuguese-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-portuguese',
      displayPrefix: 'Wav2Vec2 PT',
      description: 'Wav2Vec2 XLSR-53 Portuguese CTC',
      defaultLanguages: langsPt,
    ),
    'wav2vec2-ar': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-large-xlsr-53-arabic-GGUF',
      baseName: 'wav2vec2-large-xlsr-53-arabic',
      displayPrefix: 'Wav2Vec2 AR',
      description: 'Wav2Vec2 XLSR-53 Arabic CTC',
      defaultLanguages: langsAr,
    ),
    'wav2vec2-cs': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-xls-r-300m-cs-250-GGUF',
      baseName: 'wav2vec2-xls-r-300m-cs-250',
      displayPrefix: 'Wav2Vec2 CS',
      description: 'Wav2Vec2 XLS-R 300M Czech CTC',
      defaultLanguages: langsCs,
    ),
    'wav2vec2-uk': BackendRepo(
      backend: 'wav2vec2',
      repoId: 'cstr/wav2vec2-xls-r-300m-uk-with-small-lm-GGUF',
      baseName: 'wav2vec2-xls-r-300m-uk-with-small-lm',
      displayPrefix: 'Wav2Vec2 UK',
      description: 'Wav2Vec2 XLS-R 300M Ukrainian CTC',
      defaultLanguages: langsUk,
    ),
    // §10 — canary-ctc-aligner (forced alignment GGUF)
    'canary-ctc-aligner': BackendRepo(
      backend: 'canary-ctc-aligner',
      repoId: 'cstr/canary-ctc-aligner-GGUF',
      baseName: 'canary-ctc-aligner',
      displayPrefix: 'Canary CTC Aligner',
      description: 'CTC forced aligner for word-level timestamps',
      defaultLanguages: langsAll,
    ),
    'omniasr-ctc': BackendRepo(
      backend: 'omniasr',
      repoId: 'cstr/omniASR-CTC-300M-v2-GGUF',
      baseName: 'omniasr-ctc-300m-v2',
      displayPrefix: 'OmniASR CTC 300M',
      description: 'OmniASR CTC 300M — 1600+ languages, tiny',
      defaultLanguages: langsAll,
    ),
    'parakeet-ja': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-tdt-0.6b-ja-GGUF',
      baseName: 'parakeet-tdt-0.6b-ja',
      displayPrefix: 'Parakeet JA',
      description: 'Parakeet TDT 0.6B Japanese',
      defaultLanguages: langsJa,
    ),
    'parakeet-ctc-0.6b': BackendRepo(
      backend: 'fastconformer-ctc',
      repoId: 'cstr/parakeet-ctc-0.6b-GGUF',
      baseName: 'parakeet-ctc-0.6b',
      displayPrefix: 'Parakeet CTC 0.6B',
      description: 'Parakeet CTC-only 0.6B (English)',
      defaultLanguages: langsEn,
    ),
    'parakeet-ctc-1.1b': BackendRepo(
      backend: 'fastconformer-ctc',
      repoId: 'cstr/parakeet-ctc-1.1b-GGUF',
      baseName: 'parakeet-ctc-1.1b',
      displayPrefix: 'Parakeet CTC 1.1B',
      description: 'Parakeet CTC-only 1.1B (English)',
      defaultLanguages: langsEn,
    ),
    'parakeet-tdt_ctc-110m': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-tdt_ctc-110m-GGUF',
      baseName: 'parakeet-tdt_ctc-110m',
      displayPrefix: 'Parakeet TDT+CTC 110M',
      description: 'Parakeet TDT+CTC 110M — tiny hybrid (English)',
      defaultLanguages: langsEn,
    ),
    'parakeet-tdt_ctc-1.1b': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-tdt_ctc-1.1b-GGUF',
      baseName: 'parakeet-tdt_ctc-1.1b',
      displayPrefix: 'Parakeet TDT+CTC 1.1B',
      description: 'Parakeet TDT+CTC 1.1B — large hybrid, multilingual',
      defaultLanguages: langsEU25,
    ),
    'parakeet-rnnt-0.6b': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-rnnt-0.6b-GGUF',
      baseName: 'parakeet-rnnt-0.6b',
      displayPrefix: 'Parakeet RNNT 0.6B',
      description: 'Parakeet RNN-Transducer 0.6B (English)',
      defaultLanguages: langsEn,
    ),
    'parakeet-rnnt-1.1b': BackendRepo(
      backend: 'parakeet',
      repoId: 'cstr/parakeet-rnnt-1.1b-GGUF',
      baseName: 'parakeet-rnnt-1.1b',
      displayPrefix: 'Parakeet RNNT 1.1B',
      description: 'Parakeet RNN-Transducer 1.1B (English)',
      defaultLanguages: langsEn,
    ),
    // ----- Truecaser BackendRepo -----
    'truecaser-de': BackendRepo(
      backend: 'truecaser',
      repoId: 'cstr/truecaser-de',
      baseName: 'truecaser',
      displayPrefix: 'Truecaser',
      description:
          'Character-level truecaser (DE/EN/ES/RU) — restores capitalization',
      extension: '.bin',
      kind: ModelKind.punc,
      defaultLanguages: <String>['de', 'en', 'es', 'ru'],
    ),
    'pcs': BackendRepo(
      backend: 'pcs',
      repoId: 'cstr/pcs-xlmr-base-GGUF',
      baseName: 'pcs-xlmr-base',
      displayPrefix: 'PCS',
      description: 'Punctuation + Capitalization + Segmentation (47 languages)',
      kind: ModelKind.punc,
      defaultLanguages: langsAll,
    ),
    // §5.25.2 — Embedding model repos for semantic transcript search.
    'embed': BackendRepo(
      backend: 'embed',
      repoId: 'cstr/all-MiniLM-L6-v2-GGUF',
      baseName: 'all-MiniLM-L6-v2',
      displayPrefix: 'all-MiniLM-L6-v2',
      description: 'Compact text embedding model for semantic search (384 dim)',
      kind: ModelKind.embed,
      defaultLanguages: ['*'],
    ),
    // §5.25.2 — Omnimodal embedding model: text + audio + vision.
    'embed-omni': BackendRepo(
      backend: 'embed',
      repoId: 'cstr/bidirlm-omni-2.5b-GGUF',
      baseName: 'bidirlm-omni-2.5b',
      displayPrefix: 'BidirLM-Omni 2.5B',
      description:
          'Omnimodal embedding model — text + audio + vision (2048 dim)',
      kind: ModelKind.embed,
      defaultLanguages: ['*'],
    ),
    // §12.3a — Reranker repos
    'reranker-msmarco': BackendRepo(
      backend: 'reranker',
      repoId: 'cstr/ms-marco-MiniLM-L-6-v2-GGUF',
      baseName: 'ms-marco-MiniLM-L-6-v2',
      displayPrefix: 'MS MARCO MiniLM-L6 Reranker',
      description: 'Compact cross-encoder reranker',
      kind: ModelKind.reranker,
      defaultLanguages: ['en'],
    ),
    'reranker-mxbai-xsmall': BackendRepo(
      backend: 'reranker',
      repoId: 'cstr/mxbai-rerank-xsmall-v1-GGUF',
      baseName: 'mxbai-rerank-xsmall-v1',
      displayPrefix: 'mxbai Rerank XSmall',
      description: 'mxbai cross-encoder reranker',
      kind: ModelKind.reranker,
      defaultLanguages: ['en'],
    ),
    'reranker-bge-m3': BackendRepo(
      backend: 'reranker',
      repoId: 'cstr/bge-reranker-v2-m3-GGUF',
      baseName: 'bge-reranker-v2-m3',
      displayPrefix: 'BGE Reranker v2 M3',
      description: 'Multilingual cross-encoder reranker',
      kind: ModelKind.reranker,
      defaultLanguages: ['*'],
    ),
    // §12.4 — Larger embedding repos
    'embed-nomic': BackendRepo(
      backend: 'embed',
      repoId: 'cstr/nomic-embed-text-v1.5-GGUF',
      baseName: 'nomic-embed-text-v1.5',
      displayPrefix: 'Nomic Embed v1.5',
      description: 'Nomic BERT 768-dim (8192 context)',
      kind: ModelKind.embed,
      defaultLanguages: ['en'],
    ),
    'embed-e5-small': BackendRepo(
      backend: 'embed',
      repoId: 'cstr/multilingual-e5-small-GGUF',
      baseName: 'multilingual-e5-small',
      displayPrefix: 'Multilingual E5 Small',
      description: 'Multilingual 384-dim (100+ langs)',
      kind: ModelKind.embed,
      defaultLanguages: ['*'],
    ),
    'embed-qwen3-0.6b': BackendRepo(
      backend: 'embed',
      repoId: 'cstr/qwen3-embed-0.6b-GGUF',
      baseName: 'qwen3-embed-0.6b',
      displayPrefix: 'Qwen3 Embedding 0.6B',
      description: 'Qwen3 decoder embedding 1024-dim, Matryoshka',
      kind: ModelKind.embed,
      defaultLanguages: ['*'],
    ),
    // §12.6b — OCR model repos
    'ocr-pix2tex': BackendRepo(
      backend: 'ocr',
      repoId: 'cstr/pix2tex-mfr-gguf',
      baseName: 'pix2tex-mfr',
      displayPrefix: 'pix2tex Math OCR',
      description: 'DeiT+TrOCR math formula recognition',
      kind: ModelKind.ocr,
    ),
    'ocr-hmer': BackendRepo(
      backend: 'ocr',
      repoId: 'cstr/hmer-handwritten-math-gguf',
      baseName: 'hmer-hw',
      displayPrefix: 'HMER Handwritten Math',
      description: 'DenseNet+Transformer handwritten math OCR',
      kind: ModelKind.ocr,
    ),
    'ocr-granite-vision': BackendRepo(
      backend: 'ocr',
      repoId: 'cstr/granite-vision-crispembed-GGUF',
      baseName: 'granite-vision-3.3-2b',
      displayPrefix: 'Granite Vision 3.3',
      description: 'SigLIP + Granite 2B VLM document OCR',
      kind: ModelKind.ocr,
    ),
  };

  /// Whether [name] is the recommended default for its backend — drives
  /// the "Recommended" badge in the model pickers.
  static bool isRecommendedDefault(String name) =>
      recommendedDefaultModels.containsValue(name);

  /// Resolve the language-picker codes for [def]. Single source of truth
  /// used by the Transcribe screen's language dropdown AND the
  /// catalogue-invariant tests so a regression in one is caught by
  /// the other.
  ///
  /// Resolution order:
  ///   1. `def.languages` if non-empty.
  ///   2. Longest-prefix BackendRepo match: among repos with the
  ///      same `backend` field, pick the one whose `baseName` is
  ///      the longest prefix of the model's filename stem. This
  ///      disambiguates families where multiple BackendRepos share
  ///      a backend id — e.g. `funasr` (zh+en+ja+ko) vs
  ///      `funasr-mlt` (30 langs) both have backend='funasr', or
  ///      `parakeet` (v3, EU25) vs `parakeet-tdt-1.1b` (en-only),
  ///      or `chatterbox` (23 langs base) vs `chatterbox-turbo`
  ///      (English-only) vs `kartoffelbox` (de+en). Without the
  ///      prefix tie-breaker, the FIRST-declared repo wins for the
  ///      whole family — which is exactly the #14 v2 bug the
  ///      reporter hit where funasr-mlt-nano resolved to funasr-nano's
  ///      4 codes.
  ///   3. Plain backend match (no baseName overlap with the def)
  ///      as a last-resort fallback for HF-direct-import / untagged
  ///      entries.
  ///   4. `['*']` from any path → expands via `expandAll`.
  ///   5. Empty after all that → returns const empty.
  static List<String> resolveLanguageCodes(
    ModelDefinition? def, {
    required List<String> Function() expandAll,
  }) {
    if (def == null) return const [];
    var codes = def.languages;
    if (codes.isEmpty) {
      // Strip .gguf / .bin suffix from the filename so the prefix
      // comparison is against the model stem (matches the baseName
      // shape the catalogue uses).
      final stem = def.fileName.replaceFirst(RegExp(r'\.(gguf|bin)$'), '');
      BackendRepo? best;
      int bestLen = -1;
      for (final repo in backendRepos.values) {
        if (repo.backend != def.backend) continue;
        if (repo.defaultLanguages.isEmpty) continue;
        if (repo.baseName.isEmpty) continue; // voicepack-only repo
        if (!stem.startsWith(repo.baseName)) continue;
        if (repo.baseName.length > bestLen) {
          bestLen = repo.baseName.length;
          best = repo;
        }
      }
      if (best != null) {
        codes = best.defaultLanguages;
      } else {
        // No baseName prefix matched — fall back to first
        // backend-only match. Used by HF-direct-import entries
        // whose filename doesn't follow any catalogue convention.
        for (final repo in backendRepos.values) {
          if (repo.backend == def.backend && repo.defaultLanguages.isNotEmpty) {
            codes = repo.defaultLanguages;
            break;
          }
        }
      }
    }
    if (codes.isEmpty) return const [];
    if (codes.contains('*')) return expandAll();
    return codes.toList();
  }

  /// Best-effort mapping from CrispASR backend id → catalog [ModelKind].
  /// Falls back to ASR for unknown backends so they still show up in the
  /// default Model Management view.
  static ModelKind kindForBackend(String backend) {
    const tts = {
      'vibevoice-tts',
      'qwen3-tts',
      'kokoro',
      'orpheus',
      'chatterbox',
      'indextts',
      'f5-tts',
      'dots-tts',
      'moss-tts',
      'omnivoice',
      'irodori-tts',
      'voxtral-tts',
      'cosyvoice3-tts',
    };
    const punc = {'firered-punc', 'fullstop-punc'};
    const diarize = {'pyannote', 'wespeaker'};
    const vad = {'vad'};
    const lid = {'lid', 'titanet'};
    const translate = {'m2m100', 'm2m100-wmt21', 'madlad'};
    if (tts.contains(backend)) return ModelKind.tts;
    if (punc.contains(backend)) return ModelKind.punc;
    if (diarize.contains(backend)) return ModelKind.diarize;
    if (vad.contains(backend)) return ModelKind.vad;
    if (lid.contains(backend)) return ModelKind.lid;
    if (translate.contains(backend)) return ModelKind.translate;
    return ModelKind.asr;
  }
}
