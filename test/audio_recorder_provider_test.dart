// Unit tests for AudioRecorderNotifier (§8.2).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/audio_recorder_provider.dart';

void main() {
  late ProviderContainer container;
  late AudioRecorderNotifier n;

  AudioRecorderState readState() => container.read(audioRecorderProvider);

  setUp(() {
    container = ProviderContainer();
    container.read(audioRecorderProvider);
    n = container.read(audioRecorderProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('initial state has sensible defaults', () {
    final s = readState();
    expect(s.isRecording, isFalse);
    expect(s.isPaused, isFalse);
    expect(s.isPlaying, isFalse);
    expect(s.amplitudes, isEmpty);
    expect(s.recordingDuration, Duration.zero);
    expect(s.recordingPath, isNull);
    expect(s.streamMode, isFalse);
    expect(s.isCapturingSystemAudio, isFalse);
    expect(s.systemAudioSupported, isFalse);
  });

  test('setIsRecording updates flag', () {
    n.setIsRecording(true);
    expect(readState().isRecording, isTrue);
  });

  test('setIsPaused updates flag', () {
    n.setIsPaused(true);
    expect(readState().isPaused, isTrue);
  });

  test('setIsPlaying updates flag', () {
    n.setIsPlaying(true);
    expect(readState().isPlaying, isTrue);
  });

  test('setStreamMode updates flag', () {
    n.setStreamMode(true);
    expect(readState().streamMode, isTrue);
  });

  test('setSystemAudioSupported updates flag', () {
    n.setSystemAudioSupported(true);
    expect(readState().systemAudioSupported, isTrue);
  });

  test('addAmplitude appends and caps at 100', () {
    for (int i = 0; i < 105; i++) {
      n.addAmplitude(i.toDouble());
    }
    final amps = readState().amplitudes;
    expect(amps.length, 100);
    // Oldest entries removed, newest kept
    expect(amps.first, 5.0);
    expect(amps.last, 104.0);
  });

  test('incrementDuration adds to existing duration', () {
    n.incrementDuration(const Duration(milliseconds: 100));
    n.incrementDuration(const Duration(milliseconds: 200));
    expect(readState().recordingDuration, const Duration(milliseconds: 300));
  });

  test('startRecording resets state with path', () {
    // Set some pre-existing state
    n.setIsPaused(true);
    n.incrementDuration(const Duration(seconds: 5));
    n.addAmplitude(0.5);

    n.startRecording(path: '/tmp/rec.wav');
    final s = readState();
    expect(s.isRecording, isTrue);
    expect(s.isPaused, isFalse);
    expect(s.recordingDuration, Duration.zero);
    expect(s.recordingPath, '/tmp/rec.wav');
    expect(s.amplitudes, isEmpty);
  });

  test('startRecording with null path clears recordingPath', () {
    n.setRecordingPath('/old.wav');
    n.startRecording(path: null);
    expect(readState().recordingPath, isNull);
    expect(readState().isRecording, isTrue);
  });

  test('stopRecording updates recording flag and path', () {
    n.startRecording(path: null);
    n.stopRecording(path: '/tmp/out.wav');
    final s = readState();
    expect(s.isRecording, isFalse);
    expect(s.isPaused, isFalse);
    expect(s.recordingPath, '/tmp/out.wav');
  });

  test('stopRecording without path clears recordingPath', () {
    n.startRecording(path: '/tmp/rec.wav');
    n.stopRecording();
    expect(readState().recordingPath, isNull);
  });

  test('deleteRecording clears path and duration', () {
    n.startRecording(path: '/tmp/rec.wav');
    n.stopRecording(path: '/tmp/rec.wav');
    n.deleteRecording();
    final s = readState();
    expect(s.recordingPath, isNull);
    expect(s.recordingDuration, Duration.zero);
  });

  test('startSystemCapture sets flag and resets duration', () {
    n.incrementDuration(const Duration(seconds: 10));
    n.startSystemCapture();
    final s = readState();
    expect(s.isCapturingSystemAudio, isTrue);
    expect(s.recordingDuration, Duration.zero);
  });

  test('stopSystemCapture clears flag', () {
    n.startSystemCapture();
    n.stopSystemCapture();
    expect(readState().isCapturingSystemAudio, isFalse);
  });

  test('multiple mutations are independent', () {
    n.setIsRecording(true);
    n.setStreamMode(true);
    n.setSystemAudioSupported(true);
    final s = readState();
    expect(s.isRecording, isTrue);
    expect(s.streamMode, isTrue);
    expect(s.systemAudioSupported, isTrue);
    // Unchanged defaults preserved
    expect(s.isPaused, isFalse);
    expect(s.isPlaying, isFalse);
    expect(s.recordingPath, isNull);
  });
}
