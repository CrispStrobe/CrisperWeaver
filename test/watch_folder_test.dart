import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisper_weaver/services/watch_folder_service.dart';

void main() {
  group('WatchFolderService', () {
    late Directory tmpDir;
    late WatchFolderService service;
    late List<String> detectedFiles;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('watch_folder_test_');
      detectedFiles = [];
      service = WatchFolderService(
        onNewFile: (path) => detectedFiles.add(path),
      );
    });

    tearDown(() {
      service.dispose();
      tmpDir.deleteSync(recursive: true);
    });

    test('isWatching is false before start', () {
      expect(service.isWatching, isFalse);
      expect(service.watchPath, isNull);
    });

    test('isWatching is true after start', () {
      service.start(tmpDir.path);
      expect(service.isWatching, isTrue);
      expect(service.watchPath, equals(tmpDir.path));
    });

    test('isWatching is false after stop', () {
      service.start(tmpDir.path);
      service.stop();
      expect(service.isWatching, isFalse);
    });

    test('ignores non-audio files', () async {
      service.start(tmpDir.path);
      // Create a .txt file
      File(p.join(tmpDir.path, 'test.txt')).writeAsStringSync('hello');
      // Wait for debounce (2s + margin)
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(detectedFiles, isEmpty);
    });

    test('detects new .wav file after debounce', () async {
      service.start(tmpDir.path);
      final wavFile = File(p.join(tmpDir.path, 'recording.wav'));
      wavFile.writeAsBytesSync([0x52, 0x49, 0x46, 0x46]); // RIFF header stub
      // Wait for the 2-second debounce + margin
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(detectedFiles, hasLength(1));
      expect(detectedFiles.first, endsWith('recording.wav'));
    },
        skip: Platform.isLinux
            ? null
            : 'FileSystemEntity.watch may not fire on all CI platforms');

    test('start on nonexistent dir does not crash', () {
      service.start('/nonexistent/path/that/does/not/exist');
      expect(service.isWatching, isFalse);
    });
  });
}
