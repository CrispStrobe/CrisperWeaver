// VoiceCloneWizardScreen — PLAN §5.1.12.
//
// Guided three-step flow for runtime voice cloning on top of
// the existing chatterbox / indextts / qwen3-tts Base / vibevoice
// backends. The synthesize screen already accepts a custom WAV
// + reference-transcript pair; this wizard wraps that surface in
// a linear flow so a first-time user doesn't have to know which
// backends support cloning and which fields go together.
//
// Steps:
//   1. Capture — record a 10 s clip from the mic OR pick an
//      existing audio file (WAV / FLAC / MP3).
//   2. Reference text — what was said in the clip. Required
//      for backends like indextts / vibevoice that need a
//      transcript of the reference for the alignment-based
//      cloner. v1 is type-it-yourself; v2 will auto-fill via
//      a quick ASR pass (deferred to keep the wizard from
//      bundling the transcription stack).
//   3. Hand-off — push to /synthesize with both values pre-
//      populated. The user picks the target text, clone-
//      capable model + voice in the existing screen and runs
//      it from there.
//
// Pure-Dart, cross-platform; reuses AudioService for the
// 10-second mic recording path and FilePicker for "pick an
// existing audio file".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../l10n/generated/app_localizations.dart';
import '../services/audio_service.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../utils/file_picker_util.dart';

/// What step the wizard is on. Linear forward-only flow with a
/// Back button that just decrements the index. Each step owns
/// the validation logic that gates the Next button.
enum _Step { capture, refText, handoff }

class VoiceCloneWizardScreen extends ConsumerStatefulWidget {
  const VoiceCloneWizardScreen({super.key});

  @override
  ConsumerState<VoiceCloneWizardScreen> createState() =>
      _VoiceCloneWizardScreenState();
}

class _VoiceCloneWizardScreenState
    extends ConsumerState<VoiceCloneWizardScreen> {
  _Step _step = _Step.capture;

  // Step 1 state.
  bool _recording = false;
  Timer? _recordCountdownTimer;
  int _recordSecondsLeft = 0;
  /// 10 s is the documented sweet-spot for the chatterbox /
  /// indextts / qwen3-tts cloners — long enough to capture the
  /// timbre, short enough to avoid stitching artefacts in the
  /// reference encoder. Hard-coded for v1; v2 can expose a
  /// slider once we have real-world data on what users want.
  static const int _recordSecondsTarget = 10;
  String? _recordedPath;
  String? _captureError;

  // Step 2 state.
  final _refTextController = TextEditingController();

  // Step 3 / hand-off.
  AudioPlayer? _previewPlayer;
  bool _previewPlaying = false;

  @override
  void dispose() {
    _recordCountdownTimer?.cancel();
    _refTextController.dispose();
    _previewPlayer?.dispose();
    super.dispose();
  }

  // ----- Step 1: capture -----

  Future<void> _startRecording() async {
    Log.instance.i('voice-clone', 'recording start',
        fields: {'target_seconds': _recordSecondsTarget});
    setState(() {
      _captureError = null;
      _recording = true;
      _recordSecondsLeft = _recordSecondsTarget;
    });
    try {
      final audio = ref.read(audioServiceProvider);
      final settings = ref.read(settingsServiceProvider);
      final path = await audio.startRecording(settingsService: settings);
      if (path == null) {
        setState(() {
          _recording = false;
          _captureError = AppLocalizations.of(context)
              .voiceCloneCaptureNoPermission;
        });
        return;
      }
      _recordedPath = path;
      _recordCountdownTimer =
          Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_recordSecondsLeft <= 1) {
          t.cancel();
          await _stopRecording();
        } else {
          setState(() => _recordSecondsLeft -= 1);
        }
      });
    } catch (e, st) {
      Log.instance.e('voice-clone', 'start recording failed',
          error: e, stack: st);
      if (mounted) {
        setState(() {
          _recording = false;
          _captureError = e.toString();
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordCountdownTimer?.cancel();
    final audio = ref.read(audioServiceProvider);
    try {
      // audio.stopRecording returns the file path; AudioService
      // tracks it but we keep the one from startRecording too
      // in case the stop call returns null on platform quirks.
      final ret = await audio.stopRecording();
      if (ret != null) _recordedPath = ret;
    } catch (e, st) {
      Log.instance.w('voice-clone', 'stop recording failed',
          error: e, stack: st);
    }
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _pickFile() async {
    setState(() => _captureError = null);
    try {
      final pick = await pickFilesRobust(
        type: FileType.audio,
        allowedExtensions: const ['wav', 'flac', 'mp3', 'ogg', 'opus', 'm4a'],
      );
      if (pick.isEmpty) return;
      setState(() => _recordedPath = pick.localPaths.first);
    } on FilePickerCloudUriUnsupported catch (e, st) {
      Log.instance.w('voice-clone',
          'cloud-URI pick failed even with fallback',
          error: e, stack: st);
      if (mounted) {
        setState(() => _captureError =
            AppLocalizations.of(context).filePickerCloudFileUnsupported);
      }
    } catch (e, st) {
      Log.instance.w('voice-clone', 'file pick failed',
          error: e, stack: st);
      if (mounted) setState(() => _captureError = e.toString());
    }
  }

  Future<void> _togglePreview() async {
    final path = _recordedPath;
    if (path == null) return;
    _previewPlayer ??= AudioPlayer();
    _previewPlayer!.playingStream.listen((p) {
      if (mounted) setState(() => _previewPlaying = p);
    });
    if (_previewPlaying) {
      await _previewPlayer!.pause();
      return;
    }
    try {
      if (_previewPlayer!.audioSource == null) {
        await _previewPlayer!.setFilePath(path);
      }
      await _previewPlayer!.seek(Duration.zero);
      await _previewPlayer!.play();
    } catch (e, st) {
      Log.instance.w('voice-clone', 'preview play failed',
          error: e, stack: st);
    }
  }

  void _clearCapture() {
    setState(() {
      _recordedPath = null;
      _captureError = null;
      _previewPlayer?.stop();
    });
  }

  // ----- Navigation -----

  bool get _canAdvance {
    switch (_step) {
      case _Step.capture:
        return _recordedPath != null;
      case _Step.refText:
        // Empty allowed — some backends (chatterbox without a
        // baked GGUF) clone from audio alone. We still surface
        // a helper telling the user "leave empty for backends
        // that don't need it" but don't block forward motion.
        return true;
      case _Step.handoff:
        return false; // terminal; "Done" finishes
    }
  }

  void _next() {
    switch (_step) {
      case _Step.capture:
        setState(() => _step = _Step.refText);
        break;
      case _Step.refText:
        setState(() => _step = _Step.handoff);
        break;
      case _Step.handoff:
        _finishToSynthesize();
        break;
    }
  }

  void _back() {
    switch (_step) {
      case _Step.capture:
        Navigator.of(context).maybePop();
        break;
      case _Step.refText:
        setState(() => _step = _Step.capture);
        break;
      case _Step.handoff:
        setState(() => _step = _Step.refText);
        break;
    }
  }

  /// Hand the user off to /synthesize with the captured WAV +
  /// reference transcript pre-populated. Uses GoRouter's
  /// `extra` (in-memory) for the WAV path so we don't have to
  /// URL-encode an arbitrarily-long filesystem path through
  /// query parameters.
  void _finishToSynthesize() {
    final path = _recordedPath;
    if (path == null) return;
    context.go('/synthesize', extra: <String, String>{
      'voiceWavPath': path,
      'refText': _refTextController.text.trim(),
    });
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.voiceCloneTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepper(l),
            const SizedBox(height: 16),
            Expanded(child: _buildStepBody(l)),
            const SizedBox(height: 8),
            _buildFooter(l),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper(AppLocalizations l) {
    final index = _Step.values.indexOf(_step);
    return Row(
      children: List.generate(_Step.values.length, (i) {
        final active = i == index;
        final done = i < index;
        final label = switch (_Step.values[i]) {
          _Step.capture => l.voiceCloneStepCapture,
          _Step.refText => l.voiceCloneStepRefText,
          _Step.handoff => l.voiceCloneStepHandoff,
        };
        return Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: done
                    ? Colors.green.shade400
                    : active
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade400,
                child: Text('${i + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade700,
                      fontWeight: active
                          ? FontWeight.w600
                          : FontWeight.w400)),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepBody(AppLocalizations l) {
    switch (_step) {
      case _Step.capture:
        return _buildCaptureBody(l);
      case _Step.refText:
        return _buildRefTextBody(l);
      case _Step.handoff:
        return _buildHandoffBody(l);
    }
  }

  Widget _buildCaptureBody(AppLocalizations l) {
    final hasPath = _recordedPath != null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.voiceCloneCaptureHeading,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l.voiceCloneCaptureHelp(_recordSecondsTarget),
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                if (_recording)
                  Column(
                    children: [
                      const Icon(Icons.mic,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        l.voiceCloneRecordingCountdown(
                            _recordSecondsLeft),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.stop, size: 18),
                        label: Text(l.voiceCloneRecordingStop),
                        onPressed: _stopRecording,
                      ),
                    ],
                  )
                else if (hasPath)
                  Column(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 48),
                      const SizedBox(height: 8),
                      Text(_recordedPath!.split(p.separator).last,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: Icon(_previewPlaying
                                ? Icons.pause
                                : Icons.play_arrow),
                            label: Text(_previewPlaying
                                ? l.voiceClonePreviewPause
                                : l.voiceClonePreviewPlay),
                            onPressed: _togglePreview,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.clear),
                            label: Text(l.voiceCloneCaptureClear),
                            onPressed: _clearCapture,
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.mic, size: 18),
                        label: Text(l.voiceCloneRecord(
                            _recordSecondsTarget)),
                        onPressed: _startRecording,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.file_open, size: 18),
                        label: Text(l.voiceClonePickFile),
                        onPressed: _pickFile,
                      ),
                    ],
                  ),
                if (_captureError != null) ...[
                  const SizedBox(height: 12),
                  Text(_captureError!,
                      style: TextStyle(
                          color: Colors.red.shade700, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefTextBody(AppLocalizations l) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.voiceCloneRefTextHeading,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l.voiceCloneRefTextHelp,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          TextField(
            controller: _refTextController,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: l.voiceCloneRefTextLabel,
              hintText: l.voiceCloneRefTextHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandoffBody(AppLocalizations l) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.voiceCloneHandoffHeading,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l.voiceCloneHandoffHelp,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          _summaryRow(l.voiceCloneSummaryReference,
              _recordedPath?.split(p.separator).last ?? '—'),
          _summaryRow(
            l.voiceCloneSummaryRefText,
            _refTextController.text.trim().isEmpty
                ? l.voiceCloneSummaryRefTextEmpty
                : _refTextController.text.trim(),
          ),
          const SizedBox(height: 16),
          Text(l.voiceCloneHandoffModelHint,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 13),
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l) {
    final isLast = _step == _Step.handoff;
    return Row(
      children: [
        TextButton(
          onPressed: _back,
          child: Text(_step == _Step.capture
              ? l.cancel
              : l.voiceCloneBack),
        ),
        const Spacer(),
        FilledButton.icon(
          icon: Icon(isLast ? Icons.check : Icons.arrow_forward,
              size: 18),
          label: Text(
              isLast ? l.voiceCloneFinish : l.voiceCloneNext),
          onPressed:
              (_canAdvance || isLast) ? _next : null,
        ),
      ],
    );
  }
}
