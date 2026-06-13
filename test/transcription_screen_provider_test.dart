// Unit tests for TranscriptionScreenNotifier (§8.2).

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/transcription_screen_provider.dart';

void main() {
  late ProviderContainer container;
  late TranscriptionScreenNotifier n;

  TranscriptionScreenState readState() =>
      container.read(transcriptionScreenProvider);

  setUp(() {
    container = ProviderContainer();
    container.read(transcriptionScreenProvider);
    n = container.read(transcriptionScreenProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('initial state has sensible defaults', () {
    final s = readState();
    expect(s.selectedFilePath, isNull);
    expect(s.selectedFileBytes, isNull);
    expect(s.selectedFileName, isNull);
    expect(s.showAdvancedOptions, isFalse);
    expect(s.enableDiarization, isFalse);
    expect(s.language, 'auto');
    expect(s.modelName, 'base');
    expect(s.engineReady, isFalse);
    expect(s.availableModels, isEmpty);
    expect(s.loadingModels, isFalse);
    expect(s.modelNameFilter, isEmpty);
    expect(s.backendFilter, isEmpty);
    expect(s.transcribePending, isFalse);
    expect(s.loadCancelled, isFalse);
    expect(s.dropHover, isFalse);
    expect(s.tagSegmentLanguages, isFalse);
  });

  test('setSelectedFilePath updates and clears', () {
    n.setSelectedFilePath('/tmp/audio.wav');
    expect(readState().selectedFilePath, '/tmp/audio.wav');
    n.setSelectedFilePath(null);
    expect(readState().selectedFilePath, isNull);
  });

  test('setSelectedFileBytes updates and clears', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    n.setSelectedFileBytes(bytes);
    expect(readState().selectedFileBytes, bytes);
    n.setSelectedFileBytes(null);
    expect(readState().selectedFileBytes, isNull);
  });

  test('setSelectedFileName updates and clears', () {
    n.setSelectedFileName('test.wav');
    expect(readState().selectedFileName, 'test.wav');
    n.setSelectedFileName(null);
    expect(readState().selectedFileName, isNull);
  });

  test('setShowAdvancedOptions updates flag', () {
    n.setShowAdvancedOptions(true);
    expect(readState().showAdvancedOptions, isTrue);
    n.setShowAdvancedOptions(false);
    expect(readState().showAdvancedOptions, isFalse);
  });

  test('setEnableDiarization updates flag', () {
    n.setEnableDiarization(true);
    expect(readState().enableDiarization, isTrue);
  });

  test('setLanguage updates language', () {
    n.setLanguage('de');
    expect(readState().language, 'de');
  });

  test('setModelName updates model', () {
    n.setModelName('tiny');
    expect(readState().modelName, 'tiny');
  });

  test('setEngineReady updates flag', () {
    n.setEngineReady(true);
    expect(readState().engineReady, isTrue);
  });

  test('setLoadingModels updates flag', () {
    n.setLoadingModels(true);
    expect(readState().loadingModels, isTrue);
    n.setLoadingModels(false);
    expect(readState().loadingModels, isFalse);
  });

  test('setModelNameFilter updates filter', () {
    n.setModelNameFilter('whisper');
    expect(readState().modelNameFilter, 'whisper');
  });

  test('setBackendFilter updates filter', () {
    n.setBackendFilter('parakeet');
    expect(readState().backendFilter, 'parakeet');
  });

  test('setTranscribePending updates flag', () {
    n.setTranscribePending(true);
    expect(readState().transcribePending, isTrue);
    n.setTranscribePending(false);
    expect(readState().transcribePending, isFalse);
  });

  test('setLoadCancelled updates flag', () {
    n.setLoadCancelled(true);
    expect(readState().loadCancelled, isTrue);
  });

  test('setDropHover updates flag', () {
    n.setDropHover(true);
    expect(readState().dropHover, isTrue);
    n.setDropHover(false);
    expect(readState().dropHover, isFalse);
  });

  test('setTagSegmentLanguages updates flag', () {
    n.setTagSegmentLanguages(true);
    expect(readState().tagSegmentLanguages, isTrue);
  });

  test('setWebFile sets bytes and name, clears path', () {
    n.setSelectedFilePath('/old/path.wav');
    n.setWebFile(
      bytes: Uint8List.fromList([10, 20, 30]),
      name: 'upload.wav',
    );
    final s = readState();
    expect(s.selectedFileBytes, isNotNull);
    expect(s.selectedFileBytes!.length, 3);
    expect(s.selectedFileName, 'upload.wav');
    expect(s.selectedFilePath, isNull);
  });

  test('startTranscription sets pending and clears loadCancelled', () {
    n.setLoadCancelled(true);
    n.startTranscription();
    final s = readState();
    expect(s.transcribePending, isTrue);
    expect(s.loadCancelled, isFalse);
  });

  test('multiple mutations are independent', () {
    n.setLanguage('fr');
    n.setModelName('small');
    n.setEngineReady(true);
    n.setEnableDiarization(true);
    final s = readState();
    expect(s.language, 'fr');
    expect(s.modelName, 'small');
    expect(s.engineReady, isTrue);
    expect(s.enableDiarization, isTrue);
    // Unchanged defaults preserved
    expect(s.showAdvancedOptions, isFalse);
    expect(s.loadingModels, isFalse);
    expect(s.transcribePending, isFalse);
    expect(s.dropHover, isFalse);
  });

  test('copyWith preserves non-overridden fields', () {
    n.setLanguage('es');
    n.setModelName('medium');
    final s = readState();
    final s2 = s.copyWith(language: 'zh');
    expect(s2.language, 'zh');
    expect(s2.modelName, 'medium'); // preserved
  });

  test('copyWith clearSelectedFilePath resets to null', () {
    n.setSelectedFilePath('/test.wav');
    final s = readState().copyWith(clearSelectedFilePath: true);
    expect(s.selectedFilePath, isNull);
  });
}
