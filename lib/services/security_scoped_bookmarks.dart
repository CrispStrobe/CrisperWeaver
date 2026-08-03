// SecurityScopedBookmarks — Dart side of the macOS security-scoped
// bookmark channel.
//
// Wire protocol (matches macos/Runner/SecurityScopedBookmarks.swift):
//   Channel: crisperweaver/security_bookmarks
//     create(path: String)        -> String?  base64 bookmark blob
//     resolve(bookmark: String)   -> {path: String, stale: bool}?
//     stopAccessing(path: String) -> null
//
// Why this exists: under the App Store sandbox, the access granted by
// `com.apple.security.files.user-selected.read-write` lasts only for the
// session in which the open panel ran. Anything that re-opens a user-picked
// location after a relaunch — today just the watch folder — has to persist a
// bookmark rather than a path string.
//
// macOS-only. Every other platform gets the null/no-op path so callers can
// invoke this unconditionally and fall back to the raw path they already
// hold; on Linux, Windows and the mobile targets a stored path stays valid
// across launches on its own.

import 'package:flutter/services.dart';

import '../utils/platform_utils.dart' as plat;
import 'log_service.dart';

const String _kChannel = 'crisperweaver/security_bookmarks';

/// A resolved bookmark: where it points now, and whether the blob needs
/// re-creating.
class BookmarkResolution {
  const BookmarkResolution({required this.path, required this.stale});

  /// The directory the bookmark resolves to. May differ from the path the
  /// bookmark was created for — bookmarks follow a moved or renamed folder,
  /// which is a feature, not a discrepancy to correct.
  final String path;

  /// A stale bookmark still resolved this time but will not keep doing so.
  /// The caller should re-create and re-persist it while access is live.
  final bool stale;
}

class SecurityScopedBookmarks {
  SecurityScopedBookmarks({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_kChannel);

  final MethodChannel _channel;

  /// Whether this platform needs (and supports) bookmarks at all.
  bool get isSupported => plat.isMacOS;

  /// Create a bookmark for [path], which must have been chosen by the user
  /// in the current session. Returns null on any platform but macOS, and on
  /// failure — callers fall back to persisting the raw path.
  Future<String?> create(String path) async {
    if (!isSupported) return null;
    try {
      return await _channel
          .invokeMethod<String>('create', <String, dynamic>{'path': path});
    } on MissingPluginException {
      // Older bundle without the channel registered; not fatal.
      Log.instance.d('bookmarks', 'security-bookmark channel unavailable');
      return null;
    } catch (e) {
      Log.instance.w('bookmarks', 'failed to create security-scoped bookmark',
          error: e, fields: {'path': path});
      return null;
    }
  }

  /// Resolve [bookmark] and begin accessing the directory it points at.
  ///
  /// Returns null when the bookmark can no longer be resolved — the user
  /// moved the folder to somewhere the app was never granted, deleted it, or
  /// the blob predates a restore. That is a real "you need to pick this
  /// again" state and callers must surface it rather than treat it as an
  /// empty folder.
  Future<BookmarkResolution?> resolve(String bookmark) async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
          'resolve', <String, dynamic>{'bookmark': bookmark});
      final path = res?['path'] as String?;
      if (path == null || path.isEmpty) return null;
      return BookmarkResolution(
        path: path,
        stale: res?['stale'] as bool? ?? false,
      );
    } on MissingPluginException {
      Log.instance.d('bookmarks', 'security-bookmark channel unavailable');
      return null;
    } catch (e) {
      Log.instance.w('bookmarks', 'failed to resolve security-scoped bookmark',
          error: e);
      return null;
    }
  }

  /// Release the scope taken by [resolve]. Safe to call for a path that was
  /// never resolved.
  Future<void> stopAccessing(String path) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(
          'stopAccessing', <String, dynamic>{'path': path});
    } on MissingPluginException {
      // Nothing was ever acquired.
    } catch (e) {
      Log.instance.d('bookmarks', 'stopAccessing failed', fields: {'err': '$e'});
    }
  }
}
