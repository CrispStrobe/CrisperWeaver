import 'dart:math' as math;

import '../engines/transcription_engine.dart';
import 'log_service.dart';

/// §5.25.6 — Audio chapter markers / podcast show notes.
///
/// Detects topic shifts in a transcript by measuring vocabulary change
/// between consecutive windows of segments. When the overlap drops
/// below a threshold, a chapter boundary is inserted.
///
/// When CrispEmbed becomes available, this will upgrade to
/// cosine-distance-based topic detection using per-segment embeddings.
class ChapterDetectionService {
  ChapterDetectionService._();

  /// Detect chapter boundaries using a sliding-window Jaccard distance.
  ///
  /// [windowSize] is the number of segments in each comparison window.
  /// [threshold] is the maximum Jaccard similarity between adjacent
  /// windows before a chapter break is inserted (lower = more sensitive).
  static List<ChapterMarker> detectChapters({
    required List<TranscriptionSegment> segments,
    int windowSize = 5,
    double threshold = 0.25,
    int minChapterSegments = 3,
  }) {
    if (segments.length < windowSize * 2) {
      // Too short to detect chapters — return one chapter for everything
      return [
        ChapterMarker(
          startTime: segments.first.startTime,
          endTime: segments.last.endTime,
          startSegmentIndex: 0,
          title: _generateTitle(segments, 0, segments.length),
        ),
      ];
    }

    final boundaries = <int>[0]; // Always start with index 0

    for (var i = windowSize; i < segments.length - windowSize; i++) {
      final leftWindow = segments.sublist(i - windowSize, i);
      final rightWindow = segments.sublist(i, math.min(i + windowSize, segments.length));

      final leftVocab = _extractVocab(leftWindow);
      final rightVocab = _extractVocab(rightWindow);

      final similarity = _jaccardSimilarity(leftVocab, rightVocab);

      if (similarity < threshold) {
        // Check minimum gap from last boundary
        if (i - boundaries.last >= minChapterSegments) {
          boundaries.add(i);
        }
      }
    }

    // Build chapter markers
    final chapters = <ChapterMarker>[];
    for (var i = 0; i < boundaries.length; i++) {
      final start = boundaries[i];
      final end = i + 1 < boundaries.length
          ? boundaries[i + 1]
          : segments.length;
      final chapterSegments = segments.sublist(start, end);

      chapters.add(ChapterMarker(
        startTime: chapterSegments.first.startTime,
        endTime: chapterSegments.last.endTime,
        startSegmentIndex: start,
        title: _generateTitle(segments, start, end),
      ));
    }

    Log.instance.i('chapters',
        'detected ${chapters.length} chapters from ${segments.length} segments');
    return chapters;
  }

  /// Export chapters as YouTube-format timestamps.
  ///
  /// EU AI Act Art. 50(2): chapter titles are verbatim transcript text, so
  /// this writes machine-produced content to a file the user then shares.
  /// [disclosure] carries the notice `NoteExportService` puts on the
  /// neighbouring "export as YouTube chapters" action — the 2026-08-04 audit
  /// found this route, reached from the menu two entries away, writing the
  /// same shape of file with nothing on it. Pass the exporter's
  /// `disclosureFor(segments)` so a Q&A answer or a machine translation is
  /// described as what it is rather than as a transcript.
  static String toYouTubeFormat(List<ChapterMarker> chapters,
      {String? disclosure}) {
    final buf = StringBuffer();
    if (disclosure != null && disclosure.isNotEmpty) {
      // A YouTube description box has no comment syntax, so the notice has
      // to be a visible line or nothing — same call as `toYouTubeChapters`.
      buf.writeln('[$disclosure]');
      buf.writeln();
    }
    for (final ch in chapters) {
      final h = (ch.startTime / 3600).floor();
      final m = ((ch.startTime % 3600) / 60).floor();
      final s = (ch.startTime % 60).floor();
      buf.writeln(
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} ${ch.title}');
    }
    return buf.toString();
  }

  /// Export chapters as podcast:chapters JSON (Podcasting 2.0 spec).
  ///
  /// [disclosure] lands in a `_disclosure` key, matching the shape
  /// `FileUtils.generateJsonContent` uses for transcript JSON. The spec
  /// ignores unknown top-level keys, so the file stays valid.
  static Map<String, dynamic> toPodcastChaptersJson(
      List<ChapterMarker> chapters,
      {String? disclosure}) {
    return {
      'version': '1.2.0',
      if (disclosure != null && disclosure.isNotEmpty) '_disclosure': disclosure,
      'chapters': chapters
          .map((ch) => {
                'startTime': ch.startTime,
                'title': ch.title,
              })
          .toList(),
    };
  }

  static Set<String> _extractVocab(List<TranscriptionSegment> segments) {
    return segments
        .expand((s) => s.text.toLowerCase().split(RegExp(r'\s+')))
        .where((w) => w.length > 2) // Skip tiny words
        .toSet();
  }

  static double _jaccardSimilarity(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 1.0 : intersection / union;
  }

  /// Generate a chapter title from the first segment's text.
  static String _generateTitle(
      List<TranscriptionSegment> allSegments, int start, int end) {
    if (start >= allSegments.length) return 'Chapter';
    final text = allSegments[start].text;
    // Take first ~50 chars, break at word boundary
    if (text.length <= 50) return text;
    final cutoff = text.lastIndexOf(' ', 50);
    return '${text.substring(0, cutoff > 0 ? cutoff : 50)}...';
  }
}

/// A detected chapter boundary in the transcript.
class ChapterMarker {
  final double startTime;
  final double endTime;
  final int startSegmentIndex;
  final String title;

  const ChapterMarker({
    required this.startTime,
    required this.endTime,
    required this.startSegmentIndex,
    required this.title,
  });
}
