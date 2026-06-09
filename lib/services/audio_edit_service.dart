// AudioEditService — PLAN §5.1.5 audio editing (trim / cut / split).
//
// Operates on Float32 PCM samples loaded via CrispASR's miniaudio
// FFI (`crispasr.decodeAudioFile`). All outputs are 16 kHz mono
// little-endian PCM-WAV files — the same format the transcription
// pipeline expects, so a "Crop + Transcribe" handoff is one
// file-handoff with no re-decode needed.
//
// Why WAV-only? Encoding back to mp3 / m4a / opus would need
// FFmpeg or an FFI codec — out of v1 scope. Users who want
// re-encoded output can pipe the WAV through their own ffmpeg
// post-hoc. WAV at 16 kHz mono is ~32 KB/s, so a 1-hour file is
// ~115 MB — large but bearable for the typical use case
// (extract → transcribe → discard the WAV).
//
// Cross-platform: pure Dart + dart:io + the existing crispasr
// decoder. No native edit-side code, no FFmpeg, no platform
// channels. Works identically on every platform CrisperWeaver
// ships on (including iOS, since the only writes are to
// `getApplicationDocumentsDirectory()`).
//
// Operations:
//   • trim(src, t0, t1) — emit samples in [t0, t1) as a WAV.
//   • cut(src, regions) — remove `regions` from `src`; emit
//     the splice as a WAV.
//   • split(src, splitPoints) — emit N+1 files where the splits
//     fall at the given seconds, ordered earliest first.
//
// All time inputs are floats in seconds; the service clamps
// negative or out-of-bounds values rather than throwing — same
// convention as the existing chunked-whisper offset routing
// (§5.23 Q3).

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'log_service.dart';

/// One contiguous removal range in [cut] — both bounds in
/// seconds, half-open `[start, end)`. Regions are sorted +
/// non-overlapping per `cut`'s contract.
class AudioCutRegion {
  const AudioCutRegion(this.startSec, this.endSec);
  final double startSec;
  final double endSec;
}

/// Decoded source — what the service caches between operations
/// so a "trim then immediately cut" doesn't re-decode the file
/// (the FFI decode is the slowest step for large files). Public
/// so the UI can probe the duration without spinning up the
/// service first.
class DecodedSource {
  const DecodedSource({
    required this.path,
    required this.samples,
    required this.sampleRate,
  });
  final String path;
  final Float32List samples;
  final int sampleRate;

  double get durationSec => samples.length / sampleRate;
  int secondsToSample(double s) {
    if (s <= 0) return 0;
    final i = (s * sampleRate).round();
    return i > samples.length ? samples.length : i;
  }
}

class AudioEditService {
  AudioEditService();

  /// Decode a source file once, cache by path so repeat
  /// operations on the same file don't re-decode. Caller can
  /// drop the cache via [invalidate] when memory pressure
  /// matters (we hold the full Float32 buffer in RAM — a 1-hour
  /// 16 kHz mono buffer is ~230 MB).
  final Map<String, DecodedSource> _cache = {};

  Future<DecodedSource> decode(String absolutePath) async {
    final cached = _cache[absolutePath];
    if (cached != null) return cached;
    // Run on a worker isolate so the UI thread doesn't stall on
    // a 1-hour decode. Same pattern AudioPrefetchService uses
    // for §5.23 Q2 v1 pipeline parallelism — keeps the editor
    // responsive while the source loads.
    final decoded = await Isolate.run(() {
      return crispasr.decodeAudioFile(absolutePath);
    });
    final src = DecodedSource(
      path: absolutePath,
      samples: decoded.samples,
      sampleRate: decoded.sampleRate,
    );
    _cache[absolutePath] = src;
    return src;
  }

  void invalidate([String? path]) {
    if (path == null) {
      _cache.clear();
    } else {
      _cache.remove(path);
    }
  }

  /// §5.1.5 — emit samples in `[t0, t1)` from the source as a
  /// WAV file at `destination`. Returns the file. Negative t0
  /// clamps to 0; t1 > duration clamps to the end. Empty range
  /// (after clamp) writes a zero-sample WAV — caller's choice
  /// to validate UI-side if they want to forbid it.
  Future<File> trim({
    required String sourcePath,
    required double startSec,
    required double endSec,
    required String destinationPath,
  }) async {
    final src = await decode(sourcePath);
    final i0 = src.secondsToSample(startSec);
    final i1 = src.secondsToSample(endSec);
    final lo = i0 < i1 ? i0 : i1;
    final hi = i1 > i0 ? i1 : i0;
    final slice = (lo == 0 && hi == src.samples.length)
        ? src.samples
        : Float32List.sublistView(src.samples, lo, hi);
    return _writeWav(destinationPath, slice, src.sampleRate);
  }

  /// §5.1.5 — emit `source` minus every region in `regions` as
  /// a single WAV. Regions are clamped + sorted + collapsed (so
  /// `[(2,4), (3,5)]` is treated as a single `(2, 5)` removal),
  /// caller doesn't need to pre-process.
  Future<File> cut({
    required String sourcePath,
    required List<AudioCutRegion> regions,
    required String destinationPath,
  }) async {
    final src = await decode(sourcePath);
    if (regions.isEmpty) {
      return _writeWav(destinationPath, src.samples, src.sampleRate);
    }
    // Normalise: clamp + sort + merge overlapping.
    final ranges = regions
        .map((r) => [
              src.secondsToSample(r.startSec.clamp(0.0, src.durationSec)),
              src.secondsToSample(r.endSec.clamp(0.0, src.durationSec)),
            ])
        .where((p) => p[1] > p[0])
        .toList()
      ..sort((a, b) => a[0].compareTo(b[0]));
    final merged = <List<int>>[];
    for (final r in ranges) {
      if (merged.isEmpty || r[0] > merged.last[1]) {
        merged.add(r);
      } else {
        merged.last[1] = r[1] > merged.last[1] ? r[1] : merged.last[1];
      }
    }
    // Walk the source emitting kept slices between the cuts.
    final out = BytesBuilder();
    var cursor = 0;
    for (final r in merged) {
      if (r[0] > cursor) {
        _appendSamplesAsBytes(out, src.samples, cursor, r[0]);
      }
      cursor = r[1];
    }
    if (cursor < src.samples.length) {
      _appendSamplesAsBytes(out, src.samples, cursor, src.samples.length);
    }
    final raw = out.takeBytes();
    final nFrames = raw.length ~/ 4;
    final spliced = Float32List.view(raw.buffer, raw.offsetInBytes, nFrames);
    return _writeWav(destinationPath, spliced, src.sampleRate);
  }

  /// §5.1.5 — split `source` at every `splitPoint`, emitting
  /// N+1 WAVs where N is the number of unique splits. Output
  /// filename comes from the `destinationBuilder` callback so
  /// the UI can pick its own numbering convention
  /// (`"<base>-part-001.wav"` is the typical choice).
  Future<List<File>> split({
    required String sourcePath,
    required List<double> splitPoints,
    required String Function(int partIndex) destinationBuilder,
  }) async {
    final src = await decode(sourcePath);
    final pts = splitPoints
        .map((s) => src.secondsToSample(s.clamp(0.0, src.durationSec)))
        .where((s) => s > 0 && s < src.samples.length)
        .toSet()
        .toList()
      ..sort();
    final out = <File>[];
    var cursor = 0;
    var partIndex = 0;
    for (final p in pts) {
      final slice = Float32List.sublistView(src.samples, cursor, p);
      out.add(await _writeWav(
          destinationBuilder(partIndex), slice, src.sampleRate));
      partIndex++;
      cursor = p;
    }
    // Tail (always emit — even when no split points produce one
    // file covering the whole source).
    final tail =
        Float32List.sublistView(src.samples, cursor, src.samples.length);
    out.add(
        await _writeWav(destinationBuilder(partIndex), tail, src.sampleRate));
    return out;
  }

  // ---------------------------------------------------------------
  // WAV encoder — 16-bit PCM little-endian; sample-rate matches
  // the source (typically 16 kHz from miniaudio's decode); always
  // mono since CrispASR's decoder downmixes. RIFF/WAVE/fmt + data
  // chunks per the standard. ~44-byte header.
  // ---------------------------------------------------------------

  Future<File> _writeWav(
      String destinationPath, Float32List samples, int sampleRate) async {
    final dir = File(destinationPath).parent;
    if (!await dir.exists()) await dir.create(recursive: true);
    final bytes = _encodeWav(samples, sampleRate);
    final file = File(destinationPath);
    await file.writeAsBytes(bytes, flush: true);
    Log.instance.i('audio-edit',
        'wrote ${samples.length} samples to $destinationPath');
    return file;
  }

  /// Pure encoder — pulled out so it's unit-testable without
  /// touching the filesystem.
  static Uint8List _encodeWav(Float32List samples, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final dataLen = samples.length * channels * (bitsPerSample ~/ 8);
    final totalLen = 36 + dataLen;
    final bb = BytesBuilder();
    void w(String ascii) => bb.add(ascii.codeUnits);
    void wu32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      bb.add(b.buffer.asUint8List());
    }
    void wu16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      bb.add(b.buffer.asUint8List());
    }
    // RIFF header.
    w('RIFF');
    wu32(totalLen);
    w('WAVE');
    // fmt chunk.
    w('fmt ');
    wu32(16); // PCM fmt chunk size
    wu16(1); // PCM format code
    wu16(channels);
    wu32(sampleRate);
    wu32(byteRate);
    wu16(channels * (bitsPerSample ~/ 8)); // block align
    wu16(bitsPerSample);
    // data chunk.
    w('data');
    wu32(dataLen);
    // PCM: Float32 [-1, 1] → Int16 little-endian.
    final pcm = ByteData(dataLen);
    for (var i = 0; i < samples.length; i++) {
      var s = samples[i];
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      final v = (s * 32767.0).round();
      pcm.setInt16(i * 2, v, Endian.little);
    }
    bb.add(pcm.buffer.asUint8List());
    return bb.takeBytes();
  }

  /// Append `samples[lo..hi)` to `out` as raw float32-le bytes.
  /// Used by [cut] to splice non-contiguous slices before the
  /// final WAV encode step.
  static void _appendSamplesAsBytes(
      BytesBuilder out, Float32List samples, int lo, int hi) {
    final view =
        Float32List.sublistView(samples, lo, hi);
    out.add(view.buffer.asUint8List(view.offsetInBytes, view.lengthInBytes));
  }
}

final audioEditServiceProvider =
    Provider<AudioEditService>((ref) => AudioEditService());
