import 'dart:math' as math;
import 'dart:typed_data';

import '../engines/transcription_engine.dart';
import 'log_service.dart';

/// §5.25.2 — Semantic transcript search via embeddings.
///
/// Scaffold for meaning-based search over transcript history. When a
/// CrispEmbed binding becomes available, this service will:
///   1. Embed each segment's text as a 2048-d vector
///   2. Embed the user's search query
///   3. Rank segments by cosine similarity
///
/// Until then, this provides a fallback TF-IDF-style keyword relevance
/// scorer that's still better than substring matching for natural
/// language queries.
class SemanticSearchService {
  SemanticSearchService._();

  /// Score each segment against a query using simple TF-IDF-style
  /// word overlap with IDF weighting. Returns (index, score) pairs
  /// sorted by descending score. Score 0 = no match.
  static List<SearchResult> search({
    required String query,
    required List<TranscriptionSegment> segments,
    int maxResults = 20,
  }) {
    if (query.trim().isEmpty || segments.isEmpty) return [];

    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty) return [];

    // Compute document frequencies
    final df = <String, int>{};
    final segTokens = <List<String>>[];
    for (final seg in segments) {
      final tokens = _tokenize(seg.text);
      segTokens.add(tokens);
      for (final unique in tokens.toSet()) {
        df[unique] = (df[unique] ?? 0) + 1;
      }
    }

    final n = segments.length;
    final results = <SearchResult>[];

    for (var i = 0; i < segments.length; i++) {
      final tokens = segTokens[i];
      if (tokens.isEmpty) continue;

      double score = 0;
      for (final qt in queryTerms) {
        final tf = tokens.where((t) => t == qt).length / tokens.length;
        final idf = math.log((n + 1) / ((df[qt] ?? 0) + 1)) + 1;
        score += tf * idf;
      }

      if (score > 0) {
        results.add(SearchResult(
          segmentIndex: i,
          score: score,
          segment: segments[i],
        ));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(maxResults).toList();
  }

  /// Cosine similarity between two vectors. Used when real embeddings
  /// are available.
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length || a.isEmpty) return 0;
    double dot = 0, normA = 0, normB = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    return denom == 0 ? 0 : dot / denom;
  }

  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1) // Skip single chars
        .toList();
  }
}

/// A single search result pointing to a transcript segment.
class SearchResult {
  final int segmentIndex;
  final double score;
  final TranscriptionSegment segment;

  const SearchResult({
    required this.segmentIndex,
    required this.score,
    required this.segment,
  });
}
