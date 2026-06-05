import 'dart:io';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../engines/transcription_engine.dart';
import '../main.dart' show modelServiceProvider;
import 'log_service.dart';
import 'model_service.dart';

/// Punctuation + truecasing restoration via CrispASR post-processors.
///
/// Two families of models:
///   1. **PuncModel** (FireRedPunc / fullstop-punc) — GGUF, restores
///      punctuation AND capitalization. Best for backends that emit
///      lowercased, unpunctuated text (wav2vec2, fastconformer-ctc).
///   2. **TruecaseModel** (truecaser-lstm-*.bin) — .bin, restores ONLY
///      capitalization. Best for backends that already emit punctuation
///      but lowercase everything (parakeet-ctc). Requires C-ABI ≥0.5.3
///      (`feat/truecase-abi` branch).
///
/// Lifecycle: models are loaded lazily and cached for the session.
class PuncService {
  /// Filenames the service recognises as a punctuation GGUF. Both
  /// FireRedPunc (ZH+EN) and fullstop-punc (EN/DE/FR/IT) load through
  /// the same `crispasr.PuncModel` ABI; pick by user preference.
  static const List<String> _knownFilenames = [
    // FireRedPunc — Chinese + English
    'fireredpunc-q8_0.gguf',
    'fireredpunc-q4_k.gguf',
    'fireredpunc-f16.gguf',
    // Fullstop-punc multilang — EN/DE/FR/IT
    'fullstop-punc-multilang-q8_0.gguf',
    'fullstop-punc-multilang-q4_k.gguf',
    'fullstop-punc-multilang-f16.gguf',
  ];

  /// Filenames recognised as PCS GGUF models. Loaded via PcsModel
  /// (C-ABI ≥0.5.3). PCS handles all three tasks (punct + truecase + SBD)
  /// in one pass — when available, it supersedes both PuncModel and
  /// TruecaseModel for supported languages (47 via XLM-R).
  static const List<String> _pcsFilenames = [
    'pcs-xlmr-base-q4_k.gguf',
    'pcs-xlmr-base-q8_0.gguf',
    'pcs-xlmr-base.gguf',
  ];

  /// Filenames recognised as truecaser models. Loaded via TruecaseModel
  /// (C-ABI ≥0.5.3). Preference order: LSTM > CRF > statistical.
  static const List<String> _truecaseFilenames = [
    'truecaser-lstm-de.bin',
    'truecaser-lstm-en.bin',
    'truecaser-lstm-es.bin',
    'truecaser-lstm-ru.bin',
    'truecaser-crf-de.bin',
    'truecaser-de.bin',
  ];

  /// Optional ModelService injection. When present we honour the
  /// custom-models-dir setting; when null we fall back to a temp-dir
  /// path so the not-found check fires cleanly in test fixtures.
  final ModelService? modelService;
  PuncService({this.modelService});

  crispasr.PuncModel? _model;
  String? _loadedPath;
  bool _searched = false;
  String? _cachedPath;

  /// User-preferred filename hint (e.g. `"fullstop"` to prefer fullstop-punc
  /// over fireredpunc when both are on disk). Honoured by [_findModel] as
  /// a substring match against the basename. Empty / null = first match.
  String? preferredFamily;

  /// Locate a downloaded punctuation GGUF. Both FireRedPunc and
  /// fullstop-punc are recognised; pick by [preferredFamily] when both
  /// are present. Returns null if neither is on disk.
  Future<String?> _findModel() async {
    if (_searched) return _cachedPath;
    _searched = true;
    try {
      await modelService?.initialize();
      final dirPath = modelService?.whisperCppDir() ??
          p.join(Directory.systemTemp.path, 'crisper_weaver_models',
              'whisper_cpp');
      final modelsDir = Directory(dirPath);
      if (!await modelsDir.exists()) return null;
      final entries = await modelsDir.list().toList();
      final matches = <File>[];
      for (final e in entries) {
        if (e is! File) continue;
        final base = p.basename(e.path);
        final lower = base.toLowerCase();
        if (_knownFilenames.contains(base) ||
            lower.startsWith('fireredpunc') ||
            lower.startsWith('fullstop-punc')) {
          matches.add(e);
        }
      }
      if (matches.isEmpty) return null;
      // Honour the user preference: if `preferredFamily` is set,
      // prefer the file whose basename contains that substring.
      final pref = preferredFamily?.toLowerCase();
      if (pref != null && pref.isNotEmpty) {
        for (final f in matches) {
          if (p.basename(f.path).toLowerCase().contains(pref)) {
            _cachedPath = f.path;
            Log.instance.d('punc', 'found punc model (preferred)',
                fields: {'path': f.path, 'pref': pref});
            return _cachedPath;
          }
        }
      }
      _cachedPath = matches.first.path;
      Log.instance
          .d('punc', 'found punc model', fields: {'path': matches.first.path});
      return _cachedPath;
    } catch (e, st) {
      Log.instance
          .w('punc', 'failed to search models dir', error: e, stack: st);
      return null;
    }
  }

  /// Reset the search cache so a new `preferredFamily` value is honoured
  /// on the next [restore] call.
  void invalidate() {
    _searched = false;
    _cachedPath = null;
  }

  Future<crispasr.PuncModel?> _ensureLoaded() async {
    final path = await _findModel();
    if (path == null) return null;
    if (_model != null && _loadedPath == path) return _model;
    // A different file was picked since the last call (rare — e.g. user
    // deleted the q8_0 and downloaded the q4_k). Drop the stale model.
    _model?.close();
    _model = null;
    try {
      _model = crispasr.PuncModel.open(path);
      _loadedPath = path;
      Log.instance
          .i('punc', 'loaded FireRedPunc', fields: {'path': p.basename(path)});
      return _model;
    } catch (e, st) {
      Log.instance.w('punc', 'PuncModel.open failed',
          error: e, stack: st, fields: {'path': p.basename(path)});
      return null;
    }
  }

  /// Apply punctuation restoration to every non-empty segment text.
  /// Returns the input list unchanged if no FireRedPunc GGUF is on disk
  /// or the model failed to load.
  Future<List<TranscriptionSegment>> restore(
      List<TranscriptionSegment> segments) async {
    if (segments.isEmpty) return segments;
    final model = await _ensureLoaded();
    if (model == null) {
      Log.instance.d('punc',
          'no FireRedPunc GGUF available — skipping punctuation post-step');
      return segments;
    }
    final out = <TranscriptionSegment>[];
    var changed = 0;
    for (final s in segments) {
      final src = s.text.trim();
      if (src.isEmpty) {
        out.add(s);
        continue;
      }
      String dst;
      try {
        dst = model.process(src);
      } catch (e, st) {
        Log.instance.w('punc', 'PuncModel.process threw', error: e, stack: st);
        out.add(s);
        continue;
      }
      if (dst.trim().isEmpty || dst == src) {
        out.add(s);
        continue;
      }
      changed++;
      out.add(TranscriptionSegment(
        text: dst,
        startTime: s.startTime,
        endTime: s.endTime,
        speaker: s.speaker,
        confidence: s.confidence,
        words: s.words,
        metadata: s.metadata,
      ));
    }
    Log.instance.i('punc', 'punctuation restored', fields: {
      'segments': segments.length,
      'changed': changed,
    });
    return out;
  }

  // ---- Truecaser (capitalization-only, C-ABI ≥0.5.3) ----

  crispasr.TruecaseModel? _truecaseModel;
  String? _truecaseLoadedPath;
  bool _truecaseSearched = false;
  String? _truecaseCachedPath;

  /// Preferred truecaser language (e.g. 'de', 'en'). Used to pick
  /// the right language-specific model when multiple are on disk.
  String? preferredTruecaseLang;

  /// Locate a downloaded truecaser .bin model.
  Future<String?> _findTruecaseModel() async {
    if (_truecaseSearched) return _truecaseCachedPath;
    _truecaseSearched = true;
    try {
      await modelService?.initialize();
      final dirPath = modelService?.whisperCppDir() ??
          p.join(Directory.systemTemp.path, 'crisper_weaver_models',
              'whisper_cpp');
      final modelsDir = Directory(dirPath);
      if (!await modelsDir.exists()) return null;
      final entries = await modelsDir.list().toList();
      final matches = <File>[];
      for (final e in entries) {
        if (e is! File) continue;
        final base = p.basename(e.path);
        if (_truecaseFilenames.contains(base) ||
            base.startsWith('truecaser-')) {
          matches.add(e);
        }
      }
      if (matches.isEmpty) return null;
      // Prefer language-matched LSTM model.
      final lang = preferredTruecaseLang?.toLowerCase();
      if (lang != null && lang.isNotEmpty) {
        for (final f in matches) {
          final base = p.basename(f.path).toLowerCase();
          if (base.contains('lstm') && base.contains(lang)) {
            _truecaseCachedPath = f.path;
            return _truecaseCachedPath;
          }
        }
        // Fall back to any model matching the language.
        for (final f in matches) {
          if (p.basename(f.path).toLowerCase().contains(lang)) {
            _truecaseCachedPath = f.path;
            return _truecaseCachedPath;
          }
        }
      }
      // Prefer LSTM over CRF over statistical.
      for (final f in matches) {
        if (p.basename(f.path).contains('lstm')) {
          _truecaseCachedPath = f.path;
          return _truecaseCachedPath;
        }
      }
      _truecaseCachedPath = matches.first.path;
      return _truecaseCachedPath;
    } catch (e, st) {
      Log.instance.w('punc', 'truecaser search failed', error: e, stack: st);
      return null;
    }
  }

  Future<crispasr.TruecaseModel?> _ensureTruecaseLoaded() async {
    final path = await _findTruecaseModel();
    if (path == null) return null;
    if (_truecaseModel != null && _truecaseLoadedPath == path) {
      return _truecaseModel;
    }
    _truecaseModel?.close();
    _truecaseModel = null;
    try {
      _truecaseModel = crispasr.TruecaseModel.open(path);
      _truecaseLoadedPath = path;
      Log.instance.i('punc', 'loaded truecaser',
          fields: {'path': p.basename(path)});
      return _truecaseModel;
    } catch (e, st) {
      Log.instance.w('punc', 'TruecaseModel.open failed',
          error: e, stack: st, fields: {'path': p.basename(path)});
      return null;
    }
  }

  /// Apply truecasing (capitalization only) to segment texts.
  /// No-ops when no truecaser model is on disk or the C-ABI lacks
  /// the `crispasr_truecase_*` symbols (pre-0.5.3 builds).
  Future<List<TranscriptionSegment>> restoreTruecase(
      List<TranscriptionSegment> segments) async {
    if (segments.isEmpty) return segments;
    final model = await _ensureTruecaseLoaded();
    if (model == null) return segments;
    final out = <TranscriptionSegment>[];
    var changed = 0;
    for (final s in segments) {
      final src = s.text.trim();
      if (src.isEmpty) {
        out.add(s);
        continue;
      }
      String dst;
      try {
        dst = model.process(src);
      } catch (e, st) {
        Log.instance.w('punc', 'TruecaseModel.process threw',
            error: e, stack: st);
        out.add(s);
        continue;
      }
      if (dst.trim().isEmpty || dst == src) {
        out.add(s);
        continue;
      }
      changed++;
      out.add(TranscriptionSegment(
        text: dst,
        startTime: s.startTime,
        endTime: s.endTime,
        speaker: s.speaker,
        confidence: s.confidence,
        words: s.words,
        metadata: s.metadata,
      ));
    }
    Log.instance.i('punc', 'truecasing restored', fields: {
      'segments': segments.length,
      'changed': changed,
    });
    return out;
  }

  // ---- PCS (all-in-one: punct + truecase + SBD, C-ABI ≥0.5.3) ----

  crispasr.PcsModel? _pcsModel;
  String? _pcsLoadedPath;
  bool _pcsSearched = false;
  String? _pcsCachedPath;

  /// Locate a downloaded PCS GGUF model.
  Future<String?> _findPcsModel() async {
    if (_pcsSearched) return _pcsCachedPath;
    _pcsSearched = true;
    try {
      await modelService?.initialize();
      final dirPath = modelService?.whisperCppDir() ??
          p.join(Directory.systemTemp.path, 'crisper_weaver_models',
              'whisper_cpp');
      final modelsDir = Directory(dirPath);
      if (!await modelsDir.exists()) return null;
      final entries = await modelsDir.list().toList();
      for (final e in entries) {
        if (e is! File) continue;
        final base = p.basename(e.path);
        if (_pcsFilenames.contains(base) || base.startsWith('pcs-')) {
          _pcsCachedPath = e.path;
          Log.instance.d('punc', 'found PCS model',
              fields: {'path': e.path});
          return _pcsCachedPath;
        }
      }
      return null;
    } catch (e, st) {
      Log.instance.w('punc', 'PCS model search failed', error: e, stack: st);
      return null;
    }
  }

  Future<crispasr.PcsModel?> _ensurePcsLoaded() async {
    final path = await _findPcsModel();
    if (path == null) return null;
    if (_pcsModel != null && _pcsLoadedPath == path) return _pcsModel;
    _pcsModel?.close();
    _pcsModel = null;
    try {
      _pcsModel = crispasr.PcsModel.open(path);
      _pcsLoadedPath = path;
      Log.instance.i('punc', 'loaded PCS model',
          fields: {'path': p.basename(path)});
      return _pcsModel;
    } catch (e, st) {
      Log.instance.w('punc', 'PcsModel.open failed',
          error: e, stack: st, fields: {'path': p.basename(path)});
      return null;
    }
  }

  /// Apply PCS (punctuation + truecasing + sentence boundaries) in one
  /// pass. Supersedes both [restore] (FireRedPunc) and [restoreTruecase]
  /// when a PCS model is on disk. No-ops otherwise.
  Future<List<TranscriptionSegment>> restorePcs(
      List<TranscriptionSegment> segments) async {
    if (segments.isEmpty) return segments;
    final model = await _ensurePcsLoaded();
    if (model == null) return segments;
    final out = <TranscriptionSegment>[];
    var changed = 0;
    for (final s in segments) {
      final src = s.text.trim();
      if (src.isEmpty) {
        out.add(s);
        continue;
      }
      String dst;
      try {
        dst = model.process(src);
      } catch (e, st) {
        Log.instance.w('punc', 'PcsModel.process threw', error: e, stack: st);
        out.add(s);
        continue;
      }
      if (dst.trim().isEmpty || dst == src) {
        out.add(s);
        continue;
      }
      changed++;
      out.add(TranscriptionSegment(
        text: dst,
        startTime: s.startTime,
        endTime: s.endTime,
        speaker: s.speaker,
        confidence: s.confidence,
        words: s.words,
        metadata: s.metadata,
      ));
    }
    Log.instance.i('punc', 'PCS restored', fields: {
      'segments': segments.length,
      'changed': changed,
    });
    return out;
  }

  /// Drop the loaded model. Safe to call multiple times.
  void dispose() {
    _model?.close();
    _model = null;
    _loadedPath = null;
    _searched = false;
    _cachedPath = null;
    _truecaseModel?.close();
    _truecaseModel = null;
    _truecaseLoadedPath = null;
    _truecaseSearched = false;
    _truecaseCachedPath = null;
    _pcsModel?.close();
    _pcsModel = null;
    _pcsLoadedPath = null;
    _pcsSearched = false;
    _pcsCachedPath = null;
  }
}

final puncServiceProvider = Provider<PuncService>((ref) {
  final svc = PuncService(modelService: ref.watch(modelServiceProvider));
  ref.onDispose(svc.dispose);
  return svc;
});
