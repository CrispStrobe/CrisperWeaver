// Web stub for package:crispembed — provides the CrispEmbed type surface
// but every FFI-backed operation throws UnsupportedError.
//
// Updated July 2026 to match CrispEmbed 0.13.0 API: reranker, sparse,
// ColBERT, vision, config, and audio APIs.

import 'dart:typed_data';

/// Result from bi-encoder reranking.
class RerankResult {
  final int index;
  final double score;
  final String? document;
  RerankResult({required this.index, required this.score, this.document});
}

class CrispEmbed {
  CrispEmbed(String modelPath,
      {int nThreads = 0, String? libPath, bool? autoDownload}) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- Capability queries --
  bool get hasAudio => false;
  bool get hasVision => false;
  bool get hasSparse => false;
  bool get hasColbert => false;
  bool get isReranker => false;

  // -- Dimension --
  int get dim {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- Config --
  void setDim(int dim) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  void setPrefix(String prefix) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  String get ctxQueryPrefix => '';
  String get ctxPassagePrefix => '';

  // -- Dense embeddings --
  Float32List encode(String text) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  List<Float32List> encodeBatch(List<String> texts) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- Sparse retrieval (BGE-M3 / SPLADE) --
  Map<int, double> encodeSparse(String text) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- ColBERT multi-vector --
  List<Float32List> encodeMultivec(String text) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  double colbertScore(Float32List queryVecs, int nQuery, Float32List docVecs,
      int nDoc, int dim) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- Cross-encoder reranking --
  double rerank(String query, String document) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- Bi-encoder reranking --
  List<RerankResult> rerankBiencoder(String query, List<String> documents,
      {int? topN, bool returnDocuments = false}) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- Audio (BidirLM-Omni) --
  Float32List encodeAudio(Float32List pcm) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- Vision (BidirLM-Omni) --
  Float32List encodeImage(Float32List pixelPatches, Int32List gridThw) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  (Float32List, List<Float32List>) encodeImageRaw(
      Float32List pixelPatches, Int32List gridThw) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  Float32List encodeImageFile(String path) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  Float32List encodeTextWithImageFile(String text, String imagePath) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- LoRA hot-swap --
  bool get hasLora => false;

  bool setLora(String? adapterName) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  String get activeLora => '';

  List<String> listLora() {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  // -- Lifecycle --
  void dispose() {}
}
