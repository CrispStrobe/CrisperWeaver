// CloudLlmSettingsScreen — phone-form sub-screen for the BYOK
// cloud-LLM settings.
//
// Wide / desktop layouts still see the AlertDialog rendered by
// settings_screen.dart's `_showCloudLlmDialog`; phones get this
// route instead because the dialog feels out of place on the
// platform. Both containers share the same
// [CloudLlmSettingsForm] body, so behaviour stays consistent.
//
// Conventions:
//   - Save / Clear sit in the AppBar's actions row — the
//     standard mobile pattern for "edit screen with commit".
//   - The leading back button is implicit (Scaffold provides
//     it) and discards in-progress edits without committing,
//     matching the dialog's Cancel.
//   - We pop with `result = true` on Save so the calling
//     Settings screen can rebuild its tile subtitle. Cancel
//     pops with null; both flows are safe.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/build_flavor.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/settings_service.dart';
import '../widgets/cloud_llm_settings_form.dart';

class CloudLlmSettingsScreen extends ConsumerStatefulWidget {
  const CloudLlmSettingsScreen({super.key});

  @override
  ConsumerState<CloudLlmSettingsScreen> createState() =>
      _CloudLlmSettingsScreenState();
}

class _CloudLlmSettingsScreenState
    extends ConsumerState<CloudLlmSettingsScreen> {
  final GlobalKey<CloudLlmSettingsFormState> _formKey =
      GlobalKey<CloudLlmSettingsFormState>();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.read(settingsServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(BuildFlavor.isLite
            ? l.settingsLocalHttpLlm
            : l.settingsCloudLlmCleanup),
        actions: [
          TextButton(
            onPressed: () {
              _formKey.currentState?.clear();
              Navigator.of(context).pop(true);
            },
            child: Text(l.settingsCloudLlmClear,
                style: const TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              if (_formKey.currentState?.save() != true) return;
              Navigator.of(context).pop(true);
            },
            child: Text(l.save.toUpperCase(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: CloudLlmSettingsForm(
          key: _formKey,
          initialApiUrl: settings.cloudLlmApiUrl,
          initialApiKey: settings.cloudLlmApiKey,
          initialModel: settings.cloudLlmModel,
          onCommit: (url, key, model) {
            settings.cloudLlmApiUrl = url;
            settings.cloudLlmApiKey = key;
            settings.cloudLlmModel = model;
          },
          onCleared: () {
            settings.cloudLlmApiUrl = '';
            settings.cloudLlmApiKey = '';
            settings.cloudLlmModel =
                BuildFlavor.isLite ? 'llama3.2' : 'gpt-4o-mini';
          },
        ),
      ),
    );
  }
}
