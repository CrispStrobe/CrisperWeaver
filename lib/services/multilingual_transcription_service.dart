import 'dart:typed_data';

import '../engines/transcription_engine.dart';
import 'lid_service.dart';
import 'log_service.dart';

/// §5.25.5 — Multilingual simultaneous transcription.
///
/// For code-switching meetings: runs per-segment language detection
/// after VAD splits, groups consecutive same-language segments, and
/// tags each segment with its detected language. The caller can then
/// dispatch each group to the best backend for that language or
/// simply use the language tags for downstream processing.
///
/// This does NOT switch ASR models mid-stream (too slow). Instead it:
///   1. Transcribes all segments with the primary model (fast path)
///   2. Runs LID on each segment's audio
///   3. Tags each segment with `metadata['lang']`
///   4. Optionally groups by language for re-transcription with
///      a language-specific model (slow path, opt-in)
class MultilingualTranscriptionService {
  final LidService _lidService;

  MultilingualTranscriptionService({required LidService lidService})
      : _lidService = lidService;

  /// Tag each segment with its detected language. Returns the segments
  /// with `metadata['lang']` set to the ISO 639-1 code.
  ///
  /// [audioData] is the full 16 kHz mono PCM.
  /// [segments] are the already-transcribed segments.
  /// [sampleRate] is typically 16000.
  Future<List<TranscriptionSegment>> tagSegmentLanguages({
    required Float32List audioData,
    required List<TranscriptionSegment> segments,
    required int sampleRate,
  }) async {
    if (segments.isEmpty) return segments;
    // LID availability is checked per-segment via detectIfModelAvailable
    // which returns null when no LID model is on disk.

    final tagged = <TranscriptionSegment>[];
    for (final seg in segments) {
      // Extract the PCM slice for this segment
      final startSample = (seg.startTime * sampleRate).round();
      final endSample = (seg.endTime * sampleRate).round();
      if (startSample >= audioData.length || endSample <= startSample) {
        tagged.add(seg);
        continue;
      }

      final slice = audioData.sublist(
        startSample.clamp(0, audioData.length),
        endSample.clamp(0, audioData.length),
      );

      // Minimum 0.5s of audio for reliable LID
      if (slice.length < sampleRate ~/ 2) {
        tagged.add(seg);
        continue;
      }

      try {
        final lang = await _lidService.detectIfModelAvailable(slice);
        tagged.add(TranscriptionSegment(
          text: seg.text,
          startTime: seg.startTime,
          endTime: seg.endTime,
          speaker: seg.speaker,
          confidence: seg.confidence,
          words: seg.words,
          metadata: {...seg.metadata, 'lang': lang ?? 'unknown'},
          tags: seg.tags,
        ));
        Log.instance.d('multilingual',
            'segment [${seg.startTime.toStringAsFixed(1)}s] → $lang');
      } catch (e) {
        tagged.add(seg);
      }
    }

    // Log language distribution
    final langCounts = <String, int>{};
    for (final seg in tagged) {
      final lang = seg.metadata['lang'] as String? ?? 'unknown';
      langCounts[lang] = (langCounts[lang] ?? 0) + 1;
    }
    Log.instance.i('multilingual', 'language distribution: $langCounts');

    return tagged;
  }

  /// Group consecutive segments by language. Returns a list of
  /// (language, segments) pairs.
  static List<LanguageGroup> groupByLanguage(
      List<TranscriptionSegment> segments) {
    if (segments.isEmpty) return [];

    final groups = <LanguageGroup>[];
    String? currentLang;
    var currentSegments = <TranscriptionSegment>[];

    for (final seg in segments) {
      final lang = seg.metadata['lang'] as String? ?? 'unknown';
      if (lang != currentLang && currentSegments.isNotEmpty) {
        groups.add(LanguageGroup(
          language: currentLang ?? 'unknown',
          segments: currentSegments,
        ));
        currentSegments = [];
      }
      currentLang = lang;
      currentSegments.add(seg);
    }
    if (currentSegments.isNotEmpty) {
      groups.add(LanguageGroup(
        language: currentLang ?? 'unknown',
        segments: currentSegments,
      ));
    }
    return groups;
  }
}

/// A group of consecutive segments sharing the same detected language.
class LanguageGroup {
  final String language;
  final List<TranscriptionSegment> segments;

  const LanguageGroup({required this.language, required this.segments});

  double get startTime => segments.first.startTime;
  double get endTime => segments.last.endTime;
}
