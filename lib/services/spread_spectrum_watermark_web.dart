import 'dart:typed_data';

/// Web stub — watermarking uses 64-bit integer arithmetic that dart2js
/// cannot represent. On web the embed/detect paths are no-ops.
class SpreadSpectrumWatermark {
  SpreadSpectrumWatermark._();

  static const int key = 0;
  static const int nBins = 32;

  static Float32List embed(Float32List pcm, {double alpha = 0.08}) => pcm;

  static double detect(Float32List pcm) => 0.0;
}
