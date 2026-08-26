// §OOM pre-flight (issues #33, #34).
//
// The guard exists because the session-backend path hands libcrispasr the
// whole file in one FFI call — only whisper is chunked — so audio length is
// an unbounded input to a native allocation. What that failure looks like
// from outside is a native abort with no Dart stack, or on Windows a
// whole-desktop freeze with no log at all.
//
// These tests pin the two properties that matter: the projection actually
// scales with audio length, and we never refuse on a guess.

import 'dart:io';

import 'package:crisper_weaver/services/memory_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late File modelFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('preflight');
    modelFile = File('${tmp.path}/model.gguf');
    // 2 GB "on disk" without writing 2 GB.
    modelFile.createSync();
    final raf = modelFile.openSync(mode: FileMode.write);
    raf.truncateSync(2 * 1024 * 1024 * 1024);
    raf.closeSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  MemoryEstimator estimatorWith(int? ram) =>
      MemoryEstimator()..physicalMemoryBytesForTest = ram;

  test('a short file with a big model on a small box still fits', () {
    final e = estimatorWith(8 * 1024 * 1024 * 1024); // 8 GB
    final r = e.estimateTranscribe(
      modelPath: modelFile.path,
      audioSeconds: 30,
    );
    // 400 MB base + 2 GB x 1.6 + negligible audio = ~3.6 GB, under 6.4 GB.
    expect(r.fits, isTrue);
    expect(r.reason, 'fits');
  });

  test('the same model and box refuses a long enough recording', () {
    final e = estimatorWith(8 * 1024 * 1024 * 1024); // 8 GB
    // 4 hours at 256 KB/s is ~3.7 GB on top of the ~3.6 GB fixed cost,
    // which clears the 6.4 GB budget. This is the shape of the reports we
    // cannot debug: nothing is wrong with the model or the audio, there is
    // simply not enough RAM, and the native side has no way to say so.
    final r = e.estimateTranscribe(
      modelPath: modelFile.path,
      audioSeconds: 4 * 60 * 60,
    );
    expect(r.fits, isFalse);
    expect(r.reason, 'too-large');
    expect(r.prettyAudio, '240m 0s');
  });

  test('projection grows with audio length', () {
    final e = estimatorWith(64 * 1024 * 1024 * 1024);
    final short =
        e.estimateTranscribe(modelPath: modelFile.path, audioSeconds: 60);
    final long =
        e.estimateTranscribe(modelPath: modelFile.path, audioSeconds: 3600);
    expect(long.projectedUsageBytes,
        greaterThan(short.projectedUsageBytes));
    // The delta is exactly the audio term — the model term is unchanged.
    expect(long.projectedUsageBytes - short.projectedUsageBytes,
        (3600 - 60) * MemoryEstimator.bytesPerAudioSecond);
    expect(short.modelBytes, long.modelBytes);
  });

  test('a roomy machine is never blocked', () {
    final e = estimatorWith(128 * 1024 * 1024 * 1024);
    final r = e.estimateTranscribe(
      modelPath: modelFile.path,
      audioSeconds: 6 * 60 * 60,
    );
    expect(r.fits, isTrue);
  });

  group('never refuse on a guess', () {
    test('unknown system RAM permits the run', () {
      final e = estimatorWith(null);
      final r = e.estimateTranscribe(
        modelPath: modelFile.path,
        audioSeconds: 10 * 60 * 60,
      );
      expect(r.fits, isTrue);
      expect(r.reason, 'unknown-mem');
    });

    test('an unreadable model path permits the run', () {
      // Not our failure to report: the model load below raises a proper
      // ModelLoadException, which says something far more useful than a
      // memory refusal built on a zero-byte estimate.
      final e = estimatorWith(4 * 1024 * 1024 * 1024);
      final r = e.estimateTranscribe(
        modelPath: '${tmp.path}/does-not-exist.gguf',
        audioSeconds: 10 * 60 * 60,
      );
      expect(r.fits, isTrue);
      expect(r.reason, 'unknown-mem');
    });

    test('a null model path permits the run', () {
      final e = estimatorWith(4 * 1024 * 1024 * 1024);
      final r = e.estimateTranscribe(modelPath: null, audioSeconds: 600);
      expect(r.fits, isTrue);
      expect(r.reason, 'unknown-mem');
    });
  });

  test('measured baseline: qwen3-asr-0.6b at 30 min fits in 16 GB', () {
    // Anchored to the run that motivated the constant: qwen3-asr-0.6b-q4_k
    // (631 MB GGUF) transcribed 1804 s on a 16 GB machine at 1.58 GB peak
    // RSS. The guard must not stand in the way of a decode we have watched
    // succeed — a false refusal is a regression, not a safety margin.
    final gguf = File('${tmp.path}/qwen.gguf');
    gguf.createSync();
    final raf = gguf.openSync(mode: FileMode.write);
    raf.truncateSync(631026336);
    raf.closeSync();
    final e = estimatorWith(16 * 1024 * 1024 * 1024);
    final r = e.estimateTranscribe(modelPath: gguf.path, audioSeconds: 1804);
    expect(r.fits, isTrue);
  });
}
