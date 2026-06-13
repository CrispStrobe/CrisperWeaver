// AudioUtils — pure audio math and formatting helpers.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/utils/audio_utils.dart';

void main() {
  group('isSupportedAudioFile', () {
    test('recognises common audio extensions', () {
      for (final ext in ['.wav', '.mp3', '.flac', '.m4a', '.ogg', '.aac', '.opus']) {
        expect(AudioUtils.isSupportedAudioFile('test$ext'), isTrue,
            reason: ext);
      }
    });

    test('rejects non-audio extensions', () {
      expect(AudioUtils.isSupportedAudioFile('readme.txt'), isFalse);
      expect(AudioUtils.isSupportedAudioFile('photo.png'), isFalse);
    });

    test('case insensitive', () {
      expect(AudioUtils.isSupportedAudioFile('LOUD.WAV'), isTrue);
      expect(AudioUtils.isSupportedAudioFile('song.Mp3'), isTrue);
    });
  });

  group('formatDuration', () {
    test('zero seconds', () {
      expect(AudioUtils.formatDuration(0), '00:00');
    });

    test('seconds only', () {
      expect(AudioUtils.formatDuration(45), '00:45');
    });

    test('minutes and seconds', () {
      expect(AudioUtils.formatDuration(125), '02:05');
    });

    test('hours', () {
      final result = AudioUtils.formatDuration(3661);
      expect(result, contains('01'));
      expect(result, contains('01'));
    });
  });

  group('formatFileSize', () {
    test('bytes', () {
      expect(AudioUtils.formatFileSize(500), contains('B'));
    });

    test('kilobytes', () {
      final result = AudioUtils.formatFileSize(2048);
      expect(result, contains('KB'));
    });

    test('megabytes', () {
      final result = AudioUtils.formatFileSize(5 * 1024 * 1024);
      expect(result, contains('MB'));
    });

    test('gigabytes', () {
      final result = AudioUtils.formatFileSize(3 * 1024 * 1024 * 1024);
      expect(result, contains('GB'));
    });
  });

  group('float32 ↔ bytes', () {
    test('round-trip preserves data', () {
      final original = Float32List.fromList([0.5, -0.5, 1.0, -1.0, 0.0]);
      final bytes = AudioUtils.float32ListToBytes(original);
      final restored = AudioUtils.bytesToFloat32List(bytes);
      expect(restored.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(restored[i], closeTo(original[i], 1e-6));
      }
    });

    test('byte length is 4x float count', () {
      final floats = Float32List.fromList([1.0, 2.0, 3.0]);
      expect(AudioUtils.float32ListToBytes(floats).length, 12);
    });
  });

  group('normalizeAudio', () {
    test('scales peak to 1.0', () {
      final samples = Float32List.fromList([0.0, 0.25, -0.5, 0.1]);
      final norm = AudioUtils.normalizeAudio(samples);
      expect(norm.reduce((a, b) => a.abs() > b.abs() ? a : b).abs(),
          closeTo(1.0, 1e-6));
    });

    test('silent input returns zeros', () {
      final samples = Float32List.fromList([0.0, 0.0, 0.0]);
      final norm = AudioUtils.normalizeAudio(samples);
      expect(norm.every((s) => s == 0.0), isTrue);
    });
  });

  group('calculateRMS', () {
    test('silence → 0', () {
      final silence = Float32List.fromList([0.0, 0.0, 0.0]);
      expect(AudioUtils.calculateRMS(silence), closeTo(0.0, 1e-10));
    });

    test('DC signal → amplitude', () {
      // Constant 0.5 → RMS = 0.5
      final dc = Float32List.fromList([0.5, 0.5, 0.5, 0.5]);
      expect(AudioUtils.calculateRMS(dc), closeTo(0.5, 1e-6));
    });
  });

  group('calculatePeak', () {
    test('finds positive peak', () {
      final samples = Float32List.fromList([0.1, 0.8, -0.3]);
      expect(AudioUtils.calculatePeak(samples), closeTo(0.8, 1e-6));
    });

    test('finds negative peak', () {
      final samples = Float32List.fromList([0.1, -0.9, 0.3]);
      expect(AudioUtils.calculatePeak(samples), closeTo(0.9, 1e-6));
    });
  });

  group('isSilence', () {
    test('true for zeros', () {
      expect(AudioUtils.isSilence(Float32List.fromList([0.0, 0.0])), isTrue);
    });

    test('false for loud signal', () {
      expect(AudioUtils.isSilence(Float32List.fromList([0.5, -0.5])), isFalse);
    });

    test('respects custom threshold', () {
      final quiet = Float32List.fromList([0.005, -0.005, 0.003]);
      expect(AudioUtils.isSilence(quiet, threshold: 0.01), isTrue);
      expect(AudioUtils.isSilence(quiet, threshold: 0.001), isFalse);
    });
  });

  group('stereoToMono', () {
    test('averages L/R channels', () {
      // Stereo: [L0, R0, L1, R1]
      final stereo = Float32List.fromList([1.0, 0.0, 0.0, 1.0]);
      final mono = AudioUtils.stereoToMono(stereo);
      expect(mono.length, 2);
      expect(mono[0], closeTo(0.5, 1e-6)); // (1+0)/2
      expect(mono[1], closeTo(0.5, 1e-6)); // (0+1)/2
    });
  });

  group('generateSineWave', () {
    test('generates correct length', () {
      final wave = AudioUtils.generateSineWave(440, 0.5, 16000);
      expect(wave.length, 8000); // 16000 * 0.5
    });

    test('peak amplitude matches parameter', () {
      final wave = AudioUtils.generateSineWave(440, 0.1, 16000,
          amplitude: 0.7);
      final peak = AudioUtils.calculatePeak(wave);
      expect(peak, closeTo(0.7, 0.01));
    });
  });

}
