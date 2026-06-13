// lib/widgets/cleanup_dialog.dart — §5.1.6 transcript cleanup dialog.
// Extracted from transcription_output_widget.dart (§8.1).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../engines/transcription_engine.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/settings_service.dart';
import '../services/transcript_cleanup_service.dart';
import '../utils/responsive.dart';

/// §5.1.6 — dialog that exposes CleanupOptions toggles plus a
/// before/after preview of the first three segments. "Apply"
/// hands the chosen options back via [onApply]; the caller
/// runs the transforms over every segment and persists.
class CleanupDialog extends ConsumerStatefulWidget {
  const CleanupDialog({super.key, required this.segments, required this.onApply});

  final List<TranscriptionSegment> segments;
  final Future<void> Function(CleanupOptions opts, LlmCleanupMode llmMode)
      onApply;

  @override
  ConsumerState<CleanupDialog> createState() => _CleanupDialogState();
}

class _CleanupDialogState extends ConsumerState<CleanupDialog> {
  CleanupOptions _opts = const CleanupOptions();
  // Seed with the user's persisted preference so a repeat user
  // doesn't have to re-select the mode every time. They can
  // still override per-dialog without writing back to prefs —
  // intentional, the dialog is for one-shot tweaks.
  late LlmCleanupMode _llmMode;
  final _customFillersController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _llmMode = ref.read(settingsServiceProvider).llmCleanupMode;
  }

  @override
  void dispose() {
    _customFillersController.dispose();
    super.dispose();
  }

  void _toggle(CleanupOptions Function(CleanupOptions) m) {
    setState(() => _opts = m(_opts));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final svc = ref.read(transcriptCleanupServiceProvider);
    // Compute live preview from the first three segments. Cheap
    // enough to do on every rebuild — these are short strings.
    final previewSegs =
        widget.segments.take(3).toList(growable: false);
    final previewOpts = _opts.copyWith(
      customFillers: _customFillersController.text
          .split(RegExp(r'[,\s]+'))
          .where((s) => s.isNotEmpty)
          .toList(),
    );

    return AlertDialog(
      title: Text(l.outputCleanupTitle),
      content: SizedBox(
        width: responsiveDialogWidth(context, designed: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.outputCleanupHelp,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l.outputCleanupRemoveFillers),
                value: _opts.removeFillers,
                onChanged: (v) =>
                    _toggle((o) => o.copyWith(removeFillers: v)),
              ),
              SwitchListTile(
                title: Text(l.outputCleanupCollapseRepeats),
                value: _opts.collapseRepeats,
                onChanged: (v) =>
                    _toggle((o) => o.copyWith(collapseRepeats: v)),
              ),
              SwitchListTile(
                title: Text(l.outputCleanupSentenceCase),
                value: _opts.sentenceCase,
                onChanged: (v) =>
                    _toggle((o) => o.copyWith(sentenceCase: v)),
              ),
              SwitchListTile(
                title: Text(l.outputCleanupFixPunctuation),
                value: _opts.fixPunctuation,
                onChanged: (v) =>
                    _toggle((o) => o.copyWith(fixPunctuation: v)),
              ),
              SwitchListTile(
                title: Text(l.outputCleanupNormalizeWhitespace),
                value: _opts.normalizeWhitespace,
                onChanged: (v) =>
                    _toggle((o) => o.copyWith(normalizeWhitespace: v)),
              ),
              SwitchListTile(
                title: Text(l.outputCleanupStripAnnotations),
                subtitle: Text(l.outputCleanupStripAnnotationsHelp,
                    style: const TextStyle(fontSize: 11)),
                value: _opts.stripAnnotations,
                onChanged: (v) =>
                    _toggle((o) => o.copyWith(stripAnnotations: v)),
              ),
              TextField(
                controller: _customFillersController,
                decoration: InputDecoration(
                  labelText: l.outputCleanupCustomFillers,
                  hintText: l.outputCleanupCustomFillersHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              // §5.1.6 v2 / v3 — three-mode LLM pass selector.
              // Off / Cloud (BYOK HTTP) / Local (on-device chat
              // model via CrispASR chat ABI). Modes whose
              // settings aren't configured are disabled and the
              // help text points the user at the right Settings
              // section.
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final settings = ref.read(settingsServiceProvider);
                final hasCloud = settings.cloudLlmApiUrl.isNotEmpty &&
                    settings.cloudLlmApiKey.isNotEmpty;
                final hasLocal = settings.localLlmModelPath.isNotEmpty;
                // Disabled modes can't be picked; if the current
                // selection points at one, drop back to Off so
                // we don't try to run an unconfigured path.
                if (_llmMode == LlmCleanupMode.cloud && !hasCloud) {
                  _llmMode = LlmCleanupMode.off;
                } else if (_llmMode == LlmCleanupMode.local && !hasLocal) {
                  _llmMode = LlmCleanupMode.off;
                }
                String? subtitle;
                switch (_llmMode) {
                  case LlmCleanupMode.off:
                    subtitle = null;
                    break;
                  case LlmCleanupMode.cloud:
                    subtitle = hasCloud
                        ? l.outputCleanupLlmModeCloudHelp(
                            settings.cloudLlmModel)
                        : l.outputCleanupLlmModeCloudUnconfigured;
                    break;
                  case LlmCleanupMode.local:
                    subtitle = hasLocal
                        ? l.outputCleanupLlmModeLocalHelp(
                            _shortModelPath(settings.localLlmModelPath))
                        : l.outputCleanupLlmModeLocalUnconfigured;
                    break;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(l.outputCleanupLlmMode,
                          style:
                              Theme.of(context).textTheme.bodyMedium),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AdaptiveSegmentedButton<LlmCleanupMode>(
                        segments: [
                          AdaptiveSegment(
                              value: LlmCleanupMode.off,
                              label: l.outputCleanupLlmModeOff),
                          AdaptiveSegment(
                              value: LlmCleanupMode.cloud,
                              enabled: hasCloud,
                              label: l.outputCleanupLlmModeCloud),
                          AdaptiveSegment(
                              value: LlmCleanupMode.local,
                              enabled: hasLocal,
                              label: l.outputCleanupLlmModeLocal),
                        ],
                        selected: _llmMode,
                        onChanged: (v) =>
                            setState(() => _llmMode = v),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(subtitle,
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ],
                );
              }),
              const SizedBox(height: 12),
              Text(l.outputCleanupPreviewHeading,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              if (previewSegs.isEmpty)
                Text(l.outputCleanupPreviewEmpty,
                    style: TextStyle(color: Colors.grey.shade600)),
              for (final seg in previewSegs) ...[
                _PreviewRow(
                  before: seg.text,
                  after: svc.cleanupText(seg.text, previewOpts),
                ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: Text(l.outputCleanupApply),
          onPressed: () async {
            final apply = previewOpts;
            final mode = _llmMode;
            Navigator.of(context).pop();
            await widget.onApply(apply, mode);
          },
        ),
      ],
    );
  }

  /// Shorten an absolute path for display under the mode
  /// selector. Just the basename — the full path is shown in
  /// Settings; here we just want the user to recognise which
  /// model is going to be used.
  static String _shortModelPath(String path) {
    final ix = path.lastIndexOf(p.separator);
    return ix == -1 ? path : path.substring(ix + 1);
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.before, required this.after});

  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = before != after;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: changed
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(before,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  decoration: changed ? TextDecoration.lineThrough : null)),
          if (changed) ...[
            const SizedBox(height: 2),
            Text(after,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}
