// Desktop argv triage (issue #35). `crisper_weaver.exe --help` on Windows
// used to log `WRN [share] Shared file does not exist: --help`, because
// main()'s argv went into the share-intake pipeline verbatim and every
// argument was treated as a file path. The filter is a pure static so it can
// be tested without a ProviderContainer or a plugin channel.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/share_intake_service.dart';

void main() {
  group('ShareIntakeService.filterDesktopArgs', () {
    test('keeps plain file paths untouched', () {
      expect(
        ShareIntakeService.filterDesktopArgs(
            const ['/tmp/a.wav', r'C:\Users\me\b.mp3']),
        const ['/tmp/a.wav', r'C:\Users\me\b.mp3'],
      );
    });

    test('drops long and short flags', () {
      expect(
        ShareIntakeService.filterDesktopArgs(
            const ['--help', '-h', '--verbose=2', '/tmp/a.wav']),
        const ['/tmp/a.wav'],
      );
    });

    test('reports every dropped flag exactly once', () {
      final seen = <String>[];
      final kept = ShareIntakeService.filterDesktopArgs(
        const ['--help', '/tmp/a.wav', '-v'],
        onFlag: seen.add,
      );
      expect(kept, const ['/tmp/a.wav']);
      expect(seen, const ['--help', '-v']);
    });

    test('drops blank / whitespace-only arguments without reporting them', () {
      final seen = <String>[];
      final kept = ShareIntakeService.filterDesktopArgs(
        const ['', '   ', '/tmp/a.wav'],
        onFlag: seen.add,
      );
      expect(kept, const ['/tmp/a.wav']);
      expect(seen, isEmpty);
    });

    test('an all-flags argv yields no paths at all', () {
      expect(ShareIntakeService.filterDesktopArgs(const ['--help']), isEmpty);
      expect(ShareIntakeService.filterDesktopArgs(const []), isEmpty);
    });

    test('macOS process-serial-number argv is not a file path', () {
      // Finder used to launch apps with `-psn_0_123456`; anything Cocoa or
      // the Flutter tool injects starts with `-` too.
      expect(
        ShareIntakeService.filterDesktopArgs(const ['-psn_0_123456']),
        isEmpty,
      );
    });

    test('a leading dash wins over an existing file — documented trade', () {
      // A real file named `-weird` is unreachable via argv, the same way it
      // is for every POSIX tool. Pinned so the behaviour is a decision, not
      // an accident.
      expect(ShareIntakeService.filterDesktopArgs(const ['-weird']), isEmpty);
    });
  });
}
