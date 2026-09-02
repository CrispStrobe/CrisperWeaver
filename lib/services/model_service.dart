// lib/services/model_service.dart (COMPLETE IMPLEMENTATION)
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import '../native/crispasr_import.dart' as crispasr;
import '../native/crispasr_detect_import.dart' as crispasr_detect;

import 'baked_catalog_loader.dart';
import 'ios_helpers.dart';
import '../native/disk_space_import.dart';
import 'log_service.dart';
import 'settings_service.dart';
import 'security_scoped_bookmarks.dart';
import '../utils/platform_utils.dart' as plat;
import 'model_catalog.dart';

export 'model_catalog.dart';

class ModelService {
  final Dio _dio;
  late String _modelsDir;
  final SettingsService _settingsService;
  final Map<String, CancelToken> _activeDowloads = {};

  // Live-probed quants, keyed by model name (same as the hardcoded maps).
  // Merged with the static catalog in getWhisperCppModels().
  final Map<String, ModelDefinition> _discoveredModels = {};
  DateTime? _lastProbeAt;

  /// [dio] is injectable so tests can drive [probeHfRepoForBackend] and
  /// the other HF-API paths through a mock HttpClientAdapter without
  /// touching the network. Production callers omit it and get the
  /// default client.
  ModelService(this._settingsService, {Dio? dio}) : _dio = dio ?? Dio() {
    _configureDio();
  }

  void _configureDio() {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(minutes: 30),
      headers: {
        'User-Agent': 'CrisperWeaver-Flutter/1.0.0',
      },
    );

    // Dio's LogInterceptor dumps 50+ trace lines per HTTP request
    // (every header, every response body). Our own `download start` /
    // `download done` + the DioException catch already capture what we
    // need. Leave it off so the in-app Log view is actually readable.

    // Add interceptors for debugging and retry logic
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        options: const RetryOptions(
          retries: 3,
          retryInterval: Duration(seconds: 2),
        ),
      ),
    );
  }

  Future<void> initialize() async {
    // On web there's no local filesystem — skip all directory setup.
    if (plat.isWeb) {
      _modelsDir = '/web-stub';
      return;
    }
    String baseDirPath;
    // On iOS, prefer the App Group container so model downloads survive
    // `flutter install` (which uninstalls the old build first, wiping
    // the per-app `Documents/` sandbox). Other platforms keep the
    // historical layout — macOS / Linux / Windows / Android either
    // disable the sandbox entirely (macOS) or persist `Documents/`
    // across normal updates.
    //
    // App Group identity matches the one declared in
    // Runner.entitlements + ShareExtension.entitlements, so the Share
    // Extension can also see the models directory if it ever needs to
    // hand audio off without an extra copy.
    if (plat.isIOS) {
      final groupPath =
          await appGroupContainerPath('group.com.crispstrobe.crisperweaver');
      if (groupPath != null && groupPath.isNotEmpty) {
        baseDirPath = groupPath;
        Log.instance.i('model', 'Using App Group container for models',
            fields: {'path': groupPath});
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        baseDirPath = appDir.path;
        Log.instance.w(
            'model', 'App Group resolve failed — falling back to docs dir',
            fields: {'path': appDir.path});
      }
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      baseDirPath = appDir.path;
    }
    _modelsDir = path.join(baseDirPath, 'models');
    await Directory(_modelsDir).create(recursive: true);

    // Default sandbox layout. The custom-models-dir override
    // (settingsService.customModelsDir) is consulted by `_whisperCppDir`
    // on every read, so changing the setting takes effect immediately
    // without re-running initialize().
    await Directory(whisperCppDir()).create(recursive: true);

    // Rename models whose catalogue filename changed under them, so a
    // user who already downloaded the old name keeps the bytes.
    await _migrateLegacyModelFilesOnce();

    // Rewrite persisted model *names* that were renamed in the catalogue,
    // so the stale name doesn't outlive this process.
    _migrateLegacyModelNamesInSettings();

    // Re-register any HF repos the user added by hand in a prior run.
    // Best-effort and memoised — a network failure here never blocks
    // the rest of initialize().
    await _replayUserHfReposOnce();
  }

  /// Guards [_migrateLegacyModelFilesOnce] — `initialize()` runs on
  /// every `getWhisperCppModels()` call, and the rename only ever needs
  /// to happen once per process.
  bool _legacyRenamesDone = false;

  /// Issue #35 — one-time, best-effort rename of on-disk model files
  /// whose catalogue filename changed. Only renames when the legacy
  /// file exists and the current one does not, so a user who has both
  /// (or only the new one) is left alone. Every failure is logged and
  /// swallowed: a model that can't be renamed is simply re-downloadable
  /// under its new name, which is strictly better than blocking startup.
  Future<void> _migrateLegacyModelFilesOnce() async {
    if (_legacyRenamesDone) return;
    _legacyRenamesDone = true;
    final dir = whisperCppDir();
    for (final rename in ModelCatalog.legacyModelFileRenames.entries) {
      try {
        final legacy = File(path.join(dir, rename.key));
        if (!await legacy.exists()) continue;
        final current = File(path.join(dir, rename.value));
        if (await current.exists()) {
          Log.instance.i('model', 'legacy model file superseded — leaving it',
              fields: {'legacy': rename.key, 'current': rename.value});
          continue;
        }
        await legacy.rename(current.path);
        Log.instance.i('model', 'renamed legacy model file',
            fields: {'from': rename.key, 'to': rename.value});
      } catch (e) {
        Log.instance.w('model', 'legacy model rename failed',
            error: e, fields: {'from': rename.key, 'to': rename.value});
      }
    }
  }

  /// Guards [_migrateLegacyModelNamesInSettings] — same story as
  /// [_legacyRenamesDone]: `initialize()` runs on every model-list call.
  bool _legacySettingNamesDone = false;

  /// One-time rewrite of the three persisted model-name settings when
  /// they still point at a name that was renamed in the catalogue
  /// ([ModelCatalog.legacyModelNameAliases]). `lookupDefinition` already
  /// heals a stale name on read; this makes the healing stick, so the
  /// Settings screen's radio list, the model dropdown and anything that
  /// compares the stored name against a catalogue key all agree.
  ///
  /// Idempotent by construction: the target of an alias is never itself
  /// an alias key, so a second pass finds nothing to do. Names with no
  /// alias — including ones deleted outright — are left exactly as they
  /// are; the picker's "not downloaded → auto-switch" path handles those.
  void _migrateLegacyModelNamesInSettings() {
    if (_legacySettingNamesDone) return;
    _legacySettingNamesDone = true;
    const aliases = ModelCatalog.legacyModelNameAliases;

    final asr = _settingsService.defaultModel;
    final asrTarget = aliases[asr];
    if (asrTarget != null) {
      _settingsService.defaultModel = asrTarget;
      Log.instance.i('model', 'migrated legacy defaultModel name',
          fields: {'from': asr, 'to': asrTarget});
    }

    final tts = _settingsService.defaultTtsModel;
    final ttsTarget = aliases[tts];
    if (ttsTarget != null) {
      _settingsService.defaultTtsModel = ttsTarget;
      Log.instance.i('model', 'migrated legacy defaultTtsModel name',
          fields: {'from': tts, 'to': ttsTarget});
    }

    final voice = _settingsService.defaultTtsVoice;
    final voiceTarget = aliases[voice];
    if (voiceTarget != null) {
      _settingsService.defaultTtsVoice = voiceTarget;
      Log.instance.i('model', 'migrated legacy defaultTtsVoice name',
          fields: {'from': voice, 'to': voiceTarget});
    }
  }

  /// Resolved directory where ASR / TTS / companion GGUFs live. When
  /// the user has set `settingsService.customModelsDir` (e.g.
  /// `/Volumes/backups/ai/crispasr-models`) we point straight at that
  /// path so an existing on-disk library is reused without
  /// re-downloading. Otherwise falls back to the historical sandbox
  /// path `<app-docs>/models/whisper_cpp`.
  ///
  /// Synchronous because every caller is downstream of `initialize()`,
  /// which already established `_modelsDir`. The override path is
  /// validated lazily — if the user picks a directory that doesn't
  /// exist yet, this attempts to create it; on failure we fall back
  /// to the sandbox path so model loads never silently break.
  String whisperCppDir() {
    final override = _settingsService.customModelsDir;
    if (override.isNotEmpty) {
      try {
        final dir = Directory(override);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return override;
      } catch (e) {
        Log.instance.w(
            'model', 'customModelsDir unusable, falling back to sandbox',
            error: e, fields: {'attempted': override});
      }
    }
    return path.join(_modelsDir, 'whisper_cpp');
  }

  /// Names to hide from the Models screen because a higher-ranked
  /// catalogue row already offers the exact same file — see
  /// [ModelCatalog.duplicateFileNameEntries].
  Set<String> _duplicateFileNames() => ModelCatalog.duplicateFileNameEntries(
        baked: BakedCatalogLoader.cached,
        discovered: _discoveredModels,
      );

  /// Get available Whisper.cpp models with download status
  Future<List<ModelInfo>> getWhisperCppModels() async {
    await initialize();

    final modelInfos = <ModelInfo>[];
    final suppressed = _duplicateFileNames();

    for (final entry in ModelCatalog.whisperCppModels.entries) {
      final modelDef = entry.value;
      if (suppressed.contains(modelDef.name)) continue;
      final localPath = path.join(whisperCppDir(), modelDef.fileName);
      final isDownloaded = await _isModelDownloaded(localPath, modelDef);

      modelInfos.add(ModelInfo(
        name: modelDef.name,
        displayName: modelDef.displayName,
        size: _formatSize(modelDef.sizeBytes),
        sizeBytes: modelDef.sizeBytes,
        isDownloaded: isDownloaded,
        localPath: isDownloaded ? localPath : null,
        description: modelDef.description,
        modelType: ModelType.whisperCpp,
        quantization: modelDef.quantization,
        backend: modelDef.backend,
        kind: modelDef.kind,
        languages: modelDef.languages,
        recommendedDefault: ModelCatalog.isRecommendedDefault(modelDef.name),
      ));
    }

    // Non-Whisper CrispASR backends. They share the same on-disk directory
    // since each file is just a GGUF blob, but their `backend` field tells
    // the engine which runtime path to dispatch to. We merge in:
    //   * the baked catalog (generated by scripts/bake_models_catalog.dart,
    //     hits the HF API for every BackendRepo at build time so first
    //     launch doesn't wait on the network probe — every release ships
    //     with this in sync),
    //   * the hardcoded core catalog (every backend's default GGUF —
    //     curated display names beat the baked catalog's generic ones),
    //   * the multilingual TTS voicepack catalog (33 vibevoice + kokoro
    //     voices keyed by `<family>-voice-<id>`),
    //   * any quant variants discovered live from HF via _probeRepo
    //     (sizes from those overwrite the baked + hardcoded estimates).
    //
    // Spread order = merge priority (later wins). Live probe beats
    // hardcoded curated entries beats the baked snapshot. That resolves
    // collisions on the *name*; rows that collide on the *file* under
    // two different names are resolved by [_duplicateFileNames].
    final merged = <String, ModelDefinition>{
      ...BakedCatalogLoader.cached,
      ...ModelCatalog.crispasrBackendModels,
      ...ModelCatalog.ttsVoicepacks,
      ..._discoveredModels,
    };
    for (final entry in merged.entries) {
      final modelDef = entry.value;
      if (suppressed.contains(modelDef.name)) continue;
      final localPath = path.join(whisperCppDir(), modelDef.fileName);
      final isDownloaded = await _isModelDownloaded(localPath, modelDef);

      modelInfos.add(ModelInfo(
        name: modelDef.name,
        displayName: modelDef.displayName,
        size: _formatSize(modelDef.sizeBytes),
        sizeBytes: modelDef.sizeBytes,
        isDownloaded: isDownloaded,
        localPath: isDownloaded ? localPath : null,
        description: modelDef.description,
        modelType: ModelType.whisperCpp,
        quantization: modelDef.quantization,
        backend: modelDef.backend,
        kind: modelDef.kind,
        languages: modelDef.languages,
        recommendedDefault: ModelCatalog.isRecommendedDefault(modelDef.name),
      ));
    }

    return modelInfos;
  }

  /// Unified lookup — finds a model by name across every catalog including
  /// quants probed from HuggingFace. Live-probed entries take precedence
  /// so their exact byte-sizes overwrite the rounded catalog estimates.
  ///
  /// When nothing matches, the name is retried once through
  /// [ModelCatalog.legacyModelNameAliases] so a name persisted by an
  /// older release (a stored default, a preset, a queued batch job)
  /// still resolves to whatever the catalogue calls it today. The retry
  /// is deliberately last: a live-probed or catalogued entry under the
  /// legacy name always wins over the alias. Names that were removed
  /// with no successor stay `null` — see the doc on the alias map.
  ModelDefinition? lookupDefinition(String name) {
    final direct = _lookupExact(name);
    if (direct != null) return direct;
    final alias = ModelCatalog.legacyModelNameAliases[name];
    if (alias == null) return null;
    return _lookupExact(alias);
  }

  ModelDefinition? _lookupExact(String name) {
    return _discoveredModels[name] ??
        ModelCatalog.whisperCppModels[name] ??
        ModelCatalog.crispasrBackendModels[name] ??
        ModelCatalog.ttsVoicepacks[name] ??
        BakedCatalogLoader.cached[name];
  }

  /// Persist a backend correction for [name] into the runtime overlay so
  /// the rest of the app (capability gating, list filters, reloads) sees
  /// the real backend rather than a placeholder. Used when the on-disk
  /// GGUF's architecture metadata resolves a concrete backend for an
  /// `auto`-probed / mislabelled entry (#30). No-op when the definition
  /// is unknown or already carries [backend].
  void overrideBackend(String name, String backend) {
    if (backend.isEmpty) return;
    final def = lookupDefinition(name);
    if (def == null || def.backend == backend) return;
    _discoveredModels[name] = def.copyWith(backend: backend);
    Log.instance.i('model', 'backend override from GGUF metadata',
        fields: {'model': name, 'from': def.backend, 'to': backend});
  }

  /// PLAN §5.4 — the recommended "start here" model for [backend], or
  /// `null` when the backend has no curated default (companions,
  /// post-processors, etc.). Resolves the [ModelCatalog.recommendedDefaultModels]
  /// pointer through [lookupDefinition] so callers get the full
  /// definition (with `companions`, size, url) ready for
  /// `downloadWhisperCppModel` — whose existing companion co-download
  /// makes the one-tap fetch a complete, runnable setup.
  ModelDefinition? defaultForBackend(String backend) {
    final name = ModelCatalog.recommendedDefaultModels[backend];
    if (name == null) return null;
    return lookupDefinition(name);
  }

  /// Whether a probe has succeeded at least once in this session.
  bool get hasProbedQuants => _lastProbeAt != null;
  DateTime? get lastQuantProbeAt => _lastProbeAt;

  /// Enumerate every available quant variant in each CrispASR backend's
  /// HuggingFace repo via `GET /api/models/<repo>`. Results are merged
  /// into the model picker on success; on error we fall back to the
  /// hardcoded catalog and log.
  ///
  /// Returns the total number of freshly-discovered ModelDefinitions
  /// (can be 0 if every file was already in the hardcoded catalog).
  Future<QuantProbeResult> refreshAvailableQuants() async {
    int added = 0;
    final failed = <String>[];
    for (final repo in ModelCatalog.backendRepos.values) {
      try {
        final models = await _probeRepo(repo);
        for (final m in models) {
          final existed = _discoveredModels.containsKey(m.name) ||
              ModelCatalog.crispasrBackendModels.containsKey(m.name) ||
              ModelCatalog.whisperCppModels.containsKey(m.name);
          _discoveredModels[m.name] = m;
          if (!existed) added++;
        }
        Log.instance
            .i('model', 'Probed ${repo.repoId}: ${models.length} variants');
      } catch (e, st) {
        failed.add(repo.repoId);
        Log.instance.w('model', 'Quant probe failed for ${repo.repoId}',
            error: e, stack: st);
      }
    }
    _lastProbeAt = DateTime.now();
    return QuantProbeResult(added: added, failedRepos: failed);
  }

  /// Probe an arbitrary HuggingFace repo for .gguf files and register
  /// each as a runtime ModelDefinition tagged with [backend]. The
  /// catalogue-baked [_probeRepo] requires a [BackendRepo] with strict
  /// naming conventions; this looser variant accepts any repo + any
  /// backend the user picks (mirrors `crispasr --hf-repo OWNER/REPO`
  /// on the CLI side).
  ///
  /// Returns the discovered models. Throws on network / 404 / private
  /// repo so the UI can surface a meaningful error to the user.
  Future<List<ModelDefinition>> probeHfRepoForBackend({
    required String repoId,
    required String backend,
    String? displayPrefix,
    bool persist = true,
  }) async {
    final repoIdTrimmed = repoId.trim();
    if (repoIdTrimmed.isEmpty || !repoIdTrimmed.contains('/')) {
      throw ArgumentError('HF repo id must be in OWNER/NAME form');
    }
    final headers = <String, dynamic>{};
    final token = hfToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final url = 'https://huggingface.co/api/models/$repoIdTrimmed?blobs=true';
    final resp =
        await _dio.get<dynamic>(url, options: Options(headers: headers));
    if (resp.data is! Map) {
      throw StateError('HF API returned unexpected payload for $repoIdTrimmed');
    }
    final siblings = ((resp.data as Map)['siblings'] as List?) ?? const [];
    final prefix = displayPrefix ?? repoIdTrimmed.split('/').last;
    final out = <ModelDefinition>[];
    for (final raw in siblings) {
      if (raw is! Map) continue;
      final fname = raw['rfilename'] as String? ?? '';
      // Accept the two extensions CrispASR's session_open can dlopen.
      // .bin is whisper-cpp legacy; .gguf is the modern format.
      if (!fname.endsWith('.gguf') && !fname.endsWith('.bin')) continue;
      final stem = fname.endsWith('.gguf')
          ? fname.substring(0, fname.length - '.gguf'.length)
          : fname.substring(0, fname.length - '.bin'.length);
      final sizeBytes = (raw['size'] as num?)?.toInt() ?? 0;
      // Best-effort quantisation extraction from the file stem —
      // matches q4_k / q5_0 / q8_0 / f16 / fp16 / iq2_xs etc.
      final quantMatch = RegExp(
              r'(q\d[_a-z0-9]*|f16|fp16|f32|bf16|iq\d[_a-z0-9]*)',
              caseSensitive: false)
          .firstMatch(stem);
      final quant = quantMatch?.group(0)?.toLowerCase() ?? 'unknown';
      // Namespace runtime entries by repo so two repos that ship a
      // file with the same stem don't clobber each other in
      // _discoveredModels.
      final nameKey = '${repoIdTrimmed.replaceAll('/', '__')}--$stem';
      final def = ModelDefinition(
        name: nameKey,
        displayName: '$prefix · $stem',
        fileName: fname,
        url: 'https://huggingface.co/$repoIdTrimmed/resolve/main/$fname',
        sizeBytes: sizeBytes,
        checksum: '',
        description: '$prefix · $stem — ${_formatSize(sizeBytes)}',
        quantization: quant,
        backend: backend,
      );
      _discoveredModels[nameKey] = def;
      out.add(def);
    }
    Log.instance.i('model',
        'probeHfRepoForBackend: ${out.length} model(s) from $repoIdTrimmed',
        fields: {'backend': backend});
    // Persist the (repoId, backend) pair so the user's manually-added
    // repo survives a restart — replayed from `initialize()`. Only when
    // the probe actually found something, and not when the replay path
    // itself is re-probing (persist: false) to avoid pointless writes.
    if (persist && out.isNotEmpty) {
      _settingsService.addHfUserRepo(repoIdTrimmed, backend,
          displayPrefix: displayPrefix);
    }
    return out;
  }

  /// Forget a user-added HF repo: drop its runtime ModelDefinitions and
  /// its persisted (repoId, backend) entry. Downloaded files on disk are
  /// left untouched — this only removes the catalogue listing.
  void removeUserHfRepo({required String repoId, required String backend}) {
    final repoIdTrimmed = repoId.trim();
    final keyPrefix = '${repoIdTrimmed.replaceAll('/', '__')}--';
    _discoveredModels.removeWhere(
        (name, def) => name.startsWith(keyPrefix) && def.backend == backend);
    _settingsService.removeHfUserRepo(repoIdTrimmed, backend);
    Log.instance.i('model', 'removeUserHfRepo',
        fields: {'repo': repoIdTrimmed, 'backend': backend});
  }

  // Replay user-added HF repos exactly once per ModelService lifetime.
  // Memoised so concurrent `initialize()` callers await the same probe
  // and we never re-issue the network fan-out.
  Future<void>? _userRepoReplay;

  Future<void> _replayUserHfReposOnce() {
    return _userRepoReplay ??= () async {
      final repos = _settingsService.hfUserRepos;
      if (repos.isEmpty) return;
      Log.instance
          .i('model', 'replaying ${repos.length} user-added HF repo(s)');
      for (final r in repos) {
        final repoId = r['repoId'] ?? '';
        final backend = r['backend'] ?? '';
        if (repoId.isEmpty || backend.isEmpty) continue;
        try {
          await probeHfRepoForBackend(
            repoId: repoId,
            backend: backend,
            displayPrefix: r['displayPrefix'],
            persist: false,
          );
        } catch (e) {
          // Offline / 404 / private — keep the persisted entry so a
          // later online refresh still surfaces it; just skip for now.
          Log.instance.w('model', 'user HF repo replay failed — skipping',
              error: e, fields: {'repo': repoId, 'backend': backend});
        }
      }
    }();
  }

  /// Discover models from CrispASR's built-in C-side registry — no
  /// network, no hardcoding. For every backend the loaded `libcrispasr`
  /// reports as linked (`CrispasrSession.availableBackends()`), this
  /// queries `crispasr_registry_lookup` and merges the canonical entry
  /// into [_discoveredModels].
  ///
  /// Why bother when [refreshAvailableQuants] already probes HF? Two
  /// reasons:
  /// 1. **Offline-safe.** The registry data ships inside libcrispasr;
  ///    works on a plane / locked-down corp network where the HF probe
  ///    times out.
  /// 2. **New-backend discoverability.** When a CrispASR upgrade adds
  ///    a backend the bundled libcrispasr knows about it but
  ///    [backendRepos] doesn't yet — this probe surfaces it without a
  ///    CrisperWeaver code change. Think `/v1/models` on an OpenAI-
  ///    compatible server, but local.
  ///
  /// Returns the number of newly-discovered ModelDefinitions added in
  /// this call (already-known names are refreshed in place but not
  /// counted).
  int refreshFromCrispasrRegistry() {
    int added = 0;
    final List<String> backends;
    try {
      backends = crispasr.CrispasrSession.availableBackends();
    } catch (e, st) {
      Log.instance.w('model', 'availableBackends() threw', error: e, stack: st);
      return 0;
    }
    if (backends.isEmpty) {
      Log.instance.d('model',
          'CrispASR registry probe: no backends reported by libcrispasr');
      return 0;
    }
    for (final backend in backends) {
      // Whisper has its own catalog (whisperCppModels) and the registry
      // entry is the .bin path under ggerganov/whisper.cpp — already
      // covered. Skip to avoid double-listing.
      if (backend == 'whisper') continue;
      crispasr.RegistryEntry? entry;
      try {
        entry = crispasr.registryLookup(backend);
      } catch (e, st) {
        Log.instance.d('model', 'registryLookup threw',
            fields: {'backend': backend}, error: e, stack: st);
        continue;
      }
      if (entry == null || entry.filename.isEmpty || entry.url.isEmpty) {
        continue;
      }
      // Strip the .gguf extension for the keying convention used by the
      // rest of the catalog (e.g. "parakeet-tdt-0.6b-v3-q4_k").
      final fname = entry.filename;
      final dot = fname.lastIndexOf('.');
      final stem = dot > 0 ? fname.substring(0, dot) : fname;
      final name = stem;
      if (_discoveredModels.containsKey(name) ||
          ModelCatalog.crispasrBackendModels.containsKey(name) ||
          ModelCatalog.whisperCppModels.containsKey(name)) {
        continue;
      }
      // Best-effort size parse: registry hands us a string like "~580 MB"
      // or "~4.5 GB". Keep it as the human-readable description and feed
      // a rough byte estimate to the UI so progress bars work.
      final sizeBytes = _parseApproxSize(entry.approxSize);
      _discoveredModels[name] = ModelDefinition(
        name: name,
        displayName: '$stem (CrispASR registry)',
        fileName: fname,
        url: entry.url,
        sizeBytes: sizeBytes,
        checksum: '',
        description:
            'Auto-discovered from CrispASR registry — ${entry.approxSize}',
        quantization: _inferQuant(stem),
        backend: backend,
        kind: ModelCatalog.kindForBackend(backend),
      );
      added++;
    }
    Log.instance.i('model', 'CrispASR registry probe done', fields: {
      'backends': backends.length,
      'added': added,
    });
    return added;
  }

  /// Parse a registry approx-size string like `"~580 MB"` / `"~4.5 GB"`
  /// into a byte count. Returns 0 on parse failure so the UI falls back
  /// to "unknown size" instead of misleading numbers.
  int _parseApproxSize(String s) {
    final m = RegExp(r'~?\s*([\d.]+)\s*(KB|MB|GB|TB)', caseSensitive: false)
        .firstMatch(s);
    if (m == null) return 0;
    final n = double.tryParse(m.group(1)!) ?? 0;
    final unit = m.group(2)!.toUpperCase();
    final mult = switch (unit) {
      'KB' => 1024,
      'MB' => 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      'TB' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    return (n * mult).round();
  }

  /// Pull the quant suffix off a stem like `"parakeet-tdt-0.6b-v3-q4_k"`.
  String _inferQuant(String stem) {
    final m = RegExp(r'-(q[0-9][a-z_0-9]*|f16|f32|bf16)$').firstMatch(stem);
    return m == null ? 'f16' : m.group(1)!;
  }

  /// Derive ISO 639-1 language codes for a voicepack file from its
  /// naming convention — see [ModelCatalog.voicepackLanguages] for the
  /// per-family schemes. Lives on the catalogue rather than here so the
  /// offline bake script (`scripts/bake_models_catalog.dart`) tags baked
  /// voices exactly the way this probe tags live ones (issue #35).
  ///
  /// Returns `[]` when the scheme doesn't recognise the id — the caller
  /// falls back to the BackendRepo's defaultLanguages.
  static List<String> voicepackLanguages(BackendRepo repo, String voiceId) =>
      ModelCatalog.voicepackLanguages(repo.backend, voiceId);

  Future<List<ModelDefinition>> _probeRepo(BackendRepo repo) async {
    final headers = <String, dynamic>{};
    final token = hfToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    // `?blobs=true` surfaces per-file sizes in a stable shape.
    final url = 'https://huggingface.co/api/models/${repo.repoId}?blobs=true';
    final resp =
        await _dio.get<dynamic>(url, options: Options(headers: headers));
    if (resp.data is! Map) return const [];
    final siblings = ((resp.data as Map)['siblings'] as List?) ?? const [];

    final out = <ModelDefinition>[];
    final voicepackPrefix =
        repo.voicepackBaseName == null ? null : '${repo.voicepackBaseName}-';
    for (final raw in siblings) {
      if (raw is! Map) continue;
      final fname = raw['rfilename'] as String? ?? '';
      if (!fname.endsWith(repo.extension)) continue;
      final stem = fname.substring(0, fname.length - repo.extension.length);
      final sizeBytes = (raw['size'] as num?)?.toInt() ?? 0;

      // A file published under a superseded name (the repo keeps both;
      // the bytes are identical). Listing it again would resurrect the
      // duplicate row issue #35 reported — skip it here the same way
      // the bake script does.
      if (ModelCatalog.legacyModelFileRenames.containsKey(fname)) continue;

      // Voicepack file? Stamp as ModelKind.voice, tag with the repo's
      // backend so the synthesize screen's `m.backend == modelDef.backend`
      // filter still groups them under the right main model. The
      // Models-screen language filter also wants per-voicepack
      // language tags so e.g. picking "Deutsch" shows kokoro's
      // German voicepacks (df_eva, dm_bernd, df_victoria, dm_martin)
      // without surfacing every English af_*.
      if (voicepackPrefix != null && stem.startsWith(voicepackPrefix)) {
        final voiceId = stem.substring(voicepackPrefix.length);
        final modelNameKey = '${repo.voicepackBaseName}-$voiceId';
        final voiceLangs = voicepackLanguages(repo, voiceId);
        final resolvedLangs =
            voiceLangs.isEmpty ? repo.defaultLanguages : voiceLangs;
        // Carry the same `[lang=xx]` tag the static voicepack catalogue
        // writes. A live probe overwrites the static entry by name, so
        // without this the Voices language chips (which read the tag)
        // emptied out the moment the HF refresh ran — issue #35.
        final langTag = resolvedLangs.length == 1 && resolvedLangs.first != '*'
            ? ' [lang=${resolvedLangs.first}]'
            : '';
        out.add(ModelDefinition(
          name: modelNameKey,
          displayName: '${repo.displayPrefix} voice — $voiceId',
          fileName: fname,
          url: 'https://huggingface.co/${repo.repoId}/resolve/main/$fname',
          sizeBytes: sizeBytes,
          checksum: '',
          description: '${repo.displayPrefix} voicepack — '
              '${_formatSize(sizeBytes)}$langTag',
          quantization: 'f16',
          backend: repo.backend,
          kind: ModelKind.voice,
          languages: resolvedLangs,
        ));
        continue;
      }

      // Main-model variant? Skip when this is a voicepack-only repo
      // (baseName left empty).
      if (repo.baseName.isEmpty) continue;
      String? quant;
      String modelNameKey;
      if (stem == repo.baseName) {
        quant = 'f16';
        modelNameKey = '${repo.baseName}-f16';
      } else if (stem.startsWith('${repo.baseName}-')) {
        quant = stem.substring(repo.baseName.length + 1);
        modelNameKey = '${repo.baseName}-$quant';
      } else {
        // Skip files that don't follow the expected naming convention.
        continue;
      }
      out.add(ModelDefinition(
        name: modelNameKey,
        displayName: '${repo.displayPrefix} ($quant)',
        fileName: fname,
        url: 'https://huggingface.co/${repo.repoId}/resolve/main/$fname',
        sizeBytes: sizeBytes,
        checksum: '',
        description: '${repo.description} — ${_formatSize(sizeBytes)}',
        quantization: quant,
        backend: repo.backend,
        kind: repo.kind,
        companions: repo.defaultCompanions,
        languages: repo.defaultLanguages,
      ));
    }
    return out;
  }

  /// Whether the user has disabled SHA-1 checksum validation for downloads.
  bool get skipChecksum => _settingsService.skipChecksum;

  /// Hugging Face API token for gated/private repositories.
  String? get hfToken => _settingsService.hfToken;
  set hfToken(String? value) {
    _settingsService.hfToken = value ?? '';
  }

  /// Download a Whisper.cpp model with comprehensive error handling
  Future<bool> downloadWhisperCppModel(
    String modelName, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
  }) async {
    await initialize();

    final modelDef = lookupDefinition(modelName);
    if (modelDef == null) {
      throw ModelException('Unknown Whisper.cpp model: $modelName');
    }

    final modelDir = whisperCppDir();
    final localPath = path.join(modelDir, modelDef.fileName);
    final tempPath = '$localPath.tmp';

    // Check if already downloaded and valid
    if (await _isModelDownloaded(localPath, modelDef)) {
      onProgress?.call(1.0);
      onStatusChange?.call('Model already downloaded');
      return true;
    }

    // Check if download is already in progress
    if (_activeDowloads.containsKey(modelName)) {
      throw ModelException('Download already in progress for $modelName');
    }

    final cancelToken = CancelToken();
    _activeDowloads[modelName] = cancelToken;

    try {
      onStatusChange?.call('Checking available space...');

      // Free-space precheck. `_getAvailableSpace` probes the real
      // filesystem (statvfs on POSIX, GetDiskFreeSpaceExW on Windows)
      // and returns -1 when the platform isn't covered — treat that
      // as "skip the check, let the actual download surface the OS
      // error if we genuinely run out." We don't multiply by 1.2 any
      // more either: the old "* 1.2" buffer over a 5 GB hardcoded
      // ceiling false-positived every model >= 4.2 GB (issue #8).
      // Compare against the raw byte count + a fixed 256 MB headroom
      // so a partially-resumed download still has room to fit a tail
      // chunk + checksum verify.
      final freeSpace = await _getAvailableSpace();
      if (freeSpace >= 0) {
        final needed = modelDef.sizeBytes + 256 * 1024 * 1024;
        if (freeSpace < needed) {
          throw ModelException(
              'Insufficient storage space. Need ${_formatSize(modelDef.sizeBytes)}, '
              'have ${_formatSize(freeSpace)}');
        }
      }

      onStatusChange?.call('Starting download...');
      onProgress?.call(0.0);

      // Download → verify → on a checksum failure delete the bad file
      // and retry ONCE from scratch. A mismatch is almost always a
      // proxy/CDN hiccup that a clean second attempt fixes; telling the
      // user to switch verification off (what the old message did) is
      // terrible advice for a file we *know* is corrupt.
      var attempt = 0;
      while (true) {
        attempt++;
        final dlDone =
            Log.instance.stopwatch('model', msg: 'download done', fields: {
          'name': modelName,
          'url': modelDef.url,
          'expected_bytes': modelDef.sizeBytes,
          'backend': modelDef.backend,
          'quant': modelDef.quantization,
          'target': tempPath,
          'attempt': attempt,
        });
        Log.instance.i('model', 'download start', fields: {
          'name': modelName,
          'url': modelDef.url,
          'expected_bytes': modelDef.sizeBytes,
          'backend': modelDef.backend,
          'quant': modelDef.quantization,
          'attempt': attempt,
        });

        // Download with resume capability
        try {
          await _downloadWithResume(
            modelDef.url,
            tempPath,
            expectedSize: modelDef.sizeBytes,
            onProgress: onProgress,
            onStatusChange: onStatusChange,
            cancelToken: cancelToken,
          );
          int realBytes = 0;
          try {
            realBytes = await File(tempPath).length();
          } catch (e) {
            Log.instance.d('model-svc', 'post-download size probe failed',
                fields: {'path': tempPath, 'err': e.toString()});
          }
          dlDone(extra: {'actual_bytes': realBytes});
        } catch (e) {
          dlDone(error: e);
          rethrow;
        }

        onStatusChange?.call('Verifying download...');
        onProgress?.call(0.95);

        // Verify download
        if (skipChecksum) {
          Log.instance
              .i('model', 'Skipping checksum for $modelName (user override)');
          break;
        }
        if (modelDef.checksum.isEmpty) break;
        if (await _verifyChecksum(tempPath, modelDef.checksum)) break;

        // Bad bytes on disk: resuming would only re-verify the same
        // corruption, so the partial has to go.
        await _cleanupTempFile(tempPath);
        Log.instance
            .w('model', 'Checksum mismatch for $modelName (attempt $attempt)');
        if (attempt >= 2) {
          throw const ModelException(
              'Download failed verification twice and was deleted. '
              'Check your network or proxy; you can retry, or as a last '
              'resort enable "Skip checksum verification" in '
              'Settings → Debugging.');
        }
        onStatusChange?.call('Verification failed — retrying download...');
        onProgress?.call(0.0);
      }

      // Move temp file to final location
      await File(tempPath).rename(localPath);

      // Auto-detect backend from GGUF metadata when the catalogue
      // entry came from a user-added HF repo (backend may be wrong
      // or the user picked "auto"). If detection succeeds and differs
      // from the current entry, patch it in place so subsequent
      // transcription / synthesis calls dispatch to the right engine.
      if (localPath.endsWith('.gguf')) {
        try {
          final detected = crispasr_detect.detectBackendFromGguf(localPath);
          if (detected != null &&
              detected.isNotEmpty &&
              detected != modelDef.backend) {
            Log.instance.i(
                'model',
                'auto-detected backend "$detected" for $modelName '
                    '(was "${modelDef.backend}")');
            final patched = modelDef.copyWith(backend: detected);
            _discoveredModels[modelName] = patched;
          }
        } catch (e, st) {
          // Non-fatal — keep the user-supplied backend.
          Log.instance
              .d('model', 'detectBackendFromGguf skipped', error: e, stack: st);
        }
      }

      // CoreML companion fetch: Whisper backends auto-load a sibling
      // ggml-MODEL-encoder.mlmodelc directory when CrispASR was built
      // with -DCRISPASR_COREML=ON. The companion lives on HF as a zip
      // alongside the .bin; download + unzip if available. Best-effort
      // — failures are logged but don't fail the main download (user
      // still gets the working .bin, just without ANE acceleration).
      // iOS gets the same treatment because the Apple Neural Engine on
      // every modern iPhone is the entire point of the CoreML build.
      if (modelDef.backend == 'whisper' &&
          modelDef.fileName.endsWith('.bin') &&
          (plat.isMacOS || plat.isIOS)) {
        await _maybeFetchCoreMLCompanion(modelDef, modelDir);
      }

      onProgress?.call(1.0);
      onStatusChange?.call('Download complete');
      return true;
    } catch (e) {
      // Cleanup on failure — but only when the bytes on disk are of no
      // further use. An interrupted transfer (cancel, timeout, reset
      // connection) leaves a valid *prefix* of the file behind, and
      // deleting it means the next attempt re-downloads multiple GB
      // from zero. Corrupt files are deleted at the point we detect
      // the corruption (checksum mismatch, over-long file), not here.
      if (_shouldDiscardPartial(e)) {
        await _cleanupTempFile(tempPath);
      } else {
        final kept = await _sizeOrZero(tempPath);
        if (kept > 0) {
          Log.instance.i('model', 'keeping partial download for resume',
              fields: {'path': tempPath, 'bytes': kept});
        }
      }

      if (e is DioException) {
        final resp = e.response;
        Log.instance.e('model', 'DioException during download: ${e.type}');
        if (resp != null) {
          Log.instance.e(
              'model', 'HTTP ${resp.statusCode} for ${e.requestOptions.uri}');
          Log.instance.e('model', 'Headers: ${resp.headers}');
          Log.instance.e('model', 'Body: ${resp.data}');
        } else {
          Log.instance.e('model', 'No response for ${e.requestOptions.uri}');
        }

        if (e.type == DioExceptionType.cancel) {
          throw const ModelException('Download cancelled');
        } else if (e.type == DioExceptionType.connectionTimeout) {
          throw const ModelException(
              'Download timeout. Please check your internet connection.');
        } else if (e.response?.statusCode == 404) {
          throw const ModelException('Model not found on server');
        } else if (e.response?.statusCode == 401) {
          throw const ModelException(
              'Authentication required (401). This model repository is private or gated.');
        } else {
          throw ModelException('Download failed: ${e.message}');
        }
      }

      // Our own exceptions already carry a user-facing message (the
      // model-management screen shows it verbatim), so don't bury it
      // under a "Failed to download model: ModelException: …" prefix.
      if (e is ModelException) rethrow;

      throw ModelException('Failed to download model: $e');
    } finally {
      _activeDowloads.remove(modelName);
    }
  }

  /// Cancel an ongoing download
  Future<void> cancelDownload(String modelName, {ModelType? modelType}) async {
    final cancelToken = _activeDowloads[modelName];
    if (cancelToken != null) {
      cancelToken.cancel('Download cancelled by user');
      _activeDowloads.remove(modelName);
    }
  }

  /// Download with byte-accurate resume.
  ///
  /// Thin wrapper kept for the existing call sites; the protocol lives
  /// in [DownloadEngine] so it can be exercised against a local
  /// HttpServer in tests.
  Future<void> _downloadWithResume(
    String url,
    String savePath, {
    required int expectedSize,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
    CancelToken? cancelToken,
  }) {
    return DownloadEngine(_dio, authToken: hfToken).download(
      url,
      savePath,
      expectedSize: expectedSize,
      onProgress: onProgress,
      onStatusChange: onStatusChange,
      cancelToken: cancelToken,
    );
  }

  /// Whether a failed download attempt should wipe the partial `.tmp`.
  ///
  /// The default is *keep*: everything we write is a byte-exact prefix
  /// of the remote file, so a retry resumes instead of restarting. Only
  /// a hard "this URL will never serve us the file" answer makes the
  /// (potentially multi-GB) partial dead weight worth deleting.
  static bool _shouldDiscardPartial(Object e) {
    if (e is ResumableDownloadException) return false;
    if (e is DioException) {
      final code = e.response?.statusCode ?? 0;
      if (code == 401 || code == 403 || code == 404 || code == 410) {
        return true;
      }
      // cancel / timeouts / connection errors / 5xx: transport trouble,
      // the bytes already on disk stay valid.
      return false;
    }
    if (e is IOException) return false;
    return true;
  }

  static Future<int> _sizeOrZero(String filePath) async {
    try {
      final f = File(filePath);
      if (await f.exists()) return await f.length();
    } catch (_) {
      // Ignore — this is only used for a log line.
    }
    return 0;
  }

  /// Verify file checksum using SHA-1
  Future<bool> _verifyChecksum(String filePath, String expectedChecksum) async {
    if (expectedChecksum.isEmpty) return true;

    final file = File(filePath);
    if (!await file.exists()) return false;

    // Use isolate for CPU-intensive checksum calculation
    final result = await Isolate.run(() async {
      final bytes = await File(filePath).readAsBytes();
      final digest = sha1.convert(bytes);
      return digest.toString();
    });

    return result.toLowerCase() == expectedChecksum.toLowerCase();
  }

  /// Get model path if downloaded and valid
  Future<String?> getWhisperCppModelPath(String modelName) async {
    await initialize();

    final modelDef = lookupDefinition(modelName);
    if (modelDef == null) return null;

    final localPath = path.join(whisperCppDir(), modelDef.fileName);

    if (await _isModelDownloaded(localPath, modelDef)) {
      return localPath;
    }

    return null;
  }

  /// Delete a model with proper cleanup
  Future<bool> deleteModel(String modelName, {ModelType? modelType}) async {
    await initialize();

    // Cancel any ongoing downloads first.
    await cancelDownload(modelName, modelType: modelType);

    final whisperPath = await getWhisperCppModelPath(modelName);
    if (whisperPath != null) {
      await File(whisperPath).delete();
      return true;
    }

    return false;
  }

  /// Per-backend disk-usage breakdown for the Storage screen. Walks
  /// the resolved models directory once and groups files by their
  /// catalogued backend. Files that don't match any catalog entry
  /// (loose downloads, .mlmodelc bundles, leftover .tmp) are bucketed
  /// under "(other)" so users can see them too.
  Future<List<BackendStorage>> getStorageByBackend() async {
    await initialize();
    final dir = Directory(whisperCppDir());
    if (!await dir.exists()) return const [];
    return groupDirByBackend(dir, _buildFilenameBackendMap());
  }

  /// Snapshot of the actual model filesystem used for the next download.
  /// This probes the resolved override path rather than the app-documents
  /// volume, because those can be different disks on desktop.
  Future<ModelStorageHealth> getStorageHealth() async {
    await initialize();
    final directory = whisperCppDir();
    return ModelStorageHealth(
      directory: directory,
      usedBytes: await _getDirectorySize(directory),
      freeBytes: await _getAvailableSpace(),
      isCustomDirectory: _settingsService.customModelsDir.isNotEmpty,
    );
  }

  /// Copy the complete resolved model store to [targetDirectory], verify each
  /// file, then atomically switch future loads/downloads to the new location.
  /// The source is retained until the UI asks for a second, explicit cleanup.
  Future<ModelMoveResult> moveModelsTo(
    String targetDirectory, {
    void Function(double progress)? onProgress,
  }) async {
    await initialize();
    final source = Directory(whisperCppDir()).absolute;
    final target = Directory(targetDirectory).absolute;
    final sourcePath = path.normalize(source.path);
    final targetPath = path.normalize(target.path);
    if (sourcePath == targetPath ||
        path.isWithin(sourcePath, targetPath) ||
        path.isWithin(targetPath, sourcePath)) {
      throw const ModelException(
          'Choose a different folder, not the current folder or one inside it.');
    }
    await target.create(recursive: true);

    final files = <File>[];
    if (await source.exists()) {
      await for (final entity in source.list(recursive: true)) {
        if (entity is File) files.add(entity);
      }
    }
    var totalBytes = 0;
    for (final file in files) {
      totalBytes += await file.length();
    }
    final free = getAvailableDiskSpace(target.path);
    if (free >= 0 && free < totalBytes + 256 * 1024 * 1024) {
      throw ModelException(
          'The selected volume does not have enough free space for the model library.');
    }

    var copiedBytes = 0;
    for (final sourceFile in files) {
      final relative = path.relative(sourceFile.path, from: source.path);
      final destination = File(path.join(target.path, relative));
      await destination.parent.create(recursive: true);
      final sourceSize = await sourceFile.length();
      if (await destination.exists()) {
        if (await destination.length() != sourceSize) {
          throw ModelException(
              'A different file already exists at ${destination.path}.');
        }
      } else {
        final partial = File('${destination.path}.crisper-copy');
        if (await partial.exists()) await partial.delete();
        await sourceFile.copy(partial.path);
        if (await partial.length() != sourceSize) {
          await partial.delete();
          throw ModelException('Copy verification failed for $relative.');
        }
        await partial.rename(destination.path);
      }
      copiedBytes += sourceSize;
      onProgress?.call(totalBytes == 0 ? 1 : copiedBytes / totalBytes);
    }

    _settingsService.customModelsDir = target.path;
    _settingsService.modelsDirAccessLost = false;
    _settingsService.modelsDirBookmark =
        await SecurityScopedBookmarks().create(target.path);
    Log.instance.i('storage', 'model library copied and switched', fields: {
      'source': source.path,
      'target': target.path,
      'files': files.length,
      'bytes': totalBytes,
    });
    return ModelMoveResult(
      sourceDirectory: source.path,
      targetDirectory: target.path,
      fileCount: files.length,
      bytes: totalBytes,
    );
  }

  /// Remove only source files that have an identical verified counterpart in
  /// [targetDirectory]. Used after the user separately confirms cleanup.
  Future<int> removeVerifiedOldModelCopy(
      String sourceDirectory, String targetDirectory) async {
    final source = Directory(sourceDirectory).absolute;
    final target = Directory(targetDirectory).absolute;
    if (path.normalize(target.path) != path.normalize(whisperCppDir()) ||
        path.normalize(source.path) == path.normalize(target.path)) {
      throw const ModelException('Model cleanup paths no longer match.');
    }
    var removed = 0;
    if (!await source.exists()) return 0;
    final directories = <Directory>[];
    await for (final entity in source.list(recursive: true)) {
      if (entity is Directory) {
        directories.add(entity);
        continue;
      }
      if (entity is! File) continue;
      final relative = path.relative(entity.path, from: source.path);
      final counterpart = File(path.join(target.path, relative));
      if (!await counterpart.exists()) continue;
      final size = await entity.length();
      if (await counterpart.length() != size) continue;
      await entity.delete();
      removed += size;
    }
    directories.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final dir in directories) {
      if (await dir.exists() && await dir.list().isEmpty) await dir.delete();
    }
    Log.instance.i('storage', 'removed verified old model copies',
        fields: {'source': source.path, 'bytes': removed});
    return removed;
  }

  /// Pure file-walk + grouping logic, factored out of
  /// [getStorageByBackend] so it can be tested with a temp dir +
  /// fake filenames without spinning up path_provider, an FFI
  /// session, or any of the catalog setup. The returned list is
  /// sorted by descending byte count.
  ///
  /// `byFilename` maps catalog filename → backend label. Anything not
  /// in the map lands in the `(other)` bucket. Trailing `.tmp` is
  /// stripped before lookup so an in-progress download still groups
  /// with its target backend.
  static Future<List<BackendStorage>> groupDirByBackend(
    Directory dir,
    Map<String, String> byFilename,
  ) async {
    final groups = <String, _BackendBytes>{};
    await for (final ent in dir.list(recursive: true)) {
      if (ent is! File) continue;
      final base = path.basename(ent.path);
      final logical =
          base.endsWith('.tmp') ? base.substring(0, base.length - 4) : base;
      final backend = byFilename[logical] ?? '(other)';
      int sz;
      try {
        sz = await ent.length();
      } catch (e) {
        Log.instance.d('model-svc', 'storage size probe failed',
            fields: {'file': ent.path, 'err': e.toString()});
        sz = 0;
      }
      final g = groups.putIfAbsent(backend, () => _BackendBytes());
      g.bytes += sz;
      g.count++;
    }
    return groups.entries
        .map((e) => BackendStorage(
              backend: e.key,
              bytes: e.value.bytes,
              fileCount: e.value.count,
            ))
        .toList()
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
  }

  Map<String, String> _buildFilenameBackendMap() {
    final byFilename = <String, String>{};
    final allDefs = <ModelDefinition>[
      ...BakedCatalogLoader.cached.values,
      ...ModelCatalog.whisperCppModels.values,
      ...ModelCatalog.crispasrBackendModels.values,
      ...ModelCatalog.ttsVoicepacks.values,
      ..._discoveredModels.values,
    ];
    for (final def in allDefs) {
      byFilename[def.fileName] = def.backend;
    }
    return byFilename;
  }

  /// Delete every file in the resolved models directory whose
  /// catalogued backend matches `backend`. Returns the freed byte
  /// count. Cancels any active downloads for that backend first.
  /// Files in the "(other)" bucket aren't touched here — those are
  /// removed via the per-row delete in Model Management.
  Future<int> deleteBackendModels(String backend) async {
    await initialize();
    final dir = Directory(whisperCppDir());
    if (!await dir.exists()) return 0;
    final freed =
        await deleteBackendFilesIn(dir, _buildFilenameBackendMap(), backend);
    Log.instance.i('storage', 'deleted backend models', fields: {
      'backend': backend,
      'freed_bytes': freed,
    });
    return freed;
  }

  /// Pure deletion logic, factored out of [deleteBackendModels] so
  /// it can be tested with a temp dir. Returns the freed byte count.
  /// Errors per-file are swallowed (logged and skipped) so a stuck
  /// inode doesn't abort the rest of the sweep.
  static Future<int> deleteBackendFilesIn(
    Directory dir,
    Map<String, String> byFilename,
    String backend,
  ) async {
    var freed = 0;
    await for (final ent in dir.list(recursive: true)) {
      if (ent is! File) continue;
      final base = path.basename(ent.path);
      final logical =
          base.endsWith('.tmp') ? base.substring(0, base.length - 4) : base;
      final fileBackend = byFilename[logical];
      if (fileBackend != backend) continue;
      try {
        freed += await ent.length();
        await ent.delete();
      } catch (e) {
        Log.instance.w('storage', 'failed to delete ${ent.path}', error: e);
      }
    }
    return freed;
  }

  /// Get total storage used by models
  Future<StorageInfo> getStorageInfo() async {
    await initialize();

    int whisperCppSize = 0;
    final whisperDir = Directory(whisperCppDir());
    if (await whisperDir.exists()) {
      whisperCppSize = await _getDirectorySize(whisperDir.path);
    }

    return StorageInfo(
      whisperCppBytes: whisperCppSize,
      totalBytes: whisperCppSize,
    );
  }

  /// Clear all model cache
  Future<void> clearAllModels() async {
    await initialize();

    // Cancel all downloads first
    for (final entry in _activeDowloads.entries) {
      entry.value.cancel('Clearing all models');
    }
    _activeDowloads.clear();

    final modelsDir = Directory(_modelsDir);
    if (await modelsDir.exists()) {
      await modelsDir.delete(recursive: true);
      await modelsDir.create(recursive: true);

      // Recreate subdirectories
      await Directory(whisperCppDir()).create();
    }
  }

  // Private helper methods

  Future<bool> _isModelDownloaded(
      String localPath, ModelDefinition modelDef) async {
    final file = File(localPath);
    if (!await file.exists()) return false;

    final size = await file.length();

    // Reject only truly suspicious files (empty / near-empty). The
    // hardcoded `sizeBytes` are estimates — frequently off by 30+
    // percent (kokoro listed as 100 MB, real ~135 MB; kokoro voices
    // listed as 1 MB, real ~0.5 MB). The HF probe corrects sizes
    // lazily, so any size-tolerance check that fired BEFORE the
    // probe made downloaded models look "not downloaded yet" on
    // cold launch.
    //
    // We rely on:
    //   * The download path's own 5% / 2 MB integrity check at
    //     download time + atomic rename of the .tmp file. A file
    //     surviving that flow is complete.
    //   * The checksum verification below for models that ship one.
    //
    // So here: just guard against zero-length file (a corrupt
    // rename or interrupted download where the .tmp got promoted
    // anyway).
    if (size < 256) return false;

    // For critical models, verify checksum — unless the user has explicitly
    // opted into skipping verification.
    if (!skipChecksum &&
        modelDef.checksum.isNotEmpty &&
        modelDef.sizeBytes > 100 * 1024 * 1024) {
      return await _verifyChecksum(localPath, modelDef.checksum);
    }

    return true;
  }

  Future<void> _cleanupTempFile(String tempPath) async {
    try {
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  /// Best-effort download of the CoreML encoder companion for a Whisper
  /// model. URL convention is upstream's
  ///   `ggerganov/whisper.cpp/resolve/main/<basename>-encoder.mlmodelc.zip`
  /// where basename is the .bin filename without the extension. Skips
  /// silently when the zip 404s (most quantised whisper models don't
  /// have one) or when the destination .mlmodelc directory already
  /// exists. Unzips into the same dir as the .bin so libwhisper picks
  /// it up on first transcribe.
  Future<void> _maybeFetchCoreMLCompanion(
      ModelDefinition modelDef, String modelDir) async {
    final stem = modelDef.fileName.endsWith('.bin')
        ? modelDef.fileName.substring(0, modelDef.fileName.length - 4)
        : modelDef.fileName;
    final mlmodelcDir =
        Directory(path.join(modelDir, '$stem-encoder.mlmodelc'));
    if (await mlmodelcDir.exists()) {
      Log.instance
          .d('coreml', 'CoreML companion already present for ${modelDef.name}');
      return;
    }
    final zipUrl =
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$stem-encoder.mlmodelc.zip';
    final zipPath = path.join(modelDir, '$stem-encoder.mlmodelc.zip');
    try {
      Log.instance
          .i('coreml', 'fetching CoreML companion', fields: {'url': zipUrl});
      final resp = await _dio.download(zipUrl, zipPath);
      if (resp.statusCode != 200) {
        Log.instance.d(
            'coreml', 'CoreML companion not on HF (status ${resp.statusCode})');
        await File(zipPath).delete().catchError((_) => File(zipPath));
        return;
      }
      // Unzip alongside the .bin via the existing `archive` dep.
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        final outPath = path.join(modelDir, f.name);
        if (f.isFile) {
          await File(outPath).create(recursive: true);
          await File(outPath).writeAsBytes(f.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      await File(zipPath).delete();
      Log.instance.i('coreml', 'CoreML companion installed',
          fields: {'dir': mlmodelcDir.path});
    } catch (e, st) {
      // 404 / network blip / decompression failure all funnel here.
      // CoreML is an optional accelerator; whisper falls back to ggml
      // automatically when the .mlmodelc isn't present.
      Log.instance
          .d('coreml', 'CoreML companion fetch skipped', error: e, stack: st);
      try {
        await File(zipPath).delete();
      } catch (e) {
        Log.instance.d('coreml', 'CoreML zip cleanup failed',
            fields: {'path': zipPath, 'err': e.toString()});
      }
    }
  }

  Future<int> _getAvailableSpace() async {
    // Real free-space probe — statvfs on POSIX, GetDiskFreeSpaceExW
    // on Windows. Returns -1 when the platform-specific call fails
    // or isn't available; the caller treats that as "skip the
    // precheck and let the actual download fail if we run out of
    // disk." Fixes issue #8: the previous hardcoded 5 GB constant
    // false-positived every model >= 4.2 GB.
    try {
      final dir = whisperCppDir();
      return getAvailableDiskSpace(dir);
    } catch (e, st) {
      Log.instance.w('model', 'free-space probe threw', error: e, stack: st);
      return -1;
    }
  }

  Future<int> _getDirectorySize(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return 0;

    int totalSize = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          totalSize += stat.size;
        } catch (e) {
          // Skip files that can't be accessed
        }
      }
    }

    return totalSize;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _BackendBytes {
  int bytes = 0;
  int count = 0;
}

/// Raised when a transfer stopped early but everything already written
/// is a byte-exact prefix of the remote file — i.e. the partial on disk
/// is worth keeping because the next attempt resumes from
/// [bytesOnDisk] instead of restarting from zero.
class ResumableDownloadException extends ModelException {
  const ResumableDownloadException(super.message, {required this.bytesOnDisk});

  /// How many valid bytes are sitting in the `.tmp` file.
  final int bytesOnDisk;
}

/// One parsed `Content-Range: bytes START-END/TOTAL` header.
class _ContentRange {
  const _ContentRange(this.start, this.end, this.total);
  final int start;
  final int end;

  /// `null` when the server sent `*` for the total.
  final int? total;
}

/// Streamed HTTP downloader with byte-accurate resume.
///
/// Split out of [ModelService] so the resume protocol can be driven
/// against a local `HttpServer` in tests without a model catalogue, a
/// settings store, or Flutter bindings.
///
/// Why this exists at all: the previous implementation sent a
/// `Range: bytes=N-` header and then handed the URL to `Dio.download`,
/// which truncates the destination and writes the response from byte 0.
/// The server answered `206` with only the tail, so the file ended up
/// *missing its first N bytes* — a plausible-looking file that failed
/// checksum verification (issue #35). Streaming the body ourselves is
/// the only way to append to what is already on disk.
class DownloadEngine {
  DownloadEngine(this.dio, {this.authToken});

  final Dio dio;

  /// Optional Hugging Face token, sent as `Authorization: Bearer …`.
  final String? authToken;

  /// ~4 Hz: fast enough to look live, slow enough that a multi-GB
  /// download doesn't stutter the UI thread with thousands of rebuilds.
  static const int _progressIntervalMs = 250;

  DateTime? _speedStart;
  int _speedStartBytes = 0;

  /// Fetch [url] into [savePath], resuming from whatever is already
  /// there.
  ///
  /// [expectedSize] is only the catalogue's estimate: it is used for
  /// progress and the completeness check *solely* when the server
  /// declines to tell us the real length.
  Future<void> download(
    String url,
    String savePath, {
    required int expectedSize,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
    CancelToken? cancelToken,
  }) async {
    _speedStart = null;
    _speedStartBytes = 0;

    final restart = await _attempt(
      url,
      savePath,
      expectedSize: expectedSize,
      allowResume: true,
      onProgress: onProgress,
      onStatusChange: onStatusChange,
      cancelToken: cancelToken,
    );

    if (restart) {
      // The server couldn't (or wouldn't) continue from our offset and
      // the partial has been deleted. One clean pass from byte 0; the
      // return value is ignored because a no-Range request can't ask
      // for another restart.
      _speedStart = null;
      _speedStartBytes = 0;
      await _attempt(
        url,
        savePath,
        expectedSize: expectedSize,
        allowResume: false,
        onProgress: onProgress,
        onStatusChange: onStatusChange,
        cancelToken: cancelToken,
      );
    }
  }

  /// One HTTP attempt. Returns `true` when the caller must retry from
  /// scratch (the partial has already been removed in that case).
  Future<bool> _attempt(
    String url,
    String savePath, {
    required int expectedSize,
    required bool allowResume,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
    CancelToken? cancelToken,
  }) async {
    final file = File(savePath);
    var partialBytes = 0;
    if (allowResume && await file.exists()) {
      partialBytes = await file.length();
    }
    if (partialBytes > 0) {
      onStatusChange?.call('Resuming download...');
    }

    final headers = <String, dynamic>{
      'Accept': '*/*',
      // Never let a proxy hand us a compressed body: byte offsets are
      // meaningless once the transfer is encoded, and offsets are the
      // whole basis of resume.
      'Accept-Encoding': 'identity',
    };
    if (partialBytes > 0) {
      headers['Range'] = 'bytes=$partialBytes-';
    }
    final token = authToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    Log.instance.d('model', 'download request', fields: {
      'url': url,
      'resume_from': partialBytes,
      'ranged': partialBytes > 0,
    });

    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        // 416 isn't an error here: it means our partial is at or past
        // the end of the resource, which we resolve by reading
        // Content-Range rather than by blowing up.
        validateStatus: (s) => s != null && ((s >= 200 && s < 300) || s == 416),
      ),
      cancelToken: cancelToken,
    );

    final status = response.statusCode ?? 0;
    final body = response.data;
    if (body == null) {
      throw ModelException('Download failed: empty response (HTTP $status)');
    }

    final contentRange =
        response.headers.value(HttpHeaders.contentRangeHeader)?.trim();

    if (status == 416) {
      await _discard(body);
      final total = _totalFromContentRange(contentRange);
      if (total != null && partialBytes == total) {
        // Everything was already fetched by an earlier run that died
        // before the checksum step. Nothing left to do.
        Log.instance.i('model', 'resume: file already complete',
            fields: {'bytes': partialBytes});
        return false;
      }
      Log.instance.w('model', 'server rejected our range (416) — restarting',
          fields: {'have': partialBytes, 'content_range': contentRange ?? ''});
      await _deleteQuietly(file);
      return true;
    }

    int startOffset;
    int? serverTotal;
    if (status == 206) {
      final range = _parseContentRange(contentRange);
      if (range == null || range.start != partialBytes) {
        // The tail we're being offered doesn't line up with the bytes we
        // have. Splicing it on would corrupt the file, so start over.
        Log.instance.w('model', 'Content-Range mismatch — restarting',
            fields: {
              'have': partialBytes,
              'content_range': contentRange ?? '(none)',
            });
        await _discard(body);
        await _deleteQuietly(file);
        return true;
      }
      startOffset = partialBytes;
      serverTotal = range.total;
    } else {
      // 200 (or any other 2xx): the server ignored the Range header and
      // is sending the whole resource. The partial must be dropped or
      // we'd splice two copies together.
      if (partialBytes > 0) {
        Log.instance.w(
            'model', 'server ignored Range (HTTP $status) — restarting at 0',
            fields: {'discarded': partialBytes});
      }
      startOffset = 0;
      final len = response.headers.value(HttpHeaders.contentLengthHeader);
      final parsed = len == null ? null : int.tryParse(len.trim());
      serverTotal = (parsed != null && parsed > 0) ? parsed : null;
    }

    // Trust the server's length over the catalogue's estimate; fall back
    // to the estimate only when the server told us nothing (chunked
    // transfer, no Content-Length).
    final totalForProgress =
        serverTotal ?? (expectedSize > 0 ? expectedSize : 0);

    final sink = file.openWrite(
        mode: startOffset > 0 ? FileMode.append : FileMode.write);
    var sinkClosed = false;
    Future<void> closeSink() async {
      if (sinkClosed) return;
      sinkClosed = true;
      try {
        await sink.flush();
      } catch (_) {
        // Nothing useful to do — the length check below is the arbiter.
      }
      try {
        await sink.close();
      } catch (_) {
        // Same.
      }
    }

    var received = 0;
    var lastTick = 0;
    try {
      // addStream applies backpressure (the socket pauses while the disk
      // catches up), which plain `sink.add` in a loop would not.
      await sink.addStream(body.stream.map((chunk) {
        received += chunk.length;
        final onDisk = startOffset + received;
        final now = DateTime.now();
        final ms = now.millisecondsSinceEpoch;
        if (ms - lastTick >= _progressIntervalMs) {
          lastTick = ms;
          if (totalForProgress > 0) {
            onProgress?.call((onDisk / totalForProgress).clamp(0.0, 1.0));
          }
          final doneMb = onDisk / (1024 * 1024);
          final totalMb = totalForProgress / (1024 * 1024);
          onStatusChange?.call('Downloaded ${doneMb.toStringAsFixed(1)} MB '
              'of ${totalMb.toStringAsFixed(1)} MB (${_speed(onDisk, now)})');
        }
        return chunk;
      }));
      await closeSink();
    } catch (e) {
      // A cancelled or broken transfer: flush what made it through so the
      // file stays a valid prefix and a later call can resume from it.
      await closeSink();
      Log.instance.w('model', 'download stream failed', fields: {
        'bytes_on_disk': await _lengthOrZero(file),
        'err': e.toString(),
      });
      rethrow;
    } finally {
      await closeSink();
    }

    final finalSize = await _lengthOrZero(file);

    if (serverTotal != null) {
      // The server told us exactly how big the file is, so "close
      // enough" is not a thing: any shortfall is a truncated transfer.
      if (finalSize == serverTotal) return false;
      if (finalSize > serverTotal) {
        await _deleteQuietly(file);
        throw ModelException(
            'Download corrupt: got $finalSize bytes for a $serverTotal byte '
            'file. The partial file was deleted — please retry.');
      }
      throw ResumableDownloadException(
        'Download interrupted at $finalSize of $serverTotal bytes '
        '(${_humanBytes(serverTotal - finalSize)} still missing). The partial '
        'file was kept — retrying resumes from $finalSize bytes.',
        bytesOnDisk: finalSize,
      );
    }

    // No server-side length. Fall back to the catalogue estimate, which
    // is rounded to the nearest MB, so tolerate a 5% (or 2 MB, whichever
    // is larger) undershoot before calling the download incomplete.
    if (expectedSize > 0 && finalSize < expectedSize) {
      final diff = expectedSize - finalSize;
      final tolerance = (expectedSize * 0.05).ceil();
      final absTolerance =
          tolerance > 2 * 1024 * 1024 ? tolerance : 2 * 1024 * 1024;
      if (diff > absTolerance) {
        throw ResumableDownloadException(
          'Download incomplete. Expected at least $expectedSize bytes, got '
          '$finalSize bytes. The partial file was kept — retrying resumes '
          'from $finalSize bytes.',
          bytesOnDisk: finalSize,
        );
      }
      Log.instance.w(
        'model',
        'Download finished at $finalSize bytes, expected $expectedSize '
            '(diff ${_humanBytes(diff)}); server sent no length, accepting '
            'within tolerance.',
      );
    }
    return false;
  }

  String _speed(int bytesDownloaded, DateTime now) {
    if (_speedStart == null) {
      _speedStart = now;
      _speedStartBytes = bytesDownloaded;
      return '';
    }
    final elapsedMs = now.difference(_speedStart!).inMilliseconds;
    if (elapsedMs <= 0) return '';
    final speed = (bytesDownloaded - _speedStartBytes) * 1000 / elapsedMs;
    if (speed < 1024) return '${speed.toStringAsFixed(0)} B/s';
    if (speed < 1024 * 1024) {
      return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  /// Drop a response body we've decided not to write, closing the
  /// socket instead of draining (and paying for) the whole tail.
  static Future<void> _discard(ResponseBody body) async {
    try {
      await body.stream.listen(null).cancel();
    } catch (_) {
      // Best effort — the connection dies with the response either way.
    }
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort.
    }
  }

  static Future<int> _lengthOrZero(File f) async {
    try {
      if (await f.exists()) return await f.length();
    } catch (_) {
      // Best effort.
    }
    return 0;
  }

  /// `bytes 1024-4095/4096` → start 1024, end 4095, total 4096.
  static _ContentRange? _parseContentRange(String? header) {
    if (header == null || header.isEmpty) return null;
    final m = RegExp(r'bytes\s+(\d+)\s*-\s*(\d+)\s*/\s*(\d+|\*)',
            caseSensitive: false)
        .firstMatch(header);
    if (m == null) return null;
    final start = int.tryParse(m.group(1)!);
    final end = int.tryParse(m.group(2)!);
    if (start == null || end == null) return null;
    final rawTotal = m.group(3)!;
    return _ContentRange(
        start, end, rawTotal == '*' ? null : int.tryParse(rawTotal));
  }

  /// Total from either form of the header, including the `bytes * /N`
  /// shape a 416 uses.
  static int? _totalFromContentRange(String? header) {
    if (header == null || header.isEmpty) return null;
    final m = RegExp(r'/\s*(\d+)\s*$').firstMatch(header);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// Retry interceptor for Dio
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final RetryOptions options;

  RetryInterceptor({required this.dio, required this.options});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = RetryOptions.fromExtra(err.requestOptions) ?? options;

    if (extra.retries <= 0) {
      return handler.next(err);
    }

    if (err.type == DioExceptionType.cancel) {
      return handler.next(err);
    }

    await Future<void>.delayed(extra.retryInterval);

    final requestOptions = err.requestOptions;
    requestOptions.extra[RetryOptions.extraKey] =
        extra.copyWith(retries: extra.retries - 1);

    try {
      final response = await dio.fetch<dynamic>(requestOptions);
      return handler.resolve(response);
    } catch (e) {
      return handler.next(err);
    }
  }
}

class RetryOptions {
  static const String extraKey = 'retry_options';

  final int retries;
  final Duration retryInterval;

  const RetryOptions({
    required this.retries,
    required this.retryInterval,
  });

  static RetryOptions? fromExtra(RequestOptions request) {
    return request.extra[extraKey] as RetryOptions?;
  }

  RetryOptions copyWith({int? retries, Duration? retryInterval}) {
    return RetryOptions(
      retries: retries ?? this.retries,
      retryInterval: retryInterval ?? this.retryInterval,
    );
  }
}
