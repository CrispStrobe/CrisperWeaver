// Unit tests for EditAudioNotifier (§8.2).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/edit_audio_provider.dart';
import 'package:crisper_weaver/widgets/waveform_painter.dart';

void main() {
  late ProviderContainer container;
  late EditAudioNotifier n;

  EditAudioState readState() => container.read(editAudioProvider);

  setUp(() {
    container = ProviderContainer();
    container.read(editAudioProvider);
    n = container.read(editAudioProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('initial state has sensible defaults', () {
    final s = readState();
    expect(s.decoded, isNull);
    expect(s.bars, isNull);
    expect(s.waveformWidth, 0);
    expect(s.decodeError, isNull);
    expect(s.isPlaying, isFalse);
    expect(s.selection, isNull);
    expect(s.cutMarkers, isEmpty);
    expect(s.showTranscript, isFalse);
    expect(s.highlightedSegmentIndex, isNull);
  });

  test('setIsPlaying updates playing flag', () {
    n.setIsPlaying(true);
    expect(readState().isPlaying, isTrue);
    n.setIsPlaying(false);
    expect(readState().isPlaying, isFalse);
  });

  test('setSelection and clear', () {
    const sel = WaveformSelection(startSec: 1.0, endSec: 3.0);
    n.setSelection(sel);
    expect(readState().selection, isNotNull);
    expect(readState().selection!.startSec, 1.0);
    expect(readState().selection!.endSec, 3.0);
    n.setSelection(null);
    expect(readState().selection, isNull);
  });

  test('addCutMarker appends marker', () {
    n.addCutMarker(const WaveformCutMarker(startSec: 2.0, endSec: 2.0));
    n.addCutMarker(const WaveformCutMarker(startSec: 5.0, endSec: 5.0));
    expect(readState().cutMarkers.length, 2);
    expect(readState().cutMarkers[0].startSec, 2.0);
    expect(readState().cutMarkers[1].startSec, 5.0);
  });

  test('clearCutMarkers empties list', () {
    n.addCutMarker(const WaveformCutMarker(startSec: 1.0, endSec: 1.0));
    n.clearCutMarkers();
    expect(readState().cutMarkers, isEmpty);
  });

  test('setDecodeError and clear', () {
    n.setDecodeError('bad file');
    expect(readState().decodeError, 'bad file');
    n.setDecodeError(null);
    expect(readState().decodeError, isNull);
  });

  test('setShowTranscript toggles pane visibility', () {
    n.setShowTranscript(true);
    expect(readState().showTranscript, isTrue);
    n.setShowTranscript(false);
    expect(readState().showTranscript, isFalse);
  });

  test('setHighlightedSegmentIndex and clear', () {
    n.setHighlightedSegmentIndex(5);
    expect(readState().highlightedSegmentIndex, 5);
    n.setHighlightedSegmentIndex(null);
    expect(readState().highlightedSegmentIndex, isNull);
  });

  test('setBarsAndWidth sets both atomically', () {
    final bars = WaveformBars(peaks: const [0.1, 0.5, 0.3]);
    n.setBarsAndWidth(bars: bars, width: 400.0);
    final s = readState();
    expect(s.bars, isNotNull);
    expect(s.bars!.peaks.length, 3);
    expect(s.waveformWidth, 400.0);
  });

  test('multiple mutations are independent', () {
    n.setIsPlaying(true);
    n.setShowTranscript(true);
    n.setDecodeError('oops');
    final s = readState();
    expect(s.isPlaying, isTrue);
    expect(s.showTranscript, isTrue);
    expect(s.decodeError, 'oops');
    // Unchanged defaults preserved
    expect(s.selection, isNull);
    expect(s.cutMarkers, isEmpty);
  });
}
