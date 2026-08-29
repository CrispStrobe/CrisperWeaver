// CrisperWeaver CLI (PLAN §9.4) — headless access to the same on-device
// speech engine the GUI uses. It wraps `package:crispasr` directly (the
// FFI binding) rather than the app's Flutter-coupled service layer, because
// a `dart run` entrypoint has no Flutter bindings, path_provider, or
// Riverpod. So it reaches the engine capabilities (ASR/TTS/translate/VAD/
// LID/punctuation/alignment/diarization/watermark/speaker) at parity with
// what the GUI exposes; GUI-only orchestration (history, presets, cleanup)
// is intentionally out of scope — see docs/PARITY.md.
//
// Run:
//   dart run crisper_weaver:crisperweaver --help
//   dart run crisper_weaver:crisperweaver transcribe a.wav -m whisper.bin
//   dart run crisper_weaver:crisperweaver vad a.wav -m silero.bin
//
// The dylib is resolved from --lib, then $CRISPASR_LIB, then the
// conventional CrispASR build outputs.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:path/path.dart' as p;

import 'package:crisper_weaver/constants/app_constants.dart';
import 'package:crisper_weaver/native/vad_native.dart' show vadSlicesNative;
import 'package:crisper_weaver/services/audio_watermark_service.dart';
import 'package:crisper_weaver/services/content_provenance_service.dart';
import 'package:crisper_weaver/services/spread_spectrum_watermark.dart';
import 'package:crisper_weaver/utils/affective_prompt_guard.dart';
import 'package:crisper_weaver/utils/ai_text_disclosure.dart';
import 'package:crisper_weaver/utils/emotion_inference.dart';
import 'package:crisper_weaver/utils/marked_wav.dart';

String? _resolveLib(String? explicit) {
  for (final c in [
    explicit,
    Platform.environment['CRISPASR_LIB'],
    '../CrispASR/build/src/libcrispasr.dylib',
    '../CrispASR/build/src/libcrispasr.so',
    '../CrispASR/build/src/libwhisper.dylib',
  ]) {
    if (c != null && c.isNotEmpty && File(c).existsSync()) {
      return File(c).absolute.path;
    }
  }
  return explicit; // let the binding try its default loader path
}

/// Confidence floor for the spread-spectrum detector. Measured gap: clean
/// audio peaks at ~0.50, freshly marked audio sits at 0.78–0.91 (PLAN §15.8).
/// Kept in sync with `TtsService._watermarkConfidenceFloor`.
const double _watermarkFloor = 0.65;

/// Write AI-generated audio with the same EU AI Act marking the GUI applies
/// — Art. 50(4) beep on deepfake output, a verified Art. 50(2) watermark,
/// `LIST`/`INFO` provenance, and a C2PA manifest.
///
/// The CLI used to write bare 44-byte WAVs from `synthesize` and `s2s`,
/// so headless output carried none of this. [deepfake] is true for cloned
/// synthesis and for speech-to-speech voice conversion — PLAN §15.2g is the
/// same finding on the GUI/server side.
void _writeMarkedWav(
  File out,
  Float32List pcm,
  int rate, {
  required String modelName,
  String? voiceId,
  bool deepfake = false,
  String? disclaimerOverride,
  DynamicLibrary? dylib,
}) {
  final ts = DateTime.now();
  final override = disclaimerOverride?.trim();
  final beepSuppressed = override != null && override.isNotEmpty;

  // Art. 50(4): mandatory beep disclaimer on cloned / converted audio.
  var samples = pcm;
  if (deepfake) {
    if (!beepSuppressed) {
      final beeps = AudioWatermarkService.generateBeepDisclaimer(sampleRate: rate);
      final combined = Float32List(beeps.length + pcm.length);
      combined.setRange(0, beeps.length, beeps);
      combined.setRange(beeps.length, combined.length, pcm);
      samples = combined;
    } else {
      stderr.writeln('[DISCLAIMER-OVERRIDE] ts=${ts.toUtc().toIso8601String()} '
          'beep suppressed — burden shifted to caller; '
          'attestation="$override"');
    }
  }

  // Art. 50(2): probe for the watermark the C API normally auto-embeds
  // rather than assuming it ran, and fall back to the Dart embedder when it
  // did not — the same reasoning as PLAN §15.2f. Detection runs on the
  // pre-beep PCM because the native mark covers only the synthesised audio.
  var pcmForWav = samples;
  var fallback = false;
  if (SpreadSpectrumWatermark.detect(pcm) < _watermarkFloor) {
    pcmForWav = SpreadSpectrumWatermark.embed(samples);
    fallback = true;
  }

  var bytes = MarkedWav.encode(
    pcmForWav,
    rate,
    generatorVersion: AppConstants.appVersion,
    modelName: modelName,
    voiceId: voiceId,
    timestamp: ts,
  );
  if (fallback) {
    // LSB mark too, for back-compat with older detectors.
    bytes = AudioWatermarkService.embedWatermark(bytes,
        timestamp: ts, synthetic: true);
  }

  // Post-embed verification, so a silent marking failure is reported here
  // rather than discovered by whoever receives the file.
  final confidence = SpreadSpectrumWatermark.detect(pcmForWav);
  final watermarked = confidence >= _watermarkFloor;

  // C2PA: native COSE/X.509 signing where the dylib provides it, unsigned
  // JSON-LD manifest otherwise.
  var c2paSigned = false;
  if (crispasr.CrispasrC2pa.isAvailable(lib: dylib)) {
    final signed =
        crispasr.CrispasrC2pa.sign(bytes, format: 'audio/wav', lib: dylib);
    if (signed != null) {
      bytes = signed;
      c2paSigned = true;
    }
  }
  if (!c2paSigned) {
    bytes = ContentProvenanceService.injectIntoWav(
      bytes,
      generator: 'CrisperWeaver',
      generatorVersion: AppConstants.appVersion,
      modelName: modelName,
      voiceId: voiceId,
      timestamp: ts,
    );
  }

  out.writeAsBytesSync(bytes);
  stdout.writeln('marking: watermark=${watermarked ? "verified" : "FAILED"} '
      '(${confidence.toStringAsFixed(3)}, ${fallback ? "dart-fallback" : "native"}) '
      'c2pa=${c2paSigned ? "signed" : "unsigned-manifest"} '
      'beep=${deepfake ? (beepSuppressed ? "suppressed" : "yes") : "n/a"}');
  if (!watermarked && !c2paSigned) {
    stderr.writeln('[MARKING] no robust mark on this output — neither a '
        'verified watermark nor a signed C2PA manifest; only strippable '
        'container metadata (EU AI Act Art. 50(2)).');
  }
}

/// Minimal 16-bit PCM WAV writer. Used by the commands whose output is not
/// AI-generated speech (watermark round-trip, denoise); generated audio goes
/// through [_writeMarkedWav] instead.
Uint8List _wav(Float32List pcm, int sampleRate) {
  final n = pcm.length;
  final bytes = BytesBuilder();
  void s(String v) => bytes.add(v.codeUnits);
  void u32(int v) => bytes.add([v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255]);
  void u16(int v) => bytes.add([v & 255, v >> 8 & 255]);
  final dataBytes = n * 2;
  s('RIFF'); u32(36 + dataBytes); s('WAVE');
  s('fmt '); u32(16); u16(1); u16(1); u32(sampleRate);
  u32(sampleRate * 2); u16(2); u16(16);
  s('data'); u32(dataBytes);
  final pcm16 = Uint8List(dataBytes);
  final bd = ByteData.view(pcm16.buffer);
  for (var i = 0; i < n; i++) {
    final v = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    bd.setInt16(i * 2, v, Endian.little);
  }
  bytes.add(pcm16);
  return bytes.toBytes();
}

/// Write AI-*generated text* to stdout with its EU AI Act Art. 50(2)
/// disclosure attached, matching what the GUI puts on the clipboard and what
/// `/v1/audio/translations` returns in its `_disclosure` field.
///
/// The 2026-08-02 audit brought the CLI inside the *audio* marking scope but
/// left the text half behind: `translate` wrote a bare line to stdout while
/// every other surface disclosed. `ai_text_disclosure.dart` was already
/// pure-Dart specifically so the CLI could reach it — it just never did.
///
/// Disclosure is the default and [suppress] is an explicit opt-out, the same
/// direction of travel as `FileUtils.saveTranscription`'s
/// `syntheticDisclosure`. Suppression is for piping into another tool that
/// will do its own marking, not for shipping unmarked text to a human.
void _writeDisclosedText(String text, String disclosure,
    {required bool suppress}) {
  stdout.writeln(suppress ? text : AiTextDisclosure.attach(text, disclosure));
}

/// Adds the `--no-disclosure` opt-out to commands that emit generated text.
void _addDisclosureFlag(ArgParser p) {
  p.addFlag('no-disclosure',
      negatable: false,
      help: 'Omit the EU AI Act Art. 50(2) AI-generated-text disclosure from '
          'stdout. For piping into a tool that marks the output itself — not '
          'for handing unmarked machine-generated text to a person.');
}

abstract class _Base extends Command<int> {
  _Base() {
    argParser.addOption('lib', help: 'Path to libcrispasr dylib/so.');
  }
  String? get lib => _resolveLib(argResults?['lib'] as String?);

  /// A DynamicLibrary handle for the APIs that take one (TitaNet, SpeakerDB,
  /// alignWords, diarizeSegments). null → the binding's default loader.
  DynamicLibrary? get dylib {
    final p = lib;
    return p == null ? null : DynamicLibrary.open(p);
  }

  String _abs(String path) => File(path).absolute.path;

  /// Absolute path of an input that must already exist.
  ///
  /// A missing file used to reach the decoder / the FFI loader and surface
  /// as an uncaught exception with a Dart stack trace (exit 255). A typo in
  /// a path is a usage error.
  String _absExisting(String path, String what) {
    if (!File(path).existsSync()) {
      usageException('$what not found: $path');
    }
    return File(path).absolute.path;
  }

  /// An integer-valued option, or a usage error.
  ///
  /// `int.parse` on user input throws FormatException, which nothing caught:
  /// `--best-of two` printed a stack trace and exited 255 instead of saying
  /// what was wrong.
  int _intOpt(String name) {
    final raw = (argResults![name] as String).trim();
    final value = int.tryParse(raw);
    if (value == null) {
      usageException('--$name expects an integer, got "$raw".');
    }
    return value;
  }

  /// A double-valued option, or a usage error. See [_intOpt].
  double _doubleOpt(String name) {
    final raw = (argResults![name] as String).trim();
    final value = double.tryParse(raw);
    if (value == null) {
      usageException('--$name expects a number, got "$raw".');
    }
    return value;
  }
}

class _BackendsCmd extends _Base {
  @override
  String get name => 'backends';
  @override
  String get description => 'List ASR/TTS backends linked into the dylib.';
  @override
  int run() {
    final list = crispasr.CrispasrSession.availableBackends(libPath: lib);
    if (list.isEmpty) {
      stderr.writeln('No backends reported (is the dylib resolvable?).');
      return 1;
    }
    stdout.writeln(list.join('\n'));
    return 0;
  }
}

class _TranscribeCmd extends _Base {
  _TranscribeCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'ASR model (GGUF/bin).', mandatory: true)
      ..addOption('backend', abbr: 'b', help: 'Backend name (auto if omitted).')
      ..addOption('language', abbr: 'l', help: 'Language hint, e.g. en.')
      ..addOption('target-language', help: 'Target language for translation backends.')
      ..addFlag('srt', help: 'Emit SRT instead of plain text.')
      ..addFlag('vtt', help: 'Emit WebVTT instead of plain text.')
      ..addFlag('translate', help: 'Translate to English (whisper).')
      ..addFlag('word-timestamps', help: 'Include per-word timings.')
      ..addOption('temperature', help: 'Decoder temperature (0.0 = greedy).', defaultsTo: '0.0')
      ..addOption('best-of', help: 'Best-of-N decoding.', defaultsTo: '1')
      ..addOption('initial-prompt', help: 'Initial prompt / vocabulary hint.')
      ..addOption('hotwords', help: 'Comma-separated hotwords for contextual biasing.')
      ..addOption('hotwords-boost', help: 'Hotword boost factor (CTC/TDT).', defaultsTo: '1.5')
      ..addOption('seed', help: 'RNG seed for reproducible sampling.', defaultsTo: '-1')
      ..addOption('max-new-tokens', help: 'Cap on generated tokens (LLM backends).', defaultsTo: '4096')
      ..addOption('frequency-penalty', help: 'Frequency penalty (LLM backends).', defaultsTo: '0.0')
      ..addOption('beam-size', help: 'Beam search width (0 = greedy).', defaultsTo: '0')
      ..addFlag('vad', help: 'Enable Silero VAD pre-filtering.')
      ..addOption('vad-model', help: 'Path to the Silero VAD GGUF (required with --vad).')
      ..addOption('ask', help: 'Audio Q&A prompt (instruct LLM backends).');
    _addDisclosureFlag(argParser);
  }
  @override
  String get name => 'transcribe';
  @override
  String get description => 'Transcribe an audio file to text or SRT.';
  @override
  int run() {
    // Read mandatory options before any I/O so a missing one is a clean
    // usage error rather than a file/decoder failure.
    final modelPath = argResults!['model'] as String;
    final rest = argResults!.rest;
    if (rest.isEmpty) { usageException('Pass an audio file path.'); }
    // EU AI Act Art. 5(1)(f) / Annex III 1(c): refuse audio-Q&A prompts
    // asking the model to infer a speaker's emotions or intent. Checked here,
    // before the decode and the model load, so a refused run costs nothing
    // and cannot be mistaken for a transcription failure. The engine and the
    // HTTP server enforce the same list.
    final ScreenedAskPrompt screenedAsk;
    try {
      screenedAsk = ScreenedAskPrompt.screen(argResults!['ask'] as String?);
    } on AffectivePromptRefused catch (e) {
      stderr.writeln(e.message);
      return 2;
    }
    // Generation controls, parsed up front: a bad `--best-of two` should be
    // a usage error before the decode and the (slow) session open, not a
    // FormatException stack trace afterwards.
    final temp = _doubleOpt('temperature');
    final bestOf = _intOpt('best-of');
    final hotwords = argResults!['hotwords'] as String?;
    final hotwordsBoost = _doubleOpt('hotwords-boost');
    final seed = _intOpt('seed');
    final maxNewTokens = _intOpt('max-new-tokens');
    final freqPenalty = _doubleOpt('frequency-penalty');
    final beamSize = _intOpt('beam-size');
    final ask = argResults!['ask'] as String?;
    final targetLang = argResults!['target-language'] as String?;
    final lang = argResults!['language'] as String?;

    // `--vad` and `--vad-model` were parsed and then dropped on the floor:
    // the flags have been in `--help` since the CLI shipped but nothing ever
    // read them, so a headless run decoded the silence too. Route them
    // through the same C-ABI call the GUI uses
    // (`crispasr_session_transcribe_vad`). The GUI can auto-detect the model
    // because it ships Silero as a Flutter asset; a `dart run` entrypoint has
    // no asset bundle, so here the path is required.
    final useVad = argResults!['vad'] as bool;
    final vadModelArg = argResults!['vad-model'] as String?;
    final String? vadModel;
    if (useVad) {
      if (vadModelArg == null || vadModelArg.trim().isEmpty) {
        usageException('--vad needs --vad-model <silero .gguf/.bin>: the '
            'bundled VAD asset is only reachable from the app, not from the '
            'CLI.');
      }
      vadModel = _absExisting(vadModelArg, 'VAD model');
    } else {
      vadModel = null;
    }
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    final backend = argResults!['backend'] as String?;
    final session = crispasr.CrispasrSession.open(
      _absExisting(modelPath, 'ASR model'),
      backend: backend,
      libPath: lib,
    );
    try {
      try { session.setTemperature(temp, seed: seed >= 0 ? seed : 0); } catch (_) {}
      try { session.setBestOf(bestOf); } catch (_) {}
      if (hotwords != null && hotwords.isNotEmpty) {
        try { session.setHotwords(hotwords, boost: hotwordsBoost); } catch (_) {}
      }
      try { session.setMaxNewTokens(maxNewTokens); } catch (_) {}
      if (freqPenalty != 0.0) {
        try { session.setFrequencyPenalty(freqPenalty); } catch (_) {}
      }
      if (beamSize > 0) {
        try { session.setBeamSize(beamSize); } catch (_) {}
      }
      // Art. 5(1)(f): only a ScreenedAskPrompt can reach setAsk.
      if (screenedAsk.isNotEmpty) {
        try { session.setAsk(screenedAsk.value); } catch (_) {}
      }
      if (lang != null && lang.isNotEmpty && lang != 'auto') {
        try { session.setSourceLanguage(lang); } catch (_) {}
      }
      if (targetLang != null && targetLang.isNotEmpty) {
        try { session.setTargetLanguage(targetLang); } catch (_) {}
      }
      if (argResults!['translate'] as bool) {
        try { session.setTargetLanguage('en'); } catch (_) {}
      }
      try { session.setPunctuation(true); } catch (_) {}

      final segs = vadModel == null
          ? session.transcribe(audio.samples, language: lang)
          : session.transcribeVad(audio.samples, vadModel, language: lang);

      // Art. 50(2). Plain transcription of real speech is not synthetic
      // text and needs no mark — but asking for a *translation* makes the
      // output machine-generated, exactly as it does in the GUI's translate
      // screen and on `/v1/audio/translations`.
      //
      // So does `--ask`: in Q&A mode the backend answers the question
      // instead of transcribing, so stdout carries a language model's prose
      // and not a record of what anyone said. The 2026-08-02 audit brought
      // the CLI inside the text-marking scope but keyed the rule on
      // translation alone, so `--ask` output kept going out bare.
      final translated = (argResults!['translate'] as bool) ||
          (targetLang != null && targetLang.isNotEmpty);
      final isQa = ask != null && ask.trim().isNotEmpty;
      final noDisclosure = argResults!['no-disclosure'] as bool;
      final disclose = (translated || isQa) && !noDisclosure;
      // Q&A wins the wording: it is the stronger claim, and a translated
      // answer is still an answer.
      final disclosureText =
          isQa ? AiTextDisclosure.audioQa : AiTextDisclosure.translation;

      // SenseVoice writes `<|HAPPY|>`-style emotion inferences inline.
      // The app does not do emotion recognition — surfacing those made it
      // an Annex III 1(c) high-risk system — so `_noEmotion` drops them on
      // the way out, exactly as `CrispasrEngine` does, rather than passing
      // an inference about a natural person through to stdout.
      if (argResults!['srt'] as bool) {
        if (disclose) {
          // SRT has no comment directive — `NOTE` is WebVTT's, and a bare
          // line before cue 1 is a parse error or a silently dropped
          // disclosure depending on the player. Ship it as a real cue.
          stdout.writeln('0');
          stdout.writeln('00:00:00,000 --> 00:00:03,000');
          stdout.writeln('$disclosureText\n');
        }
        var i = 1;
        for (final s in segs) {
          stdout.writeln(i++);
          stdout.writeln('${_ts(s.start)} --> ${_ts(s.end)}');
          stdout.writeln('${_noEmotion(s.text)}\n');
        }
      } else if (argResults!['vtt'] as bool) {
        stdout.writeln('WEBVTT\n');
        if (disclose) {
          stdout.writeln('NOTE $disclosureText\n');
        }
        for (final s in segs) {
          stdout.writeln('${_vts(s.start)} --> ${_vts(s.end)}');
          stdout.writeln('${_noEmotion(s.text)}\n');
        }
      } else if (argResults!['word-timestamps'] as bool) {
        for (final s in segs) {
          if (s.words.isNotEmpty) {
            for (final w in s.words) {
              stdout.writeln('${w.start.toStringAsFixed(3)}\t${w.end.toStringAsFixed(3)}\t${w.text}');
            }
          } else {
            stdout.writeln('${s.start.toStringAsFixed(3)}\t${s.end.toStringAsFixed(3)}\t${_noEmotion(s.text)}');
          }
        }
      } else {
        final joined = segs.map((s) => _noEmotion(s.text)).join(' ').trim();
        if (disclose) {
          _writeDisclosedText(joined, disclosureText, suppress: false);
        } else {
          stdout.writeln(joined);
        }
      }
    } finally {
      session.close();
    }
    return 0;
  }

  /// [text] with any inline SenseVoice emotion tag removed.
  ///
  /// The app performs no emotion recognition: surfacing `<|HAPPY|>` and
  /// friends made it an Annex III 1(c) high-risk system, so they are
  /// dropped at every output boundary. Shares [EmotionInference]'s tag set
  /// with `CrispasrEngine` so the CLI and the GUI cannot disagree about
  /// what an emotion inference is.
  ///
  /// Acoustic *event* tags (`<|BGM|>`, `<|Laughter|>`) are left alone —
  /// they describe the recording, not the speaker's inner state.
  static String _noEmotion(String text) => text
      .replaceAllMapped(
          RegExp(r'<\|([A-Za-z_]+)\|>'),
          (m) => EmotionInference.isEmotionTag(m.group(1)!) ? '' : m.group(0)!)
      .trim();

  String _ts(double sec) {
    final ms = (sec * 1000).round();
    final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000, mm = ms % 1000;
    String p(int v, int w) => v.toString().padLeft(w, '0');
    return '${p(h, 2)}:${p(m, 2)}:${p(s, 2)},${p(mm, 3)}';
  }

  String _vts(double sec) => _ts(sec).replaceFirst(',', '.');
}

class _VadCmd extends _Base {
  _VadCmd() {
    argParser.addOption('model', abbr: 'm', help: 'VAD model (GGUF/bin).', mandatory: true);
  }
  @override
  String get name => 'vad';
  @override
  String get description => 'Print speech spans (start,end seconds) for audio.';
  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');
    final model = _absExisting(argResults!['model'] as String, 'VAD model');
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    // Call the *free* C function `crispasr_vad_slices` (via vad_native.dart),
    // not `CrispASR(model).vadSlices(...)`. The instance route loads the VAD
    // model as a whisper context purely to reach the method, and the
    // matching `dispose()` then runs `whisper_free` over a context that was
    // never a whisper model — a SIGABRT of the whole isolate (LEARNINGS §9.5,
    // the same bug VadService had). No context is needed at all here.
    for (final s in vadSlicesNative(model, audio.samples, libPath: lib)) {
      stdout.writeln('${s.start.toStringAsFixed(3)}\t${s.end.toStringAsFixed(3)}');
    }
    return 0;
  }
}

class _LidCmd extends _Base {
  _LidCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'ASR model (audio LID) or text-LID GGUF.')
      ..addFlag('text', help: 'Treat the argument as text, not an audio path.');
  }
  @override
  String get name => 'lid';
  @override
  String get description => 'Detect the language of audio or text.';
  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio path or, with --text, a string.');
    if (argResults!['text'] as bool) {
      final model = argResults!['model'] as String?;
      if (model == null) usageException('--model <text-lid GGUF> required for --text.');
      final r = crispasr.detectTextLanguage(
          rest.join(' '), _absExisting(model, 'Text-LID model'),
          libPath: lib);
      if (r == null) { stderr.writeln('detection failed'); return 1; }
      stdout.writeln('${r.code}\t${r.confidence.toStringAsFixed(3)}');
      return 0;
    }
    final model = argResults!['model'] as String?;
    if (model == null) usageException('--model <multilingual ASR model> required.');
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    // Audio LID runs through Whisper's language detector, so the model must
    // be a MULTILINGUAL whisper checkpoint. Handing it a different family
    // (a silero-lid GGUF, an English-only .en model) used to die with a raw
    // stack trace; name the requirement instead.
    final crispasr.CrispASR cr;
    try {
      cr = crispasr.CrispASR(_absExisting(model, 'ASR model'), libPath: lib);
    } catch (e) {
      stderr.writeln('Could not open "${p.basename(model)}" for language '
          'detection: $e\nAudio LID needs a multilingual Whisper model '
          '(e.g. ggml-tiny.bin / ggml-base.bin — not a .en variant, and not '
          'a text-LID GGUF; use --text for those).');
      return 64;
    }
    try {
      final d = cr.detectLanguage(audio.samples);
      stdout.writeln('${d.code}\t${d.probability.toStringAsFixed(3)}');
    } catch (e) {
      stderr.writeln('Language detection failed: $e\nAudio LID needs a '
          'multilingual Whisper model (not a .en variant).');
      return 1;
    } finally {
      cr.dispose();
    }
    return 0;
  }
}

class _PunctuateCmd extends _Base {
  _PunctuateCmd() {
    argParser.addOption('model', abbr: 'm', help: 'Punctuation GGUF.', mandatory: true);
  }
  @override
  String get name => 'punctuate';
  @override
  String get description => 'Restore punctuation/capitalization in text.';
  @override
  int run() {
    final rest = argResults!.rest;
    final text = rest.isNotEmpty ? rest.join(' ') : stdin.readLineSync() ?? '';
    final model = crispasr.PuncModel.open(
        _absExisting(argResults!['model'] as String, 'Punctuation model'),
        libPath: lib);
    try {
      stdout.writeln(model.process(text));
    } finally {
      model.close();
    }
    return 0;
  }
}

class _TranslateCmd extends _Base {
  _TranslateCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'Translation GGUF.', mandatory: true)
      ..addOption('from', help: 'Source language code.', defaultsTo: 'en')
      ..addOption('to', abbr: 't', help: 'Target language code.', mandatory: true);
    _addDisclosureFlag(argParser);
  }
  @override
  String get name => 'translate';
  @override
  String get description => 'Translate text between languages.';
  @override
  int run() {
    final rest = argResults!.rest;
    final text = rest.isNotEmpty ? rest.join(' ') : stdin.readLineSync() ?? '';
    final session = crispasr.CrispasrSession.open(
        _absExisting(argResults!['model'] as String, 'Translation model'),
        libPath: lib);
    try {
      final out = session.translateText(
          text, argResults!['from'] as String, argResults!['to'] as String);
      if (out == null) { stderr.writeln('translation failed'); return 1; }
      // Art. 50(2): machine translation generates text — it is not the
      // "assistive function for standard editing" carve-out.
      _writeDisclosedText(out, AiTextDisclosure.translation,
          suppress: argResults!['no-disclosure'] as bool);
    } finally {
      session.close();
    }
    return 0;
  }
}

class _SynthesizeCmd extends _Base {
  _SynthesizeCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'TTS GGUF.', mandatory: true)
      ..addOption('out', abbr: 'o', help: 'Output WAV path.', mandatory: true)
      ..addOption('voice', help: 'Reference voice WAV/GGUF (cloning).')
      ..addFlag('i-have-rights',
          negatable: false,
          help: 'Attest that you have the voice owner\'s explicit consent to '
              'clone this voice. Required with --voice (GDPR Art. 9(2)(a); '
              'mirrors the GUI voice-clone consent gate).')
      ..addOption('disclaimer-override',
          help: 'Suppress the mandatory Art. 50(4) beep disclaimer on cloned '
              'output. Takes a written legal basis, which is logged. Only the '
              'beep is suppressed — watermark and provenance still apply.')
      ..addOption('rate', help: 'Output sample rate.', defaultsTo: '24000')
      ..addOption('temperature', help: 'Sampling temperature.', defaultsTo: '0.7')
      ..addOption('seed', help: 'RNG seed (-1 = random).', defaultsTo: '-1');
  }
  @override
  String get name => 'synthesize';
  @override
  String get description => 'Synthesize speech from text to a WAV file.';
  @override
  int run() {
    final rest = argResults!.rest;
    final text = rest.isNotEmpty ? rest.join(' ') : stdin.readLineSync() ?? '';
    final voice = argResults!['voice'] as String?;
    final hasVoice = voice != null && voice.isNotEmpty;
    // A baked .gguf voicepack (kokoro af_heart, VibeVoice Emma, …) is a
    // catalogue voice, not a recording of a natural person — selecting one
    // needs no biometric-consent attestation, exactly as in the GUI, where
    // only the clone wizard's reference-audio path carries the consent
    // checkbox. Cloning from an audio file keeps the gate.
    final isRefClone = hasVoice && !voice.toLowerCase().endsWith('.gguf');

    // GDPR Art. 9(2)(a) consent gate, matching the GUI wizard. Refuse rather
    // than warn: a headless flag that only prints a warning is a flag nobody
    // reads. Mirrors CrispASR's --i-have-rights.
    if (isRefClone && !(argResults!['i-have-rights'] as bool)) {
      stderr.writeln(
          'Refusing to clone a voice without --i-have-rights.\n'
          'Voice cloning processes biometric characteristics of a natural '
          'person. Pass --i-have-rights to attest that you have the voice '
          'owner\'s explicit consent (GDPR Art. 9(2)(a)).');
      return 2;
    }

    // Validate every argument before the model load: a typo in --rate should
    // not cost a multi-second session open first.
    final ttsTemp = _doubleOpt('temperature');
    final ttsSeed = _intOpt('seed');
    final rate = _intOpt('rate');
    final session = crispasr.CrispasrSession.open(
        _absExisting(argResults!['model'] as String, 'TTS model'),
        libPath: lib);
    try {
      if (hasVoice) session.setVoice(_absExisting(voice, 'Reference voice'));
      try { session.setTemperature(ttsTemp, seed: ttsSeed >= 0 ? ttsSeed : 0); } catch (_) {}
      final pcm = session.synthesize(text);
      final out = File(argResults!['out'] as String);
      final model = argResults!['model'] as String;
      if (isRefClone) {
        stdout.writeln('[CONSENT] ts=${DateTime.now().toUtc().toIso8601String()} '
            'model=${p.basename(model)} voice=${p.basename(voice)} '
            'attestation="--i-have-rights"');
      }
      _writeMarkedWav(
        out,
        pcm,
        rate,
        modelName: p.basenameWithoutExtension(model),
        voiceId: hasVoice ? p.basenameWithoutExtension(voice) : null,
        // Beep disclaimer for ANY voice reference, voicepack included —
        // identical to the GUI (TtsService.writeWav beeps whenever a
        // voiceRefPath is set). Only the GDPR consent gate above
        // distinguishes a catalogue voicepack from reference-audio cloning.
        deepfake: hasVoice,
        disclaimerOverride: argResults!['disclaimer-override'] as String?,
        dylib: dylib,
      );
      // "synthesized", not "wrote": with the beep disclaimer prepended the
      // file holds more samples than the model produced.
      stdout.writeln(
          'synthesized ${pcm.length} samples @ ${rate}Hz -> ${out.path}');
    } finally {
      session.close();
    }
    return 0;
  }
}

class _WatermarkCmd extends _Base {
  _WatermarkCmd() {
    argParser
      ..addFlag('detect', help: 'Detect a watermark instead of embedding.')
      ..addOption('out', abbr: 'o', help: 'Output WAV (embed mode).')
      ..addOption('rate', help: 'Sample rate for output WAV.', defaultsTo: '24000');
  }
  @override
  String get name => 'watermark';
  @override
  String get description => 'Embed or detect the spread-spectrum AI watermark.';
  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');
    final detect = argResults!['detect'] as bool;
    final out = argResults!['out'] as String?;
    // Check the output argument *before* embedding: the old order ran the
    // whole spread-spectrum embed and only then discovered it had nowhere to
    // write the result.
    if (!detect && (out == null || out.isEmpty)) {
      usageException('--out <file.wav> required in embed mode.');
    }
    final rate = detect ? 0 : _intOpt('rate');
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    // CrispasrWatermark.{embed,detect} take a DynamicLibrary; open the
    // resolved dylib path directly (null → the binding's default loader).
    final libPath = lib;
    final dylib = libPath == null ? null : DynamicLibrary.open(libPath);
    if (detect) {
      final c = crispasr.CrispasrWatermark.detect(audio.samples, lib: dylib);
      stdout.writeln(c.toStringAsFixed(4));
    } else {
      final wm = crispasr.CrispasrWatermark.embed(audio.samples, alpha: 0.1, lib: dylib);
      File(out!).writeAsBytesSync(_wav(wm, rate));
      stdout.writeln('embedded -> $out');
    }
    return 0;
  }
}

class _DenoiseCmd extends _Base {
  _DenoiseCmd() {
    argParser
      ..addOption('out', abbr: 'o', help: 'Output WAV path.', mandatory: true)
      ..addOption('rate', help: 'Sample rate for output WAV.', defaultsTo: '16000');
  }
  @override
  String get name => 'denoise';
  @override
  String get description => 'Denoise audio via RNNoise (16 kHz mono).';
  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');
    final rate = _intOpt('rate');
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    final enhanced = crispasr.enhanceAudioRnnoise(audio.samples, lib: dylib);
    final out = argResults!['out'] as String;
    File(out).writeAsBytesSync(_wav(enhanced, rate));
    stdout.writeln('denoised ${audio.samples.length} samples -> $out');
    return 0;
  }
}

class _StreamCmd extends _Base {
  _StreamCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'ASR model.', mandatory: true)
      ..addOption('language', abbr: 'l', help: 'Language hint.')
      ..addOption('chunk-ms', help: 'Feed chunk size (ms).', defaultsTo: '1000')
      ..addOption('hotwords', help: 'Comma-separated hotwords for contextual biasing.')
      ..addOption('hotwords-boost', help: 'Hotword boost factor.', defaultsTo: '1.5')
      ..addOption('temperature', help: 'Decoder temperature.', defaultsTo: '0.0');
  }
  @override
  String get name => 'stream';
  @override
  String get description => 'Streaming transcription (rolling-window decode).';
  @override
  int run() {
    final modelPath = _absExisting(argResults!['model'] as String, 'ASR model');
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');
    final chunkMs = _intOpt('chunk-ms');
    if (chunkMs <= 0) usageException('--chunk-ms must be positive.');
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    final cr = crispasr.CrispASR(modelPath, libPath: lib);
    try {
      // The streaming session decodes EMPTY text when no language is set —
      // auto-LID is not wired into the rolling-window decoder, on either
      // .en or multilingual checkpoints (verified against jfk.wav: bare
      // `stream` printed nothing, `-l en` transcribed fine). Resolve the
      // language up front instead of streaming silence: `.en` models are
      // English by construction; for multilingual ones run the ordinary
      // language detector over the first ~10 s.
      var language = argResults!['language'] as String?;
      if (language == null || language.isEmpty || language == 'auto') {
        if (p.basename(modelPath).contains('.en')) {
          language = 'en';
        } else {
          final probeLen = audio.samples.length < 160000
              ? audio.samples.length
              : 160000;
          final d = cr.detectLanguage(
              Float32List.sublistView(audio.samples, 0, probeLen));
          language = d.code;
        }
        stderr.writeln('stream: no --language given; using "$language"');
      }
      // Note: hotwords + temperature from CLI args are not applied to
      // the streaming session because StreamingSession doesn't expose
      // those setters. They are accepted by the parser for forward-
      // compatibility when the C ABI adds stream-level overrides.
      final session = cr.openStream(language: language);
      try {
        final chunk = chunkMs * 16; // 16 smp/ms @16k
        final buf = StringBuffer();
        for (var off = 0; off < audio.samples.length; off += chunk) {
          final end = (off + chunk) < audio.samples.length
              ? off + chunk
              : audio.samples.length;
          final u = session.feed(Float32List.sublistView(audio.samples, off, end));
          if (u != null && u.text.trim().isNotEmpty) buf.write('${u.text.trim()} ');
        }
        final f = session.flush();
        if (f != null && f.text.trim().isNotEmpty) buf.write(f.text.trim());
        stdout.writeln(buf.toString().trim());
      } finally {
        session.close();
      }
    } finally {
      cr.dispose();
    }
    return 0;
  }
}

class _AlignCmd extends _Base {
  _AlignCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'Aligner GGUF path. When omitted, auto-discovers '
          'a language-matched wav2vec2 or canary-ctc-aligner in the models dir.')
      ..addOption('language', abbr: 'l', help: 'ISO 639-1 language code (e.g. fr, de, ja). '
          'Auto-selects the matching wav2vec2 aligner when --model is omitted.')
      ..addOption('text', help: 'Reference transcript to align.', mandatory: true);
  }
  @override
  String get name => 'align';
  @override
  String get description => 'Forced-align a transcript to audio → per-word timings.';
  @override
  int run() {
    final modelArg = argResults!['model'] as String?;
    final language = argResults!['language'] as String?;
    final text = argResults!['text'] as String;
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');

    // Resolve aligner model: explicit > language-matched wav2vec2 > any on disk.
    String? model =
        modelArg != null ? _absExisting(modelArg, 'Aligner model') : null;
    if (model == null) {
      // Try language-specific wav2vec2 first, then canary-ctc-aligner.
      final modelsDir = Platform.environment['CRISPASR_MODELS_DIR'] ??
          '/Volumes/backups/ai/crispasr';
      final dir = Directory(modelsDir);
      if (dir.existsSync()) {
        // Language-matched wav2vec2 variant.
        if (language != null) {
          const langPrefixes = {
            'en': 'wav2vec2-xlsr-en',
            'de': 'wav2vec2-large-xlsr-53-german',
            'fr': 'wav2vec2-large-xlsr-53-french',
            'es': 'wav2vec2-large-xlsr-53-spanish',
            'it': 'wav2vec2-large-xlsr-53-italian',
            'ja': 'wav2vec2-large-xlsr-53-japanese',
            'zh': 'wav2vec2-large-xlsr-53-chinese-zh-cn',
            'nl': 'wav2vec2-large-xlsr-53-dutch',
            'pt': 'wav2vec2-large-xlsr-53-portuguese',
            'ar': 'wav2vec2-large-xlsr-53-arabic',
            'cs': 'wav2vec2-xls-r-300m-cs-250',
            'uk': 'wav2vec2-xls-r-300m-uk-with-small-lm',
          };
          final prefix = langPrefixes[language.toLowerCase()];
          if (prefix != null) {
            for (final f in dir.listSync()) {
              if (f is File && f.path.contains(prefix) && f.path.endsWith('.gguf')) {
                model = f.path;
                break;
              }
            }
          }
        }
        // Fallback: canary-ctc-aligner.
        if (model == null) {
          for (final f in dir.listSync()) {
            if (f is File) {
              final base = f.uri.pathSegments.last;
              if (base.contains('ctc-aligner') || base.contains('forced-aligner')) {
                model = f.path;
                break;
              }
            }
          }
        }
      }
    }
    if (model == null) {
      usageException('No aligner model found. Pass --model or download '
          'canary-ctc-aligner / wav2vec2-aligner-<lang> via Model Management.');
    }

    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    final words = crispasr.alignWords(
        alignerModel: model, transcript: text, pcm: audio.samples, lib: dylib);
    for (final w in words) {
      stdout.writeln(
          '${w.start.toStringAsFixed(3)}\t${w.end.toStringAsFixed(3)}\t${w.text}');
    }
    return 0;
  }
}

class _DiarizeCmd extends _Base {
  _DiarizeCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'ASR model (produces segments).', mandatory: true)
      ..addOption('pyannote', help: 'pyannote-seg GGUF.', mandatory: true)
      ..addOption('language', abbr: 'l', help: 'Language hint.');
  }
  @override
  String get name => 'diarize';
  @override
  List<String> get aliases => const ['diarize-speakers'];
  @override
  String get description => 'Transcribe + label speakers (pyannote).';
  @override
  int run() {
    final asr = _absExisting(argResults!['model'] as String, 'ASR model');
    final pyannote =
        _absExisting(argResults!['pyannote'] as String, 'pyannote model');
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    final cr = crispasr.CrispASR(asr, libPath: lib);
    try {
      final segs = cr.transcribePcm(audio.samples,
          options: crispasr.TranscribeOptions(
              language: argResults!['language'] as String?, silent: true));
      final dseg = segs
          .map((s) => crispasr.DiarizeSegment(t0: s.start, t1: s.end))
          .toList();
      final ok = crispasr.diarizeSegments(
        segs: dseg,
        left: audio.samples,
        isStereo: false,
        method: crispasr.DiarizeMethod.pyannote,
        pyannoteModelPath: pyannote,
        lib: dylib,
      );
      if (!ok) {
        stderr.writeln('diarization failed (pyannote model failed to load?)');
        return 1;
      }
      for (var i = 0; i < segs.length; i++) {
        final sp = dseg[i].speaker;
        stdout.writeln('${dseg[i].t0.toStringAsFixed(3)}\t'
            '${dseg[i].t1.toStringAsFixed(3)}\t'
            'spk${sp >= 0 ? sp : '?'}\t${segs[i].text.trim()}');
      }
    } finally {
      cr.dispose();
    }
    return 0;
  }
}

class _SpeakerCmd extends _Base {
  _SpeakerCmd() {
    argParser
      ..addOption('titanet', help: 'TitaNet speaker-embedding GGUF.', mandatory: true)
      ..addOption('db', help: 'Speaker DB directory.', mandatory: true)
      ..addOption('name', help: 'Speaker name (enroll mode).')
      ..addOption('expect',
          help: 'Comma-separated roster of claimed participants to confirm '
              'against (match mode). Defaults to --name. Matching is a '
              'closed-roster confirmation, never an open 1:N search.')
      ..addFlag('i-have-rights',
          negatable: false,
          help: 'Attest a lawful basis + explicit consent from every '
              'enrolled person (GDPR Art. 9(2)(a)). Required — the '
              'speaker DB refuses to open without it.')
      ..addOption('threshold', help: 'Match threshold.', defaultsTo: '0.7');
  }
  @override
  String get name => 'speaker';
  @override
  String get description => 'Enroll/match a speaker: speaker <enroll|match> <audio>.';
  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('Usage: speaker <enroll|match> <audio>');
    final action = rest[0];
    if (action != 'enroll' && action != 'match') {
      usageException('action must be "enroll" or "match"');
    }
    final dl = dylib;
    if (dl == null) {
      stderr.writeln('libcrispasr dylib not resolvable (pass --lib).');
      return 1;
    }
    // GDPR Art. 9(2)(a): biometric processing needs an explicit
    // attestation. Mirrors CrispASR's own --i-have-rights gate.
    if (argResults!['i-have-rights'] != true) {
      stderr.writeln(
          'Refusing to open the speaker DB: voice embeddings are biometric '
          'data under GDPR Art. 9. Pass --i-have-rights to attest that you '
          'have a lawful basis and explicit consent from every enrolled '
          'person.');
      return 1;
    }
    final nameOpt = argResults!['name'] as String?;
    final expectOpt = argResults!['expect'] as String?;
    final roster = (expectOpt ?? nameOpt ?? '').trim();
    if (action == 'match' && roster.isEmpty) {
      stderr.writeln(
          'match requires --expect (or --name): the roster of claimed '
          'participants to confirm against.');
      return 1;
    }
    final threshold = _doubleOpt('threshold');
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest[1], 'Audio file'), libPath: lib);
    final titanet = crispasr.CrispasrTitaNet(
        dl, _absExisting(argResults!['titanet'] as String, 'TitaNet model'));
    try {
      final emb = titanet.embed(audio.samples);
      final db = crispasr.CrispasrSpeakerDB(
        dl,
        _abs(argResults!['db'] as String),
        expectedNames: roster,
        consentAttested: true,
      );
      try {
        if (action == 'enroll') {
          final nm = nameOpt;
          if (nm == null) usageException('--name required for enroll.');
          final ok = db.enroll(nm, emb);
          stdout.writeln(ok ? 'enrolled $nm' : 'enroll failed');
          return ok ? 0 : 1;
        }
        final (matchName, score) = db.match(emb, threshold: threshold);
        stdout.writeln('${matchName ?? "(no match)"}\t${score.toStringAsFixed(3)}');
        return 0;
      } finally {
        db.close();
      }
    } finally {
      titanet.close();
    }
  }
}

class _S2sCmd extends _Base {
  _S2sCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'S2S model (lfm2-audio/mini-omni2).', mandatory: true)
      ..addOption('backend', abbr: 'b', help: 'Backend name.')
      ..addOption('out', abbr: 'o', help: 'Output WAV path.', mandatory: true)
      ..addOption('rate', help: 'Output sample rate.', defaultsTo: '24000')
      ..addOption('disclaimer-override',
          help: 'Suppress the mandatory Art. 50(4) beep disclaimer on the '
              'converted output. Takes a written legal basis, which is '
              'logged. Watermark and provenance still apply.');
  }
  @override
  String get name => 's2s';
  @override
  String get description => 'Speech-to-speech: audio in → audio out.';
  @override
  int run() {
    final model = _absExisting(argResults!['model'] as String, 'S2S model');
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an input audio file path.');
    final rate = _intOpt('rate');
    final audio =
        crispasr.decodeAudioFile(_absExisting(rest.first, 'Audio file'), libPath: lib);
    final session = crispasr.CrispasrSession.open(model,
        backend: argResults!['backend'] as String?, libPath: lib);
    try {
      final result = session.speechToSpeech(audio.samples);
      // Voice conversion is Art. 50(4) deepfake territory just as much as
      // cloning is — see PLAN §15.2g, which fixed exactly this on the GUI
      // and server paths while the CLI kept writing an unmarked WAV.
      _writeMarkedWav(
        File(argResults!['out'] as String),
        result.pcm,
        rate,
        modelName: p.basenameWithoutExtension(model),
        deepfake: true,
        disclaimerOverride: argResults!['disclaimer-override'] as String?,
        dylib: dylib,
      );
      stdout.writeln('transcript: ${result.transcript}');
      stdout.writeln(
          'converted ${result.pcm.length} samples -> ${argResults!['out']}');
    } finally {
      session.close();
    }
    return 0;
  }
}

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
      'crisperweaver', 'Headless on-device speech engine (ASR/TTS/translate/'
          'VAD/LID/diarize/align/speaker/streaming/s2s/punctuation/watermark).')
    ..addCommand(_BackendsCmd())
    ..addCommand(_TranscribeCmd())
    ..addCommand(_StreamCmd())
    ..addCommand(_VadCmd())
    ..addCommand(_LidCmd())
    ..addCommand(_DiarizeCmd())
    ..addCommand(_AlignCmd())
    ..addCommand(_SpeakerCmd())
    ..addCommand(_PunctuateCmd())
    ..addCommand(_TranslateCmd())
    ..addCommand(_SynthesizeCmd())
    ..addCommand(_S2sCmd())
    ..addCommand(_WatermarkCmd())
    ..addCommand(_DenoiseCmd());
  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  } on ArgumentError catch (e) {
    // package:args throws ArgumentError when a `mandatory` option is
    // missing; treat it as a usage error (exit 64), not a crash.
    stderr.writeln(e.message);
    exit(64);
  }
}
