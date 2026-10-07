import 'package:crisper_weaver/services/live_translate/live_translate_config.dart';
import 'package:crisper_weaver/services/live_translate/live_translator_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('microphone choice survives saving and can return to system default', () {
    final selected = const LiveTranslateConfig()
        .copyWith(microphoneDeviceId: 'usb-microphone-123');
    final restored = LiveTranslateConfig.fromJson(selected.toJson());
    expect(restored.microphoneDeviceId, 'usb-microphone-123');
    expect(restored.copyWith(fontSize: 40).microphoneDeviceId,
        'usb-microphone-123');
    expect(restored.copyWith(microphoneDeviceId: '').microphoneDeviceId, '');
    expect(LiveTranslateConfig.fromJson(const {}).microphoneDeviceId, '');
  });

  group('routing', () {
    const cfg = LiveTranslateConfig(
      routes: {
        'de': ['en'],
        'en': ['de'],
        'fr': ['de', 'en'],
        'it': [],
      },
      defaultTargets: ['en'],
    );

    test('each spoken language goes to its own targets', () {
      expect(cfg.targetsFor('de'), ['en']);
      expect(cfg.targetsFor('fr'), ['de', 'en']);
      expect(cfg.targetsFor('it'), isEmpty, reason: 'transcribe only');
    });

    test('an unexpected language falls back to the default targets', () {
      expect(cfg.targetsFor('es'), ['en']);
      // …never into itself.
      expect(cfg.targetsFor('en'), ['de']);
      expect(
          const LiveTranslateConfig(routes: {}, defaultTargets: ['en'])
              .targetsFor('en'),
          isEmpty);
    });

    test('display languages: spoken first, then targets, no duplicates', () {
      expect(cfg.displayLanguages, ['de', 'en', 'fr', 'it']);
      expect(cfg.expectedSources, {'de', 'en', 'fr', 'it'});
    });

    test('fixed mode only routes the fixed language', () {
      final f = cfg.copyWith(lidMode: LiveLidMode.fixed, fixedSource: 'fr');
      expect(f.expectedSources, {'fr'});
      expect(f.displayLanguages, ['fr', 'de', 'en']);
      expect(f.needsTranslator, isTrue);
      expect(cfg.copyWith(lidMode: LiveLidMode.fixed, fixedSource: 'it')
          .needsTranslator, isFalse);
    });
  });

  test('JSON round-trip keeps every field', () {
    final c = const LiveTranslateConfig().copyWith(
      lidMode: LiveLidMode.text,
      routes: {
        'fr': ['de', 'en']
      },
      defaultTargets: ['de'],
      asrModel: 'parakeet-tdt-0.6b-v3-q4_k',
      translatorModel: 'hy-mt2-1.8b-q4_k_m',
      audioSource: LiveAudioSource.systemAudio,
      layout: LiveLayout.columns,
      fontSize: 60,
      showSource: false,
      showDrafts: false,
      darkBackground: false,
      hiddenLanguages: {'fr'},
      finalSilenceMs: 1200,
    );
    final r = LiveTranslateConfig.fromJson(c.toJson());
    expect(r.toJson(), c.toJson());
  });

  test('a malformed or foreign config falls back to defaults', () {
    final r = LiveTranslateConfig.fromJson(const {
      'lidMode': 'telepathy',
      'routes': {'de': 'en', 7: ['x']},
      'fontSize': 9999,
      'layout': 3,
    });
    expect(r.lidMode, LiveLidMode.auto);
    expect(r.routes, {'de': <String>[]});
    expect(r.fontSize, LiveTranslateConfig.maxFont);
    expect(r.layout, LiveLayout.stacked);
    expect(LiveTranslateConfig.fromJson(null).routes, isNotEmpty);
  });

  test('LID labels normalise to the routing table\'s codes', () {
    expect(normaliseLangCode('deu_Latn'), 'de');
    expect(normaliseLangCode('__label__fr'), 'fr');
    expect(normaliseLangCode('en-US'), 'en');
    expect(normaliseLangCode('ZH'), 'zh');
    expect(normaliseLangCode('cmn_Hani'), 'zh');
  });

  test('every language keeps one hue, distinct for the usual neighbours', () {
    expect(LanguageColors.hueFor('de'), LanguageColors.hueFor('de'));
    final hues = ['de', 'en', 'fr', 'es', 'it']
        .map(LanguageColors.hueFor)
        .toSet();
    expect(hues.length, 5);
    expect(LanguageColors.of('en', dark: true),
        isNot(LanguageColors.of('en', dark: false)));
    expect(languageAutonym('de'), 'Deutsch');
    expect(languageAutonym('xx'), 'XX');
  });

  group('translation LLM prompts (crispasr_run.cpp presets)', () {
    test('preset follows the file name', () {
      expect(translationPromptPreset('/m/Index-Translate-2B.Q4_K_M.gguf'),
          'index-translate');
      expect(translationPromptPreset('/m/Hy-MT2-1.8B-Q4_K_M.gguf'), 'hy-mt2');
    });

    test('Hy-MT2 is instructed in English, Index-Translate in Chinese', () {
      expect(
          buildTranslationPrompt('hy-mt2', 'Hallo.', 'de', 'en'),
          'Translate the following text into English. Note that you should '
          'only output the translated result without any additional '
          'explanation:\n\nHallo.');
      expect(buildTranslationPrompt('index-translate', 'Hallo.', 'de', 'en'),
          '请将以下德语文本翻译为英语，直接输出翻译结果，不要进行任何解释。\n\nHallo.');
    });

    test('a think block is not translation', () {
      expect(cleanLlmTranslation('<think>\n\n</think>\n\nHello.'), 'Hello.');
      expect(cleanLlmTranslation('<think>still thinking'), '');
      expect(cleanLlmTranslation('  Hello.  '), 'Hello.');
    });
  });
}
