// LiveTranslatorWorker — the translator half of live transcribe + translate.
//
// One isolate, one translator model, any number of language pairs: m2m100 /
// MADLAD translate any-to-any through `CrispasrSession.translateText`, and a
// translation chat LLM (Hy-MT2, Index-Translate) runs through the chat ABI
// with the instruction it was trained on — the same two kinds upstream's
// `--translate-backend` accepts.
//
// Wire protocol:
//   main → worker: {type: translate, key, text, src, tgt}
//                  {type: stop}
//   worker → main: {type: ready, kind}
//                  {type: error, message}
//                  {type: translation, key, tgt, text, ms}
//                  {type: failed, key, tgt, message}
//                  {type: stopped}                 — models closed

import 'dart:async';
import 'dart:isolate';

import '../../native/crispasr_import.dart' as crispasr;

class LiveTranslatorArgs {
  const LiveTranslatorArgs({
    required this.readyPort,
    required this.modelPath,
    required this.backend,
    this.useGpu = true,
    this.nThreads = 0,
  });
  final SendPort readyPort;
  final String modelPath;

  /// Catalog backend: 'm2m100' / 'madlad' / … for a translation model,
  /// [chatTranslateBackend] for a translation chat LLM.
  final String backend;
  final bool useGpu;
  final int nThreads;
}

/// Catalog backend id of translation chat LLMs (Hy-MT2, Index-Translate).
const chatTranslateBackend = 'llm-translate';

Future<void> liveTranslatorWorkerEntry(LiveTranslatorArgs args) async {
  final cmd = ReceivePort();
  args.readyPort.send(cmd.sendPort);
  final out = args.readyPort;

  final _Translator tr;
  try {
    tr = args.backend == chatTranslateBackend
        ? _ChatTranslator.open(args)
        : _SessionTranslator.open(args);
  } catch (e) {
    out.send({'type': 'error', 'message': 'Could not load the translator: $e'});
    cmd.close();
    return;
  }
  // One throwaway translation, as upstream does before the first sentence:
  // it pays the first-call graph build, and proves this file really is a
  // text translator (a speech-translation model also claims the capability
  // but returns nothing here).
  try {
    final probe = await tr.translate('Hello.', 'en', 'de');
    if (probe.isEmpty) {
      tr.close();
      out.send({
        'type': 'error',
        'message': 'This model produced no translation — is it a text '
            'translator (M2M-100, MADLAD, Hy-MT2, Index-Translate)?',
      });
      cmd.close();
      return;
    }
  } catch (e) {
    tr.close();
    out.send({'type': 'error', 'message': 'The translator failed: $e'});
    cmd.close();
    return;
  }
  out.send({'type': 'ready', 'kind': tr.kind});

  await for (final msg in cmd) {
    if (msg is! Map) continue;
    if (msg['type'] == 'stop') {
      tr.close();
      out.send({'type': 'stopped'});
      cmd.close();
      break;
    }
    if (msg['type'] != 'translate') continue;
    final key = msg['key'];
    final tgt = msg['tgt'] as String;
    final sw = Stopwatch()..start();
    try {
      final text = await tr.translate(
          msg['text'] as String, msg['src'] as String, tgt);
      out.send({
        'type': 'translation',
        'key': key,
        'tgt': tgt,
        'text': text,
        'ms': sw.elapsedMilliseconds,
      });
    } catch (e) {
      out.send({'type': 'failed', 'key': key, 'tgt': tgt, 'message': '$e'});
    }
  }
}

abstract class _Translator {
  String get kind;
  Future<String> translate(String text, String src, String tgt);
  void close();
}

class _SessionTranslator implements _Translator {
  _SessionTranslator(this._s);
  final crispasr.CrispasrSession _s;

  factory _SessionTranslator.open(LiveTranslatorArgs a) {
    crispasr.CrispasrSession s;
    try {
      s = crispasr.CrispasrSession.openWithParams(a.modelPath,
          nThreads: a.nThreads, useGpu: a.useGpu, backend: a.backend);
    } on UnsupportedError {
      s = crispasr.CrispasrSession.open(a.modelPath,
          nThreads: a.nThreads, backend: a.backend);
    }
    // Greedy, as upstream's live mode does (--translate-beam 1): m2m100's
    // beam search has no KV cache, and beam 5 (its default since #439) took
    // ~6 s a sentence on an M1 — no use for captions.
    try {
      s.setBeamSize(1);
    } catch (_) {
      // Older library without the setter: its translators default to greedy.
    }
    return _SessionTranslator(s);
  }

  @override
  String get kind => _s.backend;

  @override
  Future<String> translate(String text, String src, String tgt) async =>
      (_s.translateText(text, src, tgt) ?? '').trim();

  @override
  void close() => _s.close();
}

class _ChatTranslator implements _Translator {
  _ChatTranslator(this._s, this._preset);
  final crispasr.CrispasrChatSession _s;
  final String _preset;

  factory _ChatTranslator.open(LiveTranslatorArgs a) {
    final s = crispasr.CrispasrChatSession.open(
      a.modelPath,
      params: crispasr.ChatOpenParams(
        nThreads: a.nThreads > 0 ? a.nThreads : null,
        nCtx: 2048, // one sentence in, one out
        nGpuLayers: a.useGpu ? null : 0,
      ),
    );
    return _ChatTranslator(s, translationPromptPreset(a.modelPath));
  }

  @override
  String get kind => 'llm:$_preset';

  @override
  Future<String> translate(String text, String src, String tgt) async {
    _s.reset(); // every sentence is its own conversation
    final raw = await _s.generate(
      [crispasr.ChatMessage.user(buildTranslationPrompt(_preset, text, src, tgt))],
      params: const crispasr.ChatGenerateParams(
        maxTokens: 256,
        temperature: 0, // greedy: a translation, not a conversation
        repeatPenalty: 1.0,
      ),
    );
    return cleanLlmTranslation(raw);
  }

  @override
  void close() => _s.close();
}

/// A translation LLM only works with the instruction it was trained on.
/// Upstream picks `index-translate` for a file named like that model and
/// `hy-mt2` otherwise; so do we.
String translationPromptPreset(String modelPath) =>
    modelPath.toLowerCase().contains('index-translate')
        ? 'index-translate'
        : 'hy-mt2';

/// The prompts of crispasr_run.cpp's `--translate-prompt` presets, verbatim.
String buildTranslationPrompt(
    String preset, String text, String src, String tgt) {
  if (preset == 'index-translate') {
    return '请将以下${langNameZh(src)}文本翻译为${langNameZh(tgt)}，'
        '直接输出翻译结果，不要进行任何解释。\n\n$text';
  }
  return 'Translate the following text into ${langNameEn(tgt)}. Note that '
      'you should only output the translated result without any additional '
      'explanation:\n\n$text';
}

/// Strip a reasoning model's `<think>` block and stray wrapping.
String cleanLlmTranslation(String raw) {
  var s = raw;
  final close = s.lastIndexOf('</think>');
  if (close >= 0) s = s.substring(close + '</think>'.length);
  s = s.replaceAll(RegExp(r'<think>[\s\S]*$'), '');
  return s.trim();
}

const _en = {
  'ar': 'Arabic', 'bg': 'Bulgarian', 'ca': 'Catalan', 'cs': 'Czech',
  'da': 'Danish', 'de': 'German', 'el': 'Greek', 'en': 'English',
  'es': 'Spanish', 'et': 'Estonian', 'fa': 'Persian', 'fi': 'Finnish',
  'fr': 'French', 'he': 'Hebrew', 'hi': 'Hindi', 'hr': 'Croatian',
  'hu': 'Hungarian', 'id': 'Indonesian', 'it': 'Italian', 'ja': 'Japanese',
  'ko': 'Korean', 'lt': 'Lithuanian', 'lv': 'Latvian', 'ms': 'Malay',
  'nl': 'Dutch', 'no': 'Norwegian', 'pl': 'Polish', 'pt': 'Portuguese',
  'ro': 'Romanian', 'ru': 'Russian', 'sk': 'Slovak', 'sl': 'Slovenian',
  'sr': 'Serbian', 'sv': 'Swedish', 'th': 'Thai', 'tl': 'Filipino',
  'tr': 'Turkish', 'uk': 'Ukrainian', 'ur': 'Urdu', 'vi': 'Vietnamese',
  'zh': 'Chinese',
};

const _zh = {
  'ar': '阿拉伯语', 'cs': '捷克语', 'da': '丹麦语', 'de': '德语', 'el': '希腊语',
  'en': '英语', 'es': '西班牙语', 'fi': '芬兰语', 'fr': '法语', 'he': '希伯来语',
  'hi': '印地语', 'hu': '匈牙利语', 'id': '印尼语', 'it': '意大利语',
  'ja': '日语', 'ko': '韩语', 'ms': '马来语', 'nl': '荷兰语', 'no': '挪威语',
  'pl': '波兰语', 'pt': '葡萄牙语', 'ro': '罗马尼亚语', 'ru': '俄语',
  'sv': '瑞典语', 'th': '泰语', 'tr': '土耳其语', 'uk': '乌克兰语',
  'vi': '越南语', 'zh': '中文',
};

String langNameEn(String code) => _en[code] ?? code;
String langNameZh(String code) => _zh[code] ?? langNameEn(code);
