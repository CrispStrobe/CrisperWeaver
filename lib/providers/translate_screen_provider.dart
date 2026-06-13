// §8.2 — Riverpod provider for TranslateScreen local UI state.
// Replaces the 14 setState calls with a single immutable state class
// so only affected subtrees rebuild on mutation.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/model_service.dart';

/// Immutable state for the TranslateScreen.
class TranslateScreenState {
  final List<ModelInfo> models;
  final bool loading;
  final bool busy;
  final String? selectedModel;
  final String srcLang;
  final String tgtLang;
  final int maxTokens;

  const TranslateScreenState({
    this.models = const [],
    this.loading = true,
    this.busy = false,
    this.selectedModel,
    this.srcLang = 'en',
    this.tgtLang = 'de',
    this.maxTokens = 200,
  });

  TranslateScreenState copyWith({
    List<ModelInfo>? models,
    bool? loading,
    bool? busy,
    String? selectedModel,
    String? srcLang,
    String? tgtLang,
    int? maxTokens,
    // Sentinel to allow explicitly setting selectedModel to null.
    bool clearSelectedModel = false,
  }) =>
      TranslateScreenState(
        models: models ?? this.models,
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
        selectedModel:
            clearSelectedModel ? null : (selectedModel ?? this.selectedModel),
        srcLang: srcLang ?? this.srcLang,
        tgtLang: tgtLang ?? this.tgtLang,
        maxTokens: maxTokens ?? this.maxTokens,
      );
}

class TranslateScreenNotifier extends Notifier<TranslateScreenState> {
  @override
  TranslateScreenState build() => const TranslateScreenState();

  void setModels(List<ModelInfo> models) =>
      state = state.copyWith(models: models);
  void setLoading(bool v) => state = state.copyWith(loading: v);
  void setBusy(bool v) => state = state.copyWith(busy: v);
  void setSelectedModel(String? v) =>
      state = state.copyWith(selectedModel: v);
  void setSrcLang(String v) => state = state.copyWith(srcLang: v);
  void setTgtLang(String v) => state = state.copyWith(tgtLang: v);
  void setMaxTokens(int v) => state = state.copyWith(maxTokens: v);

  void swapLanguages() {
    state = state.copyWith(
      srcLang: state.tgtLang,
      tgtLang: state.srcLang,
    );
  }
}

final translateScreenProvider =
    NotifierProvider<TranslateScreenNotifier, TranslateScreenState>(
  TranslateScreenNotifier.new,
);
