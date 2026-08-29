// Smoke test for the CLI (PLAN §9.4). Spawns `dart run bin/crisperweaver.dart`
// for paths that need no model/dylib — usage, command listing, arg
// validation. The per-capability behaviour (transcribe/vad/lid/punctuate/
// translate/synthesize/watermark) is covered live in the *_live_test.dart
// files against the same binding the CLI wraps. Tagged `slow` because
// `dart run` JIT-compiles the entrypoint (seconds), keeping the default
// `flutter test` fast.

@Tags(['slow'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Resolve the `dart` executable from the Flutter SDK. Inside
/// `flutter test`, `Platform.resolvedExecutable` returns `flutter_tester`
/// (the test harness), not the Dart VM. Walk up from the resolved path
/// to find `dart-sdk/bin/dart` in the Flutter cache.
final _dart = () {
  final resolved = Platform.resolvedExecutable;
  // flutter_tester lives in cache/artifacts/engine/<platform>/
  // dart is in cache/dart-sdk/bin/dart — walk up to cache/.
  final cacheDir = resolved.contains('artifacts')
      ? resolved.substring(0, resolved.indexOf('artifacts'))
      : resolved.substring(0, resolved.lastIndexOf(Platform.pathSeparator));
  final dartBin = '$cacheDir${Platform.pathSeparator}dart-sdk'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}dart';
  if (File(dartBin).existsSync()) return dartBin;
  // Fallback: try system PATH.
  return 'dart';
}();

/// Run the CLI entrypoint directly (not via `dart run`) to avoid build
/// hook lock contention when spawned from within `flutter test`.
Future<ProcessResult> _cli(List<String> args) =>
    Process.run(_dart, ['bin/crisperweaver.dart', ...args]);

void main() {
  group('crisperweaver CLI', () {
    test('--help lists every capability command', () async {
      final r = await _cli(['--help']);
      expect(r.exitCode, 0);
      final out = '${r.stdout}';
      for (final cmd in [
        'backends',
        'transcribe',
        'stream',
        'vad',
        'lid',
        'diarize',
        'align',
        'speaker',
        'punctuate',
        'translate',
        'synthesize',
        's2s',
        'watermark',
        'denoise',
      ]) {
        expect(out, contains(cmd), reason: 'help should list "$cmd"');
      }
    });

    test('a missing mandatory option is a usage error (exit 64)', () async {
      // `transcribe` without --model must fail as a usage error, not crash.
      final r = await _cli(['transcribe', 'some.wav']);
      expect(r.exitCode, 64);
      expect('${r.stderr}'.toLowerCase(), contains('model'));
    });

    test('an unknown command is a usage error', () async {
      final r = await _cli(['definitely-not-a-command']);
      expect(r.exitCode, 64);
    });

    test('an unknown flag is a usage error, not a crash', () async {
      final r = await _cli(['--definitely-not-a-flag']);
      expect(r.exitCode, 64);
      expect('${r.stderr}', contains('definitely-not-a-flag'));
    });

    test('no arguments at all prints usage instead of crashing', () async {
      final r = await _cli([]);
      expect(r.exitCode, 0);
      expect('${r.stdout}', contains('Usage:'));
    });

    // The checks below all fail before the dylib is touched, so they run
    // anywhere — no model, no libcrispasr.

    test('a non-numeric numeric option is a usage error (exit 64)', () async {
      // `int.parse` used to throw an uncaught FormatException here: a Dart
      // stack trace and exit 255 instead of a sentence about --best-of.
      final r =
          await _cli(['transcribe', '-m', 'model.bin', '--best-of', 'two', 'a.wav']);
      expect(r.exitCode, 64);
      expect('${r.stderr}', contains('best-of'));
    });

    test('a missing input file is a usage error, not a decoder crash',
        () async {
      final r = await _cli(
          ['transcribe', '-m', 'model.bin', 'no-such-audio-file-12345.wav']);
      expect(r.exitCode, 64);
      expect('${r.stderr}', contains('not found'));
    });

    test('--vad without --vad-model explains itself', () async {
      final r =
          await _cli(['transcribe', '-m', 'model.bin', '--vad', 'a.wav']);
      expect(r.exitCode, 64);
      expect('${r.stderr}', contains('vad-model'));
    });

    test('watermark embed rejects a missing --out before doing the work',
        () async {
      final r = await _cli(['watermark', 'a.wav']);
      expect(r.exitCode, 64);
      expect('${r.stderr}', contains('--out'));
    });
  });
}
