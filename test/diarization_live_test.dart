// Live diarization test (PLAN §9.1 exemplar / §5.26 diarization).
//
// Exercises the pyannote ML diarization path that DiarizationService
// relies on — `crispasr.diarizeSegments(method: pyannote)` →
// `crispasr_diarize_segments_abi` → C `apply_pyannote`, which loads the
// pyannote-seg-3.0 GGUF, runs the segmentation net over the mono PCM,
// and assigns a speaker index to each input time range. Tagged `slow`
// and self-skips when the dylib / tiny / pyannote models are absent.
//
// IMPORTANT — what the diarizer needs as input (verified against the C
// source, src/crispasr_diarize.cpp + src/crispasr_c_api.cpp):
//   The diarizer does NOT segment audio from scratch. It is given a list
//   of pre-existing time ranges (DiarizeSegment t0/t1) plus the mono
//   16 kHz PCM, and it labels each range with a speaker (0/1/2, or -1
//   when a range is pure silence). So we must produce ASR segments
//   first — transcribe jfk.wav with the tiny model (the proven pattern)
//   — then feed those ranges to the diarizer.
//
// Entrypoint semantics (crispasr_c_api.cpp:4932 crispasr_diarize_segments_abi
// → crispasr_diarize.cpp:294 crispasr_diarize_segments, case Pyannote →
// apply_pyannote @183): returns 0/true on success; the ONLY failure
// (returns 1/false) is the pyannote GGUF failing to load. On success the
// per-segment speaker index is read back into each DiarizeSegment.speaker.
// pyannote-seg-3.0's 7 output classes resolve to up to 3 speakers
// (0/1/2); a silence-dominated range stays -1.
//
// IMPORTANT (see PLAN §9.5, mirrored from the VAD exemplar): the
// CrispASR(modelPath) constructor loads `modelPath` as a *whisper ASR
// context*, so we open it on a real ASR model (tiny) and pass the
// pyannote GGUF only as diarizeSegments()'s `pyannoteModelPath` arg —
// never as the ctx model. dispose() in tearDown.
//
// jfk.wav is a single-speaker clip, so the realistic assertion is:
// diarization runs without error and returns sane speaker-labelled
// ranges (start<end, within the clip) spanning a small number of
// distinct speakers (1–2). We do NOT build a two-speaker fixture.
//
// Run:
//   scripts/run_live_tests.sh test/diarization_live_test.dart

@Tags(['slow'])
library;

import 'dart:ffi';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  // pyannote-seg-3.0.gguf (~5.7 MB) + ggml-tiny.bin (whisper_tiny) required.
  final skip = CrispModels.skipReason(models: ['whisper_tiny', 'pyannote']);

  group('Diarization live (pyannote)', () {
    late crispasr.DecodedAudio audio;
    crispasr.CrispASR? cr;

    setUp(() {
      if (skip != null) return;
      // jfk.wav is ~11 s of clear single-speaker speech.
      audio = crispasr.decodeAudioFile(
        CrispModels.fixture('jfk.wav'),
        libPath: lib,
      );
      // Open the context on a real ASR model so dispose() is safe — the
      // pyannote model is passed only as a diarize arg, never here.
      cr = crispasr.CrispASR(CrispModels.model('whisper_tiny')!, libPath: lib);
    });

    tearDown(() {
      cr?.dispose();
      cr = null;
    });

    test('pyannote labels ASR segments with sane, single-ish speakers', () {
      // 1) Produce ASR time ranges — the diarizer labels these, it does
      //    not invent them. (Verified in src/crispasr_diarize.cpp.)
      final segs = cr!.transcribePcm(
        audio.samples,
        options: const crispasr.TranscribeOptions(
          language: 'en',
          silent: true,
        ),
      );
      expect(segs, isNotEmpty,
          reason: 'tiny ASR must produce at least one segment to diarize');

      // 2) Map to DiarizeSegment (t0/t1 in seconds) and diarize via the
      //    pyannote GGUF path — the same call DiarizationService makes.
      final libSegs = segs
          .map((s) => crispasr.DiarizeSegment(t0: s.start, t1: s.end))
          .toList();

      final ok = crispasr.diarizeSegments(
        segs: libSegs,
        left: audio.samples,
        isStereo: false,
        method: crispasr.DiarizeMethod.pyannote,
        pyannoteModelPath: CrispModels.model('pyannote'),
        // diarizeSegments is a top-level fn taking a DynamicLibrary (not a
        // libPath string); passing null makes it open 'libcrispasr.dylib'
        // by name off the default search path, which fails in tests. Hand
        // it the harness-resolved dylib explicitly.
        lib: DynamicLibrary.open(lib!),
      );

      // The only failure case is the pyannote GGUF failing to load.
      expect(ok, isTrue,
          reason: 'pyannote diarize must succeed (GGUF loaded + net ran)');

      // 3) Sane bounds: ranges came from ASR, so verify they survived and
      //    sit within the clip.
      expect(libSegs, isNotEmpty);
      final dur = audio.durationSeconds;
      for (final s in libSegs) {
        expect(s.t1, greaterThan(s.t0), reason: 'start < end');
        expect(s.t0, greaterThanOrEqualTo(0));
        expect(s.t1, lessThanOrEqualTo(dur + 0.5),
            reason: 'segment within clip duration');
      }

      // 4) At least one range got a real (non-silence) speaker label, and
      //    distinct speakers stay small — jfk is single-speaker, so 1–2.
      final labelled =
          libSegs.where((s) => s.speaker >= 0).toList(growable: false);
      expect(labelled, isNotEmpty,
          reason: 'at least one speech range must be labelled (speaker >= 0)');

      final distinct = labelled.map((s) => s.speaker).toSet();
      expect(distinct.length, inInclusiveRange(1, 2),
          reason: 'single-speaker clip → 1 (allow 2 for overlap artefacts)');
      // Speaker indices are 0-based and capped at pyannote's 3 classes.
      for (final spk in distinct) {
        expect(spk, inInclusiveRange(0, 2));
      }
    }, skip: skip);
  });
}
