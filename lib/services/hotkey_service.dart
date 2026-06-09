// HotkeyService — PLAN §5.1.11.
//
// Desktop-only system-level hotkey for push-to-transcribe or
// toggle-recording. Pure Dart via hotkey_manager; the package
// has native plugins for macOS / Linux / Windows and is a no-op
// on iOS / Android (system-level shortcuts aren't a thing on
// the consumer mobile platforms).
//
// The service is pure-data + stream-broadcast: it doesn't drive
// the recorder directly so unit tests don't have to mock the
// audio stack. Subscribers (one per screen that should react to
// the hotkey — `MicRecorderWidget` today) listen on
// `HotkeyService.events` and dispatch.
//
// Persistence: encoded as a string in SharedPreferences,
// `<modifier1>+<modifier2>+...+<key>`, e.g. `meta+shift+space`
// or `control+alt+r`. Each save round-trips through `parse` →
// `serialize` to enforce a normalised shape so the Settings UI
// always shows the user's chosen combo back exactly as they
// chose it.

import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/platform_utils.dart' as plat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'log_service.dart';
import 'settings_service.dart';

/// What the hotkey emits when pressed. Subscribers map this to
/// recorder start / stop / toggle. We keep the event vocabulary
/// small so the same service can drive push-to-talk (down=start,
/// up=stop) AND toggle (down=toggle) modes from one registration.
enum HotkeyEvent { keyDown, keyUp }

/// What the user wants the hotkey to do when pressed.
enum HotkeyAction {
  /// Press to start, release to stop. Matches the typical
  /// dictation / walkie-talkie idiom. Recommended on combos
  /// that include a modifier — without a modifier, a "press
  /// and hold" keypress can produce key-repeat events from the
  /// OS that the platform plugin smooths out.
  pushToTalk,

  /// Press once to start, press again to stop. Simpler mental
  /// model for users who like discrete on/off; doesn't require
  /// holding a modifier.
  toggle,
}

class HotkeyService {
  HotkeyService(this._settings);

  final SettingsService _settings;

  final StreamController<HotkeyEvent> _events =
      StreamController<HotkeyEvent>.broadcast();
  Stream<HotkeyEvent> get events => _events.stream;

  HotKey? _registered;

  /// Returns true when the current platform supports system-
  /// level hotkeys. macOS / Windows / Linux: yes; iOS / Android:
  /// no. Web is N/A (Flutter-for-web doesn't run this app).
  bool get isPlatformSupported =>
      plat.isMacOS || plat.isWindows || plat.isLinux;

  /// Register the currently-configured hotkey, if any. Safe to
  /// call repeatedly — unregisters the previous one first.
  Future<void> applyFromSettings() async {
    if (!isPlatformSupported) return;
    await unregister();
    if (!_settings.hotkeyEnabled) return;
    final combo = _settings.hotkeyCombo;
    if (combo.isEmpty) return;
    final hotKey = parse(combo);
    if (hotKey == null) {
      Log.instance.w('hotkey',
          'failed to parse persisted hotkey combo, ignoring',
          fields: {'combo': combo});
      return;
    }
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => _events.add(HotkeyEvent.keyDown),
        keyUpHandler: (_) => _events.add(HotkeyEvent.keyUp),
      );
      _registered = hotKey;
      Log.instance.i('hotkey', 'registered',
          fields: {'combo': combo, 'action': _settings.hotkeyAction.name});
    } catch (e, st) {
      Log.instance.e('hotkey', 'register failed',
          fields: {'combo': combo}, error: e, stack: st);
    }
  }

  Future<void> unregister() async {
    if (!isPlatformSupported) return;
    final r = _registered;
    if (r == null) return;
    try {
      await hotKeyManager.unregister(r);
    } catch (e, st) {
      Log.instance.w('hotkey', 'unregister failed',
          error: e, stack: st);
    }
    _registered = null;
  }

  /// Hand the latest event mode to subscribers. Public so the
  /// recorder widget can call `service.action` lazily — keeps
  /// the action choice out of the event stream itself, which
  /// lets us swap action mode without re-registering.
  HotkeyAction get action => _settings.hotkeyAction;

  /// Disposal hook for tests.
  Future<void> dispose() async {
    await unregister();
    await _events.close();
  }

  // ----- serialization -----

  /// Parse a persisted combo string ("meta+shift+space",
  /// "control+alt+r") into a HotKey. Returns null when the
  /// string is malformed; callers fall through to "no hotkey
  /// registered" so a corrupt prefs entry can't crash startup.
  static HotKey? parse(String combo) {
    final parts = combo
        .trim()
        .toLowerCase()
        .split('+')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    final keyName = parts.removeLast();
    final modifiers = <HotKeyModifier>[];
    for (final m in parts) {
      final mod = _parseModifier(m);
      if (mod == null) return null;
      if (!modifiers.contains(mod)) modifiers.add(mod);
    }
    final key = _parseKey(keyName);
    if (key == null) return null;
    return HotKey(
      key: key,
      modifiers: modifiers.isEmpty ? null : modifiers,
      scope: HotKeyScope.system,
    );
  }

  /// Inverse of [parse]; renders a normalised
  /// "modifier+modifier+key" string. Always lowercases and
  /// orders modifiers as control → alt → shift → meta so two
  /// equivalent inputs round-trip to the same canonical form.
  static String serialize(HotKey hotKey) {
    final mods = (hotKey.modifiers ?? const <HotKeyModifier>[]).toList()
      ..sort((a, b) => _modOrder(a).compareTo(_modOrder(b)));
    final lk = hotKey.logicalKey;
    final keyName = _serializeKey(lk);
    return [...mods.map(_serializeModifier), keyName].join('+');
  }

  static HotKeyModifier? _parseModifier(String s) {
    switch (s) {
      case 'control':
      case 'ctrl':
        return HotKeyModifier.control;
      case 'alt':
      case 'option':
        return HotKeyModifier.alt;
      case 'shift':
        return HotKeyModifier.shift;
      case 'meta':
      case 'cmd':
      case 'command':
      case 'super':
      case 'win':
        return HotKeyModifier.meta;
      case 'fn':
        return HotKeyModifier.fn;
      case 'capslock':
      case 'caps_lock':
        return HotKeyModifier.capsLock;
    }
    return null;
  }

  static String _serializeModifier(HotKeyModifier m) {
    switch (m) {
      case HotKeyModifier.control:
        return 'control';
      case HotKeyModifier.alt:
        return 'alt';
      case HotKeyModifier.shift:
        return 'shift';
      case HotKeyModifier.meta:
        return 'meta';
      case HotKeyModifier.fn:
        return 'fn';
      case HotKeyModifier.capsLock:
        return 'capslock';
    }
  }

  static int _modOrder(HotKeyModifier m) {
    // Stable canonical order so two physically-equivalent
    // combos serialise to the same string.
    switch (m) {
      case HotKeyModifier.control:
        return 0;
      case HotKeyModifier.alt:
        return 1;
      case HotKeyModifier.shift:
        return 2;
      case HotKeyModifier.meta:
        return 3;
      case HotKeyModifier.fn:
        return 4;
      case HotKeyModifier.capsLock:
        return 5;
    }
  }

  static LogicalKeyboardKey? _parseKey(String name) {
    // Letter keys A..Z
    if (name.length == 1 && RegExp(r'^[a-z]$').hasMatch(name)) {
      return _letterKey(name);
    }
    // Digits 0..9
    if (name.length == 1 && RegExp(r'^[0-9]$').hasMatch(name)) {
      return _digitKey(name);
    }
    switch (name) {
      case 'space':
        return LogicalKeyboardKey.space;
      case 'enter':
      case 'return':
        return LogicalKeyboardKey.enter;
      case 'tab':
        return LogicalKeyboardKey.tab;
      case 'escape':
      case 'esc':
        return LogicalKeyboardKey.escape;
      case 'backspace':
        return LogicalKeyboardKey.backspace;
      case 'delete':
        return LogicalKeyboardKey.delete;
      case 'f1':
        return LogicalKeyboardKey.f1;
      case 'f2':
        return LogicalKeyboardKey.f2;
      case 'f3':
        return LogicalKeyboardKey.f3;
      case 'f4':
        return LogicalKeyboardKey.f4;
      case 'f5':
        return LogicalKeyboardKey.f5;
      case 'f6':
        return LogicalKeyboardKey.f6;
      case 'f7':
        return LogicalKeyboardKey.f7;
      case 'f8':
        return LogicalKeyboardKey.f8;
      case 'f9':
        return LogicalKeyboardKey.f9;
      case 'f10':
        return LogicalKeyboardKey.f10;
      case 'f11':
        return LogicalKeyboardKey.f11;
      case 'f12':
        return LogicalKeyboardKey.f12;
    }
    return null;
  }

  static String _serializeKey(LogicalKeyboardKey k) {
    final label = k.keyLabel.toLowerCase();
    if (label.length == 1 && RegExp(r'^[a-z0-9]$').hasMatch(label)) {
      return label;
    }
    if (k == LogicalKeyboardKey.space) return 'space';
    if (k == LogicalKeyboardKey.enter) return 'enter';
    if (k == LogicalKeyboardKey.tab) return 'tab';
    if (k == LogicalKeyboardKey.escape) return 'escape';
    if (k == LogicalKeyboardKey.backspace) return 'backspace';
    if (k == LogicalKeyboardKey.delete) return 'delete';
    // F-keys.
    for (var i = 1; i <= 12; i++) {
      final fkey = LogicalKeyboardKey(0x00100000700 + (i - 1));
      if (k.keyId == fkey.keyId) return 'f$i';
    }
    return label.isEmpty ? 'unknown' : label;
  }

  static LogicalKeyboardKey _letterKey(String c) {
    switch (c) {
      case 'a': return LogicalKeyboardKey.keyA;
      case 'b': return LogicalKeyboardKey.keyB;
      case 'c': return LogicalKeyboardKey.keyC;
      case 'd': return LogicalKeyboardKey.keyD;
      case 'e': return LogicalKeyboardKey.keyE;
      case 'f': return LogicalKeyboardKey.keyF;
      case 'g': return LogicalKeyboardKey.keyG;
      case 'h': return LogicalKeyboardKey.keyH;
      case 'i': return LogicalKeyboardKey.keyI;
      case 'j': return LogicalKeyboardKey.keyJ;
      case 'k': return LogicalKeyboardKey.keyK;
      case 'l': return LogicalKeyboardKey.keyL;
      case 'm': return LogicalKeyboardKey.keyM;
      case 'n': return LogicalKeyboardKey.keyN;
      case 'o': return LogicalKeyboardKey.keyO;
      case 'p': return LogicalKeyboardKey.keyP;
      case 'q': return LogicalKeyboardKey.keyQ;
      case 'r': return LogicalKeyboardKey.keyR;
      case 's': return LogicalKeyboardKey.keyS;
      case 't': return LogicalKeyboardKey.keyT;
      case 'u': return LogicalKeyboardKey.keyU;
      case 'v': return LogicalKeyboardKey.keyV;
      case 'w': return LogicalKeyboardKey.keyW;
      case 'x': return LogicalKeyboardKey.keyX;
      case 'y': return LogicalKeyboardKey.keyY;
      case 'z': return LogicalKeyboardKey.keyZ;
    }
    return LogicalKeyboardKey.keyA;
  }

  static LogicalKeyboardKey _digitKey(String c) {
    switch (c) {
      case '0': return LogicalKeyboardKey.digit0;
      case '1': return LogicalKeyboardKey.digit1;
      case '2': return LogicalKeyboardKey.digit2;
      case '3': return LogicalKeyboardKey.digit3;
      case '4': return LogicalKeyboardKey.digit4;
      case '5': return LogicalKeyboardKey.digit5;
      case '6': return LogicalKeyboardKey.digit6;
      case '7': return LogicalKeyboardKey.digit7;
      case '8': return LogicalKeyboardKey.digit8;
      case '9': return LogicalKeyboardKey.digit9;
    }
    return LogicalKeyboardKey.digit0;
  }
}

/// Provider — initialised in main once SharedPreferences is
/// available. Held as a singleton across the app so any
/// subscriber resolves the same broadcast stream.
final hotkeyServiceProvider = Provider<HotkeyService>((ref) {
  throw UnimplementedError('HotkeyService not initialized');
});
