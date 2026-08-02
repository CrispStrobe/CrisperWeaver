// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'CrisperWeaver';

  @override
  String get appTagline => 'Audio transcription with speaker diarization';

  @override
  String get menuHistory => 'History';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuModels => 'Models';

  @override
  String get menuSynthesize => 'Synthesize speech';

  @override
  String get menuTranslate => 'Translate text';

  @override
  String get menuLogs => 'Logs';

  @override
  String get menuAbout => 'About';

  @override
  String get menuOpenMore => 'More';

  @override
  String get tabInput => 'Input';

  @override
  String get tabRun => 'Run';

  @override
  String get tabOutput => 'Output';

  @override
  String get navHome => 'Transcribe';

  @override
  String get engineReady => 'Engine ready';

  @override
  String get engineStarting => 'Engine starting…';

  @override
  String get audioInput => 'Audio input';

  @override
  String get noFileSelected => 'No file selected';

  @override
  String get browse => 'Browse';

  @override
  String get urlInputLabel => 'Or enter audio URL';

  @override
  String get urlInputHint => 'https://example.com/audio.mp3';

  @override
  String get advancedOptions => 'Advanced options';

  @override
  String get language => 'Language';

  @override
  String get languageAuto => 'Auto-detect';

  @override
  String get model => 'Model';

  @override
  String get transcribe => 'Transcribe';

  @override
  String get transcribing => 'Transcribing…';

  @override
  String get stop => 'Stop';

  @override
  String get clear => 'Clear';

  @override
  String get transcriptionOutput => 'Transcription output';

  @override
  String get noTranscriptionYet => 'No transcription yet';

  @override
  String get noTranscriptionHint =>
      'Select an audio file and start transcription';

  @override
  String get searchTranscription => 'Search transcription…';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get noResultsHint => 'Try a different search term';

  @override
  String get tabSegments => 'Segments';

  @override
  String get tabFullText => 'Full Text';

  @override
  String get sharePlain => 'Share plain text';

  @override
  String get copyClipboard => 'Copy to clipboard';

  @override
  String get saveAsTxt => 'Save as .txt';

  @override
  String get saveAsSrt => 'Save as .srt';

  @override
  String get saveAsVtt => 'Save as .vtt';

  @override
  String get saveAsJson => 'Save as .json';

  @override
  String get copied => 'Copied';

  @override
  String get perfRtf => 'RTF';

  @override
  String get perfAudio => 'Audio';

  @override
  String get perfWall => 'Wall';

  @override
  String get perfWords => 'Words';

  @override
  String get perfWps => 'WPS';

  @override
  String get perfEngine => 'Engine';

  @override
  String get perfModel => 'Model';

  @override
  String get perfFasterThanRealtime => 'faster than real-time';

  @override
  String get perfSlowerThanRealtime => 'slower than real-time';

  @override
  String get diarizationTitle => 'Speaker diarization';

  @override
  String get diarizationSubtitle =>
      'Identify different speakers in audio recordings';

  @override
  String get diarizationModel => 'Diarization model';

  @override
  String get minSpeakers => 'Min. speakers';

  @override
  String get maxSpeakers => 'Max. speakers';

  @override
  String get auto => 'Auto';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppLanguage => 'App language';

  @override
  String get settingsInterfaceLanguage => 'Interface language';

  @override
  String get settingsSystemDefault => 'System default';

  @override
  String get settingsEngineSection => 'Transcription engine';

  @override
  String get settingsEnginePreferred => 'Preferred engine';

  @override
  String get settingsSelectEngine => 'Select engine';

  @override
  String settingsEngineSwitched(String engine) {
    return 'Switched to $engine';
  }

  @override
  String get settingsEngineSwitchFailed => 'Engine switch failed';

  @override
  String settingsAudioQualityCurrent(int percent) {
    return 'Recording quality: $percent%';
  }

  @override
  String get settingsCacheCleared => 'Cache cleared successfully';

  @override
  String get settingsHfToken => 'HuggingFace API token';

  @override
  String get settingsHfTokenNotSet => 'Not set (required for gated models)';

  @override
  String get settingsModelsDir => 'Models directory';

  @override
  String get settingsModelsDirDefault => 'Default (in app sandbox)';

  @override
  String get settingsModelsDirPickTitle => 'Pick models directory';

  @override
  String get settingsModelsDirCurrentDefault =>
      'Currently using the default app-sandbox path. Pick a custom directory to share GGUFs with other tools (e.g. an external drive).';

  @override
  String settingsModelsDirCurrent(String path) {
    return 'Current: $path';
  }

  @override
  String get settingsModelsDirPick => 'Pick…';

  @override
  String get settingsModelsDirReset => 'Use default';

  @override
  String settingsModelsDirSet(String path) {
    return 'Models directory set to $path';
  }

  @override
  String get languageEn => 'English';

  @override
  String get languageDe => 'German';

  @override
  String get languageEs => 'Spanish';

  @override
  String get languageFr => 'French';

  @override
  String get languageIt => 'Italian';

  @override
  String get languagePt => 'Portuguese';

  @override
  String get languageZh => 'Chinese';

  @override
  String get languageJa => 'Japanese';

  @override
  String get languageKo => 'Korean';

  @override
  String get languageRu => 'Russian';

  @override
  String modelSize(String size) {
    return 'Size: $size';
  }

  @override
  String modelDeleteConfirm(String name) {
    return 'Are you sure you want to delete $name?';
  }

  @override
  String get historyCopy => 'Copy';

  @override
  String get historyExportSrt => 'Export SRT';

  @override
  String get historyExportTxt => 'Export TXT';

  @override
  String get historyExportJson => 'Export JSON';

  @override
  String get historyDelete => 'Delete';

  @override
  String historyFailedToLoad(String error) {
    return 'Failed to load history: $error';
  }

  @override
  String historySaved(String path) {
    return 'Saved $path';
  }

  @override
  String historyExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get recorderDeleteTitle => 'Delete recording';

  @override
  String get recorderDeleteBody =>
      'Are you sure you want to delete this recording?';

  @override
  String get recorderQueuedForTranscription =>
      'Recording queued for transcription.';

  @override
  String get recorderStream => 'Stream';

  @override
  String get recorderStreamTooltip =>
      'Live mic transcribe (Whisper sliding window). Partial text appears as you speak.';

  @override
  String get recorderSystemAudioTooltip =>
      'Capture system audio (Zoom call, browser tab, podcast app) and transcribe live. macOS 13+ only; first use prompts for Screen Recording permission.';

  @override
  String get recorderSystemAudioPermission =>
      'Screen Recording permission denied. Open System Settings → Privacy & Security → Screen Recording and tick CrisperWeaver, then try again.';

  @override
  String get recorderSystemAudioUnsupported =>
      'System audio capture is not yet supported on this platform. Tracked in PLAN.md §5.1.1.';

  @override
  String get outputShowTimestamps => 'Show timestamps';

  @override
  String get outputShowSpeakers => 'Show speakers';

  @override
  String get outputShowConfidence => 'Show confidence';

  @override
  String get outputCopyAll => 'Copy all';

  @override
  String get outputPlay => 'Play';

  @override
  String get outputCopy => 'Copy';

  @override
  String get outputEdit => 'Edit';

  @override
  String get outputPlaySegment => 'Play segment';

  @override
  String get outputCopyText => 'Copy text';

  @override
  String get outputEditSegment => 'Edit segment';

  @override
  String get outputEditNotImplemented => 'Segment editing not yet implemented';

  @override
  String get outputEditAltSuggestions => 'Alternative candidates';

  @override
  String get outputEditAltSuggestionsHint =>
      'Tap a word to swap it for a runner-up Whisper picked at that step. Uses the alternative-candidate slider in Advanced Options.';

  @override
  String get outputEditAltPickTooltip =>
      'Pick an alternative candidate for this word';

  @override
  String get outputRenameSpeakerTitle => 'Rename speaker';

  @override
  String outputRenameSpeakerOriginal(String original) {
    return 'Original label: $original';
  }

  @override
  String get outputRenameSpeakerReset => 'Reset to original';

  @override
  String get outputSegmentCopied => 'Segment copied to clipboard';

  @override
  String get outputAllCopied => 'All transcription copied to clipboard';

  @override
  String outputPlayingSegment(String time) {
    return 'Playing segment: $time';
  }

  @override
  String get settingsLoading => 'Loading…';

  @override
  String get transcribeLanguageLabel => 'Language';

  @override
  String transcribeLoadingButton(String model) {
    return 'Loading $model…';
  }

  @override
  String get transcribeLoadingFallback => 'Loading model…';

  @override
  String transcribeLoadingDetail(String model) {
    return 'Loading model: $model — first transcribe on this model takes ~5–15 s while the worker pool spawns and the weights map into memory.';
  }

  @override
  String transcribeStarting(String model) {
    return 'Starting download: $model';
  }

  @override
  String transcribeUnsupportedFile(String name) {
    return 'Unsupported file type: $name';
  }

  @override
  String transcribeLoadedFile(String name) {
    return 'Loaded $name';
  }

  @override
  String aboutEmail(String email) {
    return 'Email: $email';
  }

  @override
  String aboutPhone(String phone) {
    return 'Phone: $phone';
  }

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsTranscription => 'Transcription';

  @override
  String get settingsDefaultModel => 'Default model';

  @override
  String get settingsDefaultLanguage => 'Default language';

  @override
  String get settingsAutoDetectLanguage => 'Auto-detect language';

  @override
  String get settingsAutoDetectLanguageSubtitle =>
      'Automatically detect audio language';

  @override
  String get settingsWordTimestamps => 'Word timestamps';

  @override
  String get settingsWordTimestampsSubtitle =>
      'Generate timestamps for individual words';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioQuality => 'Audio quality';

  @override
  String get settingsKeepAudioFiles => 'Keep audio files';

  @override
  String get settingsKeepAudioFilesSubtitle =>
      'Keep downloaded / recorded audio files after transcription';

  @override
  String get settingsDiarization => 'Speaker diarization';

  @override
  String get settingsEnableDiarizationByDefault => 'Enable by default';

  @override
  String get settingsEnableDiarizationByDefaultSubtitle =>
      'Automatically enable diarization for new transcriptions';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsClearCache => 'Clear cache';

  @override
  String get settingsClearCacheSubtitle => 'Clear temporary files and cache';

  @override
  String get settingsManageModels => 'Manage models';

  @override
  String get settingsManageModelsSubtitle =>
      'Download, update, or delete transcription models';

  @override
  String get settingsStorageBreakdown => 'Storage breakdown';

  @override
  String get settingsStorageBreakdownSubtitle =>
      'See per-backend disk usage and free up space';

  @override
  String get storageTitle => 'Storage breakdown';

  @override
  String get storageRefresh => 'Refresh';

  @override
  String get storageEmpty => 'No model files on disk yet.';

  @override
  String get storageTotalUsed => 'Total on disk';

  @override
  String storageBackendCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count backends',
      one: '1 backend',
    );
    return '$_temp0';
  }

  @override
  String storageFilesCount(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$size • $_temp0';
  }

  @override
  String get storageDeleteAllTooltip => 'Delete all models for this backend';

  @override
  String storageDeleteTitle(String backend) {
    return 'Delete all $backend models?';
  }

  @override
  String storageDeleteMessage(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return 'This will free $size across $_temp0 and cannot be undone.';
  }

  @override
  String get storageDeleteConfirm => 'Delete';

  @override
  String storageDeletedSnack(String size) {
    return 'Freed $size';
  }

  @override
  String get settingsDebugging => 'Debugging & development';

  @override
  String get settingsLogLevel => 'Log level';

  @override
  String settingsLogLevelCurrent(String level) {
    return 'Currently $level';
  }

  @override
  String get settingsMirrorLogs => 'Mirror logs to file';

  @override
  String get settingsMirrorLogsSubtitle =>
      'Writes to logs/session.log in the app documents directory';

  @override
  String get settingsSkipChecksum => 'Skip checksum verification';

  @override
  String get settingsSkipChecksumSubtitle =>
      'Accept downloaded models even if SHA-1 does not match';

  @override
  String get settingsGroupBatchByBackend => 'Group batch by backend';

  @override
  String get settingsGroupBatchByBackendSubtitle =>
      'Reorder queued files so consecutive jobs reuse the same model session';

  @override
  String get settingsMaxConcurrent => 'Concurrent transcriptions';

  @override
  String settingsMaxConcurrentCurrent(int n) {
    return 'Concurrent transcriptions: $n';
  }

  @override
  String get settingsMaxConcurrentSessions => 'Parallel sessions';

  @override
  String settingsMaxConcurrentSessionsCurrent(int n) {
    return 'Parallel sessions: $n';
  }

  @override
  String get settingsMaxConcurrentSessionsSubtitle =>
      '1 = single session (default). 2+ spins up N worker isolates each holding its own model copy in RAM. Cost is N × model size; pre-flight clamps down if it wouldn\'t fit on this device.';

  @override
  String settingsMemoryProjection(String projected, String total, String per) {
    return 'Projected RAM: $projected of $total (per-worker: $per)';
  }

  @override
  String settingsMemoryProjectionClamped(int affordable, int requested) {
    return 'Clamped to $affordable of $requested workers — model is too big for available RAM';
  }

  @override
  String batchResumedSnackbar(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Recovered $n interrupted transcriptions',
      one: 'Recovered 1 interrupted transcription',
    );
    return '$_temp0 — hit Start to resume';
  }

  @override
  String get settingsMaxConcurrentSubtitle =>
      '1 = serial (current behaviour). 2+ pre-decodes the next file\'s audio in a worker isolate while the current file is being transcribed — extra parallelism without extra model copies in RAM.';

  @override
  String get settingsOpenLogViewer => 'Open log viewer';

  @override
  String get settingsSpeakers => 'Speakers';

  @override
  String get settingsSpeakersSubtitle =>
      'Enrol voices for automatic speaker labels in diarisation.';

  @override
  String get speakersTitle => 'Speakers';

  @override
  String get speakersEmpty => 'No speakers enrolled yet. Tap + to add one.';

  @override
  String get speakersPrivacyNote =>
      'Voice profiles are stored on-device only. Nothing is uploaded.';

  @override
  String get speakersDownloadModelHint =>
      'Download the TitaNet model from Model Management before enrolling.';

  @override
  String get speakersAdd => 'Add speaker';

  @override
  String get speakersDeleteTitle => 'Delete enrolled speaker?';

  @override
  String speakersDeleteBody(String name) {
    return '$name\'s voice profile will be removed from this device.';
  }

  @override
  String get speakersDeleteFailed => 'Failed to delete profile.';

  @override
  String get speakersEnrolTitle => 'Enrol speaker';

  @override
  String get speakersSourceRecord => 'Record';

  @override
  String get speakersSourceFile => 'Choose file';

  @override
  String get speakersName => 'Speaker name';

  @override
  String get speakersNameRequired => 'Name is required';

  @override
  String get speakersNameTaken =>
      'A speaker with this name is already enrolled.';

  @override
  String get speakersNoSample => 'Record or pick an audio sample first.';

  @override
  String get speakersEnrolButton => 'Enrol';

  @override
  String get speakersEnrolFailed => 'Could not enrol — try a clearer sample.';

  @override
  String get speakersRecord => 'Start recording';

  @override
  String get speakersRecordStop => 'Stop';

  @override
  String speakersRecordHint(int seconds) {
    return 'Tap to record a $seconds s sample of this person speaking.';
  }

  @override
  String speakersRecordingCountdown(int seconds) {
    return 'Recording… $seconds s left';
  }

  @override
  String speakersRecordingDone(int seconds) {
    return 'Captured $seconds s of audio.';
  }

  @override
  String get speakersRecordNoPermission => 'Microphone permission was denied.';

  @override
  String get speakersPickHint =>
      'Pick any audio file with a clear sample of this person speaking.';

  @override
  String get speakersPickButton => 'Choose audio file';

  @override
  String get settingsSystemInfo => 'System information';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsAboutCrisperWeaver => 'About CrisperWeaver';

  @override
  String get settingsAboutCrisperWeaverSubtitle =>
      'Author, contact, disclaimer, licenses';

  @override
  String get settingsHfTokenTitle => 'Hugging Face API Token';

  @override
  String get settingsHfTokenSubtitle =>
      'Required for gated or private repositories.';

  @override
  String get settingsHfTokenSave => 'SAVE';

  @override
  String get settingsHfTokenCancel => 'CANCEL';

  @override
  String get transcriptionNoModelsFound => 'No models found';

  @override
  String get transcriptionRetry => 'Retry';

  @override
  String transcriptionLoadFailed(String error) {
    return 'Load failed: $error';
  }

  @override
  String transcriptionSavedTo(String path) {
    return 'Saved $path';
  }

  @override
  String transcriptionSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get transcriptionCopiedToClipboard => 'Copied to clipboard';

  @override
  String get transcriptionShareSheetTitle => 'Share or save';

  @override
  String get transcriptionSharePlainText => 'Share plain text';

  @override
  String get transcriptionCopyToClipboard => 'Copy to clipboard';

  @override
  String get transcriptionSaveAsTxt => 'Save as TXT';

  @override
  String get transcriptionSaveAsSrt => 'Save as SRT';

  @override
  String get transcriptionSaveAsVtt => 'Save as VTT';

  @override
  String get transcriptionSaveAsJson => 'Save as JSON';

  @override
  String get transcriptionDownloadModel => 'Download Model';

  @override
  String get transcriptionDownload => 'DOWNLOAD';

  @override
  String get advancedBestOfSingle => 'Best-of-N: single decode (1)';

  @override
  String advancedBestOfCurrent(int n) {
    return 'Best-of-N: $n decodes';
  }

  @override
  String get advancedBestOfHelper =>
      '1 = single decode (default). >1 runs N independent decodes and picks the highest-scoring result. Whisper consumes this internally; other backends loop externally and pick the highest-mean-confidence transcript. Cost is N× per-call decode time.';

  @override
  String get advancedTemperatureGreedy => 'Decoder temperature: greedy (0.00)';

  @override
  String advancedTemperatureCurrent(String value) {
    return 'Decoder temperature: $value';
  }

  @override
  String get advancedTemperatureHelper =>
      '0.00 = greedy / reproducible. > 0 = stochastic sampling — useful when greedy decoding hallucinates a repetition. Whisper has its own internal fallback ladder; this affects sampling backends (canary, cohere, parakeet, moonshine).';

  @override
  String downloadModelPrompt(String name, String size) {
    return 'The model \"$name\" is not yet downloaded. Would you like to download it now (~$size)?';
  }

  @override
  String get tooltipDeleteRecording => 'Delete recording';

  @override
  String get tooltipUseForTranscription => 'Use for transcription';

  @override
  String get tooltipModelSelectionHelp => 'Model selection help';

  @override
  String get tooltipDownloadModel => 'Download model';

  @override
  String get tooltipDisplayLevel => 'Display level';

  @override
  String get tooltipPauseAutoScroll => 'Pause auto-scroll';

  @override
  String get tooltipResumeAutoScroll => 'Resume auto-scroll';

  @override
  String get labelApiToken => 'API Token';

  @override
  String get streamingRequiresWhisper =>
      'Streaming requires the Whisper engine. Switch backend in Settings.';

  @override
  String get streamingMicUnavailable => 'Microphone unavailable for streaming.';

  @override
  String get streamingEngineNoSession =>
      'Engine returned no streaming session.';

  @override
  String playbackFailed(String error) {
    return 'Playback failed: $error';
  }

  @override
  String synthesizeFailed(String error) {
    return 'Synthesize failed: $error';
  }

  @override
  String logsShowLevel(String level) {
    return 'Show $level and above';
  }

  @override
  String get diarizationAuto => 'Auto';

  @override
  String get diarizationModelSelectionTitle => 'Diarization Model Selection';

  @override
  String get aboutServiceProvider => 'Service Provider';

  @override
  String get aboutContact => 'Contact';

  @override
  String get aboutPrivacy => 'Privacy';

  @override
  String get aboutDisclaimer => 'Disclaimer';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutOpenSourceLicenses => 'Open-source licenses';

  @override
  String get aboutPrivacyText =>
      'CrisperWeaver processes all audio locally on your device. No audio data, transcripts, or recordings are sent to any server. Model downloads fetch GGUF weights directly from HuggingFace over HTTPS; nothing else leaves the device.';

  @override
  String get aboutDisclaimerText =>
      'This software is provided \"as is\", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose and noninfringement. In no event shall the authors be liable for any claim, damages or other liability arising from, out of or in connection with the software or its use.';

  @override
  String get aboutLicenseText =>
      'CrisperWeaver is free software, licensed under the GNU Affero General Public License v3.0 (AGPL-3.0). You may redistribute and modify it under the terms of that license. In particular, if you run a modified version of CrisperWeaver as a network service, you must make your source code available to its users.';

  @override
  String get historyTitle => 'Transcription history';

  @override
  String get historyEmpty => 'No transcriptions yet';

  @override
  String get historyEmptyHint =>
      'Run a transcription and it will show up here.';

  @override
  String get historyRefresh => 'Refresh';

  @override
  String get historyClearAll => 'Clear all';

  @override
  String get historySearchHint => 'Search title or transcript…';

  @override
  String historySearchNoResults(String query) {
    return 'No history entries match \"$query\"';
  }

  @override
  String historySearchMatchCount(int matched, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      matched,
      locale: localeName,
      other: '$matched of $total matched',
      one: '1 of $total matched',
    );
    return '$_temp0';
  }

  @override
  String get historyClearAllPrompt =>
      'Remove every saved transcription from this device. This cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsFilterHint => 'Filter by message, tag, or error…';

  @override
  String get logsCopyVisible => 'Copy visible';

  @override
  String get logsCopyAll => 'Copy all';

  @override
  String get logsExport => 'Export to file';

  @override
  String get logsShare => 'Share as file';

  @override
  String get modelsTitle => 'Model management';

  @override
  String get modelsNoneAvailable => 'No models available';

  @override
  String get modelsRetry => 'Retry';

  @override
  String get modelsDownload => 'Download';

  @override
  String get modelsDelete => 'Delete model';

  @override
  String get modelsDownloaded => 'Downloaded';

  @override
  String get modelsNotDownloaded => 'Not downloaded';

  @override
  String modelsDownloadingPercent(String percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get error => 'Error';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Save';

  @override
  String get done => 'Done';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get settingsDefaultBackend => 'Default backend';

  @override
  String get settingsSelectBackend => 'Select default backend';

  @override
  String settingsSelectModel(String backend) {
    return 'Select default model ($backend)';
  }

  @override
  String get settingsSelectLanguage => 'Select default language';

  @override
  String get settingsSelectInterfaceLanguage => 'Select interface language';

  @override
  String settingsNoModelsForBackend(String backend) {
    return 'No models known for backend \"$backend\". Use the model manager → cloud-download icon to probe HuggingFace.';
  }

  @override
  String get modelFilterHint => 'Filter models (name / quant)';

  @override
  String get modelAnyBackend => 'Any backend';

  @override
  String get modelNoMatch => 'No models match this filter.';

  @override
  String get modelsRefreshFromHf => 'Refresh quants from HuggingFace';

  @override
  String get modelsReloadLocal => 'Reload local state';

  @override
  String get modelsQuickStartTooltip => 'Quick start';

  @override
  String get quickStartTitle => 'Quick start';

  @override
  String get quickStartSubtitle =>
      'Grab a small starter set — transcribe, synthesise speech, and tidy up text — in one tap.';

  @override
  String get quickStartDownloadAll => 'Download all missing';

  @override
  String get quickStartInstalled => 'Installed';

  @override
  String get quickStartAllInstalled => 'All starter models are installed.';

  @override
  String get modelsProbedCountZero =>
      'No new quants discovered on HuggingFace.';

  @override
  String modelsProbedCount(int count, String plural) {
    return 'Discovered $count new quant variant$plural.';
  }

  @override
  String get batchQueueTitle => 'Batch queue';

  @override
  String batchQueueSummary(int queued, int running, int done, int errored) {
    return '$queued queued · $running running · $done done · $errored failed';
  }

  @override
  String get batchClearCompleted => 'Clear done';

  @override
  String get batchRemove => 'Remove from queue';

  @override
  String batchEnqueueAdded(int count) {
    return '$count file(s) added to queue.';
  }

  @override
  String get batchRunAll => 'Transcribe all';

  @override
  String get batchStop => 'Stop batch';

  @override
  String get batchQueueDropHint => 'Drop audio files here to queue them';

  @override
  String get advancedSection => 'Advanced decoding';

  @override
  String get advancedVadTrim => 'Trim silence (VAD)';

  @override
  String get advancedVadTrimSubtitle =>
      'Skip leading and trailing silence via Silero VAD. Faster on meetings / long recordings with silent padding.';

  @override
  String get advancedTranslate => 'Translate to English';

  @override
  String get advancedTranslateSubtitle =>
      'Whisper only — forces output to English regardless of source.';

  @override
  String get advancedBeamSearch => 'Beam search';

  @override
  String get advancedBeamSearchSubtitle =>
      'Slower, usually more accurate. Default is greedy.';

  @override
  String advancedBeamSize(int n) {
    return 'Beam width: $n';
  }

  @override
  String get advancedBeamSizeHelper =>
      'Number of beams for beam search. 0 = backend default (typically 5).';

  @override
  String advancedHotwordsBoost(String value) {
    return 'Hotwords boost: $value';
  }

  @override
  String get advancedHotwordsBoostHelper =>
      'Boost factor for CTC/TDT hotword biasing (granite, parakeet). 0 = off.';

  @override
  String advancedChunkSeconds(int n) {
    return 'Chunk window: ${n}s';
  }

  @override
  String get advancedChunkSecondsHelper =>
      'Transcription chunk size in seconds. 0 = per-model default (~30s). Smaller values reduce peak memory on long files.';

  @override
  String get advancedInitialPrompt => 'Initial prompt (vocabulary / context)';

  @override
  String get advancedInitialPromptHint =>
      'e.g. \"CrispASR, Flutter, Riverpod, Sprecher-Unterscheidung\"';

  @override
  String get advancedRestorePunctuation => 'Restore punctuation (FireRedPunc)';

  @override
  String get advancedRestorePunctuationSubtitle =>
      'Capitalize and punctuate raw output. Useful for CTC backends (wav2vec2, fastconformer-ctc, firered-asr). Requires fireredpunc-*.gguf in Model Management.';

  @override
  String get advancedSourceLanguage => 'Source language (override autodetect)';

  @override
  String get advancedSourceLanguageAuto => 'Auto / use main picker';

  @override
  String get advancedSourceLanguageHelper =>
      'Pin the source language when whisper\'s autodetect is unreliable on noisy audio. Empty = fall back to the main language dropdown / autodetect.';

  @override
  String get advancedTargetLanguage => 'Translate to (target language)';

  @override
  String get advancedTargetLanguageNone => 'No translation (verbatim)';

  @override
  String get advancedTargetLanguageHelper =>
      'Visible only for translation-capable backends (Canary, Voxtral, Qwen3, Cohere, Whisper). Leave at \"No translation\" for verbatim transcription.';

  @override
  String get advancedAskPrompt => 'Ask the audio (Q&A mode)';

  @override
  String get advancedAskPromptHint =>
      'e.g. \"Summarize\" or \"What\'s the speaker\'s tone?\"';

  @override
  String get advancedAskPromptHelper =>
      'Voxtral / Qwen3-ASR only. When set, the LLM ANSWERS your question instead of producing a verbatim transcript. Leave empty for normal transcription.';

  @override
  String get editAudioOpen => 'Open in audio editor';

  @override
  String get editAudioTitle => 'Edit audio';

  @override
  String editAudioLoadFailed(String error) {
    return 'Couldn\'t decode audio: $error';
  }

  @override
  String get editAudioSaveAs => 'Save edited audio as…';

  @override
  String editAudioSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get editAudioTrim => 'Trim';

  @override
  String get editAudioCut => 'Cut middle';

  @override
  String get editAudioAddSplitMark => 'Add split mark';

  @override
  String editAudioRunSplit(int n) {
    return 'Split into $n files';
  }

  @override
  String get editAudioClearMarks => 'Clear marks';

  @override
  String get editAudioClearSelection => 'Clear selection';

  @override
  String get editAudioNeedSelection =>
      'Drag on the waveform to select a region first.';

  @override
  String get editAudioNeedSplitMarks => 'Add at least one split mark first.';

  @override
  String editAudioSelectionLabel(String start, String end) {
    return 'Selection: $start – $end';
  }

  @override
  String editAudioSplitSaved(int n) {
    return 'Saved $n files.';
  }

  @override
  String get editAudioHowto =>
      'Tap waveform to seek. Drag to select a region. Use Trim to keep [start, end]; Cut middle to remove [start, end] and splice the rest; Add split mark to drop a split point at the current playhead, then Split to write one WAV per region.';

  @override
  String get editAudioToggleTranscriptShow => 'Show transcript';

  @override
  String get editAudioToggleTranscriptHide => 'Hide transcript';

  @override
  String get editAudioTranscriptHeading => 'Transcript';

  @override
  String get editAudioTranscriptEmpty =>
      'No transcript yet. Transcribe the audio first, then return here to use it for navigation and cut-region markers.';

  @override
  String get editAudioTranscriptSegmentTapHint =>
      'Tap a line to seek the playhead. Long-press a line for cut / trim options.';

  @override
  String get editAudioMarkSegmentForCut => 'Mark segment for split';

  @override
  String get editAudioTrimToSegment => 'Trim to this segment';

  @override
  String get editAudioSelectSegment => 'Select this segment';

  @override
  String editAudioSegmentMarkedForCut(String time) {
    return 'Marked split point at $time.';
  }

  @override
  String get close => 'Close';

  @override
  String get presetsTooltip => 'Presets';

  @override
  String get presetsTitle => 'Presets';

  @override
  String get presetsHelp =>
      'Save the current backend, model, language and Advanced Options as a named preset. Apply later to restore all settings in one tap.';

  @override
  String get presetsSaveCurrent => 'Save current settings as preset';

  @override
  String get presetsSaveCurrentTitle => 'Save preset';

  @override
  String get presetsNameLabel => 'Preset name';

  @override
  String get presetsNameHint =>
      'e.g. Podcast prep, Voice memos, Multilingual interview';

  @override
  String get presetsEmpty =>
      'No presets yet. Save the current settings to start.';

  @override
  String get presetsApply => 'Apply';

  @override
  String presetsApplied(String name) {
    return 'Applied preset \"$name\".';
  }

  @override
  String get presetsRenameTitle => 'Rename preset';

  @override
  String get presetsRenameTooltip => 'Rename';

  @override
  String get presetsDeleteTitle => 'Delete preset?';

  @override
  String presetsDeleteConfirm(String name) {
    return 'Delete preset \"$name\"? This can\'t be undone.';
  }

  @override
  String get presetsDeleteTooltip => 'Delete';

  @override
  String get outputSummarize => 'Summarize…';

  @override
  String get outputOcrImage => 'OCR image…';

  @override
  String get outputRealignTimestamps => 'Re-align timestamps';

  @override
  String get outputDetectLanguage => 'Detect language';

  @override
  String get outputSummarizeTitle => 'Summarize transcript';

  @override
  String outputSummarizeHelp(String model) {
    return 'Sends the transcript to $model and asks for a structured summary. Output is Markdown-formatted bullet lists.';
  }

  @override
  String get outputSummarizeUnconfigured =>
      'No cloud LLM endpoint configured. Open Settings → Cloud LLM cleanup to add one — the same endpoint is used for both cleanup and summarisation.';

  @override
  String get outputSummarizeKindActionItems => 'Action items';

  @override
  String get outputSummarizeKindKeyTopics => 'Key topics';

  @override
  String get outputSummarizeKindDecisions => 'Decisions';

  @override
  String get outputSummarizeRun => 'Summarize';

  @override
  String get outputSummarizeEmpty => 'Pick sections and run.';

  @override
  String get outputSummarizeNothing =>
      'The model returned no items for the selected sections.';

  @override
  String get outputCleanup => 'Tidy transcript…';

  @override
  String get outputCleanupTitle => 'Tidy transcript';

  @override
  String get outputCleanupHelp =>
      'Deterministic cleanup of common ASR artifacts. Pick what to apply, preview the result, then Apply to all.';

  @override
  String get outputCleanupRemoveFillers =>
      'Remove filler words (um, uh, ah, …)';

  @override
  String get outputCleanupCollapseRepeats =>
      'Collapse repeated words (the the → the)';

  @override
  String get outputCleanupSentenceCase => 'Capitalise sentence starts';

  @override
  String get outputCleanupFixPunctuation =>
      'Fix punctuation (… , doubled commas, stray dots)';

  @override
  String get outputCleanupNormalizeWhitespace => 'Normalise whitespace';

  @override
  String get outputCleanupStripAnnotations => 'Strip annotation tags';

  @override
  String get outputCleanupStripAnnotationsHelp =>
      'Removes [laughter], (applause), <noise>. Off by default — useful for accessibility.';

  @override
  String get outputCleanupCustomFillers => 'Custom filler words';

  @override
  String get outputCleanupCustomFillersHint =>
      'Comma- or space-separated, e.g. like, basically, you know';

  @override
  String get outputCleanupPreviewHeading => 'Preview (first 3 segments)';

  @override
  String get outputCleanupPreviewEmpty => 'No segments to preview.';

  @override
  String get outputCleanupApply => 'Apply to all';

  @override
  String get outputCleanupLlmPass => 'Also run LLM pass (cloud)';

  @override
  String outputCleanupLlmPassHelp(String model) {
    return 'After the deterministic pass, send each segment to $model for a context-aware cleanup. Slower; uses your configured API key.';
  }

  @override
  String get outputCleanupLlmPassUnconfigured =>
      'Configure a cloud LLM endpoint in Settings → Cloud LLM cleanup to enable this.';

  @override
  String get outputCleanupLlmRunning => 'Running LLM cleanup pass…';

  @override
  String get outputCleanupLlmMode => 'LLM pass';

  @override
  String get outputCleanupLlmModeOff => 'Off';

  @override
  String get outputCleanupLlmModeCloud => 'Cloud';

  @override
  String get outputCleanupLlmModeLocal => 'Local';

  @override
  String outputCleanupLlmModeCloudHelp(String model) {
    return 'After the deterministic pass, send each segment to $model (cloud, BYOK). Slower; uses your configured API key.';
  }

  @override
  String outputCleanupLlmModeLocalHelp(String model) {
    return 'After the deterministic pass, run each segment through $model on this device. No network, no API key; first run loads the model into memory.';
  }

  @override
  String get outputCleanupLlmModeCloudUnconfigured =>
      'Configure a cloud LLM endpoint in Settings → Cloud LLM cleanup to enable this.';

  @override
  String get outputCleanupLlmModeLocalUnconfigured =>
      'Point at a GGUF chat model in Settings → Local LLM cleanup to enable this.';

  @override
  String get settingsLocalLlmCleanup => 'Local LLM cleanup (on-device)';

  @override
  String get settingsLocalLlmCleanupOff =>
      'Off (point at a GGUF chat model to enable)';

  @override
  String get settingsLocalLlmHelp =>
      'Optional. Loads a GGUF chat model on this device and runs every Tidy / Summarize pass against it. No network, no API key. Needs ~2–8 GB of free RAM depending on model size; Metal / CUDA acceleration is used when available.';

  @override
  String get settingsLocalLlmModelPath => 'Chat model file (GGUF)';

  @override
  String get settingsLocalLlmModelPathEmpty => 'No model selected';

  @override
  String get settingsLocalLlmModelPick => 'Browse…';

  @override
  String get settingsLocalLlmModelClear => 'Clear';

  @override
  String get settingsLocalLlmAdvanced => 'Advanced parameters';

  @override
  String settingsLocalLlmNGpuLayers(int n) {
    return 'GPU layers: $n';
  }

  @override
  String get settingsLocalLlmNGpuLayersAll => 'GPU layers: all';

  @override
  String get settingsLocalLlmNGpuLayersHelp =>
      '-1 = offload every layer to the GPU (default; Metal on macOS / CUDA on Linux+Windows when available). 0 = CPU only. Positive values are partial offload for low-VRAM machines.';

  @override
  String settingsLocalLlmNCtx(int n) {
    return 'Context window (tokens): $n';
  }

  @override
  String get settingsLocalLlmNCtxDefault => 'Context window: model default';

  @override
  String get settingsLocalLlmNCtxHelp =>
      '0 keeps the GGUF\'s baked-in default. Raise this when summarising long transcripts; lower it on memory-constrained hosts.';

  @override
  String settingsLocalLlmNThreads(int n) {
    return 'CPU threads: $n';
  }

  @override
  String get settingsLocalLlmNThreadsAuto => 'CPU threads: auto';

  @override
  String settingsLocalLlmMaxTokens(int n) {
    return 'Max output tokens per call: $n';
  }

  @override
  String settingsLocalLlmTemperature(String t) {
    return 'Temperature: $t';
  }

  @override
  String get settingsLocalLlmUnsupported =>
      'This libcrispasr build doesn\'t expose the chat ABI — needs CrispASR 0.7.0 or newer.';

  @override
  String get outputCleanupLocalLlmRunning => 'Running local LLM cleanup pass…';

  @override
  String get outputCleanupLocalLlmLoading =>
      'Loading local LLM (first run may take a few seconds)…';

  @override
  String get settingsHotkey => 'Global hotkey';

  @override
  String get settingsHotkeyOff =>
      'Off (configure a combo + behaviour to enable)';

  @override
  String get settingsHotkeyHelp =>
      'Register a system-wide keyboard shortcut so you can start / stop recording without bringing the app forward. Desktop only — iOS / Android don\'t expose a global-shortcut surface.';

  @override
  String get settingsHotkeyEnable => 'Enable global hotkey';

  @override
  String get settingsHotkeyCombo => 'Key combination';

  @override
  String get settingsHotkeyBehavior => 'Behaviour';

  @override
  String get settingsHotkeyActionPushToTalk => 'Push to talk';

  @override
  String get settingsHotkeyActionPushToTalkHelp =>
      'Hold to record, release to stop. Pairs well with combos that include a modifier (e.g. meta+shift+space).';

  @override
  String get settingsHotkeyActionToggle => 'Toggle';

  @override
  String get settingsHotkeyActionToggleHelp =>
      'Press once to start, press again to stop. Simpler mental model; doesn\'t require holding a modifier.';

  @override
  String settingsHotkeyInvalid(String combo) {
    return 'Invalid combo \"$combo\". Use modifier+modifier+key, e.g. meta+shift+space.';
  }

  @override
  String get settingsCloudLlmCleanup => 'Cloud LLM cleanup (BYOK)';

  @override
  String get settingsCloudLlmCleanupOff =>
      'Off (paste an OpenAI-compatible URL + API key to enable)';

  @override
  String get settingsCloudLlmHelp =>
      'Optional. Sends each segment to an OpenAI-compatible /v1/chat/completions endpoint for context-aware cleanup. Works against OpenAI, Anthropic via proxy, OpenRouter, Groq, a local llama-server, etc. Your key stays on this device.';

  @override
  String get settingsCloudLlmUrl => 'API URL';

  @override
  String get settingsCloudLlmKey => 'API key';

  @override
  String get settingsCloudLlmModel => 'Model id';

  @override
  String get settingsCloudLlmClear => 'Clear';

  @override
  String outputCleanupApplied(int n) {
    return 'Cleanup applied to $n segment(s).';
  }

  @override
  String get outputEditSegmentInAudioEditor =>
      'Edit this segment in audio editor';

  @override
  String get outputMarkSegmentInAudioEditor => 'Mark for split in audio editor';

  @override
  String editAudioSegmentSelected(String start, String end) {
    return 'Selection set: $start – $end.';
  }

  @override
  String advancedMaxLen(int n) {
    return 'Max tokens per segment: $n';
  }

  @override
  String get advancedMaxLenOff => 'off';

  @override
  String get advancedMaxLenSubtitle =>
      'Whisper-only soft cap. 0 = no cap (default). Pair with \"Split on word\" for SRT-friendly short subtitle lines.';

  @override
  String get advancedSplitOnWord => 'Split on word boundaries';

  @override
  String get advancedSplitOnWordSubtitle =>
      'When the segment cap is hit, break on the next word boundary instead of mid-word. Yields more readable subtitle output.';

  @override
  String get advancedSplitOnPunct => 'Split on punctuation';

  @override
  String get advancedSplitOnPunctSubtitle =>
      'Split segments at sentence-ending punctuation (. ! ?) for natural subtitle lines. Works with any backend.';

  @override
  String get advancedVocabulary => 'Custom vocabulary';

  @override
  String get advancedVocabularyHint =>
      'Type a term and press Enter (e.g. API, kubectl, Alice)';

  @override
  String get advancedVocabularyAdd => 'Add term';

  @override
  String get advancedVocabularyHelperPrompt =>
      'Biases the decoder via Whisper\'s initial_prompt. Useful for brand names, acronyms, technical jargon and people\'s names that the model otherwise mishears.';

  @override
  String get advancedVocabularyHelperAsk =>
      'Biases the LLM by prepending these terms to its prompt. Combined with Q&A — your question still runs.';

  @override
  String get advancedVocabularyHelperUnsupported =>
      'The active backend is CTC-style and can\'t bias vocabulary at the decoder. Switch to Whisper / Moonshine / an LLM-backend (Voxtral, Qwen3, Granite, …) to enable.';

  @override
  String get advancedHotwords => 'Hotwords';

  @override
  String get advancedHotwordsHint =>
      'Comma-separated words or phrases (e.g. ACME Corp, TensorFlow, Dr. Smith)';

  @override
  String get advancedHotwordsHelper =>
      'Biases the decoder toward these words/phrases. Useful for names, brands, or domain terms the model is likely to mishear.';

  @override
  String get advancedHotwordsUnsupported =>
      'The active backend doesn\'t support hotword biasing. Switch to an LLM-backend or Whisper to enable.';

  @override
  String get voiceCloneOpenTooltip => 'Clone a voice…';

  @override
  String get voiceCloneTitle => 'Voice clone wizard';

  @override
  String get voiceCloneStepCapture => 'Capture';

  @override
  String get voiceCloneStepRefText => 'Reference text';

  @override
  String get voiceCloneStepHandoff => 'Synthesize';

  @override
  String get voiceCloneCaptureHeading => 'Capture a reference clip';

  @override
  String voiceCloneCaptureHelp(int seconds) {
    return 'Record about $seconds seconds of clean speech, or pick an existing audio file. A single speaker with minimal background noise gives the best clone.';
  }

  @override
  String get voiceCloneCaptureNoPermission =>
      'Microphone permission was denied. Grant it in your system settings and try again.';

  @override
  String voiceCloneRecord(int seconds) {
    return 'Record $seconds s';
  }

  @override
  String get voiceClonePickFile => 'Pick file';

  @override
  String voiceCloneRecordingCountdown(int seconds) {
    return '$seconds s remaining';
  }

  @override
  String get voiceCloneRecordingStop => 'Stop';

  @override
  String get voiceClonePreviewPlay => 'Play';

  @override
  String get voiceClonePreviewPause => 'Pause';

  @override
  String get voiceCloneCaptureClear => 'Start over';

  @override
  String get voiceCloneRefTextHeading => 'What was said in the clip?';

  @override
  String get voiceCloneRefTextHelp =>
      'Some cloners (indextts, vibevoice) need a verbatim transcript of the reference clip for alignment. Others (chatterbox, qwen3-tts Base) clone from audio alone — leave this empty if your chosen backend doesn\'t need it.';

  @override
  String get voiceCloneRefTextLabel => 'Reference transcript';

  @override
  String get voiceCloneRefTextHint =>
      'Type what was said in the reference clip…';

  @override
  String get voiceCloneHandoffHeading => 'Ready to synthesize';

  @override
  String get voiceCloneHandoffHelp =>
      'We\'ll open the Synthesize screen with the clip and reference text pre-populated. Pick a clone-capable model (chatterbox, indextts, qwen3-tts Base, vibevoice-1.5b), type the text you want spoken, and hit Synthesize.';

  @override
  String get voiceCloneHandoffModelHint =>
      'Tip: chatterbox / qwen3-tts Base clone from audio alone; indextts / vibevoice also use the reference transcript.';

  @override
  String get voiceCloneSummaryReference => 'Reference clip';

  @override
  String get voiceCloneSummaryRefText => 'Reference text';

  @override
  String get voiceCloneSummaryRefTextEmpty => '(none — audio-only clone)';

  @override
  String get voiceCloneBack => 'Back';

  @override
  String get voiceCloneNext => 'Next';

  @override
  String get voiceCloneConsentTitle => 'Voice Rights Attestation';

  @override
  String get voiceCloneConsentBody =>
      'Voice cloning creates a synthetic replica of the voice in your reference audio. Under the EU AI Act (Art. 50) and GDPR (Art. 9), you must have explicit consent from the voice owner, or the voice must be your own. Misuse of voice cloning for impersonation is prohibited.';

  @override
  String get voiceCloneConsentCheckbox =>
      'I confirm that I have the rights to clone this voice (it is my own voice, or I have explicit consent from the voice owner)';

  @override
  String get voiceCloneFinish => 'Open in Synthesize';

  @override
  String get synthTitle => 'Synthesize';

  @override
  String get synthModelLabel => 'TTS model';

  @override
  String get synthVoiceLabel => 'Voice / voicepack';

  @override
  String get synthCodecLabel => 'Codec / tokenizer';

  @override
  String get synthTextHint => 'Type text to synthesise…';

  @override
  String get synthDiaTextHint =>
      '[S1] Hello, how are you? [S2] I\'m doing great, thanks!';

  @override
  String get synthDiaHelper =>
      'Dia uses [S1] and [S2] tags to mark different speakers in dialogue. Use 100+ character prompts for best results.';

  @override
  String get synthS2sToggle => 'Speech-to-Speech mode';

  @override
  String get synthS2sHelper =>
      'Transform audio input through the model instead of synthesizing from text. Requires LFM2-Audio or Mini-Omni2.';

  @override
  String get synthS2sPickAudio => 'No audio file selected';

  @override
  String get synthS2sBrowse => 'Browse';

  @override
  String get synthRunButton => 'Synthesize';

  @override
  String get synthPlayButton => 'Play';

  @override
  String get synthStopButton => 'Stop';

  @override
  String get synthShareButton => 'Save / share WAV';

  @override
  String get synthNoTtsModelsDownloaded =>
      'No TTS models downloaded yet. Open Models → Models tab → switch to \"TTS\" to fetch one.';

  @override
  String get synthOpenModelManagement => 'Open Model Management';

  @override
  String defaultModelNotDownloaded(String modelId) {
    return 'Default model \"$modelId\" isn\'t downloaded yet.';
  }

  @override
  String get noModelsDownloadedYet =>
      'No transcription model is downloaded yet — open Models to grab one.';

  @override
  String get filePickerCloudFileUnsupported =>
      'This file lives in cloud storage and can\'t be opened directly. Please copy it to local storage (Downloads / Files on this device) and try again.';

  @override
  String filePickerFailed(String error) {
    return 'File picker failed: $error';
  }

  @override
  String get openModels => 'Open Models';

  @override
  String synthMissingDependency(String name) {
    return 'Missing required companion file: $name';
  }

  @override
  String synthBackendUnsupported(String backend) {
    return '$backend synthesis isn\'t available in this build yet. This voice will work once an updated engine ships.';
  }

  @override
  String get synthSpeakerLabel => 'Speaker';

  @override
  String get synthSpeakerHelper =>
      'This voice has built-in speakers — pick one.';

  @override
  String get synthPreviewVoice => 'Preview voice';

  @override
  String get synthPreviewSample => 'Hello, this is a voice preview.';

  @override
  String get advancedVadBackend => 'VAD backend';

  @override
  String get advancedVadBackendHelper =>
      'Silero is bundled (~885 KB). FireRed / MarbleNet / Whisper-VAD need a Model Management download; missing files fall back to Silero.';

  @override
  String get advancedVadBackendSilero => 'Silero (bundled, default)';

  @override
  String get advancedVadBackendFirered => 'FireRedVAD (F1 97.57%, ~3 MB)';

  @override
  String get advancedVadBackendMarblenet => 'MarbleNet (small, multilingual)';

  @override
  String get advancedVadBackendWhisperEncDec =>
      'Whisper-VAD-EncDec (experimental EN)';

  @override
  String advancedVadThreshold(String value) {
    return 'VAD threshold: $value';
  }

  @override
  String get advancedVadThresholdHelper =>
      'Higher = fewer / shorter speech regions detected. CrispASR default is 0.50.';

  @override
  String advancedVadMinSpeech(int ms) {
    return 'Min. speech duration: $ms ms';
  }

  @override
  String get advancedVadMinSpeechHelper =>
      'Shortest voiced run kept as a speech segment.';

  @override
  String advancedVadMinSilence(int ms) {
    return 'Min. silence duration: $ms ms';
  }

  @override
  String get advancedVadMinSilenceHelper =>
      'Shortest silence that splits one segment from the next.';

  @override
  String advancedVadSpeechPad(int ms) {
    return 'Speech padding: $ms ms';
  }

  @override
  String get advancedVadSpeechPadHelper =>
      'Extra context added on each side of every speech segment.';

  @override
  String get advancedLidMethod => 'Language detection method';

  @override
  String get advancedLidMethodHelper =>
      'Used when the model lacks native LID and you picked Auto. Whisper reuses any multilingual ggml-*.bin; Silero / Firered / Ecapa each need their own GGUF.';

  @override
  String get advancedLidMethodWhisper =>
      'Whisper encoder (reuses an existing model)';

  @override
  String get advancedLidMethodSilero => 'Silero (95 languages, ~16 MB GGUF)';

  @override
  String get advancedLidMethodFirered =>
      'FireRed (120 languages, ~300 MB GGUF)';

  @override
  String get advancedLidMethodEcapa =>
      'ECAPA-TDNN (107 languages, ~42 MB GGUF)';

  @override
  String get advancedGrammarTitle => 'GBNF grammar (Whisper only)';

  @override
  String get advancedGrammarSubtitle =>
      'Force a structured output shape (JSON / SKU / phone numbers / …). Empty = no constraint.';

  @override
  String get advancedGrammarSubtitleActive =>
      'Grammar active — output will be constrained to this GBNF.';

  @override
  String get advancedGrammarTextLabel => 'GBNF source';

  @override
  String get advancedGrammarRootRule => 'Root rule';

  @override
  String get advancedGrammarRootRuleHelper =>
      'Symbol name to start parsing from. The GBNF convention is \"root\".';

  @override
  String advancedGrammarPenalty(String value) {
    return 'Grammar penalty: $value';
  }

  @override
  String get advancedGrammarPenaltyHelper =>
      'Higher = harder constraint, lower = softer suggestion. Upstream default is 100; useful range is 50..200.';

  @override
  String get advancedTranscribeWindowTitle =>
      'Transcribe window (offset + duration)';

  @override
  String get advancedTranscribeWindowSubtitle =>
      'Process only a [start, start+duration) slice of the audio. Empty / 0 = transcribe the whole file (default).';

  @override
  String advancedTranscribeWindowSubtitleActive(String start, String end) {
    return 'Active: ${start}s..${end}s of the file. Timestamps remain absolute on output.';
  }

  @override
  String get advancedTranscribeWindowEndOfFile => 'end-of-file';

  @override
  String get advancedTranscribeWindowStart => 'Start (seconds)';

  @override
  String get advancedTranscribeWindowStartHelper =>
      'Offset into the file. 0 = start.';

  @override
  String get advancedTranscribeWindowDuration => 'Duration (seconds)';

  @override
  String get advancedTranscribeWindowDurationHelper =>
      '0 = transcribe until end-of-file.';

  @override
  String get advancedFallbackThresholdsTitle => 'Whisper decoder fallbacks';

  @override
  String get advancedFallbackThresholdsSubtitle =>
      'Tune when the decoder retries at a higher temperature or treats audio as silence. Defaults match stock whisper.cpp.';

  @override
  String get advancedFallbackThresholdsSubtitleActive =>
      'Custom thresholds active — defaults are 2.4 / -1.0 / 0.6 / 0.2.';

  @override
  String get advancedFallbackThresholdsReset => 'Reset to defaults';

  @override
  String advancedEntropyThold(String value) {
    return 'Entropy threshold: $value';
  }

  @override
  String get advancedEntropyTholdHelper =>
      'Per-token entropy that triggers a fallback pass. Default 2.4. Lower = stricter (more retries on hard audio); raise to suppress excessive retries.';

  @override
  String advancedLogprobThold(String value) {
    return 'Logprob threshold: $value';
  }

  @override
  String get advancedLogprobTholdHelper =>
      'Average log-probability cutoff that triggers a fallback pass. Default -1.0. More negative = more tolerant of noisy decoding.';

  @override
  String advancedNoSpeechThold(String value) {
    return 'No-speech threshold: $value';
  }

  @override
  String get advancedNoSpeechTholdHelper =>
      'Silence detector cutoff. Default 0.6. Higher = less aggressive silence gating (keeps faint speech).';

  @override
  String advancedTemperatureInc(String value) {
    return 'Temperature increment: $value';
  }

  @override
  String get advancedTemperatureIncDisabled =>
      'Temperature increment: 0 (fallback disabled)';

  @override
  String get advancedTemperatureIncHelper =>
      'Temperature step per fallback pass. Default 0.2. Set to 0 to disable the fallback loop entirely (= the CLI\'s --no-fallback).';

  @override
  String get advancedWhisperDecodeExtrasTitle => 'Whisper text suppression';

  @override
  String get advancedWhisperDecodeExtrasSubtitle =>
      'Drop non-speech markers, suppress regex-matched tokens, or repeat the initial prompt on every decode window.';

  @override
  String get advancedWhisperDecodeExtrasSubtitleActive =>
      'Custom suppression active — defaults are: keep all tokens / no regex / single-window prompt.';

  @override
  String get advancedSuppressNonSpeechTokens => 'Drop non-speech tokens';

  @override
  String get advancedSuppressNonSpeechTokensHelper =>
      'Strip [LAUGHTER] / [MUSIC] / [NOISE] markers whisper emits on top of the spoken words. Off by default.';

  @override
  String get advancedSuppressTokensRegex => 'Suppress regex (Posix)';

  @override
  String get advancedSuppressTokensRegexHelper =>
      'Tokens whose text matches this regex get dropped during decoding. Empty disables. Useful for purging hallucinated tokens or speaker-tag patterns.';

  @override
  String get advancedCarryInitialPrompt =>
      'Carry initial prompt to every window';

  @override
  String get advancedCarryInitialPromptHelper =>
      'Repeat the initial prompt at the start of every decode window (not just the first). Strengthens vocabulary biasing on long audio at the cost of weakening previous-context conditioning.';

  @override
  String get advancedEnhanceAudio => 'Enhance audio (noise reduction)';

  @override
  String get advancedEnhanceAudioHelper =>
      'Runs an RNNoise pre-step on the audio before transcription. Reduces HVAC / fan / keyboard noise. Costs ~1× realtime on CPU; off by default.';

  @override
  String get settingsLocalLlmCatalogueTitle => 'Suggested chat models';

  @override
  String get settingsLocalLlmCatalogueHelp =>
      'Tap a downloaded model to select it. Tap an undownloaded model to open Model Management and download it.';

  @override
  String get settingsLocalLlmCatalogueManage => 'Manage';

  @override
  String settingsLocalLlmCatalogueDownloaded(String size) {
    return 'Downloaded · $size';
  }

  @override
  String settingsLocalLlmCatalogueNotDownloaded(String size) {
    return 'Not downloaded · $size';
  }

  @override
  String get settingsLocalLlmCatalogueDownload => 'DOWNLOAD';

  @override
  String get modelsKindFilterChatLlm => 'Chat LLM';

  @override
  String get advancedDiarizeMethod => 'Diarisation method';

  @override
  String get advancedDiarizeMethodHelper =>
      'Only takes effect when diarisation is enabled. vad-turns is mono-friendly; pyannote requires its segmentation GGUF; energy / xcorr need stereo audio.';

  @override
  String get advancedDiarizeVadTurns => 'VAD turns (mono, no extra model)';

  @override
  String get advancedDiarizePyannote => 'Pyannote v3 (ML, needs GGUF)';

  @override
  String get advancedDiarizeEnergy => 'Stereo L/R energy';

  @override
  String get advancedDiarizeXcorr => 'Stereo cross-correlation';

  @override
  String get advancedSpeakerRecognition => 'Identify enrolled speakers';

  @override
  String get advancedSpeakerRecognitionSubtitle =>
      'After diarisation, match each speaker cluster against the on-device speaker DB (Settings → Speakers) and replace \'Speaker N\' with the enrolled name when confident. Requires the TitaNet GGUF.';

  @override
  String get advancedTdrz => 'Tinydiarize speaker turns (Whisper only)';

  @override
  String get advancedTdrzSubtitle =>
      'Insert [SPEAKER_TURN] markers via a Whisper .en.tdrz finetune. No-op on session backends.';

  @override
  String get advancedTokenTimestamps => 'Token-level timestamps';

  @override
  String get advancedTokenTimestampsSubtitle =>
      'DTW-aligned per-token timing. Slower than word timestamps; useful for fine-grained subtitle tooling.';

  @override
  String get advancedAltN => 'Alternative candidates per word (Whisper only)';

  @override
  String advancedAltNLabel(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Top $n',
      zero: 'Off',
    );
    return '$_temp0';
  }

  @override
  String get advancedAltNSubtitle =>
      'Capture the top-N runner-up tokens at each Whisper greedy step. Lets you tap an ambiguous word in the transcript editor and pick a competing candidate (kubectl / cubicle / …). 0 = off (default). Best with greedy decoding — beam search not supported. Pre-0.5.13 dylibs silently ignore.';

  @override
  String get advancedPuncFamily => 'Punctuation model';

  @override
  String get advancedPuncFamilyHelper =>
      'PCS is all-in-one (punct + truecase + SBD, 47 langs). FireRedPunc and fullstop-punc chain with the truecaser.';

  @override
  String get advancedPuncFamilyPcs => 'PCS (47 languages, all-in-one)';

  @override
  String get advancedPuncFamilyFirered => 'FireRedPunc (Chinese + English)';

  @override
  String get advancedPuncFamilyFullstop =>
      'Fullstop-punc multilang (EN/DE/FR/IT)';

  @override
  String get transcriptionSaveAsCsv => 'Save as CSV';

  @override
  String get transcriptionSaveAsLrc => 'Save as LRC (lyrics)';

  @override
  String get transcriptionSaveAsWts => 'Save as WTS (debug)';

  @override
  String get transcriptionSaveAsMarkdown => 'Save as Markdown';

  @override
  String get transcriptionShareAudioAndTranscript => 'Share audio + transcript';

  @override
  String get transcriptionShareAudioAndTranscriptHelp =>
      'Sends the audio file and the SRT transcript as a single share — useful for archiving or handing off to a colleague.';

  @override
  String get transcriptionShareAudioMissing =>
      'Select an audio file first to share both together.';

  @override
  String get synthAdvancedSection => 'Advanced synthesis';

  @override
  String get synthRefText => 'Reference transcript (voice cloning)';

  @override
  String get synthRefTextHelper =>
      'Required when pairing a WAV voice with qwen3-tts Base or vibevoice-1.5b for runtime cloning. Empty for baked GGUF voices.';

  @override
  String get synthInstruct => 'Voice description (VoiceDesign / Parler-TTS)';

  @override
  String get synthInstructHelper =>
      'Natural-language description of the desired voice (\"warm female narrator, slight British accent\"). Used by qwen3-tts VoiceDesign and Parler-TTS; ignored on other backends.';

  @override
  String get synthTrimSilence => 'Trim silence';

  @override
  String get synthTrimSilenceSubtitle =>
      'Strip leading and trailing silence below -72 dBFS from the synthesised PCM.';

  @override
  String synthSpeed(String value) {
    return 'Speed: $value×';
  }

  @override
  String get synthSpeedHelper =>
      'Playback speed multiplier (0.25× – 4.00×). Nearest-neighbour resample; no pitch correction.';

  @override
  String get translateTitle => 'Translate text';

  @override
  String get translateModelLabel => 'Translation model';

  @override
  String get translateSourceLang => 'From';

  @override
  String get translateTargetLang => 'To';

  @override
  String get translateSwap => 'Swap source and target';

  @override
  String get translateInputLabel => 'Source text';

  @override
  String get translateInputHint => 'Type or paste text to translate…';

  @override
  String get translateOutputLabel => 'Translation';

  @override
  String get translateRunButton => 'Translate';

  @override
  String get translateNoModelsDownloaded =>
      'No translation models downloaded. Open Models, switch to the Translate filter, and fetch one of M2M-100, WMT21 (en→X / X→en), or MADLAD-400.';

  @override
  String get translateAdvanced => 'Advanced';

  @override
  String translateMaxTokens(int n) {
    return 'Max output tokens: $n';
  }

  @override
  String get translateMaxTokensHelper =>
      'Hard cap on translated-text length. CrispASR\'s default is 200; raise for long passages, lower to keep generation snappy.';

  @override
  String get advancedPerfHeader => 'Performance';

  @override
  String get advancedLidUseGpu => 'LID on GPU';

  @override
  String get advancedLidUseGpuSubtitle =>
      'Route language detection to Metal / CUDA / Vulkan when supported. ASR backends honour their own per-session GPU setup at load time.';

  @override
  String get advancedLidFlashAttn => 'LID flash-attention';

  @override
  String get advancedLidFlashAttnSubtitle =>
      'Faster attention kernel during the LID encoder pass. Disable only if you suspect a flash-attn correctness bug on your build.';

  @override
  String advancedNThreads(int n) {
    return 'CPU threads: $n';
  }

  @override
  String get advancedNThreadsHelper =>
      'Threads used for LID and other non-decoder passes. Defaults to 4.';

  @override
  String get synthCustomVoice => 'Custom voice (WAV reference)';

  @override
  String get synthCustomVoiceHelper =>
      'Pick a WAV from disk for runtime cloning. Pair with the Reference transcript on qwen3-tts Base / vibevoice-1.5b. Overrides the voicepack dropdown when set.';

  @override
  String get synthCustomVoicePick => 'Pick reference WAV…';

  @override
  String get synthCustomVoiceReplace => 'Replace reference WAV…';

  @override
  String get synthCustomVoiceClear => 'Clear custom voice';

  @override
  String get recorderStreamSession => 'Stream (session)';

  @override
  String get recorderStreamSessionTooltip =>
      'Live mic transcribe through the active backend\'s streaming arm (kyutai-stt / moonshine-streaming / voxtral4b). Falls back to Whisper sliding-window when the backend has no native stream API.';

  @override
  String streamingNotAvailableForBackend(String backend) {
    return 'The active backend ($backend) has no streaming arm. Switch to whisper, kyutai-stt, moonshine-streaming, or voxtral4b.';
  }

  @override
  String get streamingNoModelLoaded =>
      'No model loaded yet. Pick a model from the dropdown above (it\'ll auto-load if downloaded), or open Model Management to download one first.';

  @override
  String get transcribeNoSource =>
      'Please select an audio file, enter a URL, or make a recording.';

  @override
  String get voiceBakeTitle => 'Bake voice (WAV → GGUF)';

  @override
  String get voiceBakeOpenTooltip =>
      'Bake a Chatterbox voice from a WAV reference';

  @override
  String get voiceBakeIntro =>
      'Run CrispASR\'s bake-chatterbox-voice-from-wav.py to convert a WAV reference into a baked voicepack GGUF. Requires Python 3 + chatterbox-tts + gguf installed on the system.';

  @override
  String get voiceBakeWavLabel => 'Reference WAV';

  @override
  String get voiceBakeWavPick => 'Pick WAV…';

  @override
  String get voiceBakeOutputName => 'Output filename';

  @override
  String get voiceBakeOutputNameHelper =>
      'Saved into your models directory next to other voicepacks. Use the .gguf extension.';

  @override
  String voiceBakeExaggeration(String value) {
    return 'Exaggeration: $value';
  }

  @override
  String get voiceBakeExaggerationHelper =>
      'Default emotion-advance scalar (0.0 – 1.0). 0.5 is the upstream default.';

  @override
  String get voiceBakePythonLabel => 'Python interpreter';

  @override
  String get voiceBakePythonHelper =>
      'Defaults to `python3` on PATH. Override if your chatterbox-tts / gguf install lives in a venv.';

  @override
  String get voiceBakeScriptLabel => 'Bake script path';

  @override
  String get voiceBakeScriptHelper =>
      'Defaults to ../CrispASR/models/bake-chatterbox-voice-from-wav.py. Adjust if your CrispASR checkout is elsewhere.';

  @override
  String get voiceBakeRun => 'Bake voice';

  @override
  String get voiceBakeRunning => 'Baking…';

  @override
  String voiceBakeSuccess(String path) {
    return 'Voice baked → $path';
  }

  @override
  String voiceBakeFailure(String error) {
    return 'Bake failed: $error';
  }

  @override
  String get voiceBakeMissingInputs =>
      'Pick a reference WAV and an output filename first.';

  @override
  String get advancedAsrUseGpu => 'ASR on GPU';

  @override
  String get advancedAsrUseGpuSubtitle =>
      'Route ASR session inits to Metal / CUDA / Vulkan when supported. Takes effect on the next model load. Backends without runtime GPU control keep their compile-time default.';

  @override
  String get advancedAsrFlashAttn => 'ASR flash-attention';

  @override
  String get advancedAsrFlashAttnSubtitle =>
      'Use the flash-attention kernel for the ASR compute graph. Honoured by Whisper natively; other backends accept the toggle but their compute graphs aren\'t yet branched on it. Takes effect on the next model load.';

  @override
  String advancedAsrNGpuLayers(int n) {
    return 'GPU layers (LLM): $n';
  }

  @override
  String get advancedAsrNGpuLayersAuto => 'GPU layers (LLM): auto (max)';

  @override
  String get advancedAsrNGpuLayersHelper =>
      'Cap on GPU-offloaded transformer layers for LLM-based backends (orpheus / voxtral / qwen3 / granite / chatterbox). 0 = run LLM on CPU; 1+ = explicit bound; auto = as many as fit. Takes effect on the next model load.';

  @override
  String get settingsServerSection => 'Local HTTP server (OpenAI-compatible)';

  @override
  String get settingsServerEnable => 'Run server';

  @override
  String settingsServerRunningAt(String url) {
    return 'Listening on $url';
  }

  @override
  String get settingsServerStopped =>
      'Stopped. Toggle on to expose CrisperWeaver\'s services on a local port.';

  @override
  String settingsServerStartFailed(String error) {
    return 'Failed to start server: $error';
  }

  @override
  String get settingsServerEndpoints => 'Endpoints';

  @override
  String get settingsServerEndpointsHelp =>
      'POST /v1/audio/transcriptions (multipart upload, file=audio) · POST /v1/audio/speech (JSON: model, input, voice, speed) · POST /v1/translations (JSON: model, text, src, tgt) · GET /health. Binds to 127.0.0.1 only — no auth.';

  @override
  String synthTemperature(String value) {
    return 'Temperature: $value';
  }

  @override
  String get synthTemperatureHelper =>
      'Sampling temperature shared across orpheus / chatterbox / canary. 0.0 = greedy / reproducible. Higher = more variety.';

  @override
  String synthTtsSteps(int n) {
    return 'Diffusion steps: $n';
  }

  @override
  String get synthTtsStepsHelper =>
      'Number of CFM Euler steps in the chatterbox mel decoder (default 10). Higher = smoother audio at the cost of latency.';

  @override
  String synthCfgWeight(String value) {
    return 'CFG weight: $value';
  }

  @override
  String get synthCfgWeightHelper =>
      'Classifier-free-guidance weight (chatterbox). 0 disables CFG; 0.5 is the upstream default; 1+ amplifies the conditional path.';

  @override
  String synthExaggeration(String value) {
    return 'Exaggeration: $value';
  }

  @override
  String get synthExaggerationHelper =>
      'Emotion-exaggeration scalar (chatterbox). 0.5 is the upstream default; raise for dramatic delivery, lower for monotone.';

  @override
  String synthTopP(String value) {
    return 'Top-p: $value';
  }

  @override
  String get synthTopPHelper =>
      'Top-p nucleus sampling threshold (chatterbox). 1.0 disables top-p; lower values cut the long tail of unlikely tokens.';

  @override
  String synthMinP(String value) {
    return 'Min-p: $value';
  }

  @override
  String get synthMinPHelper =>
      'Min-p threshold (chatterbox). 0 disables; positive values drop tokens whose probability falls below this fraction of the most-likely token.';

  @override
  String synthRepetitionPenalty(String value) {
    return 'Repetition penalty: $value';
  }

  @override
  String get synthRepetitionPenaltyHelper =>
      'Repeat-penalty scalar (chatterbox). 1.0 disables; raise to discourage the model from loop-stuttering on repeated tokens.';

  @override
  String synthMaxSpeechTokens(int n) {
    return 'Max speech tokens: $n';
  }

  @override
  String get synthMaxSpeechTokensHelper =>
      'Hard cap on AR speech tokens per call (chatterbox). 1000 ≈ 20 s; raise for long inputs, lower to bound runaway generation.';

  @override
  String synthSeed(int n) {
    return 'Seed: $n';
  }

  @override
  String get synthSeedHelper =>
      'Random seed for reproducible output (chatterbox, vibevoice, qwen3-tts, orpheus). 0 = non-deterministic.';

  @override
  String synthFrequencyPenalty(String value) {
    return 'Frequency penalty: $value';
  }

  @override
  String get synthFrequencyPenaltyHelper =>
      'Penalises repeated tokens in autoregressive backends. 0 = off; raise to reduce loop-stuttering artefacts.';

  @override
  String synthTopK(int n) {
    return 'Top-K: $n';
  }

  @override
  String get synthTopKHelper =>
      'Top-K sampling width (qwen3-tts, chatterbox, orpheus, dots-tts, tada). 0 = disabled.';

  @override
  String get synthDoSample => 'Stochastic sampling';

  @override
  String get synthDoSampleHelper =>
      'Enable stochastic sampling instead of greedy decoding.';

  @override
  String synthNumCandidates(int n) {
    return 'Acoustic candidates: $n';
  }

  @override
  String get synthNumCandidatesHelper =>
      'Number of acoustic candidates for ranking (tada, chatterbox, kokoro). 0 = backend default.';

  @override
  String synthNoiseTemp(String value) {
    return 'Noise temperature: $value';
  }

  @override
  String get synthNoiseTempHelper =>
      'Noise temperature for stochastic generation (kokoro, vibevoice). 0 = backend default.';

  @override
  String get synthG2pDict => 'G2P dictionary';

  @override
  String get synthG2pDictHelper =>
      'Grapheme-to-phoneme dictionary path (kokoro, vibevoice, speecht5).';

  @override
  String get synthClearPhonemeCache => 'Clear phoneme cache';

  @override
  String get synthClearPhonemeCacheDone => 'Phoneme cache cleared.';

  @override
  String get synthClearPhonemeCacheUnsupported =>
      'This backend doesn\'t use a phoneme cache (or the open session is too old).';

  @override
  String modelsLoadFailed(String error) {
    return 'Failed to load models: $error';
  }

  @override
  String modelsProbeFailed(String error) {
    return 'HuggingFace probe failed: $error';
  }

  @override
  String modelsSkippedRepos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count private/gated repos',
      one: '1 private/gated repo',
    );
    return ' Skipped $_temp0.';
  }

  @override
  String get modelsHfRepoTitle => 'Add from HuggingFace repo';

  @override
  String get modelsHfRepoAddTooltip => 'Add from HuggingFace repo…';

  @override
  String get modelsHfReposManageTooltip => 'Manage added HuggingFace repos…';

  @override
  String get modelsHfRepoBody =>
      'Paste a HuggingFace repo id like \"cstr/voxtral-mini-3b-2507-GGUF\". CrisperWeaver lists every .gguf / .bin file in the repo, registers each as a downloadable model under the backend you pick, and adds them to the models list.';

  @override
  String get modelsHfRepoIdLabel => 'Repo id (OWNER/NAME)';

  @override
  String get modelsHfRepoIdHint => 'e.g. cstr/voxtral-mini-3b-2507-GGUF';

  @override
  String get modelsHfRepoBackendLabel => 'Backend';

  @override
  String get modelsHfRepoBackendHelper => 'How the model should be loaded.';

  @override
  String get modelsHfRepoProbe => 'Probe';

  @override
  String modelsHfRepoNoneFound(String repo) {
    return 'No .gguf / .bin files found in $repo.';
  }

  @override
  String modelsHfRepoAdded(int count, String repo) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models',
      one: '1 model',
    );
    return 'Added $_temp0 from $repo.';
  }

  @override
  String modelsHfRepoProbeFailed(String repo, String error) {
    return 'Failed to probe $repo:\n$error';
  }

  @override
  String get modelsHfReposTitle => 'Added HuggingFace repos';

  @override
  String get modelsHfReposEmpty =>
      'No repos added yet. Use “Add from HuggingFace repo…” to register one — it will persist across restarts.';

  @override
  String modelsHfRepoBackendValue(String backend) {
    return 'backend: $backend';
  }

  @override
  String get modelsHfRepoForget => 'Forget this repo';

  @override
  String get modelsAnyLanguage => 'Any language';

  @override
  String get modelsCategoryEmpty =>
      'No models in this category yet — try the cloud-refresh button or download one from another category first.';

  @override
  String get modelsFilterAll => 'All';

  @override
  String get modelsFilterAsr => 'ASR';

  @override
  String get modelsFilterTts => 'TTS';

  @override
  String get modelsFilterVoices => 'Voices';

  @override
  String get modelsFilterCodecs => 'Codecs';

  @override
  String get modelsFilterPostproc => 'Post-processors';

  @override
  String get modelsFilterTranslate => 'Translate';

  @override
  String get modelsFilterAllLangs => 'All langs';

  @override
  String modelsDownloadedOne(String name) {
    return '$name downloaded';
  }

  @override
  String modelsDownloadedMany(int count, String names) {
    return '$count files downloaded: $names';
  }

  @override
  String modelsDeletedNamed(String name) {
    return '$name deleted';
  }

  @override
  String modelsTotalSize(String size) {
    return 'Total size: $size';
  }

  @override
  String modelsDownloadFailedNamed(String name) {
    return 'Failed to download $name';
  }

  @override
  String modelsDownloadFailedReason(String error) {
    return 'Download failed: $error';
  }

  @override
  String modelsDeleteFailedNamed(String name) {
    return 'Failed to delete $name';
  }

  @override
  String modelsDeleteFailedReason(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get enrollFromSegment => 'Enroll speaker from this segment…';

  @override
  String get enrollSpeakerTitle => 'Enroll speaker';

  @override
  String get enrollSpeakerNameLabel => 'Speaker name';

  @override
  String get enrollSpeakerNameHint => 'e.g. Alex';

  @override
  String get enrollAction => 'Enroll';

  @override
  String get enrollInProgress => 'Enrolling…';

  @override
  String get enrollNoAudio => 'Segment has no audio to enroll.';

  @override
  String enrollSucceeded(String name) {
    return 'Enrolled \"$name\" — future recordings will be matched.';
  }

  @override
  String get enrollFailedShort => 'Enrollment failed.';

  @override
  String enrollFailedReason(String error) {
    return 'Enrollment failed: $error';
  }

  @override
  String get modelsRecommendedBadge => 'Recommended';

  @override
  String transcribeNoBackendModelHint(String backend) {
    return 'No $backend model downloaded yet.';
  }

  @override
  String transcribeDownloadRecommended(String name, String size) {
    return 'Download recommended: $name ($size)';
  }

  @override
  String synthDownloadingNamed(String name) {
    return 'Downloading $name…';
  }

  @override
  String synthDownloadFailedShort(String name) {
    return 'Download of $name failed';
  }

  @override
  String synthDownloadFailedNamed(String name, String error) {
    return 'Download of $name failed: $error';
  }

  @override
  String get aiGeneratedAudio => 'AI-Generated Audio';

  @override
  String get speakerConsentTitle => 'Biometric Data Consent';

  @override
  String get speakerConsentBody =>
      'Speaker enrollment creates a voice embedding (biometric data under GDPR Art. 9). It is stored only on your device, is never transmitted, and can be deleted at any time from the speaker management screen.\n\nIf the voice is not your own, you must have the explicit consent of the person it belongs to before enrolling them. Only speakers with a consent record are matched.\n\nBy proceeding you confirm that the voice is your own, or that you have the explicit consent of the person it belongs to (GDPR Art. 9(2)(a)).';

  @override
  String get speakerConsentAgree => 'I Confirm';

  @override
  String get aboutSyntheticCompliance => 'Synthetic Content Compliance';

  @override
  String get aboutSyntheticComplianceText =>
      'Synthetic speech outputs are watermarked and carry machine-readable provenance metadata. Speaker enrollment requires explicit biometric consent (GDPR Art. 9). All data stays on-device; you can delete your data at any time.';

  @override
  String get syntheticDisclosureNote =>
      'This content contains AI-generated synthetic speech.';

  @override
  String get aiTransparencyTitle => 'AI-Powered Application';

  @override
  String get aiTransparencyBody =>
      'CrisperWeaver uses artificial intelligence systems for:\n\n• Speech recognition (ASR) — converting audio to text\n• Speech synthesis (TTS) — generating spoken audio from text\n• Speaker identification — biometric voice matching\n• Document analysis (OCR) — recognizing text in images\n• Text generation — translation, summarisation, and transcript cleanup by language models\n• Semantic search — AI-powered content retrieval\n\nBy default everything runs on your device and nothing is sent anywhere. Some features are off until you switch them on and then do use the network: model downloads, optional cloud transcription, and optional cloud summarisation or cleanup, which send the text or audio concerned to the provider you configure. Speaker profiles and voice recordings never leave your device.\n\nAI-generated audio is automatically watermarked and signed with machine-readable provenance metadata, and AI-generated text carries a disclosure when you copy or export it (EU AI Act Art. 50).\n\nFor details, see the About screen and PRIVACY.md.';

  @override
  String get aiTransparencyWebNote =>
      'Note for this web version: unlike the desktop and mobile apps, the browser build has no on-device engine. Speech recognition and synthesis run on a remote CrispASR server, so the audio you submit is sent there for processing. Text embeddings for search still run locally in your browser.';

  @override
  String get aiTransparencyAcknowledge => 'I understand';

  @override
  String get historySearchSemanticTooltip => 'Semantic search (active)';

  @override
  String get historySearchSubstringTooltip =>
      'Substring search (tap for semantic)';

  @override
  String get historyCompareButton => 'Compare…';

  @override
  String get historyCompareNoOtherEntries => 'No other entries to compare with';

  @override
  String get historyComparePickerTitle => 'Compare with…';

  @override
  String get menuCompareModels => 'Compare models';

  @override
  String get menuSubtitleOverlay => 'Subtitle overlay';

  @override
  String get advancedTagSegmentLanguages => 'Tag segment languages';

  @override
  String get advancedTagSegmentLanguagesSubtitle =>
      'Detect language per segment (multilingual)';

  @override
  String get exportObsidian => 'Obsidian';

  @override
  String get exportNotion => 'Notion';

  @override
  String get exportLogseq => 'Logseq';

  @override
  String get exportYouTubeChapters => 'YouTube chapters';

  @override
  String get exportDetectChapters => 'Detect chapters';

  @override
  String get exportPodcastChapters => 'Podcast chapters (JSON)';

  @override
  String get compareModelsNeedSecond => 'Download a second model to compare';

  @override
  String get compareModelsPickerTitle => 'Compare with model…';

  @override
  String compareModelsRunning(String modelA, String modelB) {
    return 'Running A/B: $modelA vs $modelB…';
  }

  @override
  String compareModelsFailed(String error) {
    return 'A/B test failed: $error';
  }

  @override
  String get settingsWatchFolder => 'Watch folder';

  @override
  String get settingsWatchFolderAutoTranscribe => 'Auto-transcribe new files';

  @override
  String settingsWatchFolderWatching(String path) {
    return 'Watching: $path';
  }

  @override
  String get settingsWatchFolderMonitorHint =>
      'Monitor a folder for new audio files';

  @override
  String get settingsWatchFolderPath => 'Watch folder path';

  @override
  String get settingsWatchFolderNotSet => 'Not set';

  @override
  String get settingsWatchFolderPickerTitle => 'Select folder to watch';

  @override
  String get settingsSpeakerVocab => 'Speaker vocabulary';

  @override
  String get settingsSpeakerVocabSubtitle => 'Per-speaker domain word lists';

  @override
  String get settingsSpeakerVocabDialogTitle => 'Speaker vocabulary';

  @override
  String settingsSpeakerVocabAddTermTitle(String name) {
    return 'Add term for $name';
  }

  @override
  String get settingsSpeakerVocabAddTermHint => 'Domain word or phrase';

  @override
  String get settingsSpeakerVocabNoSpeakers =>
      'No enrolled speakers. Enrol speakers first in the Speaker Management screen.';

  @override
  String get add => 'Add';

  @override
  String get synthLexiconSectionTitle => 'Pronunciation lexicon';

  @override
  String get synthLexiconAddTitle => 'Add pronunciation';

  @override
  String get synthLexiconAddEntryTooltip => 'Add entry';

  @override
  String get synthLexiconWordLabel => 'Word';

  @override
  String get synthLexiconWordHint => 'e.g. CrispASR';

  @override
  String get synthLexiconPronunciationLabel => 'Pronunciation';

  @override
  String get synthLexiconPronunciationHint => 'e.g. Crisp A S R';

  @override
  String get synthLexiconIpaLabel => 'IPA notation';

  @override
  String get synthLexiconEmpty =>
      'No entries. Add word → pronunciation mappings.';

  @override
  String get outputSegmentEditedTooltip => 'Edited';

  @override
  String get subtitleExitOverlayTooltip => 'Exit overlay';

  @override
  String get subtitleSmallerTextTooltip => 'Smaller text';

  @override
  String get subtitleLargerTextTooltip => 'Larger text';

  @override
  String get subtitleTogglePositionTooltip => 'Toggle position';

  @override
  String get subtitleToggleBackgroundTooltip => 'Toggle background';

  @override
  String get subtitleWaitingForTranscription => 'Waiting for transcription…';

  @override
  String get compareTranscriptsTitle => 'Compare Transcripts';

  @override
  String get compareLeftFallback => 'Left';

  @override
  String get compareRightFallback => 'Right';

  @override
  String get compareLeftWords => 'Left words';

  @override
  String get compareRightWords => 'Right words';

  @override
  String get compareSimilarity => 'Similarity';

  @override
  String get abTestNeedSecondModel => 'Download a second model to compare';

  @override
  String get abTestPickModel => 'Compare with model…';

  @override
  String abTestRunning(String modelA, String modelB) {
    return 'Running A/B: $modelA vs $modelB…';
  }

  @override
  String abTestFailed(String error) {
    return 'A/B test failed: $error';
  }

  @override
  String get subtitleOverlayExitTooltip => 'Exit overlay';

  @override
  String get subtitleOverlaySmallerText => 'Smaller text';

  @override
  String get subtitleOverlayLargerText => 'Larger text';

  @override
  String get subtitleOverlayTogglePosition => 'Toggle position';

  @override
  String get subtitleOverlayToggleBackground => 'Toggle background';

  @override
  String get subtitleOverlayWaiting => 'Waiting for transcription…';

  @override
  String get outputNoTranscriptionYet => 'No transcription yet';

  @override
  String get outputSelectAudioFile =>
      'Select an audio file and start transcription';

  @override
  String get outputNoResultsFound => 'No results found';

  @override
  String get outputTryDifferentSearch => 'Try a different search term';

  @override
  String get outputEdited => 'Edited';

  @override
  String get outputLidModelNeeded =>
      'Download a text language-ID model (CLD3, GlotLID, or FastText LID-176) to detect the language.';

  @override
  String get outputLidModelsButton => 'Models';

  @override
  String get outputLidFailed => 'Couldn\'t detect the language.';

  @override
  String outputLidDetected(String code, String pct, String model) {
    return 'Detected language: $code ($pct%) [$model]';
  }

  @override
  String get outputTagSegment => 'Tag segment';

  @override
  String get dialogCancel => 'Cancel';

  @override
  String get dialogAdd => 'Add';

  @override
  String get dialogApply => 'Apply';

  @override
  String get settingsAllFilesAccessNeeded => '\"All files access\" needed';

  @override
  String get settingsAllFilesAccessExplanation =>
      'Picking a folder outside the app sandbox needs Android\'s \"All files access\" permission. Tap \"Open Settings\", enable \"All files access\" for CrisperWeaver, then come back. After uninstalling and reinstalling the app, the grant is reset by Android and must be re-enabled.';

  @override
  String get settingsOpenSettings => 'Open Settings';

  @override
  String get settingsAllFilesAccessDenied =>
      '\"All files access\" denied — using sandbox dir instead.';

  @override
  String get fingerprintDedupTitle => 'Already transcribed';

  @override
  String get fingerprintDedupBody =>
      'This file has already been transcribed. Transcribe again?';

  @override
  String get fingerprintDedupTranscribeAgain => 'Transcribe again';
}
