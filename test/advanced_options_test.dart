// AdvancedOptions is a value class threaded through every transcribe
// call. copyWith must preserve every other field when one is changed,
// or sliders silently reset their neighbours on each rebuild — the
// kind of bug that's easy to introduce when adding a new field and
// hard to spot in the UI.
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/widgets/advanced_options_widget.dart';

void main() {
  group('AdvancedOptions', () {
    test('default construction', () {
      const o = AdvancedOptions();
      expect(o.translate, isFalse);
      expect(o.beamSearch, isFalse);
      expect(o.initialPrompt, '');
      expect(o.vad, isFalse);
      expect(o.restorePunctuation, isFalse);
      expect(o.targetLanguage, '');
      expect(o.askPrompt, '');
      expect(o.temperature, 0.0);
      expect(o.sourceLanguage, '');
      expect(o.bestOf, 1);
    });

    test('copyWith with no args returns identical-valued copy', () {
      const original = AdvancedOptions(
        translate: true,
        beamSearch: true,
        initialPrompt: 'context line',
        vad: true,
        restorePunctuation: true,
        targetLanguage: 'de',
        askPrompt: 'Summarize the audio.',
        temperature: 0.7,
        sourceLanguage: 'en',
      );
      final copy = original.copyWith();
      expect(copy.translate, original.translate);
      expect(copy.beamSearch, original.beamSearch);
      expect(copy.initialPrompt, original.initialPrompt);
      expect(copy.vad, original.vad);
      expect(copy.restorePunctuation, original.restorePunctuation);
      expect(copy.targetLanguage, original.targetLanguage);
      expect(copy.askPrompt, original.askPrompt);
      expect(copy.temperature, original.temperature);
      expect(copy.sourceLanguage, original.sourceLanguage);
    });

    test('sourceLanguage roundtrips through copyWith', () {
      const original = AdvancedOptions(targetLanguage: 'en');
      final updated = original.copyWith(sourceLanguage: 'de');
      expect(updated.sourceLanguage, 'de');
      expect(updated.targetLanguage, 'en');

      final cleared = updated.copyWith(sourceLanguage: '');
      expect(cleared.sourceLanguage, '');
      expect(cleared.targetLanguage, 'en');
    });

    test('bestOf roundtrips through copyWith', () {
      const original = AdvancedOptions();
      final five = original.copyWith(bestOf: 5);
      expect(five.bestOf, 5);

      final back = five.copyWith(bestOf: 1);
      expect(back.bestOf, 1);
    });

    test('copyWith preserves untouched fields when one is changed', () {
      const original = AdvancedOptions(
        translate: true,
        beamSearch: true,
        targetLanguage: 'de',
        temperature: 0.5,
      );
      final adjusted = original.copyWith(temperature: 0.8);
      expect(adjusted.temperature, 0.8);
      expect(adjusted.translate, isTrue);
      expect(adjusted.beamSearch, isTrue);
      expect(adjusted.targetLanguage, 'de');
    });

    test('copyWith allows setting fields back to their defaults', () {
      const original = AdvancedOptions(
        beamSearch: true,
        targetLanguage: 'de',
        temperature: 0.7,
      );
      final reset = original.copyWith(
        beamSearch: false,
        targetLanguage: '',
        temperature: 0.0,
      );
      expect(reset.beamSearch, isFalse);
      expect(reset.targetLanguage, '');
      expect(reset.temperature, 0.0);
    });

    test('capability sets cover the documented backends', () {
      // Translation: shipped backends with `-tl` support today,
      // including the Granite Speech 4.1 family added in the CrispASR
      // 0.6 parity sweep.
      expect(
          AdvancedOptions.translationCapableBackends.containsAll([
            'canary',
            'cohere',
            'voxtral',
            'voxtral4b',
            'qwen3',
            'whisper',
            'granite',
            'granite-4.1',
            'granite-4.1-plus',
            'granite-4.1-nar',
          ]),
          isTrue);
      // Q&A: instruct-tuned audio LLMs — Granite + GLM-ASR joined in
      // the parity sweep.
      expect(
          AdvancedOptions.askCapableBackends.containsAll([
            'voxtral',
            'voxtral4b',
            'qwen3',
            'granite',
            'glm-asr',
          ]),
          isTrue);
      // Temperature: every backend `crispasr_session_set_temperature`
      // honours per the CrispASR CLI surface. Sweep added the LLM
      // backends (voxtral, qwen3, granite, glm-asr, gemma4-e2b,
      // omniasr-llm).
      expect(
          AdvancedOptions.temperatureCapableBackends.containsAll([
            'canary',
            'cohere',
            'parakeet',
            'moonshine',
            'voxtral',
            'voxtral4b',
            'qwen3',
            'granite',
            'glm-asr',
            'gemma4-e2b',
            'omniasr-llm',
          ]),
          isTrue);
      // Source-language: strict superset of translation-capable
      // (every translator accepts a source-lang pin) plus the
      // multilingual ASR backends that auto-detect language and
      // benefit from a pinned override on short clips.
      expect(
          AdvancedOptions.sourceLanguageCapableBackends
              .containsAll(AdvancedOptions.translationCapableBackends),
          isTrue,
          reason: 'every translation-capable backend also accepts a '
              'source-lang pin');
      expect(
          AdvancedOptions.sourceLanguageCapableBackends.containsAll([
            'parakeet',
            'mimo-asr',
            'firered-asr',
            'kyutai-stt',
            'glm-asr',
            'gemma4-e2b',
            'omniasr-llm',
            'omniasr-llm-unlimited',
            'moonshine',
          ]),
          isTrue,
          reason: 'multilingual ASR backends should get the source-lang '
              'picker too — not just translators');
      // English-only / non-ASR backends are excluded — the dropdown
      // would be useless on them.
      for (final excluded in const [
        'wav2vec2',
        'fastconformer-ctc',
        'kokoro',
        'orpheus',
        'chatterbox',
        'indextts',
        'vibevoice-tts',
        'pyannote',
        'firered-punc',
        'fullstop-punc',
      ]) {
        expect(
            AdvancedOptions.sourceLanguageCapableBackends.contains(excluded),
            isFalse,
            reason: '$excluded is English-only / non-ASR — no source-lang');
      }
    });

    test('new CrispASR 0.6 parity fields roundtrip', () {
      const opts = AdvancedOptions();
      // Defaults match the historical behaviour so old call sites
      // see no change.
      expect(opts.vadThreshold, 0.5);
      expect(opts.vadMinSpeechMs, 250);
      expect(opts.vadMinSilenceMs, 100);
      expect(opts.vadSpeechPadMs, 30);
      expect(opts.tdrz, isFalse);
      expect(opts.tokenTimestamps, isFalse);
      expect(opts.enableSpeakerRecognition, isFalse,
          reason: '§5.8.1 — off by default so users without TitaNet '
              'downloaded pay zero cost');
      expect(opts.puncFamily, 'firered');
      // Perf defaults: GPU off (so first run on a Metal box doesn't
      // surprise the user), flash-attn on (matches CrispASR CLI), 4
      // threads (CrispASR's historical n_threads).
      expect(opts.lidUseGpu, isFalse);
      expect(opts.lidFlashAttn, isTrue);
      expect(opts.nThreads, 4);

      final tuned = opts.copyWith(
        vadThreshold: 0.65,
        vadMinSpeechMs: 400,
        tdrz: true,
        tokenTimestamps: true,
        enableSpeakerRecognition: true,
        puncFamily: 'fullstop',
        lidUseGpu: true,
        lidFlashAttn: false,
        nThreads: 8,
      );
      expect(tuned.vadThreshold, 0.65);
      expect(tuned.vadMinSpeechMs, 400);
      expect(tuned.tdrz, isTrue);
      expect(tuned.tokenTimestamps, isTrue);
      expect(tuned.enableSpeakerRecognition, isTrue);
      expect(tuned.puncFamily, 'fullstop');
      expect(tuned.lidUseGpu, isTrue);
      expect(tuned.lidFlashAttn, isFalse);
      expect(tuned.nThreads, 8);
      // Unrelated fields preserved.
      expect(tuned.vadMinSilenceMs, opts.vadMinSilenceMs);
      expect(tuned.bestOf, opts.bestOf);
    });

    group('vocabulary (§5.1.2)', () {
      test('default vocabulary is empty', () {
        expect(const AdvancedOptions().vocabulary, isEmpty);
      });

      test('copyWith roundtrips the vocabulary list', () {
        const o = AdvancedOptions();
        final next = o.copyWith(vocabulary: const ['API', 'gRPC']);
        expect(next.vocabulary, ['API', 'gRPC']);
        // Other fields untouched.
        expect(next.bestOf, o.bestOf);
        expect(next.initialPrompt, o.initialPrompt);
      });

      test('capability sets cover the documented backends', () {
        // Whisper-style — initial_prompt mechanism.
        expect(
            AdvancedOptions.vocabularyViaInitialPromptBackends,
            containsAll(['whisper', 'moonshine']));
        // LLM backends — askPrompt mechanism.
        expect(
            AdvancedOptions.vocabularyViaAskPromptBackends,
            containsAll([
              'voxtral',
              'voxtral4b',
              'qwen3',
              'granite',
              'granite-4.1',
              'glm-asr',
              'kyutai-stt',
              'gemma4-e2b',
              'omniasr-llm',
              'mimo-asr',
            ]));
        // The union (vocabularyCapableBackends) must include both
        // halves.
        expect(
            AdvancedOptions.vocabularyCapableBackends,
            containsAll([
              ...AdvancedOptions.vocabularyViaInitialPromptBackends,
              ...AdvancedOptions.vocabularyViaAskPromptBackends,
            ]));
      });

      test('CTC backends are deliberately excluded', () {
        // These backends have no token-prefill point — biasing
        // would require an external LM rescoring pass which
        // CrisperWeaver doesn't ship.
        for (final ctc in [
          'parakeet',
          'canary',
          'cohere',
          'fastconformer-ctc',
          'wav2vec2',
          'firered-asr',
        ]) {
          expect(AdvancedOptions.vocabularyCapableBackends.contains(ctc),
              isFalse,
              reason:
                  '$ctc is CTC-style and must not appear in the vocab set');
        }
      });
    });

    group('mergeVocabularyIntoPrompt (§5.1.2)', () {
      test('empty vocabulary returns existing unchanged', () {
        expect(
          AdvancedOptions.mergeVocabularyIntoPrompt(
            backend: 'whisper',
            vocabulary: const [],
            existing: 'some prompt',
          ),
          'some prompt',
        );
        expect(
          AdvancedOptions.mergeVocabularyIntoPrompt(
            backend: 'whisper',
            vocabulary: const [],
            existing: '',
          ),
          '',
        );
      });

      test('CTC backend returns existing unchanged regardless of vocab',
          () {
        // Defense-in-depth: even if the caller forgot to gate on
        // vocabularyCapableBackends, the helper refuses to merge.
        expect(
          AdvancedOptions.mergeVocabularyIntoPrompt(
            backend: 'parakeet',
            vocabulary: const ['API'],
            existing: '',
          ),
          '',
        );
        expect(
          AdvancedOptions.mergeVocabularyIntoPrompt(
            backend: 'parakeet',
            vocabulary: const ['API'],
            existing: 'foo',
          ),
          'foo',
        );
      });

      test('whisper: vocab prepended to existing prompt', () {
        expect(
          AdvancedOptions.mergeVocabularyIntoPrompt(
            backend: 'whisper',
            vocabulary: const ['API', 'gRPC'],
            existing: 'tech talk',
          ),
          'Vocabulary: API, gRPC. tech talk',
        );
      });

      test('whisper: empty existing → standalone hint with trailing space',
          () {
        final out = AdvancedOptions.mergeVocabularyIntoPrompt(
          backend: 'whisper',
          vocabulary: const ['kubectl'],
          existing: '',
        );
        expect(out, 'Vocabulary: kubectl. ');
        // Trailing space matters — leaves room for the decoder
        // to continue cleanly without running into the period.
        expect(out.endsWith(' '), isTrue);
      });

      test('LLM-backend: same shape — merge into askPrompt', () {
        expect(
          AdvancedOptions.mergeVocabularyIntoPrompt(
            backend: 'voxtral',
            vocabulary: const ['Anthropic'],
            existing: 'What is being discussed?',
          ),
          'Vocabulary: Anthropic. What is being discussed?',
        );
      });

      test('whitespace-only terms are filtered out', () {
        expect(
          AdvancedOptions.mergeVocabularyIntoPrompt(
            backend: 'whisper',
            vocabulary: const ['  ', 'API', '\t'],
            existing: '',
          ),
          'Vocabulary: API. ',
        );
      });

      test('all whitespace = effectively empty', () {
        // After filtering all terms are empty → existing unchanged.
        expect(
          AdvancedOptions.mergeVocabularyIntoPrompt(
            backend: 'whisper',
            vocabulary: const ['  ', '\t', ''],
            existing: 'user prompt',
          ),
          'user prompt',
        );
      });
    });

    group('§5.1.11 alt-token capture (altN)', () {
      test('default is 0 (off)', () {
        const o = AdvancedOptions();
        expect(o.altN, 0);
      });

      test('copyWith preserves altN', () {
        const original = AdvancedOptions(altN: 3);
        final copy = original.copyWith();
        expect(copy.altN, 3);
      });

      test('copyWith mutates only altN, neighbours intact', () {
        const original =
            AdvancedOptions(altN: 2, beamSearch: true, bestOf: 4);
        final updated = original.copyWith(altN: 5);
        expect(updated.altN, 5);
        // Neighbouring sliders mustn't reset — that's the bug
        // class this whole copyWith test file exists to catch.
        expect(updated.beamSearch, true);
        expect(updated.bestOf, 4);
      });

      test('copyWith can dial altN back to 0', () {
        const original = AdvancedOptions(altN: 5);
        final cleared = original.copyWith(altN: 0);
        expect(cleared.altN, 0);
      });
    });

    group('hotwords (§5.26.2)', () {
      test('default hotwords is empty', () {
        expect(const AdvancedOptions().hotwords, isEmpty);
      });

      test('copyWith roundtrips the hotwords string', () {
        const o = AdvancedOptions();
        final next = o.copyWith(hotwords: 'ACME, TensorFlow');
        expect(next.hotwords, 'ACME, TensorFlow');
        // Other fields untouched.
        expect(next.bestOf, o.bestOf);
        expect(next.vocabulary, o.vocabulary);
      });

      test('hotwordsCapableBackends covers the documented backends', () {
        expect(
            AdvancedOptions.hotwordsCapableBackends,
            containsAll([
              'whisper',
              'moonshine',
              'voxtral',
              'qwen3',
              'granite',
              'granite-4.1',
              'glm-asr',
              'gemma4-e2b',
              'omniasr-llm',
              'mimo-asr',
              'moss-audio',
              'lfm2-audio',
              'mini-omni2',
            ]));
      });

      test('CTC backends excluded from hotwords', () {
        for (final ctc in ['parakeet', 'canary', 'cohere', 'wav2vec2']) {
          expect(
              AdvancedOptions.hotwordsCapableBackends.contains(ctc), isFalse,
              reason: '$ctc is CTC-style — no hotword support');
        }
      });
    });

    group('mergeHotwordsIntoPrompt (§5.26.2)', () {
      test('empty hotwords returns existing unchanged', () {
        expect(
          AdvancedOptions.mergeHotwordsIntoPrompt(
            backend: 'whisper',
            hotwords: '',
            existing: 'some prompt',
          ),
          'some prompt',
        );
      });

      test('whitespace-only hotwords returns existing unchanged', () {
        expect(
          AdvancedOptions.mergeHotwordsIntoPrompt(
            backend: 'qwen3',
            hotwords: '   ',
            existing: 'ask',
          ),
          'ask',
        );
      });

      test('unsupported backend returns existing unchanged', () {
        expect(
          AdvancedOptions.mergeHotwordsIntoPrompt(
            backend: 'parakeet',
            hotwords: 'ACME, TensorFlow',
            existing: '',
          ),
          '',
        );
      });

      test('merges hotwords into empty prompt for LLM backend', () {
        final result = AdvancedOptions.mergeHotwordsIntoPrompt(
          backend: 'qwen3',
          hotwords: 'ACME, TensorFlow',
          existing: '',
        );
        expect(result, contains('ACME, TensorFlow'));
        expect(result, contains('following words may appear'));
      });

      test('merges hotwords before existing prompt', () {
        final result = AdvancedOptions.mergeHotwordsIntoPrompt(
          backend: 'voxtral',
          hotwords: 'Dr. Smith',
          existing: 'Summarize the audio.',
        );
        expect(result, startsWith('The following words'));
        expect(result, endsWith('Summarize the audio.'));
      });

      test('works for whisper (initial_prompt) backends', () {
        final result = AdvancedOptions.mergeHotwordsIntoPrompt(
          backend: 'whisper',
          hotwords: 'kubectl, gRPC',
          existing: '',
        );
        expect(result, contains('kubectl, gRPC'));
      });
    });
  });
}
