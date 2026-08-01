// §12 integration live tests — exercises features added in the
// CrispASR 0.8.7 + CrispEmbed 0.13.0 sweep. Tagged `slow`; self-skips
// when models or dylibs are absent.
//
// Run:
//   scripts/run_live_tests.sh test/s12_integration_live_test.dart

@Tags(['slow'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/aligner_service.dart';
import 'package:crisper_weaver/services/history_service.dart';
import 'package:crisper_weaver/services/semantic_search_service.dart';

import 'support/crispasr_models.dart';

void main() {
  final lib = CrispModels.lib;

  // ---- §12.5 TADA re-alignment live test ----
  group('§12.5 TADA re-alignment live', () {
    final alignerModel = CrispModels.model('canary_aligner');
    final whisperModel = CrispModels.model('whisper_tiny');
    // Use the shared gate rather than a hand-rolled markTestSkipped: this
    // group used to run on a plain `flutter test` whenever the models
    // happened to be on disk, which is exactly what CrispModels.enabled
    // exists to prevent. It was the sole red test in the pre-push gate.
    final skip = CrispModels.skipReason(
        models: ['canary_aligner', 'whisper_tiny']);

    test('realignTimestamps produces word-level timings', () async {
      if (alignerModel == null || whisperModel == null) return;

      // Decode a reference audio file to get PCM.
      final jfk = File('${CrispModels.modelsDir}/samples/jfk.wav');
      if (!jfk.existsSync()) {
        markTestSkipped('jfk.wav sample not on disk');
        return;
      }
      // Pass the resolved lib explicitly: without libPath this falls back
      // to bare-name `libcrispasr.dylib` resolution, which fails even
      // though the guard above proved a dylib exists — so the test threw
      // instead of skipping. Matches how the other live tests call it.
      final decoded = crispasr.decodeAudioFile(jfk.path, libPath: lib);
      expect(decoded.samples.isNotEmpty, isTrue);

      // Create segments as if from a prior ASR pass.
      final ctx = crispasr.CrispASR(whisperModel, libPath: lib);
      final segs = ctx.transcribePcm(decoded.samples);
      ctx.dispose();
      final resultText = segs.map((s) => s.text).join(' ').trim();
      expect(resultText.isNotEmpty, isTrue);

      final segments = [
        TranscriptionSegment(
          text: resultText,
          startTime: 0.0,
          endTime: decoded.samples.length / 16000.0,
        ),
      ];

      // Run standalone re-alignment.
      final aligner = AlignerService();
      final aligned = await aligner.realignTimestamps(
        segments,
        decoded.samples,
        alignerModel: alignerModel,
      );

      expect(aligned.length, 1);
      final words = aligned.first.words;
      expect(words, isNotNull);
      expect(words!, isNotEmpty);

      // Verify word timings are monotonically increasing.
      for (var i = 1; i < words.length; i++) {
        expect(words[i].startTime, greaterThanOrEqualTo(words[i - 1].startTime),
            reason: 'word ${words[i].word} has non-monotonic start time');
      }
    }, skip: skip);
  });

  // ---- §12.1e VAD silent audio live test ----
  // The deterministic core of "silence must not hallucinate a transcript":
  // the Silero VAD dispatcher finds NO speech spans in pure silence, so
  // the VAD-gated transcribe path emits nothing. (A raw whisper decode of
  // silence DOES hallucinate — "you", "Thank you.", subtitle credits — so
  // we exercise the VAD dispatcher directly rather than asserting on a
  // flaky raw transcript.) Opt-in gated (skipReason) and pins the resolved
  // dylib via libPath, like the rest of the live suite — so the default
  // `flutter test` pre-push gate skips it instead of loading a GGUF.
  group('§12.1e VAD silent audio live', () {
    final skip = CrispModels.skipReason(models: ['whisper_tiny']);
    test('VAD finds no speech spans in pure silence', () {
      // whisper_tiny is guaranteed present when skip == null.
      final cr = crispasr.CrispASR(CrispModels.model('whisper_tiny')!,
          libPath: lib);
      addTearDown(cr.dispose);

      // 2 seconds of digital silence.
      final silence = Float32List(32000);
      final spans = cr.vadSlices(
        silence,
        modelPath: CrispModels.sileroAsset,
        minSpeechMs: 250,
        minSilenceMs: 100,
      );
      expect(spans, isEmpty,
          reason: 'Silero VAD must detect no speech in pure silence '
              '(got ${spans.length} span(s))');
    }, skip: skip);
  });

  // ---- §12.8f BidirLM-Omni audio embedding e2e ----
  group('§12.8f BidirLM-Omni audio embedding', () {
    test('HistoryEntry preserves audioEmbedding from constructor', () {
      // Unit-level check: the data flows into the HistoryEntry correctly.
      final embedding = List.filled(2048, 0.42);
      final entry = HistoryEntry(
        id: 'test-audio-emb',
        createdAt: DateTime.now(),
        engineId: 'crispasr',
        segments: [
          TranscriptionSegment(
              text: 'test audio', startTime: 0, endTime: 5),
        ],
        audioEmbedding: embedding,
      );
      expect(entry.audioEmbedding, isNotNull);
      expect(entry.audioEmbedding!.length, 2048);
      expect(entry.audioEmbedding!.first, closeTo(0.42, 1e-6));
    });

    test('audioEmbedding round-trips through JSON serialization', () {
      final embedding = List.filled(384, 0.1);
      final entry = HistoryEntry(
        id: 'test-json-rt',
        createdAt: DateTime(2026, 7, 4),
        engineId: 'crispasr',
        segments: [
          TranscriptionSegment(text: 'hello', startTime: 0, endTime: 1),
        ],
        audioEmbedding: embedding,
      );
      final json = entry.toJson();
      final restored = HistoryEntry.fromJson(json);
      expect(restored.audioEmbedding, isNotNull);
      expect(restored.audioEmbedding!.length, 384);
      expect(restored.audioEmbedding!.first, closeTo(0.1, 1e-6));
    });
  });

  // ---- §12.3a reranker logic live test (no model needed) ----
  group('§12.3a reranker scoring live', () {
    test('rerankWithScorer inverts cosine ranking for targeted query', () {
      // Use keyword-based scorer to verify the rerank pipeline.
      final segments = [
        TranscriptionSegment(
            text: 'the weather is sunny today', startTime: 0, endTime: 5),
        TranscriptionSegment(
            text: 'deep learning models are powerful', startTime: 5, endTime: 10),
        TranscriptionSegment(
            text: 'flutter builds beautiful apps', startTime: 10, endTime: 15),
      ];

      // Create fake cosine candidates with weather ranked first.
      final candidates = [
        for (var i = 0; i < segments.length; i++)
          SearchResult(
            segmentIndex: i,
            score: 1.0 - i * 0.1, // weather=1.0, learning=0.9, flutter=0.8
            segment: segments[i],
          ),
      ];

      // Scorer that prefers "learning" keyword.
      final reranked = SemanticSearchService.rerankWithScorer(
        query: 'machine learning',
        candidates: candidates,
        scorer: (q, doc) => doc.contains('learning') ? 5.0 : 0.1,
        maxResults: 3,
      );

      // "deep learning" should now be first.
      expect(reranked.first.segmentIndex, 1);
      expect(reranked.first.score, 5.0);
    });
  });
}
