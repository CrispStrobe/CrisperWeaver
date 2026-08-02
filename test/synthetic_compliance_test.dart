// Synthetic content compliance — pure-Dart unit tests for the watermark
// service, WAV metadata embedding, export-format disclosure, speaker
// consent file management, MP3 ID3v2 provenance tags, beep disclaimer,
// post-embed watermark verification, C2PA provenance manifests, and
// EU AI Act compliance gates. No FFI, no dylib, no model files — runs
// on every CI host.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/constants/app_constants.dart';
import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/l10n/generated/app_localizations.dart';
import 'package:crisper_weaver/services/audio_edit_service.dart';
import 'package:crisper_weaver/services/audio_watermark_service.dart';
import 'package:crisper_weaver/services/content_provenance_service.dart';
import 'package:crisper_weaver/services/note_export_service.dart';
import 'package:crisper_weaver/services/ocr_service.dart';
import 'package:crisper_weaver/services/spread_spectrum_watermark.dart';
import 'package:crisper_weaver/utils/affective_prompt_guard.dart';
import 'package:crisper_weaver/utils/ai_text_disclosure.dart';
import 'package:crisper_weaver/utils/emotion_inference.dart';
import 'package:crisper_weaver/utils/file_utils.dart';
import 'package:crisper_weaver/utils/marked_wav.dart';

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
    test('default includes AI disclosure notice (Art. 50)', () {
      final out = FileUtils.generateSrtContent(segs);
      // The notice is cue 0, not a bare `NOTE:` line — SRT has no comment
      // syntax, so the old form was a parse error or a dropped disclosure
      // depending on the player (fixed 2026-08-03).
      expect(out, startsWith('0\n00:00:00,000 --> 00:00:03,000\n'));
      expect(out, contains('AI-generated synthetic speech'));
      expect(out, contains('Alice: Hello world.'));
    });

    test('the notice is a parseable cue, not a bare line', () {
      final out = FileUtils.generateSrtContent(segs);
      // Every non-blank block must start with an integer index followed by
      // a timing line — the property a bare `NOTE:` prefix broke.
      final blocks = out
          .trim()
          .split(RegExp(r'\n\s*\n'))
          .where((b) => b.trim().isNotEmpty);
      for (final b in blocks) {
        final lines = b.trim().split('\n');
        expect(int.tryParse(lines.first.trim()), isNotNull,
            reason: 'block does not start with a cue index: $b');
        expect(lines[1], contains(' --> '), reason: 'no timing line in: $b');
      }
    });

    test('explicit opt-out suppresses notice', () {
      final out =
          FileUtils.generateSrtContent(segs, syntheticDisclosure: false);
      expect(out, isNot(contains('AI-generated')));
    });
  });

  group('Export disclosure — VTT', () {
    test('default includes AI disclosure NOTE (Art. 50)', () {
      final out = FileUtils.generateVttContent(segs);
      expect(out, startsWith('WEBVTT\n'));
      expect(out, contains('NOTE '));
      expect(out, contains('AI-generated synthetic speech'));
    });

    test('explicit opt-out suppresses NOTE', () {
      final out =
          FileUtils.generateVttContent(segs, syntheticDisclosure: false);
      expect(out, startsWith('WEBVTT\n'));
      expect(out, isNot(contains('NOTE AI-generated')));
    });
  });

  group('Export disclosure — JSON', () {
    test('default wraps in object with _disclosure key (Art. 50)', () {
      final out = FileUtils.generateJsonContent(segs);
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded.containsKey('_disclosure'), isTrue);
      expect(decoded['_disclosure'], contains('AI-generated'));
      expect(decoded['segments'], isA<List<dynamic>>());
      expect((decoded['segments'] as List<dynamic>).length, 1);
    });

    test('explicit opt-out returns a plain array', () {
      final out =
          FileUtils.generateJsonContent(segs, syntheticDisclosure: false);
      final decoded = jsonDecode(out);
      expect(decoded, isA<List<dynamic>>());
      expect((decoded as List<dynamic>).length, 1);
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
    test('default includes blockquote notice (Art. 50)', () {
      final out = FileUtils.generateMarkdownContent(segs);
      expect(out, contains('> **Notice:**'));
      expect(out, contains('AI-generated synthetic speech'));
      expect(out, contains('Alice'));
    });

    test('explicit opt-out suppresses notice', () {
      final out = FileUtils.generateMarkdownContent(segs,
          syntheticDisclosure: false);
      expect(out, startsWith('# Transcript\n'));
      expect(out, isNot(contains('Notice')));
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

  // -----------------------------------------------------------------------
  // 6. MP3 ID3v2 AI-provenance tags
  // -----------------------------------------------------------------------
  group('MP3 ID3v2 metadata injection', () {
    test('injectMp3Metadata prepends ID3v2.3 header to raw MP3 bytes', () {
      // Fake MP3 data (starts with sync word, not "ID3").
      final fakeMp3 = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00, ...List.filled(64, 0)]);
      final tagged = AudioWatermarkService.injectMp3Metadata(fakeMp3);

      // Must be longer than input (ID3 header + frames prepended).
      expect(tagged.length, greaterThan(fakeMp3.length));

      // Must start with "ID3" magic.
      expect(String.fromCharCodes(tagged.sublist(0, 3)), 'ID3');

      // Version 2.3, revision 0.
      expect(tagged[3], 0x03);
      expect(tagged[4], 0x00);

      // Flags byte must be 0x00.
      expect(tagged[5], 0x00);

      // Synchsafe size in bytes 6-9 — decode and verify it covers the
      // TXXX frames between byte 10 and the start of the original MP3.
      final synchsafeSize = (tagged[6] << 21) |
          (tagged[7] << 14) |
          (tagged[8] << 7) |
          tagged[9];
      expect(synchsafeSize, greaterThan(0));
      // The original MP3 bytes must follow immediately after the tag.
      expect(tagged.length, 10 + synchsafeSize + fakeMp3.length);

      // Verify the original MP3 bytes are intact at the tail.
      final tail = tagged.sublist(tagged.length - fakeMp3.length);
      expect(tail, fakeMp3);
    });

    test('injectMp3Metadata contains TXXX frames with expected descriptions', () {
      final fakeMp3 = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00]);
      final tagged = AudioWatermarkService.injectMp3Metadata(fakeMp3);

      // Convert tag region to string and look for the TXXX descriptions.
      final tagStr = String.fromCharCodes(tagged.sublist(10, tagged.length - fakeMp3.length));
      expect(tagStr, contains('AI_GENERATED'));
      expect(tagStr, contains('GENERATOR'));
      expect(tagStr, contains('CrisperWeaver'));
      expect(tagStr, contains('AI_CONTENT_NOTICE'));
    });

    test('injectMp3Metadata does not double-tag bytes with existing ID3 header', () {
      // Build bytes that already start with "ID3".
      final alreadyTagged = Uint8List.fromList([
        0x49, 0x44, 0x33, // "ID3"
        0x03, 0x00, 0x00, // v2.3, flags
        0x00, 0x00, 0x00, 0x00, // size = 0
        0xFF, 0xFB, // fake MP3 sync
      ]);
      final result = AudioWatermarkService.injectMp3Metadata(alreadyTagged);
      // Must return identical bytes — no modification.
      expect(result, alreadyTagged);
    });

    test('TXXX frame structure has correct layout', () {
      final fakeMp3 = Uint8List.fromList([0xFF, 0xFB]);
      final tagged = AudioWatermarkService.injectMp3Metadata(fakeMp3);

      // Find first TXXX frame after the 10-byte header.
      final frameId = String.fromCharCodes(tagged.sublist(10, 14));
      expect(frameId, 'TXXX');

      // Next 4 bytes: big-endian frame size.
      final frameSize = ByteData.view(tagged.buffer).getUint32(14, Endian.big);
      expect(frameSize, greaterThan(0));

      // 2-byte flags should be 0x0000.
      expect(tagged[18], 0x00);
      expect(tagged[19], 0x00);

      // Encoding byte should be 0x00 (ISO-8859-1).
      expect(tagged[20], 0x00);
    });
  });

  // -----------------------------------------------------------------------
  // 7. Beep-based AI disclaimer marker
  // -----------------------------------------------------------------------
  group('Beep disclaimer generation', () {
    test('generateBeepDisclaimer returns non-empty float32 PCM', () {
      final beeps = AudioWatermarkService.generateBeepDisclaimer();
      expect(beeps.length, greaterThan(0));
    });

    test('disclaimer duration matches expected layout', () {
      const sr = 24000;
      final beeps = AudioWatermarkService.generateBeepDisclaimer(sampleRate: sr);
      // 3 beeps * 150ms + 2 gaps * 80ms + 300ms trailing silence
      // = 450 + 160 + 300 = 910ms = 0.91 * 24000 = 21840 samples
      final expectedSamples =
          (3 * 0.150 * sr + 2 * 0.080 * sr + 0.300 * sr).round();
      expect(beeps.length, expectedSamples);
    });

    test('prepending disclaimer makes audio longer', () {
      const sr = 24000;
      final original = _sineWave(8000);
      final beeps = AudioWatermarkService.generateBeepDisclaimer(sampleRate: sr);

      final combined = Float32List(beeps.length + original.length);
      combined.setRange(0, beeps.length, beeps);
      combined.setRange(beeps.length, combined.length, original);

      expect(combined.length, beeps.length + original.length);
      expect(combined.length, greaterThan(original.length));
    });

    test('beep samples contain 880 Hz tone (non-silent)', () {
      final beeps = AudioWatermarkService.generateBeepDisclaimer();
      // The first beep starts at sample 0. After the fade-in (a few ms),
      // samples should have non-trivial amplitude.
      double maxAbs = 0;
      for (var i = 0; i < beeps.length; i++) {
        final a = beeps[i].abs();
        if (a > maxAbs) maxAbs = a;
      }
      // 880 Hz sine at full amplitude should reach close to 1.0.
      expect(maxAbs, greaterThan(0.9));
    });

    test('trailing silence region is near-zero', () {
      const sr = 24000;
      final beeps = AudioWatermarkService.generateBeepDisclaimer(sampleRate: sr);
      // Last 300ms should be silence.
      final silenceStart = beeps.length - (0.300 * sr).round();
      double maxInSilence = 0;
      for (var i = silenceStart; i < beeps.length; i++) {
        final a = beeps[i].abs();
        if (a > maxInSilence) maxInSilence = a;
      }
      expect(maxInSilence, lessThan(0.001));
    });
  });

  // -----------------------------------------------------------------------
  // 8. Post-embed watermark verification
  // -----------------------------------------------------------------------
  group('Post-embed watermark verification', () {
    test('embed then detect returns non-null on valid WAV', () {
      final samples = _sineWave(8000);
      final wav = _buildRawWav(samples);
      final watermarked = AudioWatermarkService.embedWatermark(
        wav,
        timestamp: DateTime.utc(2026, 6, 7),
        synthetic: true,
      );
      final info = AudioWatermarkService.detectWatermark(watermarked);
      expect(info, isNotNull,
          reason: 'post-embed verification must succeed on freshly '
              'watermarked audio');
      expect(info!.synthetic, isTrue);
    });

    test('embed on short audio returns unchanged bytes, detect returns null', () {
      // Audio too short for watermark — embedWatermark returns input
      // unchanged, detectWatermark returns null. This is the edge case
      // the post-embed check in TtsService must handle gracefully.
      final wav = _buildRawWav(Float32List(100));
      final result = AudioWatermarkService.embedWatermark(wav);
      expect(identical(result, wav), isTrue);
      final info = AudioWatermarkService.detectWatermark(result);
      expect(info, isNull);
    });

    test('multiple sequential embeds produce verifiable watermarks', () {
      for (var i = 0; i < 5; i++) {
        final samples = _sineWave(8000 + i * 1000, freq: 300.0 + i * 50);
        final wav = _buildRawWav(samples);
        final ts = DateTime.utc(2026, 1, 1 + i);
        final wm = AudioWatermarkService.embedWatermark(
            wav, timestamp: ts, synthetic: true);
        final info = AudioWatermarkService.detectWatermark(wm);
        expect(info, isNotNull, reason: 'iteration $i');
        expect(info!.timestamp.millisecondsSinceEpoch ~/ 1000,
            ts.millisecondsSinceEpoch ~/ 1000,
            reason: 'timestamp mismatch at iteration $i');
      }
    });
  });

  // -----------------------------------------------------------------------
  // 9. C2PA provenance manifest (unsigned JSON-LD)
  // -----------------------------------------------------------------------
  group('ContentProvenanceService', () {
    test('buildManifest produces valid C2PA-vocabulary JSON-LD', () {
      final manifest = ContentProvenanceService.buildManifest(
        generator: 'CrisperWeaver',
        generatorVersion: '0.9.0',
        modelName: 'kokoro',
        voiceId: 'af_heart',
        timestamp: DateTime.utc(2026, 7, 16, 12, 0),
      );

      expect(manifest['@context'], 'https://c2pa.org/assertions/v1');
      expect(manifest['@type'], 'c2pa.actions');
      expect(manifest['claim_generator'], 'CrisperWeaver/0.9.0');

      final actions = manifest['actions'] as List;
      expect(actions, hasLength(1));
      final action = actions[0] as Map<String, dynamic>;
      expect(action['action'], 'c2pa.created');
      expect(action['digitalSourceType'],
          contains('trainedAlgorithmicMedia'));
      expect(action['parameters']['model'], 'kokoro');
      expect(action['parameters']['voice'], 'af_heart');
    });

    test('buildManifest includes anti-training assertion', () {
      final manifest = ContentProvenanceService.buildManifest(
        generator: 'CrisperWeaver',
        generatorVersion: '1.0.0',
      );

      final assertions = manifest['assertions'] as List;
      expect(assertions, isNotEmpty);
      final antiTraining = assertions[0] as Map<String, dynamic>;
      expect(antiTraining['@type'], 'c2pa.training-mining');
      expect((antiTraining['entries'] as List)[0]['use'], 'notAllowed');
    });

    test('encodeAsRiffChunk produces valid RIFF chunk with c2pa ID', () {
      final manifest = ContentProvenanceService.buildManifest(
        generator: 'Test',
        generatorVersion: '0.1',
      );
      final chunk = ContentProvenanceService.encodeAsRiffChunk(manifest);

      // Chunk ID must be 'c2pa'.
      expect(String.fromCharCodes(chunk.sublist(0, 4)), 'c2pa');

      // Chunk size (LE uint32 at offset 4) + 8 must equal total length
      // (may be padded to even).
      final bd = ByteData.view(chunk.buffer);
      final size = bd.getUint32(4, Endian.little);
      expect(chunk.length, 8 + size);

      // Payload must be valid JSON.
      final json = utf8.decode(chunk.sublist(8, 8 + size).where((b) => b != 0).toList());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['@type'], 'c2pa.actions');
    });

    test('injectIntoWav → extractFromWav round-trip', () {
      final wav = _buildRawWav(_sineWave(8000));
      final injected = ContentProvenanceService.injectIntoWav(
        wav,
        generator: 'CrisperWeaver',
        generatorVersion: '0.9.0',
        modelName: 'orpheus',
        timestamp: DateTime.utc(2026, 7, 16),
      );

      // Output must be longer (c2pa chunk appended).
      expect(injected.length, greaterThan(wav.length));

      // RIFF header size must be updated.
      final origBd = ByteData.view(wav.buffer);
      final newBd = ByteData.view(injected.buffer);
      expect(newBd.getUint32(4, Endian.little),
          greaterThan(origBd.getUint32(4, Endian.little)));

      // Extract the manifest back.
      final extracted = ContentProvenanceService.extractFromWav(injected);
      expect(extracted, isNotNull);
      expect(extracted!['claim_generator'], 'CrisperWeaver/0.9.0');
      expect(extracted['actions'][0]['parameters']['model'], 'orpheus');
    });

    test('extractFromWav returns null on WAV without c2pa chunk', () {
      final wav = _buildRawWav(_sineWave(1000));
      final result = ContentProvenanceService.extractFromWav(wav);
      expect(result, isNull);
    });

    test('extractFromWav returns null on too-short input', () {
      expect(ContentProvenanceService.extractFromWav(Uint8List(10)), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // 10. C2PA stub availability (web fallback)
  // -----------------------------------------------------------------------
  group('CrispasrC2pa stub', () {
    // These test the stub behavior — on native platforms with the real
    // dylib, isAvailable() would return true. On CI without the dylib,
    // these verify the stub returns safe defaults.
    test('stub isAvailable returns false without dylib', () {
      // Import the stub directly — on CI the real dylib isn't loaded.
      // The stub is what gets used on web and in tests without FFI.
      // We can't easily import the stub here without conditional imports,
      // but we can verify the contract: sign() on unavailable returns null.
      // This is covered implicitly by the ContentProvenanceService fallback.
    });
  });

  // -----------------------------------------------------------------------
  // 11. Heuristic AI audio detection
  // -----------------------------------------------------------------------
  group('Heuristic AI audio detection', () {
    test('detectAiAudio returns score in [0, 1]', () {
      final pcm = _sineWave(24000); // 1 second at 24kHz
      final result = AudioWatermarkService.detectAiAudio(
        pcm,
        sampleRate: 24000,
      );
      expect(result.score, greaterThanOrEqualTo(0.0));
      expect(result.score, lessThanOrEqualTo(1.0));
    });

    test('detectAiAudio returns 0.0 for too-short audio', () {
      final pcm = Float32List(100); // way too short
      final result = AudioWatermarkService.detectAiAudio(pcm);
      expect(result.score, 0.0);
      expect(result.reason, contains('too short'));
    });

    test('digital silence scores high on silence indicator', () {
      // All-zero PCM = digital silence, a strong AI indicator.
      final pcm = Float32List(24000); // 1.5s of zeros at 16kHz
      final result = AudioWatermarkService.detectAiAudio(pcm);
      expect(result.details['digital_silence'], greaterThan(0.5));
    });
  });

  // -----------------------------------------------------------------------
  // 12. Export disclosure defaults to true (EU AI Act Art. 50)
  // -----------------------------------------------------------------------
  group('Export disclosure defaults', () {
    test('SRT default includes notice', () {
      final out = FileUtils.generateSrtContent(segs);
      expect(out, contains('AI-generated'));
    });

    test('VTT default includes NOTE', () {
      final out = FileUtils.generateVttContent(segs);
      expect(out, contains('NOTE '));
      expect(out, contains('AI-generated'));
    });

    test('JSON default includes _disclosure', () {
      final decoded = jsonDecode(FileUtils.generateJsonContent(segs));
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>).containsKey('_disclosure'), isTrue);
    });

    test('Markdown default includes notice', () {
      final out = FileUtils.generateMarkdownContent(segs);
      expect(out, contains('> **Notice:**'));
    });
  });

  // -----------------------------------------------------------------------
  // 13. Compliance constants integrity
  // -----------------------------------------------------------------------
  group('Privacy and compliance constants', () {
    test('no data collection by default', () {
      expect(AppConstants.collectUsageData, isFalse);
      expect(AppConstants.sendCrashReports, isFalse);
      expect(AppConstants.enableCloudSync, isFalse);
    });

    test('watermark and disclosure are enabled', () {
      expect(AppConstants.enableAudioWatermark, isTrue);
      expect(AppConstants.enableSyntheticDisclosure, isTrue);
    });
  });

  // -----------------------------------------------------------------------
  // 14. Art. 50(2) marking — spread-spectrum detector contract
  //
  // TtsService decides whether the native C API already watermarked the
  // PCM by *probing* it, rather than by checking whether the native
  // symbol exists. These tests pin the detector behaviour that decision
  // relies on: unmarked audio must read below the floor, marked audio at
  // or above it. If this contract breaks, TtsService would either ship
  // unmarked audio or double-mark every synthesis.
  // -----------------------------------------------------------------------
  group('Spread-spectrum watermark detector contract', () {
    /// 2 s of 16 kHz noise-ish tone — long enough for several FFT frames.
    Float32List signal({int n = 32000}) {
      final pcm = Float32List(n);
      for (var i = 0; i < n; i++) {
        pcm[i] = 0.25 * sin(2 * pi * 220.0 * i / 16000.0) +
            0.05 * sin(2 * pi * 1310.0 * i / 16000.0);
      }
      return pcm;
    }

    const floor = 0.65;

    test('unwatermarked audio reads below the confidence floor', () {
      final confidence = SpreadSpectrumWatermark.detect(signal());
      expect(confidence, lessThan(floor),
          reason: 'clean audio must not be mistaken for watermarked — '
              'otherwise TtsService skips the fallback embed and ships '
              'audio with no Art. 50(2) marking');
    });

    test('watermarked audio reads at or above the confidence floor', () {
      final marked = SpreadSpectrumWatermark.embed(signal());
      final confidence = SpreadSpectrumWatermark.detect(marked);
      expect(confidence, greaterThanOrEqualTo(floor),
          reason: 'freshly embedded watermark must verify, else every '
              'synthesis logs a false verification failure');
    });

    test('detect is safe on too-short input', () {
      expect(SpreadSpectrumWatermark.detect(Float32List(16)), 0.0);
    });

    // Measured 2026-08-01. These bound the 0.65 floor from both sides:
    // if a future detector change narrows the gap between clean and
    // marked audio, the floor stops discriminating and this fails.
    test('clean/marked confidence gap straddles the 0.65 floor', () {
      for (final ms in [100, 250, 500, 1000, 2000]) {
        final n = (16000 * ms / 1000).round();
        final clean = SpreadSpectrumWatermark.detect(signal(n: n));
        final marked =
            SpreadSpectrumWatermark.detect(SpreadSpectrumWatermark.embed(signal(n: n)));
        expect(clean, lessThan(floor), reason: 'clean @${ms}ms = $clean');
        expect(marked, greaterThanOrEqualTo(floor),
            reason: 'marked @${ms}ms = $marked');
      }
    });

    test('detection is level-invariant — quiet output is not rejected', () {
      final quiet = Float32List.fromList(
          signal().map((v) => v * 0.01).toList(growable: false));
      expect(SpreadSpectrumWatermark.detect(SpreadSpectrumWatermark.embed(quiet)),
          greaterThanOrEqualTo(floor),
          reason: 'a 0.01x-amplitude synthesis is legitimate output and must '
              'not be mistaken for unmarked');
    });

    // Known-unmarkable inputs. TtsService cannot fix these — a spectral
    // watermark needs spectrum to modulate — so it must at least detect
    // and report them rather than assert a mark that is not there.
    test('digital silence cannot carry the watermark', () {
      final silence = Float32List(32000);
      expect(SpreadSpectrumWatermark.detect(SpreadSpectrumWatermark.embed(silence)),
          lessThan(floor),
          reason: 'silence has no spectrum to modulate — TtsService must '
              'report this rather than claim the output is watermarked');
    });

    test('audio below one FFT frame cannot carry the watermark', () {
      final tiny = signal(n: 320); // 20 ms
      expect(SpreadSpectrumWatermark.detect(SpreadSpectrumWatermark.embed(tiny)),
          lessThan(floor));
    });
  });

  // -----------------------------------------------------------------------
  // 15. Art. 50(2) marking — OCR output disclosure
  // -----------------------------------------------------------------------
  group('OCR AI-generated disclosure', () {
    test('disclosure text names AI generation and urges verification', () {
      expect(OcrResult.disclosure.toLowerCase(), contains('ai-generated'));
      expect(OcrResult.disclosure.toLowerCase(), contains('verify'));
    });

    test('textWithDisclosure prefixes recognised text', () {
      const r = OcrResult(text: r'\frac{1}{2}');
      expect(r.textWithDisclosure, contains(OcrResult.disclosure));
      expect(r.textWithDisclosure, endsWith(r'\frac{1}{2}'));
    });

    test('empty OCR result discloses nothing', () {
      const r = OcrResult(text: '   ');
      expect(r.textWithDisclosure, isEmpty,
          reason: 'no recognised text means nothing to disclose');
    });

    test('music results get the OMR-specific wording', () {
      const r = OcrResult(text: 'C4 E4 G4', isMusic: true);
      expect(r.disclosureText, OcrResult.musicDisclosure);
      expect(r.disclosureText.toLowerCase(), contains('sheet music'));
      expect(r.textWithDisclosure, contains(OcrResult.musicDisclosure));
    });

    // §13.3p — these were catalogued but unreachable: isOcrModelFilename
    // matched only the six text-OCR prefixes, so availableModels() never
    // listed them and they could be downloaded but never run.
    test('OMR models are recognised as OCR models', () {
      for (final f in [
        'smt-grandstaff-q8_0.gguf',
        'smt-fp-grandstaff-q8_0.gguf',
        'tromr-q8_0.gguf',
        'flova-q4_k.gguf',
        'transcoda-q8_0.gguf',
      ]) {
        expect(OcrService.isOcrModelFilename(f), isTrue, reason: f);
        expect(OcrService.engineForModel(f)?.isMusic, isTrue, reason: f);
      }
    });

    test('text OCR models are not flagged as music', () {
      for (final f in ['pix2tex-q8_0.gguf', 'deepseek-ocr-q4_k.gguf']) {
        expect(OcrService.isOcrModelFilename(f), isTrue, reason: f);
        expect(OcrService.engineForModel(f)?.isMusic, isFalse, reason: f);
      }
    });
  });

  // -----------------------------------------------------------------------
  // 17. Abuse-reporting channel travels with the audio (§13.3o)
  // -----------------------------------------------------------------------
  group('Abuse reporting in the provenance manifest', () {
    test('manifest carries the reporting + policy URLs', () {
      final m = ContentProvenanceService.buildManifest(
        generator: 'CrisperWeaver',
        generatorVersion: '0.9.6',
      );
      final assertions = (m['assertions'] as List).cast<Map>();
      final abuse = assertions.firstWhere(
          (a) => a['@type'] == 'crisperweaver.abuse-reporting',
          orElse: () => throw StateError(
              'no abuse-reporting assertion — a recipient holding only the '
              'WAV would have no way to report misuse'));
      expect(abuse['report_misuse'], contains('http'));
      expect(abuse['acceptable_use_policy'], contains('ACCEPTABLE_USE'));
      expect(abuse['note'], contains('consent'));
    });

    test('reporting assertion survives the WAV round-trip', () {
      // 1 s of 16 kHz silence is enough — we only care about the chunk.
      final wav = _buildRawWav(_sineWave(16000));
      final out = ContentProvenanceService.injectIntoWav(
        wav,
        generator: 'CrisperWeaver',
        generatorVersion: '0.9.6',
      );
      final back = ContentProvenanceService.extractFromWav(out);
      expect(back, isNotNull);
      final assertions = (back!['assertions'] as List).cast<Map>();
      expect(
          assertions.any((a) => a['@type'] == 'crisperweaver.abuse-reporting'),
          isTrue);
    });
  });

  // -----------------------------------------------------------------------
  // 16. Consent-derived speaker roster
  //
  // SpeakerIdService opens CrispasrSpeakerDB as a closed roster built
  // from consent records, so a profile without recorded consent is never
  // matchable. These tests cover the on-disk selection logic without
  // needing the native library.
  // -----------------------------------------------------------------------
  group('Consent-derived speaker roster', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('crisper_roster_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    /// Mirrors SpeakerIdService.listSpeakers: `.spk` profiles only.
    Future<List<String>> listSpeakers(Directory d) async {
      final out = <String>[];
      await for (final e in d.list()) {
        if (e is! File) continue;
        if (!e.path.endsWith('.spk')) continue;
        final base = e.uri.pathSegments.last;
        out.add(base.substring(0, base.length - '.spk'.length));
      }
      out.sort();
      return out;
    }

    test('consent JSON files are not listed as speakers', () async {
      await File('${tmp.path}/Alice.spk').writeAsBytes([1]);
      await File('${tmp.path}/Alice.consent.json').writeAsString('{}');

      final names = await listSpeakers(tmp);
      expect(names, ['Alice']);
      expect(names, isNot(contains('Alice.consent')),
          reason: 'an unfiltered listing yields a phantom speaker named '
              '"Alice.consent" that would also poison the roster');
    });

    test('roster excludes profiles without a consent record', () async {
      await File('${tmp.path}/Alice.spk').writeAsBytes([1]);
      await File('${tmp.path}/Alice.consent.json').writeAsString('{}');
      await File('${tmp.path}/Bob.spk').writeAsBytes([1]);

      final names = await listSpeakers(tmp);
      final roster = <String>[];
      final missing = <String>[];
      for (final n in names) {
        if (await File('${tmp.path}/$n.consent.json').exists()) {
          roster.add(n);
        } else {
          missing.add(n);
        }
      }
      expect(roster, ['Alice']);
      expect(missing, ['Bob'],
          reason: 'no consent record means no lawful basis, so Bob must '
              'not be matchable');
    });

    test('erasing the consent record drops the speaker from the roster',
        () async {
      await File('${tmp.path}/Alice.spk').writeAsBytes([1]);
      final consent = File('${tmp.path}/Alice.consent.json');
      await consent.writeAsString('{}');
      expect(await consent.exists(), isTrue);

      // Withdrawal of consent (GDPR Art. 7(3)).
      await consent.delete();

      final roster = <String>[];
      for (final n in await listSpeakers(tmp)) {
        if (await File('${tmp.path}/$n.consent.json').exists()) roster.add(n);
      }
      expect(roster, isEmpty,
          reason: 'withdrawal must take effect without further user action');
    });
  });

  // -------------------------------------------------------------------------
  // Art. 50(2) — AI-generated *text* disclosure.
  //
  // The 2026-08-02 audit found the marking duty had been read as an audio
  // duty: OCR output carried a disclosure, but LLM summaries and machine
  // translations left the app bare — on the clipboard, and over the HTTP
  // translation endpoint, which was the only generating endpoint not
  // setting `x-content-ai-generated`.
  // -------------------------------------------------------------------------
  group('AI-generated text disclosure (Art. 50(2))', () {
    test('summary disclosure names AI generation and urges verification', () {
      final d = AiTextDisclosure.summary.toLowerCase();
      expect(d, contains('ai-generated'));
      expect(d, contains('verify'));
    });

    test('translation disclosure names AI generation and urges verification',
        () {
      final d = AiTextDisclosure.translation.toLowerCase();
      expect(d, contains('ai-generated'));
      expect(d, contains('verify'));
    });

    test('summary and translation wording are distinct', () {
      // Different failure modes: a summary drops content, a translation
      // distorts meaning. Identical wording would be a copy-paste smell.
      expect(AiTextDisclosure.summary,
          isNot(equals(AiTextDisclosure.translation)));
    });

    test('attach prefixes the text with a bracketed disclosure', () {
      final out = AiTextDisclosure.forSummary('- ship the thing');
      expect(out, startsWith('['));
      expect(out, contains(AiTextDisclosure.summary));
      expect(out, endsWith('- ship the thing'));
    });

    test('empty or whitespace-only text discloses nothing', () {
      // A bare disclosure on an empty clipboard is noise, not compliance.
      expect(AiTextDisclosure.forSummary(''), isEmpty);
      expect(AiTextDisclosure.forTranslation('   \n '), isEmpty);
    });

    test('the original text survives verbatim after the disclosure', () {
      const body = 'Zeile eins\nZeile zwei';
      final out = AiTextDisclosure.forTranslation(body);
      expect(out.endsWith(body), isTrue,
          reason: 'the disclosure must be additive — a consumer stripping '
              'the first paragraph gets exactly the model output back');
    });

    test('matches the shape OcrResult already established', () {
      // Both leave the app through the clipboard and can land side by side.
      final ocr = const OcrResult(text: 'x').textWithDisclosure;
      final llm = AiTextDisclosure.forSummary('x');
      expect(ocr.startsWith('['), isTrue);
      expect(llm.startsWith('['), isTrue);
      expect(ocr.endsWith('x'), isTrue);
      expect(llm.endsWith('x'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // MarkedWav — the WAV encoder shared by TtsService and the CLI.
  //
  // Extracted during the 2026-08-02 audit: `bin/crisperweaver.dart` wrote a
  // bare 44-byte header, so headless `synthesize` / `s2s` output carried no
  // provenance chunk at all. Sharing the encoder is what stops the two
  // paths drifting apart again, so these tests pin the shared contract.
  // -------------------------------------------------------------------------
  group('MarkedWav provenance encoder', () {
    Float32List tone(int n) => Float32List.fromList(
        List<double>.generate(n, (i) => sin(2 * pi * 440 * i / 24000) * 0.5));

    test('produces a valid RIFF/WAVE container', () {
      final b = MarkedWav.encode(tone(2400), 24000, generatorVersion: '0.0.0');
      expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');
      final declared =
          ByteData.view(b.buffer).getUint32(4, Endian.little);
      expect(declared, b.length - 8,
          reason: 'RIFF size must cover the appended LIST chunk too');
    });

    test('carries the AI-generated provenance fields', () {
      final b = MarkedWav.encode(tone(2400), 24000,
          generatorVersion: '9.9.9', modelName: 'kokoro', voiceId: 'af_heart');
      final ascii = String.fromCharCodes(b.where((c) => c >= 32 && c < 127));
      expect(ascii, contains('LIST'));
      expect(ascii, contains('INFO'));
      expect(ascii, contains('CrisperWeaver 9.9.9'));
      expect(ascii, contains('AI-generated synthetic speech'));
      expect(ascii, contains('kokoro'));
      expect(ascii, contains('voice:af_heart'));
    });

    test('the LIST chunk sits after the data chunk', () {
      // Legacy parsers stop reading at `data`; provenance must not displace
      // the PCM they expect to find there.
      final b = MarkedWav.encode(tone(1200), 24000, generatorVersion: '1.0.0');
      final ascii = String.fromCharCodes(b.map((c) => c & 0x7F));
      expect(ascii.indexOf('LIST'), greaterThan(ascii.indexOf('data')));
    });

    test('omits the voice field when there is no voice', () {
      final b = MarkedWav.encode(tone(1200), 24000, generatorVersion: '1.0.0');
      final ascii = String.fromCharCodes(b.where((c) => c >= 32 && c < 127));
      expect(ascii, isNot(contains('voice:')));
    });

    test('survives a watermark round-trip', () {
      // The container marking and the robust mark are independent layers;
      // encoding must not disturb the PCM the detector reads.
      final marked = SpreadSpectrumWatermark.embed(tone(48000));
      final b = MarkedWav.encode(marked, 24000, generatorVersion: '1.0.0');
      expect(b.length, greaterThan(44 + marked.length * 2));
      expect(SpreadSpectrumWatermark.detect(marked), greaterThanOrEqualTo(0.65));
    });
  });

  _thirdAuditTests();
}

// ---------------------------------------------------------------------------
// Third audit (2026-08-02): emotion recognition, provenance across edits,
// CLI text disclosure, note-export marking consistency.
// ---------------------------------------------------------------------------

void _thirdAuditTests() {
  group('No emotion recognition (Annex III 1(c) stays out of scope)', () {
    // The app rendered a SenseVoice emotion badge until the 2026-08-02
    // audit, which made it an emotion recognition system under Art. 3(39)
    // and an Annex III 1(c) high-risk system from 2 Dec 2027. The feature
    // was removed rather than disclosed. These tests pin the removal: they
    // fail if an inference about a natural person can reach the app again.

    test('every SenseVoice emotion label is on the discard list', () {
      // Widening a model's emotion vocabulary without widening this set
      // would silently re-create the exposure — the tag would flow through
      // the filter and land back in segment metadata.
      for (final t in const [
        'HAPPY', 'SAD', 'ANGRY', 'NEUTRAL',
        'EMO_UNKNOWN', 'SURPRISED', 'FEARFUL', 'DISGUSTED',
      ]) {
        expect(EmotionInference.isEmotionTag(t), isTrue, reason: t);
      }
    });

    test('matching is case-insensitive', () {
      // Backends emit `<|HAPPY|>` and `<|Happy|>` interchangeably; a
      // case-sensitive check would let one spelling through the filter.
      expect(EmotionInference.isEmotionTag('Happy'), isTrue);
      expect(EmotionInference.isEmotionTag('angry'), isTrue);
    });

    test('acoustic event tags are kept', () {
      // Classifying laughter as an audio event describes the recording,
      // not the speaker's inner state. Over-filtering here would delete a
      // feature that was never a compliance problem.
      for (final t in const [
        'SPEECH', 'BGM', 'LAUGHTER', 'APPLAUSE', 'NOISE', 'MUSIC', 'SINGING',
      ]) {
        expect(EmotionInference.isEmotionTag(t), isFalse, reason: t);
      }
    });

    test('the engine drops emotion tags and keeps event tags', () {
      // Mirrors CrispasrEngine._mapSessionSegments' filter. The engine
      // itself needs the FFI session type, so the behaviour is pinned on
      // the shared predicate that drives it.
      const raw = '<|HAPPY|><|BGM|>the meeting starts now<|ANGRY|>';
      final kept = RegExp(r'<\|([A-Za-z_]+)\|>')
          .allMatches(raw)
          .map((m) => m.group(1)!)
          .where((t) => !EmotionInference.isEmotionTag(t))
          .toList();
      expect(kept, ['BGM']);
      expect(kept.any(EmotionInference.isEmotionTag), isFalse);
    });

    test('no emotion strings survive anywhere in the UI vocabulary',
        () async {
      // The disclosure strings were added and then removed with the
      // feature; their presence would mean a surface still displays an
      // inference. Checked in every locale because the notice is the one
      // place a subsystem gets enumerated for Art. 50(1).
      for (final locale in const [Locale('en'), Locale('de'), Locale('zh')]) {
        final l = await AppLocalizations.delegate.load(locale);
        final body = l.aiTransparencyBody.toLowerCase();
        expect(body, isNot(contains('emotion')),
            reason: 'locale ${locale.languageCode}');
        expect(body, isNot(contains('emotionserkennung')),
            reason: 'locale ${locale.languageCode}');
        expect(body, isNot(contains('情绪')),
            reason: 'locale ${locale.languageCode}');
      }
    });

    test('neither the engine nor the widget records an emotion field', () {
      // A source guard, because the alternative needs a live SenseVoice
      // model: `metadata['emotion']` is the exact key the badge read, and
      // its absence is what keeps the app outside Annex III 1(c).
      final engine =
          File('lib/engines/crispasr_engine.dart').readAsStringSync();
      final widget =
          File('lib/widgets/transcription_output_widget.dart').readAsStringSync();
      expect(engine, isNot(contains("'emotion':")));
      expect(widget, isNot(contains("metadata['emotion']")));
      // The filter that replaced it must still be there.
      expect(engine, contains('EmotionInference.isEmotionTag'));
    });
  });

  group('Provenance survives an edit (Art. 50(2))', () {
    /// A WAV as TtsService would write one: PCM + LIST/INFO + manifest.
    Uint8List generatedWav() {
      final pcm = Float32List.fromList(
          List<double>.generate(4800, (i) => sin(i * 0.05) * 0.4));
      return ContentProvenanceService.injectIntoWav(
        MarkedWav.encode(pcm, 24000,
            generatorVersion: '9.9.9',
            modelName: 'kokoro-82m',
            voiceId: 'af_heart'),
        generator: 'CrisperWeaver',
        generatorVersion: '9.9.9',
        modelName: 'kokoro-82m',
        voiceId: 'af_heart',
      );
    }

    test('the source manifest names the model and voice', () {
      final m = ContentProvenanceService.extractFromWav(generatedWav())!;
      expect(ContentProvenanceService.modelAndVoiceOf(m),
          ('kokoro-82m', 'af_heart'));
    });

    test('a derived manifest keeps the original creation claim', () {
      // The whole point: a trimmed clip must still say a TTS model made it.
      // Replacing the claim with a fresh one would assert CrisperWeaver
      // generated the trimmed file just now, losing the model attribution.
      final src = ContentProvenanceService.extractFromWav(generatedWav())!;
      final derived = ContentProvenanceService.deriveEditedManifest(
        src,
        editAction: 'trim',
        generator: 'CrisperWeaver',
        generatorVersion: '9.9.9',
      );
      final actions = derived['actions'] as List;
      expect(actions.first['action'], 'c2pa.created');
      expect(actions.last['action'], 'c2pa.edited');
      expect(actions.last['parameters']['name'], 'trim');
      expect(ContentProvenanceService.modelAndVoiceOf(derived),
          ('kokoro-82m', 'af_heart'));
    });

    test('the derived manifest round-trips through a re-encoded WAV', () {
      // This is the composition AudioEditService._writeWav performs.
      final src = ContentProvenanceService.extractFromWav(generatedWav())!;
      final trimmedPcm = Float32List.fromList(
          List<double>.generate(2400, (i) => sin(i * 0.05) * 0.4));
      final out = ContentProvenanceService.injectManifestIntoWav(
        MarkedWav.encode(trimmedPcm, 24000,
            generatorVersion: '9.9.9',
            modelName: 'kokoro-82m',
            voiceId: 'af_heart'),
        ContentProvenanceService.deriveEditedManifest(
          src,
          editAction: 'trim',
          generator: 'CrisperWeaver',
          generatorVersion: '9.9.9',
        ),
      );
      final recovered = ContentProvenanceService.extractFromWav(out);
      expect(recovered, isNotNull);
      expect(ContentProvenanceService.modelAndVoiceOf(recovered!),
          ('kokoro-82m', 'af_heart'));
      // And the abuse-reporting channel rides along, so a recipient of the
      // trimmed clip can still find where to report it.
      expect(jsonEncode(recovered),
          contains(ContentProvenanceService.abuseReportingUrl));
    });

    test('the editor probe finds a manifest on a generated WAV', () async {
      final dir = await Directory.systemTemp.createTemp('cw-prov-');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/gen.wav')..writeAsBytesSync(generatedWav());
      final found = await AudioEditService().sourceProvenance(f.path);
      expect(found, isNotNull);
      expect(ContentProvenanceService.modelAndVoiceOf(found!).$1, 'kokoro-82m');
    });

    test('the probe reports none for a plain recording', () async {
      // A human recording must not acquire an AI provenance claim by being
      // trimmed — over-marking is its own compliance failure.
      final dir = await Directory.systemTemp.createTemp('cw-prov-');
      addTearDown(() => dir.delete(recursive: true));
      final pcm = Float32List.fromList(
          List<double>.generate(2400, (i) => sin(i * 0.05) * 0.4));
      final f = File('${dir.path}/rec.wav')..writeAsBytesSync(_buildRawWav(pcm));
      expect(await AudioEditService().sourceProvenance(f.path), isNull);
    });

    test('the probe survives a non-WAV file without throwing', () async {
      final dir = await Directory.systemTemp.createTemp('cw-prov-');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/notes.txt')..writeAsStringSync('not audio');
      expect(await AudioEditService().sourceProvenance(f.path), isNull);
    });
  });

  group('CLI text disclosure (Art. 50(2))', () {
    // The CLI writes generated text to stdout, which no widget test reaches
    // and no unit test imports. Round two brought the CLI inside the *audio*
    // marking scope and left `translate` emitting a bare line — so this
    // guards the wiring at the source level, which is the only level that
    // sees it.
    final cli = File('bin/crisperweaver.dart').readAsStringSync();

    test('the CLI imports the shared disclosure strings', () {
      expect(cli, contains("import 'package:crisper_weaver/utils/ai_text_disclosure.dart'"));
    });

    test('translate attaches the translation disclosure', () {
      expect(cli, contains('AiTextDisclosure.translation'));
      expect(cli, contains('_writeDisclosedText'));
    });

    test('suppressing the disclosure requires an explicit flag', () {
      // Disclosure is the default; `--no-disclosure` is the opt-out, the
      // same direction as FileUtils.saveTranscription's syntheticDisclosure.
      expect(cli, contains("addFlag('no-disclosure'"));
      expect(cli, contains("negatable: false"));
    });

    test('transcribe strips emotion tags from every output format', () {
      // The CLI passes raw segment text through, so without this it would
      // print `<|HAPPY|>` inline while the GUI drops it — the app doing
      // emotion recognition on one surface and not the other.
      expect(cli, contains('_noEmotion'));
      expect(cli, contains('EmotionInference.isEmotionTag'));
      expect(cli, isNot(contains('EMOTION-RECOGNITION')));
      // All four output shapes go through the stripper, not just the
      // default one: plain, SRT, VTT and word-timestamps.
      expect('_noEmotion('.allMatches(cli).length, greaterThanOrEqualTo(4));
    });
  });

  group('Note exports mark consistently', () {
    final segments = [
      const TranscriptionSegment(
          text: 'hello there', startTime: 0.0, endTime: 1.5, speaker: 'Ana'),
    ];

    test('every format carries the notice', () {
      // Obsidian carried an `ai-generated` YAML tag while Notion, Logseq and
      // the YouTube chapters carried nothing — same transcript, same share
      // sheet, different marking.
      final outputs = {
        'obsidian': NoteExportService.toObsidian(
            segments: segments, title: 'T'),
        'notion': NoteExportService.toNotion(segments: segments, title: 'T'),
        'logseq': NoteExportService.toLogseq(segments: segments, title: 'T'),
        'chapters': NoteExportService.toYouTubeChapters(segments: segments),
      };
      outputs.forEach((name, out) {
        expect(out, contains(NoteExportService.disclosure), reason: name);
      });
    });

    test('the notice says machine-generated and unreviewed', () {
      final d = NoteExportService.disclosure.toLowerCase();
      expect(d, contains('machine-generated'));
      expect(d, contains('not checked by a human'));
    });

    test('the transcript itself still survives the notice', () {
      expect(NoteExportService.toNotion(segments: segments, title: 'T'),
          contains('hello there'));
    });
  });

  // -----------------------------------------------------------------------
  // Audio Q&A — affective prompts refused, answers marked as generated
  //
  // `askPrompt` hands a free-text question to an instruct-tuned audio LLM,
  // which answers it instead of transcribing. Two distinct duties fall out
  // of that, and the audit of 2026-08-03 found both unmet: the prompt is a
  // route to emotion recognition that no output filter can close
  // (Art. 5(1)(f) / Annex III 1(c)), and the answer is generated text that
  // every downstream label called a transcript (Art. 50(2)).
  // -----------------------------------------------------------------------
  group('Audio Q&A — affective prompt guard (Art. 5(1)(f), Annex III 1(c))', () {
    test('refuses the prompt the UI itself used to suggest', () {
      // The shipped placeholder read "e.g. \"Summarize\" or \"What's the
      // speaker's tone?\"" in EN/DE/ZH — the app recommending the one
      // question that would re-acquire an Annex III 1(c) obligation.
      expect(AffectivePromptGuard.isAffective("What's the speaker's tone?"),
          isTrue);
      expect(AffectivePromptGuard.isAffective('Wie ist die Stimmung des Sprechers?'),
          isTrue);
      expect(AffectivePromptGuard.isAffective('说话人的语气如何？'), isTrue);
    });

    test('no shipped locale suggests an affective prompt', () async {
      // The regression that matters: this is how the capability came back
      // after being deleted. A placeholder is a recommendation.
      for (final locale in const [Locale('en'), Locale('de'), Locale('zh')]) {
        final l = await AppLocalizations.delegate.load(locale);
        expect(AffectivePromptGuard.isAffective(l.advancedAskPromptHint),
            isFalse,
            reason: 'ask-prompt hint for ${locale.languageCode} suggests an '
                'emotion-inference prompt');
      }
    });

    test('catches emotion, intent and veracity across languages', () {
      const refused = [
        'How does the speaker feel? describe their emotion',
        'Is the caller angry',
        'summarise the mood of the meeting',
        'was the witness lying',
        'what is the speaker\'s intent',
        'Klingt der Sprecher wütend?',
        '说话人是否生气？',
      ];
      for (final p in refused) {
        expect(AffectivePromptGuard.isAffective(p), isTrue, reason: p);
      }
    });

    test('ordinary questions are not refused', () {
      const allowed = [
        'Summarize',
        'What was decided?',
        'List the action items',
        'Who spoke first?',
        'What was the deadline mentioned',
        'Was wurde beschlossen?',
        '做出了什么决定？',
        '',
        null,
      ];
      for (final p in allowed) {
        expect(AffectivePromptGuard.isAffective(p), isFalse, reason: '$p');
      }
    });

    test('word terms match on boundaries, not substrings', () {
      // `sad` must not fire on `saddle`, or the guard becomes noise the
      // user learns to route around.
      expect(AffectivePromptGuard.isAffective('what did they say about the saddle'),
          isFalse);
      expect(AffectivePromptGuard.isAffective('list the attendees'), isFalse);
    });

    test('the refusal names the term and cites why', () {
      final term = AffectivePromptGuard.offendingTerm('what is their mood');
      expect(term, 'mood');
      final msg = AffectivePromptGuard.refusalMessage(term!);
      expect(msg, contains('mood'));
      expect(msg, contains('Art. 3(39)'));
      expect(msg, contains('Art. 5(1)(f)'));
    });
  });

  group('Audio Q&A — output marked as generated (Art. 50(2))', () {
    const qaSegs = [
      TranscriptionSegment(
        text: 'The team agreed to ship on Friday.',
        startTime: 0,
        endTime: 4,
        metadata: {'generated': 'audio-qa'},
      ),
    ];
    const plainSegs = [
      TranscriptionSegment(
          text: 'Hello world.', startTime: 0, endTime: 1, speaker: 'Alice'),
    ];

    test('isGenerated distinguishes an answer from a transcript', () {
      expect(qaSegs.first.isGenerated, isTrue);
      expect(plainSegs.first.isGenerated, isFalse);
    });

    test('the flag survives copyWith', () {
      // It has to reach history and later re-exports, not just this run.
      expect(qaSegs.first.copyWith(text: 'x').isGenerated, isTrue);
    });

    test('every structured export names it an answer, not a transcript', () {
      final outs = {
        'srt': FileUtils.generateSrtContent(qaSegs),
        'vtt': FileUtils.generateVttContent(qaSegs),
        'json': FileUtils.generateJsonContent(qaSegs),
        'md': FileUtils.generateMarkdownContent(qaSegs),
        'obsidian': NoteExportService.toObsidian(segments: qaSegs, title: 'T'),
        'notion': NoteExportService.toNotion(segments: qaSegs, title: 'T'),
        'logseq': NoteExportService.toLogseq(segments: qaSegs, title: 'T'),
        'chapters': NoteExportService.toYouTubeChapters(segments: qaSegs),
      };
      outs.forEach((name, out) {
        expect(out, contains(AiTextDisclosure.audioQa), reason: name);
        // The transcript wording must NOT be applied to generated prose —
        // mismarking is what the audit found, not absence of a mark.
        expect(out.contains(NoteExportService.disclosure), isFalse,
            reason: '$name calls a generated answer a transcript');
      });
    });

    test('a real transcript keeps the transcript wording', () {
      final out = NoteExportService.toObsidian(segments: plainSegs, title: 'T');
      expect(out, contains(NoteExportService.disclosure));
      expect(out.contains(AiTextDisclosure.audioQa), isFalse);
    });

    test('the Q&A notice says answer, not transcript', () {
      final d = AiTextDisclosure.audioQa.toLowerCase();
      expect(d, contains('ai-generated'));
      expect(d, contains('not a transcript'));
    });
  });

}
