// Live proof for issue #30 — a Cohere ASR GGUF linked via "Add from
// HuggingFace repo" was mis-routed to the whisper pipeline and crashed
// ("Model uses the whisper backend ... built with {}"). The fix reads the
// GGUF architecture metadata at load time and routes to the real backend.
//
// This exercises the exact fix mechanism against the real
// cohere-transcribe-arabic-q4_k.gguf (the model from the bug report):
//   1. detectBackendFromGguf() resolves the file to the cohere backend,
//      NOT whisper — this is what CrispasrEngine.loadModel now calls to
//      correct an `auto`/mis-tagged entry.
//   2. Opening a session on the detected backend transcribes without
//      throwing the whisper-backend error, and the session reports a
//      cohere-family backend (i.e. it did NOT fall into the whisper arm).
//
// Tagged `slow`: loads a ~1.4 GB GGUF. Self-skips unless opted in
// (CRISPASR_LIB set) and the model is under $CRISPASR_MODELS_DIR
// (run: CRISPASR_MODELS_DIR=/Volumes/backups/ai/crispasr-gguf
//        scripts/run_live_tests.sh test/issue30_cohere_autodetect_live_test.dart).

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
// The CORRECTED detect helper the engine now uses (the `crispasr` package's
// own detectBackendFromGguf has an inverted rc check — see
// lib/native/crispasr_detect_native.dart).
import 'package:crisper_weaver/native/crispasr_detect_import.dart'
    as crispasr_detect;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  final skip = CrispModels.skipReason(models: ['cohere_arabic']);

  group('#30 Cohere GGUF auto-detect (live)', () {
    test('detectBackendFromGguf routes the Cohere GGUF to cohere, not whisper',
        () {
      final modelPath = CrispModels.model('cohere_arabic')!;
      final detected = crispasr_detect.detectBackendFromGguf(modelPath, libPath: lib);

      // The core of the fix: the GGUF's architecture metadata resolves a
      // concrete, non-whisper backend. Without this, the HF-repo `auto`
      // path left the model tagged `whisper` and it crashed on load.
      expect(detected, isNotNull,
          reason: 'detectBackendFromGguf returned null — the fix relies on '
              'it recovering the backend from GGUF metadata');
      expect(detected, isNot('whisper'),
          reason: 'a Cohere GGUF must not resolve to the whisper backend (#30)');
      expect(detected, contains('cohere'),
          reason: 'expected a cohere-family backend, got "$detected"');
    }, skip: skip);

    test('opens on the detected backend + transcribes without the whisper crash',
        () {
      final modelPath = CrispModels.model('cohere_arabic')!;
      final detected =
          crispasr_detect.detectBackendFromGguf(modelPath, libPath: lib) ?? 'cohere';

      // Mirror CrispasrEngine.loadModel: open the session on the
      // GGUF-resolved backend. Pre-fix this ran through the whisper arm
      // and threw; now it opens the cohere arm cleanly.
      final session = crispasr.CrispasrSession.open(
        modelPath,
        backend: detected,
        libPath: lib,
      );
      addTearDown(session.close);

      expect(session.backend, contains('cohere'),
          reason: 'session opened on the wrong dispatch arm (#30 regression)');

      // Transcribe the bundled English clip. The Arabic model won't
      // produce a clean English transcript, but the point of #30 is
      // routing: the call must complete via the cohere pipeline without
      // throwing the "Model uses the whisper backend" error, and return
      // a real result list.
      final audio = crispasr.decodeAudioFile(
        CrispModels.fixture('jfk.wav'),
        libPath: lib,
      );
      final segments = session.transcribe(audio.samples);
      expect(segments, isA<List<crispasr.SessionSegment>>(),
          reason: 'transcribe must return cleanly through the cohere arm');
    }, skip: skip);
  });
}
