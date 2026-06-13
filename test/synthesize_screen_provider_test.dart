// Unit tests for SynthesizeScreenNotifier (§8.2).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/synthesize_screen_provider.dart';

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
}
