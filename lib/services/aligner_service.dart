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

  /// Optional ModelService injection. When present we honour the
  /// custom-models-dir setting; when null we fall back to the legacy
  /// `<app-docs>/models/whisper_cpp` sandbox path so the service still
  /// works in tests / standalone use.
  final ModelService? modelService;
  AlignerService({this.modelService});

  String? _cachedPath;
  bool _searched = false;

  /// Return the path to a downloaded aligner GGUF, or null if none found.
  /// Re-checks on every call when no ModelService is wired (no caching
  /// without one because the directory could change underneath us).
  Future<String?> _findAligner() async {
    if (_searched) return _cachedPath;
    _searched = true;
    try {
      // Prefer the ModelService-resolved path so the user's
      // customModelsDir override is honoured automatically.
      await modelService?.initialize();
      final dirPath = modelService?.whisperCppDir() ??
          await _legacyDefaultModelsDir();
      final modelsDir = Directory(dirPath);
      if (!await modelsDir.exists()) return null;

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
    Float32List pcm,
  ) async {
    if (segments.isEmpty || pcm.isEmpty) return segments;
    final alignerPath = await _findAligner();
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
