import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../services/log_service.dart';
import '../services/memory_estimator.dart' show memoryEstimatorProvider;
import '../services/model_service.dart';
import '../services/starter_models.dart';
import '../services/settings_service.dart' show settingsServiceProvider;
import '../widgets/root_aware_back_leading.dart';

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
  // against [ModelInfo.languages] via `matchesLanguage`. Explicitly
  // multilingual entries (`['*']`) pass any filter, and so do untagged
  // *model* rows — so picking "German" narrows the list to
  // German-tagged + multilingual models without hiding catalogue
  // entries that don't yet carry language metadata. Voicepacks are the
  // exception: they are all tagged, so an untagged one is hidden
  // rather than shown under every language (issue #35).
  String _languageFilter = '';
  bool _isLoading = true;
  String? _downloadingModel;
  double _downloadProgress = 0.0;
  // null = "All". Otherwise filter to entries whose `kind` matches.
  ModelKind? _kindFilter;
  // Secondary filter active when _kindFilter == ModelKind.voice. Empty
  // means "any language". Holds an ISO 639-1 code from the same
  // alphabet as [_languageFilter] — the chip row derives it from each
  // voice's `languages`, so "ja" here selects the VibeVoice files the
  // repo happens to name `jp-*`.
  String _voiceLangFilter = '';

  @override
  void initState() {
    super.initState();
    // Pre-select the filter chip when the route arrived with
    // `?kind=<name>` (or the host explicitly passed
    // `initialKindFilter:`).
    final advanced = ref.read(settingsServiceProvider).experimentalFeatures;
    _kindFilter = widget.initialKindFilter ?? (advanced ? null : ModelKind.asr);
    _loadModels();
    // Auto-probe HuggingFace the first time the screen opens so users see
    // every available quant for every backend without having to know the
    // cloud-download button exists. Subsequent visits reuse the cached
    // results (no re-probe unless the user taps the button explicitly).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = ref.read(modelServiceProvider);
      if (ref.read(settingsServiceProvider).experimentalFeatures &&
          !svc.hasProbedQuants) {
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
    // No AppLocalizations.of(context) before the first await: this runs
    // from initState, where dependOnInheritedWidgetOfExactType throws.
    // Because the method is async that throw landed on an un-awaited
    // future — the screen rendered but the list never loaded in debug
    // builds (found by the GUI integration suite). Resolve l10n lazily,
    // in the error path, where the tree is guaranteed mounted.
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
      if (!mounted) return;
      _showErrorDialog(AppLocalizations.of(context).modelsLoadFailed(e.toString()));
    }

    if (!mounted) return;
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
          : l10n.modelsProbedCount(result.added, result.added == 1 ? '' : 's');
      // Surface gated / 401 repos so the user knows some sources
      // weren't reachable — historically this was silent and they
      // wondered why "we only see q4_k" for everything.
      final detail = result.hasFailures
          ? l10n.modelsSkippedRepos(result.failedRepos.length)
          : '';
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
  /// in [ModelCatalog.backendRepos] yet.
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
                      helperMaxLines: 2,
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
      // When the user picks "auto", register with a 'whisper' placeholder
      // for the probe pass. The real backend is recovered from the GGUF
      // architecture metadata once the file is on disk — both after a
      // download (ModelService) and again at load time (CrispasrEngine,
      // which also covers manually-placed files). Users who want to skip
      // the guesswork can pick a concrete backend from the dropdown.
      final probeBackend =
          result.backend == 'auto' ? 'whisper' : result.backend;
      final added = await ref.read(modelServiceProvider).probeHfRepoForBackend(
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
      Log.instance
          .w('models', 'HF custom-repo probe failed', error: e, stack: st);
      if (!mounted) return;
      _showErrorDialog(
          l10n.modelsHfRepoProbeFailed(result.repoId, e.toString()));
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
                            subtitle: Text(l10n
                                .modelsHfRepoBackendValue(r['backend'] ?? '')),
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

  /// Backends this app knows how to route, used to backfill the HF-repo
  /// dialog dropdown when the native `availableBackends()` underreports.
  /// Older/mis-bundled dylibs (esp. on Windows, #30) can return an empty
  /// or whisper-only list even though the linked engine supports far
  /// more; without this the user can only pick `auto`/`whisper` and a
  /// non-whisper GGUF (e.g. Cohere ASR) gets force-routed to whisper and
  /// crashes. The engine still auto-detects the real backend from the
  /// GGUF at load time — this just lets the user force it explicitly.
  static const List<String> _knownBackends = [
    'whisper',
    'parakeet',
    'canary',
    'canary-ctc',
    'qwen3',
    'cohere',
    'granite',
    'fastconformer-ctc',
    'voxtral',
    'voxtral4b',
    'moonshine',
    'wav2vec2',
  ];

  /// Returns the runtime CrispASR backend list unioned with the curated
  /// [_knownBackends] set, so the dropdown always offers the common
  /// backends even when the dylib is too old to expose the symbol
  /// (pre-0.5.15 builds also had a 256-byte truncation bug). The list
  /// isn't strict on the CrispASR side either — `omniasr-llm-foo` works
  /// as long as it starts with an advertised prefix.
  List<String> _safeAvailableBackends() {
    final seen = <String>{};
    final out = <String>[];
    void add(String b) {
      if (b.isNotEmpty && seen.add(b)) out.add(b);
    }

    try {
      crispasr.CrispasrSession.availableBackends().forEach(add);
    } catch (e) {
      Log.instance.w('model-mgmt', 'availableBackends() failed, using defaults',
          fields: {'err': e.toString()});
    }
    // Backfill the curated set so nothing common is ever missing.
    _knownBackends.forEach(add);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final advanced = ref.read(settingsServiceProvider).experimentalFeatures;
    return Scaffold(
      appBar: AppBar(
        // #35 — onboarding can `go()` straight here, leaving no route to
        // pop and so no back button; fall back to a home button.
        leading: rootAwareBackLeading(context),
        title: Text(AppLocalizations.of(context).modelsTitle),
        actions: [
          // §5.8(b) — one-tap curated starter set (ASR + TTS + chat-LLM).
          IconButton(
            icon: const Icon(Icons.rocket_launch_outlined),
            tooltip: AppLocalizations.of(context).modelsQuickStartTooltip,
            onPressed:
                (_downloadingModel != null) ? null : _showQuickStartSheet,
          ),
          if (advanced) ...[
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
          ],
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
    // Sub-filter by language inside the Voices tab. Goes through the
    // same `matchesLanguage` the dropdown uses rather than a substring
    // hunt in the description, so a voice tagged only in `languages`
    // (live HF probe) filters identically to a static catalogue row.
    if (_kindFilter == ModelKind.voice && _voiceLangFilter.isNotEmpty) {
      filtered = filtered
          .where((m) => m.matchesLanguage(_voiceLangFilter))
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
        if (_kindFilter == ModelKind.voice) _buildVoiceLangFilterRow(models),
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
              : _buildCuratedList(filtered),
        ),
      ],
    );
  }

  /// The list, with curated starters lifted to the top under a header.
  ///
  /// A 367-entry catalogue with good filters still answers only "which of
  /// these is a Parakeet?" — never "which should I take?". A new install had
  /// no way to know that `moonshine-base-q4_k` is 47 MB and a sane first pick
  /// while `MiMo ASR (f16)` is 16 GB and will not load on any phone. The
  /// recommendations are the answer to the second question; see
  /// `StarterModels`.
  ///
  /// Suppressed once the user is searching or has narrowed by backend — at
  /// that point they have told us what they want and a "Recommended" block is
  /// in the way. Also suppressed when every pick is already downloaded, which
  /// is the state the section exists to get the user out of.
  Widget _buildCuratedList(List<ModelInfo> filtered) {
    final kind = _kindFilter;
    final narrowing = _nameFilter.isNotEmpty || _backendFilter.isNotEmpty;
    final picks = <ModelInfo>[];
    if (kind != null && !narrowing && StarterModels.hasPicksFor(kind)) {
      final ids = StarterModels.pickIdsFor(kind);
      picks.addAll(filtered.where((m) => ids.contains(m.name)));
      picks.sort((a, b) => StarterModels.rankOf(kind, a.name)
          .compareTo(StarterModels.rankOf(kind, b.name)));
    }
    final showPicks = picks.isNotEmpty && picks.any((m) => !m.isDownloaded);
    final rest = showPicks
        ? filtered.where((m) => !picks.contains(m)).toList()
        : filtered;

    final l10n = AppLocalizations.of(context);
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: (showPicks ? picks.length + 2 : 0) + rest.length,
      itemBuilder: (context, index) {
        if (showPicks) {
          if (index == 0) return _listHeader(l10n.modelsRecommendedHeader);
          if (index <= picks.length) return _buildModelCard(picks[index - 1]);
          if (index == picks.length + 1) {
            return _listHeader(l10n.modelsAllHeader(rest.length));
          }
          return _buildModelCard(rest[index - picks.length - 2]);
        }
        return _buildModelCard(rest[index]);
      },
    );
  }

  Widget _listHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
      );

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
    final advanced = ref.read(settingsServiceProvider).experimentalFeatures;
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              onChanged: (v) => setState(() => _nameFilter = v.toLowerCase()),
            ),
          ),
          if (advanced) ...[
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
          ],
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

  /// Sub-filter row shown only when the Voices tab is active. Renders
  /// one chip per language present in the voice catalogue, plus an
  /// "All" chip; the counts in parens reveal how many voices each
  /// language has.
  ///
  /// Codes come from `ModelInfo.languages` (the `[lang=xx]` description
  /// tag is only a fallback for rows that predate the tagging), and
  /// they are normalised to ISO 639-1 — the VibeVoice repo's `jp` /
  /// `kr` / `sp` / `in` filenames used to leak into the chip labels and
  /// could never match the ISO codes the language dropdown offers
  /// (issue #35).
  Widget _buildVoiceLangFilterRow(List<ModelInfo> models) {
    final voices = models.where((m) => m.kind == ModelKind.voice).toList();
    final langCounts = <String, int>{};
    final re = RegExp(r'\[lang=([a-z]+)\]');
    for (final m in voices) {
      var codes = m.languages.where((c) => c != '*');
      if (codes.isEmpty) {
        final hit = re.firstMatch(m.description);
        codes = hit == null ? const <String>[] : <String>[hit.group(1)!];
      }
      for (final c in codes) {
        langCounts.update(ModelCatalog.normalizeLanguageCode(c),
            (v) => v + 1,
            ifAbsent: () => 1);
      }
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
          // Same label shape as the language dropdown ("German (de)")
          // so the two filters are visibly the same vocabulary.
          for (final l in langs)
            chip('${AppConstants.getLanguageName(l)} ($l)', l, langCounts[l]!),
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
                    AppLocalizations.of(context).modelsCatalogueHeader,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)
                        .modelsDownloadedOfTotal(downloadedCount, models.length),
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
    final fit = StarterModels.fitFor(
        model.sizeBytes, ref.read(memoryEstimatorProvider));

    return Semantics(
      container: true,
      label: '${model.displayName}, ${_useCase(model)}, ${model.size}',
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: model.isDownloaded
                ? Colors.green.shade100
                : Colors.grey.shade200,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(AppLocalizations.of(context)
                      .modelsBestFor(_useCase(model))),
                  Text(AppLocalizations.of(context).modelSize(model.size)),
                  if (fit == DeviceFit.comfortable)
                    Text(AppLocalizations.of(context).modelsFitsDevice,
                        style: TextStyle(color: Colors.green.shade700)),
                  if (fit == DeviceFit.tight)
                    Text(AppLocalizations.of(context).modelsMemoryTight,
                        style: TextStyle(color: Colors.orange.shade800)),
                ],
              ),
              // Marked in the list, not only at the moment of download — the
              // point is that a tester can see which rows are plausible before
              // committing to a multi-gigabyte transfer.
              if (!model.isDownloaded &&
                  StarterModels.fitFor(
                          model.sizeBytes, ref.read(memoryEstimatorProvider)) ==
                      DeviceFit.tooLarge)
                Row(
                  children: [
                    Icon(Icons.memory,
                        size: 13, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).modelsTooLargeInline,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
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
      ),
    );
  }

  String _useCase(ModelInfo model) {
    final l = AppLocalizations.of(context);
    switch (model.kind) {
      case ModelKind.asr:
        if (model.backend == 'whisper') return l.modelsUseMultilingual;
        if (model.backend.contains('parakeet') ||
            model.backend.contains('moonshine')) {
          return l.modelsUseFastTranscription;
        }
        return l.modelsUseTranscription;
      case ModelKind.tts:
        return l.modelsUseSpeech;
      case ModelKind.translate:
        return l.modelsUseTranslation;
      case ModelKind.chatLlm:
        return l.modelsUseCleanup;
      case ModelKind.voice:
        return l.modelsUseVoice;
      default:
        return l.modelsUseAdvanced;
    }
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
  /// (ModelCatalog.recommendedDefaultModels) and is resolved here via
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
  /// Confirm a download the device probably cannot load.
  ///
  /// Deliberately names the two numbers rather than saying "too large":
  /// a user who disagrees with our RAM estimate can see what it was.
  Future<bool> _confirmOversizedDownload(ModelInfo model) async {
    final l10n = AppLocalizations.of(context);
    final est = ref.read(memoryEstimatorProvider);
    final budget = StarterModels.budgetBytes(est);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.memory, color: Colors.orange),
        title: Text(l10n.modelsTooLargeTitle),
        content: Text(l10n.modelsTooLargeBody(
          model.displayName,
          _formatBytes(model.sizeBytes),
          budget == null ? '—' : _formatBytes(budget),
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.modelsDownloadAnyway),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static String _formatBytes(int b) => b >= 1000000000
      ? '${(b / 1000000000).toStringAsFixed(1)} GB'
      : '${(b / 1000000).round()} MB';

  Future<bool> _confirmNonCommercialDownload(ModelDefinition def) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gavel, color: Colors.orange),
        title: Text(AppLocalizations.of(ctx).modelsNonCommercialTitle),
        content: Text(AppLocalizations.of(ctx)
            .modelsNonCommercialBody(def.displayName, def.license ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(ctx).modelsNonCommercialAccept),
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
    // Memory gate. `MemoryEstimator` has always known this device's budget,
    // but was wired only to the worker-count slider — so the app would
    // carefully refuse to run two workers against a 400 MB model and then
    // let the user download 16 GB and OOM on load. 150 catalogue entries
    // exceed 1 GB; the largest is 17.3 GB; iOS is assumed to have 3 GB.
    //
    // Confirm rather than block: the RAM figure on mobile is a conservative
    // platform default, not a reading, and a wrong estimate should not be a
    // hard wall on the user's own device.
    if (StarterModels.fitFor(
            model.sizeBytes, ref.read(memoryEstimatorProvider)) ==
        DeviceFit.tooLarge) {
      final proceed = await _confirmOversizedDownload(model);
      if (!proceed) return;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(summary)));
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
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
