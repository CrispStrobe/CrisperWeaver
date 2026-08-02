// Pure-Dart coverage for the FileUtils export GENERATORS that
// subtitle_export_test.dart leaves untested: CSV / LRC / WTS / Markdown.
// SRT + VTT + formatSrtTime live in subtitle_export_test; this file
// fills the remaining `generate*Content` surface so a regression in
// the share/export menu's lesser-used formats gets caught.
//
// No FFI, no platform channels, no disk — every generator is a pure
// `List<TranscriptionSegment> -> String` transform.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/utils/file_utils.dart';

void main() {
  final twoSegs = <TranscriptionSegment>[
    const TranscriptionSegment(
      text: 'Hello world.',
      startTime: 0.0,
      endTime: 1.5,
      speaker: 'Alice',
    ),
    const TranscriptionSegment(
      text: 'How are you?',
      startTime: 1.5,
      endTime: 3.0,
      speaker: 'Bob',
    ),
  ];

  group('FileUtils.generateCsvContent', () {
    test('emits the canonical header row first', () {
      final out = FileUtils.generateCsvContent(twoSegs);
      expect(out.split('\n').first, 'start_s,end_s,speaker,text');
    });

    test('one data row per segment with 3-decimal times', () {
      final out = FileUtils.generateCsvContent(twoSegs);
      expect(out, contains('0.000,1.500,Alice,Hello world.'));
      expect(out, contains('1.500,3.000,Bob,How are you?'));
    });

    test('empty segments produce header-only output', () {
      final out = FileUtils.generateCsvContent([]);
      expect(out.trim(), 'start_s,end_s,speaker,text');
    });

    test('null speaker becomes an empty cell, not the string "null"', () {
      final out = FileUtils.generateCsvContent([
        const TranscriptionSegment(text: 'lonely', startTime: 0, endTime: 1),
      ]);
      // ...,<empty speaker>,lonely
      expect(out, contains('0.000,1.000,,lonely'));
      expect(out, isNot(contains('null')));
    });

    test('cells with commas are quoted', () {
      final out = FileUtils.generateCsvContent([
        const TranscriptionSegment(
            text: 'one, two, three', startTime: 0, endTime: 1),
      ]);
      expect(out, contains('"one, two, three"'));
    });

    test('embedded double-quotes are RFC-4180 doubled and wrapped', () {
      final out = FileUtils.generateCsvContent([
        const TranscriptionSegment(text: 'say "hi"', startTime: 0, endTime: 1),
      ]);
      expect(out, contains('"say ""hi"""'));
    });

    test('newline inside a cell forces quoting', () {
      final out = FileUtils.generateCsvContent([
        const TranscriptionSegment(
            text: 'line1\nline2', startTime: 0, endTime: 1),
      ]);
      expect(out, contains('"line1\nline2"'));
    });

    test('plain text without special chars is left unquoted', () {
      final out = FileUtils.generateCsvContent([
        const TranscriptionSegment(
            text: 'plain text', startTime: 0, endTime: 1),
      ]);
      expect(out, contains(',plain text'));
      expect(out, isNot(contains('"plain text"')));
    });
  });

  group('FileUtils.formatLrcTime', () {
    test('zero is 00:00.00', () {
      expect(FileUtils.formatLrcTime(0), '00:00.00');
    });

    test('sub-second is rendered as centiseconds', () {
      expect(FileUtils.formatLrcTime(1.23), '00:01.23');
    });

    test('minute rollover', () {
      expect(FileUtils.formatLrcTime(61.5), '01:01.50');
    });

    test('two-digit minutes are zero-padded', () {
      expect(FileUtils.formatLrcTime(5.0), '00:05.00');
    });
  });

  group('FileUtils.generateLrcContent', () {
    test('starts with title + length metadata tags', () {
      final out = FileUtils.generateLrcContent(twoSegs);
      final lines = out.split('\n');
      expect(lines[0], '[ti:CrisperWeaver transcription]');
      expect(lines[1], '[length:00:03.00]');
    });

    test('empty segments still emit a [length:00:00.00] header', () {
      final out = FileUtils.generateLrcContent([]);
      expect(out, contains('[length:00:00.00]'));
    });

    test('each segment becomes a [mm:ss.xx] tagged line', () {
      final out = FileUtils.generateLrcContent(twoSegs);
      expect(out, contains('[00:00.00]Alice: Hello world.'));
      expect(out, contains('[00:01.50]Bob: How are you?'));
    });

    test('null speaker omits the inline label entirely', () {
      final out = FileUtils.generateLrcContent([
        const TranscriptionSegment(text: 'no label', startTime: 0, endTime: 1),
      ]);
      expect(out, contains('[00:00.00]no label'));
      expect(out, isNot(contains(': no label')));
    });
  });

  group('FileUtils.generateWtsContent', () {
    test('uses [SRT --> SRT] timestamp ranges', () {
      final out = FileUtils.generateWtsContent(twoSegs);
      expect(out,
          contains('[00:00:00,000 --> 00:00:01,500] <Alice> Hello world.'));
      expect(
          out, contains('[00:00:01,500 --> 00:00:03,000] <Bob> How are you?'));
    });

    test('wraps the speaker label in angle brackets', () {
      final out = FileUtils.generateWtsContent(twoSegs);
      expect(out, contains('<Alice>'));
      expect(out, contains('<Bob>'));
    });

    test('null speaker emits no angle-bracket label', () {
      final out = FileUtils.generateWtsContent([
        const TranscriptionSegment(text: 'anon line', startTime: 0, endTime: 1),
      ]);
      expect(out, contains('[00:00:00,000 --> 00:00:01,000] anon line'));
      expect(out, isNot(contains('<')));
    });

    test('empty segments produce empty output', () {
      expect(FileUtils.generateWtsContent([]), isEmpty);
    });

    test('text is trimmed', () {
      final out = FileUtils.generateWtsContent([
        const TranscriptionSegment(
            text: '   padded   ', startTime: 0, endTime: 1),
      ]);
      expect(out, contains('] padded\n'));
    });
  });

  group('FileUtils.generateMarkdownContent', () {
    test('always opens with the # Transcript heading', () {
      final out = FileUtils.generateMarkdownContent(twoSegs);
      expect(out.startsWith('# Transcript'), isTrue);
    });

    test('segments render as bullets with millis-stripped times', () {
      final out = FileUtils.generateMarkdownContent(twoSegs);
      // 00:00:00,000 -> 00:00:00 (no comma / millis in the chat view)
      expect(out, contains('- `00:00:00 → 00:00:01` **Alice**: Hello world.'));
      expect(out, contains('- `00:00:01 → 00:00:03` **Bob**: How are you?'));
      expect(out, isNot(contains(',000')));
    });

    test('speaker labels are bolded', () {
      final out = FileUtils.generateMarkdownContent(twoSegs);
      expect(out, contains('**Alice**:'));
    });

    test('empty-speaker segment drops the bold label', () {
      final out = FileUtils.generateMarkdownContent([
        const TranscriptionSegment(
            text: 'plain', startTime: 0, endTime: 1, speaker: '   '),
      ], syntheticDisclosure: false);
      expect(out, contains('` plain'));
      expect(out, isNot(contains('**')));
    });

    test('falls back to plainText paragraph when no segments', () {
      final out = FileUtils.generateMarkdownContent(
        [],
        plainText: 'just a paragraph',
        syntheticDisclosure: false,
      );
      expect(out, contains('# Transcript'));
      expect(out, contains('just a paragraph'));
      // No bullet lines without segments.
      expect(out, isNot(contains('- `')));
    });

    test('no segments and no plainText yields just the heading', () {
      final out = FileUtils.generateMarkdownContent([],
          syntheticDisclosure: false);
      expect(out.trim(), '# Transcript');
    });

    test('default includes disclosure notice (Art. 50)', () {
      final out = FileUtils.generateMarkdownContent(twoSegs);
      expect(out, contains('> **Notice:**'));
      // Against the shared string, not a literal. The transcript wording
      // changed on 2026-08-02: it used to say the content "contains
      // AI-generated synthetic speech", which told a reader the recording
      // itself was synthesised when only the transcription is machine work.
      expect(out, contains(FileUtils.disclosureFor(twoSegs)));
    });

    test('disclosure omitted when explicitly opted out', () {
      final out = FileUtils.generateMarkdownContent(twoSegs,
          syntheticDisclosure: false);
      expect(out, isNot(contains('Notice:')));
    });
  });
}
