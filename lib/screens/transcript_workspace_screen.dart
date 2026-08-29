import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../engines/transcription_engine.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show historyServiceProvider;
import '../services/history_service.dart';
import '../utils/file_utils.dart';
import '../widgets/root_aware_back_leading.dart';

class TranscriptWorkspaceScreen extends ConsumerStatefulWidget {
  const TranscriptWorkspaceScreen({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<TranscriptWorkspaceScreen> createState() =>
      _TranscriptWorkspaceScreenState();
}

class _TranscriptWorkspaceScreenState
    extends ConsumerState<TranscriptWorkspaceScreen> {
  HistoryEntry? _entry;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entry =
        await ref.read(historyServiceProvider).loadEntry(widget.entryId);
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = _entry;
    return Scaffold(
      appBar: AppBar(
        // #35 — no back button when this was reached by a stack-replacing
        // `go()`; fall back to a home button.
        leading: rootAwareBackLeading(context),
        title: Text(entry?.title ?? l.workspaceTitle),
        actions: entry == null
            ? const []
            : [
                IconButton(
                  tooltip: l.historyCopy,
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: _copy,
                ),
                PopupMenuButton<TranscriptFormat>(
                  tooltip: l.workspaceExport,
                  icon: const Icon(Icons.ios_share_outlined),
                  onSelected: _export,
                  itemBuilder: (_) => [
                    for (final format in TranscriptFormat.values)
                      PopupMenuItem(
                        value: format,
                        child: Text(format.name.toUpperCase()),
                      ),
                  ],
                ),
              ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : entry == null
              ? Center(child: Text(l.workspaceMissing))
              : _body(entry),
    );
  }

  Widget _body(HistoryEntry entry) {
    final l = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final metadata = _metadataCard(entry);
    final transcript = _transcript(entry);
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.copy_outlined),
                label: Text(l.historyCopy),
                onPressed: _copy,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined),
                label: Text(l.logsShare),
                onPressed: _shareText,
              ),
              if (entry.sourcePath != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.graphic_eq),
                  label: Text(l.editAudioOpen),
                  onPressed: () => context.push(
                    '/edit-audio?path=${Uri.encodeQueryComponent(entry.sourcePath!)}',
                  ),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.translate),
                label: Text(l.menuTranslate),
                onPressed: () =>
                    context.push('/translate', extra: entry.fullText),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: transcript),
                const SizedBox(width: 16),
                SizedBox(width: 280, child: metadata),
              ],
            )
          else ...[
            metadata,
            const SizedBox(height: 12),
            transcript,
          ],
        ],
      ),
    );
  }

  Widget _metadataCard(HistoryEntry entry) {
    final l = AppLocalizations.of(context);
    final date = DateFormat.yMMMd().add_Hm().format(entry.createdAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.workspaceDetails,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _detail(l.workspaceCreated, date),
            _detail(l.workspaceEngine, entry.engineId),
            if (entry.modelId != null)
              _detail(l.workspaceModel, entry.modelId!),
            if (entry.language != null)
              _detail(l.workspaceLanguage, entry.language!),
            _detail(
                l.workspaceDuration,
                _duration(
                    entry.segments.isEmpty ? 0 : entry.segments.last.endTime)),
            _detail(l.workspaceSegments, '${entry.segments.length}'),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            SelectableText(value),
          ],
        ),
      );

  Widget _transcript(HistoryEntry entry) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.workspaceTranscript,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var i = 0; i < entry.segments.length; i++) _segment(entry, i),
          ],
        ),
      ),
    );
  }

  Widget _segment(HistoryEntry entry, int index) {
    final segment = entry.segments[index];
    final originalSpeaker = segment.speaker;
    final speaker = originalSpeaker == null
        ? null
        : entry.speakerNames[originalSpeaker] ?? originalSpeaker;
    final l = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l.workspaceSegmentSemantics(
        index + 1,
        _duration(segment.startTime),
        segment.text,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                _duration(segment.startTime),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (speaker != null)
                    ActionChip(
                      avatar: const Icon(Icons.person_outline, size: 16),
                      label: Text(speaker),
                      onPressed: () =>
                          _renameSpeaker(originalSpeaker!, speaker),
                    ),
                  SelectableText(segment.text),
                  if (segment.tags.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final tag in segment.tags) Chip(label: Text(tag))
                      ],
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: l.workspaceEditSegment,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _editSegment(index, segment),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSegment(int index, TranscriptionSegment segment) async {
    final controller = TextEditingController(text: segment.text);
    final changed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).workspaceEditSegment),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (changed == null || changed.isEmpty || _entry == null) return;
    final segments = [..._entry!.segments];
    segments[index] = TranscriptionSegment(
      text: changed,
      startTime: segment.startTime,
      endTime: segment.endTime,
      speaker: segment.speaker,
      confidence: segment.confidence,
      tags: segment.tags,
      metadata: {...segment.metadata, 'edited': true},
    );
    await _save(_entry!.copyWith(segments: segments));
  }

  Future<void> _renameSpeaker(String original, String current) async {
    final controller = TextEditingController(text: current);
    final changed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).workspaceRenameSpeaker),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (changed == null || changed.isEmpty || _entry == null) return;
    await _save(_entry!.copyWith(
      speakerNames: {..._entry!.speakerNames, original: changed},
    ));
  }

  Future<void> _save(HistoryEntry entry) async {
    await ref.read(historyServiceProvider).update(entry);
    if (mounted) setState(() => _entry = entry);
  }

  Future<void> _copy() async {
    final entry = _entry!;
    await Clipboard.setData(ClipboardData(
      text: FileUtils.withDisclosure(entry.fullText, entry.segments),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).copied)),
    );
  }

  Future<void> _shareText() async {
    final entry = _entry!;
    await SharePlus.instance.share(ShareParams(
      text: FileUtils.withDisclosure(entry.fullText, entry.segments),
      subject: entry.title,
    ));
  }

  Future<void> _export(TranscriptFormat format) async {
    final entry = _entry!;
    final file = await FileUtils.saveTranscription(
      entry.fullText,
      entry.title,
      format: format,
      segments: entry.segments,
    );
    await FileUtils.shareFile(file.path, subject: entry.title);
  }

  static String _duration(double seconds) {
    final d = Duration(milliseconds: (seconds * 1000).round());
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }
}
