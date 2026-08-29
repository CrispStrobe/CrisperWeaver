// Shared live-test model locator (PLAN §9.1).
//
// One place that resolves (a) the libcrispasr dylib and (b) the
// smallest `q4_k` model per feature family on disk, so every live
// test can light up without each file re-implementing `_resolveLibPath`
// and without the owner exporting 30 env vars by hand.
//
// Resolution order for both lib and models:
//   1. explicit env override (CRISPASR_LIB, CRISPASR_TEST_<KEY>_MODEL)
//   2. conventional on-disk location
//        - lib:    ../CrispASR/build*/src/lib{crispasr,whisper}.dylib
//        - models: $CRISPASR_MODELS_DIR (default /Volumes/backups/ai/crispasr)
//   3. null  →  the caller passes the null to `skipReason(...)` and the
//               test self-skips (never fails) on machines without the
//               artefacts. Same contract as the existing live tests.
//
// Constraint baked in (owner): only `q4_k` quants are mapped, and
// nothing here points at a model that must be downloaded — every
// filename below already exists under the models dir on the dev box.
library;

import 'dart:io';

/// Logical model key → on-disk filename (smallest q4_k per family).
/// Every entry is verified present under the default models dir.
const Map<String, String> _modelFiles = {
  // ASR
  'whisper_tiny': 'ggml-tiny.bin',
  // #30 repro — the Cohere Arabic ASR GGUF that mis-routed to whisper.
  // Lives under the `crispasr-gguf` models dir; self-skips elsewhere.
  'cohere_arabic': 'cohere-transcribe-arabic-q4_k.gguf',
  'moonshine_tiny': 'moonshine-tiny-q4_k.gguf',
  'sensevoice': 'sensevoice-small-q4_k.gguf',
  'parakeet_110m': 'parakeet-tdt_ctc-110m-q4_k.gguf',
  // v0.8.10 backend catch-up — NVIDIA Nemotron 3.5 streaming ASR.
  'nemotron': 'nemotron-3.5-asr-streaming-0.6b-q4_k.gguf',
  'fastconformer_ctc': 'stt-en-fastconformer-ctc-large-q4_k.gguf',
  'wav2vec2': 'wav2vec2-xlsr-en-q4_k.gguf',
  'paraformer_zh': 'paraformer-zh-q4_k.gguf',
  // Language ID
  'glotlid': 'lid-glotlid-q4_k.gguf',
  'cld3': 'cld3-f32.gguf',
  // Audio LID — the Silero 95-language classifier the app's LidService
  // drives through `LidMethod.silero`. q8_0 is 13 MB, so unlike the
  // whisper-encoder LID path it needs no multilingual ggml-*.bin.
  // Env override: CRISPASR_TEST_SILERO_LID_MODEL.
  'silero_lid': 'silero-lid-95-q8_0.gguf',
  // VAD
  'whisper_vad': 'whisper-vad-asmr-q4_k.gguf',
  'marblenet_vad': 'marblenet-vad.gguf',
  'firered_vad': 'firered-vad.gguf',
  'silero_vad': 'ggml-silero-v5.1.2.bin',
  // Diarization / speaker
  'pyannote': 'pyannote-seg-3.0.gguf',
  'titanet': 'titanet-large.gguf',
  // Alignment
  'canary_aligner': 'canary-ctc-aligner-q4_k.gguf',
  // Punctuation
  'fireredpunc': 'fireredpunc-q4_k.gguf',
  // Translation. madlad is the q4_k, owner-constraint-compliant choice
  // (already on disk, not downloaded); m2m100 is a lighter q8_0 fallback.
  'madlad': 'madlad400-3b-mt-q4_k.gguf',
  'm2m100': 'm2m100-418m-q8_0.gguf',
  'wmt21_en_x': 'wmt21-dense-24-wide-en-x-q4_k.gguf',
  // TTS (chatterbox turbo: both parts are q4_k and <500 MB)
  'chatterbox_t3': 'chatterbox-t3-q4_k-regen.gguf',
  'chatterbox_s3gen': 'chatterbox-turbo-s3gen-q4_k-regen.gguf',
  // Chat LLM (heavy — lower priority)
  'gemma4_e2b': 'gemma4-e2b-it-q4_k.gguf',
};

/// Resolves the libcrispasr / libwhisper dylib, or null if absent.
class CrispModels {
  CrispModels._();

  /// The models directory. Override with `CRISPASR_MODELS_DIR`.
  static String get modelsDir {
    final env = Platform.environment['CRISPASR_MODELS_DIR'];
    if (env != null && env.isNotEmpty) return env;
    return '/Volumes/backups/ai/crispasr';
  }

  /// Absolute path to the dylib, or null if not found.
  static String? get lib {
    final env = Platform.environment['CRISPASR_LIB'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return File(env).absolute.path;
    }
    const candidates = [
      '../CrispASR/build/src/libcrispasr.dylib',
      '../CrispASR/build-flutter-bundle/src/libcrispasr.dylib',
      '../CrispASR/build/src/libwhisper.dylib',
      '../CrispASR/build-flutter-bundle/src/libwhisper.dylib',
      '../CrispASR/build-vk/src/libcrispasr.dylib',
      // Linux / Windows fallbacks
      '../CrispASR/build/src/libcrispasr.so',
      '../CrispASR/build/src/crispasr.dll',
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f.absolute.path;
    }
    return null;
  }

  /// Absolute path to the model for [key], or null if not found.
  ///
  /// Honours `CRISPASR_TEST_<KEY>_MODEL` (KEY upper-cased) first, then
  /// `$modelsDir/<mapped filename>`.
  static String? model(String key) {
    final envName = 'CRISPASR_TEST_${key.toUpperCase()}_MODEL';
    final env = Platform.environment[envName];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return File(env).absolute.path;
    }
    final file = _modelFiles[key];
    if (file == null) return null;
    final f = File('$modelsDir/$file');
    return f.existsSync() ? f.absolute.path : null;
  }

  /// A bundled audio fixture shipped in the repo (always present).
  /// [name] e.g. 'jfk-2s.wav', 'jfk.wav', 'jfk.mp3'.
  static String fixture(String name) => File('test/$name').absolute.path;

  /// Bundled Silero VAD asset (always present in the repo) — lets the
  /// VAD exemplar run without the external models volume.
  static String get sileroAsset =>
      File('assets/vad/silero-v6.2.0-ggml.bin').absolute.path;

  /// Whether the live/slow suite is opted in. These tests load real
  /// GGUFs (and can take many minutes), so — matching the project's
  /// `slow`-tag convention — they self-skip unless explicitly enabled:
  /// set `CRISPASR_LIB` (e.g. via `scripts/run_live_tests.sh`) or
  /// `RUN_LIVE_TESTS`. Otherwise a default `flutter test` (the pre-push
  /// gate) would run them just because the models happen to be on disk.
  static bool get enabled =>
      (Platform.environment['CRISPASR_LIB']?.isNotEmpty ?? false) ||
      (Platform.environment['RUN_LIVE_TESTS']?.isNotEmpty ?? false);

  /// Returns a skip reason string when the suite isn't opted in, or the
  /// dylib / any required model is missing; null when everything needed
  /// is present.
  ///
  /// Usage:
  ///   final skip = CrispModels.skipReason(models: ['glotlid']);
  ///   test('...', () { ... }, skip: skip);
  static String? skipReason({List<String> models = const []}) {
    if (!enabled) {
      return 'live/slow tests are opt-in — set CRISPASR_LIB or '
          'RUN_LIVE_TESTS (see scripts/run_live_tests.sh).';
    }
    if (lib == null) {
      return 'libcrispasr dylib not found — build CrispASR or set CRISPASR_LIB.';
    }
    final missing = <String>[];
    for (final key in models) {
      if (model(key) == null) missing.add(_modelFiles[key] ?? key);
    }
    if (missing.isNotEmpty) {
      return 'model(s) not found under $modelsDir: ${missing.join(', ')} '
          '(set CRISPASR_MODELS_DIR or CRISPASR_TEST_<KEY>_MODEL).';
    }
    return null;
  }
}
