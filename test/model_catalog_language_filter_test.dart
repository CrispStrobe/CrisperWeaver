// Regression guards for GitHub issue #35 (Windows, Model Management):
//
//   1. Picking "English (en)" in the language dropdown still listed the
//      German and French voicepacks. Two causes: `matchesLanguage` let
//      every untagged row through, and the generated voicepack entries
//      carried their language only inside the description string, never
//      in `languages:`.
//   2. The same voice appeared twice — a hand-written
//      `vibevoice-voice-emma` row alongside the generated
//      `vibevoice-voice-en-Emma_woman` one. Upstream publishes the
//      identical 2 740 832-byte file under both names. Roughly thirty
//      more downloads were listed twice the same way, once under the
//      baked snapshot's auto-generated key and once under the curated
//      catalogue's friendlier one.
//   3. The Voices chips spoke the VibeVoice repo's own tags (jp, kr,
//      sp, in) while the dropdown spoke ISO 639-1 (ja, ko, es, hi), so
//      the two filters could never agree.
//
// Pure data + pure functions — no dylib, no filesystem beyond reading
// the baked JSON asset, so this runs in well under a second on CI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_catalog.dart';
import 'package:crisper_weaver/services/model_service.dart'
    show ModelService;

/// ISO 639-1 codes a voicepack is allowed to claim. Deliberately
/// narrow: voices are hand-curated per family, so a code outside this
/// set means someone pasted a repo-local tag (`jp`) instead of the ISO
/// one (`ja`). Extend it when a family genuinely adds a language.
const _voiceLanguageAllowlist = <String>{
  'ar', 'cs', 'de', 'el', 'en', 'es', 'fi', 'fr', 'he', 'hi', 'hu',
  'id', 'it', 'ja', 'ko', 'nl', 'no', 'pl', 'pt', 'ro', 'ru', 'sv',
  'tr', 'uk', 'vi', 'zh',
};

/// Repo-local tags that must never reach `languages:` — the exact codes
/// that leaked into the voice chips before the fix.
const _forbiddenLanguageCodes = <String>{'jp', 'kr', 'sp', 'in', 'cn', 'gr'};

List<Map<String, dynamic>> _readBakedCatalog() {
  final file = File('assets/models/catalog.json');
  expect(file.existsSync(), isTrue,
      reason: 'assets/models/catalog.json must exist');
  return (jsonDecode(file.readAsStringSync()) as List<dynamic>)
      .cast<Map<String, dynamic>>();
}

/// Every static catalogue row the Models screen renders, keyed by name.
Map<String, ModelDefinition> _staticCatalog() => <String, ModelDefinition>{
      ...ModelCatalog.whisperCppModels,
      ...ModelCatalog.crispasrBackendModels,
      ...ModelCatalog.ttsVoicepacks,
    };

const _voiceTemplate = ModelDefinition(
  name: 'template',
  displayName: 'template',
  fileName: 'template.gguf',
  url: 'https://example.invalid/template.gguf',
  sizeBytes: 0,
  checksum: '',
  description: 'template',
  kind: ModelKind.voice,
);

void main() {
  group('matchesLanguage (issue #35 root cause)', () {
    test('an English filter excludes a German-tagged voice', () {
      final german = _voiceTemplate.copyWith(
        name: 'vibevoice-voice-de-Spk0_man',
        languages: const ['de'],
      );
      expect(german.matchesLanguage('de'), isTrue);
      expect(german.matchesLanguage('en'), isFalse,
          reason: 'a German voice under the English filter is the '
              'exact symptom reported in #35');
      // The "Any" sentinel still shows everything.
      expect(german.matchesLanguage(''), isTrue);
    });

    test('an untagged voice is hidden rather than shown under every '
        'language', () {
      const untaggedVoice = _voiceTemplate;
      expect(untaggedVoice.languages, isEmpty);
      expect(untaggedVoice.matchesLanguage(''), isTrue);
      expect(untaggedVoice.matchesLanguage('en'), isFalse);
      expect(untaggedVoice.matchesLanguage('de'), isFalse);
    });

    test('untagged non-voice rows stay permissive', () {
      // The catalogue is not fully tagged for ASR/TTS/embed/ocr, and
      // hiding an untagged-but-good model is worse than showing it.
      for (final kind in ModelKind.values) {
        if (kind == ModelKind.voice) continue;
        final def = _voiceTemplate.copyWith(kind: kind);
        expect(def.matchesLanguage('en'), isTrue,
            reason: 'untagged ${kind.name} must still pass the filter');
      }
    });

    test('the multilingual sentinel passes any code, voice included', () {
      final multi = _voiceTemplate.copyWith(languages: const ['*']);
      expect(multi.matchesLanguage('en'), isTrue);
      expect(multi.matchesLanguage('zh'), isTrue);
    });

    test('ModelInfo mirrors ModelDefinition semantics', () {
      // The Models screen filters `ModelInfo`, not `ModelDefinition`;
      // the two implementations must not drift apart.
      const cases = <List<String>>[
        <String>[],
        <String>['*'],
        <String>['de'],
        <String>['en', 'de'],
      ];
      for (final langs in cases) {
        for (final kind in ModelKind.values) {
          for (final probe in <String>['', 'en', 'de', 'zh']) {
            final def = _voiceTemplate.copyWith(kind: kind, languages: langs);
            final info = ModelInfo(
              name: def.name,
              displayName: def.displayName,
              size: '0 B',
              sizeBytes: 0,
              isDownloaded: false,
              description: def.description,
              modelType: ModelType.whisperCpp,
              kind: kind,
              languages: langs,
            );
            expect(info.matchesLanguage(probe), def.matchesLanguage(probe),
                reason: 'ModelInfo/ModelDefinition disagree for '
                    'kind=${kind.name} languages=$langs probe="$probe"');
          }
        }
      }
    });
  });

  group('every voicepack carries an ISO 639-1 language', () {
    test('static catalogue voices are tagged', () {
      final untagged = <String>[];
      for (final entry in _staticCatalog().entries) {
        if (entry.value.kind != ModelKind.voice) continue;
        if (entry.value.languages.isEmpty) untagged.add(entry.key);
      }
      expect(untagged, isEmpty,
          reason: 'Voicepacks without `languages:` vanish from every '
              'language filter now that untagged voices no longer pass '
              '(issue #35). Tag them:\n  ${untagged.join('\n  ')}');
    });

    test('baked catalog.json voices are tagged', () {
      final untagged = <String>[];
      for (final item in _readBakedCatalog()) {
        if (item['kind'] != 'voice') continue;
        final langs = (item['languages'] as List<dynamic>?) ?? const [];
        if (langs.isEmpty) untagged.add(item['name'] as String);
      }
      expect(untagged, isEmpty,
          reason: 'The baked asset shipped 33 voices with no `languages` '
              'field at all — the JSON is what the app loads at boot, so '
              'an untagged voice there defeats the filter no matter what '
              'the Dart catalogue says. Re-run '
              '`dart run scripts/bake_models_catalog.dart`:\n  '
              '${untagged.join('\n  ')}');
    });

    test('no voice claims a repo-local tag instead of the ISO code', () {
      final bad = <String>[];
      void check(String name, Iterable<String> langs) {
        for (final code in langs) {
          if (code == '*') continue;
          if (_forbiddenLanguageCodes.contains(code)) {
            bad.add('$name → "$code" (repo-local tag, not ISO 639-1)');
          } else if (!_voiceLanguageAllowlist.contains(code)) {
            bad.add('$name → "$code" (not in the voice language allowlist)');
          }
        }
      }

      for (final entry in _staticCatalog().entries) {
        if (entry.value.kind != ModelKind.voice) continue;
        check(entry.key, entry.value.languages);
      }
      for (final item in _readBakedCatalog()) {
        if (item['kind'] != 'voice') continue;
        check(item['name'] as String,
            ((item['languages'] as List<dynamic>?) ?? const []).cast<String>());
      }
      expect(bad, isEmpty,
          reason: 'Voice language codes must be ISO 639-1 so the chips and '
              'the dropdown share one alphabet:\n  ${bad.join('\n  ')}');
    });

    test('the `[lang=xx]` description tag agrees with `languages`', () {
      // The chips fall back to the description tag for rows whose
      // `languages` never got filled in; the two must never disagree.
      final re = RegExp(r'\[lang=([a-z]+)\]');
      final mismatched = <String>[];
      void check(String name, String description, List<String> langs) {
        final hit = re.firstMatch(description);
        if (hit == null || langs.isEmpty) return;
        if (!langs.contains(hit.group(1))) {
          mismatched.add('$name: description says "${hit.group(1)}", '
              'languages says $langs');
        }
      }

      for (final entry in _staticCatalog().entries) {
        check(entry.key, entry.value.description, entry.value.languages);
      }
      for (final item in _readBakedCatalog()) {
        check(
          item['name'] as String,
          item['description'] as String,
          ((item['languages'] as List<dynamic>?) ?? const []).cast<String>(),
        );
      }
      expect(mismatched, isEmpty, reason: mismatched.join('\n  '));
    });

    test('the VibeVoice voices the repo names jp/kr/sp/in are tagged '
        'ja/ko/es/en', () {
      final v = ModelCatalog.ttsVoicepacks;
      expect(v['vibevoice-voice-jp-Spk0_man']?.languages, ['ja']);
      expect(v['vibevoice-voice-kr-Spk0_woman']?.languages, ['ko']);
      expect(v['vibevoice-voice-sp-Spk0_woman']?.languages, ['es']);
      // `in-` is the repo's tag for Indian English, not Indonesian.
      expect(v['vibevoice-voice-in-Samuel_man']?.languages, ['en']);
    });

    test('filtering the voice catalogue by "en" leaves no non-English '
        'voice behind', () {
      final matched = ModelCatalog.ttsVoicepacks.values
          .where((d) => d.matchesLanguage('en'))
          .map((d) => d.name)
          .toSet();
      expect(matched, contains('vibevoice-voice-en-Emma_woman'));
      expect(matched, contains('vibevoice-voice-in-Samuel_man'));
      expect(matched, isNot(contains('vibevoice-voice-de-Spk0_man')));
      expect(matched, isNot(contains('vibevoice-voice-fr-Spk0_man')));
      expect(matched, isNot(contains('kokoro-voice-df_eva')));
      expect(matched, isNot(contains('kokoro-voice-ff_siwis')));
    });
  });

  group('voicepack language derivation', () {
    test('VibeVoice ids fold through the ISO alias map', () {
      expect(ModelCatalog.voicepackLanguages('vibevoice-tts', 'jp-Spk0_man'),
          ['ja']);
      expect(ModelCatalog.voicepackLanguages('vibevoice-tts', 'kr-Spk1_man'),
          ['ko']);
      expect(ModelCatalog.voicepackLanguages('vibevoice-tts', 'sp-Spk0_woman'),
          ['es']);
      expect(ModelCatalog.voicepackLanguages('vibevoice-tts', 'in-Samuel_man'),
          ['en']);
      expect(ModelCatalog.voicepackLanguages('vibevoice-tts', 'de-Spk0_man'),
          ['de']);
    });

    test('Kokoro ids map off the leading character', () {
      expect(ModelCatalog.voicepackLanguages('kokoro', 'af_heart'), ['en']);
      expect(ModelCatalog.voicepackLanguages('kokoro', 'bm_george'), ['en']);
      expect(ModelCatalog.voicepackLanguages('kokoro', 'df_eva'), ['de']);
      expect(ModelCatalog.voicepackLanguages('kokoro', 'ef_dora'), ['es']);
      expect(ModelCatalog.voicepackLanguages('kokoro', 'ff_siwis'), ['fr']);
      expect(ModelCatalog.voicepackLanguages('kokoro', 'jf_alpha'), ['ja']);
    });

    test('an unrecognised id yields no opinion', () {
      expect(ModelCatalog.voicepackLanguages('kokoro', ''), isEmpty);
      expect(ModelCatalog.voicepackLanguages('kokoro', 'qq_nobody'), isEmpty);
      expect(ModelCatalog.voicepackLanguages('piper', 'whatever'), isEmpty);
      expect(ModelCatalog.voicepackLanguages('vibevoice-tts', 'Emma'), isEmpty);
    });

    test('the HF probe and the offline bake derive the same codes', () {
      // ModelService.voicepackLanguages is what the live probe uses;
      // the bake script calls ModelCatalog.voicepackLanguages. If they
      // ever diverge, a refreshed catalogue silently retags every voice.
      const repo = BackendRepo(
        backend: 'vibevoice-tts',
        repoId: 'cstr/vibevoice-realtime-0.5b-GGUF',
        baseName: 'vibevoice-realtime-0.5b',
        displayPrefix: 'VibeVoice Realtime 0.5B',
        description: 'x',
        voicepackBaseName: 'vibevoice-voice',
      );
      for (final id in const ['jp-Spk0_man', 'de-Spk1_woman', 'en-Emma_woman']) {
        expect(ModelService.voicepackLanguages(repo, id),
            ModelCatalog.voicepackLanguages(repo.backend, id));
      }
    });

    test('normalizeLanguageCode passes ISO codes through untouched', () {
      for (final code in const ['en', 'de', 'ja', 'ko', 'es', 'zh']) {
        expect(ModelCatalog.normalizeLanguageCode(code), code);
      }
      expect(ModelCatalog.normalizeLanguageCode('JP'), 'ja');
      expect(ModelCatalog.normalizeLanguageCode(' kr '), 'ko');
      // Unknown codes degrade to themselves rather than disappearing.
      expect(ModelCatalog.normalizeLanguageCode('xx'), 'xx');
    });
  });

  group('no duplicate downloads (issue #35, the two Emmas)', () {
    late Map<String, ModelDefinition> baked;
    late Map<String, ModelDefinition> visible;

    setUpAll(() {
      baked = <String, ModelDefinition>{
        for (final item in _readBakedCatalog())
          item['name'] as String: ModelDefinition.fromJson(item),
      };
      final suppressed = ModelCatalog.duplicateFileNameEntries(baked: baked);
      visible = <String, ModelDefinition>{
        for (final e in <String, ModelDefinition>{...baked, ..._staticCatalog()}
            .entries)
          if (!suppressed.contains(e.key)) e.key: e.value,
      };
    });

    test('the hand-written vibevoice-voice-emma row is gone', () {
      expect(_staticCatalog().containsKey('vibevoice-voice-emma'), isFalse);
      expect(baked.containsKey('vibevoice-voice-emma'), isFalse);
      // …and the survivor is still there for the companions to point at.
      expect(ModelCatalog.ttsVoicepacks,
          contains('vibevoice-voice-en-Emma_woman'));
    });

    test('no baked entry serves a superseded file (re-bake regression)', () {
      // The HF repo keeps publishing both Emma files, so the bake script
      // and the live probe must skip the legacy name — otherwise every
      // re-bake resurrects the duplicate row this group exists to kill.
      final legacy = ModelCatalog.legacyModelFileRenames.keys.toSet();
      for (final e in baked.entries) {
        expect(legacy.contains(e.value.fileName), isFalse,
            reason: '${e.key} serves superseded file ${e.value.fileName}');
      }
    });

    test('nothing references the removed name any more', () {
      final dangling = <String>[];
      for (final entry in _staticCatalog().entries) {
        for (final c in entry.value.companions) {
          if (c == 'vibevoice-voice-emma') dangling.add(entry.key);
        }
      }
      for (final entry in ModelCatalog.backendRepos.entries) {
        for (final c in entry.value.defaultCompanions) {
          if (c == 'vibevoice-voice-emma') {
            dangling.add('BackendRepo[${entry.key}]');
          }
        }
      }
      expect(dangling, isEmpty,
          reason: 'still pointing at the deleted Emma row: '
              '${dangling.join(', ')}');
    });

    test('every companion reference resolves across the merged catalogue',
        () {
      final all = <String, ModelDefinition>{...baked, ..._staticCatalog()};
      final dangling = <String>[];
      for (final entry in all.entries) {
        for (final c in entry.value.companions) {
          if (!all.containsKey(c)) dangling.add('${entry.key} → "$c"');
        }
      }
      for (final entry in ModelCatalog.backendRepos.entries) {
        for (final c in entry.value.defaultCompanions) {
          if (!all.containsKey(c)) {
            dangling.add('BackendRepo[${entry.key}] → "$c"');
          }
        }
      }
      expect(dangling, isEmpty, reason: dangling.join('\n  '));
    });

    test('no two visible rows share a fileName', () {
      final byFile = <String, List<String>>{};
      for (final e in visible.entries) {
        byFile
            .putIfAbsent(e.value.fileName.toLowerCase(), () => <String>[])
            .add(e.key);
      }
      final dups = byFile.entries.where((e) => e.value.length > 1).toList();
      expect(dups, isEmpty,
          reason: 'Same file offered under two names — the Models screen '
              'lists it twice and the user downloads the same bytes '
              'again:\n  ${dups.map((e) => '${e.key}: ${e.value}').join('\n  ')}');
    });

    test('no two visible rows share a URL', () {
      final byUrl = <String, List<String>>{};
      for (final e in visible.entries) {
        byUrl.putIfAbsent(e.value.url, () => <String>[]).add(e.key);
      }
      final dups = byUrl.entries.where((e) => e.value.length > 1).toList();
      expect(dups, isEmpty,
          reason: 'Same download URL under two names:\n  '
              '${dups.map((e) => '${e.key}: ${e.value}').join('\n  ')}');
    });

    test('the baked asset has no internal fileName or URL collisions', () {
      // `emittedKeys` in the bake script deduped on the generated key
      // only, so one repo matched by two RepoSpecs emitted the same
      // download twice (Orpheus-3b-German-FT-Q8_0).
      final files = <String, String>{};
      final urls = <String, String>{};
      final dups = <String>[];
      for (final item in _readBakedCatalog()) {
        final name = item['name'] as String;
        final f = (item['fileName'] as String).toLowerCase();
        final u = item['url'] as String;
        final priorFile = files.putIfAbsent(f, () => name);
        if (priorFile != name) dups.add('$f: $priorFile + $name');
        final priorUrl = urls.putIfAbsent(u, () => name);
        if (priorUrl != name) dups.add('$u: $priorUrl + $name');
      }
      expect(dups, isEmpty, reason: dups.join('\n  '));
    });

    test('a suppressed duplicate keeps the curated row, not the baked one',
        () {
      final suppressed = ModelCatalog.duplicateFileNameEntries(baked: baked);
      for (final name in suppressed) {
        expect(_staticCatalog().containsKey(name), isFalse,
            reason: 'hand-curated "$name" was suppressed in favour of a '
                'baked row — the priority order is inverted');
      }
    });
  });

  group('legacy file renames', () {
    test('each rename target is a real catalogue entry and the source is '
        'not', () {
      final all = <String, ModelDefinition>{
        ..._staticCatalog(),
        for (final item in _readBakedCatalog())
          item['name'] as String: ModelDefinition.fromJson(item),
      };
      final fileNames =
          all.values.map((d) => d.fileName.toLowerCase()).toSet();
      for (final e in ModelCatalog.legacyModelFileRenames.entries) {
        expect(fileNames, contains(e.value.toLowerCase()),
            reason: 'rename target "${e.value}" is not in the catalogue');
        expect(fileNames, isNot(contains(e.key.toLowerCase())),
            reason: 'legacy name "${e.key}" is still offered as a download; '
                'renaming a file the catalogue still lists would make it '
                'look un-downloaded');
      }
    });

    test('renames do not chain', () {
      // A → B and B → C would need ordering guarantees the migration
      // deliberately does not have.
      for (final target in ModelCatalog.legacyModelFileRenames.values) {
        expect(ModelCatalog.legacyModelFileRenames.containsKey(target), isFalse,
            reason: '"$target" is both a rename target and a rename source');
      }
    });
  });

  group('languages survive the JSON round-trip', () {
    test('every baked entry keeps its languages through fromJson/toJson', () {
      for (final item in _readBakedCatalog()) {
        final def = ModelDefinition.fromJson(item);
        final expected =
            ((item['languages'] as List<dynamic>?) ?? const []).cast<String>();
        expect(def.languages, expected,
            reason: 'fromJson dropped languages for ${item['name']}');
        final reencoded = ModelDefinition.fromJson(
            jsonDecode(jsonEncode(def.toJson())) as Map<String, dynamic>);
        expect(reencoded.languages, expected,
            reason: 'toJson dropped languages for ${item['name']}');
      }
    });

    test('every static catalogue entry survives a round-trip intact', () {
      for (final entry in _staticCatalog().entries) {
        final original = entry.value;
        final restored = ModelDefinition.fromJson(
            jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
        expect(restored.languages, original.languages, reason: entry.key);
        expect(restored.companions, original.companions, reason: entry.key);
        expect(restored.kind, original.kind, reason: entry.key);
        expect(restored.license, original.license, reason: entry.key);
        expect(restored.requiresVoice, original.requiresVoice,
            reason: entry.key);
      }
    });

    test('copyWith preserves requiresVoice', () {
      // `overrideBackend` copies a definition to stamp a resolved
      // backend; dropping requiresVoice there let a Base TTS model
      // claim it needed no voice.
      const base = ModelDefinition(
        name: 'qwen3-tts-base',
        displayName: 'Qwen3-TTS base',
        fileName: 'qwen3-tts-base.gguf',
        url: 'https://example.invalid/qwen3-tts-base.gguf',
        sizeBytes: 1,
        checksum: '',
        description: 'x',
        kind: ModelKind.tts,
        requiresVoice: true,
      );
      expect(base.copyWith(backend: 'qwen3-tts').requiresVoice, isTrue);
      expect(base.copyWith(requiresVoice: false).requiresVoice, isFalse);
    });
  });

  group('baked catalogue language coverage', () {
    test('the asset is no longer language-blind', () {
      // It shipped with zero `languages` fields on all 364 rows, which
      // is what made the dropdown a no-op for everything the baked
      // snapshot owned.
      final entries = _readBakedCatalog();
      final tagged = entries.where((e) => e['languages'] != null).length;
      expect(tagged, greaterThan(entries.length ~/ 2),
          reason: 'only $tagged of ${entries.length} baked entries carry '
              'languages — re-run scripts/bake_models_catalog.dart');
    });

    test('no baked entry carries a repo-local language tag', () {
      final bad = <String>[];
      for (final item in _readBakedCatalog()) {
        for (final code
            in ((item['languages'] as List<dynamic>?) ?? const [])) {
          if (_forbiddenLanguageCodes.contains(code)) {
            bad.add('${item['name']} → "$code"');
          }
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n  '));
    });
  });
}
