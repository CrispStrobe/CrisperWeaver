// Schema regression tests for HistoryEntry. Adding a field to
// HistoryEntry without updating fromJson silently drops it on the
// round trip — these tests catch that.
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/history_service.dart';

void main() {
  group('HistoryEntry', () {
    test('round-trips every field including speakerNames', () {
      final original = HistoryEntry(
        id: '550e8400-e29b-41d4-a716-446655440000',
        createdAt: DateTime.utc(2026, 5, 3, 12, 34, 56),
        sourcePath: '/tmp/recording.wav',
        sourceUrl: 'https://example.com/clip.mp3',
        engineId: 'crispasr',
        modelId: 'whisper-tiny',
        language: 'en',
        diarizationEnabled: true,
        processingTime: const Duration(milliseconds: 12345),
        speakerNames: const {
          'Speaker 1': 'Alice',
          'Speaker 2': 'Bob with spaces & punct.',
        },
        segments: const [
          TranscriptionSegment(
            text: 'Hello world.',
            startTime: 0.0,
            endTime: 1.5,
            speaker: 'Speaker 1',
            confidence: 0.95,
          ),
          TranscriptionSegment(
            text: 'How are you?',
            startTime: 1.5,
            endTime: 3.0,
            speaker: 'Speaker 2',
            confidence: 0.87,
          ),
        ],
      );

      final restored = HistoryEntry.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.createdAt, original.createdAt);
      expect(restored.sourcePath, original.sourcePath);
      expect(restored.sourceUrl, original.sourceUrl);
      expect(restored.engineId, original.engineId);
      expect(restored.modelId, original.modelId);
      expect(restored.language, original.language);
      expect(restored.diarizationEnabled, isTrue);
      expect(restored.processingTime, const Duration(milliseconds: 12345));
      expect(restored.speakerNames, original.speakerNames);
      expect(restored.segments.length, 2);
      expect(restored.segments[0].text, 'Hello world.');
      expect(restored.segments[0].speaker, 'Speaker 1');
      expect(restored.segments[1].confidence, closeTo(0.87, 1e-9));
    });

    test('back-compat: loads JSON without speakerNames key as empty', () {
      // JSON shape from before the speaker-rename field landed.
      final legacyJson = {
        'id': 'legacy-id',
        'createdAt': '2026-04-15T10:00:00.000Z',
        'engineId': 'mock',
        'segments': <Map<String, dynamic>>[],
      };

      final entry = HistoryEntry.fromJson(legacyJson);

      expect(entry.speakerNames, isEmpty);
      expect(entry.diarizationEnabled, isFalse);
      expect(entry.processingTime, Duration.zero);
      expect(entry.sourcePath, isNull);
      expect(entry.modelId, isNull);
    });

    test('back-compat: bool-keyed speakerNames map is coerced to strings',
        () {
      // A future bug where someone serializes int-or-bool-keyed maps;
      // the loader's `.map((k, v) => MapEntry(k.toString(), v.toString()))`
      // catches that. This guards the contract.
      final json = {
        'id': 'coerce',
        'createdAt': '2026-04-15T10:00:00.000Z',
        'engineId': 'mock',
        'segments': <Map<String, dynamic>>[],
        'speakerNames': {1: 'One', 'Two': 2},
      };

      final entry = HistoryEntry.fromJson(json);
      expect(entry.speakerNames, {'1': 'One', 'Two': '2'});
    });

    test('title falls back through sourcePath → sourceUrl → timestamp', () {
      final withPath = HistoryEntry(
        id: 'a',
        createdAt: DateTime.utc(2026, 1, 1),
        engineId: 'mock',
        segments: const [],
        sourcePath: '/var/folders/abc/recording_42.wav',
      );
      expect(withPath.title, 'recording_42.wav');

      final withUrl = HistoryEntry(
        id: 'b',
        createdAt: DateTime.utc(2026, 1, 1),
        engineId: 'mock',
        segments: const [],
        sourceUrl: 'https://x.test/clip',
      );
      expect(withUrl.title, 'https://x.test/clip');

      final neither = HistoryEntry(
        id: 'c',
        createdAt: DateTime.utc(2026, 1, 1, 9, 0),
        engineId: 'mock',
        segments: const [],
      );
      expect(neither.title, contains('2026-01-01'));
    });

    test('round-trips audioEmbedding field', () {
      final original = HistoryEntry(
        id: 'audio-emb-test',
        createdAt: DateTime.utc(2026, 6, 8),
        engineId: 'crispasr',
        segments: const [
          TranscriptionSegment(
              text: 'Hello.', startTime: 0, endTime: 1, confidence: 1),
        ],
        audioEmbedding: [0.1, 0.2, 0.3, -0.5, 1.0],
      );

      final json = original.toJson();
      expect(json.containsKey('audioEmbedding'), isTrue);

      final restored = HistoryEntry.fromJson(json);
      expect(restored.audioEmbedding, isNotNull);
      expect(restored.audioEmbedding!.length, 5);
      expect(restored.audioEmbedding![0], closeTo(0.1, 1e-9));
      expect(restored.audioEmbedding![3], closeTo(-0.5, 1e-9));
    });

    test('back-compat: loads JSON without audioEmbedding as null', () {
      final json = {
        'id': 'no-audio-emb',
        'createdAt': '2026-06-01T10:00:00.000Z',
        'engineId': 'mock',
        'segments': <Map<String, dynamic>>[],
      };
      final entry = HistoryEntry.fromJson(json);
      expect(entry.audioEmbedding, isNull);
    });

    test('withAudioEmbedding returns copy with audioEmbedding set', () {
      final original = HistoryEntry(
        id: 'copy-test',
        createdAt: DateTime.utc(2026, 6, 8),
        engineId: 'crispasr',
        segments: const [],
        segmentEmbeddings: const {0: [1.0, 2.0]},
      );
      final copy = original.withAudioEmbedding([0.5, 0.6, 0.7]);
      expect(copy.audioEmbedding, [0.5, 0.6, 0.7]);
      expect(copy.segmentEmbeddings, original.segmentEmbeddings);
      expect(copy.id, original.id);
    });

    test('fullText joins segment text with single spaces', () {
      final e = HistoryEntry(
        id: 'x',
        createdAt: DateTime.utc(2026, 1, 1),
        engineId: 'mock',
        segments: const [
          TranscriptionSegment(
              text: 'Hello.', startTime: 0, endTime: 1, confidence: 1),
          TranscriptionSegment(
              text: 'World!', startTime: 1, endTime: 2, confidence: 1),
        ],
      );
      expect(e.fullText, 'Hello. World!');
    });
  });
}
