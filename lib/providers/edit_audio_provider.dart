// §8.2 — Riverpod provider for EditAudioScreen local UI state.
// AudioPlayer, ScrollController, and GlobalKeys stay as local widget
// state for dispose lifecycle.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_edit_service.dart';
import '../widgets/waveform_painter.dart';

/// Immutable state for the EditAudioScreen.
class EditAudioState {
  final DecodedSource? decoded;
  final WaveformBars? bars;
  final double waveformWidth;
  final String? decodeError;
  final bool isPlaying;
  final WaveformSelection? selection;
  final List<WaveformCutMarker> cutMarkers;
  final bool showTranscript;
  final int? highlightedSegmentIndex;

  const EditAudioState({
    this.decoded,
    this.bars,
    this.waveformWidth = 0,
    this.decodeError,
    this.isPlaying = false,
    this.selection,
    this.cutMarkers = const [],
    this.showTranscript = false,
    this.highlightedSegmentIndex,
  });

  EditAudioState copyWith({
    DecodedSource? decoded,
    WaveformBars? bars,
    double? waveformWidth,
    String? decodeError,
    bool? isPlaying,
    WaveformSelection? selection,
    List<WaveformCutMarker>? cutMarkers,
    bool? showTranscript,
    int? highlightedSegmentIndex,
    bool clearDecoded = false,
    bool clearDecodeError = false,
    bool clearSelection = false,
    bool clearHighlightedSegmentIndex = false,
  }) =>
      EditAudioState(
        decoded: clearDecoded ? null : (decoded ?? this.decoded),
        bars: bars ?? this.bars,
        waveformWidth: waveformWidth ?? this.waveformWidth,
        decodeError:
            clearDecodeError ? null : (decodeError ?? this.decodeError),
        isPlaying: isPlaying ?? this.isPlaying,
        selection: clearSelection ? null : (selection ?? this.selection),
        cutMarkers: cutMarkers ?? this.cutMarkers,
        showTranscript: showTranscript ?? this.showTranscript,
        highlightedSegmentIndex: clearHighlightedSegmentIndex
            ? null
            : (highlightedSegmentIndex ?? this.highlightedSegmentIndex),
      );
}

class EditAudioNotifier extends Notifier<EditAudioState> {
  @override
  EditAudioState build() => const EditAudioState();

  void setDecoded(DecodedSource? v) =>
      state = state.copyWith(decoded: v, clearDecoded: v == null);
  void setBars(WaveformBars v) => state = state.copyWith(bars: v);
  void setWaveformWidth(double v) => state = state.copyWith(waveformWidth: v);
  void setDecodeError(String? v) =>
      state = state.copyWith(decodeError: v, clearDecodeError: v == null);
  void setIsPlaying(bool v) => state = state.copyWith(isPlaying: v);
  void setSelection(WaveformSelection? v) =>
      state = state.copyWith(selection: v, clearSelection: v == null);
  void setCutMarkers(List<WaveformCutMarker> v) =>
      state = state.copyWith(cutMarkers: v);
  void addCutMarker(WaveformCutMarker marker) =>
      state = state.copyWith(cutMarkers: [...state.cutMarkers, marker]);
  void clearCutMarkers() => state = state.copyWith(cutMarkers: const []);
  void setShowTranscript(bool v) =>
      state = state.copyWith(showTranscript: v);
  void setHighlightedSegmentIndex(int? v) => state = state.copyWith(
        highlightedSegmentIndex: v,
        clearHighlightedSegmentIndex: v == null,
      );

  void setBarsAndWidth({required WaveformBars bars, required double width}) {
    state = state.copyWith(bars: bars, waveformWidth: width);
  }
}

final editAudioProvider =
    NotifierProvider<EditAudioNotifier, EditAudioState>(
  EditAudioNotifier.new,
);
