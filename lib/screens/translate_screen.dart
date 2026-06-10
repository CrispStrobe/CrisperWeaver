import '../native/crispasr_import.dart' as crispasr;
import '../utils/platform_utils.dart' as plat;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../services/log_service.dart';
import '../services/model_service.dart';
import '../services/settings_service.dart';
import '../services/text_translation_service.dart';

/// Text-to-text translation via CrispASR's `crispasr_session_translate_text`.
/// Mirrors the Synthesize screen's structure: pick a downloaded model,
/// pick src/tgt languages, type text, hit Translate. Supports
/// M2M-100 (any-to-any, 100 langs), WMT21 (en↔X, two dedicated
/// checkpoints), and MADLAD-400 (419 langs).
class TranslateScreen extends ConsumerStatefulWidget {
  const TranslateScreen({super.key});

  @override
  ConsumerState<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends ConsumerState<TranslateScreen> {
  final _inputController = TextEditingController();
  final _outputController = TextEditingController();

  List<ModelInfo> _all = const [];
  bool _loading = true;
  bool _busy = false;

  String? _selectedModel;
  String _srcLang = 'en';
  String _tgtLang = 'de';
  int _maxTokens = 200;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final svc = ref.read(modelServiceProvider);
      svc.refreshFromCrispasrRegistry();
      _all = await svc.getWhisperCppModels();
      final downloaded = _all
          .where((m) => m.kind == ModelKind.translate && m.isDownloaded)
          .toList();
      if (downloaded.isNotEmpty) {
        _selectedModel ??= downloaded.first.name;
      }
    } catch (e, st) {
      Log.instance.w('translate', 'failed to refresh model list',
          error: e, stack: st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _translate() async {
    final input = _inputController.text.trim();
    if (input.isEmpty || _selectedModel == null) return;
    setState(() {
      _busy = true;
      _outputController.text = '';
    });
    try {
      final svc = ref.read(textTranslationServiceProvider);
      final out = await svc.translate(
        modelName: _selectedModel!,
        text: input,
        srcLang: _srcLang,
        tgtLang: _tgtLang,
        maxTokens: _maxTokens,
      );
      if (!mounted) return;
      setState(() => _outputController.text = out);
    } on TextTranslationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e, st) {
      Log.instance.e('translate', 'translate failed', error: e, stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Auto-detect the source language of the typed text via CrispASR's
  /// text-LID. Tries GlotLID (2102 langs) and FastText LID-176 first
  /// for wider coverage; falls back to CLD3.
  Future<void> _detectSourceLanguage() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;
    final modelService = ref.read(modelServiceProvider);

    // Try text-LID models in coverage order: GlotLID > FastText > CLD3.
    String? modelPath;
    for (final id in ['glotlid-f16', 'fasttext-lid176-f16', 'cld3-f16']) {
      final p = await modelService.getWhisperCppModelPath(id);
      if (p != null) {
        modelPath = p;
        break;
      }
    }

    if (!mounted) return;
    if (modelPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            'Download a text language-ID model (CLD3, GlotLID, or '
            'FastText LID-176) to auto-detect.'),
        action: SnackBarAction(
          label: 'Models',
          onPressed: () {
            if (mounted) context.push('/models');
          },
        ),
      ));
      return;
    }
    crispasr.TextLanguage? result;
    try {
      result = crispasr.detectTextLanguage(input, modelPath);
    } catch (e, st) {
      Log.instance.w('translate', 'text-LID failed', error: e, stack: st);
    }
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't detect the language.")));
      return;
    }
    final code = result.code;
    final known =
        TextTranslationService.supportedLanguages.any((e) => e.key == code);
    final pct = (result.confidence * 100).round();
    if (known) {
      setState(() => _srcLang = code);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Detected source: $code ($pct%)'),
        duration: const Duration(seconds: 2),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text("Detected '$code' ($pct%) — not a supported source.")));
    }
  }

  void _swapLanguages() {
    setState(() {
      final tmp = _srcLang;
      _srcLang = _tgtLang;
      _tgtLang = tmp;
      // Promote any existing output to the input pane so a quick
      // round-trip translation works without retyping.
      if (_outputController.text.isNotEmpty) {
        _inputController.text = _outputController.text;
        _outputController.text = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final translateModels = _all
        .where((m) => m.kind == ModelKind.translate)
        .toList(growable: false);
    final downloadedTranslate = translateModels
        .where((m) => m.isDownloaded)
        .toList(growable: false);

    if (plat.isWeb) {
      return _WebTranslateScreen(key: const ValueKey('web-translate'));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.translateTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (downloadedTranslate.isEmpty)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.translateNoModelsDownloaded),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                // Pre-select the Translate kind filter
                                // so the user lands directly on
                                // M2M-100 / WMT21 / MADLAD-400 entries
                                // instead of the full catalog. Await
                                // the push + refresh on return so the
                                // empty-state card disappears after a
                                // download.
                                onPressed: () async {
                                  await context.push('/models?kind=translate');
                                  if (mounted) await _refresh();
                                },
                                icon: const Icon(Icons.cloud_download_outlined,
                                    size: 18),
                                label: Text(l.synthOpenModelManagement),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      decoration:
                          InputDecoration(labelText: l.translateModelLabel),
                      initialValue: _selectedModel,
                      items: downloadedTranslate
                          .map((m) => DropdownMenuItem(
                                value: m.name,
                                child: Text(m.displayName,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedModel = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _langDropdown(l.translateSourceLang, _srcLang,
                            (v) => setState(() => _srcLang = v))),
                        IconButton(
                          tooltip: 'Auto-detect source language (CLD3)',
                          icon: const Icon(Icons.language),
                          onPressed: _busy ? null : _detectSourceLanguage,
                        ),
                        IconButton(
                          tooltip: l.translateSwap,
                          icon: const Icon(Icons.swap_horiz),
                          onPressed: _swapLanguages,
                        ),
                        Expanded(child: _langDropdown(l.translateTargetLang, _tgtLang,
                            (v) => setState(() => _tgtLang = v))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inputController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: l.translateInputLabel,
                      hintText: l.translateInputHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ||
                                  _selectedModel == null ||
                                  downloadedTranslate.isEmpty
                              ? null
                              : _translate,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.translate),
                          label: Text(l.translateRunButton),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _outputController.text.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(
                                    ClipboardData(text: _outputController.text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l.copied)),
                                );
                              },
                        icon: const Icon(Icons.content_copy),
                        label: Text(l.copyClipboard),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _outputController,
                    minLines: 4,
                    maxLines: 8,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: l.translateOutputLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(l.translateAdvanced),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.translateMaxTokens(_maxTokens),
                                style:
                                    const TextStyle(fontWeight: FontWeight.w500)),
                            Slider(
                              value: _maxTokens.toDouble(),
                              min: 32,
                              max: 1024,
                              divisions: 31,
                              label: _maxTokens.toString(),
                              onChanged: (v) =>
                                  setState(() => _maxTokens = v.round()),
                            ),
                            Text(l.translateMaxTokensHelper,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _langDropdown(
      String label, String value, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      initialValue: value,
      isExpanded: true,
      items: [
        for (final e in TextTranslationService.supportedLanguages)
          DropdownMenuItem(
            value: e.key,
            child: Text('${e.value} (${e.key})',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Web translate screen — routes through the CrispASR HF Space Gradio API
// ---------------------------------------------------------------------------

class _WebTranslateScreen extends ConsumerStatefulWidget {
  const _WebTranslateScreen({super.key});

  @override
  ConsumerState<_WebTranslateScreen> createState() =>
      _WebTranslateScreenState();
}

class _WebTranslateScreenState extends ConsumerState<_WebTranslateScreen> {
  final _inputCtrl = TextEditingController(
      text: 'The quick brown fox jumps over the lazy dog.');
  final _outputCtrl = TextEditingController();
  String _srcLang = 'en';
  String _tgtLang = 'de';
  String _model = 'M2M-100 418M — 100 langs, any→any';
  bool _busy = false;

  static const _models = [
    'M2M-100 418M — 100 langs, any→any',
    'WMT21 Dense — en↔X, 14 high-resource',
    'MADLAD-400 — 419 langs (CC-BY-SA)',
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _outputCtrl.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final baseUrl = ref.read(settingsServiceProvider).hfSpaceUrl;
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 300),
      ));
      // Call the Gradio API
      final r = await dio.post<dynamic>(
        '$baseUrl/call/translate_text',
        data: {
          'data': [text, _model, _srcLang, _tgtLang]
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final eventId =
          (r.data as Map<String, dynamic>?)?['event_id'] as String?;
      if (eventId == null) {
        _outputCtrl.text = '(no event_id returned)';
        return;
      }
      // SSE result
      final sse = await dio.get<String>(
        '$baseUrl/call/translate_text/$eventId',
        options: Options(responseType: ResponseType.plain),
      );
      for (final line in (sse.data ?? '').split('\n')) {
        if (!line.startsWith('data: ')) continue;
        final json = line.substring(6);
        // The result is a JSON array; first element is the translated text
        if (json.startsWith('[')) {
          final match = RegExp(r'"([^"]*)"').firstMatch(json);
          if (match != null) {
            _outputCtrl.text = match.group(1) ?? '';
            return;
          }
        }
      }
      _outputCtrl.text = '(no result parsed)';
    } catch (e) {
      _outputCtrl.text = 'Error: $e';
      Log.instance.e('translate-web', 'translation failed', error: e);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.translateTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Via CrispASR Cloud (HF Space)',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _model,
              decoration: const InputDecoration(labelText: 'NMT Model'),
              items: _models
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _model = v);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _srcLang,
                    decoration: const InputDecoration(labelText: 'Source lang'),
                    onChanged: (v) => _srcLang = v,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: TextFormField(
                    initialValue: _tgtLang,
                    decoration: const InputDecoration(labelText: 'Target lang'),
                    onChanged: (v) => _tgtLang = v,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  labelText: 'Source text',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _translate,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.translate),
              label: Text(_busy ? 'Translating...' : 'Translate'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _outputCtrl,
                maxLines: null,
                expands: true,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Translation',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
