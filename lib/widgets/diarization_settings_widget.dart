import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../native/crispasr_import.dart' as crispasr;

/// The diarisation card at the top of Advanced options.
///
/// §35 — this used to be a half-dead control: the model / min / max
/// pickers lived in the widget's own State and nothing ever read them
/// back, so every choice except the on/off switch was decoration. It is
/// now fully controlled — the parent owns the values and every change
/// is reported upward, which is what puts them into the
/// `diarizeSegments` call.
///
/// The model picker also stopped lying. It used to offer
/// Default/English/Chinese/… language variants that do not exist
/// anywhere in the catalogue; the real choice is which diarisation
/// *method* (and therefore which model file) runs, so that is what it
/// offers now, with unavailable model files marked.
class DiarizationSettingsWidget extends StatelessWidget {
  final bool enabled;
  final void Function(bool enabled) onChanged;

  /// The diarisation method — the real "model" choice. Mirrors
  /// `AdvancedOptions.diarizeMethod`; the parent writes it back there.
  final crispasr.DiarizeMethod method;
  final void Function(crispasr.DiarizeMethod method)? onMethodChanged;

  /// Speaker-count bounds. null = "Auto" (let the diarizer estimate).
  final int? minSpeakers;
  final int? maxSpeakers;
  final void Function(int? value)? onMinSpeakersChanged;
  final void Function(int? value)? onMaxSpeakersChanged;

  /// Methods whose model file isn't on disk. Those entries are marked
  /// "(Not downloaded)" — picking one is not an error (the service
  /// degrades to vad-turns and logs why), but the user gets told
  /// before the run instead of after.
  final Set<crispasr.DiarizeMethod> unavailableMethods;

  /// Whether the audio in hand is stereo. The energy / xcorr methods
  /// are channel-based and produce nothing useful on mono, so they are
  /// only offered when a stereo source is loaded.
  final bool stereoAvailable;

  const DiarizationSettingsWidget({
    super.key,
    required this.enabled,
    required this.onChanged,
    this.method = crispasr.DiarizeMethod.vadTurns,
    this.onMethodChanged,
    this.minSpeakers,
    this.maxSpeakers,
    this.onMinSpeakersChanged,
    this.onMaxSpeakersChanged,
    this.unavailableMethods = const <crispasr.DiarizeMethod>{},
    this.stereoAvailable = false,
  });

  /// Methods offered by the picker, in the order they appear.
  List<crispasr.DiarizeMethod> get _methods => [
        crispasr.DiarizeMethod.vadTurns,
        crispasr.DiarizeMethod.pyannote,
        crispasr.DiarizeMethod.foxNose,
        // Stereo-only methods stay in the list when they're the current
        // selection, so a value picked in Advanced options never falls
        // out from under the dropdown.
        if (stereoAvailable || method == crispasr.DiarizeMethod.energy)
          crispasr.DiarizeMethod.energy,
        if (stereoAvailable || method == crispasr.DiarizeMethod.xcorr)
          crispasr.DiarizeMethod.xcorr,
      ];

  String _methodLabel(BuildContext context, crispasr.DiarizeMethod m) {
    final l = AppLocalizations.of(context);
    // if-chain rather than a switch: a method the library adds later
    // then shows its raw name instead of failing to compile or, worse,
    // being silently mislabelled as one of these.
    String base = m.name;
    if (m == crispasr.DiarizeMethod.vadTurns) {
      base = l.advancedDiarizeVadTurns;
    } else if (m == crispasr.DiarizeMethod.pyannote) {
      base = l.advancedDiarizePyannote;
    } else if (m == crispasr.DiarizeMethod.foxNose) {
      base = l.advancedDiarizeFoxnose;
    } else if (m == crispasr.DiarizeMethod.energy) {
      base = l.advancedDiarizeEnergy;
    } else if (m == crispasr.DiarizeMethod.xcorr) {
      base = l.advancedDiarizeXcorr;
    }
    if (unavailableMethods.contains(m)) {
      return '$base  (${l.modelsNotDownloaded})';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with enable/disable toggle
            Row(
              children: [
                const Icon(Icons.people, size: 20),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).diarizationTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                // Hover (desktop) / long-press (touch) help — the
                // subtitle below says WHAT it is, the tooltip says
                // when it's worth the extra processing time.
                Tooltip(
                  message: AppLocalizations.of(context).diarizationEnableTooltip,
                  child: Switch(
                    value: enabled,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              AppLocalizations.of(context).diarizationSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),

            if (enabled) ...[
              const SizedBox(height: 16),
              _buildDiarizationSettings(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiarizationSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Diarization method / model selection
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context).diarizationModel),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<crispasr.DiarizeMethod>(
                    // Keyed on the value so an external change (the
                    // expert picker in Advanced decoding writes the
                    // same state) is reflected here — FormField only
                    // reads initialValue on first build.
                    key: ValueKey<String>('diarize-method-${method.name}'),
                    initialValue:
                        _methods.contains(method) ? method : _methods.first,
                    // Labels like "VAD turns (fast, less accurate)
                    // (Not downloaded)" outgrow a narrow card; without
                    // isExpanded the selected-item Row overflows.
                    isExpanded: true,
                    decoration: InputDecoration(
                      helperText:
                          AppLocalizations.of(context).diarizationModelHelper,
                      helperMaxLines: 3,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: _methods.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(_methodLabel(context, m),
                            overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: onMethodChanged == null
                        ? null
                        : (value) {
                            if (value != null) onMethodChanged!(value);
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () => _showModelHelp(context),
              tooltip: AppLocalizations.of(context).tooltipModelSelectionHelp,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Speaker count settings
        Row(
          children: [
            // Minimum speakers
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context).minSpeakers),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int?>(
                    key: ValueKey<String>('min-speakers-$minSpeakers'),
                    initialValue: minSpeakers,
                    decoration: InputDecoration(
                      helperText:
                          AppLocalizations.of(context).minSpeakersHelper,
                      helperMaxLines: 3,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    hint: Text(AppLocalizations.of(context).diarizationAuto),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                            AppLocalizations.of(context).diarizationAuto),
                      ),
                      ...List.generate(10, (i) => i + 1).map((count) {
                        return DropdownMenuItem<int?>(
                          value: count,
                          child: Text(count.toString()),
                        );
                      }),
                    ],
                    onChanged: onMinSpeakersChanged,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Maximum speakers
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context).maxSpeakers),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int?>(
                    key: ValueKey<String>('max-speakers-$maxSpeakers'),
                    initialValue: maxSpeakers,
                    decoration: InputDecoration(
                      helperText:
                          AppLocalizations.of(context).maxSpeakersHelper,
                      helperMaxLines: 3,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    hint: Text(AppLocalizations.of(context).diarizationAuto),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                            AppLocalizations.of(context).diarizationAuto),
                      ),
                      ...List.generate(10, (i) => i + 1).map((count) {
                        return DropdownMenuItem<int?>(
                          value: count,
                          child: Text(count.toString()),
                        );
                      }),
                    ],
                    onChanged: onMaxSpeakersChanged,
                  ),
                ],
              ),
            ),
          ],
        ),

        // Honest note about what the bounds actually reach. FoxNose is
        // the one method the library lets us bound directly; for the
        // others the upper bound still drives the embedding-based
        // re-clustering pass, and the lower bound is only a hint the
        // library may ignore.
        if (method != crispasr.DiarizeMethod.foxNose &&
            (minSpeakers != null || maxSpeakers != null)) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).diarizationSpeakerBoundsNote,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),

        // Tips and information
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context).diarizationTipsTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).diarizationTipsBody,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Performance note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange.shade700, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).diarizationPerformanceNote,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showModelHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(AppLocalizations.of(context).diarizationModelSelectionTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).diarizationModelHelpIntro,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(AppLocalizations.of(context).diarizationModelHelpVadTurns),
              Text(AppLocalizations.of(context).diarizationModelHelpPyannote),
              Text(AppLocalizations.of(context).diarizationModelHelpFoxnose),
              Text(AppLocalizations.of(context).diarizationModelHelpStereo),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).diarizationModelHelpFooter,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).ok),
          ),
        ],
      ),
    );
  }
}
