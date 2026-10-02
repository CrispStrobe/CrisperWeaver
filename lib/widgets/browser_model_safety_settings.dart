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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
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
      ),
      const Text('CrispASR CPU processing'),
      DropdownButton<int>(
        value: settings.browserCpuThreads,
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: 1, child: Text('One thread (default)')),
          DropdownMenuItem(value: 2, child: Text('Two threads')),
          DropdownMenuItem(value: 4, child: Text('Four threads')),
        ],
        onChanged: (value) async {
          if (value == null) return;
          await settings.setBrowserCpuThreads(value);
          if (!mounted) return;
          setState(() {});
          widget.onChanged?.call();
        },
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Applies on the next model load. Parallel processing requires browser isolation; otherwise one thread is used. More threads can use more memory and are not always faster.',
        ),
      ),
      const Text('ONNX processing'),
      DropdownButton<String>(
        value: settings.browserExecutionProvider,
        isExpanded: true,
        items: const [
          DropdownMenuItem(
              value: 'auto', child: Text('Automatic: GPU when available')),
          DropdownMenuItem(value: 'wasm', child: Text('CPU (WASM)')),
          DropdownMenuItem(value: 'webgpu', child: Text('Try GPU (WebGPU)')),
        ],
        onChanged: (value) async {
          if (value == null) return;
          if (value != 'wasm' && !settings.browserGpuWarningAccepted) {
            final accepted = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                      title: const Text('GPU processing may crash or fail'),
                      content: const Text(
                          'Browser GPU support depends on the model and graphics driver. GPU processing downloads larger, unquantized model weights. It may use extra memory, freeze or crash this tab, or fail to run. Save your work first. Recoverable GPU errors fall back to local CPU processing; a crashed tab cannot recover automatically. This does not enable remote AI.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Keep CPU processing')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('I understand; try GPU'))
                      ],
                    ));
            if (!mounted || accepted != true) {
              if (mounted) setState(() {});
              return;
            }
            await settings.acknowledgeBrowserGpuWarning();
          }
          await settings.setBrowserExecutionProvider(value);
          if (!mounted) return;
          setState(() {});
          widget.onChanged?.call();
        },
      ),
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
              'Applies on the next model load. CPU is the default. Recoverable GPU errors fall back to local CPU processing. CrispASR models use CPU processing.')),
    ]);
  }
}
