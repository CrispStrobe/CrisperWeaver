// Web stub for CrispEmbed scan cleanup.

import 'dart:typed_data';

class ScanCleanupResult {
  final Uint8List pixels;
  final int width;
  final int height;
  const ScanCleanupResult({
    required this.pixels,
    required this.width,
    required this.height,
  });
}

class CrispScanCleanup {
  CrispScanCleanup({String? modelPath, int nThreads = 4, String? libPath}) {
    throw UnsupportedError('CrispScanCleanup is not available on web');
  }

  ScanCleanupResult process(
    Uint8List pixels,
    int width,
    int height, {
    int channels = 3,
    bool deskew = true,
    bool cropBorders = true,
    bool whitenBackground = true,
    bool binarize = false,
  }) {
    throw UnsupportedError('CrispScanCleanup is not available on web');
  }

  void dispose() {}
}
