// Live language-ID test (PLAN §9.1 exemplar / LID).
//
// Two LID paths exercised, mirroring what the app does:
//
//  1. AUDIO LID via CrispASR.detectLanguage(pcm) — the whisper-encoder
//     language head. This REUSES the already-loaded tiny ASR context
//     (no extra model on disk), exactly like LidService's whisper LID
//     fallback. C entrypoint: crispasr_detect_language(ctx, …) in
//     src/crispasr_c_api.cpp:539. It runs whisper_pcm_to_mel +
//     whisper_encode + whisper_lang_auto_detect over the *open ctx*, so
//     the model passed to the constructor IS the model it uses. Returns
//     the language posterior (>= 0) on success; NEGATIVE error codes
//     mean failure: -1 bad args, -2 mel, -3 encode, -4 auto-detect,
//     -5 lang-str lookup. We open the ctx on the multilingual
//     `ggml-tiny.bin` (NOT tiny.en) so whisper_lang_auto_detect has all
//     languages to choose from.
//
//  2. TEXT LID via detectTextLanguage(text, modelPath) — the in-process
//     text-LID C-ABI. C entrypoint: crispasr_text_detect_language in
//     src/crispasr_c_api.cpp:5084 (wraps text_lid_dispatch over CLD3 /
//     GlotLID). Returns 0 on success with the label written; non-zero
//     means failure: -1 bad args, 1 model-init / predict failure, 2 the
//     label didn't fit the buffer. CLD3 emits ISO 639-1 ("en"); GlotLID
//     emits `xxx_Script` (e.g. "eng_Latn").
//
// IMPORTANT (see PLAN §9.5, same class of bug as the VAD exemplar): the
// CrispASR(modelPath) constructor loads `modelPath` as a *whisper ASR
// context*. We therefore open it on a real ASR model (multilingual tiny)
// and dispose() it in tearDown — never on the GlotLID/CLD3 GGUFs, which
// aren't whisper models. The text-LID path takes its model only as a
// detectTextLanguage() argument and loads/frees its own ctx internally.
//
// Tagged `slow`; self-skips when the dylib / tiny model are absent. The
// text sub-test self-skips (markTestSkipped) when neither GlotLID nor
// CLD3 is on disk.
//
// Run:
//   scripts/run_live_tests.sh test/lid_live_test.dart

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  // ggml-tiny.bin is the *multilingual* tiny model (tiny.en would be
  // English-only and can't run whisper_lang_auto_detect meaningfully).
  final skip = CrispModels.skipReason(models: ['whisper_tiny']);

  group('LID live', () {
    late crispasr.DecodedAudio audio;
    crispasr.CrispASR? cr;

    setUp(() {
      if (skip != null) return;
      // jfk.wav is ~11 s of clear English speech — a sound multilingual
      // LID must pick 'en' with high posterior.
      audio = crispasr.decodeAudioFile(
        CrispModels.fixture('jfk.wav'),
        libPath: lib,
      );
      // Open the context on the multilingual tiny ASR model. detectLanguage
      // reuses THIS ctx — no auxiliary model is loaded for audio LID.
      cr = crispasr.CrispASR(CrispModels.model('whisper_tiny')!, libPath: lib);
    });

    tearDown(() {
      cr?.dispose();
      cr = null;
    });

    test('decodes the fixture to 16 kHz mono PCM', () {
      expect(audio.sampleRate, 16000);
      expect(audio.samples.length, greaterThan(16000)); // > 1 s of audio
    }, skip: skip);

    // AUDIO LID — whisper encoder language head over the open tiny ctx.
    // crispasr_detect_language returns the posterior (>= 0) on success and
    // a NEGATIVE error code on failure (see header comment). LanguageDetection
    // surfaces that as `probability` and `ok` (code non-empty && prob >= 0).
    test('whisper-encoder LID detects English in the JFK clip', () {
      final det = cr!.detectLanguage(audio.samples);
      expect(det.probability, greaterThanOrEqualTo(0.0),
          reason: 'negative probability is a C-side error code '
              '(-2 mel / -3 encode / -4 auto-detect): det=$det');
      expect(det.ok, isTrue, reason: 'LID should succeed: $det');
      expect(det.code, 'en',
          reason: 'JFK clip is English; got $det');
      expect(det.probability, greaterThan(0.3),
          reason: 'top-language posterior should be confident: $det');
    }, skip: skip);

    // TEXT LID — in-process CLD3 / GlotLID over a known English sentence.
    // Self-skips when neither model GGUF is on disk. Accepts any of the
    // label conventions the two models use for English.
    test('text LID detects English via GlotLID or CLD3', () {
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      const sentence =
          'The quick brown fox jumps over the lazy dog near the river bank.';
      const englishLabels = {'en', 'eng', 'eng_Latn', 'en_Latn', '__label__en'};

      // Prefer the tiny CLD3 (855 KB) when present, else GlotLID (234 MB).
      final cld3 = CrispModels.model('cld3');
      final glotlid = CrispModels.model('glotlid');
      final modelPath = cld3 ?? glotlid;
      if (modelPath == null) {
        markTestSkipped('neither cld3-f32.gguf nor lid-glotlid-q4_k.gguf '
            'under ${CrispModels.modelsDir}');
        return;
      }

      final r = crispasr.detectTextLanguage(sentence, modelPath, libPath: lib);
      expect(r, isNotNull,
          reason: 'detectTextLanguage returned null — the loaded lib may '
              'predate crispasr_text_detect_language, or the model failed '
              'to init (C rc=1). model=$modelPath');
      expect(englishLabels.contains(r!.code), isTrue,
          reason: 'expected an English label, got $r (model=$modelPath)');
      expect(r.confidence, greaterThan(0.0),
          reason: 'confidence should be positive on a clean sentence: $r');
    }, skip: skip);
  });
}
