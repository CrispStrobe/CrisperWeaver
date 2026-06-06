import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../main.dart' show modelServiceProvider;
import 'log_service.dart';
import 'model_service.dart';

/// Persistent on-device speaker identification.
///
/// Wraps the CrispASR `CrispasrTitaNet` (192-d L2-normalised speaker
/// embedding extractor) + `CrispasrSpeakerDB` (file-per-speaker on-disk
/// profile DB) bindings to resolve diarisation cluster labels to
/// enrolled names. The DB lives under
/// `<app-docs>/speakers/`; no embeddings ever leave the device.
class SpeakerIdService {
  final ModelService modelService;

  SpeakerIdService(this.modelService);

  /// Cached basename → on-disk path resolution. Cleared by [invalidate]
  /// after a fresh download.
  String? _cachedModelPath;

  /// Lazy-opened TitaNet handle. Loading the GGUF takes ~1 s, so we
  /// hold it for the process lifetime.
  crispasr.CrispasrTitaNet? _titanet;

  /// Lazy-opened DB handle. The DB also owns the in-memory profile
  /// cache, so reusing one handle keeps `match` fast.
  crispasr.CrispasrSpeakerDB? _db;

  /// Serialises [_ensureOpen] so two parallel diarisation passes can't
  /// double-init the C side.
  Completer<void>? _openInFlight;

  /// 192-d embedding length asserted by upstream — we surface it so
  /// callers can size buffers without hitting the binding.
  static const int embeddingDim = 192;

  /// Cosine-similarity threshold below which a match is treated as
  /// "no enrolled speaker". 0.7 matches upstream's default and the
  /// SpeechBrain-style speaker-verification literature.
  static const double defaultThreshold = 0.7;

  /// True when the TitaNet GGUF is on disk AND the loaded CrispASR
  /// dylib exports the TitaNet C symbols. Quick check — does NOT open
  /// the model. Use this to gate the diarisation post-process.
  Future<bool> get isAvailable async {
    final path = await _findTitanetModel();
    if (path == null) return false;
    final lib = DynamicLibrary.open(crispasr.CrispASR.defaultLibName());
    return lib.providesSymbol('crispasr_titanet_init') &&
        lib.providesSymbol('crispasr_speaker_db_load');
  }

  /// Match [pcm16k] (mono 16 kHz float32) against the enrolled DB.
  /// Returns `(name, score)`; `name` is null when no profile meets
  /// [threshold]. Throws when the TitaNet model isn't downloaded or
  /// the dylib lacks the TitaNet symbols — callers should gate on
  /// [isAvailable] first.
  Future<(String?, double)> matchSegment(
    Float32List pcm16k, {
    double threshold = defaultThreshold,
  }) async {
    await _ensureOpen();
    final embedding = _titanet!.embed(pcm16k);
    return _db!.match(embedding, threshold: threshold);
  }

  /// Enrol a speaker with the supplied PCM sample. Returns true on
  /// success. Upstream `CrispasrSpeakerDB.enroll` overwrites the
  /// on-disk profile when a speaker with the same name already
  /// exists, so callers don't need to delete-then-enrol.
  Future<bool> enroll(String name, Float32List pcm16k) async {
    if (name.trim().isEmpty) return false;
    await _ensureOpen();
    final embedding = _titanet!.embed(pcm16k);
    final ok = _db!.enroll(name.trim(), embedding);
    if (!ok) {
      Log.instance.w('speakers', 'enroll failed', fields: {'name': name});
    } else {
      Log.instance
          .i('speakers', 'enrolled speaker', fields: {'name': name.trim()});
    }
    return ok;
  }

  /// Names currently in the on-disk DB, sorted alphabetically. Reads
  /// the speakers directory directly rather than via the binding so
  /// the UI can list profiles without opening the TitaNet model.
  Future<List<String>> listSpeakers() async {
    final dir = await _ensureDbDir();
    final names = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final base = p.basenameWithoutExtension(entity.path);
      if (base.isEmpty) continue;
      names.add(base);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// Remove an enrolled speaker. Upstream's `CrispasrSpeakerDB` owns
  /// the on-disk format (one file per speaker named `<name>.spk` in
  /// the speakers dir). Deleting the file is the documented teardown
  /// path. Returns true when the file existed and was removed.
  Future<bool> deleteSpeaker(String name) async {
    final dir = await _ensureDbDir();
    final candidates = await dir
        .list()
        .where((e) =>
            e is File &&
            p.basenameWithoutExtension(e.path).toLowerCase() ==
                name.toLowerCase())
        .toList();
    if (candidates.isEmpty) return false;
    for (final entity in candidates) {
      try {
        await (entity as File).delete();
      } catch (e, st) {
        Log.instance.w('speakers',
            'failed to delete speaker file ${entity.path}',
            error: e, stack: st);
        return false;
      }
    }
    // Also remove the companion consent record (GDPR Art. 17 erasure).
    final consentFile = File(p.join(dir.path, '$name.consent.json'));
    if (await consentFile.exists()) {
      try {
        await consentFile.delete();
      } catch (_) {}
    }
    // Force the DB to re-scan next time it's opened — it caches profiles
    // on load.
    _closeHandles();
    Log.instance.i('speakers', 'deleted speaker', fields: {'name': name});
    return true;
  }

  /// Save a biometric-consent record for [name]. Called after the user
  /// explicitly consents to voice-embedding storage (GDPR Art. 9(2)(a)).
  Future<void> saveConsent(String name) async {
    final dir = await _ensureDbDir();
    final file = File(p.join(dir.path, '${name.trim()}.consent.json'));
    await file.writeAsString(jsonEncode({
      'speaker': name.trim(),
      'consentedAt': DateTime.now().toUtc().toIso8601String(),
      'purpose': 'Speaker identification via TitaNet voice embeddings',
      'lawfulBasis': 'GDPR Art. 9(2)(a) — explicit consent',
      'storageLocation': 'on-device only',
    }));
  }

  /// Export all stored data for [name] (GDPR Art. 20 data portability).
  /// Returns null when the speaker doesn't exist.
  Future<Map<String, dynamic>?> exportSpeakerData(String name) async {
    final dir = await _ensureDbDir();
    final spkFile = await dir
        .list()
        .where((e) =>
            e is File &&
            p.basenameWithoutExtension(e.path).toLowerCase() ==
                name.toLowerCase() &&
            p.extension(e.path) == '.spk')
        .cast<File>()
        .firstOrNull;
    if (spkFile == null) return null;

    final data = <String, dynamic>{
      'speaker': name,
      'embeddingDimension': embeddingDim,
      'embeddingFileBytes': (await spkFile.stat()).size,
    };

    final consentFile = File(p.join(dir.path, '$name.consent.json'));
    if (await consentFile.exists()) {
      try {
        data['consent'] = jsonDecode(await consentFile.readAsString());
      } catch (_) {}
    }
    return data;
  }

  /// Force the next call to re-resolve the GGUF path. Call after a
  /// fresh download or when the user removes the TitaNet model.
  void invalidate() {
    _cachedModelPath = null;
    _closeHandles();
  }

  /// Close the TitaNet + DB handles. Idempotent. Call on app exit
  /// or when the user opens Settings → Storage and clears models.
  void dispose() {
    _closeHandles();
  }

  void _closeHandles() {
    try {
      _titanet?.close();
    } catch (_) {}
    try {
      _db?.close();
    } catch (_) {}
    _titanet = null;
    _db = null;
  }

  /// Open the TitaNet model + DB handles. Idempotent + serialised so
  /// two concurrent matchers don't race on first open.
  Future<void> _ensureOpen() async {
    if (_titanet != null && _db != null) return;
    if (_openInFlight != null) {
      await _openInFlight!.future;
      return;
    }
    final completer = Completer<void>();
    _openInFlight = completer;
    try {
      final modelPath = await _findTitanetModel();
      if (modelPath == null) {
        throw StateError(
            'TitaNet GGUF not downloaded — install titanet-large-f16 '
            'from Model Management before enrolling speakers');
      }
      final lib = DynamicLibrary.open(crispasr.CrispASR.defaultLibName());
      if (!lib.providesSymbol('crispasr_titanet_init')) {
        throw StateError(
            'Loaded CrispASR dylib lacks TitaNet support — rebuild against '
            'the upstream CrispASR pulled in by this project.');
      }
      _titanet = crispasr.CrispasrTitaNet(lib, modelPath);
      final dir = await _ensureDbDir();
      _db = crispasr.CrispasrSpeakerDB(lib, dir.path);
      Log.instance.i('speakers', 'opened TitaNet + SpeakerDB', fields: {
        'model': p.basename(modelPath),
        'dbDir': dir.path,
        'enrolled': _db!.count,
      });
      completer.complete();
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _openInFlight = null;
    }
  }

  /// Find the TitaNet GGUF the user downloaded. Matches both the
  /// canonical `titanet-large*` filename (what the registry entry
  /// uses) and any TitaNet-shaped GGUF a power user dropped into
  /// the models dir manually.
  Future<String?> _findTitanetModel() async {
    final cached = _cachedModelPath;
    if (cached != null && await File(cached).exists()) return cached;
    try {
      final models = await modelService.getWhisperCppModels();
      for (final m in models) {
        if (!m.isDownloaded || m.localPath == null) continue;
        final base = p.basename(m.localPath!).toLowerCase();
        if (base.startsWith('titanet')) {
          _cachedModelPath = m.localPath;
          return _cachedModelPath;
        }
      }
      return null;
    } catch (e, st) {
      Log.instance.w('speakers', 'failed to enumerate models for TitaNet',
          error: e, stack: st);
      return null;
    }
  }

  Future<Directory> _ensureDbDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'speakers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

final speakerIdServiceProvider = Provider<SpeakerIdService>(
  (ref) => SpeakerIdService(ref.watch(modelServiceProvider)),
);
