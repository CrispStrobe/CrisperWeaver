import 'dart:async';
import 'dart:io';

import 'dart:ui' show AppExitResponse;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/transcription_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/cloud_llm_settings_screen.dart';
import 'screens/hotkey_settings_screen.dart';
import 'screens/local_llm_settings_screen.dart';
import 'screens/speaker_management_screen.dart';
import 'screens/model_management_screen.dart';
import 'screens/history_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/about_screen.dart';
import 'screens/storage_screen.dart';
import 'screens/synthesize_screen.dart';
import 'screens/voice_clone_wizard_screen.dart';
import 'screens/translate_screen.dart';
import 'screens/voice_bake_screen.dart';
import 'screens/edit_audio_screen.dart';
import 'screens/subtitle_overlay_screen.dart';
import 'screens/transcript_compare_screen.dart';
import 'services/watch_folder_service.dart';
import 'services/audio_service.dart';
import 'services/batch_queue_service.dart';
import 'services/desktop_open_with_bridge.dart';
import 'services/env_helpers.dart';
import 'services/espeak_data_service.dart';
import 'services/history_service.dart';
import 'services/log_service.dart';
import 'services/native_licenses.dart';
import 'services/share_intake_service.dart';
import 'services/speaker_id_service.dart';
import 'services/transcription_service.dart';
import 'services/model_service.dart';
import 'services/hotkey_service.dart';
import 'services/preset_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'package:crispembed/crispembed.dart' show CrispEmbed;
import 'engines/transcription_engine.dart'; // Use engine TranscriptionSegment

/// Desktop-side argv intake — populated in [main] from the args
/// Flutter passes after the executable name. Linux `.desktop`
/// launches with `Exec=crisper_weaver %F` feed file paths here;
/// macOS `Open With` (when fully wired in a future pass) will
/// route through the same list. The CrisperWeaverApp's
/// postFrameCallback drains this into ShareIntakeService.acceptPaths
/// once the provider graph is up.
List<String> _bootArgs = const [];

void main(List<String> args) async {
  _bootArgs = List<String>.unmodifiable(args);
  WidgetsFlutterBinding.ensureInitialized();

  // Pin kokoro's F0Ntrain + decoder-body compute graphs to CPU on
  // Apple Silicon Metal. Set BEFORE any libcrispasr session opens —
  // the C side reads these via env_bool() inside
  // kokoro_init_from_file. Workaround for an AdainResBlk1d Metal
  // kernel divergence localised by the upstream bisect on
  // 2026-05-17; remaining stages (text encoder, BERT, predictor
  // duration LSTM, iSTFTNet generator) still get Metal acceleration.
  // Drop this once upstream fixes AdainResBlk1d on Metal.
  applyKokoroMetalWorkaround();

  // Point libespeak-ng at the bundled espeak-ng-data/ so kokoro's
  // in-process phonemizer can initialise on platforms where the user
  // doesn't have espeak-ng installed system-wide (Windows + macOS .app
  // releases ship the data dir alongside the runtime). Must fire before
  // the first kokoro session opens — CrispASR reads
  // CRISPASR_ESPEAK_DATA_PATH once in phonemize_espeak_lib. Android is
  // handled separately: the assets bundle gets extracted to the docs
  // dir on first launch and the path is set via the explicitOverride.
  applyKokoroEspeakDataPath();

  // Android can't dlopen a directory of phoneme tables straight out
  // of the APK (it's a zip). EspeakDataService extracts the bundled
  // espeak-ng-data/ asset to the app's docs dir on first launch and
  // calls applyKokoroEspeakDataPath with the resulting path so
  // libespeak-ng's init points at writable files. No-op on every
  // other platform.
  await EspeakDataService.ensureExtractedAndSetEnv();

  // just_audio ships native code for iOS/Android/macOS/web only. On
  // Windows and Linux it has no platform implementation, which crashes
  // every player call with MissingPluginException(disposeAllPlayers).
  // Route those two platforms through libmpv via just_audio_media_kit.
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Persist the rolling session log from the very first line so bug reports
  // always have the startup trail on disk.
  await Log.instance.enableFileSink(true);
  await Log.instance.logBootBanner();
  Log.instance.i('main', 'CrisperWeaver starting',
      fields: {'level': Log.instance.minLevel.tag});

  FlutterError.onError = (details) {
    Log.instance.e(
      'flutter',
      details.exceptionAsString(),
      error: details.exception,
      stack: details.stack,
    );
    FlutterError.presentError(details);
  };

  // Surface uncaught platform/dispatcher errors too.
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    Log.instance.e('uncaught', '$error', error: error, stack: stack);
    return true;
  };

  await _requestPermissions();
  await _initializeServices();
  await _configureAudioSession();
  await registerNativeLicenses();

  final prefs = await SharedPreferences.getInstance();
  final settingsService = SettingsService(prefs);

  // Honour persisted user choice for log level. If unset, Log's default
  // (trace in debug, info in release) holds.
  Log.instance.setMinLevel(settingsService.logLevel);

  final presetService = PresetService(prefs);
  final hotkeyService = HotkeyService(settingsService);
  // §5.1.11 — register the persisted hotkey before the first
  // frame builds. Errors here are caught + logged inside the
  // service; we don't gate runApp on it because a hotkey
  // failure shouldn't prevent the app from launching.
  unawaited(hotkeyService.applyFromSettings());

  runApp(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
        presetServiceProvider.overrideWithValue(presetService),
        hotkeyServiceProvider.overrideWithValue(hotkeyService),
      ],
      child: const CrisperWeaverApp(),
    ),
  );
}

Future<void> _requestPermissions() async {
  // Only request mobile-only permissions on mobile platforms. On desktop the
  // permission_handler plugin simply returns granted or unknown, so asking
  // is cheap but unnecessary.
  if (!(Platform.isIOS || Platform.isAndroid)) return;

  final permissions = <Permission>[
    Permission.microphone,
  ];
  if (Platform.isAndroid) {
    permissions.add(Permission.storage);
  }

  try {
    await permissions.request();
  } catch (e) {
    debugPrint('Permission request failed: $e');
  }
}

Future<void> _initializeServices() async {
  try {
    await getApplicationDocumentsDirectory();
  } catch (e) {
    debugPrint('Failed to initialize services: $e');
  }
}

/// Configure AVAudioSession (iOS) / AudioFocus (Android) so playback
/// and recording cooperate with the rest of the OS — silent-mode
/// honours playback, mic recording doesn't permanently steal the
/// session from other apps, and the `UIBackgroundModes = audio`
/// declaration in Info.plist actually keeps streaming-mic alive when
/// the screen locks. `speech()` is just_audio's recommended preset
/// for transcription/dictation apps: `playAndRecord` category +
/// `speakerOverride` so speaker output works when no headphones are
/// connected. No-op on desktop.
Future<void> _configureAudioSession() async {
  if (!(Platform.isIOS || Platform.isAndroid)) return;
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  } catch (e, st) {
    Log.instance.w('main', 'audio_session configure failed',
        error: e, stack: st);
  }
}

class CrisperWeaverApp extends ConsumerStatefulWidget {
  const CrisperWeaverApp({super.key});

  @override
  ConsumerState<CrisperWeaverApp> createState() => _CrisperWeaverAppState();
}

class _CrisperWeaverAppState extends ConsumerState<CrisperWeaverApp> {
  late final AppLifecycleListener _lifecycle;
  WatchFolderService? _watchFolderService;

  @override
  void initState() {
    super.initState();
    // Kick off OS-level share intake after the first frame so Riverpod's
    // provider graph is fully built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final intake = ref.read(shareIntakeServiceProvider);
      intake.start();
      // Desktop argv intake — Linux `.desktop` launches with
      // `Exec=crisper_weaver %F`, so the file paths arrive as
      // positional args. The intake service triages them the
      // same way Android / iOS shares are routed; non-audio,
      // non-transcript args (e.g. flutter-tool flags) drop
      // silently. We only run this on desktop platforms — on
      // mobile the args list is always empty and forwarding
      // would be a no-op anyway.
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        intake.acceptPaths(_bootArgs);
      }
      // macOS Open-With / drag-on-dock bridge — drains the
      // Swift-side buffer of cold-launch file paths and listens
      // for live opens after the app is up. No-op on other
      // platforms (the channel isn't registered there).
      unawaited(
          DesktopOpenWithBridge(sink: intake.acceptPaths).start());
      // Hydrate the batch queue from disk so jobs survive restarts
      // (§5.23 Q1). Running-when-killed jobs are demoted back to
      // queued so the next drain pass picks them up; a separate
      // Q3 path will look for matching .ckpt.jsonl files and stamp
      // resumeOffsetSec onto each before dispatch (commit 2 of the
      // batch slice).
      unawaited(ref.read(batchQueueProvider.notifier).load());

      // §5.25.11 — Pre-load known audio fingerprints from history so
      // the batch queue can detect already-transcribed files.
      unawaited(ref.read(historyServiceProvider).list().then((entries) {
        final fps = entries
            .where((e) => e.audioFingerprint != null)
            .map((e) => e.audioFingerprint!)
            .toList();
        ref.read(batchQueueProvider.notifier).loadKnownFingerprints(fps);
      }));

      // §5.25.8 — Start watch-folder service if enabled.
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        final settings = ref.read(settingsServiceProvider);
        if (settings.watchFolderEnabled && settings.watchFolderPath != null) {
          _watchFolderService = WatchFolderService(
            onNewFile: (path) async {
              final q = ref.read(batchQueueProvider.notifier);
              // §5.25.11 — Auto-skip already-transcribed files in watch folder.
              final dup = await q.checkFingerprintDedup(path);
              if (dup != null) {
                Log.instance.i('watch-folder',
                    'skipping duplicate: $path (fingerprint: $dup)');
                return;
              }
              q.enqueue(path);
            },
          );
          _watchFolderService!.start(settings.watchFolderPath!);
        }
      }
    });

    // On desktop, the user clicking the red close button fires
    // `applicationShouldTerminate:` → Flutter's onExitRequested. We need
    // to dispose the CrispASR engine here so ggml-metal's background
    // residency-set dispatch queue gets cancelled BEFORE the process
    // calls exit(). Otherwise `ggml_metal_rsets_free` asserts from
    // inside __cxa_finalize_ranges and macOS pops a "closed
    // unexpectedly" dialog.
    _lifecycle = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
  }

  Future<AppExitResponse> _onExitRequested() async {
    try {
      Log.instance.i('main', 'exit requested — disposing engine');
      final t = ref.read(transcriptionServiceProvider);
      t.dispose(); // Returns void, do not await

      // Give it a moment to actually stop any native threads if needed
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await Log.instance.enableFileSink(false); // flush + close sink
    } catch (e, st) {
      Log.instance.w('main', 'dispose on exit failed', error: e, stack: st);
    }
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _watchFolderService?.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  static final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const TranscriptionScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          // Phone-form sub-screens — wide layouts still see the
          // dialogs in settings_screen.dart. The branch lives
          // on the calling ListTile's onTap (isPhoneWidth ?
          // context.push : showDialog), so these routes are
          // never reached on desktop unless somebody types the
          // URL by hand — which still works.
          GoRoute(
            path: 'cloud-llm',
            name: 'settings-cloud-llm',
            builder: (context, state) => const CloudLlmSettingsScreen(),
          ),
          GoRoute(
            path: 'local-llm',
            name: 'settings-local-llm',
            builder: (context, state) => const LocalLlmSettingsScreen(),
          ),
          GoRoute(
            path: 'hotkey',
            name: 'settings-hotkey',
            builder: (context, state) => const HotkeySettingsScreen(),
          ),
          GoRoute(
            path: 'speakers',
            name: 'settings-speakers',
            builder: (context, state) => const SpeakerManagementScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/models',
        name: 'models',
        builder: (context, state) {
          // Optional `?kind=<ModelKind.name>` deep-link: pre-selects
          // the filter chip on open. Used by Settings → Local LLM's
          // "Manage" link to drop the user into the chat-LLM filter.
          final raw = state.uri.queryParameters['kind'];
          ModelKind? kind;
          if (raw != null) {
            for (final k in ModelKind.values) {
              if (k.name == raw) {
                kind = k;
                break;
              }
            }
          }
          return ModelManagementScreen(initialKindFilter: kind);
        },
      ),
      GoRoute(
        path: '/history',
        name: 'history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/logs',
        name: 'logs',
        builder: (context, state) => const LogsScreen(),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/storage',
        name: 'storage',
        builder: (context, state) => const StorageScreen(),
      ),
      GoRoute(
        path: '/synthesize',
        name: 'synthesize',
        builder: (context, state) {
          // §5.1.12 — the voice-clone wizard hands off via
          // GoRouter `extra` (in-memory) since the WAV path
          // may be arbitrarily long. Both keys are optional;
          // when present, the screen pre-populates its custom-
          // voice + ref-text fields.
          final extra = state.extra;
          String? voiceWavPath;
          String? refText;
          if (extra is Map) {
            final m = extra;
            final v = m['voiceWavPath'];
            if (v is String) voiceWavPath = v;
            final r = m['refText'];
            if (r is String) refText = r;
          }
          return SynthesizeScreen(
            initialVoiceWavPath: voiceWavPath,
            initialRefText: refText,
          );
        },
      ),
      GoRoute(
        path: '/voice-clone',
        name: 'voice-clone',
        builder: (context, state) => const VoiceCloneWizardScreen(),
      ),
      GoRoute(
        path: '/translate',
        name: 'translate',
        builder: (context, state) => const TranslateScreen(),
      ),
      GoRoute(
        path: '/voice-bake',
        name: 'voice-bake',
        builder: (context, state) => const VoiceBakeScreen(),
      ),
      GoRoute(
        path: '/subtitle-overlay',
        name: 'subtitle-overlay',
        builder: (context, state) => const SubtitleOverlayScreen(),
      ),
      GoRoute(
        path: '/compare',
        name: 'compare',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return TranscriptCompareScreen(
            leftEntryId: q['left'] ?? '',
            rightEntryId: q['right'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/edit-audio',
        name: 'edit-audio',
        builder: (context, state) {
          // Source path arrives as a query parameter rather than a
          // path segment so it survives URL-encoding cleanly on
          // platforms where the path may contain spaces/specials.
          final q = state.uri.queryParameters;
          final src = q['path'] ?? '';
          // §5.1.5 Phase D — optional `start` + `end` (seconds)
          // pre-populate a waveform selection on open; optional
          // `mark` pre-drops a single cut point. Used by the
          // transcript long-press menu's "edit / mark this segment
          // in audio editor" actions.
          double? parse(String? s) => s == null ? null : double.tryParse(s);
          return EditAudioScreen(
            sourcePath: src,
            initialSelectionStartSec: parse(q['start']),
            initialSelectionEndSec: parse(q['end']),
            initialCutMarkSec: parse(q['mark']),
          );
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    Log.instance.d(
        'locale',
        'MaterialApp.build locale=$locale '
            'supported=${AppLocalizations.supportedLocales}');

    return MaterialApp.router(
      title: 'CrisperWeaver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: _router,
      locale: locale,
      // i18n: English (fallback) + German. Flutter picks the closest match
      // to the system locale automatically.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Make the title locale-aware too.
      onGenerateTitle: (ctx) {
        final l = AppLocalizations.of(ctx);
        Log.instance.d(
            'locale',
            'onGenerateTitle resolved to locale=${Localizations.localeOf(ctx)} '
                'appName="${l.appName}"');
        return l.appName;
      },
    );
  }
}

// Global providers
// (audioServiceProvider moved into lib/services/audio_service.dart so
// downstream services can wire to it without round-tripping through
// main.dart.)

final historyServiceProvider =
    Provider<HistoryService>((ref) => HistoryService());

final modelServiceProvider = Provider<ModelService>((ref) {
  final settingsService = ref.watch(settingsServiceProvider);
  return ModelService(settingsService);
});

/// §5.25.2 — Optional CrispEmbed instance for semantic transcript search.
/// Lazy-loads when a native library + embedding GGUF are available on disk.
/// Returns null otherwise — callers fall back to TF-IDF.
final crispEmbedProvider = Provider<CrispEmbed?>((ref) {
  final modelService = ref.watch(modelServiceProvider);
  return _tryLoadCrispEmbed(modelService);
});

/// Attempt to find a downloaded embedding GGUF and load it via CrispEmbed.
/// Returns null on any failure (missing native lib, no model on disk, …).
CrispEmbed? _tryLoadCrispEmbed(ModelService modelService) {
  try {
    final modelsDir = modelService.whisperCppDir();
    for (final def in ModelService.whisperCppModels.values) {
      if (def.kind != ModelKind.embed) continue;
      final modelPath = '$modelsDir/${def.fileName}';
      if (File(modelPath).existsSync()) {
        return CrispEmbed(modelPath);
      }
    }
    return null;
  } catch (_) {
    // Native library not bundled or model load failed — degrade silently.
    return null;
  }
}

final transcriptionServiceProvider = Provider<TranscriptionService>((ref) {
  final audioService = ref.watch(audioServiceProvider);
  final modelService = ref.watch(modelServiceProvider);
  final speakerIdService = ref.watch(speakerIdServiceProvider);
  return TranscriptionService(
    audioService,
    modelService,
    speakerIdService: speakerIdService,
  );
});

/// Path to the audio file the user has selected or just recorded — used to
/// hand off a recording from the recorder widget to the transcription screen.
final selectedAudioPathProvider = StateProvider<String?>((ref) => null);

// App state using engine TranscriptionSegment
class AppState {
  final String? currentTranscription;
  final bool isTranscribing;
  final double progress;
  final String? errorMessage;
  final List<TranscriptionSegment> segments;
  final PerformanceStats? performance;
  /// Per-session map from diariser-emitted speaker labels (e.g.
  /// "Speaker 1", "Speaker 2") to user-chosen names (e.g. "Alice",
  /// "Host"). Applied at render time so future segments arriving
  /// after the rename also get the new label, and so the original
  /// label is recoverable. Persisted into HistoryEntry on save so
  /// renames survive across launches.
  final Map<String, String> speakerNames;
  /// History entry id of the most recent save. Set by the
  /// transcription screen / batch drain loop after a successful
  /// `historyService.save()`. Used by [editSegment] to propagate
  /// inline edits back to the on-disk JSON (§5.1.3). Null while
  /// transcription is mid-flight or when nothing has been saved
  /// yet (e.g. an aborted run).
  final String? historyEntryId;

  const AppState({
    this.currentTranscription,
    this.isTranscribing = false,
    this.progress = 0.0,
    this.errorMessage,
    this.segments = const [],
    this.performance,
    this.speakerNames = const {},
    this.historyEntryId,
  });

  AppState copyWith({
    String? currentTranscription,
    bool? isTranscribing,
    double? progress,
    String? errorMessage,
    List<TranscriptionSegment>? segments,
    PerformanceStats? performance,
    Map<String, String>? speakerNames,
    String? historyEntryId,
  }) {
    return AppState(
      currentTranscription: currentTranscription ?? this.currentTranscription,
      isTranscribing: isTranscribing ?? this.isTranscribing,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      segments: segments ?? this.segments,
      performance: performance ?? this.performance,
      speakerNames: speakerNames ?? this.speakerNames,
      historyEntryId: historyEntryId ?? this.historyEntryId,
    );
  }
}

/// Performance snapshot for the most recent transcription run.
class PerformanceStats {
  final double audioSeconds;
  final double wallSeconds;
  final double rtf;
  final int wordCount;
  final double wordsPerSecond;
  final String? engineId;
  final String? modelId;

  const PerformanceStats({
    required this.audioSeconds,
    required this.wallSeconds,
    required this.rtf,
    required this.wordCount,
    required this.wordsPerSecond,
    this.engineId,
    this.modelId,
  });

  static PerformanceStats? fromMetadata(
    Map<String, dynamic>? md, {
    String? engineId,
    String? modelId,
  }) {
    if (md == null) return null;
    final a = (md['audioSeconds'] as num?)?.toDouble();
    final w = (md['wallSeconds'] as num?)?.toDouble();
    final r = (md['rtf'] as num?)?.toDouble();
    final wc = (md['wordCount'] as num?)?.toInt();
    final wps = (md['wordsPerSecond'] as num?)?.toDouble();
    if (a == null || w == null) return null;
    return PerformanceStats(
      audioSeconds: a,
      wallSeconds: w,
      rtf: r ?? 0.0,
      wordCount: wc ?? 0,
      wordsPerSecond: wps ?? 0.0,
      engineId: engineId ?? md['engine'] as String?,
      modelId: modelId ?? md['model'] as String?,
    );
  }
}

final appStateProvider =
    StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(const AppState());

  void startTranscription() {
    // Direct AppState() construction (not copyWith) so a previous
    // run's `historyEntryId` is genuinely cleared rather than
    // carried forward by the `?? this.field` fallback in copyWith.
    // Without this, inline edits made on a fresh transcription
    // would overwrite the previously-saved entry on disk (§5.1.3).
    state = const AppState(
      isTranscribing: true,
      progress: 0.0,
    );
  }

  /// Rename a speaker (e.g. "Speaker 1" → "Alice"). The mapping is
  /// applied at render time so segments are not mutated; this keeps
  /// the original label recoverable and means future segments
  /// arriving with the original label automatically pick up the new
  /// name. Empty `newName` removes the override.
  void renameSpeaker(String original, String newName) {
    if (original.isEmpty) return;
    final next = Map<String, String>.from(state.speakerNames);
    if (newName.trim().isEmpty) {
      next.remove(original);
    } else {
      next[original] = newName.trim();
    }
    state = state.copyWith(speakerNames: next);
  }

  void updateProgress(double progress) {
    state = state.copyWith(progress: progress.clamp(0.0, 1.0));
  }

  void addSegment(TranscriptionSegment segment) {
    Log.instance.d('state', 'Adding segment: "${segment.text}"');
    final updatedSegments = [...state.segments, segment];
    final fullText = updatedSegments.map((s) => s.text).join(' ');
    state = state.copyWith(
        segments: updatedSegments, currentTranscription: fullText);
  }

  void completeTranscription(
    List<TranscriptionSegment> segments, {
    PerformanceStats? performance,
  }) {
    final fullText = segments.map((s) => s.text).join(' ');
    state = state.copyWith(
      isTranscribing: false,
      segments: segments,
      currentTranscription: fullText,
      progress: 1.0,
      errorMessage: null,
      performance: performance,
    );
  }

  void setError(String error) {
    state = state.copyWith(isTranscribing: false, errorMessage: error);
  }

  void clearTranscription() {
    state = const AppState();
  }

  /// Replace the live transcription text in-place. Used by mic-stream
  /// mode where the engine emits a rolling decode of the last 10 s
  /// window — each commit overwrites rather than appends, otherwise
  /// the text would visibly duplicate as the window slides.
  void replaceLiveStreamingText(String text) {
    state = state.copyWith(currentTranscription: text);
  }

  /// Replace a segment's text after the user manually edited it.
  /// Marks the segment as `edited: true` in metadata so the UI can
  /// flag it visually. Updates the joined `currentTranscription` so
  /// downstream consumers (export, copy-all) see the corrected text.
  void editSegment(int index, String newText) {
    if (index < 0 || index >= state.segments.length) return;
    final original = state.segments[index];
    final updated = TranscriptionSegment(
      text: newText,
      startTime: original.startTime,
      endTime: original.endTime,
      speaker: original.speaker,
      confidence: original.confidence,
      words: original.words,
      metadata: {
        ...original.metadata,
        'edited': true,
      },
    );
    final segments = [...state.segments];
    segments[index] = updated;
    state = state.copyWith(
      segments: segments,
      currentTranscription: segments.map((s) => s.text).join(' ').trim(),
    );
  }

  /// §5.25.10 — Replace the full segment list (e.g. after tagging).
  /// Updates currentTranscription from the new segments and persists
  /// tags to the history entry if one exists.
  void replaceSegments(List<TranscriptionSegment> segments) {
    state = state.copyWith(
      segments: segments,
      currentTranscription: segments.map((s) => s.text).join(' ').trim(),
    );
  }

  /// §5.1.3 — clear the saved history id, e.g. when starting a
  /// new transcription. Without this, post-restart edits on a
  /// fresh transcription would overwrite the previously-saved
  /// entry.
  void setHistoryEntryId(String? id) {
    state = AppState(
      currentTranscription: state.currentTranscription,
      isTranscribing: state.isTranscribing,
      progress: state.progress,
      errorMessage: state.errorMessage,
      segments: state.segments,
      performance: state.performance,
      speakerNames: state.speakerNames,
      historyEntryId: id,
    );
  }
}

/// Manages the app's locale based on user preference or system default.
class LocaleNotifier extends StateNotifier<Locale?> {
  final SettingsService _settingsService;

  LocaleNotifier(this._settingsService) : super(null) {
    _init();
  }

  void _init() {
    final localeCode = _settingsService.appLocale;
    Log.instance.d('locale', 'Initial app locale from settings: $localeCode');
    if (localeCode != null && localeCode.isNotEmpty) {
      state = Locale(localeCode);
    }
  }

  Future<void> setLocale(String? languageCode) async {
    Log.instance.i('locale', 'Changing app locale to: $languageCode');
    _settingsService.appLocale = languageCode;
    if (languageCode == null || languageCode.isEmpty) {
      state = null;
    } else {
      state = Locale(languageCode);
    }
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  final settingsService = ref.watch(settingsServiceProvider);
  return LocaleNotifier(settingsService);
});
