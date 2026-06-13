// §5.8.1 — Settings → Speakers
//
// Manage the on-device speaker DB used by the diarisation
// post-process. Enrol via a short live recording or an existing
// audio file; the SpeakerIdService extracts a 192-d TitaNet
// embedding and persists it under <app-docs>/speakers/. Nothing
// ever leaves the device.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/generated/app_localizations.dart';
import '../providers/speaker_management_provider.dart';
import '../services/audio_service.dart' show audioServiceProvider;
import '../services/log_service.dart';
import '../services/settings_service.dart' show settingsServiceProvider;
import '../services/speaker_id_service.dart';
import '../utils/file_picker_util.dart';
import '../native/crispasr_import.dart' as crispasr;

class SpeakerManagementScreen extends ConsumerStatefulWidget {
  const SpeakerManagementScreen({super.key});

  @override
  ConsumerState<SpeakerManagementScreen> createState() =>
      _SpeakerManagementScreenState();
}

class _SpeakerManagementScreenState
    extends ConsumerState<SpeakerManagementScreen> {
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final svc = ref.read(speakerIdServiceProvider);
    final names = await svc.listSpeakers();
    final available = await svc.isAvailable;
    if (!mounted) return;
    ref.read(speakerManagementProvider.notifier).setRefreshResult(
      speakers: names,
      modelAvailable: available,
    );
  }

  Future<void> _openEnrolFlow() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const _EnrolSpeakerScreen(),
        fullscreenDialog: true,
      ),
    );
    if (ok == true) _refresh();
  }

  Future<void> _confirmDelete(String name) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.speakersDeleteTitle),
        content: Text(l.speakersDeleteBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final svc = ref.read(speakerIdServiceProvider);
    final ok = await svc.deleteSpeaker(name);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.speakersDeleteFailed)),
      );
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final spkState = ref.watch(speakerManagementProvider);
    final speakers = spkState.speakers;
    return Scaffold(
      appBar: AppBar(title: Text(l.speakersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEnrolFlow,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(l.speakersAdd),
      ),
      body: speakers == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l.speakersPrivacyNote)),
                      ],
                    ),
                  ),
                ),
                if (!spkState.modelAvailable) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_download_outlined),
                          const SizedBox(width: 12),
                          Expanded(child: Text(l.speakersDownloadModelHint)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (speakers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(l.speakersEmpty,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  )
                else
                  ...speakers.map((name) => ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(name),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l.delete,
                          onPressed: () => _confirmDelete(name),
                        ),
                      )),
              ],
            ),
    );
  }
}

enum _EnrolSource { record, file }

class _EnrolSpeakerScreen extends ConsumerStatefulWidget {
  const _EnrolSpeakerScreen();

  @override
  ConsumerState<_EnrolSpeakerScreen> createState() =>
      _EnrolSpeakerScreenState();
}

class _EnrolSpeakerScreenState extends ConsumerState<_EnrolSpeakerScreen> {
  static const int _recordSeconds = 10;

  final TextEditingController _nameCtrl = TextEditingController();
  _EnrolSource _source = _EnrolSource.record;
  String? _capturedPath;
  bool _recording = false;
  int _secondsLeft = _recordSeconds;
  Timer? _timer;
  bool _busy = false;
  String? _error;
  List<String> _existingNames = const [];

  @override
  void initState() {
    super.initState();
    _loadExistingNames();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingNames() async {
    final svc = ref.read(speakerIdServiceProvider);
    final names = await svc.listSpeakers();
    if (!mounted) return;
    setState(() => _existingNames = names);
  }

  Future<void> _startRecording() async {
    setState(() {
      _error = null;
      _capturedPath = null;
      _secondsLeft = _recordSeconds;
      _recording = true;
    });
    try {
      final audio = ref.read(audioServiceProvider);
      final settings = ref.read(settingsServiceProvider);
      final path = await audio.startRecording(settingsService: settings);
      if (path == null) {
        if (!mounted) return;
        setState(() {
          _recording = false;
          _error = AppLocalizations.of(context).speakersRecordNoPermission;
        });
        return;
      }
      _capturedPath = path;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_secondsLeft <= 1) {
          t.cancel();
          await _stopRecording();
        } else {
          setState(() => _secondsLeft -= 1);
        }
      });
    } catch (e, st) {
      Log.instance.e('speakers', 'start recording failed', error: e, stack: st);
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final audio = ref.read(audioServiceProvider);
    try {
      final ret = await audio.stopRecording();
      if (ret != null) _capturedPath = ret;
    } catch (e, st) {
      Log.instance.w('speakers', 'stop recording failed', error: e, stack: st);
    }
    if (!mounted) return;
    setState(() => _recording = false);
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final pick = await pickFilesRobust(
        type: FileType.audio,
        allowedExtensions: const ['wav', 'flac', 'mp3', 'm4a', 'ogg'],
      );
      if (pick.isEmpty) return;
      if (!mounted) return;
      setState(() => _capturedPath = pick.localPaths.first);
    } on FilePickerCloudUriUnsupported catch (e, st) {
      Log.instance.w('speakers', 'cloud-URI pick failed even with fallback',
          error: e, stack: st);
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context).filePickerCloudFileUnsupported);
    } catch (e, st) {
      Log.instance.w('speakers', 'file pick failed', error: e, stack: st);
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  String? _validateName(String name) {
    final l = AppLocalizations.of(context);
    final trimmed = name.trim();
    if (trimmed.isEmpty) return l.speakersNameRequired;
    if (_existingNames.any((n) => n.toLowerCase() == trimmed.toLowerCase())) {
      return l.speakersNameTaken;
    }
    return null;
  }

  Future<void> _enrol() async {
    final l = AppLocalizations.of(context);
    final nameError = _validateName(_nameCtrl.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final path = _capturedPath;
    if (path == null) {
      setState(() => _error = l.speakersNoSample);
      return;
    }

    // GDPR Art. 9(2)(a) — explicit consent before biometric processing.
    final consented = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.speakerConsentTitle),
        content: Text(l.speakerConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.speakerConsentAgree),
          ),
        ],
      ),
    );
    if (consented != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final decoded = crispasr.decodeAudioFile(path);
      final svc = ref.read(speakerIdServiceProvider);
      final ok = await svc.enroll(_nameCtrl.text.trim(), decoded.samples);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = l.speakersEnrolFailed;
        });
        return;
      }
      // Persist the consent record alongside the speaker profile.
      await svc.saveConsent(_nameCtrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      Log.instance.e('speakers', 'enrol failed', error: e, stack: st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.speakersEnrolTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_EnrolSource>(
              segments: [
                ButtonSegment(
                  value: _EnrolSource.record,
                  label: Text(l.speakersSourceRecord),
                  icon: const Icon(Icons.mic_outlined),
                ),
                ButtonSegment(
                  value: _EnrolSource.file,
                  label: Text(l.speakersSourceFile),
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ],
              selected: {_source},
              onSelectionChanged: _recording
                  ? null
                  : (s) => setState(() {
                        _source = s.first;
                        _capturedPath = null;
                      }),
            ),
            const SizedBox(height: 16),
            if (_source == _EnrolSource.record)
              _buildRecordPanel(context)
            else
              _buildFilePanel(context),
            const SizedBox(height: 24),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: l.speakersName,
                border: const OutlineInputBorder(),
              ),
              enabled: !_busy,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy || _capturedPath == null ? null : _enrol,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(l.speakersEnrolButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordPanel(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _recording
                  ? l.speakersRecordingCountdown(_secondsLeft)
                  : _capturedPath != null
                      ? l.speakersRecordingDone(_recordSeconds)
                      : l.speakersRecordHint(_recordSeconds),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : (_recording ? _stopRecording : _startRecording),
              icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(_recording ? l.speakersRecordStop : l.speakersRecord),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePanel(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _capturedPath != null
                  ? _shortPath(_capturedPath!)
                  : l.speakersPickHint,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(l.speakersPickButton),
            ),
          ],
        ),
      ),
    );
  }

  String _shortPath(String full) {
    final sep = p.separator;
    final parts = full.split(sep);
    if (parts.length <= 2) return full;
    return '.../${parts[parts.length - 2]}$sep${parts.last}';
  }
}
