// §12 end-to-end live test: real CrispEmbed embedding + reranking.
//
// Exercises the embedding model (all-MiniLM-L6-v2 IQ4_XS) and
// the reranker (MS MARCO MiniLM-L6) with actual GGUF inference.
//
// Run:
//   CRISPEMBED_LIB=/mnt/volume1/CrispEmbed/build/libcrispembed.so \
//   flutter test test/reranker_embed_live_test.dart

@Tags(['slow'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crispembed/crispembed.dart';

void main() {
  final libPath = Platform.environment['CRISPEMBED_LIB'] ??
      (() {
        const candidates = [
          '../CrispEmbed/build/libcrispembed.so',
          '../CrispEmbed/build/libcrispembed.dylib',
        ];
        for (final c in candidates) {
          if (File(c).existsSync()) return File(c).absolute.path;
        }
        return null;
      })();

  const modelsDir = '/mnt/volume1/models';
  final embedModel = '$modelsDir/all-MiniLM-L6-v2-iq4_xs.gguf';
  final rerankerModel = '$modelsDir/ms-marco-MiniLM-L-6-v2-iq4_xs.gguf';

  group('CrispEmbed dense embedding (live)', () {
    test('encode produces 384-dim vector', () {
      if (libPath == null || !File(embedModel).existsSync()) {
        markTestSkipped('CrispEmbed lib or embed model not on disk');
        return;
      }
      final model = CrispEmbed(embedModel, libPath: libPath);
      final vec = model.encode('hello world');
      expect(vec.length, 384);
      // L2 normalized → magnitude ~1.0
      var norm = 0.0;
      for (final v in vec) {
        norm += v * v;
      }
      expect(norm, closeTo(1.0, 0.05));
      model.dispose();
    });

    test('cosine similarity: similar texts score higher', () {
      if (libPath == null || !File(embedModel).existsSync()) {
        markTestSkipped('CrispEmbed lib or embed model not on disk');
        return;
      }
      final model = CrispEmbed(embedModel, libPath: libPath);
      final v1 = model.encode('machine learning algorithms');
      final v2 = model.encode('deep learning neural networks');
      final v3 = model.encode('the weather is sunny today');

      double cos(Float32List a, Float32List b) {
        var dot = 0.0;
        for (var i = 0; i < a.length; i++) {
          dot += a[i] * b[i];
        }
        return dot; // L2-normalized, so dot = cosine
      }

      final simRelated = cos(v1, v2);
      final simUnrelated = cos(v1, v3);
      expect(simRelated, greaterThan(simUnrelated),
          reason:
              'ML↔DL ($simRelated) should score higher than ML↔weather ($simUnrelated)');
      model.dispose();
    });
  });

  group('CrispEmbed cross-encoder reranker (live)', () {
    test('reranker scores relevant doc higher than irrelevant', () {
      if (libPath == null || !File(rerankerModel).existsSync()) {
        markTestSkipped('CrispEmbed lib or reranker model not on disk');
        return;
      }
      final model = CrispEmbed(rerankerModel, libPath: libPath);
      expect(model.isReranker, isTrue,
          reason: 'MS MARCO model should report isReranker=true');

      final scoreRelevant =
          model.rerank('machine learning', 'deep learning is a subset of ML');
      final scoreIrrelevant =
          model.rerank('machine learning', 'the weather is sunny');

      expect(scoreRelevant, greaterThan(scoreIrrelevant),
          reason:
              'relevant ($scoreRelevant) should score higher than irrelevant ($scoreIrrelevant)');
      model.dispose();
    });

    test('reranker orders multiple documents correctly', () {
      if (libPath == null || !File(rerankerModel).existsSync()) {
        markTestSkipped('CrispEmbed lib or reranker model not on disk');
        return;
      }
      final model = CrispEmbed(rerankerModel, libPath: libPath);
      final results = model.rerankBiencoder(
        'what is machine learning',
        [
          'machine learning is a branch of AI',
          'the stock market rose today',
          'neural networks are used in deep learning',
        ],
      );
      expect(results.length, 3);
      // First result should be the ML definition
      expect(results.first.index, 0,
          reason: 'ML definition should rank first');
      model.dispose();
    });
  });

  group('CrispEmbed LoRA API (live)', () {
    test('LoRA API works on embedding model (no adapters)', () {
      if (libPath == null || !File(embedModel).existsSync()) {
        markTestSkipped('CrispEmbed lib or embed model not on disk');
        return;
      }
      final model = CrispEmbed(embedModel, libPath: libPath);
      // hasLora is true when the library supports it (symbol found).
      // MiniLM is a BERT encoder with no LoRA adapters baked in.
      expect(model.hasLora, isTrue);
      expect(model.listLora(), isEmpty);
      expect(model.activeLora, isEmpty);
      // setLora on a model without adapters returns false gracefully.
      expect(model.setLora('nonexistent'), isFalse);
      model.dispose();
    });
  });
}
