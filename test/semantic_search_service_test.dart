// Tests for SemanticSearchService — the TF-IDF fallback ranking used
// when real embeddings aren't available (§5.25.2), plus §12.3a reranker.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/history_service.dart';
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

  group('§5.25.2 cross-modal audio embedding in search', () {
    test('audioEmbedding dimension mismatch is ignored gracefully', () {
      // Simulate text embedder producing 384-d vectors but audio
      // embedding stored as 2048-d — dimensionality mismatch should
      // cause the audio score to be ignored (0), and text TF-IDF
      // fallback still works.
      final entry = HistoryEntry(
        id: 'test-audio-dim-mismatch',
        createdAt: DateTime.now(),
        engineId: 'crispasr',
        segments: _segs(['machine learning is powerful']),
        // 2048-d audio embedding (omni model) vs text-only search
        audioEmbedding: List.filled(2048, 0.5),
      );
      // Without an embedder, falls back to TF-IDF — audioEmbedding
      // is simply not used.
      final results = SemanticSearchService.search(
        query: 'machine learning',
        segments: entry.segments,
        historyEntry: entry,
      );
      expect(results, isNotEmpty);
      expect(results.first.score, greaterThan(0));
    });

    test('audioEmbedding null does not break search', () {
      final entry = HistoryEntry(
        id: 'test-audio-null',
        createdAt: DateTime.now(),
        engineId: 'crispasr',
        segments: _segs(['flutter dart widgets']),
        audioEmbedding: null,
      );
      final results = SemanticSearchService.search(
        query: 'flutter',
        segments: entry.segments,
        historyEntry: entry,
      );
      expect(results, isNotEmpty);
    });

    test('audioEmbedding empty list does not break search', () {
      final entry = HistoryEntry(
        id: 'test-audio-empty',
        createdAt: DateTime.now(),
        engineId: 'crispasr',
        segments: _segs(['hello world']),
        audioEmbedding: const [],
      );
      final results = SemanticSearchService.search(
        query: 'hello',
        segments: entry.segments,
        historyEntry: entry,
      );
      expect(results, isNotEmpty);
    });
  });

  group('§12.3b BidirLM-Omni audio embedding parameter', () {
    test('search accepts audioData parameter without embedder', () {
      // Without an embedder, audioData is simply ignored (falls back to
      // TF-IDF). This verifies the parameter doesn't break the API.
      final results = SemanticSearchService.search(
        query: 'hello',
        segments: _segs(['hello world', 'goodbye world']),
        audioData: Float32List.fromList(List.filled(16000, 0.1)),
      );
      expect(results, isNotEmpty);
    });

    test('search accepts audioData with null embedder gracefully', () {
      final results = SemanticSearchService.search(
        query: 'test',
        segments: _segs(['test audio embedding']),
        embedder: null,
        audioData: Float32List(16000),
      );
      expect(results, isNotEmpty);
      expect(results.first.score, greaterThan(0));
    });
  });

  group('§12.3a reranker integration', () {
    final candidates = [
      SearchResult(
        segmentIndex: 0,
        score: 0.9,
        segment: TranscriptionSegment(
            text: 'the weather is nice', startTime: 0, endTime: 10),
      ),
      SearchResult(
        segmentIndex: 1,
        score: 0.8,
        segment: TranscriptionSegment(
            text: 'machine learning rocks', startTime: 10, endTime: 20),
      ),
      SearchResult(
        segmentIndex: 2,
        score: 0.7,
        segment: TranscriptionSegment(
            text: 'deep learning models', startTime: 20, endTime: 30),
      ),
    ];

    test('rerankWithScorer re-orders candidates by scorer output', () {
      // Scorer reverses the original cosine ranking: gives highest
      // score to "deep learning" when searching for "learning".
      final results = SemanticSearchService.rerankWithScorer(
        query: 'learning',
        candidates: candidates,
        scorer: (q, doc) {
          if (doc.contains('deep')) return 0.95;
          if (doc.contains('machine')) return 0.85;
          return 0.1;
        },
        maxResults: 3,
      );
      expect(results.length, 3);
      // "deep learning models" should now be first (was third)
      expect(results[0].segmentIndex, 2);
      expect(results[0].score, closeTo(0.95, 1e-6));
      // "machine learning rocks" second
      expect(results[1].segmentIndex, 1);
    });

    test('rerankWithScorer respects maxResults', () {
      final results = SemanticSearchService.rerankWithScorer(
        query: 'test',
        candidates: candidates,
        scorer: (q, doc) => 0.5,
        maxResults: 2,
      );
      expect(results.length, 2);
    });

    test('rerankWithScorer handles scorer exception gracefully', () {
      var callCount = 0;
      final results = SemanticSearchService.rerankWithScorer(
        query: 'test',
        candidates: candidates,
        scorer: (q, doc) {
          callCount++;
          if (callCount == 2) throw Exception('model error');
          return 0.5;
        },
        maxResults: 10,
      );
      // All 3 candidates should still be in results (failed one keeps
      // its original cosine score).
      expect(results.length, 3);
    });

    test('rerankWithScorer skips empty-text segments', () {
      final candidatesWithEmpty = [
        ...candidates,
        SearchResult(
          segmentIndex: 3,
          score: 0.6,
          segment: TranscriptionSegment(
              text: '   ', startTime: 30, endTime: 40),
        ),
      ];
      final results = SemanticSearchService.rerankWithScorer(
        query: 'test',
        candidates: candidatesWithEmpty,
        scorer: (q, doc) => 0.5,
        maxResults: 10,
      );
      // Empty-text segment should be skipped
      expect(results.length, 3);
      expect(results.any((r) => r.segmentIndex == 3), isFalse);
    });
  });
}
