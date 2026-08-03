class AppConstants {
  // App Information
  static const String appName = 'CrisperWeaver';
  static const String appDescription =
      'Audio Transcription with Speaker Diarization';
  /// Must match `version:` in pubspec.yaml — this is stamped into the
  /// C2PA provenance manifest (`generatorVersion`) and the WAV `ISFT`
  /// tag, so a stale value is a false provenance claim in exactly the
  /// metadata auditors are asked to trust. It read '1.0.0' while the app
  /// shipped 0.9.5. Guarded by app_version_test.dart.
  static const String appVersion = '0.9.8';
  static const String appBuildNumber = '1';

  // Audio Processing Constants
  static const int defaultSampleRate = 16000;
  static const int defaultChannels = 1;
  static const int defaultBitDepth = 16;
  static const int maxAudioFileSizeMB = 100;
  static const Duration maxAudioDuration = Duration(hours: 2);

  // Transcription Constants
  static const int maxTranscriptionLength = 1000000; // 1M characters
  static const Duration transcriptionTimeout = Duration(minutes: 30);
  static const double defaultConfidenceThreshold = 0.5;

  // Diarization Constants
  static const int minSpeakers = 1;
  static const int maxSpeakers = 10;
  static const int defaultMaxSpeakers = 6;
  static const double silenceThreshold = 0.01;
  static const Duration minSilenceDuration = Duration(milliseconds: 500);
  static const Duration minSegmentDuration = Duration(seconds: 1);

  // Model Constants
  static const List<String> supportedModelSizes = [
    'tiny',
    'base',
    'small',
    'medium',
    'large',
    'large-v2',
    'large-v3',
  ];

  static const Map<String, int> modelSizeMB = {
    'tiny': 39,
    'base': 74,
    'small': 244,
    'medium': 769,
    'large': 1550,
    'large-v2': 1550,
    'large-v3': 1550,
  };

  // Language Codes
  static const Map<String, String> supportedLanguages = {
    'auto': 'Auto-detect',
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean',
    'ar': 'Arabic',
    'el': 'Greek',
    'he': 'Hebrew',
    'fa': 'Persian',
    'id': 'Indonesian',
    'ms': 'Malay',
    'mk': 'Macedonian',
    'sr': 'Serbian',
    'sw': 'Swahili',
    'ha': 'Hausa',
    'hi': 'Hindi',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'nl': 'Dutch',
    'tr': 'Turkish',
    'pl': 'Polish',
    'sv': 'Swedish',
    'da': 'Danish',
    'no': 'Norwegian',
    'fi': 'Finnish',
    'uk': 'Ukrainian',
    'bg': 'Bulgarian',
    'hr': 'Croatian',
    'cs': 'Czech',
    'et': 'Estonian',
    'lv': 'Latvian',
    'lt': 'Lithuanian',
    'hu': 'Hungarian',
    'ro': 'Romanian',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'ca': 'Catalan',
    'eu': 'Basque',
    'gl': 'Galician',
    'is': 'Icelandic',
    'mt': 'Maltese',
    'cy': 'Welsh',
    'ga': 'Irish',
    'gd': 'Scottish Gaelic',
    'br': 'Breton',
    'fo': 'Faroese',
    'kw': 'Cornish',
    'mg': 'Malagasy',
    'mi': 'Maori',
    'oc': 'Occitan',
    'rm': 'Romansh',
    'sc': 'Sardinian',
    'tl': 'Tagalog',
    'ty': 'Tahitian',
  };

  // Audio File Extensions
  static const List<String> supportedAudioExtensions = [
    '.wav',
    '.mp3',
    '.m4a',
    '.aac',
    '.ogg',
    '.flac',
    '.opus',
    '.webm',
    '.mp4',
    '.wma',
    '.aiff',
    '.au',
    '.amr',
    '.ra',
  ];

  // URL Patterns
  static const String youTubeUrlPattern =
      r'(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[\w-]+';
  static const String soundCloudUrlPattern =
      r'(https?://)?(www\.)?soundcloud\.com/[\w-]+/[\w-]+';
  static const String audioUrlPattern =
      r'(https?://.*\.(?:wav|mp3|m4a|aac|ogg|flac|opus|webm))';

  // UI Constants
  static const double borderRadius = 8.0;
  static const double cardElevation = 2.0;
  static const double iconSize = 24.0;
  static const double buttonHeight = 48.0;
  static const double inputHeight = 56.0;

  // Animation Durations
  static const Duration shortAnimationDuration = Duration(milliseconds: 200);
  static const Duration mediumAnimationDuration = Duration(milliseconds: 400);
  static const Duration longAnimationDuration = Duration(milliseconds: 600);

  // Debounce Durations
  static const Duration searchDebounce = Duration(milliseconds: 500);
  static const Duration inputDebounce = Duration(milliseconds: 300);

  // Cache Settings
  static const Duration cacheExpiration = Duration(hours: 24);
  static const int maxCacheSize = 50; // MB
  static const int maxRecentFiles = 20;

  // Network Settings
  static const Duration httpTimeout = Duration(seconds: 30);
  static const Duration downloadTimeout = Duration(minutes: 10);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // File Size Limits
  static const int maxFileSizeBytes = 100 * 1024 * 1024; // 100MB
  static const int maxModelSizeBytes = 2 * 1024 * 1024 * 1024; // 2GB

  // Feature Flags
  static const bool enableDiarization = true;
  static const bool enableWordTimestamps = true;
  static const bool enableNoiseReduction = true;
  static const bool enableAutoSave = true;
  static const bool enableAnalytics = false;

  // Privacy Settings
  static const bool collectUsageData = false;
  static const bool sendCrashReports = false;
  static const bool enableCloudSync = false;

  // Synthetic content compliance
  static const bool enableAudioWatermark = true;
  static const bool enableSyntheticDisclosure = true;
  static const int watermarkMagic = 0x43573031; // ASCII 'CW01'

  // Default Settings Keys
  static const String keyPreferredBackend = 'preferred_backend';
  static const String keyDefaultModel = 'default_model';
  static const String keyDefaultLanguage = 'default_language';
  static const String keyAutoDetectLanguage = 'auto_detect_language';
  static const String keyEnableWordTimestamps = 'enable_word_timestamps';
  static const String keyKeepAudioFiles = 'keep_audio_files';
  static const String keyAudioQuality = 'audio_quality';
  static const String keyEnableDiarizationByDefault =
      'enable_diarization_by_default';
  static const String keyThemeMode = 'theme_mode';
  static const String keyFirstLaunch = 'first_launch';
  static const String keyLastUpdateCheck = 'last_update_check';

  // Error Messages
  static const String errorFileNotFound = 'File not found';
  static const String errorFileTooBig = 'File is too large';
  static const String errorUnsupportedFormat = 'Unsupported file format';
  static const String errorNetworkConnection = 'Network connection error';
  static const String errorPermissionDenied = 'Permission denied';
  static const String errorInsufficientStorage = 'Insufficient storage space';
  static const String errorModelNotFound = 'Model not found';
  static const String errorTranscriptionFailed = 'Transcription failed';
  static const String errorDiarizationFailed = 'Speaker diarization failed';
  static const String errorAudioProcessing = 'Audio processing error';

  // Success Messages
  static const String successTranscriptionComplete =
      'Transcription completed successfully';
  static const String successModelDownloaded = 'Model downloaded successfully';
  static const String successFileSaved = 'File saved successfully';
  static const String successFileShared = 'File shared successfully';
  static const String successCacheCleared = 'Cache cleared successfully';

  // Help URLs
  static const String helpUrl =
      'https://github.com/crisperweaver/flutter-app/wiki';
  static const String documentationUrl =
      'https://github.com/crisperweaver/flutter-app/blob/main/README.md';
  static const String issuesUrl =
      'https://github.com/crisperweaver/flutter-app/issues';
  static const String privacyPolicyUrl =
      'https://github.com/CrispStrobe/CrisperWeaver/blob/main/PRIVACY.md';
  static const String licenseUrl =
      'https://github.com/crisperweaver/flutter-app/blob/main/LICENSE';

  // Model Download URLs
  static const String whisperCppModelsUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/';

  // Regular Expressions
  static final RegExp filenameRegex = RegExp(r'[<>:"/\\|?*]');
  static final RegExp urlRegex = RegExp(r'https?://[^\s]+');
  static final RegExp timeCodeRegex = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})');

  // Audio Processing Parameters
  static const int fftSize = 2048;
  static const int hopLength = 512;
  static const int melBins = 80;
  static const int mfccCoefficients = 13;
  static const double preEmphasisAlpha = 0.97;
  static const double hammingWindowAlpha = 0.54;

  // Diarization Parameters
  static const int diarizationFrameRate = 100; // frames per second
  static const int embeddingDimension = 256;
  static const double speakerThreshold = 0.75;
  static const int minSpeechFrames = 30; // 0.3 seconds at 100fps
  static const int minSilenceFrames = 10; // 0.1 seconds at 100fps

  // Performance Settings
  static const int maxConcurrentTranscriptions = 1;
  static const int audioChunkSize = 1024;
  static const int maxMemoryUsageMB = 500;
  static const Duration memoryCheckInterval = Duration(seconds: 10);

  // Testing Constants
  static const String testAudioPath = 'assets/test_audio.wav';
  static const String testModelPath = 'assets/test_model.bin';
  static const Duration testTimeout = Duration(seconds: 5);

  // Build Configurations
  static const bool isDebugMode =
      bool.fromEnvironment('DEBUG', defaultValue: false);
  static const bool isProfileMode =
      bool.fromEnvironment('PROFILE', defaultValue: false);
  static const bool isReleaseMode =
      bool.fromEnvironment('RELEASE', defaultValue: true);

  // Platform-specific Constants
  static const String iosAppId = 'com.crispstrobe.crisperweaver';
  static const String androidPackageName = 'com.crispstrobe.crisperweaver';
  static const String windowsAppId = 'CrisperWeaver.Flutter';
  static const String macosAppId = 'com.crispstrobe.crisperweaver';
  static const String linuxAppId = 'com.crispstrobe.crisperweaver';

  // Minimum Platform Versions
  static const String minIosVersion = '13.0';
  static const String minAndroidVersion = '21'; // API level 21 (Android 5.0)
  static const String minMacosVersion = '10.15';

  // Hardware Requirements
  static const int minRamMB = 1024; // 1GB
  static const int recommendedRamMB = 2048; // 2GB
  static const int minStorageSpaceMB = 500; // 500MB
  static const int recommendedStorageSpaceMB = 2048; // 2GB

  // Accessibility
  static const Duration semanticsDebounce = Duration(milliseconds: 100);
  static const double minTouchTargetSize = 44.0;
  static const double minContrastRatio = 4.5;

  // Security
  static const bool enableSslPinning = true;
  static const bool validateCertificates = true;
  static const Duration sessionTimeout = Duration(hours: 24);

  // Logging
  static const int maxLogFileSize = 5 * 1024 * 1024; // 5MB
  static const int maxLogFiles = 5;
  static const bool enableVerboseLogging = isDebugMode;

  // Update Check
  static const Duration updateCheckInterval = Duration(days: 7);
  static const String updateCheckUrl =
      'https://api.github.com/repos/crisperweaver/flutter-app/releases/latest';

  // Utility Methods
  static String getModelFileName(String modelName) {
    return 'ggml-$modelName.bin';
  }

  static String getLanguageName(String languageCode) {
    return supportedLanguages[languageCode] ?? languageCode;
  }

  static bool isLanguageSupported(String languageCode) {
    return supportedLanguages.containsKey(languageCode);
  }

  static bool isAudioFile(String filePath) {
    final extension = filePath.toLowerCase();
    return supportedAudioExtensions.any((ext) => extension.endsWith(ext));
  }

  static bool isUrlSupported(String url) {
    return RegExp(youTubeUrlPattern).hasMatch(url) ||
        RegExp(soundCloudUrlPattern).hasMatch(url) ||
        RegExp(audioUrlPattern).hasMatch(url);
  }

  static Duration parseTimeCode(String timeCode) {
    final match = timeCodeRegex.firstMatch(timeCode);
    if (match != null) {
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      final seconds = int.parse(match.group(3)!);
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }
    return Duration.zero;
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
  }
}
