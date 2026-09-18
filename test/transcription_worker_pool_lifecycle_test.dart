import 'dart:isolate';
import 'dart:typed_data';

import 'package:crisper_weaver/services/transcription_worker.dart';
import 'package:crisper_weaver/services/transcription_worker_pool.dart';
import 'package:flutter_test/flutter_test.dart';

// Real isolates and ports, but no native library/model dependency.
Future<void> fakeWorkerEntry(TranscriptionWorkerArgs args) async {
  final commands = ReceivePort();
  args.readySendPort.send(commands.sendPort);
  args.readySendPort.send({'type': 'ready'});
  await for (final raw in commands) {
    final command = raw as Map;
    if (command['type'] == 'shutdown') {
      commands.close();
      return;
    }
    final reply = command['replyPort'] as SendPort;
    final mode = (command['samples'] as Float32List).first.toInt();
    if (mode == 2) Isolate.exit();
    if (mode == 1) {
      reply.send({'type': 'error', 'message': 'invalid grammar'});
    } else {
      reply.send({
        'type': 'done',
        'segments': [
          {'text': 'ok', 'startTime': 0.0, 'endTime': 1.0},
        ],
      });
    }
  }
}

Future<TranscriptionWorkerPool> spawnPool({int count = 1}) async {
  final pool = await TranscriptionWorkerPool.spawn(
    count: count,
    modelPath: 'fake',
    backend: 'fake',
    workerEntry: fakeWorkerEntry,
  );
  addTearDown(pool.shutdown);
  return pool;
}

void main() {
  test('unexpected isolate exit fails active dispatch instead of hanging', () async {
    final pool = await spawnPool();
    await expectLater(
      pool.dispatch(samples: Float32List.fromList([2]))
          .timeout(const Duration(seconds: 2)),
      throwsA(isA<TranscriptionWorkerException>()),
    );
    expect(pool.aliveCount, 0);
  });

  test('ordinary job errors keep worker available for queued requests', () async {
    final pool = await spawnPool();
    final failed = expectLater(
      pool.dispatch(samples: Float32List.fromList([1])),
      throwsA(isA<TranscriptionWorkerException>()),
    );
    final next = pool.dispatch(samples: Float32List.fromList([0]));
    await failed;
    expect(pool.aliveCount, 1);
    expect((await next.timeout(const Duration(seconds: 2))).single.text, 'ok');
  });
}
