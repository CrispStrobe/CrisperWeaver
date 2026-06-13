// §8.2 — Riverpod provider for AudioRecorderWidget local UI state.
// Timer, AnimationController, StreamController/Subscription stay as
// local widget state for dispose lifecycle.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable state for the AudioRecorderWidget.
class AudioRecorderState {
  final bool isRecording;
  final bool isPaused;
  final bool isPlaying;
  final List<double> amplitudes;
  final Duration recordingDuration;
  final String? recordingPath;
  final bool streamMode;
  final bool isCapturingSystemAudio;
  final bool systemAudioSupported;

  const AudioRecorderState({
    this.isRecording = false,
    this.isPaused = false,
    this.isPlaying = false,
    this.amplitudes = const [],
    this.recordingDuration = Duration.zero,
    this.recordingPath,
    this.streamMode = false,
    this.isCapturingSystemAudio = false,
    this.systemAudioSupported = false,
  });

  AudioRecorderState copyWith({
    bool? isRecording,
    bool? isPaused,
    bool? isPlaying,
    List<double>? amplitudes,
    Duration? recordingDuration,
    String? recordingPath,
    bool? streamMode,
    bool? isCapturingSystemAudio,
    bool? systemAudioSupported,
    bool clearRecordingPath = false,
  }) =>
      AudioRecorderState(
        isRecording: isRecording ?? this.isRecording,
        isPaused: isPaused ?? this.isPaused,
        isPlaying: isPlaying ?? this.isPlaying,
        amplitudes: amplitudes ?? this.amplitudes,
        recordingDuration: recordingDuration ?? this.recordingDuration,
        recordingPath:
            clearRecordingPath ? null : (recordingPath ?? this.recordingPath),
        streamMode: streamMode ?? this.streamMode,
        isCapturingSystemAudio:
            isCapturingSystemAudio ?? this.isCapturingSystemAudio,
        systemAudioSupported:
            systemAudioSupported ?? this.systemAudioSupported,
      );
}

class AudioRecorderNotifier
    extends Notifier<AudioRecorderState> {
  @override
  AudioRecorderState build() => const AudioRecorderState();

  void setIsRecording(bool v) => state = state.copyWith(isRecording: v);
  void setIsPaused(bool v) => state = state.copyWith(isPaused: v);
  void setIsPlaying(bool v) => state = state.copyWith(isPlaying: v);
  void setAmplitudes(List<double> v) => state = state.copyWith(amplitudes: v);
  void setRecordingDuration(Duration v) =>
      state = state.copyWith(recordingDuration: v);
  void setRecordingPath(String? v) =>
      state = state.copyWith(recordingPath: v, clearRecordingPath: v == null);
  void setStreamMode(bool v) => state = state.copyWith(streamMode: v);
  void setIsCapturingSystemAudio(bool v) =>
      state = state.copyWith(isCapturingSystemAudio: v);
  void setSystemAudioSupported(bool v) =>
      state = state.copyWith(systemAudioSupported: v);

  void addAmplitude(double amp) {
    final list = [...state.amplitudes, amp];
    if (list.length > 100) list.removeAt(0);
    state = state.copyWith(amplitudes: list);
  }

  void incrementDuration(Duration delta) {
    state = state.copyWith(
        recordingDuration: state.recordingDuration + delta);
  }

  /// Bulk update for start-recording transition.
  void startRecording({required String? path}) {
    state = state.copyWith(
      isRecording: true,
      isPaused: false,
      recordingDuration: Duration.zero,
      recordingPath: path,
      amplitudes: const [],
      clearRecordingPath: path == null,
    );
  }

  /// Bulk update for stop-recording transition.
  void stopRecording({String? path}) {
    state = state.copyWith(
      isRecording: false,
      isPaused: false,
      recordingPath: path,
      clearRecordingPath: path == null,
    );
  }

  /// Bulk update for delete recording.
  void deleteRecording() {
    state = state.copyWith(
      clearRecordingPath: true,
      recordingDuration: Duration.zero,
    );
  }

  /// Start system audio capture.
  void startSystemCapture() {
    state = state.copyWith(
      isCapturingSystemAudio: true,
      recordingDuration: Duration.zero,
    );
  }

  /// Stop system audio capture.
  void stopSystemCapture() {
    state = state.copyWith(isCapturingSystemAudio: false);
  }
}

final audioRecorderProvider = NotifierProvider<
    AudioRecorderNotifier, AudioRecorderState>(
  AudioRecorderNotifier.new,
);
