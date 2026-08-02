import '../engines/transcription_engine.dart';
import '../models/segment_tag.dart';
import '../utils/ai_text_disclosure.dart';

/// §5.25.14 — Export to note-taking tools.
///
/// Pure-function formatters that convert a transcript into structured
/// formats for popular note-taking apps. No API integration needed —
/// users paste or import the generated file.
class NoteExportService {
  NoteExportService._();

  /// Machine-processed-content notice carried by every format here.
  ///
  /// Strictly this is over-compliance: a transcript of real speech is not
  /// "synthetic text" under EU AI Act Art. 50(2), which is why nothing
  /// forces a mark onto it. But `FileUtils.saveTranscription` has always
  /// disclosed by default, and these exports write straight to disk and
  /// hand off to the share sheet without going through it — so before the
  /// 2026-08-02 audit an Obsidian export carried an `ai-generated` tag and
  /// a Notion export of the same transcript carried nothing at all. The
  /// mark is cheap; the inconsistency is what looks like an oversight.
  static const String disclosure =
      'Machine-generated transcript — produced by AI speech recognition and '
      'not checked by a human. It may contain recognition errors.';

  /// The notice appropriate to [segments].
  ///
  /// [disclosure] describes speech recognition, which is the wrong claim for
  /// audio-Q&A output: those segments are a language model's answer, and
  /// calling them a transcript tells the reader the words were spoken. The
  /// 2026-08-03 audit found every format here asserting exactly that. Both
  /// artefacts still leave through the same exporters, so the notice is
  /// chosen per export rather than fixed.
  static String disclosureFor(List<TranscriptionSegment> segments) =>
      segments.any((s) => s.isGenerated)
          ? AiTextDisclosure.audioQa
          : disclosure;

  /// Frontmatter/tag label matching [disclosureFor] — `transcript` is a
  /// factual claim about the file's contents in Obsidian and Logseq, and
  /// searching `type:transcript` should not surface generated answers.
  static String _kindFor(List<TranscriptionSegment> segments) =>
      segments.any((s) => s.isGenerated) ? 'ai-answer' : 'transcript';

  /// Export as Obsidian-flavoured Markdown with YAML frontmatter.
  ///
  /// Includes metadata (date, duration, speakers, model) in the
  /// frontmatter block, segments as timestamped bullet points, and
  /// any tags as inline markers.
  static String toObsidian({
    required List<TranscriptionSegment> segments,
    required String title,
    String? model,
    String? language,
    DateTime? date,
    Duration? duration,
    List<String>? speakers,
    Map<int, List<SegmentTag>>? segmentTags,
  }) {
    final buf = StringBuffer();

    // YAML frontmatter
    buf.writeln('---');
    buf.writeln('title: "${_escapeYaml(title)}"');
    buf.writeln('type: ${_kindFor(segments)}');
    if (date != null) buf.writeln('date: ${date.toIso8601String()}');
    if (duration != null) {
      buf.writeln(
          'duration: ${duration.inHours}h${(duration.inMinutes % 60).toString().padLeft(2, '0')}m');
    }
    if (model != null) buf.writeln('model: "$model"');
    if (language != null) buf.writeln('language: "$language"');
    if (speakers != null && speakers.isNotEmpty) {
      buf.writeln('speakers:');
      for (final s in speakers) {
        buf.writeln('  - "$s"');
      }
    }
    buf.writeln('tags:');
    buf.writeln('  - ${_kindFor(segments)}');
    buf.writeln('  - ai-generated');
    buf.writeln('ai-notice: "${_escapeYaml(disclosureFor(segments))}"');
    buf.writeln('---');
    buf.writeln();
    buf.writeln('> **Notice:** ${disclosureFor(segments)}');
    buf.writeln();

    // Title
    buf.writeln('# $title');
    buf.writeln();

    // Segments
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final ts = _formatTimestamp(seg.startTime);
      final tags = segmentTags?[i];
      final tagStr =
          tags != null && tags.isNotEmpty ? ' ${tags.map((t) => t.emoji).join()}' : '';

      if (seg.speaker != null) {
        buf.writeln('- **[$ts] ${seg.speaker}:**$tagStr ${seg.text}');
      } else {
        buf.writeln('- **[$ts]**$tagStr ${seg.text}');
      }
    }

    return buf.toString();
  }

  /// Export as Notion-compatible Markdown (simpler, no frontmatter).
  ///
  /// Notion imports Markdown files directly. Uses H2 for speakers,
  /// toggle blocks for timestamps.
  static String toNotion({
    required List<TranscriptionSegment> segments,
    required String title,
    DateTime? date,
    Map<int, List<SegmentTag>>? segmentTags,
  }) {
    final buf = StringBuffer();
    buf.writeln('# $title');
    if (date != null) {
      buf.writeln(
          '*Transcribed: ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}*');
    }
    buf.writeln();
    buf.writeln('> **Notice:** ${disclosureFor(segments)}');
    buf.writeln();

    String? currentSpeaker;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.speaker != null && seg.speaker != currentSpeaker) {
        currentSpeaker = seg.speaker;
        buf.writeln();
        buf.writeln('## $currentSpeaker');
        buf.writeln();
      }
      final ts = _formatTimestamp(seg.startTime);
      final tags = segmentTags?[i];
      final tagStr =
          tags != null && tags.isNotEmpty ? ' ${tags.map((t) => t.emoji).join()}' : '';
      buf.writeln('`$ts`$tagStr ${seg.text}');
      buf.writeln();
    }

    return buf.toString();
  }

  /// Export as Logseq indented bullet blocks.
  ///
  /// Logseq uses indented `- ` bullets for block hierarchy. Each
  /// segment is a block; metadata is a child block.
  static String toLogseq({
    required List<TranscriptionSegment> segments,
    required String title,
    DateTime? date,
    String? model,
    Map<int, List<SegmentTag>>? segmentTags,
  }) {
    final buf = StringBuffer();
    buf.writeln('- # $title');
    buf.writeln('  collapsed:: true');
    if (date != null) buf.writeln('  date:: ${date.toIso8601String()}');
    if (model != null) buf.writeln('  model:: $model');
    buf.writeln('  type:: [[${_kindFor(segments)}]]');
    buf.writeln('  tags:: ai-generated');
    buf.writeln('  ai-notice:: ${disclosureFor(segments)}');

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final ts = _formatTimestamp(seg.startTime);
      final tags = segmentTags?[i];
      final tagStr =
          tags != null && tags.isNotEmpty ? ' ${tags.map((t) => t.emoji).join()}' : '';
      final speaker = seg.speaker != null ? '**${seg.speaker}:** ' : '';
      buf.writeln('  - $speaker$tagStr${seg.text}');
      buf.writeln('    timestamp:: $ts');
    }

    return buf.toString();
  }

  /// Export as YouTube chapter format (simple `HH:MM:SS Title` lines).
  ///
  /// Useful for podcast chapter markers. Each segment with a speaker
  /// change or tag becomes a chapter marker.
  static String toYouTubeChapters({
    required List<TranscriptionSegment> segments,
    int maxChapters = 50,
  }) {
    // YouTube pastes this straight into a description box, which has no
    // comment syntax — so the notice has to be a visible line or nothing.
    final buf = StringBuffer();
    buf.writeln('[${disclosureFor(segments)}]');
    buf.writeln();
    String? lastSpeaker;
    var count = 0;

    for (final seg in segments) {
      if (count >= maxChapters) break;

      // New chapter on speaker change or at regular intervals
      if (seg.speaker != lastSpeaker || count == 0) {
        lastSpeaker = seg.speaker;
        final ts = _formatTimestampHMS(seg.startTime);
        final label = seg.speaker ?? 'Segment ${count + 1}';
        // YouTube chapters: first line of text as the title
        final titleText = seg.text.length > 60
            ? '${seg.text.substring(0, 57)}...'
            : seg.text;
        buf.writeln('$ts $label: $titleText');
        count++;
      }
    }

    return buf.toString();
  }

  static String _formatTimestamp(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static String _formatTimestampHMS(double seconds) {
    final hours = (seconds / 3600).floor();
    final mins = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static String _escapeYaml(String s) => s.replaceAll('"', '\\"');
}
