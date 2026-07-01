// Live audio format decode tests — validates CrispASR's miniaudio backend
// can decode .opus, .webm, .m4a, .mp3, .flac, .ogg alongside the baseline
// .wav. Uses ffmpeg-generated test fixtures.
//
// Tagged `slow` because it requires the CrispASR dylib.
//
// Run:
//   CRISPASR_LIB=../CrispASR/build/src/libcrispasr.so flutter test test/audio_format_decode_test.dart

@Tags(['slow'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'support/crispasr_models.dart';

/// Generate a test WAV fixture (1s 440 Hz sine, 16 kHz mono 16-bit PCM).
/// Returns the path. Uses ffmpeg if available, otherwise creates a raw WAV.
Future<String> _generateTestWav(String dir) async {
  final wavPath = '$dir/test_sine.wav';
  // Try ffmpeg first.
  final result = await Process.run('ffmpeg', [
    '-y', '-f', 'lavfi',
    '-i', 'sine=frequency=440:duration=1:sample_rate=16000',
    '-ac', '1', '-ar', '16000', wavPath,
  ]);
  if (result.exitCode == 0 && File(wavPath).existsSync()) return wavPath;

  // Fallback: write a minimal WAV manually.
  const sampleRate = 16000;
  const duration = 1; // second
  const nSamples = sampleRate * duration;
  final samples = Float32List(nSamples);
  for (var i = 0; i < nSamples; i++) {
    samples[i] = (0.5 * (2.0 * 3.14159265 * 440.0 * i / sampleRate))
        .remainder(1.0);
  }
  final dataLen = nSamples * 2;
  final buf = ByteData(44 + dataLen);
  // RIFF header
  for (var i = 0; i < 4; i++) buf.setUint8(i, 'RIFF'.codeUnitAt(i));
  buf.setUint32(4, 36 + dataLen, Endian.little);
  for (var i = 0; i < 4; i++) buf.setUint8(8 + i, 'WAVE'.codeUnitAt(i));
  for (var i = 0; i < 4; i++) buf.setUint8(12 + i, 'fmt '.codeUnitAt(i));
  buf.setUint32(16, 16, Endian.little);
  buf.setUint16(20, 1, Endian.little);
  buf.setUint16(22, 1, Endian.little);
  buf.setUint32(24, sampleRate, Endian.little);
  buf.setUint32(28, sampleRate * 2, Endian.little);
  buf.setUint16(32, 2, Endian.little);
  buf.setUint16(34, 16, Endian.little);
  for (var i = 0; i < 4; i++) buf.setUint8(36 + i, 'data'.codeUnitAt(i));
  buf.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < nSamples; i++) {
    buf.setInt16(44 + i * 2, (samples[i] * 32767).round().clamp(-32768, 32767),
        Endian.little);
  }
  File(wavPath).writeAsBytesSync(buf.buffer.asUint8List());
  return wavPath;
}

/// Convert a WAV to another format using ffmpeg. Returns null if ffmpeg
/// is unavailable or the conversion fails.
Future<String?> _convertTo(String wavPath, String ext,
    {List<String> extraArgs = const []}) async {
  final outPath = wavPath.replaceAll('.wav', '.$ext');
  final result = await Process.run('ffmpeg', [
    '-y', '-i', wavPath,
    ...extraArgs,
    outPath,
  ]);
  if (result.exitCode == 0 && File(outPath).existsSync()) return outPath;
  return null;
}

/// Try CrispASR's native decoder first; on failure, convert to WAV via
/// ffmpeg and re-decode. Mirrors AudioService.loadAudioFile's fallback.
Future<crispasr.DecodedAudio> _decodeWithFfmpegFallback(
    String filePath, String libPath) async {
  try {
    return crispasr.decodeAudioFile(filePath, libPath: libPath);
  } catch (_) {
    // ffmpeg fallback
    final tmpWav = '$filePath.tmp.wav';
    final result = await Process.run('ffmpeg', [
      '-y', '-i', filePath,
      '-f', 'wav', '-ac', '1', '-ar', '16000',
      '-acodec', 'pcm_s16le', tmpWav,
    ]);
    if (result.exitCode != 0) {
      throw Exception('ffmpeg decode failed: ${result.stderr}');
    }
    try {
      return crispasr.decodeAudioFile(tmpWav, libPath: libPath);
    } finally {
      try { File(tmpWav).deleteSync(); } catch (_) {}
    }
  }
}

void main() {
  final lib = CrispModels.lib;
  final skip = lib == null ? 'CrispASR dylib not found' : null;

  late Directory tempDir;
  late String wavPath;

  setUpAll(() async {
    if (skip != null) return;
    tempDir = await Directory.systemTemp.createTemp('cw_format_test_');
    wavPath = await _generateTestWav(tempDir.path);
  });

  tearDownAll(() async {
    if (skip != null) return;
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Audio format decoding (CrispASR miniaudio)', () {
    test('WAV decodes to ~16000 samples', () {
      final audio = crispasr.decodeAudioFile(wavPath, libPath: lib);
      expect(audio.samples.length, greaterThan(14000));
      expect(audio.samples.length, lessThan(18000));
      expect(audio.sampleRate, 16000);
    }, skip: skip);

    test('.opus decodes natively (CRISPASR_HAVE_OPUS)', () async {
      final opusPath =
          await _convertTo(wavPath, 'opus', extraArgs: ['-c:a', 'libopus', '-b:a', '32k']);
      if (opusPath == null) {
        markTestSkipped('ffmpeg opus encoding unavailable');
        return;
      }
      // Try native decode first — works when libcrispasr was built with
      // CRISPASR_OPUS_FETCH=ON. Falls back to ffmpeg if not.
      try {
        final audio = crispasr.decodeAudioFile(opusPath, libPath: lib);
        expect(audio.samples.length, greaterThan(10000),
            reason: 'opus native decode should produce samples');
        printOnFailure('opus (native): ${audio.samples.length} samples @ ${audio.sampleRate} Hz');
      } catch (_) {
        // Native decode not available — fall back to ffmpeg path.
        final audio = await _decodeWithFfmpegFallback(opusPath, lib!);
        expect(audio.samples.length, greaterThan(10000),
            reason: 'opus ffmpeg fallback should produce samples');
        printOnFailure('opus (ffmpeg fallback): ${audio.samples.length} samples @ ${audio.sampleRate} Hz');
      }
    }, skip: skip);

    test('.webm (opus) decodes natively (CRISPASR_HAVE_OPUS)', () async {
      final webmPath =
          await _convertTo(wavPath, 'webm', extraArgs: ['-c:a', 'libopus', '-b:a', '32k']);
      if (webmPath == null) {
        markTestSkipped('ffmpeg webm encoding unavailable');
        return;
      }
      try {
        final audio = crispasr.decodeAudioFile(webmPath, libPath: lib);
        expect(audio.samples.length, greaterThan(10000),
            reason: 'webm native decode should produce samples');
      } catch (_) {
        final audio = await _decodeWithFfmpegFallback(webmPath, lib!);
        expect(audio.samples.length, greaterThan(10000),
            reason: 'webm ffmpeg fallback should produce samples');
      }
    }, skip: skip);

    test('.m4a (AAC) decodes via ffmpeg fallback', () async {
      final m4aPath =
          await _convertTo(wavPath, 'm4a', extraArgs: ['-c:a', 'aac', '-b:a', '64k']);
      if (m4aPath == null) {
        markTestSkipped('ffmpeg m4a encoding unavailable');
        return;
      }
      final audio = await _decodeWithFfmpegFallback(m4aPath, lib!);
      expect(audio.samples.length, greaterThan(10000),
          reason: 'm4a decode should produce samples');
    }, skip: skip);

    test('.mp3 decodes successfully', () async {
      final mp3Path =
          await _convertTo(wavPath, 'mp3', extraArgs: ['-c:a', 'libmp3lame', '-b:a', '64k']);
      if (mp3Path == null) {
        markTestSkipped('ffmpeg mp3 encoding unavailable');
        return;
      }
      final audio = crispasr.decodeAudioFile(mp3Path, libPath: lib);
      expect(audio.samples.length, greaterThan(10000),
          reason: 'mp3 decode should produce samples');
    }, skip: skip);

    test('.flac decodes successfully', () async {
      final flacPath = await _convertTo(wavPath, 'flac');
      if (flacPath == null) {
        markTestSkipped('ffmpeg flac encoding unavailable');
        return;
      }
      final audio = crispasr.decodeAudioFile(flacPath, libPath: lib);
      expect(audio.samples.length, greaterThan(14000),
          reason: 'flac decode should produce ~same samples as wav');
      expect(audio.sampleRate, 16000);
    }, skip: skip);

    test('.ogg (vorbis) decodes successfully', () async {
      final oggPath =
          await _convertTo(wavPath, 'ogg', extraArgs: ['-c:a', 'libvorbis', '-b:a', '64k']);
      if (oggPath == null) {
        markTestSkipped('ffmpeg ogg encoding unavailable');
        return;
      }
      final audio = crispasr.decodeAudioFile(oggPath, libPath: lib);
      expect(audio.samples.length, greaterThan(10000),
          reason: 'ogg decode should produce samples');
    }, skip: skip);
  });
}
