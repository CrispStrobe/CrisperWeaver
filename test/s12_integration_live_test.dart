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

/// Generate a 1-second 440 Hz sine wave at 16 kHz.
Float32List _sine440(int sampleRate, double durationSeconds) {
  final n = (sampleRate * durationSeconds).toInt();
  final pcm = Float32List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = 0.5 *
        (2.0 * 3.14159265 * 440.0 * i / sampleRate)
            .remainder(1.0);
  }
  return pcm;
}

void main() {
  final lib = CrispModels.lib;

  // ---- §12.5 TADA re-alignment live test ----
  group('§12.5 TADA re-alignment live', () {
    final alignerModel = CrispModels.model('canary_aligner');
    final whisperModel = CrispModels.model('whisper_tiny');

    test('realignTimestamps produces word-level timings', () async {
      if (lib == null || alignerModel == null || whisperModel == null) {
        markTestSkipped('CrispASR dylib or aligner/whisper model not on disk');
        return;
      }

      // Decode a reference audio file to get PCM.
      final jfk = File('${CrispModels.modelsDir}/samples/jfk.wav');
      if (!jfk.existsSync()) {
        markTestSkipped('jfk.wav sample not on disk');
        return;
      }
      final decoded = crispasr.decodeAudioFile(jfk.path);
      expect(decoded.samples.isNotEmpty, isTrue);

      // Create segments as if from a prior ASR pass.
      final ctx = crispasr.CrispASR(whisperModel);
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
    });
  });

  // ---- §12.1e VAD empty-result live test ----
  group('§12.1e VAD silent audio live', () {
    test('transcribing silence produces empty result', () {
      final whisperModel = CrispModels.model('whisper_tiny');
      if (lib == null || whisperModel == null) {
        markTestSkipped('CrispASR dylib or whisper model not on disk');
        return;
      }

      // 2 seconds of silence.
      final silence = Float32List(32000);
      final ctx = crispasr.CrispASR(whisperModel);
      final segs = ctx.transcribePcm(silence);
      ctx.dispose();
      final text = segs.map((s) => s.text).join(' ').trim();

      // CrispASR 0.8.7 should return empty/near-empty for silence
      // (VAD hallucination fix). Accept empty or very short text.
      expect(text.length, lessThan(10),
          reason: 'silence should produce empty/near-empty text');
    });
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
