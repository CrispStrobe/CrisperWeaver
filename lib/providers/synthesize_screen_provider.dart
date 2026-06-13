// §8.2 — Riverpod provider for SynthesizeScreen local UI state.
// TextEditingControllers and AudioPlayer stay as local widget state
// for dispose lifecycle.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pronunciation_lexicon.dart';
import '../services/model_service.dart';

/// Sampling parameters sub-class — groups the ~12 TTS knobs so the
/// main state class stays readable.
class TtsSamplingParams {
  final double temperature;
  final double topP;
  final double cfgWeight;
  final double exaggeration;
  final int ttsSteps;
  final double minP;
  final double repetitionPenalty;
  final int maxSpeechTokens;
  final int ttsSeed;
  final double frequencyPenalty;

  const TtsSamplingParams({
    this.temperature = 0.8,
    this.topP = 1.0,
    this.cfgWeight = 0.5,
    this.exaggeration = 0.5,
    this.ttsSteps = 10,
    this.minP = 0.0,
    this.repetitionPenalty = 1.0,
    this.maxSpeechTokens = 1000,
    this.ttsSeed = 0,
    this.frequencyPenalty = 0.0,
  });

  TtsSamplingParams copyWith({
    double? temperature,
    double? topP,
    double? cfgWeight,
    double? exaggeration,
    int? ttsSteps,
    double? minP,
    double? repetitionPenalty,
    int? maxSpeechTokens,
    int? ttsSeed,
    double? frequencyPenalty,
  }) =>
      TtsSamplingParams(
        temperature: temperature ?? this.temperature,
        topP: topP ?? this.topP,
        cfgWeight: cfgWeight ?? this.cfgWeight,
        exaggeration: exaggeration ?? this.exaggeration,
        ttsSteps: ttsSteps ?? this.ttsSteps,
        minP: minP ?? this.minP,
        repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
        maxSpeechTokens: maxSpeechTokens ?? this.maxSpeechTokens,
        ttsSeed: ttsSeed ?? this.ttsSeed,
        frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      );
}

/// Immutable state for the SynthesizeScreen.
class SynthesizeScreenState {
  final List<ModelInfo> allModels;
  final bool loading;
  final bool busy;
  final String? selectedModel;
  final String? selectedVoice;
  final String? selectedCodec;
  final String? selectedSpeaker;
  final List<String> presetSpeakers;
  final bool loadingSpeakers;
  final int nSpeakers;
  final int? selectedSpeakerId;
  final String? customVoiceWavPath;
  final File? lastWav;
  final bool trimSilence;
  final double speed;
  final bool showAdvanced;
  final TtsSamplingParams sampling;
  final bool s2sMode;
  final String? s2sInputPath;
  final PronunciationLexicon? lexicon;

  const SynthesizeScreenState({
    this.allModels = const [],
    this.loading = true,
    this.busy = false,
    this.selectedModel,
    this.selectedVoice,
    this.selectedCodec,
    this.selectedSpeaker,
    this.presetSpeakers = const [],
    this.loadingSpeakers = false,
    this.nSpeakers = 0,
    this.selectedSpeakerId,
    this.customVoiceWavPath,
    this.lastWav,
    this.trimSilence = false,
    this.speed = 1.0,
    this.showAdvanced = false,
    this.sampling = const TtsSamplingParams(),
    this.s2sMode = false,
    this.s2sInputPath,
    this.lexicon,
  });

  SynthesizeScreenState copyWith({
    List<ModelInfo>? allModels,
    bool? loading,
    bool? busy,
    String? selectedModel,
    String? selectedVoice,
    String? selectedCodec,
    String? selectedSpeaker,
    List<String>? presetSpeakers,
    bool? loadingSpeakers,
    int? nSpeakers,
    int? selectedSpeakerId,
    String? customVoiceWavPath,
    File? lastWav,
    bool? trimSilence,
    double? speed,
    bool? showAdvanced,
    TtsSamplingParams? sampling,
    bool? s2sMode,
    String? s2sInputPath,
    PronunciationLexicon? lexicon,
    bool clearSelectedModel = false,
    bool clearSelectedVoice = false,
    bool clearSelectedCodec = false,
    bool clearSelectedSpeaker = false,
    bool clearSelectedSpeakerId = false,
    bool clearCustomVoiceWavPath = false,
    bool clearLastWav = false,
    bool clearS2sInputPath = false,
    bool clearLexicon = false,
  }) =>
      SynthesizeScreenState(
        allModels: allModels ?? this.allModels,
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
        selectedModel: clearSelectedModel
            ? null
            : (selectedModel ?? this.selectedModel),
        selectedVoice: clearSelectedVoice
            ? null
            : (selectedVoice ?? this.selectedVoice),
        selectedCodec: clearSelectedCodec
            ? null
            : (selectedCodec ?? this.selectedCodec),
        selectedSpeaker: clearSelectedSpeaker
            ? null
            : (selectedSpeaker ?? this.selectedSpeaker),
        presetSpeakers: presetSpeakers ?? this.presetSpeakers,
        loadingSpeakers: loadingSpeakers ?? this.loadingSpeakers,
        nSpeakers: nSpeakers ?? this.nSpeakers,
        selectedSpeakerId: clearSelectedSpeakerId
            ? null
            : (selectedSpeakerId ?? this.selectedSpeakerId),
        customVoiceWavPath: clearCustomVoiceWavPath
            ? null
            : (customVoiceWavPath ?? this.customVoiceWavPath),
        lastWav: clearLastWav ? null : (lastWav ?? this.lastWav),
        trimSilence: trimSilence ?? this.trimSilence,
        speed: speed ?? this.speed,
        showAdvanced: showAdvanced ?? this.showAdvanced,
        sampling: sampling ?? this.sampling,
        s2sMode: s2sMode ?? this.s2sMode,
        s2sInputPath: clearS2sInputPath
            ? null
            : (s2sInputPath ?? this.s2sInputPath),
        lexicon: clearLexicon ? null : (lexicon ?? this.lexicon),
      );
}

class SynthesizeScreenNotifier
    extends Notifier<SynthesizeScreenState> {
  @override
  SynthesizeScreenState build() => const SynthesizeScreenState();

  void setAllModels(List<ModelInfo> v) =>
      state = state.copyWith(allModels: v);
  void setLoading(bool v) => state = state.copyWith(loading: v);
  void setBusy(bool v) => state = state.copyWith(busy: v);
  void setSelectedModel(String? v) =>
      state = state.copyWith(selectedModel: v, clearSelectedModel: v == null);
  void setSelectedVoice(String? v) =>
      state = state.copyWith(selectedVoice: v, clearSelectedVoice: v == null);
  void setSelectedCodec(String? v) =>
      state = state.copyWith(selectedCodec: v, clearSelectedCodec: v == null);
  void setSelectedSpeaker(String? v) => state =
      state.copyWith(selectedSpeaker: v, clearSelectedSpeaker: v == null);
  void setPresetSpeakers(List<String> v) =>
      state = state.copyWith(presetSpeakers: v);
  void setLoadingSpeakers(bool v) =>
      state = state.copyWith(loadingSpeakers: v);
  void setNSpeakers(int v) => state = state.copyWith(nSpeakers: v);
  void setSelectedSpeakerId(int? v) => state = state.copyWith(
      selectedSpeakerId: v, clearSelectedSpeakerId: v == null);
  void setCustomVoiceWavPath(String? v) => state = state.copyWith(
      customVoiceWavPath: v, clearCustomVoiceWavPath: v == null);
  void setLastWav(File? v) =>
      state = state.copyWith(lastWav: v, clearLastWav: v == null);
  void setTrimSilence(bool v) => state = state.copyWith(trimSilence: v);
  void setSpeed(double v) => state = state.copyWith(speed: v);
  void setShowAdvanced(bool v) => state = state.copyWith(showAdvanced: v);
  void setSampling(TtsSamplingParams v) =>
      state = state.copyWith(sampling: v);
  void setS2sMode(bool v) => state = state.copyWith(s2sMode: v);
  void setS2sInputPath(String? v) =>
      state = state.copyWith(s2sInputPath: v, clearS2sInputPath: v == null);
  void setLexicon(PronunciationLexicon? v) =>
      state = state.copyWith(lexicon: v, clearLexicon: v == null);

  // Convenience setters for individual sampling params.
  void setTemperature(double v) =>
      state = state.copyWith(sampling: state.sampling.copyWith(temperature: v));
  void setTopP(double v) =>
      state = state.copyWith(sampling: state.sampling.copyWith(topP: v));
  void setCfgWeight(double v) =>
      state = state.copyWith(sampling: state.sampling.copyWith(cfgWeight: v));
  void setExaggeration(double v) =>
      state =
          state.copyWith(sampling: state.sampling.copyWith(exaggeration: v));
  void setTtsSteps(int v) =>
      state = state.copyWith(sampling: state.sampling.copyWith(ttsSteps: v));
  void setMinP(double v) =>
      state = state.copyWith(sampling: state.sampling.copyWith(minP: v));
  void setRepetitionPenalty(double v) => state = state.copyWith(
      sampling: state.sampling.copyWith(repetitionPenalty: v));
  void setMaxSpeechTokens(int v) => state = state.copyWith(
      sampling: state.sampling.copyWith(maxSpeechTokens: v));
  void setTtsSeed(int v) =>
      state = state.copyWith(sampling: state.sampling.copyWith(ttsSeed: v));
  void setFrequencyPenalty(double v) => state = state.copyWith(
      sampling: state.sampling.copyWith(frequencyPenalty: v));

  /// Reset speaker-related fields when model changes.
  void resetSpeakerState() {
    state = state.copyWith(
      clearSelectedSpeaker: true,
      clearSelectedSpeakerId: true,
      nSpeakers: 0,
      presetSpeakers: const [],
    );
  }

  /// Bulk update for start-synth.
  void startSynth() {
    state = state.copyWith(busy: true, clearLastWav: true);
  }
}

final synthesizeScreenProvider = NotifierProvider<
    SynthesizeScreenNotifier, SynthesizeScreenState>(
  SynthesizeScreenNotifier.new,
);
