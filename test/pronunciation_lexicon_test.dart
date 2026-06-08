// Tests for PronunciationLexicon — the TTS word-replacement engine (§5.25.9).

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/models/pronunciation_lexicon.dart';

void main() {
  group('PronunciationLexicon', () {
    test('empty lexicon passes text through unchanged', () {
      const lex = PronunciationLexicon();
      expect(lex.apply('Hello world'), 'Hello world');
    });

    test('put adds a new entry', () {
      const lex = PronunciationLexicon();
      final updated = lex.put(const LexiconEntry(
        word: 'GHz',
        replacement: 'gigahertz',
      ));
      expect(updated.entries, hasLength(1));
      expect(updated.entries['ghz']?.replacement, 'gigahertz');
    });

    test('put overwrites an existing entry', () {
      var lex = const PronunciationLexicon();
      lex = lex.put(const LexiconEntry(word: 'GHz', replacement: 'gigahertz'));
      lex = lex.put(
          const LexiconEntry(word: 'GHz', replacement: 'gigahertz frequency'));
      expect(lex.entries, hasLength(1));
      expect(lex.entries['ghz']?.replacement, 'gigahertz frequency');
    });

    test('remove deletes an entry', () {
      var lex = const PronunciationLexicon();
      lex = lex.put(const LexiconEntry(word: 'GHz', replacement: 'gigahertz'));
      lex = lex.remove('GHz');
      expect(lex.entries, isEmpty);
    });

    test('remove is case-insensitive', () {
      var lex = const PronunciationLexicon();
      lex = lex.put(const LexiconEntry(word: 'CPU', replacement: 'C P U'));
      lex = lex.remove('cpu');
      expect(lex.entries, isEmpty);
    });

    test('apply replaces words case-insensitively', () {
      var lex = const PronunciationLexicon();
      lex = lex.put(const LexiconEntry(word: 'GHz', replacement: 'gigahertz'));
      expect(lex.apply('The CPU runs at 3.5 GHz'), 'The CPU runs at 3.5 gigahertz');
    });

    test('apply respects word boundaries', () {
      var lex = const PronunciationLexicon();
      lex = lex.put(const LexiconEntry(word: 'CPU', replacement: 'C P U'));
      // "CPU" should match, but "CPUs" should not be partially replaced
      expect(lex.apply('The CPU is fast'), 'The C P U is fast');
    });

    test('apply handles multiple entries', () {
      var lex = const PronunciationLexicon();
      lex = lex.put(const LexiconEntry(word: 'GHz', replacement: 'gigahertz'));
      lex = lex.put(const LexiconEntry(word: 'CPU', replacement: 'C P U'));
      expect(
        lex.apply('The CPU runs at 3.5 GHz'),
        'The C P U runs at 3.5 gigahertz',
      );
    });

    test('apply with IPA-flagged entry works the same', () {
      var lex = const PronunciationLexicon();
      lex = lex.put(const LexiconEntry(
        word: 'Kubernetes',
        replacement: '/kuːbərˈnɛtɪz/',
        isIpa: true,
      ));
      expect(
        lex.apply('Deploy to Kubernetes'),
        'Deploy to /kuːbərˈnɛtɪz/',
      );
    });

    test('apply with empty text returns empty', () {
      var lex = const PronunciationLexicon();
      lex = lex.put(const LexiconEntry(word: 'test', replacement: 'exam'));
      expect(lex.apply(''), '');
    });
  });

  group('LexiconEntry', () {
    test('toJson round-trips correctly', () {
      const entry = LexiconEntry(
        word: 'GHz',
        replacement: 'gigahertz',
        isIpa: false,
      );
      final json = entry.toJson();
      final restored = LexiconEntry.fromJson(json);
      expect(restored.word, 'GHz');
      expect(restored.replacement, 'gigahertz');
      expect(restored.isIpa, false);
    });

    test('toJson round-trips with IPA flag', () {
      const entry = LexiconEntry(
        word: 'Kubernetes',
        replacement: '/kuːbərˈnɛtɪz/',
        isIpa: true,
      );
      final json = entry.toJson();
      final restored = LexiconEntry.fromJson(json);
      expect(restored.isIpa, true);
    });
  });
}
