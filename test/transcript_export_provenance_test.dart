import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/utils/file_utils.dart';

void main() {
  test('known model transcription is processing, not invented source speech',
      () {
    final segment = TranscriptionSegment.fromModelText(
      rawText: 'Words from the recording',
      startTime: 0,
      endTime: 1,
      metadata: {'internal_endpoint': 'https://private.example/?key=secret'},
    );
    expect(segment.isGenerated, isFalse);
    expect(segment.metadata['ai_processed'], true);

    final encoded = FileUtils.generateJsonContent([segment]);
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final exported = (json['segments'] as List).single as Map<String, dynamic>;
    expect(exported['metadata'], {'ai_processed': true});
    expect(json['_disclosure'], contains('AI-transcribed'));
    expect(json.containsKey('_content'), isFalse);
    expect(encoded, isNot(contains('secret')));
    expect(encoded, isNot(contains('private.example')));
    expect(encoded, isNot(contains('synthetic speech')));
  });

  test('generated flags survive JSON export even without a prose notice', () {
    final segment = TranscriptionSegment.fromModelText(
      rawText: 'A model answer',
      startTime: 0,
      endTime: 1,
      metadata: {'generated': 'audio-qa'},
    );
    final json = jsonDecode(FileUtils.generateJsonContent(
      [segment],
      syntheticDisclosure: false,
    )) as List;
    expect((json.single as Map)['metadata'], {
      'generated': 'audio-qa',
      'ai_processed': true,
    });
  });

  test('imported and historical segments acquire no inferred AI attribution',
      () {
    const segment = TranscriptionSegment(
      text: 'Imported words',
      startTime: 0,
      endTime: 1,
    );
    final json = jsonDecode(FileUtils.generateJsonContent([segment])) as Map;
    expect(((json['segments'] as List).single as Map).containsKey('metadata'),
        false);
    expect(json['_disclosure'],
        contains('origin and review status are not recorded'));
    expect(json.containsKey('_content'), false);
  });
}
