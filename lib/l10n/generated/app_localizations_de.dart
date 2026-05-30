// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'CrisperWeaver';

  @override
  String get appTagline => 'Audio-Transkription mit Sprecher-Unterscheidung';

  @override
  String get menuHistory => 'Verlauf';

  @override
  String get menuSettings => 'Einstellungen';

  @override
  String get menuModels => 'Modelle';

  @override
  String get menuSynthesize => 'Sprache erzeugen';

  @override
  String get menuTranslate => 'Text übersetzen';

  @override
  String get menuLogs => 'Protokoll';

  @override
  String get menuAbout => 'Über';

  @override
  String get menuOpenMore => 'Mehr';

  @override
  String get tabInput => 'Eingabe';

  @override
  String get tabRun => 'Start';

  @override
  String get tabOutput => 'Ausgabe';

  @override
  String get navHome => 'Transkribieren';

  @override
  String get engineReady => 'Engine bereit';

  @override
  String get engineStarting => 'Engine wird gestartet…';

  @override
  String get audioInput => 'Audio-Eingabe';

  @override
  String get noFileSelected => 'Keine Datei ausgewählt';

  @override
  String get browse => 'Durchsuchen';

  @override
  String get urlInputLabel => 'Oder Audio-URL eingeben';

  @override
  String get urlInputHint => 'https://example.com/audio.mp3';

  @override
  String get advancedOptions => 'Erweiterte Optionen';

  @override
  String get language => 'Sprache';

  @override
  String get languageAuto => 'Automatisch erkennen';

  @override
  String get model => 'Modell';

  @override
  String get transcribe => 'Transkribieren';

  @override
  String get transcribing => 'Transkribiere…';

  @override
  String get stop => 'Stopp';

  @override
  String get clear => 'Löschen';

  @override
  String get transcriptionOutput => 'Transkriptions-Ausgabe';

  @override
  String get noTranscriptionYet => 'Noch keine Transkription';

  @override
  String get noTranscriptionHint =>
      'Audio-Datei wählen und Transkription starten';

  @override
  String get searchTranscription => 'Transkription durchsuchen…';

  @override
  String get noResultsFound => 'Keine Treffer';

  @override
  String get noResultsHint => 'Anderen Suchbegriff probieren';

  @override
  String get tabSegments => 'Segmente';

  @override
  String get tabFullText => 'Volltext';

  @override
  String get sharePlain => 'Als Text teilen';

  @override
  String get copyClipboard => 'In Zwischenablage kopieren';

  @override
  String get saveAsTxt => 'Als .txt speichern';

  @override
  String get saveAsSrt => 'Als .srt speichern';

  @override
  String get saveAsVtt => 'Als .vtt speichern';

  @override
  String get saveAsJson => 'Als .json speichern';

  @override
  String get copied => 'Kopiert';

  @override
  String get perfRtf => 'RTF';

  @override
  String get perfAudio => 'Audio';

  @override
  String get perfWall => 'Zeit';

  @override
  String get perfWords => 'Wörter';

  @override
  String get perfWps => 'W/s';

  @override
  String get perfEngine => 'Engine';

  @override
  String get perfModel => 'Modell';

  @override
  String get perfFasterThanRealtime => 'schneller als Echtzeit';

  @override
  String get perfSlowerThanRealtime => 'langsamer als Echtzeit';

  @override
  String get diarizationTitle => 'Sprecher-Unterscheidung';

  @override
  String get diarizationSubtitle =>
      'Verschiedene Sprecher in Aufnahmen identifizieren';

  @override
  String get diarizationModel => 'Unterscheidungs-Modell';

  @override
  String get minSpeakers => 'Min. Sprecher';

  @override
  String get maxSpeakers => 'Max. Sprecher';

  @override
  String get auto => 'Auto';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsAppLanguage => 'App-Sprache';

  @override
  String get settingsInterfaceLanguage => 'Oberflächen-Sprache';

  @override
  String get settingsSystemDefault => 'Systemvorgabe';

  @override
  String get settingsEngineSection => 'Transkriptions-Engine';

  @override
  String get settingsEnginePreferred => 'Bevorzugte Engine';

  @override
  String get settingsSelectEngine => 'Engine wählen';

  @override
  String settingsEngineSwitched(String engine) {
    return 'Gewechselt zu $engine';
  }

  @override
  String get settingsEngineSwitchFailed => 'Engine-Wechsel fehlgeschlagen';

  @override
  String settingsAudioQualityCurrent(int percent) {
    return 'Aufnahmequalität: $percent%';
  }

  @override
  String get settingsCacheCleared => 'Cache erfolgreich geleert';

  @override
  String get settingsHfToken => 'HuggingFace-API-Token';

  @override
  String get settingsHfTokenNotSet =>
      'Nicht gesetzt (erforderlich für gated-Modelle)';

  @override
  String get settingsModelsDir => 'Modellverzeichnis';

  @override
  String get settingsModelsDirDefault => 'Standard (App-Sandbox)';

  @override
  String get settingsModelsDirPickTitle => 'Modellverzeichnis wählen';

  @override
  String get settingsModelsDirCurrentDefault =>
      'Aktuell wird der Standard-Sandbox-Pfad verwendet. Wähle ein eigenes Verzeichnis, um GGUFs mit anderen Tools zu teilen (z. B. von einer externen Festplatte).';

  @override
  String settingsModelsDirCurrent(String path) {
    return 'Aktuell: $path';
  }

  @override
  String get settingsModelsDirPick => 'Wählen …';

  @override
  String get settingsModelsDirReset => 'Standard verwenden';

  @override
  String settingsModelsDirSet(String path) {
    return 'Modellverzeichnis gesetzt auf $path';
  }

  @override
  String get languageEn => 'Englisch';

  @override
  String get languageDe => 'Deutsch';

  @override
  String get languageEs => 'Spanisch';

  @override
  String get languageFr => 'Französisch';

  @override
  String get languageIt => 'Italienisch';

  @override
  String get languagePt => 'Portugiesisch';

  @override
  String get languageZh => 'Chinesisch';

  @override
  String get languageJa => 'Japanisch';

  @override
  String get languageKo => 'Koreanisch';

  @override
  String get languageRu => 'Russisch';

  @override
  String modelSize(String size) {
    return 'Größe: $size';
  }

  @override
  String modelDeleteConfirm(String name) {
    return 'Möchten Sie $name wirklich löschen?';
  }

  @override
  String get historyCopy => 'Kopieren';

  @override
  String get historyExportSrt => 'SRT exportieren';

  @override
  String get historyExportTxt => 'TXT exportieren';

  @override
  String get historyExportJson => 'JSON exportieren';

  @override
  String get historyDelete => 'Löschen';

  @override
  String historyFailedToLoad(String error) {
    return 'Verlauf konnte nicht geladen werden: $error';
  }

  @override
  String historySaved(String path) {
    return 'Gespeichert: $path';
  }

  @override
  String historyExportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get recorderDeleteTitle => 'Aufnahme löschen';

  @override
  String get recorderDeleteBody =>
      'Möchten Sie diese Aufnahme wirklich löschen?';

  @override
  String get recorderQueuedForTranscription =>
      'Aufnahme zur Transkription eingereiht.';

  @override
  String get recorderStream => 'Stream';

  @override
  String get recorderStreamTooltip =>
      'Live-Mikrofon-Transkription (Whisper-Schiebefenster). Teil-Text erscheint beim Sprechen.';

  @override
  String get recorderSystemAudioTooltip =>
      'Systemton aufnehmen (Zoom-Anruf, Browser-Tab, Podcast-App) und live transkribieren. Nur macOS 13+; bei erster Nutzung wird die Bildschirmaufzeichnungs-Berechtigung abgefragt.';

  @override
  String get recorderSystemAudioPermission =>
      'Berechtigung für Bildschirmaufzeichnung verweigert. Öffne Systemeinstellungen → Datenschutz & Sicherheit → Bildschirmaufzeichnung, aktiviere CrisperWeaver und versuche es erneut.';

  @override
  String get recorderSystemAudioUnsupported =>
      'Systemton-Aufnahme wird auf dieser Plattform noch nicht unterstützt. Siehe PLAN.md §5.1.1.';

  @override
  String get outputShowTimestamps => 'Zeitstempel anzeigen';

  @override
  String get outputShowSpeakers => 'Sprecher anzeigen';

  @override
  String get outputShowConfidence => 'Konfidenz anzeigen';

  @override
  String get outputCopyAll => 'Alle kopieren';

  @override
  String get outputPlay => 'Abspielen';

  @override
  String get outputCopy => 'Kopieren';

  @override
  String get outputEdit => 'Bearbeiten';

  @override
  String get outputPlaySegment => 'Segment abspielen';

  @override
  String get outputCopyText => 'Text kopieren';

  @override
  String get outputEditSegment => 'Segment bearbeiten';

  @override
  String get outputEditNotImplemented =>
      'Segment-Bearbeitung noch nicht implementiert';

  @override
  String get outputEditAltSuggestions => 'Alternative Kandidaten';

  @override
  String get outputEditAltSuggestionsHint =>
      'Tippe auf ein Wort, um es durch einen alternativen Whisper-Kandidaten an derselben Stelle zu ersetzen. Nutzt den Schieberegler in den erweiterten Optionen.';

  @override
  String get outputEditAltPickTooltip =>
      'Alternativen Kandidaten für dieses Wort wählen';

  @override
  String get outputRenameSpeakerTitle => 'Sprecher umbenennen';

  @override
  String outputRenameSpeakerOriginal(String original) {
    return 'Originale Bezeichnung: $original';
  }

  @override
  String get outputRenameSpeakerReset => 'Auf Original zurücksetzen';

  @override
  String get outputSegmentCopied => 'Segment in Zwischenablage kopiert';

  @override
  String get outputAllCopied =>
      'Gesamte Transkription in Zwischenablage kopiert';

  @override
  String outputPlayingSegment(String time) {
    return 'Segment wird abgespielt: $time';
  }

  @override
  String get settingsLoading => 'Lade…';

  @override
  String get transcribeLanguageLabel => 'Sprache';

  @override
  String transcribeLoadingButton(String model) {
    return 'Lädt $model…';
  }

  @override
  String get transcribeLoadingFallback => 'Modell wird geladen…';

  @override
  String transcribeLoadingDetail(String model) {
    return 'Modell wird geladen: $model — die erste Transkription mit diesem Modell dauert ~5–15 s, während der Worker-Pool startet und die Gewichte in den Speicher gemappt werden.';
  }

  @override
  String transcribeStarting(String model) {
    return 'Download startet: $model';
  }

  @override
  String transcribeUnsupportedFile(String name) {
    return 'Nicht unterstützter Dateityp: $name';
  }

  @override
  String transcribeLoadedFile(String name) {
    return 'Geladen: $name';
  }

  @override
  String aboutEmail(String email) {
    return 'E-Mail: $email';
  }

  @override
  String aboutPhone(String phone) {
    return 'Telefon: $phone';
  }

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsTranscription => 'Transkription';

  @override
  String get settingsDefaultModel => 'Standard-Modell';

  @override
  String get settingsDefaultLanguage => 'Standard-Sprache';

  @override
  String get settingsAutoDetectLanguage => 'Sprache automatisch erkennen';

  @override
  String get settingsAutoDetectLanguageSubtitle =>
      'Audio-Sprache automatisch ermitteln';

  @override
  String get settingsWordTimestamps => 'Wort-Zeitstempel';

  @override
  String get settingsWordTimestampsSubtitle =>
      'Zeitstempel für einzelne Wörter erzeugen';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioQuality => 'Audio-Qualität';

  @override
  String get settingsKeepAudioFiles => 'Audio-Dateien behalten';

  @override
  String get settingsKeepAudioFilesSubtitle =>
      'Heruntergeladene/aufgenommene Dateien nach der Transkription behalten';

  @override
  String get settingsDiarization => 'Sprecher-Unterscheidung';

  @override
  String get settingsEnableDiarizationByDefault => 'Standardmäßig aktivieren';

  @override
  String get settingsEnableDiarizationByDefaultSubtitle =>
      'Unterscheidung für neue Transkriptionen automatisch aktivieren';

  @override
  String get settingsStorage => 'Speicher';

  @override
  String get settingsClearCache => 'Cache leeren';

  @override
  String get settingsClearCacheSubtitle =>
      'Temporäre Dateien und Cache entfernen';

  @override
  String get settingsManageModels => 'Modelle verwalten';

  @override
  String get settingsManageModelsSubtitle =>
      'Transkriptions-Modelle laden, aktualisieren oder löschen';

  @override
  String get settingsStorageBreakdown => 'Speicheraufteilung';

  @override
  String get settingsStorageBreakdownSubtitle =>
      'Speicherverbrauch pro Backend ansehen und freigeben';

  @override
  String get storageTitle => 'Speicheraufteilung';

  @override
  String get storageRefresh => 'Aktualisieren';

  @override
  String get storageEmpty => 'Noch keine Modelldateien auf der Festplatte.';

  @override
  String get storageTotalUsed => 'Gesamt belegt';

  @override
  String storageBackendCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Backends',
      one: '1 Backend',
    );
    return '$_temp0';
  }

  @override
  String storageFilesCount(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '1 Datei',
    );
    return '$size • $_temp0';
  }

  @override
  String get storageDeleteAllTooltip => 'Alle Modelle dieses Backends löschen';

  @override
  String storageDeleteTitle(String backend) {
    return 'Alle Modelle von $backend löschen?';
  }

  @override
  String storageDeleteMessage(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '1 Datei',
    );
    return 'Dadurch werden $size aus $_temp0 freigegeben. Diese Aktion lässt sich nicht rückgängig machen.';
  }

  @override
  String get storageDeleteConfirm => 'Löschen';

  @override
  String storageDeletedSnack(String size) {
    return '$size freigegeben';
  }

  @override
  String get settingsDebugging => 'Debugging & Entwicklung';

  @override
  String get settingsLogLevel => 'Protokoll-Ebene';

  @override
  String settingsLogLevelCurrent(String level) {
    return 'Aktuell: $level';
  }

  @override
  String get settingsMirrorLogs => 'Protokoll in Datei schreiben';

  @override
  String get settingsMirrorLogsSubtitle =>
      'Schreibt nach logs/session.log im App-Dokumentverzeichnis';

  @override
  String get settingsSkipChecksum => 'Prüfsummen-Validierung überspringen';

  @override
  String get settingsSkipChecksumSubtitle =>
      'Heruntergeladene Modelle auch bei SHA-1-Abweichung akzeptieren';

  @override
  String get settingsGroupBatchByBackend => 'Stapel nach Backend gruppieren';

  @override
  String get settingsGroupBatchByBackendSubtitle =>
      'Sortiert wartende Dateien so um, dass aufeinanderfolgende Jobs dieselbe Modell-Sitzung wiederverwenden';

  @override
  String get settingsMaxConcurrent => 'Gleichzeitige Transkriptionen';

  @override
  String settingsMaxConcurrentCurrent(int n) {
    return 'Gleichzeitige Transkriptionen: $n';
  }

  @override
  String get settingsMaxConcurrentSessions => 'Parallele Sitzungen';

  @override
  String settingsMaxConcurrentSessionsCurrent(int n) {
    return 'Parallele Sitzungen: $n';
  }

  @override
  String get settingsMaxConcurrentSessionsSubtitle =>
      '1 = eine Sitzung (Standard). 2+ startet N Worker-Isolates mit jeweils eigener Modell-Kopie im RAM. Kosten: N × Modellgröße; Vorabprüfung kappt automatisch, wenn es nicht passt.';

  @override
  String settingsMemoryProjection(String projected, String total, String per) {
    return 'RAM-Schätzung: $projected von $total (pro Worker: $per)';
  }

  @override
  String settingsMemoryProjectionClamped(int affordable, int requested) {
    return 'Auf $affordable von $requested Workern reduziert — Modell zu groß für verfügbaren RAM';
  }

  @override
  String batchResumedSnackbar(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n unterbrochene Transkriptionen wiederhergestellt',
      one: '1 unterbrochene Transkription wiederhergestellt',
    );
    return '$_temp0 — Start drücken zum Fortsetzen';
  }

  @override
  String get settingsMaxConcurrentSubtitle =>
      '1 = seriell (bisheriges Verhalten). 2+ dekodiert die Audio-Daten der nächsten Datei in einem Worker-Isolate, während die aktuelle Datei transkribiert wird — zusätzliche Parallelität ohne weitere Modell-Kopien im RAM.';

  @override
  String get settingsOpenLogViewer => 'Protokoll-Ansicht öffnen';

  @override
  String get settingsSpeakers => 'Sprecher';

  @override
  String get settingsSpeakersSubtitle =>
      'Stimmen einspeichern, damit die Diarisierung Sprecher automatisch benennen kann.';

  @override
  String get speakersTitle => 'Sprecher';

  @override
  String get speakersEmpty =>
      'Noch keine Sprecher eingespeichert. Tippen Sie auf +, um einen hinzuzufügen.';

  @override
  String get speakersPrivacyNote =>
      'Stimmprofile werden ausschließlich lokal gespeichert. Nichts wird hochgeladen.';

  @override
  String get speakersDownloadModelHint =>
      'Bitte zuerst das TitaNet-Modell in der Modellverwaltung herunterladen.';

  @override
  String get speakersAdd => 'Sprecher hinzufügen';

  @override
  String get speakersDeleteTitle => 'Eingespeicherten Sprecher löschen?';

  @override
  String speakersDeleteBody(String name) {
    return 'Das Stimmprofil von $name wird von diesem Gerät entfernt.';
  }

  @override
  String get speakersDeleteFailed => 'Profil konnte nicht gelöscht werden.';

  @override
  String get speakersEnrolTitle => 'Sprecher einspeichern';

  @override
  String get speakersSourceRecord => 'Aufnahme';

  @override
  String get speakersSourceFile => 'Datei wählen';

  @override
  String get speakersName => 'Sprechername';

  @override
  String get speakersNameRequired => 'Name ist erforderlich';

  @override
  String get speakersNameTaken =>
      'Ein Sprecher mit diesem Namen ist bereits gespeichert.';

  @override
  String get speakersNoSample =>
      'Bitte zuerst eine Audioprobe aufnehmen oder auswählen.';

  @override
  String get speakersEnrolButton => 'Einspeichern';

  @override
  String get speakersEnrolFailed =>
      'Einspeichern fehlgeschlagen – bitte mit einer deutlicheren Probe erneut versuchen.';

  @override
  String get speakersRecord => 'Aufnahme starten';

  @override
  String get speakersRecordStop => 'Stopp';

  @override
  String speakersRecordHint(int seconds) {
    return 'Tippen Sie, um $seconds s dieser Person sprechend aufzunehmen.';
  }

  @override
  String speakersRecordingCountdown(int seconds) {
    return 'Aufnahme läuft… noch $seconds s';
  }

  @override
  String speakersRecordingDone(int seconds) {
    return '$seconds s Audio aufgenommen.';
  }

  @override
  String get speakersRecordNoPermission =>
      'Mikrofon-Berechtigung wurde verweigert.';

  @override
  String get speakersPickHint =>
      'Bitte eine Audiodatei mit einer deutlichen Probe dieser Person wählen.';

  @override
  String get speakersPickButton => 'Audiodatei wählen';

  @override
  String get settingsSystemInfo => 'Systeminformation';

  @override
  String get settingsAbout => 'Über';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsAboutCrisperWeaver => 'Über CrisperWeaver';

  @override
  String get settingsAboutCrisperWeaverSubtitle =>
      'Anbieter, Kontakt, Haftungsausschluss, Lizenzen';

  @override
  String get settingsHfTokenTitle => 'Hugging Face API-Token';

  @override
  String get settingsHfTokenSubtitle =>
      'Erforderlich für gesperrte oder private Repositories.';

  @override
  String get settingsHfTokenSave => 'SPEICHERN';

  @override
  String get settingsHfTokenCancel => 'ABBRECHEN';

  @override
  String get transcriptionNoModelsFound => 'Keine Modelle gefunden';

  @override
  String get transcriptionRetry => 'Erneut versuchen';

  @override
  String transcriptionLoadFailed(String error) {
    return 'Laden fehlgeschlagen: $error';
  }

  @override
  String transcriptionSavedTo(String path) {
    return 'Gespeichert: $path';
  }

  @override
  String transcriptionSaveFailed(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get transcriptionCopiedToClipboard => 'In Zwischenablage kopiert';

  @override
  String get transcriptionShareSheetTitle => 'Teilen oder speichern';

  @override
  String get transcriptionSharePlainText => 'Als Text teilen';

  @override
  String get transcriptionCopyToClipboard => 'In Zwischenablage kopieren';

  @override
  String get transcriptionSaveAsTxt => 'Als TXT speichern';

  @override
  String get transcriptionSaveAsSrt => 'Als SRT speichern';

  @override
  String get transcriptionSaveAsVtt => 'Als VTT speichern';

  @override
  String get transcriptionSaveAsJson => 'Als JSON speichern';

  @override
  String get transcriptionDownloadModel => 'Modell herunterladen';

  @override
  String get transcriptionDownload => 'HERUNTERLADEN';

  @override
  String get advancedBestOfSingle => 'Best-of-N: einzelner Decode (1)';

  @override
  String advancedBestOfCurrent(int n) {
    return 'Best-of-N: $n Decodes';
  }

  @override
  String get advancedBestOfHelper =>
      '1 = einzelner Decode (Standard). >1 führt N unabhängige Decodes aus und wählt das beste Ergebnis. Whisper verarbeitet dies intern; andere Backends laufen extern in einer Schleife und wählen das Transkript mit der höchsten mittleren Konfidenz. Kosten: N× pro-Aufruf Decode-Zeit.';

  @override
  String get advancedTemperatureGreedy => 'Decoder-Temperatur: greedy (0,00)';

  @override
  String advancedTemperatureCurrent(String value) {
    return 'Decoder-Temperatur: $value';
  }

  @override
  String get advancedTemperatureHelper =>
      '0,00 = greedy / reproduzierbar. > 0 = stochastisches Sampling — hilfreich, wenn greedy in einer halluzinierten Wiederholung hängenbleibt. Whisper hat eine eigene interne Fallback-Leiter; dieser Wert betrifft Sampling-Backends (canary, cohere, parakeet, moonshine).';

  @override
  String downloadModelPrompt(String name, String size) {
    return 'Das Modell „$name\" ist noch nicht heruntergeladen. Jetzt herunterladen (~$size)?';
  }

  @override
  String get tooltipDeleteRecording => 'Aufnahme löschen';

  @override
  String get tooltipUseForTranscription => 'Für Transkription verwenden';

  @override
  String get tooltipModelSelectionHelp => 'Hilfe zur Modellauswahl';

  @override
  String get tooltipDownloadModel => 'Modell herunterladen';

  @override
  String get tooltipDisplayLevel => 'Anzeige-Stufe';

  @override
  String get tooltipPauseAutoScroll => 'Auto-Scroll pausieren';

  @override
  String get tooltipResumeAutoScroll => 'Auto-Scroll fortsetzen';

  @override
  String get labelApiToken => 'API-Token';

  @override
  String get streamingRequiresWhisper =>
      'Streaming benötigt die Whisper-Engine. Backend in den Einstellungen wechseln.';

  @override
  String get streamingMicUnavailable =>
      'Mikrofon für Streaming nicht verfügbar.';

  @override
  String get streamingEngineNoSession =>
      'Engine liefert keine Streaming-Sitzung.';

  @override
  String playbackFailed(String error) {
    return 'Wiedergabe fehlgeschlagen: $error';
  }

  @override
  String synthesizeFailed(String error) {
    return 'Synthese fehlgeschlagen: $error';
  }

  @override
  String logsShowLevel(String level) {
    return '$level und darüber anzeigen';
  }

  @override
  String get diarizationAuto => 'Auto';

  @override
  String get diarizationModelSelectionTitle => 'Diarisierung: Modellauswahl';

  @override
  String get aboutServiceProvider => 'Anbieter';

  @override
  String get aboutContact => 'Kontakt';

  @override
  String get aboutPrivacy => 'Datenschutz';

  @override
  String get aboutDisclaimer => 'Haftungsausschluss';

  @override
  String get aboutLicense => 'Lizenz';

  @override
  String get aboutOpenSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get aboutPrivacyText =>
      'CrisperWeaver verarbeitet alle Audio-Daten ausschließlich lokal auf Ihrem Gerät. Weder Audio noch Transkripte oder Aufnahmen werden an Server übertragen. Modell-Downloads laden GGUF-Gewichte direkt von HuggingFace über HTTPS; darüber hinaus verlässt nichts das Gerät.';

  @override
  String get aboutDisclaimerText =>
      'Diese Software wird „wie besehen“ zur Verfügung gestellt, ohne jegliche ausdrückliche oder stillschweigende Gewährleistung, insbesondere der Marktgängigkeit, Eignung für einen bestimmten Zweck oder der Nichtverletzung von Rechten Dritter. In keinem Fall haften die Autor:innen für Ansprüche, Schäden oder sonstige Haftungen, die sich aus oder im Zusammenhang mit der Software oder deren Nutzung ergeben.';

  @override
  String get aboutLicenseText =>
      'CrisperWeaver ist freie Software und wird unter der GNU Affero General Public License v3.0 (AGPL-3.0) veröffentlicht. Sie dürfen es unter den Bedingungen dieser Lizenz weitergeben und verändern. Insbesondere gilt: Wenn Sie eine veränderte Version von CrisperWeaver als Netzwerk-Dienst betreiben, müssen Sie den zugehörigen Quellcode Ihren Nutzer:innen zugänglich machen.';

  @override
  String get historyTitle => 'Transkriptions-Verlauf';

  @override
  String get historyEmpty => 'Noch keine Transkriptionen';

  @override
  String get historyEmptyHint =>
      'Eine Transkription ausführen – sie erscheint hier.';

  @override
  String get historyRefresh => 'Aktualisieren';

  @override
  String get historyClearAll => 'Alle löschen';

  @override
  String get historySearchHint => 'Titel oder Transkript suchen…';

  @override
  String historySearchNoResults(String query) {
    return 'Keine Verlaufseinträge passen zu „$query“';
  }

  @override
  String historySearchMatchCount(int matched, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      matched,
      locale: localeName,
      other: '$matched von $total gefunden',
      one: '1 von $total gefunden',
    );
    return '$_temp0';
  }

  @override
  String get historyClearAllPrompt =>
      'Alle gespeicherten Transkriptionen von diesem Gerät entfernen. Das kann nicht rückgängig gemacht werden.';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get logsTitle => 'Protokoll';

  @override
  String get logsFilterHint => 'Nach Nachricht, Tag oder Fehler filtern…';

  @override
  String get logsCopyVisible => 'Sichtbare kopieren';

  @override
  String get logsCopyAll => 'Alle kopieren';

  @override
  String get logsExport => 'In Datei exportieren';

  @override
  String get logsShare => 'Als Datei teilen';

  @override
  String get modelsTitle => 'Modell-Verwaltung';

  @override
  String get modelsNoneAvailable => 'Keine Modelle verfügbar';

  @override
  String get modelsRetry => 'Erneut versuchen';

  @override
  String get modelsDownload => 'Laden';

  @override
  String get modelsDelete => 'Modell löschen';

  @override
  String get modelsDownloaded => 'Geladen';

  @override
  String get modelsNotDownloaded => 'Nicht geladen';

  @override
  String modelsDownloadingPercent(String percent) {
    return 'Lade… $percent%';
  }

  @override
  String get error => 'Fehler';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Speichern';

  @override
  String get done => 'Fertig';

  @override
  String get settingsSaved => 'Einstellungen gespeichert';

  @override
  String get settingsDefaultBackend => 'Standard-Backend';

  @override
  String get settingsSelectBackend => 'Standard-Backend wählen';

  @override
  String settingsSelectModel(String backend) {
    return 'Standard-Modell wählen ($backend)';
  }

  @override
  String get settingsSelectLanguage => 'Standard-Sprache wählen';

  @override
  String get settingsSelectInterfaceLanguage => 'Oberflächen-Sprache wählen';

  @override
  String settingsNoModelsForBackend(String backend) {
    return 'Keine Modelle für Backend „$backend“ bekannt. Modell-Verwaltung → Cloud-Download-Symbol öffnen, um HuggingFace zu durchsuchen.';
  }

  @override
  String get modelFilterHint => 'Modelle filtern (Name / Quant)';

  @override
  String get modelAnyBackend => 'Beliebiges Backend';

  @override
  String get modelNoMatch => 'Keine Modelle entsprechen diesem Filter.';

  @override
  String get modelsRefreshFromHf => 'Quants von HuggingFace aktualisieren';

  @override
  String get modelsReloadLocal => 'Lokalen Zustand neu laden';

  @override
  String get modelsQuickStartTooltip => 'Schnellstart';

  @override
  String get quickStartTitle => 'Schnellstart';

  @override
  String get quickStartSubtitle =>
      'Hol dir mit einem Tippen ein kleines Startpaket – transkribieren, Sprache erzeugen und Text aufräumen.';

  @override
  String get quickStartDownloadAll => 'Alle fehlenden laden';

  @override
  String get quickStartInstalled => 'Installiert';

  @override
  String get quickStartAllInstalled => 'Alle Startmodelle sind installiert.';

  @override
  String get modelsProbedCountZero =>
      'Keine neuen Quants auf HuggingFace gefunden.';

  @override
  String modelsProbedCount(int count, String plural) {
    return '$count neue Quant-Variante$plural gefunden.';
  }

  @override
  String get batchQueueTitle => 'Stapel-Warteschlange';

  @override
  String batchQueueSummary(int queued, int running, int done, int errored) {
    return '$queued wartend · $running läuft · $done fertig · $errored fehlgeschlagen';
  }

  @override
  String get batchClearCompleted => 'Fertige entfernen';

  @override
  String get batchRemove => 'Aus Warteschlange entfernen';

  @override
  String batchEnqueueAdded(int count) {
    return '$count Datei(en) zur Warteschlange hinzugefügt.';
  }

  @override
  String get batchRunAll => 'Alle transkribieren';

  @override
  String get batchStop => 'Stapel stoppen';

  @override
  String get batchQueueDropHint =>
      'Audio-Dateien hier ablegen, um sie in die Warteschlange zu stellen';

  @override
  String get advancedSection => 'Erweiterte Decodierung';

  @override
  String get advancedVadTrim => 'Stille schneiden (VAD)';

  @override
  String get advancedVadTrimSubtitle =>
      'Stille am Anfang und Ende via Silero-VAD überspringen. Schneller bei Meetings / langen Aufnahmen mit Stille-Padding.';

  @override
  String get advancedTranslate => 'Ins Englische übersetzen';

  @override
  String get advancedTranslateSubtitle =>
      'Nur Whisper — erzwingt englische Ausgabe unabhängig von der Quellsprache.';

  @override
  String get advancedBeamSearch => 'Beam-Search';

  @override
  String get advancedBeamSearchSubtitle =>
      'Langsamer, meist genauer. Standard ist greedy.';

  @override
  String get advancedInitialPrompt => 'Initial-Prompt (Vokabular / Kontext)';

  @override
  String get advancedInitialPromptHint =>
      'z. B. „CrispASR, Flutter, Riverpod, Sprecher-Unterscheidung“';

  @override
  String get advancedRestorePunctuation =>
      'Interpunktion wiederherstellen (FireRedPunc)';

  @override
  String get advancedRestorePunctuationSubtitle =>
      'Großschreibung und Satzzeichen für Roh-Transkripte. Nützlich für CTC-Backends (wav2vec2, fastconformer-ctc, firered-asr). Benötigt fireredpunc-*.gguf in der Modellverwaltung.';

  @override
  String get advancedSourceLanguage =>
      'Quellsprache (Autoerkennung überschreiben)';

  @override
  String get advancedSourceLanguageAuto => 'Auto / Hauptauswahl verwenden';

  @override
  String get advancedSourceLanguageHelper =>
      'Quellsprache festlegen, wenn Whispers Autoerkennung bei verrauschtem Audio unzuverlässig ist. Leer = Hauptsprachen-Auswahl / Autoerkennung verwenden.';

  @override
  String get advancedTargetLanguage => 'Übersetzen in (Zielsprache)';

  @override
  String get advancedTargetLanguageNone => 'Keine Übersetzung (wörtlich)';

  @override
  String get advancedTargetLanguageHelper =>
      'Nur sichtbar für übersetzungsfähige Backends (Canary, Voxtral, Qwen3, Cohere, Whisper). „Keine Übersetzung\" für wortgetreue Transkription.';

  @override
  String get advancedAskPrompt => 'Audio fragen (Q&A-Modus)';

  @override
  String get advancedAskPromptHint =>
      'z. B. „Zusammenfassen\" oder „Wie klingt der Sprecher?\"';

  @override
  String get advancedAskPromptHelper =>
      'Nur Voxtral / Qwen3-ASR. Wenn gesetzt, ANTWORTET das LLM auf deine Frage, statt eine wortgetreue Transkription zu liefern. Leer lassen für normale Transkription.';

  @override
  String get editAudioOpen => 'Im Audio-Editor öffnen';

  @override
  String get editAudioTitle => 'Audio bearbeiten';

  @override
  String editAudioLoadFailed(String error) {
    return 'Audio konnte nicht dekodiert werden: $error';
  }

  @override
  String get editAudioSaveAs => 'Bearbeitetes Audio speichern unter…';

  @override
  String editAudioSavedTo(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get editAudioTrim => 'Zuschneiden';

  @override
  String get editAudioCut => 'Mitte ausschneiden';

  @override
  String get editAudioAddSplitMark => 'Splitmarke setzen';

  @override
  String editAudioRunSplit(int n) {
    return 'In $n Dateien aufteilen';
  }

  @override
  String get editAudioClearMarks => 'Marken löschen';

  @override
  String get editAudioClearSelection => 'Auswahl löschen';

  @override
  String get editAudioNeedSelection =>
      'Bitte zuerst auf der Wellenform einen Bereich auswählen (ziehen).';

  @override
  String get editAudioNeedSplitMarks =>
      'Bitte mindestens eine Splitmarke setzen.';

  @override
  String editAudioSelectionLabel(String start, String end) {
    return 'Auswahl: $start – $end';
  }

  @override
  String editAudioSplitSaved(int n) {
    return '$n Dateien gespeichert.';
  }

  @override
  String get editAudioHowto =>
      'Tippe auf die Wellenform, um zu springen. Ziehe, um einen Bereich auszuwählen. „Zuschneiden“ behält [Start, Ende]; „Mitte ausschneiden“ entfernt [Start, Ende] und fügt den Rest zusammen; „Splitmarke“ setzt einen Punkt an der aktuellen Position, dann „Aufteilen“ schreibt pro Bereich eine WAV-Datei.';

  @override
  String get editAudioToggleTranscriptShow => 'Transkript anzeigen';

  @override
  String get editAudioToggleTranscriptHide => 'Transkript ausblenden';

  @override
  String get editAudioTranscriptHeading => 'Transkript';

  @override
  String get editAudioTranscriptEmpty =>
      'Noch kein Transkript. Transkribiere die Audiodatei zuerst und kehre hierher zurück, um darin zu navigieren und Schnittmarken zu setzen.';

  @override
  String get editAudioTranscriptSegmentTapHint =>
      'Tippe auf eine Zeile, um die Wiedergabeposition zu setzen. Lange tippen für Schnitt-/Auswahloptionen.';

  @override
  String get editAudioMarkSegmentForCut => 'Segment als Splitmarke';

  @override
  String get editAudioTrimToSegment => 'Auf dieses Segment zuschneiden';

  @override
  String get editAudioSelectSegment => 'Dieses Segment auswählen';

  @override
  String editAudioSegmentMarkedForCut(String time) {
    return 'Splitmarke bei $time gesetzt.';
  }

  @override
  String get close => 'Schließen';

  @override
  String get presetsTooltip => 'Voreinstellungen';

  @override
  String get presetsTitle => 'Voreinstellungen';

  @override
  String get presetsHelp =>
      'Aktuelle Auswahl von Backend, Modell, Sprache und erweiterten Optionen unter einem Namen speichern. Später per Klick wiederherstellen.';

  @override
  String get presetsSaveCurrent =>
      'Aktuelle Einstellungen als Voreinstellung speichern';

  @override
  String get presetsSaveCurrentTitle => 'Voreinstellung speichern';

  @override
  String get presetsNameLabel => 'Name';

  @override
  String get presetsNameHint =>
      'z. B. Podcast, Sprachmemos, Mehrsprachiges Interview';

  @override
  String get presetsEmpty =>
      'Noch keine Voreinstellungen. Aktuelle Einstellungen speichern, um zu beginnen.';

  @override
  String get presetsApply => 'Anwenden';

  @override
  String presetsApplied(String name) {
    return 'Voreinstellung „$name\" angewendet.';
  }

  @override
  String get presetsRenameTitle => 'Voreinstellung umbenennen';

  @override
  String get presetsRenameTooltip => 'Umbenennen';

  @override
  String get presetsDeleteTitle => 'Voreinstellung löschen?';

  @override
  String presetsDeleteConfirm(String name) {
    return 'Voreinstellung „$name\" löschen? Das kann nicht rückgängig gemacht werden.';
  }

  @override
  String get presetsDeleteTooltip => 'Löschen';

  @override
  String get outputSummarize => 'Zusammenfassen…';

  @override
  String get outputDetectLanguage => 'Sprache erkennen';

  @override
  String get outputSummarizeTitle => 'Transkript zusammenfassen';

  @override
  String outputSummarizeHelp(String model) {
    return 'Sendet das Transkript an $model und fordert eine strukturierte Zusammenfassung an. Ausgabe als Markdown-Aufzählungslisten.';
  }

  @override
  String get outputSummarizeUnconfigured =>
      'Kein Cloud-LLM-Endpunkt konfiguriert. Einstellungen → Cloud-LLM-Bereinigung öffnen, um einen einzurichten — derselbe Endpunkt wird für Bereinigung und Zusammenfassung verwendet.';

  @override
  String get outputSummarizeKindActionItems => 'Aufgaben';

  @override
  String get outputSummarizeKindKeyTopics => 'Wichtige Themen';

  @override
  String get outputSummarizeKindDecisions => 'Entscheidungen';

  @override
  String get outputSummarizeRun => 'Zusammenfassen';

  @override
  String get outputSummarizeEmpty => 'Abschnitte wählen und ausführen.';

  @override
  String get outputSummarizeNothing =>
      'Das Modell hat für die gewählten Abschnitte nichts zurückgegeben.';

  @override
  String get outputCleanup => 'Transkript aufräumen…';

  @override
  String get outputCleanupTitle => 'Transkript aufräumen';

  @override
  String get outputCleanupHelp =>
      'Deterministische Bereinigung typischer ASR-Artefakte. Wähle die gewünschten Schritte, prüfe die Vorschau, dann auf alle anwenden.';

  @override
  String get outputCleanupRemoveFillers => 'Füllwörter entfernen (äh, ähm, …)';

  @override
  String get outputCleanupCollapseRepeats =>
      'Wiederholte Wörter zusammenführen (die die → die)';

  @override
  String get outputCleanupSentenceCase => 'Satzanfänge großschreiben';

  @override
  String get outputCleanupFixPunctuation =>
      'Zeichensetzung korrigieren (doppelte Kommas, Streupunkte)';

  @override
  String get outputCleanupNormalizeWhitespace => 'Leerzeichen normalisieren';

  @override
  String get outputCleanupStripAnnotations => 'Annotations-Tags entfernen';

  @override
  String get outputCleanupStripAnnotationsHelp =>
      'Entfernt [Lachen], (Applaus), <Geräusch>. Standardmäßig aus — nützlich für Barrierefreiheit.';

  @override
  String get outputCleanupCustomFillers => 'Eigene Füllwörter';

  @override
  String get outputCleanupCustomFillersHint =>
      'Mit Komma oder Leerzeichen getrennt, z. B. quasi, sozusagen, halt';

  @override
  String get outputCleanupPreviewHeading => 'Vorschau (erste 3 Segmente)';

  @override
  String get outputCleanupPreviewEmpty => 'Keine Segmente vorhanden.';

  @override
  String get outputCleanupApply => 'Auf alle anwenden';

  @override
  String get outputCleanupLlmPass => 'Zusätzlich LLM-Durchlauf (Cloud)';

  @override
  String outputCleanupLlmPassHelp(String model) {
    return 'Nach dem deterministischen Durchlauf jedes Segment an $model für kontextsensitive Bereinigung schicken. Langsamer; nutzt deinen konfigurierten API-Key.';
  }

  @override
  String get outputCleanupLlmPassUnconfigured =>
      'In Einstellungen → Cloud-LLM-Bereinigung einen Endpunkt einrichten, um diese Option zu aktivieren.';

  @override
  String get outputCleanupLlmRunning => 'LLM-Bereinigung läuft…';

  @override
  String get outputCleanupLlmMode => 'LLM-Durchlauf';

  @override
  String get outputCleanupLlmModeOff => 'Aus';

  @override
  String get outputCleanupLlmModeCloud => 'Cloud';

  @override
  String get outputCleanupLlmModeLocal => 'Lokal';

  @override
  String outputCleanupLlmModeCloudHelp(String model) {
    return 'Nach dem deterministischen Durchlauf jedes Segment an $model (Cloud, BYOK) schicken. Langsamer; nutzt deinen konfigurierten API-Key.';
  }

  @override
  String outputCleanupLlmModeLocalHelp(String model) {
    return 'Nach dem deterministischen Durchlauf jedes Segment lokal durch $model laufen lassen. Kein Netzwerk, kein API-Key; beim ersten Aufruf wird das Modell in den Speicher geladen.';
  }

  @override
  String get outputCleanupLlmModeCloudUnconfigured =>
      'In Einstellungen → Cloud-LLM-Bereinigung einen Endpunkt einrichten, um diese Option zu aktivieren.';

  @override
  String get outputCleanupLlmModeLocalUnconfigured =>
      'In Einstellungen → Lokale LLM-Bereinigung ein GGUF-Chatmodell auswählen, um diese Option zu aktivieren.';

  @override
  String get settingsLocalLlmCleanup =>
      'Lokale LLM-Bereinigung (auf diesem Gerät)';

  @override
  String get settingsLocalLlmCleanupOff =>
      'Aus (ein GGUF-Chatmodell auswählen, um zu aktivieren)';

  @override
  String get settingsLocalLlmHelp =>
      'Optional. Lädt ein GGUF-Chatmodell auf diesem Gerät und nutzt es für jeden Tidy- / Summarize-Durchlauf. Kein Netzwerk, kein API-Key. Benötigt je nach Modellgröße ~2–8 GB freien RAM; Metal- / CUDA-Beschleunigung wird genutzt, wenn verfügbar.';

  @override
  String get settingsLocalLlmModelPath => 'Chatmodell-Datei (GGUF)';

  @override
  String get settingsLocalLlmModelPathEmpty => 'Kein Modell ausgewählt';

  @override
  String get settingsLocalLlmModelPick => 'Durchsuchen…';

  @override
  String get settingsLocalLlmModelClear => 'Leeren';

  @override
  String get settingsLocalLlmAdvanced => 'Erweiterte Parameter';

  @override
  String settingsLocalLlmNGpuLayers(int n) {
    return 'GPU-Layer: $n';
  }

  @override
  String get settingsLocalLlmNGpuLayersAll => 'GPU-Layer: alle';

  @override
  String get settingsLocalLlmNGpuLayersHelp =>
      '-1 = alle Layer auf der GPU (Standard; Metal auf macOS / CUDA auf Linux+Windows, wenn verfügbar). 0 = nur CPU. Positive Werte sind teilweise Offload-Konfigurationen für Geräte mit wenig VRAM.';

  @override
  String settingsLocalLlmNCtx(int n) {
    return 'Kontextfenster (Tokens): $n';
  }

  @override
  String get settingsLocalLlmNCtxDefault => 'Kontextfenster: Modell-Standard';

  @override
  String get settingsLocalLlmNCtxHelp =>
      '0 lässt den im GGUF eingebauten Standard. Höher setzen beim Zusammenfassen langer Transkripte; auf speicherbeschränkten Geräten reduzieren.';

  @override
  String settingsLocalLlmNThreads(int n) {
    return 'CPU-Threads: $n';
  }

  @override
  String get settingsLocalLlmNThreadsAuto => 'CPU-Threads: automatisch';

  @override
  String settingsLocalLlmMaxTokens(int n) {
    return 'Max. Output-Tokens pro Aufruf: $n';
  }

  @override
  String settingsLocalLlmTemperature(String t) {
    return 'Temperatur: $t';
  }

  @override
  String get settingsLocalLlmUnsupported =>
      'Diese libcrispasr-Version stellt das Chat-ABI nicht bereit — benötigt CrispASR 0.7.0 oder neuer.';

  @override
  String get outputCleanupLocalLlmRunning => 'Lokale LLM-Bereinigung läuft…';

  @override
  String get outputCleanupLocalLlmLoading =>
      'Lokales LLM wird geladen (der erste Aufruf kann ein paar Sekunden dauern)…';

  @override
  String get settingsHotkey => 'Globaler Hotkey';

  @override
  String get settingsHotkeyOff =>
      'Aus (Tastenkombination + Verhalten konfigurieren, um zu aktivieren)';

  @override
  String get settingsHotkeyHelp =>
      'Registriert eine systemweite Tastenkombination, mit der du Aufnahmen starten / stoppen kannst, ohne die App in den Vordergrund zu holen. Nur Desktop — iOS / Android bieten keine systemweiten Tastenkombinationen.';

  @override
  String get settingsHotkeyEnable => 'Globalen Hotkey aktivieren';

  @override
  String get settingsHotkeyCombo => 'Tastenkombination';

  @override
  String get settingsHotkeyBehavior => 'Verhalten';

  @override
  String get settingsHotkeyActionPushToTalk => 'Push-to-Talk';

  @override
  String get settingsHotkeyActionPushToTalkHelp =>
      'Halten zum Aufnehmen, loslassen zum Stoppen. Passt gut zu Kombinationen mit Modifier (z. B. meta+shift+space).';

  @override
  String get settingsHotkeyActionToggle => 'Umschalten';

  @override
  String get settingsHotkeyActionToggleHelp =>
      'Einmal drücken zum Starten, erneut drücken zum Stoppen. Einfacheres Modell; kein Halten eines Modifiers nötig.';

  @override
  String settingsHotkeyInvalid(String combo) {
    return 'Ungültige Kombination „$combo\". Format: modifier+modifier+key, z. B. meta+shift+space.';
  }

  @override
  String get settingsCloudLlmCleanup => 'Cloud-LLM-Bereinigung (BYOK)';

  @override
  String get settingsCloudLlmCleanupOff =>
      'Aus (OpenAI-kompatible URL + API-Key eintragen)';

  @override
  String get settingsCloudLlmHelp =>
      'Optional. Sendet jedes Segment an einen OpenAI-kompatiblen /v1/chat/completions-Endpunkt zur kontextsensitiven Bereinigung. Funktioniert mit OpenAI, Anthropic via Proxy, OpenRouter, Groq, lokaler llama-server etc. Dein Schlüssel bleibt auf diesem Gerät.';

  @override
  String get settingsCloudLlmUrl => 'API-URL';

  @override
  String get settingsCloudLlmKey => 'API-Key';

  @override
  String get settingsCloudLlmModel => 'Modell-ID';

  @override
  String get settingsCloudLlmClear => 'Löschen';

  @override
  String outputCleanupApplied(int n) {
    return '$n Segment(e) bereinigt.';
  }

  @override
  String get outputEditSegmentInAudioEditor =>
      'Dieses Segment im Audio-Editor bearbeiten';

  @override
  String get outputMarkSegmentInAudioEditor =>
      'Im Audio-Editor als Splitmarke setzen';

  @override
  String editAudioSegmentSelected(String start, String end) {
    return 'Auswahl gesetzt: $start – $end.';
  }

  @override
  String advancedMaxLen(int n) {
    return 'Max. Tokens pro Segment: $n';
  }

  @override
  String get advancedMaxLenOff => 'aus';

  @override
  String get advancedMaxLenSubtitle =>
      'Nur Whisper. 0 = kein Limit (Standard). Kombiniere mit „An Wortgrenze trennen\" für SRT-taugliche kurze Untertitelzeilen.';

  @override
  String get advancedSplitOnWord => 'An Wortgrenze trennen';

  @override
  String get advancedSplitOnWordSubtitle =>
      'Wenn das Segmentlimit erreicht ist, an der nächsten Wortgrenze umbrechen statt mitten im Wort. Liefert lesbarere Untertitel.';

  @override
  String get advancedVocabulary => 'Benutzerdefiniertes Vokabular';

  @override
  String get advancedVocabularyHint =>
      'Begriff eingeben und Enter drücken (z. B. API, kubectl, Alice)';

  @override
  String get advancedVocabularyAdd => 'Begriff hinzufügen';

  @override
  String get advancedVocabularyHelperPrompt =>
      'Beeinflusst den Whisper-Decoder über initial_prompt. Nützlich für Markennamen, Akronyme, Fachjargon und Personennamen, die das Modell sonst falsch transkribiert.';

  @override
  String get advancedVocabularyHelperAsk =>
      'Beeinflusst das LLM, indem die Begriffe dem Prompt vorangestellt werden. Wird mit Q&A kombiniert — deine Frage läuft weiter.';

  @override
  String get advancedVocabularyHelperUnsupported =>
      'Das aktive Backend ist CTC-basiert und kann das Vokabular nicht im Decoder berücksichtigen. Wechsle zu Whisper / Moonshine / einem LLM-Backend (Voxtral, Qwen3, Granite, …), um diese Funktion zu aktivieren.';

  @override
  String get voiceCloneOpenTooltip => 'Stimme klonen…';

  @override
  String get voiceCloneTitle => 'Stimm-Klon-Assistent';

  @override
  String get voiceCloneStepCapture => 'Aufnahme';

  @override
  String get voiceCloneStepRefText => 'Referenztext';

  @override
  String get voiceCloneStepHandoff => 'Synthese';

  @override
  String get voiceCloneCaptureHeading => 'Referenzaufnahme erstellen';

  @override
  String voiceCloneCaptureHelp(int seconds) {
    return 'Etwa $seconds Sekunden saubere Sprache aufnehmen oder eine bestehende Audiodatei auswählen. Eine Sprecherin / ein Sprecher ohne Störgeräusche liefert die besten Ergebnisse.';
  }

  @override
  String get voiceCloneCaptureNoPermission =>
      'Mikrofonzugriff wurde verweigert. Bitte in den Systemeinstellungen erlauben und erneut versuchen.';

  @override
  String voiceCloneRecord(int seconds) {
    return '$seconds s aufnehmen';
  }

  @override
  String get voiceClonePickFile => 'Datei wählen';

  @override
  String voiceCloneRecordingCountdown(int seconds) {
    return 'noch $seconds s';
  }

  @override
  String get voiceCloneRecordingStop => 'Stopp';

  @override
  String get voiceClonePreviewPlay => 'Wiedergabe';

  @override
  String get voiceClonePreviewPause => 'Pause';

  @override
  String get voiceCloneCaptureClear => 'Neu starten';

  @override
  String get voiceCloneRefTextHeading => 'Was wurde im Clip gesagt?';

  @override
  String get voiceCloneRefTextHelp =>
      'Einige Cloner (indextts, vibevoice) benötigen einen wortgetreuen Transkriptionstext der Referenz für die Ausrichtung. Andere (chatterbox, qwen3-tts Base) klonen nur aus Audio — leer lassen, wenn dein Backend keine Transkription braucht.';

  @override
  String get voiceCloneRefTextLabel => 'Referenztranskription';

  @override
  String get voiceCloneRefTextHint =>
      'Tippe, was im Referenzclip gesagt wurde…';

  @override
  String get voiceCloneHandoffHeading => 'Bereit für die Synthese';

  @override
  String get voiceCloneHandoffHelp =>
      'Wir öffnen die Synthese-Seite mit dem Clip und dem Referenztext vorausgefüllt. Wähle ein klonfähiges Modell (chatterbox, indextts, qwen3-tts Base, vibevoice-1.5b), tippe den gewünschten Text und drücke auf Synthetisieren.';

  @override
  String get voiceCloneHandoffModelHint =>
      'Tipp: chatterbox / qwen3-tts Base klonen aus Audio allein; indextts / vibevoice nutzen zusätzlich den Referenztext.';

  @override
  String get voiceCloneSummaryReference => 'Referenzclip';

  @override
  String get voiceCloneSummaryRefText => 'Referenztext';

  @override
  String get voiceCloneSummaryRefTextEmpty => '(keiner — reines Audio-Cloning)';

  @override
  String get voiceCloneBack => 'Zurück';

  @override
  String get voiceCloneNext => 'Weiter';

  @override
  String get voiceCloneFinish => 'In Synthese öffnen';

  @override
  String get synthTitle => 'Synthese';

  @override
  String get synthModelLabel => 'TTS-Modell';

  @override
  String get synthVoiceLabel => 'Stimme / Voicepack';

  @override
  String get synthCodecLabel => 'Codec / Tokenizer';

  @override
  String get synthTextHint => 'Text zum Synthetisieren eingeben…';

  @override
  String get synthRunButton => 'Synthetisieren';

  @override
  String get synthPlayButton => 'Abspielen';

  @override
  String get synthStopButton => 'Stopp';

  @override
  String get synthShareButton => 'WAV speichern / teilen';

  @override
  String get synthNoTtsModelsDownloaded =>
      'Noch keine TTS-Modelle geladen. Öffne Modelle → Tab „TTS“, um eines herunterzuladen.';

  @override
  String get synthOpenModelManagement => 'Modellverwaltung öffnen';

  @override
  String defaultModelNotDownloaded(String modelId) {
    return 'Standardmodell „$modelId“ ist noch nicht heruntergeladen.';
  }

  @override
  String get noModelsDownloadedYet =>
      'Noch kein Transkriptionsmodell heruntergeladen — öffne „Modelle“, um eines zu laden.';

  @override
  String get filePickerCloudFileUnsupported =>
      'Diese Datei liegt im Cloud-Speicher und kann nicht direkt geöffnet werden. Bitte erst lokal kopieren (Downloads / Dateien auf diesem Gerät) und erneut versuchen.';

  @override
  String filePickerFailed(String error) {
    return 'Dateiauswahl fehlgeschlagen: $error';
  }

  @override
  String get openModels => 'Modelle öffnen';

  @override
  String synthMissingDependency(String name) {
    return 'Fehlende Begleitdatei: $name';
  }

  @override
  String synthBackendUnsupported(String backend) {
    return '$backend-Synthese ist in dieser Version noch nicht verfügbar. Diese Stimme funktioniert, sobald eine aktualisierte Engine ausgeliefert wird.';
  }

  @override
  String get synthSpeakerLabel => 'Sprecher';

  @override
  String get synthSpeakerHelper =>
      'Diese Stimme hat eingebaute Sprecher – bitte einen auswählen.';

  @override
  String get advancedVadBackend => 'VAD-Backend';

  @override
  String get advancedVadBackendHelper =>
      'Silero ist eingebettet (~885 KB). FireRed / MarbleNet / Whisper-VAD müssen über die Modellverwaltung geladen werden; fehlt die Datei, fällt CrisperWeaver auf Silero zurück.';

  @override
  String get advancedVadBackendSilero => 'Silero (eingebettet, Standard)';

  @override
  String get advancedVadBackendFirered => 'FireRedVAD (F1 97,57 %, ~3 MB)';

  @override
  String get advancedVadBackendMarblenet => 'MarbleNet (klein, mehrsprachig)';

  @override
  String get advancedVadBackendWhisperEncDec =>
      'Whisper-VAD-EncDec (experimentell, EN)';

  @override
  String advancedVadThreshold(String value) {
    return 'VAD-Schwelle: $value';
  }

  @override
  String get advancedVadThresholdHelper =>
      'Höher = weniger / kürzere erkannte Sprechabschnitte. CrispASR-Standard: 0,50.';

  @override
  String advancedVadMinSpeech(int ms) {
    return 'Mindest-Sprechdauer: $ms ms';
  }

  @override
  String get advancedVadMinSpeechHelper =>
      'Kürzester gesprochener Abschnitt, der als Sprachsegment erhalten bleibt.';

  @override
  String advancedVadMinSilence(int ms) {
    return 'Mindest-Stilledauer: $ms ms';
  }

  @override
  String get advancedVadMinSilenceHelper =>
      'Kürzeste Stille, die ein Segment vom nächsten trennt.';

  @override
  String advancedVadSpeechPad(int ms) {
    return 'Sprachpolsterung: $ms ms';
  }

  @override
  String get advancedVadSpeechPadHelper =>
      'Zusätzlicher Kontext links und rechts jedes Sprachsegments.';

  @override
  String get advancedLidMethod => 'Sprach-Erkennungsmethode';

  @override
  String get advancedLidMethodHelper =>
      'Nur aktiv, wenn das Modell keine eingebaute Spracherkennung hat und Auto gewählt wurde. Whisper nutzt ein vorhandenes ggml-*.bin; Silero / FireRed / Ecapa benötigen jeweils ihre eigene GGUF.';

  @override
  String get advancedLidMethodWhisper =>
      'Whisper-Encoder (nutzt vorhandenes Modell)';

  @override
  String get advancedLidMethodSilero => 'Silero (95 Sprachen, ~16 MB GGUF)';

  @override
  String get advancedLidMethodFirered => 'FireRed (120 Sprachen, ~300 MB GGUF)';

  @override
  String get advancedLidMethodEcapa => 'ECAPA-TDNN (107 Sprachen, ~42 MB GGUF)';

  @override
  String get advancedGrammarTitle => 'GBNF-Grammatik (nur Whisper)';

  @override
  String get advancedGrammarSubtitle =>
      'Erzwingt strukturierte Ausgabe (JSON / SKU / Telefonnummern / …). Leer = keine Einschränkung.';

  @override
  String get advancedGrammarSubtitleActive =>
      'Grammatik aktiv — die Ausgabe wird durch diese GBNF beschränkt.';

  @override
  String get advancedGrammarTextLabel => 'GBNF-Quelltext';

  @override
  String get advancedGrammarRootRule => 'Startregel';

  @override
  String get advancedGrammarRootRuleHelper =>
      'Symbolname, mit dem das Parsing beginnt. Die GBNF-Konvention ist \"root\".';

  @override
  String advancedGrammarPenalty(String value) {
    return 'Grammatik-Penalty: $value';
  }

  @override
  String get advancedGrammarPenaltyHelper =>
      'Höher = härtere Einschränkung, niedriger = weichere Empfehlung. Upstream-Standard ist 100; sinnvoller Bereich 50..200.';

  @override
  String get advancedTranscribeWindowTitle =>
      'Transkriptions-Fenster (Offset + Dauer)';

  @override
  String get advancedTranscribeWindowSubtitle =>
      'Nur einen [Start, Start+Dauer)-Ausschnitt der Audio verarbeiten. Leer / 0 = gesamte Datei (Standard).';

  @override
  String advancedTranscribeWindowSubtitleActive(String start, String end) {
    return 'Aktiv: ${start}s..${end}s der Datei. Zeitstempel bleiben absolut.';
  }

  @override
  String get advancedTranscribeWindowEndOfFile => 'Datei-Ende';

  @override
  String get advancedTranscribeWindowStart => 'Start (Sekunden)';

  @override
  String get advancedTranscribeWindowStartHelper =>
      'Versatz in die Datei. 0 = Anfang.';

  @override
  String get advancedTranscribeWindowDuration => 'Dauer (Sekunden)';

  @override
  String get advancedTranscribeWindowDurationHelper =>
      '0 = bis zum Datei-Ende transkribieren.';

  @override
  String get advancedFallbackThresholdsTitle => 'Whisper-Decoder-Fallbacks';

  @override
  String get advancedFallbackThresholdsSubtitle =>
      'Steuert, wann der Decoder mit höherer Temperatur erneut decodiert oder Audio als Stille einstuft. Standardwerte entsprechen whisper.cpp.';

  @override
  String get advancedFallbackThresholdsSubtitleActive =>
      'Eigene Schwellen aktiv — Standardwerte sind 2.4 / -1.0 / 0.6 / 0.2.';

  @override
  String get advancedFallbackThresholdsReset => 'Auf Standard zurücksetzen';

  @override
  String advancedEntropyThold(String value) {
    return 'Entropie-Schwelle: $value';
  }

  @override
  String get advancedEntropyTholdHelper =>
      'Token-Entropie, ab der ein Fallback-Durchlauf startet. Standard 2.4. Niedriger = strenger (mehr Wiederholungen); höher gegen exzessive Retries.';

  @override
  String advancedLogprobThold(String value) {
    return 'Logprob-Schwelle: $value';
  }

  @override
  String get advancedLogprobTholdHelper =>
      'Durchschnittliche Log-Wahrscheinlichkeit, ab der ein Fallback-Durchlauf startet. Standard -1.0. Negativer = toleranter gegenüber verrauschter Decodierung.';

  @override
  String advancedNoSpeechThold(String value) {
    return 'Keine-Sprache-Schwelle: $value';
  }

  @override
  String get advancedNoSpeechTholdHelper =>
      'Schwelle des Silence-Detectors. Standard 0.6. Höher = weniger aggressives Stille-Gating (behält leise Sprache).';

  @override
  String advancedTemperatureInc(String value) {
    return 'Temperatur-Inkrement: $value';
  }

  @override
  String get advancedTemperatureIncDisabled =>
      'Temperatur-Inkrement: 0 (Fallback deaktiviert)';

  @override
  String get advancedTemperatureIncHelper =>
      'Temperaturschritt pro Fallback-Durchlauf. Standard 0.2. Auf 0 setzen, um die Fallback-Schleife komplett zu deaktivieren (entspricht --no-fallback).';

  @override
  String get advancedWhisperDecodeExtrasTitle => 'Whisper-Text-Filter';

  @override
  String get advancedWhisperDecodeExtrasSubtitle =>
      'Nicht-Sprach-Marker verwerfen, per Regex passende Tokens unterdrücken oder das Initial-Prompt in jedem Decode-Fenster wiederholen.';

  @override
  String get advancedWhisperDecodeExtrasSubtitleActive =>
      'Eigene Filter aktiv — Standardwerte: alle Tokens behalten / kein Regex / Prompt nur einmal.';

  @override
  String get advancedSuppressNonSpeechTokens => 'Nicht-Sprach-Tokens verwerfen';

  @override
  String get advancedSuppressNonSpeechTokensHelper =>
      'Entfernt [LAUGHTER] / [MUSIC] / [NOISE] aus dem Transkript. Standardmäßig deaktiviert.';

  @override
  String get advancedSuppressTokensRegex => 'Unterdrückungs-Regex (Posix)';

  @override
  String get advancedSuppressTokensRegexHelper =>
      'Tokens, deren Text dem Regex entspricht, werden bei der Decodierung verworfen. Leer deaktiviert. Praktisch gegen halluzinierte Tokens oder Sprecher-Tags.';

  @override
  String get advancedCarryInitialPrompt => 'Initial-Prompt in jedes Fenster';

  @override
  String get advancedCarryInitialPromptHelper =>
      'Wiederholt das Initial-Prompt am Anfang jedes Decode-Fensters (nicht nur am Anfang). Stärkt Vokabular-Bias bei langen Audio-Dateien, schwächt Kontext-Conditioning aus vorherigen Fenstern.';

  @override
  String get advancedEnhanceAudio => 'Audio verbessern (Rauschunterdrückung)';

  @override
  String get advancedEnhanceAudioHelper =>
      'Führt vor der Transkription einen RNNoise-Vorlauf auf dem Audio aus. Reduziert Klima-/Lüfter-/Tastatur-Geräusche. Kosten ~1× Echtzeit auf CPU; standardmäßig deaktiviert.';

  @override
  String get settingsLocalLlmCatalogueTitle => 'Empfohlene Chat-Modelle';

  @override
  String get settingsLocalLlmCatalogueHelp =>
      'Heruntergeladenes Modell antippen, um es auszuwählen. Nicht heruntergeladenes antippen, um zur Modell-Verwaltung zu gehen.';

  @override
  String get settingsLocalLlmCatalogueManage => 'Verwalten';

  @override
  String settingsLocalLlmCatalogueDownloaded(String size) {
    return 'Heruntergeladen · $size';
  }

  @override
  String settingsLocalLlmCatalogueNotDownloaded(String size) {
    return 'Nicht heruntergeladen · $size';
  }

  @override
  String get settingsLocalLlmCatalogueDownload => 'HERUNTERLADEN';

  @override
  String get modelsKindFilterChatLlm => 'Chat-LLM';

  @override
  String get advancedDiarizeMethod => 'Diarisierungs-Methode';

  @override
  String get advancedDiarizeMethodHelper =>
      'Nur wirksam bei aktiver Diarisierung. VAD-Turns ist mono-freundlich; Pyannote benötigt eine eigene GGUF; Energie / Kreuzkorrelation benötigen Stereo.';

  @override
  String get advancedDiarizeVadTurns => 'VAD-Turns (Mono, ohne Zusatzmodell)';

  @override
  String get advancedDiarizePyannote => 'Pyannote v3 (ML, GGUF nötig)';

  @override
  String get advancedDiarizeEnergy => 'Stereo L/R-Energie';

  @override
  String get advancedDiarizeXcorr => 'Stereo-Kreuzkorrelation';

  @override
  String get advancedSpeakerRecognition => 'Eingespeicherte Sprecher erkennen';

  @override
  String get advancedSpeakerRecognitionSubtitle =>
      'Gleicht nach der Diarisierung jeden Sprecher-Cluster mit der lokalen Sprecher-Datenbank (Einstellungen → Sprecher) ab und ersetzt „Sprecher N“ durch den gespeicherten Namen, sobald die Übereinstimmung sicher ist. Benötigt das TitaNet-GGUF.';

  @override
  String get advancedTdrz => 'Tinydiarize-Sprecherwechsel (nur Whisper)';

  @override
  String get advancedTdrzSubtitle =>
      'Fügt [SPEAKER_TURN]-Marker per Whisper .en.tdrz-Finetune ein. Keine Wirkung auf Session-Backends.';

  @override
  String get advancedTokenTimestamps => 'Token-genaue Zeitstempel';

  @override
  String get advancedTokenTimestampsSubtitle =>
      'DTW-ausgerichtete Pro-Token-Zeiten. Langsamer als Wortzeitstempel; nützlich für feinkörnige Untertitel-Tools.';

  @override
  String get advancedAltN => 'Alternative Kandidaten pro Wort (nur Whisper)';

  @override
  String advancedAltNLabel(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Top $n',
      zero: 'Aus',
    );
    return '$_temp0';
  }

  @override
  String get advancedAltNSubtitle =>
      'Erfasst bei jedem Whisper-Greedy-Schritt die Top-N-Alternativtoken. Im Transkript-Editor lässt sich dann auf ein mehrdeutiges Wort tippen, um ein konkurrierendes Kandidat-Token zu wählen (kubectl / Quark / …). 0 = aus (Standard). Funktioniert am besten mit Greedy-Decoding — Beam Search wird nicht unterstützt. Vor Version 0.5.13 wird der Wert ignoriert.';

  @override
  String get advancedPuncFamily => 'Interpunktionsmodell';

  @override
  String get advancedPuncFamilyHelper =>
      'Nur sichtbar, wenn Interpunktion wiederherstellen aktiviert ist. Wahl zwischen FireRedPunc (ZH+EN) und fullstop-punc (EN/DE/FR/IT). Fällt automatisch auf das vorhandene Modell zurück.';

  @override
  String get advancedPuncFamilyFirered => 'FireRedPunc (Chinesisch + Englisch)';

  @override
  String get advancedPuncFamilyFullstop =>
      'Fullstop-punc multilingual (EN/DE/FR/IT)';

  @override
  String get transcriptionSaveAsCsv => 'Als CSV speichern';

  @override
  String get transcriptionSaveAsLrc => 'Als LRC speichern (Lyrics)';

  @override
  String get transcriptionSaveAsWts => 'Als WTS speichern (Debug)';

  @override
  String get transcriptionSaveAsMarkdown => 'Als Markdown speichern';

  @override
  String get transcriptionShareAudioAndTranscript =>
      'Audio + Transkript teilen';

  @override
  String get transcriptionShareAudioAndTranscriptHelp =>
      'Versendet die Audio-Datei zusammen mit dem SRT-Transkript als gemeinsame Freigabe — praktisch für Archivierung oder Übergabe an Kolleg·innen.';

  @override
  String get transcriptionShareAudioMissing =>
      'Erst eine Audio-Datei auswählen, um beides zusammen zu teilen.';

  @override
  String get synthAdvancedSection => 'Erweiterte Synthese';

  @override
  String get synthRefText => 'Referenz-Transkript (Stimmen-Klonen)';

  @override
  String get synthRefTextHelper =>
      'Erforderlich, wenn eine WAV-Stimme mit qwen3-tts Base oder vibevoice-1.5b für Laufzeit-Klonen kombiniert wird. Leer lassen bei vorgebackenen GGUF-Stimmen.';

  @override
  String get synthInstruct => 'Stimm-Beschreibung (nur qwen3-tts VoiceDesign)';

  @override
  String get synthInstructHelper =>
      'Natursprachliche Beschreibung der gewünschten Stimme („warmer weiblicher Erzähler, leichter britischer Akzent“). Wird bei anderen Backends ignoriert.';

  @override
  String get synthTrimSilence => 'Stille beschneiden';

  @override
  String get synthTrimSilenceSubtitle =>
      'Entfernt Stille unter -72 dBFS am Anfang und Ende der synthetisierten PCM.';

  @override
  String synthSpeed(String value) {
    return 'Geschwindigkeit: $value×';
  }

  @override
  String get synthSpeedHelper =>
      'Wiedergabe-Geschwindigkeit (0,25× – 4,00×). Nearest-Neighbor-Resample, ohne Tonhöhenkorrektur.';

  @override
  String get translateTitle => 'Text übersetzen';

  @override
  String get translateModelLabel => 'Übersetzungs-Modell';

  @override
  String get translateSourceLang => 'Von';

  @override
  String get translateTargetLang => 'Nach';

  @override
  String get translateSwap => 'Quell- und Zielsprache tauschen';

  @override
  String get translateInputLabel => 'Quelltext';

  @override
  String get translateInputHint =>
      'Text zum Übersetzen eingeben oder einfügen…';

  @override
  String get translateOutputLabel => 'Übersetzung';

  @override
  String get translateRunButton => 'Übersetzen';

  @override
  String get translateNoModelsDownloaded =>
      'Keine Übersetzungs-Modelle geladen. Öffne Modelle, wechsle auf den Filter „Übersetzen“ und lade M2M-100, WMT21 (en→X / X→en) oder MADLAD-400 herunter.';

  @override
  String get translateAdvanced => 'Erweitert';

  @override
  String translateMaxTokens(int n) {
    return 'Max. Ausgabetoken: $n';
  }

  @override
  String get translateMaxTokensHelper =>
      'Obergrenze für die Länge der Übersetzung. CrispASR-Standard ist 200; höher für lange Passagen, niedriger für schnellere Antworten.';

  @override
  String get advancedPerfHeader => 'Leistung';

  @override
  String get advancedLidUseGpu => 'Sprach-Erkennung auf der GPU';

  @override
  String get advancedLidUseGpuSubtitle =>
      'Leitet die Spracherkennung an Metal / CUDA / Vulkan weiter, falls verfügbar. ASR-Backends nutzen ihre eigene GPU-Initialisierung beim Laden.';

  @override
  String get advancedLidFlashAttn => 'Sprach-Erkennung mit Flash-Attention';

  @override
  String get advancedLidFlashAttnSubtitle =>
      'Schnellerer Attention-Kernel im LID-Encoder. Nur abschalten, wenn ein Flash-Attention-Korrektheits-Bug auf deinem Build vermutet wird.';

  @override
  String advancedNThreads(int n) {
    return 'CPU-Threads: $n';
  }

  @override
  String get advancedNThreadsHelper =>
      'Thread-Anzahl für Spracherkennung und andere Helfer-Pässe. Standard ist 4.';

  @override
  String get synthCustomVoice => 'Eigene Stimme (WAV-Referenz)';

  @override
  String get synthCustomVoiceHelper =>
      'Wählt eine WAV-Datei für Laufzeit-Klonen. Kombiniere mit dem Referenz-Transkript bei qwen3-tts Base / vibevoice-1.5b. Übersteuert das Voicepack-Auswahlmenü, wenn gesetzt.';

  @override
  String get synthCustomVoicePick => 'Referenz-WAV auswählen…';

  @override
  String get synthCustomVoiceReplace => 'Referenz-WAV ersetzen…';

  @override
  String get synthCustomVoiceClear => 'Eigene Stimme entfernen';

  @override
  String get recorderStreamSession => 'Stream (Session)';

  @override
  String get recorderStreamSessionTooltip =>
      'Live-Transkription über den aktiven Backend-Streamer (kyutai-stt / moonshine-streaming / voxtral4b). Fällt auf Whisper-Sliding-Window zurück, wenn das Backend keinen Streaming-Pfad bietet.';

  @override
  String streamingNotAvailableForBackend(String backend) {
    return 'Das aktive Backend ($backend) hat keinen Streaming-Pfad. Wechsle zu whisper, kyutai-stt, moonshine-streaming oder voxtral4b.';
  }

  @override
  String get streamingNoModelLoaded =>
      'Kein Modell geladen. Wähle ein Modell aus dem Dropdown oben (es lädt automatisch, falls heruntergeladen), oder öffne die Modellverwaltung, um zuerst eines herunterzuladen.';

  @override
  String get transcribeNoSource =>
      'Bitte wähle eine Audiodatei, gib eine URL ein oder nimm eine Aufnahme auf.';

  @override
  String get voiceBakeTitle => 'Stimme backen (WAV → GGUF)';

  @override
  String get voiceBakeOpenTooltip =>
      'Erzeugt aus einer WAV-Referenz eine Chatterbox-Stimme';

  @override
  String get voiceBakeIntro =>
      'Ruft CrispASRs bake-chatterbox-voice-from-wav.py auf und wandelt eine WAV-Referenz in ein Voicepack-GGUF um. Benötigt Python 3 mit den Paketen chatterbox-tts und gguf.';

  @override
  String get voiceBakeWavLabel => 'Referenz-WAV';

  @override
  String get voiceBakeWavPick => 'WAV auswählen…';

  @override
  String get voiceBakeOutputName => 'Ausgabe-Dateiname';

  @override
  String get voiceBakeOutputNameHelper =>
      'Wird im Modellverzeichnis neben den anderen Voicepacks abgelegt. Endung .gguf verwenden.';

  @override
  String voiceBakeExaggeration(String value) {
    return 'Übertreibung: $value';
  }

  @override
  String get voiceBakeExaggerationHelper =>
      'Standard-Emotionswert (0,0 – 1,0). Upstream-Vorgabe ist 0,5.';

  @override
  String get voiceBakePythonLabel => 'Python-Interpreter';

  @override
  String get voiceBakePythonHelper =>
      'Standard ist `python3` aus PATH. Überschreibe, wenn deine chatterbox-tts/gguf-Installation in einem venv liegt.';

  @override
  String get voiceBakeScriptLabel => 'Pfad des Bake-Skripts';

  @override
  String get voiceBakeScriptHelper =>
      'Standard ist ../CrispASR/models/bake-chatterbox-voice-from-wav.py. Anpassen, wenn dein CrispASR-Checkout woanders liegt.';

  @override
  String get voiceBakeRun => 'Stimme backen';

  @override
  String get voiceBakeRunning => 'Backe…';

  @override
  String voiceBakeSuccess(String path) {
    return 'Stimme gebacken → $path';
  }

  @override
  String voiceBakeFailure(String error) {
    return 'Backen fehlgeschlagen: $error';
  }

  @override
  String get voiceBakeMissingInputs =>
      'Wähle erst eine Referenz-WAV und einen Ausgabe-Dateinamen.';

  @override
  String get advancedAsrUseGpu => 'ASR auf der GPU';

  @override
  String get advancedAsrUseGpuSubtitle =>
      'Leitet die ASR-Initialisierung an Metal / CUDA / Vulkan weiter, sofern unterstützt. Wird beim nächsten Modell-Laden aktiv. Backends ohne Laufzeit-GPU-Steuerung behalten ihre Compile-Time-Vorgabe.';

  @override
  String get advancedAsrFlashAttn => 'ASR mit Flash-Attention';

  @override
  String get advancedAsrFlashAttnSubtitle =>
      'Verwendet den Flash-Attention-Kernel im ASR-Compute-Graph. Whisper unterstützt das nativ; andere Backends akzeptieren den Schalter, ihr Compute-Graph wird aber noch nicht darauf verzweigt. Wird beim nächsten Modell-Laden aktiv.';

  @override
  String advancedAsrNGpuLayers(int n) {
    return 'GPU-Schichten (LLM): $n';
  }

  @override
  String get advancedAsrNGpuLayersAuto => 'GPU-Schichten (LLM): auto (max.)';

  @override
  String get advancedAsrNGpuLayersHelper =>
      'Obergrenze für GPU-Schichten bei LLM-Backends (orpheus / voxtral / qwen3 / granite / chatterbox). 0 = LLM auf der CPU; 1+ = harte Grenze; auto = so viele wie passen. Wird beim nächsten Modell-Laden aktiv.';

  @override
  String get settingsServerSection => 'Lokaler HTTP-Server (OpenAI-kompatibel)';

  @override
  String get settingsServerEnable => 'Server starten';

  @override
  String settingsServerRunningAt(String url) {
    return 'Lauscht auf $url';
  }

  @override
  String get settingsServerStopped =>
      'Gestoppt. Aktivieren, um die CrisperWeaver-Services auf einem lokalen Port bereitzustellen.';

  @override
  String settingsServerStartFailed(String error) {
    return 'Server konnte nicht starten: $error';
  }

  @override
  String get settingsServerEndpoints => 'Endpunkte';

  @override
  String get settingsServerEndpointsHelp =>
      'POST /v1/audio/transcriptions (Multipart-Upload, file=audio) · POST /v1/audio/speech (JSON: model, input, voice, speed) · POST /v1/translations (JSON: model, text, src, tgt) · GET /health. Bindet nur an 127.0.0.1 — keine Authentifizierung.';

  @override
  String synthTemperature(String value) {
    return 'Temperatur: $value';
  }

  @override
  String get synthTemperatureHelper =>
      'Sampling-Temperatur (gemeinsam für Orpheus / Chatterbox / Canary). 0,0 = greedy / reproduzierbar. Höher = mehr Variation.';

  @override
  String synthTtsSteps(int n) {
    return 'Diffusionsschritte: $n';
  }

  @override
  String get synthTtsStepsHelper =>
      'Anzahl der CFM-Euler-Schritte im Chatterbox-Mel-Decoder (Standard 10). Höher = glatterer Klang, aber höhere Latenz.';

  @override
  String synthCfgWeight(String value) {
    return 'CFG-Gewicht: $value';
  }

  @override
  String get synthCfgWeightHelper =>
      'Classifier-Free-Guidance-Gewicht (Chatterbox). 0 deaktiviert CFG; 0,5 ist die Standardvorgabe; ≥1 verstärkt den konditionalen Pfad.';

  @override
  String synthExaggeration(String value) {
    return 'Übertreibung: $value';
  }

  @override
  String get synthExaggerationHelper =>
      'Emotionswert (Chatterbox). 0,5 ist die Standardvorgabe; höher für dramatischere Ausführung, niedriger für monoton.';

  @override
  String synthTopP(String value) {
    return 'Top-p: $value';
  }

  @override
  String get synthTopPHelper =>
      'Top-p-Nucleus-Sampling-Schwelle (Chatterbox). 1,0 deaktiviert Top-p; kleinere Werte schneiden den unwahrscheinlichen Schwanz ab.';

  @override
  String synthMinP(String value) {
    return 'Min-p: $value';
  }

  @override
  String get synthMinPHelper =>
      'Min-p-Schwelle (Chatterbox). 0 deaktiviert; positive Werte verwerfen Tokens, deren Wahrscheinlichkeit unter diesem Anteil des wahrscheinlichsten Tokens liegt.';

  @override
  String synthRepetitionPenalty(String value) {
    return 'Wiederholungs-Penalty: $value';
  }

  @override
  String get synthRepetitionPenaltyHelper =>
      'Wiederholungs-Penalty-Skalar (Chatterbox). 1,0 deaktiviert; höher entmutigt Schleifenwiederholungen einzelner Tokens.';

  @override
  String synthMaxSpeechTokens(int n) {
    return 'Max. Sprach-Tokens: $n';
  }

  @override
  String get synthMaxSpeechTokensHelper =>
      'Obergrenze für AR-Sprach-Tokens pro Aufruf (Chatterbox). 1000 ≈ 20 s; bei langen Eingaben erhöhen, bei Ausreißern senken.';

  @override
  String get synthClearPhonemeCache => 'Phonem-Cache leeren';

  @override
  String get synthClearPhonemeCacheDone => 'Phonem-Cache geleert.';

  @override
  String get synthClearPhonemeCacheUnsupported =>
      'Dieses Backend verwendet keinen Phonem-Cache (oder die aktive Session ist zu alt).';

  @override
  String modelsLoadFailed(String error) {
    return 'Modelle konnten nicht geladen werden: $error';
  }

  @override
  String modelsProbeFailed(String error) {
    return 'HuggingFace-Abfrage fehlgeschlagen: $error';
  }

  @override
  String modelsSkippedRepos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count private/gesperrte Repos',
      one: '1 privates/gesperrtes Repo',
    );
    return ' $_temp0 übersprungen.';
  }

  @override
  String get modelsHfRepoTitle => 'Aus HuggingFace-Repo hinzufügen';

  @override
  String get modelsHfRepoAddTooltip => 'Aus HuggingFace-Repo hinzufügen…';

  @override
  String get modelsHfReposManageTooltip =>
      'Hinzugefügte HuggingFace-Repos verwalten…';

  @override
  String get modelsHfRepoBody =>
      'Füge eine HuggingFace-Repo-ID ein, z. B. „cstr/voxtral-mini-3b-2507-GGUF“. CrisperWeaver listet jede .gguf-/.bin-Datei im Repo auf, registriert jede als herunterladbares Modell unter dem von dir gewählten Backend und fügt sie zur Modellliste hinzu.';

  @override
  String get modelsHfRepoIdLabel => 'Repo-ID (OWNER/NAME)';

  @override
  String get modelsHfRepoIdHint => 'z. B. cstr/voxtral-mini-3b-2507-GGUF';

  @override
  String get modelsHfRepoBackendLabel => 'Backend';

  @override
  String get modelsHfRepoBackendHelper => 'Wie das Modell geladen werden soll.';

  @override
  String get modelsHfRepoProbe => 'Abfragen';

  @override
  String modelsHfRepoNoneFound(String repo) {
    return 'Keine .gguf-/.bin-Dateien in $repo gefunden.';
  }

  @override
  String modelsHfRepoAdded(int count, String repo) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Modelle',
      one: '1 Modell',
    );
    return '$_temp0 aus $repo hinzugefügt.';
  }

  @override
  String modelsHfRepoProbeFailed(String repo, String error) {
    return 'Abfrage von $repo fehlgeschlagen:\n$error';
  }

  @override
  String get modelsHfReposTitle => 'Hinzugefügte HuggingFace-Repos';

  @override
  String get modelsHfReposEmpty =>
      'Noch keine Repos hinzugefügt. Nutze „Aus HuggingFace-Repo hinzufügen…“, um eines zu registrieren — es bleibt über Neustarts hinweg erhalten.';

  @override
  String modelsHfRepoBackendValue(String backend) {
    return 'Backend: $backend';
  }

  @override
  String get modelsHfRepoForget => 'Dieses Repo entfernen';

  @override
  String get modelsAnyLanguage => 'Beliebige Sprache';

  @override
  String get modelsCategoryEmpty =>
      'Noch keine Modelle in dieser Kategorie — nutze die Cloud-Aktualisierung oder lade zuerst eines aus einer anderen Kategorie herunter.';

  @override
  String get modelsFilterAll => 'Alle';

  @override
  String get modelsFilterAsr => 'ASR';

  @override
  String get modelsFilterTts => 'TTS';

  @override
  String get modelsFilterVoices => 'Stimmen';

  @override
  String get modelsFilterCodecs => 'Codecs';

  @override
  String get modelsFilterPostproc => 'Nachbearbeitung';

  @override
  String get modelsFilterTranslate => 'Übersetzen';

  @override
  String get modelsFilterAllLangs => 'Alle Sprachen';

  @override
  String modelsDownloadedOne(String name) {
    return '$name heruntergeladen';
  }

  @override
  String modelsDownloadedMany(int count, String names) {
    return '$count Dateien heruntergeladen: $names';
  }

  @override
  String modelsDeletedNamed(String name) {
    return '$name gelöscht';
  }

  @override
  String modelsTotalSize(String size) {
    return 'Gesamtgröße: $size';
  }

  @override
  String modelsDownloadFailedNamed(String name) {
    return 'Download von $name fehlgeschlagen';
  }

  @override
  String modelsDownloadFailedReason(String error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String modelsDeleteFailedNamed(String name) {
    return 'Löschen von $name fehlgeschlagen';
  }

  @override
  String modelsDeleteFailedReason(String error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get enrollFromSegment => 'Sprecher aus diesem Segment anlegen…';

  @override
  String get enrollSpeakerTitle => 'Sprecher anlegen';

  @override
  String get enrollSpeakerNameLabel => 'Sprechername';

  @override
  String get enrollSpeakerNameHint => 'z. B. Alex';

  @override
  String get enrollAction => 'Anlegen';

  @override
  String get enrollInProgress => 'Wird angelegt…';

  @override
  String get enrollNoAudio => 'Segment hat kein Audio zum Anlegen.';

  @override
  String enrollSucceeded(String name) {
    return '„$name“ angelegt — künftige Aufnahmen werden zugeordnet.';
  }

  @override
  String get enrollFailedShort => 'Anlegen fehlgeschlagen.';

  @override
  String enrollFailedReason(String error) {
    return 'Anlegen fehlgeschlagen: $error';
  }

  @override
  String get modelsRecommendedBadge => 'Empfohlen';

  @override
  String transcribeNoBackendModelHint(String backend) {
    return 'Noch kein $backend-Modell heruntergeladen.';
  }

  @override
  String transcribeDownloadRecommended(String name, String size) {
    return 'Empfohlenes laden: $name ($size)';
  }

  @override
  String synthDownloadingNamed(String name) {
    return '$name wird heruntergeladen…';
  }

  @override
  String synthDownloadFailedShort(String name) {
    return 'Download von $name fehlgeschlagen';
  }

  @override
  String synthDownloadFailedNamed(String name, String error) {
    return 'Download von $name fehlgeschlagen: $error';
  }
}
