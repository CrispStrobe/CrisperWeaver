import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crisper_weaver/services/live_translate/live_asr_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (kind, useVad) in [(2, false), (3, false), (2, true)]) {
    test('stream kind $kind preserves the stop tail (VAD warm-up: $useVad)',
        () async {
      final temp = Directory.systemTemp.createTempSync('cw-stream-worker-');
      final libPath =
          '${temp.path}/stream.${Platform.isMacOS ? 'dylib' : 'so'}';
      final cc = await Process.run('cc', [
        '-shared',
        '-fPIC',
        'test/live_translate/fixtures/stream_recognizer.c',
        '-o',
        libPath
      ]);
      expect(cc.exitCode, 0, reason: '${cc.stderr}');
      final lib = DynamicLibrary.open(libPath);
      int count(String name) =>
          lib.lookupFunction<Int32 Function(), int Function()>(name)();
      final events = ReceivePort();
      final ready = Completer<void>();
      final stopped = Completer<void>();
      final errors = <String>[];
      final units = <String>[];
      SendPort? commands;
      final sub = events.listen((event) {
        if (event is SendPort) commands = event;
        if (event is! Map) return;
        switch (event['type']) {
          case 'ready':
            expect(event['streamingMode'],
                kind == 2 ? 'native streaming' : 'prefix streaming');
            ready.complete();
          case 'error':
            errors.add('${event['message']}');
            if (!ready.isCompleted) ready.completeError(errors.last);
          case 'unit':
            units.add('${event['text']}');
          case 'stopped':
            stopped.complete();
        }
      });
      final worker = await Isolate.spawn(
          liveAsrWorkerEntry,
          LiveAsrArgs(
            readyPort: events.sendPort,
            modelPath: kind == 2 ? 'fixture' : 'prefix',
            backend: '',
            libPath: libPath,
            vadModelPath: useVad ? 'fixture' : null,
            fixedSource: 'de',
            useGpu: false,
          ));
      try {
        await ready.future.timeout(const Duration(seconds: 30));
        final frames = useVad ? 60 : 12;
        for (var i = 0; i < frames; i++) {
          commands!.send({
            'type': 'audio',
            'pcm': Float32List(1600)..fillRange(0, 1600, .1)
          });
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        // Last 200 ms arrive after the second 500 ms tick; Stop must feed them.
        commands!.send({'type': 'stop'});
        await stopped.future.timeout(const Duration(seconds: 30));
        expect(errors, isEmpty);
        expect(count('fixture_opens'), 1);
        if (!useVad) expect(count('fixture_samples'), frames * 1600);
        expect(count('fixture_flushes'), 1);
        expect(count('fixture_closes'), 1);
        expect(units.join(' '),
            'Das ist Deutsch. Auch die letzten Wörter bleiben.');
      } finally {
        worker.kill(priority: Isolate.immediate);
        await sub.cancel();
        events.close();
        temp.deleteSync(recursive: true);
      }
    }, skip: Platform.isWindows ? 'requires a C compiler' : null);
  }
}
