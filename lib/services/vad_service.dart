import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../main.dart' show modelServiceProvider;
import 'log_service.dart';
import 'model_service.dart';

/// Which VAD GGUF the user has selected. Silero is bundled as a Flutter
/// asset (no download needed); the other three live in Model Management
/// and the picker falls back to silero if the chosen GGUF isn't on disk.
enum VadBackend {
  /// Bundled Silero v6.2.0 — default, always available, ~885 KB.
  silero,

  /// FireRedVAD — best F1 (97.57%), ~3 MB. Recommended over silero
  /// when downloaded.
  firered,

  /// MarbleNet — small (~500 KB), strict EN/DE/FR/ES/RU/ZH.
  marblenet,

  /// Whisper-VAD-EncDec — experimental, English-only, ~22 MB.
  whisperEncDec,
}

/// Locates the on-disk VAD GGUF for the requested [VadBackend]. Silero
/// is bundled as a Flutter asset and extracted to the app docs dir on
/// first use; the others live in the model catalog and the user must
/// download them through Model Management.
class VadService {
  static const String _sileroAssetPath = 'assets/vad/silero-v6.2.0-ggml.bin';

  /// Optional ModelService — used to resolve the non-silero VAD GGUFs
  /// from the user's models dir. Null in tests / fixtures (only silero
  /// will be reachable in that case).
  final ModelService? modelService;
  VadService({this.modelService});

  String? _sileroPath;

  /// Path to the Silero VAD model, extracting the bundled asset on the
  /// first call. Returns null on extraction failure.
  Future<String?> _ensureSilero() async {
    if (_sileroPath != null) return _sileroPath;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'vad'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final dest = File(p.join(dir.path, 'silero-v6.2.0-ggml.bin'));
      if (!await dest.exists()) {
        final data = await rootBundle.load(_sileroAssetPath);
        await dest.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        Log.instance.i('vad', 'extracted silero model',
            fields: {'path': dest.path, 'bytes': await dest.length()});
      }
      _sileroPath = dest.path;
      return _sileroPath;
    } catch (e, st) {
      Log.instance
          .w('vad', 'failed to extract silero model', error: e, stack: st);
      return null;
    }
  }

  /// Locate a VAD GGUF the user downloaded through Model Management.
  /// Matches by basename prefix (case-insensitive). Returns null when
  /// neither the file nor a fallback is available.
  Future<String?> _findCatalogVad(String prefix) async {
    final svc = modelService;
    if (svc == null) return null;
    try {
      final dir = Directory(svc.whisperCppDir());
      if (!await dir.exists()) return null;
      await for (final ent in dir.list()) {
        if (ent is! File) continue;
        final base = p.basename(ent.path).toLowerCase();
        if (base.startsWith(prefix.toLowerCase()) && base.endsWith('.gguf')) {
          return ent.path;
        }
      }
    } catch (e, st) {
      Log.instance.w('vad', 'failed to locate VAD GGUF',
          error: e, stack: st, fields: {'prefix': prefix});
    }
    return null;
  }

  /// Resolve the on-disk path for the chosen VAD backend. Falls back to
  /// silero (bundled) when the requested GGUF isn't on disk yet.
  Future<String?> ensureModel({VadBackend backend = VadBackend.silero}) async {
    String? path;
    switch (backend) {
      case VadBackend.silero:
        path = await _ensureSilero();
        break;
      case VadBackend.firered:
        path = await _findCatalogVad('firered-vad');
        break;
      case VadBackend.marblenet:
        path = await _findCatalogVad('marblenet-vad');
        break;
      case VadBackend.whisperEncDec:
        // The current public GGUF is at `cstr/whisper-vad-encdec-asmr-GGUF`
        // and ships as `whisper-vad-asmr-*.gguf`; match both the new and
        // legacy naming so already-downloaded files keep working.
        path = await _findCatalogVad('whisper-vad-asmr');
        path ??= await _findCatalogVad('whisper-vad-encdec');
        break;
    }
    if (path == null && backend != VadBackend.silero) {
      Log.instance.w(
          'vad',
          '${backend.name} VAD GGUF not downloaded — '
              'falling back to bundled silero');
      path = await _ensureSilero();
    }
    return path;
  }

  /// Legacy single-arg API — kept so unchanged call sites work. Always
  /// resolves to silero.
  Future<String?> ensureSileroModel() =>
      ensureModel(backend: VadBackend.silero);

  /// Run VAD over [pcm] (mono 16 kHz float32) and return the detected
  /// speech spans. Each span is a `(start, end)` pair in seconds.
  /// Returns an empty list when the VAD model isn't available or the
  /// call fails. Useful for waveform UI overlays showing speech vs
  /// silence regions.
  Future<List<crispasr.VadSpan>> detectSpeechSpans(
    Float32List pcm, {
    VadBackend backend = VadBackend.silero,
    double threshold = 0.5,
    int minSpeechMs = 250,
    int minSilenceMs = 100,
  }) async {
    final modelPath = await ensureModel(backend: backend);
    if (modelPath == null) return const [];
    try {
      final model = crispasr.CrispASR(modelPath);
      try {
        return model.vad(
          pcm,
          modelPath: modelPath,
          threshold: threshold,
          minSpeechMs: minSpeechMs,
          minSilenceMs: minSilenceMs,
        );
      } finally {
        model.close();
      }
    } catch (e, st) {
      Log.instance.w('vad', 'detectSpeechSpans failed', error: e, stack: st);
      return const [];
    }
  }
}

final vadServiceProvider = Provider<VadService>(
    (ref) => VadService(modelService: ref.watch(modelServiceProvider)));
