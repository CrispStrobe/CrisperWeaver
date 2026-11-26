// Hermetic tests for TranscriptSummarizeService.
//
// Pins the Markdown parser independently of the HTTP path so
// model-output drift surfaces as a clear parser-test diff
// rather than a cryptic end-to-end fail. The HTTP path uses
// MockClient to verify the request envelope + the disabled-
// config + non-2xx error surfaces.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crisper_weaver/services/cloud_llm_cleanup_service.dart'
    show CloudLlmConfig, CloudLlmHttpException, CloudLlmDisabledException;
import 'package:crisper_weaver/services/transcript_summarize_service.dart';

void main() {
  CloudLlmConfig config(
      {String apiUrl = 'https://api.example.com/v1/chat/completions',
      String apiKey = 'sk-test',
      String model = 'gpt-4o-mini'}) {
    return CloudLlmConfig(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      timeout: const Duration(seconds: 5),
    );
  }

  String chatBody(String content) => jsonEncode(<String, dynamic>{
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
            'finish_reason': 'stop',
          }
        ],
      });

  group('parseMarkdown', () {
    final svc = TranscriptSummarizeService();
    tearDownAll(svc.dispose);

    test('three populated sections split cleanly', () {
      const md = '''
## Action Items
- Send the report (Alice)
- Schedule next sync (Bob)

## Key Topics
- Q3 hiring plan
- Roadmap for Project Cobalt

## Decisions
- Approve the v0.5 release candidate
''';
      final r = svc.parseMarkdown(md);
      expect(r.actionItems,
          ['Send the report (Alice)', 'Schedule next sync (Bob)']);
      expect(r.keyTopics,
          ['Q3 hiring plan', 'Roadmap for Project Cobalt']);
      expect(r.decisions, ['Approve the v0.5 release candidate']);
      expect(r.rawMarkdown, md);
    });

    test('"None" placeholder yields an empty list', () {
      const md = '''
## Action Items
- None

## Key Topics
- Catch-up

## Decisions
- None
''';
      final r = svc.parseMarkdown(md);
      expect(r.actionItems, isEmpty);
      expect(r.keyTopics, ['Catch-up']);
      expect(r.decisions, isEmpty);
    });

    test('case-insensitive header match', () {
      const md = '''
## ACTION ITEMS
- thing
## key topics
- another
## decisions
- a third
''';
      final r = svc.parseMarkdown(md);
      expect(r.actionItems, ['thing']);
      expect(r.keyTopics, ['another']);
      expect(r.decisions, ['a third']);
    });

    test('asterisk and numbered bullets accepted', () {
      const md = '''
## Action Items
* dash
* dash-dash
## Key Topics
1. one
2. two
## Decisions
- normal
''';
      final r = svc.parseMarkdown(md);
      expect(r.actionItems, ['dash', 'dash-dash']);
      expect(r.keyTopics, ['one', 'two']);
      expect(r.decisions, ['normal']);
    });

    test('rows before any header are silently dropped', () {
      const md = '''
- pre-header noise
- more noise

## Action Items
- real
''';
      final r = svc.parseMarkdown(md);
      expect(r.actionItems, ['real']);
      expect(r.keyTopics, isEmpty);
      expect(r.decisions, isEmpty);
    });

    test('missing sections yield empty lists', () {
      const md = '''
## Action Items
- only this section
''';
      final r = svc.parseMarkdown(md);
      expect(r.actionItems, ['only this section']);
      expect(r.keyTopics, isEmpty);
      expect(r.decisions, isEmpty);
    });

    test('SummaryResult.isEmpty is true when nothing parsed', () {
      final r = svc.parseMarkdown('## Action Items\n- None\n');
      expect(r.isEmpty, true);
    });

    test('preserves rawMarkdown verbatim', () {
      const md = '## Action Items\n- a\n\n## Key Topics\n- b\n';
      final r = svc.parseMarkdown(md);
      expect(r.rawMarkdown, md);
    });
  });

  group('summarize HTTP path', () {
    test(
        'successful generation captures portable provenance; parsing does not invent it',
        () async {
      final svc = TranscriptSummarizeService(
        client: MockClient(
          (_) async => http.Response(chatBody('## Key Topics\n- Budget'), 200),
        ),
      );
      addTearDown(svc.dispose);
      final result = await svc.summarize(
        transcript: 'Private source text',
        kinds: {SummaryKind.keyTopics},
        config: config(
          apiUrl: 'https://tenant.example/private?key=secret',
          apiKey: 'sk-secret',
        ),
      );
      expect(result.provenance?.provider, 'configured-endpoint');
      expect(result.provenance?.model, 'gpt-4o-mini');
      expect(result.portableMarkdown, contains('crisperweaver-provenance:'));
      expect(result.portableMarkdown, contains('AI-generated:'));
      for (final secret in [
        'sk-secret',
        'tenant.example',
        'Private source text',
      ]) {
        expect(result.portableMarkdown, isNot(contains(secret)));
      }
      final parsed = svc.parseMarkdown('## Key Topics\n- Old text');
      expect(parsed.provenance, isNull);
      expect(parsed.portableMarkdown, isNot(contains('generated_at')));
      expect(parsed.portableMarkdown, '## Key Topics\n- Old text');
    });

    test('disabled config throws CloudLlmDisabledException', () async {
      final svc = TranscriptSummarizeService(
        client: MockClient((_) async {
          throw StateError('should not be called');
        }),
      );
      addTearDown(svc.dispose);
      await expectLater(
        svc.summarize(
          transcript: 'hello',
          kinds: {SummaryKind.actionItems},
          config: const CloudLlmConfig(
            apiUrl: '',
            apiKey: '',
            model: 'gpt-4o-mini',
          ),
        ),
        throwsA(isA<CloudLlmDisabledException>()),
      );
    });

    test('empty transcript short-circuits without HTTP', () async {
      var calls = 0;
      final svc = TranscriptSummarizeService(client: MockClient((_) async {
        calls++;
        return http.Response(chatBody('## Action Items\n- x'), 200);
      }));
      addTearDown(svc.dispose);
      final r = await svc.summarize(
        transcript: '   ',
        kinds: {SummaryKind.actionItems},
        config: config(),
      );
      expect(r.isEmpty, true);
      expect(calls, 0);
    });

    test('empty kinds short-circuits without HTTP', () async {
      var calls = 0;
      final svc = TranscriptSummarizeService(client: MockClient((_) async {
        calls++;
        return http.Response(chatBody(''), 200);
      }));
      addTearDown(svc.dispose);
      final r = await svc.summarize(
        transcript: 'some words',
        kinds: const {},
        config: config(),
      );
      expect(r.isEmpty, true);
      expect(calls, 0);
    });

    test('happy path — request envelope + parsed sections', () async {
      late Map<String, dynamic> capturedBody;
      late String capturedAuth;
      final svc = TranscriptSummarizeService(
          client: MockClient((req) async {
        capturedAuth = req.headers['Authorization'] ?? '';
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            chatBody('## Action Items\n- a\n## Key Topics\n- t'), 200);
      }));
      addTearDown(svc.dispose);
      final r = await svc.summarize(
        transcript: 'long transcript text',
        kinds: const {SummaryKind.actionItems, SummaryKind.keyTopics},
        config: config(apiKey: 'sk-xyz'),
      );
      expect(capturedAuth, 'Bearer sk-xyz');
      expect(capturedBody['model'], 'gpt-4o-mini');
      expect(capturedBody['temperature'], 0.0);
      expect(capturedBody['max_tokens'], 4096);
      final msgs = (capturedBody['messages'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(msgs, hasLength(2));
      expect(msgs[0]['role'], 'system');
      expect(msgs[1]['role'], 'user');
      expect(msgs[1]['content'], 'long transcript text');
      // Prompt should include the headers for the requested kinds
      // and NOT include the un-requested one (Decisions).
      expect(msgs[0]['content'], contains('## Action Items'));
      expect(msgs[0]['content'], contains('## Key Topics'));
      expect(msgs[0]['content'], isNot(contains('## Decisions')));
      expect(r.actionItems, ['a']);
      expect(r.keyTopics, ['t']);
      expect(r.decisions, isEmpty);
    });

    test('non-2xx throws CloudLlmHttpException', () async {
      final svc = TranscriptSummarizeService(client: MockClient((_) async {
        return http.Response('{"error":"rate_limited"}', 429);
      }));
      addTearDown(svc.dispose);
      await expectLater(
        svc.summarize(
            transcript: 'hello',
            kinds: {SummaryKind.actionItems},
            config: config()),
        throwsA(isA<CloudLlmHttpException>()
            .having((e) => e.statusCode, 'statusCode', 429)),
      );
    });
  });
}
