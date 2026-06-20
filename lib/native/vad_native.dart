// Native VAD entrypoint — calls the free C function `crispasr_vad_slices`
// directly (PLAN §9.5 fix).
//
// Why this exists: the `crispasr` binding only exposes `vadSlices()` as an
// *instance* method on `CrispASR`, whose constructor loads the given path as
// a whisper ASR context. Pointing that at a VAD model (Silero/whisper-vad)
// is wrong twice over: the legacy `vad()` path returns -2 ("model init
// failed") for non-whisper VAD models, and `dispose()` then runs
// `whisper_free` over a context that was never a real whisper model →
// SIGABRT. `crispasr_vad_slices` is the unified VAD dispatcher and a free
// function — it loads the VAD model itself, no whisper context required —
// so we call it straight through here and skip the doomed ctx entirely.
import 'dart:typed_data';

import 'ffi_import.dart';
import 'ffi_helpers_import.dart';
import 'crispasr_import.dart' as crispasr;

typedef _VadSlicesNative = Int32 Function(
    Pointer<Utf8>, Pointer<Float>, Int32, Int32, Float, Int32, Int32, Int32,
    Float, Int32, Pointer<Pointer<Float>>);
typedef _VadSlices = int Function(
    Pointer<Utf8>, Pointer<Float>, int, int, double, int, int, int,
    double, int, Pointer<Pointer<Float>>);
typedef _VadFreeNative = Void Function(Pointer<Float>);
typedef _VadFree = void Function(Pointer<Float>);

DynamicLibrary? _lib;
_VadSlices? _slices;
_VadFree? _free;
String? _loadedFrom;

void _ensure(String? libPath) {
  // Re-resolve if the caller pinned a different lib (tests pass CRISPASR_LIB).
  if (_lib != null && libPath == _loadedFrom) return;
  final lib = DynamicLibrary.open(libPath ?? crispasr.CrispASR.defaultLibName());
  _slices =
      lib.lookupFunction<_VadSlicesNative, _VadSlices>('crispasr_vad_slices');
  _free = lib.lookupFunction<_VadFreeNative, _VadFree>('crispasr_vad_free');
  _lib = lib;
  _loadedFrom = libPath;
}

/// Run the unified VAD dispatcher over [pcm] (mono 16 kHz float32) using the
/// model at [modelPath]. Returns speech spans in seconds. Throws on a
/// negative native error code (so a no-op dylib fails loudly).
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
}) {
  _ensure(libPath);
  final samples = calloc<Float>(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    samples[i] = pcm[i];
  }
  final modelPtr = modelPath.toNativeUtf8();
  final outPtr = calloc<Pointer<Float>>();
  try {
    final n = _slices!(
      modelPtr, samples, pcm.length, sampleRate, threshold,
      minSpeechMs, minSilenceMs, speechPadMs,
      maxChunkDurationS, nThreads, outPtr,
    );
    if (n < 0) throw Exception('VAD slices failed (error $n)');
    final spans = <crispasr.VadSpan>[];
    if (n > 0) {
      final data = outPtr.value;
      for (var i = 0; i < n; i++) {
        spans.add(crispasr.VadSpan(start: data[2 * i], end: data[2 * i + 1]));
      }
      _free!(data);
    }
    return spans;
  } finally {
    calloc.free(samples);
    calloc.free(modelPtr);
    calloc.free(outPtr);
  }
}
