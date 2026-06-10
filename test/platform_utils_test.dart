// Unit tests for platform_utils.dart — web-safe Platform wrappers.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/utils/platform_utils.dart' as plat;

void main() {
  group('platform_utils', () {
    test('isWeb matches kIsWeb', () {
      expect(plat.isWeb, kIsWeb);
    });

    // On native test runner (not web), Platform calls should work
    // and plat.* should match them.
    test('isAndroid matches Platform.isAndroid', () {
      expect(plat.isAndroid, Platform.isAndroid);
    });

    test('isIOS matches Platform.isIOS', () {
      expect(plat.isIOS, Platform.isIOS);
    });

    test('isMacOS matches Platform.isMacOS', () {
      expect(plat.isMacOS, Platform.isMacOS);
    });

    test('isLinux matches Platform.isLinux', () {
      expect(plat.isLinux, Platform.isLinux);
    });

    test('isWindows matches Platform.isWindows', () {
      expect(plat.isWindows, Platform.isWindows);
    });

    test('isDesktop is true on desktop platforms', () {
      expect(plat.isDesktop,
          Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    });

    test('isMobile is true on mobile platforms', () {
      expect(plat.isMobile, Platform.isIOS || Platform.isAndroid);
    });

    test('operatingSystem matches Platform.operatingSystem', () {
      expect(plat.operatingSystem, Platform.operatingSystem);
    });

    test('numberOfProcessors matches Platform.numberOfProcessors', () {
      expect(plat.numberOfProcessors, Platform.numberOfProcessors);
    });

    // Verify the getters are consistent with each other
    test('exactly one of isDesktop/isMobile/isWeb is true', () {
      final count = [plat.isDesktop, plat.isMobile, plat.isWeb]
          .where((b) => b)
          .length;
      expect(count, 1, reason: 'Exactly one platform category should be true');
    });
  });
}
