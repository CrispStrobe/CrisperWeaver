// 16-bit PCM WAV writer carrying EU AI Act Art. 50(2) provenance metadata.
//
// Extracted from `TtsService._floatPcmToWavBytes` so the CLI
// (`bin/crisperweaver.dart`) writes byte-identical marking to the GUI. The
// CLI previously hand-rolled a bare 44-byte header, which meant headless
// synthesis shipped without the `LIST`/`INFO` provenance chunk, without a
// C2PA manifest, and without the beep disclaimer — the marking pipeline
// existed only on the Flutter side of the app.
//
// Pure Dart on purpose: `dart run` has no Flutter bindings, so anything the
// CLI shares with the app has to stay free of `package:flutter`.

import 'dart:typed_data';

/// Encodes float PCM as mono 16-bit WAV with a `LIST`/`INFO` provenance
/// chunk appended after the `data` chunk.
class MarkedWav {
  MarkedWav._();

  /// Mono 16-bit WAV bytes for [samples] at [sampleRate], with machine-
  /// readable provenance in a `LIST`/`INFO` chunk.
  ///
  /// The INFO chunk goes *after* the PCM data so parsers that stop reading
  /// at `data` still decode the audio. [generatorVersion] is passed in
  /// rather than read from AppConstants so this file stays dependency-free.
  ///
  /// Note what this marking is and is not: container metadata is trivially
  /// stripped by any re-encode. It complements the spread-spectrum
  /// watermark (which survives re-encoding); it does not substitute for it.
  static Uint8List encode(
    Float32List samples,
    int sampleRate, {
    required String generatorVersion,
    String? modelName,
    String? voiceId,
    DateTime? timestamp,
  }) {
    final dataBytes = samples.length * 2; // int16 mono

    final infoFields = <String, String>{
      'ISFT': 'CrisperWeaver $generatorVersion',
      'ICMT': 'AI-generated synthetic speech',
      'IART': '${modelName ?? "unknown"} TTS',
      'ICRD': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
      if (voiceId != null) 'IGNR': 'voice:$voiceId',
    };
    // Each INFO sub-chunk: 4-byte ID + 4-byte size + null-terminated
    // string (padded to even length).
    final infoChunks = <int>[];
    for (final entry in infoFields.entries) {
      final id = entry.key.codeUnits; // always 4 ASCII chars
      final strBytes = [...entry.value.codeUnits, 0]; // null-terminated
      if (strBytes.length.isOdd) strBytes.add(0); // pad to even
      final size = strBytes.length;
      infoChunks.addAll(id);
      infoChunks.addAll([
        size & 0xFF,
        (size >> 8) & 0xFF,
        (size >> 16) & 0xFF,
        (size >> 24) & 0xFF,
      ]);
      infoChunks.addAll(strBytes);
    }
    // LIST chunk: 'LIST' + uint32 size + 'INFO' + sub-chunks
    final listPayloadSize = 4 + infoChunks.length; // 'INFO' + sub-chunks
    final listChunkSize = 8 + listPayloadSize; // 'LIST' + size field + payload

    final fileBytes = 44 + dataBytes + listChunkSize;
    final out = Uint8List(fileBytes);
    final bd = ByteData.view(out.buffer);

    // RIFF header — total file size includes everything after 'RIFF'+size.
    out.setRange(0, 4, 'RIFF'.codeUnits);
    bd.setUint32(4, fileBytes - 8, Endian.little);
    out.setRange(8, 12, 'WAVE'.codeUnits);
    // fmt
    out.setRange(12, 16, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little); // chunk size
    bd.setUint16(20, 1, Endian.little); // PCM format
    bd.setUint16(22, 1, Endian.little); // mono
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bd.setUint16(32, 2, Endian.little); // block align
    bd.setUint16(34, 16, Endian.little); // bits per sample
    // data
    out.setRange(36, 40, 'data'.codeUnits);
    bd.setUint32(40, dataBytes, Endian.little);

    var off = 44;
    for (var i = 0; i < samples.length; i++) {
      var s = samples[i];
      if (!s.isFinite) s = 0.0;
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      bd.setInt16(off, (s * 32767).round(), Endian.little);
      off += 2;
    }

    // LIST INFO chunk — appended after PCM data.
    out.setRange(off, off + 4, 'LIST'.codeUnits);
    bd.setUint32(off + 4, listPayloadSize, Endian.little);
    out.setRange(off + 8, off + 12, 'INFO'.codeUnits);
    out.setRange(off + 12, off + 12 + infoChunks.length, infoChunks);

    return out;
  }
}
