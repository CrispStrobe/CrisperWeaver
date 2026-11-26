import 'dart:convert';

import 'package:crypto/crypto.dart';

/// An unsigned receipt created after a successful text generation. It records
/// the actual operation and configuration, never guesses the origin of old or
/// imported text. This is application metadata, not a C2PA claim or watermark.
class AiTextProvenance {
  const AiTextProvenance({
    required this.kind,
    required this.generatorVersion,
    required this.provider,
    required this.model,
    required this.modelIdentifierSource,
    required this.generatedAt,
  });

  final String kind;
  final String generatorVersion;
  final String provider;
  final String model;
  final String modelIdentifierSource;
  final DateTime generatedAt;

  Map<String, Object> toJson(String content) => {
        'schema': 'urn:crisperweaver:ai-text-provenance:1',
        'generator': 'CrisperWeaver',
        'generator_version': generatorVersion,
        'content_type': kind,
        'ai_generated': true,
        'provider': provider,
        'model': model,
        'model_identifier_source': modelIdentifierSource,
        'generated_at': generatedAt.toUtc().toIso8601String(),
        'content_sha256': sha256.convert(utf8.encode(content)).toString(),
        'signature': 'unsigned',
      };

  /// Travels with copied Markdown without changing its displayed content.
  /// The caller also includes a visible disclosure. Formatting, edits or
  /// copy/paste through another application may remove this receipt.
  String annotateMarkdown(String content) {
    if (content.trim().isEmpty) return '';
    final json = jsonEncode(toJson(content))
        .replaceAll('<', r'\u003c')
        .replaceAll('>', r'\u003e')
        .replaceAll('--', r'\u002d\u002d');
    return '<!-- crisperweaver-provenance: $json -->\n\n$content';
  }

  /// Do not publish a configured URL: it may include a credential, a private
  /// hostname or a tenant identifier. A proxy's upstream provider is unknown.
  static String providerForEndpoint(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    return switch (host) {
      'api.openai.com' => 'OpenAI',
      'api.anthropic.com' => 'Anthropic',
      'openrouter.ai' => 'OpenRouter',
      'api.groq.com' => 'Groq',
      'api.studio.nebius.com' || 'api.tokenfactory.nebius.com' => 'Nebius',
      '127.0.0.1' || '::1' || 'localhost' => 'local-http-endpoint',
      _ => 'configured-endpoint',
    };
  }

  /// Preserve the model filename, never the user's directory or account name.
  static String localModelName(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}
