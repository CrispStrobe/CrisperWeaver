// Run against the installed macOS app's dylib and downloaded Parakeet model:
// DYLD_LIBRARY_PATH=/Applications/crisper_weaver.app/Contents/Frameworks \
// CRISPASR_TEST_LIVE_ASR_MODEL=/path/to/parakeet-tdt-0.6b-v3-q4_k.gguf \
// CRISPASR_TEST_LIVE_VAD_MODEL=/path/to/silero-v6.2.0-ggml.bin \
// <flutter-sdk>/bin/cache/dart-sdk/bin/dart \
// <flutter-sdk>/bin/cache/flutter_tools.snapshot test \
// test/live_translate/fixed_german_live_test.dart -r expanded
// Launch Dart directly on macOS: Flutter's shell shebang strips DYLD variables.
@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crisper_weaver/services/live_translate/live_asr_worker.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _fixture() {
  final bytes = File(Platform.environment['CRISPASR_TEST_LIVE_WAV'] ??
          'web-e2e/fixtures/fleurs-de_de.wav')
      .readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  for (var off = 12; off + 8 <= bytes.length;) {
    final size = data.getUint32(off + 4, Endian.little);
    if (String.fromCharCodes(bytes.sublist(off, off + 4)) == 'data') {
      // Two seconds of trailing silence lets the worker finish the utterance.
      return Float32List(size ~/ 2 + 32000)
        ..setRange(0, size ~/ 2, [
          for (var i = 0; i < size ~/ 2; i++)
            data.getInt16(off + 8 + i * 2, Endian.little) / 32768.0,
        ]);
    }
    off += 8 + size + (size & 1);
  }
  throw StateError('Missing WAV data');
}

void main() {
  final model = Platform.environment['CRISPASR_TEST_LIVE_ASR_MODEL'];
  final backend =
      Platform.environment['CRISPASR_TEST_LIVE_ASR_BACKEND'] ?? 'parakeet';
  test('fixed German stays German with $backend in the live worker', () async {
    final events = ReceivePort();
    final ready = Completer<void>();
    final stopped = Completer<void>();
    final units = <Map<Object?, Object?>>[];
    final errors = <String>[];
    SendPort? commands;
    final sub = events.listen((event) {
      if (event is SendPort) {
        commands = event;
      } else if (event is Map) {
        switch (event['type']) {
          case 'ready':
            expect(event['backend'], backend);
            if (backend == 'nemotron' ||
                (backend == 'moonshine-onnx' && model!.contains('streaming'))) {
              expect(event['streamingMode'], 'native streaming');
            }
            ready.complete();
          case 'error':
            errors.add('${event['message']}');
            if (!ready.isCompleted) ready.completeError(errors.last);
          case 'unit':
            units.add(event);
            stdout.writeln(
                '[${event['lang']} utt=${event['utt']}] ${event['text']}');
          case 'stopped':
            stopped.complete();
        }
      }
    });
    final worker = await Isolate.spawn(
      liveAsrWorkerEntry,
      LiveAsrArgs(
        readyPort: events.sendPort,
        modelPath: model!,
        libPath: Platform.environment['CRISPASR_LIB'],
        backend: backend,
        lidMode: 'fixed',
        fixedSource: 'de',
        expectedSources: const ['de'],
        vadModelPath: Platform.environment['CRISPASR_TEST_LIVE_VAD_MODEL'],
        nThreads: 3,
        useGpu: backend != 'nemotron' && backend != 'moonshine-onnx',
      ),
    );
    try {
      await ready.future.timeout(const Duration(minutes: 3));
      final pcm = _fixture();
      for (var off = 0; off < pcm.length; off += 1600) {
        final end = (off + 1600).clamp(0, pcm.length);
        commands!.send({
          'type': 'audio',
          'pcm': Float32List.fromList(pcm.sublist(off, end)),
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      commands!.send({'type': 'stop'});
      await stopped.future.timeout(const Duration(minutes: 3));
      expect(errors, isEmpty);
      expect(units, isNotEmpty);
      expect(units.every((u) => u['lang'] == 'de'), isTrue);
      final text = units.map((u) => u['text']).join(' ').toLowerCase();
      expect(text.trim(), isNotEmpty);
      if (Platform.environment['CRISPASR_TEST_LIVE_WAV'] == null) {
        expect(units.map((u) => u['utt']).toSet(), hasLength(1),
            reason: 'VAD overlap must not invent pauses in this sentence');
        if (backend == 'parakeet') expect(text, contains('starke winde'));
        expect(text, contains('niederschläge'));
        expect(text, contains('wasserhosen'));
      } else {
        final expected = Platform.environment['CRISPASR_TEST_LIVE_EXPECT'];
        if (expected != null) expect(text, contains(expected.toLowerCase()));
        final maxUtterances =
            Platform.environment['CRISPASR_TEST_LIVE_MAX_UTTERANCES'];
        if (maxUtterances != null) {
          expect(units.map((u) => u['utt']).toSet().length,
              lessThanOrEqualTo(int.parse(maxUtterances)),
              reason: 'Quiet continuous speech must not become false pauses');
        }
      }
    } finally {
      worker.kill(priority: Isolate.immediate);
      await sub.cancel();
      events.close();
    }
  },
      skip: model == null ? 'set CRISPASR_TEST_LIVE_ASR_MODEL' : null,
      timeout: const Timeout(Duration(minutes: 8)));
}
