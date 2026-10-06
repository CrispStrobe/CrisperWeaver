// Live end-to-end check of the live transcribe + translate workers against
// real models: a WAV is fed in real time, as a microphone would, through the
// recogniser isolate; every committed sentence goes to the translator
// isolate. Skipped unless the models are named in the environment:
//
//   CRISPASR_TEST_LIVE_ASR_MODEL     parakeet-tdt-0.6b-v3 GGUF (multilingual)
//   CRISPASR_TEST_LIVE_TR_MODEL      m2m100 GGUF (or a translation LLM with
//                                    CRISPASR_TEST_LIVE_TR_BACKEND=llm-translate)
//   CRISPASR_TEST_LIVE_LID_MODEL     ecapa-lid-107 GGUF (optional → audio LID)
//   CRISPASR_TEST_LIVE_VAD_MODEL     ggml-silero VAD (optional; energy VAD otherwise)
//   CRISPASR_TEST_LIVE_WAV           16 kHz mono WAV, German then English
//   CRISPASR_TEST_LIVE_SPEED         replay speed factor (default 1.0)
//   CRISPASR_TEST_LIVE_LID_MODE      audio | text | recognizer | fixed
//                                    (default: audio when a LID model is set)
//   CRISPASR_TEST_LIVE_TEXT_LID_MODEL  cld3 / fastText / GlotLID GGUF (text mode)
//
// Run with LD_LIBRARY_PATH pointing at libcrispasr.
@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crisper_weaver/services/live_translate/live_asr_worker.dart';
import 'package:crisper_weaver/services/live_translate/live_translator_worker.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _readWav16kMono(String path) {
  final b = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(b);
  var off = 12;
  while (off + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(off, off + 4));
    final len = bd.getUint32(off + 4, Endian.little);
    if (id == 'data') {
      final n = len ~/ 2;
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = bd.getInt16(off + 8 + i * 2, Endian.little) / 32768.0;
      }
      return out;
    }
    off += 8 + len + (len & 1);
  }
  throw StateError('no data chunk in $path');
}

void main() {
  final env = Platform.environment;
  final asr = env['CRISPASR_TEST_LIVE_ASR_MODEL'];
  final tr = env['CRISPASR_TEST_LIVE_TR_MODEL'];
  final wav = env['CRISPASR_TEST_LIVE_WAV'];
  final skip = (asr == null || wav == null)
      ? 'set CRISPASR_TEST_LIVE_ASR_MODEL and CRISPASR_TEST_LIVE_WAV'
      : null;

  test('German then English speech: sentences committed, routed, translated',
      () async {
    final lid = env['CRISPASR_TEST_LIVE_LID_MODEL'];
    final textLid = env['CRISPASR_TEST_LIVE_TEXT_LID_MODEL'];
    final lidMode = env['CRISPASR_TEST_LIVE_LID_MODE'] ??
        (lid != null ? 'audio' : (textLid != null ? 'text' : 'fixed'));
    final speed = double.tryParse(env['CRISPASR_TEST_LIVE_SPEED'] ?? '') ?? 1.0;
    final routes = {
      'de': ['en'],
      'en': ['de'],
    };

    // Translator.
    SendPort? trPort;
    final trReady = Completer<void>();
    final translations = <String, String>{};
    final trEvents = ReceivePort();
    final pending = <String>{};
    trEvents.listen((m) {
      if (m is SendPort) {
        trPort = m;
      } else if (m is Map) {
        if (m['type'] == 'ready') trReady.complete();
        if (m['type'] == 'error') trReady.completeError(m['message'] as String);
        if (m['type'] == 'translation' || m['type'] == 'failed') {
          final key = '${m['key']}';
          pending.remove(key);
          translations['$key:${m['tgt']}'] = '${m['text'] ?? m['message']}';
          stdout.writeln('  ⇒ [${m['tgt']}] ${m['text'] ?? 'FAILED ${m['message']}'}'
              '${m['ms'] != null ? '  (${m['ms']} ms)' : ''}');
        }
      }
    });
    if (tr != null) {
      await Isolate.spawn(
          liveTranslatorWorkerEntry,
          LiveTranslatorArgs(
            readyPort: trEvents.sendPort,
            modelPath: tr,
            backend: env['CRISPASR_TEST_LIVE_TR_BACKEND'] ?? 'm2m100',
            nThreads: 2,
          ));
      await trReady.future.timeout(const Duration(minutes: 3));
    }

    // Recogniser.
    SendPort? asrPort;
    final asrReady = Completer<void>();
    final stopped = Completer<void>();
    final units = <Map<Object?, Object?>>[];
    var maxStepMs = 0;
    final asrEvents = ReceivePort();
    asrEvents.listen((m) {
      if (m is SendPort) {
        asrPort = m;
        return;
      }
      if (m is! Map) return;
      switch (m['type']) {
        case 'ready':
          asrReady.complete();
        case 'error':
          if (!asrReady.isCompleted) {
            asrReady.completeError(m['message'] as String);
          } else {
            stdout.writeln('  ! ${m['message']}');
          }
        case 'lang':
          stdout.writeln('  ~ lang ${m['lang']} p=${(m['conf'] as num).toStringAsFixed(2)} (${m['method']})');
        case 'unit':
          units.add(m);
          final lang = m['lang'] as String? ?? 'de';
          stdout.writeln('[$lang @${(m['t'] as num).toStringAsFixed(1)}s] ${m['text']}');
          for (final t in routes[lang] ?? const ['en']) {
            if (t == lang || trPort == null) continue;
            pending.add('${m['id']}');
            trPort!.send({
              'type': 'translate',
              'key': m['id'],
              'text': m['text'],
              'src': lang,
              'tgt': t,
            });
          }
        case 'stats':
          final s = m['stepMs'] as int;
          if (s > maxStepMs) maxStepMs = s;
          if (env['CRISPASR_TEST_LIVE_STATS'] != null && s > 50) {
            stdout.writeln('  · step ${s}ms open=${(m['openSec'] as num).toStringAsFixed(1)}s');
          }
        case 'tail':
          if (env['CRISPASR_TEST_LIVE_STATS'] != null) {
            stdout.writeln('  … ${m['text']}');
          }
        case 'stopped':
          stopped.complete();
      }
    });
    await Isolate.spawn(
        liveAsrWorkerEntry,
        LiveAsrArgs(
          readyPort: asrEvents.sendPort,
          modelPath: asr!,
          backend: env['CRISPASR_TEST_LIVE_ASR_BACKEND'] ?? 'parakeet',
          vadModelPath: env['CRISPASR_TEST_LIVE_VAD_MODEL'],
          lidMode: lidMode,
          audioLidPath: lid,
          textLidPath: textLid,
          fixedSource: lidMode == 'fixed' ? 'de' : null,
          expectedSources: routes.keys.toList(),
          nThreads: 3,
        ));
    await asrReady.future.timeout(const Duration(minutes: 3));

    // Feed in real time (scaled by speed), 100 ms at a time.
    final pcm = _readWav16kMono(wav!);
    final sw = Stopwatch()..start();
    for (var pos = 0; pos < pcm.length; pos += 1600) {
      final end = (pos + 1600).clamp(0, pcm.length);
      asrPort!.send({
        'type': 'audio',
        'pcm': Float32List.fromList(Float32List.sublistView(pcm, pos, end)),
      });
      final due = Duration(microseconds: (end / 16000 / speed * 1e6).round());
      final wait = due - sw.elapsed;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    asrPort!.send({'type': 'stop'});
    await stopped.future.timeout(const Duration(seconds: 60));
    // Generous: a translation LLM on a busy CPU takes seconds a sentence.
    final until = DateTime.now().add(const Duration(seconds: 240));
    while (pending.isNotEmpty && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    trPort?.send({'type': 'stop'});
    stdout.writeln('units=${units.length} translations=${translations.length} '
        'maxStepMs=$maxStepMs audio=${(pcm.length / 16000).toStringAsFixed(1)}s '
        'wall=${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');

    expect(units.length, greaterThanOrEqualTo(4),
        reason: 'a 30 s talk should commit several sentences');
    final all = units.map((u) => u['text']).join(' ').toLowerCase();
    expect(all, contains('tagesordnung'));
    expect(all, contains('questions'));
    if (lidMode != 'fixed') {
      final langs = units.map((u) => u['lang']).toSet();
      expect(langs, containsAll(['de', 'en']),
          reason: '$lidMode LID should switch between the two languages');
      // The routing must follow the language: the German sentences are
      // labelled German, the English ones English.
      String langOf(String needle) => units
          .firstWhere((u) => (u['text'] as String).toLowerCase().contains(needle))['lang']
          as String;
      expect(langOf('tagesordnung'), 'de');
      expect(langOf('questions'), 'en');
    }
    if (tr != null) {
      expect(translations, isNotEmpty);
      expect(pending, isEmpty, reason: 'every sentence was translated');
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 15)));
}
