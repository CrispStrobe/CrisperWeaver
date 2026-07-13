// Native glint codec entrypoint — thin wrapper over the `glint` FFI
// package so the rest of the app can encode/decode MP3 / AAC-LC / Opus
// without importing `dart:ffi` directly (keeps the web build compiling
// against the stub sibling `glint_native_stub.dart`).
//
// The `glint` package's own loader resolves the shared library by name
// (`libglint.dylib` / `libglint.so` / `glint.dll`, and
// `DynamicLibrary.process()` on iOS where it's statically linked). We
// probe the same way here so callers can gate on availability and fall
// back to the WAV/ffmpeg path when the lib isn't bundled on a platform.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:glint/glint.dart' as glint;

// Re-export the value types callers need so they don't depend on the
// `glint` package directly (the web stub mirrors these names).
export 'package:glint/glint.dart' show GlintCodec, GlintDecodedAudio;

bool? _available;

/// Whether the bundled `libglint` can be loaded and exposes the codec
/// entrypoint on this platform. Cached after the first probe.
bool glintNativeAvailable() {
  final cached = _available;
  if (cached != null) return cached;
  bool ok;
  try {
    final DynamicLibrary lib;
    if (Platform.isIOS) {
      // Statically linked into the app binary on iOS.
      lib = DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.open('libglint.dylib');
    } else if (Platform.isWindows) {
      lib = DynamicLibrary.open('glint.dll');
    } else {
      // Android + Linux.
      lib = DynamicLibrary.open('libglint.so');
    }
    ok = lib.providesSymbol('glint_encode_audio');
  } catch (_) {
    ok = false;
  }
  return _available = ok;
}

/// One-call encode: interleaved float PCM (±1.0, 1–2 channels) at any
/// rate to a complete MP3 / AAC-LC / Ogg-Opus stream. The input is
/// auto-resampled to a codec-valid rate by glint.
Uint8List glintNativeEncode(
  Float32List pcm,
  int channels,
  int sampleRate,
  glint.GlintCodec codec, {
  int bitrate = 128,
}) =>
    glint.glintEncodeAudio(pcm, channels, sampleRate, codec, bitrate: bitrate);

/// Decode a whole encoded stream (MP3 / AAC-LC / Ogg-Opus, format
/// auto-detected from the header) to interleaved float PCM. [rate]
/// resamples the output (0 = keep native).
glint.GlintDecodedAudio glintNativeDecode(Uint8List data, {int rate = 0}) =>
    glint.glintDecodeAudio(data, rate: rate);
