import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pronunciation_lexicon.dart';
import '../native/crispasr_import.dart' as crispasr;
import '../services/voice_baking_service.dart';

import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../providers/synthesize_screen_provider.dart';
import '../services/log_service.dart';
import '../services/model_service.dart';
import '../services/tts_service.dart';
import '../utils/file_picker_util.dart';

/// Text → speech, using whichever CrispASR TTS backend the user has
/// downloaded. Mirrors the structure of the Transcribe screen but
/// streamlined: there's no language picker (the TTS backend infers from
/// text + voicepack), no diarisation, no advanced decoding knobs.
class SynthesizeScreen extends ConsumerStatefulWidget {
  const SynthesizeScreen({
    super.key,
    this.initialVoiceWavPath,
    this.initialRefText,
  });

  /// §5.1.12 — pre-populate the custom-voice WAV field when
  /// arriving from the voice-clone wizard. The wizard pushes
  /// these via GoRouter `extra` so the path doesn't have to
  /// fit in a query parameter.
  final String? initialVoiceWavPath;
  final String? initialRefText;

  /// #17 — decide which preset speaker should be selected given the
  /// freshly-enumerated [speakers] and the [current] selection:
  ///   * empty list → `null` (the backend has no preset-speaker contract);
  ///   * a still-valid [current] choice is preserved across re-enumeration;
  ///   * otherwise auto-pick the first, so a one-tap synth Just Works and
  ///     CustomVoice never synthesises silence for want of a speaker.
  /// Pure + static so the selection contract is unit-testable without
  /// opening an FFI session (mirrors
  /// [TranscriptionOutputWidget.replaceFirstWholeWord]).
  static String? resolveSpeakerSelection(
      List<String> speakers, String? current) {
    if (speakers.isEmpty) return null;
    if (current != null && speakers.contains(current)) return current;
    return speakers.first;
  }

  @override
  ConsumerState<SynthesizeScreen> createState() => _SynthesizeScreenState();
}

class _SynthesizeScreenState extends ConsumerState<SynthesizeScreen> {
  final _textController = TextEditingController();
  final _refTextController = TextEditingController();
  final _instructController = TextEditingController();
  final _player = AudioPlayer();

  /// Backends that may expose preset speakers. We only open the model to
  /// enumerate speakers for these — opening kokoro / vibevoice / chatterbox
  /// just to discover an always-empty speaker list would be wasted work.
  static const _speakerCapableBackends = {'orpheus', 'qwen3-tts'};

  /// Backends with integer-indexed speakers (melotts, piper, fastpitch).
  /// Uses setSpeakerID(int) instead of setSpeakerName(String).
  static const _speakerIdCapableBackends = {'melotts', 'piper', 'fastpitch'};

  /// Backends that support speech-to-speech at the C level.
  static const _s2sCapableBackends = {'lfm2-audio', 'mini-omni2'};

  @override
  void initState() {
    super.initState();
    // §5.1.12 — seed from wizard hand-off when present. The
    // user can still clear / change these in the existing UI;
    // we only set them once on screen-open.
    final wav = widget.initialVoiceWavPath;
    if (wav != null && wav.isNotEmpty) {
      ref.read(synthesizeScreenProvider.notifier).setCustomVoiceWavPath(wav);
    }
    final rt = widget.initialRefText;
    if (rt != null && rt.isNotEmpty) {
      _refTextController.text = rt;
    }
    _refresh();
    _loadLexicon();
  }

  /// §5.25.9 — Load pronunciation lexicon from disk and inject into TTS.
  Future<void> _loadLexicon() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final loaded = await PronunciationLexicon.load(docs.path);
      if (!mounted) return;
      ref.read(synthesizeScreenProvider.notifier).setLexicon(loaded);
      ref.read(ttsServiceProvider).lexicon = loaded;
    } catch (e) {
      Log.instance.w('synth', 'Failed to load lexicon: $e');
    }
  }

  /// §5.25.9 — Show dialog to add a new lexicon entry.
  Future<void> _addLexiconEntry() async {
    final wordCtrl = TextEditingController();
    final replacementCtrl = TextEditingController();
    bool isIpa = false;
    final l = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.synthLexiconAddTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordCtrl,
                decoration: InputDecoration(
                  labelText: l.synthLexiconWordLabel,
                  hintText: l.synthLexiconWordHint,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: replacementCtrl,
                decoration: InputDecoration(
                  labelText: l.synthLexiconPronunciationLabel,
                  hintText: l.synthLexiconPronunciationHint,
                ),
              ),
              SwitchListTile(
                title: Text(l.synthLexiconIpaLabel),
                value: isIpa,
                onChanged: (v) => setDialogState(() => isIpa = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.add),
            ),
          ],
        ),
      ),
    );
    if (result != true || wordCtrl.text.isEmpty) return;
    final entry = LexiconEntry(
      word: wordCtrl.text,
      replacement: replacementCtrl.text,
      isIpa: isIpa,
    );
    final updated = (ref.read(synthesizeScreenProvider).lexicon ?? const PronunciationLexicon()).put(entry);
    final docs = await getApplicationDocumentsDirectory();
    await updated.save(docs.path);
    if (!mounted) return;
    ref.read(synthesizeScreenProvider.notifier).setLexicon(updated);
    ref.read(ttsServiceProvider).lexicon = updated;
  }

  /// §5.25.9 — Remove a lexicon entry by word.
  Future<void> _removeLexiconEntry(String word) async {
    final lexicon = ref.read(synthesizeScreenProvider).lexicon;
    if (lexicon == null) return;
    final updated = lexicon.remove(word);
    final docs = await getApplicationDocumentsDirectory();
    await updated.save(docs.path);
    if (!mounted) return;
    ref.read(synthesizeScreenProvider.notifier).setLexicon(updated);
    ref.read(ttsServiceProvider).lexicon = updated;
  }

  @override
  void dispose() {
    _textController.dispose();
    _refTextController.dispose();
    _instructController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final n = ref.read(synthesizeScreenProvider.notifier);
    n.setLoading(true);
    try {
      final svc = ref.read(modelServiceProvider);
      // Probe the C-side registry so any TTS backend the bundled
      // libcrispasr knows about shows up here without a code change.
      svc.refreshFromCrispasrRegistry();
      final all = await svc.getWhisperCppModels();
      n.setAllModels(all);
      // Auto-select the first downloaded TTS model + matching voice/codec.
      final ttsDownloaded =
          all.where((m) => m.kind == ModelKind.tts && m.isDownloaded).toList();
      if (ttsDownloaded.isNotEmpty) {
        final current = ref.read(synthesizeScreenProvider).selectedModel;
        if (current == null) n.setSelectedModel(ttsDownloaded.first.name);
        _autoSelectCompanions();
      }
    } catch (e, st) {
      Log.instance
          .w('synth', 'failed to refresh model list', error: e, stack: st);
    } finally {
      if (mounted) n.setLoading(false);
    }
    // NB: we deliberately do NOT enumerate speakers for the auto-selected
    // model here. speakers() requires opening the model, and the open is a
    // synchronous FFI call that would freeze the UI isolate for seconds on
    // a large GGUF (qwen3-tts ~923 MB) right as the screen appears. Speaker
    // discovery happens on an explicit model pick (_loadSpeakers in the
    // dropdown's onChanged), and _synthesize has a fallback that auto-picks
    // a speaker for the auto-selected model so the first synth still works.
  }

  /// Pick the first downloaded voicepack / codec whose backend matches
  /// the selected TTS model. Cheap heuristic — keeps the UX one click
  /// when the user has only one of each.
  /// Voice / codec dropdown change handler. If the user picks an entry
  /// that isn't on disk yet, kick off a download right from here — they
  /// don't need to round-trip through Model Management. Same one-tap
  /// behaviour the Model Management screen has for the "Download" button
  /// row, but inline in the synthesize flow.
  Future<void> _onVoicePicked(String? name, List<ModelInfo> voices) async {
    if (name == null) return;
    final picked = voices.firstWhere(
      (m) => m.name == name,
      orElse: () => voices.first,
    );
    ref.read(synthesizeScreenProvider.notifier).setSelectedVoice(name);
    if (picked.isDownloaded) return;
    await _downloadCompanion(picked);
  }

  Future<void> _onCodecPicked(String? name, List<ModelInfo> codecs) async {
    if (name == null) return;
    final picked = codecs.firstWhere(
      (m) => m.name == name,
      orElse: () => codecs.first,
    );
    ref.read(synthesizeScreenProvider.notifier).setSelectedCodec(name);
    if (picked.isDownloaded) return;
    await _downloadCompanion(picked);
  }

  /// Shared download path for voice / codec companions picked from the
  /// inline dropdowns. Surfaces a snackbar with a progress percentage so
  /// the user knows the work is happening; refreshes the model list when
  /// done so the "(not downloaded)" suffix clears.
  Future<void> _downloadCompanion(ModelInfo info) async {
    Log.instance.i('synth', 'companion download start',
        fields: {'name': info.name, 'backend': info.backend});
    final l10n = AppLocalizations.of(context);
    final svc = ref.read(modelServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.synthDownloadingNamed(info.displayName)),
      duration: const Duration(seconds: 30),
    ));
    try {
      final ok = await svc.downloadWhisperCppModel(info.name);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? l10n.modelsDownloadedOne(info.displayName)
            : l10n.synthDownloadFailedShort(info.displayName)),
      ));
      if (ok) await _refresh();
    } catch (e, st) {
      Log.instance.w('synth', 'companion download failed',
          error: e, stack: st, fields: {'name': info.name});
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(
              l10n.synthDownloadFailedNamed(info.displayName, e.toString())),
        ));
      }
    }
  }

  void _autoSelectCompanions() {
    final n = ref.read(synthesizeScreenProvider.notifier);
    final s = ref.read(synthesizeScreenProvider);
    // Model changed — drop any stale speaker selection; _loadSpeakers
    // repopulates for the new model.
    n.resetSpeakerState();
    final modelDef =
        ref.read(modelServiceProvider).lookupDefinition(s.selectedModel ?? '');
    if (modelDef == null) return;
    final voices = s.allModels.where((m) =>
        m.kind == ModelKind.voice &&
        m.backend == modelDef.backend &&
        m.isDownloaded);
    final codecs = s.allModels.where((m) =>
        m.kind == ModelKind.codec &&
        m.backend == modelDef.backend &&
        m.isDownloaded);
    n.setSelectedVoice(voices.isEmpty ? null : voices.first.name);
    n.setSelectedCodec(codecs.isEmpty ? null : codecs.first.name);
  }

  /// #17 — open the selected model (when its backend can carry preset
  /// speakers) to enumerate the baked speaker names, and auto-select the
  /// first so qwen3-tts CustomVoice / orpheus never synthesise silence for
  /// want of a `setSpeakerName()` call. No-op for backends without preset
  /// speakers, and degrades quietly when companions aren't downloaded yet
  /// (the session can't open → no speakers → the dropdown stays hidden and
  /// the existing missing-companion flow guides the user).
  ///
  /// Triggered on an explicit model pick (not on screen open) because the
  /// underlying open is a synchronous FFI call — running it only when the
  /// user deliberately selects a speaker-capable model keeps the heavy work
  /// at a moment the user expects it.
  Future<void> _loadSpeakers() async {
    final s = ref.read(synthesizeScreenProvider);
    final modelName = s.selectedModel;
    if (modelName == null) return;
    final svc = ref.read(modelServiceProvider);
    final backend = svc.lookupDefinition(modelName)?.backend;
    // Named-speaker backends (orpheus, qwen3-tts CustomVoice).
    if (backend != null && _speakerIdCapableBackends.contains(backend)) {
      return _loadSpeakersById();
    }
    if (backend == null || !_speakerCapableBackends.contains(backend)) {
      return;
    }
    final n = ref.read(synthesizeScreenProvider.notifier);
    n.setLoadingSpeakers(true);
    try {
      final tts = ref.read(ttsServiceProvider);
      final status = await tts.prepare(
        modelName: modelName,
        voiceName: s.selectedVoice,
        codecName: s.selectedCodec,
      );
      if (!mounted) return;
      final speakers = status.ready ? tts.presetSpeakers : const <String>[];
      n.setPresetSpeakers(speakers);
      // Auto-pick the first speaker so a one-tap synth Just Works;
      // preserve a still-valid prior choice across rebuilds.
      n.setSelectedSpeaker(
          SynthesizeScreen.resolveSpeakerSelection(speakers, ref.read(synthesizeScreenProvider).selectedSpeaker));
    } catch (e, st) {
      Log.instance.w('synth', 'speaker enumeration failed',
          error: e, stack: st, fields: {'model': modelName});
    } finally {
      if (mounted) n.setLoadingSpeakers(false);
    }
  }

  /// Load speaker count for integer-indexed backends (melotts, piper,
  /// fastpitch). Opens the session to query nSpeakers.
  Future<void> _loadSpeakersById() async {
    final s = ref.read(synthesizeScreenProvider);
    final modelName = s.selectedModel;
    if (modelName == null) return;
    final n = ref.read(synthesizeScreenProvider.notifier);
    n.setLoadingSpeakers(true);
    try {
      final tts = ref.read(ttsServiceProvider);
      final status = await tts.prepare(
        modelName: modelName,
        voiceName: s.selectedVoice,
        codecName: s.selectedCodec,
      );
      if (!mounted) return;
      if (status.ready) {
        final count = tts.session?.nSpeakers ?? 0;
        n.setNSpeakers(count);
        n.setSelectedSpeakerId(
            (count > 0) ? (s.selectedSpeakerId ?? 0).clamp(0, count - 1) : null);
        // Clear named speakers so the UI shows the ID picker instead.
        n.setPresetSpeakers(const []);
      }
    } catch (e, st) {
      Log.instance.w('synth', 'speaker ID enumeration failed',
          error: e, stack: st, fields: {'model': modelName});
    } finally {
      if (mounted) n.setLoadingSpeakers(false);
    }
  }

  Future<void> _clearPhonemeCache() async {
    final l = AppLocalizations.of(context);
    final tts = ref.read(ttsServiceProvider);
    final ok = await tts.clearPhonemeCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          ok ? l.synthClearPhonemeCacheDone : l.synthClearPhonemeCacheUnsupported),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _synthesize() async {
    final ss = ref.read(synthesizeScreenProvider);
    final sn = ref.read(synthesizeScreenProvider.notifier);
    // §5.26.3 — S2S mode: audio input instead of text.
    if (ss.s2sMode) {
      await _synthesizeS2S();
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty || ss.selectedModel == null) return;
    sn.startSynth();
    final tts = ref.read(ttsServiceProvider);
    try {
      final refText = _refTextController.text.trim();
      final instructPrompt = _instructController.text.trim();
      Log.instance.i('synth', 'prepare', fields: {
        'model': ss.selectedModel ?? '',
        'voice': ss.selectedVoice ?? '',
        'codec': ss.selectedCodec ?? '',
        'speaker': ss.selectedSpeaker ?? '',
        'customWav': ss.customVoiceWavPath != null,
      });
      final status = await tts.prepare(
        modelName: ss.selectedModel!,
        voiceName: ss.selectedVoice,
        codecName: ss.selectedCodec,
        refText: refText.isEmpty ? null : refText,
        speakerName: ss.selectedSpeaker,
        speakerId: ss.selectedSpeakerId,
        instructPrompt: instructPrompt.isEmpty ? null : instructPrompt,
        voiceWavPath: ss.customVoiceWavPath,
      );
      if (!status.ready) {
        Log.instance.w('synth', 'prepare failed', fields: {
          'model': ss.selectedModel ?? '',
          'missing_model': status.missingModelName ?? '',
          'missing_voice': status.missingVoiceName ?? '',
          'missing_codec': status.missingCodecName ?? '',
          'unsupported': status.unsupportedBackend ?? '',
          'error': status.errorMessage ?? '',
        });
        if (!mounted) return;
        final l = AppLocalizations.of(context);
        if (status.unsupportedBackend != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(l.synthBackendUnsupported(status.unsupportedBackend!))),
          );
          return;
        }
        final missing = status.missingModelName ??
            status.missingVoiceName ??
            status.missingCodecName ??
            (status.errorMessage ?? '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.synthMissingDependency(missing))),
        );
        return;
      }

      // #17 — belt-and-suspenders: if the model bakes in preset speakers
      // (CustomVoice / orpheus) but none is selected yet — e.g. the codec
      // finished downloading after _loadSpeakers ran — auto-pick the first
      // and re-open with it. Without a speaker these backends emit no
      // audio. instructPrompt is forced null here so prepare() takes the
      // speaker branch rather than the (mutually-exclusive) instruct one.
      final curSpeaker = ref.read(synthesizeScreenProvider).selectedSpeaker;
      if (curSpeaker == null && tts.presetSpeakers.isNotEmpty) {
        final speakers = tts.presetSpeakers;
        if (mounted) {
          sn.setPresetSpeakers(speakers);
          sn.setSelectedSpeaker(speakers.first);
        }
        await tts.prepare(
          modelName: ss.selectedModel!,
          voiceName: ss.selectedVoice,
          codecName: ss.selectedCodec,
          speakerName: speakers.first,
        );
      }

      final samp = ss.sampling;
      // Pass the chatterbox-specific knobs unconditionally; the
      // session setters no-op on backends that don't honour each
      // field, so no per-backend branching needed.
      final audio = await tts.synthesize(
        text,
        trimSilence: ss.trimSilence,
        speed: ss.speed,
        ttsSteps: samp.ttsSteps,
        temperature: samp.temperature,
        topP: samp.topP,
        // Skip default-valued knobs so the C-side picks its own
        // backend-default — keeps untouched sliders identical to
        // pre-0.5.1 behaviour. Chatterbox is the only TTS backend
        // that honours these today; others silently ignore.
        minP: samp.minP > 0 ? samp.minP : null,
        cfgWeight: samp.cfgWeight,
        exaggeration: samp.exaggeration,
        repetitionPenalty:
            (samp.repetitionPenalty - 1.0).abs() < 1e-3 ? null : samp.repetitionPenalty,
        maxSpeechTokens: samp.maxSpeechTokens != 1000 ? samp.maxSpeechTokens : null,
        seed: samp.ttsSeed != 0 ? samp.ttsSeed : null,
        frequencyPenalty:
            samp.frequencyPenalty.abs() < 1e-3 ? null : samp.frequencyPenalty,
      );
      // #22 — surface a visible error when synthesis produces no audio
      // instead of silently returning. The previous `if (audio == null)
      // return` left the user with "nothing happens".
      if (audio == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context).synthesizeFailed(
                    'no audio produced — try a different model or '
                    'quantisation (q8_0 recommended)'))),
          );
        }
        return;
      }
      final wav = await tts.writeWav(audio);
      sn.setLastWav(wav);

      // Auto-play once synthesised so the user gets immediate feedback.
      try {
        await _player.setFilePath(wav.path);
        await _player.play();
      } catch (e, st) {
        Log.instance.w('synth', 'auto-play failed', error: e, stack: st);
      }
    } catch (e, st) {
      Log.instance.e('synth', 'synthesize failed', error: e, stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)
                  .synthesizeFailed(e.toString()))),
        );
      }
    } finally {
      if (mounted) sn.setBusy(false);
    }
  }

  /// One labeled slider row — shared shape for the TTS sampling knobs
  /// in the Advanced section. Helper text below; padded so consecutive
  /// sliders don't visually collide.
  Widget _buildSampleSlider({
    required String label,
    required String helper,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
          Text(helper,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  /// Show the OS file picker for a WAV reference. Limits to
  /// audio extensions so the iOS picker filters cleanly.
  Future<void> _pickCustomVoice() async {
    try {
      final pick = await pickFilesRobust(
        type: FileType.audio,
        allowedExtensions: const ['wav', 'flac', 'mp3', 'ogg', 'opus', 'm4a'],
      );
      if (pick.isEmpty) return;
      final path = pick.localPaths.first;
      ref.read(synthesizeScreenProvider.notifier).setCustomVoiceWavPath(path);
      Log.instance.i('synth', 'custom voice picked',
          fields: {'path': path, 'cloud_fallback': pick.usedCloudFallback});
    } on FilePickerCloudUriUnsupported catch (e, st) {
      Log.instance.w('synth', 'cloud-URI pick failed even with fallback',
          error: e, stack: st);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.filePickerCloudFileUnsupported)),
        );
      }
    } catch (e, st) {
      Log.instance.w('synth', 'custom voice picker failed',
          error: e, stack: st);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.filePickerFailed(e.toString()))),
        );
      }
    }
  }

  /// §5.26.3 — S2S synthesis: load audio from file, run S2S, play result.
  Future<void> _synthesizeS2S() async {
    final ss = ref.read(synthesizeScreenProvider);
    final sn = ref.read(synthesizeScreenProvider.notifier);
    if (ss.s2sInputPath == null || ss.selectedModel == null) return;
    sn.startSynth();
    final tts = ref.read(ttsServiceProvider);
    try {
      // Prepare the TTS session (loads model + codec).
      final status = await tts.prepare(
        modelName: ss.selectedModel!,
        voiceName: ss.selectedVoice,
        codecName: ss.selectedCodec,
      );
      if (!status.ready) {
        if (!mounted) return;
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l.synthMissingDependency(
                  status.missingModelName ?? status.errorMessage ?? ''))),
        );
        return;
      }

      // Load input audio as 16 kHz mono PCM via crispasr_audio_load.
      final decoded = crispasr.decodeAudioFile(ss.s2sInputPath!);
      final inputPcm = decoded.samples;
      if (inputPcm.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load input audio')),
        );
        return;
      }

      final audio = await tts.speechToSpeech(inputPcm);
      if (audio == null || audio.samples.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('S2S produced no audio')),
        );
        return;
      }

      final wav = await tts.writeWav(audio);
      if (!mounted) return;
      sn.setLastWav(wav);
      await _player.setFilePath(wav.path);
      await _player.play();
    } catch (e, st) {
      Log.instance.e('synth', 's2s error', error: e, stack: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('S2S error: $e')),
      );
    } finally {
      if (mounted) sn.setBusy(false);
    }
  }

  Future<void> _shareWav() async {
    final wav = ref.read(synthesizeScreenProvider).lastWav;
    if (wav == null) return;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(wav.path)],
        subject: 'CrisperWeaver synth',
      ));
    } catch (e, st) {
      Log.instance.w('synth', 'share failed', error: e, stack: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ss = ref.watch(synthesizeScreenProvider);
    final sn = ref.read(synthesizeScreenProvider.notifier);
    final ttsModels =
        ss.allModels.where((m) => m.kind == ModelKind.tts).toList(growable: false);
    final downloadedTtsModels =
        ttsModels.where((m) => m.isDownloaded).toList(growable: false);

    final modelDef = ss.selectedModel == null
        ? null
        : ref.read(modelServiceProvider).lookupDefinition(ss.selectedModel!);
    final voices = ss.allModels
        .where(
            (m) => m.kind == ModelKind.voice && m.backend == modelDef?.backend)
        .toList(growable: false);
    final codecs = ss.allModels
        .where(
            (m) => m.kind == ModelKind.codec && m.backend == modelDef?.backend)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.synthTitle),
        actions: [
          // §5.1.12 — guided clone-a-voice wizard. Always
          // available; the wizard hands back into this screen
          // with the captured WAV + ref text pre-populated.
          IconButton(
            tooltip: l.voiceCloneOpenTooltip,
            icon: const Icon(Icons.record_voice_over_outlined),
            onPressed: () => context.push('/voice-clone'),
          ),
          if (VoiceBakingService.isSupported)
            IconButton(
              tooltip: l.voiceBakeOpenTooltip,
              icon: const Icon(Icons.cake),
              onPressed: () => context.push('/voice-bake'),
            ),
        ],
      ),
      body: ss.loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              // Reserve space for the on-screen keyboard so tapping the
              // text field doesn't overflow the Column on iPad / iPhone.
              // On desktop `viewInsets.bottom` is 0 so this is a no-op.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (downloadedTtsModels.isEmpty)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.synthNoTtsModelsDownloaded),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                // Drop the user straight into the TTS
                                // filter so they don't have to hunt for
                                // it in the kind chips. Await the push
                                // so we can refresh the model list when
                                // the user comes back — without this
                                // the empty-state card stays visible
                                // even after they download a TTS model.
                                onPressed: () async {
                                  await context.push('/models?kind=tts');
                                  if (mounted) await _refresh();
                                },
                                icon: const Icon(Icons.cloud_download_outlined,
                                    size: 18),
                                label: Text(l.synthOpenModelManagement),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // EU AI Act Art. 50 compliance indicator.
                    Card(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.verified_user,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'AI provenance: watermark + WAV metadata + '
                                '${ss.selectedVoice != null ? "beep disclaimer + " : ""}'
                                'MP3 ID3v2 tags embedded automatically',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(labelText: l.synthModelLabel),
                      initialValue: ss.selectedModel,
                      items: downloadedTtsModels
                          .map((m) => DropdownMenuItem(
                                value: m.name,
                                child: Text(m.displayName,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) {
                        sn.setSelectedModel(v);
                        _autoSelectCompanions();
                        // Re-enumerate preset speakers for the new model
                        // (#17); fire-and-forget so the dropdown stays
                        // responsive.
                        _loadSpeakers();
                      },
                    ),
                    if (voices.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration:
                            InputDecoration(labelText: l.synthVoiceLabel),
                        initialValue: ss.selectedVoice,
                        items: voices
                            .map((m) => DropdownMenuItem(
                                  value: m.name,
                                  child: Text(
                                    '${m.displayName}'
                                    '${m.isDownloaded ? "" : "  (not downloaded)"}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) => _onVoicePicked(v, voices),
                      ),
                    ],
                    if (codecs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration:
                            InputDecoration(labelText: l.synthCodecLabel),
                        initialValue: ss.selectedCodec,
                        items: codecs
                            .map((m) => DropdownMenuItem(
                                  value: m.name,
                                  child: Text(
                                    '${m.displayName}'
                                    '${m.isDownloaded ? "" : "  (not downloaded)"}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) => _onCodecPicked(v, codecs),
                      ),
                    ],
                    // #17 — preset-speaker picker for backends that bake
                    // speakers in (qwen3-tts CustomVoice, orpheus). Without
                    // a selection here CustomVoice synthesises silence.
                    if (ss.presetSpeakers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: l.synthSpeakerLabel,
                          helperText: l.synthSpeakerHelper,
                        ),
                        initialValue: ss.selectedSpeaker,
                        items: ss.presetSpeakers
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child:
                                      Text(s, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            sn.setSelectedSpeaker(v),
                      ),
                    ] else if (ss.nSpeakers > 1) ...[
                      // Integer-indexed speaker picker (melotts, piper, fastpitch).
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        decoration: InputDecoration(
                          labelText: l.synthSpeakerLabel,
                          helperText: '${ss.nSpeakers} speakers available (0-indexed)',
                        ),
                        initialValue: ss.selectedSpeakerId ?? 0,
                        items: List.generate(
                          ss.nSpeakers,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('Speaker $i'),
                          ),
                        ),
                        onChanged: (v) =>
                            sn.setSelectedSpeakerId(v),
                      ),
                    ] else if (ss.loadingSpeakers) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                  ],
                  const SizedBox(height: 16),
                  // §5.26.3 — S2S toggle + audio input (visible for
                  // S2S-capable backends only).
                  if (_s2sCapableBackends
                      .contains(modelDef?.backend)) ...[
                    SwitchListTile(
                      title: Text(l.synthS2sToggle),
                      subtitle: Text(l.synthS2sHelper),
                      value: ss.s2sMode,
                      onChanged: (v) => sn.setS2sMode(v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    if (ss.s2sMode) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ss.s2sInputPath != null
                                  ? p.basename(ss.s2sInputPath!)
                                  : l.synthS2sPickAudio,
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final result =
                                  await pickFilesRobust(
                                type: FileType.audio,
                              );
                              if (result.localPaths.isNotEmpty) {
                                sn.setS2sInputPath(result.localPaths.first);
                              }
                            },
                            icon: const Icon(Icons.audio_file, size: 18),
                            label: Text(l.synthS2sBrowse),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (!ss.s2sMode)
                    TextField(
                      controller: _textController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: modelDef?.backend == 'dia'
                            ? l.synthDiaTextHint
                            : l.synthTextHint,
                        helperText: modelDef?.backend == 'dia'
                            ? l.synthDiaHelper
                            : null,
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    initiallyExpanded: ss.showAdvanced,
                    onExpansionChanged: (v) =>
                        sn.setShowAdvanced(v),
                    tilePadding: EdgeInsets.zero,
                    title: Text(l.synthAdvancedSection),
                    children: [
                      // Custom WAV picker — overrides the catalog voicepack
                      // dropdown for backends that support runtime cloning
                      // (qwen3-tts Base, vibevoice-1.5b, indextts,
                      // chatterbox without a baked GGUF).
                      Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.graphic_eq, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(l.synthCustomVoice,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  if (ss.customVoiceWavPath != null)
                                    IconButton(
                                      tooltip: l.synthCustomVoiceClear,
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () =>
                                          sn.setCustomVoiceWavPath(null),
                                    ),
                                ],
                              ),
                              if (ss.customVoiceWavPath != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    p.basename(ss.customVoiceWavPath!),
                                    style: const TextStyle(fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(l.synthCustomVoiceHelper,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey)),
                                ),
                              const SizedBox(height: 4),
                              OutlinedButton.icon(
                                onPressed: _pickCustomVoice,
                                icon: const Icon(Icons.audio_file),
                                label: Text(ss.customVoiceWavPath == null
                                    ? l.synthCustomVoicePick
                                    : l.synthCustomVoiceReplace),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Reference transcript — paired with a WAV voice on
                      // qwen3-tts Base / vibevoice-1.5b for runtime cloning.
                      TextField(
                        controller: _refTextController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: l.synthRefText,
                          helperText: l.synthRefTextHelper,
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Natural-language voice description — qwen3-tts
                      // VoiceDesign only. Silently ignored on others.
                      TextField(
                        controller: _instructController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: l.synthInstruct,
                          helperText: l.synthInstructHelper,
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.synthTrimSilence),
                        subtitle: Text(l.synthTrimSilenceSubtitle,
                            style: const TextStyle(fontSize: 11)),
                        value: ss.trimSilence,
                        onChanged: (v) => sn.setTrimSilence(v),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.synthSpeed(ss.speed.toStringAsFixed(2)),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Slider(
                              value: ss.speed,
                              min: 0.25,
                              max: 4.0,
                              divisions: 30,
                              label: ss.speed.toStringAsFixed(2),
                              onChanged: (v) => sn.setSpeed(v),
                            ),
                            Text(l.synthSpeedHelper,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      // CrispASR 0.6.1 sampling knobs. Most are
                      // chatterbox-specific (cfg_weight, exaggeration,
                      // top_p); other backends silently no-op when
                      // the setter doesn't apply, so we always show
                      // the sliders rather than gating by backend.
                      _buildSampleSlider(
                        label: l.synthTemperature(ss.sampling.temperature.toStringAsFixed(2)),
                        helper: l.synthTemperatureHelper,
                        value: ss.sampling.temperature,
                        min: 0.0,
                        max: 1.5,
                        divisions: 30,
                        onChanged: (v) => sn.setTemperature(v),
                      ),
                      _buildSampleSlider(
                        label: l.synthTtsSteps(ss.sampling.ttsSteps),
                        helper: l.synthTtsStepsHelper,
                        value: ss.sampling.ttsSteps.toDouble(),
                        min: 1,
                        max: 50,
                        divisions: 49,
                        onChanged: (v) =>
                            sn.setTtsSteps(v.round()),
                      ),
                      _buildSampleSlider(
                        label: l.synthCfgWeight(ss.sampling.cfgWeight.toStringAsFixed(2)),
                        helper: l.synthCfgWeightHelper,
                        value: ss.sampling.cfgWeight,
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        onChanged: (v) => sn.setCfgWeight(v),
                      ),
                      _buildSampleSlider(
                        label:
                            l.synthExaggeration(ss.sampling.exaggeration.toStringAsFixed(2)),
                        helper: l.synthExaggerationHelper,
                        value: ss.sampling.exaggeration,
                        min: 0.0,
                        max: 1.5,
                        divisions: 15,
                        onChanged: (v) => sn.setExaggeration(v),
                      ),
                      _buildSampleSlider(
                        label: l.synthTopP(ss.sampling.topP.toStringAsFixed(2)),
                        helper: l.synthTopPHelper,
                        value: ss.sampling.topP,
                        min: 0.05,
                        max: 1.0,
                        divisions: 19,
                        onChanged: (v) => sn.setTopP(v),
                      ),
                      _buildSampleSlider(
                        label: l.synthMinP(ss.sampling.minP.toStringAsFixed(2)),
                        helper: l.synthMinPHelper,
                        value: ss.sampling.minP,
                        min: 0.0,
                        max: 0.5,
                        divisions: 50,
                        onChanged: (v) => sn.setMinP(v),
                      ),
                      _buildSampleSlider(
                        label: l.synthRepetitionPenalty(
                            ss.sampling.repetitionPenalty.toStringAsFixed(2)),
                        helper: l.synthRepetitionPenaltyHelper,
                        value: ss.sampling.repetitionPenalty,
                        min: 1.0,
                        max: 2.0,
                        divisions: 20,
                        onChanged: (v) =>
                            sn.setRepetitionPenalty(v),
                      ),
                      _buildSampleSlider(
                        label:
                            l.synthMaxSpeechTokens(ss.sampling.maxSpeechTokens),
                        helper: l.synthMaxSpeechTokensHelper,
                        // Slider is double-only; we round for state +
                        // label.
                        value: ss.sampling.maxSpeechTokens.toDouble(),
                        min: 100,
                        max: 4000,
                        divisions: 39,
                        onChanged: (v) =>
                            sn.setMaxSpeechTokens(v.round()),
                      ),
                      _buildSampleSlider(
                        label: l.synthSeed(ss.sampling.ttsSeed),
                        helper: l.synthSeedHelper,
                        value: ss.sampling.ttsSeed.toDouble(),
                        min: 0,
                        max: 9999,
                        divisions: 9999,
                        onChanged: (v) =>
                            sn.setTtsSeed(v.round()),
                      ),
                      _buildSampleSlider(
                        label: l.synthFrequencyPenalty(
                            ss.sampling.frequencyPenalty.toStringAsFixed(2)),
                        helper: l.synthFrequencyPenaltyHelper,
                        value: ss.sampling.frequencyPenalty,
                        min: 0.0,
                        max: 2.0,
                        divisions: 40,
                        onChanged: (v) =>
                            sn.setFrequencyPenalty(v),
                      ),
                      const SizedBox(height: 8),
                      // §5.25.9 — Pronunciation lexicon editor.
                      Card(
                        elevation: 0,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.spellcheck, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(l.synthLexiconSectionTitle,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  IconButton(
                                    tooltip: l.synthLexiconAddEntryTooltip,
                                    icon:
                                        const Icon(Icons.add_circle, size: 20),
                                    onPressed: _addLexiconEntry,
                                  ),
                                ],
                              ),
                              if (ss.lexicon != null &&
                                  ss.lexicon!.entries.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                ...(ss.lexicon!.entries.values.map((e) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                          '${e.word} → ${e.replacement}'),
                                      subtitle: e.isIpa
                                          ? const Text('IPA',
                                              style: TextStyle(fontSize: 10))
                                          : null,
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18),
                                        onPressed: () => _removeLexiconEntry(
                                            e.word),
                                      ),
                                    ))),
                              ] else
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    l.synthLexiconEmpty,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Kokoro phoneme cache — purely a runtime
                      // memory knob. Always-visible because the user
                      // doesn't know which backend they're on from
                      // here; calling it on a non-kokoro session is
                      // a no-op upstream.
                      OutlinedButton.icon(
                        icon: const Icon(Icons.cleaning_services_outlined,
                            size: 18),
                        label: Text(l.synthClearPhonemeCache),
                        onPressed: _clearPhonemeCache,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: ss.busy ||
                                  ss.selectedModel == null ||
                                  downloadedTtsModels.isEmpty ||
                                  (ss.s2sMode && ss.s2sInputPath == null) ||
                                  (!ss.s2sMode &&
                                      modelDef?.requiresVoice == true &&
                                      ss.selectedVoice == null &&
                                      ss.customVoiceWavPath == null &&
                                      ss.presetSpeakers.isEmpty)
                              ? null
                              : _synthesize,
                          icon: ss.busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.graphic_eq),
                          label: Text(l.synthRunButton),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: ss.lastWav == null ? null : _shareWav,
                        icon: const Icon(Icons.ios_share),
                        label: Text(l.synthShareButton),
                      ),
                    ],
                  ),
                  if (modelDef?.requiresVoice == true &&
                      ss.selectedVoice == null &&
                      ss.customVoiceWavPath == null &&
                      ss.presetSpeakers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'This model requires a voice reference — download a voice pack or use the voice clone wizard.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (ss.lastWav != null) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.audiotrack),
                        title: Text(p.basename(ss.lastWav!.path)),
                        subtitle: StreamBuilder<Duration?>(
                          stream: _player.durationStream,
                          builder: (_, snap) => Text(snap.data == null
                              ? '—'
                              : '${snap.data!.inMilliseconds / 1000.0} s'),
                        ),
                        trailing: StreamBuilder<PlayerState>(
                          stream: _player.playerStateStream,
                          builder: (_, snap) {
                            final playing = snap.data?.playing ?? false;
                            return IconButton(
                              icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow),
                              onPressed: () async {
                                if (playing) {
                                  await _player.pause();
                                } else {
                                  await _player.seek(Duration.zero);
                                  await _player.play();
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      avatar: Icon(Icons.smart_toy,
                          size: 16,
                          color: Theme.of(context)
                              .colorScheme
                              .onTertiaryContainer),
                      label: Text(l.aiGeneratedAudio),
                      backgroundColor:
                          Theme.of(context).colorScheme.tertiaryContainer,
                      side: BorderSide.none,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
