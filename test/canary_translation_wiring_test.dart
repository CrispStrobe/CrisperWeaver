import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pooled Canary transcription forwards the selected target language', () {
    final source = File('lib/engines/crispasr_engine.dart').readAsStringSync();

    final helperStart = source.indexOf(
      '_runSessionTranscriptionViaPool(\n    Float32List pcm',
    );
    expect(helperStart, greaterThanOrEqualTo(0));
    final helperEnd = source.indexOf(
      '\n  List<TranscriptionSegment> _mapWhisperSegments',
      helperStart,
    );
    expect(helperEnd, greaterThan(helperStart));
    final helper = source.substring(helperStart, helperEnd);

    expect(helper, contains('String? targetLanguage,'));
    expect(helper, contains('targetLanguage: targetLanguage,'));

    final callPattern = RegExp(
      r'_runSessionTranscriptionViaPool\(\s*trimmed,\s*'
      r'language: language,\s*targetLanguage: targetLanguage,',
      multiLine: true,
    );
    expect(
      callPattern.allMatches(source).length,
      greaterThanOrEqualTo(2),
      reason: 'both pooled transcribe routes must forward the UI target',
    );
  });
}
