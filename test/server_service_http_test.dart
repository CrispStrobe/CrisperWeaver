// Unit coverage for the built-in OpenAI-compatible HTTP server
// (`lib/services/server_service.dart`).
//
// `server_service_test.dart` next door covers the routing + validation
// paths that return *before* any service is touched. This file covers
// everything past that point: it starts the real ServerService on an
// ephemeral port and overrides the Riverpod providers it reads with
// fakes, so the request handlers, the multipart parser, the response
// formatters (json / text / srt / vtt / diarized_json), the EU AI Act
// consent + disclosure gates, and the WebSocket streaming protocol all
// run for real without a GGUF, a dylib, or a model download.
//
// Nothing here needs the native engine. The handful of endpoints that
// call straight into `crispasr` FFI (backends, denoise, watermark
// embed, align, text-LID) are asserted tolerantly — the point of those
// cases is the request plumbing around the native call, which is the
// part this repo owns; whether libcrispasr is present differs between
// a dev box and the CI runner and must not decide the test.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisper_weaver/engines/transcription_engine.dart';
import 'package:crisper_weaver/main.dart'
    show modelServiceProvider, transcriptionServiceProvider;
import 'package:crisper_weaver/native/crispasr_import.dart' as crispasr;
import 'package:crisper_weaver/services/aligner_service.dart';
import 'package:crisper_weaver/services/audio_service.dart';
import 'package:crisper_weaver/services/lid_service.dart';
import 'package:crisper_weaver/services/model_service.dart';
import 'package:crisper_weaver/services/punc_service.dart';
import 'package:crisper_weaver/services/server_service.dart';
import 'package:crisper_weaver/services/text_translation_service.dart';
import 'package:crisper_weaver/services/transcription_service.dart';
import 'package:crisper_weaver/services/tts_service.dart';
import 'package:crisper_weaver/services/vad_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Fakes. Each `implements` + `noSuchMethod`, so only the members the server
// actually calls need a body; anything else throws a named error rather than
// silently returning null.
// ---------------------------------------------------------------------------

class _Unstubbed extends Error {
  _Unstubbed(this.member);
  final Symbol member;
  @override
  String toString() => 'fake: $member was called but is not stubbed';
}

class _FakeEngine implements TranscriptionEngine {
  _FakeEngine({this.engineId = 'fake-engine', this.currentModelId = 'fake-v1'});

  @override
  final String engineId;
  @override
  final String? currentModelId;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

/// Records the decoded form fields so a test can assert that
/// `/v1/audio/transcriptions` parsed them into the right arguments.
class _TranscribeCall {
  String? language;
  bool? wordTimestamps;
  bool? diarization;
  bool? translate;
  String? initialPrompt;
  bool? vad;
  bool? restorePunctuation;
  double? temperature;
  int? bestOf;
  String? askPrompt;
  String? targetLanguage;
  AdvancedTranscribeOptions? advanced;
}

class _FakeTranscriptionService implements TranscriptionService {
  _FakeTranscriptionService({
    this.engine,
    this.segments = const <TranscriptionSegment>[],
    this.transcribeError,
    this.streamFactory,
  });

  final TranscriptionEngine? engine;
  final List<TranscriptionSegment> segments;
  final Object? transcribeError;

  /// Returns the stream `transcribeStream` should hand back. Returning
  /// null models "this model can't stream".
  final Stream<TranscriptionSegment>? Function(Stream<Float32List> audio)?
      streamFactory;

  final _TranscribeCall lastCall = _TranscribeCall();
  Stream<Float32List>? lastAudioStream;

  @override
  TranscriptionEngine? get currentEngine => engine;

  @override
  Future<List<TranscriptionSegment>> transcribeFile(
    File audioFile, {
    String? language,
    bool enableDiarization = false,
    bool enableWordTimestamps = false,
    bool translate = false,
    bool beamSearch = false,
    String? initialPrompt,
    bool vad = false,
    bool restorePunctuation = false,
    String? targetLanguage,
    String? askPrompt,
    double temperature = 0.0,
    int bestOf = 1,
    int? minSpeakers,
    int? maxSpeakers,
    AdvancedTranscribeOptions advanced = const AdvancedTranscribeOptions(),
    double startOffsetSec = 0.0,
    void Function(double progress)? onProgress,
    void Function(TranscriptionSegment segment)? onSegment,
  }) async {
    lastCall
      ..language = language
      ..wordTimestamps = enableWordTimestamps
      ..diarization = enableDiarization
      ..translate = translate
      ..initialPrompt = initialPrompt
      ..vad = vad
      ..restorePunctuation = restorePunctuation
      ..temperature = temperature
      ..bestOf = bestOf
      ..askPrompt = askPrompt
      ..targetLanguage = targetLanguage
      ..advanced = advanced;
    // The handler writes the upload to a temp file before calling us; prove
    // it arrived rather than trusting the path string.
    expect(await audioFile.exists(), isTrue);
    final err = transcribeError;
    if (err != null) throw err;
    return segments;
  }

  @override
  Stream<TranscriptionSegment>? transcribeStream(
    Stream<Float32List> audioStream, {
    String? language,
    bool enableWordTimestamps = false,
  }) {
    lastAudioStream = audioStream;
    lastCall.language = language;
    return streamFactory?.call(audioStream);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

class _FakeTtsService implements TtsService {
  _FakeTtsService({
    this.prepareStatus,
    this.audio,
    this.synthesizeError,
    this.s2sAudio,
    this.s2sError,
  });

  final TtsLoadStatus? prepareStatus;
  final SynthesizedAudio? audio;
  final Object? synthesizeError;
  final SynthesizedAudio? s2sAudio;
  final Object? s2sError;

  String? preparedModel;
  String? preparedVoice;
  String? synthesizedText;
  double? synthesizedSpeed;
  String? wavVoiceRefPath;
  String? wavDisclaimerOverride;
  bool? wavVoiceConverted;
  Float32List? s2sInput;

  @override
  Future<TtsLoadStatus> prepare({
    required String modelName,
    String? voiceName,
    String? codecName,
    String? refText,
    String? voiceWavPath,
    String? speakerName,
    int? speakerId,
    String? instructPrompt,
    String? referenceLanguage,
    int minSpeechTokens = 0,
  }) async {
    preparedModel = modelName;
    preparedVoice = voiceName;
    return prepareStatus ?? TtsLoadStatus.ready('fake');
  }

  @override
  Future<SynthesizedAudio?> synthesize(
    String text, {
    bool trimSilence = false,
    double speed = 1.0,
    int? ttsSteps,
    double? temperature,
    double? topP,
    double? minP,
    double? cfgWeight,
    double? exaggeration,
    double? repetitionPenalty,
    int? maxSpeechTokens,
    int? seed,
    double? frequencyPenalty,
    int? topK,
    bool? doSample,
    int? ttsNumCandidates,
    String? g2pDict,
    double? noiseTemp,
  }) async {
    synthesizedText = text;
    synthesizedSpeed = speed;
    final err = synthesizeError;
    if (err != null) throw err;
    return audio;
  }

  @override
  Future<SynthesizedAudio?> speechToSpeech(Float32List inputPcm) async {
    s2sInput = inputPcm;
    final err = s2sError;
    if (err != null) throw err;
    return s2sAudio;
  }

  @override
  Future<File> writeWav(
    SynthesizedAudio audio, {
    String? basename,
    String? voiceRefPath,
    bool voiceConverted = false,
    String? disclaimerOverrideAttestation,
  }) async {
    wavVoiceRefPath = voiceRefPath;
    wavVoiceConverted = voiceConverted;
    wavDisclaimerOverride = disclaimerOverrideAttestation;
    final dir = await Directory.systemTemp.createTemp('fake_tts_wav_');
    final f = File('${dir.path}/out.wav');
    await f.writeAsBytes(const [0x52, 0x49, 0x46, 0x46, 0x00]); // "RIFF\0"
    return f;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

class _FakeTranslationService implements TextTranslationService {
  _FakeTranslationService({this.result = 'hallo welt', this.error});

  final String result;
  final Object? error;

  String? lastModel;
  String? lastSrc;
  String? lastTgt;
  int? lastMaxTokens;

  @override
  Future<String> translate({
    required String modelName,
    required String text,
    required String srcLang,
    required String tgtLang,
    int maxTokens = 0,
  }) async {
    lastModel = modelName;
    lastSrc = srcLang;
    lastTgt = tgtLang;
    lastMaxTokens = maxTokens;
    final err = error;
    if (err != null) throw err;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

class _FakeAudioService implements AudioService {
  _FakeAudioService({this.error});

  final Object? error;

  @override
  Future<AudioData> loadAudioFile(File audioFile) async {
    final err = error;
    if (err != null) throw err;
    return AudioData(
      samples: Float32List.fromList(List<double>.filled(1600, 0.1)),
      sampleRate: 16000,
      duration: const Duration(milliseconds: 100),
      channels: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

class _FakeVadService implements VadService {
  _FakeVadService(this.spans);
  final List<crispasr.VadSpan> spans;

  @override
  Future<List<crispasr.VadSpan>> detectSpeechSpans(
    Float32List pcm, {
    VadBackend backend = VadBackend.silero,
    double threshold = 0.5,
    int minSpeechMs = 250,
    int minSilenceMs = 100,
  }) async =>
      spans;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

class _FakeLidService implements LidService {
  _FakeLidService(this.code);
  final String? code;

  @override
  Future<String?> detectIfModelAvailable(Float32List pcm,
          {double minConfidence = 0.35}) async =>
      code;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

class _FakePuncService implements PuncService {
  _FakePuncService(this.restored);
  final List<TranscriptionSegment> restored;

  @override
  Future<List<TranscriptionSegment>> restore(
          List<TranscriptionSegment> segments) async =>
      restored;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

class _FakeAlignerService implements AlignerService {
  _FakeAlignerService(this.path);
  final String? path;

  String? lastLanguage;
  String? lastExplicit;

  @override
  Future<String?> findAligner({String? language, String? explicit}) async {
    lastLanguage = language;
    lastExplicit = explicit;
    return path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

class _FakeModelService implements ModelService {
  _FakeModelService(this.dir);
  final String dir;

  @override
  Future<void> initialize() async {}

  @override
  String whisperCppDir() => dir;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw _Unstubbed(invocation.memberName);
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// One running server plus the fakes it was wired with.
class _Harness {
  _Harness(this.container, this.server, this.base);
  final ProviderContainer container;
  final ServerService server;
  final String base;

  Uri uri(String path) => Uri.parse('$base$path');
}

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The test binding installs a mock HttpClient that answers every request
    // with a 400. This suite talks to a real socket, so it has to go.
    HttpOverrides.global = null;
    tmpDir = await Directory.systemTemp.createTemp('server_http_test_');
    // The upload handlers spool to getTemporaryDirectory() before decoding.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tmpDir.path,
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  Future<_Harness> start({
    TranscriptionService? tx,
    TtsService? tts,
    TextTranslationService? translation,
    AudioService? audio,
    VadService? vad,
    LidService? lid,
    PuncService? punc,
    AlignerService? aligner,
    ModelService? models,
  }) async {
    final container = ProviderContainer(overrides: [
      transcriptionServiceProvider
          .overrideWithValue(tx ?? _FakeTranscriptionService()),
      ttsServiceProvider.overrideWithValue(tts ?? _FakeTtsService()),
      textTranslationServiceProvider
          .overrideWithValue(translation ?? _FakeTranslationService()),
      audioServiceProvider.overrideWithValue(audio ?? _FakeAudioService()),
      vadServiceProvider
          .overrideWithValue(vad ?? _FakeVadService(const [])),
      lidServiceProvider.overrideWithValue(lid ?? _FakeLidService(null)),
      puncServiceProvider
          .overrideWithValue(punc ?? _FakePuncService(const [])),
      alignerServiceProvider
          .overrideWithValue(aligner ?? _FakeAlignerService(null)),
      modelServiceProvider
          .overrideWithValue(models ?? _FakeModelService(tmpDir.path)),
    ]);
    final server = container.read(serverServiceProvider);
    final base = await server.start(port: 0);
    addTearDown(() async {
      await server.stop();
      container.dispose();
    });
    return _Harness(container, server, base);
  }

  /// Bytes that survive the multipart parser's trailing-CRLF trim — the
  /// parser strips 0x0D/0x0A off the tail of every part, so a fixture must
  /// not end in one.
  Uint8List fakeAudioBytes() =>
      Uint8List.fromList(List<int>.generate(512, (i) => (i % 251) + 1));

  Future<http.Response> postMultipart(
    Uri uri, {
    Map<String, String> fields = const {},
    Map<String, Uint8List> files = const {},
    String filename = 'audio.wav',
  }) async {
    final req = http.MultipartRequest('POST', uri)..fields.addAll(fields);
    files.forEach((name, bytes) {
      req.files.add(http.MultipartFile.fromBytes(name, bytes,
          filename: name == 'file' ? filename : '$name.wav'));
    });
    return http.Response.fromStream(await req.send());
  }

  Future<http.Response> postJson(Uri uri, Object? body) => http.post(uri,
      headers: {'content-type': 'application/json'},
      body: body is String ? body : jsonEncode(body));

  /// Poll until [ready] holds. A fixed sleep is a flake waiting to happen
  /// here: the coverage-instrumented CI run is an order of magnitude slower
  /// than a bare one, and every WebSocket assertion below depends on the
  /// server having got round to processing a frame we just sent.
  Future<void> waitFor(bool Function() ready, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  TranscriptionSegment seg(
    String text,
    double start,
    double end, {
    String? speaker,
    Map<String, dynamic> metadata = const {},
  }) =>
      TranscriptionSegment(
        text: text,
        startTime: start,
        endTime: end,
        speaker: speaker,
        metadata: metadata,
      );

  // -------------------------------------------------------------------------
  group('lifecycle', () {
    test('boundUrl/isRunning track start and stop', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final svc = container.read(serverServiceProvider);
      expect(svc.isRunning, isFalse);
      expect(svc.boundUrl, isNull);

      final url = await svc.start(port: 0);
      expect(svc.isRunning, isTrue);
      expect(svc.boundUrl, url);
      expect(url, startsWith('http://127.0.0.1:'));

      await svc.stop();
      expect(svc.isRunning, isFalse);
      expect(svc.boundUrl, isNull);
      // stop() on an already-stopped server is a no-op, not a throw.
      await svc.stop();
    });

    test('start() while already running returns the same URL', () async {
      final h = await start();
      expect(await h.server.start(port: 0), h.base);
    });

    test('start() on a taken port throws ServerStartException', () async {
      final blocker = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => blocker.close(force: true));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final svc = container.read(serverServiceProvider);
      await expectLater(
        svc.start(port: blocker.port),
        throwsA(isA<ServerStartException>()),
      );
      expect(svc.isRunning, isFalse);
      expect(const ServerStartException('boom').toString(),
          contains('ServerStartException: boom'));
    });
  });

  // -------------------------------------------------------------------------
  group('GET /health', () {
    test('reports the loaded engine and model', () async {
      final h = await start(
        tx: _FakeTranscriptionService(
            engine: _FakeEngine(engineId: 'crispasr', currentModelId: 'base')),
      );
      final r = await http.get(h.uri('/health'));
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], contains('application/json'));
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['ok'], isTrue);
      expect(body['service'], 'CrisperWeaver');
      expect(body['engine'], 'crispasr');
      expect(body['model'], 'base');
    });

    test('reports nulls when no engine is loaded', () async {
      final h = await start();
      final body =
          jsonDecode((await http.get(h.uri('/health'))).body) as Map;
      expect(body['ok'], isTrue);
      expect(body['engine'], isNull);
      expect(body['model'], isNull);
    });

    test('GET /backends answers (200 with a list, or 500 without the '
        'native lib)', () async {
      final h = await start();
      final r = await http.get(h.uri('/backends'));
      expect(r.statusCode, anyOf(200, 500));
      if (r.statusCode == 200) {
        expect(jsonDecode(r.body),
            containsPair('backends', isA<List<dynamic>>()));
      }
    });
  });

  // -------------------------------------------------------------------------
  group('POST /v1/audio/transcriptions — request validation', () {
    test('rejects a non-multipart body', () async {
      final h = await start();
      final r = await postJson(h.uri('/v1/audio/transcriptions'), {});
      expect(r.statusCode, 400);
      expect(r.body, contains('multipart/form-data'));
    });

    test('rejects multipart with no boundary parameter', () async {
      final h = await start();
      final r = await http.post(h.uri('/v1/audio/transcriptions'),
          headers: {'content-type': 'multipart/form-data'}, body: 'x');
      expect(r.statusCode, 400);
      expect(r.body, contains('boundary'));
    });

    test('rejects a multipart body with no "file" part', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'model': 'whisper-1'});
      expect(r.statusCode, 400);
      expect(r.body, contains('file'));
    });

    test('refuses an affective audio-Q&A prompt with 400 (AI Act Art. 5)',
        () async {
      final h = await start(
          tx: _FakeTranscriptionService(engine: _FakeEngine()));
      final r = await postMultipart(
        h.uri('/v1/audio/transcriptions'),
        fields: {'ask': 'what emotion is the speaker showing?'},
        files: {'file': fakeAudioBytes()},
      );
      expect(r.statusCode, 400);
      expect(r.body, contains('Refusing this audio Q&A prompt'));
      expect(r.body, contains('emotion'));
    });

    test('500s when no engine is loaded', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 500);
      expect(r.body, contains('no transcription engine loaded'));
    });

    test('maps an engine failure to 500', () async {
      final h = await start(
        tx: _FakeTranscriptionService(
          engine: _FakeEngine(),
          transcribeError: StateError('decoder exploded'),
        ),
      );
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 500);
      expect(r.body, contains('transcribe failed'));
      expect(r.body, contains('decoder exploded'));
    });
  });

  group('POST /v1/audio/transcriptions — form fields', () {
    test('every documented form field reaches transcribeFile', () async {
      final tx = _FakeTranscriptionService(
          engine: _FakeEngine(), segments: [seg('hi', 0, 1)]);
      final h = await start(tx: tx);
      final r = await postMultipart(
        h.uri('/v1/audio/transcriptions'),
        fields: {
          'model': 'whisper-1',
          'language': 'de',
          'word_timestamps': 'TRUE',
          'temperature': '0.4',
          'best_of': '5',
          'initial_prompt': 'a hint',
          'hotwords': 'CrisperWeaver',
          'hotwords_boost': '2.5',
          'translate': 'true',
          'vad': 'true',
          'diarize': 'true',
          'punctuation': 'true',
          'target_language': 'en',
          'aligner': '/tmp/aligner.gguf',
        },
        files: {'file': fakeAudioBytes()},
      );
      expect(r.statusCode, 200);
      final c = tx.lastCall;
      expect(c.language, 'de');
      // `TRUE` proves the flag parse is case-insensitive.
      expect(c.wordTimestamps, isTrue);
      expect(c.temperature, 0.4);
      expect(c.bestOf, 5);
      expect(c.initialPrompt, 'a hint');
      expect(c.translate, isTrue);
      expect(c.vad, isTrue);
      expect(c.diarization, isTrue);
      expect(c.restorePunctuation, isTrue);
      expect(c.targetLanguage, 'en');
      expect(c.advanced!.alignerModel, '/tmp/aligner.gguf');
      expect(c.advanced!.hotwords, 'CrisperWeaver');
      expect(c.advanced!.hotwordsBoost, 2.5);
    });

    test('unparseable numeric fields fall back to their defaults', () async {
      final tx = _FakeTranscriptionService(engine: _FakeEngine());
      final h = await start(tx: tx);
      final r = await postMultipart(
        h.uri('/v1/audio/transcriptions'),
        fields: {
          'temperature': 'hot',
          'best_of': 'many',
          'hotwords_boost': 'loud',
          'word_timestamps': 'yes-please',
        },
        files: {'file': fakeAudioBytes()},
      );
      expect(r.statusCode, 200);
      expect(tx.lastCall.temperature, 0.0);
      expect(tx.lastCall.bestOf, 1);
      expect(tx.lastCall.advanced!.hotwordsBoost, 1.5);
      // Anything that isn't literally "true" is false.
      expect(tx.lastCall.wordTimestamps, isFalse);
    });

    test('`prompt` is accepted as an alias for `initial_prompt`', () async {
      final tx = _FakeTranscriptionService(engine: _FakeEngine());
      final h = await start(tx: tx);
      await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'prompt': 'via alias'}, files: {'file': fakeAudioBytes()});
      expect(tx.lastCall.initialPrompt, 'via alias');
    });

    test('a benign `ask` prompt passes the affective screen', () async {
      final tx = _FakeTranscriptionService(engine: _FakeEngine());
      final h = await start(tx: tx);
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'ask': 'what did they say about the budget?'},
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      expect(tx.lastCall.askPrompt, 'what did they say about the budget?');
    });
  });

  group('POST /v1/audio/transcriptions — response formats', () {
    Future<_Harness> withSegments(List<TranscriptionSegment> segments) =>
        start(
            tx: _FakeTranscriptionService(
                engine: _FakeEngine(), segments: segments));

    test('json (default) carries task, duration, text and segments',
        () async {
      final h = await withSegments([
        seg('hello there', 0.0, 1.5),
        seg('general kenobi', 1.5, 3.25, speaker: 'S1'),
      ]);
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      expect(r.headers, isNot(contains('x-content-ai-generated')));
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['task'], 'transcribe');
      expect(body.containsKey('_disclosure'), isFalse);
      expect(body['duration'], 3.25);
      expect(body['text'], 'hello there general kenobi');
      final segs = body['segments'] as List;
      expect(segs, hasLength(2));
      expect(segs[0]['id'], 0);
      expect(segs[0].containsKey('speaker'), isFalse);
      expect(segs[1]['speaker'], 'S1');
      expect(segs[1]['start'], 1.5);
    });

    test('an empty result reports duration 0', () async {
      final h = await withSegments(const []);
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          files: {'file': fakeAudioBytes()});
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['duration'], 0.0);
      expect(body['text'], '');
      expect(body['segments'], isEmpty);
    });

    test('verbose_json takes the same branch as json', () async {
      final h = await withSegments([seg('x', 0, 1)]);
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'response_format': 'verbose_json'},
          files: {'file': fakeAudioBytes()});
      expect(jsonDecode(r.body)['task'], 'transcribe');
    });

    test('text returns bare text/plain', () async {
      final h = await withSegments([seg('one', 0, 1), seg('two', 1, 2)]);
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'response_format': 'TEXT'},
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], contains('text/plain'));
      expect(r.body, 'one two');
    });

    test('srt numbers cues from 1 and formats hh:mm:ss,mmm', () async {
      final h = await withSegments([
        seg('first', 0.0, 1.5),
        seg('second', 61.25, 3661.5, speaker: 'Alice'),
      ]);
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'response_format': 'srt'},
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      final lines = const LineSplitter().convert(r.body);
      expect(lines[0], '1');
      expect(lines[1], '00:00:00,000 --> 00:00:01,500');
      expect(lines[2], 'first');
      expect(lines[4], '2');
      expect(lines[5], '00:01:01,250 --> 01:01:01,500');
      expect(lines[6], 'Alice: second');
    });

    test('vtt starts with WEBVTT and uses a dot for milliseconds', () async {
      final h = await withSegments([seg('hi', 2.5, 4.0)]);
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'response_format': 'vtt'},
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], contains('text/vtt'));
      expect(r.body, startsWith('WEBVTT'));
      expect(r.body, contains('00:00:02.500 --> 00:00:04.000'));
      expect(r.body, contains('hi'));
    });

    test('diarized_json groups cues by speaker', () async {
      final h = await withSegments([
        seg('a', 0, 1, speaker: 'S1'),
        seg('b', 1, 2, speaker: 'S2'),
        seg('c', 2, 3, speaker: 'S1'),
        seg('d', 3, 4),
      ]);
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'response_format': 'diarized_json'},
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['task'], 'transcribe');
      expect(body['duration'], 4.0);
      final speakers = body['speakers'] as Map<String, dynamic>;
      expect(speakers.keys, containsAll(['S1', 'S2', 'unknown']));
      expect(speakers['S1'], hasLength(2));
      expect((speakers['S1'] as List)[1]['id'], 2);
      expect(speakers['unknown'], hasLength(1));
    });
  });

  group('POST /v1/audio/transcriptions — AI Act Art. 50(2) disclosure', () {
    test('translate=true marks the response as generated', () async {
      final h = await start(
          tx: _FakeTranscriptionService(
              engine: _FakeEngine(), segments: [seg('hallo', 0, 1)]));
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'translate': 'true'}, files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      expect(r.headers['x-content-ai-generated'], 'true');
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['task'], 'translate');
      expect(body['_disclosure'], isA<String>());
      expect((body['_disclosure'] as String), isNotEmpty);
    });

    test('a non-empty target_language marks it too', () async {
      final h = await start(
          tx: _FakeTranscriptionService(
              engine: _FakeEngine(), segments: [seg('hallo', 0, 1)]));
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'target_language': 'de'},
          files: {'file': fakeAudioBytes()});
      expect(r.headers['x-content-ai-generated'], 'true');
      expect(jsonDecode(r.body)['task'], 'translate');
    });

    test('a blank target_language does not', () async {
      final h = await start(
          tx: _FakeTranscriptionService(
              engine: _FakeEngine(), segments: [seg('hallo', 0, 1)]));
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'target_language': '   '},
          files: {'file': fakeAudioBytes()});
      expect(r.headers.containsKey('x-content-ai-generated'), isFalse);
      expect(jsonDecode(r.body)['task'], 'transcribe');
    });

    test('a segment stamped generated:audio-qa wins over the request flag',
        () async {
      final h = await start(
        tx: _FakeTranscriptionService(engine: _FakeEngine(), segments: [
          seg('yes', 0, 1),
          seg('the answer', 1, 2, metadata: const {'generated': 'audio-qa'}),
        ]),
      );
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'translate': 'true'}, files: {'file': fakeAudioBytes()});
      expect(r.headers['x-content-ai-generated'], 'true');
      expect(jsonDecode(r.body)['task'], 'audio-qa');
    });

    test('srt ships the disclosure as a cue at 00:00:00', () async {
      final h = await start(
          tx: _FakeTranscriptionService(
              engine: _FakeEngine(), segments: [seg('hallo', 0, 1)]));
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'translate': 'true', 'response_format': 'srt'},
          files: {'file': fakeAudioBytes()});
      final lines = const LineSplitter().convert(r.body);
      expect(lines[0], '0');
      expect(lines[1], '00:00:00,000 --> 00:00:03,000');
      expect(lines[2], isNotEmpty);
      // The real first cue still follows, renumbered from 1.
      expect(lines[4], '1');
      expect(r.headers['x-content-ai-generated'], 'true');
    });

    test('vtt ships the disclosure as a NOTE', () async {
      final h = await start(
          tx: _FakeTranscriptionService(
              engine: _FakeEngine(), segments: [seg('hallo', 0, 1)]));
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'translate': 'true', 'response_format': 'vtt'},
          files: {'file': fakeAudioBytes()});
      expect(r.body, startsWith('WEBVTT'));
      expect(r.body, contains('NOTE '));
    });

    test('text appends the disclosure to the body', () async {
      final h = await start(
          tx: _FakeTranscriptionService(
              engine: _FakeEngine(), segments: [seg('hallo', 0, 1)]));
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'translate': 'true', 'response_format': 'text'},
          files: {'file': fakeAudioBytes()});
      expect(r.body, contains('hallo'));
      expect(r.body.length, greaterThan('hallo'.length));
      expect(r.headers['x-content-ai-generated'], 'true');
    });

    test('diarized_json carries _disclosure when generated', () async {
      final h = await start(
          tx: _FakeTranscriptionService(
              engine: _FakeEngine(),
              segments: [seg('hallo', 0, 1, speaker: 'S1')]));
      final r = await postMultipart(h.uri('/v1/audio/transcriptions'),
          fields: {'translate': 'true', 'response_format': 'diarized_json'},
          files: {'file': fakeAudioBytes()});
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['task'], 'translate');
      expect(body['_disclosure'], isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  group('POST /v1/audio/speech', () {
    test('rejects invalid JSON', () async {
      final h = await start();
      final r = await postJson(h.uri('/v1/audio/speech'), 'not json');
      expect(r.statusCode, 400);
      expect(r.body, contains('invalid JSON'));
    });

    test('rejects a body with no model/input', () async {
      final h = await start();
      final r = await postJson(h.uri('/v1/audio/speech'), {'input': '  '});
      expect(r.statusCode, 400);
      expect(r.body, contains('model + input'));
    });

    test('synthesises from a JSON body', () async {
      final tts = _FakeTtsService(
          audio: SynthesizedAudio(
              samples: Float32List.fromList(const [0.0, 0.5]),
              sampleRate: 24000));
      final h = await start(tts: tts);
      final r = await postJson(h.uri('/v1/audio/speech'), {
        'model': 'kokoro',
        'input': 'hello world',
        'speed': 1.25,
      });
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], 'audio/wav');
      expect(r.headers['x-content-ai-generated'], 'true');
      expect(r.bodyBytes, isNotEmpty);
      expect(tts.preparedModel, 'kokoro');
      expect(tts.preparedVoice, isNull);
      expect(tts.synthesizedText, 'hello world');
      expect(tts.synthesizedSpeed, 1.25);
    });

    test('speed is clamped to the OpenAI 0.25–4.0 range', () async {
      final tts = _FakeTtsService(
          audio: SynthesizedAudio(
              samples: Float32List(2), sampleRate: 24000));
      final h = await start(tts: tts);
      await postJson(h.uri('/v1/audio/speech'),
          {'model': 'kokoro', 'input': 'x', 'speed': 99});
      expect(tts.synthesizedSpeed, 4.0);
      await postJson(h.uri('/v1/audio/speech'),
          {'model': 'kokoro', 'input': 'x', 'speed': 0.01});
      expect(tts.synthesizedSpeed, 0.25);
    });

    test('a voice-clone request without consent is 403 (AI Act Art. 50(4))',
        () async {
      final h = await start();
      final r = await postJson(h.uri('/v1/audio/speech'),
          {'model': 'vibevoice', 'input': 'hi', 'voice': 'alice'});
      expect(r.statusCode, 403);
      expect(r.body, contains('consent_attestation'));
      expect(r.body, contains('Art. 50(4)'));
    });

    test('consent_attestation unlocks a voice-clone request', () async {
      final tts = _FakeTtsService(
          audio: SynthesizedAudio(
              samples: Float32List(2), sampleRate: 24000));
      final h = await start(tts: tts);
      final r = await postJson(h.uri('/v1/audio/speech'), {
        'model': 'vibevoice',
        'input': 'hi',
        'voice': 'alice',
        'consent_attestation': 'I have consent.',
      });
      expect(r.statusCode, 200);
      expect(tts.preparedVoice, 'alice');
      expect(tts.wavVoiceRefPath, 'alice');
      // Consent alone must NOT suppress the audible beep.
      expect(tts.wavDisclaimerOverride, isNull);
    });

    test('disclaimer_override_attestation still counts as consent, and is '
        'forwarded to writeWav', () async {
      final tts = _FakeTtsService(
          audio: SynthesizedAudio(
              samples: Float32List(2), sampleRate: 24000));
      final h = await start(tts: tts);
      final r = await postJson(h.uri('/v1/audio/speech'), {
        'model': 'vibevoice',
        'input': 'hi',
        'voice': 'alice',
        'disclaimer_override_attestation': 'I accept responsibility.',
      });
      expect(r.statusCode, 200);
      expect(tts.wavDisclaimerOverride, 'I accept responsibility.');
    });

    test('a blank consent_attestation is not consent', () async {
      final h = await start();
      final r = await postJson(h.uri('/v1/audio/speech'), {
        'model': 'vibevoice',
        'input': 'hi',
        'voice': 'alice',
        'consent_attestation': '   ',
      });
      expect(r.statusCode, 403);
    });

    test('a failed prepare() is a 500 naming the missing piece', () async {
      final h = await start(
          tts: _FakeTtsService(
              prepareStatus: TtsLoadStatus.missing(voiceName: 'af_heart')));
      final r = await postJson(
          h.uri('/v1/audio/speech'), {'model': 'kokoro', 'input': 'hi'});
      expect(r.statusCode, 500);
      expect(r.body, contains('tts.prepare failed'));
      expect(r.body, contains('af_heart'));
    });

    test('a prepare() error message is surfaced', () async {
      final h = await start(
          tts: _FakeTtsService(prepareStatus: TtsLoadStatus.error('no gguf')));
      final r = await postJson(
          h.uri('/v1/audio/speech'), {'model': 'kokoro', 'input': 'hi'});
      expect(r.statusCode, 500);
      expect(r.body, contains('no gguf'));
    });

    test('a throwing synthesize() is a 500', () async {
      final h = await start(
          tts: _FakeTtsService(synthesizeError: StateError('oom')));
      final r = await postJson(
          h.uri('/v1/audio/speech'), {'model': 'kokoro', 'input': 'hi'});
      expect(r.statusCode, 500);
      expect(r.body, contains('synthesize failed'));
    });

    test('a null synthesize() result is a 500', () async {
      final h = await start(tts: _FakeTtsService());
      final r = await postJson(
          h.uri('/v1/audio/speech'), {'model': 'kokoro', 'input': 'hi'});
      expect(r.statusCode, 500);
      expect(r.body, contains('synthesize returned null'));
    });

    test('multipart with no boundary is 400', () async {
      final h = await start();
      final r = await http.post(h.uri('/v1/audio/speech'),
          headers: {'content-type': 'multipart/form-data'}, body: 'x');
      expect(r.statusCode, 400);
      expect(r.body, contains('boundary'));
    });

    test('multipart voice_file becomes the voice reference path', () async {
      final tts = _FakeTtsService(
          audio: SynthesizedAudio(
              samples: Float32List(2), sampleRate: 24000));
      final h = await start(tts: tts);
      final r = await postMultipart(
        h.uri('/v1/audio/speech'),
        fields: {
          'model': 'vibevoice',
          'input': 'clone me',
          'speed': '2.0',
          'consent_attestation': 'I have consent.',
        },
        files: {'voice_file': fakeAudioBytes()},
      );
      expect(r.statusCode, 200);
      expect(tts.synthesizedSpeed, 2.0);
      // The upload was spooled into the temp dir and handed on as the voice.
      expect(tts.preparedVoice, isNotNull);
      expect(tts.preparedVoice, contains('crispasr-server-voice-'));
      // …and cleaned up once the response was built.
      expect(File(tts.preparedVoice!).existsSync(), isFalse);
    });

    test('a multipart request missing input is 400 and still cleans up',
        () async {
      final h = await start();
      final before = tmpDir.listSync().length;
      final r = await postMultipart(h.uri('/v1/audio/speech'),
          fields: {'model': 'vibevoice'},
          files: {'voice_file': fakeAudioBytes()});
      expect(r.statusCode, 400);
      expect(tmpDir.listSync().length, before);
    });

    test('a multipart voice_file with no consent is 403 and cleans up',
        () async {
      final h = await start();
      final before = tmpDir.listSync().length;
      final r = await postMultipart(h.uri('/v1/audio/speech'),
          fields: {'model': 'vibevoice', 'input': 'hi'},
          files: {'voice_file': fakeAudioBytes()});
      expect(r.statusCode, 403);
      expect(tmpDir.listSync().length, before);
    });
  });

  // -------------------------------------------------------------------------
  group('POST /v1/translations', () {
    test('rejects invalid JSON', () async {
      final h = await start();
      final r = await postJson(h.uri('/v1/translations'), 'nope');
      expect(r.statusCode, 400);
      expect(r.body, contains('invalid JSON'));
    });

    test('rejects a body missing any required field', () async {
      final h = await start();
      for (final body in <Map<String, Object?>>[
        {},
        {'text': 'hi'},
        {'text': 'hi', 'src': 'en'},
        {'text': 'hi', 'src': 'en', 'tgt': 'de'},
        {'text': '   ', 'src': 'en', 'tgt': 'de', 'model': 'm'},
      ]) {
        final r = await postJson(h.uri('/v1/translations'), body);
        expect(r.statusCode, 400, reason: '$body');
        expect(r.body, contains('model + text + src + tgt'));
      }
    });

    test('translates and marks the result as AI-generated', () async {
      final svc = _FakeTranslationService(result: 'hallo welt');
      final h = await start(translation: svc);
      final r = await postJson(h.uri('/v1/translations'), {
        'model': 'nllb',
        'text': 'hello world',
        'src': 'en',
        'tgt': 'de',
        'max_tokens': 42,
      });
      expect(r.statusCode, 200);
      expect(r.headers['x-content-ai-generated'], 'true');
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['translation'], 'hallo welt');
      expect(body['_disclosure'], isA<String>());
      expect(svc.lastModel, 'nllb');
      expect(svc.lastMaxTokens, 42);
    });

    test('source_language/target_language are accepted as aliases', () async {
      final svc = _FakeTranslationService();
      final h = await start(translation: svc);
      final r = await postJson(h.uri('/v1/translations'), {
        'model': 'nllb',
        'text': 'hello',
        'source_language': 'en',
        'target_language': 'fr',
      });
      expect(r.statusCode, 200);
      expect(svc.lastSrc, 'en');
      expect(svc.lastTgt, 'fr');
      // Default max_tokens when the caller omits it.
      expect(svc.lastMaxTokens, 200);
    });

    test('a TextTranslationException becomes a 500 with its message',
        () async {
      final h = await start(
          translation: _FakeTranslationService(
              error: const TextTranslationException('model not downloaded')));
      final r = await postJson(h.uri('/v1/translations'),
          {'model': 'nllb', 'text': 'hi', 'src': 'en', 'tgt': 'de'});
      expect(r.statusCode, 500);
      expect(r.body, contains('model not downloaded'));
    });
  });

  // -------------------------------------------------------------------------
  group('POST /v1/audio/vad', () {
    test('returns the detected spans', () async {
      final h = await start(
        vad: _FakeVadService(const [
          crispasr.VadSpan(start: 0.1, end: 0.9),
          crispasr.VadSpan(start: 1.4, end: 2.0),
        ]),
      );
      final r = await postMultipart(h.uri('/v1/audio/vad'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      final spans = (jsonDecode(r.body) as Map)['spans'] as List;
      expect(spans, hasLength(2));
      expect(spans[0], {'start': 0.1, 'end': 0.9});
      expect(spans[1]['end'], 2.0);
    });

    test('a multipart body with no file is 400', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/vad'));
      expect(r.statusCode, 400);
      expect(r.body, contains('file'));
    });

    test('an audio decode failure is 400, not 500', () async {
      final h = await start(
          audio: _FakeAudioService(error: StateError('bad riff header')));
      final r = await postMultipart(h.uri('/v1/audio/vad'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 400);
      expect(r.body, contains('audio decode failed'));
    });
  });

  group('POST /v1/audio/language', () {
    test('returns the detected language code', () async {
      final h = await start(lid: _FakeLidService('de'));
      final r = await postMultipart(h.uri('/v1/audio/language'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      expect(jsonDecode(r.body)['language'], 'de');
    });

    test('500s when no LID model is available', () async {
      final h = await start(lid: _FakeLidService(null));
      final r = await postMultipart(h.uri('/v1/audio/language'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 500);
      expect(r.body, contains('no LID model available'));
    });

    test('an audio decode failure is 400', () async {
      final h = await start(
          audio: _FakeAudioService(error: StateError('nope')),
          lid: _FakeLidService('de'));
      final r = await postMultipart(h.uri('/v1/audio/language'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 400);
    });
  });

  group('POST /v1/text/punctuate', () {
    test('returns the restored text', () async {
      final h = await start(
          punc: _FakePuncService([seg('Hello, world.', 0, 0)]));
      final r = await postJson(
          h.uri('/v1/text/punctuate'), {'text': 'hello world'});
      expect(r.statusCode, 200);
      expect(jsonDecode(r.body)['text'], 'Hello, world.');
    });

    test('falls back to the input when the restorer returns nothing',
        () async {
      final h = await start(punc: _FakePuncService(const []));
      final r = await postJson(
          h.uri('/v1/text/punctuate'), {'text': 'hello world'});
      expect(r.statusCode, 200);
      expect(jsonDecode(r.body)['text'], 'hello world');
    });

    test('a whitespace-only text is 400', () async {
      final h = await start();
      final r =
          await postJson(h.uri('/v1/text/punctuate'), {'text': '   '});
      expect(r.statusCode, 400);
    });
  });

  // -------------------------------------------------------------------------
  group('POST /v1/audio/diarize', () {
    test('500s when no engine is loaded', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/diarize'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 500);
      expect(r.body, contains('no transcription engine loaded'));
    });

    test('a multipart body with no file is 400', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/diarize'),
          fields: {'mode': 'x'});
      expect(r.statusCode, 400);
      expect(r.body, contains('file'));
    });

    test('with an engine it reaches the diariser and answers either way',
        () async {
      final h = await start(
          tx: _FakeTranscriptionService(
              engine: _FakeEngine(), segments: [seg('hi', 0, 1)]));
      final r = await postMultipart(h.uri('/v1/audio/diarize'),
          files: {'file': fakeAudioBytes()});
      // pyannote needs the native lib + a GGUF; without them the handler is
      // required to answer 500 "diarize failed" rather than hang or crash.
      expect(r.statusCode, anyOf(200, 500));
      if (r.statusCode == 500) expect(r.body, contains('diarize failed'));
    });
  });

  group('POST /v1/audio/watermark', () {
    test('detect mode on non-watermarked bytes reports false', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/watermark'),
          fields: {'mode': 'detect'}, files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['watermarked'], isFalse);
      expect(body.containsKey('synthetic'), isFalse);
    });

    test('a multipart body with no file is 400', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/watermark'),
          fields: {'mode': 'detect'});
      expect(r.statusCode, 400);
    });

    test('embed mode decodes the upload first, and 400s if that fails',
        () async {
      final h = await start(
          audio: _FakeAudioService(error: StateError('not audio')));
      final r = await postMultipart(h.uri('/v1/audio/watermark'),
          fields: {'mode': 'embed'}, files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 400);
      expect(r.body, contains('audio decode failed'));
    });

    test('embed mode on decodable audio answers WAV or 500', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/watermark'),
          fields: {'mode': 'embed'}, files: {'file': fakeAudioBytes()});
      expect(r.statusCode, anyOf(200, 500));
      if (r.statusCode == 200) {
        expect(r.headers['content-type'], 'audio/wav');
        expect(r.headers['x-content-ai-generated'], 'true');
        // 44-byte RIFF header written by _wavBytes.
        expect(r.bodyBytes.length, greaterThan(44));
        expect(utf8.decode(r.bodyBytes.sublist(0, 4)), 'RIFF');
      }
    });
  });

  group('POST /v1/audio/align', () {
    test('a multipart body with no file is 400', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/align'),
          fields: {'text': 'hello'});
      expect(r.statusCode, 400);
      expect(r.body, contains('file'));
    });

    test('a request with no text is 400', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/align'),
          fields: {'text': '  '}, files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 400);
      expect(r.body, contains('text'));
    });

    test('a decode failure is 400', () async {
      final h = await start(
          audio: _FakeAudioService(error: StateError('nope')));
      final r = await postMultipart(h.uri('/v1/audio/align'),
          fields: {'text': 'hello'}, files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 400);
      expect(r.body, contains('audio decode failed'));
    });

    test('500s when no aligner model is installed, forwarding the hints',
        () async {
      final aligner = _FakeAlignerService(null);
      final h = await start(aligner: aligner);
      final r = await postMultipart(h.uri('/v1/audio/align'), fields: {
        'text': 'hello',
        'language': 'de',
        'model': '/tmp/explicit.gguf',
      }, files: {
        'file': fakeAudioBytes()
      });
      expect(r.statusCode, 500);
      expect(r.body, contains('no aligner model available'));
      expect(aligner.lastLanguage, 'de');
      expect(aligner.lastExplicit, '/tmp/explicit.gguf');
    });

    test('with an aligner path it calls through and answers either way',
        () async {
      final h = await start(
          aligner: _FakeAlignerService('/nonexistent/aligner.gguf'));
      final r = await postMultipart(h.uri('/v1/audio/align'),
          fields: {'text': 'hello'}, files: {'file': fakeAudioBytes()});
      expect(r.statusCode, anyOf(200, 500));
      if (r.statusCode == 500) expect(r.body, contains('alignment failed'));
    });
  });

  group('POST /v1/text/language', () {
    test('500s when no text-LID model is on disk', () async {
      final h = await start(models: _FakeModelService(tmpDir.path));
      final r =
          await postJson(h.uri('/v1/text/language'), {'text': 'guten tag'});
      expect(r.statusCode, 500);
      expect(r.body, contains('no text-LID model available'));
    });

    test('a candidate GGUF on disk is picked up and used', () async {
      final modelsDir =
          await Directory('${tmpDir.path}/lid_models').create(recursive: true);
      addTearDown(() => modelsDir.delete(recursive: true));
      await File('${modelsDir.path}/cld3-f16.gguf').writeAsBytes([0, 1, 2]);
      final h = await start(models: _FakeModelService(modelsDir.path));
      final r =
          await postJson(h.uri('/v1/text/language'), {'text': 'guten tag'});
      // It got past the "no model" gate; the native call then fails or
      // succeeds depending on the runner.
      expect(r.statusCode, anyOf(200, 500));
      expect(r.body, isNot(contains('no text-LID model available')));
    });

    test('an explicit model path skips the scan', () async {
      final h = await start();
      final r = await postJson(h.uri('/v1/text/language'),
          {'text': 'guten tag', 'model': '/nonexistent/lid.gguf'});
      expect(r.statusCode, anyOf(200, 500));
      expect(r.body, isNot(contains('no text-LID model available')));
    });
  });

  group('POST /v1/audio/denoise', () {
    test('a decode failure is 400', () async {
      final h = await start(
          audio: _FakeAudioService(error: StateError('nope')));
      final r = await postMultipart(h.uri('/v1/audio/denoise'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 400);
    });

    test('decodable audio reaches RNNoise and answers WAV or 500', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/denoise'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, anyOf(200, 500));
      if (r.statusCode == 200) {
        expect(r.headers['content-type'], 'audio/wav');
        expect(utf8.decode(r.bodyBytes.sublist(0, 4)), 'RIFF');
      } else {
        expect(r.body, contains('denoise failed'));
      }
    });
  });

  group('POST /v1/audio/s2s', () {
    test('a multipart body with no file is 400', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/s2s'),
          fields: {'model': 'lfm2-audio'});
      expect(r.statusCode, 400);
    });

    test('a decode failure is 400', () async {
      final h = await start(
          audio: _FakeAudioService(error: StateError('nope')));
      final r = await postMultipart(h.uri('/v1/audio/s2s'),
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 400);
    });

    test('no consent attestation is 403 (voice conversion gate)', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/s2s'),
          fields: {'model': 'lfm2-audio'}, files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 403);
      expect(r.body, contains('Speech-to-speech voice conversion requires '
          'consent'));
    });

    test('a blank consent attestation is 403', () async {
      final h = await start();
      final r = await postMultipart(h.uri('/v1/audio/s2s'),
          fields: {'consent_attestation': '  '},
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 403);
    });

    test('a failed prepare() is 500', () async {
      final h = await start(
          tts: _FakeTtsService(prepareStatus: TtsLoadStatus.error('nope')));
      final r = await postMultipart(h.uri('/v1/audio/s2s'), fields: {
        'model': 'lfm2-audio',
        'consent_attestation': 'I have consent.',
      }, files: {
        'file': fakeAudioBytes()
      });
      expect(r.statusCode, 500);
      expect(r.body, contains('tts.prepare failed for s2s'));
    });

    test('a null speechToSpeech() result is 500 naming the requirement',
        () async {
      final h = await start(tts: _FakeTtsService());
      final r = await postMultipart(h.uri('/v1/audio/s2s'),
          fields: {'consent_attestation': 'I have consent.'},
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 500);
      expect(r.body, contains('speech-to-speech returned null'));
      expect(r.body, contains('lfm2-audio'));
    });

    test('a throwing speechToSpeech() is 500', () async {
      final h =
          await start(tts: _FakeTtsService(s2sError: StateError('boom')));
      final r = await postMultipart(h.uri('/v1/audio/s2s'),
          fields: {'consent_attestation': 'I have consent.'},
          files: {'file': fakeAudioBytes()});
      expect(r.statusCode, 500);
      expect(r.body, contains('speech-to-speech failed'));
    });

    test('a converted result is marked and flagged voiceConverted',
        () async {
      final tts = _FakeTtsService(
          s2sAudio: SynthesizedAudio(
              samples: Float32List.fromList(const [0.1, -0.1]),
              sampleRate: 24000));
      final h = await start(tts: tts);
      final r = await postMultipart(h.uri('/v1/audio/s2s'), fields: {
        'consent_attestation': 'I have consent.',
        'disclaimer_override_attestation': 'and I accept responsibility',
      }, files: {
        'file': fakeAudioBytes()
      });
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], 'audio/wav');
      expect(r.headers['x-content-ai-generated'], 'true');
      expect(tts.wavVoiceConverted, isTrue);
      expect(tts.wavDisclaimerOverride, 'and I accept responsibility');
      expect(tts.s2sInput, isNotNull);
      expect(tts.s2sInput!.length, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  group('WebSocket /v1/audio/stream', () {
    Future<WebSocket> connect(_Harness h) =>
        WebSocket.connect('${h.base.replaceFirst('http', 'ws')}'
            '/v1/audio/stream');

    test('a non-upgrade GET on the stream path falls through to shelf (404)',
        () async {
      final h = await start();
      final r = await http.get(h.uri('/v1/audio/stream'));
      expect(r.statusCode, 404);
    });

    test('refuses to open a session with no engine loaded', () async {
      final h = await start();
      final ws = await connect(h);
      final msgs = await ws.toList();
      expect(msgs, hasLength(1));
      expect(jsonDecode(msgs.single as String)['error'],
          contains('no transcription engine loaded'));
    });

    test('a config message opens the session and segments stream back',
        () async {
      final out = StreamController<TranscriptionSegment>();
      // Not `addTearDown(out.close)`: when the session never started,
      // nothing ever listened to this controller, so close()'s future
      // never completes and an awaited teardown hangs out the test.
      addTearDown(() {
        out.close();
      });
      final tx = _FakeTranscriptionService(
        engine: _FakeEngine(),
        streamFactory: (_) => out.stream,
      );
      final h = await start(tx: tx);
      final ws = await connect(h);
      final received = <Map<String, dynamic>>[];
      final done = Completer<void>();
      ws.listen((d) {
        received.add(jsonDecode(d as String) as Map<String, dynamic>);
        if (received.length == 2) done.complete();
      });

      ws.add(jsonEncode({'language': 'de'}));
      await waitFor(() => tx.lastAudioStream != null, 'the session to open');
      expect(tx.lastCall.language, 'de');

      out.add(seg('partial', 0.0, 1.0));
      out.add(seg('final bit', 1.0, 2.0,
          metadata: const {'final': true}));
      await done.future.timeout(const Duration(seconds: 5));

      expect(received[0]['text'], 'partial');
      expect(received[0]['start'], 0.0);
      expect(received[0].containsKey('final'), isFalse);
      expect(received[1]['text'], 'final bit');
      expect(received[1]['final'], isTrue);
      await ws.close();
    });

    test('binary PCM frames are decoded to float32 and forwarded', () async {
      final out = StreamController<TranscriptionSegment>();
      // Not `addTearDown(out.close)`: when the session never started,
      // nothing ever listened to this controller, so close()'s future
      // never completes and an awaited teardown hangs out the test.
      addTearDown(() {
        out.close();
      });
      final received = <Float32List>[];
      final tx = _FakeTranscriptionService(
        engine: _FakeEngine(),
        streamFactory: (audio) {
          audio.listen(received.add);
          return out.stream;
        },
      );
      final h = await start(tx: tx);
      final ws = await connect(h);
      // Two 16-bit LE samples: +0.5 full-scale and -1.0 full-scale.
      final frame = Uint8List(4);
      ByteData.view(frame.buffer)
        ..setInt16(0, 16384, Endian.little)
        ..setInt16(2, -32768, Endian.little);
      ws.add(frame);
      await waitFor(() => received.isNotEmpty, 'the PCM frame to arrive');
      expect(received, hasLength(1));
      expect(received.single, hasLength(2));
      expect(received.single[0], closeTo(0.5, 1e-4));
      expect(received.single[1], closeTo(-1.0, 1e-4));
      await ws.close();
    });

    test('a malformed config message is reported, not fatal', () async {
      final out = StreamController<TranscriptionSegment>();
      // Not `addTearDown(out.close)`: when the session never started,
      // nothing ever listened to this controller, so close()'s future
      // never completes and an awaited teardown hangs out the test.
      addTearDown(() {
        out.close();
      });
      final h = await start(
        tx: _FakeTranscriptionService(
            engine: _FakeEngine(), streamFactory: (_) => out.stream),
      );
      final ws = await connect(h);
      final first = Completer<Map<String, dynamic>>();
      ws.listen((d) {
        if (!first.isCompleted) {
          first.complete(jsonDecode(d as String) as Map<String, dynamic>);
        }
      });
      ws.add('{not json');
      final msg = await first.future.timeout(const Duration(seconds: 5));
      expect(msg['error'], contains('invalid config JSON'));
      await ws.close();
    });

    test('a model that cannot stream says so and closes', () async {
      final h = await start(
        tx: _FakeTranscriptionService(
            engine: _FakeEngine(), streamFactory: (_) => null),
      );
      final ws = await connect(h);
      ws.add(jsonEncode(const {'language': 'en'}));
      final msgs = await ws.toList();
      expect(msgs, hasLength(1));
      expect(jsonDecode(msgs.single as String)['error'],
          contains('streaming not supported'));
    });

    test('an engine stream error is relayed as {"error": …}', () async {
      final out = StreamController<TranscriptionSegment>();
      // Not `addTearDown(out.close)`: when the session never started,
      // nothing ever listened to this controller, so close()'s future
      // never completes and an awaited teardown hangs out the test.
      addTearDown(() {
        out.close();
      });
      final tx = _FakeTranscriptionService(
          engine: _FakeEngine(), streamFactory: (_) => out.stream);
      final h = await start(tx: tx);
      final ws = await connect(h);
      final first = Completer<Map<String, dynamic>>();
      ws.listen((d) {
        if (!first.isCompleted) {
          first.complete(jsonDecode(d as String) as Map<String, dynamic>);
        }
      });
      ws.add(jsonEncode(const {'language': 'en'}));
      await waitFor(() => tx.lastAudioStream != null, 'the session to open');
      out.addError(StateError('engine died'));
      final msg = await first.future.timeout(const Duration(seconds: 5));
      expect(msg['error'], contains('engine died'));
      await ws.close();
    });

    test('the engine stream closing sends {"done": true}', () async {
      final out = StreamController<TranscriptionSegment>();
      final tx = _FakeTranscriptionService(
          engine: _FakeEngine(), streamFactory: (_) => out.stream);
      final h = await start(tx: tx);
      final ws = await connect(h);
      final first = Completer<Map<String, dynamic>>();
      ws.listen((d) {
        if (!first.isCompleted) {
          first.complete(jsonDecode(d as String) as Map<String, dynamic>);
        }
      });
      ws.add(jsonEncode(const {'language': 'en'}));
      await waitFor(() => tx.lastAudioStream != null, 'the session to open');
      await out.close();
      final msg = await first.future.timeout(const Duration(seconds: 5));
      expect(msg['done'], isTrue);
      await ws.close();
    });

    test('the client closing tears the session down without an error',
        () async {
      final out = StreamController<TranscriptionSegment>();
      addTearDown(() {
        if (!out.isClosed) out.close();
      });
      final tx = _FakeTranscriptionService(
          engine: _FakeEngine(), streamFactory: (_) => out.stream);
      final h = await start(tx: tx);
      final ws = await connect(h);
      ws.add(jsonEncode(const {'language': 'en'}));
      await waitFor(() => tx.lastAudioStream != null, 'the session to open');
      await ws.close();
      // The server's onDone closes the audio controller it owns and cancels
      // the transcript subscription; the server itself stays up for the next
      // client rather than tearing down with the socket.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.server.isRunning, isTrue);
    });
  });
}
