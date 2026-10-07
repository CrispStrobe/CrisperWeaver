import 'package:crisper_weaver/services/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('German Moonshine ONNX bundles isolate every companion', () {
    const catalog = ModelCatalog.crispasrBackendModels;
    for (final name in [
      'moonshine-streaming-small-de-onnx',
      'moonshine-streaming-tiny-de-onnx',
      'moonshine-tiny-de-phreak87-onnx',
      'moonshine-streaming-small-de-onnx-f32',
      'moonshine-streaming-tiny-de-onnx-f32',
    ]) {
      final model = catalog[name]!;
      expect(model.backend, 'moonshine-onnx');
      expect(model.languages, ['de']);
      expect(model.license, 'MIT');
      expect(model.isOffered, isTrue);
      expect(model.companions, isNotEmpty);
      for (final companion in model.companions) {
        final entry = catalog[companion]!;
        expect(entry.fileName, startsWith('$name/'));
        expect(entry.kind, ModelKind.codec);
        expect(entry.checksum, hasLength(64));
      }
    }
  });
  test('permissive German GGUF has its own tokenizer', () {
    const catalog = ModelCatalog.crispasrBackendModels;
    final model = catalog['moonshine-tiny-de-dattazigzag-q4_k']!;
    expect(model.isOffered, isTrue);
    expect(model.languages, ['de']);
    final tokenizer = catalog[model.companions.single]!;
    expect(tokenizer.fileName, '${model.name}/tokenizer.bin');
    expect(tokenizer.url, contains('dattazigzag-GGUF'));
  });
  test('fidoriel ONNX re-exports retain upstream restrictions', () {
    for (final repo in [
      'Phreak87/moonshine-base-de-onnx',
      'Phreak87/moonshine-base_V2',
      'Phreak87/moonshine-tiny_V2',
    ]) {
      expect(ModelCatalog.nonCommercialRepos, contains(repo));
    }
  });
}
