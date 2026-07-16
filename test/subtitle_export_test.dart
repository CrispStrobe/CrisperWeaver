// Subtitle export — pure data formatters that silently corrupt
// downstream tooling if the timestamp format drifts. SRT uses comma
// for the millisecond separator (`00:00:01,500`), VTT uses dot
// (`00:00:01.500`); swapping them breaks every player.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/utils/file_utils.dart';

void main() {
  group('FileUtils.formatSrtTime', () {
    test('zero seconds → 00:00:00,000', () {
      expect(FileUtils.formatSrtTime(0.0), '00:00:00,000');
    });

    test('sub-second fractions round to milliseconds', () {
      expect(FileUtils.formatSrtTime(0.5), '00:00:00,500');
      expect(FileUtils.formatSrtTime(0.001), '00:00:00,001');
      expect(FileUtils.formatSrtTime(0.999), '00:00:00,999');
    });

    test('minute boundary', () {
      expect(FileUtils.formatSrtTime(60.0), '00:01:00,000');
      expect(FileUtils.formatSrtTime(61.5), '00:01:01,500');
    });

    test('hour boundary', () {
      expect(FileUtils.formatSrtTime(3600.0), '01:00:00,000');
      expect(FileUtils.formatSrtTime(3661.25), '01:01:01,250');
    });

    test('uses comma as ms separator (SRT convention)', () {
      expect(FileUtils.formatSrtTime(1.5), contains(','));
      expect(FileUtils.formatSrtTime(1.5), isNot(contains('.')));
    });
  });

  group('FileUtils.formatVttTime', () {
    test('zero seconds → 00:00:00.000', () {
      expect(FileUtils.formatVttTime(0.0), '00:00:00.000');
    });

    test('uses dot as ms separator (VTT convention)', () {
      expect(FileUtils.formatVttTime(1.5), contains('.'));
      expect(FileUtils.formatVttTime(1.5), isNot(contains(',')));
    });

    test('matches SRT format aside from the ms separator', () {
      for (final t in [0.0, 1.5, 60.0, 3600.0, 3661.25]) {
        final srt = FileUtils.formatSrtTime(t);
        final vtt = FileUtils.formatVttTime(t);
        expect(vtt, srt.replaceFirst(',', '.'),
            reason: 'mismatch for t=$t s');
      }
    });
  });

  const segs = [
    TranscriptionSegment(
      text: 'Hello world.',
      startTime: 0.0,
      endTime: 1.5,
      speaker: 'Alice',
      confidence: 0.95,
    ),
    TranscriptionSegment(
      text: 'How are you?',
      startTime: 1.5,
      endTime: 3.0,
      speaker: 'Bob',
      confidence: 0.87,
    ),
  ];

  group('FileUtils.generateSrtContent', () {
    test('emits standard 4-line cue blocks', () {
      final out = FileUtils.generateSrtContent(segs);
      // Cue 1: index, timing arrow, "Speaker: text", blank.
      expect(out, contains('1\n'));
      expect(out, contains('00:00:00,000 --> 00:00:01,500\n'));
      expect(out, contains('Alice: Hello world.\n'));
      // Cue 2.
      expect(out, contains('2\n'));
      expect(out, contains('00:00:01,500 --> 00:00:03,000\n'));
      expect(out, contains('Bob: How are you?\n'));
    });

    test('handles segments without a speaker (writes empty prefix)', () {
      const noSpk = [
        TranscriptionSegment(
            text: 'no speaker here',
            startTime: 0.0,
            endTime: 1.0,
            confidence: 1.0),
      ];
      final out = FileUtils.generateSrtContent(noSpk);
      expect(out, contains(': no speaker here\n'));
    });

    test('empty input with no disclosure yields empty output', () {
      expect(FileUtils.generateSrtContent(const [],
          syntheticDisclosure: false), '');
    });
  });

  group('FileUtils.generateVttContent', () {
    test('begins with the WEBVTT magic header', () {
      final out = FileUtils.generateVttContent(segs);
      expect(out, startsWith('WEBVTT\n'));
    });

    test('uses dot-separated timing per VTT spec', () {
      final out = FileUtils.generateVttContent(segs);
      expect(out, contains('00:00:00.000 --> 00:00:01.500\n'));
      expect(out, isNot(contains(',')));
    });
  });

  group('FileUtils.generateJsonContent', () {
    test('serializes every field per segment', () {
      final out = FileUtils.generateJsonContent(segs,
          syntheticDisclosure: false);
      final decoded = jsonDecode(out) as List;
      expect(decoded.length, 2);

      final first = decoded[0] as Map;
      expect(first['text'], 'Hello world.');
      expect(first['startTime'], 0.0);
      expect(first['endTime'], 1.5);
      expect(first['speaker'], 'Alice');
      expect((first['confidence'] as num).toDouble(), closeTo(0.95, 1e-9));
    });

    test('null speaker is preserved as null in JSON', () {
      const noSpk = [
        TranscriptionSegment(
            text: 't', startTime: 0.0, endTime: 1.0, confidence: 1.0),
      ];
      final decoded =
          jsonDecode(FileUtils.generateJsonContent(noSpk,
              syntheticDisclosure: false)) as List;
      expect((decoded[0] as Map)['speaker'], isNull);
    });
  });

  group('FileUtils.generateCsvContent', () {
    test('emits a header and one row per segment', () {
      final out = FileUtils.generateCsvContent(segs);
      final lines = out.trim().split('\n');
      expect(lines.first, 'start_s,end_s,speaker,text');
      expect(lines.length, 3); // header + 2 rows
      expect(lines[1], '0.000,1.500,Alice,Hello world.');
      expect(lines[2], '1.500,3.000,Bob,How are you?');
    });

    test('RFC-4180 quoting on cells containing commas, quotes, newlines', () {
      const tricky = [
        TranscriptionSegment(
          text: 'Hello, "world"!\nNewline here',
          startTime: 0.0,
          endTime: 1.0,
          speaker: 'Alice',
          confidence: 1.0,
        ),
      ];
      final out = FileUtils.generateCsvContent(tricky);
      // Embedded `"` is doubled, the whole cell is quoted, and the
      // commas inside the cell don't break column alignment.
      expect(
          out,
          contains(
              '0.000,1.000,Alice,"Hello, ""world""!\nNewline here"'));
    });

    test('empty input still emits the header', () {
      expect(FileUtils.generateCsvContent(const []), 'start_s,end_s,speaker,text\n');
    });
  });

  group('FileUtils.formatLrcTime / generateLrcContent', () {
    test('LRC time uses mm:ss.cs format', () {
      expect(FileUtils.formatLrcTime(0.0), '00:00.00');
      expect(FileUtils.formatLrcTime(1.50), '00:01.50');
      expect(FileUtils.formatLrcTime(61.25), '01:01.25');
    });

    test('emits standard LRC tags + one line per segment', () {
      final out = FileUtils.generateLrcContent(segs);
      expect(out, contains('[ti:CrisperWeaver transcription]'));
      expect(out, contains('[length:00:03.00]'));
      expect(out, contains('[00:00.00]Alice: Hello world.'));
      expect(out, contains('[00:01.50]Bob: How are you?'));
    });
  });

  group('FileUtils.generateWtsContent', () {
    test('emits one [t0 --> t1] line per segment', () {
      final out = FileUtils.generateWtsContent(segs);
      expect(out,
          contains('[00:00:00,000 --> 00:00:01,500] <Alice> Hello world.'));
      expect(out,
          contains('[00:00:01,500 --> 00:00:03,000] <Bob> How are you?'));
    });

    test('omits the speaker wrapper when speaker is null', () {
      const noSpk = [
        TranscriptionSegment(
            text: 'no speaker', startTime: 0.0, endTime: 1.0, confidence: 1.0),
      ];
      final out = FileUtils.generateWtsContent(noSpk);
      expect(out, contains('[00:00:00,000 --> 00:00:01,000] no speaker'));
      expect(out, isNot(contains('<>')));
    });
  });
}
