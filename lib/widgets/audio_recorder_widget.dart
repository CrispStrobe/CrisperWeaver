import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engines/transcription_engine.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart';
import '../providers/audio_recorder_provider.dart';
import '../services/audio_service.dart';
import '../services/hotkey_service.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../services/system_audio_capture_service.dart';

class AudioRecorderWidget extends ConsumerStatefulWidget {
  const AudioRecorderWidget({super.key});

  @override
  ConsumerState<AudioRecorderWidget> createState() =>
      _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends ConsumerState<AudioRecorderWidget>
    with TickerProviderStateMixin {
  Timer? _timer;
  StreamController<Float32List>? _micController;
  StreamSubscription<TranscriptionSegment>? _streamSub;
  StreamSubscription<Float32List>? _sysAudioFramesSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  /// §5.1.11 — subscription to the global hotkey stream. Lives
  /// for the lifetime of this widget so subsequent presses are
  /// honoured; cancelled in dispose.
  StreamSubscription<HotkeyEvent>? _hotkeySub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    // Async probe for system-audio capture support so the UI button
    // can grey out on macOS 11/12 / Linux / Windows / Android / iOS
    // (every platform without §5.1.1 wiring yet).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = ref.read(systemAudioCaptureServiceProvider);
      svc.isSupported().then((ok) {
        if (mounted) ref.read(audioRecorderProvider.notifier).setSystemAudioSupported(ok);
      });
      // §5.1.11 — start listening for global-hotkey events.
      // Mode (push-to-talk vs toggle) is read fresh on each
      // event from settings so a settings change mid-session
      // takes effect immediately.
      final hk = ref.read(hotkeyServiceProvider);
      _hotkeySub = hk.events.listen(_onHotkeyEvent);
    });
  }

  void _onHotkeyEvent(HotkeyEvent event) {
    if (!mounted) return;
    final action = ref.read(hotkeyServiceProvider).action;
    final isRecording = ref.read(audioRecorderProvider).isRecording;
    switch (action) {
      case HotkeyAction.pushToTalk:
        if (event == HotkeyEvent.keyDown && !isRecording) {
          _startRecording();
        } else if (event == HotkeyEvent.keyUp && isRecording) {
          _stopRecording();
        }
        break;
      case HotkeyAction.toggle:
        if (event != HotkeyEvent.keyDown) return;
        if (isRecording) {
          _stopRecording();
        } else {
          _startRecording();
        }
        break;
    }
  }

  @override
  void dispose() {
    _hotkeySub?.cancel();
    _timer?.cancel();
    _streamSub?.cancel();
    _micController?.close();
    _sysAudioFramesSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rState = ref.watch(audioRecorderProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Audio Recorder',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                // Stream-mode toggle. When ON, hitting Record opens a
                // live PCM stream into the engine's transcribeStream
                // (Whisper-only sliding window) instead of writing a
                // WAV. Disabled mid-recording so we don't tear down
                // the active session.
                Tooltip(
                  message:
                      AppLocalizations.of(context).recorderStreamTooltip,
                  child: Row(
                    children: [
                      Text(
                        AppLocalizations.of(context).recorderStream,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      Switch(
                        value: rState.streamMode,
                        onChanged: rState.isRecording
                            ? null
                            : (v) => ref.read(audioRecorderProvider.notifier).setStreamMode(v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Recording controls
            Row(
              children: [
                // Record/Stop button
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: rState.isRecording ? _pulseAnimation.value : 1.0,
                      child: FloatingActionButton(
                        heroTag: "record_button",
                        onPressed:
                            rState.isRecording ? _stopRecording : _startRecording,
                        backgroundColor:
                            rState.isRecording ? Colors.red : Colors.blue,
                        child: Icon(
                          rState.isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(width: 16),

                // §5.1.1 — System audio capture button. Greyed out
                // when the platform doesn't support it (everything
                // except macOS 13+ in v1). Mutually exclusive with
                // mic recording — toggling either off cancels both.
                if (rState.systemAudioSupported || rState.isCapturingSystemAudio)
                  Tooltip(
                    message: AppLocalizations.of(context)
                        .recorderSystemAudioTooltip,
                    child: IconButton(
                      iconSize: 28,
                      onPressed: rState.isRecording
                          ? null
                          : (rState.isCapturingSystemAudio
                              ? _stopSystemAudioCapture
                              : _startSystemAudioCapture),
                      icon: Icon(
                        rState.isCapturingSystemAudio
                            ? Icons.stop_screen_share
                            : Icons.screen_share,
                        color: rState.isCapturingSystemAudio
                            ? Colors.red
                            : null,
                      ),
                    ),
                  ),

                // Pause/Resume button (only show when recording)
                if (rState.isRecording) ...[
                  IconButton(
                    onPressed: rState.isPaused ? _resumeRecording : _pauseRecording,
                    icon: Icon(rState.isPaused ? Icons.play_arrow : Icons.pause),
                    iconSize: 32,
                  ),
                  const SizedBox(width: 16),
                ],

                // Duration display
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDuration(rState.recordingDuration),
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: rState.isRecording ? Colors.red : null,
                                ),
                      ),
                      if (rState.isRecording)
                        Text(
                          rState.isPaused ? 'Paused' : 'Recording...',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: rState.isPaused ? Colors.orange : Colors.red,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Recording visualizer
            if (rState.isRecording) ...[
              const SizedBox(height: 16),
              _buildAudioVisualizer(),
            ],

            // Recorded file info
            if (rState.recordingPath != null && !rState.isRecording) ...[
              const SizedBox(height: 16),
              _buildRecordedFileInfo(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioVisualizer() {
    final rState = ref.watch(audioRecorderProvider);
    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: CustomPaint(
        painter: AudioVisualizerPainter(
          isRecording: rState.isRecording && !rState.isPaused,
          animationValue: _pulseController.value,
          amplitudes: rState.amplitudes,
        ),
      ),
    );
  }

  Widget _buildRecordedFileInfo() {
    final rState = ref.watch(audioRecorderProvider);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recording completed',
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Duration: ${_formatDuration(rState.recordingDuration)}',
                  style: TextStyle(color: Colors.green.shade600),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(rState.isPlaying ? Icons.stop : Icons.play_arrow),
                onPressed: rState.isPlaying ? _stopPlayback : _playRecording,
                tooltip: rState.isPlaying ? 'Stop playback' : 'Play recording',
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _deleteRecording,
                tooltip: AppLocalizations.of(context).tooltipDeleteRecording,
              ),
              IconButton(
                icon: const Icon(Icons.upload),
                onPressed: _useRecording,
                tooltip:
                    AppLocalizations.of(context).tooltipUseForTranscription,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _startRecording() async {
    if (ref.read(audioRecorderProvider).streamMode) {
      await _startStreamRecording();
      return;
    }
    final audioService = ref.read(audioServiceProvider);
    final settingsService = ref.read(settingsServiceProvider);
    final n = ref.read(audioRecorderProvider.notifier);

    try {
      final path =
          await audioService.startRecording(settingsService: settingsService);
      if (path != null) {
        n.startRecording(path: path);

        // Start animation
        _pulseController.repeat(reverse: true);

        // Start timer
        _timer =
            Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          final s = ref.read(audioRecorderProvider);
          if (s.isRecording && !s.isPaused) {
            final amp = await audioService.getAmplitude();
            if (mounted) {
              final rn = ref.read(audioRecorderProvider.notifier);
              rn.incrementDuration(const Duration(milliseconds: 100));
              rn.addAmplitude(amp);
            }
          }
        });
      }
    } catch (e) {
      _showErrorDialog('Failed to start recording: $e');
    }
  }

  /// Stream-mode entry point. Opens a live PCM stream and feeds it
  /// into the engine's `transcribeStream`. Each commit replaces the
  /// running transcription text in app state, so the UI shows the
  /// rolling 10 s window's text live. Eligible backends are whisper,
  /// kyutai-stt, moonshine-streaming, voxtral4b — anything else
  /// surfaces the streamingNotAvailableForBackend error.
  Future<void> _startStreamRecording() async {
    final audioService = ref.read(audioServiceProvider);
    final transcriptionService = ref.read(transcriptionServiceProvider);
    final engine = transcriptionService.currentEngine;
    final status = transcriptionService.getEngineStatus();
    final l = AppLocalizations.of(context);
    if (engine == null) {
      _showErrorDialog(l.streamingNoModelLoaded);
      return;
    }
    if (status.currentModelId == null) {
      _showErrorDialog(l.streamingNoModelLoaded);
      return;
    }
    if (!engine.supportsStreaming) {
      _showErrorDialog(
          l.streamingNotAvailableForBackend(status.currentModelId ?? 'unknown'));
      return;
    }

    final pcmStream = await audioService.startStreamingRecording();
    if (pcmStream == null) {
      if (mounted) {
        _showErrorDialog(
            AppLocalizations.of(context).streamingMicUnavailable);
      }
      return;
    }

    ref.read(audioRecorderProvider.notifier).startRecording(path: null);
    _pulseController.repeat(reverse: true);

    // Funnel mic frames through a controller so the engine stream can
    // be cancelled cleanly on stop without tearing down the recorder.
    _micController = StreamController<Float32List>(sync: true);
    pcmStream.listen(_micController!.add,
        onError: _micController!.addError, onDone: _micController!.close);

    final segStream = engine.transcribeStream(_micController!.stream);
    if (segStream == null) {
      await _stopStreamRecording();
      if (mounted) {
        // CrispASR 0.6 added the unified session-stream path, so this
        // error now means "the active backend has no streaming arm" —
        // not "you need Whisper". Surface the backend id so the user
        // knows what to swap to (whisper / kyutai-stt /
        // moonshine-streaming / voxtral4b).
        final backend =
            transcriptionService.getEngineStatus().currentModelId ?? 'unknown';
        _showErrorDialog(AppLocalizations.of(context)
            .streamingNotAvailableForBackend(backend));
      }
      return;
    }

    final appNotifier = ref.read(appStateProvider.notifier);
    appNotifier.startTranscription();
    _streamSub = segStream.listen((seg) {
      // The engine's streaming contract overwrites the rolling text on
      // every commit — replace the current "transcription" rather than
      // append, so the user sees the latest decoder pass instead of a
      // duplicated growing string.
      appNotifier.replaceLiveStreamingText(seg.text);
    }, onError: (Object e, StackTrace st) {
      Log.instance.w('mic-stream', 'transcribeStream failed', error: e, stack: st);
    });

    // Heartbeat for the duration display (no amplitude — record
    // doesn't expose it during stream mode on every platform).
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final s = ref.read(audioRecorderProvider);
      if (s.isRecording && !s.isPaused && mounted) {
        ref.read(audioRecorderProvider.notifier)
            .incrementDuration(const Duration(milliseconds: 100));
      }
    });
  }

  Future<void> _stopStreamRecording() async {
    final audioService = ref.read(audioServiceProvider);
    await audioService.stopStreaming();
    await _streamSub?.cancel();
    _streamSub = null;
    await _micController?.close();
    _micController = null;
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    if (mounted) {
      ref.read(audioRecorderProvider.notifier).stopRecording();
    }
  }

  /// §5.1.1 — start a system-audio capture stream and pipe its
  /// PCM frames into the engine's `transcribeStream`. Same UX
  /// shape as mic stream-mode: rolling text into the output card.
  /// Whisper-only today; non-streaming-capable backends surface
  /// the same "backend doesn't support streaming" error as the
  /// mic stream path.
  Future<void> _startSystemAudioCapture() async {
    // Snapshot localised strings BEFORE the first `await` so the
    // linter doesn't complain about reading BuildContext across
    // async gaps. The screen lives as long as the recorder widget,
    // so saving a stale string is fine on cancellation.
    final l = AppLocalizations.of(context);
    final transcriptionService = ref.read(transcriptionServiceProvider);
    final engine = transcriptionService.currentEngine;
    final status = transcriptionService.getEngineStatus();
    if (engine == null || status.currentModelId == null) {
      _showErrorDialog(l.streamingNoModelLoaded);
      return;
    }
    if (!engine.supportsStreaming) {
      _showErrorDialog(
          l.streamingNotAvailableForBackend(status.currentModelId ?? 'unknown'));
      return;
    }
    final svc = ref.read(systemAudioCaptureServiceProvider);
    Stream<Float32List> frames;
    try {
      frames = await svc.start();
    } on SystemAudioPermissionException catch (e) {
      Log.instance.w('sysaudio', 'permission denied: ${e.message}');
      _showErrorDialog(l.recorderSystemAudioPermission);
      return;
    } on SystemAudioUnsupportedException catch (e) {
      Log.instance.w('sysaudio', 'unsupported: ${e.message}');
      _showErrorDialog(l.recorderSystemAudioUnsupported);
      return;
    } catch (e, st) {
      Log.instance
          .e('sysaudio', 'start failed', error: e, stack: st);
      _showErrorDialog(e.toString());
      return;
    }

    ref.read(audioRecorderProvider.notifier).startSystemCapture();

    _micController = StreamController<Float32List>(sync: true);
    _sysAudioFramesSub = frames.listen(
      _micController!.add,
      onError: _micController!.addError,
      onDone: _micController!.close,
    );

    final segStream = engine.transcribeStream(_micController!.stream);
    if (segStream == null) {
      await _stopSystemAudioCapture();
      final backend =
          transcriptionService.getEngineStatus().currentModelId ?? 'unknown';
      _showErrorDialog(l.streamingNotAvailableForBackend(backend));
      return;
    }

    final appNotifier = ref.read(appStateProvider.notifier);
    appNotifier.startTranscription();
    _streamSub = segStream.listen(
      (seg) => appNotifier.replaceLiveStreamingText(seg.text),
      onError: (Object e, StackTrace st) {
        Log.instance.w('sysaudio',
            'transcribeStream failed', error: e, stack: st);
      },
    );

    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (ref.read(audioRecorderProvider).isCapturingSystemAudio && mounted) {
        ref.read(audioRecorderProvider.notifier)
            .incrementDuration(const Duration(milliseconds: 100));
      }
    });
  }

  Future<void> _stopSystemAudioCapture() async {
    final svc = ref.read(systemAudioCaptureServiceProvider);
    await svc.stop();
    await _sysAudioFramesSub?.cancel();
    _sysAudioFramesSub = null;
    await _streamSub?.cancel();
    _streamSub = null;
    await _micController?.close();
    _micController = null;
    _timer?.cancel();
    if (mounted) {
      ref.read(audioRecorderProvider.notifier).stopSystemCapture();
    }
  }

  Future<void> _stopRecording() async {
    if (ref.read(audioRecorderProvider).streamMode) {
      await _stopStreamRecording();
      return;
    }
    final audioService = ref.read(audioServiceProvider);

    try {
      final path = await audioService.stopRecording();
      ref.read(audioRecorderProvider.notifier).stopRecording(path: path);

      // Auto-select the recording so the user can hit Transcribe
      // immediately. Tapping "Use Recording" still works (it shows
      // the confirmation snackbar + stops any active playback) but
      // shouldn't be required — the universal expectation is
      // "I recorded → that's what I want to transcribe".
      if (path != null) {
        ref.read(selectedAudioPathProvider.notifier).state = path;
      }

      _timer?.cancel();
      _pulseController.stop();
      _pulseController.reset();
    } catch (e) {
      _showErrorDialog('Failed to stop recording: $e');
    }
  }

  void _pauseRecording() {
    ref.read(audioRecorderProvider.notifier).setIsPaused(true);
    _pulseController.stop();
  }

  void _resumeRecording() {
    ref.read(audioRecorderProvider.notifier).setIsPaused(false);
    _pulseController.repeat(reverse: true);
  }

  Future<void> _playRecording() async {
    final recordingPath = ref.read(audioRecorderProvider).recordingPath;
    if (recordingPath == null) return;

    final audioService = ref.read(audioServiceProvider);
    final n = ref.read(audioRecorderProvider.notifier);
    try {
      n.setIsPlaying(true);
      await audioService.playAudio(File(recordingPath));
      if (mounted) n.setIsPlaying(false);
    } catch (e) {
      if (mounted) n.setIsPlaying(false);
      _showErrorDialog('Failed to play recording: $e');
    }
  }

  Future<void> _stopPlayback() async {
    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.stopPlayback();
      if (mounted) ref.read(audioRecorderProvider.notifier).setIsPlaying(false);
    } catch (_) {}
  }

  void _deleteRecording() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).recorderDeleteTitle),
        content: Text(AppLocalizations.of(context).recorderDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performDeleteRecording();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );
  }

  void _performDeleteRecording() {
    final recordingPath = ref.read(audioRecorderProvider).recordingPath;
    if (recordingPath != null) {
      try {
        File(recordingPath).deleteSync();
        ref.read(audioRecorderProvider.notifier).deleteRecording();
      } catch (e) {
        _showErrorDialog('Failed to delete recording: $e');
      }
    }
  }

  void _useRecording() {
    final recordingPath = ref.read(audioRecorderProvider).recordingPath;
    if (recordingPath == null) return;
    _stopPlayback();
    ref.read(selectedAudioPathProvider.notifier).state = recordingPath;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              AppLocalizations.of(context).recorderQueuedForTranscription)),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    final milliseconds = (duration.inMilliseconds % 1000) ~/ 10;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}.'
          '${milliseconds.toString().padLeft(2, '0')}';
    }
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).error),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).ok),
          ),
        ],
      ),
    );
  }
}

class AudioVisualizerPainter extends CustomPainter {
  final bool isRecording;
  final double animationValue;
  final List<double> amplitudes;

  AudioVisualizerPainter({
    required this.isRecording,
    required this.animationValue,
    required this.amplitudes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final paint = Paint()
      ..color = isRecording
          ? Colors.red.withValues(alpha: 0.6)
          : Colors.grey.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final spacing = size.width / amplitudes.length;
    final centerY = size.height / 2;

    for (int i = 0; i < amplitudes.length; i++) {
      final x = i * spacing;
      final amplitude = amplitudes[i];
      final height = (amplitude * size.height).clamp(4.0, size.height - 4);

      final rect = Rect.fromCenter(
        center: Offset(x, centerY),
        width: spacing * 0.8,
        height: height,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AudioVisualizerPainter oldDelegate) {
    return oldDelegate.isRecording != isRecording ||
        oldDelegate.amplitudes.length != amplitudes.length ||
        isRecording;
  }
}
