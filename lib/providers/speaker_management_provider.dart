// §8.2 — Riverpod provider for SpeakerManagementScreen local UI state.
// Only covers the outer management screen; the inner _EnrolSpeakerScreen
// keeps its own local setState since it's a dialog-like flow.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable state for the SpeakerManagementScreen.
class SpeakerManagementState {
  final List<String>? speakers;
  final bool modelAvailable;

  const SpeakerManagementState({
    this.speakers,
    this.modelAvailable = false,
  });

  SpeakerManagementState copyWith({
    List<String>? speakers,
    bool? modelAvailable,
    bool clearSpeakers = false,
  }) =>
      SpeakerManagementState(
        speakers: clearSpeakers ? null : (speakers ?? this.speakers),
        modelAvailable: modelAvailable ?? this.modelAvailable,
      );
}

class SpeakerManagementNotifier
    extends Notifier<SpeakerManagementState> {
  @override
  SpeakerManagementState build() => const SpeakerManagementState();

  void setSpeakers(List<String>? v) => state = state.copyWith(
        speakers: v,
        clearSpeakers: v == null,
      );
  void setModelAvailable(bool v) =>
      state = state.copyWith(modelAvailable: v);

  void setRefreshResult({required List<String> speakers, required bool modelAvailable}) {
    state = state.copyWith(speakers: speakers, modelAvailable: modelAvailable);
  }
}

final speakerManagementProvider = NotifierProvider<
    SpeakerManagementNotifier, SpeakerManagementState>(
  SpeakerManagementNotifier.new,
);
