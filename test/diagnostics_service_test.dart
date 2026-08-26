import 'package:crisper_weaver/services/diagnostics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostics sanitizer removes home paths and common API tokens', () {
    const raw = '/Users/alice/models/a.gguf\n'
        'Authorization: Bearer secret.jwt.value\n'
        'hf-abcdefghijklmnop\n'
        'https://example.test?a=1&api_key=super-secret';
    final clean = DiagnosticsService.sanitize(
      raw,
      homeDirectory: '/Users/alice',
    );
    expect(clean, contains('<home>/models/a.gguf'));
    expect(clean, contains('Bearer <redacted>'));
    expect(clean, contains('<redacted-token>'));
    expect(clean, contains('api_key=<redacted>'));
    expect(clean, isNot(contains('super-secret')));
  });
}
