// §5.25.8 — WatchFolderService: start/stop lifecycle, extension filter.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisper_weaver/services/watch_folder_service.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crisper_watch_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('WatchFolderService', () {
    test('isWatching is false before start', () {
      final svc = WatchFolderService(onNewFile: (_) {});
      expect(svc.isWatching, isFalse);
      expect(svc.watchPath, isNull);
    });

    test('start sets isWatching and watchPath', () {
      final svc = WatchFolderService(onNewFile: (_) {});
      svc.start(tmp.path);
      expect(svc.isWatching, isTrue);
      expect(svc.watchPath, tmp.path);
      svc.dispose();
    });

    test('stop clears state', () {
      final svc = WatchFolderService(onNewFile: (_) {});
      svc.start(tmp.path);
      svc.stop();
      expect(svc.isWatching, isFalse);
      expect(svc.watchPath, isNull);
    });

    test('start on nonexistent dir does not crash', () {
      final svc = WatchFolderService(onNewFile: (_) {});
      svc.start('/tmp/no-such-dir-crisper-xyz-123');
      expect(svc.isWatching, isFalse);
      svc.dispose();
    });

    test('detects new audio file after debounce', () async {
      final detected = Completer<String>();
      final svc = WatchFolderService(
        onNewFile: (path) {
          if (!detected.isCompleted) detected.complete(path);
        },
      );
      svc.start(tmp.path);

      // Write an audio file.
      final wavFile = File(p.join(tmp.path, 'test.wav'));
      await wavFile.writeAsBytes(List<int>.filled(100, 0));

      // The debounce is 2 seconds; wait up to 5.
      final result = await detected.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 'TIMEOUT',
      );

      expect(result, isNot('TIMEOUT'), reason: 'should have detected the file');
      expect(result, endsWith('test.wav'));
      svc.dispose();
    });

    test('ignores non-audio extensions', () async {
      var called = false;
      final svc = WatchFolderService(
        onNewFile: (_) => called = true,
      );
      svc.start(tmp.path);

      // Write a non-audio file.
      await File(p.join(tmp.path, 'readme.txt'))
          .writeAsString('not audio');

      // Wait past the debounce window.
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(called, isFalse, reason: '.txt should be ignored');
      svc.dispose();
    });

    test('dispose is idempotent', () {
      final svc = WatchFolderService(onNewFile: (_) {});
      svc.start(tmp.path);
      svc.dispose();
      svc.dispose(); // no crash
    });
  });
}
