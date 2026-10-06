// Live check of the system-audio input the live-captions screen offers:
// SystemAudioCaptureService captures what plays through the default sink
// (Linux: `parec` on its monitor) while a recording is played into it, and
// the captured PCM is then transcribed. Skipped unless a PulseAudio server
// is reachable and the env names a recording + recogniser:
//
//   CRISPASR_TEST_PULSE=1               a PulseAudio/PipeWire server is up
//   CRISPASR_TEST_LIVE_WAV              recording to play (16 kHz mono WAV)
//   CRISPASR_TEST_LIVE_ASR_MODEL        parakeet-tdt-0.6b-v3 GGUF
//
// A private server works: `pulseaudio -n --daemonize --load=
// module-native-protocol-unix --load="module-null-sink sink_name=talk"`
// under a scratch XDG_RUNTIME_DIR, then `pactl set-default-sink talk`.
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crisper_weaver/native/crispasr_import.dart' as crispasr;
import 'package:crisper_weaver/services/system_audio_capture_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = Platform.environment;
  final wav = env['CRISPASR_TEST_LIVE_WAV'];
  final asr = env['CRISPASR_TEST_LIVE_ASR_MODEL'];
  final skip = !Platform.isLinux
      ? 'Linux only (parec)'
      : env['CRISPASR_TEST_PULSE'] == null || wav == null || asr == null
          ? 'set CRISPASR_TEST_PULSE, CRISPASR_TEST_LIVE_WAV and '
              'CRISPASR_TEST_LIVE_ASR_MODEL'
          : null;

  test('system audio: what plays through the default sink is captured and '
      'transcribable', () async {
    final svc = SystemAudioCaptureService();
    expect(await svc.isSupported(), isTrue, reason: 'parec on PATH');
    final frames = await svc.start();
    final chunks = <Float32List>[];
    final sub = frames.listen(chunks.add);
    // Let parec attach before the playback starts.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final play = await Process.run('paplay', [wav!]);
    expect(play.exitCode, 0, reason: 'paplay: ${play.stderr}');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await svc.stop();
    await sub.cancel();

    final n = chunks.fold<int>(0, (a, c) => a + c.length);
    final pcm = Float32List(n);
    var o = 0;
    for (final c in chunks) {
      pcm.setRange(o, o + c.length, c);
      o += c.length;
    }
    var peak = 0.0;
    for (final x in pcm) {
      peak = math.max(peak, x.abs());
    }
    stdout.writeln('captured ${(n / 16000).toStringAsFixed(1)} s, peak '
        '${peak.toStringAsFixed(3)}');
    expect(n / 16000, greaterThan(20), reason: 'the whole recording');
    expect(peak, greaterThan(0.05), reason: 'speech, not silence');

    final session = crispasr.CrispasrSession.openWithParams(asr!,
        nThreads: 3, backend: 'parakeet');
    final text = session
        .transcribe(pcm)
        .map((s) => s.text)
        .join(' ')
        .toLowerCase();
    session.close();
    stdout.writeln(text);
    expect(text, contains('tagesordnung'));
    expect(text, contains('questions'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
}
