// Live ASR test for the non-Whisper backends (PLAN §9.1 family).
//
// Proves the alternative (non-whisper) ASR backends actually transcribe
// the bundled jfk.wav clip end-to-end through the unified session API —
// the same `CrispasrSession.transcribe(pcm)` path CrispASREngine drives
// for every non-whisper model (lib/engines/crispasr_engine.dart, the
// `_runSessionTranscription` arm at ~line 1497). Each backend opens its
// own session on its own q4_k model and self-skips when that model
// isn't on the dev box's models volume, so a vanilla checkout stays
// green without gigabytes of fixtures.
//
// Tagged `slow`: these load real GGUFs and run a CTC/encoder decode.
// The default `flutter test` skips them; the owner opts in serially via
//   scripts/run_live_tests.sh test/alt_asr_backends_live_test.dart
// (or `flutter test --tags slow`).
//
// HOW BACKENDS ARE OPENED — explicit, NOT auto-detect.
//   CrispasrSession.open(path, backend: <name>, libPath: lib) routes to
//   `crispasr_session_open_explicit` when a non-empty `backend:` is
//   passed, vs `crispasr_session_open` (GGUF-metadata auto-detect) when
//   it's omitted (../CrispASR/flutter/crispasr/lib/src/crispasr.dart, the
//   `CrispasrSession.open` factory: `if (backend != null && backend
//   .isNotEmpty) { ... openExpl(...) } else { ... open(...) }`). We pass
//   the backend explicitly — matching the engine, which always supplies
//   `def.backend` from the catalogue (crispasr_engine.dart loadModel:
//   `CrispasrSession.open(modelPath, backend: def.backend)`). Auto-detect
//   would also work for these archs, but naming the backend keeps the
//   test honest about which dispatch arm it exercises and gives a clean
//   error if the bundled dylib lacks the arm.
//
// SAMPLE RATE: decodeAudioFile returns 16 kHz mono PCM (asserted once
//   below); every one of these backends consumes 16 kHz, so no resample
//   is needed (unlike the TTS→ASR roundtrips in backend_dispatch_test,
//   which resample 24 kHz synth output down to 16 kHz first).
//
// COMPANION CAVEAT: none of these five backends need a companion file.
//   They are single-file CTC / encoder ASR models — their catalogue
//   ModelDefinitions carry no `companions`, so the engine's companion
//   loop (crispasr_engine.dart, the `for (final companion in
//   def.companions)` block) is a no-op for them. Backends that DO need a
//   companion (mimo-asr's tokenizer, the TTS codecs) live in
//   backend_dispatch_test.dart and are gated on extra env vars; they're
//   deliberately out of scope here.

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

/// One non-whisper ASR backend under test: the explicit backend name the
/// dispatcher matches, plus the CrispModels key for its smallest on-disk
/// q4_k model.
class _AsrBackend {
  const _AsrBackend(this.backend, this.modelKey, {this.note});

  /// Explicit backend string passed to CrispasrSession.open(..., backend:).
  /// Matches `def.backend` in lib/services/model_catalog.dart.
  final String backend;

  /// CrispModels key → smallest q4_k file for this backend on disk.
  final String modelKey;

  /// Optional per-backend quirk worth surfacing in the test name.
  final String? note;
}

void main() {
  final lib = CrispModels.lib;
  // Opt-in + dylib gate (per-backend model presence checked below).
  final libSkip = CrispModels.skipReason();

  // The five non-whisper ASR backends that have a small q4_k model mapped
  // in CrispModels and need no companion. Backend strings verified against
  // lib/services/model_catalog.dart:
  //   moonshine-tiny-q4_k      → 'moonshine'         (20 MB)
  //   sensevoice-small-q4_k    → 'sensevoice'        (129 MB)
  //   parakeet-tdt_ctc-110m    → 'parakeet'          (86 MB)
  //   stt-en-fastconformer-ctc → 'fastconformer-ctc' (83 MB)
  //   wav2vec2-xlsr-en-q4_k    → 'wav2vec2'          (212 MB, largest — slowest)
  const backends = <_AsrBackend>[
    _AsrBackend('moonshine', 'moonshine_tiny',
        note: 'tiny encoder-decoder, English'),
    _AsrBackend('sensevoice', 'sensevoice',
        note: 'SenseVoice-small, multilingual CTC'),
    _AsrBackend('parakeet', 'parakeet_110m',
        note: 'NVIDIA Parakeet TDT/CTC 110M, English'),
    _AsrBackend('fastconformer-ctc', 'fastconformer_ctc',
        note: 'NeMo FastConformer CTC, English'),
    _AsrBackend('wav2vec2', 'wav2vec2',
        note: 'wav2vec2/HuBERT XLSR CTC, English'),
    _AsrBackend('nemotron', 'nemotron',
        note: 'NVIDIA Nemotron 3.5 streaming ASR 0.6B (v0.8.10 catch-up)'),
  ];

  // The famous JFK line: "And so, my fellow Americans, ask not what your
  // country can do for you...". Lenient keyword set — small q4_k CTC
  // models routinely mis-spell or drop words, so we require only that the
  // transcript is real text AND contains at least one of these. wav2vec2
  // in particular emits uppercase, no-punctuation output, so we lower-case
  // before matching.
  const jfkKeywords = ['country', 'ask', 'fellow', 'americans'];

  group('alt ASR backends live', () {
    // Decode the fixture once for the whole group. jfk.wav ships in the
    // repo; decodeAudioFile yields 16 kHz mono PCM — exactly what every
    // session backend wants, no resample needed.
    late crispasr.DecodedAudio audio;

    setUpAll(() {
      if (libSkip != null) return;
      audio = crispasr.decodeAudioFile(
        CrispModels.fixture('jfk.wav'),
        libPath: lib,
      );
    });

    test('fixture decodes to 16 kHz mono PCM', () {
      expect(audio.sampleRate, 16000);
      expect(audio.samples.length, greaterThan(16000)); // > 1 s of audio
    }, skip: libSkip);

    for (final b in backends) {
      final label = b.note == null ? b.backend : '${b.backend} (${b.note})';
      test('$label transcribes jfk.wav', () {
        // Per-backend self-skip: only run when this backend's q4_k model
        // is actually on disk. CrispModels.model() honours
        // CRISPASR_TEST_<KEY>_MODEL overrides then the default models dir.
        final modelPath = CrispModels.model(b.modelKey);
        if (modelPath == null) {
          markTestSkipped(
              '${b.backend}: model for "${b.modelKey}" not under '
              '${CrispModels.modelsDir} — skipping (set CRISPASR_MODELS_DIR '
              'or CRISPASR_TEST_${b.modelKey.toUpperCase()}_MODEL).');
          return;
        }

        // Open an explicit-backend session on this model. Each backend gets
        // its own session on its own ASR model (these ARE ASR models, so
        // the "open ctx on tiny whisper" rule from the VAD test does not
        // apply) and we close it in the tearDown below — no leaks.
        final session = crispasr.CrispasrSession.open(
          modelPath,
          backend: b.backend,
          libPath: lib,
        );
        addTearDown(session.close);

        // Sanity: the dispatcher reports the backend we asked for.
        expect(session.backend, b.backend,
            reason: '${b.backend}: session opened on the wrong dispatch arm');

        final segments = session.transcribe(audio.samples);
        final text =
            segments.map((s) => s.text).join(' ').trim().toLowerCase();

        // 1) Real, non-trivial transcript. A working CTC/encoder decode of
        //    ~11 s of clear speech yields well over a handful of chars; an
        //    empty/whitespace result means the backend silently no-op'd.
        expect(text, isNotEmpty,
            reason: '${b.backend}: empty transcript on jfk.wav '
                '(segments=${segments.length})');
        expect(text.length, greaterThan(8),
            reason: '${b.backend}: implausibly short transcript "$text"');

        // 2) At least one plausible JFK keyword survives. Lenient (any one
        //    of several) because small q4_k models mis-spell; printOnFailure
        //    surfaces the actual transcript when the assertion trips.
        printOnFailure('${b.backend} transcript: "$text"');
        final hit = jfkKeywords.any(text.contains);
        expect(hit, isTrue,
            reason: '${b.backend}: transcript "$text" contains none of '
                '$jfkKeywords — likely a broken decode, not just a typo');
      }, skip: libSkip);
    }
  });
}
