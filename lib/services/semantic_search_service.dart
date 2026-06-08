import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crispembed/crispembed.dart' show CrispEmbed;

import '../engines/transcription_engine.dart';
import 'history_service.dart';

/// §5.25.2 — Semantic transcript search via embeddings.
///
/// When a [CrispEmbed] instance is available, this service encodes
/// each segment's text as a dense vector and ranks by cosine similarity.
/// Otherwise it falls back to TF-IDF-style keyword relevance scoring.
class SemanticSearchService {
  SemanticSearchService._();

  /// Cache of segment-text → embedding vector so we don't re-encode
  /// the same text on every search. Keyed by the raw segment text.
  static final Map<String, Float32List> _embeddingCache = {};

  /// Clear the embedding cache (e.g. when the model changes or memory
  /// needs reclaiming).
  static void clearEmbeddingCache() => _embeddingCache.clear();

  /// Score each segment against a query. When [embedder] is provided,
  /// uses real vector embeddings + cosine similarity. Otherwise falls
  /// back to TF-IDF word-overlap scoring. Returns (index, score) pairs
  /// sorted by descending score. Score 0 = no match.
  ///
  /// When [historyEntry] is provided, pre-computed embeddings from the
  /// persisted entry are used first, avoiding on-the-fly encoding for
  /// entries saved after §5.25.2 embedding persistence was added.
  static List<SearchResult> search({
    required String query,
    required List<TranscriptionSegment> segments,
    int maxResults = 20,
    CrispEmbed? embedder,
    HistoryEntry? historyEntry,
  }) {
    if (query.trim().isEmpty || segments.isEmpty) return [];

    // Use real embeddings when available.
    if (embedder != null) {
      return _embeddingSearch(
        query: query,
        segments: segments,
        embedder: embedder,
        maxResults: maxResults,
        historyEntry: historyEntry,
      );
    }

    return _tfidfSearch(
      query: query,
      segments: segments,
      maxResults: maxResults,
    );
  }

  /// Embedding-based search: encode query + segments, rank by cosine.
  /// If [historyEntry] has pre-computed embeddings for a segment, those
  /// are used directly; otherwise falls back to the in-memory cache and
  /// finally to on-the-fly encoding via [embedder].
  static List<SearchResult> _embeddingSearch({
    required String query,
    required List<TranscriptionSegment> segments,
    required CrispEmbed embedder,
    required int maxResults,
    HistoryEntry? historyEntry,
  }) {
    final queryVec = embedder.encode(query);
    if (queryVec.isEmpty) {
      // Encoding failed — fall back to TF-IDF.
      return _tfidfSearch(
        query: query,
        segments: segments,
        maxResults: maxResults,
      );
    }

    final results = <SearchResult>[];
    for (var i = 0; i < segments.length; i++) {
      final text = segments[i].text;
      if (text.trim().isEmpty) continue;

      // 1) Try pre-computed embeddings from persisted history entry.
      Float32List? segVec = historyEntry?.embeddingForSegment(i);

      // 2) Fall back to in-memory cache.
      segVec ??= _embeddingCache[text];

      // 3) Fall back to on-the-fly encoding + cache.
      if (segVec == null) {
        segVec = embedder.encode(text);
        if (segVec.isNotEmpty) {
          _embeddingCache[text] = segVec;
        }
      }

      if (segVec.isEmpty) continue;

      final score = cosineSimilarity(queryVec, segVec);
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

  /// TF-IDF fallback search (original implementation).
  static List<SearchResult> _tfidfSearch({
    required String query,
    required List<TranscriptionSegment> segments,
    required int maxResults,
  }) {
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
