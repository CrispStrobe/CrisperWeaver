import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../services/model_service.dart';
import '../services/settings_service.dart';
import '../services/starter_models.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  /// #35 — record the TTS starter pick so the Synthesize screen opens on the
  /// model (and voice) onboarding just downloaded.
  ///
  /// `_finish` fetches the recommended model *plus every companion in its
  /// catalogue row* — for the synthesize task that is `kokoro-82m-q8_0` and
  /// `kokoro-voice-af_heart`. Nothing was persisted for TTS, so the screen
  /// fell back to "first downloaded TTS model in catalogue order" and "first
  /// downloaded voicepack for that backend", which is how the app came to
  /// download one voice and play another.
  ///
  /// [companionDefinitions] are the catalogue rows of the model's companions,
  /// in the order the row lists them (the caller resolves them; unknown ids
  /// are simply absent). The voice default is the first companion that is a
  /// [ModelKind.voice] — a codec companion is not a voice and must not be
  /// stored as one — and is cleared when the model has no voicepack, so a
  /// later re-run of onboarding can't leave a stale voice from a previous
  /// pick behind.
  ///
  /// Takes the service rather than a `ref` so the contract is unit-testable
  /// against a SharedPreferences-backed [SettingsService] without pumping
  /// the widget.
  static void persistTtsDefaults(
    SettingsService settings,
    String modelId,
    List<ModelDefinition> companionDefinitions,
  ) {
    settings.defaultTtsModel = modelId;
    var voice = '';
    for (final def in companionDefinitions) {
      if (def.kind == ModelKind.voice) {
        voice = def.name;
        break;
      }
    }
    settings.defaultTtsVoice = voice;
  }

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  StarterTask _task = StarterTask.transcribe;
  StarterPriority _priority = StarterPriority.balanced;
  String _language = 'auto';
  bool _working = false;
  double _progress = 0;
  String? _status;
  late Future<List<ModelInfo>> _models;

  @override
  void initState() {
    super.initState();
    _models = ref.read(modelServiceProvider).getWhisperCppModels();
  }

  StarterRecommendation get _recommendation => StarterModels.recommend(
        task: _task,
        priority: _priority,
        language: _language,
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l.onboardingTitle),
        actions: [
          TextButton(
            onPressed: _working ? null : _skip,
            child: Text(l.onboardingSkip),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Stepper(
              currentStep: _step,
              onStepTapped:
                  _working ? null : (value) => setState(() => _step = value),
              onStepContinue: _working
                  ? null
                  : _step < 2
                      ? () => setState(() => _step++)
                      : _finish,
              onStepCancel:
                  _working || _step == 0 ? null : () => setState(() => _step--),
              controlsBuilder: (context, details) => Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: details.onStepContinue,
                      child: Text(_step == 2
                          ? l.onboardingSetUp
                          : l.onboardingContinue),
                    ),
                    if (_step > 0) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: Text(MaterialLocalizations.of(context)
                            .backButtonTooltip),
                      ),
                    ],
                  ],
                ),
              ),
              steps: [
                Step(
                  title: Text(l.onboardingTaskTitle),
                  subtitle: Text(l.onboardingTaskSubtitle),
                  isActive: _step >= 0,
                  content: _taskPicker(l),
                ),
                Step(
                  title: Text(l.onboardingLanguageTitle),
                  subtitle: Text(l.onboardingLanguageSubtitle),
                  isActive: _step >= 1,
                  content: _preferencePicker(l),
                ),
                Step(
                  title: Text(l.onboardingRecommendationTitle),
                  subtitle: Text(l.onboardingRecommendationSubtitle),
                  isActive: _step >= 2,
                  content: _recommendationCard(l),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskPicker(AppLocalizations l) => RadioGroup<StarterTask>(
        groupValue: _task,
        onChanged: (value) {
          if (value != null) setState(() => _task = value);
        },
        child: Column(
          children: [
            _taskTile(StarterTask.transcribe, Icons.audio_file,
                l.onboardingTaskTranscribe, l.onboardingTaskTranscribeHelp),
            _taskTile(StarterTask.meeting, Icons.groups_outlined,
                l.onboardingTaskMeeting, l.onboardingTaskMeetingHelp),
            _taskTile(StarterTask.translate, Icons.translate,
                l.onboardingTaskTranslate, l.onboardingTaskTranslateHelp),
            _taskTile(StarterTask.synthesize, Icons.record_voice_over_outlined,
                l.onboardingTaskSynthesize, l.onboardingTaskSynthesizeHelp),
          ],
        ),
      );

  Widget _taskTile(
          StarterTask task, IconData icon, String title, String help) =>
      RadioListTile<StarterTask>(
        value: task,
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(help),
      );

  Widget _preferencePicker(AppLocalizations l) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: InputDecoration(
              labelText: l.onboardingLanguageLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 'auto', child: Text(l.languageAuto)),
              DropdownMenuItem(value: 'en', child: Text(l.languageEn)),
              DropdownMenuItem(value: 'de', child: Text(l.languageDe)),
              DropdownMenuItem(value: 'es', child: Text(l.languageEs)),
              DropdownMenuItem(value: 'fr', child: Text(l.languageFr)),
              DropdownMenuItem(value: 'it', child: Text(l.languageIt)),
              DropdownMenuItem(value: 'pt', child: Text(l.languagePt)),
              DropdownMenuItem(value: 'zh', child: Text(l.languageZh)),
              DropdownMenuItem(value: 'ja', child: Text(l.languageJa)),
              DropdownMenuItem(value: 'ko', child: Text(l.languageKo)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _language = value);
            },
          ),
          const SizedBox(height: 16),
          Text(l.onboardingPriorityLabel,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<StarterPriority>(
            segments: [
              ButtonSegment(
                  value: StarterPriority.balanced,
                  icon: const Icon(Icons.balance),
                  label: Text(l.onboardingPriorityBalanced)),
              ButtonSegment(
                  value: StarterPriority.speed,
                  icon: const Icon(Icons.speed),
                  label: Text(l.onboardingPrioritySpeed)),
              ButtonSegment(
                  value: StarterPriority.quality,
                  icon: const Icon(Icons.high_quality_outlined),
                  label: Text(l.onboardingPriorityQuality)),
              ButtonSegment(
                  value: StarterPriority.storage,
                  icon: const Icon(Icons.sd_storage_outlined),
                  label: Text(l.onboardingPriorityStorage)),
            ],
            selected: {_priority},
            onSelectionChanged: (values) =>
                setState(() => _priority = values.first),
          ),
        ],
      );

  Widget _recommendationCard(AppLocalizations l) =>
      FutureBuilder<List<ModelInfo>>(
        future: _models,
        builder: (context, snapshot) {
          final id = _recommendation.modelId;
          ModelInfo? model;
          if (id != null) {
            for (final candidate in snapshot.data ?? const <ModelInfo>[]) {
              if (candidate.name == id) {
                model = candidate;
                break;
              }
            }
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (model == null) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: Text(l.onboardingChooseModelTitle),
                subtitle: Text(l.onboardingChooseModelBody),
              ),
            );
          }
          return Semantics(
            container: true,
            label:
                l.onboardingRecommendedSemantics(model.displayName, model.size),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.recommend_outlined, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(model.displayName,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text('${model.size} • ${model.description}'),
                            ],
                          ),
                        ),
                        if (model.isDownloaded)
                          Chip(
                            avatar: const Icon(Icons.check, size: 16),
                            label: Text(l.quickStartInstalled),
                          ),
                      ],
                    ),
                    if (_working) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 6),
                      Text(_status ?? l.onboardingPreparing),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );

  Future<void> _finish() async {
    setState(() {
      _working = true;
      _progress = 0;
      _status = AppLocalizations.of(context).onboardingPreparing;
    });
    try {
      final models = await _models;
      final recommendation = _recommendation;
      final id = recommendation.modelId;
      ModelInfo? selected;
      if (id != null) {
        for (final model in models) {
          if (model.name == id) selected = model;
        }
      }
      if (selected != null && !selected.isDownloaded) {
        final service = ref.read(modelServiceProvider);
        final names = <String>[selected.name];
        final definition = service.lookupDefinition(selected.name);
        if (definition != null) names.addAll(definition.companions);
        for (var i = 0; i < names.length; i++) {
          if (!mounted) return;
          final name = names[i];
          await service.downloadWhisperCppModel(
            name,
            onStatusChange: (status) {
              if (mounted) setState(() => _status = status);
            },
            onProgress: (value) {
              if (mounted) {
                setState(() => _progress = (i + value) / names.length);
              }
            },
          );
        }
      }
      if (!mounted) return;
      _persist(recommendation);
      // #35 — `go()` replaces the whole stack, so landing straight on
      // /synthesize or /translate left the user on a screen with no back
      // button and no way home short of restarting the app. Put home at
      // the bottom of the stack first, then push the destination on top
      // of it so the AppBar draws its normal back arrow.
      final route = recommendation.route;
      final router = GoRouter.of(context);
      router.go('/');
      if (route != '/') {
        // `push` reads `routerDelegate.currentConfiguration` synchronously
        // as its base, while `go` only notifies the route-information
        // provider — pushing in the same turn can therefore stack the
        // destination on top of /onboarding instead of /. Waiting for the
        // frame that `go` triggers makes the ordering deterministic. The
        // router outlives this widget, so no `mounted`/context use here.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          router.push<Object?>(route);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).onboardingFailed(e.toString()))),
      );
    }
  }

  void _persist(StarterRecommendation recommendation) {
    final settings = ref.read(settingsServiceProvider);
    settings.onboardingCompleted = true;
    settings.onboardingTask = _task.name;
    settings.onboardingPriority = _priority.name;
    settings.defaultLanguage = _language;
    if (recommendation.kind == ModelKind.asr &&
        recommendation.modelId != null) {
      final def = ref
          .read(modelServiceProvider)
          .lookupDefinition(recommendation.modelId!);
      settings.defaultModel = recommendation.modelId!;
      settings.defaultBackend = def?.backend ?? 'whisper';
      settings.enableDiarizationByDefault = recommendation.enableDiarization;
    }
    if (recommendation.kind == ModelKind.tts &&
        recommendation.modelId != null) {
      // #35 — `_finish` downloaded this model *and* the companions listed on
      // its catalogue row; record both so the Synthesize screen selects what
      // was fetched instead of the first row that happens to be on disk.
      final service = ref.read(modelServiceProvider);
      final def = service.lookupDefinition(recommendation.modelId!);
      final companionDefs = <ModelDefinition>[];
      for (final name in def?.companions ?? const <String>[]) {
        final companion = service.lookupDefinition(name);
        if (companion != null) companionDefs.add(companion);
      }
      OnboardingScreen.persistTtsDefaults(
          settings, recommendation.modelId!, companionDefs);
    }
  }

  void _skip() {
    final settings = ref.read(settingsServiceProvider);
    settings.onboardingCompleted = true;
    context.go('/');
  }
}
