import 'package:flutter/services.dart';

import 'platform_utils.dart' as plat;

/// Real fullscreen for the live-captions screen (§D).
///
/// Desktop: the native window goes fullscreen through the same
/// `crisperweaver/window_overlay` channel the subtitle overlay uses
/// (MainFlutterWindow.swift, linux/runner/my_application.cc,
/// windows/runner/flutter_window.cpp). Mobile: immersive mode hides the
/// status and navigation bars. Anything else is a no-op, so callers never
/// need to branch on the platform.
class WindowFullscreen {
  static const _channel = MethodChannel('crisperweaver/window_overlay');

  static bool get _isDesktop => plat.isMacOS || plat.isLinux || plat.isWindows;
  static bool get _isMobile => plat.isAndroid || plat.isIOS;

  static Future<void> set(bool on) async {
    if (_isDesktop) {
      try {
        await _channel.invokeMethod<void>('setFullScreen', on);
      } on MissingPluginException {
        // An older runner without the method — stay windowed.
      } on PlatformException {
        // Likewise.
      }
    } else if (_isMobile) {
      await SystemChrome.setEnabledSystemUIMode(
          on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }
}
