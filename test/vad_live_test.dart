// Live VAD test (PLAN §9.1 exemplar / §9.2 VAD).
//
// Exercises CrispASR.vad(pcm, modelPath: …) — the native VAD dispatcher
// VadService and transcribeVad rely on — against the bundled Silero
// asset and, when present, the on-disk whisper-vad q4_k model. Tagged
// `slow` and self-skips when the dylib / tiny model are absent.
//
// IMPORTANT (see PLAN §9.5): the CrispASR(modelPath) constructor loads
// `modelPath` as a *whisper ASR context*. Constructing it directly with
// a VAD model (as VadService currently does) means dispose() runs
// whisper_free() over a context that was never a real whisper model,
// which SIGABRTs the native layer. So we open the context on a real ASR
// model (tiny) and pass the VAD model only as vad()'s `modelPath`
// argument — the same shape transcribeVad uses. The VadService pattern
// is flagged for follow-up.
//
// Run:
//   scripts/run_live_tests.sh test/vad_live_test.dart

@Tags(['slow'])
library;

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:crisper_weaver/native/vad_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;
  final skip = CrispModels.skipReason(models: ['whisper_tiny']);

  group('VAD live', () {
    late crispasr.DecodedAudio audio;
    crispasr.CrispASR? cr;

    setUp(() {
      if (skip != null) return;
      // jfk.wav is ~11 s of clear speech with leading/trailing pauses —
      // a real VAD must return at least one span inside the clip.
      audio = crispasr.decodeAudioFile(
        CrispModels.fixture('jfk.wav'),
        libPath: lib,
      );
      // Open the context on a real ASR model so dispose() is safe.
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

    // NOTE: use vadSlices() (the unified VAD dispatcher,
    // crispasr_vad_slices), NOT vad() (legacy crispasr_vad_segments).
    // The legacy path uses whisper's native VAD loader, which returns
    // error -2 ("model init failed") for the Silero v6.2.0 asset and for
    // the whisper-vad q4_k model. VadService currently calls vad() and
    // swallows the error → VAD is a silent no-op against this dylib.
    // Tracked in PLAN §9.5.
    test('Silero dispatcher finds speech spans in the JFK clip', () {
      final spans = cr!.vadSlices(
        audio.samples,
        modelPath: CrispModels.sileroAsset,
        minSpeechMs: 250,
        minSilenceMs: 100,
      );
      expect(spans, isNotEmpty,
          reason: 'Silero must detect at least one speech span');
      final totalSpeech = spans.fold<double>(0, (a, s) => a + s.duration);
      expect(totalSpeech, greaterThan(0.5),
          reason: 'at least half a second of speech across spans');
      for (final s in spans) {
        expect(s.end, greaterThan(s.start));
        expect(s.start, greaterThanOrEqualTo(0));
        expect(s.end, lessThanOrEqualTo(audio.durationSeconds + 0.5));
      }
    }, skip: skip);

    test('whisper-vad q4_k also detects speech (when on disk)', () {
      final vadModel = CrispModels.model('whisper_vad');
      if (vadModel == null) {
        markTestSkipped('whisper-vad-asmr-q4_k.gguf not under models dir');
        return;
      }
      final spans = cr!.vadSlices(audio.samples, modelPath: vadModel);
      expect(spans, isNotEmpty);
    }, skip: skip);

    // Regression for PLAN §9.5: the app's own path is VadService →
    // vadSlicesNative (the free crispasr_vad_slices dispatcher), NOT the
    // binding's instance vad()/dispose dance that returned -2 + SIGABRT.
    // This exercises that helper directly with no whisper context.
    test('vadSlicesNative (the VadService path) finds spans without a ctx',
        () {
      final spans = vadSlicesNative(
        CrispModels.sileroAsset,
        audio.samples,
        threshold: 0.5,
        libPath: lib,
      );
      expect(spans, isNotEmpty,
          reason: 'VadService must get real spans via crispasr_vad_slices');
      for (final s in spans) {
        expect(s.end, greaterThan(s.start));
        expect(s.start, greaterThanOrEqualTo(0));
      }
    }, skip: skip);
  });
}
