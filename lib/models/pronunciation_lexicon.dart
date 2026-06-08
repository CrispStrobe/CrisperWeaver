import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// §5.25.9 — TTS pronunciation lexicon.
///
/// User-editable table of word → pronunciation overrides that patches
/// TTS input text before synthesis. Handles proper nouns, acronyms, and
/// domain terms that the default phonemiser mispronounces.
///
/// Two override styles:
///   1. **Respelling** — `"GHz" → "gigahertz"` (text substitution)
///   2. **IPA** — `"Kubernetes" → "/kuːbərˈnɛtɪz/"` (for backends that
///      accept IPA inline, like Kokoro via espeak-ng)
///
/// Persisted as `<app-docs>/lexicon.json`.
class PronunciationLexicon {
  /// Entries keyed by the original word (case-insensitive matching
  /// during application).
  final Map<String, LexiconEntry> entries;

  const PronunciationLexicon({this.entries = const {}});

  static const _filename = 'lexicon.json';

  /// Apply the lexicon to input text, replacing known words with their
  /// pronunciation overrides. Case-insensitive matching with
  /// word-boundary awareness.
  String apply(String text) {
    if (entries.isEmpty) return text;
    var result = text;
    for (final entry in entries.values) {
      // Word-boundary-aware replacement so "CPU" doesn't match inside "CPUs"
      final escaped = entry.word.replaceAllMapped(
          RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');
      final re = RegExp(
        '(?<![A-Za-z0-9])$escaped(?![A-Za-z0-9])',
        caseSensitive: false,
      );
      result = result.replaceAll(re, entry.replacement);
    }
    return result;
  }

  /// Load from disk. Returns an empty lexicon if the file doesn't exist.
  static Future<PronunciationLexicon> load(String appDocsPath) async {
    final file = File(p.join(appDocsPath, _filename));
    if (!await file.exists()) return const PronunciationLexicon();
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = <String, LexiconEntry>{};
      for (final item in list) {
        final e = LexiconEntry.fromJson(item as Map<String, dynamic>);
        entries[e.word.toLowerCase()] = e;
      }
      return PronunciationLexicon(entries: entries);
    } catch (_) {
      return const PronunciationLexicon();
    }
  }

  /// Save to disk.
  Future<void> save(String appDocsPath) async {
    final file = File(p.join(appDocsPath, _filename));
    final list = entries.values.map((e) => e.toJson()).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(list),
    );
  }

  /// Add or update an entry.
  PronunciationLexicon put(LexiconEntry entry) {
    final updated = Map<String, LexiconEntry>.from(entries);
    updated[entry.word.toLowerCase()] = entry;
    return PronunciationLexicon(entries: updated);
  }

  /// Remove an entry by word.
  PronunciationLexicon remove(String word) {
    final updated = Map<String, LexiconEntry>.from(entries);
    updated.remove(word.toLowerCase());
    return PronunciationLexicon(entries: updated);
  }
}

/// A single lexicon entry.
class LexiconEntry {
  /// The original word to match (case-insensitive).
  final String word;

  /// The replacement text (respelling or IPA).
  final String replacement;

  /// Whether [replacement] is IPA notation.
  final bool isIpa;

  const LexiconEntry({
    required this.word,
    required this.replacement,
    this.isIpa = false,
  });

  factory LexiconEntry.fromJson(Map<String, dynamic> json) => LexiconEntry(
        word: json['word'] as String,
        replacement: json['replacement'] as String,
        isIpa: json['isIpa'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'word': word,
        'replacement': replacement,
        if (isIpa) 'isIpa': true,
      };
}
