// Web stub for vad_native.dart — FFI is unavailable on web, where VAD is
// served by the cloud HfSpace engine, not the local dylib. Returns no spans.
import 'dart:typed_data';

import 'crispasr_import.dart' as crispasr;

List<crispasr.VadSpan> vadSlicesNative(
  String modelPath,
  Float32List pcm, {
  int sampleRate = 16000,
  double threshold = 0.0,
  int minSpeechMs = 250,
  int minSilenceMs = 100,
  int speechPadMs = 30,
  double maxChunkDurationS = 30.0,
  int nThreads = 4,
  String? libPath,
}) =>
    const [];
