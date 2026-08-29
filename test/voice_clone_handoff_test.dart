// #35 — the voice-clone wizard → /synthesize hand-off.
//
// The wizard captures a clip + transcript and pushes them into
// SynthesizeScreen, which then has to pick a model that can actually
// clone from that clip and refuse the combinations CrispASR's
// `crispasr_session_set_voice()` answers with a bare `rc`. Both
// decisions are pure statics so they can be exercised without opening
// an FFI session (same pattern as `resolveSpeakerSelection`).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/providers/synthesize_screen_provider.dart';
import 'package:crisper_weaver/screens/synthesize_screen.dart';
import 'package:crisper_weaver/services/model_service.dart';

ModelInfo _model(
  String name,
  String backend, {
  bool downloaded = true,
  ModelKind kind = ModelKind.tts,
}) =>
    ModelInfo(
      name: name,
      displayName: name,
      size: '1.0 GB',
      sizeBytes: 1024,
      isDownloaded: downloaded,
      description: '',
      modelType: ModelType.whisperCpp,
      backend: backend,
      kind: kind,
    );

void main() {
  group('preferCloneCapableModel', () {
    test('returns null when the only downloaded TTS model cannot clone', () {
      // The onboarding starter: kokoro alone. Handing its setVoice() a
      // WAV is what made the wizard "end with an error".
      final models = [_model('kokoro-q8_0', 'kokoro')];
      expect(SynthesizeScreen.preferCloneCapableModel(models, 'kokoro-q8_0'),
          isNull);
    });

    test('prefers a clone-capable model over the first downloaded one', () {
      final models = [
        _model('kokoro-q8_0', 'kokoro'),
        _model('chatterbox-q8_0', 'chatterbox'),
      ];
      final picked =
          SynthesizeScreen.preferCloneCapableModel(models, 'kokoro-q8_0');
      expect(picked?.name, 'chatterbox-q8_0');
    });

    test('keeps a current selection that can already clone', () {
      final models = [
        _model('chatterbox-q8_0', 'chatterbox'),
        _model('indextts-1.5-q8_0', 'indextts'),
      ];
      final picked = SynthesizeScreen.preferCloneCapableModel(
          models, 'indextts-1.5-q8_0');
      expect(picked?.name, 'indextts-1.5-q8_0',
          reason: 'a valid pick must not be yanked out from under the user');
    });

    test('ignores clone-capable models that are not downloaded', () {
      final models = [
        _model('kokoro-q8_0', 'kokoro'),
        _model('chatterbox-q8_0', 'chatterbox', downloaded: false),
      ];
      expect(SynthesizeScreen.preferCloneCapableModel(models, null), isNull);
    });

    test('ignores non-TTS rows with a clone-capable backend', () {
      // Voicepacks / codecs carry the same backend id as their model.
      final models = [
        _model('chatterbox-voice-emma', 'chatterbox', kind: ModelKind.voice),
        _model('qwen3-tts-tokenizer-12hz', 'qwen3-tts', kind: ModelKind.codec),
      ];
      expect(SynthesizeScreen.preferCloneCapableModel(models, null), isNull);
    });

    test('vibevoice 1.5B base counts as clone-capable', () {
      final models = [_model('vibevoice-1.5b-q8_0', 'vibevoice-1.5b')];
      expect(SynthesizeScreen.preferCloneCapableModel(models, null)?.name,
          'vibevoice-1.5b-q8_0');
    });
  });

  group('cloneReferenceProblem', () {
    test('kokoro cannot clone from a clip at all', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'kokoro', referencePath: '/tmp/ref.wav', refText: 'hello'),
        CloneReferenceProblem.backendCannotClone,
      );
    });

    test('an unknown backend is treated as unable to clone', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: '', referencePath: '/tmp/ref.wav', refText: ''),
        CloneReferenceProblem.backendCannotClone,
      );
    });

    test('qwen3-tts without a transcript is rejected (C side returns -2)', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'qwen3-tts', referencePath: '/tmp/ref.wav', refText: '  '),
        CloneReferenceProblem.refTextRequired,
      );
    });

    test('qwen3-tts with a transcript is accepted', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'qwen3-tts',
            referencePath: '/tmp/ref.wav',
            refText: 'the quick brown fox'),
        isNull,
      );
    });

    test('cosyvoice3 also needs the transcript', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'cosyvoice3-tts',
            referencePath: '/tmp/ref.wav',
            refText: ''),
        CloneReferenceProblem.refTextRequired,
      );
    });

    test('a non-WAV clip is rejected for suffix-routed backends', () {
      // The wizard's picker allows mp3/m4a/…; every backend except
      // chatterbox routes on `ends_with_wav(path)`.
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'indextts',
            referencePath: '/tmp/ref.mp3',
            refText: 'hello'),
        CloneReferenceProblem.wavOnly,
      );
    });

    test('chatterbox accepts any container the audio loader understands', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'chatterbox', referencePath: '/tmp/ref.mp3', refText: ''),
        isNull,
      );
    });

    test('chatterbox clones from audio alone', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'chatterbox', referencePath: '/tmp/ref.wav', refText: ''),
        isNull,
      );
    });

    test('the .wav check is case-insensitive', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'vibevoice-1.5b',
            referencePath: r'C:\clips\REF.WAV',
            refText: ''),
        isNull,
      );
    });

    test('tada is not offered as clone-capable (opt-in behind an env var)', () {
      expect(
        SynthesizeScreen.cloneReferenceProblem(
            backend: 'tada', referencePath: '/tmp/ref.wav', refText: 'hello'),
        CloneReferenceProblem.backendCannotClone,
      );
    });
  });

  group('isAsciiPath', () {
    test('a plain Windows path is ASCII', () {
      expect(SynthesizeScreen.isAsciiPath(r'C:\Users\Bob\Documents\rec.wav'),
          isTrue);
    });

    test('spaces do not make a path non-ASCII', () {
      expect(
          SynthesizeScreen.isAsciiPath(r'C:\Users\Bob\My Recordings\rec.wav'),
          isTrue);
    });

    test('an umlaut in the profile name is not ASCII', () {
      // The Windows CRT reads the narrow char* we pass in the ANSI code
      // page, so this path cannot be fopen'd by the engine at all.
      expect(SynthesizeScreen.isAsciiPath(r'C:\Users\Jörg\Documents\rec.wav'),
          isFalse);
    });

    test('a CJK profile name is not ASCII', () {
      expect(SynthesizeScreen.isAsciiPath(r'C:\Users\张伟\rec.wav'), isFalse);
    });
  });

  group('wizard hand-off state', () {
    test('the reference clip and transcript survive as screen state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(synthesizeScreenProvider.notifier);

      // What SynthesizeScreen.initState does with `initialVoiceWavPath`.
      n.setCustomVoiceWavPath(r'C:\Users\Bob\Documents\recording_1.wav');
      expect(container.read(synthesizeScreenProvider).customVoiceWavPath,
          r'C:\Users\Bob\Documents\recording_1.wav');

      // …and what the card above the Synthesize button clears.
      n.setCustomVoiceWavPath(null);
      expect(container.read(synthesizeScreenProvider).customVoiceWavPath,
          isNull);
    });

    test('a clone reference plus a stale preset speaker is a real state', () {
      // Guards the reason _synthesize suppresses speakerName while
      // cloning: prepare() only reaches setVoice() when no speaker is
      // set, so the clone would silently render the preset voice.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(synthesizeScreenProvider.notifier);
      n.setSelectedSpeaker('Ethan');
      n.setCustomVoiceWavPath('/tmp/ref.wav');
      final s = container.read(synthesizeScreenProvider);
      expect(s.selectedSpeaker, 'Ethan');
      expect(s.customVoiceWavPath, '/tmp/ref.wav');
    });
  });
}
