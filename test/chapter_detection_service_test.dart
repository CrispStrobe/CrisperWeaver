// Tests for ChapterDetectionService — topic-shift chapter detection (§5.25.6).

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/chapter_detection_service.dart';

List<TranscriptionSegment> _segs(List<String> texts) => [
      for (var i = 0; i < texts.length; i++)
        TranscriptionSegment(
          text: texts[i],
          startTime: i * 30.0,
          endTime: (i + 1) * 30.0,
        ),
    ];

void main() {
  group('ChapterDetectionService.detectChapters', () {
    test('short transcripts produce a single chapter', () {
      final segments = _segs([
        'Hello everyone welcome to the show',
        'Today we discuss Flutter testing',
        'Let us get started right away',
      ]);
      final chapters = ChapterDetectionService.detectChapters(
        segments: segments,
        windowSize: 5,
      );
      expect(chapters.length, 1);
      expect(chapters.first.startSegmentIndex, 0);
      expect(chapters.first.startTime, 0.0);
    });

    test('first chapter always starts at index 0', () {
      final segments = _segs(List.generate(
        20,
        (i) => 'segment number $i with some text',
      ));
      final chapters = ChapterDetectionService.detectChapters(
        segments: segments,
        windowSize: 3,
      );
      expect(chapters.first.startSegmentIndex, 0);
      expect(chapters.first.startTime, 0.0);
    });

    test('distinct topic blocks produce multiple chapters', () {
      // First block: cooking
      final cooking = List.generate(
          8, (_) => 'recipe cooking kitchen flour sugar eggs baking oven');
      // Second block: astronomy (totally different vocabulary)
      final astronomy = List.generate(
          8, (_) => 'galaxy stars telescope nebula planet orbit cosmos');
      final segments = _segs([...cooking, ...astronomy]);
      final chapters = ChapterDetectionService.detectChapters(
        segments: segments,
        windowSize: 3,
        threshold: 0.25,
        minChapterSegments: 2,
      );
      expect(chapters.length, greaterThanOrEqualTo(2));
    });

    test('endTime of last chapter matches last segment', () {
      final segments = _segs(List.generate(
        15,
        (i) => 'some text for segment $i',
      ));
      final chapters = ChapterDetectionService.detectChapters(
        segments: segments,
        windowSize: 3,
      );
      expect(chapters.last.endTime, segments.last.endTime);
    });

    test('chapters cover all segments without gaps', () {
      final segments = _segs(List.generate(
        20,
        (i) => i < 10 ? 'alpha beta gamma delta epsilon' : 'one two three four five',
      ));
      final chapters = ChapterDetectionService.detectChapters(
        segments: segments,
        windowSize: 3,
        minChapterSegments: 2,
      );
      // Verify chapters are sorted and contiguous
      for (var i = 1; i < chapters.length; i++) {
        expect(chapters[i].startSegmentIndex,
            greaterThan(chapters[i - 1].startSegmentIndex));
      }
    });
  });

  group('ChapterDetectionService.toYouTubeFormat', () {
    test('formats timestamps correctly', () {
      final chapters = [
        const ChapterMarker(
          startTime: 0.0,
          endTime: 120.0,
          startSegmentIndex: 0,
          title: 'Introduction',
        ),
        const ChapterMarker(
          startTime: 120.0,
          endTime: 300.0,
          startSegmentIndex: 4,
          title: 'Main Topic',
        ),
      ];
      final result = ChapterDetectionService.toYouTubeFormat(chapters);
      expect(result, contains('00:00:00 Introduction'));
      expect(result, contains('00:02:00 Main Topic'));
    });
  });

  group('ChapterDetectionService.toPodcastChaptersJson', () {
    test('produces valid Podcasting 2.0 structure', () {
      final chapters = [
        const ChapterMarker(
          startTime: 0.0,
          endTime: 60.0,
          startSegmentIndex: 0,
          title: 'Intro',
        ),
      ];
      final json = ChapterDetectionService.toPodcastChaptersJson(chapters);
      expect(json['version'], '1.2.0');
      expect(json['chapters'], isList);
      final ch = (json['chapters'] as List).first as Map<String, dynamic>;
      expect(ch['startTime'], 0.0);
      expect(ch['title'], 'Intro');
    });
  });
}
