// Unit tests for OcrService (§12.6b).

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/ocr_service.dart';

void main() {
  group('OcrResult', () {
    test('default has empty text and zero duration', () {
      const r = OcrResult(text: '');
      expect(r.text, isEmpty);
      expect(r.confidence, isNull);
      expect(r.processingTime, Duration.zero);
    });

    test('holds text and confidence', () {
      const r = OcrResult(
        text: 'x^{2} + 1',
        confidence: 0.95,
        processingTime: Duration(milliseconds: 150),
      );
      expect(r.text, 'x^{2} + 1');
      expect(r.confidence, 0.95);
      expect(r.processingTime.inMilliseconds, 150);
    });
  });

  group('OcrEngine', () {
    test('all engines have non-empty backendPrefix', () {
      for (final e in OcrEngine.values) {
        expect(e.backendPrefix, isNotEmpty);
      }
    });
  });

  group('OcrService.engineForModel', () {
    test('detects pix2tex math OCR', () {
      expect(
          OcrService.engineForModel('pix2tex-mfr-q4_k.gguf'),
          OcrEngine.mathOcr);
    });

    test('detects HMER handwritten math OCR', () {
      expect(
          OcrService.engineForModel('hmer-hw-f32.gguf'), OcrEngine.hmerOcr);
    });

    test('detects BTTR OCR', () {
      expect(
          OcrService.engineForModel('bttr-hw-q4_k.gguf'), OcrEngine.bttrOcr);
    });

    test('detects PosFormer OCR', () {
      expect(OcrService.engineForModel('posformer-handwritten-q4_k.gguf'),
          OcrEngine.posformerOcr);
    });

    test('returns null for non-OCR model', () {
      expect(OcrService.engineForModel('whisper-tiny.bin'), isNull);
    });

    test('returns null for empty filename', () {
      expect(OcrService.engineForModel(''), isNull);
    });
  });

  group('OcrService._isOcrModel', () {
    test('identifies OCR models', () {
      expect(OcrService.isOcrModelFilename('pix2tex-mfr-q4_k.gguf'), isTrue);
      expect(OcrService.isOcrModelFilename('hmer-hw-f32.gguf'), isTrue);
      expect(OcrService.isOcrModelFilename('bttr-hw-q4_k.gguf'), isTrue);
    });

    test('rejects non-OCR models', () {
      expect(OcrService.isOcrModelFilename('whisper-tiny.bin'), isFalse);
      expect(OcrService.isOcrModelFilename('kokoro-82m-q8_0.gguf'), isFalse);
    });

    test('identifies VLM OCR models', () {
      expect(OcrService.isOcrModelFilename('granite-vision-3.3-2b-q4_k.gguf'),
          isTrue);
      expect(OcrService.isOcrModelFilename('deepseek-ocr2-f16.gguf'), isTrue);
    });
  });

  group('OCR catalog entries (§12.6b)', () {
    test('pix2tex is in catalog as ModelKind.ocr', () {
      final def = ModelCatalog.crispasrBackendModels['pix2tex-mfr-q4_k'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.ocr);
      expect(def.backend, 'ocr');
    });

    test('hmer is in catalog as ModelKind.ocr', () {
      final def = ModelCatalog.crispasrBackendModels['hmer-hw-q4_k'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.ocr);
    });

    test('bttr is in catalog as ModelKind.ocr', () {
      final def = ModelCatalog.crispasrBackendModels['bttr-hw-q4_k'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.ocr);
    });

    test('posformer is in catalog with NC license', () {
      final def = ModelCatalog.crispasrBackendModels['posformer-crohme-q8_0'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.ocr);
      expect(def.isNonCommercial, isTrue);
    });

    test('granite-vision is in catalog as ModelKind.ocr', () {
      final def =
          ModelCatalog.crispasrBackendModels['granite-vision-3.3-2b-q4_k'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.ocr);
    });

    test('deepseek-ocr2 is in catalog as ModelKind.ocr', () {
      final def = ModelCatalog.crispasrBackendModels['deepseek-ocr2-f16'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.ocr);
    });

    test('all OCR entries have non-empty URLs', () {
      const keys = [
        'pix2tex-mfr-q4_k',
        'hmer-hw-q4_k',
        'bttr-hw-q4_k',
        'posformer-crohme-q8_0',
        'granite-vision-3.3-2b-q4_k',
        'deepseek-ocr2-f16',
      ];
      for (final key in keys) {
        final def = ModelCatalog.crispasrBackendModels[key];
        expect(def, isNotNull, reason: '$key missing');
        expect(def!.url, isNotEmpty, reason: '$key has empty URL');
        expect(def.sizeBytes, greaterThan(0), reason: '$key has zero size');
      }
    });
  });

  group('Reranker catalog entries (§12.3a)', () {
    test('MS MARCO MiniLM reranker is in catalog', () {
      final def = ModelCatalog
          .crispasrBackendModels['ms-marco-minilm-l-6-v2-iq4_xs'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.reranker);
      expect(def.backend, 'reranker');
    });

    test('mxbai reranker is in catalog', () {
      final def = ModelCatalog
          .crispasrBackendModels['mxbai-rerank-xsmall-v1-q8_0'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.reranker);
    });

    test('BGE multilingual reranker is in catalog', () {
      final def =
          ModelCatalog.crispasrBackendModels['bge-reranker-v2-m3-q8_0'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.reranker);
      expect(def.languages, contains('*'));
    });

    test('reranker BackendRepos exist', () {
      expect(ModelCatalog.backendRepos.containsKey('reranker-msmarco'),
          isTrue);
      expect(ModelCatalog.backendRepos.containsKey('reranker-mxbai-xsmall'),
          isTrue);
      expect(
          ModelCatalog.backendRepos.containsKey('reranker-bge-m3'), isTrue);
    });
  });

  group('Larger embedding catalog entries (§12.4)', () {
    test('Nomic embed v1.5 is in catalog', () {
      final def = ModelCatalog
          .crispasrBackendModels['nomic-embed-text-v1.5-q4_k'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.embed);
    });

    test('Multilingual E5 small is in catalog', () {
      final def = ModelCatalog
          .crispasrBackendModels['multilingual-e5-small-iq4_xs'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.embed);
      expect(def.languages, contains('*'));
    });

    test('Qwen3 Embedding 0.6B is in catalog', () {
      final def =
          ModelCatalog.crispasrBackendModels['qwen3-embed-0.6b-q4_k'];
      expect(def, isNotNull);
      expect(def!.kind, ModelKind.embed);
    });

    test('embedding BackendRepos exist', () {
      expect(ModelCatalog.backendRepos.containsKey('embed-nomic'), isTrue);
      expect(
          ModelCatalog.backendRepos.containsKey('embed-e5-small'), isTrue);
      expect(ModelCatalog.backendRepos.containsKey('embed-qwen3-0.6b'),
          isTrue);
    });
  });
}
