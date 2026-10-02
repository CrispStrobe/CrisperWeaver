import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';

/// This is a separate, acknowledged user preference, not the general beta flag.
class BrowserModelSafetySettings extends ConsumerStatefulWidget {
  const BrowserModelSafetySettings({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  ConsumerState<BrowserModelSafetySettings> createState() =>
      _BrowserModelSafetySettingsState();
}

class _BrowserModelSafetySettingsState
    extends ConsumerState<BrowserModelSafetySettings> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsServiceProvider);
    return SwitchListTile(
      title: const Text('Allow experimental browser models'),
      subtitle: const Text(
          'Off by default. Large or unvalidated models may crash this tab or fail to run. Remote AI stays disabled in Lite.'),
      value: settings.browserAllowExperimentalModels,
      onChanged: (enabled) async {
        if (enabled) {
          final accepted = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Browser models may crash or fail'),
              content: const Text(
                  'Large and unvalidated models may exhaust browser memory, freeze or crash this tab, or fail to load. Some backends and companion files are unavailable in the browser. Download size is not total memory use. Unsaved work may be lost. This setting does not enable remote AI processing.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep filtering')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('I understand; show models')),
              ],
            ),
          );
          if (accepted != true || !mounted) return;
        }
        await settings.setBrowserAllowExperimentalModels(enabled);
        if (!mounted) return;
        if (mounted) setState(() {});
        widget.onChanged?.call();
      },
    );
  }
}
