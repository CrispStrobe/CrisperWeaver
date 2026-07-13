// Web stub for `glint_native.dart` — no `dart:ffi`, so codec ops are
// unavailable and callers fall back to the WAV path. Mirrors the value
// types the native side re-exports so shared code compiles on web.
import 'dart:typed_data';

/// Output codec for [glintNativeEncode]. Mirrors `glint`'s enum.
enum GlintCodec { mp3, aac, opus }

/// Decoded audio: interleaved float PCM plus its stream parameters.
class GlintDecodedAudio {
  final Float32List pcm;
  final int sampleRate;
  final int channels;
  GlintDecodedAudio(this.pcm, this.sampleRate, this.channels);
}

bool glintNativeAvailable() => false;

Uint8List glintNativeEncode(
  Float32List pcm,
  int channels,
  int sampleRate,
  GlintCodec codec, {
  int bitrate = 128,
}) =>
    throw UnsupportedError('glint codec is not available on web');

GlintDecodedAudio glintNativeDecode(Uint8List data, {int rate = 0}) =>
    throw UnsupportedError('glint codec is not available on web');
