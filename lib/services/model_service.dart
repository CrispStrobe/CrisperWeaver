// lib/services/model_service.dart (COMPLETE IMPLEMENTATION)
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart' show ZipDecoder;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:crispasr/crispasr.dart' as crispasr;

import 'baked_models_catalog.dart';
import 'ios_helpers.dart';
import 'disk_space.dart';
import 'log_service.dart';
import 'settings_service.dart';

class ModelService {
  /// Upstream ggerganov repo — the canonical source for F16 GGML Whisper models.
  static const String whisperCppBaseUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  /// Secondary repo under the cstr namespace — used for quantized Whisper
  /// variants (q4_0 / q5_0 / q8_0) and mirrors.
  static const String cstrWhisperCppBaseUrl =
      'https://huggingface.co/cstr/whisper-ggml-quants/resolve/main';

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
  // The 25-language EU set Canary 1B-v2 + Parakeet TDT v3 advertise.
  // Per the upstream HF model cards: includes Maltese (mt), excludes
  // Norwegian (the EU25 ASR set uses Swedish for Scandinavia and
  // omits no).
  static const List<String> langsEU25 = <String>[
    'en', 'de', 'fr', 'es', 'it', 'pt', 'nl', 'pl', 'ru', 'uk',
    'cs', 'da', 'sv', 'mt', 'fi', 'el', 'bg', 'ro', 'sk', 'sl',
    'lt', 'lv', 'et', 'hr', 'hu',
  ];
  // 14-language set Cohere transcribe-03-2026 advertises (added
  // Greek / Dutch / Polish / Vietnamese, dropped Hindi / Russian /
  // Turkish vs the older 13-lang variant).
  static const List<String> langsCohere14 = <String>[
    'en', 'es', 'fr', 'de', 'it', 'pt', 'zh', 'ja', 'ko',
    'ar', 'el', 'nl', 'pl', 'vi',
  ];
  // Kept under the old name for any catalogue rows still referring
  // to it — alias to the corrected list so the diff stays consistent.
  static const List<String> langsCohere13 = langsCohere14;
  // 8-language set Voxtral Mini 3B 2507 advertises on HF. The
  // 9th-language addition (Arabic) the user-facing card showed
  // earlier was a card edit; the actual HF API tags list 8.
  static const List<String> langsVoxtral9 = <String>[
    'en', 'fr', 'es', 'pt', 'it', 'nl', 'de', 'hi',
  ];
  // Legacy alias retained for older catalogue rows that referred to
  // the earlier 8-language voxtral set. Same list now points at the
  // 9-language one — the 8-lang card was stale.
  static const List<String> langsVoxtral8 = langsVoxtral9;
  // 6-language set used by Granite Speech 3.x and 4.0 / 4.1 base.
  static const List<String> langsGranite6 = <String>[
    'en', 'fr', 'de', 'es', 'pt', 'ja',
  ];
  // 5-language set used by Granite Speech 4.1-plus / -nar (dropped
  // Japanese vs the 6-lang base).
  static const List<String> langsGranite5 = <String>[
    'en', 'fr', 'de', 'es', 'pt',
  ];
  // 29-language set used by the Qwen3-ASR family + Mega-ASR. From
  // the upstream HF cards.
  static const List<String> langsQwen3Asr29 = <String>[
    'ar', 'cs', 'da', 'de', 'el', 'en', 'es', 'fa', 'fi', 'fr',
    'hi', 'hu', 'id', 'it', 'ja', 'ko', 'mk', 'ms', 'nl', 'pl',
    'pt', 'ro', 'ru', 'sv', 'th', 'tl', 'tr', 'vi', 'zh',
  ];
  // 10-language set used by the qwen3-tts base + voicedesign + codec
  // repos. customvoice variants use the 9-language subset below (no
  // Russian).
  static const List<String> langsQwen3Tts10 = <String>[
    'de', 'en', 'es', 'fr', 'it', 'ja', 'ko', 'pt', 'ru', 'zh',
  ];
  static const List<String> langsQwen3TtsCustom9 = <String>[
    'de', 'en', 'es', 'fr', 'it', 'ja', 'ko', 'pt', 'zh',
  ];
  // 8-language set the WMT21 Dense translators advertise.
  static const List<String> langsWmt21_8 = <String>[
    'cs', 'de', 'en', 'ha', 'is', 'ja', 'ru', 'zh',
  ];
  // 10-language set Vibevoice TTS lists (jp/kr/sp are non-standard
  // 2-letter codes mapped to ja/ko/es by the runtime).
  static const List<String> langsVibevoiceTts10 = <String>[
    'de', 'en', 'fr', 'it', 'ja', 'ko', 'nl', 'pl', 'pt', 'es',
  ];
  // SenseVoice supports zh/en/ja/ko/yue; we surface yue under zh.
  static const List<String> langsSensevoice = <String>['zh', 'en', 'ja', 'ko'];
  // Fullstop-punc multilingual checkpoint.
  static const List<String> langsFullstopPunc = <String>['en', 'de', 'fr', 'it'];
  // Chatterbox base (ResembleAI) advertises 23 langs.
  static const List<String> langsChatterbox23 = <String>[
    'ar', 'da', 'de', 'el', 'en', 'es', 'fi', 'fr', 'he', 'hi',
    'it', 'ja', 'ko', 'ms', 'nl', 'no', 'pl', 'pt', 'ru', 'sv',
    'sw', 'tr', 'zh',
  ];
  // VoxCPM2 (openbmb/VoxCPM2) advertises 29 langs per cstr/voxcpm2-GGUF's
  // cardData. Diffusion AR TTS, 48 kHz native (decimated to 24 kHz in the
  // C API to match the host's fixed-rate playback path).
  static const List<String> langsVoxcpm2_29 = <String>[
    'en', 'zh', 'ja', 'ko', 'de', 'fr', 'es', 'pt', 'it', 'nl',
    'ru', 'ar', 'hi', 'vi', 'th', 'id', 'ms', 'tl', 'tr', 'pl',
    'cs', 'sv', 'da', 'no', 'fi', 'el', 'he', 'uk', 'ro',
  ];
  // The 99 languages whisper.cpp supports — from the whisper.cpp
  // source's lang_id table. Codes are ISO 639-1 where one exists;
  // a handful are 3-letter aliases (haw / yue) that the runtime
  // recognises. ggerganov/whisper.cpp's HF cardData doesn't list
  // them so we hardcode rather than read from the API.
  static const List<String> langsWhisper99 = <String>[
    'en', 'zh', 'de', 'es', 'ru', 'ko', 'fr', 'ja', 'pt', 'tr',
    'pl', 'ca', 'nl', 'ar', 'sv', 'it', 'id', 'hi', 'fi', 'vi',
    'he', 'uk', 'el', 'ms', 'cs', 'ro', 'da', 'hu', 'ta', 'no',
    'th', 'ur', 'hr', 'bg', 'lt', 'la', 'mi', 'ml', 'cy', 'sk',
    'te', 'fa', 'lv', 'bn', 'sr', 'az', 'sl', 'kn', 'et', 'mk',
    'br', 'eu', 'is', 'hy', 'ne', 'mn', 'bs', 'kk', 'sq', 'sw',
    'gl', 'mr', 'pa', 'si', 'km', 'sn', 'yo', 'so', 'af', 'oc',
    'ka', 'be', 'tg', 'sd', 'gu', 'am', 'yi', 'lo', 'uz', 'fo',
    'ht', 'ps', 'tk', 'nn', 'mt', 'sa', 'lb', 'my', 'bo', 'tl',
    'mg', 'as', 'tt', 'haw', 'ln', 'ha', 'ba', 'jw', 'su', 'yue',
  ];
  // VibeVoice ASR's 48-language list (per cstr/vibevoice-asr-GGUF's
  // cardData on HF).
  static const List<String> langsVibevoice48 = <String>[
    'en', 'zh', 'es', 'pt', 'de', 'ja', 'ko', 'fr', 'ru', 'id',
    'sv', 'it', 'he', 'nl', 'pl', 'no', 'tr', 'th', 'ar', 'hu',
    'ca', 'cs', 'da', 'fa', 'af', 'hi', 'fi', 'et', 'el', 'ro',
    'vi', 'bg', 'is', 'sl', 'sk', 'lt', 'sw', 'uk', 'lv', 'hr',
    'ne', 'sr', 'tl', 'ms', 'ur', 'mn', 'hy', 'jv',
  ];
  // FunASR MLT Nano's 31-language list (per cstr/funasr-mlt-nano-GGUF
  // cardData). The 'yue' (Cantonese) entry maps to 'zh' for the
  // picker since users picking Chinese expect both varieties.
  static const List<String> langsFunasrMlt31 = <String>[
    'zh', 'en', 'ja', 'ko', 'vi', 'th', 'id', 'ms', 'tl', 'ar',
    'hi', 'bg', 'ru', 'de', 'fr', 'es', 'it', 'pt', 'nl', 'pl',
    'cs', 'ro', 'el', 'fi', 'sv', 'tr', 'fa', 'da', 'hu', 'mk',
  ];

  final Dio _dio = Dio();
  late String _modelsDir;
  final SettingsService _settingsService;
  final Map<String, CancelToken> _activeDowloads = {};

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
      description: 'Distilled Whisper Large v3 (English) — ~1.5 GB, faster decode',
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

    // ----- Quantized variants (cstr mirrors) -----
    // These are rough size estimates. Checksums are intentionally empty —
    // size-only validation is used until we have authoritative SHAs.
    'tiny-q5_0': ModelDefinition(
      name: 'tiny-q5_0',
      displayName: 'Whisper Tiny (q5_0)',
      fileName: 'ggml-tiny-q5_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-tiny-q5_0.bin',
      sizeBytes: 33 * 1024 * 1024,
      checksum: '',
      description: '5-bit quantized tiny — smaller, ~same accuracy',
      quantization: 'q5_0',
    ),
    'base-q5_0': ModelDefinition(
      name: 'base-q5_0',
      displayName: 'Whisper Base (q5_0)',
      fileName: 'ggml-base-q5_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-base-q5_0.bin',
      sizeBytes: 60 * 1024 * 1024,
      checksum: '',
      description: '5-bit quantized base — ~60 MB',
      quantization: 'q5_0',
    ),
    'small-q5_0': ModelDefinition(
      name: 'small-q5_0',
      displayName: 'Whisper Small (q5_0)',
      fileName: 'ggml-small-q5_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-small-q5_0.bin',
      sizeBytes: 190 * 1024 * 1024,
      checksum: '',
      description: '5-bit quantized small — ~190 MB',
      quantization: 'q5_0',
    ),
    'medium-q5_0': ModelDefinition(
      name: 'medium-q5_0',
      displayName: 'Whisper Medium (q5_0)',
      fileName: 'ggml-medium-q5_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-medium-q5_0.bin',
      sizeBytes: 540 * 1024 * 1024,
      checksum: '',
      description: '5-bit quantized medium — ~540 MB',
      quantization: 'q5_0',
    ),
    'large-v3-q5_0': ModelDefinition(
      name: 'large-v3-q5_0',
      displayName: 'Whisper Large v3 (q5_0)',
      fileName: 'ggml-large-v3-q5_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-large-v3-q5_0.bin',
      sizeBytes: 1100 * 1024 * 1024,
      checksum: '',
      description: '5-bit quantized large-v3 — ~1.1 GB',
      quantization: 'q5_0',
    ),
    'large-v3-q4_0': ModelDefinition(
      name: 'large-v3-q4_0',
      displayName: 'Whisper Large v3 (q4_0)',
      fileName: 'ggml-large-v3-q4_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-large-v3-q4_0.bin',
      sizeBytes: 880 * 1024 * 1024,
      checksum: '',
      description: '4-bit quantized large-v3 — ~880 MB',
      quantization: 'q4_0',
    ),
    'large-v3-q2_k': ModelDefinition(
      name: 'large-v3-q2_k',
      displayName: 'Whisper Large v3 (q2_k)',
      fileName: 'ggml-large-v3-q2_k.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-large-v3-q2_k.bin',
      sizeBytes: 500 * 1024 * 1024,
      checksum: '',
      description: '2-bit quantized large-v3 — ~500 MB',
      quantization: 'q2_k',
    ),
    'base-q4_0': ModelDefinition(
      name: 'base-q4_0',
      displayName: 'Whisper Base (q4_0)',
      fileName: 'ggml-base-q4_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-base-q4_0.bin',
      sizeBytes: 46 * 1024 * 1024,
      checksum: '',
      description: '4-bit quantized base — ~46 MB',
      quantization: 'q4_0',
    ),
    'small-q4_0': ModelDefinition(
      name: 'small-q4_0',
      displayName: 'Whisper Small (q4_0)',
      fileName: 'ggml-small-q4_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-small-q4_0.bin',
      sizeBytes: 150 * 1024 * 1024,
      checksum: '',
      description: '4-bit quantized small — ~150 MB',
      quantization: 'q4_0',
    ),
    'base-q8_0': ModelDefinition(
      name: 'base-q8_0',
      displayName: 'Whisper Base (q8_0)',
      fileName: 'ggml-base-q8_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-base-q8_0.bin',
      sizeBytes: 78 * 1024 * 1024,
      checksum: '',
      description: '8-bit quantized base — ~78 MB',
      quantization: 'q8_0',
    ),
    'large-v3-q8_0': ModelDefinition(
      name: 'large-v3-q8_0',
      displayName: 'Whisper Large v3 (q8_0)',
      fileName: 'ggml-large-v3-q8_0.bin',
      url: '$cstrWhisperCppBaseUrl/ggml-large-v3-q8_0.bin',
      sizeBytes: 1650 * 1024 * 1024,
      checksum: '',
      description: '8-bit quantized large-v3 — ~1.65 GB',
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
      description:
          'Qwen3-ASR 1.7B + robustness LoRA — multilingual, ~1.3 GB',
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
      description:
          'Moonshine streaming tiny — for live mic streaming, ~32 MB',
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
      description: 'Kokoro multilingual TTS — needs a kokoro-voice-*.gguf',
      quantization: 'q8_0',
      backend: 'kokoro',
      kind: ModelKind.tts,
      companions: ['kokoro-voice-af_heart'],
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
      description:
          'VibeVoice realtime TTS with bundled Tekken tokenizer — '
          'needs a vibevoice-voice-*.gguf voicepack',
      quantization: 'f16',
      backend: 'vibevoice-tts',
      kind: ModelKind.tts,
      companions: ['vibevoice-voice-emma'],
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
          'Qwen3-TTS base — needs the qwen3-tts-tokenizer-12hz codec GGUF',
      quantization: 'q8_0',
      backend: 'qwen3-tts',
      kind: ModelKind.tts,
      companions: ['qwen3-tts-tokenizer-12hz'],
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
      description: 'VoxCPM2 diffusion TTS (f16 reference) — 29 languages, 48 kHz',
      quantization: 'f16',
      backend: 'voxcpm2-tts',
      kind: ModelKind.tts,
      languages: langsVoxcpm2_29,
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
      description: 'Kokoro voicepack — English (af_heart)',
      quantization: 'f16',
      backend: 'kokoro',
      kind: ModelKind.voice,
    ),
    'vibevoice-voice-emma': ModelDefinition(
      name: 'vibevoice-voice-emma',
      displayName: 'VibeVoice voice — Emma',
      fileName: 'vibevoice-voice-emma.gguf',
      url:
          'https://huggingface.co/cstr/vibevoice-realtime-0.5b-GGUF/resolve/main/vibevoice-voice-emma.gguf',
      sizeBytes: 5 * 1024 * 1024,
      checksum: '',
      description: 'VibeVoice voicepack — English (Emma)',
      quantization: 'f16',
      backend: 'vibevoice-tts',
      kind: ModelKind.voice,
    ),
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
      description: 'SNAC 24 kHz codec for Orpheus (load via setCodecPath)',
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
      description: 'Multilingual ASR (140+ languages, instruction-tuned) — ~2.8 GB',
      quantization: 'q4_k',
      backend: 'gemma4-e2b',
    ),
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
      description:
          'ECAPA-TDNN language identification (107 languages) — '
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
      description:
          'FireRed language identification (120 languages) — '
          'highest coverage among bundled LID GGUFs, especially on low-resource languages',
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
  };

  /// Multilingual TTS voicepack catalog. Generated from the HF repos
  /// `cstr/vibevoice-realtime-0.5b-GGUF` (26 voices: en/de/fr/it/jp/kr/
  /// nl/pl/pt/sp/in) and `cstr/kokoro-voices-GGUF` (7 voices: en/de/es/
  /// fr) as of 2026-05. Tagged `kind: voice` so the Voices filter chip
  /// in Model Management surfaces them grouped from the main TTS
  /// models. Each entry's `description` carries the language code so
  /// the UI can group / filter by language without hand-parsing the
  /// filename.
  ///
  /// Computed lazily (not `const`) because the entries are constructed
  /// from a list comprehension. Merged into `lookupDefinition` and
  /// `getWhisperCppModels` alongside the static catalogs above.
  static final Map<String, ModelDefinition> _ttsVoicepacks = () {
    const vibevoiceVoices = <List<String>>[
      // [filename-leaf, language code, display name]
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
      ['in-Samuel_man', 'in', 'Indian English — Samuel (m)'],
      ['it-Spk0_woman', 'it', 'Italian (Spk0, w)'],
      ['it-Spk1_man', 'it', 'Italian (Spk1, m)'],
      ['jp-Spk0_man', 'jp', 'Japanese (Spk0, m)'],
      ['jp-Spk1_woman', 'jp', 'Japanese (Spk1, w)'],
      ['kr-Spk0_woman', 'kr', 'Korean (Spk0, w)'],
      ['kr-Spk1_man', 'kr', 'Korean (Spk1, m)'],
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
      description: 'NVIDIA Canary — multilingual speech translation (25 EU langs)',
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
      description: 'Voxtral realtime variant (en/es/fr/de/it/pt/ru/zh/ja/ko/ar/hi/nl)',
      defaultLanguages: <String>[
        'en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'zh', 'ja', 'ko',
        'ar', 'hi', 'nl',
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
      defaultCompanions: ['vibevoice-voice-emma'],
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
    // Kokoro — multilingual TTS (needs voicepack via setVoice).
    'kokoro': BackendRepo(
      backend: 'kokoro',
      repoId: 'cstr/kokoro-82m-GGUF',
      baseName: 'kokoro-82m',
      displayPrefix: 'Kokoro 82M TTS',
      description: 'Kokoro multilingual TTS (~100 MB)',
      kind: ModelKind.tts,
      defaultCompanions: ['kokoro-voice-af_heart'],
      defaultLanguages: langsAll,
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
      description: 'Qwen3-TTS base talker — needs qwen3-tts-tokenizer-12hz codec',
      kind: ModelKind.tts,
      defaultCompanions: ['qwen3-tts-tokenizer-12hz'],
      defaultLanguages: langsQwen3Tts10,
    ),
    'qwen3-tts-0.6b-customvoice': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/qwen3-tts-0.6b-customvoice-GGUF',
      baseName: 'qwen3-tts-12hz-0.6b-customvoice',
      displayPrefix: 'Qwen3-TTS 0.6B custom-voice',
      description: 'Qwen3-TTS 0.6B with ICL voice cloning (9 langs, no Russian)',
      kind: ModelKind.tts,
      defaultCompanions: ['qwen3-tts-tokenizer-12hz'],
      defaultLanguages: langsQwen3TtsCustom9,
    ),
    'qwen3-tts-1.7b-customvoice': BackendRepo(
      backend: 'qwen3-tts',
      repoId: 'cstr/qwen3-tts-1.7b-customvoice-GGUF',
      baseName: 'qwen3-tts-12hz-1.7b-customvoice',
      displayPrefix: 'Qwen3-TTS 1.7B custom-voice',
      description: 'Qwen3-TTS 1.7B with ICL voice cloning (9 langs, no Russian)',
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
      description: 'Qwen3-TTS 12 Hz audio codec — companion to every Qwen3-TTS talker',
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
  };

  // Live-probed quants, keyed by model name (same as the hardcoded maps).
  // Merged with the static catalog in getWhisperCppModels().
  final Map<String, ModelDefinition> _discoveredModels = {};
  DateTime? _lastProbeAt;

  ModelService(this._settingsService) {
    _configureDio();
  }

  void _configureDio() {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(minutes: 30),
      headers: {
        'User-Agent': 'CrisperWeaver-Flutter/1.0.0',
      },
    );

    // Dio's LogInterceptor dumps 50+ trace lines per HTTP request
    // (every header, every response body). Our own `download start` /
    // `download done` + the DioException catch already capture what we
    // need. Leave it off so the in-app Log view is actually readable.

    // Add interceptors for debugging and retry logic
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        options: const RetryOptions(
          retries: 3,
          retryInterval: Duration(seconds: 2),
        ),
      ),
    );
  }

  Future<void> initialize() async {
    String baseDirPath;
    // On iOS, prefer the App Group container so model downloads survive
    // `flutter install` (which uninstalls the old build first, wiping
    // the per-app `Documents/` sandbox). Other platforms keep the
    // historical layout — macOS / Linux / Windows / Android either
    // disable the sandbox entirely (macOS) or persist `Documents/`
    // across normal updates.
    //
    // App Group identity matches the one declared in
    // Runner.entitlements + ShareExtension.entitlements, so the Share
    // Extension can also see the models directory if it ever needs to
    // hand audio off without an extra copy.
    if (Platform.isIOS) {
      final groupPath =
          await appGroupContainerPath('group.com.crispstrobe.crisperweaver');
      if (groupPath != null && groupPath.isNotEmpty) {
        baseDirPath = groupPath;
        Log.instance.i('model',
            'Using App Group container for models', fields: {'path': groupPath});
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        baseDirPath = appDir.path;
        Log.instance.w('model',
            'App Group resolve failed — falling back to docs dir',
            fields: {'path': appDir.path});
      }
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      baseDirPath = appDir.path;
    }
    _modelsDir = path.join(baseDirPath, 'models');
    await Directory(_modelsDir).create(recursive: true);

    // Default sandbox layout. The custom-models-dir override
    // (settingsService.customModelsDir) is consulted by `_whisperCppDir`
    // on every read, so changing the setting takes effect immediately
    // without re-running initialize().
    await Directory(whisperCppDir())
        .create(recursive: true);

    // Re-register any HF repos the user added by hand in a prior run.
    // Best-effort and memoised — a network failure here never blocks
    // the rest of initialize().
    await _replayUserHfReposOnce();
  }

  /// Resolved directory where ASR / TTS / companion GGUFs live. When
  /// the user has set `settingsService.customModelsDir` (e.g.
  /// `/Volumes/backups/ai/crispasr-models`) we point straight at that
  /// path so an existing on-disk library is reused without
  /// re-downloading. Otherwise falls back to the historical sandbox
  /// path `<app-docs>/models/whisper_cpp`.
  ///
  /// Synchronous because every caller is downstream of `initialize()`,
  /// which already established `_modelsDir`. The override path is
  /// validated lazily — if the user picks a directory that doesn't
  /// exist yet, this attempts to create it; on failure we fall back
  /// to the sandbox path so model loads never silently break.
  String whisperCppDir() {
    final override = _settingsService.customModelsDir;
    if (override.isNotEmpty) {
      try {
        final dir = Directory(override);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return override;
      } catch (e) {
        Log.instance.w('model',
            'customModelsDir unusable, falling back to sandbox',
            error: e, fields: {'attempted': override});
      }
    }
    return path.join(_modelsDir, 'whisper_cpp');
  }

  /// Get available Whisper.cpp models with download status
  Future<List<ModelInfo>> getWhisperCppModels() async {
    await initialize();

    final modelInfos = <ModelInfo>[];

    for (final entry in whisperCppModels.entries) {
      final modelDef = entry.value;
      final localPath = path.join(whisperCppDir(), modelDef.fileName);
      final isDownloaded = await _isModelDownloaded(localPath, modelDef);

      modelInfos.add(ModelInfo(
        name: modelDef.name,
        displayName: modelDef.displayName,
        size: _formatSize(modelDef.sizeBytes),
        sizeBytes: modelDef.sizeBytes,
        isDownloaded: isDownloaded,
        localPath: isDownloaded ? localPath : null,
        description: modelDef.description,
        modelType: ModelType.whisperCpp,
        quantization: modelDef.quantization,
        backend: modelDef.backend,
        kind: modelDef.kind,
        languages: modelDef.languages,
      ));
    }

    // Non-Whisper CrispASR backends. They share the same on-disk directory
    // since each file is just a GGUF blob, but their `backend` field tells
    // the engine which runtime path to dispatch to. We merge in:
    //   * the baked catalog (generated by scripts/bake_models_catalog.dart,
    //     hits the HF API for every BackendRepo at build time so first
    //     launch doesn't wait on the network probe — every release ships
    //     with this in sync),
    //   * the hardcoded core catalog (every backend's default GGUF —
    //     curated display names beat the baked catalog's generic ones),
    //   * the multilingual TTS voicepack catalog (33 vibevoice + kokoro
    //     voices keyed by `<family>-voice-<id>`),
    //   * any quant variants discovered live from HF via _probeRepo
    //     (sizes from those overwrite the baked + hardcoded estimates).
    //
    // Spread order = merge priority (later wins). Live probe beats
    // hardcoded curated entries beats the baked snapshot.
    final merged = <String, ModelDefinition>{
      ...bakedDiscoveredModels,
      ...crispasrBackendModels,
      ..._ttsVoicepacks,
      ..._discoveredModels,
    };
    for (final entry in merged.entries) {
      final modelDef = entry.value;
      final localPath = path.join(whisperCppDir(), modelDef.fileName);
      final isDownloaded = await _isModelDownloaded(localPath, modelDef);

      modelInfos.add(ModelInfo(
        name: modelDef.name,
        displayName: modelDef.displayName,
        size: _formatSize(modelDef.sizeBytes),
        sizeBytes: modelDef.sizeBytes,
        isDownloaded: isDownloaded,
        localPath: isDownloaded ? localPath : null,
        description: modelDef.description,
        modelType: ModelType.whisperCpp,
        quantization: modelDef.quantization,
        backend: modelDef.backend,
        kind: modelDef.kind,
        languages: modelDef.languages,
      ));
    }

    return modelInfos;
  }

  /// Unified lookup — finds a model by name across every catalog including
  /// quants probed from HuggingFace. Live-probed entries take precedence
  /// so their exact byte-sizes overwrite the rounded catalog estimates.
  ModelDefinition? lookupDefinition(String name) {
    return _discoveredModels[name] ??
        whisperCppModels[name] ??
        crispasrBackendModels[name] ??
        _ttsVoicepacks[name] ??
        bakedDiscoveredModels[name];
  }

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
      final stem = def.fileName
          .replaceFirst(RegExp(r'\.(gguf|bin)$'), '');
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
          if (repo.backend == def.backend &&
              repo.defaultLanguages.isNotEmpty) {
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

  /// Whether a probe has succeeded at least once in this session.
  bool get hasProbedQuants => _lastProbeAt != null;
  DateTime? get lastQuantProbeAt => _lastProbeAt;

  /// Enumerate every available quant variant in each CrispASR backend's
  /// HuggingFace repo via `GET /api/models/<repo>`. Results are merged
  /// into the model picker on success; on error we fall back to the
  /// hardcoded catalog and log.
  ///
  /// Returns the total number of freshly-discovered ModelDefinitions
  /// (can be 0 if every file was already in the hardcoded catalog).
  Future<QuantProbeResult> refreshAvailableQuants() async {
    int added = 0;
    final failed = <String>[];
    for (final repo in backendRepos.values) {
      try {
        final models = await _probeRepo(repo);
        for (final m in models) {
          final existed = _discoveredModels.containsKey(m.name) ||
              crispasrBackendModels.containsKey(m.name) ||
              whisperCppModels.containsKey(m.name);
          _discoveredModels[m.name] = m;
          if (!existed) added++;
        }
        Log.instance
            .i('model', 'Probed ${repo.repoId}: ${models.length} variants');
      } catch (e, st) {
        failed.add(repo.repoId);
        Log.instance.w('model', 'Quant probe failed for ${repo.repoId}',
            error: e, stack: st);
      }
    }
    _lastProbeAt = DateTime.now();
    return QuantProbeResult(added: added, failedRepos: failed);
  }

  /// Probe an arbitrary HuggingFace repo for .gguf files and register
  /// each as a runtime ModelDefinition tagged with [backend]. The
  /// catalogue-baked [_probeRepo] requires a [BackendRepo] with strict
  /// naming conventions; this looser variant accepts any repo + any
  /// backend the user picks (mirrors `crispasr --hf-repo OWNER/REPO`
  /// on the CLI side).
  ///
  /// Returns the discovered models. Throws on network / 404 / private
  /// repo so the UI can surface a meaningful error to the user.
  Future<List<ModelDefinition>> probeHfRepoForBackend({
    required String repoId,
    required String backend,
    String? displayPrefix,
    bool persist = true,
  }) async {
    final repoIdTrimmed = repoId.trim();
    if (repoIdTrimmed.isEmpty || !repoIdTrimmed.contains('/')) {
      throw ArgumentError('HF repo id must be in OWNER/NAME form');
    }
    final headers = <String, dynamic>{};
    final token = hfToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final url = 'https://huggingface.co/api/models/$repoIdTrimmed?blobs=true';
    final resp =
        await _dio.get<dynamic>(url, options: Options(headers: headers));
    if (resp.data is! Map) {
      throw StateError('HF API returned unexpected payload for $repoIdTrimmed');
    }
    final siblings = ((resp.data as Map)['siblings'] as List?) ?? const [];
    final prefix = displayPrefix ?? repoIdTrimmed.split('/').last;
    final out = <ModelDefinition>[];
    for (final raw in siblings) {
      if (raw is! Map) continue;
      final fname = raw['rfilename'] as String? ?? '';
      // Accept the two extensions CrispASR's session_open can dlopen.
      // .bin is whisper-cpp legacy; .gguf is the modern format.
      if (!fname.endsWith('.gguf') && !fname.endsWith('.bin')) continue;
      final stem = fname.endsWith('.gguf')
          ? fname.substring(0, fname.length - '.gguf'.length)
          : fname.substring(0, fname.length - '.bin'.length);
      final sizeBytes = (raw['size'] as num?)?.toInt() ?? 0;
      // Best-effort quantisation extraction from the file stem —
      // matches q4_k / q5_0 / q8_0 / f16 / fp16 / iq2_xs etc.
      final quantMatch = RegExp(r'(q\d[_a-z0-9]*|f16|fp16|f32|bf16|iq\d[_a-z0-9]*)',
              caseSensitive: false)
          .firstMatch(stem);
      final quant = quantMatch?.group(0)?.toLowerCase() ?? 'unknown';
      // Namespace runtime entries by repo so two repos that ship a
      // file with the same stem don't clobber each other in
      // _discoveredModels.
      final nameKey = '${repoIdTrimmed.replaceAll('/', '__')}--$stem';
      final def = ModelDefinition(
        name: nameKey,
        displayName: '$prefix · $stem',
        fileName: fname,
        url: 'https://huggingface.co/$repoIdTrimmed/resolve/main/$fname',
        sizeBytes: sizeBytes,
        checksum: '',
        description: '$prefix · $stem — ${_formatSize(sizeBytes)}',
        quantization: quant,
        backend: backend,
      );
      _discoveredModels[nameKey] = def;
      out.add(def);
    }
    Log.instance.i('model',
        'probeHfRepoForBackend: ${out.length} model(s) from $repoIdTrimmed',
        fields: {'backend': backend});
    // Persist the (repoId, backend) pair so the user's manually-added
    // repo survives a restart — replayed from `initialize()`. Only when
    // the probe actually found something, and not when the replay path
    // itself is re-probing (persist: false) to avoid pointless writes.
    if (persist && out.isNotEmpty) {
      _settingsService.addHfUserRepo(repoIdTrimmed, backend,
          displayPrefix: displayPrefix);
    }
    return out;
  }

  /// Forget a user-added HF repo: drop its runtime ModelDefinitions and
  /// its persisted (repoId, backend) entry. Downloaded files on disk are
  /// left untouched — this only removes the catalogue listing.
  void removeUserHfRepo({required String repoId, required String backend}) {
    final repoIdTrimmed = repoId.trim();
    final keyPrefix = '${repoIdTrimmed.replaceAll('/', '__')}--';
    _discoveredModels.removeWhere(
        (name, def) => name.startsWith(keyPrefix) && def.backend == backend);
    _settingsService.removeHfUserRepo(repoIdTrimmed, backend);
    Log.instance.i('model', 'removeUserHfRepo',
        fields: {'repo': repoIdTrimmed, 'backend': backend});
  }

  // Replay user-added HF repos exactly once per ModelService lifetime.
  // Memoised so concurrent `initialize()` callers await the same probe
  // and we never re-issue the network fan-out.
  Future<void>? _userRepoReplay;

  Future<void> _replayUserHfReposOnce() {
    return _userRepoReplay ??= () async {
      final repos = _settingsService.hfUserRepos;
      if (repos.isEmpty) return;
      Log.instance.i('model',
          'replaying ${repos.length} user-added HF repo(s)');
      for (final r in repos) {
        final repoId = r['repoId'] ?? '';
        final backend = r['backend'] ?? '';
        if (repoId.isEmpty || backend.isEmpty) continue;
        try {
          await probeHfRepoForBackend(
            repoId: repoId,
            backend: backend,
            displayPrefix: r['displayPrefix'],
            persist: false,
          );
        } catch (e) {
          // Offline / 404 / private — keep the persisted entry so a
          // later online refresh still surfaces it; just skip for now.
          Log.instance.w('model', 'user HF repo replay failed — skipping',
              error: e, fields: {'repo': repoId, 'backend': backend});
        }
      }
    }();
  }

  /// Discover models from CrispASR's built-in C-side registry — no
  /// network, no hardcoding. For every backend the loaded `libcrispasr`
  /// reports as linked (`CrispasrSession.availableBackends()`), this
  /// queries `crispasr_registry_lookup` and merges the canonical entry
  /// into [_discoveredModels].
  ///
  /// Why bother when [refreshAvailableQuants] already probes HF? Two
  /// reasons:
  /// 1. **Offline-safe.** The registry data ships inside libcrispasr;
  ///    works on a plane / locked-down corp network where the HF probe
  ///    times out.
  /// 2. **New-backend discoverability.** When a CrispASR upgrade adds
  ///    a backend the bundled libcrispasr knows about it but
  ///    [backendRepos] doesn't yet — this probe surfaces it without a
  ///    CrisperWeaver code change. Think `/v1/models` on an OpenAI-
  ///    compatible server, but local.
  ///
  /// Returns the number of newly-discovered ModelDefinitions added in
  /// this call (already-known names are refreshed in place but not
  /// counted).
  int refreshFromCrispasrRegistry() {
    int added = 0;
    final List<String> backends;
    try {
      backends = crispasr.CrispasrSession.availableBackends();
    } catch (e, st) {
      Log.instance.w('model', 'availableBackends() threw', error: e, stack: st);
      return 0;
    }
    if (backends.isEmpty) {
      Log.instance.d('model',
          'CrispASR registry probe: no backends reported by libcrispasr');
      return 0;
    }
    for (final backend in backends) {
      // Whisper has its own catalog (whisperCppModels) and the registry
      // entry is the .bin path under ggerganov/whisper.cpp — already
      // covered. Skip to avoid double-listing.
      if (backend == 'whisper') continue;
      crispasr.RegistryEntry? entry;
      try {
        entry = crispasr.registryLookup(backend);
      } catch (e, st) {
        Log.instance.d('model', 'registryLookup threw',
            fields: {'backend': backend}, error: e, stack: st);
        continue;
      }
      if (entry == null || entry.filename.isEmpty || entry.url.isEmpty) {
        continue;
      }
      // Strip the .gguf extension for the keying convention used by the
      // rest of the catalog (e.g. "parakeet-tdt-0.6b-v3-q4_k").
      final fname = entry.filename;
      final dot = fname.lastIndexOf('.');
      final stem = dot > 0 ? fname.substring(0, dot) : fname;
      final name = stem;
      if (_discoveredModels.containsKey(name) ||
          crispasrBackendModels.containsKey(name) ||
          whisperCppModels.containsKey(name)) {
        continue;
      }
      // Best-effort size parse: registry hands us a string like "~580 MB"
      // or "~4.5 GB". Keep it as the human-readable description and feed
      // a rough byte estimate to the UI so progress bars work.
      final sizeBytes = _parseApproxSize(entry.approxSize);
      _discoveredModels[name] = ModelDefinition(
        name: name,
        displayName: '$stem (CrispASR registry)',
        fileName: fname,
        url: entry.url,
        sizeBytes: sizeBytes,
        checksum: '',
        description:
            'Auto-discovered from CrispASR registry — ${entry.approxSize}',
        quantization: _inferQuant(stem),
        backend: backend,
        kind: _kindForBackend(backend),
      );
      added++;
    }
    Log.instance.i('model', 'CrispASR registry probe done', fields: {
      'backends': backends.length,
      'added': added,
    });
    return added;
  }

  /// Parse a registry approx-size string like `"~580 MB"` / `"~4.5 GB"`
  /// into a byte count. Returns 0 on parse failure so the UI falls back
  /// to "unknown size" instead of misleading numbers.
  int _parseApproxSize(String s) {
    final m = RegExp(r'~?\s*([\d.]+)\s*(KB|MB|GB|TB)', caseSensitive: false)
        .firstMatch(s);
    if (m == null) return 0;
    final n = double.tryParse(m.group(1)!) ?? 0;
    final unit = m.group(2)!.toUpperCase();
    final mult = switch (unit) {
      'KB' => 1024,
      'MB' => 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      'TB' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    return (n * mult).round();
  }

  /// Pull the quant suffix off a stem like `"parakeet-tdt-0.6b-v3-q4_k"`.
  String _inferQuant(String stem) {
    final m = RegExp(r'-(q[0-9][a-z_0-9]*|f16|f32|bf16)$').firstMatch(stem);
    return m == null ? 'f16' : m.group(1)!;
  }

  /// Best-effort mapping from CrispASR backend id → catalog [ModelKind].
  /// Falls back to ASR for unknown backends so they still show up in the
  /// default Model Management view.
  ModelKind _kindForBackend(String backend) {
    const tts = {
      'vibevoice-tts',
      'qwen3-tts',
      'kokoro',
      'orpheus',
      'chatterbox',
      'indextts',
    };
    const punc = {'firered-punc', 'fullstop-punc'};
    const diarize = {'pyannote'};
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

  /// Derive ISO 639-1 language codes for a voicepack file from its
  /// naming convention. Different TTS families use different schemes:
  ///   * Kokoro: a single-letter prefix on the voice id —
  ///     `af_heart` → English (a/b), `df_eva` → German (d),
  ///     `ef_dora` → Spanish (e), `ff_siwis` → French (f),
  ///     `if_*` / `im_*` → Italian (i), `jf_*` / `jm_*` → Japanese
  ///     (j), `pf_*` / `pm_*` → Portuguese (p), `zf_*` / `zm_*` →
  ///     Mandarin (z), `hf_*` / `hm_*` → Hindi (h). Second char is
  ///     gender (f/m), not a language hint.
  ///   * VibeVoice: voice ids embed the language code explicitly —
  ///     `de-Spk1_woman`, `en-Emma_woman`, `fr-Spk1_woman`. Two-
  ///     letter prefix matches ISO 639-1 directly.
  /// Returns `[]` when the scheme doesn't recognise the prefix —
  /// the caller falls back to the BackendRepo's defaultLanguages.
  static List<String> _voicepackLanguages(BackendRepo repo, String voiceId) {
    // VibeVoice convention: `<iso>-<...>`.
    if (repo.backend == 'vibevoice-tts') {
      final m = RegExp(r'^([a-z]{2})-').firstMatch(voiceId);
      if (m != null) return [m.group(1)!];
    }
    // Kokoro convention: first character maps to a language.
    if (repo.backend == 'kokoro' && voiceId.isNotEmpty) {
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
      if (code != null) return [code];
    }
    return const [];
  }

  Future<List<ModelDefinition>> _probeRepo(BackendRepo repo) async {
    final headers = <String, dynamic>{};
    final token = hfToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    // `?blobs=true` surfaces per-file sizes in a stable shape.
    final url = 'https://huggingface.co/api/models/${repo.repoId}?blobs=true';
    final resp =
        await _dio.get<dynamic>(url, options: Options(headers: headers));
    if (resp.data is! Map) return const [];
    final siblings = ((resp.data as Map)['siblings'] as List?) ?? const [];

    final out = <ModelDefinition>[];
    final voicepackPrefix = repo.voicepackBaseName == null
        ? null
        : '${repo.voicepackBaseName}-';
    for (final raw in siblings) {
      if (raw is! Map) continue;
      final fname = raw['rfilename'] as String? ?? '';
      if (!fname.endsWith(repo.extension)) continue;
      final stem = fname.substring(0, fname.length - repo.extension.length);
      final sizeBytes = (raw['size'] as num?)?.toInt() ?? 0;

      // Voicepack file? Stamp as ModelKind.voice, tag with the repo's
      // backend so the synthesize screen's `m.backend == modelDef.backend`
      // filter still groups them under the right main model. The
      // Models-screen language filter also wants per-voicepack
      // language tags so e.g. picking "Deutsch" shows kokoro's
      // German voicepacks (df_eva, dm_bernd, df_victoria, dm_martin)
      // without surfacing every English af_*.
      if (voicepackPrefix != null && stem.startsWith(voicepackPrefix)) {
        final voiceId = stem.substring(voicepackPrefix.length);
        final modelNameKey = '${repo.voicepackBaseName}-$voiceId';
        final voiceLangs = _voicepackLanguages(repo, voiceId);
        out.add(ModelDefinition(
          name: modelNameKey,
          displayName: '${repo.displayPrefix} voice — $voiceId',
          fileName: fname,
          url: 'https://huggingface.co/${repo.repoId}/resolve/main/$fname',
          sizeBytes: sizeBytes,
          checksum: '',
          description:
              '${repo.displayPrefix} voicepack — ${_formatSize(sizeBytes)}',
          quantization: 'f16',
          backend: repo.backend,
          kind: ModelKind.voice,
          languages: voiceLangs.isEmpty ? repo.defaultLanguages : voiceLangs,
        ));
        continue;
      }

      // Main-model variant? Skip when this is a voicepack-only repo
      // (baseName left empty).
      if (repo.baseName.isEmpty) continue;
      String? quant;
      String modelNameKey;
      if (stem == repo.baseName) {
        quant = 'f16';
        modelNameKey = '${repo.baseName}-f16';
      } else if (stem.startsWith('${repo.baseName}-')) {
        quant = stem.substring(repo.baseName.length + 1);
        modelNameKey = '${repo.baseName}-$quant';
      } else {
        // Skip files that don't follow the expected naming convention.
        continue;
      }
      out.add(ModelDefinition(
        name: modelNameKey,
        displayName: '${repo.displayPrefix} ($quant)',
        fileName: fname,
        url: 'https://huggingface.co/${repo.repoId}/resolve/main/$fname',
        sizeBytes: sizeBytes,
        checksum: '',
        description: '${repo.description} — ${_formatSize(sizeBytes)}',
        quantization: quant,
        backend: repo.backend,
        kind: repo.kind,
        companions: repo.defaultCompanions,
        languages: repo.defaultLanguages,
      ));
    }
    return out;
  }

  /// Whether the user has disabled SHA-1 checksum validation for downloads.
  bool get skipChecksum => _settingsService.skipChecksum;

  /// Hugging Face API token for gated/private repositories.
  String? get hfToken => _settingsService.hfToken;
  set hfToken(String? value) {
    _settingsService.hfToken = value ?? '';
  }

  /// Download a Whisper.cpp model with comprehensive error handling
  Future<bool> downloadWhisperCppModel(
    String modelName, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
  }) async {
    await initialize();

    final modelDef = lookupDefinition(modelName);
    if (modelDef == null) {
      throw ModelException('Unknown Whisper.cpp model: $modelName');
    }

    final modelDir = whisperCppDir();
    final localPath = path.join(modelDir, modelDef.fileName);
    final tempPath = '$localPath.tmp';

    // Check if already downloaded and valid
    if (await _isModelDownloaded(localPath, modelDef)) {
      onProgress?.call(1.0);
      onStatusChange?.call('Model already downloaded');
      return true;
    }

    // Check if download is already in progress
    if (_activeDowloads.containsKey(modelName)) {
      throw ModelException('Download already in progress for $modelName');
    }

    final cancelToken = CancelToken();
    _activeDowloads[modelName] = cancelToken;

    try {
      onStatusChange?.call('Checking available space...');

      // Free-space precheck. `_getAvailableSpace` probes the real
      // filesystem (statvfs on POSIX, GetDiskFreeSpaceExW on Windows)
      // and returns -1 when the platform isn't covered — treat that
      // as "skip the check, let the actual download surface the OS
      // error if we genuinely run out." We don't multiply by 1.2 any
      // more either: the old "* 1.2" buffer over a 5 GB hardcoded
      // ceiling false-positived every model >= 4.2 GB (issue #8).
      // Compare against the raw byte count + a fixed 256 MB headroom
      // so a partially-resumed download still has room to fit a tail
      // chunk + checksum verify.
      final freeSpace = await _getAvailableSpace();
      if (freeSpace >= 0) {
        final needed = modelDef.sizeBytes + 256 * 1024 * 1024;
        if (freeSpace < needed) {
          throw ModelException(
              'Insufficient storage space. Need ${_formatSize(modelDef.sizeBytes)}, '
              'have ${_formatSize(freeSpace)}');
        }
      }

      onStatusChange?.call('Starting download...');
      onProgress?.call(0.0);

      final dlDone =
          Log.instance.stopwatch('model', msg: 'download done', fields: {
        'name': modelName,
        'url': modelDef.url,
        'expected_bytes': modelDef.sizeBytes,
        'backend': modelDef.backend,
        'quant': modelDef.quantization,
        'target': tempPath,
      });
      Log.instance.i('model', 'download start', fields: {
        'name': modelName,
        'url': modelDef.url,
        'expected_bytes': modelDef.sizeBytes,
        'backend': modelDef.backend,
        'quant': modelDef.quantization,
      });

      // Download with resume capability
      try {
        await _downloadWithResume(
          modelDef.url,
          tempPath,
          expectedSize: modelDef.sizeBytes,
          onProgress: onProgress,
          onStatusChange: onStatusChange,
          cancelToken: cancelToken,
        );
        int realBytes = 0;
        try {
          realBytes = await File(tempPath).length();
        } catch (_) {}
        dlDone(extra: {'actual_bytes': realBytes});
      } catch (e) {
        dlDone(error: e);
        rethrow;
      }

      onStatusChange?.call('Verifying download...');
      onProgress?.call(0.95);

      // Verify download
      if (modelDef.checksum.isNotEmpty && !skipChecksum) {
        final isValid = await _verifyChecksum(tempPath, modelDef.checksum);
        if (!isValid) {
          await File(tempPath).delete();
          Log.instance.w('model', 'Checksum mismatch for $modelName');
          throw const ModelException(
              'Download verification failed. File may be corrupted. '
              'Enable "Skip checksum verification" in Settings → Debugging to bypass.');
        }
      } else if (skipChecksum) {
        Log.instance
            .i('model', 'Skipping checksum for $modelName (user override)');
      }

      // Move temp file to final location
      await File(tempPath).rename(localPath);

      // CoreML companion fetch: Whisper backends auto-load a sibling
      // ggml-MODEL-encoder.mlmodelc directory when CrispASR was built
      // with -DCRISPASR_COREML=ON. The companion lives on HF as a zip
      // alongside the .bin; download + unzip if available. Best-effort
      // — failures are logged but don't fail the main download (user
      // still gets the working .bin, just without ANE acceleration).
      // iOS gets the same treatment because the Apple Neural Engine on
      // every modern iPhone is the entire point of the CoreML build.
      if (modelDef.backend == 'whisper' &&
          modelDef.fileName.endsWith('.bin') &&
          (Platform.isMacOS || Platform.isIOS)) {
        await _maybeFetchCoreMLCompanion(modelDef, modelDir);
      }

      onProgress?.call(1.0);
      onStatusChange?.call('Download complete');
      return true;
    } catch (e) {
      // Cleanup on failure
      await _cleanupTempFile(tempPath);

      if (e is DioException) {
        final resp = e.response;
        Log.instance.e('model', 'DioException during download: ${e.type}');
        if (resp != null) {
          Log.instance.e(
              'model', 'HTTP ${resp.statusCode} for ${e.requestOptions.uri}');
          Log.instance.e('model', 'Headers: ${resp.headers}');
          Log.instance.e('model', 'Body: ${resp.data}');
        } else {
          Log.instance.e('model', 'No response for ${e.requestOptions.uri}');
        }

        if (e.type == DioExceptionType.cancel) {
          throw const ModelException('Download cancelled');
        } else if (e.type == DioExceptionType.connectionTimeout) {
          throw const ModelException(
              'Download timeout. Please check your internet connection.');
        } else if (e.response?.statusCode == 404) {
          throw const ModelException('Model not found on server');
        } else if (e.response?.statusCode == 401) {
          throw const ModelException(
              'Authentication required (401). This model repository is private or gated.');
        } else {
          throw ModelException('Download failed: ${e.message}');
        }
      }

      throw ModelException('Failed to download model: $e');
    } finally {
      _activeDowloads.remove(modelName);
    }
  }

  /// Cancel an ongoing download
  Future<void> cancelDownload(String modelName, {ModelType? modelType}) async {
    final cancelToken = _activeDowloads[modelName];
    if (cancelToken != null) {
      cancelToken.cancel('Download cancelled by user');
      _activeDowloads.remove(modelName);
    }
  }

  /// Download with resume capability and comprehensive error handling
  Future<void> _downloadWithResume(
    String url,
    String savePath, {
    required int expectedSize,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
    CancelToken? cancelToken,
  }) async {
    final file = File(savePath);
    int downloadedBytes = 0;

    // Check if partial download exists
    if (await file.exists()) {
      downloadedBytes = await file.length();
      onStatusChange?.call('Resuming download...');
    }

    // Set range header for resume
    final headers = <String, dynamic>{
      'Accept': '*/*',
      'Accept-Encoding': 'identity', // Disable compression for resume
    };

    if (downloadedBytes > 0 && downloadedBytes < expectedSize) {
      headers['Range'] = 'bytes=$downloadedBytes-';
    }

    final token = hfToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    Log.instance.d('model', 'Request headers: $headers');

    int lastProgressUpdate = DateTime.now().millisecondsSinceEpoch;

    await _dio.download(
      url,
      savePath,
      options: Options(headers: headers),
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        final now = DateTime.now().millisecondsSinceEpoch;

        // Throttle progress updates to ~4 Hz so a multi-GB download
        // doesn't stutter the UI thread with thousands of rebuilds.
        if (now - lastProgressUpdate < 250) return;
        lastProgressUpdate = now;

        final totalBytes = downloadedBytes + received;
        final progress =
            total > 0 ? totalBytes / expectedSize : totalBytes / expectedSize;

        onProgress?.call(progress.clamp(0.0, 1.0));

        // Update status periodically
        if (totalBytes % (1024 * 1024) < 100 * 1024) {
          // Every MB
          final downloadedMB = totalBytes / (1024 * 1024);
          final totalMB = expectedSize / (1024 * 1024);
          final speed = _calculateDownloadSpeed(totalBytes, DateTime.now());
          onStatusChange?.call(
              'Downloaded ${downloadedMB.toStringAsFixed(1)} MB of ${totalMB.toStringAsFixed(1)} MB ($speed)');
        }
      },
    );

    // Verify final file size. Hardcoded catalog entries rounded to the
    // nearest MB so we tolerate up to 5% (or 2 MB, whichever larger)
    // undershoot before declaring the download incomplete — Dio already
    // bubbles up real HTTP errors, so at this point a non-zero length
    // file is almost always a complete download that just disagrees
    // with our estimate.
    final finalSize = await file.length();
    if (expectedSize > 0 && finalSize < expectedSize) {
      final diff = expectedSize - finalSize;
      final tolerance = (expectedSize * 0.05).ceil();
      final absTolerance =
          tolerance > 2 * 1024 * 1024 ? tolerance : 2 * 1024 * 1024;
      if (diff > absTolerance) {
        await file.delete();
        throw ModelException(
          'Download incomplete. Expected at least $expectedSize bytes, got $finalSize bytes',
        );
      }
      Log.instance.w(
        'model',
        'Download finished at $finalSize bytes, expected $expectedSize '
            '(diff ${_formatSize(diff)}); accepting within tolerance.',
      );
    }
  }

  DateTime? _speedStart;
  final int _speedStartBytes = 0;

  String _calculateDownloadSpeed(int bytesDownloaded, DateTime currentTime) {
    _speedStart ??= currentTime;

    final elapsed = currentTime.difference(_speedStart!).inSeconds;
    if (elapsed <= 0) return '';

    final speed = (bytesDownloaded - _speedStartBytes) / elapsed;
    if (speed < 1024) {
      return '${speed.toStringAsFixed(0)} B/s';
    } else if (speed < 1024 * 1024) {
      return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  /// Verify file checksum using SHA-1
  Future<bool> _verifyChecksum(String filePath, String expectedChecksum) async {
    if (expectedChecksum.isEmpty) return true;

    final file = File(filePath);
    if (!await file.exists()) return false;

    // Use isolate for CPU-intensive checksum calculation
    final result = await Isolate.run(() async {
      final bytes = await File(filePath).readAsBytes();
      final digest = sha1.convert(bytes);
      return digest.toString();
    });

    return result.toLowerCase() == expectedChecksum.toLowerCase();
  }

  /// Get model path if downloaded and valid
  Future<String?> getWhisperCppModelPath(String modelName) async {
    await initialize();

    final modelDef = lookupDefinition(modelName);
    if (modelDef == null) return null;

    final localPath = path.join(whisperCppDir(), modelDef.fileName);

    if (await _isModelDownloaded(localPath, modelDef)) {
      return localPath;
    }

    return null;
  }

  /// Delete a model with proper cleanup
  Future<bool> deleteModel(String modelName, {ModelType? modelType}) async {
    await initialize();

    // Cancel any ongoing downloads first.
    await cancelDownload(modelName, modelType: modelType);

    final whisperPath = await getWhisperCppModelPath(modelName);
    if (whisperPath != null) {
      await File(whisperPath).delete();
      return true;
    }

    return false;
  }

  /// Per-backend disk-usage breakdown for the Storage screen. Walks
  /// the resolved models directory once and groups files by their
  /// catalogued backend. Files that don't match any catalog entry
  /// (loose downloads, .mlmodelc bundles, leftover .tmp) are bucketed
  /// under "(other)" so users can see them too.
  Future<List<BackendStorage>> getStorageByBackend() async {
    await initialize();
    final dir = Directory(whisperCppDir());
    if (!await dir.exists()) return const [];
    return groupDirByBackend(dir, _buildFilenameBackendMap());
  }

  /// Pure file-walk + grouping logic, factored out of
  /// [getStorageByBackend] so it can be tested with a temp dir +
  /// fake filenames without spinning up path_provider, an FFI
  /// session, or any of the catalog setup. The returned list is
  /// sorted by descending byte count.
  ///
  /// `byFilename` maps catalog filename → backend label. Anything not
  /// in the map lands in the `(other)` bucket. Trailing `.tmp` is
  /// stripped before lookup so an in-progress download still groups
  /// with its target backend.
  static Future<List<BackendStorage>> groupDirByBackend(
    Directory dir,
    Map<String, String> byFilename,
  ) async {
    final groups = <String, _BackendBytes>{};
    await for (final ent in dir.list(recursive: true)) {
      if (ent is! File) continue;
      final base = path.basename(ent.path);
      final logical = base.endsWith('.tmp')
          ? base.substring(0, base.length - 4)
          : base;
      final backend = byFilename[logical] ?? '(other)';
      int sz;
      try {
        sz = await ent.length();
      } catch (_) {
        sz = 0;
      }
      final g = groups.putIfAbsent(backend, () => _BackendBytes());
      g.bytes += sz;
      g.count++;
    }
    return groups.entries
        .map((e) => BackendStorage(
              backend: e.key,
              bytes: e.value.bytes,
              fileCount: e.value.count,
            ))
        .toList()
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
  }

  Map<String, String> _buildFilenameBackendMap() {
    final byFilename = <String, String>{};
    final allDefs = <ModelDefinition>[
      ...bakedDiscoveredModels.values,
      ...whisperCppModels.values,
      ...crispasrBackendModels.values,
      ..._ttsVoicepacks.values,
      ..._discoveredModels.values,
    ];
    for (final def in allDefs) {
      byFilename[def.fileName] = def.backend;
    }
    return byFilename;
  }

  /// Delete every file in the resolved models directory whose
  /// catalogued backend matches `backend`. Returns the freed byte
  /// count. Cancels any active downloads for that backend first.
  /// Files in the "(other)" bucket aren't touched here — those are
  /// removed via the per-row delete in Model Management.
  Future<int> deleteBackendModels(String backend) async {
    await initialize();
    final dir = Directory(whisperCppDir());
    if (!await dir.exists()) return 0;
    final freed = await deleteBackendFilesIn(
        dir, _buildFilenameBackendMap(), backend);
    Log.instance.i('storage', 'deleted backend models', fields: {
      'backend': backend,
      'freed_bytes': freed,
    });
    return freed;
  }

  /// Pure deletion logic, factored out of [deleteBackendModels] so
  /// it can be tested with a temp dir. Returns the freed byte count.
  /// Errors per-file are swallowed (logged and skipped) so a stuck
  /// inode doesn't abort the rest of the sweep.
  static Future<int> deleteBackendFilesIn(
    Directory dir,
    Map<String, String> byFilename,
    String backend,
  ) async {
    var freed = 0;
    await for (final ent in dir.list(recursive: true)) {
      if (ent is! File) continue;
      final base = path.basename(ent.path);
      final logical = base.endsWith('.tmp')
          ? base.substring(0, base.length - 4)
          : base;
      final fileBackend = byFilename[logical];
      if (fileBackend != backend) continue;
      try {
        freed += await ent.length();
        await ent.delete();
      } catch (e) {
        Log.instance.w('storage', 'failed to delete ${ent.path}', error: e);
      }
    }
    return freed;
  }

  /// Get total storage used by models
  Future<StorageInfo> getStorageInfo() async {
    await initialize();

    int whisperCppSize = 0;
    final whisperDir = Directory(whisperCppDir());
    if (await whisperDir.exists()) {
      whisperCppSize = await _getDirectorySize(whisperDir.path);
    }

    return StorageInfo(
      whisperCppBytes: whisperCppSize,
      totalBytes: whisperCppSize,
    );
  }

  /// Clear all model cache
  Future<void> clearAllModels() async {
    await initialize();

    // Cancel all downloads first
    for (final entry in _activeDowloads.entries) {
      entry.value.cancel('Clearing all models');
    }
    _activeDowloads.clear();

    final modelsDir = Directory(_modelsDir);
    if (await modelsDir.exists()) {
      await modelsDir.delete(recursive: true);
      await modelsDir.create(recursive: true);

      // Recreate subdirectories
      await Directory(whisperCppDir()).create();
    }
  }

  // Private helper methods

  Future<bool> _isModelDownloaded(
      String localPath, ModelDefinition modelDef) async {
    final file = File(localPath);
    if (!await file.exists()) return false;

    final size = await file.length();

    // Reject only truly suspicious files (empty / near-empty). The
    // hardcoded `sizeBytes` are estimates — frequently off by 30+
    // percent (kokoro listed as 100 MB, real ~135 MB; kokoro voices
    // listed as 1 MB, real ~0.5 MB). The HF probe corrects sizes
    // lazily, so any size-tolerance check that fired BEFORE the
    // probe made downloaded models look "not downloaded yet" on
    // cold launch.
    //
    // We rely on:
    //   * The download path's own 5% / 2 MB integrity check at
    //     download time + atomic rename of the .tmp file. A file
    //     surviving that flow is complete.
    //   * The checksum verification below for models that ship one.
    //
    // So here: just guard against zero-length file (a corrupt
    // rename or interrupted download where the .tmp got promoted
    // anyway).
    if (size < 256) return false;

    // For critical models, verify checksum — unless the user has explicitly
    // opted into skipping verification.
    if (!skipChecksum &&
        modelDef.checksum.isNotEmpty &&
        modelDef.sizeBytes > 100 * 1024 * 1024) {
      return await _verifyChecksum(localPath, modelDef.checksum);
    }

    return true;
  }

  Future<void> _cleanupTempFile(String tempPath) async {
    try {
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  /// Best-effort download of the CoreML encoder companion for a Whisper
  /// model. URL convention is upstream's
  ///   `ggerganov/whisper.cpp/resolve/main/<basename>-encoder.mlmodelc.zip`
  /// where basename is the .bin filename without the extension. Skips
  /// silently when the zip 404s (most quantised whisper models don't
  /// have one) or when the destination .mlmodelc directory already
  /// exists. Unzips into the same dir as the .bin so libwhisper picks
  /// it up on first transcribe.
  Future<void> _maybeFetchCoreMLCompanion(
      ModelDefinition modelDef, String modelDir) async {
    final stem = modelDef.fileName.endsWith('.bin')
        ? modelDef.fileName.substring(0, modelDef.fileName.length - 4)
        : modelDef.fileName;
    final mlmodelcDir = Directory(path.join(modelDir, '$stem-encoder.mlmodelc'));
    if (await mlmodelcDir.exists()) {
      Log.instance.d('coreml',
          'CoreML companion already present for ${modelDef.name}');
      return;
    }
    final zipUrl =
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$stem-encoder.mlmodelc.zip';
    final zipPath = path.join(modelDir, '$stem-encoder.mlmodelc.zip');
    try {
      Log.instance.i('coreml', 'fetching CoreML companion',
          fields: {'url': zipUrl});
      final resp = await _dio.download(zipUrl, zipPath);
      if (resp.statusCode != 200) {
        Log.instance
            .d('coreml', 'CoreML companion not on HF (status ${resp.statusCode})');
        await File(zipPath).delete().catchError((_) => File(zipPath));
        return;
      }
      // Unzip alongside the .bin via the existing `archive` dep.
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        final outPath = path.join(modelDir, f.name);
        if (f.isFile) {
          await File(outPath).create(recursive: true);
          await File(outPath).writeAsBytes(f.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      await File(zipPath).delete();
      Log.instance.i('coreml', 'CoreML companion installed',
          fields: {'dir': mlmodelcDir.path});
    } catch (e, st) {
      // 404 / network blip / decompression failure all funnel here.
      // CoreML is an optional accelerator; whisper falls back to ggml
      // automatically when the .mlmodelc isn't present.
      Log.instance.d('coreml', 'CoreML companion fetch skipped',
          error: e, stack: st);
      try {
        await File(zipPath).delete();
      } catch (_) {/* ignore */}
    }
  }

  Future<int> _getAvailableSpace() async {
    // Real free-space probe — statvfs on POSIX, GetDiskFreeSpaceExW
    // on Windows. Returns -1 when the platform-specific call fails
    // or isn't available; the caller treats that as "skip the
    // precheck and let the actual download fail if we run out of
    // disk." Fixes issue #8: the previous hardcoded 5 GB constant
    // false-positived every model >= 4.2 GB.
    try {
      final dir = whisperCppDir();
      return getAvailableDiskSpace(dir);
    } catch (e, st) {
      Log.instance.w('model', 'free-space probe threw', error: e, stack: st);
      return -1;
    }
  }

  Future<int> _getDirectorySize(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return 0;

    int totalSize = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          totalSize += stat.size;
        } catch (e) {
          // Skip files that can't be accessed
        }
      }
    }

    return totalSize;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

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
  });

  /// True when this row should appear under the given language
  /// filter. Untagged + multilingual rows pass for any picked code.
  /// `''` (the "Any" sentinel) always passes too. Used by the
  /// Model Manager filter row.
  bool matchesLanguage(String code) {
    if (code.isEmpty) return true;
    if (languages.isEmpty) return true;
    if (languages.contains('*')) return true;
    return languages.contains(code.toLowerCase());
  }
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
  });

  /// Same filter helper as [ModelDefinition.matchesLanguage] — kept on
  /// the UI-facing type so the Model Manager doesn't have to round-trip
  /// to the ModelService just to filter a list it already holds.
  bool matchesLanguage(String code) {
    if (code.isEmpty) return true;
    if (languages.isEmpty) return true;
    if (languages.contains('*')) return true;
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

class _BackendBytes {
  int bytes = 0;
  int count = 0;
}

class ModelException implements Exception {
  final String message;
  const ModelException(this.message);

  @override
  String toString() => 'ModelException: $message';
}

// Retry interceptor for Dio
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final RetryOptions options;

  RetryInterceptor({required this.dio, required this.options});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = RetryOptions.fromExtra(err.requestOptions) ?? options;

    if (extra.retries <= 0) {
      return handler.next(err);
    }

    if (err.type == DioExceptionType.cancel) {
      return handler.next(err);
    }

    await Future<void>.delayed(extra.retryInterval);

    final requestOptions = err.requestOptions;
    requestOptions.extra[RetryOptions.extraKey] =
        extra.copyWith(retries: extra.retries - 1);

    try {
      final response = await dio.fetch<dynamic>(requestOptions);
      return handler.resolve(response);
    } catch (e) {
      return handler.next(err);
    }
  }
}

class RetryOptions {
  static const String extraKey = 'retry_options';

  final int retries;
  final Duration retryInterval;

  const RetryOptions({
    required this.retries,
    required this.retryInterval,
  });

  static RetryOptions? fromExtra(RequestOptions request) {
    return request.extra[extraKey] as RetryOptions?;
  }

  RetryOptions copyWith({int? retries, Duration? retryInterval}) {
    return RetryOptions(
      retries: retries ?? this.retries,
      retryInterval: retryInterval ?? this.retryInterval,
    );
  }
}
