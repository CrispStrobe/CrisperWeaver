// Live check of a speech-translation recogniser in the live-captions loop:
// Index-Echo decodes each utterance once and returns transcript +
// translation per cue; LiveAsrWorker must emit units that carry the
// translation, so the translator is not asked for that target again.
//
//   CRISPASR_TEST_INDEX_ECHO_MODEL  index-echo-2b-q8_0.gguf, with its decoder
//                                   (and ggml-silero-v6.2.0.bin) beside it
//   CRISPASR_TEST_ZH_WAV            Chinese speech, 16 kHz mono WAV
//
// About 40x slower than real time on a CPU — a GPU build is what makes it
// usable live; this checks the wiring, not the speed.
@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crisper_weaver/services/live_translate/live_asr_worker.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _wav(String path) {
  final b = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(b);
  var off = 12;
  while (off + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(off, off + 4));
    final len = bd.getUint32(off + 4, Endian.little);
    if (id == 'data') {
      final out = Float32List(len ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = bd.getInt16(off + 8 + i * 2, Endian.little) / 32768.0;
      }
      return out;
    }
    off += 8 + len + (len & 1);
  }
  throw StateError('no data chunk in $path');
}

void main() {
  final env = Platform.environment;
  final model = env['CRISPASR_TEST_INDEX_ECHO_MODEL'];
  final wav = env['CRISPASR_TEST_ZH_WAV'];
  final skip = model == null || wav == null
      ? 'set CRISPASR_TEST_INDEX_ECHO_MODEL and CRISPASR_TEST_ZH_WAV'
      : null;

  test('Index-Echo: each Chinese cue arrives with its English translation',
      () async {
    final units = <Map<Object?, Object?>>[];
    final ready = Completer<void>();
    final stopped = Completer<void>();
    SendPort? port;
    final events = ReceivePort();
    events.listen((m) {
      if (m is SendPort) {
        port = m;
      } else if (m is Map) {
        switch (m['type']) {
          case 'ready':
            ready.complete();
          case 'error':
            if (!ready.isCompleted) ready.completeError('${m['message']}');
          case 'unit':
            units.add(m);
            stdout.writeln('[${m['lang']}] ${m['text']}  ⇒ ${m['translations']}');
          case 'stopped':
            stopped.complete();
        }
      }
    });
    await Isolate.spawn(
        liveAsrWorkerEntry,
        LiveAsrArgs(
          readyPort: events.sendPort,
          modelPath: model!,
          backend: 'index-echo',
          fixedSource: 'zh',
          expectedSources: const ['zh'],
          nThreads: 4,
          directTranslationTarget: 'en',
        ));
    await ready.future.timeout(const Duration(minutes: 10));

    // Feed the clip plus two seconds of silence so the utterance closes on
    // its own pause, not on stop.
    final pcm = _wav(wav!);
    final padded = Float32List(pcm.length + 32000)..setAll(0, pcm);
    for (var pos = 0; pos < padded.length; pos += 1600) {
      final end = (pos + 1600).clamp(0, padded.length);
      port!.send({
        'type': 'audio',
        'pcm': Float32List.fromList(Float32List.sublistView(padded, pos, end)),
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    port!.send({'type': 'stop'});
    await stopped.future.timeout(const Duration(minutes: 30));

    expect(units, isNotEmpty);
    for (final u in units) {
      expect(u['lang'], 'zh');
      final tr = u['translations'] as Map?;
      expect(tr?['en'], isA<String>(),
          reason: 'every cue carries its own English translation');
      expect((tr!['en'] as String).trim(), isNotEmpty);
    }
    final english = units
        .map((u) => (u['translations'] as Map)['en'] as String)
        .join(' ')
        .toLowerCase();
    expect(english, contains('justice'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 45)));
}
