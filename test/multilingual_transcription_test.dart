// Unit tests for MultilingualTranscriptionService (§5.25.5).
//
// The service's tagSegmentLanguages() needs a real LidService with a model,
// so we only test the pure static groupByLanguage() and the LanguageGroup
// model here. Live LID tagging is tested by the existing LID live tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/multilingual_transcription_service.dart';

TranscriptionSegment _seg(String text, double start, double end,
    {String? lang}) {
  return TranscriptionSegment(
    text: text,
    startTime: start,
    endTime: end,
    metadata: {if (lang != null) 'lang': lang},
  );
}

void main() {
  group('§5.25.5 — MultilingualTranscriptionService', () {
    group('groupByLanguage', () {
      test('empty segments → empty groups', () {
        expect(
            MultilingualTranscriptionService.groupByLanguage([]), isEmpty);
      });

      test('single language → one group', () {
        final segs = [
          _seg('hello', 0, 1, lang: 'en'),
          _seg('world', 1, 2, lang: 'en'),
        ];
        final groups =
            MultilingualTranscriptionService.groupByLanguage(segs);
        expect(groups.length, 1);
        expect(groups[0].language, 'en');
        expect(groups[0].segments.length, 2);
      });

      test('alternating languages → multiple groups', () {
        final segs = [
          _seg('hello', 0, 1, lang: 'en'),
          _seg('bonjour', 1, 2, lang: 'fr'),
          _seg('world', 2, 3, lang: 'en'),
        ];
        final groups =
            MultilingualTranscriptionService.groupByLanguage(segs);
        expect(groups.length, 3);
        expect(groups[0].language, 'en');
        expect(groups[1].language, 'fr');
        expect(groups[2].language, 'en');
      });

      test('consecutive same-lang segments are merged into one group',
          () {
        final segs = [
          _seg('eins', 0, 1, lang: 'de'),
          _seg('zwei', 1, 2, lang: 'de'),
          _seg('three', 2, 3, lang: 'en'),
          _seg('four', 3, 4, lang: 'en'),
          _seg('five', 4, 5, lang: 'en'),
        ];
        final groups =
            MultilingualTranscriptionService.groupByLanguage(segs);
        expect(groups.length, 2);
        expect(groups[0].language, 'de');
        expect(groups[0].segments.length, 2);
        expect(groups[1].language, 'en');
        expect(groups[1].segments.length, 3);
      });

      test('segments without lang tag default to "unknown"', () {
        final segs = [
          _seg('no lang', 0, 1),
          _seg('also no lang', 1, 2),
        ];
        final groups =
            MultilingualTranscriptionService.groupByLanguage(segs);
        expect(groups.length, 1);
        expect(groups[0].language, 'unknown');
      });
    });

    group('LanguageGroup', () {
      test('startTime and endTime match first/last segment', () {
        final segs = [
          _seg('a', 1.5, 2.0, lang: 'en'),
          _seg('b', 2.0, 3.5, lang: 'en'),
        ];
        final group = LanguageGroup(language: 'en', segments: segs);
        expect(group.startTime, 1.5);
        expect(group.endTime, 3.5);
      });
    });
  });
}
