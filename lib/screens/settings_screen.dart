import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:path/path.dart' as p;

import '../build_info.dart';
import '../engines/engine_factory.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart';
import '../services/hotkey_service.dart';
import '../services/log_service.dart';
import '../services/memory_estimator.dart';
import '../services/model_service.dart';
import '../services/server_service.dart';
import '../services/settings_service.dart';
import '../services/speaker_id_service.dart';
import '../models/speaker_vocab.dart';
import '../utils/platform_utils.dart' as plat;
import '../utils/responsive.dart';
import '../widgets/cloud_llm_settings_form.dart';
import '../widgets/hotkey_settings_form.dart';
import '../widgets/local_llm_settings_form.dart';

/// True when [path] points into Android's shared external storage
/// (`/storage/emulated/0/...`, `/sdcard/...`, `/storage/self/primary/...`)
/// — those paths only become readable after the user grants
/// MANAGE_EXTERNAL_STORAGE ("All files access") in system settings, so
/// the models-dir picker prompts for it. App-private dirs under
/// `/Android/data/<package>/files/...` are sandboxed and need no special
/// permission; we return false for those so the user isn't pestered when
/// picking a sandboxed location. This predicate is the sole gate for the
/// "All files access" dialog, so it is unit-tested directly.
@visibleForTesting
bool looksLikeAndroidSharedStoragePath(String path) {
  if (path.startsWith('/storage/emulated/') ||
      path.startsWith('/sdcard/') ||
      path.startsWith('/storage/self/primary/')) {
    // /Android/data/<pkg>/ is sandboxed — no special perm needed.
    if (path.contains('/Android/data/')) return false;
    return true;
  }
  return false;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsServiceProvider);
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.settingsSaved)),
              );
              Navigator.of(context).pop();
            },
            child: Text(l.done.toUpperCase(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        children: [
          _buildLocaleSettings(settings),
          _buildEngineSettings(settings),
          _buildTranscriptionSettings(settings),
          _buildAudioSettings(settings),
          _buildDiarizationSettings(settings),
          _buildStorageSettings(),
          _buildServerSettings(),
          _buildWatchFolderSettings(settings),
          _buildDeveloperSettings(settings),
          _buildSystemInfo(),
          _buildAboutSection(),
        ],
      ),
      bottomNavigationBar: isPhoneWidth(context)
          ? const PhoneNavBar(current: PhoneNavDestination.settings)
          : null,
    );
  }

  Widget _buildLocaleSettings(SettingsService settings) {
    final l = AppLocalizations.of(context);
    return _buildSettingsSection(
      title: l.settingsAppLanguage,
      icon: Icons.language,
      children: [
        ListTile(
          title: Text(l.settingsInterfaceLanguage),
          subtitle: Text(_getAppLocaleDisplayName(settings.appLocale ?? '')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAppLocaleSelector(settings),
        ),
      ],
    );
  }

  void _showAppLocaleSelector(SettingsService settings) {
    final l = AppLocalizations.of(context);
    final locales = {
      '': l.settingsSystemDefault,
      'en': 'English',
      'de': 'Deutsch',
    };

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(AppLocalizations.of(context).settingsSelectInterfaceLanguage),
        content: RadioGroup<String>(
          groupValue: settings.appLocale ?? '',
          onChanged: (value) {
            if (value == null) return;
            settings.appLocale = value;
            final languageCode = value.isEmpty ? null : value;
            ref.read(localeProvider.notifier).setLocale(languageCode);
            Navigator.of(context).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: locales.entries
                .map((entry) => RadioListTile<String>(
                      title: Text(entry.value),
                      value: entry.key,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  String _getAppLocaleDisplayName(String code) {
    if (code == 'en') return 'English';
    if (code == 'de') return 'Deutsch';
    return AppLocalizations.of(context).settingsSystemDefault;
  }

  Widget _buildEngineSettings(SettingsService settings) {
    final l = AppLocalizations.of(context);
    return _buildSettingsSection(
      title: l.settingsEngineSection,
      icon: Icons.psychology,
      children: [
        ListTile(
          title: Text(l.settingsEnginePreferred),
          subtitle: Text(settings.preferredEngine.displayName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showEngineSelector(settings),
        ),
      ],
    );
  }

  void _showEngineSelector(SettingsService settings) {
    final availableEngines = EngineFactory.getAvailableEngines();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).settingsSelectEngine),
        content: RadioGroup<EngineType>(
          groupValue: settings.preferredEngine,
          onChanged: (value) async {
            if (value == null) return;
            settings.preferredEngine = value;
            Navigator.of(context).pop();

            // Try to swap engines immediately
            final service = ref.read(transcriptionServiceProvider);
            try {
              final ok = await service.switchEngine(value);
              if (!context.mounted) return;
              final sl = AppLocalizations.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? sl.settingsEngineSwitched(value.displayName)
                      : sl.settingsEngineSwitchFailed),
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        '${AppLocalizations.of(context).settingsEngineSwitchFailed}: $e')),
              );
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: availableEngines
                .map((engine) => RadioListTile<EngineType>(
                      title: Text(engine.displayName),
                      subtitle: Text(engine.description),
                      value: engine,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTranscriptionSettings(SettingsService settings) {
    return _buildSettingsSection(
      title: AppLocalizations.of(context).settingsTranscription,
      icon: Icons.transcribe,
      children: [
        if (settings.preferredEngine == EngineType.crispasr)
          ListTile(
            title: Text(AppLocalizations.of(context).settingsDefaultBackend),
            subtitle: Text(settings.defaultBackend),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBackendSelector(settings),
          ),
        ListTile(
          title: Text(AppLocalizations.of(context).settingsDefaultModel),
          subtitle: Text(settings.defaultModel),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showModelSelector(settings),
        ),
        ListTile(
          title: Text(AppLocalizations.of(context).settingsDefaultLanguage),
          subtitle: Text(_getLanguageDisplayName(settings.defaultLanguage)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showLanguageSelector(settings),
        ),
        SwitchListTile(
          title: Text(AppLocalizations.of(context).settingsAutoDetectLanguage),
          subtitle: Text(
              AppLocalizations.of(context).settingsAutoDetectLanguageSubtitle),
          value: settings.autoDetectLanguage,
          onChanged: (value) {
            settings.autoDetectLanguage = value;
          },
        ),
        SwitchListTile(
          title: Text(AppLocalizations.of(context).settingsWordTimestamps),
          subtitle:
              Text(AppLocalizations.of(context).settingsWordTimestampsSubtitle),
          value: settings.enableWordTimestamps,
          onChanged: (value) {
            settings.enableWordTimestamps = value;
          },
        ),
      ],
    );
  }

  void _showBackendSelector(SettingsService settings) {
    final backends = [
      'whisper',
      'parakeet',
      'canary',
      'qwen3',
      'cohere',
      'granite',
      'fastconformer-ctc',
      'canary-ctc',
      'voxtral',
      'voxtral4b',
      'wav2vec2',
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).settingsSelectBackend),
        content: SingleChildScrollView(
          child: RadioGroup<String>(
            groupValue: settings.defaultBackend,
            onChanged: (value) {
              if (value == null) return;
              settings.defaultBackend = value;
              Navigator.of(ctx).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: backends
                  .map((b) => RadioListTile<String>(
                        title: Text(b),
                        value: b,
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _showModelSelector(SettingsService settings) async {
    final backendFilter = settings.defaultBackend;
    List<ModelInfo> models = [];
    try {
      models = await ref.read(modelServiceProvider).getWhisperCppModels();
    } catch (e) {
      Log.instance.w('settings', 'Failed to load models for picker', error: e);
    }
    // Filter by currently-selected backend — user chose "parakeet" as
    // default backend, picker shows parakeet quants only.
    final filtered = models.where((m) => m.backend == backendFilter).toList();

    if (!mounted) return;
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsSelectModel(backendFilter)),
        content: SizedBox(
          width: double.maxFinite,
          child: filtered.isEmpty
              ? Text(l.settingsNoModelsForBackend(backendFilter))
              : SingleChildScrollView(
                  child: RadioGroup<String>(
                    groupValue: settings.defaultModel,
                    onChanged: (value) {
                      if (value == null) return;
                      settings.defaultModel = value;
                      Navigator.of(ctx).pop();
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: filtered
                          .map((m) => RadioListTile<String>(
                                title: Text(m.displayName),
                                subtitle: Text(
                                    '${m.quantization.isEmpty ? "f16" : m.quantization} • ${m.size}'),
                                value: m.name,
                              ))
                          .toList(),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _showLanguageSelector(SettingsService settings) {
    final l = AppLocalizations.of(context);
    final languages = {
      'auto': l.languageAuto,
      'en': l.languageEn,
      'es': l.languageEs,
      'fr': l.languageFr,
      'de': l.languageDe,
      'it': l.languageIt,
      'pt': l.languagePt,
      'zh': l.languageZh,
      'ja': l.languageJa,
      'ko': l.languageKo,
    };

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).settingsSelectLanguage),
        content: RadioGroup<String>(
          groupValue: settings.defaultLanguage,
          onChanged: (value) {
            if (value == null) return;
            settings.defaultLanguage = value;
            Navigator.of(context).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: languages.entries
                .map((entry) => RadioListTile<String>(
                      title: Text(entry.value),
                      value: entry.key,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioSettings(SettingsService settings) {
    return _buildSettingsSection(
      title: AppLocalizations.of(context).settingsAudio,
      icon: Icons.audiotrack,
      children: [
        ListTile(
          title: Text(AppLocalizations.of(context).settingsAudioQuality),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).settingsAudioQualityCurrent(
                  (settings.audioQuality * 100).toInt())),
              Slider(
                value: settings.audioQuality,
                onChanged: (value) {
                  settings.audioQuality = value;
                },
                divisions: 4,
                label: '${(settings.audioQuality * 100).toInt()}%',
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: Text(AppLocalizations.of(context).settingsKeepAudioFiles),
          subtitle:
              Text(AppLocalizations.of(context).settingsKeepAudioFilesSubtitle),
          value: settings.keepAudioFiles,
          onChanged: (value) {
            settings.keepAudioFiles = value;
          },
        ),
      ],
    );
  }

  Widget _buildDiarizationSettings(SettingsService settings) {
    return _buildSettingsSection(
      title: AppLocalizations.of(context).settingsDiarization,
      icon: Icons.people,
      children: [
        SwitchListTile(
          title: Text(
              AppLocalizations.of(context).settingsEnableDiarizationByDefault),
          subtitle: Text(AppLocalizations.of(context)
              .settingsEnableDiarizationByDefaultSubtitle),
          value: settings.enableDiarizationByDefault,
          onChanged: (value) {
            settings.enableDiarizationByDefault = value;
          },
        ),
        // §5.8.1 — On-device speaker DB (TitaNet enrolment).
        ListTile(
          title: Text(AppLocalizations.of(context).settingsSpeakers),
          subtitle:
              Text(AppLocalizations.of(context).settingsSpeakersSubtitle),
          trailing: const Icon(Icons.people_outline),
          onTap: () => context.push('/settings/speakers'),
        ),
        // §5.25.4 — Per-speaker vocabulary editor.
        ListTile(
          title: Text(AppLocalizations.of(context).settingsSpeakerVocab),
          subtitle: Text(AppLocalizations.of(context).settingsSpeakerVocabSubtitle),
          trailing: const Icon(Icons.spellcheck),
          onTap: () => _showSpeakerVocabEditor(),
        ),
      ],
    );
  }

  Widget _buildStorageSettings() {
    return _buildSettingsSection(
      title: AppLocalizations.of(context).settingsStorage,
      icon: Icons.storage,
      children: [
        ListTile(
          title: Text(AppLocalizations.of(context).settingsClearCache),
          subtitle:
              Text(AppLocalizations.of(context).settingsClearCacheSubtitle),
          trailing: const Icon(Icons.delete_outline),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(AppLocalizations.of(context).settingsCacheCleared)),
            );
          },
        ),
        ListTile(
          title: Text(AppLocalizations.of(context).settingsManageModels),
          subtitle:
              Text(AppLocalizations.of(context).settingsManageModelsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/models'),
        ),
        ListTile(
          title: Text(AppLocalizations.of(context).settingsStorageBreakdown),
          subtitle: Text(
              AppLocalizations.of(context).settingsStorageBreakdownSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/storage'),
        ),
      ],
    );
  }

  Widget _buildServerSettings() {
    final server = ref.watch(serverServiceProvider);
    final running = server.isRunning;
    final l = AppLocalizations.of(context);
    return _buildSettingsSection(
      title: l.settingsServerSection,
      icon: Icons.cloud,
      children: [
        SwitchListTile(
          title: Text(l.settingsServerEnable),
          subtitle: Text(
            running
                ? l.settingsServerRunningAt(server.boundUrl ?? '')
                : l.settingsServerStopped,
          ),
          value: running,
          onChanged: (v) async {
            if (v) {
              try {
                await server.start();
              } on ServerStartException catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.settingsServerStartFailed(e.message))),
                );
              }
            } else {
              await server.stop();
            }
          },
        ),
        ListTile(
          title: Text(l.settingsServerEndpoints),
          subtitle: Text(l.settingsServerEndpointsHelp,
              style: const TextStyle(fontSize: 11)),
          isThreeLine: true,
        ),
      ],
    );
  }

  /// §5.25.8 — Watch-folder settings.
  Widget _buildWatchFolderSettings(SettingsService settings) {
    final l = AppLocalizations.of(context);
    final watchPath = settings.watchFolderPath;
    final enabled = settings.watchFolderEnabled;
    // Watch folder is desktop-only.
    if (!plat.isMacOS && !plat.isLinux && !plat.isWindows) {
      return const SizedBox.shrink();
    }
    return _buildSettingsSection(
      title: l.settingsWatchFolder,
      icon: Icons.folder_special,
      children: [
        SwitchListTile(
          title: Text(l.settingsWatchFolderAutoTranscribe),
          subtitle: Text(
            enabled && watchPath != null
                ? l.settingsWatchFolderWatching(watchPath)
                : l.settingsWatchFolderMonitorHint,
          ),
          value: enabled,
          onChanged: (v) {
            settings.watchFolderEnabled = v;
            
          },
        ),
        ListTile(
          title: Text(l.settingsWatchFolderPath),
          subtitle: Text(watchPath ?? l.settingsWatchFolderNotSet),
          trailing: const Icon(Icons.folder_open),
          onTap: () async {
            final result = await FilePicker.getDirectoryPath(
              dialogTitle: l.settingsWatchFolderPickerTitle,
            );
            if (result != null) {
              settings.watchFolderPath = result;
              
            }
          },
        ),
      ],
    );
  }

  Widget _buildDeveloperSettings(SettingsService settings) {
    return _buildSettingsSection(
      title: AppLocalizations.of(context).settingsDebugging,
      icon: Icons.bug_report,
      children: [
        ListTile(
          title: Text(AppLocalizations.of(context).settingsLogLevel),
          subtitle: Text(AppLocalizations.of(context)
              .settingsLogLevelCurrent(settings.logLevel.tag)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showLogLevelSelector(settings),
        ),
        SwitchListTile(
          title: Text(AppLocalizations.of(context).settingsMirrorLogs),
          subtitle:
              Text(AppLocalizations.of(context).settingsMirrorLogsSubtitle),
          value: settings.logToFile,
          onChanged: (value) async {
            settings.logToFile = value;
            await Log.instance.enableFileSink(value);
          },
        ),
        SwitchListTile(
          title: Text(AppLocalizations.of(context).settingsSkipChecksum),
          subtitle:
              Text(AppLocalizations.of(context).settingsSkipChecksumSubtitle),
          value: settings.skipChecksum,
          onChanged: (value) {
            settings.skipChecksum = value;
            Log.instance.i(
                'settings',
                value
                    ? 'Checksum verification disabled'
                    : 'Checksum verification enabled');
          },
        ),
        SwitchListTile(
          title:
              Text(AppLocalizations.of(context).settingsGroupBatchByBackend),
          subtitle: Text(AppLocalizations.of(context)
              .settingsGroupBatchByBackendSubtitle),
          value: settings.groupBatchByBackend,
          onChanged: (value) {
            settings.groupBatchByBackend = value;
            Log.instance.i('settings',
                'Group batch by backend: ${value ? "ON" : "OFF"}');
          },
        ),
        // §5.23 Q2 v1 — pipeline parallelism slider. 1 = current
        // serial behaviour, 2..N = pre-decode next file's audio in
        // a worker isolate while the current file's GPU work runs.
        // Cap is platform-specific (2 on iOS, 4 elsewhere).
        Builder(builder: (context) {
          final n = settings.maxConcurrentTranscriptions;
          final cap = settings.maxConcurrentTranscriptionsLimit;
          return ListTile(
            title: Text(AppLocalizations.of(context)
                .settingsMaxConcurrentCurrent(n)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: n.toDouble(),
                  min: 1,
                  max: cap.toDouble(),
                  divisions: cap - 1,
                  label: n.toString(),
                  onChanged: (v) {
                    settings.maxConcurrentTranscriptions = v.round();
                  },
                ),
                Text(AppLocalizations.of(context)
                    .settingsMaxConcurrentSubtitle),
              ],
            ),
          );
        }),
        // §5.23 Q2 v2 — N-way session pool slider. 1 = no pool
        // (existing behaviour). 2+ spawns N worker isolates each
        // holding its own model copy. RAM projection shows
        // realtime estimate against the currently-selected model;
        // pre-flight at batch-start time may clamp lower if the
        // model doesn't fit.
        Builder(builder: (context) {
          final l = AppLocalizations.of(context);
          final n = settings.maxConcurrentSessions;
          final cap = settings.maxConcurrentSessionsLimit;
          final estimator = ref.read(memoryEstimatorProvider);
          final modelPath = _activeModelPath(ref, settings.defaultModel);
          final est = estimator.estimate(
              requested: n, modelPath: modelPath);
          return ListTile(
            title: Text(l.settingsMaxConcurrentSessionsCurrent(n)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: n.toDouble(),
                  min: 1,
                  max: cap.toDouble(),
                  divisions: cap - 1,
                  label: n.toString(),
                  onChanged: (v) {
                    settings.maxConcurrentSessions = v.round();
                  },
                ),
                Text(l.settingsMaxConcurrentSessionsSubtitle),
                const SizedBox(height: 4),
                Text(
                  l.settingsMemoryProjection(
                    est.prettyProjected,
                    est.prettyPhysical,
                    est.prettyPerWorker,
                  ),
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade700),
                ),
                if (est.wasClamped)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l.settingsMemoryProjectionClamped(
                          est.affordableWorkers, est.requestedWorkers),
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          );
        }),
        ListTile(
          title: Text(AppLocalizations.of(context).settingsHfToken),
          subtitle: Text(settings.hfToken.isEmpty
              ? AppLocalizations.of(context).settingsHfTokenNotSet
              : '••••••••${settings.hfToken.length > 8 ? settings.hfToken.substring(settings.hfToken.length - 4) : ""}'),
          trailing: const Icon(Icons.vpn_key),
          onTap: () => _showHfTokenDialog(settings),
        ),
        // iOS sandboxes apps inside their container; pointing the model
        // store at an arbitrary folder requires security-scoped bookmarks
        // and a different storage flow. Hide the picker on iOS until that
        // exists — the default path inside the app's documents directory
        // is the only sane location there.
        if (!plat.isIOS)
          ListTile(
            title: Text(AppLocalizations.of(context).settingsModelsDir),
            subtitle: Text(settings.customModelsDir.isEmpty
                ? AppLocalizations.of(context).settingsModelsDirDefault
                : settings.customModelsDir),
            trailing: const Icon(Icons.folder_open),
            onTap: () => _showModelsDirDialog(settings),
          ),
        // §5.1.11 — desktop global hotkey configuration.
        // Hidden on mobile where the OS doesn't expose a
        // system-level shortcut surface.
        if (plat.isMacOS || plat.isWindows || plat.isLinux)
          ListTile(
            title: Text(AppLocalizations.of(context).settingsHotkey),
            subtitle: Text(!settings.hotkeyEnabled ||
                    settings.hotkeyCombo.isEmpty
                ? AppLocalizations.of(context).settingsHotkeyOff
                : '${settings.hotkeyCombo} '
                    '(${settings.hotkeyAction == HotkeyAction.pushToTalk ? AppLocalizations.of(context).settingsHotkeyActionPushToTalk : AppLocalizations.of(context).settingsHotkeyActionToggle})'),
            trailing: const Icon(Icons.keyboard),
            onTap: () async {
              if (isPhoneWidth(context)) {
                await context.push('/settings/hotkey');
                if (mounted) setState(() {});
              } else {
                _showHotkeyDialog(settings);
              }
            },
          ),
        // §5.1.6 v2 — BYOK cloud-LLM cleanup settings.
        ListTile(
          title: Text(
              AppLocalizations.of(context).settingsCloudLlmCleanup),
          subtitle: Text(settings.cloudLlmApiUrl.isEmpty ||
                  settings.cloudLlmApiKey.isEmpty
              ? AppLocalizations.of(context)
                  .settingsCloudLlmCleanupOff
              : '${settings.cloudLlmModel} · ${settings.cloudLlmApiUrl}'),
          trailing: const Icon(Icons.cloud_outlined),
          onTap: () async {
            // Phone → push the sub-screen; wide → keep the
            // existing dialog. Both paths share the same form
            // widget, so behaviour stays identical.
            if (isPhoneWidth(context)) {
              await context.push('/settings/cloud-llm');
              if (mounted) setState(() {});
            } else {
              _showCloudLlmDialog(settings);
            }
          },
        ),
        // §5.1.6 v3 — on-device chat-LLM cleanup settings.
        ListTile(
          title: Text(
              AppLocalizations.of(context).settingsLocalLlmCleanup),
          subtitle: Text(settings.localLlmModelPath.isEmpty
              ? AppLocalizations.of(context).settingsLocalLlmCleanupOff
              : _shortGgufLabel(settings.localLlmModelPath)),
          trailing: const Icon(Icons.memory_outlined),
          onTap: () async {
            if (isPhoneWidth(context)) {
              await context.push('/settings/local-llm');
              if (mounted) setState(() {});
            } else {
              _showLocalLlmDialog(settings);
            }
          },
        ),
        ListTile(
          title: Text(AppLocalizations.of(context).settingsOpenLogViewer),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/logs'),
        ),
      ],
    );
  }

  /// §5.25.4 — Speaker vocabulary editor dialog. Lists enrolled speakers
  /// and their per-speaker vocab terms. Users can add/remove terms.
  Future<void> _showSpeakerVocabEditor() async {
    final speakerIdService = ref.read(speakerIdServiceProvider);
    final docs = await getApplicationDocumentsDirectory();
    final speakersDir = '${docs.path}/speakers';
    // Ensure dir exists
    final dir = Directory(speakersDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    var vocabs = await SpeakerVocab.listAll(speakersDir);
    final enrolled = await speakerIdService.listSpeakers();

    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.settingsSpeakerVocabDialogTitle),
          content: SizedBox(
            width: 400,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final name in enrolled) ...[
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Builder(builder: (_) {
                    final vocab = vocabs
                        .where((v) => v.speakerName == name)
                        .cast<SpeakerVocab?>()
                        .firstWhere((_) => true, orElse: () => null);
                    return Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        if (vocab != null)
                          for (final term in vocab.terms)
                            Chip(
                              label: Text(term, style: const TextStyle(fontSize: 12)),
                              onDeleted: () async {
                                final updated = SpeakerVocab(
                                  speakerName: name,
                                  terms: vocab.terms.where((t) => t != term).toList(),
                                );
                                await updated.save(speakersDir);
                                vocabs = await SpeakerVocab.listAll(speakersDir);
                                setDialogState(() {});
                              },
                              deleteIconColor: Colors.red,
                            ),
                        ActionChip(
                          label: const Text('+', style: TextStyle(fontSize: 12)),
                          onPressed: () async {
                            final ctrl = TextEditingController();
                            final term = await showDialog<String>(
                              context: ctx,
                              builder: (innerCtx) => AlertDialog(
                                title: Text(l.settingsSpeakerVocabAddTermTitle(name)),
                                content: TextField(
                                  controller: ctrl,
                                  decoration: InputDecoration(
                                    hintText: l.settingsSpeakerVocabAddTermHint,
                                  ),
                                  autofocus: true,
                                  onSubmitted: (v) =>
                                      Navigator.of(innerCtx).pop(v.trim()),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(innerCtx).pop(null),
                                    child: Text(l.dialogCancel),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(innerCtx)
                                        .pop(ctrl.text.trim()),
                                    child: Text(l.dialogAdd),
                                  ),
                                ],
                              ),
                            );
                            if (term == null || term.isEmpty) return;
                            final existing = vocab?.terms ?? [];
                            final updated = SpeakerVocab(
                              speakerName: name,
                              terms: [...existing, term],
                            );
                            await updated.save(speakersDir);
                            vocabs = await SpeakerVocab.listAll(speakersDir);
                            setDialogState(() {});
                          },
                        ),
                      ],
                    );
                  }),
                  const Divider(),
                ],
                if (enrolled.isEmpty)
                  Text(
                    l.settingsSpeakerVocabNoSpeakers,
                    style: const TextStyle(color: Colors.grey),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.done),
            ),
          ],
        ),
      ),
    );
  }

  /// Pretty-print a model file path for the Settings list tile.
  /// Just the basename plus a parent-dir crumb; the full path
  /// is visible in the picker dialog itself.
  String _shortGgufLabel(String path) {
    final sep = p.separator;
    final parts = path.split(sep).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return path;
    return '${parts[parts.length - 2]}$sep${parts.last}';
  }

  void _showCloudLlmDialog(SettingsService settings) {
    final l = AppLocalizations.of(context);
    final formKey = GlobalKey<CloudLlmSettingsFormState>();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l.settingsCloudLlmCleanup),
          content: SizedBox(
            width: responsiveDialogWidth(ctx, designed: 520),
            child: CloudLlmSettingsForm(
              key: formKey,
              initialApiUrl: settings.cloudLlmApiUrl,
              initialApiKey: settings.cloudLlmApiKey,
              initialModel: settings.cloudLlmModel,
              onCommit: (url, key, model) {
                settings.cloudLlmApiUrl = url;
                settings.cloudLlmApiKey = key;
                settings.cloudLlmModel = model;
              },
              onCleared: () {
                settings.cloudLlmApiUrl = '';
                settings.cloudLlmApiKey = '';
                settings.cloudLlmModel = 'gpt-4o-mini';
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.cancel)),
            TextButton(
                onPressed: () {
                  formKey.currentState?.clear();
                  Navigator.of(ctx).pop();
                },
                child: Text(l.settingsCloudLlmClear)),
            FilledButton(
                onPressed: () {
                  formKey.currentState?.save();
                  Navigator.of(ctx).pop();
                },
                child: Text(l.save)),
          ],
        );
      },
    );
  }

  /// §5.1.6 v3 — Local LLM cleanup dialog. File picker for the
  /// GGUF chat model, expandable advanced params. No URL / key
  /// fields — the local path doesn't need them.
  void _showLocalLlmDialog(SettingsService settings) {
    final l = AppLocalizations.of(context);
    final formKey = GlobalKey<LocalLlmSettingsFormState>();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l.settingsLocalLlmCleanup),
          content: SizedBox(
            width: responsiveDialogWidth(ctx, designed: 560),
            child: SingleChildScrollView(
              child: LocalLlmSettingsForm(
                key: formKey,
                initialModelPath: settings.localLlmModelPath,
                initialNGpuLayers: settings.localLlmNGpuLayers,
                initialNCtx: settings.localLlmNCtx,
                initialNThreads: settings.localLlmNThreads,
                initialMaxTokens: settings.localLlmMaxTokens,
                initialTemperature: settings.localLlmTemperature,
                onCommit: (path, gpu, ctx2, threads, maxT, temp) {
                  settings.localLlmModelPath = path;
                  settings.localLlmNGpuLayers = gpu;
                  settings.localLlmNCtx = ctx2;
                  settings.localLlmNThreads = threads;
                  settings.localLlmMaxTokens = maxT;
                  settings.localLlmTemperature = temp;
                },
                onCleared: () {
                  settings.localLlmModelPath = '';
                  settings.localLlmNGpuLayers = -1;
                  settings.localLlmNCtx = 0;
                  settings.localLlmNThreads = 0;
                  settings.localLlmMaxTokens = 512;
                  settings.localLlmTemperature = 0.0;
                },
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.cancel)),
            TextButton(
              onPressed: () {
                formKey.currentState?.clear();
                Navigator.of(ctx).pop();
              },
              child: Text(l.settingsLocalLlmModelClear),
            ),
            FilledButton(
              onPressed: () {
                formKey.currentState?.save();
                Navigator.of(ctx).pop();
              },
              child: Text(l.save),
            ),
          ],
        );
      },
    );
  }

  /// §5.1.11 — global-hotkey configuration dialog. Text-input
  /// field for the combo string plus a Radio group for the
  /// push-to-talk / toggle behaviour and an enable switch.
  /// Hotkey-recorder UI is intentionally simple for v1 — a
  /// HotkeyRecorder widget exists in the package but adds a
  /// modal-overlay UX the v1 doesn't need. v2 can swap in the
  /// recorder.
  void _showHotkeyDialog(SettingsService settings) {
    final l = AppLocalizations.of(context);
    final formKey = GlobalKey<HotkeySettingsFormState>();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l.settingsHotkey),
          content: SizedBox(
            width: responsiveDialogWidth(ctx, designed: 480),
            child: HotkeySettingsForm(
              key: formKey,
              initialEnabled: settings.hotkeyEnabled,
              initialCombo: settings.hotkeyCombo,
              initialAction: settings.hotkeyAction,
              onCommit: (enabled, combo, action) {
                settings.hotkeyEnabled = enabled;
                settings.hotkeyCombo = combo;
                settings.hotkeyAction = action;
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.cancel)),
            FilledButton(
              onPressed: () async {
                final res = formKey.currentState?.save();
                if (res == null) return;
                if (!res.ok) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(
                        l.settingsHotkeyInvalid(res.invalidCombo!)),
                  ));
                  return;
                }
                // Re-register with the freshly-saved values.
                await ref
                    .read(hotkeyServiceProvider)
                    .applyFromSettings();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(l.save),
            ),
          ],
        );
      },
    );
  }

  void _showLogLevelSelector(SettingsService settings) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).settingsLogLevel),
        content: RadioGroup<LogLevel>(
          groupValue: settings.logLevel,
          onChanged: (v) {
            if (v == null) return;
            settings.logLevel = v;
            Log.instance.setMinLevel(v);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: LogLevel.values
                .map((l) => RadioListTile<LogLevel>(
                      title: Text('${l.tag} — ${l.name}'),
                      value: l,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  /// Folder-picker for the optional custom models directory. Lets the
  /// user point CrisperWeaver at a shared library on an external disk
  /// (e.g. `/Volumes/backups/ai/crispasr-models`) so existing GGUFs
  /// are reused without re-downloading into the sandbox. The empty
  /// string ("Use default") restores the historical
  /// `<app-docs>/models/whisper_cpp` location.
  Future<void> _showModelsDirDialog(SettingsService settings) async {
    final l = AppLocalizations.of(context);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsModelsDirPickTitle),
        content: Text(settings.customModelsDir.isEmpty
            ? l.settingsModelsDirCurrentDefault
            : l.settingsModelsDirCurrent(settings.customModelsDir)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(l.cancel),
          ),
          if (settings.customModelsDir.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('reset'),
              child: Text(l.settingsModelsDirReset),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('pick'),
            child: Text(l.settingsModelsDirPick),
          ),
        ],
      ),
    );
    if (action == 'reset') {
      settings.customModelsDir = '';
      Log.instance.i('settings', 'customModelsDir cleared (back to sandbox)');
      return;
    }
    if (action != 'pick') return;
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: l.settingsModelsDirPickTitle,
      initialDirectory:
          settings.customModelsDir.isEmpty ? null : settings.customModelsDir,
    );
    if (picked == null || picked.isEmpty) return;
    // Picking an external dir on Android 11+ requires the
    // "All files access" runtime permission (MANAGE_EXTERNAL_STORAGE).
    // The manifest declares it but it stays denied until the user
    // toggles it in Settings → Apps → CrisperWeaver → Special access.
    // permission_handler.request() on Android 11+ redirects to that
    // Settings page. Without this, the picker returns a path string
    // but every Directory(path).listSync / File(path).readAsBytes
    // fails with "OS Error: Permission denied, errno = 13" — most
    // visibly after uninstall+reinstall, when Android resets the
    // grant but the saved customModelsDir path persists.
    if (plat.isAndroid && looksLikeAndroidSharedStoragePath(picked)) {
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        if (!mounted) return;
        // l10n: this dialog is an Android-only error path so we keep
        // the copy inline rather than threading 4 new ARB keys through
        // every locale just for this niche flow. The Settings page
        // permission_handler opens is OS-localized anyway.
        final fl = AppLocalizations.of(context);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(fl.settingsAllFilesAccessNeeded),
            content: Text(fl.settingsAllFilesAccessExplanation),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(fl.dialogCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(fl.settingsOpenSettings),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        await Permission.manageExternalStorage.request();
        final newStatus = await Permission.manageExternalStorage.status;
        if (!newStatus.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).settingsAllFilesAccessDenied,
              ),
            ),
          );
          return;
        }
      }
    }
    settings.customModelsDir = picked;
    Log.instance.i('settings', 'customModelsDir set', fields: {'path': picked});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.settingsModelsDirSet(picked))),
    );
  }

  void _showHfTokenDialog(SettingsService settings) {
    final controller = TextEditingController(text: settings.hfToken);
    showDialog<void>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.settingsHfTokenTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.settingsHfTokenSubtitle,
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                    labelText: l.labelApiToken,
                    border: const OutlineInputBorder(),
                    hintText: 'hf_...'),
                obscureText: true,
                autocorrect: false,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.settingsHfTokenCancel)),
            ElevatedButton(
              onPressed: () {
                final newToken = controller.text.trim();
                settings.hfToken = newToken;
                ref.read(modelServiceProvider).hfToken = newToken;
                Navigator.of(context).pop();
                Log.instance.i(
                    'settings',
                    newToken.isEmpty
                        ? 'HF Token cleared'
                        : 'HF Token updated');
              },
              child: Text(l.settingsHfTokenSave),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSystemInfo() {
    return _buildSettingsSection(
      title: AppLocalizations.of(context).settingsSystemInfo,
      icon: Icons.info,
      children: [
        FutureBuilder<Map<String, String>>(
          future: _getSystemInfo(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return ListTile(
                  title: Text(AppLocalizations.of(context).settingsLoading));
            }
            return Column(
              children: snapshot.data!.entries
                  .map((entry) => ListTile(
                        title: Text(entry.key),
                        subtitle: Text(entry.value),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return _buildSettingsSection(
      title: AppLocalizations.of(context).settingsAbout,
      icon: Icons.help_outline,
      children: [
        ListTile(
          title: Text(AppLocalizations.of(context).settingsVersion),
          subtitle: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) => Text(snapshot.hasData
                ? '${snapshot.data!.version}+${snapshot.data!.buildNumber} ($kBuildGitHash)'
                : AppLocalizations.of(context).settingsLoading),
          ),
          onLongPress: () {
            // Copy full build info to clipboard on long-press.
            const info = 'git:$kBuildGitHashFull built:$kBuildTimestamp';
            Clipboard.setData(const ClipboardData(text: info));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Build info copied to clipboard'),
                  duration: Duration(seconds: 2)),
            );
          },
        ),
        ListTile(
          title: Text(AppLocalizations.of(context).settingsAboutCrisperWeaver),
          subtitle: Text(
              AppLocalizations.of(context).settingsAboutCrisperWeaverSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/about'),
        ),
      ],
    );
  }

  Widget _buildSettingsSection(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Future<Map<String, String>> _getSystemInfo() async {
    final info = <String, String>{};
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      info['App Version'] =
          '${packageInfo.version} (${packageInfo.buildNumber})';
      final deviceInfo = DeviceInfoPlugin();
      if (plat.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        info['Device'] = '${iosInfo.name} (${iosInfo.model})';
        info['iOS Version'] = '${iosInfo.systemName} ${iosInfo.systemVersion}';
      } else if (plat.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        info['Device'] = '${androidInfo.manufacturer} ${androidInfo.model}';
        info['Android Version'] = 'API ${androidInfo.version.sdkInt}';
      } else if (plat.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        info['Device'] = '${macInfo.computerName} (${macInfo.model})';
        info['macOS Version'] = macInfo.osRelease;
      } else if (plat.isWindows) {
        final winInfo = await deviceInfo.windowsInfo;
        info['Device'] = winInfo.computerName;
        info['Windows Version'] =
            '${winInfo.productName} (build ${winInfo.buildNumber})';
      } else if (plat.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        info['Device'] = linuxInfo.name;
        info['Linux Version'] = linuxInfo.prettyName;
      }
    } catch (e) {
      info['Error'] = 'Could not load system info';
    }
    return info;
  }

  String _getLanguageDisplayName(String languageCode) {
    final l = AppLocalizations.of(context);
    switch (languageCode) {
      case 'auto':
        return l.languageAuto;
      case 'en':
        return l.languageEn;
      case 'es':
        return l.languageEs;
      case 'fr':
        return l.languageFr;
      case 'de':
        return l.languageDe;
      case 'it':
        return l.languageIt;
      case 'pt':
        return l.languagePt;
      case 'zh':
        return l.languageZh;
      case 'ja':
        return l.languageJa;
      case 'ko':
        return l.languageKo;
      default:
        return languageCode;
    }
  }
}

/// Resolve the on-disk path for [modelId] so the §5.23 Q2 v2 memory
/// pre-flight has something to size against. Looks up the model's
/// fileName via [ModelService] catalogs + joins under the
/// configured models dir. Returns null when the model isn't in the
/// catalog yet (covers user-bring-your-own GGUFs) — the memory
/// estimator treats null as "unknown size", refuses to project a
/// pool count.
String? _activeModelPath(WidgetRef ref, String modelId) {
  final def = ModelCatalog.whisperCppModels[modelId] ??
      ModelCatalog.crispasrBackendModels[modelId];
  if (def == null) return null;
  final dir = ref.read(modelServiceProvider).whisperCppDir();
  return p.join(dir, def.fileName);
}
