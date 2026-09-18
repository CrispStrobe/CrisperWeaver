// Cache isolation + bounding for §5.25.2 / §14.3l semantic search.
//
// Both caches key on the embedder instance. A text-only key would reuse a
// vector produced by a *different* model after the user switches embedders.
// The assertion below is the encode-call count rather than a vector
// comparison: with a text-only key the second embedder is never asked to
// encode, which is exactly the bug — a cache hit that shouldn't have been one.

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/semantic_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_crisp_embed.dart';

List<TranscriptionSegment> segments(List<String> texts) => [
      for (var i = 0; i < texts.length; i++)
        TranscriptionSegment(
          text: texts[i],
          startTime: i.toDouble(),
          endTime: i + 1.0,
        ),
    ];

void main() {
  setUp(SemanticSearchService.clearEmbeddingCache);

  group('model isolation', () {
    test('dense cache: a second embedder re-encodes text cached by the first',
        () {
      final a = FakeCrispEmbed();
      final b = FakeCrispEmbed();
      final docs = segments(['shared text']);

      SemanticSearchService.search(query: 'q', segments: docs, embedder: a);
      expect(a.encodeCallsByText['shared text'], 1);

      SemanticSearchService.search(query: 'q', segments: docs, embedder: b);
      expect(b.encodeCallsByText['shared text'], 1,
          reason: 'a text-only cache key would have served embedder A\'s '
              'vector to embedder B');
    });

    test(
        'multivec cache: a second embedder re-encodes text cached by the first',
        () {
      final a = FakeCrispEmbed(hasColbert: true);
      final b = FakeCrispEmbed(hasColbert: true);
      final docs = segments(['shared text']);

      SemanticSearchService.search(query: 'q', segments: docs, embedder: a);
      expect(a.multivecCallsByText['shared text'], 1);

      SemanticSearchService.search(query: 'q', segments: docs, embedder: b);
      expect(b.multivecCallsByText['shared text'], 1);
    });

    test('a repeat search under the same embedder is served from cache', () {
      final a = FakeCrispEmbed(hasColbert: true);
      final docs = segments(['shared text', 'other text']);
      SemanticSearchService.search(query: 'q', segments: docs, embedder: a);
      SemanticSearchService.search(query: 'q', segments: docs, embedder: a);
      expect(a.multivecCallsByText['shared text'], 1);
      expect(a.multivecCallsByText['other text'], 1);
    });
  });

  group('bounding', () {
    test('dense cache does not grow without limit', () {
      final embedder = FakeCrispEmbed();
      SemanticSearchService.search(
        query: 'q',
        segments: segments([for (var i = 0; i < 5000; i++) 'text $i']),
        embedder: embedder,
      );
      expect(SemanticSearchService.denseCacheSizeForTesting, lessThan(5000));
    });

    test('multivec cache does not grow without limit', () {
      final embedder = FakeCrispEmbed(hasColbert: true);
      SemanticSearchService.search(
        query: 'q',
        segments: segments([for (var i = 0; i < 3000; i++) 'text $i']),
        embedder: embedder,
      );
      expect(SemanticSearchService.multivecCacheSizeForTesting, lessThan(3000));
    });

    test('clearEmbeddingCache empties both caches', () {
      final embedder = FakeCrispEmbed(hasColbert: true);
      SemanticSearchService.search(
        query: 'q',
        segments: segments(['one', 'two']),
        embedder: embedder,
      );
      expect(SemanticSearchService.multivecCacheSizeForTesting,
          greaterThan(0));
      SemanticSearchService.clearEmbeddingCache();
      expect(SemanticSearchService.denseCacheSizeForTesting, 0);
      expect(SemanticSearchService.multivecCacheSizeForTesting, 0);
      embedder.multivecCallsByText.clear();
      SemanticSearchService.search(
        query: 'q',
        segments: segments(['one']),
        embedder: embedder,
      );
      expect(embedder.multivecCallsByText['one'], 1);
    });
  });
}
