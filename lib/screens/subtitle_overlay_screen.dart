import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show appStateProvider;

/// §5.25.3 — Real-time subtitle overlay / teleprompter mode.
///
/// A fullscreen dark-transparent screen showing only the latest streaming
/// transcription text. Designed to be used as an always-on-top overlay on
/// desktop (via platform channel) or as a dedicated screen on mobile.
///
/// On desktop, entering this screen requests the platform to make the
/// window always-on-top and semi-transparent. Exiting restores normal
/// window behaviour.
class SubtitleOverlayScreen extends ConsumerStatefulWidget {
  const SubtitleOverlayScreen({super.key});

  @override
  ConsumerState<SubtitleOverlayScreen> createState() =>
      _SubtitleOverlayScreenState();
}

class _SubtitleOverlayScreenState
    extends ConsumerState<SubtitleOverlayScreen> {
  static const _channel = MethodChannel('crisperweaver/window_overlay');

  double _fontSize = 28.0;
  double _opacity = 0.85;
  bool _showBackground = true;
  Alignment _textAlignment = Alignment.bottomCenter;

  @override
  void initState() {
    super.initState();
    _enterOverlayMode();
  }

  @override
  void dispose() {
    _exitOverlayMode();
    super.dispose();
  }

  Future<void> _enterOverlayMode() async {
    if (!_isDesktop) return;
    try {
      await _channel.invokeMethod('setAlwaysOnTop', true);
      await _channel.invokeMethod('setWindowOpacity', 0.9);
    } on MissingPluginException {
      // Platform channel not wired yet — degrade gracefully.
    }
  }

  Future<void> _exitOverlayMode() async {
    if (!_isDesktop) return;
    try {
      await _channel.invokeMethod('setAlwaysOnTop', false);
      await _channel.invokeMethod('setWindowOpacity', 1.0);
    } on MissingPluginException {
      // Platform channel not wired yet.
    }
  }

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final text = appState.currentTranscription ?? '';

    return Scaffold(
      backgroundColor: _showBackground
          ? Colors.black.withValues(alpha: _opacity)
          : Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Exit overlay',
        ),
        actions: [
          // Font size controls
          IconButton(
            icon: const Icon(Icons.text_decrease, color: Colors.white70),
            onPressed: () => setState(() {
              _fontSize = (_fontSize - 4).clamp(14.0, 72.0);
            }),
            tooltip: 'Smaller text',
          ),
          IconButton(
            icon: const Icon(Icons.text_increase, color: Colors.white70),
            onPressed: () => setState(() {
              _fontSize = (_fontSize + 4).clamp(14.0, 72.0);
            }),
            tooltip: 'Larger text',
          ),
          // Position toggle
          IconButton(
            icon: Icon(
              _textAlignment == Alignment.bottomCenter
                  ? Icons.vertical_align_top
                  : Icons.vertical_align_bottom,
              color: Colors.white70,
            ),
            onPressed: () => setState(() {
              _textAlignment = _textAlignment == Alignment.bottomCenter
                  ? Alignment.topCenter
                  : Alignment.bottomCenter;
            }),
            tooltip: 'Toggle position',
          ),
          // Background toggle
          IconButton(
            icon: Icon(
              _showBackground ? Icons.visibility_off : Icons.visibility,
              color: Colors.white70,
            ),
            onPressed: () => setState(() => _showBackground = !_showBackground),
            tooltip: 'Toggle background',
          ),
        ],
      ),
      body: GestureDetector(
        // Double-tap to hide/show the AppBar (immersive mode)
        onDoubleTap: () {
          // Future: toggle AppBar visibility
        },
        child: Align(
          alignment: _textAlignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: text.isEmpty
                  ? Text(
                      'Waiting for transcription...',
                      key: const ValueKey('empty'),
                      style: TextStyle(
                        fontSize: _fontSize * 0.7,
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    )
                  : _buildSubtitleText(text),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleText(String text) {
    // Show only the last ~200 characters for subtitle-style display
    final display = text.length > 200 ? text.substring(text.length - 200) : text;

    return Container(
      key: ValueKey(display),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _showBackground
            ? Colors.black.withValues(alpha: 0.6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontSize: _fontSize,
          color: Colors.white,
          fontWeight: FontWeight.w500,
          height: 1.4,
          shadows: _showBackground
              ? null
              : const [
                  Shadow(
                    blurRadius: 4,
                    color: Colors.black,
                    offset: Offset(1, 1),
                  ),
                ],
        ),
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
