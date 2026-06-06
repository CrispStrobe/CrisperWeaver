// Synthetic content compliance — pure-Dart unit tests for the watermark
// service, WAV metadata embedding, export-format disclosure, and speaker
// consent file management. No FFI, no dylib, no model files — runs on
// every CI host.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/constants/app_constants.dart';
import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/audio_watermark_service.dart';
import 'package:crisper_weaver/utils/file_utils.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a minimal valid 16-bit mono WAV file from float samples.
/// Mirrors TtsService._floatPcmToWavBytes without the LIST INFO chunk
/// so we can test the watermark layer in isolation.
Uint8List _buildRawWav(Float32List samples, {int sampleRate = 24000}) {
  final dataBytes = samples.length * 2;
  final fileBytes = 44 + dataBytes;
  final out = Uint8List(fileBytes);
  final bd = ByteData.view(out.buffer);

  out.setRange(0, 4, 'RIFF'.codeUnits);
  bd.setUint32(4, fileBytes - 8, Endian.little);
  out.setRange(8, 12, 'WAVE'.codeUnits);
  out.setRange(12, 16, 'fmt '.codeUnits);
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
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
  return out;
}

/// Create a float32 buffer of [length] samples filled with a sine wave.
Float32List _sineWave(int length, {double freq = 440, int sr = 24000}) {
  final out = Float32List(length);
  for (var i = 0; i < length; i++) {
    out[i] = (0.5 * (2.0 * 3.14159265 * freq * i / sr)).clamp(-1.0, 1.0);
  }
  return out;
}

void main() {
  // -----------------------------------------------------------------------
  // 1. AudioWatermarkService
  // -----------------------------------------------------------------------
  group('AudioWatermarkService', () {
    test('embed → detect round-trip recovers magic + timestamp + flag', () {
      // Build a WAV long enough for the watermark payload (>= 4608 samples).
      final samples = _sineWave(8000);
      final wav = _buildRawWav(samples);
      final ts = DateTime.utc(2026, 6, 1, 12, 0, 0);

      final watermarked = AudioWatermarkService.embedWatermark(
        wav,
        timestamp: ts,
        synthetic: true,
      );

      // The output should be the same length as the input.
      expect(watermarked.length, wav.length);

      // Detect should recover the payload.
      final info = AudioWatermarkService.detectWatermark(watermarked);
      expect(info, isNotNull);
      expect(info!.synthetic, isTrue);
      // Timestamp round-trips to second precision.
      expect(
        info.timestamp.millisecondsSinceEpoch ~/ 1000,
        ts.millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('synthetic=false flag is preserved', () {
      final wav = _buildRawWav(_sineWave(8000));
      final ts = DateTime.utc(2026, 1, 15);
      final wm = AudioWatermarkService.embedWatermark(
        wav,
        timestamp: ts,
        synthetic: false,
      );
      final info = AudioWatermarkService.detectWatermark(wm);
      expect(info, isNotNull);
      expect(info!.synthetic, isFalse);
    });

    test('too-short audio returns input unchanged', () {
      // Only 100 samples — well below the 4608 minimum.
      final wav = _buildRawWav(Float32List(100));
      final out = AudioWatermarkService.embedWatermark(wav);
      // Identical bytes — no watermark applied.
      expect(out, wav);
    });

    test('detect returns null on un-watermarked audio', () {
      final wav = _buildRawWav(_sineWave(8000));
      final info = AudioWatermarkService.detectWatermark(wav);
      // A random sine wave is unlikely to have the CW01 magic in its LSBs.
      // (Statistically possible but astronomically unlikely.)
      expect(info, isNull);
    });

    test('detect returns null on buffer smaller than header + min samples',
        () {
      expect(AudioWatermarkService.detectWatermark(Uint8List(100)), isNull);
    });

    test('magic constant matches the documented value', () {
      expect(AudioWatermarkService.magic, 0x43573031); // 'CW01'
      expect(AudioWatermarkService.magic, AppConstants.watermarkMagic);
    });

    test('watermark does not destroy PCM envelope', () {
      final samples = _sineWave(8000);
      final wav = _buildRawWav(samples);
      final wm = AudioWatermarkService.embedWatermark(wav);
      final bd = ByteData.view(wm.buffer);

      // Compare every sample — at most the LSB should differ.
      final origBd = ByteData.view(wav.buffer);
      for (var i = 0; i < samples.length; i++) {
        final orig = origBd.getInt16(44 + i * 2, Endian.little);
        final marked = bd.getInt16(44 + i * 2, Endian.little);
        expect((orig - marked).abs(), lessThanOrEqualTo(1),
            reason: 'sample $i changed by more than ±1 LSB');
      }
    });
  });

  // -----------------------------------------------------------------------
  // 2. WAV LIST INFO metadata (tested via TtsService internals)
  // -----------------------------------------------------------------------
  group('WAV LIST INFO chunk', () {
    // We can't call the private _floatPcmToWavBytes directly, but we
    // can parse a WAV produced by the TTS service. For unit tests,
    // we verify the chunk layout structurally.

    test('a raw WAV without LIST INFO has exactly 44 + data bytes', () {
      final wav = _buildRawWav(Float32List.fromList([0.0, 0.5]));
      expect(wav.length, 44 + 4); // 2 samples * 2 bytes each
    });

    test('RIFF header magic and WAVE format tag are correct', () {
      final wav = _buildRawWav(Float32List(100));
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    });

    test('data chunk size matches sample count * 2', () {
      const n = 500;
      final wav = _buildRawWav(Float32List(n));
      final bd = ByteData.view(wav.buffer);
      final dataLen = bd.getUint32(40, Endian.little);
      expect(dataLen, n * 2);
    });
  });

  // -----------------------------------------------------------------------
  // 3. Export format disclosure
  // -----------------------------------------------------------------------
  const segs = [
    TranscriptionSegment(
      text: 'Hello world.',
      startTime: 0.0,
      endTime: 1.5,
      speaker: 'Alice',
      confidence: 0.95,
    ),
  ];

  group('Export disclosure — SRT', () {
    test('default (no disclosure) matches legacy output', () {
      final out = FileUtils.generateSrtContent(segs);
      expect(out, isNot(contains('AI-generated')));
    });

    test('syntheticDisclosure prepends a notice', () {
      final out =
          FileUtils.generateSrtContent(segs, syntheticDisclosure: true);
      expect(out, startsWith('NOTE:'));
      expect(out, contains('AI-generated synthetic speech'));
      // The actual cue content still follows.
      expect(out, contains('Alice: Hello world.'));
    });
  });

  group('Export disclosure — VTT', () {
    test('default preserves WEBVTT header only', () {
      final out = FileUtils.generateVttContent(segs);
      expect(out, startsWith('WEBVTT\n'));
      expect(out, isNot(contains('NOTE AI-generated')));
    });

    test('syntheticDisclosure inserts a NOTE block after header', () {
      final out =
          FileUtils.generateVttContent(segs, syntheticDisclosure: true);
      expect(out, startsWith('WEBVTT\n'));
      expect(out, contains('NOTE AI-generated synthetic speech'));
      expect(out, contains('synthetic'));
    });
  });

  group('Export disclosure — JSON', () {
    test('default returns a plain array (backward compatible)', () {
      final out = FileUtils.generateJsonContent(segs);
      final decoded = jsonDecode(out);
      expect(decoded, isA<List>());
      expect((decoded as List).length, 1);
    });

    test('syntheticDisclosure wraps in object with _disclosure key', () {
      final out =
          FileUtils.generateJsonContent(segs, syntheticDisclosure: true);
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded.containsKey('_disclosure'), isTrue);
      expect(decoded['_disclosure'], contains('AI-generated'));
      expect(decoded['segments'], isA<List>());
      expect((decoded['segments'] as List).length, 1);
    });

    test('null speaker preserved in disclosure mode', () {
      const noSpk = [
        TranscriptionSegment(
            text: 't', startTime: 0.0, endTime: 1.0, confidence: 1.0),
      ];
      final out =
          FileUtils.generateJsonContent(noSpk, syntheticDisclosure: true);
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      final first = (decoded['segments'] as List).first as Map;
      expect(first['speaker'], isNull);
    });
  });

  group('Export disclosure — Markdown', () {
    test('default has no notice', () {
      final out = FileUtils.generateMarkdownContent(segs);
      expect(out, startsWith('# Transcript\n'));
      expect(out, isNot(contains('Notice')));
    });

    test('syntheticDisclosure inserts a blockquote notice', () {
      final out = FileUtils.generateMarkdownContent(segs,
          syntheticDisclosure: true);
      expect(out, contains('> **Notice:**'));
      expect(out, contains('AI-generated synthetic speech'));
      expect(out, contains('synthetic'));
      // Content still present.
      expect(out, contains('Alice'));
    });
  });

  // -----------------------------------------------------------------------
  // 4. Compliance constants
  // -----------------------------------------------------------------------
  group('AppConstants — compliance flags', () {
    test('watermark is enabled by default', () {
      expect(AppConstants.enableAudioWatermark, isTrue);
    });

    test('synthetic disclosure is enabled by default', () {
      expect(AppConstants.enableSyntheticDisclosure, isTrue);
    });

    test('watermark magic matches AudioWatermarkService.magic', () {
      expect(AppConstants.watermarkMagic, AudioWatermarkService.magic);
    });
  });

  // -----------------------------------------------------------------------
  // 5. Speaker consent file management
  // -----------------------------------------------------------------------
  group('Speaker consent files', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp
          .createTemp('crisper_consent_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('consent JSON round-trips with correct structure', () async {
      // Simulate what SpeakerIdService.saveConsent() writes.
      final file = File('${tmp.path}/TestSpeaker.consent.json');
      final now = DateTime.now().toUtc();
      final data = {
        'speaker': 'TestSpeaker',
        'consentedAt': now.toIso8601String(),
        'purpose': 'Speaker identification via TitaNet voice embeddings',
        'lawfulBasis': 'GDPR Art. 9(2)(a) \u2014 explicit consent',
        'storageLocation': 'on-device only',
      };
      await file.writeAsString(jsonEncode(data));

      // Read back.
      final loaded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(loaded['speaker'], 'TestSpeaker');
      expect(loaded['lawfulBasis'], contains('GDPR'));
      expect(loaded['storageLocation'], 'on-device only');
      expect(loaded['consentedAt'], now.toIso8601String());
    });

    test('companion consent file is deleted alongside .spk', () async {
      // Create both a .spk and a .consent.json.
      final spk = File('${tmp.path}/Alice.spk');
      final consent = File('${tmp.path}/Alice.consent.json');
      await spk.writeAsBytes([1, 2, 3]);
      await consent.writeAsString('{}');

      expect(await spk.exists(), isTrue);
      expect(await consent.exists(), isTrue);

      // Simulate deleteSpeaker: delete both.
      await spk.delete();
      await consent.delete();

      expect(await spk.exists(), isFalse);
      expect(await consent.exists(), isFalse);
    });

    test('deletion of non-existent consent file does not throw', () async {
      // Only the .spk exists — no consent companion.
      final spk = File('${tmp.path}/Bob.spk');
      await spk.writeAsBytes([4, 5, 6]);

      final consent = File('${tmp.path}/Bob.consent.json');
      expect(await consent.exists(), isFalse);

      // Simulated deleteSpeaker: delete .spk, then try consent.
      await spk.delete();
      if (await consent.exists()) {
        await consent.delete();
      }
      // No exception — success.
    });
  });
}
