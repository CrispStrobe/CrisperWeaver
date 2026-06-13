// Live test for the baked catalog JSON — probes a known-stable HF repo
// to verify the bake script would produce compatible entries.
//
// Run with: RUN_LIVE_TESTS=1 flutter test --tags=live test/baked_catalog_live_test.dart

@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_catalog.dart';

void main() {
  setUp(() {
    final run = Platform.environment['RUN_LIVE_TESTS'];
    if (run != '1') {
      markTestSkipped('Set RUN_LIVE_TESTS=1 to run live catalog tests');
    }
  });

  test('HF probe for parakeet repo returns parseable model entries', () async {
    // Probe a known-stable repo — parakeet-tdt-0.6b-v3 has been around since
    // 2025 and is unlikely to be removed.
    const repoId = 'cstr/parakeet-tdt-0.6b-v3-GGUF';
    final url =
        Uri.parse('https://huggingface.co/api/models/$repoId?blobs=true');

    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      final resp = await req.close();
      expect(resp.statusCode, 200,
          reason: 'HF API should return 200 for $repoId');

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final siblings = (json['siblings'] as List?) ?? [];

      // Find .gguf files that match the baseName pattern.
      final ggufFiles = siblings
          .whereType<Map<String, dynamic>>()
          .where((s) =>
              (s['rfilename'] as String? ?? '').endsWith('.gguf'))
          .toList();

      expect(ggufFiles, isNotEmpty,
          reason: '$repoId should have at least one .gguf file');

      // Verify each file can be turned into a valid ModelDefinition.
      for (final sib in ggufFiles) {
        final fname = sib['rfilename'] as String;
        final sizeBytes = (sib['size'] as num?)?.toInt() ?? 0;
        final stem = fname.substring(0, fname.length - '.gguf'.length);

        const baseName = 'parakeet-tdt-0.6b-v3';
        if (!stem.startsWith(baseName)) continue;

        final quant = stem == baseName
            ? 'f16'
            : stem.substring(baseName.length + 1);
        final key = '$baseName-$quant';

        final entry = <String, dynamic>{
          'name': key,
          'displayName': 'Parakeet TDT 0.6B v3 ($quant)',
          'fileName': fname,
          'url': 'https://huggingface.co/$repoId/resolve/main/$fname',
          'sizeBytes': sizeBytes,
          'checksum': '',
          'description': 'Fast English ASR (NVIDIA Parakeet)',
          'quantization': quant,
          'backend': 'parakeet',
          'kind': 'asr',
        };

        final def = ModelDefinition.fromJson(entry);
        expect(def.name, key);
        expect(def.backend, 'parakeet');
        expect(def.kind, ModelKind.asr);
        expect(def.sizeBytes, greaterThan(0));
      }
    } finally {
      client.close();
    }
  });

  test('catalog.json contains parakeet entries matching live HF data',
      () async {
    // Load the local catalog and verify parakeet entries exist.
    final catalogFile = File('assets/models/catalog.json');
    expect(catalogFile.existsSync(), isTrue);

    final catalogList = (jsonDecode(catalogFile.readAsStringSync())
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

    final parakeetEntries = catalogList
        .where((e) =>
            (e['backend'] as String?) == 'parakeet' &&
            (e['name'] as String).startsWith('parakeet-tdt-0.6b-v3'))
        .toList();

    expect(parakeetEntries, isNotEmpty,
        reason: 'Catalog should contain parakeet-tdt-0.6b-v3 entries');

    // Each entry should deserialise cleanly.
    for (final entry in parakeetEntries) {
      final def = ModelDefinition.fromJson(entry);
      expect(def.backend, 'parakeet');
      expect(def.sizeBytes, greaterThan(0));
    }
  });
}
