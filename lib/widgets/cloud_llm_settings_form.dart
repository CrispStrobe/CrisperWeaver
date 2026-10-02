// CloudLlmSettingsForm — the BYOK cloud-LLM settings form body.
//
// Reusable between two containers:
//   - The original AlertDialog (settings_screen.dart's
//     _showCloudLlmDialog) on wide layouts.
//   - The phone-only `/settings/cloud-llm` sub-screen
//     (cloud_llm_settings_screen.dart) on narrow layouts.
//
// The form holds its own controllers (the only stateful bit
// worth encapsulating); the parent supplies initial values,
// reads back via the controller-style API, and decides what to
// do with Save / Clear (commit + pop in both cases — see the
// containers for the exact wiring).
//
// Pattern: parent holds a `GlobalKey<CloudLlmSettingsFormState>`
// and calls `.save()` / `.clear()` from its action buttons. The
// callbacks `onCommit` / `onCleared` fire after the
// corresponding controller mutation so the parent can update
// SettingsService.

import 'package:flutter/material.dart';

import '../constants/build_flavor.dart';
import '../l10n/generated/app_localizations.dart';

class CloudLlmSettingsForm extends StatefulWidget {
  const CloudLlmSettingsForm({
    super.key,
    required this.initialApiUrl,
    required this.initialApiKey,
    required this.initialModel,
    required this.onCommit,
    required this.onCleared,
  });

  final String initialApiUrl;
  final String initialApiKey;
  final String initialModel;

  /// Fires when the parent calls `save()`. Already-trimmed
  /// strings; `model` falls back to `'gpt-4o-mini'` when the
  /// user typed an empty string (matches the dialog's
  /// historical behaviour so we don't break existing installs).
  final void Function(String apiUrl, String apiKey, String model) onCommit;

  /// Fires when the parent calls `clear()`. Same defaults as
  /// the old dialog wiped to.
  final VoidCallback onCleared;

  @override
  State<CloudLlmSettingsForm> createState() => CloudLlmSettingsFormState();
}

class CloudLlmSettingsFormState extends State<CloudLlmSettingsForm> {
  String? _error;
  late final TextEditingController _urlCtl;
  late final TextEditingController _keyCtl;
  late final TextEditingController _modelCtl;

  @override
  void initState() {
    super.initState();
    _urlCtl = TextEditingController(text: widget.initialApiUrl);
    _keyCtl = TextEditingController(text: widget.initialApiKey);
    _modelCtl = TextEditingController(text: widget.initialModel);
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    _keyCtl.dispose();
    _modelCtl.dispose();
    super.dispose();
  }

  /// Commit the current form values via [widget.onCommit]. Does
  /// NOT pop — the caller decides whether this Save also closes
  /// the dialog / pops the screen.
  bool save() {
    final m = _modelCtl.text.trim();
    final url = _urlCtl.text.trim();
    if (BuildFlavor.isLite &&
        url.isNotEmpty &&
        (!BuildFlavor.allowsAiEndpoint(url) ||
            !BuildFlavor.allowsHttpModel(m))) {
      setState(
          () => _error = AppLocalizations.of(context).settingsLocalHttpInvalid);
      return false;
    }
    setState(() => _error = null);
    widget.onCommit(
      _urlCtl.text.trim(),
      _keyCtl.text.trim(),
      m.isEmpty ? (BuildFlavor.isLite ? 'llama3.2' : 'gpt-4o-mini') : m,
    );
    return true;
  }

  /// Wipe the fields back to defaults and notify the parent via
  /// [widget.onCleared] so SettingsService gets cleared too.
  void clear() {
    _urlCtl.text = '';
    _keyCtl.text = '';
    _modelCtl.text = BuildFlavor.isLite ? 'llama3.2' : 'gpt-4o-mini';
    widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
            BuildFlavor.isLite
                ? l.settingsLocalHttpLlmHelp
                : l.settingsCloudLlmHelp,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 12),
        TextField(
          controller: _urlCtl,
          decoration: InputDecoration(
            labelText: l.settingsCloudLlmUrl,
            errorText: _error,
            hintText: BuildFlavor.isLite
                ? 'http://127.0.0.1:11434/v1/chat/completions'
                : 'https://api.openai.com/v1/chat/completions',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keyCtl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l.settingsCloudLlmKey,
            hintText:
                BuildFlavor.isLite ? l.settingsLocalHttpKeyOptional : 'sk-…',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _modelCtl,
          decoration: InputDecoration(
            labelText: l.settingsCloudLlmModel,
            hintText: BuildFlavor.isLite ? 'llama3.2' : 'gpt-4o-mini',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
