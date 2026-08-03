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
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../utils/marked_wav.dart';
import 'audio_watermark_service.dart';
import 'content_provenance_service.dart';
import 'glint_codec_service.dart';
import 'log_service.dart';

/// One contiguous removal range in [cut] — both bounds in
/// seconds, half-open `[start, end)`. Regions are sorted +
/// non-overlapping per `cut`'s contract.
/// Thrown when AI-generated audio would be written to a container that cannot
/// carry a machine-readable provenance mark (EU AI Act Art. 50(2)).
///
/// AAC and Opus have no manifest slot on this path, so the spread-spectrum
/// watermark in the samples would be the only surviving mark — a
/// machine-readable channel with no human-readable or standard counterpart.
/// `AudioEditService.exportEncoded` refuses by default; callers that want the
/// export anyway pass `allowUnmarkedContainer: true` and take the decision
/// explicitly.
class UnmarkableContainerException implements Exception {
  const UnmarkableContainerException(this.format);
  final String format;

  @override
  String toString() =>
      'Refusing to export AI-generated audio as .$format: the container '
      'cannot carry a provenance manifest, so the output would be marked '
      'only by the audio watermark. Export as WAV or MP3, or pass '
      'allowUnmarkedContainer: true to accept this deliberately.';
}

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

  /// C2PA manifests probed off source files, keyed by absolute path.
  /// A null *value* means "probed, carries none" — distinct from an absent
  /// key, so a source without provenance is not re-probed on every part of
  /// a multi-output [split].
  final Map<String, Map<String, dynamic>?> _provenanceCache = {};

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
      _provenanceCache.clear();
    } else {
      _cache.remove(path);
      _provenanceCache.remove(path);
      _provenanceCache.remove(File(path).absolute.path);
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
    return _writeWav(destinationPath, slice, src.sampleRate,
        sourcePath: sourcePath, editAction: 'trim');
  }

  /// Export the decoded source — optionally just the `[startSec, endSec)`
  /// slice — as a compressed MP3 / AAC-LC / Opus file via the bundled
  /// libglint (no external ffmpeg). glint auto-resamples to a codec-valid
  /// rate. Throws [StateError] when the codec is unavailable, so callers
  /// should offer this only when [GlintCodecService.isAvailable] and fall
  /// back to [trim]/[_writeWav] (WAV) otherwise.
  Future<File> exportEncoded({
    required String sourcePath,
    required GlintFormat format,
    required String destinationPath,
    double? startSec,
    double? endSec,
    int bitrateKbps = 128,
    /// Art. 50(2) escape hatch. When the source carries a provenance
    /// manifest and the target container cannot, this method **refuses** by
    /// default rather than emitting audio whose only mark is the watermark.
    /// Pass true to accept that trade deliberately; it is logged either way.
    bool allowUnmarkedContainer = false,
  }) async {
    final src = await decode(sourcePath);
    var samples = src.samples;
    if (startSec != null || endSec != null) {
      final i0 = src.secondsToSample(startSec ?? 0);
      final i1 = src.secondsToSample(endSec ?? src.durationSec);
      final lo = i0 < i1 ? i0 : i1;
      final hi = i1 > i0 ? i1 : i0;
      if (!(lo == 0 && hi == src.samples.length)) {
        samples = Float32List.sublistView(src.samples, lo, hi);
      }
    }
    final encoded = await const GlintCodecService().encodePcmToFile(
      samples,
      channels: 1, // decode() yields mono
      sampleRate: src.sampleRate,
      format: format,
      destinationPath: destinationPath,
      bitrateKbps: bitrateKbps,
    );

    // EU AI Act Art. 50(2) on the compressed path. `AI_ACT_RISK.md` §7.4
    // said "no MP3 export exists" — true of the UI, which never wired this
    // up, but false of the service, and a marking gap that only exists in
    // unreachable code is still a gap waiting for the day someone reaches
    // it. MP3 can carry ID3v2 provenance; AAC and Opus cannot here, so on
    // those the watermark in the samples is the only surviving mark and we
    // say so rather than let it pass silently.
    final provenance =
        await _sourceProvenance(File(sourcePath).absolute.path);
    if (provenance == null) return encoded;

    final (model, voice) = ContentProvenanceService.modelAndVoiceOf(provenance);
    if (format.extension == 'mp3') {
      final tagged = AudioWatermarkService.injectMp3Metadata(
        await encoded.readAsBytes(),
        modelName: model,
        voiceId: voice,
      );
      await encoded.writeAsBytes(tagged, flush: true);
      Log.instance.i('audio-edit', 'carried AI provenance into MP3 ID3v2',
          fields: {'dest': destinationPath});
    } else if (allowUnmarkedContainer) {
      Log.instance.w('audio-edit',
          'encoded AI-generated audio to a container that cannot carry a '
          'provenance manifest — only the spread-spectrum watermark marks '
          'this output (EU AI Act Art. 50(2))',
          fields: {'format': format.extension, 'dest': destinationPath});
    } else {
      // Fail closed. `AI_ACT_RISK.md` §7.4 left this open — "mark-and-warn or
      // refuse?" — and deferred it until the path had a UI caller. Deciding
      // it then would have meant deciding it under pressure, with a feature
      // waiting on the answer; deciding it now costs nothing, because nothing
      // in the shipped app reaches this branch.
      //
      // Delete first. The encoder has already written the file, so returning
      // an error while leaving unmarked AI-generated audio on disk would be
      // the worst of both outcomes.
      try {
        await encoded.delete();
      } catch (_) {/* best effort — the throw below is the contract */}
      Log.instance.w('audio-edit',
          'refused to export AI-generated audio to a container that cannot '
          'carry a provenance manifest (EU AI Act Art. 50(2))',
          fields: {'format': format.extension, 'dest': destinationPath});
      throw UnmarkableContainerException(format.extension);
    }
    return encoded;
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
      return _writeWav(destinationPath, src.samples, src.sampleRate,
          sourcePath: sourcePath, editAction: 'cut');
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
    return _writeWav(destinationPath, spliced, src.sampleRate,
        sourcePath: sourcePath, editAction: 'cut');
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
          destinationBuilder(partIndex), slice, src.sampleRate,
          sourcePath: sourcePath, editAction: 'split'));
      partIndex++;
      cursor = p;
    }
    // Tail (always emit — even when no split points produce one
    // file covering the whole source).
    final tail =
        Float32List.sublistView(src.samples, cursor, src.samples.length);
    out.add(await _writeWav(destinationBuilder(partIndex), tail, src.sampleRate,
        sourcePath: sourcePath, editAction: 'split'));
    return out;
  }

  // ---------------------------------------------------------------
  // WAV encoder — 16-bit PCM little-endian; sample-rate matches
  // the source (typically 16 kHz from miniaudio's decode); always
  // mono since CrispASR's decoder downmixes. RIFF/WAVE/fmt + data
  // chunks per the standard. ~44-byte header.
  // ---------------------------------------------------------------

  Future<File> _writeWav(
      String destinationPath, Float32List samples, int sampleRate,
      {String? sourcePath, String editAction = 'edit'}) async {
    final dir = File(destinationPath).parent;
    if (!await dir.exists()) await dir.create(recursive: true);

    // EU AI Act Art. 50(2): if the source carries a provenance manifest,
    // the derived file has to keep it. Decoding to PCM and re-encoding a
    // bare 44-byte header used to drop the manifest and the LIST/INFO tags
    // outright — the app stripping marking the app itself had written.
    // The watermark survives regardless (it lives in the samples), so this
    // restores the machine-readable half rather than the robust half.
    final source = sourcePath == null
        ? null
        : await _sourceProvenance(File(sourcePath).absolute.path);

    Uint8List bytes;
    if (source == null) {
      bytes = _encodeWav(samples, sampleRate);
    } else {
      final (model, voice) =
          ContentProvenanceService.modelAndVoiceOf(source);
      // MarkedWav restores the LIST/INFO tags; the manifest below restores
      // the C2PA claim, carrying the original creation action plus a record
      // of this edit rather than asserting the clip was generated just now.
      bytes = MarkedWav.encode(
        samples,
        sampleRate,
        generatorVersion: AppConstants.appVersion,
        modelName: model,
        voiceId: voice,
      );
      bytes = ContentProvenanceService.injectManifestIntoWav(
        bytes,
        ContentProvenanceService.deriveEditedManifest(
          source,
          editAction: editAction,
          generator: 'CrisperWeaver',
          generatorVersion: AppConstants.appVersion,
        ),
      );
      Log.instance.i('audio-edit',
          'carried AI provenance across $editAction',
          fields: {'model': model ?? 'unknown', 'dest': destinationPath});
    }

    final file = File(destinationPath);
    await file.writeAsBytes(bytes, flush: true);
    Log.instance.i('audio-edit',
        'wrote ${samples.length} samples to $destinationPath');
    return file;
  }

  /// The C2PA manifest on [absolutePath], or null when the file is not a
  /// WAV or carries none. Cached alongside the decoded-PCM cache.
  ///
  /// Walks the RIFF chunk table with a [RandomAccessFile] instead of
  /// reading the file in: an hour of 16 kHz mono is ~115 MB, and the
  /// common case is a plain recording with no manifest at all, so slurping
  /// it to answer "no" would make every trim pay for the check.
  ///
  /// Visible for testing because the edit operations that use it all go
  /// through the CrispASR decoder, so a test of the marking behaviour
  /// would otherwise need the dylib and be skipped on CI — which is how
  /// the gap this fixes survived two audits.
  @visibleForTesting
  Future<Map<String, dynamic>?> sourceProvenance(String absolutePath) =>
      _sourceProvenance(absolutePath);

  Future<Map<String, dynamic>?> _sourceProvenance(String absolutePath) async {
    if (_provenanceCache.containsKey(absolutePath)) {
      return _provenanceCache[absolutePath];
    }
    Map<String, dynamic>? manifest;
    RandomAccessFile? raf;
    try {
      raf = await File(absolutePath).open();
      final header = await raf.read(12);
      if (header.length == 12 &&
          String.fromCharCodes(header.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(header.sublist(8, 12)) == 'WAVE') {
        final length = await raf.length();
        var offset = 12;
        while (offset + 8 <= length) {
          await raf.setPosition(offset);
          final head = await raf.read(8);
          if (head.length < 8) break;
          final id = String.fromCharCodes(head.sublist(0, 4));
          final size = ByteData.sublistView(Uint8List.fromList(head))
              .getUint32(4, Endian.little);
          if (id == 'c2pa') {
            if (offset + 8 + size <= length) {
              manifest = ContentProvenanceService.decodeManifestPayload(
                  await raf.read(size));
            }
            break;
          }
          // Chunk sizes are padded to an even boundary.
          offset += 8 + size + (size.isOdd ? 1 : 0);
        }
      }
    } catch (e) {
      // A source we cannot read provenance from is treated as carrying
      // none — the edit still succeeds, it just cannot preserve a mark it
      // could not find. Logged so it is not silent.
      Log.instance.w('audio-edit', 'provenance probe failed',
          fields: {'path': absolutePath, 'err': e.toString()});
    } finally {
      await raf?.close();
    }
    _provenanceCache[absolutePath] = manifest;
    return manifest;
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
