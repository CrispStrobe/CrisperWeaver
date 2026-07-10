// §8.7 / §9.3 — Widget tests for TranscriptionScreen.
//
// Provider-level tests pass cleanly. Widget render tests require
// provider overrides (the screen modifies providers in initState).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/transcription_screen_provider.dart';

void main() {
  group('TranscriptionScreenProvider', () {
    test('has sensible defaults', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(transcriptionScreenProvider);
      expect(state.transcribePending, isFalse);
      expect(state.showAdvancedOptions, isFalse);
      expect(state.enableDiarization, isFalse);
      expect(state.language, 'auto');
      expect(state.modelName, isNotNull);
    });

    test('toggles advanced options', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setShowAdvancedOptions(true);
      expect(container.read(transcriptionScreenProvider).showAdvancedOptions,
          isTrue);
      n.setShowAdvancedOptions(false);
      expect(container.read(transcriptionScreenProvider).showAdvancedOptions,
          isFalse);
    });

    test('sets language', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setLanguage('de');
      expect(container.read(transcriptionScreenProvider).language, 'de');
      n.setLanguage('auto');
      expect(container.read(transcriptionScreenProvider).language, 'auto');
    });

    test('toggles diarization', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setEnableDiarization(true);
      expect(
          container.read(transcriptionScreenProvider).enableDiarization, isTrue);
      n.setEnableDiarization(false);
      expect(container.read(transcriptionScreenProvider).enableDiarization,
          isFalse);
    });

    test('sets model name', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setModelName('whisper-tiny');
      expect(
          container.read(transcriptionScreenProvider).modelName, 'whisper-tiny');
    });

    test('setSelectedFilePath and setSelectedFileName update state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setSelectedFilePath('/tmp/test.wav');
      n.setSelectedFileName('test.wav');
      final state = container.read(transcriptionScreenProvider);
      expect(state.selectedFilePath, '/tmp/test.wav');
      expect(state.selectedFileName, 'test.wav');
    });

    test('setTagSegmentLanguages toggles', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(transcriptionScreenProvider.notifier);
      n.setTagSegmentLanguages(true);
      expect(container.read(transcriptionScreenProvider).tagSegmentLanguages,
          isTrue);
    });
  });
}
