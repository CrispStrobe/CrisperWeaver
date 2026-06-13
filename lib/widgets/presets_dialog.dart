// lib/widgets/presets_dialog.dart — §5.1.7 presets dialog.
// Extracted from transcription_screen.dart (§8.1).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/preset_service.dart';
import '../utils/responsive.dart';
import 'advanced_options_widget.dart' show advancedOptionsProvider;

/// §5.1.7 — dialog that lists saved presets, lets the user
/// save the current (backend, modelId, language, options)
/// tuple as a new preset, rename / delete existing rows, and
/// pop the chosen preset back to the caller for application.
class PresetsDialog extends ConsumerStatefulWidget {
  const PresetsDialog({
    super.key,
    required this.currentBackend,
    required this.currentModelId,
    required this.currentLanguage,
  });

  /// Snapshot of the screen's current state, used as the seed
  /// when the user taps "Save current as preset".
  final String currentBackend;
  final String currentModelId;
  final String currentLanguage;

  @override
  ConsumerState<PresetsDialog> createState() => _PresetsDialogState();
}

class _PresetsDialogState extends ConsumerState<PresetsDialog> {
  late List<Preset> _presets;

  @override
  void initState() {
    super.initState();
    _presets = ref.read(presetServiceProvider).all();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _presets = ref.read(presetServiceProvider).all());
  }

  Future<void> _saveCurrent() async {
    final l = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(l.presetsSaveCurrentTitle),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.presetsNameLabel,
              hintText: l.presetsNameHint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.cancel)),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(c.text.trim()),
                child: Text(l.save)),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    final svc = ref.read(presetServiceProvider);
    final opts = ref.read(advancedOptionsProvider);
    await svc.add(
      name: name,
      backend: widget.currentBackend,
      modelId: widget.currentModelId,
      language: widget.currentLanguage,
      options: opts,
    );
    await _refresh();
  }

  Future<void> _rename(Preset p) async {
    final l = AppLocalizations.of(context);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: p.name);
        return AlertDialog(
          title: Text(l.presetsRenameTitle),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.presetsNameLabel,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.cancel)),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(c.text.trim()),
                child: Text(l.save)),
          ],
        );
      },
    );
    if (next == null || next.isEmpty || next == p.name) return;
    await ref.read(presetServiceProvider).update(p.copyWith(name: next));
    await _refresh();
  }

  Future<void> _delete(Preset p) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.presetsDeleteTitle),
        content: Text(l.presetsDeleteConfirm(p.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel)),
          FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(presetServiceProvider).remove(p.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.presetsTitle),
      content: SizedBox(
        width: responsiveDialogWidth(context, designed: 560),
        height: responsiveDialogHeight(context, designed: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.presetsHelp,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(l.presetsSaveCurrent),
              onPressed: _saveCurrent,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: _presets.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.presetsEmpty,
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.grey.shade600)),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _presets.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = _presets[i];
                        return ListTile(
                          leading:
                              const Icon(Icons.bookmark_outline),
                          title: Text(p.name),
                          subtitle: Text(
                            _presetSummary(p),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: l.presetsRenameTooltip,
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _rename(p),
                              ),
                              IconButton(
                                tooltip: l.presetsDeleteTooltip,
                                icon: const Icon(Icons.delete_outline,
                                    size: 18),
                                onPressed: () => _delete(p),
                              ),
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.check, size: 16),
                                label: Text(l.presetsApply),
                                onPressed: () =>
                                    Navigator.of(context).pop(p),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
      ],
    );
  }

  String _presetSummary(Preset p) {
    final parts = <String>[];
    if (p.modelId.isNotEmpty) parts.add(p.modelId);
    if (p.language.isNotEmpty && p.language != 'auto') {
      parts.add(p.language);
    }
    if (p.options.beamSearch) parts.add('beam');
    if (p.options.vad) parts.add('vad');
    if (p.options.vocabulary.isNotEmpty) {
      parts.add('vocab:${p.options.vocabulary.length}');
    }
    if (p.options.askPrompt.isNotEmpty) parts.add('ask');
    if (p.options.targetLanguage.isNotEmpty) {
      parts.add('→${p.options.targetLanguage}');
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}
