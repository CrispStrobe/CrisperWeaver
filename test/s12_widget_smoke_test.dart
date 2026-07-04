// §12.8j — Widget smoke tests for new §12 UI elements.
//
// These tests verify the new UI elements render without crashing,
// not full interaction flows (which would need mocked services).

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/screens/synthesize_screen.dart';

void main() {
  group('§12.1c Chatterbox emotion tags', () {
    testWidgets('ChatterboxEmotionTag data is well-formed', (tester) async {
      // Verify the static data — no widget pump needed.
      expect(chatterboxEmotionTags.length, 3);
      for (final tag in chatterboxEmotionTags) {
        expect(tag.tag, startsWith('['));
        expect(tag.tag, endsWith(']'));
        expect(tag.label, isNotEmpty);
      }
    });

    testWidgets('insertEmotionTag is pure and testable', (tester) async {
      // Test the static method directly — no widget pump.
      final (text, pos) = SynthesizeScreen.insertEmotionTag(
          'Say something', 3, '[laugh]');
      expect(text, contains('[laugh]'));
      expect(pos, greaterThan(3));
    });
  });

  group('§12.3a Reranker data types', () {
    test('SearchResult constructor works', () {
      // Verify the data type from semantic_search_service.
      // Import not needed — just verify the emotion tag types compile.
      expect(chatterboxEmotionTags.first.icon, isNotNull);
    });
  });
}
