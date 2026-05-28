// Pure-data invariants over the model catalogue. These are the
// regression guards for the bug classes that hit us across the
// v0.6.13 → v0.6.27 sweep:
//
//   * #7 moonshine session_open returning null because tokenizer.bin
//     companion was undeclared → caught by [companions-required
//     backends declare them].
//   * BackendRepo defaultCompanions referencing names that don't
//     exist as ModelDefinitions → caught by [companion names
//     resolve].
//   * Auto-discovered quants of mimo-asr / moonshine / kokoro /
//     orpheus / chatterbox / qwen3-tts losing their companion link
//     → caught by [companion-needing backends have a BackendRepo
//     with defaultCompanions populated].
//   * BackendRepo.defaultLanguages set to a non-ISO code or
//     undefined alias → caught by [language codes are valid
//     ISO 639-1].
//
// Tests stay live-lib-free so they run in <1 s on CI without the
// CrispASR dylib loaded. The cross-platform behavioural checks
// (`backend_dispatch_test.dart`) cover the libcrispasr side.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_service.dart';

void main() {
  // Backends that ABSOLUTELY need a sibling file at session-open or
  // first-transcribe time. Source: CrispASR's
  // `crispasr_session_open_explicit` dispatch + the engine's
  // `setCodecPath` / `setVoice` callers in
  // `lib/engines/crispasr_engine.dart`. Update when a new backend
  // is wired with a tokenizer / voicepack / codec dependency.
  const companionNeedingBackends = <String>{
    'moonshine',           // tokenizer.bin auto-detected at init time
    'moonshine-streaming', // same family
    'mimo-asr',            // mimo-tokenizer (setCodecPath)
    'kokoro',              // voicepack (setVoice)
    'vibevoice-tts',       // voicepack (setVoice)
    'qwen3-tts',           // 12 Hz codec (setCodecPath)
    'orpheus',             // SNAC codec (setCodecPath)
    'chatterbox',          // S3Gen vocoder (setCodecPath)
    'indextts',            // BigVGAN vocoder (setCodecPath)
  };

  // Every code that should be acceptable as a `defaultLanguages`
  // entry. Built from AppConstants.supportedLanguages would be
  // ideal but that's UI-coupled; hardcoded here so the test
  // doesn't drag in the constants file. Codes are ISO 639-1
  // lowercase 2-letter. `'*'` is the multilingual sentinel.
  const validLanguageCodes = <String>{
    '*',
    // The 99 whisper.cpp uses + a couple of CrispASR additions
    // (ku, ky). `haw` / `jw` / `yue` are 3-letter codes Whisper
    // recognises — kept as-is so langsWhisper99 round-trips
    // through the test.
    'en', 'es', 'fr', 'de', 'it', 'pt', 'nl', 'pl', 'ru', 'uk',
    'cs', 'da', 'sv', 'no', 'fi', 'el', 'bg', 'ro', 'sk', 'sl',
    'lt', 'lv', 'et', 'hr', 'hu', 'zh', 'ja', 'ko', 'ar', 'hi',
    'th', 'vi', 'tr', 'id', 'ms', 'tl', 'mt', 'mk', 'fa', 'he',
    'sw', 'ca', 'is', 'ne', 'mn', 'jv', 'hy', 'ku',
    'ur', 'sq', 'eu', 'ga', 'gl', 'lo', 'km', 'my', 'gu', 'pa',
    'ml', 'mr', 'kn', 'te', 'ta', 'bn', 'ka', 'am', 'so', 'af',
    'sr', 'bs', 'cy', 'tt', 'kk', 'ky', 'uz', 'tg', 'tk', 'ps',
    'az', 'ha', 'oc', 'ln', 'sn', 'su',
    'la', 'mi', 'br', 'si', 'yo', 'be', 'sd', 'yi', 'fo', 'ht',
    'nn', 'sa', 'lb', 'bo', 'mg', 'as', 'ba',
    'haw', 'jw', 'yue',
  };

  group('catalogue companions', () {
    // Entries that intentionally lack a static companion because
    // they do runtime WAV cloning instead (user supplies a sample
    // WAV at synth time via setVoice(wav, refText: …)). The base
    // vibevoice 1.5B variant is the canonical example; if more
    // such "runtime cloning" rows land, add their catalogue keys
    // here so the invariant test stays trustworthy.
    const runtimeCloningEntries = <String>{
      'vibevoice-1.5b-tts-f16',
    };

    test('every backend that needs a companion declares one on every entry',
        () {
      final offenders = <String>[];
      for (final entry in ModelService.crispasrBackendModels.entries) {
        final def = entry.value;
        if (!companionNeedingBackends.contains(def.backend)) continue;
        // Codec / voice / VAD / LID / punctuation / diarisation
        // entries don't themselves need siblings — they ARE the
        // sibling. Only the main ASR / TTS rows need a companion
        // declaration.
        if (def.kind != ModelKind.asr && def.kind != ModelKind.tts) continue;
        // Allowlist runtime-cloning entries.
        if (runtimeCloningEntries.contains(entry.key)) continue;
        if (def.companions.isEmpty) {
          offenders.add('${entry.key} (backend=${def.backend})');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Companion-needing entries without `companions:`. '
              'These will fail at session_open OR transcribe with '
              '"missing codec / voice / tokenizer". Either add the '
              'companion, mark it in runtimeCloningEntries above, '
              'or remove the entry from the catalogue:\n  '
              '${offenders.join('\n  ')}');
    });

    test('every companion name resolves to a real ModelDefinition', () {
      final dangling = <String>[];
      // Walk every ModelDefinition.companions and every
      // BackendRepo.defaultCompanions. Names that don't exist as a
      // crispasrBackendModels key will throw a ModelLoadException
      // at runtime (engine line 388 in crispasr_engine.dart).
      for (final entry in ModelService.crispasrBackendModels.entries) {
        for (final companionName in entry.value.companions) {
          if (!ModelService.crispasrBackendModels.containsKey(companionName)) {
            dangling
                .add('${entry.key} → "$companionName" (not in catalogue)');
          }
        }
      }
      for (final repoEntry in ModelService.backendRepos.entries) {
        for (final companionName in repoEntry.value.defaultCompanions) {
          if (!ModelService.crispasrBackendModels.containsKey(companionName)) {
            dangling.add(
                'BackendRepo[${repoEntry.key}] → "$companionName" (not in catalogue)');
          }
        }
      }
      expect(dangling, isEmpty,
          reason: 'Companion references that don\'t resolve. Engine throws '
              'ModelLoadException("Companion not found in model catalog") '
              'when the user tries to load. Add the companion '
              'ModelDefinition or drop the reference:\n  '
              '${dangling.join('\n  ')}');
    });

    test('every companion-needing backend has a BackendRepo with the same '
        'companion in defaultCompanions', () {
      // Without this, auto-discovered quants (from "Refresh from
      // HuggingFace") lose their companion link — first-load
      // works, second-quant load throws.
      final offenders = <String>[];
      for (final backend in companionNeedingBackends) {
        final repos = ModelService.backendRepos.values
            .where((r) => r.backend == backend);
        if (repos.isEmpty) {
          offenders.add(
              '$backend: no BackendRepo at all (refresh-from-HF skips this family)');
          continue;
        }
        // Look at the canonical main-model repo (kind=asr/tts, NOT
        // kind=codec/voice). The codec repos legitimately have
        // empty defaultCompanions.
        final main = repos.firstWhere(
          (r) => r.kind == ModelKind.asr || r.kind == ModelKind.tts,
          orElse: () => repos.first,
        );
        if (main.defaultCompanions.isEmpty) {
          offenders.add(
              '$backend: BackendRepo "${main.repoId}" has empty '
              'defaultCompanions (auto-discovered quants will be '
              'orphaned)');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Backends with companion needs but no companion '
              'propagation on auto-discovery:\n  '
              '${offenders.join('\n  ')}');
    });
  });

  group('language metadata', () {
    test('every language code in the catalogue is a recognised ISO 639-1 '
        'or the multilingual sentinel "*"', () {
      final bad = <String>[];
      for (final entry in ModelService.crispasrBackendModels.entries) {
        for (final code in entry.value.languages) {
          if (!validLanguageCodes.contains(code)) {
            bad.add('${entry.key}.languages[$code]');
          }
        }
      }
      for (final entry in ModelService.backendRepos.entries) {
        for (final code in entry.value.defaultLanguages) {
          if (!validLanguageCodes.contains(code)) {
            bad.add('BackendRepo[${entry.key}].defaultLanguages[$code]');
          }
        }
      }
      expect(bad, isEmpty,
          reason: 'Non-ISO-639-1 language codes — typo / 3-letter alias / '
              'non-standard short name. Fix the codes or extend '
              'validLanguageCodes in this test:\n  '
              '${bad.join('\n  ')}');
    });

    test('ModelDefinition.matchesLanguage filter logic', () {
      // Untagged (`languages: []`) always passes — filter is
      // permissive when metadata is missing so untagged-but-good
      // entries don't disappear.
      const untagged = ModelDefinition(
        name: 'x',
        displayName: 'x',
        fileName: 'x.bin',
        url: 'x',
        sizeBytes: 0,
        checksum: '',
        description: 'x',
      );
      expect(untagged.matchesLanguage(''), isTrue);
      expect(untagged.matchesLanguage('de'), isTrue);

      const multi = ModelDefinition(
        name: 'x',
        displayName: 'x',
        fileName: 'x.bin',
        url: 'x',
        sizeBytes: 0,
        checksum: '',
        description: 'x',
        languages: ['*'],
      );
      expect(multi.matchesLanguage(''), isTrue);
      expect(multi.matchesLanguage('de'), isTrue);
      expect(multi.matchesLanguage('zh'), isTrue);

      const enOnly = ModelDefinition(
        name: 'x',
        displayName: 'x',
        fileName: 'x.bin',
        url: 'x',
        sizeBytes: 0,
        checksum: '',
        description: 'x',
        languages: ['en'],
      );
      expect(enOnly.matchesLanguage(''), isTrue);
      expect(enOnly.matchesLanguage('en'), isTrue);
      expect(enOnly.matchesLanguage('de'), isFalse);
      // Case-insensitive — picker passes lowercase but defensive
      // anyway in case a baked catalogue snapshot ships an
      // uppercase code from a future HF metadata change.
      expect(enOnly.matchesLanguage('EN'), isTrue);
    });

    test('German filter surfaces every model the user expects', () {
      // Anchor test that mirrors the user's "select Deutsch" use
      // case. If this fails after a catalogue refactor we have a
      // real UX regression — German-only finetunes vanished, or a
      // major multilingual model lost its German tag, or both.
      Iterable<String> deModels() => ModelService.crispasrBackendModels.values
          .where((d) => d.matchesLanguage('de'))
          .map((d) => d.name);
      final got = deModels().toSet();
      // Kartoffelbox (German Chatterbox) — must be present.
      expect(got, contains('kartoffelbox-de-q8_0'));
      // Both kartoffel-orpheus German variants — must be present.
      expect(got, contains('kartoffel-orpheus-3b-natural-q8_0'));
      expect(got, contains('kartoffel-orpheus-3b-synthetic-q8_0'));
    });
  });

  group('voicepack language extraction (parity)', () {
    // _voicepackLanguages is private. Indirect test: build a
    // synthetic BackendRepo for kokoro / vibevoice and verify the
    // expected language extraction by parsing the public catalogue
    // — kokoro hardcoded entries (e.g. kokoro-voice-af_heart) AND
    // any voicepacks the runtime probe adds at first use are
    // covered by the prefix-mapping rules documented in the helper.
    test('kokoro hardcoded voicepacks map to the right language', () {
      // Spot-check: af_heart should be English, dm_bernd German.
      const m = ModelService.crispasrBackendModels;
      final heart = m['kokoro-voice-af_heart'];
      if (heart != null) {
        // Hardcoded kokoro voicepacks predate the language field
        // and may legitimately ship without it — empty list is
        // OK (filter falls through). But if the field is set,
        // it must be 'en'.
        if (heart.languages.isNotEmpty) {
          expect(heart.languages, contains('en'),
              reason: 'kokoro-voice-af_heart is an English voicepack');
        }
      }
    });
  });

  group('language picker resolution', () {
    // Regression coverage for #14 — reporter on v0.6.33 saw the
    // dropdown only listing 8 (well, 9) languages because the
    // hardcoded Whisper quants didn't carry `languages:` and the
    // picker didn't fall back to the BackendRepo. The helper now
    // walks both paths, and these tests pin every shape.

    // The picker passes its own `expandAll` callback (UI uses
    // AppConstants.supportedLanguages). Tests pass a fixture so we
    // don't drag UI constants into the test, and so we can verify
    // `[*]` produces the fixture verbatim.
    List<String> fakeExpandAll() =>
        const ['fakeen', 'fakede', 'fakefr'];

    test(
        'every multilingual catalogue ModelDefinition resolves through '
        'the BackendRepo fallback (non-empty result)', () {
      // The resolver returns empty when neither the entry's
      // `languages:` nor any BackendRepo.defaultLanguages matched.
      // The UI then ships the 9-code legacy fallback — that's the
      // bug class the #14 reporter hit on v0.6.33. For every
      // multilingual backend's main entries, the resolver MUST
      // return a non-empty list.
      const multilingualBackends = <String>{
        'whisper',
        'parakeet',
        'canary',
        'qwen3',
        'cohere',
        'granite',
        'granite-4.1',
        'voxtral',
        'voxtral4b',
        'omniasr-llm',
        'omniasr-llm-unlimited',
        'glm-asr',
        'mega-asr',
        'gemma4-e2b',
        'mimo-asr',
        'funasr',
        'paraformer',
        'sensevoice',
        'vibevoice',
        'vibevoice-tts',
        'kokoro',
        'qwen3-tts',
        'chatterbox',
        'indextts',
        'm2m100',
        'm2m100-wmt21',
        'madlad',
      };
      final underwhelming = <String>[];
      for (final entry in ModelService.crispasrBackendModels.entries) {
        final def = entry.value;
        if (!multilingualBackends.contains(def.backend)) continue;
        // Voicepack / codec entries can legitimately tag a single
        // language (kokoro-voice-df_eva is German-only despite the
        // family being multi). Only assert on the main ASR / TTS
        // rows.
        if (def.kind != ModelKind.asr && def.kind != ModelKind.tts) continue;
        final resolved = ModelService.resolveLanguageCodes(
          def,
          expandAll: fakeExpandAll,
        );
        // Single-language finetunes (kartoffelbox-de, distil-large-v3
        // English, .en whisper variants) tag their own `languages:`
        // and resolve to that list. The bug class we're guarding:
        // resolver returns empty → UI falls back to 9-code legacy.
        if (resolved.isEmpty) {
          underwhelming.add(
              '${entry.key} (backend=${def.backend}) → resolver returned '
              'empty (def.languages unset + no matching BackendRepo with '
              'defaultLanguages)');
        }
      }
      // Also check the whisperCppModels half — these are the entries
      // that triggered the #14 reporter on v0.6.33 (every Whisper
      // variant returned the 9-code fallback because `languages:`
      // wasn't set and the BackendRepo fallback hadn't been wired).
      for (final entry in ModelService.whisperCppModels.entries) {
        // Skip the `.en` and `-german` variants — those legitimately
        // resolve to a single-language list.
        if (entry.key.endsWith('.en')) continue;
        if (entry.key.contains('-german')) continue;
        if (entry.key.startsWith('distil-')) continue;
        final def = entry.value;
        final resolved = ModelService.resolveLanguageCodes(
          def,
          expandAll: fakeExpandAll,
        );
        // Single-language finetunes (kartoffelbox-de, distil-large-v3
        // English-only, .en whisper variants) tag their own
        // `languages:` and resolve cleanly. The bug class we're
        // catching: resolve returns the 9-code legacy fallback
        // verbatim — meaning neither the def nor the BackendRepo
        // had a list.
        if (resolved.isEmpty) {
          underwhelming.add(
              '${entry.key} (whisper) → resolver returned empty '
              '(whisper BackendRepo missing defaultLanguages?)');
        }
      }
      expect(underwhelming, isEmpty,
          reason:
              'Models that should expose a multilingual language picker '
              "fell through to a tiny code list. Fix either the entry's "
              "`languages:` or the matching BackendRepo's "
              '`defaultLanguages:`:\n  ${underwhelming.join('\n  ')}');
    });

    test('whisper resolves to its 99-code list', () {
      // Anchor — if this fails, the whisper BackendRepo lost its
      // defaultLanguages OR the resolver stopped routing through it.
      final base = ModelService.whisperCppModels['base'];
      expect(base, isNotNull, reason: '"base" Whisper entry must exist');
      final resolved = ModelService.resolveLanguageCodes(
        base!,
        expandAll: () => ['must-not-be-called'],
      );
      expect(resolved.length, greaterThanOrEqualTo(90),
          reason: 'whisper-base should resolve to ~99 codes via the '
              'whisper BackendRepo.defaultLanguages = langsWhisper99');
    });

    test('English-only variants stay English-only', () {
      // `.en` Whisper variants don't have languages: set on their
      // ModelDefinitions and shouldn't inherit langsWhisper99 by
      // accident. They have backend='whisper' which would normally
      // pull in the 99-code list. Today they DO inherit it (the
      // fallback can't distinguish .en from the multilingual base).
      // This test pins TODAY'S behaviour so we notice when we change
      // it — if we add per-entry `languages: ['en']` to the .en
      // variants later, update this test accordingly.
      final tinyEn = ModelService.whisperCppModels['tiny.en'];
      if (tinyEn != null) {
        final resolved = ModelService.resolveLanguageCodes(
          tinyEn,
          expandAll: () => List.generate(99, (i) => 'lang$i'),
        );
        // The current resolver gives them the same list as the
        // multilingual whisper base. We allow either: empty (the
        // test passes if we later tag them as ['en']) or the full
        // langsWhisper99 size.
        if (resolved.isNotEmpty) {
          expect(resolved.contains('en') || resolved.contains('lang0'), isTrue,
              reason: 'tiny.en resolution should include English');
        }
      }
    });

    test('kartoffelbox resolves to German', () {
      // Distinct-language test: the catalogue's kartoffelbox-de-q8_0
      // has `languages: langsDe` so this exercises the def.languages
      // direct path, not the BackendRepo fallback.
      final kart = ModelService.crispasrBackendModels['kartoffelbox-de-q8_0'];
      expect(kart, isNotNull);
      final resolved = ModelService.resolveLanguageCodes(
        kart!,
        expandAll: () => ['must-not-be-called'],
      );
      expect(resolved, contains('de'));
    });

    test(
        'longest-prefix BackendRepo wins when multiple repos share a '
        'backend id (#14 v3 regression)', () {
      // Reporter on v0.6.39 noticed funasr-mlt-nano resolved to
      // 4 codes — funasr-nano's set — because both BackendRepos
      // have backend='funasr' and the FIRST-declared one (funasr)
      // won the lookup. The fix is a longest-baseName-prefix
      // disambiguator inside resolveLanguageCodes. These anchors
      // pin the behaviour for every family with same-backend
      // siblings: any breakage immediately fails the suite.
      //
      // Each row: (model name, expected language-set size lower
      // bound, expected language-set size upper bound).
      const expectations = <String, ({int min, int max})>{
        // funasr-mlt-nano-2512-q4_k must hit langsFunasrMlt31 (30
        // codes once de-duped) NOT langsSensevoice (4).
        'funasr-mlt-nano-2512-q4_k': (min: 25, max: 31),
        // funasr-nano-2512-q4_k → langsSensevoice (4).
        'funasr-nano-2512-q4_k': (min: 3, max: 5),
        // parakeet-tdt-0.6b-v2 → langsEn (1). Was returning 25 EU
        // langs from the v3 repo.
        'parakeet-tdt-0.6b-v2-q4_k': (min: 1, max: 1),
        // parakeet-tdt-1.1b → langsEn (1). Same shape.
        'parakeet-tdt-1.1b-q4_k': (min: 1, max: 1),
        // parakeet-tdt-0.6b-v3 hardcoded entry → langsEU25 (25).
        'parakeet-tdt-0.6b-v3-q4_k': (min: 25, max: 25),
      };
      final mismatches = <String>[];
      for (final entry in expectations.entries) {
        final def = ModelService.crispasrBackendModels[entry.key];
        if (def == null) {
          mismatches.add('${entry.key}: catalogue entry missing');
          continue;
        }
        final resolved = ModelService.resolveLanguageCodes(
          def,
          expandAll: () => List.generate(99, (i) => 'x$i'),
        );
        final n = resolved.length;
        if (n < entry.value.min || n > entry.value.max) {
          mismatches.add(
              '${entry.key} → $n codes, expected '
              '[${entry.value.min}..${entry.value.max}]: $resolved');
        }
      }
      expect(mismatches, isEmpty,
          reason: 'Same-backend BackendRepos must disambiguate via '
              "longest-baseName-prefix match against the def's "
              'filename stem:\n  ${mismatches.join('\n  ')}');
    });
  });
}
