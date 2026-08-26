import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS release declares the architecture its native engines support',
      () {
    final config = File('macos/Runner/Configs/Release.xcconfig')
        .readAsStringSync();
    expect(config, contains('ARCHS = arm64'));
    expect(config, contains('ONLY_ACTIVE_ARCH = YES'));
  });

  test('macOS native build has an explicit honest deployment floor', () {
    final podfile = File('macos/Podfile').readAsStringSync();
    final buildScript = File('scripts/build_macos.sh').readAsStringSync();
    expect(podfile, contains("platform :osx, '14.0'"));
    expect(buildScript, contains('-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3'));
    expect(buildScript, contains('--target crispembed-shared'));
  });

  test('release verifier rejects architecture and min-OS drift', () {
    final verifier =
        File('scripts/verify_macos_release.sh').readAsStringSync();
    expect(verifier, contains('expected arm64 only'));
    expect(verifier, contains('vtool -show-build'));
    expect(verifier, contains('requires macOS'));
    expect(verifier, contains('codesign --verify --deep --strict'));
  });

  test('bundler removes stale optional codec dependencies', () {
    final bundler =
        File('scripts/bundle_macos_dylibs.sh').readAsStringSync();
    expect(bundler, contains(r'"$FRAMEWORKS"/libogg*.dylib'));
    expect(bundler, contains(r'"$FRAMEWORKS"/libopus*.dylib'));
  });

  test('large native phases remain load gated and bounded', () {
    final buildScript = File('scripts/build_macos.sh').readAsStringSync();
    expect(
      RegExp(r'check_build_load\.sh').allMatches(buildScript).length,
      greaterThanOrEqualTo(4),
    );
    expect(buildScript, contains('then JOBS=2'));
  });
}
