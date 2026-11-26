import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/local_llm_backend.dart';
import 'package:crisper_weaver/services/local_llm_cleanup_service.dart';
import 'package:crisper_weaver/services/transcript_summarize_service.dart';

class _SummaryBackend implements LocalLlmBackend {
  _SummaryBackend({this.fail = false});
  final bool fail;
  @override
  bool isOpen = false;

  @override
  Future<void> open(LocalLlmConfig config) async => isOpen = true;

  @override
  Future<String> generate({
    required List<Map<String, String>> messages,
    required Map<String, Object?> generateParams,
    int? abortFlagAddress,
  }) async {
    if (fail) throw StateError('generation failed');
    return '## Key Topics\n- Local summary';
  }

  @override
  Stream<String> generateStream({
    required List<Map<String, String>> messages,
    required Map<String, Object?> generateParams,
    int? abortFlagAddress,
  }) async* {
    yield '## Key Topics\n';
    if (fail) throw StateError('generation failed');
    yield '- Local summary';
  }

  @override
  Future<int?> countTokens(
          {required List<Map<String, String>> messages}) async =>
      null;
  @override
  Future<void> reset() async {}
  @override
  Future<void> dispose() async => isOpen = false;
}

void main() {
  const config = LocalLlmConfig(modelPath: '/home/person/private/model.gguf');

  for (final streaming in [false, true]) {
    test(
        'successful local summary has portable provenance (streaming=$streaming)',
        () async {
      final service =
          TranscriptSummarizeService(localBackend: _SummaryBackend());
      addTearDown(service.dispose);
      final deltas = <String>[];
      final result = await service.summarizeLocal(
        transcript: 'Private input words',
        kinds: {SummaryKind.keyTopics},
        config: config,
        onToken: streaming ? deltas.add : null,
      );
      expect(result.provenance?.provider, 'local');
      expect(result.provenance?.model, 'model.gguf');
      expect(result.provenance?.modelIdentifierSource, 'local-model-filename');
      expect(result.portableMarkdown, contains('crisperweaver-provenance:'));
      expect(result.portableMarkdown, contains('AI-generated:'));
      expect(result.portableMarkdown, isNot(contains('/home/person')));
      expect(result.portableMarkdown, isNot(contains('Private input words')));
      if (streaming) expect(deltas.join(), result.rawMarkdown);
    });
  }

  test('failed generation does not return a completed summary receipt',
      () async {
    final service =
        TranscriptSummarizeService(localBackend: _SummaryBackend(fail: true));
    addTearDown(service.dispose);
    await expectLater(
      service.summarizeLocal(
        transcript: 'Source words',
        kinds: {SummaryKind.keyTopics},
        config: config,
      ),
      throwsStateError,
    );
  });
}
