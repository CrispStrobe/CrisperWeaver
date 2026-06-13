// §5.25.13 — A/B test result aggregation + model ratings.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/services/ab_test_service.dart';

AbTestResult _result({
  String modelA = 'whisper-tiny',
  String modelB = 'parakeet-0.6b',
  List<String> picks = const [],
}) =>
    AbTestResult(
      modelA: modelA,
      modelB: modelB,
      audioPath: '/tmp/test.wav',
      timestamp: DateTime(2026, 6, 13),
      segmentsA: const [TranscriptionSegment(text: 'a', startTime: 0, endTime: 1)],
      segmentsB: const [TranscriptionSegment(text: 'b', startTime: 0, endTime: 1)],
      picks: picks,
    );

void main() {
  group('AbTestResult', () {
    test('winsA / winsB / ties count correctly', () {
      final r = _result(picks: ['A', 'B', 'A', 'tie', 'A']);
      expect(r.winsA, 3);
      expect(r.winsB, 1);
      expect(r.ties, 1);
    });

    test('overallWinner is A when A has more wins', () {
      expect(_result(picks: ['A', 'A', 'B']).overallWinner, 'A');
    });

    test('overallWinner is B when B has more wins', () {
      expect(_result(picks: ['B', 'B', 'A']).overallWinner, 'B');
    });

    test('overallWinner is tie when equal', () {
      expect(_result(picks: ['A', 'B']).overallWinner, 'tie');
    });

    test('overallWinner is tie on empty picks', () {
      expect(_result(picks: []).overallWinner, 'tie');
    });

    test('toJson contains all fields', () {
      final r = _result(picks: ['A', 'B']);
      final j = r.toJson();
      expect(j['modelA'], 'whisper-tiny');
      expect(j['modelB'], 'parakeet-0.6b');
      expect(j['winsA'], 1);
      expect(j['winsB'], 1);
      expect(j['overallWinner'], 'tie');
    });
  });

  group('ModelRatings', () {
    test('records a single A win correctly', () {
      final ratings = ModelRatings();
      ratings.recordResult(_result(picks: ['A', 'A', 'B']));
      final lb = ratings.leaderboard;
      expect(lb.length, 2);
      // whisper-tiny won → higher rate
      expect(lb.first.key, 'whisper-tiny');
      expect(lb.first.value, greaterThan(0.5));
    });

    test('records a tie correctly', () {
      final ratings = ModelRatings();
      // Equal picks → overallWinner is 'tie' → both get a tie count,
      // zero wins → win rate = 0/1 = 0.0, not 0.5.
      ratings.recordResult(_result(picks: ['A', 'B']));
      final lb = ratings.leaderboard;
      expect(lb.length, 2);
      for (final e in lb) {
        expect(e.value, closeTo(0.0, 0.01));
      }
    });

    test('multiple results accumulate', () {
      final ratings = ModelRatings();
      // First test: A wins
      ratings.recordResult(_result(picks: ['A', 'A']));
      // Second test: B wins
      ratings.recordResult(_result(picks: ['B', 'B', 'B']));
      final lb = ratings.leaderboard;
      // A: 1 win, 1 loss → 50%. B: 1 win, 1 loss → 50%.
      expect(lb.length, 2);
    });

    test('toJson round-trips', () {
      final ratings = ModelRatings();
      ratings.recordResult(_result(picks: ['A']));
      final j = ratings.toJson();
      expect(j['whisper-tiny'], isNotNull);
      expect(j['whisper-tiny']['wins'], 1);
      expect(j['parakeet-0.6b']['losses'], 1);
    });

    test('leaderboard sorted descending by win rate', () {
      final ratings = ModelRatings();
      ratings.recordResult(_result(
        modelA: 'fast',
        modelB: 'slow',
        picks: ['A', 'A', 'A', 'B'],
      ));
      final lb = ratings.leaderboard;
      expect(lb.first.key, 'fast');
      expect(lb.last.key, 'slow');
      expect(lb.first.value, greaterThan(lb.last.value));
    });
  });
}
