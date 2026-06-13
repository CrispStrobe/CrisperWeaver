// lib/widgets/summarize_dialog.dart — §5.1.8 meeting summarisation dialog.
// Extracted from transcription_output_widget.dart (§8.1).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../engines/transcription_engine.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/cloud_llm_cleanup_service.dart';
import '../services/local_llm_cleanup_service.dart';
import '../services/settings_service.dart';
import '../services/transcript_summarize_service.dart';
import '../utils/responsive.dart';

/// §5.1.8 — dialog for meeting-style summarisation. Three
/// section toggles (action items / key topics / decisions),
/// a Run button gated on the cloud-LLM config, and a result
/// pane that renders the structured Markdown + per-section
/// lists once the run completes.
class SummarizeDialog extends ConsumerStatefulWidget {
  const SummarizeDialog({super.key, required this.segments});

  final List<TranscriptionSegment> segments;

  @override
  ConsumerState<SummarizeDialog> createState() =>
      _SummarizeDialogState();
}

class _SummarizeDialogState extends ConsumerState<SummarizeDialog> {
  bool _includeAction = true;
  bool _includeTopics = true;
  bool _includeDecisions = true;
  bool _running = false;
  SummaryResult? _result;
  String? _error;
  // Which path runs when the user clicks Summarise. Initialised
  // in initState from the persisted setting, then mutable per
  // dialog session. `off` is treated as "neither configured" in
  // this surface — Summarise has no off-mode of its own.
  LlmCleanupMode _mode = LlmCleanupMode.off;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsServiceProvider);
    final hasCloud =
        s.cloudLlmApiUrl.isNotEmpty && s.cloudLlmApiKey.isNotEmpty;
    final hasLocal = s.localLlmModelPath.isNotEmpty;
    // Honour the user's persisted preference when its path is
    // configured; otherwise fall through to whichever path IS
    // configured (preferring local since it doesn't burn
    // tokens). Default `off` only when nothing is configured.
    final pref = s.llmCleanupMode;
    if (pref == LlmCleanupMode.local && hasLocal) {
      _mode = LlmCleanupMode.local;
    } else if (pref == LlmCleanupMode.cloud && hasCloud) {
      _mode = LlmCleanupMode.cloud;
    } else if (hasLocal) {
      _mode = LlmCleanupMode.local;
    } else if (hasCloud) {
      _mode = LlmCleanupMode.cloud;
    } else {
      _mode = LlmCleanupMode.off;
    }
  }

  Set<SummaryKind> get _kinds => <SummaryKind>{
        if (_includeAction) SummaryKind.actionItems,
        if (_includeTopics) SummaryKind.keyTopics,
        if (_includeDecisions) SummaryKind.decisions,
      };

  Future<void> _run() async {
    final settings = ref.read(settingsServiceProvider);
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final transcript = widget.segments.map((s) => s.text).join('\n');
      final svc = ref.read(transcriptSummarizeServiceProvider);
      SummaryResult r;
      if (_mode == LlmCleanupMode.local) {
        final cfg = LocalLlmConfig(
          modelPath: settings.localLlmModelPath,
          nGpuLayers: settings.localLlmNGpuLayers,
          nCtx: settings.localLlmNCtx == 0 ? null : settings.localLlmNCtx,
          nThreads: settings.localLlmNThreads == 0
              ? null
              : settings.localLlmNThreads,
          maxTokens: settings.localLlmMaxTokens,
          temperature: settings.localLlmTemperature,
        );
        if (!cfg.enabled) return;
        r = await svc.summarizeLocal(
          transcript: transcript,
          kinds: _kinds,
          config: cfg,
        );
      } else {
        final cfg = CloudLlmConfig(
          apiUrl: settings.cloudLlmApiUrl,
          apiKey: settings.cloudLlmApiKey,
          model: settings.cloudLlmModel,
        );
        if (!cfg.enabled) return;
        r = await svc.summarize(
          transcript: transcript,
          kinds: _kinds,
          config: cfg,
        );
      }
      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _copyAll() {
    final r = _result;
    if (r == null) return;
    Clipboard.setData(ClipboardData(text: r.rawMarkdown));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).outputAllCopied),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.read(settingsServiceProvider);
    final hasCloud = settings.cloudLlmApiUrl.isNotEmpty &&
        settings.cloudLlmApiKey.isNotEmpty;
    final hasLocal = settings.localLlmModelPath.isNotEmpty;
    final hasAny = hasCloud || hasLocal;
    final activeModel = _mode == LlmCleanupMode.local
        ? _shortModelPath(settings.localLlmModelPath)
        : settings.cloudLlmModel;
    return AlertDialog(
      title: Text(l.outputSummarizeTitle),
      content: SizedBox(
        width: responsiveDialogWidth(context, designed: 620),
        height: responsiveDialogHeight(context, designed: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasAny)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.orange.shade50,
                child: Text(l.outputSummarizeUnconfigured,
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade900)),
              )
            else
              Text(
                l.outputSummarizeHelp(activeModel),
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700),
              ),
            if (hasAny) ...[
              const SizedBox(height: 8),
              Center(
                child: AdaptiveSegmentedButton<LlmCleanupMode>(
                  segments: [
                    AdaptiveSegment(
                      value: LlmCleanupMode.cloud,
                      enabled: hasCloud && !_running,
                      label: l.outputCleanupLlmModeCloud,
                    ),
                    AdaptiveSegment(
                      value: LlmCleanupMode.local,
                      enabled: hasLocal && !_running,
                      label: l.outputCleanupLlmModeLocal,
                    ),
                  ],
                  selected: (_mode == LlmCleanupMode.cloud ||
                          _mode == LlmCleanupMode.local)
                      ? _mode
                      : (hasLocal
                          ? LlmCleanupMode.local
                          : LlmCleanupMode.cloud),
                  onChanged: (v) => setState(() => _mode = v),
                ),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              title: Text(l.outputSummarizeKindActionItems),
              value: _includeAction,
              onChanged: _running
                  ? null
                  : (v) => setState(() => _includeAction = v ?? true),
            ),
            CheckboxListTile(
              dense: true,
              title: Text(l.outputSummarizeKindKeyTopics),
              value: _includeTopics,
              onChanged: _running
                  ? null
                  : (v) => setState(() => _includeTopics = v ?? true),
            ),
            CheckboxListTile(
              dense: true,
              title: Text(l.outputSummarizeKindDecisions),
              value: _includeDecisions,
              onChanged: _running
                  ? null
                  : (v) => setState(() => _includeDecisions = v ?? true),
            ),
            const Divider(height: 16),
            Expanded(child: _buildResultPane(l)),
          ],
        ),
      ),
      actions: [
        if (_result != null)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: Text(l.outputCopyAll),
            onPressed: _copyAll,
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
        FilledButton.icon(
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.summarize_outlined, size: 18),
          label: Text(l.outputSummarizeRun),
          onPressed:
              (!hasAny || _running || _kinds.isEmpty) ? null : _run,
        ),
      ],
    );
  }

  Widget _buildResultPane(AppLocalizations l) {
    if (_error != null) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(_error!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
        ),
      );
    }
    final r = _result;
    if (r == null) {
      return Center(
        child: Text(l.outputSummarizeEmpty,
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    if (r.isEmpty) {
      return Center(
        child: Text(l.outputSummarizeNothing,
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return ListView(
      children: [
        if (_includeAction)
          _SummarizeSection(
            heading: l.outputSummarizeKindActionItems,
            items: r.actionItems,
          ),
        if (_includeTopics)
          _SummarizeSection(
            heading: l.outputSummarizeKindKeyTopics,
            items: r.keyTopics,
          ),
        if (_includeDecisions)
          _SummarizeSection(
            heading: l.outputSummarizeKindDecisions,
            items: r.decisions,
          ),
      ],
    );
  }

  static String _shortModelPath(String path) {
    final ix = path.lastIndexOf(p.separator);
    return ix == -1 ? path : path.substring(ix + 1);
  }
}

class _SummarizeSection extends StatelessWidget {
  const _SummarizeSection({required this.heading, required this.items});

  final String heading;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('—',
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
                child: Text('• $item',
                    style: const TextStyle(fontSize: 13)),
              ),
        ],
      ),
    );
  }
}
