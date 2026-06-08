// Tests for SemanticSearchService — the TF-IDF fallback ranking used
// when real embeddings aren't available (§5.25.2).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/semantic_search_service.dart';

List<TranscriptionSegment> _segs(List<String> texts) => [
      for (var i = 0; i < texts.length; i++)
        TranscriptionSegment(
          text: texts[i],
          startTime: i * 10.0,
          endTime: (i + 1) * 10.0,
        ),
    ];

void main() {
  group('SemanticSearchService.search', () {
    test('returns empty for empty query', () {
      final results = SemanticSearchService.search(
        query: '',
        segments: _segs(['hello world']),
      );
      expect(results, isEmpty);
    });

    test('returns empty for empty segments', () {
      final results = SemanticSearchService.search(
        query: 'hello',
        segments: [],
      );
      expect(results, isEmpty);
    });

    test('returns empty when no terms match', () {
      final results = SemanticSearchService.search(
        query: 'quantum',
        segments: _segs(['the cat sat on the mat']),
      );
      expect(results, isEmpty);
    });

    test('ranks exact keyword match above partial overlap', () {
      final results = SemanticSearchService.search(
        query: 'kubernetes deployment',
        segments: _segs([
          'we discussed the new deployment pipeline',
          'kubernetes deployment strategy for production',
          'the weather was nice today',
        ]),
      );
      expect(results, isNotEmpty);
      // The segment mentioning both terms should rank first
      expect(results.first.segmentIndex, 1);
    });

    test('respects maxResults', () {
      final segs = _segs(List.generate(50, (i) => 'word$i is interesting'));
      final results = SemanticSearchService.search(
        query: 'interesting',
        segments: segs,
        maxResults: 5,
      );
      expect(results.length, 5);
    });

    test('scores are positive for matching segments', () {
      final results = SemanticSearchService.search(
        query: 'flutter dart',
        segments: _segs([
          'flutter is a UI toolkit',
          'dart is a programming language',
          'flutter and dart work together',
        ]),
      );
      for (final r in results) {
        expect(r.score, greaterThan(0));
      }
    });

    test('IDF boosts rare terms over common ones', () {
      // "machine" appears in all segments, "learning" only in one
      final results = SemanticSearchService.search(
        query: 'machine learning',
        segments: _segs([
          'machine is a common word here',
          'machine learning is powerful',
          'machine operates the factory',
        ]),
      );
      expect(results.first.segmentIndex, 1);
    });
  });

  group('SemanticSearchService.cosineSimilarity', () {
    test('identical vectors return 1.0', () {
      final v = Float32List.fromList([1.0, 2.0, 3.0]);
      expect(SemanticSearchService.cosineSimilarity(v, v), closeTo(1.0, 1e-6));
    });

    test('orthogonal vectors return 0.0', () {
      final a = Float32List.fromList([1.0, 0.0]);
      final b = Float32List.fromList([0.0, 1.0]);
      expect(SemanticSearchService.cosineSimilarity(a, b), closeTo(0.0, 1e-6));
    });

    test('opposite vectors return -1.0', () {
      final a = Float32List.fromList([1.0, 0.0]);
      final b = Float32List.fromList([-1.0, 0.0]);
      expect(
          SemanticSearchService.cosineSimilarity(a, b), closeTo(-1.0, 1e-6));
    });

    test('empty vectors return 0.0', () {
      final a = Float32List(0);
      final b = Float32List(0);
      expect(SemanticSearchService.cosineSimilarity(a, b), 0.0);
    });

    test('mismatched lengths return 0.0', () {
      final a = Float32List.fromList([1.0, 2.0]);
      final b = Float32List.fromList([1.0, 2.0, 3.0]);
      expect(SemanticSearchService.cosineSimilarity(a, b), 0.0);
    });
  });
}
