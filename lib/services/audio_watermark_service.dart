import 'dart:math' as math;
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

  // ---------------------------------------------------------------
  // MP3 ID3v2 AI-provenance tags (EU AI Act Art. 50)
  // ---------------------------------------------------------------

  /// Prepend an ID3v2.3 tag with AI-provenance TXXX frames to [mp3Bytes].
  /// If the bytes already start with an ID3 header, they are returned
  /// unchanged to avoid double-tagging.
  ///
  /// Injected TXXX frames:
  /// - AI_GENERATED = "true"
  /// - GENERATOR = "CrisperWeaver"
  /// - AI_CONTENT_NOTICE = "This audio was synthesized by an AI
  ///   text-to-speech model. It is not a recording of a human speaker."
  static Uint8List injectMp3Metadata(Uint8List mp3Bytes) {
    // Don't double-tag if ID3 header is already present.
    if (mp3Bytes.length >= 3 &&
        mp3Bytes[0] == 0x49 && // 'I'
        mp3Bytes[1] == 0x44 && // 'D'
        mp3Bytes[2] == 0x33) { // '3'
      return mp3Bytes;
    }

    final frames = BytesBuilder(copy: false);
    frames.add(_makeTxxx('AI_GENERATED', 'true'));
    frames.add(_makeTxxx('GENERATOR', 'CrisperWeaver'));
    frames.add(_makeTxxx(
      'AI_CONTENT_NOTICE',
      'This audio was synthesized by an AI text-to-speech model. '
          'It is not a recording of a human speaker.',
    ));

    final framesBytes = frames.toBytes();
    final sz = framesBytes.length;

    // ID3v2.3 header: "ID3" + version(03 00) + flags(00) + synchsafe size.
    final header = Uint8List(10);
    header[0] = 0x49; // 'I'
    header[1] = 0x44; // 'D'
    header[2] = 0x33; // '3'
    header[3] = 0x03; // version 2.3
    header[4] = 0x00; // revision 0
    header[5] = 0x00; // flags
    // Synchsafe integer: 4 bytes, 7 bits each.
    header[6] = (sz >> 21) & 0x7F;
    header[7] = (sz >> 14) & 0x7F;
    header[8] = (sz >> 7) & 0x7F;
    header[9] = sz & 0x7F;

    final out = BytesBuilder(copy: false);
    out.add(header);
    out.add(framesBytes);
    out.add(mp3Bytes);
    return out.toBytes();
  }

  /// Build a single TXXX frame: "TXXX" + 4-byte BE size + 2-byte flags +
  /// encoding(0x00) + description + NUL + value.
  static Uint8List _makeTxxx(String description, String value) {
    final descBytes = description.codeUnits;
    final valBytes = value.codeUnits;
    // payload = encoding(1) + desc + NUL(1) + value
    final payloadLen = 1 + descBytes.length + 1 + valBytes.length;

    final frame = Uint8List(10 + payloadLen);
    // Frame ID
    frame[0] = 0x54; // 'T'
    frame[1] = 0x58; // 'X'
    frame[2] = 0x58; // 'X'
    frame[3] = 0x58; // 'X'
    // Size (4-byte big-endian)
    frame[4] = (payloadLen >> 24) & 0xFF;
    frame[5] = (payloadLen >> 16) & 0xFF;
    frame[6] = (payloadLen >> 8) & 0xFF;
    frame[7] = payloadLen & 0xFF;
    // Flags
    frame[8] = 0x00;
    frame[9] = 0x00;
    // Encoding: ISO-8859-1
    frame[10] = 0x00;
    // Description + NUL
    frame.setRange(11, 11 + descBytes.length, descBytes);
    frame[11 + descBytes.length] = 0x00;
    // Value
    frame.setRange(12 + descBytes.length, 12 + descBytes.length + valBytes.length, valBytes);

    return frame;
  }

  // ---------------------------------------------------------------
  // Beep-based AI disclaimer marker (EU AI Act Art. 50(4))
  // ---------------------------------------------------------------

  /// Generate a beep-based disclaimer marker for voice-cloned TTS output.
  ///
  /// Produces 3 short 880 Hz beeps (150 ms each) with 80 ms gaps, followed
  /// by 300 ms of silence. The returned float32 PCM is meant to be prepended
  /// to synthesised audio before WAV encoding.
  static Float32List generateBeepDisclaimer({int sampleRate = 24000}) {
    const int beepCount = 3;
    const double beepDurationSec = 0.150;
    const double gapDurationSec = 0.080;
    const double trailingSilenceSec = 0.300;
    const double freq = 880.0;
    const double fadeSec = 0.005; // 5 ms fade in/out

    final int beepSamples = (beepDurationSec * sampleRate).round();
    final int gapSamples = (gapDurationSec * sampleRate).round();
    final int silenceSamples = (trailingSilenceSec * sampleRate).round();
    final int fadeSamples = (fadeSec * sampleRate).round();

    final totalSamples =
        beepCount * beepSamples +
        (beepCount - 1) * gapSamples +
        silenceSamples;

    final out = Float32List(totalSamples);
    var pos = 0;

    for (var b = 0; b < beepCount; b++) {
      // Beep tone.
      for (var i = 0; i < beepSamples; i++) {
        final t = i / sampleRate;
        var sample = math.sin(2.0 * math.pi * freq * t);
        // Fade in.
        if (i < fadeSamples) {
          sample *= i / fadeSamples;
        }
        // Fade out.
        final fromEnd = beepSamples - 1 - i;
        if (fromEnd < fadeSamples) {
          sample *= fromEnd / fadeSamples;
        }
        out[pos++] = sample;
      }
      // Gap (silence) between beeps — not after the last one.
      if (b < beepCount - 1) {
        for (var i = 0; i < gapSamples; i++) {
          out[pos++] = 0.0;
        }
      }
    }

    // Trailing silence after beeps.
    // pos already past last beep; remaining samples are zero-initialised.
    // (Float32List default is 0.0.)

    return out;
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
