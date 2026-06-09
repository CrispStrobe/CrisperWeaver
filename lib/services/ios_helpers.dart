// Thin Dart wrapper around the `crisperweaver/ios_helpers`
// MethodChannel registered in ios/Runner/AppDelegate.swift.
//
// Currently only one helper:
//   • [excludeFromBackup] — set `NSURLIsExcludedFromBackupKey` on a
//     directory so iCloud doesn't upload its contents. Used by the
//     batch persistence service for the in-flight checkpoint dir
//     under `<app-docs>/batch/`, where the data is ephemeral
//     (deleted on successful job completion) and uploading it to
//     iCloud is wasted user bandwidth.
//
// Every method is a no-op on non-iOS platforms — desktop and
// Android don't have an iCloud equivalent that needs opting out of,
// so callers can fire-and-forget without an `if (plat.isIOS)`
// gate.

import 'package:flutter/services.dart';

import 'log_service.dart';
import '../utils/platform_utils.dart' as plat;

const MethodChannel _channel = MethodChannel('crisperweaver/ios_helpers');

/// Flag [dir] (typically a directory path) as excluded from iCloud
/// backup. No-op on every non-iOS platform. Failures are logged at
/// debug + swallowed — the absence of the exclusion flag isn't a
/// correctness issue, just a polish item, so we don't want to fail
/// loud paths like batch persistence init on its absence.
Future<void> excludeFromBackup(String dir) async {
  if (!plat.isIOS) return;
  try {
    await _channel.invokeMethod<bool>(
      'excludeFromBackup',
      <String, Object?>{'path': dir},
    );
    Log.instance.d('ios-helpers', 'excluded from backup',
        fields: {'path': dir});
  } on PlatformException catch (e) {
    Log.instance
        .d('ios-helpers', 'excludeFromBackup failed: ${e.message}',
            fields: {'path': dir, 'code': e.code});
  } catch (e) {
    Log.instance
        .d('ios-helpers', 'excludeFromBackup threw: $e', fields: {'path': dir});
  }
}

/// On-disk path of the App Group container identified by [groupId].
/// Surfaces the iOS `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`
/// API.
///
/// Returns `null` on every non-iOS platform AND on iOS when the
/// container can't be resolved (the entitlement isn't declared,
/// or the OS hasn't provisioned it yet). Callers should fall back
/// to `getApplicationDocumentsDirectory()` in those cases.
///
/// Use this instead of the docs directory for files that should
/// survive `flutter install` (which uninstalls the old build,
/// wiping the docs sandbox). Model downloads are the obvious
/// example.
Future<String?> appGroupContainerPath(String groupId) async {
  if (!plat.isIOS) return null;
  try {
    final p = await _channel.invokeMethod<String?>(
      'appGroupContainerPath',
      <String, Object?>{'groupId': groupId},
    );
    if (p != null && p.isNotEmpty) {
      Log.instance.d('ios-helpers', 'app group container resolved',
          fields: {'group': groupId, 'path': p});
      return p;
    }
    Log.instance.w('ios-helpers', 'app group container returned nil',
        fields: {'group': groupId});
    return null;
  } on PlatformException catch (e) {
    Log.instance.w('ios-helpers',
        'appGroupContainerPath failed: ${e.message}',
        fields: {'group': groupId, 'code': e.code});
    return null;
  } catch (e) {
    Log.instance.w('ios-helpers', 'appGroupContainerPath threw: $e',
        fields: {'group': groupId});
    return null;
  }
}
