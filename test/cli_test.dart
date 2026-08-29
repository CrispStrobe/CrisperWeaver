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

  // =====================================================================
  // CLI-level TTS → ASR roundtrip (opt-in).
  //
  // test/tts_asr_roundtrip_live_test.dart proves the *engine* survives a
  // roundtrip. This proves the CLI does — which is not the same claim,
  // because `synthesize` does a pile of work the engine path never sees:
  // the Art. 50(4) beep, the spread-spectrum watermark (with a Dart
  // fallback when the native embed didn't take), the LIST/INFO
  // provenance chunk and a C2PA manifest are all spliced into the WAV
  // before it hits disk. Every one of those edits the container or the
  // samples. If any of them corrupts the audio — a provenance chunk
  // written where the decoder expects `data`, a watermark loud enough to
  // mask speech — the words stop coming back, and only a roundtrip
  // through the real binary can tell us.
  //
  // Self-skips unless CRISPASR_TEST_KOKORO_MODEL, CRISPASR_TEST_KOKORO_VOICE
  // and CRISPASR_TEST_WHISPER_MODEL all point at files on disk. Models are
  // used from their env paths — nothing is copied anywhere.
  // =====================================================================
  group('crisperweaver CLI roundtrip (opt-in)', () {
    String? env(String name) {
      final v = Platform.environment[name];
      return (v != null && v.isNotEmpty && File(v).existsSync()) ? v : null;
    }

    final kokoro = env('CRISPASR_TEST_KOKORO_MODEL');
    final voice = env('CRISPASR_TEST_KOKORO_VOICE');
    final whisper = env('CRISPASR_TEST_WHISPER_MODEL');

    final skip = kokoro == null
        ? 'set CRISPASR_TEST_KOKORO_MODEL to a kokoro-82m-*.gguf'
        : voice == null
            ? 'set CRISPASR_TEST_KOKORO_VOICE to a kokoro-voice-*.gguf'
            : whisper == null
                ? 'set CRISPASR_TEST_WHISPER_MODEL to a ggml-*.bin'
                : null;

    test('synthesize → transcribe preserves the spoken words', () async {
      final tmp = Directory.systemTemp.createTempSync('cw_cli_roundtrip_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {
          // A leaked temp dir is not worth failing a live run over.
        }
      });
      final wav = '${tmp.path}/spoken.wav';
      const phrase = 'The quick brown fox jumps over the lazy dog.';
      const salient = ['quick', 'brown', 'fox', 'jumps', 'lazy', 'dog'];

      // `--voice` is the only way the CLI can hand kokoro its voicepack.
      // A `.gguf` voicepack is a catalogue voice, so it needs no
      // --i-have-rights attestation — but it still triggers the Art. 50(4)
      // beep, which would be the first thing whisper hears. Suppress just
      // the beep with --disclaimer-override so the ASR leg scores speech
      // rather than a tone; the watermark, LIST/INFO provenance and C2PA
      // manifest all still go into the file, which is precisely the part
      // of the pipeline this test exists to put audio through.
      final synth = await _cli([
        'synthesize',
        '-m', kokoro!,
        '--voice', voice!,
        '--disclaimer-override',
        'automated regression fixture, never distributed',
        '-o', wav,
        phrase,
      ]);
      expect(synth.exitCode, 0,
          reason: 'synthesize failed: ${synth.stderr}');
      expect(File(wav).existsSync(), isTrue,
          reason: 'synthesize reported success but wrote no WAV');
      // 44 bytes is a bare header. The marking pipeline adds chunks, so
      // anything near that means no samples made it through.
      expect(File(wav).lengthSync(), greaterThan(16000),
          reason: 'the synthesized WAV is implausibly small '
              '(${File(wav).lengthSync()} bytes)');
      expect('${synth.stdout}', contains('synthesized'),
          reason: 'synthesize did not report what it wrote: ${synth.stdout}');

      final asr = await _cli(['transcribe', '-m', whisper!, '-l', 'en', wav]);
      expect(asr.exitCode, 0, reason: 'transcribe failed: ${asr.stderr}');

      // Case- and punctuation-insensitive, with a naive plural stem —
      // the same scoring the engine-level roundtrip uses. An exact match
      // would be a flake generator through two neural models.
      String stem(String w) =>
          (w.length > 3 && w.endsWith('s') && !w.endsWith('ss'))
              ? w.substring(0, w.length - 1)
              : w;
      final got = '${asr.stdout}'
          .toLowerCase()
          .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
          .split(' ')
          .where((t) => t.isNotEmpty)
          .map(stem)
          .toSet();
      final hits = salient.map(stem).where(got.contains).length;
      final score = hits / salient.length;
      printOnFailure('CLI roundtrip transcript: "${asr.stdout}"');
      expect(score, greaterThanOrEqualTo(0.6),
          reason: 'only ${(score * 100).round()}% of $salient survived the '
              'CLI synthesize → transcribe roundtrip (need 60%); '
              'transcript was "${asr.stdout}"');
    }, skip: skip, timeout: const Timeout(Duration(minutes: 15)));
  });
}
