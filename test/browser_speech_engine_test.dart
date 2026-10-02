import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisper_weaver/engines/browser_speech_engine.dart';
import 'package:crisper_weaver/services/browser_speech_client.dart';

class _Client extends BrowserSpeechClient {
  _Client({this.text = 'A local result'}) : super('crispasr');
  final String text;
  final operations = <String>[];
  bool failLoad = false;
  @override
  Future<dynamic> request(String operation, Map<String, dynamic> payload,
      {void Function(double)? onProgress}) async {
    operations.add(operation);
    if (operation == 'load' && failLoad) throw StateError('Invalid model');
    if (operation == 'transcribe') {
      return {
        'segments': [
          {'text': text, 'start': 0.0, 'end': 1.0}
        ]
      };
    }
    return true;
  }
}

void main() {
  test('browser model emotion tags are stripped before callbacks and output',
      () async {
    final engine = BrowserSpeechEngine('crispasr',
        client: _Client(text: '<|HAPPY|>A local result<|ANGRY|>'));
    await engine.initialize();
    await engine.loadModel('tiny');
    final emitted = <String>[];
    final result = await engine.transcribe(Float32List(16000),
        onSegment: (segment) => emitted.add(segment.text));
    expect(result.fullText, 'A local result');
    expect(result.segments.single.text, 'A local result');
    expect(emitted, ['A local result']);
  });

  test('failed replacement cannot transcribe using a stale model', () async {
    final client = _Client();
    final engine = BrowserSpeechEngine('crispasr', client: client);
    await engine.initialize();
    await engine.loadModel('tiny');
    client.failLoad = true;
    await expectLater(engine.loadModel('base'), throwsStateError);
    expect(engine.currentModelId, isNull);
    await expectLater(engine.transcribe(Float32List(16000)), throwsStateError);
    expect(client.operations, isNot(contains('transcribe')));
  });

  test('unsupported diarization fails before inference', () async {
    final client = _Client();
    final engine = BrowserSpeechEngine('crispasr', client: client);
    await engine.initialize();
    await engine.loadModel('tiny');
    await expectLater(
        engine.transcribe(Float32List(16000), enableSpeakerDiarization: true),
        throwsUnsupportedError);
    expect(client.operations, isNot(contains('transcribe')));
  });

  test('translated output retains provenance and source timestamps', () async {
    final engine = BrowserSpeechEngine('crispasr', client: _Client());
    await engine.initialize();
    await engine.loadModel('tiny');
    final result = await engine.transcribe(Float32List(32000),
        translate: true, startOffsetSec: 1);
    expect(result.segments.single.startTime, 1);
    expect(result.segments.single.endTime, 2);
    expect(result.segments.single.metadata['generated'], 'translation');
    expect(result.segments.single.metadata['local'], true);
  });
}
