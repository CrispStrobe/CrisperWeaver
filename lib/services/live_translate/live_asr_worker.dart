// LiveAsrWorker — the recogniser half of live transcribe + translate.
//
// Runs in its own isolate because every native call here (VAD, LID,
// transcribe) blocks for tens to hundreds of milliseconds, and the
// fullscreen caption view must keep repainting meanwhile. The translator
// runs in a second isolate (live_translator_worker.dart) so a slow
// translator delays the translation line and never the recogniser — the
// same split as upstream's `--live-translate`.
//
// The loop mirrors crispasr_run.cpp's live-translate path (CrispASR #493):
//   * every step (500 ms) VAD covers the audio that arrived since the last;
//     speech opens an utterance, trailing silence closes it
//     (`finalSilenceMs`), half of that silence is a pause that commits a
//     finished sentence early;
//   * each step decodes only the audio not yet committed — from the last
//     committed word's timestamp when the recogniser has word times, from an
//     estimate otherwise (SentenceCommitter.decodeFrom);
//   * more than ~9 s still open sets pressure, so a never-ending sentence is
//     committed at a clause boundary instead of re-decoded forever;
//   * a step that ran long reads the whole backlog at once, closing every
//     utterance that ended inside it at its own pause.
//
// Wire protocol (maps only; no closures or FFI handles cross the boundary):
//   main → worker: {type: audio, pcm: Float32List}
//                  {type: stop}           — close the open utterance, exit
//   worker → main: {type: ready, backend}
//                  {type: error, message}
//                  {type: tail, utt, text, lang}
//                  {type: held, utt, text, lang}   settled, not yet a unit
//                  {type: unit, utt, id, text, lang, t, langConf}
//                  {type: lang, utt, lang, conf, method}
//                  {type: stats, stepMs, openSec, behindSec, misses}
//                  {type: stopped}

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../native/crispasr_import.dart' as crispasr;
import '../../native/vad_native_import.dart';
import '../../utils/emotion_inference.dart';
import '../../utils/language_code.dart' show normaliseLangCode;
import 'sentence_committer.dart';

const _sr = 16000;
// A stateless Silero call needs enough history to distinguish a soft syllable
// from a pause. Half a second made segmentation depend on ASR decode speed.
const _vadHistory = 2 * _sr;

class LiveAsrArgs {
  const LiveAsrArgs({
    required this.readyPort,
    required this.modelPath,
    required this.backend,
    this.libPath,
    this.vadModelPath,
    this.lidMode = 'fixed',
    this.audioLidPath,
    this.textLidPath,
    this.fixedSource,
    this.expectedSources = const [],
    this.stepMs = 500,
    this.minDecodeMs = 0,
    this.finalSilenceMs = 800,
    this.useGpu = true,
    this.nThreads = 0,
    this.directTranslationTarget,
  });

  final SendPort readyPort;
  final String modelPath;
  final String backend;

  /// Optional native library path for embedders and integration tests.
  final String? libPath;
  final String? vadModelPath;

  /// 'fixed' | 'audio' | 'text' | 'recognizer'
  final String lidMode;
  final String? audioLidPath;
  final String? textLidPath;
  final String? fixedSource;
  final List<String> expectedSources;
  final int stepMs;

  /// 0 selects a backend default: Cohere needs 3 s before draft decoding.
  /// Final utterances are still decoded even when shorter.
  final int minDecodeMs;
  final int finalSilenceMs;
  final bool useGpu;
  final int nThreads;

  /// Set for a speech-translation recogniser (Index-Echo): the language it
  /// translates into itself. Such a model decodes whole utterances (its
  /// own speech windows, transcript + translation per cue), so it is run
  /// once per utterance instead of re-decoded every step, and its
  /// translation is sent along with the transcript.
  final String? directTranslationTarget;
}

Future<void> liveAsrWorkerEntry(LiveAsrArgs args) async {
  final cmd = ReceivePort();
  args.readyPort.send(cmd.sendPort);
  final out = args.readyPort;

  crispasr.CrispasrSession session;
  try {
    try {
      session = crispasr.CrispasrSession.openWithParams(
        args.modelPath,
        nThreads: args.nThreads,
        useGpu: args.useGpu,
        backend: args.backend,
        libPath: args.libPath,
      );
    } on UnsupportedError {
      session = crispasr.CrispasrSession.open(args.modelPath,
          nThreads: args.nThreads,
          backend: args.backend,
          libPath: args.libPath);
    }
  } catch (e) {
    out.send({'type': 'error', 'message': 'Could not load the recogniser: $e'});
    cmd.close();
    return;
  }
  if (args.directTranslationTarget != null) {
    try {
      session.setTargetLanguage(args.directTranslationTarget!);
    } catch (_) {}
  }
  // Pay the first-call graph build now, while the screen says "loading",
  // rather than on the first words the speaker says (~2 s on a busy CPU).
  try {
    session.transcribe(Float32List(_sr), language: args.fixedSource);
  } catch (_) {}
  final kind = session.streamingKind;
  if (session.backend == 'nemotron' && kind != 2) {
    session.close();
    out.send({
      'type': 'error',
      'message':
          'This CrispASR library does not expose native Nemotron streaming. Rebuild the native library.'
    });
    cmd.close();
    return;
  }
  out.send({
    'type': 'ready',
    'backend': session.backend,
    'streamingMode': kind == 2
        ? 'native streaming'
        : kind == 3
            ? 'prefix streaming'
            : 'buffered recognition'
  });

  final loop = _LiveLoop(args, session, out);
  final done = Completer<void>();
  cmd.listen((msg) {
    if (msg is! Map) return;
    switch (msg['type']) {
      case 'audio':
        loop.push(msg['pcm'] as Float32List,
            capturedAtMs: msg['capturedAtMs'] as int?);
      case 'stop':
        loop.stop();
        session.close();
        out.send({'type': 'stopped'});
        cmd.close();
        if (!done.isCompleted) done.complete();
    }
  });
  loop.start();
  await done.future;
}

class _LiveLoop {
  _LiveLoop(this.a, this.session, this.out)
      : stepSamples = a.stepMs * _sr ~/ 1000,
        silenceSamples = a.finalSilenceMs * _sr ~/ 1000;

  final LiveAsrArgs a;
  final crispasr.CrispasrSession session;
  final SendPort out;
  final int stepSamples;
  final int silenceSamples;
  bool get _stateful => !_direct && session.streamingKind >= 2;
  int get _minDecodeSamples =>
      (a.minDecodeMs > 0
          ? a.minDecodeMs
          : (session.backend == 'cohere' ? 3000 : 500)) *
      _sr ~/
      1000;
  crispasr.StreamingSession? _stream;
  int _streamFedUntil = 0;

  static const _pad = _sr ~/ 5; // 200 ms of context around speech
  static const _maxUtterance = 60 * _sr;

  // Audio: [_buf] holds samples [_bufStart, _bufStart + _bufLen).
  Float32List _buf = Float32List(_sr * 30);
  int _bufLen = 0;
  int _bufStart = 0;
  int get _now => _bufStart + _bufLen;

  final _committer = SentenceCommitter();
  final _assembler = SentenceAssembler();
  Timer? _timer;
  bool _stopped = false;
  bool _vadBroken = false;
  double _noiseFloor = 0.003;

  // Speech timeline: absolute [start, end) spans, oldest first, and how far
  // VAD has looked. VAD covers every new sample exactly once (plus a little
  // overlap), so a step that fell behind still sees every pause in its
  // backlog — the 4-second look-back this replaced merged a whole talk
  // into one utterance whenever decoding was slower than speech.
  final List<(int, int)> _spans = [];
  int _vadPos = 0;

  // Utterance state.
  int _utt = 0;
  bool _open = false;
  int _uttStart = 0;
  int _closedUntil = 0; // speech before this belongs to closed utterances
  int _lastDecodedEnd = 0;
  String _lastText = '';
  int _lastStepAt = 0;

  // Language state.
  String? _uttLang;
  double _uttLangConf = 0;
  int _lidRuns = 0;
  String? _lastLang;

  void start() {
    _lastLang = a.fixedSource ??
        (a.expectedSources.isNotEmpty ? a.expectedSources.first : null);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  int _lastAudioAtMs = 0;

  void push(Float32List pcm, {int? capturedAtMs}) {
    if (_stopped || pcm.isEmpty) return;
    if (_bufLen + pcm.length > _buf.length) _compact(pcm.length);
    _buf.setRange(_bufLen, _bufLen + pcm.length, pcm);
    _bufLen += pcm.length;
    _lastAudioAtMs = capturedAtMs ?? DateTime.now().millisecondsSinceEpoch;
  }

  /// Drop audio no longer needed: everything before the open utterance (or
  /// before what VAD has yet to see), and grow when that is not enough.
  void _compact(int incoming) {
    var keepFrom = math.min(_vadPos, _now) - _vadHistory - _sr ~/ 2;
    if (_open) keepFrom = math.min(keepFrom, _uttStart);
    keepFrom = math.max(keepFrom, math.max(_bufStart, _now - 120 * _sr));
    final drop = keepFrom - _bufStart;
    if (drop > 0) {
      _buf.setRange(0, _bufLen - drop, _buf, drop);
      _bufLen -= drop;
      _bufStart = keepFrom;
      _spans.removeWhere((s) => s.$2 <= _bufStart);
    }
    if (_bufLen + incoming > _buf.length) {
      final grown = Float32List(math.max(_buf.length * 2, _bufLen + incoming));
      grown.setRange(0, _bufLen, _buf);
      _buf = grown;
    }
  }

  Float32List _slice(int from, int to) {
    from = math.max(from, _bufStart);
    to = math.min(to, _now);
    if (to <= from) return Float32List(0);
    return Float32List.sublistView(_buf, from - _bufStart, to - _bufStart);
  }

  void stop() {
    if (_stopped) return;
    _timer?.cancel();
    // Drain the last received PCM even when stop arrives before the next tick.
    // This also opens/closes an utterance that only exists in queued audio.
    try {
      _step(flushAll: true);
    } catch (e) {
      out.send({'type': 'error', 'message': 'Live step failed: $e'});
    }
    _stream?.close();
    _stream = null;
    _stopped = true;
  }

  void _tick() {
    if (_stopped) return;
    // Speech can start slightly after a scheduled step. If that step was
    // skipped for insufficient context, do not wait another full interval
    // before the first draft. Later drafts retain the configured cadence.
    final firstDraftDue = !_direct &&
        !_stateful &&
        _open &&
        _lastDecodedEnd == _uttStart &&
        _now - _uttStart >= _minDecodeSamples;
    if (_now - _lastStepAt < stepSamples && !firstDraftDue) return;
    final sw = Stopwatch()..start();
    _lastStepAt = _now;
    try {
      _step();
    } catch (e) {
      out.send({'type': 'error', 'message': 'Live step failed: $e'});
    }
    sw.stop();
    out.send({
      'type': 'stats',
      'stepMs': sw.elapsedMilliseconds,
      'audioUntilSec': _now / _sr,
      'decodedUntilSec': _lastDecodedEnd / _sr,
      'openSec': _open ? (_now - _uttStart) / _sr : 0.0,
      // Native calls block this isolate, so _now cannot advance during a
      // decode. Compare to the capture timestamp to include queued audio.
      'behindSec': _lastAudioAtMs == 0
          ? 0.0
          : math.max(0.0,
              (DateTime.now().millisecondsSinceEpoch - _lastAudioAtMs) / 1000),
      'misses': _committer.alignMisses,
    });
  }

  /// One pass over everything heard since the last pass. A step normally
  /// covers 500 ms; after a slow decode it covers the whole backlog, and
  /// may open, finish and close several utterances in one go.
  void _step({bool flushAll = false}) {
    final now = _now;
    _runVad(now);

    for (var guard = 0; guard < 64; guard++) {
      if (!_open) {
        final next = _spans.where((s) => s.$2 > _closedUntil).firstOrNull;
        if (next == null) return;
        _openUtterance(
            math.max(next.$1 - _pad, math.max(_closedUntil, _bufStart)));
      }

      final end = _utteranceEnd(now);
      if (end != null) {
        final to = math.min(now, end + _pad);
        _maybeAudioLid(to);
        // The last partial may already cover the whole utterance; then it
        // IS the final (the committer's fast path), no re-decode needed.
        if (_direct) {
          _decodeDirect(to);
        } else if (_lastText.isEmpty || _lastDecodedEnd < end) {
          _decode(to, finalPass: true);
        }
        _close(end);
        continue; // the backlog may hold the next utterance already
      }

      _maybeAudioLid(now);
      final lastSpeech = _lastSpeechEnd();
      if (_direct) {
        // Whole utterances only; on stop, what is open is decoded as one.
        if (flushAll) _decodeDirect(now);
      } else if (lastSpeech > _lastDecodedEnd ||
          _lastText.isEmpty ||
          flushAll) {
        _decode(now, finalPass: flushAll);
      }
      if (flushAll || now - _uttStart > _maxUtterance) {
        _close(now);
      } else if (now - lastSpeech >= silenceSamples ~/ 2) {
        // A breath at a sentence end: commit it now rather than after the
        // full closing silence.
        _handle(_committer.onPause(_utt));
      }
      return;
    }
  }

  void _openUtterance(int at) {
    _open = true;
    _utt++;
    _uttStart = at;
    _lastText = '';
    _lastDecodedEnd = at;
    _streamFedUntil = at;
    _uttLang = a.lidMode == 'fixed' ? a.fixedSource : null;
    _uttLangConf = 0;
    _lidRuns = 0;
    _committer.pressure = false;
  }

  int _lastSpeechEnd() {
    var e = _uttStart;
    for (final s in _spans) {
      if (s.$2 > _uttStart) e = math.max(e, s.$2);
    }
    return e;
  }

  /// Where the open utterance ended — the end of its last speech before a
  /// silence of at least `finalSilenceMs` — or null while it goes on.
  int? _utteranceEnd(int now) {
    final mine = _spans.where((s) => s.$2 > _uttStart).toList();
    if (mine.isEmpty) {
      // Opened on speech VAD has since revised away.
      return now - _uttStart >= silenceSamples ? _uttStart : null;
    }
    for (var k = 0; k < mine.length; k++) {
      final gapEnd = k + 1 < mine.length ? mine[k + 1].$1 : now;
      if (gapEnd - mine[k].$2 >= silenceSamples) return mine[k].$2;
    }
    return null;
  }

  /// History warms up the stateless detector; only the last half second
  /// may revise earlier spans. Rewriting the warm-up prefix invents pauses.
  void _runVad(int now) {
    var reviseFrom = math.max(_bufStart, _vadPos - _sr ~/ 2);
    while (now - reviseFrom >= _sr ~/ 4) {
      final contextFrom = math.max(_bufStart, reviseFrom - _vadHistory);
      final to = math.min(now, contextFrom + 30 * _sr);
      final found = [
        for (final span in _vad(contextFrom, to))
          if (span.$2 > reviseFrom) (math.max(reviseFrom, span.$1), span.$2),
      ];
      int? cutStart;
      _spans.removeWhere((span) {
        if (span.$2 <= reviseFrom) return false;
        if (span.$1 < reviseFrom) cutStart = span.$1;
        return true;
      });
      for (var i = 0; i < found.length; i++) {
        var span = found[i];
        if (i == 0 && cutStart != null && span.$1 <= reviseFrom + _sr ~/ 10) {
          span = (cutStart!, span.$2);
          cutStart = null;
        }
        _spans.add(span);
      }
      if (cutStart != null) _spans.add((cutStart!, reviseFrom));
      _spans.sort((a, b) => a.$1.compareTo(b.$1));
      _vadPos = to;
      if (to == now) break;
      reviseFrom = to - _sr ~/ 2;
    }
  }

  /// Speech spans in [from, to) as absolute sample indices.
  List<(int, int)> _vad(int from, int to) {
    final pcm = _slice(from, to);
    final model = a.vadModelPath;
    if (model != null && !_vadBroken) {
      try {
        // Quiet microphones can leave valid speech below Silero's useful
        // input range. Lift only the detector input; ASR keeps the original
        // waveform. Limit gain and peak level to preserve pauses and headroom.
        var energy = 0.0;
        var peak = 0.0;
        for (final sample in pcm) {
          energy += sample * sample;
          peak = math.max(peak, sample.abs());
        }
        final rms = pcm.isEmpty ? 0.0 : math.sqrt(energy / pcm.length);
        var detectorPcm = pcm;
        if (rms > 0 && rms < 0.01 && peak > 0) {
          final gain = math.min(12.0, math.min(0.03 / rms, 1.0 / peak));
          if (gain > 1) {
            detectorPcm =
                Float32List.fromList([for (final sample in pcm) sample * gain]);
          }
        }
        final spans = vadSlicesNative(model, detectorPcm,
            threshold: 0.35,
            minSpeechMs: 200,
            minSilenceMs: 150,
            speechPadMs: 30,
            nThreads: 1,
            libPath: a.libPath);
        return [
          for (final s in spans)
            (from + (s.start * _sr).round(), from + (s.end * _sr).round())
        ];
      } catch (_) {
        _vadBroken = true; // fall through to the energy detector for good
      }
    }
    return _energyVad(pcm, from);
  }

  /// Fallback: 30 ms RMS frames against an adaptive noise floor.
  List<(int, int)> _energyVad(Float32List pcm, int from) {
    const frame = 480;
    final out = <(int, int)>[];
    int? start;
    var silentFrames = 0;
    for (var i = 0; i + frame <= pcm.length; i += frame) {
      var e = 0.0;
      for (var k = i; k < i + frame; k++) {
        e += pcm[k] * pcm[k];
      }
      final rms = math.sqrt(e / frame);
      // Falls fast to a quieter frame, rises slowly (~7 %/s) so steady
      // room noise is learnt but a long sentence is not.
      _noiseFloor = rms < _noiseFloor
          ? 0.9 * _noiseFloor + 0.1 * rms
          : _noiseFloor * 1.002;
      final speech = rms > math.max(0.008, _noiseFloor * 3.5);
      if (speech) {
        start ??= i;
        silentFrames = 0;
      } else if (start != null && ++silentFrames > 6) {
        out.add((from + start, from + i - silentFrames * frame + frame));
        start = null;
        silentFrames = 0;
      }
    }
    if (start != null) out.add((from + start, from + pcm.length));
    return out;
  }

  void _maybeAudioLid(int availableEnd) {
    if (a.lidMode != 'audio' || a.audioLidPath == null) return;
    final have = availableEnd - _uttStart;
    // First look after 1.5 s of speech; one more at 5 s if unsure.
    final due = (_lidRuns == 0 && have >= 3 * _sr ~/ 2) ||
        (_lidRuns == 1 && _uttLangConf < 0.7 && have >= 5 * _sr);
    if (!due) return;
    _lidRuns++;
    final pcm = _slice(_uttStart, math.min(availableEnd, _uttStart + 8 * _sr));
    try {
      final path = a.audioLidPath!;
      final r = crispasr.detectLanguagePcm(
        pcm: pcm,
        method: _lidMethodFor(path),
        modelPath: path,
        nThreads: math.max(1, a.nThreads ~/ 2),
      );
      if (r.isEmpty) return;
      _acceptLang(normaliseLangCode(r.langCode), r.confidence, 'audio');
    } catch (_) {
      // LID is best-effort; the utterance falls back to the last language.
    }
  }

  static crispasr.LidMethod _lidMethodFor(String path) {
    final base = path.split(RegExp(r'[/\\]')).last.toLowerCase();
    if (base.startsWith('silero')) return crispasr.LidMethod.silero;
    if (base.startsWith('firered-lid')) return crispasr.LidMethod.firered;
    if (base.startsWith('ecapa')) return crispasr.LidMethod.ecapa;
    return crispasr.LidMethod.whisper;
  }

  /// Accept a detection unless it is an unexpected language detected with
  /// low confidence — a short noisy clip flipping a German talk to Dutch
  /// costs more than a missed switch, which the next utterance corrects.
  bool _acceptLang(String code, double conf, String method) {
    if (code.isEmpty || code == 'unknown') return false;
    final expected = a.expectedSources;
    final ok = expected.isEmpty || expected.contains(code) || conf >= 0.85;
    if (!ok) return false;
    // Audio LID decides the utterance (and steers the recogniser). Text
    // and recogniser reports label sentence by sentence instead: they see
    // the language of what was just decoded, which can change inside one
    // utterance (a quote, a switch mid-answer) — locking the first report
    // forced Whisper to translate the rest into that language.
    if (method == 'audio') {
      _uttLang = code;
      _uttLangConf = conf;
    }
    _lastLang = code;
    out.send({
      'type': 'lang',
      'utt': _utt,
      'lang': code,
      'conf': conf,
      'method': method,
    });
    return true;
  }

  /// Language passed to the recogniser. Whisper with no hint falls back
  /// to its historical default, English — German speech then comes out
  /// TRANSLATED into English and `detectedLanguage()` just echoes "en".
  /// Until the utterance's language is decided, ask Whisper to detect it.
  String? get _hint =>
      _uttLang ?? (session.backend == 'whisper' ? 'auto' : null);

  bool get _direct => a.directTranslationTarget != null;

  static final _nemotronLanguageTag = RegExp(r'<[a-z]{2,3}-[A-Z]{2}>');

  String _clean(String raw) {
    // Nemotron's detokenizer currently exposes its language control tokens
    // in both segment text and timed words. They are not spoken words.
    if (session.backend == 'nemotron') {
      raw = raw.replaceAll(_nemotronLanguageTag, '');
    }
    return EmotionInference.strip(raw.trim()).text.trim();
  }

  /// A speech-translation recogniser's utterance: each cue is
  /// "transcript\ntranslation"; every cue becomes one unit carrying its
  /// translation, so the translator only handles the other targets.
  void _decodeDirect(int to) {
    final pcm = _slice(_uttStart, to);
    _lastDecodedEnd = to;
    if (pcm.length < _sr ~/ 2) return;
    final segs = session.transcribe(pcm);
    final tgt = a.directTranslationTarget!;
    for (final g in segs) {
      final lines =
          g.text.split('\n').map(_clean).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final source = lines.first;
      final translation = lines.length > 1 ? lines.sublist(1).join(' ') : '';
      out.send({
        'type': 'unit',
        'utt': _utt,
        'id': _directId++,
        'text': source,
        'lang': _uttLang ?? _lastLang,
        'langConf': _uttLangConf,
        't': _uttStart / _sr + g.end,
        if (translation.isNotEmpty) 'translations': {tgt: translation},
      });
    }
  }

  int _directId = 0;

  void _decode(int to, {bool finalPass = false}) {
    if (_stateful) {
      _decodeStream(to);
      return;
    }
    var d0 = _uttStart;
    final from = _committer.decodeFrom;
    if (session.backend == 'cohere') {
      // Cohere is a buffered encoder-decoder. Cutting at a committed word
      // leaves it with tiny fragments and removes the linguistic context
      // that made its offline decode useful. Retain a bounded acoustic
      // window; the committer aligns/deduplicates the repeated hypothesis.
      d0 = math.max(_uttStart, to - 25 * _sr);
    } else if (from >= 0) {
      final lead = _committer.decodeFromExact ? 0.3 : 1.5;
      d0 = ((from - lead) * _sr).round().clamp(_uttStart, to);
    }
    // Conv front-ends need ~2 s; never hand them less while there is more.
    if (to - d0 < 2 * _sr) d0 = math.max(_uttStart, to - 2 * _sr);
    _committer.pressure = to - d0 > 9 * _sr;
    final pcm = _slice(d0, to);
    if (!finalPass && pcm.length < _minDecodeSamples) return;
    _lastDecodedEnd = to;
    if (pcm.length < _sr ~/ 2) return;
    final segs = session.transcribe(pcm, language: _hint);
    // EU AI Act Annex III 1(c): emotion / acoustic-event tags (SenseVoice
    // emits them inline) are discarded here as on every other transcription
    // path — this worker reaches the native session directly, so the
    // engine-side filter never sees its output.
    final text =
        segs.map((s) => _clean(s.text)).where((s) => s.isNotEmpty).join(' ');
    final off = d0 / _sr;
    final timed = <LtTimedWord>[];
    for (final s in segs) {
      for (final w in s.words) {
        final t = _clean(w.text);
        if (t.isEmpty) continue;
        timed.add(LtTimedWord(t, off + w.start, off + w.end));
      }
    }
    if (a.lidMode == 'recognizer') {
      final l = session.detectedLanguage();
      if (l != 'unknown' && normaliseLangCode(l) != _lastLang) {
        _acceptLang(normaliseLangCode(l), 0.6, 'recognizer');
      }
    }
    if (text.isEmpty) return;
    _lastText = text;
    // Word lists from sub-word tokenisers do not line up with the text;
    // the committer checks that itself and then ignores them.
    _handle(_committer.onPartial(_utt, text,
        tAudio: to / _sr, timed: timed.isEmpty ? null : timed));
  }

  void _streamUpdate(crispasr.StreamingUpdate? update, int to) {
    if (update == null) return;
    final text = _clean(update.text);
    if (text.isEmpty) return;
    _lastText = text;
    _handle(_committer.onPartial(_utt, text, tAudio: to / _sr));
  }

  void _decodeStream(int to) {
    // A single stream per utterance. Feed only newly arrived audio; never
    // feed the committer's overlapping decode window into a cached encoder.
    if (to <= _streamFedUntil) return;
    if (_stream == null) {
      _stream = session.openStream(
          language: _hint ?? 'auto', stepMs: a.stepMs, nThreads: a.nThreads);
      _stream!.setLiveDecode(true);
    }
    final pcm = _slice(_streamFedUntil, to);
    _streamUpdate(_stream!.feed(pcm), to);
    _streamFedUntil = to;
    _lastDecodedEnd = to;
  }

  void _close(int speechEnd) {
    if (!_open) return;
    final stream = _stream;
    if (stream != null) {
      try {
        _streamUpdate(stream.flush(), _streamFedUntil);
      } finally {
        stream.close();
        _stream = null;
      }
    }
    if (_lastText.isNotEmpty) {
      _handle(_committer.onFinal(_utt, _lastText));
    }
    final rest = _assembler.flush();
    if (rest != null) _emitUnit(rest.$1, rest.$2, rest.$3);
    out.send({'type': 'held', 'utt': _utt, 'text': '', 'lang': _lastLang});
    out.send({'type': 'tail', 'utt': _utt, 'text': '', 'lang': _lastLang});
    _open = false;
    _lastText = '';
    _closedUntil = math.max(_closedUntil, math.max(speechEnd, _uttStart + 1));
    _committer.pressure = false;
  }

  void _handle(LtUpdate up) {
    if (up.committed.isNotEmpty) {
      for (final u in _assembler.add(up.committed)) {
        _emitUnit(u.$1, u.$2, u.$3);
      }
      out.send({
        'type': 'held',
        'utt': _utt,
        'text': _assembler.heldText,
        'lang': _uttLang ?? _lastLang,
      });
    }
    if (up.tailChanged || up.committed.isNotEmpty) {
      out.send({
        'type': 'tail',
        'utt': _utt,
        'text': up.tail,
        'lang': _uttLang ?? _lastLang,
      });
    }
  }

  void _emitUnit(int id, String text, [double tEnd = -1]) {
    var conf = _uttLangConf;
    if (a.lidMode == 'text' && a.textLidPath != null) {
      // Text LID on a few words is a coin toss; keep the running language.
      if (ltSplitWords(text).length >= 3) {
        try {
          final r = crispasr.detectTextLanguage(text, a.textLidPath!);
          if (r != null) {
            final code = normaliseLangCode(r.code);
            if (_acceptLang(code, r.confidence, 'text')) conf = r.confidence;
          }
        } catch (_) {}
      }
    }
    out.send({
      'type': 'unit',
      'utt': _utt,
      'id': id,
      'text': text,
      'lang': _uttLang ?? _lastLang,
      'langConf': conf,
      // Where the sentence ends in the stream: its last word's timestamp
      // when the recogniser has them, else when it was committed.
      't': tEnd >= 0 ? tEnd : _now / _sr,
    });
  }
}
