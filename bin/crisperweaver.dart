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

import 'package:args/command_runner.dart';
import 'package:crispasr/crispasr.dart' as crispasr;

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

/// Minimal 16-bit PCM WAV writer for TTS output.
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
      ..addFlag('srt', help: 'Emit SRT instead of plain text.');
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
    final audio = crispasr.decodeAudioFile(File(rest.first).absolute.path, libPath: lib);
    final backend = argResults!['backend'] as String?;
    final session = crispasr.CrispasrSession.open(
      File(modelPath).absolute.path,
      backend: backend,
      libPath: lib,
    );
    try {
      final segs = session.transcribe(audio.samples,
          language: argResults!['language'] as String?);
      if (argResults!['srt'] as bool) {
        var i = 1;
        for (final s in segs) {
          stdout.writeln(i++);
          stdout.writeln('${_ts(s.start)} --> ${_ts(s.end)}');
          stdout.writeln('${s.text.trim()}\n');
        }
      } else {
        stdout.writeln(segs.map((s) => s.text.trim()).join(' ').trim());
      }
    } finally {
      session.close();
    }
    return 0;
  }

  String _ts(double sec) {
    final ms = (sec * 1000).round();
    final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000, mm = ms % 1000;
    String p(int v, int w) => v.toString().padLeft(w, '0');
    return '${p(h, 2)}:${p(m, 2)}:${p(s, 2)},${p(mm, 3)}';
  }
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
    final audio = crispasr.decodeAudioFile(File(rest.first).absolute.path, libPath: lib);
    final model = File(argResults!['model'] as String).absolute.path;
    final cr = crispasr.CrispASR(model, libPath: lib);
    try {
      // Use the unified dispatcher (vadSlices), not legacy vad(). See §9.5.
      // The ctx is loaded from the VAD model here only because the binding
      // requires an instance; the call ignores it. (CLI tolerates the
      // wasted ctx; VadService uses the free-function path instead.)
      for (final s in cr.vadSlices(audio.samples, modelPath: model)) {
        stdout.writeln('${s.start.toStringAsFixed(3)}\t${s.end.toStringAsFixed(3)}');
      }
    } finally {
      cr.dispose();
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
      final r = crispasr.detectTextLanguage(rest.join(' '),
          File(model).absolute.path, libPath: lib);
      if (r == null) { stderr.writeln('detection failed'); return 1; }
      stdout.writeln('${r.code}\t${r.confidence.toStringAsFixed(3)}');
      return 0;
    }
    final model = argResults!['model'] as String?;
    if (model == null) usageException('--model <multilingual ASR model> required.');
    final audio = crispasr.decodeAudioFile(File(rest.first).absolute.path, libPath: lib);
    final cr = crispasr.CrispASR(File(model).absolute.path, libPath: lib);
    try {
      final d = cr.detectLanguage(audio.samples);
      stdout.writeln('${d.code}\t${d.probability.toStringAsFixed(3)}');
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
        File(argResults!['model'] as String).absolute.path, libPath: lib);
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
        File(argResults!['model'] as String).absolute.path, libPath: lib);
    try {
      final out = session.translateText(
          text, argResults!['from'] as String, argResults!['to'] as String);
      if (out == null) { stderr.writeln('translation failed'); return 1; }
      stdout.writeln(out);
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
      ..addOption('rate', help: 'Output sample rate.', defaultsTo: '24000');
  }
  @override
  String get name => 'synthesize';
  @override
  String get description => 'Synthesize speech from text to a WAV file.';
  @override
  int run() {
    final rest = argResults!.rest;
    final text = rest.isNotEmpty ? rest.join(' ') : stdin.readLineSync() ?? '';
    final session = crispasr.CrispasrSession.open(
        File(argResults!['model'] as String).absolute.path, libPath: lib);
    try {
      final voice = argResults!['voice'] as String?;
      if (voice != null) session.setVoice(File(voice).absolute.path);
      final pcm = session.synthesize(text);
      final rate = int.parse(argResults!['rate'] as String);
      File(argResults!['out'] as String).writeAsBytesSync(_wav(pcm, rate));
      stdout.writeln('wrote ${pcm.length} samples @ ${rate}Hz -> ${argResults!['out']}');
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
    final audio = crispasr.decodeAudioFile(File(rest.first).absolute.path, libPath: lib);
    // CrispasrWatermark.{embed,detect} take a DynamicLibrary; open the
    // resolved dylib path directly (null → the binding's default loader).
    final p = lib;
    final dylib = p == null ? null : DynamicLibrary.open(p);
    if (argResults!['detect'] as bool) {
      final c = crispasr.CrispasrWatermark.detect(audio.samples, lib: dylib);
      stdout.writeln(c.toStringAsFixed(4));
    } else {
      final wm = crispasr.CrispasrWatermark.embed(audio.samples, alpha: 0.1, lib: dylib);
      final out = argResults!['out'] as String?;
      if (out == null) usageException('--out <file.wav> required in embed mode.');
      File(out).writeAsBytesSync(_wav(wm, int.parse(argResults!['rate'] as String)));
      stdout.writeln('embedded -> $out');
    }
    return 0;
  }
}

class _StreamCmd extends _Base {
  _StreamCmd() {
    argParser
      ..addOption('model', abbr: 'm', help: 'ASR model.', mandatory: true)
      ..addOption('language', abbr: 'l', help: 'Language hint.')
      ..addOption('chunk-ms', help: 'Feed chunk size (ms).', defaultsTo: '1000');
  }
  @override
  String get name => 'stream';
  @override
  String get description => 'Streaming transcription (rolling-window decode).';
  @override
  int run() {
    final modelPath = _abs(argResults!['model'] as String);
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');
    final audio = crispasr.decodeAudioFile(_abs(rest.first), libPath: lib);
    final cr = crispasr.CrispASR(modelPath, libPath: lib);
    try {
      final session =
          cr.openStream(language: argResults!['language'] as String?);
      try {
        final chunk =
            int.parse(argResults!['chunk-ms'] as String) * 16; // 16 smp/ms @16k
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
      ..addOption('model', abbr: 'm', help: 'Aligner GGUF (canary-ctc/wav2vec2).', mandatory: true)
      ..addOption('text', help: 'Reference transcript to align.', mandatory: true);
  }
  @override
  String get name => 'align';
  @override
  String get description => 'Forced-align a transcript to audio → per-word timings.';
  @override
  int run() {
    final model = _abs(argResults!['model'] as String);
    final text = argResults!['text'] as String;
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');
    final audio = crispasr.decodeAudioFile(_abs(rest.first), libPath: lib);
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
  String get description => 'Transcribe + label speakers (pyannote).';
  @override
  int run() {
    final asr = _abs(argResults!['model'] as String);
    final pyannote = _abs(argResults!['pyannote'] as String);
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an audio file path.');
    final audio = crispasr.decodeAudioFile(_abs(rest.first), libPath: lib);
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
    final audio = crispasr.decodeAudioFile(_abs(rest[1]), libPath: lib);
    final titanet =
        crispasr.CrispasrTitaNet(dl, _abs(argResults!['titanet'] as String));
    try {
      final emb = titanet.embed(audio.samples);
      final db = crispasr.CrispasrSpeakerDB(dl, _abs(argResults!['db'] as String));
      try {
        if (action == 'enroll') {
          final nm = argResults!['name'] as String?;
          if (nm == null) usageException('--name required for enroll.');
          final ok = db.enroll(nm, emb);
          stdout.writeln(ok ? 'enrolled $nm' : 'enroll failed');
          return ok ? 0 : 1;
        }
        final (matchName, score) = db.match(emb,
            threshold: double.parse(argResults!['threshold'] as String));
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
      ..addOption('rate', help: 'Output sample rate.', defaultsTo: '24000');
  }
  @override
  String get name => 's2s';
  @override
  String get description => 'Speech-to-speech: audio in → audio out.';
  @override
  int run() {
    final model = _abs(argResults!['model'] as String);
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Pass an input audio file path.');
    final audio = crispasr.decodeAudioFile(_abs(rest.first), libPath: lib);
    final session = crispasr.CrispasrSession.open(model,
        backend: argResults!['backend'] as String?, libPath: lib);
    try {
      final result = session.speechToSpeech(audio.samples);
      File(argResults!['out'] as String).writeAsBytesSync(
          _wav(result.pcm, int.parse(argResults!['rate'] as String)));
      stdout.writeln('transcript: ${result.transcript}');
      stdout.writeln('wrote ${result.pcm.length} samples -> ${argResults!['out']}');
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
    ..addCommand(_WatermarkCmd());
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
