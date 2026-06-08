import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engines/transcription_engine.dart';

/// §5.25.12 — Keyboard-driven transcript navigation.
///
/// Mixin for StatefulWidgets that display transcript segments. Provides
/// power-user keybindings:
///   - J / ↓ : next segment
///   - K / ↑ : previous segment
///   - Space  : play/pause at current segment
///   - Enter  : open edit dialog for current segment
///   - Tab    : jump to next low-confidence word (< 0.7)
///   - Escape : deselect / exit focus
///
/// Desktop-only UX — mobile users interact via touch.
mixin TranscriptKeyboardNav<T extends StatefulWidget> on State<T> {
  /// Override to provide the current segment list.
  List<TranscriptionSegment> get navSegments;

  /// Override to handle segment selection changes.
  void onSegmentSelected(int index);

  /// Override to handle play/pause at a segment.
  void onPlayPauseSegment(int index);

  /// Override to handle opening the edit dialog.
  void onEditSegment(int index);

  /// The currently focused segment index, or -1 if none.
  int _focusedSegmentIndex = -1;
  int get focusedSegmentIndex => _focusedSegmentIndex;

  /// The FocusNode for the transcript area.
  late final FocusNode transcriptFocusNode = FocusNode(
    debugLabel: 'TranscriptKeyboardNav',
  );

  @override
  void dispose() {
    transcriptFocusNode.dispose();
    super.dispose();
  }

  /// Call this in your build method to wrap the transcript widget
  /// with keyboard handling.
  Widget wrapWithKeyboardNav({required Widget child}) {
    return KeyboardListener(
      focusNode: transcriptFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (navSegments.isEmpty) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyJ:
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
      case LogicalKeyboardKey.keyK:
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
      case LogicalKeyboardKey.space:
        if (_focusedSegmentIndex >= 0) {
          onPlayPauseSegment(_focusedSegmentIndex);
        }
      case LogicalKeyboardKey.enter:
        if (_focusedSegmentIndex >= 0) {
          onEditSegment(_focusedSegmentIndex);
        }
      case LogicalKeyboardKey.tab:
        _jumpToNextLowConfidence();
      case LogicalKeyboardKey.escape:
        setState(() => _focusedSegmentIndex = -1);
        onSegmentSelected(-1);
    }
  }

  void _moveSelection(int delta) {
    final newIndex = (_focusedSegmentIndex + delta)
        .clamp(0, navSegments.length - 1);
    setState(() => _focusedSegmentIndex = newIndex);
    onSegmentSelected(newIndex);
  }

  void _jumpToNextLowConfidence() {
    final startIdx = _focusedSegmentIndex + 1;
    for (var i = startIdx; i < navSegments.length; i++) {
      final seg = navSegments[i];
      if (seg.confidence < 0.7 ||
          (seg.words != null &&
              seg.words!.any((w) => w.confidence < 0.7))) {
        setState(() => _focusedSegmentIndex = i);
        onSegmentSelected(i);
        return;
      }
    }
    // Wrap around from the start
    for (var i = 0; i < startIdx && i < navSegments.length; i++) {
      final seg = navSegments[i];
      if (seg.confidence < 0.7 ||
          (seg.words != null &&
              seg.words!.any((w) => w.confidence < 0.7))) {
        setState(() => _focusedSegmentIndex = i);
        onSegmentSelected(i);
        return;
      }
    }
  }

  /// Returns a decoration to highlight the currently focused segment card.
  BoxDecoration? segmentFocusDecoration(int index) {
    if (index != _focusedSegmentIndex) return null;
    return BoxDecoration(
      border: Border.all(
        color: Colors.blue.withValues(alpha: 0.6),
        width: 2,
      ),
      borderRadius: BorderRadius.circular(8),
    );
  }
}
