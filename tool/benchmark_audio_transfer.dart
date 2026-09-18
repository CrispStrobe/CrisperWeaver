// Run each mode in a fresh process to compare process-wide peak RSS:
// dart run tool/benchmark_audio_transfer.dart copy 57600000 7
// dart run tool/benchmark_audio_transfer.dart transfer 57600000 7
// dart run tool/benchmark_audio_transfer.dart chunks 57600000 7
// Deterministic PCM fixture, not ASR inference. `chunks` needs a streaming
// consumer: it intentionally does not reassemble a full-length native input.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

void _receive(SendPort ready) {
  final port = ReceivePort();
  ready.send(port.sendPort);
  port.listen((dynamic raw) {
    if (raw == null) {
      port.close();
      return;
    }
    final message = raw as List<Object>;
    final payload = message[0];
    final samples = payload is TransferableTypedData
        ? payload.materialize().asFloat32List()
        : payload as Float32List;
    // Touch every page without making an O(samples) DSP workload dominate
    // the transfer comparison. Source values are all exactly 0.25.
    var checksum = 0.0;
    for (var i = 0; i < samples.length; i += 1024) {
      checksum += samples[i];
    }
    (message[1] as SendPort).send(<Object>[samples.length, checksum]);
  });
}

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'copy' : args[0];
  final count = args.length > 1 ? int.parse(args[1]) : 16000 * 60;
  final rounds = args.length > 2 ? int.parse(args[2]) : 7;
  if (!{'copy', 'transfer', 'chunks'}.contains(mode) ||
      count < 1 ||
      rounds < 1) {
    throw ArgumentError('Usage: [copy|transfer|chunks] positiveSamples rounds');
  }
  final source = Float32List(count);
  source.fillRange(0, count, 0.25);
  final ready = ReceivePort();
  final exited = ReceivePort();
  final exit = exited.first;
  final isolate =
      await Isolate.spawn(_receive, ready.sendPort, onExit: exited.sendPort);
  final commands = await ready.first as SendPort;
  ready.close();
  final responses = ReceivePort();
  final replies = StreamIterator<dynamic>(responses);
  final durations = <int>[];
  final submitDurations = <int>[];
  try {
    // Warm up the same path, including transfer construction. Negative
    // rounds are excluded from timing summaries, but not peak RSS.
    for (var round = -2; round < rounds; round++) {
      final timer = Stopwatch()..start();
      var submitMicros = 0;
      var received = 0;
      final chunkSize = mode == 'chunks' ? 16000 * 30 : count;
      for (var offset = 0; offset < count; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, count);
        final view = Float32List.sublistView(source, offset, end);
        final submit = Stopwatch()..start();
        final Object payload =
            mode == 'copy' ? view : TransferableTypedData.fromList([view]);
        commands.send(<Object>[payload, responses.sendPort]);
        submitMicros += submit.elapsedMicroseconds;
        if (!await replies.moveNext()) throw StateError('worker exited');
        final reply = replies.current as List<dynamic>;
        final length = reply[0] as int;
        final checksum = reply[1] as double;
        if (length != view.length ||
            checksum != ((length + 1023) ~/ 1024) * .25) {
          throw StateError('Transfer changed the PCM fixture');
        }
        received += length;
      }
      if (received != count) throw StateError('Lost samples');
      if (round >= 0) {
        durations.add(timer.elapsedMicroseconds);
        submitDurations.add(submitMicros);
      }
    }
    durations.sort();
    submitDurations.sort();
    stdout.writeln(jsonEncode(<String, Object>{
      'mode': mode,
      'samples': count,
      'payloadBytes': source.lengthInBytes,
      'rounds': rounds,
      'roundTripUs': durations,
      'medianRoundTripUs': durations[durations.length ~/ 2],
      'medianSubmissionUs': submitDurations[submitDurations.length ~/ 2],
      'peakProcessRssBytes': ProcessInfo.maxRss,
      'currentProcessRssBytes': ProcessInfo.currentRss,
      'runtime': Platform.version,
      'scope': 'PCM transport only; chunks require streaming consumer',
    }));
  } finally {
    commands.send(null);
    await exit.timeout(const Duration(seconds: 5), onTimeout: () {
      isolate.kill(priority: Isolate.immediate);
      return null;
    });
    await replies.cancel();
    responses.close();
    exited.close();
  }
}
