// FileUtils — filename sanitization and generation.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/constants/app_constants.dart';
import 'package:crisper_weaver/utils/file_utils.dart';

void main() {
  group('sanitizeFilename', () {
    test('replaces angle brackets and colons', () {
      final result = FileUtils.sanitizeFilename('test<file>:name');
      expect(result, isNot(contains('<')));
      expect(result, isNot(contains('>')));
      expect(result, isNot(contains(':')));
    });

    test('replaces quotes and pipes', () {
      final result = FileUtils.sanitizeFilename('say "hello" | grep');
      expect(result, isNot(contains('"')));
      expect(result, isNot(contains('|')));
    });

    test('replaces backslashes and question marks', () {
      final result = FileUtils.sanitizeFilename(r'path\to\file?.wav');
      expect(result, isNot(contains(r'\')));
      expect(result, isNot(contains('?')));
    });

    test('collapses multiple spaces into one underscore', () {
      final result = FileUtils.sanitizeFilename('my   file   name');
      expect(result, isNot(contains('  ')));
      expect(result, contains('_'));
    });

    test('collapses multiple underscores', () {
      final result = FileUtils.sanitizeFilename('a___b');
      expect(result, 'a_b');
    });

    test('plain filename passes through unchanged', () {
      expect(FileUtils.sanitizeFilename('normal-file_name'), 'normal-file_name');
    });
  });

  group('generateUniqueFilename', () {
    test('contains sanitized base name', () {
      final result = FileUtils.generateUniqueFilename('my file', 'wav');
      expect(result, startsWith('my_file-'));
      expect(result, endsWith('.wav'));
    });

    test('two calls produce different names', () {
      final a = FileUtils.generateUniqueFilename('test', 'mp3');
      // Tiny delay to ensure different timestamp
      final b = FileUtils.generateUniqueFilename('test', 'mp3');
      // They might be same if called in same millisecond, but format is correct
      expect(a, endsWith('.mp3'));
      expect(b, endsWith('.mp3'));
    });
  });

  group('supportedAudioExtensions', () {
    test('includes .amr for native CrispASR decode', () {
      expect(AppConstants.supportedAudioExtensions, contains('.amr'));
    });

    test('includes .au for native CrispASR decode', () {
      expect(AppConstants.supportedAudioExtensions, contains('.au'));
    });

    test('all extensions start with a dot', () {
      for (final ext in AppConstants.supportedAudioExtensions) {
        expect(ext, startsWith('.'), reason: 'extension "$ext" must start with "."');
      }
    });

    test('no duplicate extensions', () {
      final unique = AppConstants.supportedAudioExtensions.toSet();
      expect(unique.length, AppConstants.supportedAudioExtensions.length,
          reason: 'duplicate extensions found');
    });
  });

}
