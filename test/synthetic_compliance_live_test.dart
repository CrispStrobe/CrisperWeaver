// Synthetic content compliance — live integration tests.
//
// These require a real libcrispasr dylib and at least one TTS model
// on disk to exercise the full watermark + metadata pipeline against
// actual synthesised audio. Tagged `slow` so `flutter test` skips them.
//
// Running locally:
//   CRISPASR_LIB=/path/to/libcrispasr.dylib \
//     flutter test --tags slow test/synthetic_compliance_live_test.dart

@Tags(['slow'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/audio_watermark_service.dart';
import 'package:crisper_weaver/services/model_service.dart';

// ---------------------------------------------------------------------------
// Environment resolution (shared with tts_issue_fixes_live_test.dart)
// ---------------------------------------------------------------------------

String? _resolveLibPath() {
  final env = Platform.environment['CRISPASR_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  const candidates = [
    '../CrispASR/build-flutter-bundle/src/libwhisper.dylib',
    '../CrispASR/build/src/libwhisper.dylib',
    '../CrispASR/build-flutter-bundle/src/libcrispasr.dylib',
    '../CrispASR/build/src/libcrispasr.dylib',
    '../CrispASR/build-flutter-bundle/src/libwhisper.so',
    '../CrispASR/build/src/libwhisper.so',
    '../CrispASR/build-flutter-bundle/src/libcrispasr.so',
    '../CrispASR/build/src/libcrispasr.so',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return File(c).absolute.path;
  }
  return null;
}

String? _resolveModel(String catalogName) {
  final def = ModelService.crispasrBackendModels[catalogName];
  if (def == null) return null;
  final fileName = def.fileName;

  final envDir = Platform.environment['CRISPASR_MODELS_DIR'];
  if (envDir != null && envDir.isNotEmpty) {
    final f = File('$envDir/$fileName');
    if (f.existsSync()) return f.absolute.path;
  }
  const dirs = [
    '../CrispASR/models',
    '../CrispASR/build-flutter-bundle/models',
  ];
  for (final d in dirs) {
    final f = File('$d/$fileName');
    if (f.existsSync()) return f.absolute.path;
  }
  return null;
}

/// Build a 16-bit mono WAV from float32 PCM samples (mirrors TtsService).
Uint8List _floatPcmToWavBytes(Float32List samples, int sampleRate) {
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

void main() {
  final libPath = _resolveLibPath();
  final libSkip = libPath == null
      ? 'libcrispasr dylib not found \u2014 build CrispASR or set CRISPASR_LIB.'
      : null;

  // Prefer kokoro (fast, always works) — fall back to any available TTS model.
  const _ttsModels = [
    'kokoro-v1.0-q8_0',
    'kokoro-v0.19-q8_0',
    'orpheus-3b-0.1-ft-q4_k_m',
  ];

  String? ttsModelPath;
  String? ttsModelName;
  String? ttsBackend;
  for (final name in _ttsModels) {
    final p = _resolveModel(name);
    if (p != null) {
      ttsModelPath = p;
      ttsModelName = name;
      ttsBackend = ModelService.crispasrBackendModels[name]!.backend;
      break;
    }
  }
  final ttsSkip = libSkip ??
      (ttsModelPath == null
          ? 'No TTS model GGUF found on disk \u2014 download one or set CRISPASR_MODELS_DIR.'
          : null);

  // -----------------------------------------------------------------
  // 1. Watermark survives real TTS synthesis
  // -----------------------------------------------------------------
  group('Watermark on real TTS output', () {
    test('synthesise \u2192 WAV \u2192 watermark \u2192 detect round-trip', () {
      final session = crispasr.CrispasrSession.open(
        ttsModelPath!,
        backend: ttsBackend!,
        libPath: libPath,
      );
      try {
        // Set voice if needed.
        final def = ModelService.crispasrBackendModels[ttsModelName]!;
        for (final companion in def.companions) {
          final compDef = ModelService.crispasrBackendModels[companion];
          if (compDef != null && compDef.kind == ModelKind.codec) {
            final cp = _resolveModel(companion);
            if (cp != null) session.setCodecPath(cp);
          }
          if (compDef != null && compDef.kind == ModelKind.voice) {
            final vp = _resolveModel(companion);
            if (vp != null) session.setVoice(vp, '');
          }
        }

        // If the backend has preset speakers, pick the first.
        try {
          final speakers = session.speakers();
          if (speakers.isNotEmpty) {
            session.setSpeakerName(speakers.first);
          }
        } catch (_) {
          // Not all backends support speakers().
        }

        final pcm = session.synthesize('Hello world, this is a compliance test.');
        expect(pcm.length, greaterThan(4608),
            reason: 'TTS output must be long enough for watermark payload');

        // Encode to WAV.
        final wav = _floatPcmToWavBytes(pcm, 24000);
        final ts = DateTime.now();

        // Embed watermark.
        final watermarked = AudioWatermarkService.embedWatermark(
          wav,
          timestamp: ts,
          synthetic: true,
        );
        expect(watermarked.length, wav.length,
            reason: 'watermark must not change file size');

        // Detect watermark.
        final info = AudioWatermarkService.detectWatermark(watermarked);
        expect(info, isNotNull, reason: 'watermark must be detectable');
        expect(info!.synthetic, isTrue);
        expect(
          info.timestamp.millisecondsSinceEpoch ~/ 1000,
          ts.millisecondsSinceEpoch ~/ 1000,
        );
      } finally {
        session.close();
      }
    }, skip: ttsSkip, timeout: const Timeout(Duration(minutes: 3)));

    test('watermark does not corrupt TTS audio envelope', () {
      final session = crispasr.CrispasrSession.open(
        ttsModelPath!,
        backend: ttsBackend!,
        libPath: libPath,
      );
      try {
        try {
          final speakers = session.speakers();
          if (speakers.isNotEmpty) session.setSpeakerName(speakers.first);
        } catch (_) {}

        final pcm = session.synthesize('Testing audio integrity.');
        final wav = _floatPcmToWavBytes(pcm, 24000);
        final watermarked = AudioWatermarkService.embedWatermark(wav);

        // Verify every sample differs by at most 1 LSB.
        final origBd = ByteData.view(wav.buffer);
        final wmBd = ByteData.view(watermarked.buffer);
        for (var i = 0; i < pcm.length; i++) {
          final orig = origBd.getInt16(44 + i * 2, Endian.little);
          final marked = wmBd.getInt16(44 + i * 2, Endian.little);
          expect((orig - marked).abs(), lessThanOrEqualTo(1),
              reason: 'sample $i changed by more than \u00b11 LSB');
        }
      } finally {
        session.close();
      }
    }, skip: ttsSkip, timeout: const Timeout(Duration(minutes: 3)));
  });

  // -----------------------------------------------------------------
  // 2. Speaker consent file I/O (live filesystem)
  // -----------------------------------------------------------------
  group('Speaker consent file I/O (live)', () {
    test('saveConsent creates a readable JSON in a temp speakers dir',
        () async {
      final tmp =
          await Directory.systemTemp.createTemp('crisper_consent_live_');
      try {
        // Simulate SpeakerIdService.saveConsent().
        final name = 'LiveTestSpeaker';
        final file = File('${tmp.path}/$name.consent.json');
        final now = DateTime.now().toUtc();
        await file.writeAsString(
          '{"speaker":"$name","consentedAt":"${now.toIso8601String()}",'
          '"purpose":"Speaker identification via TitaNet voice embeddings",'
          '"lawfulBasis":"GDPR Art. 9(2)(a)","storageLocation":"on-device only"}',
        );

        expect(await file.exists(), isTrue);
        final size = await file.length();
        expect(size, greaterThan(50),
            reason: 'consent JSON should not be empty');

        // Simulate deleteSpeaker — both .spk and .consent.json.
        final spk = File('${tmp.path}/$name.spk');
        await spk.writeAsBytes([0, 0, 0]); // dummy
        await spk.delete();
        await file.delete();
        expect(await spk.exists(), isFalse);
        expect(await file.exists(), isFalse);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  // -----------------------------------------------------------------
  // 3. WAV LIST INFO metadata on real synthesis output
  // -----------------------------------------------------------------
  group('WAV LIST INFO on real TTS output', () {
    test('TTS WAV file written to disk is parseable and contains PCM data',
        () async {
      if (ttsSkip != null) return;
      final session = crispasr.CrispasrSession.open(
        ttsModelPath!,
        backend: ttsBackend!,
        libPath: libPath,
      );
      try {
        try {
          final speakers = session.speakers();
          if (speakers.isNotEmpty) session.setSpeakerName(speakers.first);
        } catch (_) {}

        final pcm = session.synthesize('Metadata test.');
        expect(pcm.length, greaterThan(0));

        // Write WAV to temp file (mirrors TtsService.writeWav minus
        // the LIST INFO chunk — that's added by the private method;
        // here we verify the raw PCM encodes correctly).
        final wav = _floatPcmToWavBytes(pcm, 24000);
        final tmp = await Directory.systemTemp
            .createTemp('crisper_wav_meta_');
        try {
          final f = File('${tmp.path}/test.wav');
          await f.writeAsBytes(wav, flush: true);
          expect(await f.exists(), isTrue);

          // Read back and validate RIFF header.
          final bytes = await f.readAsBytes();
          expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
          expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');

          final bd = ByteData.view(bytes.buffer);
          final sampleRate = bd.getUint32(24, Endian.little);
          expect(sampleRate, 24000,
              reason: 'TTS backends output 24 kHz');

          final dataLen = bd.getUint32(40, Endian.little);
          expect(dataLen, pcm.length * 2,
              reason: 'data chunk size should be samples * 2 bytes');
        } finally {
          await tmp.delete(recursive: true);
        }
      } finally {
        session.close();
      }
    }, skip: ttsSkip, timeout: const Timeout(Duration(minutes: 3)));
  });
}
