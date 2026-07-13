// GlintCodecService — on-device MP3 / AAC-LC / Opus encode + decode via
// the bundled `libglint` (clean-room codec suite). This is what lets the
// app export compressed audio and import `.mp3` / `.aac` / `.opus` files
// without shelling out to an external ffmpeg binary.
//
// Everything degrades gracefully: when `libglint` isn't bundled on the
// running platform (or on web), [isAvailable] is false and callers fall
// back to the existing WAV / ffmpeg path. All encode/decode work is pure
// PCM in / bytes out, so it composes with AudioEditService's Float32
// pipeline (16 kHz mono, ±1.0) directly.

import 'dart:io';
import 'dart:typed_data';

import '../native/glint_native_import.dart' as glint;
import 'log_service.dart';

export '../native/glint_native_import.dart' show GlintCodec, GlintDecodedAudio;

/// A compressed output format the app can produce on-device.
class GlintFormat {
  const GlintFormat(this.codec, this.extension, this.label);

  final glint.GlintCodec codec;

  /// File extension without the leading dot (`mp3` / `aac` / `opus`).
  final String extension;

  /// Human-facing label for a format picker.
  final String label;

  static const mp3 = GlintFormat(glint.GlintCodec.mp3, 'mp3', 'MP3');
  static const aac = GlintFormat(glint.GlintCodec.aac, 'aac', 'AAC');
  static const opus = GlintFormat(glint.GlintCodec.opus, 'opus', 'Opus');

  static const all = <GlintFormat>[mp3, aac, opus];
}

class GlintCodecService {
  const GlintCodecService();

  /// Whether the bundled `libglint` can be loaded on this platform. When
  /// false, callers must fall back to WAV output / ffmpeg decode.
  static bool get isAvailable => glint.glintNativeAvailable();

  /// The file extensions this service can decode on-device when
  /// available (format is auto-detected from the header, so the list is
  /// advisory for UI file filters).
  static const decodableExtensions = <String>['mp3', 'aac', 'opus', 'ogg'];

  /// Encode interleaved float PCM (±1.0, 1–2 channels) at [sampleRate]
  /// to a complete compressed stream. glint auto-resamples to a
  /// codec-valid rate. Throws [StateError] if the codec is unavailable
  /// or the input is empty — callers should check [isAvailable] first.
  Uint8List encodePcm(
    Float32List pcm, {
    required int channels,
    required int sampleRate,
    required GlintFormat format,
    int bitrateKbps = 128,
  }) {
    if (!isAvailable) {
      throw StateError('glint codec unavailable on this platform');
    }
    if (pcm.isEmpty) throw StateError('encodePcm: empty PCM');
    return glint.glintNativeEncode(
      pcm,
      channels,
      sampleRate,
      format.codec,
      bitrate: bitrateKbps,
    );
  }

  /// Encode [pcm] and write it to [destinationPath], returning the file.
  Future<File> encodePcmToFile(
    Float32List pcm, {
    required int channels,
    required int sampleRate,
    required GlintFormat format,
    required String destinationPath,
    int bitrateKbps = 128,
  }) async {
    final bytes = encodePcm(
      pcm,
      channels: channels,
      sampleRate: sampleRate,
      format: format,
      bitrateKbps: bitrateKbps,
    );
    final file = File(destinationPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    Log.instance.i('glint', 'encoded ${format.label}', fields: {
      'path': destinationPath,
      'in_frames': pcm.length ~/ (channels == 0 ? 1 : channels),
      'out_bytes': bytes.length,
      'bitrate_kbps': bitrateKbps,
    });
    return file;
  }

  /// Decode a compressed stream (MP3 / AAC-LC / Ogg-Opus, auto-detected)
  /// to interleaved float PCM. [rate] resamples the output (0 = native).
  /// Throws when the codec is unavailable or the input can't be decoded.
  glint.GlintDecodedAudio decodeBytes(Uint8List bytes, {int rate = 0}) {
    if (!isAvailable) {
      throw StateError('glint codec unavailable on this platform');
    }
    return glint.glintNativeDecode(bytes, rate: rate);
  }

  /// Decode the file at [path] to interleaved float PCM.
  Future<glint.GlintDecodedAudio> decodeFile(String path, {int rate = 0}) async {
    final bytes = await File(path).readAsBytes();
    return decodeBytes(bytes, rate: rate);
  }

  /// Whether [path]'s extension is one glint can decode on-device (used
  /// to decide the glint-vs-ffmpeg import path). Case-insensitive.
  static bool canDecodePath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = path.substring(dot + 1).toLowerCase();
    return decodableExtensions.contains(ext);
  }
}
