import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/generated/app_localizations.dart';
import '../services/log_service.dart';
import '../services/voice_baking_service.dart';
import '../utils/file_picker_util.dart';

/// Wraps `models/bake-chatterbox-voice-from-wav.py` in a UI flow.
/// Pick a WAV, set the output filename, optionally override the
/// Python interpreter / script path, hit Bake. Streams the script's
/// stdout/stderr into the in-app log + a tail panel so progress is
/// visible without leaving the screen.
class VoiceBakeScreen extends ConsumerStatefulWidget {
  const VoiceBakeScreen({super.key});

  @override
  ConsumerState<VoiceBakeScreen> createState() => _VoiceBakeScreenState();
}

class _VoiceBakeScreenState extends ConsumerState<VoiceBakeScreen> {
  String? _wavPath;
  final _outputController = TextEditingController(text: 'my-voice.gguf');
  final _pythonController = TextEditingController(text: 'python3');
  final _scriptController =
      TextEditingController(text: VoiceBakingService.defaultScriptPath);
  double _exaggeration = 0.5;
  bool _busy = false;
  // Last-N stderr/stdout lines we echo into the screen. Bigger than
  // the user wants to scroll, smaller than the in-app log buffer.
  final List<String> _logTail = [];
  static const int _logTailMax = 60;

  @override
  void dispose() {
    _outputController.dispose();
    _pythonController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _pickWav() async {
    try {
      final pick = await pickFilesRobust(
        type: FileType.audio,
        allowedExtensions: const ['wav'],
      );
      if (pick.isEmpty) return;
      setState(() => _wavPath = pick.localPaths.first);
    } on FilePickerCloudUriUnsupported catch (e, st) {
      Log.instance.w('voice-bake', 'cloud-URI pick failed even with fallback',
          error: e, stack: st);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.filePickerCloudFileUnsupported)),
        );
      }
    } catch (e, st) {
      Log.instance.w('voice-bake', 'wav picker failed', error: e, stack: st);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.filePickerFailed(e.toString()))),
        );
      }
    }
  }

  Future<void> _bake() async {
    Log.instance.i('voice-bake', 'bake start', fields: {
      'wav': _wavPath ?? '',
      'output': _outputController.text.trim(),
    });
    final l = AppLocalizations.of(context);
    if (_wavPath == null || _outputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.voiceBakeMissingInputs)),
      );
      return;
    }
    setState(() {
      _busy = true;
      _logTail.clear();
    });
    try {
      final svc = ref.read(voiceBakingServiceProvider);
      final out = await svc.bake(
        wavPath: _wavPath!,
        outputName: _outputController.text.trim(),
        pythonExecutable: _pythonController.text.trim().isEmpty
            ? 'python3'
            : _pythonController.text.trim(),
        scriptPath: _scriptController.text.trim().isEmpty
            ? VoiceBakingService.defaultScriptPath
            : _scriptController.text.trim(),
        exaggeration: _exaggeration,
        onStdout: (line) {
          if (!mounted) return;
          setState(() {
            _logTail.add(line);
            if (_logTail.length > _logTailMax) {
              _logTail.removeRange(0, _logTail.length - _logTailMax);
            }
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.voiceBakeSuccess(out.path))),
      );
    } on VoiceBakingException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.voiceBakeFailure(e.message))),
      );
    } catch (e, st) {
      Log.instance.e('voice-bake', 'unexpected error',
          error: e, stack: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.voiceBakeFailure(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.voiceBakeTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!VoiceBakingService.isSupported)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l.voiceBakeIntro),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l.voiceBakeIntro,
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            const SizedBox(height: 12),
            // Reference WAV picker.
            Row(
              children: [
                Expanded(
                  child: Text(
                    _wavPath == null
                        ? '${l.voiceBakeWavLabel}: —'
                        : '${l.voiceBakeWavLabel}: ${p.basename(_wavPath!)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickWav,
                  icon: const Icon(Icons.audio_file),
                  label: Text(l.voiceBakeWavPick),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _outputController,
              decoration: InputDecoration(
                labelText: l.voiceBakeOutputName,
                helperText: l.voiceBakeOutputNameHelper,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            // Exaggeration slider — passes --exaggeration to the script.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.voiceBakeExaggeration(_exaggeration.toStringAsFixed(2)),
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Slider(
                  value: _exaggeration,
                  divisions: 20,
                  label: _exaggeration.toStringAsFixed(2),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _exaggeration = v),
                ),
                Text(l.voiceBakeExaggerationHelper,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l.voiceBakePythonLabel),
              children: [
                TextField(
                  controller: _pythonController,
                  decoration: InputDecoration(
                    labelText: l.voiceBakePythonLabel,
                    helperText: l.voiceBakePythonHelper,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _scriptController,
                  decoration: InputDecoration(
                    labelText: l.voiceBakeScriptLabel,
                    helperText: l.voiceBakeScriptHelper,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ||
                      _wavPath == null ||
                      !VoiceBakingService.isSupported
                  ? null
                  : _bake,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cake),
              label: Text(_busy ? l.voiceBakeRunning : l.voiceBakeRun),
            ),
            const SizedBox(height: 12),
            // Live tail of stdout/stderr — bake takes 30-60 s on M1
            // and the user wants to see something happen mid-flight.
            if (_logTail.isNotEmpty)
              Expanded(
                child: Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logTail.length,
                    reverse: true,
                    itemBuilder: (_, i) => Text(
                      _logTail[_logTail.length - 1 - i],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
