// EditAudioScreen — PLAN §5.1.5 Phase B.
//
// Dedicated audio editor with a waveform painter, transport
// controls, and three operations: trim, cut middle, split into
// chapters. Output is 16 kHz mono PCM WAV — same format the
// transcription pipeline expects, so a "Crop and transcribe"
// hand-off needs no re-decode.
//
// The collapsible transcript pane (bidirectional sync with the
// transcript editor) lands in Phase C. This commit ships the
// standalone editor — reach it from the transcription screen's
// "more actions" menu with the active audio file path.
//
// Cross-platform: pure Flutter + dart:io + the existing
// crispasr.decodeAudioFile FFI helper. No FFmpeg, no platform
// channels. Works identically on every platform CrisperWeaver
// ships on.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../engines/transcription_engine.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show appStateProvider;
import '../providers/edit_audio_provider.dart';
import '../services/audio_edit_service.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../widgets/root_aware_back_leading.dart';
import '../widgets/waveform_painter.dart';

class EditAudioScreen extends ConsumerStatefulWidget {
  const EditAudioScreen({
    super.key,
    required this.sourcePath,
    this.initialSelectionStartSec,
    this.initialSelectionEndSec,
    this.initialCutMarkSec,
  });

  /// Absolute path to the audio file being edited. Required —
  /// the editor has no "open file" picker of its own; the user
  /// reaches this screen from the transcription screen's "more
  /// actions" menu with an audio already loaded.
  final String sourcePath;

  /// §5.1.5 Phase D — pre-populate the waveform selection on
  /// open. Used by the transcript long-press flow ("Edit this
  /// segment in audio editor") to land in the editor with the
  /// segment's [start, end] already selected and the transcript
  /// pane visible. Either both must be set or both null.
  final double? initialSelectionStartSec;
  final double? initialSelectionEndSec;

  /// §5.1.5 Phase D — pre-drop a single cut marker on open.
  /// Used by the "Mark for split in audio editor" transcript
  /// long-press action.
  final double? initialCutMarkSec;

  @override
  ConsumerState<EditAudioScreen> createState() => _EditAudioScreenState();
}

class _EditAudioScreenState extends ConsumerState<EditAudioScreen> {
  final _player = AudioPlayer();
  Duration _playerPosition = Duration.zero;

  final ScrollController _transcriptScrollController = ScrollController();
  // Per-segment key so we can scroll-to + animate-highlight the
  // currently-playing one when the playhead moves.
  final Map<int, GlobalKey> _segmentKeys = {};

  @override
  void initState() {
    super.initState();
    // §5.1.5 Phase D — seed selection / cut markers from
    // constructor args. These come from the transcript-screen
    // long-press deep-links. Force the transcript pane open
    // when arriving from that flow so the user immediately
    // sees the segment they came in from.
    final n = ref.read(editAudioProvider.notifier);
    if (widget.initialSelectionStartSec != null &&
        widget.initialSelectionEndSec != null &&
        widget.initialSelectionEndSec! > widget.initialSelectionStartSec!) {
      n.setSelection(WaveformSelection(
        startSec: widget.initialSelectionStartSec!,
        endSec: widget.initialSelectionEndSec!,
      ));
    }
    if (widget.initialCutMarkSec != null) {
      n.addCutMarker(WaveformCutMarker(
        startSec: widget.initialCutMarkSec!,
        endSec: widget.initialCutMarkSec!,
      ));
    }
    final cameFromTranscript = widget.initialSelectionStartSec != null ||
        widget.initialCutMarkSec != null;

    // Restore the persisted pane-visibility preference. Read in a
    // post-frame callback so we have a fully-built ref tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(settingsServiceProvider);
      ref.read(editAudioProvider.notifier).setShowTranscript(
          cameFromTranscript || s.editAudioShowTranscript);
    });
    _player.positionStream.listen((p) {
      if (!mounted) return;
      _playerPosition = p;
      _autoHighlightCurrentSegment();
    });
    _player.playingStream.listen((playing) {
      if (mounted) ref.read(editAudioProvider.notifier).setIsPlaying(playing);
    });
    _loadAudio();
  }

  @override
  void dispose() {
    _transcriptScrollController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadAudio() async {
    final svc = ref.read(audioEditServiceProvider);
    try {
      // Kick off the player + decode in parallel — decoding the
      // raw PCM for the waveform is the slow step; player setup
      // is just header-reading.
      final decodeFuture = svc.decode(widget.sourcePath);
      await _player.setFilePath(widget.sourcePath);
      final decoded = await decodeFuture;
      if (!mounted) return;
      ref.read(editAudioProvider.notifier).setDecoded(decoded);
      // §5.1.5 Phase D — if we arrived with an initial selection
      // or cut mark, park the playhead at its start so the user
      // can play-preview immediately without scrubbing.
      final seedSec = widget.initialSelectionStartSec ??
          widget.initialCutMarkSec;
      if (seedSec != null) _seekTo(seedSec);
    } catch (e, st) {
      Log.instance.e('audio-edit', 'decode failed',
          fields: {'path': widget.sourcePath}, error: e, stack: st);
      if (mounted) ref.read(editAudioProvider.notifier).setDecodeError(e.toString());
    }
  }

  /// Lazily downsample the source to `width` columns whenever
  /// the widget gets a new layout size. Cached so a window
  /// resize doesn't re-traverse all samples on every frame.
  void _ensureBars(double width) {
    final w = width.floor();
    final eState = ref.read(editAudioProvider);
    if (w <= 0 || eState.decoded == null) return;
    if (eState.bars != null && eState.waveformWidth == w.toDouble()) return;
    ref.read(editAudioProvider.notifier).setBarsAndWidth(
      bars: WaveformBars.fromSamples(
        samples: eState.decoded!.samples,
        targetWidth: w,
      ),
      width: w.toDouble(),
    );
  }

  double _xToSec(double x, double w) {
    final decoded = ref.read(editAudioProvider).decoded;
    if (decoded == null || decoded.durationSec <= 0 || w <= 0) return 0;
    return (x / w).clamp(0.0, 1.0) * decoded.durationSec;
  }

  void _seekTo(double sec) {
    _player.seek(Duration(milliseconds: (sec * 1000).round()));
  }

  // ----- Pointer interaction -----

  // Drag state — we treat the gesture's onPanStart as the
  // selection's left edge, onPanUpdate as the right edge. A
  // pure-tap (no drag) sets the playhead via _seekTo.
  Offset? _dragStart;

  void _onPanStart(DragStartDetails d, double width) {
    _dragStart = d.localPosition;
    final sec = _xToSec(d.localPosition.dx, width);
    ref.read(editAudioProvider.notifier).setSelection(
        WaveformSelection(startSec: sec, endSec: sec));
  }

  void _onPanUpdate(DragUpdateDetails d, double width) {
    final start = _dragStart;
    if (start == null) return;
    final secStart = _xToSec(start.dx, width);
    final secEnd = _xToSec(d.localPosition.dx, width);
    final lo = secStart < secEnd ? secStart : secEnd;
    final hi = secEnd > secStart ? secEnd : secStart;
    ref.read(editAudioProvider.notifier).setSelection(
        WaveformSelection(startSec: lo, endSec: hi));
  }

  void _onTap(TapUpDetails d, double width) {
    final sec = _xToSec(d.localPosition.dx, width);
    _seekTo(sec);
  }

  // ----- Operations -----

  Future<void> _trim() async {
    final sel = ref.read(editAudioProvider).selection;
    if (sel == null || sel.endSec <= sel.startSec) {
      _toast(AppLocalizations.of(context).editAudioNeedSelection);
      return;
    }
    await _runOp(
      label: 'trim',
      op: (svc, dest) => svc.trim(
        sourcePath: widget.sourcePath,
        startSec: sel.startSec,
        endSec: sel.endSec,
        destinationPath: dest,
      ),
      defaultSuffix: 'trimmed',
    );
  }

  Future<void> _cut() async {
    final sel = ref.read(editAudioProvider).selection;
    if (sel == null || sel.endSec <= sel.startSec) {
      _toast(AppLocalizations.of(context).editAudioNeedSelection);
      return;
    }
    await _runOp(
      label: 'cut',
      op: (svc, dest) => svc.cut(
        sourcePath: widget.sourcePath,
        regions: [AudioCutRegion(sel.startSec, sel.endSec)],
        destinationPath: dest,
      ),
      defaultSuffix: 'cut',
    );
  }

  Future<void> _addSplit() async {
    if (ref.read(editAudioProvider).decoded == null) return;
    ref.read(editAudioProvider.notifier).addCutMarker(WaveformCutMarker(
          startSec: _playerPosition.inMilliseconds / 1000.0,
          endSec: _playerPosition.inMilliseconds / 1000.0,
        ));
  }

  Future<void> _runSplit() async {
    final cutMarkers = ref.read(editAudioProvider).cutMarkers;
    if (cutMarkers.isEmpty) {
      _toast(AppLocalizations.of(context).editAudioNeedSplitMarks);
      return;
    }
    final svc = ref.read(audioEditServiceProvider);
    final base = await _chooseSaveLocation('split');
    if (base == null) return;
    try {
      final files = await svc.split(
        sourcePath: widget.sourcePath,
        splitPoints: cutMarkers.map((c) => c.startSec).toList(),
        destinationBuilder: (i) {
          final dir = p.dirname(base);
          final stem = p.basenameWithoutExtension(base);
          return p.join(dir, '$stem-part-${(i + 1).toString().padLeft(3, "0")}.wav');
        },
      );
      if (!mounted) return;
      _toast(AppLocalizations.of(context).editAudioSplitSaved(files.length));
    } catch (e, st) {
      Log.instance.e('audio-edit', 'split failed', error: e, stack: st);
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _runOp({
    required String label,
    required Future<File> Function(AudioEditService svc, String dest) op,
    required String defaultSuffix,
  }) async {
    final l = AppLocalizations.of(context);
    final svc = ref.read(audioEditServiceProvider);
    final dest = await _chooseSaveLocation(defaultSuffix);
    if (dest == null) return;
    try {
      final out = await op(svc, dest);
      if (!mounted) return;
      _toast(l.editAudioSavedTo(out.path));
    } catch (e, st) {
      Log.instance.e('audio-edit', '$label failed', error: e, stack: st);
      if (mounted) _toast(e.toString());
    }
  }

  Future<String?> _chooseSaveLocation(String suffix) async {
    final dir = p.dirname(widget.sourcePath);
    final stem = p.basenameWithoutExtension(widget.sourcePath);
    final defaultName = '$stem-$suffix.wav';
    // file_picker 12 requires bytes; we pass an empty placeholder since the
    // audio-edit operation overwrites the file immediately after the dialog.
    final path = await FilePicker.saveFile(
      dialogTitle: AppLocalizations.of(context).editAudioSaveAs,
      initialDirectory: dir,
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: const ['wav'],
      bytes: Uint8List(0),
    );
    return path;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // ----- Transcript pane (§5.1.5 Phase C) -----

  /// Read segments from the global transcription state. The
  /// transcript pane only shows content when the user has
  /// already transcribed *this* audio file in the current
  /// session — there's no persistent "audio↔transcript" link in
  /// HistoryService yet (deferred to a future PLAN item), so an
  /// open editor with a freshly-opened file shows the empty
  /// state until the user transcribes from the home screen and
  /// re-enters the editor.
  List<TranscriptionSegment> _readSegments() {
    return ref.read(appStateProvider).segments;
  }

  /// Linear scan to find which segment contains a given second.
  /// Cheap enough for any realistic transcript size (~hundreds
  /// of segments) and avoids the bookkeeping a binary search
  /// would need when segments occasionally overlap.
  int? _segmentIndexAt(double sec, List<TranscriptionSegment> segs) {
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      if (sec >= s.startTime && sec <= s.endTime) return i;
    }
    return null;
  }

  /// Called from the player's positionStream — when the
  /// playhead crosses into a new segment we both highlight that
  /// row and scroll it into view. Throttled implicitly by
  /// positionStream's ~16 Hz update rate.
  void _autoHighlightCurrentSegment() {
    final eState = ref.read(editAudioProvider);
    if (!eState.showTranscript) return;
    final segs = _readSegments();
    if (segs.isEmpty) return;
    final sec = _playerPosition.inMilliseconds / 1000.0;
    final idx = _segmentIndexAt(sec, segs);
    if (idx == eState.highlightedSegmentIndex) return;
    ref.read(editAudioProvider.notifier).setHighlightedSegmentIndex(idx);
    if (idx != null) _scrollSegmentIntoView(idx);
  }

  void _scrollSegmentIntoView(int index) {
    final key = _segmentKeys[index];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: 0.3, // place near the top third for readability
    );
  }

  Future<void> _showSegmentMenu(
      BuildContext sheetCtx, TranscriptionSegment seg) async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: sheetCtx,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.select_all),
                title: Text(l.editAudioSelectSegment),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(editAudioProvider.notifier).setSelection(
                      WaveformSelection(
                        startSec: seg.startTime,
                        endSec: seg.endTime,
                      ));
                  _toast(l.editAudioSegmentSelected(
                    _formatSeconds(seg.startTime),
                    _formatSeconds(seg.endTime),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_cut),
                title: Text(l.editAudioTrimToSegment),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(editAudioProvider.notifier).setSelection(
                      WaveformSelection(
                        startSec: seg.startTime,
                        endSec: seg.endTime,
                      ));
                  _trim();
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_location),
                title: Text(l.editAudioMarkSegmentForCut),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(editAudioProvider.notifier).addCutMarker(
                      WaveformCutMarker(
                        startSec: seg.startTime,
                        endSec: seg.startTime,
                      ));
                  _toast(l.editAudioSegmentMarkedForCut(
                    _formatSeconds(seg.startTime),
                  ));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _togglePane() {
    final settings = ref.read(settingsServiceProvider);
    final next = !ref.read(editAudioProvider).showTranscript;
    ref.read(editAudioProvider.notifier).setShowTranscript(next);
    settings.editAudioShowTranscript = next;
    if (next) _autoHighlightCurrentSegment();
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final eState = ref.watch(editAudioProvider);
    return Scaffold(
      appBar: AppBar(
        // #35 — no back button when this was reached by a stack-replacing
        // `go()`; fall back to a home button.
        leading: rootAwareBackLeading(context),
        title: Text(l.editAudioTitle),
        actions: [
          IconButton(
            tooltip: eState.showTranscript
                ? l.editAudioToggleTranscriptHide
                : l.editAudioToggleTranscriptShow,
            icon: Icon(eState.showTranscript
                ? Icons.subtitles
                : Icons.subtitles_outlined),
            onPressed: _togglePane,
          ),
        ],
      ),
      body: eState.decodeError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.editAudioLoadFailed(eState.decodeError!)),
              ),
            )
          : eState.decoded == null
              ? const Center(child: CircularProgressIndicator())
              : _buildEditor(l),
    );
  }

  Widget _buildEditor(AppLocalizations l) {
    final eState = ref.watch(editAudioProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEditorCore(l),
        if (eState.showTranscript) Expanded(child: _buildTranscriptPane(l)),
      ],
    );
  }

  Widget _buildEditorCore(AppLocalizations l) {
    final eState = ref.watch(editAudioProvider);
    final selection = eState.selection;
    final cutMarkers = eState.cutMarkers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Waveform + interaction layer.
        SizedBox(
          height: 180,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(builder: (context, constraints) {
              _ensureBars(constraints.maxWidth);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _onTap(d, constraints.maxWidth),
                onPanStart: (d) => _onPanStart(d, constraints.maxWidth),
                onPanUpdate: (d) => _onPanUpdate(d, constraints.maxWidth),
                onPanEnd: (_) => _dragStart = null,
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 180),
                  painter: WaveformPainter(
                    bars: eState.bars ?? WaveformBars(peaks: const []),
                    durationSec: eState.decoded!.durationSec,
                    playheadSec:
                        _playerPosition.inMilliseconds / 1000.0,
                    selection: selection,
                    cutMarkers: cutMarkers,
                  ),
                ),
              );
            }),
          ),
        ),

        // Transport row.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                icon: Icon(eState.isPlaying ? Icons.pause : Icons.play_arrow),
                iconSize: 32,
                onPressed: () =>
                    eState.isPlaying ? _player.pause() : _player.play(),
              ),
              IconButton(
                icon: const Icon(Icons.stop),
                iconSize: 32,
                onPressed: () {
                  _player.pause();
                  _player.seek(Duration.zero);
                },
              ),
              const SizedBox(width: 16),
              Text(
                '${_formatDuration(_playerPosition)} / '
                '${_formatDuration(Duration(milliseconds: ((eState.decoded?.durationSec ?? 0) * 1000).round()))}',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 14),
              ),
              const Spacer(),
              if (selection != null) ...[
                Text(
                  l.editAudioSelectionLabel(
                    _formatSeconds(selection.startSec),
                    _formatSeconds(selection.endSec),
                  ),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade700),
                ),
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: l.editAudioClearSelection,
                  onPressed: () =>
                      ref.read(editAudioProvider.notifier).setSelection(null),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 8),
        // Op-button toolbar.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.content_cut, size: 18),
                label: Text(l.editAudioTrim),
                onPressed: selection == null ? null : _trim,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.cut, size: 18),
                label: Text(l.editAudioCut),
                onPressed: selection == null ? null : _cut,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add_location, size: 18),
                label: Text(l.editAudioAddSplitMark),
                onPressed: _addSplit,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.call_split, size: 18),
                label: Text(l.editAudioRunSplit(cutMarkers.length)),
                onPressed:
                    cutMarkers.isEmpty ? null : _runSplit,
              ),
              if (cutMarkers.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: Text(l.editAudioClearMarks),
                  onPressed: () =>
                      ref.read(editAudioProvider.notifier).clearCutMarkers(),
                ),
            ],
          ),
        ),

        const Divider(height: 24),
        // Help text — collapsible "How to use" so the screen
        // self-documents without bloating the toolbar.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l.editAudioHowto,
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  Widget _buildTranscriptPane(AppLocalizations l) {
    // Watch so the pane rebuilds when a transcript is added.
    final segs = ref.watch(appStateProvider).segments;
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.subtitles, size: 18),
                const SizedBox(width: 8),
                Text(
                  l.editAudioTranscriptHeading,
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                if (segs.isNotEmpty)
                  Text(
                    '${segs.length}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          if (segs.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.editAudioTranscriptEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.editAudioTranscriptSegmentTapHint,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: _transcriptScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: segs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 2),
                itemBuilder: (ctx, i) {
                  final seg = segs[i];
                  final key = _segmentKeys.putIfAbsent(i, GlobalKey.new);
                  final isHighlighted = ref.watch(editAudioProvider).highlightedSegmentIndex == i;
                  return Container(
                    key: key,
                    decoration: BoxDecoration(
                      color: isHighlighted
                          ? theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.6)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _seekTo(seg.startTime),
                      onLongPress: () => _showSegmentMenu(ctx, seg),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                _formatSeconds(seg.startTime),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: isHighlighted
                                      ? theme
                                          .colorScheme.onPrimaryContainer
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                seg.text.trim(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isHighlighted
                                      ? theme
                                          .colorScheme.onPrimaryContainer
                                      : null,
                                  fontWeight: isHighlighted
                                      ? FontWeight.w600
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _formatSeconds(double s) {
    final d = Duration(milliseconds: (s * 1000).round());
    return _formatDuration(d);
  }
}
