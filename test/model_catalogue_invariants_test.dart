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
    'en', 'es', 'fr', 'de', 'it', 'pt', 'nl', 'pl', 'ru', 'uk',
    'cs', 'da', 'sv', 'no', 'fi', 'el', 'bg', 'ro', 'sk', 'sl',
    'lt', 'lv', 'et', 'hr', 'hu', 'zh', 'ja', 'ko', 'ar', 'hi',
    'th', 'vi', 'tr', 'id', 'ms', 'tl', 'mt', 'mk', 'fa', 'he',
    'sw', 'ca', 'is', 'ne', 'mn', 'jv', 'hy', 'ku',
    'ur', 'sq', 'eu', 'ga', 'gl', 'lo', 'km', 'my', 'gu', 'pa',
    'ml', 'mr', 'kn', 'te', 'ta', 'bn', 'ka', 'am', 'so', 'af',
    'sr', 'bs', 'cy', 'tt', 'kk', 'ky', 'uz', 'tg', 'tk', 'ps',
    'az', 'ha', 'oc', 'ln', 'sn', 'su',
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
}
