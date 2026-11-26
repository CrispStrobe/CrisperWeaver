import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisper_weaver/utils/ai_text_provenance.dart';

void main() {
  final provenance = AiTextProvenance(
    kind: 'summary',
    generatorVersion: 'test',
    provider: 'local',
    model: 'model-->.gguf',
    modelIdentifierSource: 'local-model-filename',
    generatedAt: DateTime.utc(2026, 11, 26),
  );

  test(
    'portable metadata describes and hashes this exact generated output',
    () {
      const text = '## Decisions\n- Keep the original wording.\n';
      final output = provenance.annotateMarkdown(text);
      final marker = RegExp(
        r'^<!-- crisperweaver-provenance: (.*?) -->\n\n',
        dotAll: true,
      ).firstMatch(output)!;
      final receipt = jsonDecode(marker.group(1)!) as Map<String, dynamic>;
      expect(receipt['model'], 'model-->.gguf');
      expect(receipt['signature'], 'unsigned');
      expect(receipt['ai_generated'], true);
      expect(
        receipt['content_sha256'],
        sha256.convert(utf8.encode(text)).toString(),
      );
      expect(output.substring(marker.end), text);
      expect('-->'.allMatches(output.substring(0, marker.end)).length, 1);
      expect(provenance.annotateMarkdown('  '), '');
    },
  );

  test(
    'endpoint attribution never exports credentials, tenant paths or hosts',
    () {
      expect(
        AiTextProvenance.providerForEndpoint(
          'https://user:secret@api.openai.com/private?key=secret',
        ),
        'OpenAI',
      );
      expect(
        AiTextProvenance.providerForEndpoint(
          'https://private-customer.example/tenant/person?key=secret',
        ),
        'configured-endpoint',
      );
      expect(
        AiTextProvenance.providerForEndpoint(
          'https://api.studio.nebius.com/v1/chat/completions',
        ),
        'Nebius',
      );
      expect(
        AiTextProvenance.providerForEndpoint(
          'https://api.openai.com.example/v1/chat/completions',
        ),
        'configured-endpoint',
      );
      expect(
        AiTextProvenance.localModelName(r'C:\Users\Person\private\model.gguf'),
        'model.gguf',
      );
      expect(
        AiTextProvenance.localModelName('/home/person/models/model.gguf'),
        'model.gguf',
      );
    },
  );
}
