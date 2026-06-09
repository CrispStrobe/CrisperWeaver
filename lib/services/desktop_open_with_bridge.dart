// DesktopOpenWithBridge — Dart side of the macOS Open-With
// MethodChannel.
//
// Wire protocol (matches macos/Runner/OpenWithReceiver.swift):
//   Channel:  crisperweaver/open_with
//   Flutter → Native:  invokeMethod('consumePending')
//                      → returns List<String> of buffered paths
//   Native → Flutter:  setMethodCallHandler('onFiles', List<String>)
//
// Why both directions: cold-launch via Finder's Open With fires
// the AppDelegate's open: BEFORE the Flutter engine + this
// channel are up. The Swift side buffers those into a queue;
// we drain it via consumePending on start. After that, live
// opens (warm app, second file dropped on the dock, etc.) flow
// through onFiles in real time.
//
// Only wired on macOS for now — Linux already has argv intake
// (.desktop's `%F` passes files as positional args), Windows
// will land alongside an MSIX file-association story.

import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/platform_utils.dart' as plat;
import 'log_service.dart';

const String _kChannel = 'crisperweaver/open_with';

/// Sink callback the bridge feeds incoming paths to. Decoupled
/// from ShareIntakeService so tests can inject any callable —
/// the production wiring in main.dart passes
/// `intake.acceptPaths` directly.
typedef OpenWithSink = void Function(List<String> paths);

class DesktopOpenWithBridge {
  DesktopOpenWithBridge({
    required this.sink,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_kChannel);

  final OpenWithSink sink;
  final MethodChannel _channel;
  bool _started = false;

  /// Bind the live `onFiles` listener and drain whatever
  /// buffered up before this method was called.
  ///
  /// Safe to call on any platform; the macOS-only check lives
  /// inside so `main()` can fire it unconditionally without
  /// branching at the call site.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (!plat.isMacOS) {
      // No-op on every other platform — the Swift handler only
      // exists in macos/Runner, so invokeMethod would throw
      // MissingPluginException everywhere else.
      Log.instance.d('open_with',
          'DesktopOpenWithBridge skipped on ${plat.operatingSystem}');
      return;
    }

    _channel.setMethodCallHandler(_handle);

    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('consumePending');
      if (raw != null && raw.isNotEmpty) {
        final paths = raw.whereType<String>().toList(growable: false);
        Log.instance.i('open_with',
            'Consumed ${paths.length} buffered Open-With path(s) at boot');
        sink(paths);
      }
    } on PlatformException catch (e, st) {
      Log.instance.w('open_with',
          'consumePending failed: ${e.message ?? e.code}',
          error: e, stack: st);
    } on MissingPluginException catch (e, st) {
      Log.instance.w('open_with',
          'Open-With channel not registered (build without OpenWithReceiver?)',
          error: e, stack: st);
    }
  }

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'onFiles':
        final args = call.arguments;
        if (args is List) {
          final paths = args.whereType<String>().toList(growable: false);
          Log.instance.i('open_with',
              'Received ${paths.length} live Open-With path(s)');
          sink(paths);
        } else {
          Log.instance
              .w('open_with', 'onFiles called with unexpected payload: $args');
        }
        return null;
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
  }
}
