// Unit tests for SynthesizeScreenNotifier (§8.2).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/synthesize_screen_provider.dart';
import 'package:crisper_weaver/screens/synthesize_screen.dart';

void main() {
  late ProviderContainer container;
  late SynthesizeScreenNotifier n;

  SynthesizeScreenState readState() =>
      container.read(synthesizeScreenProvider);

  setUp(() {
    container = ProviderContainer();
    container.read(synthesizeScreenProvider);
    n = container.read(synthesizeScreenProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('initial state has sensible defaults', () {
    final s = readState();
    expect(s.allModels, isEmpty);
    expect(s.loading, isTrue);
    expect(s.busy, isFalse);
    expect(s.selectedModel, isNull);
    expect(s.selectedVoice, isNull);
    expect(s.selectedCodec, isNull);
    expect(s.selectedSpeaker, isNull);
    expect(s.presetSpeakers, isEmpty);
    expect(s.loadingSpeakers, isFalse);
    expect(s.nSpeakers, 0);
    expect(s.selectedSpeakerId, isNull);
    expect(s.customVoiceWavPath, isNull);
    expect(s.lastWav, isNull);
    expect(s.trimSilence, isFalse);
    expect(s.speed, 1.0);
    expect(s.showAdvanced, isFalse);
    expect(s.s2sMode, isFalse);
    expect(s.s2sInputPath, isNull);
    expect(s.lexicon, isNull);
  });

  test('setLoading updates loading flag', () {
    n.setLoading(false);
    expect(readState().loading, isFalse);
    n.setLoading(true);
    expect(readState().loading, isTrue);
  });

  test('setBusy updates busy flag', () {
    n.setBusy(true);
    expect(readState().busy, isTrue);
  });

  test('setSelectedModel and clear', () {
    n.setSelectedModel('kokoro-q8_0');
    expect(readState().selectedModel, 'kokoro-q8_0');
    n.setSelectedModel(null);
    expect(readState().selectedModel, isNull);
  });

  test('setSelectedVoice and clear', () {
    n.setSelectedVoice('voice-af');
    expect(readState().selectedVoice, 'voice-af');
    n.setSelectedVoice(null);
    expect(readState().selectedVoice, isNull);
  });

  test('setSelectedCodec and clear', () {
    n.setSelectedCodec('codec-x');
    expect(readState().selectedCodec, 'codec-x');
    n.setSelectedCodec(null);
    expect(readState().selectedCodec, isNull);
  });

  test('setSelectedSpeaker and clear', () {
    n.setSelectedSpeaker('Alice');
    expect(readState().selectedSpeaker, 'Alice');
    n.setSelectedSpeaker(null);
    expect(readState().selectedSpeaker, isNull);
  });

  test('setPresetSpeakers updates list', () {
    n.setPresetSpeakers(['A', 'B', 'C']);
    expect(readState().presetSpeakers, ['A', 'B', 'C']);
  });

  test('setNSpeakers and setSelectedSpeakerId', () {
    n.setNSpeakers(5);
    n.setSelectedSpeakerId(3);
    expect(readState().nSpeakers, 5);
    expect(readState().selectedSpeakerId, 3);
    n.setSelectedSpeakerId(null);
    expect(readState().selectedSpeakerId, isNull);
  });

  test('setCustomVoiceWavPath and clear', () {
    n.setCustomVoiceWavPath('/tmp/voice.wav');
    expect(readState().customVoiceWavPath, '/tmp/voice.wav');
    n.setCustomVoiceWavPath(null);
    expect(readState().customVoiceWavPath, isNull);
  });

  test('setTrimSilence updates flag', () {
    n.setTrimSilence(true);
    expect(readState().trimSilence, isTrue);
  });

  test('setSpeed updates speed', () {
    n.setSpeed(1.5);
    expect(readState().speed, 1.5);
  });

  test('setShowAdvanced updates flag', () {
    n.setShowAdvanced(true);
    expect(readState().showAdvanced, isTrue);
  });

  test('setS2sMode updates flag', () {
    n.setS2sMode(true);
    expect(readState().s2sMode, isTrue);
  });

  test('setS2sInputPath and clear', () {
    n.setS2sInputPath('/tmp/input.wav');
    expect(readState().s2sInputPath, '/tmp/input.wav');
    n.setS2sInputPath(null);
    expect(readState().s2sInputPath, isNull);
  });

  // --- Sampling params ---

  test('setTemperature updates sampling temperature', () {
    n.setTemperature(0.5);
    expect(readState().sampling.temperature, 0.5);
  });

  test('setTopP updates sampling topP', () {
    n.setTopP(0.9);
    expect(readState().sampling.topP, 0.9);
  });

  test('setCfgWeight updates sampling cfgWeight', () {
    n.setCfgWeight(1.0);
    expect(readState().sampling.cfgWeight, 1.0);
  });

  test('setExaggeration updates sampling exaggeration', () {
    n.setExaggeration(0.8);
    expect(readState().sampling.exaggeration, 0.8);
  });

  test('setTtsSteps updates sampling ttsSteps', () {
    n.setTtsSteps(25);
    expect(readState().sampling.ttsSteps, 25);
  });

  test('setMinP updates sampling minP', () {
    n.setMinP(0.1);
    expect(readState().sampling.minP, 0.1);
  });

  test('setRepetitionPenalty updates sampling repetitionPenalty', () {
    n.setRepetitionPenalty(1.5);
    expect(readState().sampling.repetitionPenalty, 1.5);
  });

  test('setMaxSpeechTokens updates sampling maxSpeechTokens', () {
    n.setMaxSpeechTokens(2000);
    expect(readState().sampling.maxSpeechTokens, 2000);
  });

  test('setTtsSeed updates sampling ttsSeed', () {
    n.setTtsSeed(42);
    expect(readState().sampling.ttsSeed, 42);
  });

  test('setFrequencyPenalty updates sampling frequencyPenalty', () {
    n.setFrequencyPenalty(0.5);
    expect(readState().sampling.frequencyPenalty, 0.5);
  });

  // --- Bulk operations ---

  test('resetSpeakerState clears speaker fields', () {
    n.setSelectedSpeaker('Alice');
    n.setSelectedSpeakerId(2);
    n.setNSpeakers(5);
    n.setPresetSpeakers(['Alice', 'Bob']);
    n.resetSpeakerState();
    final s = readState();
    expect(s.selectedSpeaker, isNull);
    expect(s.selectedSpeakerId, isNull);
    expect(s.nSpeakers, 0);
    expect(s.presetSpeakers, isEmpty);
  });

  test('startSynth sets busy and clears lastWav', () {
    n.setBusy(false);
    n.startSynth();
    final s = readState();
    expect(s.busy, isTrue);
    expect(s.lastWav, isNull);
  });

  test('sampling params are independent', () {
    n.setTemperature(0.3);
    n.setTopP(0.8);
    n.setTtsSteps(20);
    final samp = readState().sampling;
    expect(samp.temperature, 0.3);
    expect(samp.topP, 0.8);
    expect(samp.ttsSteps, 20);
    // Unchanged defaults preserved
    expect(samp.cfgWeight, 0.5);
    expect(samp.exaggeration, 0.5);
    expect(samp.minP, 0.0);
  });

  test('TtsSamplingParams const default', () {
    const params = TtsSamplingParams();
    expect(params.temperature, 0.8);
    expect(params.topP, 1.0);
    expect(params.cfgWeight, 0.5);
    expect(params.exaggeration, 0.5);
    expect(params.ttsSteps, 10);
    expect(params.minP, 0.0);
    expect(params.repetitionPenalty, 1.0);
    expect(params.maxSpeechTokens, 1000);
    expect(params.ttsSeed, 0);
    expect(params.frequencyPenalty, 0.0);
  });

  // --- Chatterbox emotion tags (§12.1c) ---

  group('chatterboxEmotionTags', () {
    test('defines laugh, whispering, and angry tags', () {
      expect(chatterboxEmotionTags.length, 3);
      expect(chatterboxEmotionTags.map((t) => t.tag),
          containsAll(['[laugh]', '[whispering]', '[angry]']));
    });

    test('all tags have non-empty labels', () {
      for (final tag in chatterboxEmotionTags) {
        expect(tag.label, isNotEmpty);
      }
    });
  });

  group('insertEmotionTag', () {
    test('inserts at cursor in middle of text', () {
      // Cursor after "Hello" (pos 5), before " world":
      // before="Hello" (needs space before), after=" world" (starts with space, no extra)
      // insert = " [laugh]", result = "Hello [laugh] world"
      final (text, pos) =
          SynthesizeScreen.insertEmotionTag('Hello world', 5, '[laugh]');
      expect(text, 'Hello [laugh] world');
      expect(pos, 13); // 5 + " [laugh]".length = 5 + 8 = 13
    });

    test('inserts at end of text', () {
      final (text, pos) =
          SynthesizeScreen.insertEmotionTag('Hello', 5, '[laugh]');
      expect(text, 'Hello [laugh]');
      expect(pos, 13);
    });

    test('inserts at start of text', () {
      final (text, pos) =
          SynthesizeScreen.insertEmotionTag('Hello', 0, '[angry]');
      expect(text, '[angry] Hello');
      expect(pos, 8); // after '[angry] '
    });

    test('inserts into empty text', () {
      final (text, pos) =
          SynthesizeScreen.insertEmotionTag('', 0, '[whispering]');
      expect(text, '[whispering]');
      expect(pos, 12);
    });

    test('does not double-space when cursor is after space', () {
      final (text, _) =
          SynthesizeScreen.insertEmotionTag('Hello ', 6, '[laugh]');
      expect(text, 'Hello [laugh]');
      // No double space before the tag
      expect(text.contains('  '), isFalse);
    });

    test('does not double-space when cursor is before space', () {
      final (text, _) =
          SynthesizeScreen.insertEmotionTag(' world', 0, '[laugh]');
      expect(text, '[laugh] world');
      expect(text.contains('  '), isFalse);
    });

    test('handles newline boundaries', () {
      // Cursor after "Line1" (pos 5), before "\nLine2":
      // before="Line1" (needs space before), after="\nLine2" (starts with \n, no extra)
      final (text, _) =
          SynthesizeScreen.insertEmotionTag('Line1\nLine2', 5, '[laugh]');
      expect(text, 'Line1 [laugh]\nLine2');
    });

    test('no space after newline before tag', () {
      // Cursor after newline (pos 6), before "Line2":
      // before="Line1\n" (ends with \n, no space before), after="Line2"
      final (text, _) =
          SynthesizeScreen.insertEmotionTag('Line1\nLine2', 6, '[laugh]');
      expect(text, 'Line1\n[laugh] Line2');
    });
  });
}
