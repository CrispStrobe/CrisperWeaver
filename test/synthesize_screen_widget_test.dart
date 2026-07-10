// §8.7 / §9.3 — Widget tests for SynthesizeScreen.
//
// Provider-level and static-method tests pass cleanly. Widget render
// tests require provider overrides (the screen modifies providers in
// initState) — those are marked for future work.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/screens/synthesize_screen.dart';
import 'package:crisper_weaver/providers/synthesize_screen_provider.dart';

void main() {
  group('SynthesizeScreenProvider', () {
    test('defaults are sensible', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(synthesizeScreenProvider);
      expect(state.loading, isTrue);
      expect(state.busy, isFalse);
      expect(state.selectedModel, isNull);
      expect(state.s2sMode, isFalse);
      expect(state.speed, 1.0);
      expect(state.trimSilence, isFalse);
    });

    test('setSpeed updates speed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(synthesizeScreenProvider.notifier);
      n.setSpeed(1.5);
      expect(container.read(synthesizeScreenProvider).speed, 1.5);
    });

    test('setS2sMode toggles', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(synthesizeScreenProvider.notifier);
      n.setS2sMode(true);
      expect(container.read(synthesizeScreenProvider).s2sMode, isTrue);
    });

    test('setShowAdvanced toggles', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(synthesizeScreenProvider.notifier);
      n.setShowAdvanced(true);
      expect(container.read(synthesizeScreenProvider).showAdvanced, isTrue);
    });
  });

  group('SynthesizeScreen static methods', () {
    test('resolveSpeakerSelection picks first on empty current', () {
      expect(
          SynthesizeScreen.resolveSpeakerSelection(['Alice', 'Bob'], null),
          'Alice');
    });

    test('resolveSpeakerSelection preserves valid current', () {
      expect(
          SynthesizeScreen.resolveSpeakerSelection(['Alice', 'Bob'], 'Bob'),
          'Bob');
    });

    test('resolveSpeakerSelection returns null on empty list', () {
      expect(SynthesizeScreen.resolveSpeakerSelection([], 'Alice'), isNull);
    });

    test('insertEmotionTag at empty string', () {
      final (t, p) = SynthesizeScreen.insertEmotionTag('', 0, '[laugh]');
      expect(t, '[laugh]');
      expect(p, 7);
    });

    test('insertEmotionTag at end', () {
      final (t, _) = SynthesizeScreen.insertEmotionTag('Hello', 5, '[angry]');
      expect(t, 'Hello [angry]');
    });

    test('insertEmotionTag no double spaces', () {
      final (t, _) =
          SynthesizeScreen.insertEmotionTag('Hello ', 6, '[laugh]');
      expect(t.contains('  '), isFalse);
    });
  });

  group('chatterboxEmotionTags', () {
    test('has exactly 3 tags', () {
      expect(chatterboxEmotionTags.length, 3);
      expect(chatterboxEmotionTags.map((t) => t.tag).toList(),
          containsAll(['[laugh]', '[whispering]', '[angry]']));
    });

    test('all have non-empty labels and icons', () {
      for (final tag in chatterboxEmotionTags) {
        expect(tag.label, isNotEmpty);
        expect(tag.icon, isNotNull);
      }
    });
  });
}
