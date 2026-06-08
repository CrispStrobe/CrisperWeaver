import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/note_export_service.dart';
import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/models/segment_tag.dart';

void main() {
  final segments = [
    TranscriptionSegment(
      text: 'Hello world, this is a test.',
      startTime: 0.0,
      endTime: 5.0,
      speaker: 'Alice',
      confidence: 0.95,
    ),
    TranscriptionSegment(
      text: 'The quick brown fox jumps over the lazy dog.',
      startTime: 5.5,
      endTime: 12.0,
      speaker: 'Bob',
      confidence: 0.82,
    ),
    TranscriptionSegment(
      text: 'This should be reviewed carefully.',
      startTime: 12.5,
      endTime: 16.0,
      speaker: 'Alice',
      confidence: 0.45,
    ),
  ];

  group('NoteExportService — Obsidian', () {
    test('produces valid YAML frontmatter', () {
      final result = NoteExportService.toObsidian(
        segments: segments,
        title: 'Test Meeting',
        date: DateTime(2026, 6, 7),
        model: 'whisper-base',
        language: 'en',
        speakers: ['Alice', 'Bob'],
      );
      expect(result, contains('---'));
      expect(result, contains('title: "Test Meeting"'));
      expect(result, contains('type: transcript'));
      expect(result, contains('model: "whisper-base"'));
      expect(result, contains('language: "en"'));
      expect(result, contains('  - "Alice"'));
      expect(result, contains('  - "Bob"'));
      expect(result, contains('# Test Meeting'));
    });

    test('renders segments with timestamps and speakers', () {
      final result = NoteExportService.toObsidian(
        segments: segments,
        title: 'Test',
      );
      expect(result, contains('[00:00] Alice'));
      expect(result, contains('[00:05] Bob'));
      expect(result, contains('Hello world'));
    });

    test('includes segment tags when provided', () {
      final result = NoteExportService.toObsidian(
        segments: segments,
        title: 'Test',
        segmentTags: {
          0: [SegmentTag.important],
          2: [SegmentTag.actionItem, SegmentTag.followUp],
        },
      );
      expect(result, contains(SegmentTag.important.emoji));
      expect(result, contains(SegmentTag.actionItem.emoji));
      expect(result, contains(SegmentTag.followUp.emoji));
    });
  });

  group('NoteExportService — Notion', () {
    test('renders speaker headers', () {
      final result = NoteExportService.toNotion(
        segments: segments,
        title: 'Test Meeting',
        date: DateTime(2026, 6, 7),
      );
      expect(result, contains('# Test Meeting'));
      expect(result, contains('## Alice'));
      expect(result, contains('## Bob'));
    });
  });

  group('NoteExportService — Logseq', () {
    test('produces indented bullet blocks', () {
      final result = NoteExportService.toLogseq(
        segments: segments,
        title: 'Test',
        model: 'whisper-base',
      );
      expect(result, contains('- # Test'));
      expect(result, contains('  type:: [[transcript]]'));
      expect(result, contains('  - **Alice:**'));
      expect(result, contains('    timestamp:: 00:00'));
    });
  });

  group('NoteExportService — YouTube chapters', () {
    test('produces timestamp-title lines', () {
      final result = NoteExportService.toYouTubeChapters(
        segments: segments,
      );
      expect(result, contains('00:00:00'));
      expect(result, contains('Alice'));
      expect(result, contains('Bob'));
    });
  });

  group('SegmentTag', () {
    test('round-trips through JSON', () {
      for (final tag in SegmentTag.values) {
        expect(SegmentTag.fromJson(tag.toJson()), equals(tag));
      }
    });

    test('list round-trips through JSON', () {
      final tags = [SegmentTag.bookmark, SegmentTag.actionItem];
      final json = SegmentTag.listToJson(tags);
      final restored = SegmentTag.listFromJson(json);
      expect(restored, equals(tags));
    });

    test('fromJson returns null for unknown values', () {
      expect(SegmentTag.fromJson('nonexistent'), isNull);
      expect(SegmentTag.fromJson(null), isNull);
    });
  });
}
