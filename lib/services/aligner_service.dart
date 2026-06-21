import 'dart:io';
import 'dart:typed_data';

import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../engines/transcription_engine.dart';
import '../main.dart' show modelServiceProvider;
import 'log_service.dart';
import 'model_service.dart';

/// CTC / forced-aligner word timestamp backfill via CrispASR 0.4.7+
/// `crispasr_align_words_abi`.
///
/// Several backends (qwen3, voxtral, voxtral4b, granite, cohere) emit
/// sentence-level segments without per-word timings. This service takes
/// the upstream transcript, runs a second pass through a CTC aligner
/// (canary-ctc or qwen3-forced-aligner, picked by filename), and fills
/// `TranscriptionSegment.words` with per-word `(t0, t1)` tuples.
///
/// Model resolution: we look for an aligner GGUF the user has already
/// downloaded (via Model Management) in the app's models directory. If
/// nothing is available the service returns the segments unchanged —
/// it never auto-downloads. Keeps the service boundary clean and means
/// no surprise network traffic mid-transcription.
class AlignerService {
  /// Known aligner filenames CrispASR accepts. Any file matching one of
  /// these basenames in the models dir is a valid aligner target.
  static const List<String> _knownAlignerFilenames = [
    'canary-ctc-aligner.gguf',
    'canary-ctc-aligner-q8_0.gguf',
    'canary-ctc-aligner-q4_k.gguf',
    'qwen3-forced-aligner-0.6b.gguf',
    'qwen3-forced-aligner-0.6b-q4_k.gguf',
  ];

  /// Wav2Vec2 XLSR / XLS-R aligner filenames indexed by ISO 639-1 code.
  /// These are CTC models that double as forced aligners — the CrispASR
  /// engine accepts them via the `wav2vec2-aligner-<lang>` dispatch alias.
  static const Map<String, String> _wav2vec2AlignerByLang = {
    'en': 'wav2vec2-xlsr-en',
    'de': 'wav2vec2-large-xlsr-53-german',
    'fr': 'wav2vec2-large-xlsr-53-french',
    'es': 'wav2vec2-large-xlsr-53-spanish',
    'it': 'wav2vec2-large-xlsr-53-italian',
    'ja': 'wav2vec2-large-xlsr-53-japanese',
    'zh': 'wav2vec2-large-xlsr-53-chinese-zh-cn',
    'nl': 'wav2vec2-large-xlsr-53-dutch',
    'pt': 'wav2vec2-large-xlsr-53-portuguese',
    'ar': 'wav2vec2-large-xlsr-53-arabic',
    'cs': 'wav2vec2-xls-r-300m-cs-250',
    'uk': 'wav2vec2-xls-r-300m-uk-with-small-lm',
  };

  /// Optional ModelService injection. When present we honour the
  /// custom-models-dir setting; when null we fall back to the legacy
  /// `<app-docs>/models/whisper_cpp` sandbox path so the service still
  /// works in tests / standalone use.
  final ModelService? modelService;
  AlignerService({this.modelService});

  String? _cachedPath;
  String? _cachedLang;
  bool _searched = false;

  /// Resolve a language-specific wav2vec2 aligner from the models dir,
  /// or null if none downloaded. Checks all quants for the language's
  /// base name.
  Future<String?> _findWav2vec2Aligner(
      String langCode, Directory modelsDir) async {
    final baseName = _wav2vec2AlignerByLang[langCode.toLowerCase()];
    if (baseName == null) return null;
    try {
      await for (final e in modelsDir.list()) {
        if (e is! File) continue;
        final base = p.basename(e.path);
        if (base.startsWith(baseName) && base.endsWith('.gguf')) {
          return e.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Return the path to a downloaded aligner GGUF, or null if none found.
  ///
  /// When [language] is provided, prefers a language-specific wav2vec2
  /// aligner (e.g., wav2vec2-large-xlsr-53-french for 'fr') before
  /// falling back to the generic canary-ctc-aligner. When [explicit] is
  /// provided (e.g., from a user setting or CLI flag), that path is
  /// returned directly.
  Future<String?> findAligner({String? language, String? explicit}) async {
    // Explicit path from user — use as-is.
    if (explicit != null && explicit.isNotEmpty) {
      if (File(explicit).existsSync()) return explicit;
      Log.instance.w('aligner', 'explicit aligner path not found',
          fields: {'path': explicit});
    }

    // Cache hit — reuse if the language hasn't changed.
    if (_searched && language == _cachedLang) return _cachedPath;
    _searched = true;
    _cachedLang = language;
    _cachedPath = null;

    try {
      await modelService?.initialize();
      final dirPath =
          modelService?.whisperCppDir() ?? await _legacyDefaultModelsDir();
      final modelsDir = Directory(dirPath);
      if (!await modelsDir.exists()) return null;

      // 1) Language-specific wav2vec2 aligner (best match).
      if (language != null && language.isNotEmpty) {
        final langPath =
            await _findWav2vec2Aligner(language, modelsDir);
        if (langPath != null) {
          _cachedPath = langPath;
          Log.instance.d('aligner', 'found language-matched aligner',
              fields: {'lang': language, 'path': langPath});
          return _cachedPath;
        }
      }

      // 2) Generic aligner (canary-ctc / qwen3-forced).
      final entries = await modelsDir.list().toList();
      for (final e in entries) {
        if (e is! File) continue;
        final base = p.basename(e.path);
        if (_knownAlignerFilenames.contains(base) ||
            base.contains('ctc-aligner') ||
            base.contains('forced-aligner')) {
          _cachedPath = e.path;
          Log.instance
              .d('aligner', 'found aligner model', fields: {'path': e.path});
          return _cachedPath;
        }
      }
      return null;
    } catch (e, st) {
      Log.instance
          .w('aligner', 'failed to search models dir', error: e, stack: st);
      return null;
    }
  }


  /// Attach word-level timestamps to each of `segments` by forced-
  /// aligning the full transcript against `pcm`. Returns the input list
  /// unchanged if no aligner model is available or the alignment fails.
  ///
  /// Per-segment assignment: each aligned word is bucketed into the
  /// first segment whose [startTime, endTime] range contains its
  /// midpoint. Words that fall outside every segment (should be rare
  /// after good ASR) are dropped.
  Future<List<TranscriptionSegment>> addWordTimestamps(
    List<TranscriptionSegment> segments,
    Float32List pcm, {
    String? language,
    String? alignerModel,
  }) async {
    if (segments.isEmpty || pcm.isEmpty) return segments;
    final alignerPath =
        await findAligner(language: language, explicit: alignerModel);
    if (alignerPath == null) {
      Log.instance.d('aligner',
          'no CTC/forced aligner model available — skipping word-timestamp post-step');
      return segments;
    }

    final transcript = segments.map((s) => s.text).join(' ').trim();
    if (transcript.isEmpty) return segments;

    List<crispasr.AlignedWord> words;
    try {
      words = crispasr.alignWords(
        alignerModel: alignerPath,
        transcript: transcript,
        pcm: pcm,
      );
    } catch (e, st) {
      Log.instance.w('aligner', 'alignWords threw', error: e, stack: st);
      return segments;
    }
    if (words.isEmpty) {
      Log.instance.d('aligner', 'aligner returned no words');
      return segments;
    }

    Log.instance.i('aligner', 'aligned words', fields: {
      'model': p.basename(alignerPath),
      'segments': segments.length,
      'words': words.length,
      'transcript_chars': transcript.length,
    });

    // Bucket each word into the segment whose range covers its midpoint.
    final out = <TranscriptionSegment>[];
    var wordIdx = 0;
    for (final seg in segments) {
      final bucket = <TranscriptionWord>[];
      while (wordIdx < words.length) {
        final w = words[wordIdx];
        final mid = (w.start + w.end) / 2.0;
        if (mid < seg.startTime) {
          wordIdx++;
          continue;
        }
        if (mid > seg.endTime) break;
        bucket.add(TranscriptionWord(
          word: w.text,
          startTime: w.start,
          endTime: w.end,
          confidence: 1.0,
        ));
        wordIdx++;
      }
      out.add(TranscriptionSegment(
        text: seg.text,
        startTime: seg.startTime,
        endTime: seg.endTime,
        speaker: seg.speaker,
        confidence: seg.confidence,
        words: bucket.isEmpty ? seg.words : bucket,
        metadata: seg.metadata,
      ));
    }
    return out;
  }

  /// Legacy fallback path when no ModelService is wired (test
  /// fixtures, standalone use). Returns a temp-dir path so the
  /// directory-not-found check above fires gracefully — production
  /// callers always inject ModelService and never hit this branch.
  Future<String> _legacyDefaultModelsDir() async {
    return p.join(Directory.systemTemp.path, 'crisper_weaver_models',
        'whisper_cpp');
  }
}

final alignerServiceProvider = Provider<AlignerService>(
    (ref) => AlignerService(modelService: ref.watch(modelServiceProvider)));
