import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/platform_utils.dart' as plat;
import 'package:shared_preferences/shared_preferences.dart';
import '../engines/engine_factory.dart';
import '../services/hotkey_service.dart' show HotkeyAction;
import '../services/log_service.dart';

/// Central service for managing application settings and persistence.
class SettingsService {
  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  // --- Transcription Settings ---

  EngineType get preferredEngine {
    final id = _prefs.getString('preferred_engine');
    return EngineType.values.firstWhere(
      (e) => e.id == id,
      orElse: () => EngineFactory.getRecommendedEngine(),
    );
  }

  set preferredEngine(EngineType type) {
    Log.instance.d('settings', 'Saving preferredEngine: ${type.id}');
    _prefs.setString('preferred_engine', type.id);
  }

  String get defaultModel => _prefs.getString('default_model') ?? 'base';
  set defaultModel(String model) {
    Log.instance.d('settings', 'Saving defaultModel: $model');
    _prefs.setString('default_model', model);
  }

  String get defaultBackend => _prefs.getString('default_backend') ?? 'whisper';
  set defaultBackend(String backend) {
    Log.instance.d('settings', 'Saving defaultBackend: $backend');
    _prefs.setString('default_backend', backend);
  }

  String get defaultLanguage => _prefs.getString('default_language') ?? 'auto';
  set defaultLanguage(String lang) {
    Log.instance.d('settings', 'Saving defaultLanguage: $lang');
    _prefs.setString('default_language', lang);
  }

  bool get autoDetectLanguage => _prefs.getBool('auto_detect_language') ?? true;
  set autoDetectLanguage(bool value) {
    Log.instance.d('settings', 'Saving autoDetectLanguage: $value');
    _prefs.setBool('auto_detect_language', value);
  }

  bool get enableWordTimestamps =>
      _prefs.getBool('enable_word_timestamps') ?? false;
  set enableWordTimestamps(bool value) {
    Log.instance.d('settings', 'Saving enableWordTimestamps: $value');
    _prefs.setBool('enable_word_timestamps', value);
  }

  // --- Audio Settings ---

  double get audioQuality => _prefs.getDouble('audio_quality') ?? 0.8;
  set audioQuality(double value) {
    Log.instance.d('settings', 'Saving audioQuality: $value');
    _prefs.setDouble('audio_quality', value);
  }

  bool get keepAudioFiles => _prefs.getBool('keep_audio_files') ?? false;
  set keepAudioFiles(bool value) {
    Log.instance.d('settings', 'Saving keepAudioFiles: $value');
    _prefs.setBool('keep_audio_files', value);
  }

  // --- Diarization Settings ---

  bool get enableDiarizationByDefault =>
      _prefs.getBool('enable_diarization_by_default') ?? false;
  set enableDiarizationByDefault(bool value) {
    Log.instance.d('settings', 'Saving enableDiarizationByDefault: $value');
    _prefs.setBool('enable_diarization_by_default', value);
  }

  // --- App Locale (i18n) ---

  String? get appLocale => _prefs.getString('app_locale');
  set appLocale(String? locale) {
    Log.instance.d('settings', 'Saving appLocale: $locale');
    if (locale == null || locale.isEmpty) {
      _prefs.remove('app_locale');
    } else {
      _prefs.setString('app_locale', locale);
    }
  }

  // --- Developer / Debug Settings ---

  LogLevel get logLevel {
    final levelName = _prefs.getString('log_level');
    return LogLevel.values.firstWhere(
      (l) => l.name == levelName,
      orElse: () => LogLevel.info,
    );
  }

  set logLevel(LogLevel level) {
    Log.instance.d('settings', 'Saving logLevel: ${level.name}');
    _prefs.setString('log_level', level.name);
  }

  bool get logToFile => _prefs.getBool('log_to_file') ?? false;
  set logToFile(bool value) {
    Log.instance.d('settings', 'Saving logToFile: $value');
    _prefs.setBool('log_to_file', value);
  }

  bool get skipChecksum => _prefs.getBool('skip_checksum') ?? false;
  set skipChecksum(bool value) {
    Log.instance.d('settings', 'Saving skipChecksum: $value');
    _prefs.setBool('skip_checksum', value);
  }

  /// Bypass the transcription memory pre-flight (§OOM guard).
  ///
  /// The guard refuses a decode whose projected footprint exceeds 80% of
  /// system RAM, because on the unchunked session-backend path that ends in
  /// a native abort or — on Windows — a whole-desktop freeze with no log
  /// (issues #33, #34). The estimate is calibrated from one measured backend
  /// and is deliberately pessimistic, so this exists for the user whose
  /// machine or model it reads wrong. Off by default: the failure it
  /// prevents costs a reboot.
  bool get ignoreMemoryPreflight =>
      _prefs.getBool('ignore_memory_preflight') ?? false;
  set ignoreMemoryPreflight(bool value) {
    Log.instance.d('settings', 'Saving ignoreMemoryPreflight: $value');
    _prefs.setBool('ignore_memory_preflight', value);
  }

  String get hfToken => _prefs.getString('hf_token') ?? '';
  set hfToken(String token) {
    Log.instance
        .d('settings', 'Saving hfToken: ${token.isNotEmpty ? "SET" : "EMPTY"}');
    _prefs.setString('hf_token', token);
  }

  /// User-added HuggingFace repos for the "Add from HuggingFace repo"
  /// direct-download flow. Persisted as a JSON list of
  /// `{repoId, backend, displayPrefix?}` maps so they survive a restart;
  /// ModelService replays each through `probeHfRepoForBackend` on
  /// initialize. Entries are keyed by the (repoId, backend) pair.
  List<Map<String, String>> get hfUserRepos {
    final raw = _prefs.getString('hf_user_repos');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) =>
              m.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
          .where((m) =>
              (m['repoId'] ?? '').isNotEmpty && (m['backend'] ?? '').isNotEmpty)
          .toList();
    } catch (e) {
      Log.instance
          .w('settings', 'hfUserRepos decode failed — ignoring', error: e);
      return const [];
    }
  }

  set hfUserRepos(List<Map<String, String>> repos) {
    _prefs.setString('hf_user_repos', jsonEncode(repos));
  }

  /// Add or replace a user HF repo entry (idempotent on the
  /// repoId+backend key).
  void addHfUserRepo(String repoId, String backend, {String? displayPrefix}) {
    final list = List<Map<String, String>>.from(hfUserRepos)
      ..removeWhere((m) => m['repoId'] == repoId && m['backend'] == backend);
    final entry = <String, String>{'repoId': repoId, 'backend': backend};
    if (displayPrefix != null && displayPrefix.isNotEmpty) {
      entry['displayPrefix'] = displayPrefix;
    }
    list.add(entry);
    hfUserRepos = list;
  }

  /// Forget a previously-added user HF repo.
  void removeHfUserRepo(String repoId, String backend) {
    final list = List<Map<String, String>>.from(hfUserRepos)
      ..removeWhere((m) => m['repoId'] == repoId && m['backend'] == backend);
    hfUserRepos = list;
  }

  /// Override directory for model GGUFs / .bin files. Empty / null
  /// means "use the platform-default `<app-docs>/models/whisper_cpp`".
  /// Useful for users who keep a shared library on an external disk
  /// (e.g. `/Volumes/backups/ai/crispasr-models`) and don't want
  /// CrisperWeaver to re-download every quant into its sandbox.
  ///
  /// ModelService.getModelsDirOverride reads this on every call so the
  /// effect is live — change the setting and the next download lands
  /// at the new path without an app restart.
  String get customModelsDir => _prefs.getString('custom_models_dir') ?? '';
  set customModelsDir(String dir) {
    Log.instance.d(
        'settings', 'Saving customModelsDir: ${dir.isEmpty ? "DEFAULT" : dir}');
    _prefs.setString('custom_models_dir', dir);
  }

  String? get modelsDirBookmark => _prefs.getString('models_dir_bookmark');
  set modelsDirBookmark(String? value) {
    if (value == null || value.isEmpty) {
      _prefs.remove('models_dir_bookmark');
    } else {
      _prefs.setString('models_dir_bookmark', value);
    }
  }

  bool get modelsDirAccessLost =>
      _prefs.getBool('models_dir_access_lost') ?? false;
  set modelsDirAccessLost(bool value) =>
      _prefs.setBool('models_dir_access_lost', value);

  /// Reorder a batch queue so jobs with the same
  /// (backend, modelId, language) run consecutively, sparing the
  /// expensive session swap between them. Stable — preserves the
  /// enqueue order within each bundle. Default off so the user's
  /// drag-and-drop order is honoured verbatim by the drain loop.
  /// §5.23 Q1 grouping sub-bullet.
  bool get groupBatchByBackend =>
      _prefs.getBool('group_batch_by_backend') ?? false;
  set groupBatchByBackend(bool value) {
    Log.instance.d('settings', 'Saving groupBatchByBackend: $value');
    _prefs.setBool('group_batch_by_backend', value);
  }

  /// How many transcription jobs the drain loop runs in pipeline-
  /// parallel mode (§5.23 Q2). Stored as 1..[maxConcurrentLimit].
  ///
  /// v1 (shipped): "pipeline parallelism" — slider > 1 enables
  /// async audio prefetch of the next queued file in a worker
  /// isolate, overlapping its decode + Mel computation with the
  /// current file's GPU transcription. One session, one model
  /// copy in RAM, real-world speedup of 5–15% on batches of
  /// compressed audio (mp3 / m4a / opus) where decode is a non-
  /// trivial slice of total wall time.
  ///
  /// v2 (deferred — see PLAN §5.23): true N-way session pool with
  /// per-isolate `CrispasrSession` instances. Memory cost is
  /// N × model size; gated behind a future "I have RAM to burn"
  /// affordance.
  int get maxConcurrentTranscriptions {
    final raw = _prefs.getInt('max_concurrent_transcriptions') ?? 1;
    if (raw < 1) return 1;
    final cap = maxConcurrentTranscriptionsLimit;
    return raw > cap ? cap : raw;
  }

  set maxConcurrentTranscriptions(int value) {
    final cap = maxConcurrentTranscriptionsLimit;
    final clamped = value < 1 ? 1 : (value > cap ? cap : value);
    Log.instance.d('settings',
        'Saving maxConcurrentTranscriptions: $clamped (requested $value, cap $cap)');
    _prefs.setInt('max_concurrent_transcriptions', clamped);
  }

  /// Per-platform upper bound for the concurrent-transcriptions
  /// slider. iOS caps at 2 because of the tight memory budget on
  /// even the largest iPhone (8 GB); desktop/Android caps at 4
  /// because beyond that Metal queue contention dominates and the
  /// marginal speedup tapers.
  int get maxConcurrentTranscriptionsLimit => plat.isIOS ? 2 : 4;

  /// How many *true* parallel session workers the drain loop spawns
  /// (§5.23 Q2 v2). 1 = no pool (the v1 prefetch is what the other
  /// slider controls). 2+ spins up N persistent worker isolates,
  /// each holding its own CrispasrSession against the same model.
  /// Real GPU + decoder concurrency; cost is N × model size in RAM.
  ///
  /// At batch start the drain loop runs `MemoryEstimator.estimate`
  /// against the active model + this slider value, and clamps the
  /// actual worker count down to what fits in
  /// `physicalMemory × 50% − 400 MB`. The user-set value is what's
  /// requested; the actual spawn count is what's affordable.
  int get maxConcurrentSessions {
    final raw = _prefs.getInt('max_concurrent_sessions') ?? 1;
    if (raw < 1) return 1;
    final cap = maxConcurrentSessionsLimit;
    return raw > cap ? cap : raw;
  }

  set maxConcurrentSessions(int value) {
    final cap = maxConcurrentSessionsLimit;
    final clamped = value < 1 ? 1 : (value > cap ? cap : value);
    Log.instance.d('settings',
        'Saving maxConcurrentSessions: $clamped (requested $value, cap $cap)');
    _prefs.setInt('max_concurrent_sessions', clamped);
  }

  /// Same per-platform shape as the prefetch slider — iOS caps at 2
  /// (very tight memory), everything else at 4 (beyond which Metal
  /// queue contention dominates). The pre-flight check may clamp
  /// lower at runtime when the chosen model is too big.
  int get maxConcurrentSessionsLimit => plat.isIOS ? 2 : 4;

  // --- §5.1.6 v2 Cloud-LLM cleanup (BYOK) ---

  /// OpenAI-compatible /v1/chat/completions endpoint. Empty
  /// means "feature off"; the Tidy dialog hides the LLM-pass
  /// toggle when this is empty. Defaults to OpenAI's public
  /// endpoint to nudge users into a known-good shape; can be
  /// pointed at any other compatible server (Anthropic via
  /// proxy, local llama-server, OpenRouter, Groq, etc.).
  String get cloudLlmApiUrl => _prefs.getString('cloud_llm_api_url') ?? '';
  set cloudLlmApiUrl(String url) {
    Log.instance
        .d('settings', 'Saving cloudLlmApiUrl: ${url.isEmpty ? "EMPTY" : url}');
    _prefs.setString('cloud_llm_api_url', url);
  }

  // --- HF Space / Cloud ASR ---
  static const _defaultHfSpaceUrl = 'https://cstr-crispasr.hf.space';
  String get hfSpaceUrl =>
      _prefs.getString('hf_space_url') ?? _defaultHfSpaceUrl;
  set hfSpaceUrl(String url) {
    _prefs.setString('hf_space_url', url);
  }

  /// API key — pasted by the user. Logged only as SET/EMPTY
  /// to avoid leaking into telemetry. Stored in
  /// SharedPreferences (platform-default; encrypted on iOS via
  /// the keychain integration, plain JSON in app-support on
  /// other platforms). For real secret storage we'd reach for
  /// flutter_secure_storage — out of scope for the v1
  /// opt-in cleanup feature.
  String get cloudLlmApiKey => _prefs.getString('cloud_llm_api_key') ?? '';
  set cloudLlmApiKey(String key) {
    Log.instance.d(
        'settings', 'Saving cloudLlmApiKey: ${key.isEmpty ? "EMPTY" : "SET"}');
    _prefs.setString('cloud_llm_api_key', key);
  }

  /// Model id sent in the chat-completions request body.
  /// Default "gpt-4o-mini" — small, fast, cheap; users
  /// pointing at non-OpenAI endpoints override per their
  /// catalog (e.g. "claude-3-5-haiku-20241022" via proxy,
  /// "llama-3.1-8b-instruct" on local llama-server, …).
  String get cloudLlmModel =>
      _prefs.getString('cloud_llm_model') ?? 'gpt-4o-mini';
  set cloudLlmModel(String model) {
    Log.instance.d('settings', 'Saving cloudLlmModel: $model');
    _prefs.setString('cloud_llm_model', model);
  }

  // --- §5.1.6 v3 Local-LLM cleanup ---

  /// Which LLM path Tidy / Summarize routes through. Single
  /// source of truth — the three-mode UI selector writes here,
  /// and downstream code reads this to pick between the cloud
  /// service, the local service, or no LLM pass at all.
  /// Stored as the enum name so an order shuffle doesn't break
  /// existing installs.
  LlmCleanupMode get llmCleanupMode {
    final raw = _prefs.getString('llm_cleanup_mode');
    if (raw == null) return LlmCleanupMode.off;
    for (final v in LlmCleanupMode.values) {
      if (v.name == raw) return v;
    }
    return LlmCleanupMode.off;
  }

  set llmCleanupMode(LlmCleanupMode mode) {
    Log.instance.d('settings', 'Saving llmCleanupMode: ${mode.name}');
    _prefs.setString('llm_cleanup_mode', mode.name);
  }

  /// Absolute path to a GGUF chat model. Empty means "no model
  /// configured" — the Tidy dialog's "Local" affordance hides /
  /// disables until this is set. We don't curate a list of
  /// models here; the Settings screen surfaces a file picker
  /// and the user points at any GGUF on disk. A curated
  /// catalogue with downloads lands in §5.1.6 v3.1.
  String get localLlmModelPath =>
      _prefs.getString('local_llm_model_path') ?? '';
  set localLlmModelPath(String path) {
    Log.instance.d('settings',
        'Saving localLlmModelPath: ${path.isEmpty ? "EMPTY" : path}');
    _prefs.setString('local_llm_model_path', path);
  }

  /// `-1` = all layers on GPU (default — Metal on macOS, CUDA
  /// on Linux/Windows when present, CPU fallback otherwise).
  /// `0` = CPU only; positive int = partial offload. Stored as
  /// int so the user-facing slider in Settings can write it
  /// without per-platform branching here.
  int get localLlmNGpuLayers => _prefs.getInt('local_llm_n_gpu_layers') ?? -1;
  set localLlmNGpuLayers(int n) {
    Log.instance.d('settings', 'Saving localLlmNGpuLayers: $n');
    _prefs.setInt('local_llm_n_gpu_layers', n);
  }

  /// Context window in tokens. 0 means "use the GGUF's baked-in
  /// default" — the binding interprets that as `null` upstream
  /// and lets the model pick. Bumping this is the lever a user
  /// pulls when summarising long transcripts.
  int get localLlmNCtx => _prefs.getInt('local_llm_n_ctx') ?? 0;
  set localLlmNCtx(int n) {
    Log.instance.d('settings', 'Saving localLlmNCtx: $n');
    _prefs.setInt('local_llm_n_ctx', n);
  }

  /// Generation threads. 0 = upstream's default (physical-cores cap).
  int get localLlmNThreads => _prefs.getInt('local_llm_n_threads') ?? 0;
  set localLlmNThreads(int n) {
    Log.instance.d('settings', 'Saving localLlmNThreads: $n');
    _prefs.setInt('local_llm_n_threads', n);
  }

  /// Per-call output cap. Smaller than the cloud default
  /// (1024) because per-segment cleanup typically produces
  /// output of similar length to the input — 512 is enough
  /// headroom while keeping a runaway generation from
  /// dominating the pass.
  int get localLlmMaxTokens => _prefs.getInt('local_llm_max_tokens') ?? 512;
  set localLlmMaxTokens(int n) {
    Log.instance.d('settings', 'Saving localLlmMaxTokens: $n');
    _prefs.setInt('local_llm_max_tokens', n);
  }

  /// Sampling temperature. 0.0 = greedy, matches the cloud
  /// path's default and keeps Tidy output reproducible.
  double get localLlmTemperature =>
      _prefs.getDouble('local_llm_temperature') ?? 0.0;
  set localLlmTemperature(double t) {
    Log.instance.d('settings', 'Saving localLlmTemperature: $t');
    _prefs.setDouble('local_llm_temperature', t);
  }

  // --- §5.1.11 Global hotkey ---

  /// Whether the global hotkey is registered at all. Off by
  /// default so a fresh install doesn't grab a system shortcut
  /// the user didn't ask for. Desktop-only — the setting is
  /// still readable on mobile but the service treats those
  /// platforms as no-ops.
  bool get hotkeyEnabled => _prefs.getBool('hotkey_enabled') ?? false;
  set hotkeyEnabled(bool value) {
    Log.instance.d('settings', 'Saving hotkeyEnabled: $value');
    _prefs.setBool('hotkey_enabled', value);
  }

  /// Normalised combo string ("meta+shift+space",
  /// "control+alt+r") — see HotkeyService.serialize for the
  /// canonical form. Empty until the user picks one in
  /// Settings.
  String get hotkeyCombo => _prefs.getString('hotkey_combo') ?? '';
  set hotkeyCombo(String combo) {
    Log.instance.d('settings', 'Saving hotkeyCombo: $combo');
    _prefs.setString('hotkey_combo', combo);
  }

  /// 'pushToTalk' (default) or 'toggle'. Stored as the enum
  /// name so it survives an enum-order shuffle.
  String get hotkeyActionName =>
      _prefs.getString('hotkey_action') ?? 'pushToTalk';
  set hotkeyActionName(String name) {
    Log.instance.d('settings', 'Saving hotkeyActionName: $name');
    _prefs.setString('hotkey_action', name);
  }

  /// Convenience: parse / write the enum directly. Defaults to
  /// pushToTalk on unknown strings so a stale prefs row doesn't
  /// crash startup.
  HotkeyAction get hotkeyAction {
    final n = hotkeyActionName;
    for (final v in HotkeyAction.values) {
      if (v.name == n) return v;
    }
    return HotkeyAction.pushToTalk;
  }

  set hotkeyAction(HotkeyAction v) {
    hotkeyActionName = v.name;
  }

  /// §5.1.5 Phase C — whether the EditAudioScreen's transcript
  /// pane is expanded by default. Persists so users who treat
  /// the editor as audio-only collapse once and never see the
  /// pane again; users who treat it as a Descript-style joint
  /// editor leave it open. Default false to favour the pure-
  /// audio-editing flow on first launch.
  bool get editAudioShowTranscript =>
      _prefs.getBool('edit_audio_show_transcript') ?? false;
  set editAudioShowTranscript(bool value) {
    Log.instance.d('settings', 'Saving editAudioShowTranscript: $value');
    _prefs.setBool('edit_audio_show_transcript', value);
  }

  /// Helper to clear all settings (for reset)
  Future<void> clearAll() async {
    await _prefs.clear();
  }

  // --- Watch Folder (§5.25.8) ---

  bool get watchFolderEnabled =>
      _prefs.getBool('watch_folder_enabled') ?? false;
  set watchFolderEnabled(bool v) {
    _prefs.setBool('watch_folder_enabled', v);
  }

  String? get watchFolderPath => _prefs.getString('watch_folder_path');
  set watchFolderPath(String? v) {
    if (v == null) {
      _prefs.remove('watch_folder_path');
    } else {
      _prefs.setString('watch_folder_path', v);
    }
  }

  /// macOS security-scoped bookmark for [watchFolderPath], base64-encoded.
  ///
  /// The path alone is not enough under the App Store sandbox: the grant that
  /// comes from the user picking a folder expires with the session, so on
  /// relaunch the raw path is unreadable and — because a sandbox denial makes
  /// `stat` fail rather than throw — the watcher silently found "no such
  /// directory" and gave up with the setting still showing as enabled.
  ///
  /// Null on every other platform and on macOS builds where bookmark creation
  /// failed; callers fall back to [watchFolderPath], which is correct
  /// everywhere the sandbox is not in play.
  String? get watchFolderBookmark => _prefs.getString('watch_folder_bookmark');
  set watchFolderBookmark(String? v) {
    if (v == null) {
      _prefs.remove('watch_folder_bookmark');
    } else {
      _prefs.setString('watch_folder_bookmark', v);
    }
  }

  /// Set when a configured watch folder could not be opened at launch, so
  /// Settings can say so instead of displaying the path as though a watch
  /// were running.
  ///
  /// Recorded as an explicit flag rather than re-probed in `build`: outside
  /// the launch path the app holds no security scope on the folder, so a
  /// `Directory.existsSync()` check in the widget would report every
  /// perfectly good sandboxed folder as missing. Cleared when the user picks
  /// a folder again, which is what restores the grant.
  bool get watchFolderAccessLost =>
      _prefs.getBool('watch_folder_access_lost') ?? false;
  set watchFolderAccessLost(bool v) =>
      _prefs.setBool('watch_folder_access_lost', v);

  // EU AI Act Art. 52 — first-use AI transparency notice.
  bool get aiTransparencyNoticeSeen =>
      _prefs.getBool('ai_transparency_notice_seen') ?? false;
  set aiTransparencyNoticeSeen(bool value) =>
      _prefs.setBool('ai_transparency_notice_seen', value);

  bool get onboardingCompleted =>
      _prefs.getBool('onboarding_completed') ?? false;
  set onboardingCompleted(bool value) =>
      _prefs.setBool('onboarding_completed', value);

  String get onboardingTask =>
      _prefs.getString('onboarding_task') ?? 'transcribe';
  set onboardingTask(String value) =>
      _prefs.setString('onboarding_task', value);

  String get onboardingPriority =>
      _prefs.getString('onboarding_priority') ?? 'balanced';
  set onboardingPriority(String value) =>
      _prefs.setString('onboarding_priority', value);

  /// Reveal the power-user surface: transcript A/B compare, subtitle overlay,
  /// voice baking, audio editing, the local HTTP server, and the log and
  /// storage inspectors.
  ///
  /// **Off by default, and that is a beta decision rather than a judgement
  /// about the features.** The app has 18 routes and 111 advanced options; a
  /// TestFlight tester who opens it for the first time needs to find "record
  /// or pick a file, get a transcript" and nothing else. Everything gated
  /// here is either a developer tool, a workflow that presumes a finished
  /// transcript, or — in the server's case — something that makes iOS ask for
  /// local-network permission on first use, which is a support conversation
  /// nobody wants to have with a beta tester.
  ///
  /// Nothing is deleted or compiled out: this flips one flag and the whole
  /// surface returns, so feedback on it stays one tap away for the testers
  /// who want it.
  bool get experimentalFeatures =>
      _prefs.getBool('experimental_features') ?? false;
  set experimentalFeatures(bool value) =>
      _prefs.setBool('experimental_features', value);
}

/// Provider for the SettingsService.
/// Note: Requires initialization in main() before use.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError('SettingsService not initialized');
});

/// §5.1.6 v3 — which LLM cleanup path Tidy / Summarize uses.
/// Single source of truth, persisted to prefs, read by both the
/// cleanup pass and the summarisation pass so a user only has
/// to pick once and both surfaces follow.
enum LlmCleanupMode { off, cloud, local }
