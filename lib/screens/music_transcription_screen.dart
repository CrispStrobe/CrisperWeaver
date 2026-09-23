import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../services/audio_service.dart';
import '../services/log_service.dart';
import '../services/model_catalog.dart';
import '../services/model_service.dart';
import '../services/music_transcription_service.dart';
import '../utils/file_picker_util.dart';
import '../utils/gm_programs.dart';
import '../utils/platform_utils.dart' as plat;
import '../widgets/root_aware_back_leading.dart';

/// Audio → MIDI: transcribe a recording into notes with a music model
/// (Basic Pitch, MT3, piano-transcription) and save a Standard MIDI File.
/// Behind "Show advanced features", with the other non-speech tools.
class MusicTranscriptionScreen extends ConsumerStatefulWidget {
  const MusicTranscriptionScreen({super.key});

  @override
  ConsumerState<MusicTranscriptionScreen> createState() =>
      _MusicTranscriptionScreenState();
}

class _MusicTranscriptionScreenState
    extends ConsumerState<MusicTranscriptionScreen> {
  List<ModelInfo> _models = const [];
  bool _loading = true;
  String? _model;
  String? _audioPath;
  bool _busy = false;
  MusicTranscription? _result;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final all = await ref.read(modelServiceProvider).getWhisperCppModels();
      final music = all
          .where((m) => m.kind == ModelKind.music && m.isDownloaded)
          .toList();
      if (!mounted) return;
      setState(() {
        _models = music;
        if (_model == null || !music.any((m) => m.name == _model)) {
          _model = music.isEmpty ? null : music.first.name;
        }
      });
    } catch (e, st) {
      Log.instance.w('music', 'model list refresh failed', error: e, stack: st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAudio() async {
    try {
      final pick = await pickFilesRobust(type: FileType.audio);
      if (pick.isEmpty || !mounted) return;
      setState(() {
        _audioPath = pick.localPaths.first;
        _result = null;
      });
    } catch (e, st) {
      Log.instance.w('music', 'audio pick failed', error: e, stack: st);
    }
  }

  Future<void> _transcribe() async {
    final audio = _audioPath;
    final model = _model;
    if (audio == null || model == null) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final svc = MusicTranscriptionService(
        modelService: ref.read(modelServiceProvider),
        audioService: ref.read(audioServiceProvider),
      );
      final result = await svc.transcribe(audioPath: audio, modelName: model);
      if (mounted) setState(() => _result = result);
    } catch (e, st) {
      Log.instance.e('music', 'transcription failed', error: e, stack: st);
      if (mounted) {
        _toast(AppLocalizations.of(context).musicFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMidi() async {
    final result = _result;
    final audio = _audioPath;
    if (result == null || audio == null) return;
    final l = AppLocalizations.of(context);
    final bytes = result.toMidi();
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: l.musicSaveAs,
        initialDirectory: p.dirname(audio),
        fileName: '${p.basenameWithoutExtension(audio)}.mid',
        type: FileType.custom,
        allowedExtensions: const ['mid'],
        bytes: bytes,
      );
      if (path == null) return;
      // Mobile pickers write `bytes` themselves; desktop returns a path.
      if (plat.isDesktop) await File(path).writeAsBytes(bytes, flush: true);
      if (mounted) _toast(l.musicSavedTo(path));
    } catch (e, st) {
      Log.instance.e('music', 'MIDI save failed', error: e, stack: st);
      if (mounted) _toast(e.toString());
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: rootAwareBackLeading(context),
        title: Text(l.menuMusicToMidi),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l.musicIntro),
                const SizedBox(height: 16),
                if (_models.isEmpty)
                  _noModelsCard(l)
                else ...[
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(labelText: l.musicModelLabel),
                    initialValue: _model,
                    items: [
                      for (final m in _models)
                        DropdownMenuItem(
                          value: m.name,
                          child: Text(m.displayName,
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _model = v;
                              _result = null;
                            }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickAudio,
                        icon: const Icon(Icons.audio_file, size: 18),
                        label: Text(l.musicPickAudio),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _audioPath == null ? '' : p.basename(_audioPath!),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: (_busy || _audioPath == null || _model == null)
                        ? null
                        : _transcribe,
                    icon: const Icon(Icons.music_note),
                    label: Text(l.musicTranscribe),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(l.musicWorking),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 16),
                    _resultCard(l, _result!),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _noModelsCard(AppLocalizations l) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.musicNoModels),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await context.push('/models?kind=${ModelKind.music.name}');
                    if (mounted) await _refresh();
                  },
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: Text(l.synthOpenModelManagement),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _resultCard(AppLocalizations l, MusicTranscription r) {
    if (r.notes.isEmpty) {
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(12), child: Text(l.musicNoNotes)));
    }
    final instruments = [
      for (final prog in r.programs) gmProgramName(prog) ?? '$prog'
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.musicResult(
              r.notes.length,
              r.lastOffSeconds.toStringAsFixed(1),
              (r.elapsed.inMilliseconds / 1000).toStringAsFixed(1),
            )),
            if (instruments.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(l.musicInstruments(instruments.join(', '))),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _saveMidi,
                icon: const Icon(Icons.save_alt),
                label: Text(l.musicSaveMidi),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
