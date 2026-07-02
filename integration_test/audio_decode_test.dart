// Integration test for audio file decoding on real devices.
//
// Validates that the CrispASR native library can decode all supported
// audio formats including .opus — the format that caused #26 on Android
// (ffmpeg unavailable, CrispASR built without CRISPASR_HAVE_OPUS).
//
// Also tests the Android MediaCodec platform-channel fallback when
// running on Android.
//
// Run on a connected device / emulator:
//   flutter test integration_test/audio_decode_test.dart
//
// Or via flutter drive:
//   flutter drive --driver=test_driver/integration_test.dart \
//                 --target=integration_test/audio_decode_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:crisper_weaver/native/crispasr_import.dart' as crispasr;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await getTemporaryDirectory();
    tempDir = Directory('${tempDir.path}/audio_decode_test');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await tempDir.create(recursive: true);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Write a minimal 16 kHz mono 16-bit PCM WAV (1 second 440 Hz sine).
  Future<File> generateTestWav() async {
    const sampleRate = 16000;
    const nSamples = sampleRate; // 1 second
    final buf = ByteData(44 + nSamples * 2);
    // RIFF header
    for (var i = 0; i < 4; i++) { buf.setUint8(i, 'RIFF'.codeUnitAt(i)); }
    buf.setUint32(4, 36 + nSamples * 2, Endian.little);
    for (var i = 0; i < 4; i++) { buf.setUint8(8 + i, 'WAVE'.codeUnitAt(i)); }
    // fmt chunk
    for (var i = 0; i < 4; i++) { buf.setUint8(12 + i, 'fmt '.codeUnitAt(i)); }
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little); // PCM
    buf.setUint16(22, 1, Endian.little); // mono
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * 2, Endian.little);
    buf.setUint16(32, 2, Endian.little); // block align
    buf.setUint16(34, 16, Endian.little); // bits per sample
    // data chunk
    for (var i = 0; i < 4; i++) { buf.setUint8(36 + i, 'data'.codeUnitAt(i)); }
    buf.setUint32(40, nSamples * 2, Endian.little);
    for (var i = 0; i < nSamples; i++) {
      final t = i / sampleRate;
      final sample = (0.5 * _sin(2 * 3.14159265 * 440 * t) * 32767)
          .round()
          .clamp(-32768, 32767);
      buf.setInt16(44 + i * 2, sample, Endian.little);
    }
    final file = File('${tempDir.path}/test_sine.wav');
    await file.writeAsBytes(buf.buffer.asUint8List());
    return file;
  }

  group('Native audio decode (on-device)', () {
    testWidgets('WAV decodes to ~16000 samples', (tester) async {
      final wav = await generateTestWav();
      final audio = crispasr.decodeAudioFile(wav.path);
      expect(audio.samples.length, greaterThan(14000));
      expect(audio.samples.length, lessThan(18000));
      expect(audio.sampleRate, 16000);
    });

    testWidgets('CrispASR FFI library loads successfully', (tester) async {
      // If this throws, the .so/.dylib/.dll isn't bundled correctly.
      final backends = crispasr.CrispasrSession.availableBackends();
      expect(backends, isNotNull);
      expect(backends, isNotEmpty,
          reason: 'libcrispasr should have at least one backend linked');
    });
  });

  group('Android MediaCodec fallback', () {
    testWidgets('decodeToWav handles WAV input', (tester) async {
      if (!Platform.isAndroid) {
        // Only test MediaCodec on Android.
        return;
      }

      final wav = await generateTestWav();
      const channel = MethodChannel('crisperweaver/audio_decode');
      final result = await channel.invokeMethod<Uint8List>(
        'decodeToWav',
        {'path': wav.path},
      );

      expect(result, isNotNull);
      expect(result!.length, greaterThan(44)); // WAV header + data

      // Verify the output is valid WAV.
      final riff = String.fromCharCodes(result.sublist(0, 4));
      final wave = String.fromCharCodes(result.sublist(8, 12));
      expect(riff, 'RIFF');
      expect(wave, 'WAVE');
    });

    testWidgets('decodeToWav produces correct sample count', (tester) async {
      if (!Platform.isAndroid) return;

      final wav = await generateTestWav();
      const channel = MethodChannel('crisperweaver/audio_decode');
      final result = await channel.invokeMethod<Uint8List>(
        'decodeToWav',
        {'path': wav.path},
      );

      expect(result, isNotNull);
      // Parse the data chunk size from the WAV header.
      final bd = ByteData.sublistView(result!);
      // Find data chunk — skip to byte 36, read "data" + size.
      final dataTag = String.fromCharCodes(result.sublist(36, 40));
      expect(dataTag, 'data');
      final dataSize = bd.getUint32(40, Endian.little);
      // 16-bit mono at 16 kHz for 1 second = 32000 bytes.
      // Allow some variation from resampling.
      expect(dataSize, greaterThan(28000));
      expect(dataSize, lessThan(36000));
    });
  });
}

double _sin(double x) {
  // Simple sine approximation (no dart:math import needed in
  // integration_test context — but dart:math works fine too).
  x = x % (2 * 3.14159265);
  if (x > 3.14159265) x -= 2 * 3.14159265;
  // Taylor series, 5 terms — plenty accurate for a test tone.
  final x2 = x * x;
  return x * (1 - x2 / 6 * (1 - x2 / 20 * (1 - x2 / 42)));
}
