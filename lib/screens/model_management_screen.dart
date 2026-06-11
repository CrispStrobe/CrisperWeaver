import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../services/log_service.dart';
import '../services/model_service.dart';
import '../services/settings_service.dart' show settingsServiceProvider;

class ModelManagementScreen extends ConsumerStatefulWidget {
  /// Optional deep-link filter — when set, the kind-filter chip
  /// row opens with that kind pre-selected. Used by Settings →
  /// Local LLM's "Manage" link to drop the user into the chat-LLM
  /// view without an extra tap.
  const ModelManagementScreen({super.key, this.initialKindFilter});

  final ModelKind? initialKindFilter;

  @override
  ConsumerState<ModelManagementScreen> createState() =>
      _ModelManagementScreenState();
}

class _ModelManagementScreenState extends ConsumerState<ModelManagementScreen> {
  List<ModelInfo> _whisperModels = [];
  // Free-text name search (matches displayName / name / backend / quant).
  String _nameFilter = '';
  final TextEditingController _nameFilterController = TextEditingController();
  // Backend dropdown filter; '' means any.
  String _backendFilter = '';
  // Language dropdown filter; '' means any. ISO 639-1 code matched
  // against [ModelInfo.languages] via `matchesLanguage`. Untagged
  // entries (languages == []) and explicitly multilingual entries
  // (`['*']`) pass any filter — so picking "German" narrows the
  // list to German-tagged + multilingual models without hiding
  // catalogue entries that don't yet carry language metadata.
  String _languageFilter = '';
  bool _isLoading = true;
  String? _downloadingModel;
  double _downloadProgress = 0.0;
  // null = "All". Otherwise filter to entries whose `kind` matches.
  ModelKind? _kindFilter;
  // Secondary filter active when _kindFilter == ModelKind.voice. Empty
  // means "any language". Each voice catalog entry's description ends
  // in `[lang=xx]` (xx ∈ en/de/fr/it/jp/kr/nl/pl/pt/sp/in/es) so we
  // can group them without parsing the filename.
  String _voiceLangFilter = '';

  @override
  void initState() {
    super.initState();
    // Pre-select the filter chip when the route arrived with
    // `?kind=<name>` (or the host explicitly passed
    // `initialKindFilter:`).
    _kindFilter = widget.initialKindFilter;
    _loadModels();
    // Auto-probe HuggingFace the first time the screen opens so users see
    // every available quant for every backend without having to know the
    // cloud-download button exists. Subsequent visits reuse the cached
    // results (no re-probe unless the user taps the button explicitly).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = ref.read(modelServiceProvider);
      if (!svc.hasProbedQuants) {
        _probeHf();
      }
    });
  }

  @override
  void dispose() {
    _nameFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isLoading = true);

    try {
      final modelService = ref.read(modelServiceProvider);
      // Pull whatever the C-side libcrispasr registry knows about into
      // the discovered-models map first. This is offline (just FFI calls
      // into bundled data), so it's cheap to do every time. The HF probe
      // below adds extra quant variants on top.
      modelService.refreshFromCrispasrRegistry();
      _whisperModels = await modelService.getWhisperCppModels();
    } catch (e) {
      _showErrorDialog(l10n.modelsLoadFailed(e.toString()));
    }

    setState(() => _isLoading = false);
  }

  bool _probing = false;

  Future<void> _probeHf() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _probing = true);
    try {
      final result =
          await ref.read(modelServiceProvider).refreshAvailableQuants();
      if (!mounted) return;
      final base = result.added == 0
          ? l10n.modelsProbedCountZero
          : l10n.modelsProbedCount(
              result.added, result.added == 1 ? '' : 's');
      // Surface gated / 401 repos so the user knows some sources
      // weren't reachable — historically this was silent and they
      // wondered why "we only see q4_k" for everything.
      final detail =
          result.hasFailures ? l10n.modelsSkippedRepos(result.failedRepos.length) : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$base$detail'),
          duration: Duration(seconds: result.hasFailures ? 8 : 4),
        ),
      );
      await _loadModels();
    } catch (e) {
      _showErrorDialog(l10n.modelsProbeFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  /// Lets the user paste a HuggingFace repo id + pick a backend, then
  /// probes the repo for .gguf / .bin files and registers each as a
  /// downloadable model. Mirrors `crispasr --hf-repo OWNER/NAME` on
  /// the CLI side. Catalogue-baked entries cover the common models
  /// out of the box; this is the escape hatch for repos that aren't
  /// in [ModelService.backendRepos] yet.
  Future<void> _showAddHfRepoDialog() async {
    final l10n = AppLocalizations.of(context);
    final repoController = TextEditingController();
    final allBackends = ['auto', ..._safeAvailableBackends()];
    const initialBackend = 'auto';
    final result = await showDialog<_AddHfRepoForm?>(
      context: context,
      builder: (ctx) {
        String selectedBackend = initialBackend;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(l10n.modelsHfRepoTitle),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.modelsHfRepoBody),
                  const SizedBox(height: 16),
                  TextField(
                    controller: repoController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: l10n.modelsHfRepoIdLabel,
                      hintText: l10n.modelsHfRepoIdHint,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBackend,
                    decoration: InputDecoration(
                      labelText: l10n.modelsHfRepoBackendLabel,
                      helperText: l10n.modelsHfRepoBackendHelper,
                    ),
                    items: [
                      for (final b in allBackends)
                        DropdownMenuItem(value: b, child: Text(b)),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => selectedBackend = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final id = repoController.text.trim();
                  if (id.isEmpty || !id.contains('/')) return;
                  Navigator.of(ctx).pop(
                    _AddHfRepoForm(repoId: id, backend: selectedBackend),
                  );
                },
                child: Text(l10n.modelsHfRepoProbe),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    setState(() => _probing = true);
    try {
      // When the user picks "auto", fall back to 'whisper' for the
      // probe pass — the post-download auto-detect in ModelService
      // will correct the backend from GGUF metadata once the file
      // lands on disk.
      final probeBackend =
          result.backend == 'auto' ? 'whisper' : result.backend;
      final added =
          await ref.read(modelServiceProvider).probeHfRepoForBackend(
                repoId: result.repoId,
                backend: probeBackend,
              );
      if (!mounted) return;
      final msg = added.isEmpty
          ? l10n.modelsHfRepoNoneFound(result.repoId)
          : l10n.modelsHfRepoAdded(added.length, result.repoId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _loadModels();
    } catch (e, st) {
      Log.instance.w('models', 'HF custom-repo probe failed', error: e, stack: st);
      if (!mounted) return;
      _showErrorDialog(l10n.modelsHfRepoProbeFailed(result.repoId, e.toString()));
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  /// Lists the HF repos the user added by hand (persisted across
  /// restarts) and lets them forget one. Removing drops the runtime
  /// listings and the persisted entry; already-downloaded files on disk
  /// stay put (manage those from the model list itself).
  Future<void> _showManageHfReposDialog() async {
    final l10n = AppLocalizations.of(context);
    final settings = ref.read(settingsServiceProvider);
    final modelService = ref.read(modelServiceProvider);
    final removed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var repos = settings.hfUserRepos;
        var didRemove = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(l10n.modelsHfReposTitle),
            content: SizedBox(
              width: 480,
              child: repos.isEmpty
                  ? Text(l10n.modelsHfReposEmpty)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final r in repos)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(r['repoId'] ?? ''),
                            subtitle:
                                Text(l10n.modelsHfRepoBackendValue(r['backend'] ?? '')),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: l10n.modelsHfRepoForget,
                              onPressed: () {
                                modelService.removeUserHfRepo(
                                  repoId: r['repoId'] ?? '',
                                  backend: r['backend'] ?? '',
                                );
                                didRemove = true;
                                setLocal(() => repos = settings.hfUserRepos);
                              },
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(didRemove),
                child: Text(l10n.close),
              ),
            ],
          ),
        );
      },
    );
    if (removed == true && mounted) await _loadModels();
  }

  /// Returns the runtime CrispASR backend list, plus a hard-coded
  /// 'whisper' fallback in case availableBackends() throws (e.g. the
  /// dylib is too old to expose the symbol — pre-0.5.15 builds had a
  /// 256-byte truncation bug too). The list isn't strict on the
  /// CrispASR side either — `omniasr-llm-foo` works as long as it
  /// starts with an advertised prefix.
  List<String> _safeAvailableBackends() {
    try {
      final b = crispasr.CrispasrSession.availableBackends();
      if (b.isNotEmpty) return b;
    } catch (e) {
      Log.instance.w('model-mgmt', 'availableBackends() failed, using defaults',
          fields: {'err': e.toString()});
    }
    return const ['whisper'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).modelsTitle),
        actions: [
          // §5.8(b) — one-tap curated starter set (ASR + TTS + chat-LLM).
          IconButton(
            icon: const Icon(Icons.rocket_launch_outlined),
            tooltip: AppLocalizations.of(context).modelsQuickStartTooltip,
            onPressed: (_downloadingModel != null) ? null : _showQuickStartSheet,
          ),
          IconButton(
            icon: _probing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download),
            tooltip: AppLocalizations.of(context).modelsRefreshFromHf,
            onPressed: _probing ? null : _probeHf,
          ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: AppLocalizations.of(context).modelsHfRepoAddTooltip,
            onPressed: _probing ? null : _showAddHfRepoDialog,
          ),
          IconButton(
            icon: const Icon(Icons.playlist_remove),
            tooltip: AppLocalizations.of(context).modelsHfReposManageTooltip,
            onPressed: _probing ? null : _showManageHfReposDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).modelsReloadLocal,
            onPressed: _loadModels,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildModelList(_whisperModels),
    );
  }

  Widget _buildModelList(List<ModelInfo> models) {
    if (models.isEmpty) {
      return _buildEmptyState();
    }

    var filtered = _kindFilter == null
        ? models
        : models.where((m) => m.kind == _kindFilter).toList();
    // Sub-filter by language inside the Voices tab.
    if (_kindFilter == ModelKind.voice && _voiceLangFilter.isNotEmpty) {
      filtered = filtered
          .where((m) => m.description.contains('[lang=$_voiceLangFilter]'))
          .toList();
    }
    // Backend filter (parakeet, whisper, voxtral, ...). Empty = any.
    if (_backendFilter.isNotEmpty) {
      filtered = filtered.where((m) => m.backend == _backendFilter).toList();
    }
    if (_languageFilter.isNotEmpty) {
      filtered =
          filtered.where((m) => m.matchesLanguage(_languageFilter)).toList();
    }
    // Free-text name search — matches displayName / name / backend /
    // quantization so users can type "q5" or "tiny" or "voxtral" and
    // narrow the list to anything relevant. Same shape as the
    // transcribe screen's model-picker filter.
    if (_nameFilter.isNotEmpty) {
      filtered = filtered.where((m) {
        final hay = ('${m.displayName} ${m.name} ${m.backend} '
                '${m.quantization}')
            .toLowerCase();
        return hay.contains(_nameFilter);
      }).toList();
    }

    return Column(
      children: [
        _buildSummaryCard(models),
        _buildKindFilterRow(models),
        if (_kindFilter == ModelKind.voice)
          _buildVoiceLangFilterRow(models),
        _buildSearchRow(models),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppLocalizations.of(context).modelsCategoryEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final model = filtered[index];
                    return _buildModelCard(model);
                  },
                ),
        ),
      ],
    );
  }

  /// Filter chips: "All / ASR / TTS / Voices / Codecs / Post-processors".
  /// Counts in parens make it obvious which buckets are populated.
  Widget _buildKindFilterRow(List<ModelInfo> models) {
    final l10n = AppLocalizations.of(context);
    int countOf(ModelKind? k) =>
        k == null ? models.length : models.where((m) => m.kind == k).length;

    Widget chip(String label, ModelKind? kind) {
      final n = countOf(kind);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilterChip(
          label: Text('$label ($n)'),
          selected: _kindFilter == kind,
          onSelected: (_) => setState(() => _kindFilter = kind),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          chip(l10n.modelsFilterAll, null),
          chip(l10n.modelsFilterAsr, ModelKind.asr),
          chip(l10n.modelsFilterTts, ModelKind.tts),
          chip(l10n.modelsFilterVoices, ModelKind.voice),
          chip(l10n.modelsFilterCodecs, ModelKind.codec),
          chip(l10n.modelsFilterPostproc, ModelKind.punc),
          // Translate filter — surfaces M2M-100 / WMT21 / MADLAD-400
          // text-to-text models. Also reachable by deep-link from the
          // Translate screen's "Open Model Management" button.
          chip(l10n.modelsFilterTranslate, ModelKind.translate),
          // §5.1.6 v3.1 — chat-LLM catalogue. Localised string so
          // future families (additional non-ASR/TTS kinds) can
          // tag-along easily.
          chip(AppLocalizations.of(context).modelsKindFilterChatLlm,
              ModelKind.chatLlm),
        ],
      ),
    );
  }

  /// Free-text name search + backend dropdown — mirrors the same
  /// filter row on the main transcribe screen. Lets the user type
  /// "q5" / "tiny" / "voxtral" or restrict by backend without
  /// scrolling through the full list.
  Widget _buildSearchRow(List<ModelInfo> models) {
    final backends = <String>{
      for (final m in models)
        if (m.backend.isNotEmpty) m.backend
    }.toList()
      ..sort();

    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameFilterController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: l.modelFilterHint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                suffixIcon: _nameFilter.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _nameFilterController.clear();
                          setState(() => _nameFilter = '');
                        },
                      ),
              ),
              onChanged: (v) =>
                  setState(() => _nameFilter = v.toLowerCase()),
            ),
          ),
          const SizedBox(width: 8),
          // Backend filter — Autocomplete rather than a plain dropdown so
          // it stays usable as the linked-backend list grows (mirrors the
          // Transcribe screen's source-language picker). '' is the
          // "any backend" sentinel, shown as the localized label.
          SizedBox(
            width: 200,
            child: _BackendFilterField(
              // Re-seed the field text when the selection changes (e.g.
              // cleared via the kind tabs) — Autocomplete otherwise
              // latches its controller text on first build.
              key: ValueKey('backend-filter-$_backendFilter'),
              backends: backends,
              selected: _backendFilter,
              anyLabel: l.modelAnyBackend,
              onSelected: (b) => setState(() => _backendFilter = b),
            ),
          ),
          const SizedBox(width: 8),
          // Language dropdown — narrows the list by `matchesLanguage`.
          // Source of options: AppConstants.supportedLanguages (the
          // 30-language list the transcription source-language picker
          // also uses), minus "auto" — the model-list language filter
          // doesn't have an "auto" concept, the empty option ("Any")
          // already covers "don't filter".
          DropdownButton<String>(
            value: _languageFilter,
            items: [
              DropdownMenuItem(
                  value: '',
                  child: Text(AppLocalizations.of(context).modelsAnyLanguage)),
              for (final entry in AppConstants.supportedLanguages.entries)
                if (entry.key != 'auto')
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text('${entry.value} (${entry.key})'),
                  ),
            ],
            onChanged: (v) => setState(() => _languageFilter = v ?? ''),
          ),
        ],
      ),
    );
  }

  /// Sub-filter row shown only when the Voices tab is active. Pulls
  /// the unique language codes from the voice catalog descriptions
  /// (each contains `[lang=xx]`) and renders one chip per language
  /// plus an "All" chip. Counts in parens reveal which languages are
  /// represented in the bundled catalog.
  Widget _buildVoiceLangFilterRow(List<ModelInfo> models) {
    final voices = models.where((m) => m.kind == ModelKind.voice).toList();
    final langCounts = <String, int>{};
    final re = RegExp(r'\[lang=([a-z]+)\]');
    for (final m in voices) {
      final hit = re.firstMatch(m.description);
      if (hit == null) continue;
      langCounts.update(hit.group(1)!, (v) => v + 1, ifAbsent: () => 1);
    }
    final langs = langCounts.keys.toList()..sort();
    if (langs.isEmpty) return const SizedBox.shrink();

    Widget chip(String label, String value, int n) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilterChip(
            label: Text('$label ($n)'),
            selected: _voiceLangFilter == value,
            onSelected: (_) => setState(() => _voiceLangFilter = value),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          chip(AppLocalizations.of(context).modelsFilterAllLangs, '',
              voices.length),
          for (final l in langs) chip(l, l, langCounts[l]!),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(List<ModelInfo> models) {
    final downloadedCount = models.where((m) => m.isDownloaded).length;
    final totalSize = _calculateTotalSize(models.where((m) => m.isDownloaded));

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.memory,
              size: 32,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CrispASR Models',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$downloadedCount of ${models.length} downloaded',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    AppLocalizations.of(context).modelsTotalSize(totalSize),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(ModelInfo model) {
    final isDownloading = _downloadingModel == model.name;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              model.isDownloaded ? Colors.green.shade100 : Colors.grey.shade200,
          child: Icon(
            model.isDownloaded ? Icons.check : Icons.download,
            color: model.isDownloaded
                ? Colors.green.shade700
                : Colors.grey.shade600,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                model.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            if (model.backend.isNotEmpty && model.backend != 'whisper')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  model.backend,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ),
            if (model.recommendedDefault) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  AppLocalizations.of(context).modelsRecommendedBadge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            if (model.quantization.isNotEmpty && model.quantization != 'f16')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  model.quantization,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade800,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).modelSize(model.size)),
            Text(model.description),
            if (model.isDownloaded)
              Text(
                AppLocalizations.of(context).modelsDownloaded,
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (isDownloading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).modelsDownloadingPercent(
                        (_downloadProgress * 100).toStringAsFixed(1)),
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: _downloadProgress),
                ],
              )
            else
              Text(AppLocalizations.of(context).modelsNotDownloaded),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (model.isDownloaded) ...[
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteModel(model),
                tooltip: AppLocalizations.of(context).modelsDelete,
              ),
            ] else if (!isDownloading) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: Text(AppLocalizations.of(context).modelsDownload),
                onPressed: () => _downloadModel(model),
              ),
            ],
          ],
        ),
        isThreeLine: isDownloading,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.memory, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).modelsNoneAvailable,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context).modelsRetry),
            onPressed: _loadModels,
          ),
        ],
      ),
    );
  }

  /// §5.8(b) — curated starter set spanning the app's three pillars:
  /// transcribe (Whisper base), synthesise (Kokoro TTS) and tidy/summarise
  /// (a small chat LLM). Curation lives in one place
  /// (ModelService.recommendedDefaultModels) and is resolved here via
  /// defaultForBackend, so this stays a pure consumer.
  static const _quickStartBackends = <String>['whisper', 'kokoro', 'chat'];

  IconData _quickStartIcon(ModelKind kind) {
    switch (kind) {
      case ModelKind.tts:
        return Icons.record_voice_over_outlined;
      case ModelKind.chatLlm:
        return Icons.smart_toy_outlined;
      default:
        return Icons.mic_none;
    }
  }

  void _showQuickStartSheet() {
    final modelService = ref.read(modelServiceProvider);
    // Resolve curated defaults to the already-loaded ModelInfo rows so we
    // get live isDownloaded + size. Skip any backend with no curated
    // default or no matching row.
    final items = <ModelInfo>[];
    for (final backend in _quickStartBackends) {
      final def = modelService.defaultForBackend(backend);
      if (def == null) continue;
      for (final m in _whisperModels) {
        if (m.name == def.name) {
          items.add(m);
          break;
        }
      }
    }
    if (items.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final missing = items.where((m) => !m.isDownloaded).toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.quickStartTitle,
                    style: Theme.of(sheetCtx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(l10n.quickStartSubtitle,
                    style: Theme.of(sheetCtx).textTheme.bodyMedium),
                const SizedBox(height: 12),
                for (final m in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_quickStartIcon(m.kind)),
                    title: Text(m.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(m.size),
                    trailing: m.isDownloaded
                        ? Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.check, size: 16),
                            label: Text(l10n.quickStartInstalled),
                          )
                        : IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () {
                              Navigator.of(sheetCtx).pop();
                              _downloadModel(m);
                            },
                          ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: missing.isEmpty
                      ? Text(l10n.quickStartAllInstalled,
                          style: Theme.of(sheetCtx).textTheme.bodySmall)
                      : FilledButton.icon(
                          icon: const Icon(Icons.download),
                          label: Text(l10n.quickStartDownloadAll),
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            _downloadMany(missing);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Fetch several starter models sequentially, reusing the single-model
  /// path so progress + error handling stay identical.
  Future<void> _downloadMany(List<ModelInfo> models) async {
    for (final m in models) {
      if (!mounted) return;
      await _downloadModel(m);
    }
  }

  /// Confirmation gate for non-commercial / research-only weights. Returns
  /// true when the user accepts the licence terms. Surfaces the licence
  /// string verbatim so the choice is informed (licence-compliance).
  Future<bool> _confirmNonCommercialDownload(ModelDefinition def) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gavel, color: Colors.orange),
        title: const Text('Non-commercial licence'),
        content: Text(
          '${def.displayName} is licensed:\n\n'
          '${def.license}\n\n'
          'This permits non-commercial / research use only. By downloading '
          'you confirm you will not use these weights commercially.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _downloadModel(ModelInfo model) async {
    final l10n = AppLocalizations.of(context);
    final modelService = ref.read(modelServiceProvider);
    // Licence-compliance gate: non-commercial (CC-BY-NC, research-only)
    // weights require explicit confirmation before download so users do
    // not unknowingly accept non-commercial terms.
    final ncDef = modelService.lookupDefinition(model.name);
    if (ncDef != null && ncDef.isNonCommercial) {
      final accepted = await _confirmNonCommercialDownload(ncDef);
      if (!accepted) return;
    }
    // Build the download queue: the main model first, then any
    // companions it declares (TTS voicepacks, codec/tokenizer GGUFs,
    // etc.) that aren't already on disk. This makes Model Management
    // a one-click affair for the multi-file backends — kokoro, orpheus,
    // qwen3-tts, vibevoice, mimo-asr — instead of forcing the user to
    // discover the engine's "Companion ... not downloaded" error at
    // load time and hunt for the matching row.
    final queue = <ModelInfo>[model];
    final mainDef = modelService.lookupDefinition(model.name);
    if (mainDef != null) {
      for (final cName in mainDef.companions) {
        ModelInfo? cInfo;
        for (final m in _whisperModels) {
          if (m.name == cName) {
            cInfo = m;
            break;
          }
        }
        if (cInfo != null && !cInfo.isDownloaded) {
          queue.add(cInfo);
        }
      }
    }

    final fetched = <String>[];
    try {
      for (final item in queue) {
        if (!mounted) return;
        setState(() {
          _downloadingModel = item.name;
          _downloadProgress = 0.0;
        });
        final ok = await modelService.downloadWhisperCppModel(
          item.name,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _downloadProgress = progress);
          },
        );
        if (!ok) {
          _showErrorDialog(l10n.modelsDownloadFailedNamed(item.displayName));
          return;
        }
        fetched.add(item.displayName);
      }
      if (!mounted) return;
      final summary = fetched.length == 1
          ? l10n.modelsDownloadedOne(fetched.first)
          : l10n.modelsDownloadedMany(fetched.length, fetched.join(', '));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary)));
      await _loadModels();
    } catch (e) {
      _showErrorDialog(l10n.modelsDownloadFailedReason(e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _downloadingModel = null;
          _downloadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _deleteModel(ModelInfo model) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).modelsDelete),
        content: Text(
            AppLocalizations.of(context).modelDeleteConfirm(model.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success =
          await ref.read(modelServiceProvider).deleteModel(model.name);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.modelsDeletedNamed(model.displayName))),
        );
        await _loadModels();
      } else {
        _showErrorDialog(l10n.modelsDeleteFailedNamed(model.displayName));
      }
    } catch (e) {
      _showErrorDialog(l10n.modelsDeleteFailedReason(e.toString()));
    }
  }

  String _calculateTotalSize(Iterable<ModelInfo> models) {
    final count = models.length;
    if (count == 0) return '0 MB';

    double totalMB = 0;
    for (final model in models) {
      if (model.size.contains('GB')) {
        final gb = double.tryParse(model.size.split(' ')[0]) ?? 0;
        totalMB += gb * 1024;
      } else if (model.size.contains('MB')) {
        final mb = double.tryParse(model.size.split(' ')[0]) ?? 0;
        totalMB += mb;
      }
    }

    if (totalMB > 1024) {
      return '${(totalMB / 1024).toStringAsFixed(1)} GB';
    } else {
      return '${totalMB.toStringAsFixed(0)} MB';
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

/// Captured from the "Add from HuggingFace repo" dialog. The screen
/// uses two fields verbatim — no need for a richer model.
class _AddHfRepoForm {
  _AddHfRepoForm({required this.repoId, required this.backend});
  final String repoId;
  final String backend;
}

/// Type-ahead backend filter for the Models screen. Mirrors the
/// Transcribe screen's source-language picker: an [Autocomplete] over the
/// backends present in the current list, with '' (the [anyLabel] entry)
/// as the "don't filter" sentinel.
class _BackendFilterField extends StatelessWidget {
  const _BackendFilterField({
    super.key,
    required this.backends,
    required this.selected,
    required this.anyLabel,
    required this.onSelected,
  });

  final List<String> backends;
  final String selected;
  final String anyLabel;
  final ValueChanged<String> onSelected;

  String _label(String b) => b.isEmpty ? anyLabel : b;

  @override
  Widget build(BuildContext context) {
    final options = <String>['', ...backends];
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _label(selected)),
      displayStringForOption: _label,
      optionsBuilder: (textValue) {
        final q = textValue.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        // Keep the "any" sentinel reachable by typing the label, plus
        // any backend id containing the query.
        return options.where((b) => _label(b).toLowerCase().contains(q));
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            suffixIcon: Icon(Icons.arrow_drop_down),
          ),
          onSubmitted: (_) => onSubmit(),
          onTap: () {
            // Select-all on tap so the dropdown re-opens even when the
            // field already holds the current pick.
            if (controller.text.isNotEmpty) {
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
        );
      },
      optionsViewBuilder: (context, onSelectedCb, list) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320, maxWidth: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final option = list.elementAt(i);
                  return InkWell(
                    onTap: () => onSelectedCb(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Text(
                        _label(option),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
