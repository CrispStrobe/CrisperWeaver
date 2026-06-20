// Smoke test for the CLI (PLAN §9.4). Spawns `dart run bin/crisperweaver.dart`
// for paths that need no model/dylib — usage, command listing, arg
// validation. The per-capability behaviour (transcribe/vad/lid/punctuate/
// translate/synthesize/watermark) is covered live in the *_live_test.dart
// files against the same binding the CLI wraps. Tagged `slow` because
// `dart run` JIT-compiles the entrypoint (seconds), keeping the default
// `flutter test` fast.

@Tags(['slow'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<ProcessResult> _cli(List<String> args) =>
    Process.run('dart', ['run', 'bin/crisperweaver.dart', ...args]);

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
  });
}
