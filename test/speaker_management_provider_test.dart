// Unit tests for SpeakerManagementNotifier (§8.2).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/speaker_management_provider.dart';

void main() {
  late ProviderContainer container;
  late SpeakerManagementNotifier n;

  SpeakerManagementState readState() =>
      container.read(speakerManagementProvider);

  setUp(() {
    container = ProviderContainer();
    container.read(speakerManagementProvider);
    n = container.read(speakerManagementProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('initial state has null speakers and modelAvailable false', () {
    final s = readState();
    expect(s.speakers, isNull);
    expect(s.modelAvailable, isFalse);
  });

  test('setSpeakers updates speaker list', () {
    n.setSpeakers(['Alice', 'Bob']);
    expect(readState().speakers, ['Alice', 'Bob']);
  });

  test('setSpeakers null clears the list', () {
    n.setSpeakers(['Alice']);
    n.setSpeakers(null);
    expect(readState().speakers, isNull);
  });

  test('setModelAvailable updates flag', () {
    n.setModelAvailable(true);
    expect(readState().modelAvailable, isTrue);
    n.setModelAvailable(false);
    expect(readState().modelAvailable, isFalse);
  });

  test('setRefreshResult sets both speakers and modelAvailable', () {
    n.setRefreshResult(speakers: ['Charlie'], modelAvailable: true);
    final s = readState();
    expect(s.speakers, ['Charlie']);
    expect(s.modelAvailable, isTrue);
  });

  test('copyWith preserves unchanged fields', () {
    n.setRefreshResult(speakers: ['A', 'B'], modelAvailable: true);
    n.setModelAvailable(false);
    expect(readState().speakers, ['A', 'B']);
    expect(readState().modelAvailable, isFalse);
  });

  test('copyWith clearSpeakers resets to null', () {
    n.setSpeakers(['X']);
    final s = readState().copyWith(clearSpeakers: true);
    expect(s.speakers, isNull);
  });
}
