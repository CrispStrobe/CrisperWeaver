import 'dart:typed_data';

import 'package:crisper_weaver/native/crispembed_import.dart';

/// Pure-Dart stand-in for the native [CrispEmbed] so tests drive the real
/// production search path without any FFI or model binaries.
class FakeCrispEmbed implements CrispEmbed {
  FakeCrispEmbed({
    this.hasColbert = false,
    this.hasAudio = false,
    this.modelPrefix = '',
  });
  @override
  final bool hasColbert;
  @override
  final bool hasAudio;
  final String modelPrefix;
  int encodeCalls = 0;
  int multivecCalls = 0;
  final encodeCallsByText = <String, int>{};
  final multivecCallsByText = <String, int>{};
  final multivecByText = <String, List<Float32List>>{};

  @override
  Float32List encode(String text) {
    encodeCalls++;
    encodeCallsByText.update(text, (n) => n + 1, ifAbsent: () => 1);
    return _denseFor(text);
  }

  @override
  List<Float32List> encodeMultivec(String text) {
    multivecCalls++;
    multivecCallsByText.update(text, (n) => n + 1, ifAbsent: () => 1);
    return multivecByText.putIfAbsent(
        text, () => _colbertTokens(text));
  }

  /// Deterministic per-word token vectors; identical words share vectors.
  List<Float32List> _colbertTokens(String text) {
    final words = text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return [for (final w in words) Float32List.fromList([w.length * 1.0, 1.0])];
  }

  Float32List _denseFor(String text) {
    final vec = Float32List(4);
    for (final w
        in text.toLowerCase().split(RegExp(r'\s+'))) {
      if (w.isEmpty) continue;
      vec[w.hashCode % 4] += 1.0;
    }
    return vec;
  }

  @override
  double colbertScore(Float32List queryVecs, int nQuery, Float32List docVecs,
      int nDoc, int dim) {
    var best = 0.0;
    for (var i = 0; i < nDoc; i++) {
      var bestQ = 0.0;
      for (var j = 0; j < nQuery; j++) {
        double dot = 0;
        for (var k = 0; k < dim; k++) {
          dot += docVecs[i * dim + k] * queryVecs[j * dim + k];
        }
        if (dot > bestQ) bestQ = dot;
      }
      if (bestQ > best) best = bestQ;
    }
    return best;
  }

  @override
  double rerank(String query, String document) =>
      document.toLowerCase().contains(query.toLowerCase()) ? 0.9 : 0.1;

  @override
  bool get isReranker => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
