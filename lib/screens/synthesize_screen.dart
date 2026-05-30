import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../services/voice_baking_service.dart';

import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
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

  @override
  ConsumerState<SynthesizeScreen> createState() => _SynthesizeScreenState();
}

class _SynthesizeScreenState extends ConsumerState<SynthesizeScreen> {
  final _textController = TextEditingController();
  final _refTextController = TextEditingController();
  final _instructController = TextEditingController();
  final _player = AudioPlayer();

  List<ModelInfo> _all = const [];
  bool _loading = true;
  bool _busy = false;

  String? _selectedModel;
  String? _selectedVoice;
  String? _selectedCodec;
  String? _selectedSpeaker;
  /// User-supplied reference WAV for runtime cloning (qwen3-tts Base,
  /// vibevoice-1.5b, indextts). Takes priority over the catalog-voice
  /// dropdown; pair with `_refTextController` for backends that need a
  /// transcript of the reference.
  String? _customVoiceWavPath;
  File? _lastWav;

  // CrispASR 0.6 TTS knobs.
  bool _trimSilence = false;
  double _speed = 1.0;
  bool _showAdvanced = false;
  // CrispASR 0.6.1 sampling knobs. Defaults that mirror the upstream
  // C-side defaults so untouched sliders behave like the historical
  // synthesize() call.
  double _temperature = 0.8;
  double _topP = 1.0;
  double _cfgWeight = 0.5;
  double _exaggeration = 0.5;
  int _ttsSteps = 10;
  // CrispASR 0.6 chatterbox extras — wired from tts_service.dart's
  // `synthesize()` parameters but not previously surfaced. Each is
  // null-on-default so the service forwards the C-side defaults
  // when the user hasn't touched the slider.
  double _minP = 0.0;
  double _repetitionPenalty = 1.0;
  int _maxSpeechTokens = 1000;

  @override
  void initState() {
    super.initState();
    // §5.1.12 — seed from wizard hand-off when present. The
    // user can still clear / change these in the existing UI;
    // we only set them once on screen-open.
    final wav = widget.initialVoiceWavPath;
    if (wav != null && wav.isNotEmpty) {
      _customVoiceWavPath = wav;
    }
    final rt = widget.initialRefText;
    if (rt != null && rt.isNotEmpty) {
      _refTextController.text = rt;
    }
    _refresh();
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
    setState(() => _loading = true);
    try {
      final svc = ref.read(modelServiceProvider);
      // Probe the C-side registry so any TTS backend the bundled
      // libcrispasr knows about shows up here without a code change.
      svc.refreshFromCrispasrRegistry();
      _all = await svc.getWhisperCppModels();
      // Auto-select the first downloaded TTS model + matching voice/codec.
      final ttsDownloaded =
          _all.where((m) => m.kind == ModelKind.tts && m.isDownloaded).toList();
      if (ttsDownloaded.isNotEmpty) {
        _selectedModel ??= ttsDownloaded.first.name;
        _autoSelectCompanions();
      }
    } catch (e, st) {
      Log.instance
          .w('synth', 'failed to refresh model list', error: e, stack: st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    setState(() => _selectedVoice = name);
    if (picked.isDownloaded) return;
    await _downloadCompanion(picked);
  }

  Future<void> _onCodecPicked(String? name, List<ModelInfo> codecs) async {
    if (name == null) return;
    final picked = codecs.firstWhere(
      (m) => m.name == name,
      orElse: () => codecs.first,
    );
    setState(() => _selectedCodec = name);
    if (picked.isDownloaded) return;
    await _downloadCompanion(picked);
  }

  /// Shared download path for voice / codec companions picked from the
  /// inline dropdowns. Surfaces a snackbar with a progress percentage so
  /// the user knows the work is happening; refreshes the model list when
  /// done so the "(not downloaded)" suffix clears.
  Future<void> _downloadCompanion(ModelInfo info) async {
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
    final modelDef =
        ref.read(modelServiceProvider).lookupDefinition(_selectedModel ?? '');
    if (modelDef == null) return;
    final voices = _all.where((m) =>
        m.kind == ModelKind.voice &&
        m.backend == modelDef.backend &&
        m.isDownloaded);
    final codecs = _all.where((m) =>
        m.kind == ModelKind.codec &&
        m.backend == modelDef.backend &&
        m.isDownloaded);
    _selectedVoice = voices.isEmpty ? null : voices.first.name;
    _selectedCodec = codecs.isEmpty ? null : codecs.first.name;
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
    final text = _textController.text.trim();
    if (text.isEmpty || _selectedModel == null) return;
    setState(() {
      _busy = true;
      _lastWav = null;
    });
    final tts = ref.read(ttsServiceProvider);
    try {
      final refText = _refTextController.text.trim();
      final instructPrompt = _instructController.text.trim();
      final status = await tts.prepare(
        modelName: _selectedModel!,
        voiceName: _selectedVoice,
        codecName: _selectedCodec,
        refText: refText.isEmpty ? null : refText,
        speakerName: _selectedSpeaker,
        instructPrompt: instructPrompt.isEmpty ? null : instructPrompt,
        voiceWavPath: _customVoiceWavPath,
      );
      if (!status.ready) {
        if (!mounted) return;
        final l = AppLocalizations.of(context);
        final missing = status.missingModelName ??
            status.missingVoiceName ??
            status.missingCodecName ??
            (status.errorMessage ?? '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.synthMissingDependency(missing))),
        );
        return;
      }

      // Pass the chatterbox-specific knobs unconditionally; the
      // session setters no-op on backends that don't honour each
      // field, so no per-backend branching needed.
      final audio = await tts.synthesize(
        text,
        trimSilence: _trimSilence,
        speed: _speed,
        ttsSteps: _ttsSteps,
        temperature: _temperature,
        topP: _topP,
        // Skip default-valued knobs so the C-side picks its own
        // backend-default — keeps untouched sliders identical to
        // pre-0.5.1 behaviour. Chatterbox is the only TTS backend
        // that honours these today; others silently ignore.
        minP: _minP > 0 ? _minP : null,
        cfgWeight: _cfgWeight,
        exaggeration: _exaggeration,
        repetitionPenalty:
            (_repetitionPenalty - 1.0).abs() < 1e-3 ? null : _repetitionPenalty,
        maxSpeechTokens: _maxSpeechTokens != 1000 ? _maxSpeechTokens : null,
      );
      if (audio == null) return;
      final wav = await tts.writeWav(audio);
      _lastWav = wav;

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
      if (mounted) setState(() => _busy = false);
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
        allowedExtensions: const ['wav', 'flac', 'mp3'],
      );
      if (pick.isEmpty) return;
      final path = pick.localPaths.first;
      setState(() => _customVoiceWavPath = path);
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

  Future<void> _shareWav() async {
    final wav = _lastWav;
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
    final ttsModels =
        _all.where((m) => m.kind == ModelKind.tts).toList(growable: false);
    final downloadedTtsModels =
        ttsModels.where((m) => m.isDownloaded).toList(growable: false);

    final modelDef = _selectedModel == null
        ? null
        : ref.read(modelServiceProvider).lookupDefinition(_selectedModel!);
    final voices = _all
        .where(
            (m) => m.kind == ModelKind.voice && m.backend == modelDef?.backend)
        .toList(growable: false);
    final codecs = _all
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
      body: _loading
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
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(labelText: l.synthModelLabel),
                      initialValue: _selectedModel,
                      items: downloadedTtsModels
                          .map((m) => DropdownMenuItem(
                                value: m.name,
                                child: Text(m.displayName,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedModel = v;
                        _autoSelectCompanions();
                      }),
                    ),
                    if (voices.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration:
                            InputDecoration(labelText: l.synthVoiceLabel),
                        initialValue: _selectedVoice,
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
                        initialValue: _selectedCodec,
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
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _textController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: l.synthTextHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    initiallyExpanded: _showAdvanced,
                    onExpansionChanged: (v) =>
                        setState(() => _showAdvanced = v),
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
                                  if (_customVoiceWavPath != null)
                                    IconButton(
                                      tooltip: l.synthCustomVoiceClear,
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => setState(
                                          () => _customVoiceWavPath = null),
                                    ),
                                ],
                              ),
                              if (_customVoiceWavPath != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    p.basename(_customVoiceWavPath!),
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
                                label: Text(_customVoiceWavPath == null
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
                        value: _trimSilence,
                        onChanged: (v) => setState(() => _trimSilence = v),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.synthSpeed(_speed.toStringAsFixed(2)),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Slider(
                              value: _speed,
                              min: 0.25,
                              max: 4.0,
                              divisions: 30,
                              label: _speed.toStringAsFixed(2),
                              onChanged: (v) => setState(() => _speed = v),
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
                        label: l.synthTemperature(_temperature.toStringAsFixed(2)),
                        helper: l.synthTemperatureHelper,
                        value: _temperature,
                        min: 0.0,
                        max: 1.5,
                        divisions: 30,
                        onChanged: (v) => setState(() => _temperature = v),
                      ),
                      _buildSampleSlider(
                        label: l.synthTtsSteps(_ttsSteps),
                        helper: l.synthTtsStepsHelper,
                        value: _ttsSteps.toDouble(),
                        min: 1,
                        max: 50,
                        divisions: 49,
                        onChanged: (v) =>
                            setState(() => _ttsSteps = v.round()),
                      ),
                      _buildSampleSlider(
                        label: l.synthCfgWeight(_cfgWeight.toStringAsFixed(2)),
                        helper: l.synthCfgWeightHelper,
                        value: _cfgWeight,
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        onChanged: (v) => setState(() => _cfgWeight = v),
                      ),
                      _buildSampleSlider(
                        label:
                            l.synthExaggeration(_exaggeration.toStringAsFixed(2)),
                        helper: l.synthExaggerationHelper,
                        value: _exaggeration,
                        min: 0.0,
                        max: 1.5,
                        divisions: 15,
                        onChanged: (v) => setState(() => _exaggeration = v),
                      ),
                      _buildSampleSlider(
                        label: l.synthTopP(_topP.toStringAsFixed(2)),
                        helper: l.synthTopPHelper,
                        value: _topP,
                        min: 0.05,
                        max: 1.0,
                        divisions: 19,
                        onChanged: (v) => setState(() => _topP = v),
                      ),
                      _buildSampleSlider(
                        label: l.synthMinP(_minP.toStringAsFixed(2)),
                        helper: l.synthMinPHelper,
                        value: _minP,
                        min: 0.0,
                        max: 0.5,
                        divisions: 50,
                        onChanged: (v) => setState(() => _minP = v),
                      ),
                      _buildSampleSlider(
                        label: l.synthRepetitionPenalty(
                            _repetitionPenalty.toStringAsFixed(2)),
                        helper: l.synthRepetitionPenaltyHelper,
                        value: _repetitionPenalty,
                        min: 1.0,
                        max: 2.0,
                        divisions: 20,
                        onChanged: (v) =>
                            setState(() => _repetitionPenalty = v),
                      ),
                      _buildSampleSlider(
                        label:
                            l.synthMaxSpeechTokens(_maxSpeechTokens),
                        helper: l.synthMaxSpeechTokensHelper,
                        // Slider is double-only; we round for state +
                        // label.
                        value: _maxSpeechTokens.toDouble(),
                        min: 100,
                        max: 4000,
                        divisions: 39,
                        onChanged: (v) =>
                            setState(() => _maxSpeechTokens = v.round()),
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
                          onPressed: _busy ||
                                  _selectedModel == null ||
                                  downloadedTtsModels.isEmpty
                              ? null
                              : _synthesize,
                          icon: _busy
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
                        onPressed: _lastWav == null ? null : _shareWav,
                        icon: const Icon(Icons.ios_share),
                        label: Text(l.synthShareButton),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_lastWav != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.audiotrack),
                        title: Text(p.basename(_lastWav!.path)),
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
                ],
              ),
            ),
    );
  }
}
