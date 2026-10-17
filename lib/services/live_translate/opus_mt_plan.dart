// Which Opus-MT models a routing table needs, and which of them are missing.
//
// Opus-MT (`marian`) models translate one direction each. LiveTranslatorWorker
// routes a sentence to its pair's model, else through English in two hops,
// else to the general translator (see `opusMtRoute`). This plans the same
// thing ahead of time for the setup page: what each direction will use, and
// the smallest set of catalogue models to download so every direction has an
// Opus-MT path — the direct pair when one is published, the two English
// halves otherwise.

import 'live_translate_config.dart';
import 'live_translator_worker.dart' show opusMtRoute;

/// How one direction will be translated.
enum OpusMtCoverage {
  /// Its own Opus-MT model is installed.
  pair,

  /// Through English, with both halves installed.
  pivot,

  /// No Opus-MT path; the general translator handles it (or nothing).
  fallback,
}

class OpusMtPlan {
  const OpusMtPlan({required this.coverage, required this.toDownload});

  /// `'src-tgt'` → how that direction is translated today.
  final Map<String, OpusMtCoverage> coverage;

  /// Catalogue directions (`'src-tgt'`) to download so that every direction
  /// that can have an Opus-MT path gets one. Sorted, no duplicates.
  final List<String> toDownload;

  bool get complete => toDownload.isEmpty;
}

/// Every translation direction [config] can produce, in display order.
List<(String, String)> translationDirections(LiveTranslateConfig config) {
  final out = <(String, String)>[];
  void add(String src) {
    for (final t in config.targetsFor(src)) {
      if (!out.contains((src, t))) out.add((src, t));
    }
  }

  if (config.lidMode == LiveLidMode.fixed) {
    add(config.fixedSource);
  } else {
    config.routes.keys.forEach(add);
  }
  return out;
}

/// [installed] and [published] are sets of `'src-tgt'` directions.
OpusMtPlan planOpusMt(
  List<(String, String)> directions, {
  required Set<String> installed,
  required Set<String> published,
}) {
  final coverage = <String, OpusMtCoverage>{};
  final want = <String>{};
  for (final (src, tgt) in directions) {
    final key = '$src-$tgt';
    coverage[key] = switch (opusMtRoute(installed, false, src, tgt)) {
      'pair' => OpusMtCoverage.pair,
      'pivot' => OpusMtCoverage.pivot,
      _ => OpusMtCoverage.fallback,
    };
    if (coverage[key] != OpusMtCoverage.fallback) continue;
    if (published.contains(key)) {
      want.add(key);
    } else if (src != 'en' &&
        tgt != 'en' &&
        published.contains('$src-en') &&
        published.contains('en-$tgt')) {
      for (final half in ['$src-en', 'en-$tgt']) {
        if (!installed.contains(half)) want.add(half);
      }
    }
  }
  return OpusMtPlan(coverage: coverage, toDownload: want.toList()..sort());
}
