// Web stub for package:crispembed — provides the CrispEmbed type surface
// but every FFI-backed operation throws UnsupportedError.

import 'dart:typed_data';

class CrispEmbed {
  CrispEmbed(String modelPath, {int nThreads = 0, String? libPath, bool? autoDownload}) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  bool get hasAudio => false;
  bool get hasVision => false;

  Float32List encode(String text) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  List<Float32List> encodeBatch(List<String> texts) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  Float32List encodeAudio(Float32List pcm) {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  int get dim {
    throw UnsupportedError('CrispEmbed is not available on web');
  }

  void dispose() {}
}
