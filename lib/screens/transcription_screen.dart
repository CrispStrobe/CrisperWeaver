import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';

import '../utils/platform_utils.dart' as plat;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../utils/file_picker_util.dart';

import '../utils/audio_utils.dart';

import '../main.dart';
import '../native/crispasr_import.dart' as crispasr;

import '../engines/crispasr_engine.dart' show CrispASREngine;
import '../engines/transcription_engine.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/audio_prefetch_service.dart';
import '../services/audio_service.dart';
import '../services/batch_persistence_service.dart';
import '../services/batch_queue_service.dart';
import '../services/log_service.dart';
import '../services/memory_estimator.dart';
import '../services/preset_service.dart';
import '../services/audio_watermark_service.dart';
import '../services/content_provenance_service.dart';
import '../services/spread_spectrum_watermark.dart';
import '../services/transcription_service.dart';
import '../constants/app_constants.dart';
import '../services/model_service.dart';
import '../services/settings_service.dart';
import '../services/transcription_worker_pool.dart';
import '../utils/file_utils.dart';
import '../utils/responsive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/speaker_vocab.dart';
import '../services/ab_test_service.dart';
import '../services/chapter_detection_service.dart';
import '../services/lid_service.dart';
import '../services/multilingual_transcription_service.dart';
import '../services/note_export_service.dart';
import '../widgets/advanced_options_widget.dart';
import '../widgets/audio_recorder_widget.dart';
import '../widgets/batch_queue_card.dart';
import '../widgets/narrow_tabbed_body.dart';
import '../widgets/presets_dialog.dart';
import '../widgets/transcription_output_widget.dart';
import '../providers/transcription_screen_provider.dart';
import '../widgets/diarization_settings_widget.dart';

class TranscriptionScreen extends ConsumerStatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  ConsumerState<TranscriptionScreen> createState() =>
      _TranscriptionScreenState();
}

class _TranscriptionScreenState extends ConsumerState<TranscriptionScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _modelFilterController = TextEditingController();
  // Memoized init future — the first `_ensureEngineReady()` call kicks it
  // off and any subsequent callers await the same future rather than
  // racing a second init through the service. Without this, tapping
  // "Transcribe" while the first-frame post-callback is still running
  // could spawn a parallel init.
  Future<bool>? _initFuture;

  // §8.2 — convenience getters proxying into the Riverpod provider so
  // the 100+ callsites that used the old _field syntax keep compiling
  // without a mechanical rename of every occurrence.
  String? get _selectedFilePath => ref.read(transcriptionScreenProvider).selectedFilePath;
  Uint8List? get _selectedFileBytes => ref.read(transcriptionScreenProvider).selectedFileBytes;
  String? get _selectedFileName => ref.read(transcriptionScreenProvider).selectedFileName;
  bool get _showAdvancedOptions => ref.read(transcriptionScreenProvider).showAdvancedOptions;
  bool get _enableDiarization => ref.read(transcriptionScreenProvider).enableDiarization;
  String get _language => ref.read(transcriptionScreenProvider).language;
  String get _modelName => ref.read(transcriptionScreenProvider).modelName;
  bool get _engineReady => ref.read(transcriptionScreenProvider).engineReady;
  List<ModelInfo> get _availableModels => ref.read(transcriptionScreenProvider).availableModels;
  bool get _loadingModels => ref.read(transcriptionScreenProvider).loadingModels;
  String get _modelNameFilter => ref.read(transcriptionScreenProvider).modelNameFilter;
  String get _backendFilter => ref.read(transcriptionScreenProvider).backendFilter;
  bool get _transcribePending => ref.read(transcriptionScreenProvider).transcribePending;

  bool get _dropHover => ref.read(transcriptionScreenProvider).dropHover;
  bool get _tagSegmentLanguages => ref.read(transcriptionScreenProvider).tagSegmentLanguages;

  @override
  void initState() {
    super.initState();

    // Initialize state from settings
    final settings = ref.read(settingsServiceProvider);
    final n = ref.read(transcriptionScreenProvider.notifier);
    n.setEnableDiarization(settings.enableDiarizationByDefault);
    n.setLanguage(settings.defaultLanguage);
    n.setModelName(settings.defaultModel);

    // Kick off engine initialization after the first frame so the error
    // dialog (if it occurs) has a context to attach to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureEngineReady();
      // §5.23 Q3 polish: if main.dart's load() recovered any
      // crash-interrupted jobs, surface a one-shot snackbar so the
      // user knows the queue card is pre-populated and can hit
      // Start. Only fires once per app launch — the count is
      // cleared after the snackbar shows.
      _maybeShowResumeSnackbar();
    });
  }

  void _maybeShowResumeSnackbar() {
    if (!mounted) return;
    final queue = ref.read(batchQueueProvider.notifier);
    final n = queue.lastLoadResumedCount;
    if (n <= 0) return;
    queue.acknowledgeResumedJobsSnackbar();
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.batchResumedSnackbar(n)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _modelFilterController.dispose();
    super.dispose();
  }

  Future<void> _ensureEngineReady() async {
    if (_engineReady) return;
    _initFuture ??= _doInitialize();
    try {
      await _initFuture;
    } catch (e) {
      if (mounted) {
        ref.read(appStateProvider.notifier).setError('Engine init failed: $e');
      }
    }
  }

  Future<bool> _doInitialize() async {
    final service = ref.read(transcriptionServiceProvider);
    final settings = ref.read(settingsServiceProvider);

    // On native, load models first so auto-switch knows what's downloaded.
    // On web, we need the engine initialized first (models come from the
    // cloud engine, not the local filesystem).
    if (!plat.isWeb) await _loadModels();

    final ok = await service.initialize(
      preferredEngine: settings.preferredEngine,
    );
    if (!ok) return ok;

    // On web, load the cloud model list now that the engine is ready.
    if (plat.isWeb) await _loadModels();

    // Auto-switch to a downloaded model if the persisted default isn't
    // downloaded yet. Covers the common first-launch flow: user gets
    // the "no models" snackbar → taps "Open Models" → downloads
    // a different model than the persisted default (e.g. has "base"
    // as default but only downloaded "tiny"). Without this, the next
    // launch / transcribe still tries the persisted default and
    // surfaces the same error.
    final downloaded =
        _availableModels.where((m) => m.isDownloaded).toList(growable: false);
    if (_modelName.isEmpty ||
        !downloaded.any((m) => m.name == _modelName)) {
      if (downloaded.isNotEmpty) {
        // Prefer a whisper one if available (most common pick), else
        // first downloaded.
        final whisperFirst = downloaded.firstWhere(
            (m) => m.backend == 'whisper',
            orElse: () => downloaded.first);
        final switched = whisperFirst.name;
        Log.instance.i('ui',
            'Auto-switching default model: was=$_modelName now=$switched');
        if (mounted) ref.read(transcriptionScreenProvider.notifier).setModelName(switched);
        settings.defaultModel = switched;
      } else if (mounted) {
        // First-launch / nothing downloaded — the "default model X isn't
        // downloaded" message names a specific model (typically `base`)
        // which is confusing because the user never picked it. Show a
        // generic "no models yet, open Models" prompt instead.
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.noModelsDownloadedYet),
            duration: const Duration(seconds: 8),
            showCloseIcon: true,
            action: SnackBarAction(
              label: l.openModels,
              onPressed: () {
                if (mounted) context.push('/models');
              },
            ),
          ),
        );
      }
    }

    if (_modelName.isNotEmpty && downloaded.isNotEmpty) {
      try {
        await service.loadModel(_modelName);
      } catch (e, st) {
        // Non-fatal — the user can still pick a different model from the
        // dropdown — but surface it so they don't silently end up with
        // "no model loaded" later (e.g. when trying to stream).
        Log.instance.w('ui', 'Default model load failed: $_modelName',
            error: e, stack: st);
        if (mounted) {
          final l = AppLocalizations.of(context);
          // A specific named model is missing on disk — point Model
          // Management at it. The blanket "no models downloaded yet"
          // case is handled above before we even try to load.
          final isNotDownloaded = e.toString().contains('is not downloaded');
          if (isNotDownloaded) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.defaultModelNotDownloaded(_modelName)),
                duration: const Duration(seconds: 8),
                showCloseIcon: true,
                action: SnackBarAction(
                  label: l.openModels,
                  onPressed: () {
                    if (mounted) context.push('/models');
                  },
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.transcriptionLoadFailed(e.toString())),
                duration: const Duration(seconds: 6),
                showCloseIcon: true,
              ),
            );
          }
        }
      }
    }
    if (mounted) ref.read(transcriptionScreenProvider.notifier).setEngineReady(ok);
    return ok;
  }

  /// Unique backend ids present in the current model list, sorted for UI.
  List<String> _uniqueBackends() {
    final set = <String>{
      for (final m in _availableModels)
        if (m.backend.isNotEmpty) m.backend
    };
    final list = set.toList()..sort();
    return list;
  }

  /// Apply the live name / backend filters.
  List<ModelInfo> _filteredModels() {
    return _availableModels.where((m) {
      if (_backendFilter.isNotEmpty && m.backend != _backendFilter) {
        return false;
      }
      if (_modelNameFilter.isEmpty) return true;
      final hay = ('${m.displayName} ${m.name} ${m.backend} ${m.quantization}')
          .toLowerCase();
      return hay.contains(_modelNameFilter);
    }).toList();
  }

  Future<void> _loadModels() async {
    final ts = ref.read(transcriptionScreenProvider);
    if (ts.loadingModels) return;
    Log.instance.d('ui', 'Loading models for advanced options...');
    ref.read(transcriptionScreenProvider.notifier).setLoadingModels(true);
    try {
      List<ModelInfo> models;
      if (plat.isWeb) {
        // On web, get the cloud model list from the HfSpace engine.
        final engine = ref.read(transcriptionServiceProvider).currentEngine;
        if (engine != null) {
          final engineModels = await engine.getAvailableModels();
          models = engineModels
              .map((m) => ModelInfo(
                    name: m.id,
                    displayName: m.name,
                    backend: m.metadata['backend'] as String? ?? m.id,
                    isDownloaded: true, // always available server-side
                    sizeBytes: m.sizeBytes,
                    size: '${(m.sizeBytes / 1e6).round()} MB',
                    description: m.description,
                    modelType: ModelType.whisperCpp,
                  ))
              .toList();
        } else {
          models = [];
        }
      } else {
        models =
            await ref.read(modelServiceProvider).getWhisperCppModels();
      }
      Log.instance.d('ui', 'Fetched ${models.length} models');
      if (mounted) {
        final tn = ref.read(transcriptionScreenProvider.notifier);
        tn.setAvailableModels(models);
        tn.setLoadingModels(false);
      }
    } catch (e, st) {
      Log.instance.e('ui', 'Failed to load models', error: e, stack: st);
      if (mounted) {
        ref.read(transcriptionScreenProvider.notifier).setLoadingModels(false);
      }
    }
  }

  Future<void> _downloadModel(ModelInfo model) async {
    final modelService = ref.read(modelServiceProvider);
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcribeStarting(model.displayName))),
      );

      final success = await modelService.downloadWhisperCppModel(
        model.name,
        onProgress: (p) {
          // Optional: update UI with progress
        },
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.displayName} downloaded')),
        );
        _loadModels(); // Refresh list
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Download failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // §8.2 — watch the provider so all getter proxies below trigger rebuilds.
    ref.watch(transcriptionScreenProvider);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    Log.instance.t('ui', 'TranscriptionScreen.build locale=$locale');

    // Responsive AppBar — three-tier behaviour:
    //   wide   (≥600): full 2-line title + every action as an icon
    //   compact(<600): single-line title, drop the tagline
    //   phone  (<480): keep only Settings as a visible icon; move
    //                   History / Models / Synthesize / Translate /
    //                   Presets into a PopupMenuButton overflow.
    final compact = isCompactWidth(context);
    final phone = isPhoneWidth(context);
    return Scaffold(
      appBar: AppBar(
        title: compact
            ? Text(l.appName)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.appName),
                  Text(
                    l.appTagline,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
        actions: phone
            ? [
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: l.menuSettings,
                  onPressed: () => context.push('/settings'),
                ),
                PopupMenuButton<String>(
                  tooltip: l.menuOpenMore,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    switch (v) {
                      case 'history':
                        context.push('/history');
                        break;
                      case 'models':
                        context.push('/models');
                        break;
                      case 'synthesize':
                        context.push('/synthesize');
                        break;
                      case 'translate':
                        context.push('/translate');
                        break;
                      case 'presets':
                        _openPresetsDialog();
                        break;
                      case 'compare-models':
                        _showModelComparison();
                        break;
                      case 'subtitle-overlay':
                        context.push('/subtitle-overlay');
                        break;
                      case 'verify-watermark':
                        _verifyWatermark();
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'history',
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(l.menuHistory),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'models',
                      child: ListTile(
                        leading: const Icon(Icons.download),
                        title: Text(l.menuModels),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'synthesize',
                      child: ListTile(
                        leading: const Icon(Icons.record_voice_over),
                        title: Text(l.menuSynthesize),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'translate',
                      child: ListTile(
                        leading: const Icon(Icons.translate),
                        title: Text(l.menuTranslate),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'presets',
                      child: ListTile(
                        leading: const Icon(Icons.bookmarks_outlined),
                        title: Text(l.presetsTooltip),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'compare-models',
                      child: ListTile(
                        leading: const Icon(Icons.compare_arrows),
                        title: Text(l.menuCompareModels),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'subtitle-overlay',
                      child: ListTile(
                        leading: const Icon(Icons.subtitles),
                        title: Text(l.menuSubtitleOverlay),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'verify-watermark',
                      child: ListTile(
                        leading: Icon(Icons.verified_user),
                        title: Text('Verify Watermark'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: l.menuHistory,
                  onPressed: () => context.push('/history'),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: l.menuSettings,
                  onPressed: () => context.push('/settings'),
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: l.menuModels,
                  onPressed: () => context.push('/models'),
                ),
                IconButton(
                  icon: const Icon(Icons.record_voice_over),
                  tooltip: l.menuSynthesize,
                  onPressed: () => context.push('/synthesize'),
                ),
                IconButton(
                  icon: const Icon(Icons.translate),
                  tooltip: l.menuTranslate,
                  onPressed: () => context.push('/translate'),
                ),
                // §5.1.7 — Presets: save / load (backend,
                // modelId, language, AdvancedOptions) bundles.
                IconButton(
                  icon: const Icon(Icons.bookmarks_outlined),
                  tooltip: l.presetsTooltip,
                  onPressed: _openPresetsDialog,
                ),
                // §5.25.13 — Model A/B comparison.
                IconButton(
                  icon: const Icon(Icons.compare_arrows),
                  tooltip: l.menuCompareModels,
                  onPressed: _showModelComparison,
                ),
                // §5.25.3 — Subtitle overlay / teleprompter mode.
                IconButton(
                  icon: const Icon(Icons.subtitles),
                  tooltip: l.menuSubtitleOverlay,
                  onPressed: () => context.push('/subtitle-overlay'),
                ),
                IconButton(
                  icon: const Icon(Icons.verified_user),
                  tooltip: 'Verify Watermark',
                  onPressed: _verifyWatermark,
                ),
              ],
      ),
      body: DropTarget(
        onDragEntered: (_) => ref.read(transcriptionScreenProvider.notifier).setDropHover(true),
        onDragExited: (_) => ref.read(transcriptionScreenProvider.notifier).setDropHover(false),
        onDragDone: _onFilesDropped,
        child: Stack(
            children: [_buildBody(), if (_dropHover) _buildDropOverlay()]),
      ),
      bottomNavigationBar: phone
          ? const PhoneNavBar(current: PhoneNavDestination.transcribe)
          : null,
    );
  }

  /// Called when the OS hands us one or more files dropped on the window.
  /// Multi-drop: first file becomes the active selection; any additional
  /// supported files go into the batch queue.
  Future<void> _onFilesDropped(DropDoneDetails details) async {
    ref.read(transcriptionScreenProvider.notifier).setDropHover(false);
    if (details.files.isEmpty) return;
    // desktop_drop delivers the same drop to every nested DropTarget.
    // If the batch card already handled it, don't double-enqueue.
    if (ref.read(batchQueueProvider.notifier).recentlyConsumedDrop) return;

    final supported = details.files
        .where((f) => AudioUtils.isSupportedAudioFile(f.path))
        .toList();
    if (supported.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcribeUnsupportedFile(details.files.first.name))),
      );
      return;
    }

    // First: active single-select pick (for the inline transcribe button).
    ref.read(transcriptionScreenProvider.notifier).setSelectedFilePath(supported.first.path);
    ref.read(selectedAudioPathProvider.notifier).state = null;

    // Rest: enqueue for batch processing. Snapshot
    // backend/modelId/language at enqueue time so the drain loop
    // (and any restart-time resume path) knows which model the job
    // was intended to run against — §5.23 Q1 grouping + Q3 resume.
    final extras = supported.skip(1).toList();
    final q = ref.read(batchQueueProvider.notifier);
    final enqueueBackend = ModelCatalog
            .crispasrBackendModels[_modelName]
            ?.backend ??
        ModelCatalog.whisperCppModels[_modelName]?.backend ??
        'whisper';
    final enqueueLang = _language == 'auto' ? null : _language;
    int skippedDups = 0;
    for (final f in extras) {
      // §5.25.11 — Skip already-transcribed files in batch enqueue.
      final dup = await q.checkFingerprintDedup(f.path);
      if (dup != null) {
        skippedDups++;
        continue;
      }
      q.enqueue(f.path,
          backend: enqueueBackend, modelId: _modelName, language: enqueueLang);
    }
    if (skippedDups > 0) {
      Log.instance.i('batch', 'skipped $skippedDups duplicate(s) by fingerprint');
    }

    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(extras.isEmpty
            ? l.transcribeLoadedFile(supported.first.name)
            : '${l.transcribeLoadedFile(supported.first.name)} · ${l.batchEnqueueAdded(extras.length)}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Tinted overlay shown while a file is hovering over the window. The
  /// actual drop handling is on the outer DropTarget — this is purely
  /// visual feedback.
  Widget _buildDropOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Drop audio file to transcribe',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final appState = ref.watch(appStateProvider);
    final transcriptionService = ref.watch(transcriptionServiceProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Four tiers:
        //   - phone (<600)        : TabBar (Input / Run / Output).
        //     One pane at a time, full viewport each. Phone-native.
        //   - narrow (600..699)   : single stacked column, all panes
        //     scroll. Suited to small tablets and tight desktop windows.
        //   - wide   (700..1299)  : 2-column input|output.
        //   - extra-wide (≥1300)  : 3-column input | queue+controls | output.
        //     Batch queue gets its own middle column so the left stays
        //     compact and the output pane is unaffected.
        final w = constraints.maxWidth;
        final input = _buildInputSection();
        final controls = _buildControlsSection(appState, transcriptionService);
        final output = _buildOutputSection(appState);

        if (w >= 1300) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 380,
                child: SingleChildScrollView(child: input),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 340,
                child: controls,
              ),
              const VerticalDivider(width: 1),
              Expanded(child: output),
            ],
          );
        }
        if (w >= 700) {
          // Compute a sensible left-column width proportional to the
          // viewport so controls don't cram when the window is ~700px.
          final leftWidth = (w * 0.40).clamp(360.0, 520.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: leftWidth,
                child: Column(
                  children: [
                    Expanded(child: SingleChildScrollView(child: input)),
                    controls,
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: output),
            ],
          );
        }
        if (w >= Breakpoints.compact) {
          // Narrow (600..699): stack vertically. Output is most
          // important → flex 3.
          return Column(
            children: [
              Expanded(
                flex: 2,
                child: SingleChildScrollView(child: input),
              ),
              controls,
              Expanded(flex: 3, child: output),
            ],
          );
        }
        // Phone (<600): one pane at a time via TabBar. Default-
        // open the tab that matches the user's current intent —
        // Output when there are segments to read, Input
        // otherwise. The DefaultTabController only reads
        // initialIndex once; subsequent rebuilds don't yank the
        // user off whichever tab they switched to.
        final hasSegments = appState.segments.isNotEmpty;
        return NarrowTabbedBody(
          input: input,
          controls: controls,
          output: output,
          initialIndex: hasSegments ? 2 : 0,
        );
      },
    );
  }

  Widget _buildInputSection() {
    final l = AppLocalizations.of(context);
    final recordedPath = ref.watch(selectedAudioPathProvider);
    final displayPath = _selectedFilePath ?? recordedPath;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  l.audioInput,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                _EngineStatusChip(ready: _engineReady),
              ],
            ),
            const SizedBox(height: 16),

            // File Selection
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      displayPath != null
                          ? p.basename(displayPath)
                          : l.noFileSelected,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(l.browse),
                  onPressed: _selectAudioFile,
                ),
                // §5.1.5 — Open the audio editor (waveform +
                // trim / cut / split) for the currently-loaded
                // file. Hidden when no file is loaded so the
                // affordance only shows up when it's actionable.
                if (displayPath != null && displayPath.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: l.editAudioOpen,
                    icon: const Icon(Icons.graphic_eq),
                    onPressed: () {
                      context.push(
                        '/edit-audio?path=${Uri.encodeQueryComponent(displayPath)}',
                      );
                    },
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),

            // URL Input
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: l.urlInputLabel,
                hintText: l.urlInputHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
              ),
            ),

            const SizedBox(height: 16),

            // Audio Recorder
            const AudioRecorderWidget(),

            const SizedBox(height: 16),

            // Advanced Options Toggle
            TextButton.icon(
              icon: Icon(
                  _showAdvancedOptions ? Icons.expand_less : Icons.expand_more),
              label: Text(l.advancedOptions),
              onPressed: () {
                final next = !ref.read(transcriptionScreenProvider).showAdvancedOptions;
                ref.read(transcriptionScreenProvider.notifier).setShowAdvancedOptions(next);
                if (next) _loadModels();
              },
            ),

            if (_showAdvancedOptions) ...[
              const SizedBox(height: 16),
              _buildAdvancedOptions(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedOptions() {
    Log.instance.d('ui',
        '_buildAdvancedOptions: _loadingModels=$_loadingModels, _availableModels.length=${_availableModels.length}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Speaker Diarization
        DiarizationSettingsWidget(
          enabled: ref.watch(transcriptionScreenProvider).enableDiarization,
          onChanged: (enabled) {
            ref.read(transcriptionScreenProvider.notifier).setEnableDiarization(enabled);
          },
        ),

        const SizedBox(height: 16),

        // Language Selection. Dynamically populated from the active
        // model's `languages` field — Canary 25 EU langs, Voxtral 9,
        // Cohere 14, Whisper / Qwen3-ASR's ~30, etc. — instead of the
        // legacy hardcoded 9. Reason: forcing LID via "auto" on Android
        // tanks RTF from ~4.5× to 0.3× per #14 — users transcribing
        // known-language audio need a way to pick the source language
        // without a slow LID pass first.
        //
        // Uses Autocomplete instead of a plain dropdown so a Whisper
        // user (60 options) can type "swed" → Swedish, "中" → 中文 /
        // Chinese, "deu" → Deutsch — without scrolling. The list also
        // shows up unfiltered when the user just focuses the field
        // (empty-text branch in optionsBuilder), so small per-model
        // lists (Granite 5, Sensevoice 4) still work like a regular
        // picker.
        Builder(
          builder: (context) {
            final l = AppLocalizations.of(context);
            final svc = ref.read(modelServiceProvider);
            final def =
                _modelName.isEmpty ? null : svc.lookupDefinition(_modelName);
            final codes = _languageCodesFor(def);
            // If the user previously picked a code the new model
            // doesn't advertise, drop back to auto so they don't
            // silently transcribe with a mismatched language.
            if (_language != 'auto' && !codes.contains(_language)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) ref.read(transcriptionScreenProvider.notifier).setLanguage('auto');
              });
            }
            final options = <_LangOption>[
              _LangOption(code: 'auto', displayName: l.languageAuto),
              for (final code in codes)
                _LangOption(code: code, displayName: _languageDisplayName(code)),
            ];
            return Row(
              children: [
                Text('${l.transcribeLanguageLabel}: '),
                const SizedBox(width: 8),
                Expanded(
                  child: Autocomplete<_LangOption>(
                    // Reset the field when the model changes —
                    // Autocomplete latches its controller's text on
                    // first build, so without a key the picked
                    // display name from a previous model would stick
                    // even after the dropdown swapped to the new
                    // codes list.
                    key: ValueKey('lang-picker-$_modelName-$_language'),
                    initialValue: TextEditingValue(
                      text: options
                          .firstWhere(
                            (o) => o.code == _language,
                            orElse: () => options.first,
                          )
                          .displayName,
                    ),
                    displayStringForOption: (o) => o.displayName,
                    optionsBuilder: (textValue) {
                      final q = textValue.text.trim().toLowerCase();
                      if (q.isEmpty) return options;
                      return options
                          .where((o) => o.matches(q))
                          .toList(growable: false);
                    },
                    onSelected: (o) => ref.read(transcriptionScreenProvider.notifier).setLanguage(o.code),
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmit) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        onSubmitted: (_) => onSubmit(),
                        onTap: () {
                          // Re-open the dropdown on tap even when the
                          // field already has focus + content — without
                          // this Autocomplete only re-shows options
                          // after a text edit, which is surprising
                          // when the user just wants to switch picks.
                          if (controller.text.isNotEmpty) {
                            controller.selection = TextSelection(
                              baseOffset: 0,
                              extentOffset: controller.text.length,
                            );
                          }
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, list) {
                      // Capped to ~10 visible rows so a 60-item list
                      // doesn't swallow the screen; scroll inside.
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 320,
                              maxWidth: 480,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final option = list.elementAt(i);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    child: Text(
                                      option.displayName,
                                      style:
                                          Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 8),

        // Model Selection — collapsed by default so the long picker
        // list doesn't dominate the left panel. Title surfaces the
        // currently-selected model so the user knows what's active
        // without expanding. Tap to open the filter + list.
        _buildModelSection(),

        const SizedBox(height: 16),

        // §5.25.5 — Tag segment languages after transcription.
        SwitchListTile(
          title: Text(AppLocalizations.of(context).advancedTagSegmentLanguages),
          subtitle: Text(AppLocalizations.of(context).advancedTagSegmentLanguagesSubtitle),
          value: ref.watch(transcriptionScreenProvider).tagSegmentLanguages,
          onChanged: (v) => ref.read(transcriptionScreenProvider.notifier).setTagSegmentLanguages(v),
          dense: true,
        ),

        const SizedBox(height: 8),

        // Advanced decoding knobs (translate / beam / initial prompt).
        const AdvancedDecodingSection(),
      ],
    );
  }

  /// Collapsible model picker — search field, backend dropdown, and
  /// the candidate list. The ExpansionTile header shows the active
  /// `_modelName` so the user knows what's selected at a glance
  /// without expanding.
  Widget _buildModelSection() {
    final l = AppLocalizations.of(context);
    final selected = _availableModels
        .where((m) => m.name == _modelName)
        .cast<ModelInfo?>()
        .firstWhere((_) => true, orElse: () => null);
    final headerSubtitle = selected == null
        ? (_modelName.isEmpty ? '—' : _modelName)
        : '${selected.displayName} • ${selected.size} • ${selected.backend} • '
            '${selected.quantization.isEmpty ? "f16" : selected.quantization}';
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        // Start expanded when no model is loaded so new users discover
        // the picker immediately (issue #27).
        initiallyExpanded: _modelName.isEmpty,
        // Tighten the default padding so it lines up with the other
        // sections in the panel.
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(l.model,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          headerSubtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          // Filter row — name search + backend dropdown.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _modelFilterController,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: l.modelFilterHint,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    suffixIcon: _modelNameFilter.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _modelFilterController.clear();
                              ref.read(transcriptionScreenProvider.notifier).setModelNameFilter('');
                            },
                          ),
                  ),
                  onChanged: (v) =>
                      ref.read(transcriptionScreenProvider.notifier).setModelNameFilter(v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _backendFilter,
                items: [
                  DropdownMenuItem(
                      value: '', child: Text(l.modelAnyBackend)),
                  for (final b in _uniqueBackends())
                    DropdownMenuItem(value: b, child: Text(b)),
                ],
                onChanged: (v) => ref.read(transcriptionScreenProvider.notifier).setBackendFilter(v ?? ''),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingModels && _availableModels.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_availableModels.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(l.transcriptionNoModelsFound),
                  TextButton.icon(
                    onPressed: () {
                      Log.instance.d('ui', 'Retry tapped in advanced options');
                      _loadModels();
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(l.transcriptionRetry),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Builder(
                builder: (context) {
                  final filtered = _filteredModels();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No models match this filter.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    );
                  }
                  // §5.4 — when a backend filter is active and nothing
                  // for it is on disk, surface a one-tap "download the
                  // recommended default" row at the top (CrispASR's
                  // `-m auto`). Reuses the existing download-prompt flow.
                  ModelInfo? recommended;
                  if (_backendFilter.isNotEmpty &&
                      !filtered.any((m) => m.isDownloaded)) {
                    for (final m in filtered) {
                      if (m.recommendedDefault) {
                        recommended = m;
                        break;
                      }
                    }
                  }
                  final bannerCount = recommended != null ? 1 : 0;
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length + bannerCount,
                    itemBuilder: (context, index) {
                      if (recommended != null && index == 0) {
                        return _buildRecommendedBanner(recommended);
                      }
                      final model = filtered[index - bannerCount];
                      final isSelected = _modelName == model.name;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                model.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (model.recommendedDefault) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.star,
                                  size: 14, color: Colors.green.shade600),
                            ],
                          ],
                        ),
                        subtitle: Text(
                            '${model.size} • ${model.backend} • ${model.quantization.isEmpty ? "f16" : model.quantization}'),
                        trailing: _buildModelAction(model),
                        onTap: () => _selectModelWithDownloadPrompt(model),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// §5.4 — top-of-list prompt to fetch a backend's recommended default
  /// when nothing for it is downloaded yet. Tapping reuses the standard
  /// download-confirm flow (whose companion co-download makes it a
  /// complete, runnable setup).
  Widget _buildRecommendedBanner(ModelInfo model) {
    final l = AppLocalizations.of(context);
    return Container(
      color: Colors.green.shade50,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.recommend, color: Colors.green.shade700),
        title: Text(l.transcribeNoBackendModelHint(_backendFilter)),
        subtitle:
            Text(l.transcribeDownloadRecommended(model.displayName, model.size)),
        trailing: const Icon(Icons.download, size: 20),
        onTap: () => _selectModelWithDownloadPrompt(model),
      ),
    );
  }

  Widget _buildModelAction(ModelInfo model) {
    if (model.isDownloaded) {
      return _modelName == model.name
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.check, color: Colors.grey);
    }
    return IconButton(
      icon: const Icon(Icons.download, size: 20),
      onPressed: () => _downloadModel(model),
      tooltip: AppLocalizations.of(context).tooltipDownloadModel,
    );
  }

  /// Codes the language dropdown should offer for [def]. Thin wrapper
  /// over [ModelCatalog.resolveLanguageCodes] — the shared helper
  /// handles the def.languages → BackendRepo.defaultLanguages → `[*]`
  /// expansion chain so the catalogue-invariant tests can exercise
  /// the same code path. Local concern is only the fallback when
  /// nothing resolves (UI-side: 9-code historical default).
  List<String> _languageCodesFor(ModelDefinition? def) {
    final resolved = ModelCatalog.resolveLanguageCodes(
      def,
      expandAll: () => AppConstants.supportedLanguages.keys
          .where((c) => c != 'auto')
          .toList(),
    );
    if (resolved.isNotEmpty) return resolved;
    return const ['en', 'es', 'fr', 'de', 'it', 'pt', 'zh', 'ja', 'ko'];
  }

  /// Human-readable name for a language code. ARB localisation only
  /// covers ~10 codes and doesn't scale to the 99 Whisper supports
  /// (would need 99 × N-locales entries to maintain in lockstep), so
  /// we ship a single English language-name map plus the native name
  /// — the ISO code itself is the stable identifier and the native
  /// label ("Deutsch", "Español", "中文") is recognisable to every
  /// user regardless of UI locale. Falls back to "{name} ({code})"
  /// when no native form is known, and finally to the uppercase code
  /// so the dropdown never shows an empty row.
  /// Compact byte-size label for the "Loading {model} ({size})…"
  /// transcribe-button label. Returns "" for unknown / zero so the
  /// caller can omit the parenthetical entirely instead of showing
  /// "(0 B)".
  String _formatLoadingSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(0)} MB';
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _languageDisplayName(String code) {
    final native = _nativeLanguageName[code];
    final english = AppConstants.supportedLanguages[code];
    if (native != null && english != null) return '$native — $english';
    if (english != null) return '$english ($code)';
    return code.toUpperCase();
  }

  /// Native (endonym) names for the most common ISO 639-1 codes we
  /// surface. Used by the language picker to render labels that read
  /// well regardless of UI locale. Codes missing here fall back to
  /// the English name from [AppConstants.supportedLanguages].
  static const _nativeLanguageName = <String, String>{
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Português',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'ru': 'Русский',
    'uk': 'Українська',
    'cs': 'Čeština',
    'da': 'Dansk',
    'sv': 'Svenska',
    'no': 'Norsk',
    'fi': 'Suomi',
    'el': 'Ελληνικά',
    'bg': 'Български',
    'ro': 'Română',
    'sk': 'Slovenčina',
    'sl': 'Slovenščina',
    'lt': 'Lietuvių',
    'lv': 'Latviešu',
    'et': 'Eesti',
    'hr': 'Hrvatski',
    'hu': 'Magyar',
    'mt': 'Malti',
    'tr': 'Türkçe',
    'ar': 'العربية',
    'he': 'עברית',
    'fa': 'فارسی',
    'hi': 'हिन्दी',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
    'id': 'Bahasa Indonesia',
    'ms': 'Bahasa Melayu',
    'tl': 'Tagalog',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
    'sw': 'Kiswahili',
    'ha': 'Hausa',
    'mk': 'Македонски',
    'sr': 'Српски',
    'ca': 'Català',
    'eu': 'Euskara',
    'gl': 'Galego',
    'is': 'Íslenska',
    'cy': 'Cymraeg',
    'ga': 'Gaeilge',
  };

  Future<void> _selectModel(String value) async {
    if (value == ref.read(transcriptionScreenProvider).modelName) return;
    ref.read(transcriptionScreenProvider.notifier).setModelName(value);

    // Save to settings
    ref.read(settingsServiceProvider).defaultModel = value;

    try {
      await ref.read(transcriptionServiceProvider).loadModel(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context).transcribeLoadedFile(value))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)
                  .transcriptionLoadFailed(e.toString()))),
        );
      }
    }
  }

  // ----- §5.1.7 Presets -----

  /// Open the preset picker. Returns the chosen preset (or
  /// Pick an audio file and check it for the CrisperWeaver AI watermark.
  /// Shows a dialog with the result.
  /// Detect whether a WAV file contains a COSE-signed C2PA manifest
  /// (JUMBF structure) as opposed to the unsigned JSON-LD fallback.
  /// The native c2pa-audio signer embeds a JUMBF superbox in a RIFF
  /// `c2pa` chunk; the first 4 bytes of the payload are a big-endian
  /// box length, followed by 'jumb'. The unsigned fallback starts with
  /// '{' (JSON). Full signature verification is blocked on a C ABI
  /// function not yet exposed; this is a structural detection only.
  static bool _hasSignedC2pa(Uint8List wavBytes) {
    if (wavBytes.length < 44) return false;
    var offset = 12;
    while (offset + 8 <= wavBytes.length) {
      final id = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final bd = ByteData.view(wavBytes.buffer);
      final size = bd.getUint32(offset + 4, Endian.little);
      if (id == 'c2pa' && size > 8) {
        // Check if payload starts with JUMBF box (not '{' JSON).
        final payloadStart = offset + 8;
        if (payloadStart + 8 <= wavBytes.length) {
          // JUMBF: big-endian box length + 'jumb' type
          final boxType = String.fromCharCodes(
              wavBytes.sublist(payloadStart + 4, payloadStart + 8));
          if (boxType == 'jumb') return true;
          // Also check for the C2PA manifest store UUID box
          if (wavBytes[payloadStart] != 0x7B /* '{' */) return true;
        }
      }
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    return false;
  }

  Future<void> _verifyWatermark() async {
    try {
      final pick = await pickFilesRobust(
        type: plat.isWeb ? FileType.any : FileType.audio,
        allowedExtensions: const ['wav'],
      );
      if (pick.isEmpty || !mounted) return;

      final filePath = pick.localPaths.isNotEmpty ? pick.localPaths.first : null;
      final displayName = filePath != null
          ? p.basename(filePath)
          : (pick.fileNames?.firstOrNull ?? 'Selected audio');
      final bytes = filePath != null
          ? await File(filePath).readAsBytes()
          : pick.fileBytes!.first;
      final info = AudioWatermarkService.detectWatermark(bytes);

      // Run spread-spectrum watermark detection + heuristic AI detection.
      double? ssScore;
      AiDetectionResult? heuristic;
      if (filePath != null) {
        try {
          final audio = await ref.read(audioServiceProvider).loadAudioFile(
              File(filePath));
          ssScore = SpreadSpectrumWatermark.detect(audio.samples);
          heuristic = AudioWatermarkService.detectAiAudio(audio.samples,
              sampleRate: audio.sampleRate);
        } catch (_) {/* non-WAV or decode failure — skip */}
      }

      // Check for C2PA provenance manifest.
      final c2pa = ContentProvenanceService.extractFromWav(bytes);

      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            info != null ? Icons.verified : Icons.help_outline,
            color: info != null
                ? Colors.green
                : (heuristic != null && heuristic.score > 0.7
                    ? Colors.orange
                    : Colors.grey),
            size: 48,
          ),
          title: Text(info != null
              ? 'Watermark Detected'
              : (heuristic != null && heuristic.score > 0.7
                  ? 'Possibly AI-Generated'
                  : 'No AI Markers Found')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CrisperWeaver watermark result
              Row(
                children: [
                  Icon(info != null ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: info != null ? Colors.green : Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(info != null
                        ? 'CrisperWeaver watermark: ${info.synthetic ? "synthetic" : "not synthetic"}, '
                            '${info.timestamp.toLocal()}'
                        : 'No CrisperWeaver watermark'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Spread-spectrum watermark (CrispASR/CrispTTS cross-compat)
              if (ssScore != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(ssScore > 0.65 ? Icons.check_circle : Icons.cancel,
                        size: 16,
                        color: ssScore > 0.65 ? Colors.green : Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(ssScore > 0.65
                          ? 'Spread-spectrum watermark: ${(ssScore * 100).toStringAsFixed(0)}% confidence'
                          : 'No spread-spectrum watermark (${(ssScore * 100).toStringAsFixed(0)}%)'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              // C2PA manifest result — distinguish signed (COSE/JUMBF)
              // from unsigned (JSON-LD fallback). Full COSE signature
              // verification requires a C ABI function not yet exposed;
              // for now we detect the manifest type by checking whether
              // the RIFF chunk contains JUMBF structure (starts with a
              // box-length header) or plain JSON (starts with '{').
              Row(
                children: [
                  Icon(c2pa != null ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: c2pa != null ? Colors.green : Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(c2pa != null
                        ? 'C2PA manifest: ${c2pa['claim_generator'] ?? 'present'}'
                            ' (unsigned JSON-LD)'
                        : _hasSignedC2pa(bytes)
                            ? 'C2PA manifest: COSE-signed (cryptographic)'
                            : 'No C2PA manifest'),
                  ),
                ],
              ),
              // Heuristic AI detection result
              if (heuristic != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      heuristic.score > 0.7
                          ? Icons.warning_amber
                          : Icons.check_circle,
                      size: 16,
                      color: heuristic.score > 0.7
                          ? Colors.orange
                          : Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Heuristic: ${(heuristic.score * 100).toStringAsFixed(0)}% AI likelihood'
                        '${heuristic.reason.isNotEmpty ? " (${heuristic.reason})" : ""}',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                displayName,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Watermark check failed: $e')),
      );
    }
  }

  /// null if the user dismissed). When non-null, the screen
  /// applies it via `_applyPreset`.
  Future<void> _openPresetsDialog() async {
    final chosen = await showDialog<Preset>(
      context: context,
      builder: (_) => PresetsDialog(
        currentBackend: _activeBackendName(),
        currentModelId: _modelName,
        currentLanguage: _language,
      ),
    );
    if (chosen != null) await _applyPreset(chosen);
  }

  /// Resolve the active backend label — derive from the
  /// currently-selected model when there's a backend column
  /// in the catalog, else use the engine type id as a best-
  /// effort fallback.
  String _activeBackendName() {
    return ModelCatalog.crispasrBackendModels[_modelName]?.backend ??
        ModelCatalog.whisperCppModels[_modelName]?.backend ??
        ref.read(settingsServiceProvider).preferredEngine.id;
  }

  /// Apply a saved preset: update model / language / advanced
  /// options atomically, persist the new defaults, snackbar
  /// the user. Engine type isn't mutated here because the
  /// backend is implied by the chosen model — `_selectModel`
  /// reloads it under the hood.
  Future<void> _applyPreset(Preset p) async {
    final l = AppLocalizations.of(context);
    // 1. Advanced options first — cheap, no I/O.
    ref.read(advancedOptionsProvider.notifier).state = p.options;
    // 2. Language.
    final ts = ref.read(transcriptionScreenProvider);
    if (p.language.isNotEmpty && p.language != ts.language) {
      ref.read(transcriptionScreenProvider.notifier).setLanguage(p.language);
      ref.read(settingsServiceProvider).defaultLanguage = p.language;
    }
    // 3. Model — triggers a reload via the existing
    //    `_selectModel` path. Skip when empty or same.
    if (p.modelId.isNotEmpty && p.modelId != ts.modelName) {
      await _selectModel(p.modelId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.presetsApplied(p.name)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildControlsSection(
      AppState appState, TranscriptionService transcriptionService) {
    final l = AppLocalizations.of(context);
    final queue = ref.watch(batchQueueProvider);
    final hasQueued = queue.any((j) => j.status == BatchJobStatus.queued);
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const BatchQueueCard(),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 16,
            runSpacing: 16,
            children: [
              // Transcribe Button. Three states from #13 reporter
              // feedback:
              //   * `_transcribePending && !appState.isTranscribing` →
              //     model is loading (10 s on Android), label
              //     "Loading <model>…" so the user knows what's happening
              //     and doesn't think the spinner is the transcription
              //     itself.
              //   * `appState.isTranscribing` → actual transcribe in
              //     flight, label "Transcribing…".
              //   * idle → "Transcribe".
              Builder(builder: (context) {
                final loading =
                    _transcribePending && !appState.isTranscribing;
                final busy = appState.isTranscribing || _transcribePending;
                // Look up the model display name + size during the
                // load phase so the user sees `Loading <model> (140 MB)…`
                // instead of the generic spinner. l10n via the
                // transcribeLoadingButton ARB key (placeholder = the
                // composed "name (size)" string); falls back to
                // transcribeLoadingFallback when the active model
                // hasn't been resolved yet.
                String loadingLabel() {
                  final svc = ref.read(modelServiceProvider);
                  final def = svc.lookupDefinition(_modelName);
                  if (def == null) return l.transcribeLoadingFallback;
                  final size = _formatLoadingSize(def.sizeBytes);
                  final composed = size.isEmpty
                      ? def.displayName
                      : '${def.displayName} ($size)';
                  return l.transcribeLoadingButton(composed);
                }

                return ElevatedButton.icon(
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.transcribe),
                  label: Text(loading
                      ? loadingLabel()
                      : busy
                          ? l.transcribing
                          : l.transcribe),
                  onPressed: busy ? null : _startTranscription,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                );
              }),

              // Transcribe all — visible only when the queue has queued items.
              if (hasQueued && !appState.isTranscribing)
                ElevatedButton.icon(
                  icon: const Icon(Icons.playlist_play),
                  label: Text(l.batchRunAll),
                  onPressed: _startBatchRun,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                  ),
                ),

              // Stop Button
              if (appState.isTranscribing)
                ElevatedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: Text(l.stop),
                  onPressed: _stopTranscription,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                ),

              // Clear Button — also disabled during the load + transcribe
              // window so the user can't wipe a transcript that's about
              // to land. Reporter on #13 v2 noted the clear button
              // stayed live while transcribe was busy.
              ElevatedButton.icon(
                icon: const Icon(Icons.clear),
                label: Text(l.clear),
                onPressed: (appState.isTranscribing ||
                        _transcribePending ||
                        appState.segments.isEmpty)
                    ? null
                    : _clearTranscription,
              ),

              // Save/Share Button
              if (appState.currentTranscription != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.share),
                  onSelected: (action) => _handleShareAction(action, appState),
                  itemBuilder: (context) {
                    final l = AppLocalizations.of(context);
                    return [
                      PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: const Icon(Icons.share),
                          title: Text(l.transcriptionSharePlainText),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy',
                        child: ListTile(
                          leading: const Icon(Icons.copy),
                          title: Text(l.transcriptionCopyToClipboard),
                          dense: true,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'save_txt',
                        child: ListTile(
                          leading: const Icon(Icons.description),
                          title: Text(l.transcriptionSaveAsTxt),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_srt',
                        child: ListTile(
                          leading: const Icon(Icons.subtitles),
                          title: Text(l.transcriptionSaveAsSrt),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_vtt',
                        child: ListTile(
                          leading: const Icon(Icons.closed_caption),
                          title: Text(l.transcriptionSaveAsVtt),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_json',
                        child: ListTile(
                          leading: const Icon(Icons.data_object),
                          title: Text(l.transcriptionSaveAsJson),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_csv',
                        child: ListTile(
                          leading: const Icon(Icons.table_chart),
                          title: Text(l.transcriptionSaveAsCsv),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_lrc',
                        child: ListTile(
                          leading: const Icon(Icons.lyrics),
                          title: Text(l.transcriptionSaveAsLrc),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_md',
                        child: ListTile(
                          leading: const Icon(Icons.code, size: 20),
                          title: Text(l.transcriptionSaveAsMarkdown),
                          dense: true,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'share_bundle',
                        child: ListTile(
                          leading: const Icon(Icons.attach_file, size: 20),
                          title: Text(l.transcriptionShareAudioAndTranscript),
                          subtitle: Text(
                              l.transcriptionShareAudioAndTranscriptHelp,
                              style: const TextStyle(fontSize: 10)),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_wts',
                        child: ListTile(
                          leading: const Icon(Icons.timer_outlined),
                          title: Text(l.transcriptionSaveAsWts),
                          dense: true,
                        ),
                      ),
                      const PopupMenuDivider(),
                      // §5.25.14 — Note-taking tool exports
                      PopupMenuItem(
                        value: 'save_obsidian',
                        child: ListTile(
                          leading: const Icon(Icons.notes, size: 20),
                          title: Text(l.exportObsidian),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_notion',
                        child: ListTile(
                          leading: const Icon(Icons.dashboard, size: 20),
                          title: Text(l.exportNotion),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_logseq',
                        child: ListTile(
                          leading: const Icon(Icons.account_tree, size: 20),
                          title: Text(l.exportLogseq),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_chapters',
                        child: ListTile(
                          leading: const Icon(Icons.bookmark_outline, size: 20),
                          title: Text(l.exportYouTubeChapters),
                          dense: true,
                        ),
                      ),
                      // §5.25.6 — Auto-detected chapters via topic shifts.
                      PopupMenuItem(
                        value: 'save_chapters_detected',
                        child: ListTile(
                          leading: const Icon(Icons.auto_stories, size: 20),
                          title: Text(l.exportDetectChapters),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_podcast_chapters',
                        child: ListTile(
                          leading: const Icon(Icons.podcasts, size: 20),
                          title: Text(l.exportPodcastChapters),
                          dense: true,
                        ),
                      ),
                    ];
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutputSection(AppState appState) {
    final l = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  l.transcriptionOutput,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (appState.isTranscribing)
                  Text(
                    '${(appState.progress * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),

          // Progress Bar. During the model-load phase we don't know
          // the actual progress yet (the FFI ctor is opaque), so show
          // an indeterminate bar + the model name. Once the worker
          // pool / model finishes loading, appState.startTranscription
          // fires and we switch to the determinate bar.
          if (_transcribePending && !appState.isTranscribing)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  Builder(builder: (context) {
                    final l = AppLocalizations.of(context);
                    final svc = ref.read(modelServiceProvider);
                    final def = svc.lookupDefinition(_modelName);
                    final size = def == null
                        ? ''
                        : _formatLoadingSize(def.sizeBytes);
                    final name = def?.displayName ?? _modelName;
                    final composed = size.isEmpty ? name : '$name ($size)';
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.transcribeLoadingDetail(composed),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        // The load can't be interrupted (FFI ctor), but
                        // Cancel gives the UI back immediately; the model
                        // finishes loading in the background and a later
                        // Transcribe click runs against it.
                        TextButton(
                          onPressed: ref.watch(transcriptionScreenProvider).loadCancelled
                              ? null
                              : () {
                                  ref.read(transcriptionScreenProvider.notifier).setLoadCancelled(true);
                                  Log.instance.i('ui',
                                      'User cancelled during model load',
                                      fields: {'model': _modelName});
                                },
                          child: Text(AppLocalizations.of(context).cancel),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          if (appState.isTranscribing)
            LinearProgressIndicator(value: appState.progress),

          // Performance readout (once a run has completed)
          if (!appState.isTranscribing && appState.performance != null)
            _PerformanceCard(stats: appState.performance!),

          // Error Message
          if (appState.errorMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                appState.errorMessage!,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),

          // Transcription Output
          Expanded(
            child: TranscriptionOutputWidget(
              segments: appState.segments,
              currentTranscription: appState.currentTranscription,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAudioFile() async {
    // FileType.audio on iOS routes through MPMediaPickerController
    // (Apple Music library) — wrong picker for our case (we want
    // recorded files in Files / iCloud Drive, not music tracks) AND
    // it requires NSAppleMusicUsageDescription. Use FileType.custom
    // with explicit extensions so iOS picks the document picker on
    // every platform.
    //
    // Formats our FFI decoder (CrispASR's miniaudio backend) handles:
    // wav / mp3 / flac / ogg / opus / webm / m4a. CrispASR decodes
    // all of these natively via miniaudio (opus & webm were added in
    // CrispASR 0.6). m4a/aac decode requires the miniaudio AAC backend
    // which is available on all platforms CrispASR builds for.
    //
    // pickFilesRobust handles the Android Unknown_path / cloud-URI
    // case by retrying with withReadStream:true and staging the
    // bytes to a local temp file we own — see lib/utils/file_picker_util.dart.
    RobustFilePick pick;
    try {
      pick = await pickFilesRobust(
        // On web, FileType.audio maps to accept="audio/*" which Safari
        // silently ignores (picker never opens or returns empty). Use
        // FileType.any on web and rely on the extension post-filter.
        type: plat.isWeb ? FileType.any : FileType.audio,
        allowedExtensions: const ['wav', 'mp3', 'flac', 'ogg', 'opus', 'webm', 'm4a', 'aac', 'amr'],
        allowMultiple: true,
      );
    } on FilePickerCloudUriUnsupported catch (e, st) {
      Log.instance.w('ui', 'cloud-URI pick failed even with fallback',
          error: e, stack: st);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.filePickerCloudFileUnsupported)),
        );
      }
      return;
    } catch (e, st) {
      Log.instance.e('ui', 'File picker threw', error: e, stack: st);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.filePickerFailed(e.toString()))),
        );
      }
      return;
    }

    if (pick.isNotEmpty) {
      // Web: store bytes directly; native: store filesystem path.
      if (pick.hasBytesOnly) {
        final tn = ref.read(transcriptionScreenProvider.notifier);
        tn.setSelectedFileBytes(pick.fileBytes!.first);
        tn.setSelectedFileName(pick.fileNames!.first);
        tn.setSelectedFilePath(pick.fileNames!.first); // display name
        ref.read(selectedAudioPathProvider.notifier).state = null;
        return;
      }
      final paths = pick.localPaths;
      final tn = ref.read(transcriptionScreenProvider.notifier);
      tn.setSelectedFilePath(paths.first);
      tn.setSelectedFileBytes(null);
      tn.setSelectedFileName(null);
      ref.read(selectedAudioPathProvider.notifier).state = null;
      if (paths.length > 1) {
        final q = ref.read(batchQueueProvider.notifier);
        // Snapshot backend/modelId/language for the batched files so
        // a crash-recovered job knows which model to reload — §5.23.
        final enqueueBackend = ModelCatalog
                .crispasrBackendModels[_modelName]
                ?.backend ??
            ModelCatalog.whisperCppModels[_modelName]?.backend ??
            'whisper';
        final enqueueLang = _language == 'auto' ? null : _language;
        int enqueued = 0;
        for (final p in paths.skip(1)) {
          // §5.25.11 — Skip already-transcribed files.
          final dup = await q.checkFingerprintDedup(p);
          if (dup != null) continue;
          q.enqueue(p,
              backend: enqueueBackend,
              modelId: _modelName,
              language: enqueueLang);
          enqueued++;
        }
        if (mounted && enqueued > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context)
                    .batchEnqueueAdded(enqueued))),
          );
        }
      }
    }
  }

  Future<void> _startTranscription() async {
    final transcriptionService = ref.read(transcriptionServiceProvider);
    final appStateNotifier = ref.read(appStateProvider.notifier);
    final recordedPath = ref.read(selectedAudioPathProvider);
    final filePath = _selectedFilePath ?? recordedPath;

    final hasWebBytes = _selectedFileBytes != null && plat.isWeb;
    if (filePath == null && !hasWebBytes && _urlController.text.isEmpty) {
      _showErrorDialog(AppLocalizations.of(context).transcribeNoSource);
      return;
    }

    // Reflect the "queued / loading / transcribing" state on the
    // button from click time, not from the post-load
    // appStateNotifier.startTranscription() call below. On Android the
    // model-load + worker-pool spawn before that call can take ~10 s;
    // without the local flag the button stayed enabled the whole time
    // and the user (issue #13) clicked again, scheduling a second
    // parallel transcription. A local flag (rather than calling
    // appState.startTranscription() up here) preserves the previous
    // run's segments / historyEntryId until the real start, so an
    // early-return between here and the actual transcribe doesn't
    // wipe what the user was looking at.
    ref.read(transcriptionScreenProvider.notifier).startTranscription();

    if (!ref.read(transcriptionScreenProvider).engineReady) {
      await _ensureEngineReady();
    }

    // Refresh the model list so we pick up anything the user downloaded
    // from Model Management since this screen first opened. Without this
    // the selected model can stay "base" even after they download "tiny".
    await _loadModels();
    final ts = ref.read(transcriptionScreenProvider);
    final downloaded = ts.availableModels
        .where((m) => m.isDownloaded)
        .toList(growable: false);
    if (ts.modelName.isNotEmpty &&
        !downloaded.any((m) => m.name == ts.modelName) &&
        downloaded.isNotEmpty) {
      final whisperFirst = downloaded.firstWhere(
          (m) => m.backend == 'whisper',
          orElse: () => downloaded.first);
      final switched = whisperFirst.name;
      Log.instance.i('ui',
          'Auto-switching selected model: was=${ts.modelName} now=$switched');
      if (mounted) {
        ref.read(transcriptionScreenProvider.notifier).setModelName(switched);
        ref.read(settingsServiceProvider).defaultModel = switched;
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.transcribeLoadedFile(whisperFirst.displayName)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    // Ensure model is loaded (if not already)
    final modelName = ref.read(transcriptionScreenProvider).modelName;
    final currentStatus = transcriptionService.getEngineStatus();
    if (currentStatus.currentModelId != modelName) {
      try {
        await transcriptionService.loadModel(modelName);
      } catch (e) {
        if (mounted) {
          // Drop the pending flag so the user can fix the
          // download and click Transcribe again. Without this
          // the button stays "Transcribing…" forever on a
          // missing-model error.
          ref.read(transcriptionScreenProvider.notifier).setTranscribePending(false);
          final l = AppLocalizations.of(context);
          final isNotDownloaded =
              e.toString().contains('is not downloaded');
          if (isNotDownloaded) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.defaultModelNotDownloaded(_modelName)),
                action: SnackBarAction(
                  label: l.openModels,
                  onPressed: () {
                    if (mounted) context.push('/models');
                  },
                ),
                duration: const Duration(seconds: 8),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.transcriptionLoadFailed(e.toString())),
                duration: const Duration(seconds: 8),
                showCloseIcon: true,
              ),
            );
          }
        }
        return;
      }
    }

    // The model load above can take ~10 s (uninterruptible FFI ctor). If
    // the user hit Cancel during that window, the load still finished —
    // but honour the intent: don't start transcribing. The model is now
    // resident, so a later Transcribe click starts immediately.
    if (ref.read(transcriptionScreenProvider).loadCancelled) {
      Log.instance.w('ui',
          'Model load completed after user cancel — leaving model resident, '
          'skipping transcription start',
          fields: {'model': _modelName});
      if (mounted) ref.read(transcriptionScreenProvider.notifier).setTranscribePending(false);
      return;
    }

    try {
      // The real "wipe-previous-transcript + flip global isTranscribing"
      // step. The local _transcribePending was just covering the
      // pre-load window; now hand off to the global flag and clear
      // ours so the button keeps showing the busy state via
      // appState.isTranscribing.
      appStateNotifier.startTranscription();
      if (mounted) ref.read(transcriptionScreenProvider.notifier).setTranscribePending(false);

      final started = DateTime.now();
      List<TranscriptionSegment> segments = [];
      final adv = ref.read(advancedOptionsProvider);
      // Source-language override: when the user pinned a source in
      // Advanced Options, it wins over the global picker / autodetect.
      // Empty means "use the global picker" — same behaviour as before.
      final language = adv.sourceLanguage.isNotEmpty
          ? adv.sourceLanguage
          : (_language == 'auto' ? null : _language);

      final advancedRun = AdvancedTranscribeOptions(
        vadBackend: adv.vadBackend,
        vadThreshold: adv.vadThreshold,
        vadMinSpeechMs: adv.vadMinSpeechMs,
        vadMinSilenceMs: adv.vadMinSilenceMs,
        vadSpeechPadMs: adv.vadSpeechPadMs,
        diarizeMethod: adv.diarizeMethod,
        enableSpeakerRecognition: adv.enableSpeakerRecognition,
        lidMethod: adv.lidMethod,
        tdrz: adv.tdrz,
        tokenTimestamps: adv.tokenTimestamps,
        puncFamily: adv.puncFamily,
        lidUseGpu: adv.lidUseGpu,
        lidFlashAttn: adv.lidFlashAttn,
        nThreads: adv.nThreads,
        asrUseGpu: adv.asrUseGpu,
        asrFlashAttn: adv.asrFlashAttn,
        asrNGpuLayers: adv.asrNGpuLayers,
        maxLen: adv.maxLen,
        splitOnWord: adv.splitOnWord,
        splitOnPunct: adv.splitOnPunct,
        grammarText: adv.grammarText,
        grammarRootRule: adv.grammarRootRule,
        grammarPenalty: adv.grammarPenalty,
        entropyThold: adv.entropyThold,
        logprobThold: adv.logprobThold,
        noSpeechThold: adv.noSpeechThold,
        temperatureInc: adv.temperatureInc,
        suppressNonSpeechTokens: adv.suppressNonSpeechTokens,
        suppressTokensRegex: adv.suppressTokensRegex,
        carryInitialPrompt: adv.carryInitialPrompt,
        enhanceAudio: adv.enhanceAudio,
        transcribeWindowStartSec: adv.transcribeWindowStartSec,
        transcribeWindowDurationSec: adv.transcribeWindowDurationSec,
        altN: adv.altN,
        hotwords: adv.hotwords,
        hotwordsBoost: adv.hotwordsBoost,
        beamSize: adv.beamSize,
        alignerModel: adv.alignerModel.isEmpty ? null : adv.alignerModel,
      );

      // §5.1.2 vocabulary merge — resolve the active backend
      // once, then ask AdvancedOptions to merge the vocabulary
      // list into the right prompt field per the per-backend
      // capability matrix. CTC backends fall through to the
      // existing user-typed prompts unchanged.
      final activeBackend = _resolveBackend(_modelName);
      final mergedInitialPrompt = AdvancedOptions.mergeHotwordsIntoPrompt(
        backend: activeBackend,
        hotwords: adv.hotwords,
        existing: AdvancedOptions.vocabularyViaInitialPromptBackends
                .contains(activeBackend)
            ? AdvancedOptions.mergeVocabularyIntoPrompt(
                backend: activeBackend,
                vocabulary: adv.vocabulary,
                existing: adv.initialPrompt,
              )
            : adv.initialPrompt,
      );
      final mergedAskPrompt = AdvancedOptions.mergeHotwordsIntoPrompt(
        backend: activeBackend,
        hotwords: adv.hotwords,
        existing: AdvancedOptions.vocabularyViaAskPromptBackends
                .contains(activeBackend)
            ? AdvancedOptions.mergeVocabularyIntoPrompt(
                backend: activeBackend,
                vocabulary: adv.vocabulary,
                existing: adv.askPrompt,
              )
            : adv.askPrompt,
      );

      if (_selectedFileBytes != null && plat.isWeb) {
        // Web path: send raw bytes to the cloud engine.
        segments = await transcriptionService.transcribeBytes(
          _selectedFileBytes!,
          _selectedFileName ?? 'audio.wav',
          language: language,
          translate: adv.translate,
          vad: adv.vad,
          diarize: _enableDiarization,
          punctuation: adv.restorePunctuation,
          initialPrompt:
              mergedInitialPrompt.isEmpty ? null : mergedInitialPrompt,
          temperature: adv.temperature,
          onProgress: appStateNotifier.updateProgress,
          onSegment: appStateNotifier.addSegment,
        );
      } else if (filePath != null) {
        segments = await transcriptionService.transcribeFile(
          File(filePath),
          language: language,
          enableDiarization: _enableDiarization,
          translate: adv.translate,
          beamSearch: adv.beamSearch,
          initialPrompt:
              mergedInitialPrompt.isEmpty ? null : mergedInitialPrompt,
          vad: adv.vad,
          restorePunctuation: adv.restorePunctuation,
          targetLanguage:
              adv.targetLanguage.isEmpty ? null : adv.targetLanguage,
          askPrompt: mergedAskPrompt.isEmpty ? null : mergedAskPrompt,
          temperature: adv.temperature,
          bestOf: adv.bestOf,
          advanced: advancedRun,
          onProgress: appStateNotifier.updateProgress,
          onSegment: appStateNotifier.addSegment,
        );
      } else {
        segments = await transcriptionService.transcribeUrl(
          _urlController.text,
          language: language,
          enableDiarization: _enableDiarization,
          translate: adv.translate,
          beamSearch: adv.beamSearch,
          initialPrompt:
              mergedInitialPrompt.isEmpty ? null : mergedInitialPrompt,
          vad: adv.vad,
          restorePunctuation: adv.restorePunctuation,
          targetLanguage:
              adv.targetLanguage.isEmpty ? null : adv.targetLanguage,
          askPrompt: mergedAskPrompt.isEmpty ? null : mergedAskPrompt,
          temperature: adv.temperature,
          bestOf: adv.bestOf,
          advanced: advancedRun,
          onProgress: appStateNotifier.updateProgress,
          onSegment: appStateNotifier.addSegment,
        );
      }

      final engine = transcriptionService.currentEngine;
      final perf = PerformanceStats.fromMetadata(
        transcriptionService.lastResult?.metadata,
        engineId: engine?.engineId,
        modelId: engine?.currentModelId,
      );
      appStateNotifier.completeTranscription(segments, performance: perf);

      // §5.25.5 — Post-transcription multilingual language tagging.
      if (_tagSegmentLanguages && transcriptionService.lastAudioData != null) {
        try {
          final lidService = ref.read(lidServiceProvider);
          final mlService =
              MultilingualTranscriptionService(lidService: lidService);
          final tagged = await mlService.tagSegmentLanguages(
            audioData: transcriptionService.lastAudioData!,
            segments: segments,
            sampleRate: transcriptionService.lastSampleRate,
          );
          appStateNotifier.replaceSegments(tagged);
          segments = tagged;
        } catch (e) {
          debugPrint('Multilingual tagging failed: $e');
        }
      }

      // Free retained PCM buffer — multilingual tagging (the only
      // consumer) is done, no need to hold ~230 MB until the next
      // transcription starts.
      transcriptionService.clearAudioBuffer();

      // §5.25.4 — Speaker-adaptive vocabulary injection.
      // After diarisation resolves speaker names, load their vocab
      // profiles and merge the terms into the global vocabulary for
      // subsequent transcriptions.
      if (_enableDiarization && segments.isNotEmpty) {
        try {
          final speakerNames = segments
              .map((s) => s.speaker)
              .where((s) => s != null && !RegExp(r'^Speaker \d+$').hasMatch(s))
              .cast<String>()
              .toSet();
          if (speakerNames.isNotEmpty) {
            final docs = await getApplicationDocumentsDirectory();
            final speakersDir = '${docs.path}/speakers';
            final allVocabs = await SpeakerVocab.listAll(speakersDir);
            final merged =
                SpeakerVocab.mergeForSpeakers(allVocabs, speakerNames);
            if (merged.isNotEmpty) {
              final currentAdv = ref.read(advancedOptionsProvider);
              final existingTerms = currentAdv.vocabulary.toSet();
              final newTerms =
                  merged.where((t) => !existingTerms.contains(t)).toList();
              if (newTerms.isNotEmpty) {
                ref.read(advancedOptionsProvider.notifier).state =
                    currentAdv.copyWith(
                  vocabulary: [...currentAdv.vocabulary, ...newTerms],
                );
                Log.instance.i('vocab', 'injected speaker-adaptive vocab',
                    fields: {
                      'speakers': speakerNames.toList(),
                      'terms_added': newTerms.length,
                    });
              }
            }
          }
        } catch (e) {
          Log.instance.w('vocab', 'speaker vocab injection failed', error: e);
        }
      }

      // Persist to history. Stash the new id on AppState so §5.1.3
      // inline edits can propagate back to the same JSON file via
      // historyService.update(...).
      try {
        final saved = await ref.read(historyServiceProvider).save(
              engineId: engine?.engineId ?? 'unknown',
              segments: segments,
              sourcePath: filePath,
              sourceUrl: filePath == null ? _urlController.text : null,
              modelId: engine?.currentModelId ?? _modelName,
              language: _language,
              diarizationEnabled: _enableDiarization,
              processingTime: DateTime.now().difference(started),
              speakerNames: ref.read(appStateProvider).speakerNames,
              embedder: ref.read(crispEmbedProvider).value,
              audioData: transcriptionService.lastAudioData,
            );
        appStateNotifier.setHistoryEntryId(saved.id);
      } catch (e, st) {
        debugPrint('History save failed: $e\n$st');
      }
    } catch (e) {
      appStateNotifier.setError(e.toString());
    } finally {
      // Safety net: appState.isTranscribing flips back to false in both
      // setError / completeTranscription, so the *global* busy state
      // is correct. The local _transcribePending should also be off
      // by now (cleared right after the appStateNotifier.startTranscription
      // hand-off earlier in this function), but clear it again here in
      // case the model-load path failed in a way that skipped that
      // line — keeps the button re-clickable for a fresh attempt.
      if (mounted && ref.read(transcriptionScreenProvider).transcribePending) {
        ref.read(transcriptionScreenProvider.notifier).setTranscribePending(false);
      }
    }
  }

  void _stopTranscription() {
    final transcriptionService = ref.read(transcriptionServiceProvider);
    transcriptionService.stopTranscription();

    final appStateNotifier = ref.read(appStateProvider.notifier);
    appStateNotifier.setError('Transcription stopped by user');
  }

  /// Drain the batch queue serially. One file at a time — concurrent FFI
  /// into a single whisper_context is unsafe.
  Future<void> _startBatchRun() async {
    final transcriptionService = ref.read(transcriptionServiceProvider);
    final queue = ref.read(batchQueueProvider.notifier);
    final appStateNotifier = ref.read(appStateProvider.notifier);
    final adv = ref.read(advancedOptionsProvider);
    final language = adv.sourceLanguage.isNotEmpty
        ? adv.sourceLanguage
        : (_language == 'auto' ? null : _language);
    final advancedRun = AdvancedTranscribeOptions(
      vadBackend: adv.vadBackend,
      vadThreshold: adv.vadThreshold,
      vadMinSpeechMs: adv.vadMinSpeechMs,
      vadMinSilenceMs: adv.vadMinSilenceMs,
      vadSpeechPadMs: adv.vadSpeechPadMs,
      diarizeMethod: adv.diarizeMethod,
      lidMethod: adv.lidMethod,
      tdrz: adv.tdrz,
      tokenTimestamps: adv.tokenTimestamps,
      puncFamily: adv.puncFamily,
      lidUseGpu: adv.lidUseGpu,
      lidFlashAttn: adv.lidFlashAttn,
      nThreads: adv.nThreads,
      asrUseGpu: adv.asrUseGpu,
      asrFlashAttn: adv.asrFlashAttn,
      asrNGpuLayers: adv.asrNGpuLayers,
      maxLen: adv.maxLen,
      splitOnWord: adv.splitOnWord,
      grammarText: adv.grammarText,
      grammarRootRule: adv.grammarRootRule,
      grammarPenalty: adv.grammarPenalty,
      entropyThold: adv.entropyThold,
      logprobThold: adv.logprobThold,
      noSpeechThold: adv.noSpeechThold,
      temperatureInc: adv.temperatureInc,
      suppressNonSpeechTokens: adv.suppressNonSpeechTokens,
      suppressTokensRegex: adv.suppressTokensRegex,
      carryInitialPrompt: adv.carryInitialPrompt,
      transcribeWindowStartSec: adv.transcribeWindowStartSec,
      transcribeWindowDurationSec: adv.transcribeWindowDurationSec,
      altN: adv.altN,
      hotwords: adv.hotwords,
      hotwordsBoost: adv.hotwordsBoost,
      beamSize: adv.beamSize,
      alignerModel: adv.alignerModel.isEmpty ? null : adv.alignerModel,
    );

    // Load the model once for the whole batch.
    if (!_engineReady) await _ensureEngineReady();
    final status = transcriptionService.getEngineStatus();
    if (status.currentModelId != _modelName) {
      try {
        await transcriptionService.loadModel(_modelName);
      } catch (e) {
        _showErrorDialog('Failed to load model $_modelName: $e');
        return;
      }
    }

    final persistence = queue.persistence;
    final settings = ref.read(settingsServiceProvider);
    // §5.23 Q1: reorder queued jobs into (backend, modelId, language)
    // bundles when the setting is on so consecutive same-bundle jobs
    // reuse the loaded session. Stable within each bundle, so the
    // user's drag-and-drop order within one model still holds. Done /
    // error / running rows stay in place.
    if (settings.groupBatchByBackend) {
      queue.reorderByGrouping();
    }

    // §5.23 Q2 v1 pipeline parallelism: pre-decode the next queued
    // file's audio in a worker isolate while the current file is
    // mid-GPU. AudioService.loadAudioFile consumes the cached
    // result if it's ready by the time we get there. Setting > 1
    // enables; setting == 1 keeps the v0.4 serial behaviour.
    final concurrent = settings.maxConcurrentTranscriptions;
    final prefetchEnabled = concurrent > 1;
    final prefetchService = prefetchEnabled
        ? ref.read(audioPrefetchServiceProvider)
        : null;

    // §5.23 Q2 v2 N-way session pool: opt-in slider gated on a
    // memory pre-flight. The pool's `dispatch` is a bare
    // `session.transcribe(samples)` — no VAD slicing, no resume
    // offset routing, no Q&A / translate / beam-search / best-of
    // (those need engine plumbing that lives on the main isolate).
    // So pool eligibility is per-job: jobs that need any of those
    // features fall through to the serial path below, while
    // "vanilla transcribe" jobs run in parallel on the pool.
    final pool = await _maybeSpawnWorkerPool(adv: adv);
    if (pool != null) {
      // Aggregate batch view (§5.23 Q2 v2 option (a)): one
      // startTranscription at batch open instead of per-job. The
      // queue card is the source of truth during parallel runs;
      // per-file segment streaming into AppState would interleave
      // N files' text.
      appStateNotifier.startTranscription();
    }

    // Track in-flight pool dispatches. The drain loop dispatches up
    // to `pool.size` pool-eligible jobs concurrently; pool-
    // ineligible jobs run serially in the same loop and block the
    // pool from receiving new work until they return.
    final inFlight = <Future<void>>{};

    try {
    while (true) {
      final next = queue.nextQueued();
      if (next == null) {
        // Pool may still have in-flight work; wait for it to drain.
        if (inFlight.isNotEmpty) {
          await Future.any(inFlight);
          continue;
        }
        break;
      }
      // §5.23 Q2 v2 parallel dispatch: if the pool is alive AND the
      // job is pool-eligible (the worker can do everything except
      // resume-offset / beamSearch / tdrz), fire it on the pool and
      // keep the main-loop walking. The advanced session knobs
      // (translate / targetLanguage / askPrompt / temperature /
      // bestOf / VAD) flow through the worker protocol; diarize +
      // punctuate run as main-isolate post-processes after the
      // worker returns.
      if (pool != null &&
          poolEligible(next, adv,
              enableDiarization: _enableDiarization)) {
        // Wait if the pool is already at capacity.
        if (inFlight.length >= pool.size) {
          await Future.any(inFlight);
          continue;
        }
        queue.setRunning(next.id);
        final fut = _runJobOnPool(
          pool: pool,
          job: next,
          language: language,
          persistence: persistence,
          queue: queue,
          adv: adv,
          advancedRun: advancedRun,
          enableDiarization: _enableDiarization,
          // Diarize speakers bounds: the screen doesn't currently
          // expose a min/max picker (existing serial path passes
          // null too), so let pyannote auto-estimate.
          minSpeakers: null,
          maxSpeakers: null,
          vadModelPath: adv.vad
              ? await transcriptionService.resolveVadModelPath(
                  backend: adv.vadBackend)
              : null,
        );
        inFlight.add(fut);
        fut.whenComplete(() => inFlight.remove(fut));
        continue;
      }
      // If the pool is alive AND busy, give it a chance to clear
      // before we start a serial job — otherwise we'd starve the
      // pool on whichever non-vanilla job came in.
      if (pool != null && inFlight.length >= pool.size) {
        await Future.any(inFlight);
        continue;
      }
      queue.setRunning(next.id);
      // §5.23 Q3 polish: if the job was enqueued against a
      // different model than the one currently loaded (because the
      // user switched models mid-queue, or because a crash-resumed
      // job had a snapshotted modelId from before that switch),
      // silently load the right one. This is what makes grouping
      // (§5.23 Q1) actually save time — without it the drain loop
      // would still use whatever `_modelName` happened to be when
      // batch started.
      final jobModelId = next.modelId;
      if (jobModelId != null && jobModelId.isNotEmpty) {
        final currentStatus = transcriptionService.getEngineStatus();
        if (currentStatus.currentModelId != jobModelId) {
          Log.instance.i('batch', 'switching model for job',
              fields: {
                'id': next.id,
                'from': currentStatus.currentModelId ?? 'none',
                'to': jobModelId,
              });
          try {
            await transcriptionService.loadModel(jobModelId);
          } catch (e, st) {
            // Couldn't load the snapshotted model — fall back to
            // the currently-loaded one and log. The transcription
            // might emit wrong-language results but won't crash.
            Log.instance.w('batch',
                'model swap failed; running against current session: $e',
                fields: {'id': next.id, 'target': jobModelId},
                stack: st);
          }
        }
      }
      // Kick off prefetch for the file AFTER the current one. The
      // current file's loadAudioFile call may also consume an
      // already-pending prefetch from the previous iteration.
      // Reads `batchQueueProvider` (the public list view) rather
      // than `queue.state` so we don't poke at StateNotifier
      // internals from outside.
      if (prefetchService != null) {
        final lookahead = _peekNextQueuedAfter(
            ref.read(batchQueueProvider), next.id);
        if (lookahead != null) {
          prefetchService.prefetch(lookahead.filePath);
        }
      }
      // §5.23 Q3 resume: replay any checkpointed segments into the
      // appState before dispatch so the user sees the partial
      // transcript that survived the crash, then the new run picks
      // up at next.resumeOffsetSec (which load() stamped from the
      // checkpoint's last segment).
      final resumeOffset = next.resumeOffsetSec ?? 0.0;
      List<TranscriptionSegment> resumedPrefix = const [];
      if (resumeOffset > 0) {
        try {
          resumedPrefix = await persistence.loadCheckpoint(next.id);
          // In pool-active mode we already fired
          // startTranscription() once at batch open. Skip the
          // per-job restart so the aggregate view stays stable.
          if (pool == null) appStateNotifier.startTranscription();
          for (final s in resumedPrefix) {
            appStateNotifier.addSegment(s);
          }
        } catch (e, st) {
          Log.instance.w('batch', 'checkpoint replay failed',
              fields: {'id': next.id}, error: e, stack: st);
          resumedPrefix = const [];
        }
      }
      Log.instance.i('batch', 'job start', fields: {
        'id': next.id,
        'file': next.filePath,
        if (resumeOffset > 0) 'resume_from_sec': resumeOffset.toStringAsFixed(1),
        if (resumeOffset > 0) 'resumed_segments': resumedPrefix.length,
      });
      try {
        if (resumeOffset == 0 && pool == null) {
          appStateNotifier.startTranscription();
        }
        final started = DateTime.now();
        // §5.1.2 — merge per-job. `next.modelId` is the
        // snapshotted model at enqueue; falls back to the
        // currently-loaded model if missing.
        final perJobBackend =
            _resolveBackend(next.modelId ?? _modelName);
        final perJobInitial = AdvancedOptions.mergeHotwordsIntoPrompt(
          backend: perJobBackend,
          hotwords: adv.hotwords,
          existing: AdvancedOptions
                  .vocabularyViaInitialPromptBackends
                  .contains(perJobBackend)
              ? AdvancedOptions.mergeVocabularyIntoPrompt(
                  backend: perJobBackend,
                  vocabulary: adv.vocabulary,
                  existing: adv.initialPrompt,
                )
              : adv.initialPrompt,
        );
        final perJobAsk = AdvancedOptions.mergeHotwordsIntoPrompt(
          backend: perJobBackend,
          hotwords: adv.hotwords,
          existing: AdvancedOptions
                  .vocabularyViaAskPromptBackends
                  .contains(perJobBackend)
              ? AdvancedOptions.mergeVocabularyIntoPrompt(
                  backend: perJobBackend,
                  vocabulary: adv.vocabulary,
                  existing: adv.askPrompt,
                )
              : adv.askPrompt,
        );
        final segments = await transcriptionService.transcribeFile(
          File(next.filePath),
          language: language,
          enableDiarization: _enableDiarization,
          translate: adv.translate,
          beamSearch: adv.beamSearch,
          initialPrompt:
              perJobInitial.isEmpty ? null : perJobInitial,
          vad: adv.vad,
          restorePunctuation: adv.restorePunctuation,
          targetLanguage:
              adv.targetLanguage.isEmpty ? null : adv.targetLanguage,
          askPrompt: perJobAsk.isEmpty ? null : perJobAsk,
          temperature: adv.temperature,
          bestOf: adv.bestOf,
          advanced: advancedRun,
          startOffsetSec: resumeOffset,
          onProgress: (p) {
            queue.setProgress(next.id, p);
            appStateNotifier.updateProgress(p);
          },
          // §5.23 Q3 checkpoint streaming — every segment hits the
          // appState (visible) AND the per-job .ckpt.jsonl on disk
          // (resumable). Fire-and-forget: a slow disk shouldn't
          // back-pressure transcription. In pool-active mode the
          // queue card is the source of truth (aggregate view), so
          // we skip the live AppState push to keep parallel files'
          // segments from interleaving in the same panel.
          onSegment: (seg) {
            if (pool == null) appStateNotifier.addSegment(seg);
            unawaited(
                persistence.appendSegmentToCheckpoint(next.id, seg));
          },
        );
        // Final transcript = recovered prefix (already in appState +
        // ckpt) ∪ freshly-emitted tail. Dedupe by endTime in case the
        // engine emitted a segment that the chunked-whisper resume
        // path also covered.
        final fullSegments = <TranscriptionSegment>[
          ...resumedPrefix,
          ...segments.where((s) =>
              resumedPrefix.every((r) => r.endTime != s.endTime)),
        ];
        final engine = transcriptionService.currentEngine;
        final perf = PerformanceStats.fromMetadata(
          transcriptionService.lastResult?.metadata,
          engineId: engine?.engineId,
          modelId: engine?.currentModelId,
        );
        // Aggregate batch view: don't fire per-job
        // completeTranscription while the pool is alive — the
        // final completion (with last-finishing job's segments)
        // fires in the finally block below.
        if (pool == null) {
          appStateNotifier.completeTranscription(fullSegments,
              performance: perf);
        }

        String? historyId;
        try {
          final saved = await ref.read(historyServiceProvider).save(
                engineId: engine?.engineId ?? 'unknown',
                modelId: engine?.currentModelId,
                language: language,
                segments: fullSegments,
                sourcePath: next.filePath,
                diarizationEnabled: _enableDiarization,
                processingTime: DateTime.now().difference(started),
                speakerNames: ref.read(appStateProvider).speakerNames,
                embedder: ref.read(crispEmbedProvider).value,
                audioData: transcriptionService.lastAudioData,
              );
          historyId = saved.id;
        } catch (e, st) {
          Log.instance.w('batch', 'history save failed', error: e, stack: st);
        }
        // setDone clears the .ckpt file via BatchQueueNotifier's
        // post-mutation hook, so a successful run leaves no stale
        // checkpoint behind.
        queue.setDone(next.id,
            resultText: fullSegments.map((s) => s.text).join(' ').trim(),
            historyEntryId: historyId);
        Log.instance.i('batch', 'job done', fields: {
          'id': next.id,
          'segments': fullSegments.length,
          if (resumeOffset > 0) 'recovered': resumedPrefix.length,
        });
      } catch (e, st) {
        queue.setError(next.id, e.toString());
        Log.instance.e('batch', 'job failed',
            fields: {'id': next.id}, error: e, stack: st);
        // Aggregate-mode: don't surface per-job errors as a global
        // appState error (it'd kick the screen out of "batch
        // running" mode while other workers are still going). The
        // queue card row already shows the error status + message.
        if (pool == null) appStateNotifier.setError(e.toString());
      }
    }
    } finally {
      // Drain remaining in-flight pool work before teardown so
      // segments + history saves complete cleanly.
      while (inFlight.isNotEmpty) {
        await Future.any(inFlight);
      }
      // Pool teardown — sends 'shutdown' to each worker, gives
      // them 100 ms to close the session, then kills the isolate.
      if (pool != null) {
        await pool.shutdown();
        // Aggregate completion: surface the final state of the
        // batch as a single "done" event. We don't have a
        // canonical "batch segments" so we use whatever the
        // serial fallback left in AppState, or empty.
        final st = ref.read(appStateProvider);
        appStateNotifier.completeTranscription(
            st.segments,
            performance: null);
      }
    }
  }

  /// Spawn an N-way session pool when the user has opted in
  /// (`Settings.maxConcurrentSessions > 1`) AND the memory
  /// estimator says N workers fit. Returns null in every other
  /// case — the drain loop then walks the serial path.
  Future<TranscriptionWorkerPool?> _maybeSpawnWorkerPool({
    required AdvancedOptions adv,
  }) async {
    final settings = ref.read(settingsServiceProvider);
    final requested = settings.maxConcurrentSessions;
    if (requested <= 1) return null;
    final modelDef = ModelCatalog.whisperCppModels[_modelName] ??
        ModelCatalog.crispasrBackendModels[_modelName];
    if (modelDef == null) {
      Log.instance.d('batch',
          'pool skipped: $_modelName not in catalog (custom GGUF?)');
      return null;
    }
    final modelsDir = ref.read(modelServiceProvider).whisperCppDir();
    final modelPath = p.join(modelsDir, modelDef.fileName);
    final estimator = ref.read(memoryEstimatorProvider);
    final est = estimator.estimate(
        requested: requested, modelPath: modelPath);
    if (est.affordableWorkers <= 1) {
      Log.instance.i('batch',
          'pool skipped: pre-flight clamped to 1 worker (${est.reason})',
          fields: {
            'requested': requested,
            'model_mb': est.modelBytesPerWorker ~/ (1024 * 1024),
          });
      return null;
    }
    Log.instance.i('batch',
        'spawning pool: ${est.affordableWorkers} workers (requested $requested)',
        fields: {
          'model': _modelName,
          'projected_gb':
              (est.projectedUsageBytes / (1024 * 1024 * 1024))
                  .toStringAsFixed(2),
        });
    try {
      return await TranscriptionWorkerPool.spawn(
        count: est.affordableWorkers,
        modelPath: modelPath,
        backend: modelDef.backend,
        useGpu: adv.asrUseGpu,
        flashAttn: adv.asrFlashAttn,
        nThreads: adv.nThreads,
        nGpuLayers: adv.asrNGpuLayers,
      );
    } catch (e, st) {
      Log.instance
          .w('batch', 'pool spawn failed; falling back to serial: $e',
              stack: st);
      return null;
    }
  }

  /// Per-job pool dispatch. Loads audio on the main isolate (uses
  /// the §5.23 Q2 v1 prefetch when warm), pushes the advanced
  /// session-state setters across the SendPort wire so the worker
  /// applies them before transcribe, hands the samples off to a
  /// free worker, streams segments through the checkpoint file
  /// (NOT AppState — aggregate mode), then runs diarization +
  /// punctuation as a main-isolate post-process on the returned
  /// segments. Finally saves to history + marks the job done.
  ///
  /// The pool dispatch is the GPU-heavy step that benefits from
  /// parallelism; diarize / punc are sequential post-processes
  /// that we run on main thread. The win is parallel transcribe,
  /// not parallel post-processing.
  Future<void> _runJobOnPool({
    required TranscriptionWorkerPool pool,
    required BatchJob job,
    required String? language,
    required BatchPersistenceService persistence,
    required BatchQueueNotifier queue,
    required AdvancedOptions adv,
    required AdvancedTranscribeOptions advancedRun,
    required bool enableDiarization,
    required int? minSpeakers,
    required int? maxSpeakers,
    String? vadModelPath,
  }) async {
    final audioService = ref.read(audioServiceProvider);
    final transcriptionService = ref.read(transcriptionServiceProvider);
    Log.instance.i('batch', 'pool job start',
        fields: {'id': job.id, 'file': job.filePath});
    final started = DateTime.now();
    try {
      final audioData = await audioService.loadAudioFile(File(job.filePath));
      // §5.1.10 — RNNoise enhancement runs on the full loaded PCM
      // before the §5.8 window slice. Order matters: slicing first
      // would lose the context the denoiser needs at the boundary
      // (RNNoise has ~10 ms of look-ahead state per frame).
      // Pre-0.5.12 libcrispasr raises UnsupportedError; we log
      // and fall through so toggling the switch never breaks
      // batch jobs.
      var baseSamples = audioData.samples;
      if (adv.enhanceAudio) {
        try {
          baseSamples = crispasr.enhanceAudioRnnoise(audioData.samples);
        } on UnsupportedError catch (e) {
          Log.instance.w(
              'batch',
              'enhanceAudio requested but libcrispasr lacks the '
                  'symbol — using original PCM ($e)');
        }
      }
      // §5.8 — `--offset-t / --duration` window slice. Pre-slice
      // the PCM here so the engine only processes the requested
      // [start, start+duration) range; we shift the returned
      // segment timestamps by `windowStart` so they stay absolute
      // in file time. Empty window (0/0) is a no-op.
      final windowedSamples = CrispASREngine.sliceTranscribeWindow(
        baseSamples,
        audioData.sampleRate,
        adv.transcribeWindowStartSec,
        adv.transcribeWindowDurationSec,
      );
      final windowStartShift = adv.transcribeWindowStartSec > 0
          ? adv.transcribeWindowStartSec
          : 0.0;
      // §5.1.2 — vocabulary biasing merges into whichever prompt
      // field the active backend uses (initial_prompt or askPrompt).
      // Pool workers consume both via their sticky setter
      // protocol, so we just pass the merged strings here.
      final poolBackend = _resolveBackend(job.modelId ?? _modelName);
      final poolAsk = AdvancedOptions.mergeHotwordsIntoPrompt(
        backend: poolBackend,
        hotwords: adv.hotwords,
        existing: AdvancedOptions
                .vocabularyViaAskPromptBackends
                .contains(poolBackend)
            ? AdvancedOptions.mergeVocabularyIntoPrompt(
                backend: poolBackend,
                vocabulary: adv.vocabulary,
                existing: adv.askPrompt,
              )
            : adv.askPrompt,
      );
      var segments = await pool.dispatch(
        samples: windowedSamples,
        language: language,
        targetLanguage:
            adv.targetLanguage.isEmpty ? null : adv.targetLanguage,
        translate: adv.translate,
        askPrompt: poolAsk.isEmpty ? null : poolAsk,
        temperature: adv.temperature,
        bestOf: adv.bestOf,
        // Beam search: when the user toggled it ON we pass whisper's
        // upstream default width (5). The setter is unconditional;
        // non-whisper backends silently no-op until CrispASR wires
        // their per-call beam_size through the high-level transcribe
        // API.
        beamSize: adv.beamSearch ? 5 : 1,
        vadModelPath:
            (adv.vad && vadModelPath != null) ? vadModelPath : null,
        vadThreshold: advancedRun.vadThreshold,
        vadMinSpeechMs: advancedRun.vadMinSpeechMs,
        vadMinSilenceMs: advancedRun.vadMinSilenceMs,
        vadSpeechPadMs: advancedRun.vadSpeechPadMs,
        // §5.8 — GBNF grammar (Whisper-only). The worker
        // unconditionally fires session.setGrammar(...) on every
        // dispatch so an empty string clears any prior grammar.
        grammarText: adv.grammarText,
        grammarRootRule: adv.grammarRootRule,
        grammarPenalty: adv.grammarPenalty,
        entropyThold: adv.entropyThold,
        logprobThold: adv.logprobThold,
        noSpeechThold: adv.noSpeechThold,
        temperatureInc: adv.temperatureInc,
        suppressNonSpeechTokens: adv.suppressNonSpeechTokens,
        suppressTokensRegex: adv.suppressTokensRegex,
        carryInitialPrompt: adv.carryInitialPrompt,
        altN: adv.altN,
        hotwords: adv.hotwords,
        onSegment: (seg) {
          // Apply the window shift here too so the checkpoint /
          // streamed-into-UI timestamps match the post-loop shift
          // applied to `segments` below.
          final shifted = windowStartShift > 0
              ? CrispASREngine.shiftSegmentForResume(seg,
                  offsetSeconds: windowStartShift)
              : seg;
          unawaited(persistence.appendSegmentToCheckpoint(
              job.id, shifted));
        },
      );
      // §5.8 — shift every returned segment's timestamps by the
      // window start so they're absolute in file time. The pool
      // workers don't know about windowing (the slice happens
      // here before dispatch), so the shift has to happen here.
      if (windowStartShift > 0) {
        segments = segments
            .map((s) => CrispASREngine.shiftSegmentForResume(s,
                offsetSeconds: windowStartShift))
            .toList(growable: false);
      }
      // Main-isolate post-process: diarize + punctuate. Same code
      // path the serial transcribeFile() uses; we just call into
      // the services directly here since we already have the raw
      // segments from the pool. Both services no-op when their
      // model files aren't on disk.
      if (enableDiarization && segments.isNotEmpty) {
        try {
          segments = await transcriptionService.diarize(
            audioData,
            segments,
            minSpeakers: minSpeakers,
            maxSpeakers: maxSpeakers,
            method: advancedRun.diarizeMethod,
            enableSpeakerRecognition: advancedRun.enableSpeakerRecognition,
          );
        } catch (e, st) {
          Log.instance.w('batch', 'diarize (pool post-process) failed',
              fields: {'id': job.id}, error: e, stack: st);
        }
      }
      if (adv.restorePunctuation && segments.isNotEmpty) {
        try {
          segments =
              await transcriptionService.restorePunctuation(segments);
        } catch (e, st) {
          Log.instance.w('batch', 'punc (pool post-process) failed',
              fields: {'id': job.id}, error: e, stack: st);
        }
      }
      // §5.25.4 — Speaker-adaptive vocabulary injection (batch path).
      if (enableDiarization && segments.isNotEmpty) {
        try {
          final speakerNames = segments
              .map((s) => s.speaker)
              .where(
                  (s) => s != null && !RegExp(r'^Speaker \d+$').hasMatch(s))
              .cast<String>()
              .toSet();
          if (speakerNames.isNotEmpty) {
            final docs = await getApplicationDocumentsDirectory();
            final speakersDir = '${docs.path}/speakers';
            final allVocabs = await SpeakerVocab.listAll(speakersDir);
            final merged =
                SpeakerVocab.mergeForSpeakers(allVocabs, speakerNames);
            if (merged.isNotEmpty) {
              final currentAdv = ref.read(advancedOptionsProvider);
              final existingTerms = currentAdv.vocabulary.toSet();
              final newTerms =
                  merged.where((t) => !existingTerms.contains(t)).toList();
              if (newTerms.isNotEmpty) {
                ref.read(advancedOptionsProvider.notifier).state =
                    currentAdv.copyWith(
                  vocabulary: [...currentAdv.vocabulary, ...newTerms],
                );
                Log.instance.i('vocab',
                    'injected speaker-adaptive vocab (batch)', fields: {
                  'speakers': speakerNames.toList(),
                  'terms_added': newTerms.length,
                });
              }
            }
          }
        } catch (e) {
          Log.instance.w('vocab', 'speaker vocab injection failed (batch)',
              error: e);
        }
      }

      String? historyId;
      try {
        final saved = await ref.read(historyServiceProvider).save(
              engineId: 'crispasr',
              modelId: _modelName,
              language: language,
              segments: segments,
              sourcePath: job.filePath,
              diarizationEnabled: enableDiarization,
              processingTime: DateTime.now().difference(started),
              speakerNames: const {},
              embedder: ref.read(crispEmbedProvider).value,
              audioData: transcriptionService.lastAudioData,
            );
        historyId = saved.id;
      } catch (e, st) {
        Log.instance.w('batch', 'history save failed (pool path)',
            fields: {'id': job.id}, error: e, stack: st);
      }
      queue.setDone(job.id,
          resultText: segments.map((s) => s.text).join(' ').trim(),
          historyEntryId: historyId);
      Log.instance.i('batch', 'pool job done',
          fields: {'id': job.id, 'segments': segments.length});
    } catch (e, st) {
      Log.instance.e('batch', 'pool job failed',
          fields: {'id': job.id}, error: e, stack: st);
      queue.setError(job.id, e.toString());
    }
  }

  /// Returns the first job after [currentId] that's still queued, or
  /// null when [currentId] is the last queued row. Used by the §5.23
  /// Q2 prefetch hook to kick off the next file's audio decode.
  static BatchJob? _peekNextQueuedAfter(
      List<BatchJob> jobs, String currentId) {
    var passedCurrent = false;
    for (final j in jobs) {
      if (!passedCurrent) {
        if (j.id == currentId) passedCurrent = true;
        continue;
      }
      if (j.status == BatchJobStatus.queued) return j;
    }
    return null;
  }

  /// §5.1.2 — resolve a modelId to its backend identifier. Looks
  /// up `crispasrBackendModels` first (session backends), then
  /// `whisperCppModels`; falls back to "whisper" when the model
  /// isn't catalogued (custom GGUFs loaded by path). The backend
  /// string is what the per-backend capability sets in
  /// AdvancedOptions key on.
  static String _resolveBackend(String modelId) {
    return ModelCatalog.crispasrBackendModels[modelId]?.backend ??
        ModelCatalog.whisperCppModels[modelId]?.backend ??
        'whisper';
  }

  void _clearTranscription() {
    final appStateNotifier = ref.read(appStateProvider.notifier);
    appStateNotifier.clearTranscription();
  }

  void _handleShareAction(String action, AppState appState) {
    switch (action) {
      case 'share':
        SharePlus.instance
            .share(ShareParams(text: appState.currentTranscription!));
        break;
      case 'copy':
        Clipboard.setData(ClipboardData(text: appState.currentTranscription!));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)
                  .transcriptionCopiedToClipboard)),
        );
        break;
      case 'save_txt':
        _saveAs(appState, TranscriptFormat.txt);
        break;
      case 'save_srt':
        _saveAs(appState, TranscriptFormat.srt);
        break;
      case 'save_vtt':
        _saveAs(appState, TranscriptFormat.vtt);
        break;
      case 'save_json':
        _saveAs(appState, TranscriptFormat.json);
        break;
      case 'save_csv':
        _saveAs(appState, TranscriptFormat.csv);
        break;
      case 'save_lrc':
        _saveAs(appState, TranscriptFormat.lrc);
        break;
      case 'save_wts':
        _saveAs(appState, TranscriptFormat.wts);
        break;
      case 'save_md':
        _saveAs(appState, TranscriptFormat.md);
        break;
      case 'share_bundle':
        _shareAudioAndTranscript(appState);
        break;
      case 'save_obsidian':
        _saveAsNote(appState, 'obsidian');
        break;
      case 'save_notion':
        _saveAsNote(appState, 'notion');
        break;
      case 'save_logseq':
        _saveAsNote(appState, 'logseq');
        break;
      case 'save_chapters':
        _saveAsNote(appState, 'chapters');
        break;
      case 'save_chapters_detected':
        _saveDetectedChapters(appState, podcast: false);
        break;
      case 'save_podcast_chapters':
        _saveDetectedChapters(appState, podcast: true);
        break;
    }
  }

  /// Share the currently-selected audio file alongside an SRT
  /// transcript as a 2-file bundle. No-op with a snackbar when
  /// no audio is selected (e.g. the user transcribed via the
  /// microphone and hasn't saved the recording).
  Future<void> _shareAudioAndTranscript(AppState appState) async {
    final l = AppLocalizations.of(context);
    final selected = ref.read(selectedAudioPathProvider);
    final audioPath = _selectedFilePath ?? selected;
    if (audioPath == null || audioPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.transcriptionShareAudioMissing),
      ));
      return;
    }
    try {
      await FileUtils.shareAudioAndTranscript(
        audioPath: audioPath,
        segments: appState.segments,
        plainText: appState.currentTranscription ?? '',
        // SRT is the universal subtitle / transcript format —
        // every player + editor recognises it. The user can
        // still pick a different format via the dedicated
        // Save-as entries.
        transcriptFormat: TranscriptFormat.srt,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.transcriptionSaveFailed(e.toString())),
      ));
    }
  }

  Future<void> _saveAs(AppState state, TranscriptFormat format) async {
    try {
      final baseName = 'transcription-${DateTime.now().millisecondsSinceEpoch}';
      final file = await FileUtils.saveTranscription(
        state.currentTranscription ?? '',
        baseName,
        format: format,
        segments: state.segments,
        syntheticDisclosure: AppConstants.enableSyntheticDisclosure,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcriptionSavedTo(file.path))),
      );
      await FileUtils.shareFile(file.path, subject: baseName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcriptionSaveFailed(e.toString()))),
      );
    }
  }

  /// §5.25.14 — Export to note-taking tools.
  Future<void> _saveAsNote(AppState state, String format) async {
    try {
      final segments = state.segments;
      final title =
          'Transcription ${DateTime.now().toIso8601String().substring(0, 10)}';
      String content;
      String ext;
      switch (format) {
        case 'obsidian':
          content = NoteExportService.toObsidian(
            segments: segments,
            title: title,
            date: DateTime.now(),
            model: _modelName,
            language: _language,
          );
          ext = 'md';
        case 'notion':
          content = NoteExportService.toNotion(
            segments: segments,
            title: title,
            date: DateTime.now(),
          );
          ext = 'md';
        case 'logseq':
          content = NoteExportService.toLogseq(
            segments: segments,
            title: title,
            date: DateTime.now(),
            model: _modelName,
          );
          ext = 'md';
        case 'chapters':
          content = NoteExportService.toYouTubeChapters(segments: segments);
          ext = 'txt';
        default:
          return;
      }
      final baseName = 'transcript-$format-${DateTime.now().millisecondsSinceEpoch}';
      final dir = await FileUtils.getDocumentsSubdir('exports');
      final file = File('${dir.path}/$baseName.$ext');
      await file.writeAsString(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcriptionSavedTo(file.path))),
      );
      await FileUtils.shareFile(file.path, subject: baseName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcriptionSaveFailed(e.toString()))),
      );
    }
  }

  /// §5.25.6 — Detect chapters via topic-shift analysis and export
  /// as YouTube timestamps or Podcasting 2.0 JSON.
  Future<void> _saveDetectedChapters(AppState state,
      {required bool podcast}) async {
    try {
      final segments = state.segments;
      if (segments.isEmpty) return;
      final chapters = ChapterDetectionService.detectChapters(
        segments: segments,
      );
      String content;
      String ext;
      if (podcast) {
        content = const JsonEncoder.withIndent('  ')
            .convert(ChapterDetectionService.toPodcastChaptersJson(chapters));
        ext = 'json';
      } else {
        content = ChapterDetectionService.toYouTubeFormat(chapters);
        ext = 'txt';
      }
      final baseName =
          'chapters-${podcast ? "podcast" : "youtube"}-${DateTime.now().millisecondsSinceEpoch}';
      final dir = await FileUtils.getDocumentsSubdir('exports');
      final file = File('${dir.path}/$baseName.$ext');
      await file.writeAsString(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcriptionSavedTo(file.path))),
      );
      await FileUtils.shareFile(file.path, subject: baseName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcriptionSaveFailed(e.toString()))),
      );
    }
  }

  /// §5.25.13 — Model A/B comparison. Shows a picker for a second model,
  /// spawns two single-worker pools (one per model) so both transcriptions
  /// run in parallel, then navigates to the compare screen.
  Future<void> _showModelComparison() async {
    final l = AppLocalizations.of(context);
    final filePath = _selectedFilePath ?? ref.read(selectedAudioPathProvider);
    if (filePath == null || filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.transcriptionShareAudioMissing)),
      );
      return;
    }

    // Pick second model
    final otherModels = _availableModels
        .where((m) => m.name != _modelName && m.isDownloaded)
        .toList();
    if (otherModels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.abTestNeedSecondModel)),
      );
      return;
    }

    final secondModel = await showDialog<ModelInfo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.abTestPickModel),
        children: [
          for (final m in otherModels)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(m),
              child: Text('${m.name} (${m.backend})'),
            ),
        ],
      ),
    );
    if (secondModel == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.abTestRunning(_modelName, secondModel.name)),
        duration: const Duration(seconds: 3),
      ),
    );

    // Resolve model paths for both models.
    final modelA = _availableModels.firstWhere((m) => m.name == _modelName);
    final pathA = modelA.localPath;
    final pathB = secondModel.localPath;
    if (pathA == null || pathB == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.abTestFailed(l.transcriptionShareAudioMissing))),
        );
      }
      return;
    }

    TranscriptionWorkerPool? poolA;
    TranscriptionWorkerPool? poolB;
    try {
      final adv = ref.read(advancedOptionsProvider);
      final historyService = ref.read(historyServiceProvider);
      final audioService = ref.read(audioServiceProvider);

      // Load audio once.
      final audioData = await audioService.loadAudioFile(File(filePath));

      // Spawn two single-worker pools in parallel — one per model.
      final backendA = _resolveBackend(_modelName);
      final backendB = _resolveBackend(secondModel.name);
      final pools = await Future.wait([
        TranscriptionWorkerPool.spawn(
          count: 1,
          modelPath: pathA,
          backend: backendA,
          useGpu: adv.asrUseGpu,
          flashAttn: adv.asrFlashAttn,
          nThreads: adv.nThreads,
          nGpuLayers: adv.asrNGpuLayers,
        ),
        TranscriptionWorkerPool.spawn(
          count: 1,
          modelPath: pathB,
          backend: backendB,
          useGpu: adv.asrUseGpu,
          flashAttn: adv.asrFlashAttn,
          nThreads: adv.nThreads,
          nGpuLayers: adv.asrNGpuLayers,
        ),
      ]);
      poolA = pools[0];
      poolB = pools[1];

      // Dispatch both transcriptions in parallel.
      final lang = _language == 'auto' ? null : _language;
      final results = await Future.wait([
        poolA.dispatch(
          samples: audioData.samples,
          language: lang,
          translate: adv.translate,
          beamSize: adv.beamSearch ? 5 : 1,
        ),
        poolB.dispatch(
          samples: audioData.samples,
          language: lang,
          translate: adv.translate,
          beamSize: adv.beamSearch ? 5 : 1,
        ),
      ]);
      final segmentsA = results[0];
      final segmentsB = results[1];

      // Save both results to history.
      final embedder = ref.read(crispEmbedProvider).value;
      final abAudioData = ref.read(transcriptionServiceProvider).lastAudioData;
      final saves = await Future.wait([
        historyService.save(
          engineId: 'crispasr',
          segments: segmentsA,
          sourcePath: filePath,
          modelId: _modelName,
          language: _language,
          embedder: embedder,
          audioData: abAudioData,
        ),
        historyService.save(
          engineId: 'crispasr',
          segments: segmentsB,
          sourcePath: filePath,
          modelId: secondModel.name,
          language: _language,
          embedder: embedder,
          audioData: abAudioData,
        ),
      ]);

      // Record A/B result.
      final abResult = AbTestResult(
        modelA: _modelName,
        modelB: secondModel.name,
        audioPath: filePath,
        timestamp: DateTime.now(),
        segmentsA: segmentsA,
        segmentsB: segmentsB,
      );
      Log.instance.i('ab-test', 'completed: ${abResult.overallWinner}');

      if (!mounted) return;
      context.push('/compare?left=${saves[0].id}&right=${saves[1].id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.abTestFailed(e.toString()))),
      );
    } finally {
      // Shut down both pools to free isolates + model memory.
      await Future.wait([
        if (poolA != null) poolA.shutdown(),
        if (poolB != null) poolB.shutdown(),
      ]);
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

  void _selectModelWithDownloadPrompt(ModelInfo model) async {
    if (model.isDownloaded) {
      _selectModel(model.name);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).transcriptionDownloadModel),
        content: Text(AppLocalizations.of(context)
            .downloadModelPrompt(model.displayName, model.size)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).cancel.toUpperCase()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child:
                Text(AppLocalizations.of(context).transcriptionDownload),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _downloadModel(model);
      final refreshedModels =
          await ref.read(modelServiceProvider).getWhisperCppModels();
      final updatedModel =
          refreshedModels.firstWhere((m) => m.name == model.name);
      if (updatedModel.isDownloaded) {
        _selectModel(model.name);
      }
    }
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.stats});
  final PerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    final rtfGood = stats.rtf >= 1.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: rtfGood ? Colors.green.shade50 : Colors.orange.shade50,
        border: Border.all(
          color: rtfGood ? Colors.green.shade200 : Colors.orange.shade200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 12,
          color: rtfGood ? Colors.green.shade900 : Colors.orange.shade900,
        ),
        child: Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _metric('RTF', '${stats.rtf.toStringAsFixed(2)}×',
                rtfGood ? 'faster than real-time' : 'slower than real-time'),
            _metric('Audio', '${stats.audioSeconds.toStringAsFixed(1)} s'),
            _metric('Wall', '${stats.wallSeconds.toStringAsFixed(2)} s'),
            _metric('Words', '${stats.wordCount}'),
            _metric('WPS', stats.wordsPerSecond.toStringAsFixed(1)),
            if (stats.engineId != null) _metric('Engine', stats.engineId!),
            if (stats.modelId != null) _metric('Model', stats.modelId!),
          ],
        ),
      ),
    );
  }

  Widget _metric(String key, String value, [String? hint]) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$key: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value),
        if (hint != null)
          Text(' ($hint)',
              style:
                  const TextStyle(fontStyle: FontStyle.italic, fontSize: 11)),
      ],
    );
  }
}

class _EngineStatusChip extends StatelessWidget {
  const _EngineStatusChip({required this.ready});
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: ready ? Colors.green.shade100 : Colors.orange.shade100,
      label: Text(
        ready ? l.engineReady : l.engineStarting,
        style: TextStyle(
          fontSize: 11,
          color: ready ? Colors.green.shade900 : Colors.orange.shade900,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One row in the source-language picker. The Autocomplete filter
/// matches against both the ISO code and the human-readable
/// (native + English) display name, lowercased — so a user can type
/// "swed", "Schwed" (German UI typing "Swedish" early), "sv", or
/// just "swed" and land on the same item.
class _LangOption {
  _LangOption({required this.code, required this.displayName});
  final String code;
  final String displayName;
  late final String _searchKey =
      '$code ${displayName.toLowerCase()}';
  bool matches(String query) => _searchKey.contains(query);
}
