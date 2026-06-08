import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// §5.25.4 — Speaker-adaptive vocabulary.
///
/// Per-speaker vocabulary profiles that automatically activate when a
/// recognized speaker is detected during diarised transcription.
/// Persisted alongside `.spk` embedding files in `<app-docs>/speakers/`.
class SpeakerVocab {
  /// The speaker name (matches the `.spk` profile name).
  final String speakerName;

  /// Domain-specific vocabulary terms for this speaker.
  /// These are injected into `initial_prompt` or `setAsk` when this
  /// speaker is identified in a diarised segment.
  final List<String> terms;

  const SpeakerVocab({
    required this.speakerName,
    required this.terms,
  });

  /// Construct from JSON map.
  factory SpeakerVocab.fromJson(Map<String, dynamic> json) {
    return SpeakerVocab(
      speakerName: json['speakerName'] as String,
      terms: (json['terms'] as List<dynamic>).cast<String>(),
    );
  }

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() => {
        'speakerName': speakerName,
        'terms': terms,
      };

  /// Load a speaker vocab from disk. Returns null if no vocab file exists.
  static Future<SpeakerVocab?> load(String speakersDir, String name) async {
    final file = File(p.join(speakersDir, '$name.vocab.json'));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return SpeakerVocab.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Save this speaker vocab to disk.
  Future<void> save(String speakersDir) async {
    final file = File(p.join(speakersDir, '$speakerName.vocab.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  /// Delete this speaker's vocab from disk.
  static Future<void> delete(String speakersDir, String name) async {
    final file = File(p.join(speakersDir, '$name.vocab.json'));
    if (await file.exists()) await file.delete();
  }

  /// List all speaker vocabs in the speakers directory.
  static Future<List<SpeakerVocab>> listAll(String speakersDir) async {
    final dir = Directory(speakersDir);
    if (!await dir.exists()) return [];
    final vocabs = <SpeakerVocab>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.vocab.json')) {
        try {
          final raw = await entity.readAsString();
          vocabs.add(SpeakerVocab.fromJson(
              jsonDecode(raw) as Map<String, dynamic>));
        } catch (_) {
          // Skip corrupt vocab files.
        }
      }
    }
    return vocabs;
  }

  /// Merge all terms from identified speakers into a single vocab list
  /// for use as the `initial_prompt` prefix. De-duplicates.
  static List<String> mergeForSpeakers(
    List<SpeakerVocab> allVocabs,
    Set<String> identifiedSpeakers,
  ) {
    final merged = <String>{};
    for (final vocab in allVocabs) {
      if (identifiedSpeakers.contains(vocab.speakerName)) {
        merged.addAll(vocab.terms);
      }
    }
    return merged.toList();
  }
}
