import 'dart:typed_data';

/// Spread-spectrum LSB audio watermarking for synthetic speech provenance.
///
/// Embeds a fixed payload into the least-significant bits of 16-bit PCM
/// samples inside a standard WAV file. The watermark payload encodes a
/// magic identifier (`CW01`), a Unix-epoch timestamp, and a synthetic-
/// content flag — enough to prove machine origin while staying well below
/// the audible threshold (only the LSB of each sample is touched).
class AudioWatermarkService {
  AudioWatermarkService._();

  /// Magic bytes identifying a CrisperWeaver watermark: ASCII `CW01`.
  static const int magic = 0x43573031;

  /// Number of PCM samples used to encode one payload bit (chip length).
  /// Higher = more robust against noise, lower = shorter minimum audio.
  static const int _chipsPerBit = 64;

  /// Total payload: 4 bytes magic + 4 bytes timestamp + 1 byte flags = 72 bits.
  static const int _payloadBits = 72;

  /// Minimum number of int16 PCM samples required in the data chunk.
  static const int _minSamples = _payloadBits * _chipsPerBit; // 4 608

  // ---------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------

  /// Embed a watermark into [wavBytes] (a complete WAV file with a 44-byte
  /// header). Returns a new `Uint8List` with the watermark baked into the
  /// PCM data region. If the audio is too short the input is returned
  /// unchanged.
  static Uint8List embedWatermark(
    Uint8List wavBytes, {
    DateTime? timestamp,
    bool synthetic = true,
  }) {
    if (wavBytes.length < 44 + _minSamples * 2) return wavBytes;

    final ts = timestamp ?? DateTime.now();
    final epochSec = ts.millisecondsSinceEpoch ~/ 1000;

    // Build 9-byte (72-bit) payload.
    final payload = Uint8List(9);
    final pbd = ByteData.view(payload.buffer);
    pbd.setUint32(0, magic, Endian.big);
    pbd.setUint32(4, epochSec, Endian.big);
    payload[8] = synthetic ? 0x01 : 0x00;

    // Clone the WAV bytes so we don't mutate the caller's buffer.
    final out = Uint8List.fromList(wavBytes);
    final bd = ByteData.view(out.buffer);

    // Walk through payload bits and stamp each across _chipsPerBit samples.
    for (var bit = 0; bit < _payloadBits; bit++) {
      final byteIdx = bit ~/ 8;
      final bitIdx = 7 - (bit % 8); // MSB first
      final payloadBit = (payload[byteIdx] >> bitIdx) & 1;

      for (var chip = 0; chip < _chipsPerBit; chip++) {
        final sampleIdx = bit * _chipsPerBit + chip;
        final offset = 44 + sampleIdx * 2;
        if (offset + 1 >= out.length) return out;

        var sample = bd.getInt16(offset, Endian.little);
        // Set LSB to the payload bit value.
        sample = (sample & ~1) | payloadBit;
        bd.setInt16(offset, sample, Endian.little);
      }
    }
    return out;
  }

  /// Attempt to detect and decode a CrisperWeaver watermark from [wavBytes].
  /// Returns `null` if the magic bytes don't match or the audio is too short.
  static WatermarkInfo? detectWatermark(Uint8List wavBytes) {
    if (wavBytes.length < 44 + _minSamples * 2) return null;

    final bd = ByteData.view(wavBytes.buffer);

    // Majority-vote LSB extraction: for each payload bit, count how many
    // of the _chipsPerBit samples have LSB=1 vs LSB=0. Since embedding
    // sets ALL chips to the same bit value, the majority (ideally 100%)
    // will agree.
    final extracted = Uint8List(9);
    for (var bit = 0; bit < _payloadBits; bit++) {
      var ones = 0;
      var total = 0;
      for (var chip = 0; chip < _chipsPerBit; chip++) {
        final sampleIdx = bit * _chipsPerBit + chip;
        final offset = 44 + sampleIdx * 2;
        if (offset + 1 >= wavBytes.length) break;
        final sample = bd.getInt16(offset, Endian.little);
        ones += sample & 1;
        total++;
      }
      if (total == 0) return null;
      final byteIdx = bit ~/ 8;
      final bitIdx = 7 - (bit % 8);
      if (ones > total ~/ 2) {
        extracted[byteIdx] |= (1 << bitIdx);
      }
    }

    // Check magic.
    final ebd = ByteData.view(extracted.buffer);
    final detectedMagic = ebd.getUint32(0, Endian.big);
    if (detectedMagic != magic) return null;

    final epochSec = ebd.getUint32(4, Endian.big);
    final flags = extracted[8];

    return WatermarkInfo(
      timestamp: DateTime.fromMillisecondsSinceEpoch(epochSec * 1000),
      synthetic: (flags & 0x01) != 0,
    );
  }
}

/// Decoded watermark payload.
class WatermarkInfo {
  final DateTime timestamp;
  final bool synthetic;

  const WatermarkInfo({required this.timestamp, required this.synthetic});

  @override
  String toString() =>
      'WatermarkInfo(timestamp: $timestamp, synthetic: $synthetic)';
}
