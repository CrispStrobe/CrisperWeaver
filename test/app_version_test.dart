// Guards the one constant that must never drift from pubspec.yaml.
//
// `AppConstants.appVersion` is stamped into the C2PA provenance manifest
// (`generatorVersion`) and the WAV `ISFT` tag. A stale value is not a
// cosmetic bug — it is a false claim inside the very metadata the EU AI
// Act Art. 50(2) marking asks a verifier to trust. It sat at '1.0.0'
// while the app shipped 0.9.5, through five releases, because nothing
// compared the two.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisper_weaver/constants/app_constants.dart';

/// `version: 0.9.6+76` -> `0.9.6`
String? _pubspecVersion() {
  final f = File('pubspec.yaml');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}

void main() {
  group('App version integrity', () {
    test('AppConstants.appVersion matches pubspec.yaml', () {
      final pub = _pubspecVersion();
      expect(pub, isNotNull, reason: 'could not parse version: from pubspec.yaml');
      expect(
        AppConstants.appVersion,
        pub,
        reason: 'AppConstants.appVersion (${AppConstants.appVersion}) has '
            'drifted from pubspec.yaml ($pub). This value is embedded in '
            'the C2PA manifest and the WAV ISFT tag, so the drift ships as '
            'a false provenance claim. Bump both together.',
      );
    });

    test('appVersion is a bare semver triple', () {
      expect(AppConstants.appVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')),
          reason: 'the build number (+N) belongs in pubspec only — C2PA '
              'consumers expect a plain version string');
    });
  });
}
