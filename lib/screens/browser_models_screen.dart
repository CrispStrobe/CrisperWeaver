import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engines/browser_speech_engine.dart';
import '../engines/engine_factory.dart';
import '../engines/transcription_engine.dart';
import '../services/settings_service.dart';
import '../main.dart' show transcriptionServiceProvider;
import '../widgets/root_aware_back_leading.dart';

class BrowserModelsScreen extends ConsumerStatefulWidget {
  const BrowserModelsScreen({super.key});
  @override
  ConsumerState<BrowserModelsScreen> createState() =>
      _BrowserModelsScreenState();
}

class _BrowserModelsScreenState extends ConsumerState<BrowserModelsScreen> {
  EngineType _engine = EngineType.crispasr;
  List<EngineModel> _models = [];
  bool _busy = false;
  String? _error;
  double _progress = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final service = ref.read(transcriptionServiceProvider);
      final selected = ref.read(settingsServiceProvider).preferredEngine;
      _engine = selected == EngineType.onnxweb ? selected : EngineType.crispasr;
      if (service.currentEngineType != _engine) {
        await service.switchEngine(_engine);
      }
      final models = await service.currentEngine!.getAvailableModels();
      if (mounted) setState(() => _models = models);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _load(EngineModel model, {bool import = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final service = ref.read(transcriptionServiceProvider);
      if (import) {
        final picked = await FilePicker.pickFiles(
            type: FileType.custom, allowedExtensions: ['bin', 'gguf']);
        if (picked == null) return;
        final bytes = await picked.files.single.readAsBytes();
        await (service.currentEngine as BrowserSpeechEngine)
            .importModel(model.id, bytes);
      } else {
        await service.loadModel(model.id, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
      }
      ref.read(settingsServiceProvider).defaultModel = model.id;
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            leading: rootAwareBackLeading(context),
            title: const Text('Browser speech models')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
              'Models run locally in your browser. Downloads retrieve weights only; audio and text are not uploaded. Cached models can be reused without downloading again.'),
          const SizedBox(height: 16),
          DropdownButton<EngineType>(
              value: _engine,
              items: const [
                DropdownMenuItem(
                    value: EngineType.crispasr,
                    child: Text('CrispASR WASM (local)')),
                DropdownMenuItem(
                    value: EngineType.onnxweb,
                    child: Text('ONNX Runtime Web (local)')),
              ],
              onChanged: _busy
                  ? null
                  : (value) async {
                      if (value == null) return;
                      ref.read(settingsServiceProvider).preferredEngine = value;
                      await _refresh();
                    }),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            TextButton(
                onPressed: () =>
                    ref.read(transcriptionServiceProvider).stopTranscription(),
                child: const Text('Cancel'))
          ],
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final model in _models)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(model.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                              '${(model.sizeBytes / 1000000).round()} MB · ${model.isDownloaded ? 'Cached in browser' : 'Download on first use'}'),
                          Wrap(spacing: 12, children: [
                            TextButton(
                                onPressed: _busy ? null : () => _load(model),
                                child: Text(model.isDownloaded
                                    ? 'Use model'
                                    : 'Download model')),
                            if (_engine == EngineType.crispasr)
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _load(model, import: true),
                                  child: const Text('Import model file')),
                          ]),
                        ]))),
        ]),
      );
}
