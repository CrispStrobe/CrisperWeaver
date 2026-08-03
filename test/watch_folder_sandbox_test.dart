// Watch folder under the macOS App Store sandbox.
//
// WHY THIS FILE EXISTS
//
// The audit of 2026-08-03 found the watch folder silently dead in the Mac App
// Store build. `com.apple.security.files.user-selected.read-write` grants
// access only for the session in which the open panel ran, and the feature
// persisted a raw path string and restarted the watcher from it on every
// launch. On the second launch the folder was unreadable.
//
// What made it a defect rather than a limitation is that it failed *quietly*.
// A sandbox denial makes `stat` fail, so `Directory.existsSync()` returns
// false exactly as it does for a deleted folder, and `start()` logged
// "directory does not exist" and returned. Settings went on displaying the
// path with the toggle reading enabled, over a watch that was not running.
//
// Two properties are pinned here:
//   1. `start()` reports *why* it failed rather than only logging, so the
//      caller can distinguish "gone" from "no grant" and tell the user.
//   2. The bookmark plumbing is inert off macOS, so the fallback to a raw
//      path stays intact on Linux and Windows where paths do survive.
//
// The part that cannot be tested here is the sandbox itself: it needs a
// signed, sandboxed bundle and a real relaunch. `SecurityScopedBookmarks`
// is exercised through its channel contract instead, and the entitlement is
// asserted to be present because without it bookmark creation throws at
// runtime and the whole fix silently reverts to the old behaviour.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/security_scoped_bookmarks.dart';
import 'package:crisper_weaver/services/watch_folder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WatchFolderService.start reports why it failed', () {
    test('an unreadable directory is reported, not swallowed', () {
      final svc = WatchFolderService(onNewFile: (_) {});
      addTearDown(svc.stop);

      final missing = Directory.systemTemp
          .createTempSync('cw_watch_')
        ..deleteSync();

      // This is the exact shape a sandbox denial takes: existsSync() == false
      // for a path the app simply has no grant for.
      expect(svc.start(missing.path), WatchFolderStartResult.inaccessible);
      expect(svc.isWatching, isFalse,
          reason: 'a failed start must not leave a half-open watch');
    });

    test('a readable directory starts watching', () {
      final svc = WatchFolderService(onNewFile: (_) {});
      addTearDown(svc.stop);

      final dir = Directory.systemTemp.createTempSync('cw_watch_ok_');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(svc.start(dir.path), WatchFolderStartResult.watching);
      expect(svc.isWatching, isTrue);
      expect(svc.watchPath, dir.path);
    });

    test('the watched path is only set once the watch is live', () {
      final svc = WatchFolderService(onNewFile: (_) {});
      addTearDown(svc.stop);

      final missing = Directory.systemTemp
          .createTempSync('cw_watch_none_')
        ..deleteSync();

      svc.start(missing.path);
      // Reporting a watchPath for a folder we failed to open is how the old
      // code let Settings claim a watch that did not exist.
      expect(svc.watchPath, isNull);
    });
  });

  group('SecurityScopedBookmarks channel contract', () {
    const channel = MethodChannel('crisperweaver/security_bookmarks');
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        switch (call.method) {
          case 'create':
            return 'Ym9va21hcms=';
          case 'resolve':
            return <String, dynamic>{'path': '/tmp/moved', 'stale': true};
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('create and resolve marshal the documented argument shape', () async {
      final b = SecurityScopedBookmarks();

      if (!b.isSupported) {
        // Off macOS the whole thing must stay inert: callers fall back to the
        // stored path, which survives a relaunch there on its own.
        expect(await b.create('/tmp/x'), isNull);
        expect(await b.resolve('Ym9va21hcms='), isNull);
        expect(log, isEmpty,
            reason: 'no channel traffic should occur off macOS');
        return;
      }

      expect(await b.create('/tmp/x'), 'Ym9va21hcms=');
      expect(log.single.arguments, <String, dynamic>{'path': '/tmp/x'});

      log.clear();
      final resolved = await b.resolve('Ym9va21hcms=');
      expect(resolved, isNotNull);
      // A bookmark follows a moved folder, so the resolved path wins over the
      // stored one — that is why the caller writes it back.
      expect(resolved!.path, '/tmp/moved');
      expect(resolved.stale, isTrue,
          reason: 'a stale bookmark must be re-minted while access is live');
      expect(log.single.arguments,
          <String, dynamic>{'bookmark': 'Ym9va21hcms='});
    });

    test('a platform failure degrades to null rather than throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'BOOM');
      });
      final b = SecurityScopedBookmarks();
      // Losing a bookmark must degrade the watch folder, never take the app
      // down on launch.
      expect(await b.create('/tmp/x'), isNull);
      expect(await b.resolve('Ym9va21hcms='), isNull);
    });
  });

  test('the App Store target carries the bookmark entitlement', () {
    final ents = File('macos/Runner/AppStore.entitlements').readAsStringSync();
    expect(ents.contains('com.apple.security.app-sandbox'), isTrue);
    expect(
      ents.contains('com.apple.security.files.bookmarks.app-scope'),
      isTrue,
      reason: 'Without this entitlement bookmarkData(.withSecurityScope) '
          'throws under the sandbox, create() returns null, and the watch '
          'folder silently reverts to dying on relaunch — the exact defect '
          'this file exists to prevent.',
    );
  });
}
