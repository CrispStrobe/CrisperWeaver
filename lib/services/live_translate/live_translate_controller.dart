import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../engines/transcription_engine.dart' show TranscriptionSegment;
import '../../main.dart' show historyServiceProvider, modelServiceProvider;
import '../../utils/ai_text_disclosure.dart';
import '../audio_service.dart';
import '../log_service.dart';
import '../model_catalog.dart';
import '../model_service.dart';
import '../settings_service.dart';
import '../system_audio_capture_service.dart';
import '../vad_service.dart';
import 'live_asr_worker.dart';
import 'live_translate_config.dart';
import 'live_translator_worker.dart';

enum LiveStatus { idle, loading, running, stopping, error }

/// One translation unit on screen: a sentence in its spoken language plus
/// its translations, which arrive one by one.
class LiveUnit {
  LiveUnit({
    required this.key,
    required this.lang,
    required this.text,
    required this.targets,
    required this.at,
    this.t0 = 0,
    this.t1 = 0,
  });

  final int key;
  final String lang;
  final String text;
  final List<String> targets;
  final DateTime at;

  /// Stream time (s) of the audio this sentence covers, approximately:
  /// from the previous commit to this one.
  final double t0;
  final double t1;

  /// target language → translation; a target missing here is pending.
  final Map<String, String> translations = {};
  final Set<String> failed = {};

  bool isPending(String tgt) =>
      !translations.containsKey(tgt) && !failed.contains(tgt);
}

class LiveTranslateState {
  const LiveTranslateState({
    this.status = LiveStatus.idle,
    this.message,
    this.units = const [],
    this.held = '',
    this.tail = '',
    this.currentLang,
    this.drafts = const {},
    this.stepMs = 0,
    this.behindSec = 0,
    this.translateMs = 0,
    this.recognizer,
    this.translator,
    this.startedAt,
    this.savedHistoryId,
    this.revision = 0,
  });

  final LiveStatus status;
  final String? message;
  final List<LiveUnit> units;

  /// Settled text not yet a whole sentence (held for translation).
  final String held;

  /// The open text still being recognised.
  final String tail;
  final String? currentLang;

  /// Draft translations of [held] + [tail], by target language.
  final Map<String, String> drafts;
  final int stepMs;
  final double behindSec;
  final int translateMs;
  final String? recognizer;
  final String? translator;
  final DateTime? startedAt;

  /// History entry the last stopped session was saved as.
  final String? savedHistoryId;

  /// Bumped on every change so listeners rebuild even when a mutable
  /// [LiveUnit] gained a translation in place.
  final int revision;

  bool get isActive =>
      status == LiveStatus.loading ||
      status == LiveStatus.running ||
      status == LiveStatus.stopping;

  LiveTranslateState copyWith({
    LiveStatus? status,
    String? message,
    bool clearMessage = false,
    List<LiveUnit>? units,
    String? held,
    String? tail,
    String? currentLang,
    Map<String, String>? drafts,
    int? stepMs,
    double? behindSec,
    int? translateMs,
    String? recognizer,
    String? translator,
    DateTime? startedAt,
    String? savedHistoryId,
  }) =>
      LiveTranslateState(
        status: status ?? this.status,
        message: clearMessage ? null : (message ?? this.message),
        units: units ?? this.units,
        held: held ?? this.held,
        tail: tail ?? this.tail,
        currentLang: currentLang ?? this.currentLang,
        drafts: drafts ?? this.drafts,
        stepMs: stepMs ?? this.stepMs,
        behindSec: behindSec ?? this.behindSec,
        translateMs: translateMs ?? this.translateMs,
        recognizer: recognizer ?? this.recognizer,
        translator: translator ?? this.translator,
        startedAt: startedAt ?? this.startedAt,
        savedHistoryId: savedHistoryId ?? this.savedHistoryId,
        revision: revision + 1,
      );
}

/// Resolved files for one live session.
class LiveModelPaths {
  const LiveModelPaths({
    required this.asrPath,
    required this.asrBackend,
    this.translatorPath,
    this.translatorBackend,
    this.vadPath,
    this.audioLidPath,
    this.textLidPath,
    required this.lidMode,
    this.warning,
    this.directTranslationTarget,
  });
  final String asrPath;
  final String asrBackend;
  final String? translatorPath;
  final String? translatorBackend;
  final String? vadPath;
  final String? audioLidPath;
  final String? textLidPath;

  /// Effective mode after `auto` was resolved against what is on disk.
  final LiveLidMode lidMode;

  /// Shown on the board while live: the setup works, but not as well as
  /// the user probably expects.
  final String? warning;

  /// Set when the recogniser translates speech itself (Index-Echo).
  final String? directTranslationTarget;
}

class LiveTranslateException implements Exception {
  const LiveTranslateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Orchestrates one live session: audio capture → recogniser isolate →
/// routing → translator isolate → state for the fullscreen view.
class LiveTranslateController extends Notifier<LiveTranslateState> {
  late LiveTranslateConfig _config;

  Isolate? _asrIso;
  SendPort? _asrPort;
  ReceivePort? _asrEvents;
  Isolate? _trIso;
  SendPort? _trPort;
  ReceivePort? _trEvents;
  StreamSubscription<Float32List>? _audioSub;
  Timer? _replayTimer;
  void Function()? _stopCapture;

  // Translation queue: committed units first, one request in flight.
  final Queue<(int, String, String, String)> _queue = Queue();
  bool _inFlight = false;
  (int, String, String, String)? _pendingDraft;
  int _draftSeq = 0;
  int _avgCommitMs = 0;
  final Map<int, LiveUnit> _byKey = {};
  final List<LiveUnit> _session = []; // every unit, for History
  int _nextKey = 0;
  double _lastUnitT = 0;
  String? _asrName;

  /// Draft translations stop while committed sentences take longer than
  /// this to translate — a slow translator would still be busy with a
  /// draft when the next real sentence arrives (upstream's rule).
  static const _draftBudgetMs = 500;

  /// Recogniser and translator run at the same time; split the cores so
  /// neither starves the other (the recogniser gets the larger share: it
  /// sets the pace of everything after it).
  static int get _cores => Platform.numberOfProcessors;
  static int get _asrThreads => (_cores * 0.6).ceil().clamp(1, 8);
  // Half the cores: a translation LLM (Hy-MT2) is several times slower on
  // one thread, and the two only overlap while a sentence is translated.
  static int get _translatorThreads => (_cores ~/ 2).clamp(1, 6);

  /// Older units are dropped from the live view beyond this many; the
  /// session transcript keeps everything.
  static const _maxUnits = 400;

  @override
  LiveTranslateState build() {
    // Release the workers and the audio device without touching `state`:
    // Riverpod forbids reading or writing it inside a lifecycle callback,
    // and nobody is left to show it to.
    ref.onDispose(() => unawaited(_teardown()));
    _config = LiveTranslateConfig.fromJson(
        ref.read(settingsServiceProvider).liveTranslateConfig);
    return const LiveTranslateState();
  }

  LiveTranslateConfig get config => _config;

  Future<void> updateConfig(LiveTranslateConfig c) async {
    _config = c;
    await ref.read(settingsServiceProvider).setLiveTranslateConfig(c.toJson());
    state = state.copyWith(); // repaint with the new display options
  }

  void clear() {
    _byKey.clear();
    state =
        state.copyWith(units: const [], held: '', tail: '', drafts: const {});
  }

  /// Plain-text transcript of the session: each sentence with its
  /// translations, in the order spoken — carrying the Art. 50(2)
  /// machine-translation notice when it contains any translation, as every
  /// other clipboard exit of translated text does.
  String transcriptText() {
    final text = _plainTranscript();
    final translated = state.units.any((u) => u.translations.isNotEmpty);
    return translated ? AiTextDisclosure.forTranslation(text) : text;
  }

  String _plainTranscript() {
    final b = StringBuffer();
    for (final u in state.units) {
      b.writeln('[${u.lang}] ${u.text}');
      for (final t in u.targets) {
        final tr = u.translations[t];
        if (tr != null) b.writeln('[$t] $tr');
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }

  // ---------------------------------------------------------------------
  // Model resolution
  // ---------------------------------------------------------------------

  Future<LiveModelPaths> resolveModels() async {
    final ms = ref.read(modelServiceProvider);
    final settings = ref.read(settingsServiceProvider);
    final models = await ms.getWhisperCppModels();
    ModelInfo? downloaded(String? name) {
      if (name == null) return null;
      for (final m in models) {
        if (m.name == name && m.isDownloaded && m.localPath != null) return m;
      }
      return null;
    }

    final asr =
        downloaded(_config.asrModel) ?? downloaded(settings.defaultModel);
    if (asr == null) {
      throw const LiveTranslateException(
          'No speech recognition model is downloaded. Pick one in the live '
          'setup, or download Parakeet TDT 0.6B v3 from Models.');
    }

    if (_config.lidMode == LiveLidMode.fixed) {
      // Prefer the current catalogue over metadata saved with an older download.
      final definition = ms.lookupDefinition(asr.name);
      final supported = definition?.matchesLanguage(_config.fixedSource) ??
          asr.matchesLanguage(_config.fixedSource);
      if (!supported) {
        throw LiveTranslateException(
            '${asr.displayName} does not support the selected spoken language '
            '(${_config.fixedSource}). Choose a model that supports it, such as '
            'multilingual Whisper for German.');
      }
    }

    ModelInfo? translator;
    if (_config.needsTranslator) {
      translator =
          downloaded(_config.translatorModel) ?? defaultTranslator(models);
    }

    String? findByPrefix(List<String> prefixes) {
      for (final pre in prefixes) {
        for (final m in models) {
          if (!m.isDownloaded || m.localPath == null) continue;
          if (p.basename(m.localPath!).toLowerCase().startsWith(pre)) {
            return m.localPath;
          }
        }
      }
      return null;
    }

    final preferredLid = downloaded(_config.lidModel)?.localPath;
    // ECAPA and FireRed before Silero: Silero LID misclassifies on some
    // CPUs (tracked upstream), and a wrong language mis-routes a sentence.
    final audioLid = preferredLid != null && preferredLid.contains('lid')
        ? preferredLid
        : findByPrefix(
            ['ecapa-lid', 'firered-lid', 'silero-lid', 'silero-lang']);
    final textLid = findByPrefix(['cld3', 'fasttext-lid', 'glotlid']);

    var mode = _config.lidMode;
    if (mode == LiveLidMode.auto) {
      mode = audioLid != null
          ? LiveLidMode.audio
          : textLid != null
              ? LiveLidMode.text
              : LiveLidMode.recognizer;
    }
    if (mode == LiveLidMode.audio && audioLid == null) {
      throw const LiveTranslateException(
          'Audio language detection needs an LID model (ECAPA-TDNN 107, '
          'FireRed-LID or Silero-LID). Download one from Models → LID, or '
          'choose "from the text" or a fixed language.');
    }
    if (mode == LiveLidMode.text && textLid == null) {
      throw const LiveTranslateException(
          'Text language detection needs CLD3, fastText-176 or GlotLID. '
          'Download one from Models → LID.');
    }

    // Only Whisper reports the language it heard. With any other recogniser
    // and no LID model, every sentence would silently be taken for the
    // first configured language — and translated from the wrong one.
    String? warning;
    if (mode == LiveLidMode.recognizer && asr.backend != 'whisper') {
      final assumed = _config.expectedSources.isEmpty
          ? 'the first language'
          : _config.routes.keys.first;
      warning = 'No language-detection model is downloaded, and '
          '${asr.displayName} does not report the language it hears: '
          'treating all speech as "$assumed". Download ECAPA-TDNN LID or '
          'CLD3 from Models for automatic detection.';
    }

    // Index-Echo translates Chinese speech itself, into en / ja / es. Use
    // the first of those the routing table asks for; the translator covers
    // any other target from its transcript.
    String? direct;
    if (asr.backend == 'index-echo') {
      const echoTargets = ['en', 'ja', 'es'];
      final wanted = _config.targetsFor('zh');
      direct = wanted.firstWhere(echoTargets.contains, orElse: () => 'en');
      warning = [
        if (warning != null) warning,
        'Index-Echo decodes whole utterances and needs a GPU to keep up '
            '(about 40× slower than real time on a CPU).',
      ].join('\n');
    }

    final vad = await ref.read(vadServiceProvider).ensureSileroModel();

    return LiveModelPaths(
      asrPath: asr.localPath!,
      asrBackend: asr.backend,
      translatorPath: translator?.localPath,
      translatorBackend: translator?.backend,
      vadPath: vad,
      audioLidPath: audioLid,
      textLidPath: textLid,
      lidMode: mode,
      warning: warning,
      directTranslationTarget: direct,
    );
  }

  /// The translator used when the user picked none — the same rule the
  /// setup page shows as "(auto)". M2M-100 first, as upstream's
  /// `--translate-model auto`: fast enough to keep up on any machine; a
  /// translation LLM is better but several times slower without a GPU.
  static ModelInfo? defaultTranslator(List<ModelInfo> models) {
    final ready = models
        .where((m) =>
            m.isDownloaded &&
            m.localPath != null &&
            m.kind == ModelKind.translate)
        .toList();
    int rank(ModelInfo m) => switch (m.backend) {
          'm2m100' => 0,
          chatTranslateBackend => 1,
          _ => 2,
        };
    ready.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.sizeBytes.compareTo(b.sizeBytes);
    });
    return ready.firstOrNull;
  }

  // ---------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------

  /// Start listening. [replayFile] replays an audio file in real time
  /// instead of capturing — for rehearsing a setup with a recording.
  Future<void> start({String? replayFile}) async {
    if (state.isActive) return;
    _cancelled = false;
    _byKey.clear();
    _session.clear();
    _lastUnitT = 0;
    _queue.clear();
    _pendingDraft = null;
    _inFlight = false;
    _avgCommitMs = 0;
    state = LiveTranslateState(
        status: LiveStatus.loading, startedAt: DateTime.now());
    try {
      final paths = await resolveModels();
      _asrName = p.basenameWithoutExtension(paths.asrPath);
      final notes = [
        if (_config.needsTranslator && paths.translatorPath == null)
          'No translation model is downloaded — showing the transcript '
              'only. Download M2M-100 or Hy-MT2 from Models.',
        if (paths.warning != null) paths.warning!,
      ];
      if (notes.isNotEmpty) state = state.copyWith(message: notes.join('\n'));
      await Future.wait([
        _spawnAsr(paths),
        if (paths.translatorPath != null) _spawnTranslator(paths),
      ]);
      await _startAudio(replayFile);
      state = state.copyWith(status: LiveStatus.running);
      Log.instance.i('live', 'started', fields: {
        'asr': p.basename(paths.asrPath),
        'recognizer': state.recognizer,
        'translator': paths.translatorPath == null
            ? '-'
            : p.basename(paths.translatorPath!),
        'lid': paths.lidMode.name,
        'source': replayFile == null ? _config.audioSource.name : 'file',
      });
    } catch (e, st) {
      await _teardown();
      if (_cancelled) {
        // Stopped by the user while loading: not an error.
        Log.instance.i('live', 'start cancelled while loading');
        state = state.copyWith(status: LiveStatus.idle);
        return;
      }
      Log.instance.w('live', 'start failed', error: e, stack: st);
      state = state.copyWith(status: LiveStatus.error, message: '$e');
    }
  }

  bool _cancelled = false;

  Future<void> stop() async {
    if (!state.isActive) return;
    if (state.status == LiveStatus.loading) {
      // start() is still waiting for the workers; tearing them down makes
      // it fail, and it reports the cancellation instead of an error.
      _cancelled = true;
      state = state.copyWith(status: LiveStatus.stopping);
      await _teardown();
      return;
    }
    state = state.copyWith(status: LiveStatus.stopping);
    await _stopAudio();
    // Let the recogniser commit the sentence in progress (it closes its
    // models and acknowledges), then drain the translations that follow.
    await _stopWorker(_asrPort, _asrStopped, const Duration(seconds: 30));
    _asrPort = null;
    final until = DateTime.now().add(const Duration(seconds: 10));
    while ((_inFlight || _queue.isNotEmpty) && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _teardown();
    Log.instance.i('live', 'stopped', fields: {'sentences': _session.length});
    final saved = await _saveToHistory();
    state = state.copyWith(
      status: LiveStatus.idle,
      tail: '',
      held: '',
      drafts: const {},
      savedHistoryId: saved,
    );
  }

  /// The session as a History entry, like every other transcription run:
  /// one segment per sentence, labelled with its language, its translations
  /// on the lines below (so every export format carries them), and the
  /// structured form in segment metadata. Returns the entry id.
  Future<String?> _saveToHistory() async {
    if (_session.isEmpty) return null;
    try {
      final segments = [
        for (final u in _session)
          // Model text (recogniser + translator): built through the
          // emotion-stripping factory like every other model-text segment,
          // even though the worker already strips — the duty sits on the
          // destination type, not on whichever source got there first.
          TranscriptionSegment.fromModelText(
            rawText: [
              u.text,
              for (final t in u.targets)
                if (u.translations[t] != null) '[$t] ${u.translations[t]}',
            ].join('\n'),
            startTime: u.t0,
            endTime: u.t1 > u.t0 ? u.t1 : u.t0,
            speaker: languageAutonym(u.lang),
            metadata: {
              // EU AI Act Art. 50(2): a sentence with a machine translation
              // under it is marked, so every exporter, History's Copy and
              // the share sheet attach the translation disclosure through
              // the one rule (AiTextDisclosure.forKind / FileUtils).
              if (u.translations.isNotEmpty) 'generated': 'translation',
              'liveTranslate': true,
              'lang': u.lang,
              'source': u.text,
              'translations': Map<String, String>.from(u.translations),
            },
          ),
      ];
      final langs = {for (final u in _session) u.lang};
      final entry = await ref.read(historyServiceProvider).save(
            engineId: 'crispasr-live',
            segments: segments,
            modelId: _asrName,
            language: langs.length == 1 ? langs.first : langs.join('+'),
            processingTime: state.startedAt == null
                ? Duration.zero
                : DateTime.now().difference(state.startedAt!),
          );
      Log.instance.i('live', 'session saved to history',
          fields: {'id': entry.id, 'sentences': _session.length});
      return entry.id;
    } catch (e, st) {
      Log.instance.w('live', 'history save failed', error: e, stack: st);
      return null;
    }
  }

  final _asrStopped = StreamController<void>.broadcast();
  final _trStopped = StreamController<void>.broadcast();

  /// Ask a worker to close its models and wait for it to say so: killing an
  /// isolate skips the native close and leaks the loaded weights.
  Future<void> _stopWorker(
      SendPort? port, StreamController<void> stopped, Duration limit) async {
    if (port == null) return;
    final done = stopped.stream.first;
    port.send({'type': 'stop'});
    await done.timeout(limit, onTimeout: () {});
  }

  Future<void> _teardown() async {
    await _stopAudio();
    await Future.wait([
      _stopWorker(_asrPort, _asrStopped, const Duration(seconds: 5)),
      _stopWorker(_trPort, _trStopped, const Duration(seconds: 5)),
    ]);
    _asrIso?.kill(priority: Isolate.beforeNextEvent);
    _trIso?.kill(priority: Isolate.beforeNextEvent);
    _asrEvents?.close();
    _trEvents?.close();
    _asrIso = _trIso = null;
    _asrPort = _trPort = null;
    _asrEvents = _trEvents = null;
  }

  /// `onExit` delivers null, `onError` a [message, stack] list. Either one
  /// before the worker said "ready" means it will never be ready.
  bool _isolateDied(Object? msg, Completer<void> ready, String what) {
    if (msg != null && msg is! List) return false;
    if (!ready.isCompleted) {
      ready.completeError(LiveTranslateException(msg is List && msg.isNotEmpty
          ? 'The $what stopped while loading: ${msg.first}'
          : 'The $what stopped while loading.'));
    }
    return true;
  }

  Future<void> _spawnAsr(LiveModelPaths paths) async {
    final events = ReceivePort();
    _asrEvents = events;
    final ready = Completer<void>();
    events.listen((msg) {
      if (msg is SendPort) {
        _asrPort = msg;
        return;
      }
      if (_isolateDied(msg, ready, 'recogniser')) return;
      if (msg is! Map) return;
      if (msg['type'] == 'ready') {
        state = state.copyWith(
            recognizer:
                '${msg['backend']} · ${msg['streamingMode'] ?? 'buffered recognition'}');
        if (!ready.isCompleted) ready.complete();
      } else if (msg['type'] == 'error' && !ready.isCompleted) {
        ready.completeError(LiveTranslateException(msg['message'] as String));
      } else {
        _onAsrEvent(msg);
      }
    });
    final lidMode = switch (paths.lidMode) {
      LiveLidMode.fixed => 'fixed',
      LiveLidMode.audio => 'audio',
      LiveLidMode.text => 'text',
      _ => 'recognizer',
    };
    _asrIso = await Isolate.spawn(
      liveAsrWorkerEntry,
      LiveAsrArgs(
        readyPort: events.sendPort,
        modelPath: paths.asrPath,
        backend: paths.asrBackend,
        vadModelPath: paths.vadPath,
        lidMode: lidMode,
        audioLidPath: paths.audioLidPath,
        textLidPath: paths.textLidPath,
        fixedSource:
            paths.lidMode == LiveLidMode.fixed ? _config.fixedSource : null,
        expectedSources: _config.expectedSources.toList(),
        finalSilenceMs: _config.finalSilenceMs,
        // Match the room-mic CLI calibration: overlapping Cohere windows
        // need more processing headroom than native streaming updates.
        stepMs: paths.asrBackend == 'cohere' ? 3000 : 500,
        nThreads: paths.asrBackend == 'cohere'
            ? _asrThreads.clamp(1, 3)
            : _asrThreads,
        // Native Nemotron uses many small graphs; on Metal their dispatch
        // overhead dominates. Match the backend's CPU default on macOS.
        useGpu: !(Platform.isMacOS && paths.asrBackend == 'nemotron'),
        directTranslationTarget: paths.directTranslationTarget,
      ),
      debugName: 'live-asr',
      onExit: events.sendPort,
      onError: events.sendPort,
    );
    // No deadline: loading weights on a busy or swapping machine can take
    // minutes, and the board says "Loading models…" with a Stop button. A
    // worker that dies completes this with an error (see _isolateDied).
    await ready.future;
  }

  Future<void> _spawnTranslator(LiveModelPaths paths) async {
    final events = ReceivePort();
    _trEvents = events;
    final ready = Completer<void>();
    events.listen((msg) {
      if (msg is SendPort) {
        _trPort = msg;
        return;
      }
      if (_isolateDied(msg, ready, 'translator')) return;
      if (msg is! Map) return;
      switch (msg['type']) {
        case 'ready':
          state = state.copyWith(translator: msg['kind'] as String?);
          if (!ready.isCompleted) ready.complete();
        case 'error':
          if (!ready.isCompleted) {
            ready.completeError(
                LiveTranslateException(msg['message'] as String));
          }
        case 'stopped':
          _trStopped.add(null);
        default:
          _onTranslatorEvent(msg);
      }
    });
    _trIso = await Isolate.spawn(
      liveTranslatorWorkerEntry,
      LiveTranslatorArgs(
        readyPort: events.sendPort,
        modelPath: paths.translatorPath!,
        backend: paths.translatorBackend ?? 'm2m100',
        nThreads: _translatorThreads,
      ),
      debugName: 'live-translator',
      onExit: events.sendPort,
      onError: events.sendPort,
    );
    await ready.future;
  }

  Future<void> _startAudio(String? replayFile) async {
    if (replayFile != null) {
      final data =
          await ref.read(audioServiceProvider).loadAudioFile(File(replayFile));
      final pcm = data.sampleRate == 16000
          ? data.samples
          : _resample(data.samples, data.sampleRate, 16000);
      var pos = 0;
      const chunk = 1600; // 100 ms
      _replayTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (pos >= pcm.length) {
          t.cancel();
          return;
        }
        final end = (pos + chunk).clamp(0, pcm.length);
        _asrPort?.send({
          'type': 'audio',
          'capturedAtMs': DateTime.now().millisecondsSinceEpoch,
          'pcm': Float32List.fromList(Float32List.sublistView(pcm, pos, end)),
        });
        pos = end;
      });
      return;
    }
    Stream<Float32List>? frames;
    if (_config.audioSource == LiveAudioSource.systemAudio) {
      final svc = ref.read(systemAudioCaptureServiceProvider);
      frames = await svc.start();
      _stopCapture = () => unawaited(svc.stop());
    } else {
      final audio = ref.read(audioServiceProvider);
      final id = _config.microphoneDeviceId;
      final devices = id.isEmpty ? null : await audio.listInputDevices();
      final device = devices?.where((d) => d.id == id).firstOrNull;
      if (id.isNotEmpty && device == null) {
        throw const LiveTranslateException(
            'The selected microphone is disconnected. Reconnect it or choose '
            'another microphone in the live setup.');
      }
      Log.instance.i('live', 'microphone selected', fields: {
        'deviceId': device?.id ?? 'system-default',
        'deviceLabel': device?.label ?? 'system-default',
      });
      frames = await audio.startStreamingRecording(device: device);
      if (frames == null) {
        throw const LiveTranslateException(
            'The microphone is unavailable — check the permission in the '
            'system settings.');
      }
      _stopCapture = () => unawaited(audio.stopStreaming());
    }
    _audioSub = frames.listen(
      (f) => _asrPort?.send({
        'type': 'audio',
        'pcm': f,
        'capturedAtMs': DateTime.now().millisecondsSinceEpoch
      }),
      // The capture died (device gone, tool failed): say so on the board
      // rather than showing a silent room.
      onError: (Object e) {
        Log.instance.w('live', 'audio input failed', error: e);
        state = state.copyWith(message: 'Audio input stopped: $e');
      },
    );
  }

  Future<void> _stopAudio() async {
    _replayTimer?.cancel();
    _replayTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    _stopCapture?.call();
    _stopCapture = null;
  }

  static Float32List _resample(Float32List x, int from, int to) {
    final n = (x.length * to / from).floor();
    final out = Float32List(n);
    final ratio = from / to;
    for (var i = 0; i < n; i++) {
      final s = i * ratio;
      final i0 = s.floor();
      final i1 = i0 + 1 < x.length ? i0 + 1 : i0;
      final f = s - i0;
      out[i] = x[i0] * (1 - f) + x[i1] * f;
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------

  void _onAsrEvent(Map<Object?, Object?> msg) {
    switch (msg['type']) {
      case 'unit':
        final lang = (msg['lang'] as String?) ?? _config.fixedSource;
        final targets = _config.targetsFor(lang);
        final t1 = (msg['t'] as num?)?.toDouble() ?? 0;
        final unit = LiveUnit(
          key: _nextKey++,
          lang: lang,
          text: msg['text'] as String,
          targets: _trPort == null
              ? [
                  for (final t in targets)
                    if (msg['translations'] is Map &&
                        (msg['translations'] as Map).containsKey(t))
                      t
                ]
              : targets,
          at: DateTime.now(),
          t0: _lastUnitT,
          t1: t1,
        );
        _lastUnitT = t1;
        // A speech-translation recogniser (Index-Echo) brings its own
        // translation; only the remaining targets go to the translator.
        final direct = msg['translations'];
        if (direct is Map) {
          for (final e in direct.entries) {
            if (e.key is String && e.value is String) {
              unit.translations[e.key as String] = e.value as String;
            }
          }
        }
        _byKey[unit.key] = unit;
        _session.add(unit);
        var units = [...state.units, unit];
        if (units.length > _maxUnits) {
          final drop = units.length - _maxUnits;
          for (final u in units.take(drop)) {
            _byKey.remove(u.key);
          }
          units = units.sublist(drop);
        }
        state =
            state.copyWith(units: units, currentLang: lang, drafts: const {});
        for (final t in unit.targets) {
          if (unit.translations.containsKey(t)) continue;
          _queue.add((unit.key, unit.text, lang, t));
        }
        _pump();
      case 'held':
        state = state.copyWith(
            held: msg['text'] as String, currentLang: msg['lang'] as String?);
        _requestDraft();
      case 'tail':
        state = state.copyWith(
            tail: msg['text'] as String,
            currentLang: msg['lang'] as String?,
            drafts: (msg['text'] as String).isEmpty && state.held.isEmpty
                ? const {}
                : null);
        _requestDraft();
      case 'lang':
        state = state.copyWith(currentLang: msg['lang'] as String?);
      case 'stats':
        state = state.copyWith(
          stepMs: msg['stepMs'] as int,
          behindSec: (msg['behindSec'] as num).toDouble(),
        );
      case 'error':
        Log.instance.w('live', '${msg['message']}');
        state = state.copyWith(message: msg['message'] as String);
      case 'stopped':
        _asrStopped.add(null);
    }
  }

  void _onTranslatorEvent(Map<Object?, Object?> msg) {
    _inFlight = false;
    final key = msg['key'];
    final tgt = msg['tgt'] as String;
    if (key is String && key.startsWith('draft:')) {
      if (key == 'draft:$_draftSeq' && msg['type'] == 'translation') {
        state = state
            .copyWith(drafts: {...state.drafts, tgt: msg['text'] as String});
      }
    } else if (key is int) {
      final unit = _byKey[key];
      if (unit != null) {
        if (msg['type'] == 'translation') {
          unit.translations[tgt] = msg['text'] as String;
          final ms = msg['ms'] as int;
          _avgCommitMs = _avgCommitMs == 0 ? ms : (_avgCommitMs * 3 + ms) ~/ 4;
        } else {
          unit.failed.add(tgt);
          Log.instance.w('live', 'translation failed: ${msg['message']}');
        }
        state = state.copyWith(translateMs: _avgCommitMs);
      }
    }
    _pump();
  }

  void _requestDraft() {
    if (!_config.showDrafts || _trPort == null) return;
    if (_avgCommitMs > _draftBudgetMs) return;
    final text = [state.held, state.tail].where((s) => s.isNotEmpty).join(' ');
    final lang = state.currentLang;
    if (text.split(' ').length < 3 || lang == null) return;
    final targets = _config.targetsFor(lang);
    if (targets.isEmpty) return;
    _draftSeq++;
    // Only the newest draft matters; drafts go to the first target only, so
    // a three-language room does not triple the translator's load.
    _pendingDraft = (-_draftSeq, text, lang, targets.first);
    _pump();
  }

  void _pump() {
    if (_inFlight || _trPort == null) return;
    (Object, String, String, String)? next;
    if (_queue.isNotEmpty) {
      final q = _queue.removeFirst();
      next = (q.$1, q.$2, q.$3, q.$4);
    } else if (_pendingDraft != null) {
      final d = _pendingDraft!;
      _pendingDraft = null;
      next = ('draft:$_draftSeq', d.$2, d.$3, d.$4);
    }
    if (next == null) return;
    _inFlight = true;
    _trPort!.send({
      'type': 'translate',
      'key': next.$1,
      'text': next.$2,
      'src': next.$3,
      'tgt': next.$4,
    });
  }
}

final liveTranslateProvider =
    NotifierProvider<LiveTranslateController, LiveTranslateState>(
        LiveTranslateController.new);
