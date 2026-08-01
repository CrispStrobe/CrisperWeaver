import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, instantiateImageCodec;

import '../native/crispasr_import.dart' as crispasr;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../engines/transcription_engine.dart'; // Use engine TranscriptionSegment
import '../models/segment_tag.dart';
import '../services/aligner_service.dart';
import '../services/log_service.dart';
import '../services/ocr_service.dart';
import '../services/scan_preprocess_service.dart';
import '../services/speaker_id_service.dart';
import '../utils/file_picker_util.dart' show pickFilesRobust;
import '../l10n/generated/app_localizations.dart';
import '../main.dart'
    show
        appStateProvider,
        historyServiceProvider,
        modelServiceProvider,
        selectedAudioPathProvider;
import '../services/cloud_llm_cleanup_service.dart';
import '../services/history_service.dart';
import '../services/local_llm_cleanup_service.dart';
import '../services/settings_service.dart';
import '../services/transcript_cleanup_service.dart';
import '../utils/responsive.dart';
import 'cleanup_dialog.dart';
import 'summarize_dialog.dart';

/// §10 — Human-readable emotion label from SenseVoice tag.
String _emotionLabel(String tag) => switch (tag.toUpperCase()) {
      'HAPPY' => 'happy',
      'SAD' => 'sad',
      'ANGRY' => 'angry',
      'NEUTRAL' => 'neutral',
      'SURPRISED' => 'surprised',
      'FEARFUL' => 'fearful',
      'DISGUSTED' => 'disgusted',
      _ => tag.toLowerCase(),
    };

/// Pre-filled name for the "enroll speaker" dialog: the segment's chip
/// label, unless it's a bare diarisation cluster id (`0`, `Speaker 1`)
/// which isn't a real name — those seed an empty field so the user types
/// the real name. Pure + [visibleForTesting].
@visibleForTesting
String speakerEnrollNameSeed(String? chipLabel) {
  final current = chipLabel?.trim() ?? '';
  if (RegExp(r'^(speaker\s*)?\d+$', caseSensitive: false).hasMatch(current)) {
    return '';
  }
  return current;
}

class TranscriptionOutputWidget extends ConsumerStatefulWidget {
  final List<TranscriptionSegment> segments;
  final String? currentTranscription;

  const TranscriptionOutputWidget({
    super.key,
    required this.segments,
    this.currentTranscription,
  });

  @override
  ConsumerState<TranscriptionOutputWidget> createState() =>
      _TranscriptionOutputWidgetState();

  /// Replaces the first **whole-word** occurrence of [word] in [text]
  /// with [replacement], returning [text] unchanged when [word] doesn't
  /// appear as a standalone token. Used by the alt-token picker so
  /// swapping the alt for "cat" never rewrites inside an earlier
  /// "category" (a plain `replaceFirst` substring match would). A word
  /// is "standalone" when it isn't flanked by ASCII letters/digits, so
  /// leading/trailing punctuation on the token is handled correctly.
  /// [word] is treated literally — regex metacharacters in it are
  /// escaped, never interpreted.
  @visibleForTesting
  static String replaceFirstWholeWord(
      String text, String word, String replacement) {
    if (word.isEmpty) return text;
    final escaped = word.replaceAllMapped(
        RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');
    final re = RegExp('(?<![A-Za-z0-9])$escaped(?![A-Za-z0-9])');
    return text.replaceFirst(re, replacement);
  }
}

class _TranscriptionOutputWidgetState
    extends ConsumerState<TranscriptionOutputWidget>
    with TickerProviderStateMixin {
  bool _showTimestamps = true;
  bool _showSpeakers = true;
  bool _showConfidence = false;
  String _searchQuery = '';

  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // §5.25.12 — keyboard navigation state
  int _focusedSegmentIndex = -1;
  final FocusNode _transcriptFocusNode = FocusNode(
    debugLabel: 'TranscriptKeyboardNav',
  );

  // Karaoke playback state. The player is created lazily on the first
  // _playSegment call so unused transcripts don't allocate one. Active
  // position drives the highlighted-word render via positionStream;
  // _karaokePlaying is true while we're actively syncing UI.
  AudioPlayer? _player;
  StreamSubscription<Duration>? _posSub;
  Duration _karaokePos = Duration.zero;
  bool _karaokePlaying = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _transcriptFocusNode.dispose();
    _posSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls
        _buildControls(),

        // Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSegmentView(),
              _buildFullTextView(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Text-only tabs to keep the output chrome compact — icons + text
          // tabs pushed the header past ~130px and overflowed short windows.
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: l.tabSegments),
              Tab(text: l.tabFullText),
            ],
          ),

          const SizedBox(height: 4),

          // Search and options
          Row(
            children: [
              // Search field
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).searchTranscription,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                ),
              ),

              const SizedBox(width: 8),

              // Options menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: _handleOption,
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: 'timestamps',
                    checked: _showTimestamps,
                    child:
                        Text(AppLocalizations.of(context).outputShowTimestamps),
                  ),
                  CheckedPopupMenuItem(
                    value: 'speakers',
                    checked: _showSpeakers,
                    child:
                        Text(AppLocalizations.of(context).outputShowSpeakers),
                  ),
                  CheckedPopupMenuItem(
                    value: 'confidence',
                    checked: _showConfidence,
                    child:
                        Text(AppLocalizations.of(context).outputShowConfidence),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'copy_all',
                    child: ListTile(
                      leading: const Icon(Icons.copy),
                      title: Text(AppLocalizations.of(context).outputCopyAll),
                      dense: true,
                    ),
                  ),
                  // §5.1.6 — deterministic transcript cleanup.
                  PopupMenuItem(
                    value: 'cleanup',
                    child: ListTile(
                      leading: const Icon(Icons.auto_fix_high),
                      title: Text(AppLocalizations.of(context).outputCleanup),
                      dense: true,
                    ),
                  ),
                  // §5.1.8 — meeting-style summarisation.
                  PopupMenuItem(
                    value: 'summarize',
                    child: ListTile(
                      leading: const Icon(Icons.summarize_outlined),
                      title:
                          Text(AppLocalizations.of(context).outputSummarize),
                      dense: true,
                    ),
                  ),
                  // §12.5 — Re-align word timestamps via standalone CTC
                  // forced alignment (TADA aligner).
                  PopupMenuItem(
                    value: 'realign_timestamps',
                    child: ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(
                          AppLocalizations.of(context).outputRealignTimestamps),
                      dense: true,
                    ),
                  ),
                  // §5.24-F — label the transcript's language via the CLD3
                  // text-LID model, outside the Translate flow.
                  PopupMenuItem(
                    value: 'detect_language',
                    child: ListTile(
                      leading: const Icon(Icons.translate_outlined),
                      title: Text(
                          AppLocalizations.of(context).outputDetectLanguage),
                      dense: true,
                    ),
                  ),
                  // §12.6b — OCR: pick an image and append recognized text.
                  PopupMenuItem(
                    value: 'ocr_image',
                    child: ListTile(
                      leading: const Icon(Icons.document_scanner_outlined),
                      title: Text(
                          AppLocalizations.of(context).outputOcrImage),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentView() {
    if (widget.segments.isEmpty) {
      return _buildEmptyState();
    }

    final filteredSegments = _searchQuery.isEmpty
        ? widget.segments
        : widget.segments
            .where(
                (segment) => segment.text.toLowerCase().contains(_searchQuery))
            .toList();

    if (filteredSegments.isEmpty) {
      return _buildNoSearchResults();
    }

    // §5.25.12 — wrap with keyboard listener for J/K/Space/Enter/Tab nav
    return KeyboardListener(
      focusNode: _transcriptFocusNode,
      onKeyEvent: (event) => _handleTranscriptKeyEvent(event, filteredSegments),
      child: ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: filteredSegments.length,
      itemBuilder: (context, index) {
        final segment = filteredSegments[index];
        return _buildSegmentCard(segment, index);
      },
    ));
  }

  Widget _buildSegmentCard(TranscriptionSegment segment, int index) {
    final hasSearch = _searchQuery.isNotEmpty;
    final isFocused = index == _focusedSegmentIndex;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: isFocused
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                width: 2,
              ),
            )
          : null,
      child: InkWell(
        onTap: () => _playSegment(segment),
        onLongPress: () => _showSegmentOptions(segment),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with timestamp and speaker
              Row(
                children: [
                  if (_showTimestamps) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        segment.formattedTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade800,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  if (_showSpeakers && segment.speaker != null) ...[
                    _buildSpeakerChip(segment.speaker!),
                    const SizedBox(width: 8),
                  ],

                  const Spacer(),

                  // §5.25.5 — Language badge from multilingual tagging.
                  if (segment.metadata['lang'] case final String lang
                      when lang.isNotEmpty && lang != 'unknown') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        lang.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.purple.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],

                  // §10 — SenseVoice emotion badge.
                  if (segment.metadata['emotion'] case final String emo
                      when emo.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _emotionLabel(emo),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],

                  // §10 — SenseVoice audio-event badge.
                  if (segment.metadata['audio_event'] case final String evt
                      when evt.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        evt.toLowerCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.teal.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],

                  // §5.25.10 — tag emoji badges
                  if (segment.tags.isNotEmpty) ...[
                    for (final tagName in segment.tags)
                      if (SegmentTag.fromJson(tagName) case final tag?)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Tooltip(
                            message: tag.label,
                            child: Text(tag.emoji,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                    const SizedBox(width: 4),
                  ],

                  // Tiny pencil icon to flag manually-edited segments.
                  // Set in metadata by AppStateNotifier.editSegment.
                  if (segment.metadata['edited'] == true) ...[
                    Tooltip(
                      message: AppLocalizations.of(context).outputEdited,
                      child: const Icon(Icons.edit, size: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 6),
                  ],

                  if (_showConfidence) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getConfidenceColor(segment.confidence),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${(segment.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],

                  // Options menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, size: 16),
                    onSelected: (action) =>
                        _handleSegmentAction(action, segment),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'play',
                        child: ListTile(
                          leading: const Icon(Icons.play_arrow, size: 16),
                          title: Text(AppLocalizations.of(context).outputPlay),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy',
                        child: ListTile(
                          leading: const Icon(Icons.copy, size: 16),
                          title: Text(AppLocalizations.of(context).outputCopy),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: const Icon(Icons.edit, size: 16),
                          title: Text(AppLocalizations.of(context).outputEdit),
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Transcription text. Render priority:
              //   1. Search highlight (yellow background on matches)
              //   2. Karaoke active-word highlight (during playback)
              //   3. Per-word confidence tint
              //   4. Plain SelectableText
              if (hasSearch)
                _buildHighlightedText(segment.text, _searchQuery)
              else if (_karaokePlaying && _karaokeActiveSegment(segment))
                _buildKaraokeText(segment)
              else if (_showConfidence &&
                  segment.words != null &&
                  segment.words!.isNotEmpty)
                _buildConfidenceTintedText(segment)
              else
                SelectableText(
                  segment.text,
                  style: const TextStyle(fontSize: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return SelectableText(text, style: const TextStyle(fontSize: 16));
    }

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    int start = 0;
    int index = lowerText.indexOf(lowerQuery);

    while (index != -1) {
      // Add text before match
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: const TextStyle(
          backgroundColor: Colors.yellow,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + query.length;
      index = lowerText.indexOf(lowerQuery, start);
    }

    // Add remaining text
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      style: const TextStyle(fontSize: 16),
    );
  }

  /// Render `segment.text` with per-word foreground tint based on each
  /// word's `confidence` score. Whisper emits real per-token
  /// probabilities; session backends currently report `1.0` (uniform
  /// green) until the C-ABI extension lands. The original spacing
  /// between words is preserved verbatim — we walk the segment text
  /// linearly and only colour ranges that match a known word.
  /// True when karaoke playback's current position falls inside this
  /// segment's `[startTime, endTime]` range. Used to render the
  /// active-word highlight only on the currently-playing segment so
  /// scrollback doesn't get noisy.
  bool _karaokeActiveSegment(TranscriptionSegment segment) {
    final t = _karaokePos.inMilliseconds / 1000.0;
    return t >= segment.startTime && t <= segment.endTime + 0.1;
  }

  /// Karaoke render: same per-word span layout as confidence-tint, but
  /// the colour scheme is "currently spoken word = filled badge,
  /// already-spoken = subtle grey, upcoming = full opacity". Falls
  /// back to plain text when the segment has no word-level data.
  Widget _buildKaraokeText(TranscriptionSegment segment) {
    final words = segment.words;
    if (words == null || words.isEmpty) {
      // No per-word data — show segment-level highlight so user still
      // sees something during playback.
      return SelectableText(
        segment.text,
        style: TextStyle(
          fontSize: 16,
          backgroundColor: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: 0.15),
        ),
      );
    }
    final tSec = _karaokePos.inMilliseconds / 1000.0;
    final text = segment.text;
    final spans = <TextSpan>[];
    var cursor = 0;
    final accent = Theme.of(context).colorScheme.primary;
    for (final w in words) {
      final hit = text.indexOf(w.word, cursor);
      if (hit < 0) {
        return SelectableText(text, style: const TextStyle(fontSize: 16));
      }
      if (hit > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, hit)));
      }
      final isActive = tSec >= w.startTime && tSec <= w.endTime + 0.05;
      final isPast = tSec > w.endTime;
      spans.add(TextSpan(
        text: w.word,
        style: TextStyle(
          color: isActive
              ? Colors.white
              : (isPast ? Colors.grey : null),
          backgroundColor:
              isActive ? accent : null,
          fontWeight: isActive ? FontWeight.bold : null,
        ),
      ));
      cursor = hit + w.word.length;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return SelectableText.rich(
      TextSpan(children: spans),
      style: const TextStyle(fontSize: 16),
    );
  }

  Widget _buildConfidenceTintedText(TranscriptionSegment segment) {
    final text = segment.text;
    final words = segment.words!;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final w in words) {
      // Find the next occurrence of this word's text starting at cursor.
      // Tolerates leading punctuation / whitespace that the model
      // attached to the segment text but not the word entry.
      final hit = text.indexOf(w.word, cursor);
      if (hit < 0) {
        // Word doesn't line up with the segment text — bail to plain
        // rendering rather than show garbled colours.
        return SelectableText(text, style: const TextStyle(fontSize: 16));
      }
      if (hit > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, hit)));
      }
      final bg = _getConfidenceBackground(w.confidence);
      spans.add(TextSpan(
        text: w.word,
        style: TextStyle(
          backgroundColor: bg,
          color: w.confidence < 0.5
              ? _getConfidenceColor(w.confidence)
              : null,
          // Underline very-low-confidence words on top of the colour
          // shift — colour alone is insufficient for users with red /
          // green deficiency.
          decoration: w.confidence < 0.5
              ? TextDecoration.underline
              : TextDecoration.none,
          decorationColor:
              w.confidence < 0.5 ? Colors.red.withValues(alpha: 0.6) : null,
        ),
      ));
      cursor = hit + w.word.length;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return SelectableText.rich(
      TextSpan(children: spans),
      style: const TextStyle(fontSize: 16),
    );
  }

  Widget _buildFullTextView() {
    if (widget.currentTranscription == null ||
        widget.currentTranscription!.isEmpty) {
      return _buildEmptyState();
    }

    final text = widget.currentTranscription!;
    final hasSearch = _searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: hasSearch
            ? _buildHighlightedText(text, _searchQuery)
            : SelectableText(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.transcribe,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).outputNoTranscriptionYet,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).outputSelectAudioFile,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade500,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).outputNoResultsFound,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).outputTryDifferentSearch,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade500,
                ),
          ),
        ],
      ),
    );
  }

  Color _getSpeakerColor(String speaker) {
    // Generate consistent colors for speakers
    final colors = [
      Colors.blue.shade600,
      Colors.green.shade600,
      Colors.orange.shade600,
      Colors.purple.shade600,
      Colors.red.shade600,
      Colors.teal.shade600,
    ];

    final hash = speaker.hashCode;
    return colors[hash.abs() % colors.length];
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }

  /// Background tint for confidence heatmap — subtle highlight that
  /// doesn't fight with text color. High confidence = transparent,
  /// low confidence = progressively warmer.
  Color _getConfidenceBackground(double confidence) {
    if (confidence >= 0.9) return Colors.transparent;
    if (confidence >= 0.7) {
      return Colors.yellow.withValues(alpha: 0.1);
    }
    if (confidence >= 0.5) {
      return Colors.orange.withValues(alpha: 0.15);
    }
    return Colors.red.withValues(alpha: 0.2);
  }

  /// Speaker chip with rename-on-tap. Display label looks up the user's
  /// custom name in `appState.speakerNames`; falls back to the
  /// diariser's original label (e.g. "Speaker 1"). Colour stays keyed
  /// to the ORIGINAL label so consistent across all segments by that
  /// speaker even after rename.
  Widget _buildSpeakerChip(String original) {
    final renames = ref.watch(appStateProvider).speakerNames;
    final display = renames[original] ?? original;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showRenameSpeakerDialog(original, display),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getSpeakerColor(original),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          display,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showRenameSpeakerDialog(String original, String currentDisplay) {
    final controller = TextEditingController(text: currentDisplay);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).outputRenameSpeakerTitle),
        content: SizedBox(
          width: responsiveDialogWidth(ctx, designed: 320),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(ctx)
                  .outputRenameSpeakerOriginal(original),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          if (currentDisplay != original)
            TextButton(
              onPressed: () {
                ref.read(appStateProvider.notifier).renameSpeaker(original, '');
                Navigator.of(ctx).pop();
              },
              child:
                  Text(AppLocalizations.of(ctx).outputRenameSpeakerReset),
            ),
          FilledButton(
            onPressed: () {
              ref
                  .read(appStateProvider.notifier)
                  .renameSpeaker(original, controller.text);
              Navigator.of(ctx).pop();
            },
            child: Text(AppLocalizations.of(ctx).ok),
          ),
        ],
      ),
    );
  }

  void _handleOption(String option) {
    switch (option) {
      case 'timestamps':
        setState(() => _showTimestamps = !_showTimestamps);
        break;
      case 'speakers':
        setState(() => _showSpeakers = !_showSpeakers);
        break;
      case 'confidence':
        setState(() => _showConfidence = !_showConfidence);
        break;
      case 'copy_all':
        _copyAllText();
        break;
      case 'cleanup':
        _openCleanupDialog();
        break;
      case 'summarize':
        _openSummarizeDialog();
        break;
      case 'detect_language':
        _detectTranscriptLanguage();
        break;
      case 'realign_timestamps':
        _realignTimestamps();
        break;
      case 'ocr_image':
        _ocrImage();
        break;
    }
  }

  /// §12.5 — Re-align word timestamps via standalone CTC forced
  /// alignment (TADA / canary-ctc / wav2vec2 aligner). Reads the
  /// current audio file and runs alignment without a full ASR pass.
  Future<void> _realignTimestamps() async {
    final audioPath = ref.read(selectedAudioPathProvider);
    if (audioPath == null || audioPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No audio file loaded')),
        );
      }
      return;
    }

    final segments = widget.segments;
    if (segments.isEmpty) return;

    try {
      // Decode the audio to PCM.
      final decoded = crispasr.decodeAudioFile(audioPath);
      if (decoded.samples.isEmpty) return;

      final aligner = ref.read(alignerServiceProvider);
      final aligned = await aligner.realignTimestamps(
        segments,
        decoded.samples,
      );

      // Update the app state with re-aligned segments.
      final appState = ref.read(appStateProvider.notifier);
      appState.replaceSegments(aligned);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Re-aligned ${aligned.where((s) => s.words != null && s.words!.isNotEmpty).length}/${aligned.length} segments'),
          ),
        );
      }
    } catch (e, st) {
      Log.instance.w('realign', 'realignTimestamps failed', error: e, stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Alignment failed: $e')),
        );
      }
    }
  }

  /// §12.6b — Pick an image and run OCR, showing the result in a dialog.
  Future<void> _ocrImage() async {
    final ocrService = ref.read(ocrServiceProvider);
    final models = await ocrService.availableModels();
    if (models.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'No OCR models downloaded. Download one from the Models screen.')),
        );
      }
      return;
    }

    // Pick an image file.
    final pick = await pickFilesRobust(
      type: FileType.any,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'bmp', 'webp', 'tiff'],
    );
    if (pick.localPaths.isEmpty) return;
    final imagePath = pick.localPaths.first;

    // Decode the image to raw RGBA bytes using Flutter's codec.
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) return;
    final bytes = await imageFile.readAsBytes();

    try {
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData =
          await image.toByteData(format: ImageByteFormat.rawRgba);
      if (byteData == null) return;
      var rgba = byteData.buffer.asUint8List();
      var width = image.width;
      var height = image.height;
      image.dispose();

      // §12.8g — Optional scan cleanup before OCR.
      // Convert RGBA→RGB for the scan cleanup pipeline.
      final scanService = ref.read(scanPreprocessServiceProvider);
      try {
        final rgbLen = width * height * 3;
        final rgb = Uint8List(rgbLen);
        for (var i = 0, j = 0; i < rgba.length && j < rgbLen; i += 4, j += 3) {
          rgb[j] = rgba[i];
          rgb[j + 1] = rgba[i + 1];
          rgb[j + 2] = rgba[i + 2];
        }
        final cleaned = scanService.process(rgb, width, height);
        if (cleaned.pixels.isNotEmpty) {
          // Convert cleaned RGB back to RGBA for OCR.
          final cleanRgba = Uint8List(cleaned.width * cleaned.height * 4);
          for (var i = 0, j = 0;
              i < cleaned.pixels.length && j < cleanRgba.length;
              i += 3, j += 4) {
            cleanRgba[j] = cleaned.pixels[i];
            cleanRgba[j + 1] = cleaned.pixels[i + 1];
            cleanRgba[j + 2] = cleaned.pixels[i + 2];
            cleanRgba[j + 3] = 255;
          }
          rgba = cleanRgba;
          width = cleaned.width;
          height = cleaned.height;
          Log.instance.i('ocr', 'scan cleanup applied',
              fields: {'ms': cleaned.processingTime.inMilliseconds});
        }
      } catch (e) {
        // Scan cleanup failed — continue with raw image.
        Log.instance.d('ocr', 'scan cleanup unavailable: $e');
      }

      // Run OCR with the first available model.
      final result = ocrService.recognizeRaw(
        rgba,
        width,
        height,
        4, // RGBA channels
        modelPath: models.first,
      );

      if (!mounted) return;

      // Show result in a dialog.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context).outputOcrImage),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.text.isNotEmpty) ...[
                  // EU AI Act Art. 50(2) — AI-generated text disclosure.
                  Text(
                    result.disclosureText,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
                SelectableText(
                  result.text.isEmpty ? 'No text recognized.' : result.text,
                ),
              ],
            ),
          ),
          actions: [
            if (result.text.isNotEmpty)
              TextButton(
                onPressed: () {
                  // Copy carries the disclosure — once the text leaves the
                  // app the surrounding UI no longer supplies context.
                  Clipboard.setData(
                      ClipboardData(text: result.textWithDisclosure));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
                child: const Text('Copy'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      Log.instance.w('ocr', 'OCR image failed', error: e, stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR failed: $e')),
        );
      }
    }
  }

  /// §5.24-F — run text-LID over the current transcript and report
  /// the detected language. Tries GlotLID (2102 langs) and FastText
  /// LID-176 first for wider coverage; falls back to CLD3.
  Future<void> _detectTranscriptLanguage() async {
    final text = (widget.currentTranscription ??
            widget.segments.map((s) => s.text).join(' '))
        .trim();
    if (text.isEmpty) return;
    final modelService = ref.read(modelServiceProvider);

    // Try text-LID models in coverage order: GlotLID > FastText > CLD3.
    String? modelPath;
    String modelName = 'cld3';
    for (final candidate in [
      ('glotlid-f16', 'GlotLID'),
      ('fasttext-lid176-f16', 'FastText'),
      ('cld3-f16', 'CLD3'),
    ]) {
      final p = await modelService.getWhisperCppModelPath(candidate.$1);
      if (p != null) {
        modelPath = p;
        modelName = candidate.$2;
        break;
      }
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (modelPath == null) {
      final ll = AppLocalizations.of(context);
      messenger.showSnackBar(SnackBar(
        content: Text(ll.outputLidModelNeeded),
        action: SnackBarAction(
          label: ll.outputLidModelsButton,
          onPressed: () {
            if (mounted) context.push('/models');
          },
        ),
      ));
      return;
    }
    crispasr.TextLanguage? result;
    try {
      result = crispasr.detectTextLanguage(text, modelPath);
    } catch (e, st) {
      Log.instance.w('output', 'text-LID failed', error: e, stack: st);
    }
    if (!mounted) return;
    if (result == null) {
      messenger.showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).outputLidFailed)));
      return;
    }
    final pct = (result.confidence * 100).round();
    messenger.showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).outputLidDetected(
          result.code, pct.toString(), modelName)),
      duration: const Duration(seconds: 3),
    ));
  }

  void _handleSegmentAction(String action, TranscriptionSegment segment) {
    switch (action) {
      case 'play':
        _playSegment(segment);
        break;
      case 'copy':
        _copySegmentText(segment);
        break;
      case 'edit':
        _editSegment(segment);
        break;
    }
  }

  /// Play the source audio from the segment's start time, with
  /// karaoke-style word highlighting driven by `positionStream`. Falls
  /// back to a stub snackbar when no source path is available
  /// (mic-stream transcripts, history entries that lost their file).
  Future<void> _playSegment(TranscriptionSegment segment) async {
    final audioPath = ref.read(selectedAudioPathProvider);
    if (audioPath == null || audioPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)
              .outputPlayingSegment(segment.formattedTime)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    _player ??= AudioPlayer();
    _posSub ??= _player!.positionStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _karaokePos = p;
        _karaokePlaying = _player!.playing;
      });
    });
    try {
      // Reload only when switching files (cheap no-op when same path).
      if (_player!.audioSource == null) {
        await _player!.setFilePath(audioPath);
      }
      await _player!.seek(Duration(milliseconds: (segment.startTime * 1000).round()));
      await _player!.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .playbackFailed(e.toString()))),
      );
    }
  }

  void _copySegmentText(TranscriptionSegment segment) {
    final renames = ref.read(appStateProvider).speakerNames;
    final spk = segment.speaker == null
        ? null
        : (renames[segment.speaker!] ?? segment.speaker!);
    final text =
        _showSpeakers && spk != null ? '$spk: ${segment.text}' : segment.text;

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).outputSegmentCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyAllText() {
    final text = widget.currentTranscription ?? '';
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).outputAllCopied),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _editSegment(TranscriptionSegment segment) {
    final index = widget.segments.indexOf(segment);
    if (index < 0) return;
    final controller = TextEditingController(text: segment.text);
    // §5.1.11 — pre-compute the per-word alt-candidate chips. Each
    // entry contains the rendered word text, the leading-space-trimmed
    // display string, and the alt list (already sorted descending by
    // p on the C side). Empty list = "no alts on this segment", which
    // collapses the suggestions block entirely.
    final altSuggestions = <_WordAltSuggestion>[];
    final segWords = segment.words;
    if (segWords != null) {
      for (final w in segWords) {
        if (w.alts.isEmpty) continue;
        final displayWord = w.word.startsWith(' ')
            ? w.word.substring(1)
            : w.word;
        if (displayWord.isEmpty) continue;
        altSuggestions.add(_WordAltSuggestion(
          original: w.word,
          display: displayWord,
          alts: w.alts,
        ));
      }
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).outputEditSegment),
        content: SizedBox(
          width: responsiveDialogWidth(ctx, designed: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                maxLines: 6,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: segment.formattedTime,
                ),
              ),
              if (altSuggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(ctx).outputEditAltSuggestions,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in altSuggestions)
                      _AltSuggestionChip(
                        suggestion: s,
                        onPick: (replacement) {
                          // Replace the first occurrence of the
                          // word in the working buffer. Picks are
                          // single-shot per chip per session; we
                          // keep the chip visible so the user can
                          // still pick a different alt if they
                          // change their mind, but the original
                          // word disappears from the textfield on
                          // first replace.
                          final cur = controller.text;
                          final replacementClean =
                              replacement.startsWith(' ')
                                  ? replacement.substring(1)
                                  : replacement;
                          final next =
                              TranscriptionOutputWidget.replaceFirstWholeWord(
                                  cur, s.display, replacementClean);
                          controller.text = next;
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(ctx).outputEditAltSuggestionsHint,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () async {
              final next = controller.text.trim();
              if (next.isNotEmpty && next != segment.text) {
                final notifier = ref.read(appStateProvider.notifier);
                notifier.editSegment(index, next);
                // §5.1.3 persist — if this transcription has a
                // history entry on disk, overwrite the JSON so
                // the edit survives a reload. Skip when there's
                // no id (mid-flight transcription, mock engine,
                // explicit "clear" before save).
                final st = ref.read(appStateProvider);
                final id = st.historyEntryId;
                if (id != null) {
                  try {
                    final entry = HistoryEntry(
                      id: id,
                      createdAt: DateTime.now(),
                      engineId: 'crispasr',
                      segments: st.segments,
                      speakerNames: st.speakerNames,
                    );
                    await ref
                        .read(historyServiceProvider)
                        .update(entry);
                  } catch (_) {
                    // History update failure isn't fatal — the
                    // edit is still in AppState.
                  }
                }
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(AppLocalizations.of(ctx).ok),
          ),
        ],
      ),
    );
  }

  void _showSegmentOptions(TranscriptionSegment segment) {
    // §5.1.5 Phase D — only show audio-editor entries when we
    // actually have an audio file to open. URL-only transcripts
    // (in-flight from a remote / mic stream that wasn't saved)
    // get the play/copy/edit-text trio without the editor links.
    final audioPath = ref.read(selectedAudioPathProvider);
    final hasAudio = audioPath != null && audioPath.isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(AppLocalizations.of(sheetCtx).outputPlaySegment),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _playSegment(segment);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(AppLocalizations.of(sheetCtx).outputCopyText),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _copySegmentText(segment);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(AppLocalizations.of(sheetCtx).outputEditSegment),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _editSegment(segment);
            },
          ),
          if (hasAudio) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.content_cut),
              title: Text(AppLocalizations.of(sheetCtx)
                  .outputEditSegmentInAudioEditor),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _openInAudioEditor(audioPath,
                    startSec: segment.startTime,
                    endSec: segment.endTime);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_location),
              title: Text(AppLocalizations.of(sheetCtx)
                  .outputMarkSegmentInAudioEditor),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _openInAudioEditor(audioPath,
                    markSec: segment.startTime);
              },
            ),
            // Enroll this segment's voice into the speaker DB so future
            // recordings re-identify the speaker (pairs with the
            // "Identify speakers" toggle). Niche path → inline English.
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: Text(AppLocalizations.of(context).enrollFromSegment),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _enrollSpeakerFromSegment(segment, audioPath);
              },
            ),
          ],
          // §5.25.10 — Segment annotation tags.
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(AppLocalizations.of(context).outputTagSegment),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _showTagPicker(segment);
            },
          ),
        ],
      ),
    );
  }

  /// §5.25.10 — Show a dialog to add/remove tags on a segment.
  void _showTagPicker(TranscriptionSegment segment) {
    final segIdx = widget.segments.indexOf(segment);
    if (segIdx < 0) return;
    final currentTags = Set<String>.from(segment.tags);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).outputTagSegment),
          content: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: SegmentTag.values.map((tag) {
              final active = currentTags.contains(tag.name);
              return FilterChip(
                label: Text('${tag.emoji} ${tag.label}'),
                selected: active,
                onSelected: (v) {
                  setDialogState(() {
                    if (v) {
                      currentTags.add(tag.name);
                    } else {
                      currentTags.remove(tag.name);
                    }
                  });
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppLocalizations.of(context).dialogCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _applyTags(segIdx, currentTags.toList());
              },
              child: Text(AppLocalizations.of(context).dialogApply),
            ),
          ],
        ),
      ),
    );
  }

  /// Apply tags to a segment and persist via AppState.
  void _applyTags(int segIdx, List<String> tags) {
    final notifier = ref.read(appStateProvider.notifier);
    final segments = List<TranscriptionSegment>.from(
        ref.read(appStateProvider).segments);
    if (segIdx >= segments.length) return;
    final old = segments[segIdx];
    segments[segIdx] = TranscriptionSegment(
      text: old.text,
      startTime: old.startTime,
      endTime: old.endTime,
      speaker: old.speaker,
      confidence: old.confidence,
      words: old.words,
      metadata: old.metadata,
      tags: tags,
    );
    notifier.replaceSegments(segments);
  }

  /// §5.25.12 — handle keyboard events for transcript navigation.
  void _handleTranscriptKeyEvent(
      KeyEvent event, List<TranscriptionSegment> segments) {
    if (event is! KeyDownEvent) return;
    if (segments.isEmpty) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyJ:
      case LogicalKeyboardKey.arrowDown:
        setState(() {
          _focusedSegmentIndex =
              (_focusedSegmentIndex + 1).clamp(0, segments.length - 1);
        });
        _scrollToFocused();
      case LogicalKeyboardKey.keyK:
      case LogicalKeyboardKey.arrowUp:
        setState(() {
          _focusedSegmentIndex =
              (_focusedSegmentIndex - 1).clamp(0, segments.length - 1);
        });
        _scrollToFocused();
      case LogicalKeyboardKey.space:
        if (_focusedSegmentIndex >= 0 &&
            _focusedSegmentIndex < segments.length) {
          _playSegment(segments[_focusedSegmentIndex]);
        }
      case LogicalKeyboardKey.enter:
        if (_focusedSegmentIndex >= 0 &&
            _focusedSegmentIndex < segments.length) {
          _editSegment(segments[_focusedSegmentIndex]);
        }
      case LogicalKeyboardKey.tab:
        // Jump to next low-confidence segment
        _jumpToNextLowConfidence(segments);
      case LogicalKeyboardKey.escape:
        setState(() => _focusedSegmentIndex = -1);
      default:
        break;
    }
  }

  void _jumpToNextLowConfidence(List<TranscriptionSegment> segments) {
    final start = _focusedSegmentIndex + 1;
    for (var i = start; i < segments.length; i++) {
      if (segments[i].confidence < 0.7 ||
          (segments[i].words?.any((w) => w.confidence < 0.7) ?? false)) {
        setState(() => _focusedSegmentIndex = i);
        _scrollToFocused();
        return;
      }
    }
    // Wrap around
    for (var i = 0; i < start && i < segments.length; i++) {
      if (segments[i].confidence < 0.7 ||
          (segments[i].words?.any((w) => w.confidence < 0.7) ?? false)) {
        setState(() => _focusedSegmentIndex = i);
        _scrollToFocused();
        return;
      }
    }
  }

  void _scrollToFocused() {
    if (_focusedSegmentIndex < 0) return;
    // Approximate: each card ~80px tall, 8px margin
    final offset = _focusedSegmentIndex * 88.0;
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Enroll the speaker heard in [segment] into the TitaNet speaker DB,
  /// so future transcripts re-identify them (when "Identify speakers" is
  /// on). Decodes [audioPath] to 16 kHz PCM, slices the segment's range
  /// (padded to >= ~3 s, TitaNet's sweet spot), and hands it to
  /// SpeakerIdService.enroll under a name the user types.
  Future<void> _enrollSpeakerFromSegment(
      TranscriptionSegment segment, String audioPath) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptSpeakerName(speakerEnrollNameSeed(segment.speaker));
    if (name == null || name.trim().isEmpty) return;

    // GDPR Art. 9(2)(a) — explicit consent before biometric processing.
    // This path used to enroll with no consent gate and no consent
    // record, which also meant the profile could never enter the
    // consent-derived match roster.
    if (!mounted) return;
    final consented = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.speakerConsentTitle),
        content: Text(l10n.speakerConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.speakerConsentAgree),
          ),
        ],
      ),
    );
    if (consented != true || !mounted) return;

    final svc = ref.read(speakerIdServiceProvider);
    if (!await svc.isAvailable) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.speakersDownloadModelHint),
        action: SnackBarAction(
          label: l10n.menuModels,
          onPressed: () {
            if (mounted) context.push('/models');
          },
        ),
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.enrollInProgress),
        duration: const Duration(seconds: 1)));
    try {
      // decodeAudioFile is a synchronous FFI decode of the whole file;
      // run it off the platform thread so a long recording doesn't jank
      // the UI. It opens its own dylib handle, so it's isolate-safe.
      final decoded = await Isolate.run(() => crispasr.decodeAudioFile(audioPath));
      final sr = decoded.sampleRate;
      final total = decoded.samples.length;
      var start = (segment.startTime * sr).floor().clamp(0, total);
      var end = (segment.endTime * sr).ceil().clamp(0, total);
      // Pad to >= 3 s when the source allows — TitaNet was trained on
      // >= 3 s windows and short slices give weak embeddings.
      const minSamples = 3 * 16000;
      if (end - start < minSamples) {
        final need = minSamples - (end - start);
        end = (end + need).clamp(0, total);
        if (end - start < minSamples) {
          start = (start - (minSamples - (end - start))).clamp(0, total);
        }
      }
      if (end <= start) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.enrollNoAudio)));
        return;
      }
      final pcm = Float32List.sublistView(decoded.samples, start, end);
      final ok = await svc.enroll(name.trim(), pcm);
      if (ok) {
        // Persist the consent record alongside the profile — without it
        // the speaker stays off the match roster (GDPR Art. 9(2)(a)).
        await svc.saveConsent(name.trim());
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? l10n.enrollSucceeded(name.trim())
            : l10n.enrollFailedShort),
      ));
    } catch (e, st) {
      Log.instance.w('speakers', 'enroll-from-segment failed',
          error: e, stack: st);
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.enrollFailedReason(e.toString()))));
      }
    }
  }

  /// Small name-entry dialog for speaker enrollment. Returns the entered
  /// name, or null on cancel.
  Future<String?> _promptSpeakerName(String seed) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: seed);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.enrollSpeakerTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.enrollSpeakerNameLabel,
            hintText: l10n.enrollSpeakerNameHint,
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.enrollAction),
          ),
        ],
      ),
    );
  }

  /// §5.1.6 — open the deterministic-cleanup dialog. Shows a
  /// toggle-set + before/after preview of the first three
  /// segments and an "Apply to all" button that runs the
  /// transforms over every segment in AppState and persists
  /// via HistoryService when the entry has an id.
  void _openCleanupDialog() {
    if (widget.segments.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => CleanupDialog(
        segments: widget.segments,
        onApply: (opts, llmMode) async {
          await _applyCleanup(opts, llmMode: llmMode);
        },
      ),
    );
  }

  Future<void> _applyCleanup(CleanupOptions opts,
      {LlmCleanupMode llmMode = LlmCleanupMode.off}) async {
    final l = AppLocalizations.of(context);
    final svc = ref.read(transcriptCleanupServiceProvider);
    final notifier = ref.read(appStateProvider.notifier);
    var changed = 0;
    // Deterministic pass first.
    for (var i = 0; i < widget.segments.length; i++) {
      final original = widget.segments[i].text;
      final cleaned = svc.cleanupText(original, opts);
      if (cleaned.isNotEmpty && cleaned != original) {
        notifier.editSegment(i, cleaned);
        changed++;
      }
    }

    // §5.1.6 v2 (cloud) / v3 (local) — optional LLM pass over
    // the (just-cleaned) segments. Off by default and silently
    // skipped when the chosen mode is unconfigured. Runs
    // sequentially with a progress snackbar; per-segment
    // failures are swallowed by the underlying service so one
    // bad call doesn't blow up the whole batch.
    if (llmMode == LlmCleanupMode.cloud) {
      final settings = ref.read(settingsServiceProvider);
      final cfg = CloudLlmConfig(
        apiUrl: settings.cloudLlmApiUrl,
        apiKey: settings.cloudLlmApiKey,
        model: settings.cloudLlmModel,
      );
      if (cfg.enabled) {
        await _runLlmPass(cfg);
      }
    } else if (llmMode == LlmCleanupMode.local) {
      final settings = ref.read(settingsServiceProvider);
      final cfg = LocalLlmConfig(
        modelPath: settings.localLlmModelPath,
        nGpuLayers: settings.localLlmNGpuLayers,
        nCtx: settings.localLlmNCtx == 0 ? null : settings.localLlmNCtx,
        nThreads:
            settings.localLlmNThreads == 0 ? null : settings.localLlmNThreads,
        maxTokens: settings.localLlmMaxTokens,
        temperature: settings.localLlmTemperature,
      );
      if (cfg.enabled) {
        await _runLocalLlmPass(cfg);
      }
    }

    // Persist to history if this transcription has a row on disk.
    final st = ref.read(appStateProvider);
    final id = st.historyEntryId;
    if (id != null) {
      try {
        final entry = HistoryEntry(
          id: id,
          createdAt: DateTime.now(),
          engineId: 'crispasr',
          segments: st.segments,
          speakerNames: st.speakerNames,
        );
        await ref.read(historyServiceProvider).update(entry);
      } catch (_) {
        // History update failure isn't fatal — the edits are
        // still in AppState.
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.outputCleanupApplied(changed)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Runs the LLM-pass over the current segments, with a
  /// cancellable progress snackbar. Reads the latest segments
  /// from AppState so any deterministic-pass edits made just
  /// before are picked up; writes the LLM-cleaned versions
  /// back via editSegment.
  Future<void> _runLlmPass(CloudLlmConfig cfg) async {
    final l = AppLocalizations.of(context);
    final llm = ref.read(cloudLlmCleanupServiceProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final cancel = CleanupCancelToken();

    // Snackbar with a Cancel action — the cancel token flips
    // on tap and the batch service bails out between segments.
    final messenger = ScaffoldMessenger.of(context);
    final controller = messenger.showSnackBar(SnackBar(
      content: Text(l.outputCleanupLlmRunning),
      duration: const Duration(minutes: 30),
      action: SnackBarAction(
        label: l.cancel,
        onPressed: cancel.cancel,
      ),
    ));

    try {
      final st = ref.read(appStateProvider);
      final texts = st.segments.map((s) => s.text).toList();
      final cleaned = await llm.cleanupBatch(
        texts: texts,
        config: cfg,
        cancel: cancel,
      );
      // Write back the deltas. cleanupBatch may return fewer
      // entries than `texts` when cancelled — only update the
      // prefix it actually processed.
      for (var i = 0; i < cleaned.length; i++) {
        if (cleaned[i] != texts[i]) {
          notifier.editSegment(i, cleaned[i]);
        }
      }
    } finally {
      controller.close();
    }
  }

  /// §5.1.6 v3 — local-LLM mirror of [_runLlmPass]. Same UX
  /// (cancellable progress snackbar, per-segment fallthrough on
  /// failure) but routes through LocalLlmCleanupService, which
  /// holds a long-lived worker isolate so the model only loads
  /// once per app session.
  Future<void> _runLocalLlmPass(LocalLlmConfig cfg) async {
    final l = AppLocalizations.of(context);
    final llm = ref.read(localLlmCleanupServiceProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final cancel = CleanupCancelToken();

    final messenger = ScaffoldMessenger.of(context);
    final controller = messenger.showSnackBar(SnackBar(
      content: Text(l.outputCleanupLocalLlmRunning),
      duration: const Duration(minutes: 30),
      action: SnackBarAction(
        label: l.cancel,
        onPressed: cancel.cancel,
      ),
    ));

    try {
      final st = ref.read(appStateProvider);
      final texts = st.segments.map((s) => s.text).toList();
      final cleaned = await llm.cleanupBatch(
        texts: texts,
        config: cfg,
        cancel: cancel,
      );
      for (var i = 0; i < cleaned.length; i++) {
        if (cleaned[i] != texts[i]) {
          notifier.editSegment(i, cleaned[i]);
        }
      }
    } on LocalLlmException catch (e) {
      // Surface the failure (e.g. "libcrispasr predates chat
      // ABI") rather than silently failing — the user picked
      // local explicitly and deserves to know why nothing
      // changed.
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
          e.kind == 'unsupported'
              ? l.settingsLocalLlmUnsupported
              : e.message,
        ),
        duration: const Duration(seconds: 6),
      ));
    } finally {
      controller.close();
    }
  }

  /// §5.1.8 — open the meeting-summarisation dialog. Gated
  /// behind the same BYOK cloud-LLM config as §5.1.6 v2; when
  /// the config is empty the dialog explains how to enable it
  /// and offers no run button.
  void _openSummarizeDialog() {
    if (widget.segments.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => SummarizeDialog(segments: widget.segments),
    );
  }

  /// Push the audio-editor route with pre-populated selection
  /// or cut-mark query params. Either pass [startSec] + [endSec]
  /// (to land with that range selected) or [markSec] (to drop a
  /// single cut marker there) — caller picks the flow.
  void _openInAudioEditor(
    String audioPath, {
    double? startSec,
    double? endSec,
    double? markSec,
  }) {
    final qp = <String, String>{
      'path': audioPath,
      if (startSec != null) 'start': startSec.toStringAsFixed(3),
      if (endSec != null) 'end': endSec.toStringAsFixed(3),
      if (markSec != null) 'mark': markSec.toStringAsFixed(3),
    };
    final query = qp.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    context.push('/edit-audio?$query');
  }
}

/// §5.1.11 — Bundle for the per-word alt suggestion. Carries the
/// original word text (with whatever leading-space marker Whisper
/// produced), the display-ready trimmed version, and the alt
/// candidate list. Built inside _editSegment and consumed by
/// `_AltSuggestionChip`.
class _WordAltSuggestion {
  final String original;
  final String display;
  final List<TranscriptionWordAlt> alts;

  const _WordAltSuggestion({
    required this.original,
    required this.display,
    required this.alts,
  });
}

/// §5.1.11 — A single tappable chip showing one word that has
/// runner-up candidates. Tapping opens a popup menu with each alt
/// (text + percent), ordered descending by probability. Selecting
/// invokes [onPick] with the alt's text — the parent dialog rewrites
/// the working textfield. The chip stays visible after a pick so the
/// user can change their mind.
class _AltSuggestionChip extends StatelessWidget {
  final _WordAltSuggestion suggestion;
  final void Function(String replacement) onPick;

  const _AltSuggestionChip({
    required this.suggestion,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: AppLocalizations.of(context).outputEditAltPickTooltip,
      onSelected: onPick,
      itemBuilder: (ctx) {
        return [
          for (final a in suggestion.alts)
            PopupMenuItem<String>(
              value: a.text,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    a.text.startsWith(' ')
                        ? a.text.substring(1)
                        : a.text,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 8),
                  // 1-decimal precision: whisper alt probabilities are
                  // often sub-1% and toStringAsFixed(0) would render
                  // every entry as "0%", which is misleading. The full
                  // 1 dp gives enough discrimination to spot the rare
                  // "actually 3.4% vs 0.2%" gap without filling the
                  // popup with noise.
                  Text('${(a.p * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
        ];
      },
      child: Chip(
        avatar: const Icon(Icons.touch_app, size: 14),
        label: Text(suggestion.display,
            style: const TextStyle(
              fontSize: 12,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
            )),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
