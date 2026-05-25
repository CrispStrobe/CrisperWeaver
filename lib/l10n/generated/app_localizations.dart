import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'CrisperWeaver'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Audio transcription with speaker diarization'**
  String get appTagline;

  /// No description provided for @menuHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get menuHistory;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

  /// No description provided for @menuModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get menuModels;

  /// No description provided for @menuSynthesize.
  ///
  /// In en, this message translates to:
  /// **'Synthesize speech'**
  String get menuSynthesize;

  /// No description provided for @menuTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate text'**
  String get menuTranslate;

  /// No description provided for @menuLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get menuLogs;

  /// No description provided for @menuAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get menuAbout;

  /// No description provided for @menuOpenMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get menuOpenMore;

  /// No description provided for @tabInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get tabInput;

  /// No description provided for @tabRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get tabRun;

  /// No description provided for @tabOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get tabOutput;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Transcribe'**
  String get navHome;

  /// No description provided for @engineReady.
  ///
  /// In en, this message translates to:
  /// **'Engine ready'**
  String get engineReady;

  /// No description provided for @engineStarting.
  ///
  /// In en, this message translates to:
  /// **'Engine starting…'**
  String get engineStarting;

  /// No description provided for @audioInput.
  ///
  /// In en, this message translates to:
  /// **'Audio input'**
  String get audioInput;

  /// No description provided for @noFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelected;

  /// No description provided for @browse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browse;

  /// No description provided for @urlInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Or enter audio URL'**
  String get urlInputLabel;

  /// No description provided for @urlInputHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/audio.mp3'**
  String get urlInputHint;

  /// No description provided for @advancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get advancedOptions;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get languageAuto;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @transcribe.
  ///
  /// In en, this message translates to:
  /// **'Transcribe'**
  String get transcribe;

  /// No description provided for @transcribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get transcribing;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @transcriptionOutput.
  ///
  /// In en, this message translates to:
  /// **'Transcription output'**
  String get transcriptionOutput;

  /// No description provided for @noTranscriptionYet.
  ///
  /// In en, this message translates to:
  /// **'No transcription yet'**
  String get noTranscriptionYet;

  /// No description provided for @noTranscriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Select an audio file and start transcription'**
  String get noTranscriptionHint;

  /// No description provided for @searchTranscription.
  ///
  /// In en, this message translates to:
  /// **'Search transcription…'**
  String get searchTranscription;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @noResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term'**
  String get noResultsHint;

  /// No description provided for @tabSegments.
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get tabSegments;

  /// No description provided for @tabFullText.
  ///
  /// In en, this message translates to:
  /// **'Full Text'**
  String get tabFullText;

  /// No description provided for @sharePlain.
  ///
  /// In en, this message translates to:
  /// **'Share plain text'**
  String get sharePlain;

  /// No description provided for @copyClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get copyClipboard;

  /// No description provided for @saveAsTxt.
  ///
  /// In en, this message translates to:
  /// **'Save as .txt'**
  String get saveAsTxt;

  /// No description provided for @saveAsSrt.
  ///
  /// In en, this message translates to:
  /// **'Save as .srt'**
  String get saveAsSrt;

  /// No description provided for @saveAsVtt.
  ///
  /// In en, this message translates to:
  /// **'Save as .vtt'**
  String get saveAsVtt;

  /// No description provided for @saveAsJson.
  ///
  /// In en, this message translates to:
  /// **'Save as .json'**
  String get saveAsJson;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @perfRtf.
  ///
  /// In en, this message translates to:
  /// **'RTF'**
  String get perfRtf;

  /// No description provided for @perfAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get perfAudio;

  /// No description provided for @perfWall.
  ///
  /// In en, this message translates to:
  /// **'Wall'**
  String get perfWall;

  /// No description provided for @perfWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get perfWords;

  /// No description provided for @perfWps.
  ///
  /// In en, this message translates to:
  /// **'WPS'**
  String get perfWps;

  /// No description provided for @perfEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get perfEngine;

  /// No description provided for @perfModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get perfModel;

  /// No description provided for @perfFasterThanRealtime.
  ///
  /// In en, this message translates to:
  /// **'faster than real-time'**
  String get perfFasterThanRealtime;

  /// No description provided for @perfSlowerThanRealtime.
  ///
  /// In en, this message translates to:
  /// **'slower than real-time'**
  String get perfSlowerThanRealtime;

  /// No description provided for @diarizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Speaker diarization'**
  String get diarizationTitle;

  /// No description provided for @diarizationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Identify different speakers in audio recordings'**
  String get diarizationSubtitle;

  /// No description provided for @diarizationModel.
  ///
  /// In en, this message translates to:
  /// **'Diarization model'**
  String get diarizationModel;

  /// No description provided for @minSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Min. speakers'**
  String get minSpeakers;

  /// No description provided for @maxSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Max. speakers'**
  String get maxSpeakers;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsAppLanguage;

  /// No description provided for @settingsInterfaceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get settingsInterfaceLanguage;

  /// No description provided for @settingsSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsSystemDefault;

  /// No description provided for @settingsEngineSection.
  ///
  /// In en, this message translates to:
  /// **'Transcription engine'**
  String get settingsEngineSection;

  /// No description provided for @settingsEnginePreferred.
  ///
  /// In en, this message translates to:
  /// **'Preferred engine'**
  String get settingsEnginePreferred;

  /// No description provided for @settingsSelectEngine.
  ///
  /// In en, this message translates to:
  /// **'Select engine'**
  String get settingsSelectEngine;

  /// No description provided for @settingsEngineSwitched.
  ///
  /// In en, this message translates to:
  /// **'Switched to {engine}'**
  String settingsEngineSwitched(String engine);

  /// No description provided for @settingsEngineSwitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Engine switch failed'**
  String get settingsEngineSwitchFailed;

  /// No description provided for @settingsAudioQualityCurrent.
  ///
  /// In en, this message translates to:
  /// **'Recording quality: {percent}%'**
  String settingsAudioQualityCurrent(int percent);

  /// No description provided for @settingsCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared successfully'**
  String get settingsCacheCleared;

  /// No description provided for @settingsHfToken.
  ///
  /// In en, this message translates to:
  /// **'HuggingFace API token'**
  String get settingsHfToken;

  /// No description provided for @settingsHfTokenNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set (required for gated models)'**
  String get settingsHfTokenNotSet;

  /// No description provided for @settingsModelsDir.
  ///
  /// In en, this message translates to:
  /// **'Models directory'**
  String get settingsModelsDir;

  /// No description provided for @settingsModelsDirDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (in app sandbox)'**
  String get settingsModelsDirDefault;

  /// No description provided for @settingsModelsDirPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick models directory'**
  String get settingsModelsDirPickTitle;

  /// No description provided for @settingsModelsDirCurrentDefault.
  ///
  /// In en, this message translates to:
  /// **'Currently using the default app-sandbox path. Pick a custom directory to share GGUFs with other tools (e.g. an external drive).'**
  String get settingsModelsDirCurrentDefault;

  /// No description provided for @settingsModelsDirCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current: {path}'**
  String settingsModelsDirCurrent(String path);

  /// No description provided for @settingsModelsDirPick.
  ///
  /// In en, this message translates to:
  /// **'Pick…'**
  String get settingsModelsDirPick;

  /// No description provided for @settingsModelsDirReset.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get settingsModelsDirReset;

  /// No description provided for @settingsModelsDirSet.
  ///
  /// In en, this message translates to:
  /// **'Models directory set to {path}'**
  String settingsModelsDirSet(String path);

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @languageDe.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageDe;

  /// No description provided for @languageEs.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageEs;

  /// No description provided for @languageFr.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get languageFr;

  /// No description provided for @languageIt.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get languageIt;

  /// No description provided for @languagePt.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get languagePt;

  /// No description provided for @languageZh.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageZh;

  /// No description provided for @languageJa.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get languageJa;

  /// No description provided for @languageKo.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get languageKo;

  /// No description provided for @languageRu.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get languageRu;

  /// No description provided for @modelSize.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String modelSize(String size);

  /// No description provided for @modelDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {name}?'**
  String modelDeleteConfirm(String name);

  /// No description provided for @historyCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get historyCopy;

  /// No description provided for @historyExportSrt.
  ///
  /// In en, this message translates to:
  /// **'Export SRT'**
  String get historyExportSrt;

  /// No description provided for @historyExportTxt.
  ///
  /// In en, this message translates to:
  /// **'Export TXT'**
  String get historyExportTxt;

  /// No description provided for @historyExportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get historyExportJson;

  /// No description provided for @historyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get historyDelete;

  /// No description provided for @historyFailedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load history: {error}'**
  String historyFailedToLoad(String error);

  /// No description provided for @historySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved {path}'**
  String historySaved(String path);

  /// No description provided for @historyExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String historyExportFailed(String error);

  /// No description provided for @recorderDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get recorderDeleteTitle;

  /// No description provided for @recorderDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this recording?'**
  String get recorderDeleteBody;

  /// No description provided for @recorderQueuedForTranscription.
  ///
  /// In en, this message translates to:
  /// **'Recording queued for transcription.'**
  String get recorderQueuedForTranscription;

  /// No description provided for @recorderStream.
  ///
  /// In en, this message translates to:
  /// **'Stream'**
  String get recorderStream;

  /// No description provided for @recorderStreamTooltip.
  ///
  /// In en, this message translates to:
  /// **'Live mic transcribe (Whisper sliding window). Partial text appears as you speak.'**
  String get recorderStreamTooltip;

  /// No description provided for @recorderSystemAudioTooltip.
  ///
  /// In en, this message translates to:
  /// **'Capture system audio (Zoom call, browser tab, podcast app) and transcribe live. macOS 13+ only; first use prompts for Screen Recording permission.'**
  String get recorderSystemAudioTooltip;

  /// No description provided for @recorderSystemAudioPermission.
  ///
  /// In en, this message translates to:
  /// **'Screen Recording permission denied. Open System Settings → Privacy & Security → Screen Recording and tick CrisperWeaver, then try again.'**
  String get recorderSystemAudioPermission;

  /// No description provided for @recorderSystemAudioUnsupported.
  ///
  /// In en, this message translates to:
  /// **'System audio capture is not yet supported on this platform. Tracked in PLAN.md §5.1.1.'**
  String get recorderSystemAudioUnsupported;

  /// No description provided for @outputShowTimestamps.
  ///
  /// In en, this message translates to:
  /// **'Show timestamps'**
  String get outputShowTimestamps;

  /// No description provided for @outputShowSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Show speakers'**
  String get outputShowSpeakers;

  /// No description provided for @outputShowConfidence.
  ///
  /// In en, this message translates to:
  /// **'Show confidence'**
  String get outputShowConfidence;

  /// No description provided for @outputCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get outputCopyAll;

  /// No description provided for @outputExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get outputExport;

  /// No description provided for @outputPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get outputPlay;

  /// No description provided for @outputCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get outputCopy;

  /// No description provided for @outputEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get outputEdit;

  /// No description provided for @outputPlaySegment.
  ///
  /// In en, this message translates to:
  /// **'Play segment'**
  String get outputPlaySegment;

  /// No description provided for @outputCopyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get outputCopyText;

  /// No description provided for @outputEditSegment.
  ///
  /// In en, this message translates to:
  /// **'Edit segment'**
  String get outputEditSegment;

  /// No description provided for @outputEditNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Segment editing not yet implemented'**
  String get outputEditNotImplemented;

  /// No description provided for @outputEditAltSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Alternative candidates'**
  String get outputEditAltSuggestions;

  /// No description provided for @outputEditAltSuggestionsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a word to swap it for a runner-up Whisper picked at that step. Uses the alternative-candidate slider in Advanced Options.'**
  String get outputEditAltSuggestionsHint;

  /// No description provided for @outputEditAltPickTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pick an alternative candidate for this word'**
  String get outputEditAltPickTooltip;

  /// No description provided for @outputRenameSpeakerTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename speaker'**
  String get outputRenameSpeakerTitle;

  /// No description provided for @outputRenameSpeakerOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original label: {original}'**
  String outputRenameSpeakerOriginal(String original);

  /// No description provided for @outputRenameSpeakerReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to original'**
  String get outputRenameSpeakerReset;

  /// No description provided for @outputExportNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Export functionality not yet implemented'**
  String get outputExportNotImplemented;

  /// No description provided for @outputSegmentCopied.
  ///
  /// In en, this message translates to:
  /// **'Segment copied to clipboard'**
  String get outputSegmentCopied;

  /// No description provided for @outputAllCopied.
  ///
  /// In en, this message translates to:
  /// **'All transcription copied to clipboard'**
  String get outputAllCopied;

  /// No description provided for @outputPlayingSegment.
  ///
  /// In en, this message translates to:
  /// **'Playing segment: {time}'**
  String outputPlayingSegment(String time);

  /// No description provided for @settingsHfTokenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Required for gated or private repositories.'**
  String get settingsHfTokenSubtitle;

  /// No description provided for @settingsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get settingsLoading;

  /// No description provided for @transcribeLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get transcribeLanguageLabel;

  /// No description provided for @transcribeStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting download: {model}'**
  String transcribeStarting(String model);

  /// No description provided for @transcribeUnsupportedFile.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file type: {name}'**
  String transcribeUnsupportedFile(String name);

  /// No description provided for @transcribeLoadedFile.
  ///
  /// In en, this message translates to:
  /// **'Loaded {name}'**
  String transcribeLoadedFile(String name);

  /// No description provided for @aboutEmail.
  ///
  /// In en, this message translates to:
  /// **'Email: {email}'**
  String aboutEmail(String email);

  /// No description provided for @aboutPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone: {phone}'**
  String aboutPhone(String phone);

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @settingsTranscription.
  ///
  /// In en, this message translates to:
  /// **'Transcription'**
  String get settingsTranscription;

  /// No description provided for @settingsDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Default model'**
  String get settingsDefaultModel;

  /// No description provided for @settingsDefaultLanguage.
  ///
  /// In en, this message translates to:
  /// **'Default language'**
  String get settingsDefaultLanguage;

  /// No description provided for @settingsAutoDetectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect language'**
  String get settingsAutoDetectLanguage;

  /// No description provided for @settingsAutoDetectLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically detect audio language'**
  String get settingsAutoDetectLanguageSubtitle;

  /// No description provided for @settingsWordTimestamps.
  ///
  /// In en, this message translates to:
  /// **'Word timestamps'**
  String get settingsWordTimestamps;

  /// No description provided for @settingsWordTimestampsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Generate timestamps for individual words'**
  String get settingsWordTimestampsSubtitle;

  /// No description provided for @settingsAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get settingsAudio;

  /// No description provided for @settingsAudioQuality.
  ///
  /// In en, this message translates to:
  /// **'Audio quality'**
  String get settingsAudioQuality;

  /// No description provided for @settingsKeepAudioFiles.
  ///
  /// In en, this message translates to:
  /// **'Keep audio files'**
  String get settingsKeepAudioFiles;

  /// No description provided for @settingsKeepAudioFilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep downloaded / recorded audio files after transcription'**
  String get settingsKeepAudioFilesSubtitle;

  /// No description provided for @settingsDiarization.
  ///
  /// In en, this message translates to:
  /// **'Speaker diarization'**
  String get settingsDiarization;

  /// No description provided for @settingsEnableDiarizationByDefault.
  ///
  /// In en, this message translates to:
  /// **'Enable by default'**
  String get settingsEnableDiarizationByDefault;

  /// No description provided for @settingsEnableDiarizationByDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically enable diarization for new transcriptions'**
  String get settingsEnableDiarizationByDefaultSubtitle;

  /// No description provided for @settingsStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsStorage;

  /// No description provided for @settingsClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get settingsClearCache;

  /// No description provided for @settingsClearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clear temporary files and cache'**
  String get settingsClearCacheSubtitle;

  /// No description provided for @settingsManageModels.
  ///
  /// In en, this message translates to:
  /// **'Manage models'**
  String get settingsManageModels;

  /// No description provided for @settingsManageModelsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download, update, or delete transcription models'**
  String get settingsManageModelsSubtitle;

  /// No description provided for @settingsStorageBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Storage breakdown'**
  String get settingsStorageBreakdown;

  /// No description provided for @settingsStorageBreakdownSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See per-backend disk usage and free up space'**
  String get settingsStorageBreakdownSubtitle;

  /// No description provided for @storageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage breakdown'**
  String get storageTitle;

  /// No description provided for @storageRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get storageRefresh;

  /// No description provided for @storageEmpty.
  ///
  /// In en, this message translates to:
  /// **'No model files on disk yet.'**
  String get storageEmpty;

  /// No description provided for @storageTotalUsed.
  ///
  /// In en, this message translates to:
  /// **'Total on disk'**
  String get storageTotalUsed;

  /// No description provided for @storageBackendCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 backend} other{{count} backends}}'**
  String storageBackendCount(int count);

  /// No description provided for @storageFilesCount.
  ///
  /// In en, this message translates to:
  /// **'{size} • {count, plural, one{1 file} other{{count} files}}'**
  String storageFilesCount(String size, int count);

  /// No description provided for @storageDeleteAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete all models for this backend'**
  String get storageDeleteAllTooltip;

  /// No description provided for @storageDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all {backend} models?'**
  String storageDeleteTitle(String backend);

  /// No description provided for @storageDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This will free {size} across {count, plural, one{1 file} other{{count} files}} and cannot be undone.'**
  String storageDeleteMessage(String size, int count);

  /// No description provided for @storageDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get storageDeleteConfirm;

  /// No description provided for @storageDeletedSnack.
  ///
  /// In en, this message translates to:
  /// **'Freed {size}'**
  String storageDeletedSnack(String size);

  /// No description provided for @settingsDebugging.
  ///
  /// In en, this message translates to:
  /// **'Debugging & development'**
  String get settingsDebugging;

  /// No description provided for @settingsLogLevel.
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get settingsLogLevel;

  /// No description provided for @settingsLogLevelCurrent.
  ///
  /// In en, this message translates to:
  /// **'Currently {level}'**
  String settingsLogLevelCurrent(String level);

  /// No description provided for @settingsMirrorLogs.
  ///
  /// In en, this message translates to:
  /// **'Mirror logs to file'**
  String get settingsMirrorLogs;

  /// No description provided for @settingsMirrorLogsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Writes to logs/session.log in the app documents directory'**
  String get settingsMirrorLogsSubtitle;

  /// No description provided for @settingsSkipChecksum.
  ///
  /// In en, this message translates to:
  /// **'Skip checksum verification'**
  String get settingsSkipChecksum;

  /// No description provided for @settingsSkipChecksumSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Accept downloaded models even if SHA-1 does not match'**
  String get settingsSkipChecksumSubtitle;

  /// No description provided for @settingsGroupBatchByBackend.
  ///
  /// In en, this message translates to:
  /// **'Group batch by backend'**
  String get settingsGroupBatchByBackend;

  /// No description provided for @settingsGroupBatchByBackendSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder queued files so consecutive jobs reuse the same model session'**
  String get settingsGroupBatchByBackendSubtitle;

  /// No description provided for @settingsMaxConcurrent.
  ///
  /// In en, this message translates to:
  /// **'Concurrent transcriptions'**
  String get settingsMaxConcurrent;

  /// No description provided for @settingsMaxConcurrentCurrent.
  ///
  /// In en, this message translates to:
  /// **'Concurrent transcriptions: {n}'**
  String settingsMaxConcurrentCurrent(int n);

  /// No description provided for @settingsMaxConcurrentSessions.
  ///
  /// In en, this message translates to:
  /// **'Parallel sessions'**
  String get settingsMaxConcurrentSessions;

  /// No description provided for @settingsMaxConcurrentSessionsCurrent.
  ///
  /// In en, this message translates to:
  /// **'Parallel sessions: {n}'**
  String settingsMaxConcurrentSessionsCurrent(int n);

  /// No description provided for @settingsMaxConcurrentSessionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'1 = single session (default). 2+ spins up N worker isolates each holding its own model copy in RAM. Cost is N × model size; pre-flight clamps down if it wouldn\'t fit on this device.'**
  String get settingsMaxConcurrentSessionsSubtitle;

  /// No description provided for @settingsMemoryProjection.
  ///
  /// In en, this message translates to:
  /// **'Projected RAM: {projected} of {total} (per-worker: {per})'**
  String settingsMemoryProjection(String projected, String total, String per);

  /// No description provided for @settingsMemoryProjectionClamped.
  ///
  /// In en, this message translates to:
  /// **'Clamped to {affordable} of {requested} workers — model is too big for available RAM'**
  String settingsMemoryProjectionClamped(int affordable, int requested);

  /// No description provided for @batchResumedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{Recovered 1 interrupted transcription} other{Recovered {n} interrupted transcriptions}} — hit Start to resume'**
  String batchResumedSnackbar(int n);

  /// No description provided for @settingsMaxConcurrentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'1 = serial (current behaviour). 2+ pre-decodes the next file\'s audio in a worker isolate while the current file is being transcribed — extra parallelism without extra model copies in RAM.'**
  String get settingsMaxConcurrentSubtitle;

  /// No description provided for @settingsOpenLogViewer.
  ///
  /// In en, this message translates to:
  /// **'Open log viewer'**
  String get settingsOpenLogViewer;

  /// No description provided for @settingsSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Speakers'**
  String get settingsSpeakers;

  /// No description provided for @settingsSpeakersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enrol voices for automatic speaker labels in diarisation.'**
  String get settingsSpeakersSubtitle;

  /// No description provided for @speakersTitle.
  ///
  /// In en, this message translates to:
  /// **'Speakers'**
  String get speakersTitle;

  /// No description provided for @speakersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No speakers enrolled yet. Tap + to add one.'**
  String get speakersEmpty;

  /// No description provided for @speakersPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Voice profiles are stored on-device only. Nothing is uploaded.'**
  String get speakersPrivacyNote;

  /// No description provided for @speakersDownloadModelHint.
  ///
  /// In en, this message translates to:
  /// **'Download the TitaNet model from Model Management before enrolling.'**
  String get speakersDownloadModelHint;

  /// No description provided for @speakersAdd.
  ///
  /// In en, this message translates to:
  /// **'Add speaker'**
  String get speakersAdd;

  /// No description provided for @speakersDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete enrolled speaker?'**
  String get speakersDeleteTitle;

  /// No description provided for @speakersDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s voice profile will be removed from this device.'**
  String speakersDeleteBody(String name);

  /// No description provided for @speakersDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete profile.'**
  String get speakersDeleteFailed;

  /// No description provided for @speakersEnrolTitle.
  ///
  /// In en, this message translates to:
  /// **'Enrol speaker'**
  String get speakersEnrolTitle;

  /// No description provided for @speakersSourceRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get speakersSourceRecord;

  /// No description provided for @speakersSourceFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get speakersSourceFile;

  /// No description provided for @speakersName.
  ///
  /// In en, this message translates to:
  /// **'Speaker name'**
  String get speakersName;

  /// No description provided for @speakersNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get speakersNameRequired;

  /// No description provided for @speakersNameTaken.
  ///
  /// In en, this message translates to:
  /// **'A speaker with this name is already enrolled.'**
  String get speakersNameTaken;

  /// No description provided for @speakersNoSample.
  ///
  /// In en, this message translates to:
  /// **'Record or pick an audio sample first.'**
  String get speakersNoSample;

  /// No description provided for @speakersEnrolButton.
  ///
  /// In en, this message translates to:
  /// **'Enrol'**
  String get speakersEnrolButton;

  /// No description provided for @speakersEnrolFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not enrol — try a clearer sample.'**
  String get speakersEnrolFailed;

  /// No description provided for @speakersRecord.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get speakersRecord;

  /// No description provided for @speakersRecordStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get speakersRecordStop;

  /// No description provided for @speakersRecordHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to record a {seconds} s sample of this person speaking.'**
  String speakersRecordHint(int seconds);

  /// No description provided for @speakersRecordingCountdown.
  ///
  /// In en, this message translates to:
  /// **'Recording… {seconds} s left'**
  String speakersRecordingCountdown(int seconds);

  /// No description provided for @speakersRecordingDone.
  ///
  /// In en, this message translates to:
  /// **'Captured {seconds} s of audio.'**
  String speakersRecordingDone(int seconds);

  /// No description provided for @speakersRecordNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission was denied.'**
  String get speakersRecordNoPermission;

  /// No description provided for @speakersPickHint.
  ///
  /// In en, this message translates to:
  /// **'Pick any audio file with a clear sample of this person speaking.'**
  String get speakersPickHint;

  /// No description provided for @speakersPickButton.
  ///
  /// In en, this message translates to:
  /// **'Choose audio file'**
  String get speakersPickButton;

  /// No description provided for @settingsSystemInfo.
  ///
  /// In en, this message translates to:
  /// **'System information'**
  String get settingsSystemInfo;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsAboutCrisperWeaver.
  ///
  /// In en, this message translates to:
  /// **'About CrisperWeaver'**
  String get settingsAboutCrisperWeaver;

  /// No description provided for @settingsAboutCrisperWeaverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Author, contact, disclaimer, licenses'**
  String get settingsAboutCrisperWeaverSubtitle;

  /// No description provided for @settingsHfTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Hugging Face API Token'**
  String get settingsHfTokenTitle;

  /// No description provided for @settingsHfTokenSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get settingsHfTokenSave;

  /// No description provided for @settingsHfTokenCancel.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get settingsHfTokenCancel;

  /// No description provided for @transcriptionNoModelsFound.
  ///
  /// In en, this message translates to:
  /// **'No models found'**
  String get transcriptionNoModelsFound;

  /// No description provided for @transcriptionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get transcriptionRetry;

  /// No description provided for @transcriptionLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String transcriptionLoadFailed(String error);

  /// No description provided for @transcriptionSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved {path}'**
  String transcriptionSavedTo(String path);

  /// No description provided for @transcriptionSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String transcriptionSaveFailed(String error);

  /// No description provided for @transcriptionCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get transcriptionCopiedToClipboard;

  /// No description provided for @transcriptionShareSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Share or save'**
  String get transcriptionShareSheetTitle;

  /// No description provided for @transcriptionSharePlainText.
  ///
  /// In en, this message translates to:
  /// **'Share plain text'**
  String get transcriptionSharePlainText;

  /// No description provided for @transcriptionCopyToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get transcriptionCopyToClipboard;

  /// No description provided for @transcriptionSaveAsTxt.
  ///
  /// In en, this message translates to:
  /// **'Save as TXT'**
  String get transcriptionSaveAsTxt;

  /// No description provided for @transcriptionSaveAsSrt.
  ///
  /// In en, this message translates to:
  /// **'Save as SRT'**
  String get transcriptionSaveAsSrt;

  /// No description provided for @transcriptionSaveAsVtt.
  ///
  /// In en, this message translates to:
  /// **'Save as VTT'**
  String get transcriptionSaveAsVtt;

  /// No description provided for @transcriptionSaveAsJson.
  ///
  /// In en, this message translates to:
  /// **'Save as JSON'**
  String get transcriptionSaveAsJson;

  /// No description provided for @transcriptionDownloadModel.
  ///
  /// In en, this message translates to:
  /// **'Download Model'**
  String get transcriptionDownloadModel;

  /// No description provided for @transcriptionDownload.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD'**
  String get transcriptionDownload;

  /// No description provided for @advancedBestOfSingle.
  ///
  /// In en, this message translates to:
  /// **'Best-of-N: single decode (1)'**
  String get advancedBestOfSingle;

  /// No description provided for @advancedBestOfCurrent.
  ///
  /// In en, this message translates to:
  /// **'Best-of-N: {n} decodes'**
  String advancedBestOfCurrent(int n);

  /// No description provided for @advancedBestOfHelper.
  ///
  /// In en, this message translates to:
  /// **'1 = single decode (default). >1 runs N independent decodes and picks the highest-scoring result. Whisper consumes this internally; other backends loop externally and pick the highest-mean-confidence transcript. Cost is N× per-call decode time.'**
  String get advancedBestOfHelper;

  /// No description provided for @advancedTemperatureGreedy.
  ///
  /// In en, this message translates to:
  /// **'Decoder temperature: greedy (0.00)'**
  String get advancedTemperatureGreedy;

  /// No description provided for @advancedTemperatureCurrent.
  ///
  /// In en, this message translates to:
  /// **'Decoder temperature: {value}'**
  String advancedTemperatureCurrent(String value);

  /// No description provided for @advancedTemperatureHelper.
  ///
  /// In en, this message translates to:
  /// **'0.00 = greedy / reproducible. > 0 = stochastic sampling — useful when greedy decoding hallucinates a repetition. Whisper has its own internal fallback ladder; this affects sampling backends (canary, cohere, parakeet, moonshine).'**
  String get advancedTemperatureHelper;

  /// No description provided for @downloadModelPrompt.
  ///
  /// In en, this message translates to:
  /// **'The model \"{name}\" is not yet downloaded. Would you like to download it now (~{size})?'**
  String downloadModelPrompt(String name, String size);

  /// No description provided for @tooltipDeleteRecording.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get tooltipDeleteRecording;

  /// No description provided for @tooltipUseForTranscription.
  ///
  /// In en, this message translates to:
  /// **'Use for transcription'**
  String get tooltipUseForTranscription;

  /// No description provided for @tooltipModelSelectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Model selection help'**
  String get tooltipModelSelectionHelp;

  /// No description provided for @tooltipDownloadModel.
  ///
  /// In en, this message translates to:
  /// **'Download model'**
  String get tooltipDownloadModel;

  /// No description provided for @tooltipDisplayLevel.
  ///
  /// In en, this message translates to:
  /// **'Display level'**
  String get tooltipDisplayLevel;

  /// No description provided for @tooltipPauseAutoScroll.
  ///
  /// In en, this message translates to:
  /// **'Pause auto-scroll'**
  String get tooltipPauseAutoScroll;

  /// No description provided for @tooltipResumeAutoScroll.
  ///
  /// In en, this message translates to:
  /// **'Resume auto-scroll'**
  String get tooltipResumeAutoScroll;

  /// No description provided for @labelApiToken.
  ///
  /// In en, this message translates to:
  /// **'API Token'**
  String get labelApiToken;

  /// No description provided for @streamingRequiresWhisper.
  ///
  /// In en, this message translates to:
  /// **'Streaming requires the Whisper engine. Switch backend in Settings.'**
  String get streamingRequiresWhisper;

  /// No description provided for @streamingMicUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone unavailable for streaming.'**
  String get streamingMicUnavailable;

  /// No description provided for @streamingEngineNoSession.
  ///
  /// In en, this message translates to:
  /// **'Engine returned no streaming session.'**
  String get streamingEngineNoSession;

  /// No description provided for @playbackFailed.
  ///
  /// In en, this message translates to:
  /// **'Playback failed: {error}'**
  String playbackFailed(String error);

  /// No description provided for @synthesizeFailed.
  ///
  /// In en, this message translates to:
  /// **'Synthesize failed: {error}'**
  String synthesizeFailed(String error);

  /// No description provided for @logsShowLevel.
  ///
  /// In en, this message translates to:
  /// **'Show {level} and above'**
  String logsShowLevel(String level);

  /// No description provided for @logsCopyVisible.
  ///
  /// In en, this message translates to:
  /// **'Copy visible'**
  String get logsCopyVisible;

  /// No description provided for @logsCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get logsCopyAll;

  /// No description provided for @logsExport.
  ///
  /// In en, this message translates to:
  /// **'Export to file'**
  String get logsExport;

  /// No description provided for @logsShare.
  ///
  /// In en, this message translates to:
  /// **'Share as file'**
  String get logsShare;

  /// No description provided for @diarizationAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get diarizationAuto;

  /// No description provided for @diarizationModelSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Diarization Model Selection'**
  String get diarizationModelSelectionTitle;

  /// No description provided for @aboutServiceProvider.
  ///
  /// In en, this message translates to:
  /// **'Service Provider'**
  String get aboutServiceProvider;

  /// No description provided for @aboutContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get aboutContact;

  /// No description provided for @aboutPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get aboutPrivacy;

  /// No description provided for @aboutDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Disclaimer'**
  String get aboutDisclaimer;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutOpenSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get aboutOpenSourceLicenses;

  /// No description provided for @aboutPrivacyText.
  ///
  /// In en, this message translates to:
  /// **'CrisperWeaver processes all audio locally on your device. No audio data, transcripts, or recordings are sent to any server. Model downloads fetch GGUF weights directly from HuggingFace over HTTPS; nothing else leaves the device.'**
  String get aboutPrivacyText;

  /// No description provided for @aboutDisclaimerText.
  ///
  /// In en, this message translates to:
  /// **'This software is provided \"as is\", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose and noninfringement. In no event shall the authors be liable for any claim, damages or other liability arising from, out of or in connection with the software or its use.'**
  String get aboutDisclaimerText;

  /// No description provided for @aboutLicenseText.
  ///
  /// In en, this message translates to:
  /// **'CrisperWeaver is free software, licensed under the GNU Affero General Public License v3.0 (AGPL-3.0). You may redistribute and modify it under the terms of that license. In particular, if you run a modified version of CrisperWeaver as a network service, you must make your source code available to its users.'**
  String get aboutLicenseText;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Transcription history'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No transcriptions yet'**
  String get historyEmpty;

  /// No description provided for @historyEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Run a transcription and it will show up here.'**
  String get historyEmptyHint;

  /// No description provided for @historyRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get historyRefresh;

  /// No description provided for @historyClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get historyClearAll;

  /// No description provided for @historySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search title or transcript…'**
  String get historySearchHint;

  /// No description provided for @historySearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No history entries match \"{query}\"'**
  String historySearchNoResults(String query);

  /// No description provided for @historySearchMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{matched, plural, =1{1 of {total} matched} other{{matched} of {total} matched}}'**
  String historySearchMatchCount(int matched, int total);

  /// No description provided for @historyClearAllPrompt.
  ///
  /// In en, this message translates to:
  /// **'Remove every saved transcription from this device. This cannot be undone.'**
  String get historyClearAllPrompt;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @logsTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logsTitle;

  /// No description provided for @logsFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter by message, tag, or error…'**
  String get logsFilterHint;

  /// No description provided for @modelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Model management'**
  String get modelsTitle;

  /// No description provided for @modelsNoneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No models available'**
  String get modelsNoneAvailable;

  /// No description provided for @modelsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get modelsRetry;

  /// No description provided for @modelsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get modelsDownload;

  /// No description provided for @modelsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete model'**
  String get modelsDelete;

  /// No description provided for @modelsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get modelsDownloaded;

  /// No description provided for @modelsNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get modelsNotDownloaded;

  /// No description provided for @modelsDownloadingPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String modelsDownloadingPercent(String percent);

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @settingsDefaultBackend.
  ///
  /// In en, this message translates to:
  /// **'Default backend'**
  String get settingsDefaultBackend;

  /// No description provided for @settingsSelectBackend.
  ///
  /// In en, this message translates to:
  /// **'Select default backend'**
  String get settingsSelectBackend;

  /// No description provided for @settingsSelectModel.
  ///
  /// In en, this message translates to:
  /// **'Select default model ({backend})'**
  String settingsSelectModel(String backend);

  /// No description provided for @settingsSelectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select default language'**
  String get settingsSelectLanguage;

  /// No description provided for @settingsSelectInterfaceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select interface language'**
  String get settingsSelectInterfaceLanguage;

  /// No description provided for @settingsNoModelsForBackend.
  ///
  /// In en, this message translates to:
  /// **'No models known for backend \"{backend}\". Use the model manager → cloud-download icon to probe HuggingFace.'**
  String settingsNoModelsForBackend(String backend);

  /// No description provided for @modelFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter models (name / quant)'**
  String get modelFilterHint;

  /// No description provided for @modelAnyBackend.
  ///
  /// In en, this message translates to:
  /// **'Any backend'**
  String get modelAnyBackend;

  /// No description provided for @modelNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No models match this filter.'**
  String get modelNoMatch;

  /// No description provided for @modelsRefreshFromHf.
  ///
  /// In en, this message translates to:
  /// **'Refresh quants from HuggingFace'**
  String get modelsRefreshFromHf;

  /// No description provided for @modelsReloadLocal.
  ///
  /// In en, this message translates to:
  /// **'Reload local state'**
  String get modelsReloadLocal;

  /// No description provided for @modelsProbedCountZero.
  ///
  /// In en, this message translates to:
  /// **'No new quants discovered on HuggingFace.'**
  String get modelsProbedCountZero;

  /// No description provided for @modelsProbedCount.
  ///
  /// In en, this message translates to:
  /// **'Discovered {count} new quant variant{plural}.'**
  String modelsProbedCount(int count, String plural);

  /// No description provided for @batchQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch queue'**
  String get batchQueueTitle;

  /// No description provided for @batchQueueSummary.
  ///
  /// In en, this message translates to:
  /// **'{queued} queued · {running} running · {done} done · {errored} failed'**
  String batchQueueSummary(int queued, int running, int done, int errored);

  /// No description provided for @batchClearCompleted.
  ///
  /// In en, this message translates to:
  /// **'Clear done'**
  String get batchClearCompleted;

  /// No description provided for @batchRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get batchRemove;

  /// No description provided for @batchEnqueueAdded.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) added to queue.'**
  String batchEnqueueAdded(int count);

  /// No description provided for @batchRunAll.
  ///
  /// In en, this message translates to:
  /// **'Transcribe all'**
  String get batchRunAll;

  /// No description provided for @batchStop.
  ///
  /// In en, this message translates to:
  /// **'Stop batch'**
  String get batchStop;

  /// No description provided for @batchQueueDropHint.
  ///
  /// In en, this message translates to:
  /// **'Drop audio files here to queue them'**
  String get batchQueueDropHint;

  /// No description provided for @advancedSection.
  ///
  /// In en, this message translates to:
  /// **'Advanced decoding'**
  String get advancedSection;

  /// No description provided for @advancedVadTrim.
  ///
  /// In en, this message translates to:
  /// **'Trim silence (VAD)'**
  String get advancedVadTrim;

  /// No description provided for @advancedVadTrimSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Skip leading and trailing silence via Silero VAD. Faster on meetings / long recordings with silent padding.'**
  String get advancedVadTrimSubtitle;

  /// No description provided for @advancedTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate to English'**
  String get advancedTranslate;

  /// No description provided for @advancedTranslateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Whisper only — forces output to English regardless of source.'**
  String get advancedTranslateSubtitle;

  /// No description provided for @advancedBeamSearch.
  ///
  /// In en, this message translates to:
  /// **'Beam search'**
  String get advancedBeamSearch;

  /// No description provided for @advancedBeamSearchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Slower, usually more accurate. Default is greedy.'**
  String get advancedBeamSearchSubtitle;

  /// No description provided for @advancedInitialPrompt.
  ///
  /// In en, this message translates to:
  /// **'Initial prompt (vocabulary / context)'**
  String get advancedInitialPrompt;

  /// No description provided for @advancedInitialPromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. \"CrispASR, Flutter, Riverpod, Sprecher-Unterscheidung\"'**
  String get advancedInitialPromptHint;

  /// No description provided for @advancedRestorePunctuation.
  ///
  /// In en, this message translates to:
  /// **'Restore punctuation (FireRedPunc)'**
  String get advancedRestorePunctuation;

  /// No description provided for @advancedRestorePunctuationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Capitalize and punctuate raw output. Useful for CTC backends (wav2vec2, fastconformer-ctc, firered-asr). Requires fireredpunc-*.gguf in Model Management.'**
  String get advancedRestorePunctuationSubtitle;

  /// No description provided for @advancedSourceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Source language (override autodetect)'**
  String get advancedSourceLanguage;

  /// No description provided for @advancedSourceLanguageAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto / use main picker'**
  String get advancedSourceLanguageAuto;

  /// No description provided for @advancedSourceLanguageHelper.
  ///
  /// In en, this message translates to:
  /// **'Pin the source language when whisper\'s autodetect is unreliable on noisy audio. Empty = fall back to the main language dropdown / autodetect.'**
  String get advancedSourceLanguageHelper;

  /// No description provided for @advancedTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Translate to (target language)'**
  String get advancedTargetLanguage;

  /// No description provided for @advancedTargetLanguageNone.
  ///
  /// In en, this message translates to:
  /// **'No translation (verbatim)'**
  String get advancedTargetLanguageNone;

  /// No description provided for @advancedTargetLanguageHelper.
  ///
  /// In en, this message translates to:
  /// **'Visible only for translation-capable backends (Canary, Voxtral, Qwen3, Cohere, Whisper). Leave at \"No translation\" for verbatim transcription.'**
  String get advancedTargetLanguageHelper;

  /// No description provided for @advancedAskPrompt.
  ///
  /// In en, this message translates to:
  /// **'Ask the audio (Q&A mode)'**
  String get advancedAskPrompt;

  /// No description provided for @advancedAskPromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. \"Summarize\" or \"What\'s the speaker\'s tone?\"'**
  String get advancedAskPromptHint;

  /// No description provided for @advancedAskPromptHelper.
  ///
  /// In en, this message translates to:
  /// **'Voxtral / Qwen3-ASR only. When set, the LLM ANSWERS your question instead of producing a verbatim transcript. Leave empty for normal transcription.'**
  String get advancedAskPromptHelper;

  /// No description provided for @editAudioOpen.
  ///
  /// In en, this message translates to:
  /// **'Open in audio editor'**
  String get editAudioOpen;

  /// No description provided for @editAudioTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit audio'**
  String get editAudioTitle;

  /// No description provided for @editAudioLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t decode audio: {error}'**
  String editAudioLoadFailed(String error);

  /// No description provided for @editAudioSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save edited audio as…'**
  String get editAudioSaveAs;

  /// No description provided for @editAudioSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String editAudioSavedTo(String path);

  /// No description provided for @editAudioTrim.
  ///
  /// In en, this message translates to:
  /// **'Trim'**
  String get editAudioTrim;

  /// No description provided for @editAudioCut.
  ///
  /// In en, this message translates to:
  /// **'Cut middle'**
  String get editAudioCut;

  /// No description provided for @editAudioAddSplitMark.
  ///
  /// In en, this message translates to:
  /// **'Add split mark'**
  String get editAudioAddSplitMark;

  /// No description provided for @editAudioRunSplit.
  ///
  /// In en, this message translates to:
  /// **'Split into {n} files'**
  String editAudioRunSplit(int n);

  /// No description provided for @editAudioClearMarks.
  ///
  /// In en, this message translates to:
  /// **'Clear marks'**
  String get editAudioClearMarks;

  /// No description provided for @editAudioClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get editAudioClearSelection;

  /// No description provided for @editAudioNeedSelection.
  ///
  /// In en, this message translates to:
  /// **'Drag on the waveform to select a region first.'**
  String get editAudioNeedSelection;

  /// No description provided for @editAudioNeedSplitMarks.
  ///
  /// In en, this message translates to:
  /// **'Add at least one split mark first.'**
  String get editAudioNeedSplitMarks;

  /// No description provided for @editAudioSelectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Selection: {start} – {end}'**
  String editAudioSelectionLabel(String start, String end);

  /// No description provided for @editAudioSplitSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved {n} files.'**
  String editAudioSplitSaved(int n);

  /// No description provided for @editAudioHowto.
  ///
  /// In en, this message translates to:
  /// **'Tap waveform to seek. Drag to select a region. Use Trim to keep [start, end]; Cut middle to remove [start, end] and splice the rest; Add split mark to drop a split point at the current playhead, then Split to write one WAV per region.'**
  String get editAudioHowto;

  /// No description provided for @editAudioToggleTranscriptShow.
  ///
  /// In en, this message translates to:
  /// **'Show transcript'**
  String get editAudioToggleTranscriptShow;

  /// No description provided for @editAudioToggleTranscriptHide.
  ///
  /// In en, this message translates to:
  /// **'Hide transcript'**
  String get editAudioToggleTranscriptHide;

  /// No description provided for @editAudioTranscriptHeading.
  ///
  /// In en, this message translates to:
  /// **'Transcript'**
  String get editAudioTranscriptHeading;

  /// No description provided for @editAudioTranscriptEmpty.
  ///
  /// In en, this message translates to:
  /// **'No transcript yet. Transcribe the audio first, then return here to use it for navigation and cut-region markers.'**
  String get editAudioTranscriptEmpty;

  /// No description provided for @editAudioTranscriptSegmentTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a line to seek the playhead. Long-press a line for cut / trim options.'**
  String get editAudioTranscriptSegmentTapHint;

  /// No description provided for @editAudioMarkSegmentForCut.
  ///
  /// In en, this message translates to:
  /// **'Mark segment for split'**
  String get editAudioMarkSegmentForCut;

  /// No description provided for @editAudioTrimToSegment.
  ///
  /// In en, this message translates to:
  /// **'Trim to this segment'**
  String get editAudioTrimToSegment;

  /// No description provided for @editAudioSelectSegment.
  ///
  /// In en, this message translates to:
  /// **'Select this segment'**
  String get editAudioSelectSegment;

  /// No description provided for @editAudioSegmentMarkedForCut.
  ///
  /// In en, this message translates to:
  /// **'Marked split point at {time}.'**
  String editAudioSegmentMarkedForCut(String time);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @presetsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presetsTooltip;

  /// No description provided for @presetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presetsTitle;

  /// No description provided for @presetsHelp.
  ///
  /// In en, this message translates to:
  /// **'Save the current backend, model, language and Advanced Options as a named preset. Apply later to restore all settings in one tap.'**
  String get presetsHelp;

  /// No description provided for @presetsSaveCurrent.
  ///
  /// In en, this message translates to:
  /// **'Save current settings as preset'**
  String get presetsSaveCurrent;

  /// No description provided for @presetsSaveCurrentTitle.
  ///
  /// In en, this message translates to:
  /// **'Save preset'**
  String get presetsSaveCurrentTitle;

  /// No description provided for @presetsNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get presetsNameLabel;

  /// No description provided for @presetsNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Podcast prep, Voice memos, Multilingual interview'**
  String get presetsNameHint;

  /// No description provided for @presetsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No presets yet. Save the current settings to start.'**
  String get presetsEmpty;

  /// No description provided for @presetsApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get presetsApply;

  /// No description provided for @presetsApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied preset \"{name}\".'**
  String presetsApplied(String name);

  /// No description provided for @presetsRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename preset'**
  String get presetsRenameTitle;

  /// No description provided for @presetsRenameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get presetsRenameTooltip;

  /// No description provided for @presetsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete preset?'**
  String get presetsDeleteTitle;

  /// No description provided for @presetsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete preset \"{name}\"? This can\'t be undone.'**
  String presetsDeleteConfirm(String name);

  /// No description provided for @presetsDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get presetsDeleteTooltip;

  /// No description provided for @outputSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize…'**
  String get outputSummarize;

  /// No description provided for @outputSummarizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Summarize transcript'**
  String get outputSummarizeTitle;

  /// No description provided for @outputSummarizeHelp.
  ///
  /// In en, this message translates to:
  /// **'Sends the transcript to {model} and asks for a structured summary. Output is Markdown-formatted bullet lists.'**
  String outputSummarizeHelp(String model);

  /// No description provided for @outputSummarizeUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'No cloud LLM endpoint configured. Open Settings → Cloud LLM cleanup to add one — the same endpoint is used for both cleanup and summarisation.'**
  String get outputSummarizeUnconfigured;

  /// No description provided for @outputSummarizeKindActionItems.
  ///
  /// In en, this message translates to:
  /// **'Action items'**
  String get outputSummarizeKindActionItems;

  /// No description provided for @outputSummarizeKindKeyTopics.
  ///
  /// In en, this message translates to:
  /// **'Key topics'**
  String get outputSummarizeKindKeyTopics;

  /// No description provided for @outputSummarizeKindDecisions.
  ///
  /// In en, this message translates to:
  /// **'Decisions'**
  String get outputSummarizeKindDecisions;

  /// No description provided for @outputSummarizeRun.
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get outputSummarizeRun;

  /// No description provided for @outputSummarizeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pick sections and run.'**
  String get outputSummarizeEmpty;

  /// No description provided for @outputSummarizeNothing.
  ///
  /// In en, this message translates to:
  /// **'The model returned no items for the selected sections.'**
  String get outputSummarizeNothing;

  /// No description provided for @outputCleanup.
  ///
  /// In en, this message translates to:
  /// **'Tidy transcript…'**
  String get outputCleanup;

  /// No description provided for @outputCleanupTitle.
  ///
  /// In en, this message translates to:
  /// **'Tidy transcript'**
  String get outputCleanupTitle;

  /// No description provided for @outputCleanupHelp.
  ///
  /// In en, this message translates to:
  /// **'Deterministic cleanup of common ASR artifacts. Pick what to apply, preview the result, then Apply to all.'**
  String get outputCleanupHelp;

  /// No description provided for @outputCleanupRemoveFillers.
  ///
  /// In en, this message translates to:
  /// **'Remove filler words (um, uh, ah, …)'**
  String get outputCleanupRemoveFillers;

  /// No description provided for @outputCleanupCollapseRepeats.
  ///
  /// In en, this message translates to:
  /// **'Collapse repeated words (the the → the)'**
  String get outputCleanupCollapseRepeats;

  /// No description provided for @outputCleanupSentenceCase.
  ///
  /// In en, this message translates to:
  /// **'Capitalise sentence starts'**
  String get outputCleanupSentenceCase;

  /// No description provided for @outputCleanupFixPunctuation.
  ///
  /// In en, this message translates to:
  /// **'Fix punctuation (… , doubled commas, stray dots)'**
  String get outputCleanupFixPunctuation;

  /// No description provided for @outputCleanupNormalizeWhitespace.
  ///
  /// In en, this message translates to:
  /// **'Normalise whitespace'**
  String get outputCleanupNormalizeWhitespace;

  /// No description provided for @outputCleanupStripAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Strip annotation tags'**
  String get outputCleanupStripAnnotations;

  /// No description provided for @outputCleanupStripAnnotationsHelp.
  ///
  /// In en, this message translates to:
  /// **'Removes [laughter], (applause), <noise>. Off by default — useful for accessibility.'**
  String get outputCleanupStripAnnotationsHelp;

  /// No description provided for @outputCleanupCustomFillers.
  ///
  /// In en, this message translates to:
  /// **'Custom filler words'**
  String get outputCleanupCustomFillers;

  /// No description provided for @outputCleanupCustomFillersHint.
  ///
  /// In en, this message translates to:
  /// **'Comma- or space-separated, e.g. like, basically, you know'**
  String get outputCleanupCustomFillersHint;

  /// No description provided for @outputCleanupPreviewHeading.
  ///
  /// In en, this message translates to:
  /// **'Preview (first 3 segments)'**
  String get outputCleanupPreviewHeading;

  /// No description provided for @outputCleanupPreviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'No segments to preview.'**
  String get outputCleanupPreviewEmpty;

  /// No description provided for @outputCleanupApply.
  ///
  /// In en, this message translates to:
  /// **'Apply to all'**
  String get outputCleanupApply;

  /// No description provided for @outputCleanupLlmPass.
  ///
  /// In en, this message translates to:
  /// **'Also run LLM pass (cloud)'**
  String get outputCleanupLlmPass;

  /// No description provided for @outputCleanupLlmPassHelp.
  ///
  /// In en, this message translates to:
  /// **'After the deterministic pass, send each segment to {model} for a context-aware cleanup. Slower; uses your configured API key.'**
  String outputCleanupLlmPassHelp(String model);

  /// No description provided for @outputCleanupLlmPassUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'Configure a cloud LLM endpoint in Settings → Cloud LLM cleanup to enable this.'**
  String get outputCleanupLlmPassUnconfigured;

  /// No description provided for @outputCleanupLlmRunning.
  ///
  /// In en, this message translates to:
  /// **'Running LLM cleanup pass…'**
  String get outputCleanupLlmRunning;

  /// No description provided for @outputCleanupLlmMode.
  ///
  /// In en, this message translates to:
  /// **'LLM pass'**
  String get outputCleanupLlmMode;

  /// No description provided for @outputCleanupLlmModeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get outputCleanupLlmModeOff;

  /// No description provided for @outputCleanupLlmModeCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get outputCleanupLlmModeCloud;

  /// No description provided for @outputCleanupLlmModeLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get outputCleanupLlmModeLocal;

  /// No description provided for @outputCleanupLlmModeCloudHelp.
  ///
  /// In en, this message translates to:
  /// **'After the deterministic pass, send each segment to {model} (cloud, BYOK). Slower; uses your configured API key.'**
  String outputCleanupLlmModeCloudHelp(String model);

  /// No description provided for @outputCleanupLlmModeLocalHelp.
  ///
  /// In en, this message translates to:
  /// **'After the deterministic pass, run each segment through {model} on this device. No network, no API key; first run loads the model into memory.'**
  String outputCleanupLlmModeLocalHelp(String model);

  /// No description provided for @outputCleanupLlmModeCloudUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'Configure a cloud LLM endpoint in Settings → Cloud LLM cleanup to enable this.'**
  String get outputCleanupLlmModeCloudUnconfigured;

  /// No description provided for @outputCleanupLlmModeLocalUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'Point at a GGUF chat model in Settings → Local LLM cleanup to enable this.'**
  String get outputCleanupLlmModeLocalUnconfigured;

  /// No description provided for @settingsLocalLlmCleanup.
  ///
  /// In en, this message translates to:
  /// **'Local LLM cleanup (on-device)'**
  String get settingsLocalLlmCleanup;

  /// No description provided for @settingsLocalLlmCleanupOff.
  ///
  /// In en, this message translates to:
  /// **'Off (point at a GGUF chat model to enable)'**
  String get settingsLocalLlmCleanupOff;

  /// No description provided for @settingsLocalLlmHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Loads a GGUF chat model on this device and runs every Tidy / Summarize pass against it. No network, no API key. Needs ~2–8 GB of free RAM depending on model size; Metal / CUDA acceleration is used when available.'**
  String get settingsLocalLlmHelp;

  /// No description provided for @settingsLocalLlmModelPath.
  ///
  /// In en, this message translates to:
  /// **'Chat model file (GGUF)'**
  String get settingsLocalLlmModelPath;

  /// No description provided for @settingsLocalLlmModelPathEmpty.
  ///
  /// In en, this message translates to:
  /// **'No model selected'**
  String get settingsLocalLlmModelPathEmpty;

  /// No description provided for @settingsLocalLlmModelPick.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get settingsLocalLlmModelPick;

  /// No description provided for @settingsLocalLlmModelClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsLocalLlmModelClear;

  /// No description provided for @settingsLocalLlmAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced parameters'**
  String get settingsLocalLlmAdvanced;

  /// No description provided for @settingsLocalLlmNGpuLayers.
  ///
  /// In en, this message translates to:
  /// **'GPU layers: {n}'**
  String settingsLocalLlmNGpuLayers(int n);

  /// No description provided for @settingsLocalLlmNGpuLayersAll.
  ///
  /// In en, this message translates to:
  /// **'GPU layers: all'**
  String get settingsLocalLlmNGpuLayersAll;

  /// No description provided for @settingsLocalLlmNGpuLayersHelp.
  ///
  /// In en, this message translates to:
  /// **'-1 = offload every layer to the GPU (default; Metal on macOS / CUDA on Linux+Windows when available). 0 = CPU only. Positive values are partial offload for low-VRAM machines.'**
  String get settingsLocalLlmNGpuLayersHelp;

  /// No description provided for @settingsLocalLlmNCtx.
  ///
  /// In en, this message translates to:
  /// **'Context window (tokens): {n}'**
  String settingsLocalLlmNCtx(int n);

  /// No description provided for @settingsLocalLlmNCtxDefault.
  ///
  /// In en, this message translates to:
  /// **'Context window: model default'**
  String get settingsLocalLlmNCtxDefault;

  /// No description provided for @settingsLocalLlmNCtxHelp.
  ///
  /// In en, this message translates to:
  /// **'0 keeps the GGUF\'s baked-in default. Raise this when summarising long transcripts; lower it on memory-constrained hosts.'**
  String get settingsLocalLlmNCtxHelp;

  /// No description provided for @settingsLocalLlmNThreads.
  ///
  /// In en, this message translates to:
  /// **'CPU threads: {n}'**
  String settingsLocalLlmNThreads(int n);

  /// No description provided for @settingsLocalLlmNThreadsAuto.
  ///
  /// In en, this message translates to:
  /// **'CPU threads: auto'**
  String get settingsLocalLlmNThreadsAuto;

  /// No description provided for @settingsLocalLlmMaxTokens.
  ///
  /// In en, this message translates to:
  /// **'Max output tokens per call: {n}'**
  String settingsLocalLlmMaxTokens(int n);

  /// No description provided for @settingsLocalLlmTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature: {t}'**
  String settingsLocalLlmTemperature(String t);

  /// No description provided for @settingsLocalLlmUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This libcrispasr build doesn\'t expose the chat ABI — needs CrispASR 0.7.0 or newer.'**
  String get settingsLocalLlmUnsupported;

  /// No description provided for @outputCleanupLocalLlmRunning.
  ///
  /// In en, this message translates to:
  /// **'Running local LLM cleanup pass…'**
  String get outputCleanupLocalLlmRunning;

  /// No description provided for @outputCleanupLocalLlmLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading local LLM (first run may take a few seconds)…'**
  String get outputCleanupLocalLlmLoading;

  /// No description provided for @settingsHotkey.
  ///
  /// In en, this message translates to:
  /// **'Global hotkey'**
  String get settingsHotkey;

  /// No description provided for @settingsHotkeyOff.
  ///
  /// In en, this message translates to:
  /// **'Off (configure a combo + behaviour to enable)'**
  String get settingsHotkeyOff;

  /// No description provided for @settingsHotkeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Register a system-wide keyboard shortcut so you can start / stop recording without bringing the app forward. Desktop only — iOS / Android don\'t expose a global-shortcut surface.'**
  String get settingsHotkeyHelp;

  /// No description provided for @settingsHotkeyEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable global hotkey'**
  String get settingsHotkeyEnable;

  /// No description provided for @settingsHotkeyCombo.
  ///
  /// In en, this message translates to:
  /// **'Key combination'**
  String get settingsHotkeyCombo;

  /// No description provided for @settingsHotkeyBehavior.
  ///
  /// In en, this message translates to:
  /// **'Behaviour'**
  String get settingsHotkeyBehavior;

  /// No description provided for @settingsHotkeyActionPushToTalk.
  ///
  /// In en, this message translates to:
  /// **'Push to talk'**
  String get settingsHotkeyActionPushToTalk;

  /// No description provided for @settingsHotkeyActionPushToTalkHelp.
  ///
  /// In en, this message translates to:
  /// **'Hold to record, release to stop. Pairs well with combos that include a modifier (e.g. meta+shift+space).'**
  String get settingsHotkeyActionPushToTalkHelp;

  /// No description provided for @settingsHotkeyActionToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle'**
  String get settingsHotkeyActionToggle;

  /// No description provided for @settingsHotkeyActionToggleHelp.
  ///
  /// In en, this message translates to:
  /// **'Press once to start, press again to stop. Simpler mental model; doesn\'t require holding a modifier.'**
  String get settingsHotkeyActionToggleHelp;

  /// No description provided for @settingsHotkeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid combo \"{combo}\". Use modifier+modifier+key, e.g. meta+shift+space.'**
  String settingsHotkeyInvalid(String combo);

  /// No description provided for @settingsCloudLlmCleanup.
  ///
  /// In en, this message translates to:
  /// **'Cloud LLM cleanup (BYOK)'**
  String get settingsCloudLlmCleanup;

  /// No description provided for @settingsCloudLlmCleanupOff.
  ///
  /// In en, this message translates to:
  /// **'Off (paste an OpenAI-compatible URL + API key to enable)'**
  String get settingsCloudLlmCleanupOff;

  /// No description provided for @settingsCloudLlmHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Sends each segment to an OpenAI-compatible /v1/chat/completions endpoint for context-aware cleanup. Works against OpenAI, Anthropic via proxy, OpenRouter, Groq, a local llama-server, etc. Your key stays on this device.'**
  String get settingsCloudLlmHelp;

  /// No description provided for @settingsCloudLlmUrl.
  ///
  /// In en, this message translates to:
  /// **'API URL'**
  String get settingsCloudLlmUrl;

  /// No description provided for @settingsCloudLlmKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get settingsCloudLlmKey;

  /// No description provided for @settingsCloudLlmModel.
  ///
  /// In en, this message translates to:
  /// **'Model id'**
  String get settingsCloudLlmModel;

  /// No description provided for @settingsCloudLlmClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsCloudLlmClear;

  /// No description provided for @outputCleanupApplied.
  ///
  /// In en, this message translates to:
  /// **'Cleanup applied to {n} segment(s).'**
  String outputCleanupApplied(int n);

  /// No description provided for @outputEditSegmentInAudioEditor.
  ///
  /// In en, this message translates to:
  /// **'Edit this segment in audio editor'**
  String get outputEditSegmentInAudioEditor;

  /// No description provided for @outputMarkSegmentInAudioEditor.
  ///
  /// In en, this message translates to:
  /// **'Mark for split in audio editor'**
  String get outputMarkSegmentInAudioEditor;

  /// No description provided for @editAudioSegmentSelected.
  ///
  /// In en, this message translates to:
  /// **'Selection set: {start} – {end}.'**
  String editAudioSegmentSelected(String start, String end);

  /// No description provided for @advancedMaxLen.
  ///
  /// In en, this message translates to:
  /// **'Max tokens per segment: {n}'**
  String advancedMaxLen(int n);

  /// No description provided for @advancedMaxLenOff.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get advancedMaxLenOff;

  /// No description provided for @advancedMaxLenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Whisper-only soft cap. 0 = no cap (default). Pair with \"Split on word\" for SRT-friendly short subtitle lines.'**
  String get advancedMaxLenSubtitle;

  /// No description provided for @advancedSplitOnWord.
  ///
  /// In en, this message translates to:
  /// **'Split on word boundaries'**
  String get advancedSplitOnWord;

  /// No description provided for @advancedSplitOnWordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When the segment cap is hit, break on the next word boundary instead of mid-word. Yields more readable subtitle output.'**
  String get advancedSplitOnWordSubtitle;

  /// No description provided for @advancedVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Custom vocabulary'**
  String get advancedVocabulary;

  /// No description provided for @advancedVocabularyHint.
  ///
  /// In en, this message translates to:
  /// **'Type a term and press Enter (e.g. API, kubectl, Alice)'**
  String get advancedVocabularyHint;

  /// No description provided for @advancedVocabularyAdd.
  ///
  /// In en, this message translates to:
  /// **'Add term'**
  String get advancedVocabularyAdd;

  /// No description provided for @advancedVocabularyHelperPrompt.
  ///
  /// In en, this message translates to:
  /// **'Biases the decoder via Whisper\'s initial_prompt. Useful for brand names, acronyms, technical jargon and people\'s names that the model otherwise mishears.'**
  String get advancedVocabularyHelperPrompt;

  /// No description provided for @advancedVocabularyHelperAsk.
  ///
  /// In en, this message translates to:
  /// **'Biases the LLM by prepending these terms to its prompt. Combined with Q&A — your question still runs.'**
  String get advancedVocabularyHelperAsk;

  /// No description provided for @advancedVocabularyHelperUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The active backend is CTC-style and can\'t bias vocabulary at the decoder. Switch to Whisper / Moonshine / an LLM-backend (Voxtral, Qwen3, Granite, …) to enable.'**
  String get advancedVocabularyHelperUnsupported;

  /// No description provided for @voiceCloneOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clone a voice…'**
  String get voiceCloneOpenTooltip;

  /// No description provided for @voiceCloneTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice clone wizard'**
  String get voiceCloneTitle;

  /// No description provided for @voiceCloneStepCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get voiceCloneStepCapture;

  /// No description provided for @voiceCloneStepRefText.
  ///
  /// In en, this message translates to:
  /// **'Reference text'**
  String get voiceCloneStepRefText;

  /// No description provided for @voiceCloneStepHandoff.
  ///
  /// In en, this message translates to:
  /// **'Synthesize'**
  String get voiceCloneStepHandoff;

  /// No description provided for @voiceCloneCaptureHeading.
  ///
  /// In en, this message translates to:
  /// **'Capture a reference clip'**
  String get voiceCloneCaptureHeading;

  /// No description provided for @voiceCloneCaptureHelp.
  ///
  /// In en, this message translates to:
  /// **'Record about {seconds} seconds of clean speech, or pick an existing audio file. A single speaker with minimal background noise gives the best clone.'**
  String voiceCloneCaptureHelp(int seconds);

  /// No description provided for @voiceCloneCaptureNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission was denied. Grant it in your system settings and try again.'**
  String get voiceCloneCaptureNoPermission;

  /// No description provided for @voiceCloneRecord.
  ///
  /// In en, this message translates to:
  /// **'Record {seconds} s'**
  String voiceCloneRecord(int seconds);

  /// No description provided for @voiceClonePickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick file'**
  String get voiceClonePickFile;

  /// No description provided for @voiceCloneRecordingCountdown.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s remaining'**
  String voiceCloneRecordingCountdown(int seconds);

  /// No description provided for @voiceCloneRecordingStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get voiceCloneRecordingStop;

  /// No description provided for @voiceClonePreviewPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get voiceClonePreviewPlay;

  /// No description provided for @voiceClonePreviewPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get voiceClonePreviewPause;

  /// No description provided for @voiceCloneCaptureClear.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get voiceCloneCaptureClear;

  /// No description provided for @voiceCloneRefTextHeading.
  ///
  /// In en, this message translates to:
  /// **'What was said in the clip?'**
  String get voiceCloneRefTextHeading;

  /// No description provided for @voiceCloneRefTextHelp.
  ///
  /// In en, this message translates to:
  /// **'Some cloners (indextts, vibevoice) need a verbatim transcript of the reference clip for alignment. Others (chatterbox, qwen3-tts Base) clone from audio alone — leave this empty if your chosen backend doesn\'t need it.'**
  String get voiceCloneRefTextHelp;

  /// No description provided for @voiceCloneRefTextLabel.
  ///
  /// In en, this message translates to:
  /// **'Reference transcript'**
  String get voiceCloneRefTextLabel;

  /// No description provided for @voiceCloneRefTextHint.
  ///
  /// In en, this message translates to:
  /// **'Type what was said in the reference clip…'**
  String get voiceCloneRefTextHint;

  /// No description provided for @voiceCloneHandoffHeading.
  ///
  /// In en, this message translates to:
  /// **'Ready to synthesize'**
  String get voiceCloneHandoffHeading;

  /// No description provided for @voiceCloneHandoffHelp.
  ///
  /// In en, this message translates to:
  /// **'We\'ll open the Synthesize screen with the clip and reference text pre-populated. Pick a clone-capable model (chatterbox, indextts, qwen3-tts Base, vibevoice-1.5b), type the text you want spoken, and hit Synthesize.'**
  String get voiceCloneHandoffHelp;

  /// No description provided for @voiceCloneHandoffModelHint.
  ///
  /// In en, this message translates to:
  /// **'Tip: chatterbox / qwen3-tts Base clone from audio alone; indextts / vibevoice also use the reference transcript.'**
  String get voiceCloneHandoffModelHint;

  /// No description provided for @voiceCloneSummaryReference.
  ///
  /// In en, this message translates to:
  /// **'Reference clip'**
  String get voiceCloneSummaryReference;

  /// No description provided for @voiceCloneSummaryRefText.
  ///
  /// In en, this message translates to:
  /// **'Reference text'**
  String get voiceCloneSummaryRefText;

  /// No description provided for @voiceCloneSummaryRefTextEmpty.
  ///
  /// In en, this message translates to:
  /// **'(none — audio-only clone)'**
  String get voiceCloneSummaryRefTextEmpty;

  /// No description provided for @voiceCloneBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get voiceCloneBack;

  /// No description provided for @voiceCloneNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get voiceCloneNext;

  /// No description provided for @voiceCloneFinish.
  ///
  /// In en, this message translates to:
  /// **'Open in Synthesize'**
  String get voiceCloneFinish;

  /// No description provided for @synthTitle.
  ///
  /// In en, this message translates to:
  /// **'Synthesize'**
  String get synthTitle;

  /// No description provided for @synthModelLabel.
  ///
  /// In en, this message translates to:
  /// **'TTS model'**
  String get synthModelLabel;

  /// No description provided for @synthVoiceLabel.
  ///
  /// In en, this message translates to:
  /// **'Voice / voicepack'**
  String get synthVoiceLabel;

  /// No description provided for @synthCodecLabel.
  ///
  /// In en, this message translates to:
  /// **'Codec / tokenizer'**
  String get synthCodecLabel;

  /// No description provided for @synthTextHint.
  ///
  /// In en, this message translates to:
  /// **'Type text to synthesise…'**
  String get synthTextHint;

  /// No description provided for @synthRunButton.
  ///
  /// In en, this message translates to:
  /// **'Synthesize'**
  String get synthRunButton;

  /// No description provided for @synthPlayButton.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get synthPlayButton;

  /// No description provided for @synthStopButton.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get synthStopButton;

  /// No description provided for @synthShareButton.
  ///
  /// In en, this message translates to:
  /// **'Save / share WAV'**
  String get synthShareButton;

  /// No description provided for @synthNoTtsModelsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'No TTS models downloaded yet. Open Models → Models tab → switch to \"TTS\" to fetch one.'**
  String get synthNoTtsModelsDownloaded;

  /// No description provided for @synthOpenModelManagement.
  ///
  /// In en, this message translates to:
  /// **'Open Model Management'**
  String get synthOpenModelManagement;

  /// No description provided for @defaultModelNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Default model \"{modelId}\" isn\'t downloaded yet.'**
  String defaultModelNotDownloaded(String modelId);

  /// Shown at first launch / before the user has downloaded any model. Replaces defaultModelNotDownloaded when there is literally nothing to load.
  ///
  /// In en, this message translates to:
  /// **'No transcription model is downloaded yet — open Models to grab one.'**
  String get noModelsDownloadedYet;

  /// Shown when the OS returns a content:// URI we can't resolve to a real path (typical for Google Drive / OneDrive / Files that haven't been synced).
  ///
  /// In en, this message translates to:
  /// **'This file lives in cloud storage and can\'t be opened directly. Please copy it to local storage (Downloads / Files on this device) and try again.'**
  String get filePickerCloudFileUnsupported;

  /// No description provided for @filePickerFailed.
  ///
  /// In en, this message translates to:
  /// **'File picker failed: {error}'**
  String filePickerFailed(String error);

  /// No description provided for @openModels.
  ///
  /// In en, this message translates to:
  /// **'Open Models'**
  String get openModels;

  /// No description provided for @synthMissingDependency.
  ///
  /// In en, this message translates to:
  /// **'Missing required companion file: {name}'**
  String synthMissingDependency(String name);

  /// No description provided for @advancedVadBackend.
  ///
  /// In en, this message translates to:
  /// **'VAD backend'**
  String get advancedVadBackend;

  /// No description provided for @advancedVadBackendHelper.
  ///
  /// In en, this message translates to:
  /// **'Silero is bundled (~885 KB). FireRed / MarbleNet / Whisper-VAD need a Model Management download; missing files fall back to Silero.'**
  String get advancedVadBackendHelper;

  /// No description provided for @advancedVadBackendSilero.
  ///
  /// In en, this message translates to:
  /// **'Silero (bundled, default)'**
  String get advancedVadBackendSilero;

  /// No description provided for @advancedVadBackendFirered.
  ///
  /// In en, this message translates to:
  /// **'FireRedVAD (F1 97.57%, ~3 MB)'**
  String get advancedVadBackendFirered;

  /// No description provided for @advancedVadBackendMarblenet.
  ///
  /// In en, this message translates to:
  /// **'MarbleNet (small, multilingual)'**
  String get advancedVadBackendMarblenet;

  /// No description provided for @advancedVadBackendWhisperEncDec.
  ///
  /// In en, this message translates to:
  /// **'Whisper-VAD-EncDec (experimental EN)'**
  String get advancedVadBackendWhisperEncDec;

  /// No description provided for @advancedVadThreshold.
  ///
  /// In en, this message translates to:
  /// **'VAD threshold: {value}'**
  String advancedVadThreshold(String value);

  /// No description provided for @advancedVadThresholdHelper.
  ///
  /// In en, this message translates to:
  /// **'Higher = fewer / shorter speech regions detected. CrispASR default is 0.50.'**
  String get advancedVadThresholdHelper;

  /// No description provided for @advancedVadMinSpeech.
  ///
  /// In en, this message translates to:
  /// **'Min. speech duration: {ms} ms'**
  String advancedVadMinSpeech(int ms);

  /// No description provided for @advancedVadMinSpeechHelper.
  ///
  /// In en, this message translates to:
  /// **'Shortest voiced run kept as a speech segment.'**
  String get advancedVadMinSpeechHelper;

  /// No description provided for @advancedVadMinSilence.
  ///
  /// In en, this message translates to:
  /// **'Min. silence duration: {ms} ms'**
  String advancedVadMinSilence(int ms);

  /// No description provided for @advancedVadMinSilenceHelper.
  ///
  /// In en, this message translates to:
  /// **'Shortest silence that splits one segment from the next.'**
  String get advancedVadMinSilenceHelper;

  /// No description provided for @advancedVadSpeechPad.
  ///
  /// In en, this message translates to:
  /// **'Speech padding: {ms} ms'**
  String advancedVadSpeechPad(int ms);

  /// No description provided for @advancedVadSpeechPadHelper.
  ///
  /// In en, this message translates to:
  /// **'Extra context added on each side of every speech segment.'**
  String get advancedVadSpeechPadHelper;

  /// No description provided for @advancedLidMethod.
  ///
  /// In en, this message translates to:
  /// **'Language detection method'**
  String get advancedLidMethod;

  /// No description provided for @advancedLidMethodHelper.
  ///
  /// In en, this message translates to:
  /// **'Used when the model lacks native LID and you picked Auto. Whisper reuses any multilingual ggml-*.bin; Silero / Firered / Ecapa each need their own GGUF.'**
  String get advancedLidMethodHelper;

  /// No description provided for @advancedLidMethodWhisper.
  ///
  /// In en, this message translates to:
  /// **'Whisper encoder (reuses an existing model)'**
  String get advancedLidMethodWhisper;

  /// No description provided for @advancedLidMethodSilero.
  ///
  /// In en, this message translates to:
  /// **'Silero (95 languages, ~16 MB GGUF)'**
  String get advancedLidMethodSilero;

  /// No description provided for @advancedLidMethodFirered.
  ///
  /// In en, this message translates to:
  /// **'FireRed (120 languages, ~300 MB GGUF)'**
  String get advancedLidMethodFirered;

  /// No description provided for @advancedLidMethodEcapa.
  ///
  /// In en, this message translates to:
  /// **'ECAPA-TDNN (107 languages, ~42 MB GGUF)'**
  String get advancedLidMethodEcapa;

  /// No description provided for @advancedGrammarTitle.
  ///
  /// In en, this message translates to:
  /// **'GBNF grammar (Whisper only)'**
  String get advancedGrammarTitle;

  /// No description provided for @advancedGrammarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Force a structured output shape (JSON / SKU / phone numbers / …). Empty = no constraint.'**
  String get advancedGrammarSubtitle;

  /// No description provided for @advancedGrammarSubtitleActive.
  ///
  /// In en, this message translates to:
  /// **'Grammar active — output will be constrained to this GBNF.'**
  String get advancedGrammarSubtitleActive;

  /// No description provided for @advancedGrammarTextLabel.
  ///
  /// In en, this message translates to:
  /// **'GBNF source'**
  String get advancedGrammarTextLabel;

  /// No description provided for @advancedGrammarRootRule.
  ///
  /// In en, this message translates to:
  /// **'Root rule'**
  String get advancedGrammarRootRule;

  /// No description provided for @advancedGrammarRootRuleHelper.
  ///
  /// In en, this message translates to:
  /// **'Symbol name to start parsing from. The GBNF convention is \"root\".'**
  String get advancedGrammarRootRuleHelper;

  /// No description provided for @advancedGrammarPenalty.
  ///
  /// In en, this message translates to:
  /// **'Grammar penalty: {value}'**
  String advancedGrammarPenalty(String value);

  /// No description provided for @advancedGrammarPenaltyHelper.
  ///
  /// In en, this message translates to:
  /// **'Higher = harder constraint, lower = softer suggestion. Upstream default is 100; useful range is 50..200.'**
  String get advancedGrammarPenaltyHelper;

  /// No description provided for @advancedTranscribeWindowTitle.
  ///
  /// In en, this message translates to:
  /// **'Transcribe window (offset + duration)'**
  String get advancedTranscribeWindowTitle;

  /// No description provided for @advancedTranscribeWindowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Process only a [start, start+duration) slice of the audio. Empty / 0 = transcribe the whole file (default).'**
  String get advancedTranscribeWindowSubtitle;

  /// No description provided for @advancedTranscribeWindowSubtitleActive.
  ///
  /// In en, this message translates to:
  /// **'Active: {start}s..{end}s of the file. Timestamps remain absolute on output.'**
  String advancedTranscribeWindowSubtitleActive(String start, String end);

  /// No description provided for @advancedTranscribeWindowEndOfFile.
  ///
  /// In en, this message translates to:
  /// **'end-of-file'**
  String get advancedTranscribeWindowEndOfFile;

  /// No description provided for @advancedTranscribeWindowStart.
  ///
  /// In en, this message translates to:
  /// **'Start (seconds)'**
  String get advancedTranscribeWindowStart;

  /// No description provided for @advancedTranscribeWindowStartHelper.
  ///
  /// In en, this message translates to:
  /// **'Offset into the file. 0 = start.'**
  String get advancedTranscribeWindowStartHelper;

  /// No description provided for @advancedTranscribeWindowDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration (seconds)'**
  String get advancedTranscribeWindowDuration;

  /// No description provided for @advancedTranscribeWindowDurationHelper.
  ///
  /// In en, this message translates to:
  /// **'0 = transcribe until end-of-file.'**
  String get advancedTranscribeWindowDurationHelper;

  /// No description provided for @advancedFallbackThresholdsTitle.
  ///
  /// In en, this message translates to:
  /// **'Whisper decoder fallbacks'**
  String get advancedFallbackThresholdsTitle;

  /// No description provided for @advancedFallbackThresholdsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tune when the decoder retries at a higher temperature or treats audio as silence. Defaults match stock whisper.cpp.'**
  String get advancedFallbackThresholdsSubtitle;

  /// No description provided for @advancedFallbackThresholdsSubtitleActive.
  ///
  /// In en, this message translates to:
  /// **'Custom thresholds active — defaults are 2.4 / -1.0 / 0.6 / 0.2.'**
  String get advancedFallbackThresholdsSubtitleActive;

  /// No description provided for @advancedFallbackThresholdsReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get advancedFallbackThresholdsReset;

  /// No description provided for @advancedEntropyThold.
  ///
  /// In en, this message translates to:
  /// **'Entropy threshold: {value}'**
  String advancedEntropyThold(String value);

  /// No description provided for @advancedEntropyTholdHelper.
  ///
  /// In en, this message translates to:
  /// **'Per-token entropy that triggers a fallback pass. Default 2.4. Lower = stricter (more retries on hard audio); raise to suppress excessive retries.'**
  String get advancedEntropyTholdHelper;

  /// No description provided for @advancedLogprobThold.
  ///
  /// In en, this message translates to:
  /// **'Logprob threshold: {value}'**
  String advancedLogprobThold(String value);

  /// No description provided for @advancedLogprobTholdHelper.
  ///
  /// In en, this message translates to:
  /// **'Average log-probability cutoff that triggers a fallback pass. Default -1.0. More negative = more tolerant of noisy decoding.'**
  String get advancedLogprobTholdHelper;

  /// No description provided for @advancedNoSpeechThold.
  ///
  /// In en, this message translates to:
  /// **'No-speech threshold: {value}'**
  String advancedNoSpeechThold(String value);

  /// No description provided for @advancedNoSpeechTholdHelper.
  ///
  /// In en, this message translates to:
  /// **'Silence detector cutoff. Default 0.6. Higher = less aggressive silence gating (keeps faint speech).'**
  String get advancedNoSpeechTholdHelper;

  /// No description provided for @advancedTemperatureInc.
  ///
  /// In en, this message translates to:
  /// **'Temperature increment: {value}'**
  String advancedTemperatureInc(String value);

  /// No description provided for @advancedTemperatureIncDisabled.
  ///
  /// In en, this message translates to:
  /// **'Temperature increment: 0 (fallback disabled)'**
  String get advancedTemperatureIncDisabled;

  /// No description provided for @advancedTemperatureIncHelper.
  ///
  /// In en, this message translates to:
  /// **'Temperature step per fallback pass. Default 0.2. Set to 0 to disable the fallback loop entirely (= the CLI\'s --no-fallback).'**
  String get advancedTemperatureIncHelper;

  /// No description provided for @advancedWhisperDecodeExtrasTitle.
  ///
  /// In en, this message translates to:
  /// **'Whisper text suppression'**
  String get advancedWhisperDecodeExtrasTitle;

  /// No description provided for @advancedWhisperDecodeExtrasSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drop non-speech markers, suppress regex-matched tokens, or repeat the initial prompt on every decode window.'**
  String get advancedWhisperDecodeExtrasSubtitle;

  /// No description provided for @advancedWhisperDecodeExtrasSubtitleActive.
  ///
  /// In en, this message translates to:
  /// **'Custom suppression active — defaults are: keep all tokens / no regex / single-window prompt.'**
  String get advancedWhisperDecodeExtrasSubtitleActive;

  /// No description provided for @advancedSuppressNonSpeechTokens.
  ///
  /// In en, this message translates to:
  /// **'Drop non-speech tokens'**
  String get advancedSuppressNonSpeechTokens;

  /// No description provided for @advancedSuppressNonSpeechTokensHelper.
  ///
  /// In en, this message translates to:
  /// **'Strip [LAUGHTER] / [MUSIC] / [NOISE] markers whisper emits on top of the spoken words. Off by default.'**
  String get advancedSuppressNonSpeechTokensHelper;

  /// No description provided for @advancedSuppressTokensRegex.
  ///
  /// In en, this message translates to:
  /// **'Suppress regex (Posix)'**
  String get advancedSuppressTokensRegex;

  /// No description provided for @advancedSuppressTokensRegexHelper.
  ///
  /// In en, this message translates to:
  /// **'Tokens whose text matches this regex get dropped during decoding. Empty disables. Useful for purging hallucinated tokens or speaker-tag patterns.'**
  String get advancedSuppressTokensRegexHelper;

  /// No description provided for @advancedCarryInitialPrompt.
  ///
  /// In en, this message translates to:
  /// **'Carry initial prompt to every window'**
  String get advancedCarryInitialPrompt;

  /// No description provided for @advancedCarryInitialPromptHelper.
  ///
  /// In en, this message translates to:
  /// **'Repeat the initial prompt at the start of every decode window (not just the first). Strengthens vocabulary biasing on long audio at the cost of weakening previous-context conditioning.'**
  String get advancedCarryInitialPromptHelper;

  /// No description provided for @advancedEnhanceAudio.
  ///
  /// In en, this message translates to:
  /// **'Enhance audio (noise reduction)'**
  String get advancedEnhanceAudio;

  /// No description provided for @advancedEnhanceAudioHelper.
  ///
  /// In en, this message translates to:
  /// **'Runs an RNNoise pre-step on the audio before transcription. Reduces HVAC / fan / keyboard noise. Costs ~1× realtime on CPU; off by default.'**
  String get advancedEnhanceAudioHelper;

  /// No description provided for @settingsLocalLlmCatalogueTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested chat models'**
  String get settingsLocalLlmCatalogueTitle;

  /// No description provided for @settingsLocalLlmCatalogueHelp.
  ///
  /// In en, this message translates to:
  /// **'Tap a downloaded model to select it. Tap an undownloaded model to open Model Management and download it.'**
  String get settingsLocalLlmCatalogueHelp;

  /// No description provided for @settingsLocalLlmCatalogueManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get settingsLocalLlmCatalogueManage;

  /// No description provided for @settingsLocalLlmCatalogueDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded · {size}'**
  String settingsLocalLlmCatalogueDownloaded(String size);

  /// No description provided for @settingsLocalLlmCatalogueNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded · {size}'**
  String settingsLocalLlmCatalogueNotDownloaded(String size);

  /// No description provided for @settingsLocalLlmCatalogueDownload.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD'**
  String get settingsLocalLlmCatalogueDownload;

  /// No description provided for @modelsKindFilterChatLlm.
  ///
  /// In en, this message translates to:
  /// **'Chat LLM'**
  String get modelsKindFilterChatLlm;

  /// No description provided for @advancedDiarizeMethod.
  ///
  /// In en, this message translates to:
  /// **'Diarisation method'**
  String get advancedDiarizeMethod;

  /// No description provided for @advancedDiarizeMethodHelper.
  ///
  /// In en, this message translates to:
  /// **'Only takes effect when diarisation is enabled. vad-turns is mono-friendly; pyannote requires its segmentation GGUF; energy / xcorr need stereo audio.'**
  String get advancedDiarizeMethodHelper;

  /// No description provided for @advancedDiarizeVadTurns.
  ///
  /// In en, this message translates to:
  /// **'VAD turns (mono, no extra model)'**
  String get advancedDiarizeVadTurns;

  /// No description provided for @advancedDiarizePyannote.
  ///
  /// In en, this message translates to:
  /// **'Pyannote v3 (ML, needs GGUF)'**
  String get advancedDiarizePyannote;

  /// No description provided for @advancedDiarizeEnergy.
  ///
  /// In en, this message translates to:
  /// **'Stereo L/R energy'**
  String get advancedDiarizeEnergy;

  /// No description provided for @advancedDiarizeXcorr.
  ///
  /// In en, this message translates to:
  /// **'Stereo cross-correlation'**
  String get advancedDiarizeXcorr;

  /// No description provided for @advancedSpeakerRecognition.
  ///
  /// In en, this message translates to:
  /// **'Identify enrolled speakers'**
  String get advancedSpeakerRecognition;

  /// No description provided for @advancedSpeakerRecognitionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'After diarisation, match each speaker cluster against the on-device speaker DB (Settings → Speakers) and replace \'Speaker N\' with the enrolled name when confident. Requires the TitaNet GGUF.'**
  String get advancedSpeakerRecognitionSubtitle;

  /// No description provided for @advancedTdrz.
  ///
  /// In en, this message translates to:
  /// **'Tinydiarize speaker turns (Whisper only)'**
  String get advancedTdrz;

  /// No description provided for @advancedTdrzSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Insert [SPEAKER_TURN] markers via a Whisper .en.tdrz finetune. No-op on session backends.'**
  String get advancedTdrzSubtitle;

  /// No description provided for @advancedTokenTimestamps.
  ///
  /// In en, this message translates to:
  /// **'Token-level timestamps'**
  String get advancedTokenTimestamps;

  /// No description provided for @advancedTokenTimestampsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'DTW-aligned per-token timing. Slower than word timestamps; useful for fine-grained subtitle tooling.'**
  String get advancedTokenTimestampsSubtitle;

  /// No description provided for @advancedAltN.
  ///
  /// In en, this message translates to:
  /// **'Alternative candidates per word (Whisper only)'**
  String get advancedAltN;

  /// No description provided for @advancedAltNLabel.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =0{Off} other{Top {n}}}'**
  String advancedAltNLabel(int n);

  /// No description provided for @advancedAltNSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Capture the top-N runner-up tokens at each Whisper greedy step. Lets you tap an ambiguous word in the transcript editor and pick a competing candidate (kubectl / cubicle / …). 0 = off (default). Best with greedy decoding — beam search not supported. Pre-0.5.13 dylibs silently ignore.'**
  String get advancedAltNSubtitle;

  /// No description provided for @advancedPuncFamily.
  ///
  /// In en, this message translates to:
  /// **'Punctuation model'**
  String get advancedPuncFamily;

  /// No description provided for @advancedPuncFamilyHelper.
  ///
  /// In en, this message translates to:
  /// **'Visible only when Restore punctuation is on. Switch between FireRedPunc (ZH+EN) and fullstop-punc (EN/DE/FR/IT). Auto-fallback to whichever is downloaded.'**
  String get advancedPuncFamilyHelper;

  /// No description provided for @advancedPuncFamilyFirered.
  ///
  /// In en, this message translates to:
  /// **'FireRedPunc (Chinese + English)'**
  String get advancedPuncFamilyFirered;

  /// No description provided for @advancedPuncFamilyFullstop.
  ///
  /// In en, this message translates to:
  /// **'Fullstop-punc multilang (EN/DE/FR/IT)'**
  String get advancedPuncFamilyFullstop;

  /// No description provided for @transcriptionSaveAsCsv.
  ///
  /// In en, this message translates to:
  /// **'Save as CSV'**
  String get transcriptionSaveAsCsv;

  /// No description provided for @transcriptionSaveAsLrc.
  ///
  /// In en, this message translates to:
  /// **'Save as LRC (lyrics)'**
  String get transcriptionSaveAsLrc;

  /// No description provided for @transcriptionSaveAsWts.
  ///
  /// In en, this message translates to:
  /// **'Save as WTS (debug)'**
  String get transcriptionSaveAsWts;

  /// No description provided for @transcriptionSaveAsMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Save as Markdown'**
  String get transcriptionSaveAsMarkdown;

  /// No description provided for @transcriptionShareAudioAndTranscript.
  ///
  /// In en, this message translates to:
  /// **'Share audio + transcript'**
  String get transcriptionShareAudioAndTranscript;

  /// No description provided for @transcriptionShareAudioAndTranscriptHelp.
  ///
  /// In en, this message translates to:
  /// **'Sends the audio file and the SRT transcript as a single share — useful for archiving or handing off to a colleague.'**
  String get transcriptionShareAudioAndTranscriptHelp;

  /// No description provided for @transcriptionShareAudioMissing.
  ///
  /// In en, this message translates to:
  /// **'Select an audio file first to share both together.'**
  String get transcriptionShareAudioMissing;

  /// No description provided for @synthAdvancedSection.
  ///
  /// In en, this message translates to:
  /// **'Advanced synthesis'**
  String get synthAdvancedSection;

  /// No description provided for @synthRefText.
  ///
  /// In en, this message translates to:
  /// **'Reference transcript (voice cloning)'**
  String get synthRefText;

  /// No description provided for @synthRefTextHelper.
  ///
  /// In en, this message translates to:
  /// **'Required when pairing a WAV voice with qwen3-tts Base or vibevoice-1.5b for runtime cloning. Empty for baked GGUF voices.'**
  String get synthRefTextHelper;

  /// No description provided for @synthInstruct.
  ///
  /// In en, this message translates to:
  /// **'Voice description (qwen3-tts VoiceDesign only)'**
  String get synthInstruct;

  /// No description provided for @synthInstructHelper.
  ///
  /// In en, this message translates to:
  /// **'Natural-language description of the desired voice (\"warm female narrator, slight British accent\"). Silently ignored on every other backend.'**
  String get synthInstructHelper;

  /// No description provided for @synthTrimSilence.
  ///
  /// In en, this message translates to:
  /// **'Trim silence'**
  String get synthTrimSilence;

  /// No description provided for @synthTrimSilenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Strip leading and trailing silence below -72 dBFS from the synthesised PCM.'**
  String get synthTrimSilenceSubtitle;

  /// No description provided for @synthSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed: {value}×'**
  String synthSpeed(String value);

  /// No description provided for @synthSpeedHelper.
  ///
  /// In en, this message translates to:
  /// **'Playback speed multiplier (0.25× – 4.00×). Nearest-neighbour resample; no pitch correction.'**
  String get synthSpeedHelper;

  /// No description provided for @translateTitle.
  ///
  /// In en, this message translates to:
  /// **'Translate text'**
  String get translateTitle;

  /// No description provided for @translateModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Translation model'**
  String get translateModelLabel;

  /// No description provided for @translateSourceLang.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get translateSourceLang;

  /// No description provided for @translateTargetLang.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get translateTargetLang;

  /// No description provided for @translateSwap.
  ///
  /// In en, this message translates to:
  /// **'Swap source and target'**
  String get translateSwap;

  /// No description provided for @translateInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Source text'**
  String get translateInputLabel;

  /// No description provided for @translateInputHint.
  ///
  /// In en, this message translates to:
  /// **'Type or paste text to translate…'**
  String get translateInputHint;

  /// No description provided for @translateOutputLabel.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translateOutputLabel;

  /// No description provided for @translateRunButton.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translateRunButton;

  /// No description provided for @translateNoModelsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'No translation models downloaded. Open Models, switch to the Translate filter, and fetch one of M2M-100, WMT21 (en→X / X→en), or MADLAD-400.'**
  String get translateNoModelsDownloaded;

  /// No description provided for @translateAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get translateAdvanced;

  /// No description provided for @translateMaxTokens.
  ///
  /// In en, this message translates to:
  /// **'Max output tokens: {n}'**
  String translateMaxTokens(int n);

  /// No description provided for @translateMaxTokensHelper.
  ///
  /// In en, this message translates to:
  /// **'Hard cap on translated-text length. CrispASR\'s default is 200; raise for long passages, lower to keep generation snappy.'**
  String get translateMaxTokensHelper;

  /// No description provided for @advancedPerfHeader.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get advancedPerfHeader;

  /// No description provided for @advancedLidUseGpu.
  ///
  /// In en, this message translates to:
  /// **'LID on GPU'**
  String get advancedLidUseGpu;

  /// No description provided for @advancedLidUseGpuSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Route language detection to Metal / CUDA / Vulkan when supported. ASR backends honour their own per-session GPU setup at load time.'**
  String get advancedLidUseGpuSubtitle;

  /// No description provided for @advancedLidFlashAttn.
  ///
  /// In en, this message translates to:
  /// **'LID flash-attention'**
  String get advancedLidFlashAttn;

  /// No description provided for @advancedLidFlashAttnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Faster attention kernel during the LID encoder pass. Disable only if you suspect a flash-attn correctness bug on your build.'**
  String get advancedLidFlashAttnSubtitle;

  /// No description provided for @advancedNThreads.
  ///
  /// In en, this message translates to:
  /// **'CPU threads: {n}'**
  String advancedNThreads(int n);

  /// No description provided for @advancedNThreadsHelper.
  ///
  /// In en, this message translates to:
  /// **'Threads used for LID and other non-decoder passes. Defaults to 4.'**
  String get advancedNThreadsHelper;

  /// No description provided for @synthCustomVoice.
  ///
  /// In en, this message translates to:
  /// **'Custom voice (WAV reference)'**
  String get synthCustomVoice;

  /// No description provided for @synthCustomVoiceHelper.
  ///
  /// In en, this message translates to:
  /// **'Pick a WAV from disk for runtime cloning. Pair with the Reference transcript on qwen3-tts Base / vibevoice-1.5b. Overrides the voicepack dropdown when set.'**
  String get synthCustomVoiceHelper;

  /// No description provided for @synthCustomVoicePick.
  ///
  /// In en, this message translates to:
  /// **'Pick reference WAV…'**
  String get synthCustomVoicePick;

  /// No description provided for @synthCustomVoiceReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace reference WAV…'**
  String get synthCustomVoiceReplace;

  /// No description provided for @synthCustomVoiceClear.
  ///
  /// In en, this message translates to:
  /// **'Clear custom voice'**
  String get synthCustomVoiceClear;

  /// No description provided for @recorderStreamSession.
  ///
  /// In en, this message translates to:
  /// **'Stream (session)'**
  String get recorderStreamSession;

  /// No description provided for @recorderStreamSessionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Live mic transcribe through the active backend\'s streaming arm (kyutai-stt / moonshine-streaming / voxtral4b). Falls back to Whisper sliding-window when the backend has no native stream API.'**
  String get recorderStreamSessionTooltip;

  /// No description provided for @streamingNotAvailableForBackend.
  ///
  /// In en, this message translates to:
  /// **'The active backend ({backend}) has no streaming arm. Switch to whisper, kyutai-stt, moonshine-streaming, or voxtral4b.'**
  String streamingNotAvailableForBackend(String backend);

  /// No description provided for @streamingNoModelLoaded.
  ///
  /// In en, this message translates to:
  /// **'No model loaded yet. Pick a model from the dropdown above (it\'ll auto-load if downloaded), or open Model Management to download one first.'**
  String get streamingNoModelLoaded;

  /// No description provided for @transcribeNoSource.
  ///
  /// In en, this message translates to:
  /// **'Please select an audio file, enter a URL, or make a recording.'**
  String get transcribeNoSource;

  /// No description provided for @voiceBakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Bake voice (WAV → GGUF)'**
  String get voiceBakeTitle;

  /// No description provided for @voiceBakeOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Bake a Chatterbox voice from a WAV reference'**
  String get voiceBakeOpenTooltip;

  /// No description provided for @voiceBakeIntro.
  ///
  /// In en, this message translates to:
  /// **'Run CrispASR\'s bake-chatterbox-voice-from-wav.py to convert a WAV reference into a baked voicepack GGUF. Requires Python 3 + chatterbox-tts + gguf installed on the system.'**
  String get voiceBakeIntro;

  /// No description provided for @voiceBakeWavLabel.
  ///
  /// In en, this message translates to:
  /// **'Reference WAV'**
  String get voiceBakeWavLabel;

  /// No description provided for @voiceBakeWavPick.
  ///
  /// In en, this message translates to:
  /// **'Pick WAV…'**
  String get voiceBakeWavPick;

  /// No description provided for @voiceBakeOutputName.
  ///
  /// In en, this message translates to:
  /// **'Output filename'**
  String get voiceBakeOutputName;

  /// No description provided for @voiceBakeOutputNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Saved into your models directory next to other voicepacks. Use the .gguf extension.'**
  String get voiceBakeOutputNameHelper;

  /// No description provided for @voiceBakeExaggeration.
  ///
  /// In en, this message translates to:
  /// **'Exaggeration: {value}'**
  String voiceBakeExaggeration(String value);

  /// No description provided for @voiceBakeExaggerationHelper.
  ///
  /// In en, this message translates to:
  /// **'Default emotion-advance scalar (0.0 – 1.0). 0.5 is the upstream default.'**
  String get voiceBakeExaggerationHelper;

  /// No description provided for @voiceBakePythonLabel.
  ///
  /// In en, this message translates to:
  /// **'Python interpreter'**
  String get voiceBakePythonLabel;

  /// No description provided for @voiceBakePythonHelper.
  ///
  /// In en, this message translates to:
  /// **'Defaults to `python3` on PATH. Override if your chatterbox-tts / gguf install lives in a venv.'**
  String get voiceBakePythonHelper;

  /// No description provided for @voiceBakeScriptLabel.
  ///
  /// In en, this message translates to:
  /// **'Bake script path'**
  String get voiceBakeScriptLabel;

  /// No description provided for @voiceBakeScriptHelper.
  ///
  /// In en, this message translates to:
  /// **'Defaults to ../CrispASR/models/bake-chatterbox-voice-from-wav.py. Adjust if your CrispASR checkout is elsewhere.'**
  String get voiceBakeScriptHelper;

  /// No description provided for @voiceBakeRun.
  ///
  /// In en, this message translates to:
  /// **'Bake voice'**
  String get voiceBakeRun;

  /// No description provided for @voiceBakeRunning.
  ///
  /// In en, this message translates to:
  /// **'Baking…'**
  String get voiceBakeRunning;

  /// No description provided for @voiceBakeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Voice baked → {path}'**
  String voiceBakeSuccess(String path);

  /// No description provided for @voiceBakeFailure.
  ///
  /// In en, this message translates to:
  /// **'Bake failed: {error}'**
  String voiceBakeFailure(String error);

  /// No description provided for @voiceBakeMissingInputs.
  ///
  /// In en, this message translates to:
  /// **'Pick a reference WAV and an output filename first.'**
  String get voiceBakeMissingInputs;

  /// No description provided for @advancedAsrUseGpu.
  ///
  /// In en, this message translates to:
  /// **'ASR on GPU'**
  String get advancedAsrUseGpu;

  /// No description provided for @advancedAsrUseGpuSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Route ASR session inits to Metal / CUDA / Vulkan when supported. Takes effect on the next model load. Backends without runtime GPU control keep their compile-time default.'**
  String get advancedAsrUseGpuSubtitle;

  /// No description provided for @advancedAsrFlashAttn.
  ///
  /// In en, this message translates to:
  /// **'ASR flash-attention'**
  String get advancedAsrFlashAttn;

  /// No description provided for @advancedAsrFlashAttnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the flash-attention kernel for the ASR compute graph. Honoured by Whisper natively; other backends accept the toggle but their compute graphs aren\'t yet branched on it. Takes effect on the next model load.'**
  String get advancedAsrFlashAttnSubtitle;

  /// No description provided for @advancedAsrNGpuLayers.
  ///
  /// In en, this message translates to:
  /// **'GPU layers (LLM): {n}'**
  String advancedAsrNGpuLayers(int n);

  /// No description provided for @advancedAsrNGpuLayersAuto.
  ///
  /// In en, this message translates to:
  /// **'GPU layers (LLM): auto (max)'**
  String get advancedAsrNGpuLayersAuto;

  /// No description provided for @advancedAsrNGpuLayersHelper.
  ///
  /// In en, this message translates to:
  /// **'Cap on GPU-offloaded transformer layers for LLM-based backends (orpheus / voxtral / qwen3 / granite / chatterbox). 0 = run LLM on CPU; 1+ = explicit bound; auto = as many as fit. Takes effect on the next model load.'**
  String get advancedAsrNGpuLayersHelper;

  /// No description provided for @settingsServerSection.
  ///
  /// In en, this message translates to:
  /// **'Local HTTP server (OpenAI-compatible)'**
  String get settingsServerSection;

  /// No description provided for @settingsServerEnable.
  ///
  /// In en, this message translates to:
  /// **'Run server'**
  String get settingsServerEnable;

  /// No description provided for @settingsServerRunningAt.
  ///
  /// In en, this message translates to:
  /// **'Listening on {url}'**
  String settingsServerRunningAt(String url);

  /// No description provided for @settingsServerStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped. Toggle on to expose CrisperWeaver\'s services on a local port.'**
  String get settingsServerStopped;

  /// No description provided for @settingsServerStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start server: {error}'**
  String settingsServerStartFailed(String error);

  /// No description provided for @settingsServerEndpoints.
  ///
  /// In en, this message translates to:
  /// **'Endpoints'**
  String get settingsServerEndpoints;

  /// No description provided for @settingsServerEndpointsHelp.
  ///
  /// In en, this message translates to:
  /// **'POST /v1/audio/transcriptions (multipart upload, file=audio) · POST /v1/audio/speech (JSON: model, input, voice, speed) · POST /v1/translations (JSON: model, text, src, tgt) · GET /health. Binds to 127.0.0.1 only — no auth.'**
  String get settingsServerEndpointsHelp;

  /// No description provided for @synthTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature: {value}'**
  String synthTemperature(String value);

  /// No description provided for @synthTemperatureHelper.
  ///
  /// In en, this message translates to:
  /// **'Sampling temperature shared across orpheus / chatterbox / canary. 0.0 = greedy / reproducible. Higher = more variety.'**
  String get synthTemperatureHelper;

  /// No description provided for @synthTtsSteps.
  ///
  /// In en, this message translates to:
  /// **'Diffusion steps: {n}'**
  String synthTtsSteps(int n);

  /// No description provided for @synthTtsStepsHelper.
  ///
  /// In en, this message translates to:
  /// **'Number of CFM Euler steps in the chatterbox mel decoder (default 10). Higher = smoother audio at the cost of latency.'**
  String get synthTtsStepsHelper;

  /// No description provided for @synthCfgWeight.
  ///
  /// In en, this message translates to:
  /// **'CFG weight: {value}'**
  String synthCfgWeight(String value);

  /// No description provided for @synthCfgWeightHelper.
  ///
  /// In en, this message translates to:
  /// **'Classifier-free-guidance weight (chatterbox). 0 disables CFG; 0.5 is the upstream default; 1+ amplifies the conditional path.'**
  String get synthCfgWeightHelper;

  /// No description provided for @synthExaggeration.
  ///
  /// In en, this message translates to:
  /// **'Exaggeration: {value}'**
  String synthExaggeration(String value);

  /// No description provided for @synthExaggerationHelper.
  ///
  /// In en, this message translates to:
  /// **'Emotion-exaggeration scalar (chatterbox). 0.5 is the upstream default; raise for dramatic delivery, lower for monotone.'**
  String get synthExaggerationHelper;

  /// No description provided for @synthTopP.
  ///
  /// In en, this message translates to:
  /// **'Top-p: {value}'**
  String synthTopP(String value);

  /// No description provided for @synthTopPHelper.
  ///
  /// In en, this message translates to:
  /// **'Top-p nucleus sampling threshold (chatterbox). 1.0 disables top-p; lower values cut the long tail of unlikely tokens.'**
  String get synthTopPHelper;

  /// No description provided for @synthMinP.
  ///
  /// In en, this message translates to:
  /// **'Min-p: {value}'**
  String synthMinP(String value);

  /// No description provided for @synthMinPHelper.
  ///
  /// In en, this message translates to:
  /// **'Min-p threshold (chatterbox). 0 disables; positive values drop tokens whose probability falls below this fraction of the most-likely token.'**
  String get synthMinPHelper;

  /// No description provided for @synthRepetitionPenalty.
  ///
  /// In en, this message translates to:
  /// **'Repetition penalty: {value}'**
  String synthRepetitionPenalty(String value);

  /// No description provided for @synthRepetitionPenaltyHelper.
  ///
  /// In en, this message translates to:
  /// **'Repeat-penalty scalar (chatterbox). 1.0 disables; raise to discourage the model from loop-stuttering on repeated tokens.'**
  String get synthRepetitionPenaltyHelper;

  /// No description provided for @synthMaxSpeechTokens.
  ///
  /// In en, this message translates to:
  /// **'Max speech tokens: {n}'**
  String synthMaxSpeechTokens(int n);

  /// No description provided for @synthMaxSpeechTokensHelper.
  ///
  /// In en, this message translates to:
  /// **'Hard cap on AR speech tokens per call (chatterbox). 1000 ≈ 20 s; raise for long inputs, lower to bound runaway generation.'**
  String get synthMaxSpeechTokensHelper;

  /// No description provided for @synthClearPhonemeCache.
  ///
  /// In en, this message translates to:
  /// **'Clear phoneme cache'**
  String get synthClearPhonemeCache;

  /// No description provided for @synthClearPhonemeCacheDone.
  ///
  /// In en, this message translates to:
  /// **'Phoneme cache cleared.'**
  String get synthClearPhonemeCacheDone;

  /// No description provided for @synthClearPhonemeCacheUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This backend doesn\'t use a phoneme cache (or the open session is too old).'**
  String get synthClearPhonemeCacheUnsupported;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
