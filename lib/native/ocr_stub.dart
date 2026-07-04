// Web stub for CrispEmbed OCR classes — provides the type surface
// but every operation throws UnsupportedError.

import 'dart:typed_data';

/// Stub for CrispEmbedOcr (pix2tex math OCR).
class CrispEmbedOcr {
  CrispEmbedOcr(String modelPath, {int nThreads = 4, String? libPath}) {
    throw UnsupportedError('CrispEmbedOcr is not available on web');
  }

  String? recognizeGray(Float32List pixels, int width, int height) {
    throw UnsupportedError('CrispEmbedOcr is not available on web');
  }

  String? recognizeRaw(Uint8List bytes, int width, int height, int channels) {
    throw UnsupportedError('CrispEmbedOcr is not available on web');
  }

  void dispose() {}
}

/// Stub for CrispEmbedHmerOcr (handwritten math OCR).
class CrispEmbedHmerOcr {
  CrispEmbedHmerOcr(String modelPath, {int nThreads = 4, String? libPath}) {
    throw UnsupportedError('CrispEmbedHmerOcr is not available on web');
  }

  String? recognizeGray(Float32List pixels, int width, int height) {
    throw UnsupportedError('CrispEmbedHmerOcr is not available on web');
  }

  String? recognizeRaw(Uint8List bytes, int width, int height, int channels) {
    throw UnsupportedError('CrispEmbedHmerOcr is not available on web');
  }

  void dispose() {}
}
