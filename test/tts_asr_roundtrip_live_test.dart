// TTS → WAV → ASR roundtrip, end to end (PLAN §9.1).
//
// The single most valuable live proof in the suite: it is the only test
// where audio the app *produced* is fed back through the audio the app
// *consumes*. Every other live test proves one half — synthesize emits
// non-zero PCM, or whisper transcribes a fixture — and neither half
// catches a regression that silently degrades the audio in between
// (wrong sample rate, wrong channel count, a truncated WAV header, a
// resampler that drops every other frame). Here the assertion is on the
// words, so any of those shows up as a transcript that has lost them.
//
// Shape (mirrors what the Synthesize screen and `crisperweaver
// synthesize` actually do, minus the Flutter-coupled service layer —
// TtsService needs path_provider + Riverpod + a ModelService, none of
// which exist under a plain `flutter test`, so this drives the same
// engine calls TtsService makes):
//
//   1. CrispasrSession.open(kokoro gguf, backend: 'kokoro')
//   2. session.setVoice(<kokoro-voice-*.gguf voicepack>)   — kokoro is a
//      two-file backend; without a voicepack synth has no speaker.
//   3. session.synthesize(phrase)                          — Float32 PCM
//   4. session.outputSampleRate                            — probed, NOT
//      assumed (TtsService._probeOutputSampleRate exists because #332 was
//      exactly the bug of assuming 24 kHz for every backend)
//   5. write a real 16-bit mono WAV to a temp dir
//   6. crispasr.decodeAudioFile(wav)                       — the same
//      decoder the Transcribe screen uses on a user-picked file
//   7. resample to 16 kHz if the decoder didn't already
//   8. CrispasrSession.open(whisper .bin).transcribe(pcm, language: 'en')
//   9. assert >= 60% of the salient words survived
//
// Step 5+6 are the point: we round-trip through an actual file on disk
// rather than handing the in-memory PCM straight to the ASR session, so
// a broken WAV writer or a decoder that mis-reads the header fails here.
//
// Threshold: 60% of the salient words, matched case- and
// punctuation-insensitively with a naive plural stem. A TTS→ASR
// roundtrip is never exact (whisper-base.en renders "brown" as "ground"
// often enough), so an exact-string assertion would be a flake
// generator; losing 40%+ of the content words is a real regression.
//
// Self-skips (never fails) unless all three env vars point at files:
//   CRISPASR_TEST_KOKORO_MODEL   kokoro-82m-*.gguf
//   CRISPASR_TEST_KOKORO_VOICE   kokoro-voice-*.gguf voicepack
//   CRISPASR_TEST_WHISPER_MODEL  ggml-*.bin
// plus the shared opt-in gate (CRISPASR_LIB / RUN_LIVE_TESTS) and a
// loadable dylib. Models are read from their env paths directly — nothing
// is copied or symlinked into a models dir.
//
// Run:
//   tools/run_live_tests.sh test/tts_asr_roundtrip_live_test.dart

@Tags(['slow'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

// ---------------------------------------------------------------------------
// Pure helpers. Unit-tested below without any model, because they decide
// whether the roundtrip assertion is meaningful: a broken normaliser
// would make the test pass on garbage.
// ---------------------------------------------------------------------------

/// Lower-case, strip everything that isn't a letter or a digit, and
/// collapse to whitespace-separated tokens. Punctuation and casing are
/// exactly what a TTS→ASR roundtrip is free to change, so neither may
/// participate in the comparison.
List<String> tokenize(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
    .split(' ')
    .where((t) => t.isNotEmpty)
    .toList();

/// Crude English plural/3rd-person stem: drop a single trailing `s` from
/// words long enough for it to be an inflection rather than the word.
/// Enough to let "jumps" match "jump" without pulling in a stemmer.
String stem(String word) =>
    (word.length > 3 && word.endsWith('s') && !word.endsWith('ss'))
        ? word.substring(0, word.length - 1)
        : word;

/// Fraction of [salient] whose stem appears among [transcript]'s stems.
/// 1.0 when every salient word survived, 0.0 when none did.
double wordOverlap(List<String> salient, String transcript) {
  if (salient.isEmpty) return 1.0;
  final got = tokenize(transcript).map(stem).toSet();
  final hits = salient.map(stem).where(got.contains).length;
  return hits / salient.length;
}

/// Linear resample between arbitrary rates. Only used when the decoder
/// hands back something other than 16 kHz — `crispasr_audio_load`
/// normally resamples for us, but it is not contractually obliged to,
/// and feeding whisper the wrong rate is a silent-garbage failure.
Float32List resampleLinear(Float32List src, int fromRate, int toRate) {
  if (src.isEmpty || fromRate == toRate || fromRate <= 0 || toRate <= 0) {
    return src;
  }
  final outN = (src.length * toRate) ~/ fromRate;
  final out = Float32List(outN);
  final ratio = fromRate / toRate;
  for (var j = 0; j < outN; j++) {
    final pos = j * ratio;
    final i0 = pos.floor();
    final i1 = (i0 + 1 < src.length) ? i0 + 1 : src.length - 1;
    final frac = pos - i0;
    out[j] = src[i0] * (1 - frac) + src[i1] * frac;
  }
  return out;
}

/// Minimal 16-bit mono PCM WAV encoder — the same 44-byte canonical
/// header TtsService writes. Deliberately hand-rolled rather than
/// pulled from lib/: if the app's writer regresses, this test should
/// still be able to tell us whether the *audio* is fine.
Uint8List encodeWav16(Float32List samples, int sampleRate) {
  final dataBytes = samples.length * 2;
  final out = Uint8List(44 + dataBytes);
  final bd = ByteData.view(out.buffer);
  out.setRange(0, 4, 'RIFF'.codeUnits);
  bd.setUint32(4, out.length - 8, Endian.little);
  out.setRange(8, 12, 'WAVE'.codeUnits);
  out.setRange(12, 16, 'fmt '.codeUnits);
  bd.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  bd.setUint16(20, 1, Endian.little); // format = PCM
  bd.setUint16(22, 1, Endian.little); // channels = mono
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bd.setUint16(32, 2, Endian.little); // block align
  bd.setUint16(34, 16, Endian.little); // bits per sample
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
  return out;
}

void main() {
  // -------------------------------------------------------------------
  // Pure unit tests — always run, no dylib, no models. These guard the
  // measurement itself.
  // -------------------------------------------------------------------
  group('roundtrip scoring helpers', () {
    test('tokenize drops punctuation and casing', () {
      expect(tokenize('The QUICK, brown fox!'),
          ['the', 'quick', 'brown', 'fox']);
      expect(tokenize('  ...  '), isEmpty);
    });

    test('stem drops an inflectional -s but never mangles short words', () {
      expect(stem('jumps'), 'jump');
      expect(stem('dogs'), 'dog');
      expect(stem('is'), 'is'); // too short to be an inflection
      expect(stem('grass'), 'grass'); // -ss is not a plural
    });

    test('wordOverlap is 1.0 on an exact hit and 0.0 on a miss', () {
      const salient = ['quick', 'fox', 'jumps'];
      expect(wordOverlap(salient, 'The quick brown fox jumped... jumps!'), 1.0);
      expect(wordOverlap(salient, 'entirely different words here'), 0.0);
    });

    test('wordOverlap ignores punctuation, case and plural forms', () {
      expect(wordOverlap(['dog', 'jump'], 'DOGS -- JUMPS.'), 1.0);
    });

    test('wordOverlap reports a partial score', () {
      expect(wordOverlap(['a1', 'b2', 'c3', 'd4'], 'a1 c3'), 0.5);
    });

    test('resampleLinear is a no-op at equal rates and 2:3 for 24k→16k', () {
      final src = Float32List.fromList(List<double>.filled(2400, 0.25));
      expect(identical(resampleLinear(src, 16000, 16000), src), isTrue);
      expect(resampleLinear(src, 24000, 16000).length, 1600);
      expect(resampleLinear(src, 24000, 16000).first, closeTo(0.25, 1e-6));
    });

    test('encodeWav16 writes a 44-byte canonical header', () {
      final wav = encodeWav16(Float32List.fromList([0.0, 1.0, -1.0]), 24000);
      expect(wav.length, 44 + 6);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      final bd = ByteData.view(wav.buffer);
      expect(bd.getUint32(24, Endian.little), 24000);
      expect(bd.getUint16(22, Endian.little), 1, reason: 'must be mono');
      expect(bd.getInt16(44 + 2, Endian.little), 32767); // +1.0 clamps
      expect(bd.getInt16(44 + 4, Endian.little), -32767); // -1.0 clamps
    });
  });

  // -------------------------------------------------------------------
  // The live roundtrip.
  // -------------------------------------------------------------------
  final lib = CrispModels.lib;
  final kokoroModel = Platform.environment['CRISPASR_TEST_KOKORO_MODEL'];
  final kokoroVoice = Platform.environment['CRISPASR_TEST_KOKORO_VOICE'];
  final whisperModel = Platform.environment['CRISPASR_TEST_WHISPER_MODEL'];

  bool present(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  final skip = CrispModels.skipReason() ??
      (!present(kokoroModel)
          ? 'set CRISPASR_TEST_KOKORO_MODEL to a downloaded kokoro-82m-*.gguf'
          : !present(kokoroVoice)
              ? 'set CRISPASR_TEST_KOKORO_VOICE to a kokoro-voice-*.gguf '
                  'voicepack (kokoro is a two-file backend)'
              : !present(whisperModel)
                  ? 'set CRISPASR_TEST_WHISPER_MODEL to a downloaded ggml-*.bin'
                  : null);

  group('TTS → WAV → ASR roundtrip (kokoro → whisper)', () {
    // Long enough that a dropped word is visible in the score, short
    // enough that synth + decode stay well under the timeout.
    const phrase = 'The quick brown fox jumps over the lazy dog.';
    const salient = ['quick', 'brown', 'fox', 'jumps', 'lazy', 'dog'];
    const minOverlap = 0.6;

    late Directory tmp;

    setUp(() {
      if (skip != null) return;
      tmp = Directory.systemTemp.createTempSync('cw_tts_asr_roundtrip_');
    });

    tearDown(() {
      if (skip != null) return;
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {
        // A leaked temp dir is not worth failing a live run over.
      }
    });

    test('a synthesized sentence survives being transcribed back', () {
      // ---- 1. synthesize -------------------------------------------
      final tts = crispasr.CrispasrSession.open(kokoroModel!,
          backend: 'kokoro', libPath: lib);
      addTearDown(tts.close);
      tts.setVoice(kokoroVoice!);
      final pcm = tts.synthesize(phrase);
      expect(pcm.length, greaterThan(0),
          reason: 'kokoro produced no audio for "$phrase"');

      // Probe the rate rather than assuming 24 kHz (#332). A backend
      // that reports 0 has no rate to give us; TtsService falls back to
      // 24 kHz there and so do we.
      var rate = 0;
      try {
        rate = tts.outputSampleRate;
      } catch (_) {
        // Older dylib without the symbol — fall through to the default.
      }
      if (rate <= 0) rate = 24000;
      expect(rate, greaterThanOrEqualTo(8000),
          reason: 'implausible output sample rate $rate Hz');
      // >= 0.5 s of audio: a backend that emits a handful of samples
      // would otherwise "pass" step 1 and fail unintelligibly at step 9.
      expect(pcm.length, greaterThan(rate ~/ 2),
          reason: 'kokoro emitted ${pcm.length} samples at $rate Hz — '
              'less than half a second for a nine-word sentence');

      // ---- 2. through a real file on disk ---------------------------
      final wav = File('${tmp.path}/roundtrip.wav');
      wav.writeAsBytesSync(encodeWav16(pcm, rate));
      expect(wav.lengthSync(), greaterThan(44),
          reason: 'the WAV holds only a header — no samples were written');

      // ---- 3. decode it back the way the Transcribe screen would ----
      final decoded = crispasr.decodeAudioFile(wav.path, libPath: lib);
      expect(decoded.samples, isNotEmpty,
          reason: 'the decoder read no samples out of the WAV we just wrote');
      final pcm16 = decoded.sampleRate == 16000
          ? decoded.samples
          : resampleLinear(decoded.samples, decoded.sampleRate, 16000);
      expect(pcm16.length, greaterThan(8000),
          reason: 'less than 0.5 s of 16 kHz audio reached the ASR leg');

      // ---- 4. transcribe --------------------------------------------
      final asr = crispasr.CrispasrSession.open(whisperModel!,
          backend: 'whisper', libPath: lib);
      addTearDown(asr.close);
      final segments = asr.transcribe(pcm16, language: 'en');
      final text = segments.map((s) => s.text).join(' ').trim();
      printOnFailure('synthesized rate=$rate Hz, ${pcm.length} samples; '
          'decoded rate=${decoded.sampleRate} Hz; transcript="$text"');
      expect(text, isNotEmpty,
          reason: 'whisper returned an empty transcript for synthesized audio');

      // ---- 5. did the words survive? --------------------------------
      final score = wordOverlap(salient, text);
      expect(score, greaterThanOrEqualTo(minOverlap),
          reason: 'only ${(score * 100).round()}% of $salient survived the '
              'kokoro → WAV → whisper roundtrip (need '
              '${(minOverlap * 100).round()}%); transcript was "$text"');
    }, skip: skip);
  });
}
