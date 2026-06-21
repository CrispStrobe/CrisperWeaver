// Unit tests for SenseVoice inline tag parsing (PLAN §10 / §9.6).
//
// SenseVoice's CTC head emits tags like <|HAPPY|>, <|Speech|>, <|BGM|>
// inline in the transcript text. The engine strips them from display
// text and surfaces them in segment metadata. These tests exercise
// the regex and classification logic in isolation (no model/GGUF needed).

import 'package:flutter_test/flutter_test.dart';

// Mirrors the regex and helpers in crispasr_engine.dart (§10).
// We re-implement them here rather than importing the engine (which
// pulls in the full FFI graph and would break on CI without a dylib).
final _tagPattern = RegExp(r'<\|([A-Za-z_]+)\|>');

bool _isEmotionTag(String t) =>
    const {
      'HAPPY',
      'SAD',
      'ANGRY',
      'NEUTRAL',
      'EMO_UNKNOWN',
      'SURPRISED',
      'FEARFUL',
      'DISGUSTED'
    }.contains(t.toUpperCase());

bool _isEventTag(String t) =>
    const {
      'SPEECH',
      'BGM',
      'LAUGHTER',
      'APPLAUSE',
      'NOISE',
      'MUSIC',
      'SINGING'
    }.contains(t.toUpperCase());

/// Parse SenseVoice tags from transcript text, returning
/// (cleaned text, list of tag names).
(String, List<String>) parseSensevoiceTags(String raw) {
  final tags = <String>[];
  for (final m in _tagPattern.allMatches(raw)) {
    tags.add(m.group(1)!);
  }
  final cleaned = raw.replaceAll(_tagPattern, '').trim();
  return (cleaned, tags);
}

void main() {
  group('SenseVoice tag parsing (§10)', () {
    test('extracts emotion + event tags from text', () {
      const input = '<|HAPPY|><|Speech|>Hello world<|BGM|>';
      final (text, tags) = parseSensevoiceTags(input);

      expect(text, 'Hello world');
      expect(tags, ['HAPPY', 'Speech', 'BGM']);
    });

    test('handles no tags gracefully', () {
      const input = 'Just a normal transcript.';
      final (text, tags) = parseSensevoiceTags(input);

      expect(text, 'Just a normal transcript.');
      expect(tags, isEmpty);
    });

    test('handles multiple emotion tags', () {
      const input = '<|HAPPY|><|SURPRISED|>Wow that is amazing';
      final (text, tags) = parseSensevoiceTags(input);

      expect(text, 'Wow that is amazing');
      expect(tags, ['HAPPY', 'SURPRISED']);
    });

    test('handles tags at end of text', () {
      const input = 'Some text<|Laughter|><|BGM|>';
      final (text, tags) = parseSensevoiceTags(input);

      expect(text, 'Some text');
      expect(tags, ['Laughter', 'BGM']);
    });

    test('handles tag in the middle of text', () {
      const input = 'Before<|ANGRY|>After';
      final (text, tags) = parseSensevoiceTags(input);

      expect(text, 'BeforeAfter');
      expect(tags, ['ANGRY']);
    });

    test('emotion tag classification', () {
      expect(_isEmotionTag('HAPPY'), isTrue);
      expect(_isEmotionTag('SAD'), isTrue);
      expect(_isEmotionTag('ANGRY'), isTrue);
      expect(_isEmotionTag('NEUTRAL'), isTrue);
      expect(_isEmotionTag('EMO_UNKNOWN'), isTrue);
      expect(_isEmotionTag('SURPRISED'), isTrue);
      expect(_isEmotionTag('FEARFUL'), isTrue);
      expect(_isEmotionTag('DISGUSTED'), isTrue);

      expect(_isEmotionTag('Speech'), isFalse);
      expect(_isEmotionTag('BGM'), isFalse);
      expect(_isEmotionTag('UNKNOWN'), isFalse);
    });

    test('event tag classification', () {
      expect(_isEventTag('Speech'), isTrue);
      expect(_isEventTag('BGM'), isTrue);
      expect(_isEventTag('Laughter'), isTrue);
      expect(_isEventTag('APPLAUSE'), isTrue);
      expect(_isEventTag('NOISE'), isTrue);
      expect(_isEventTag('MUSIC'), isTrue);
      expect(_isEventTag('SINGING'), isTrue);

      expect(_isEventTag('HAPPY'), isFalse);
      expect(_isEventTag('SAD'), isFalse);
    });

    test('classification is case-insensitive', () {
      expect(_isEmotionTag('happy'), isTrue);
      expect(_isEmotionTag('Happy'), isTrue);
      expect(_isEventTag('speech'), isTrue);
      expect(_isEventTag('bgm'), isTrue);
    });

    test('empty string produces no tags', () {
      final (text, tags) = parseSensevoiceTags('');
      expect(text, '');
      expect(tags, isEmpty);
    });

    test('tag-only string produces empty text', () {
      final (text, tags) = parseSensevoiceTags('<|NEUTRAL|><|Speech|>');
      expect(text, '');
      expect(tags, ['NEUTRAL', 'Speech']);
    });
  });

  group('AlignerService wav2vec2 language map (§10)', () {
    // Mirrors AlignerService._wav2vec2AlignerByLang
    const langMap = {
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

    test('all 12 languages have a mapping', () {
      expect(langMap.length, 12);
      for (final lang in ['en', 'de', 'fr', 'es', 'it', 'ja', 'zh', 'nl', 'pt', 'ar', 'cs', 'uk']) {
        expect(langMap.containsKey(lang), isTrue,
            reason: '$lang missing from wav2vec2 aligner map');
      }
    });

    test('each mapping has a unique base name', () {
      final baseNames = langMap.values.toSet();
      expect(baseNames.length, langMap.length,
          reason: 'duplicate base names in wav2vec2 aligner map');
    });

    test('unsupported language returns null', () {
      expect(langMap['ko'], isNull);
      expect(langMap['hi'], isNull);
      expect(langMap[''], isNull);
    });
  });
}
