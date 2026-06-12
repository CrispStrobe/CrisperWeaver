// PresetService — PLAN §5.1.7.
//
// Save the current (backend, modelId, language, AdvancedOptions)
// tuple as a named preset. Re-apply restores all four atomically
// so the user can flip between "Podcast prep", "Voice memo",
// "Multilingual interview" workflows without redoing 27 toggles.
//
// Storage: a single JSON-encoded list keyed `transcription_presets`
// in SharedPreferences. Cheap to read on app start, no file-system
// permission story, naturally migrates across platforms.
//
// Migration: each preset record stores a `schemaVersion` int.
// fromJson tolerates unknown extra keys (forward-compat when a
// future field gets added) and missing keys (backward-compat when
// loading an older preset on a newer build — fields fall through
// to AdvancedOptions defaults).
//
// Pure-Dart, no FFI, no native channels. Cross-platform identical.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../native/crispasr_import.dart' as crispasr;

import '../services/log_service.dart';
import '../services/vad_service.dart';
import '../widgets/advanced_options_widget.dart';

/// One row in the user's preset list. Immutable; copyWith for
/// edits. Identity is the [id] (uuid-like string generated on
/// save). The display [name] is editable.
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.backend,
    required this.modelId,
    required this.language,
    required this.options,
    this.schemaVersion = 1,
  });

  /// Stable identifier — once assigned, never changes. Used so
  /// rename / edit-in-place updates the right row.
  final String id;

  /// Display name shown in the preset picker. Mutable via
  /// copyWith; if empty / collides, the UI surfaces a validation
  /// error before persisting.
  final String name;

  final DateTime createdAt;

  /// ASR backend id (e.g. "whisper", "voxtral", "moonshine").
  /// Empty allowed for "preset only changes options, leaves
  /// engine alone".
  final String backend;

  /// Model id (e.g. "tiny.en", "base.q5_0", "voxtral-mini-3b").
  /// Empty allowed (same rationale as backend).
  final String modelId;

  /// Source language code or "auto". Default "auto".
  final String language;

  final AdvancedOptions options;

  /// Version of the JSON schema this preset was saved under.
  /// fromJson updates the field to the current SCHEMA when
  /// loading an older row, so subsequent saves write the
  /// current shape.
  final int schemaVersion;

  /// The version writeers stamp on freshly-saved presets. Bump
  /// this when the persisted shape changes; fromJson then
  /// branches on it for migration.
  static const int currentSchemaVersion = 1;

  Preset copyWith({
    String? name,
    String? backend,
    String? modelId,
    String? language,
    AdvancedOptions? options,
  }) =>
      Preset(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        backend: backend ?? this.backend,
        modelId: modelId ?? this.modelId,
        language: language ?? this.language,
        options: options ?? this.options,
        schemaVersion: schemaVersion,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'backend': backend,
        'modelId': modelId,
        'language': language,
        'options': _advancedOptionsToJson(options),
      };

  static Preset fromJson(Map<String, dynamic> json) {
    return Preset(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      backend: (json['backend'] as String?) ?? '',
      modelId: (json['modelId'] as String?) ?? '',
      language: (json['language'] as String?) ?? 'auto',
      options: _advancedOptionsFromJson(
          (json['options'] as Map?)?.cast<String, dynamic>() ?? const {}),
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
    );
  }
}

/// AdvancedOptions ↔ JSON. Exported as top-level helpers so the
/// unit tests can round-trip without going through Preset.
Map<String, dynamic> _advancedOptionsToJson(AdvancedOptions o) =>
    <String, dynamic>{
      'translate': o.translate,
      'beamSearch': o.beamSearch,
      'initialPrompt': o.initialPrompt,
      'vad': o.vad,
      'restorePunctuation': o.restorePunctuation,
      'targetLanguage': o.targetLanguage,
      'askPrompt': o.askPrompt,
      'temperature': o.temperature,
      'sourceLanguage': o.sourceLanguage,
      'bestOf': o.bestOf,
      'vadBackend': o.vadBackend.name,
      'vadThreshold': o.vadThreshold,
      'vadMinSpeechMs': o.vadMinSpeechMs,
      'vadMinSilenceMs': o.vadMinSilenceMs,
      'vadSpeechPadMs': o.vadSpeechPadMs,
      'diarizeMethod': o.diarizeMethod.name,
      'enableSpeakerRecognition': o.enableSpeakerRecognition,
      'lidMethod': o.lidMethod.name,
      'tdrz': o.tdrz,
      'tokenTimestamps': o.tokenTimestamps,
      'puncFamily': o.puncFamily,
      'lidUseGpu': o.lidUseGpu,
      'lidFlashAttn': o.lidFlashAttn,
      'nThreads': o.nThreads,
      'asrUseGpu': o.asrUseGpu,
      'asrFlashAttn': o.asrFlashAttn,
      'asrNGpuLayers': o.asrNGpuLayers,
      'vocabulary': o.vocabulary,
      'maxLen': o.maxLen,
      'splitOnWord': o.splitOnWord,
      'splitOnPunct': o.splitOnPunct,
      'grammarText': o.grammarText,
      'grammarRootRule': o.grammarRootRule,
      'grammarPenalty': o.grammarPenalty,
      'entropyThold': o.entropyThold,
      'logprobThold': o.logprobThold,
      'noSpeechThold': o.noSpeechThold,
      'temperatureInc': o.temperatureInc,
      'suppressNonSpeechTokens': o.suppressNonSpeechTokens,
      'suppressTokensRegex': o.suppressTokensRegex,
      'carryInitialPrompt': o.carryInitialPrompt,
      'enhanceAudio': o.enhanceAudio,
      'transcribeWindowStartSec': o.transcribeWindowStartSec,
      'transcribeWindowDurationSec': o.transcribeWindowDurationSec,
      'altN': o.altN,
      'hotwords': o.hotwords,
    };

AdvancedOptions _advancedOptionsFromJson(Map<String, dynamic> j) {
  // Defensive enum parse — unknown values fall through to the
  // ctor default so an older app loading a newer preset doesn't
  // crash; it just silently downshifts the missing-field choice.
  T enumFromName<T extends Enum>(
      List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  return AdvancedOptions(
    translate: (j['translate'] as bool?) ?? false,
    beamSearch: (j['beamSearch'] as bool?) ?? false,
    initialPrompt: (j['initialPrompt'] as String?) ?? '',
    vad: (j['vad'] as bool?) ?? false,
    restorePunctuation: (j['restorePunctuation'] as bool?) ?? false,
    targetLanguage: (j['targetLanguage'] as String?) ?? '',
    askPrompt: (j['askPrompt'] as String?) ?? '',
    temperature: ((j['temperature'] as num?) ?? 0.0).toDouble(),
    sourceLanguage: (j['sourceLanguage'] as String?) ?? '',
    bestOf: (j['bestOf'] as int?) ?? 1,
    vadBackend: enumFromName(
        VadBackend.values, j['vadBackend'] as String?, VadBackend.silero),
    vadThreshold: ((j['vadThreshold'] as num?) ?? 0.5).toDouble(),
    vadMinSpeechMs: (j['vadMinSpeechMs'] as int?) ?? 250,
    vadMinSilenceMs: (j['vadMinSilenceMs'] as int?) ?? 100,
    vadSpeechPadMs: (j['vadSpeechPadMs'] as int?) ?? 30,
    diarizeMethod: enumFromName(crispasr.DiarizeMethod.values,
        j['diarizeMethod'] as String?, crispasr.DiarizeMethod.vadTurns),
    enableSpeakerRecognition:
        (j['enableSpeakerRecognition'] as bool?) ?? false,
    lidMethod: enumFromName(crispasr.LidMethod.values,
        j['lidMethod'] as String?, crispasr.LidMethod.whisper),
    tdrz: (j['tdrz'] as bool?) ?? false,
    tokenTimestamps: (j['tokenTimestamps'] as bool?) ?? false,
    puncFamily: (j['puncFamily'] as String?) ?? 'firered',
    lidUseGpu: (j['lidUseGpu'] as bool?) ?? false,
    lidFlashAttn: (j['lidFlashAttn'] as bool?) ?? true,
    nThreads: (j['nThreads'] as int?) ?? 4,
    asrUseGpu: (j['asrUseGpu'] as bool?) ?? true,
    asrFlashAttn: (j['asrFlashAttn'] as bool?) ?? true,
    asrNGpuLayers: (j['asrNGpuLayers'] as int?) ?? -1,
    vocabulary: ((j['vocabulary'] as List?)?.cast<String>()) ?? const [],
    maxLen: (j['maxLen'] as int?) ?? 0,
    splitOnWord: (j['splitOnWord'] as bool?) ?? false,
    splitOnPunct: (j['splitOnPunct'] as bool?) ?? false,
    grammarText: (j['grammarText'] as String?) ?? '',
    grammarRootRule: (j['grammarRootRule'] as String?) ?? 'root',
    grammarPenalty:
        ((j['grammarPenalty'] as num?) ?? 100.0).toDouble(),
    entropyThold: ((j['entropyThold'] as num?) ?? 2.4).toDouble(),
    logprobThold: ((j['logprobThold'] as num?) ?? -1.0).toDouble(),
    noSpeechThold: ((j['noSpeechThold'] as num?) ?? 0.6).toDouble(),
    temperatureInc:
        ((j['temperatureInc'] as num?) ?? 0.2).toDouble(),
    suppressNonSpeechTokens:
        (j['suppressNonSpeechTokens'] as bool?) ?? false,
    suppressTokensRegex:
        (j['suppressTokensRegex'] as String?) ?? '',
    carryInitialPrompt:
        (j['carryInitialPrompt'] as bool?) ?? false,
    enhanceAudio: (j['enhanceAudio'] as bool?) ?? false,
    transcribeWindowStartSec:
        ((j['transcribeWindowStartSec'] as num?) ?? 0.0).toDouble(),
    transcribeWindowDurationSec:
        ((j['transcribeWindowDurationSec'] as num?) ?? 0.0).toDouble(),
    altN: (j['altN'] as int?) ?? 0,
    hotwords: (j['hotwords'] as String?) ?? '',
  );
}

/// Test seam — re-export the helpers under stable names so unit
/// tests can round-trip an AdvancedOptions without instantiating
/// a Preset.
@visibleForTesting
Map<String, dynamic> advancedOptionsToJson(AdvancedOptions o) =>
    _advancedOptionsToJson(o);

@visibleForTesting
AdvancedOptions advancedOptionsFromJson(Map<String, dynamic> j) =>
    _advancedOptionsFromJson(j);

class PresetService {
  PresetService(this._prefs);

  static const _prefsKey = 'transcription_presets';
  static const _idSequenceKey = 'transcription_presets_seq';

  final SharedPreferences _prefs;

  /// Returns the current list, oldest-first by createdAt. Cheap
  /// — single SharedPreferences read + JSON parse on each call.
  /// Callers that need to refresh after a mutation should re-
  /// invoke; there's no internal cache so the source of truth
  /// stays the prefs blob.
  List<Preset> all() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <Preset>[];
      for (final entry in decoded) {
        if (entry is Map) {
          out.add(Preset.fromJson(entry.cast<String, dynamic>()));
        }
      }
      out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return out;
    } catch (e, st) {
      Log.instance.e('presets', 'failed to load list', error: e, stack: st);
      return const [];
    }
  }

  /// Save a brand-new preset. Returns the persisted row (with a
  /// freshly-allocated id). Caller is expected to provide a
  /// non-empty unique name; collisions get a "(2)" suffix etc.
  Future<Preset> add({
    required String name,
    required String backend,
    required String modelId,
    required String language,
    required AdvancedOptions options,
  }) async {
    final list = all();
    final id = _nextId();
    final unique = _uniqueName(name, list);
    final row = Preset(
      id: id,
      name: unique,
      createdAt: DateTime.now(),
      backend: backend,
      modelId: modelId,
      language: language,
      options: options,
    );
    final next = [...list, row];
    await _write(next);
    Log.instance.i('presets', 'added preset',
        fields: {'id': id, 'name': unique, 'backend': backend});
    return row;
  }

  /// Overwrite an existing row by id. Falls back to add() when
  /// the id is unknown (defensive against a stale UI state).
  Future<Preset> update(Preset updated) async {
    final list = all();
    final idx = list.indexWhere((p) => p.id == updated.id);
    if (idx < 0) {
      return add(
        name: updated.name,
        backend: updated.backend,
        modelId: updated.modelId,
        language: updated.language,
        options: updated.options,
      );
    }
    final next = [...list];
    next[idx] = updated;
    await _write(next);
    Log.instance.i('presets', 'updated preset',
        fields: {'id': updated.id, 'name': updated.name});
    return updated;
  }

  Future<void> remove(String id) async {
    final list = all();
    final next = list.where((p) => p.id != id).toList();
    if (next.length == list.length) return; // unknown id, no-op
    await _write(next);
    Log.instance.i('presets', 'removed preset', fields: {'id': id});
  }

  Future<void> clear() async {
    await _prefs.remove(_prefsKey);
    Log.instance.i('presets', 'cleared all presets');
  }

  String _nextId() {
    final seq = (_prefs.getInt(_idSequenceKey) ?? 0) + 1;
    _prefs.setInt(_idSequenceKey, seq);
    // "p-<seq>-<random>" so manual file editing is debuggable
    // without breaking uniqueness across two saves on the same
    // wall-clock millisecond.
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return 'p-$seq-$ts';
  }

  String _uniqueName(String requested, List<Preset> existing) {
    final base = requested.trim();
    if (base.isEmpty) return 'Preset';
    final taken = existing.map((p) => p.name).toSet();
    if (!taken.contains(base)) return base;
    for (var n = 2; n < 1000; n++) {
      final candidate = '$base ($n)';
      if (!taken.contains(candidate)) return candidate;
    }
    // Pathological fallback — caller has 1000 presets named
    // identically, which the UI should have prevented earlier.
    return '$base (${DateTime.now().millisecondsSinceEpoch})';
  }

  Future<void> _write(List<Preset> list) async {
    final raw = jsonEncode(list.map((p) => p.toJson()).toList());
    await _prefs.setString(_prefsKey, raw);
  }
}

/// Riverpod provider. Initialized in main() once SharedPreferences
/// is available, same pattern as settingsServiceProvider.
final presetServiceProvider = Provider<PresetService>((ref) {
  throw UnimplementedError('PresetService not initialized');
});
