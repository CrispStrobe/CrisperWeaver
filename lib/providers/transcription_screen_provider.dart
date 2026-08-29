// §8.2 — Riverpod provider for TranscriptionScreen UI-only state.
// Transcription segments and progress stay in appStateProvider.
// TextEditingControllers stay as local widget state for dispose lifecycle.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/model_service.dart';

/// Immutable state for the TranscriptionScreen.
class TranscriptionScreenState {
  final String? selectedFilePath;
  final Uint8List? selectedFileBytes;
  final String? selectedFileName;
  final bool showAdvancedOptions;
  final bool enableDiarization;

  /// §35 — Speaker-count bounds from the diarisation card. `null` =
  /// "Auto" (the library estimates). These reach
  /// `TranscriptionService.transcribeFile` / `.diarize`, which forward
  /// them to `crispasr_diarize_*`; `maxSpeakers` additionally caps the
  /// Dart-side agglomerative re-clustering pass. They used to live in
  /// the widget's own State and never left it.
  final int? minSpeakers;
  final int? maxSpeakers;
  final String language;
  final String modelName;
  final bool engineReady;
  final List<ModelInfo> availableModels;
  final bool loadingModels;
  final String modelNameFilter;
  final String backendFilter;
  final bool transcribePending;
  final bool loadCancelled;
  final bool dropHover;
  final bool tagSegmentLanguages;

  const TranscriptionScreenState({
    this.selectedFilePath,
    this.selectedFileBytes,
    this.selectedFileName,
    this.showAdvancedOptions = false,
    this.enableDiarization = false,
    this.minSpeakers,
    this.maxSpeakers,
    this.language = 'auto',
    this.modelName = 'base',
    this.engineReady = false,
    this.availableModels = const [],
    this.loadingModels = false,
    this.modelNameFilter = '',
    this.backendFilter = '',
    this.transcribePending = false,
    this.loadCancelled = false,
    this.dropHover = false,
    this.tagSegmentLanguages = false,
  });

  TranscriptionScreenState copyWith({
    String? selectedFilePath,
    Uint8List? selectedFileBytes,
    String? selectedFileName,
    bool? showAdvancedOptions,
    bool? enableDiarization,
    int? minSpeakers,
    int? maxSpeakers,
    String? language,
    String? modelName,
    bool? engineReady,
    List<ModelInfo>? availableModels,
    bool? loadingModels,
    String? modelNameFilter,
    String? backendFilter,
    bool? transcribePending,
    bool? loadCancelled,
    bool? dropHover,
    bool? tagSegmentLanguages,
    bool clearSelectedFilePath = false,
    bool clearSelectedFileBytes = false,
    bool clearSelectedFileName = false,
    // Speaker bounds are nullable *values* — "Auto" has to be
    // expressible, so ?? can't carry it.
    bool clearMinSpeakers = false,
    bool clearMaxSpeakers = false,
  }) =>
      TranscriptionScreenState(
        selectedFilePath: clearSelectedFilePath
            ? null
            : (selectedFilePath ?? this.selectedFilePath),
        selectedFileBytes: clearSelectedFileBytes
            ? null
            : (selectedFileBytes ?? this.selectedFileBytes),
        selectedFileName: clearSelectedFileName
            ? null
            : (selectedFileName ?? this.selectedFileName),
        showAdvancedOptions:
            showAdvancedOptions ?? this.showAdvancedOptions,
        enableDiarization:
            enableDiarization ?? this.enableDiarization,
        minSpeakers:
            clearMinSpeakers ? null : (minSpeakers ?? this.minSpeakers),
        maxSpeakers:
            clearMaxSpeakers ? null : (maxSpeakers ?? this.maxSpeakers),
        language: language ?? this.language,
        modelName: modelName ?? this.modelName,
        engineReady: engineReady ?? this.engineReady,
        availableModels: availableModels ?? this.availableModels,
        loadingModels: loadingModels ?? this.loadingModels,
        modelNameFilter: modelNameFilter ?? this.modelNameFilter,
        backendFilter: backendFilter ?? this.backendFilter,
        transcribePending:
            transcribePending ?? this.transcribePending,
        loadCancelled: loadCancelled ?? this.loadCancelled,
        dropHover: dropHover ?? this.dropHover,
        tagSegmentLanguages:
            tagSegmentLanguages ?? this.tagSegmentLanguages,
      );
}

class TranscriptionScreenNotifier
    extends Notifier<TranscriptionScreenState> {
  @override
  TranscriptionScreenState build() => const TranscriptionScreenState();

  void setSelectedFilePath(String? v) => state = state.copyWith(
      selectedFilePath: v, clearSelectedFilePath: v == null);
  void setSelectedFileBytes(Uint8List? v) => state = state.copyWith(
      selectedFileBytes: v, clearSelectedFileBytes: v == null);
  void setSelectedFileName(String? v) => state = state.copyWith(
      selectedFileName: v, clearSelectedFileName: v == null);
  void setShowAdvancedOptions(bool v) =>
      state = state.copyWith(showAdvancedOptions: v);
  void setEnableDiarization(bool v) =>
      state = state.copyWith(enableDiarization: v);

  /// null = "Auto". Both setters keep min <= max so the pair can never
  /// describe an impossible range on its way to the diarizer.
  void setMinSpeakers(int? v) {
    final max = state.maxSpeakers;
    state = state.copyWith(
      minSpeakers: v,
      clearMinSpeakers: v == null,
      maxSpeakers: (v != null && max != null && max < v) ? v : null,
    );
  }

  void setMaxSpeakers(int? v) {
    final min = state.minSpeakers;
    state = state.copyWith(
      maxSpeakers: v,
      clearMaxSpeakers: v == null,
      minSpeakers: (v != null && min != null && min > v) ? v : null,
    );
  }
  void setLanguage(String v) => state = state.copyWith(language: v);
  void setModelName(String v) => state = state.copyWith(modelName: v);
  void setEngineReady(bool v) => state = state.copyWith(engineReady: v);
  void setAvailableModels(List<ModelInfo> v) =>
      state = state.copyWith(availableModels: v);
  void setLoadingModels(bool v) =>
      state = state.copyWith(loadingModels: v);
  void setModelNameFilter(String v) =>
      state = state.copyWith(modelNameFilter: v);
  void setBackendFilter(String v) =>
      state = state.copyWith(backendFilter: v);
  void setTranscribePending(bool v) =>
      state = state.copyWith(transcribePending: v);
  void setLoadCancelled(bool v) =>
      state = state.copyWith(loadCancelled: v);
  void setDropHover(bool v) => state = state.copyWith(dropHover: v);
  void setTagSegmentLanguages(bool v) =>
      state = state.copyWith(tagSegmentLanguages: v);

  /// Bulk update for web file pick.
  void setWebFile({required Uint8List bytes, required String name}) {
    state = state.copyWith(
      selectedFileBytes: bytes,
      selectedFileName: name,
      clearSelectedFilePath: true,
    );
  }

  /// Bulk update for start-transcription.
  void startTranscription() {
    state = state.copyWith(
      transcribePending: true,
      loadCancelled: false,
    );
  }
}

final transcriptionScreenProvider = NotifierProvider<
    TranscriptionScreenNotifier, TranscriptionScreenState>(
  TranscriptionScreenNotifier.new,
);
