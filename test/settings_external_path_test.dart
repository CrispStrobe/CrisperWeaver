// The "All files access" (MANAGE_EXTERNAL_STORAGE) prompt in
// SettingsScreen fires iff looksLikeAndroidSharedStoragePath() returns
// true for the picked folder. This pins that gate: external shared
// storage → prompt; app-private sandbox / non-Android paths → no prompt.
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/screens/settings_screen.dart';

void main() {
  group('looksLikeAndroidSharedStoragePath', () {
    test('shared external storage roots need the permission (prompt fires)',
        () {
      const external = [
        '/storage/emulated/0/Download/models',
        '/storage/emulated/0/CrisperWeaver',
        '/sdcard/models',
        '/storage/self/primary/Music',
      ];
      for (final p in external) {
        expect(looksLikeAndroidSharedStoragePath(p), isTrue, reason: p);
      }
    });

    test('app-private sandbox dirs are exempt (no prompt)', () {
      const sandbox = [
        '/storage/emulated/0/Android/data/com.crispstrobe.crisperweaver/files/models',
        '/sdcard/Android/data/com.crispstrobe.crisperweaver/files',
      ];
      for (final p in sandbox) {
        expect(looksLikeAndroidSharedStoragePath(p), isFalse, reason: p);
      }
    });

    test('non-shared-storage paths never trigger the prompt', () {
      const other = [
        '/data/user/0/com.crispstrobe.crisperweaver/app_flutter',
        '/Users/me/models', // desktop
        'C:\\Users\\me\\models', // windows
        '',
        'relative/path',
      ];
      for (final p in other) {
        expect(looksLikeAndroidSharedStoragePath(p), isFalse, reason: p);
      }
    });
  });
}
