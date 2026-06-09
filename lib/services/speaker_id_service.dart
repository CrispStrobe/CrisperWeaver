import 'dart:async';
import 'dart:convert';
import '../native/ffi_import.dart';
import 'dart:io';
import 'dart:typed_data';

import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../main.dart' show modelServiceProvider;
import 'log_service.dart';
import 'model_service.dart';

/// Persistent on-device speaker identification.
///
/// Uses CrispASR's pluggable `CrispasrSpeakerEmbedder` (auto-selects
/// the best available embedder: TitaNet 192-d > ECAPA-TDNN > IndexTTS)
/// + `CrispasrSpeakerDB` (file-per-speaker on-disk profile DB) to
/// resolve diarisation cluster labels to enrolled names. The DB lives
/// under `<app-docs>/speakers/`; no embeddings ever leave the device.
class SpeakerIdService {
  final ModelService modelService;

  SpeakerIdService(this.modelService);

  /// Cached basename → on-disk path resolution. Cleared by [invalidate]
  /// after a fresh download.
  String? _cachedModelPath;

  /// Lazy-opened pluggable embedder handle. Selects the best available
  /// model on the system (TitaNet > ECAPA > IndexTTS). Loading takes
  /// ~1 s so we hold it for the process lifetime.
  crispasr.CrispasrSpeakerEmbedder? _embedder;

  /// Lazy-opened DB handle. The DB also owns the in-memory profile
  /// cache, so reusing one handle keeps `match` fast.
  crispasr.CrispasrSpeakerDB? _db;

  /// Serialises [_ensureOpen] so two parallel diarisation passes can't
  /// double-init the C side.
  Completer<void>? _openInFlight;

  /// Embedding dimension from the active embedder. Populated after
  /// [_ensureOpen]; defaults to 192 (TitaNet) before open.
  int get embeddingDim => _embedder?.dim ?? 192;

  /// Cosine-similarity threshold below which a match is treated as
  /// "no enrolled speaker". 0.7 matches upstream's default and the
  /// SpeechBrain-style speaker-verification literature.
  static const double defaultThreshold = 0.7;

  /// True when at least one speaker-embedder GGUF is on disk AND
  /// the loaded CrispASR dylib exports the embedder C symbols.
  /// Quick check — does NOT open the model. Use this to gate the
  /// diarisation post-process.
  Future<bool> get isAvailable async {
    final path = await _findEmbedderModel();
    if (path == null) return false;
    final lib = DynamicLibrary.open(crispasr.CrispASR.defaultLibName());
    return lib.providesSymbol('crispasr_speaker_embedder_make_abi') &&
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
    final embedding = _embedder!.embed(pcm16k);
    if (embedding == null) return (null, 0.0);
    return _db!.match(embedding, threshold: threshold);
  }

  /// Enrol a speaker with the supplied PCM sample. Returns true on
  /// success. Upstream `CrispasrSpeakerDB.enroll` overwrites the
  /// on-disk profile when a speaker with the same name already
  /// exists, so callers don't need to delete-then-enrol.
  Future<bool> enroll(String name, Float32List pcm16k) async {
    if (name.trim().isEmpty) return false;
    await _ensureOpen();
    final embedding = _embedder!.embed(pcm16k);
    if (embedding == null) {
      Log.instance.w('speakers', 'embed returned null',
          fields: {'name': name});
      return false;
    }
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
    final spkFiles = await dir
        .list()
        .where((e) =>
            e is File &&
            p.basenameWithoutExtension(e.path).toLowerCase() ==
                name.toLowerCase() &&
            p.extension(e.path) == '.spk')
        .cast<File>()
        .toList();
    if (spkFiles.isEmpty) return null;
    final spkFile = spkFiles.first;

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

  /// Expose the underlying embedder handle for callers that need
  /// raw embeddings (e.g. agglomerative re-clustering in
  /// DiarizationService). Returns null before [_ensureOpen].
  crispasr.CrispasrSpeakerEmbedder? get embedder => _embedder;

  /// Open the embedder without matching — for callers that need
  /// the handle for embedding only (no DB match).
  Future<void> ensureOpenForEmbedding() => _ensureOpen();

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
      _embedder?.close();
    } catch (_) {}
    try {
      _db?.close();
    } catch (_) {}
    _embedder = null;
    _db = null;
  }

  /// Open the speaker embedder + DB handles. Idempotent + serialised
  /// so two concurrent matchers don't race on first open.
  ///
  /// Uses `CrispasrSpeakerEmbedder` with `"auto"` model spec, which
  /// auto-selects the best available embedder from the models on disk
  /// (TitaNet > ECAPA-TDNN > IndexTTS).
  Future<void> _ensureOpen() async {
    if (_embedder != null && _db != null) return;
    if (_openInFlight != null) {
      await _openInFlight!.future;
      return;
    }
    final completer = Completer<void>();
    _openInFlight = completer;
    try {
      final modelPath = await _findEmbedderModel();
      if (modelPath == null) {
        throw StateError(
            'No speaker-embedder GGUF downloaded — install titanet-large-f16 '
            '(or ecapa-tdnn / indextts embedder) '
            'from Model Management before enrolling speakers');
      }
      final lib = DynamicLibrary.open(crispasr.CrispASR.defaultLibName());
      if (!lib.providesSymbol('crispasr_speaker_embedder_make_abi')) {
        throw StateError(
            'Loaded CrispASR dylib lacks speaker-embedder support — rebuild '
            'against the upstream CrispASR pulled in by this project.');
      }
      final cacheDir = (await _ensureDbDir()).path;
      _embedder =
          crispasr.CrispasrSpeakerEmbedder(lib, 'auto', cacheDir: cacheDir);
      final dir = await _ensureDbDir();
      _db = crispasr.CrispasrSpeakerDB(lib, dir.path);
      Log.instance.i('speakers', 'opened SpeakerEmbedder + SpeakerDB',
          fields: {
            'embedder': _embedder!.name,
            'dim': _embedder!.dim,
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

  /// Find a speaker-embedder GGUF on disk. Checks for TitaNet,
  /// ECAPA-TDNN, and IndexTTS embedder models in priority order.
  /// Returns the first match or null.
  Future<String?> _findEmbedderModel() async {
    final cached = _cachedModelPath;
    if (cached != null && await File(cached).exists()) return cached;
    try {
      final models = await modelService.getWhisperCppModels();
      // Priority order: titanet > ecapa > indextts
      const prefixes = ['titanet', 'ecapa-tdnn-spk', 'indextts-spk'];
      for (final prefix in prefixes) {
        for (final m in models) {
          if (!m.isDownloaded || m.localPath == null) continue;
          final base = p.basename(m.localPath!).toLowerCase();
          if (base.startsWith(prefix)) {
            _cachedModelPath = m.localPath;
            return _cachedModelPath;
          }
        }
      }
      return null;
    } catch (e, st) {
      Log.instance.w('speakers',
          'failed to enumerate models for speaker embedder',
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
