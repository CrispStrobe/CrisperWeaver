// Semantic search performance harness (§5.25.2 / §14.3l).
//
// Not part of the default `flutter test` gate: it measures the semantic
// search pipeline over synthetic segment sets (100 / 1,000 / 10,000
// segments) and prints a JSON report to stdout. Two runs are reported
// separately:
//   * deterministic encoder fixture (FakeCrispEmbed, pure Dart) —
//     reproducible, but NOT native model speed;
//   * optional native inference (CrispEmbed against a real GGUF model)
//     enabled by defining SEMANTIC_BENCH_NATIVE_MODEL via
//     `--dart-define`; skipped when unset.
//
// Run (fixture): flutter test --no-pub test/semantic_search_benchmark_test.dart
// Run (native):  flutter test --no-pub -Ddart-define=SEMANTIC_BENCH_NATIVE_MODEL=/path/model.gguf test/semantic_search_benchmark_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/native/crispembed_import.dart';
import 'package:crisper_weaver/services/semantic_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_crisp_embed.dart';

const segmentCounts = [100, 1000, 10000];

final _words = List.generate(4096, (i) => 'word$i');
final _rng = math.Random(42);

TranscriptionSegment _segment(int i) {
  final buf = StringBuffer();
  for (var w = 0; w < 12; w++) {
    buf.write(_words[_rng.nextInt(_words.length)]);
    buf.write(' ');
  }
  return TranscriptionSegment(
    text: buf.toString(),
    startTime: i.toDouble(),
    endTime: i + 1.0,
  );
}

List<TranscriptionSegment> makeSegments(int count) =>
    List.generate(count, _segment);

Map<String, Object?> _run(
  String label,
  List<int> counts, {
  CrispEmbed? embedder,
  int iterations = 3,
}) {
  final perSize = <Map<String, Object?>>[];
  for (final n in counts) {
    final segments = makeSegments(n);
    // Warm-up + fill any caches the first search builds.
    SemanticSearchService.search(
        query: 'word5 word7', segments: segments, embedder: embedder);
    var bestEncode = double.infinity;
    var bestSearch = double.infinity;
    for (var it = 0; it < iterations; it++) {
      SemanticSearchService.clearEmbeddingCache();
      final encodeSw = Stopwatch()..start();
      SemanticSearchService.search(
          query: 'word5 word7', segments: segments, embedder: embedder);
      encodeSw.stop();
      bestEncode = math.min(bestEncode, encodeSw.elapsedMicroseconds / 1000);
      final searchSw = Stopwatch()..start();
      SemanticSearchService.search(
          query: 'word5 word7', segments: segments, embedder: embedder);
      searchSw.stop();
      bestSearch = math.min(bestSearch, searchSw.elapsedMicroseconds / 1000);
    }
    perSize.add({
      'segments': n,
      'coldMs': double.parse(bestEncode.toStringAsFixed(2)),
      'warmMs': double.parse(bestSearch.toStringAsFixed(2)),
    });
  }
  return {'encoder': label, 'results': perSize};
}

void main() {
  test('semantic search benchmark (informational, printed to stdout)', () {
    final report = <Map<String, Object?>>[];
    report.add(_run('fixture (FakeCrispEmbed)', segmentCounts,
        embedder: FakeCrispEmbed(hasColbert: true)));
    const nativeModel = String.fromEnvironment('SEMANTIC_BENCH_NATIVE_MODEL');
    if (nativeModel.isNotEmpty) {
      try {
        final embedder = CrispEmbed(nativeModel);
        report.add(_run(
            'native (${nativeModel.split('/').last})',
            // 10k segments through a real model can take minutes; keep the
            // native run bounded to the two smaller sizes.
            segmentCounts.take(2).toList(),
            embedder: embedder));
        embedder.dispose();
      } catch (e) {
        report.add({
          'encoder': 'native',
          'error': 'native benchmark skipped: $e',
        });
      }
    } else {
      report.add({
        'encoder': 'native',
        'skipped':
            'set SEMANTIC_BENCH_NATIVE_MODEL via --dart-define to measure actual native inference',
      });
    }
    // ignore: avoid_print
    print('SEMANTIC_SEARCH_BENCHMARK ${jsonEncode(report)}');
  }, tags: ['slow'], skip: !_benchRequested);
}

/// Opt-in, per the `dart_test.yaml` convention for `slow` tests: the default
/// `flutter test` pass stays offline and fast, and this runs when asked for.
final _benchRequested =
    const bool.fromEnvironment('SEMANTIC_BENCH') ||
        (Platform.environment['SEMANTIC_BENCH'] ?? '').isNotEmpty;
