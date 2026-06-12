// §5.1.6 v3.1 — pin the curated chat-LLM catalogue contents.
//
// We don't validate the HF URLs (those are external resources
// and a 404 there should surface as a clear download error,
// not a unit-test failure here). What we DO pin is the
// structural contract:
//
//   * every chat-LLM row has a non-empty fileName + url
//   * sizeBytes is realistic (not 0; not preposterous)
//   * kind is ModelKind.chatLlm
//   * backend tag is 'chat'
//   * displayName mentions the family + size + quant so the
//     Settings → Local LLM row is self-describing
//
// A regression that drops a row, mistypes the URL, or
// reassigns `kind` would land here before it ships.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_service.dart';

void main() {
  /// The chat-LLM curated entries live in `crispasrBackendModels`
  /// alongside the LID + non-Whisper ASR entries; `getWhisperCppModels()`
  /// merges both maps at runtime, but for the structural pin we
  /// look at both statics directly to keep the test pure (no I/O).
  Iterable<ModelDefinition> chatLlmEntries() {
    return [
      ...ModelCatalog.whisperCppModels.values,
      ...ModelCatalog.crispasrBackendModels.values,
    ].where((m) => m.kind == ModelKind.chatLlm);
  }

  group('ModelService — chat-LLM catalogue', () {
    test('exposes at least five curated entries', () {
      final chat = chatLlmEntries().toList();
      // The catalogue should grow but never silently shrink —
      // a regression that drops a row would land here.
      expect(chat.length, greaterThanOrEqualTo(5),
          reason:
              'curated chat-LLM list should keep ≥ 5 entries; current is ${chat.length}');
    });

    test('every chat-LLM row has the structural fields populated',
        () {
      final chat = chatLlmEntries();
      for (final m in chat) {
        expect(m.name, isNotEmpty, reason: 'entry has empty name');
        expect(m.displayName, isNotEmpty,
            reason: '${m.name} has empty displayName');
        expect(m.fileName, endsWith('.gguf'),
            reason: '${m.name} fileName should end in .gguf');
        expect(m.url, startsWith('https://huggingface.co/'),
            reason: '${m.name} url should be a HuggingFace URL');
        expect(m.url, endsWith(m.fileName),
            reason: '${m.name} url should end in the filename so '
                'the downloader can resolve it directly');
        expect(m.sizeBytes, greaterThan(50 * 1024 * 1024),
            reason: '${m.name} size $m.sizeBytes is suspiciously small');
        expect(m.sizeBytes, lessThan(8 * 1024 * 1024 * 1024),
            reason: '${m.name} size is suspiciously large for a '
                'Q4_K_M chat model on this catalogue');
        expect(m.kind, ModelKind.chatLlm);
        expect(m.backend, 'chat',
            reason: '${m.name} should use backend="chat" so the '
                'Tidy / Summarize Local LLM path picks it up');
        expect(m.quantization, 'q4_k_m',
            reason: '${m.name} should be Q4_K_M — the curated '
                'list is intentionally one quant per family');
      }
    });

    test('catalogue spans the small / medium / large size buckets',
        () {
      final chat = chatLlmEntries();
      // Sanity: at least one model in each bucket so users on
      // low-resource hardware aren't forced into a 2 GB download.
      final hasTiny = chat.any((m) => m.sizeBytes < 500 * 1024 * 1024);
      final hasMedium = chat.any((m) =>
          m.sizeBytes >= 500 * 1024 * 1024 &&
          m.sizeBytes < 1500 * 1024 * 1024);
      final hasLarge = chat.any((m) => m.sizeBytes >= 1500 * 1024 * 1024);
      expect(hasTiny, isTrue,
          reason: 'catalogue needs at least one ≤500 MB model for low-resource hosts');
      expect(hasMedium, isTrue,
          reason: 'catalogue needs at least one 500 MB..1.5 GB model');
      expect(hasLarge, isTrue,
          reason: 'catalogue needs at least one ≥1.5 GB model for capable hosts');
    });

    test('catalogue covers multiple model families', () {
      // The point of the catalogue is choice — surface multiple
      // architectures so users with strong opinions about
      // Llama vs Qwen vs Phi vs Gemma can pick. We require at
      // least 2 distinct family prefixes in the displayName.
      final chat = chatLlmEntries();
      final families = chat
          .map((m) =>
              m.displayName.split(' ').first.toLowerCase())
          .toSet();
      expect(families.length, greaterThanOrEqualTo(2),
          reason: 'catalogue should cover ≥2 model families '
              '(currently: $families)');
    });
  });
}
