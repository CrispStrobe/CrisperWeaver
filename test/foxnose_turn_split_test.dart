// #324 — splitting an ASR segment at FoxNose speaker turns.
//
// DiarizationService.splitOnTurns is pure, so the contract is tested without
// a dylib: which words go to which speaker, how short runs fold, and that
// piece text is cut from the segment's own text rather than rebuilt.
//
// Opt-in live check that the turn ABI delivers what the splitter needs:
//   CRISPASR_LIB=/path/libcrispasr.so \
//   CRISPASR_TEST_WESPEAKER_MODEL=/path/wespeaker-resnet34-lm.gguf \
//   CRISPASR_TEST_MULTISPEAKER_WAV=/path/CrispASR/samples/multispeaker.wav \
//   flutter test --tags slow test/foxnose_turn_split_test.dart

import 'dart:ffi';
import 'dart:io';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/native/crispasr_import.dart' as crispasr;
import 'package:crisper_weaver/services/diarization_service.dart';
import 'package:flutter_test/flutter_test.dart';

TranscriptionWord w(String word, double t0, double t1) =>
    TranscriptionWord(word: word, startTime: t0, endTime: t1, confidence: 1);

crispasr.DiarizeTurn turn(double t0, double t1, int speaker) =>
    crispasr.DiarizeTurn(t0: t0, t1: t1, speaker: speaker);

void main() {
  final seg = TranscriptionSegment(
    text: 'How are you? Fine, thanks.',
    startTime: 0,
    endTime: 3,
    words: [
      w(' How', 0.0, 0.3),
      w(' are', 0.3, 0.6),
      w(' you?', 0.6, 1.2),
      w(' Fine,', 1.6, 2.2),
      w(' thanks.', 2.2, 3.0),
    ],
  );

  test('splits at the speaker change, text cut from the original', () {
    final pieces = DiarizationService.splitOnTurns(
        seg, [turn(0, 1.4, 0), turn(1.4, 3, 1)])!;
    expect(pieces.map((p) => p.speaker), [0, 1]);
    expect(pieces.map((p) => p.segment.text),
        ['How are you?', 'Fine, thanks.']);
    expect(pieces[0].segment.startTime, 0.0);
    expect(pieces[0].segment.endTime, 1.2);
    expect(pieces[1].segment.startTime, 1.6);
    expect(pieces[1].segment.endTime, 3.0);
    expect(pieces[1].segment.words!.map((x) => x.word), [' Fine,', ' thanks.']);
  });

  test('one speaker throughout is left alone', () {
    expect(DiarizationService.splitOnTurns(seg, [turn(0, 3, 0)]), isNull);
  });

  test('no word timings or no turns means no split', () {
    const bare = TranscriptionSegment(text: 'x', startTime: 0, endTime: 1);
    expect(DiarizationService.splitOnTurns(bare, [turn(0, 1, 0)]), isNull);
    expect(DiarizationService.splitOnTurns(seg, const []), isNull);
  });

  test('a run shorter than the minimum folds into its neighbour', () {
    // ' are' alone falls in speaker 1's turn: 0.3 s < 0.5 s, so it must
    // not become its own piece, and folding it must not leave two
    // speaker-0 pieces behind.
    final pieces = DiarizationService.splitOnTurns(
        seg, [turn(0, 0.3, 0), turn(0.3, 0.6, 1), turn(0.6, 3, 0)]);
    expect(pieces, isNull);
  });

  test('words outside every turn join their neighbour', () {
    // ' you?' (mid 0.9) and ' Fine,' (mid 1.9) sit in a gap between turns.
    final pieces = DiarizationService.splitOnTurns(
        seg, [turn(0, 0.8, 0), turn(2.0, 3, 1)])!;
    expect(pieces.map((p) => p.speaker), [0, 1]);
    expect(pieces[0].segment.text, 'How are you? Fine,');
    expect(pieces[1].segment.text, 'thanks.');
  });

  test('CJK text keeps its own spacing', () {
    final zh = TranscriptionSegment(
      text: '你好吗？我很好。',
      startTime: 0,
      endTime: 3,
      words: [
        w('你好', 0.0, 0.6),
        w('吗？', 0.6, 1.2),
        w('我很', 1.6, 2.3),
        w('好。', 2.3, 3.0),
      ],
    );
    final pieces = DiarizationService.splitOnTurns(
        zh, [turn(0, 1.4, 0), turn(1.4, 3, 1)])!;
    expect(pieces.map((p) => p.segment.text), ['你好吗？', '我很好。']);
  });

  test('falls back to joined words when a word is not in the text', () {
    final edited = seg.copyWith(text: 'completely different');
    final pieces = DiarizationService.splitOnTurns(
        edited, [turn(0, 1.4, 0), turn(1.4, 3, 1)])!;
    expect(pieces.map((p) => p.segment.text),
        ['How are you?', 'Fine, thanks.']);
  });

  test('pieces keep the segment metadata and tags', () {
    final tagged = seg.copyWith(metadata: {'k': 1}, tags: ['bookmark']);
    final pieces = DiarizationService.splitOnTurns(
        tagged, [turn(0, 1.4, 0), turn(1.4, 3, 1)])!;
    for (final p in pieces) {
      expect(p.segment.metadata, {'k': 1});
      expect(p.segment.tags, ['bookmark']);
    }
  });

  final libPath = Platform.environment['CRISPASR_LIB'];
  final embedder = Platform.environment['CRISPASR_TEST_WESPEAKER_MODEL'];
  final wav = Platform.environment['CRISPASR_TEST_MULTISPEAKER_WAV'];

  test('FoxNose returns turns inside a single spanning segment (opt-in)',
      tags: ['slow'], () {
    final lib = DynamicLibrary.open(libPath!);
    final audio = crispasr.decodeAudioFile(wav!, libPath: libPath);
    final dur = audio.samples.length / 16000;
    // One segment across the whole recording: the per-segment label can
    // only ever be one speaker, which is the case the turns exist for.
    final segs = [crispasr.DiarizeSegment(t0: 0, t1: dur)];
    final turns = <crispasr.DiarizeTurn>[];
    final ok = crispasr.diarizeSegments(
        segs: segs,
        left: audio.samples,
        method: crispasr.DiarizeMethod.foxNose,
        foxnoseEmbedderPath: embedder,
        outTurns: turns,
        lib: lib);
    expect(ok, isTrue);
    expect(turns.map((t) => t.speaker).toSet().length, greaterThanOrEqualTo(2));
    for (var i = 1; i < turns.length; i++) {
      expect(turns[i].t0, greaterThanOrEqualTo(turns[i - 1].t0));
    }
  },
      skip: (libPath == null || embedder == null || wav == null)
          ? 'set CRISPASR_LIB + CRISPASR_TEST_WESPEAKER_MODEL + '
              'CRISPASR_TEST_MULTISPEAKER_WAV'
          : null);
}
