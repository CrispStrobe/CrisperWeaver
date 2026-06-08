import '../engines/transcription_engine.dart';

/// §5.25.13 — Model A/B testing results.
///
/// Stores the outcome of a side-by-side transcription comparison where
/// the user picks a "winner" per segment. Aggregated picks feed into
/// a local preference signal for future model recommendations.
class AbTestResult {
  final String modelA;
  final String modelB;
  final String audioPath;
  final DateTime timestamp;
  final List<TranscriptionSegment> segmentsA;
  final List<TranscriptionSegment> segmentsB;

  /// Per-segment winner: 'A', 'B', or 'tie'. Index matches the
  /// aligned segment pairs.
  final List<String> picks;

  const AbTestResult({
    required this.modelA,
    required this.modelB,
    required this.audioPath,
    required this.timestamp,
    required this.segmentsA,
    required this.segmentsB,
    this.picks = const [],
  });

  /// How many segments the user picked model A for.
  int get winsA => picks.where((p) => p == 'A').length;

  /// How many segments the user picked model B for.
  int get winsB => picks.where((p) => p == 'B').length;

  /// How many ties.
  int get ties => picks.where((p) => p == 'tie').length;

  /// Which model "won" overall ('A', 'B', or 'tie').
  String get overallWinner {
    if (winsA > winsB) return 'A';
    if (winsB > winsA) return 'B';
    return 'tie';
  }

  Map<String, dynamic> toJson() => {
        'modelA': modelA,
        'modelB': modelB,
        'audioPath': audioPath,
        'timestamp': timestamp.toIso8601String(),
        'picks': picks,
        'winsA': winsA,
        'winsB': winsB,
        'ties': ties,
        'overallWinner': overallWinner,
      };
}

/// Aggregate model ratings from A/B test results.
///
/// Maps model names to win/loss/tie counts. Used to inform the
/// recommended-default system over time.
class ModelRatings {
  final Map<String, _Rating> _ratings = {};

  void recordResult(AbTestResult result) {
    final winner = result.overallWinner;
    _ensure(result.modelA);
    _ensure(result.modelB);

    if (winner == 'A') {
      _ratings[result.modelA]!.wins++;
      _ratings[result.modelB]!.losses++;
    } else if (winner == 'B') {
      _ratings[result.modelB]!.wins++;
      _ratings[result.modelA]!.losses++;
    } else {
      _ratings[result.modelA]!.ties++;
      _ratings[result.modelB]!.ties++;
    }
  }

  void _ensure(String model) {
    _ratings.putIfAbsent(model, () => _Rating());
  }

  /// Models sorted by win rate (descending).
  List<MapEntry<String, double>> get leaderboard {
    final entries = _ratings.entries.map((e) {
      final total = e.value.wins + e.value.losses + e.value.ties;
      final rate = total == 0 ? 0.5 : e.value.wins / total;
      return MapEntry(e.key, rate);
    }).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  Map<String, dynamic> toJson() => _ratings.map(
        (k, v) => MapEntry(k, {
          'wins': v.wins,
          'losses': v.losses,
          'ties': v.ties,
        }),
      );
}

class _Rating {
  int wins = 0;
  int losses = 0;
  int ties = 0;
}
