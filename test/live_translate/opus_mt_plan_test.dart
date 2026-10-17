import 'package:crisper_weaver/services/live_translate/live_translate_config.dart';
import 'package:crisper_weaver/services/live_translate/live_translator_worker.dart';
import 'package:crisper_weaver/services/live_translate/opus_mt_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('opusMtRoute — the worker\'s per-sentence choice', () {
    test('own pair first', () {
      expect(opusMtRoute({'de-en'}, true, 'de', 'en'), 'pair');
    });

    test('through English when both halves exist', () {
      expect(opusMtRoute({'fr-en', 'en-de'}, true, 'fr', 'de'), 'pivot');
      // English itself is never pivoted through.
      expect(opusMtRoute({'de-en'}, false, 'en', 'de'), isNull);
    });

    test('the general translator otherwise, nothing without one', () {
      expect(opusMtRoute({'de-en'}, true, 'fr', 'de'), 'general');
      expect(opusMtRoute({'fr-en'}, false, 'fr', 'de'), isNull);
    });
  });

  test('directions follow the routing table and the fixed language', () {
    const cfg = LiveTranslateConfig(routes: {
      'de': ['en'],
      'fr': ['de', 'en'],
    });
    expect(translationDirections(cfg), [('de', 'en'), ('fr', 'de'), ('fr', 'en')]);
    expect(
        translationDirections(
            cfg.copyWith(lidMode: LiveLidMode.fixed, fixedSource: 'fr')),
        [('fr', 'de'), ('fr', 'en')]);
  });

  group('planOpusMt', () {
    const published = {'de-en', 'en-de', 'fr-en', 'fr-de', 'en-tr', 'tr-en'};

    test('downloads the direct pair when it is published', () {
      final plan = planOpusMt([('de', 'en'), ('en', 'de')],
          installed: {'de-en'}, published: published);
      expect(plan.coverage['de-en'], OpusMtCoverage.pair);
      expect(plan.coverage['en-de'], OpusMtCoverage.fallback);
      expect(plan.toDownload, ['en-de']);
    });

    test('downloads the missing English half for a pair with no model', () {
      // de→tr was never released: de→en (installed) + en→tr.
      final plan = planOpusMt([('de', 'tr')],
          installed: {'de-en'}, published: published);
      expect(plan.coverage['de-tr'], OpusMtCoverage.fallback);
      expect(plan.toDownload, ['en-tr']);
    });

    test('an installed pivot counts as covered', () {
      final plan = planOpusMt([('de', 'tr')],
          installed: {'de-en', 'en-tr'}, published: published);
      expect(plan.coverage['de-tr'], OpusMtCoverage.pivot);
      expect(plan.complete, isTrue);
    });

    test('a direction with no Opus-MT path at all asks for nothing', () {
      final plan = planOpusMt([('ja', 'de')],
          installed: const {}, published: published);
      expect(plan.coverage['ja-de'], OpusMtCoverage.fallback);
      expect(plan.toDownload, isEmpty);
    });

    test('shared halves are downloaded once', () {
      final plan = planOpusMt([('de', 'tr'), ('fr', 'tr')],
          installed: const {}, published: {'de-en', 'fr-en', 'en-tr'});
      expect(plan.toDownload, ['de-en', 'en-tr', 'fr-en']);
    });
  });
}
