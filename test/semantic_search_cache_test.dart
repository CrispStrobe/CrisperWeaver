import 'dart:typed_data';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/native/crispembed_import.dart';
import 'package:crisper_weaver/services/semantic_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

// No native constructor: exercises the production search entry point.
class CountingEmbedder implements CrispEmbed {
  final calls = <String, int>{};
  final queries = <Float32List>[];
  @override
  bool get hasColbert => true;
  @override
  Float32List encode(String text) => Float32List.fromList([1, 0]);
  @override
  List<Float32List> encodeMultivec(String text) {
    calls.update(text, (n) => n + 1, ifAbsent: () => 1);
    return [Float32List.fromList([text == 'better' ? 2 : 1, 0])];
  }
  @override
  double colbertScore(Float32List query, int nq, Float32List doc, int nd, int dim) {
    queries.add(query);
    return doc.first;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<TranscriptionSegment> segments(List<String> texts) => [
  for (var i = 0; i < texts.length; i++)
    TranscriptionSegment(text: texts[i], startTime: i.toDouble(), endTime: i + 1.0),
];

void main() {
  setUp(SemanticSearchService.clearEmbeddingCache);
  test('repeated search reuses document multivectors without changing ranking', () {
    final embedder = CountingEmbedder();
    final docs = segments(['ordinary', 'better', 'ordinary']);
    final first = SemanticSearchService.search(query: 'query', segments: docs, embedder: embedder);
    final second = SemanticSearchService.search(query: 'query', segments: docs, embedder: embedder);
    expect(first.map((r) => r.segmentIndex), [1, 0, 2]);
    expect(second.map((r) => r.score), first.map((r) => r.score));
    expect(embedder.calls['ordinary'], 1);
    expect(embedder.calls['better'], 1);
    expect(embedder.calls['query'], 2);
    expect(identical(embedder.queries[0], embedder.queries[1]), isTrue);
  });
}
