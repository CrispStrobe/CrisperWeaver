part of 'crisperweaver.dart';

typedef _LiveLogNative = Void Function(Int32, Pointer<Void>, Pointer<Void>);
typedef _LiveLogSetNative = Void Function(
    Pointer<NativeFunction<_LiveLogNative>>, Pointer<Void>);
typedef _LiveLogSet = void Function(
    Pointer<NativeFunction<_LiveLogNative>>, Pointer<Void>);

// A process-scoped listener: native logging can originate on GPU threads.
// Never dereference the transient text pointer asynchronously. Retain the
// callback until process exit, without keeping the Dart isolate alive.
final _liveLogCallbacks = <NativeCallable<_LiveLogNative>>[];
void _quietLiveNativeLogs(DynamicLibrary lib) {
  final callback = NativeCallable<_LiveLogNative>.listener(
      (int level, Pointer<Void> text, Pointer<Void> user) {});
  callback.keepIsolateAlive = false;
  _liveLogCallbacks.add(callback);
  for (final symbol in ['whisper_log_set', 'ggml_log_set']) {
    if (lib.providesSymbol(symbol)) {
      lib.lookupFunction<_LiveLogSetNative, _LiveLogSet>(symbol)(
          callback.nativeFunction, nullptr);
    }
  }
}

class _LiveCmd extends _Base {
  _LiveCmd() {
    argParser
      ..addFlag('native-logs',
          negatable: false,
          help: 'Include verbose native engine diagnostics on stderr.')
      ..addFlag('list-devices',
          negatable: false,
          help: 'List macOS microphone IDs and names; no model needed.')
      ..addFlag('json',
          negatable: false,
          help: 'Emit JSONL events instead of readable captions.')
      ..addOption('device',
          help:
              'Microphone name, unique name fragment, or current ID. Required for capture.')
      ..addOption('model', abbr: 'm', help: 'Local recogniser model path.')
      ..addOption('backend', abbr: 'b', defaultsTo: 'cohere')
      ..addOption('language',
          abbr: 'l',
          defaultsTo: 'de',
          help: 'Fixed spoken language; no translation.')
      ..addOption('vad-model',
          help: 'Silero VAD model. Without it, adaptive energy VAD is used.')
      ..addOption('threads', defaultsTo: '3')
      ..addFlag('gpu', defaultsTo: true)
      ..addOption('step-ms',
          defaultsTo: '3000', help: 'Minimum audio between caption updates.')
      ..addOption('final-silence-ms', defaultsTo: '800')
      ..addOption('duration',
          help: 'Stop after this many seconds of captured audio.')
      ..addOption('max-lag',
          defaultsTo: '20',
          help:
              'Fail rather than queue unlimited audio when recognition stalls (seconds).')
      ..addOption('save-audio',
          help: 'Save captured 16 kHz mono WAV. Existing files are refused.')
      ..addOption('events',
          help:
              'Save all captions, level and latency events as JSONL. Existing files are refused.')
      ..addOption('input',
          help:
              'Replay an audio file in real time through the same live worker instead of a microphone.')
      ..addOption('ffmpeg',
          defaultsTo: 'ffmpeg', help: 'Capture/resampling executable.');
  }
  @override
  String get name => 'live';
  @override
  String get description =>
      'Live microphone captions with explicit input selection and recording.';

  @override
  Future<int> run() async {
    try {
      return await _runLive();
    } on UsageException {
      rethrow;
    } on ArgumentError {
      rethrow;
    } catch (error) {
      stderr.writeln('live: $error');
      return 1;
    }
  }

  Future<int> _runLive() async {
    final args = argResults!;
    final ffmpeg = args['ffmpeg'] as String;
    if (args['list-devices'] as bool) {
      final devices = await listMicrophones(ffmpeg);
      if (args['json'] as bool) {
        stdout.writeln(jsonEncode(devices.map((d) => d.toJson()).toList()));
      } else {
        for (final d in devices) {
          stdout.writeln('${d.id}\t${d.name}');
        }
      }
      return 0;
    }
    final model = args['model'] as String?;
    if (model == null) usageException('Pass --model for live recognition.');
    final modelPath = _absExisting(model, 'ASR model');
    final language = (args['language'] as String).trim();
    if (language.isEmpty || language == 'auto') {
      usageException('Live requires a fixed --language, e.g. de.');
    }
    final step = _intOpt('step-ms');
    final silence = _intOpt('final-silence-ms');
    final threads = _intOpt('threads');
    final maxLag = _doubleOpt('max-lag');
    final durationArg = args['duration'] as String?;
    final duration = durationArg == null ? null : double.tryParse(durationArg);
    if (step < 100 ||
        silence < 100 ||
        threads < 1 ||
        !maxLag.isFinite ||
        maxLag <= 0 ||
        (durationArg != null &&
            (duration == null || !duration.isFinite || duration <= 0))) {
      usageException(
          'Use positive finite --duration/--max-lag, --threads >= 1, --step-ms/--final-silence-ms >= 100.');
    }
    final input = args['input'] as String?;
    if (args.rest.isNotEmpty) usageException('Use --input for file replay.');
    if (input != null && args['device'] != null) {
      usageException('Choose --input or --device, not both.');
    }
    if (input == null && args['device'] == null) {
      usageException('Select a microphone with --device; see --list-devices.');
    }
    final inputPath =
        input == null ? null : _absExisting(input, 'Replay audio');
    final vad = args['vad-model'] as String?;
    final vadPath = vad == null ? null : _absExisting(vad, 'VAD model');
    for (final key in ['save-audio', 'events']) {
      final path = args[key] as String?;
      if (path != null && File(path).existsSync()) {
        usageException('--$key already exists: $path');
      }
    }
    if (args['save-audio'] != null && args['save-audio'] == args['events']) {
      usageException('--save-audio and --events must be different files.');
    }
    MicrophoneDevice? device;
    if (inputPath == null) {
      device = selectMicrophone(
          await listMicrophones(ffmpeg), args['device'] as String);
    }
    final eventFile = args['events'] == null
        ? null
        : File(args['events'] as String).openWrite();
    void emit(Map<String, Object?> e) {
      final event = {'at': DateTime.now().toUtc().toIso8601String(), ...e};
      final line = jsonEncode(event);
      eventFile?.writeln(line);
      if (args['json'] as bool) {
        stdout.writeln(line);
      } else {
        switch (e['type']) {
          case 'unit':
            stdout.writeln('[${e['lang']}] ${e['text']}');
          case 'tail':
            stderr.writeln('… ${e['text']}');
          case 'ready':
            stderr.writeln(
                'Ready: ${e['backend']} / ${e['streamingMode']} / $language');
          case 'capturing':
            stderr.writeln(
                'Capturing ${device?.name ?? inputPath}. Ctrl+C stops and saves.');
          case 'level':
            stderr.writeln(
                'mic: ${e['rmsDbfs']} dBFS RMS, peak ${e['peakDbfs']} dBFS');
          case 'error':
            stderr.writeln('live: ${e['message']}');
          case 'summary':
            stderr.writeln(
                'Saved ${e['audioSeconds']} s; ${e['units']} committed units; max lag ${e['maxBehindSec']} s.');
        }
      }
    }

    final events = ReceivePort();
    final ready = Completer<void>();
    final stopped = Completer<void>();
    SendPort? commands;
    Process? capture;
    Isolate? worker;
    Timer? watchdog;
    StreamSubscription<ProcessSignal>? interrupt;
    StreamSubscription<ProcessSignal>? terminate;
    Pcm16WavSink? wav;
    var failed = false;
    var stopping = false;
    final cancelled = Completer<void>();
    Timer? captureKillTimer;
    var units = 0;
    var samples = 0;
    var maxBehind = 0.0;
    var lastWorkerEvent = DateTime.now();
    final latencies = <num>[];
    void stopCapture() {
      stopping = true;
      if (!cancelled.isCompleted) cancelled.complete();
      capture?.kill(ProcessSignal.sigterm);
      captureKillTimer ??= Timer(const Duration(seconds: 3), () {
        capture?.kill(ProcessSignal.sigkill);
      });
    }

    final eventSub = events.listen((event) {
      if (event is SendPort) {
        commands = event;
        return;
      }
      if (event is! Map) {
        failed = true;
        if (!ready.isCompleted) {
          ready.completeError(StateError('ASR worker exited: $event'));
        }
        stopCapture();
        return;
      }
      final e = Map<String, Object?>.from(event);
      lastWorkerEvent = DateTime.now();
      switch (e['type']) {
        case 'ready':
          if (!ready.isCompleted) ready.complete();
        case 'unit':
          units++;
        case 'stats':
          final behind = (e['behindSec'] as num).toDouble();
          maxBehind = math.max(maxBehind, behind);
          latencies.add(e['stepMs'] as num);
          if (behind > maxLag) {
            failed = true;
            emit({
              'type': 'error',
              'message':
                  'Recognition fell ${behind.toStringAsFixed(1)} s behind capture; stopping without dropping recorded audio.'
            });
            stopCapture();
          }
        case 'error':
          failed = true;
          if (!ready.isCompleted) {
            ready.completeError(StateError('${e['message']}'));
          }
          stopCapture();
        case 'stopped':
          if (!stopped.isCompleted) stopped.complete();
      }
      emit(e);
    });
    final framer = Pcm16Framer();
    var energy = 0.0;
    var peak = 0.0;
    var levelSamples = 0;
    var lastLevel = 0;
    var captured = false;
    void feed(Float32List pcm) {
      if (pcm.isEmpty) return;
      if (!captured) {
        captured = true;
        emit({
          'type': 'capturing',
          'device': device?.toJson(),
          'input': inputPath
        });
      }
      commands!.send({
        'type': 'audio',
        'pcm': pcm,
        'capturedAtMs': DateTime.now().millisecondsSinceEpoch
      });
      samples += pcm.length;
      for (final v in pcm) {
        energy += v * v;
        peak = math.max(peak, v.abs());
      }
      levelSamples += pcm.length;
      if (samples - lastLevel >= 16000 * 5) {
        double db(double value) =>
            value <= 0 ? -120 : 20 * math.log(value) / math.ln10;
        emit({
          'type': 'level',
          'audioSeconds': samples / 16000,
          'rmsDbfs': db(math.sqrt(energy / levelSamples)).toStringAsFixed(1),
          'peakDbfs': db(peak).toStringAsFixed(1)
        });
        lastLevel = samples;
        energy = 0;
        peak = 0;
        levelSamples = 0;
      }
    }

    try {
      interrupt = ProcessSignal.sigint.watch().listen((_) => stopCapture());
      terminate = ProcessSignal.sigterm.watch().listen((_) => stopCapture());
      stderr.writeln(
          'Loading ${args['backend']}; input: ${device?.name ?? inputPath}');
      if (!(args['native-logs'] as bool)) {
        _quietLiveNativeLogs(
            dylib ?? DynamicLibrary.open(crispasr.CrispASR.defaultLibName()));
      }
      worker = await Isolate.spawn(
          liveAsrWorkerEntry,
          LiveAsrArgs(
            readyPort: events.sendPort,
            modelPath: modelPath,
            backend: args['backend'] as String,
            libPath: lib,
            vadModelPath: vadPath,
            lidMode: 'fixed',
            fixedSource: language,
            expectedSources: [language],
            stepMs: step,
            finalSilenceMs: silence,
            nThreads: threads,
            useGpu: args['gpu'] as bool,
          ),
          onError: events.sendPort,
          errorsAreFatal: true);
      await Future.any([ready.future, cancelled.future])
          .timeout(const Duration(minutes: 3));
      if (stopping) return failed ? 1 : 0;
      if (args['save-audio'] != null) {
        wav = Pcm16WavSink(args['save-audio'] as String);
      }
      final captureArgs = [
        '-hide_banner',
        '-loglevel',
        'warning',
        '-nostdin',
        if (inputPath == null) ...[
          '-f',
          'avfoundation',
          '-i',
          ':${device!.id}'
        ] else ...[
          '-re',
          '-i',
          inputPath
        ],
        if (duration != null) ...['-t', '$duration'],
        '-ac',
        '1',
        '-ar',
        '16000',
        '-f',
        's16le',
        'pipe:1'
      ];
      capture = await Process.start(ffmpeg, captureArgs);
      final captureErrors = StringBuffer();
      final stderrDone = capture.stderr.transform(utf8.decoder).forEach((s) {
        captureErrors.write(s);
      });
      lastWorkerEvent = DateTime.now();
      final captureStart = DateTime.now();
      watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
        final now = DateTime.now();
        if (!captured && now.difference(captureStart).inSeconds > 15 ||
            captured && now.difference(lastWorkerEvent).inSeconds > maxLag) {
          failed = true;
          emit({
            'type': 'error',
            'message': captured
                ? 'Recognition stopped responding; capture stopped.'
                : 'No microphone audio received. Check macOS microphone access and device mute.'
          });
          stopCapture();
        }
      });
      await for (final bytes in capture.stdout) {
        wav?.add(bytes);
        for (final pcm in framer.add(bytes)) {
          feed(pcm);
        }
      }
      feed(framer.finish());
      final rc = await capture.exitCode;
      await stderrDone;
      watchdog.cancel();
      if (rc != 0 && !stopping || samples == 0) {
        failed = true;
        emit({
          'type': 'error',
          'message': 'Capture failed ($rc): $captureErrors'
        });
      }
      commands!.send({'type': 'stop'});
      await stopped.future.timeout(const Duration(seconds: 60));
      latencies.sort();
      emit({
        'type': 'summary',
        'audioSeconds': samples / 16000,
        'units': units,
        'maxBehindSec': maxBehind,
        'medianStepMs':
            latencies.isEmpty ? null : latencies[latencies.length ~/ 2],
        'p95StepMs': latencies.isEmpty
            ? null
            : latencies[(latencies.length * .95).ceil() - 1],
        // Includes VAD and recognition inside periodic steps. The final
        // stop/flush is outside this measurement, so this is not total CPU use.
        'periodicProcessingSeconds':
            latencies.fold<num>(0, (sum, ms) => sum + ms) / 1000,
        'periodicProcessingFraction': samples == 0
            ? null
            : latencies.fold<num>(0, (sum, ms) => sum + ms) /
                1000 /
                (samples / 16000),
        'failed': failed,
        'saveAudio': args['save-audio'],
        'events': args['events']
      });
      return failed ? 1 : 0;
    } catch (error) {
      emit({'type': 'error', 'message': '$error'});
      return 1;
    } finally {
      watchdog?.cancel();
      captureKillTimer?.cancel();
      capture?.kill(ProcessSignal.sigterm);
      await interrupt?.cancel();
      await terminate?.cancel();
      worker?.kill(priority: Isolate.immediate);
      await eventSub.cancel();
      events.close();
      wav?.close();
      await eventFile?.close();
    }
  }
}
