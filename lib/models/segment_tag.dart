/// §5.25.10 — Transcript annotation / tagging system.
///
/// Tags that can be applied to individual transcription segments for
/// quick visual marking and later filtering in history search.
enum SegmentTag {
  bookmark('Bookmark', '🔖'),
  actionItem('Action item', '✅'),
  question('Question', '❓'),
  important('Important', '⭐'),
  highlight('Highlight', '🟡'),
  decision('Decision', '🔷'),
  followUp('Follow-up', '📌');

  const SegmentTag(this.label, this.emoji);

  final String label;
  final String emoji;

  /// Serialize to JSON-safe string.
  String toJson() => name;

  /// Deserialize from JSON string.
  static SegmentTag? fromJson(String? value) {
    if (value == null) return null;
    for (final tag in SegmentTag.values) {
      if (tag.name == value) return tag;
    }
    return null;
  }

  /// Deserialize a list from JSON.
  static List<SegmentTag> listFromJson(List<dynamic>? json) {
    if (json == null) return [];
    return json
        .map((e) => fromJson(e as String?))
        .whereType<SegmentTag>()
        .toList();
  }

  /// Serialize a list to JSON.
  static List<String> listToJson(List<SegmentTag> tags) {
    return tags.map((t) => t.toJson()).toList();
  }
}
