import 'package:flutter/material.dart';

/// How the spoken language of each utterance is decided.
enum LiveLidMode {
  /// One fixed spoken language ([LiveTranslateConfig.fixedSource]).
  fixed,

  /// Pick the best available: an audio LID model if one is downloaded, else
  /// a text LID model, else what the recogniser reports.
  auto,

  /// Audio LID (ECAPA / FireRed / Silero / Whisper encoder) on the first
  /// seconds of every utterance, before it is transcribed — the only mode
  /// that can steer recognisers which need a language hint.
  audio,

  /// Text LID (CLD3 / fastText-176 / GlotLID) on every committed sentence.
  /// Works with any multilingual recogniser that detects the language
  /// itself (Parakeet v3, SenseVoice, Qwen3-ASR, …) and costs ~nothing.
  text,

  /// The language the recogniser reports (Whisper's own detection).
  recognizer,
}

enum LiveLayout {
  /// One block per sentence: the source line, its translations under it.
  stacked,

  /// One column per language, sentences aligned across columns — the
  /// conference-screen layout.
  columns,
}

enum LiveAudioSource { microphone, systemAudio }

/// Everything the live transcribe + translate screen needs, persisted as
/// JSON through `SettingsService.liveTranslateConfig`.
///
/// The routing table is the heart of it: for each spoken language, the
/// languages to translate into. `fr → [de, en]` means French speech is
/// transcribed and translated into German AND English. A language with an
/// empty list is transcribed only. Speech in a language that has no rule
/// (auto-detection found something unexpected) goes to [defaultTargets].
@immutable
class LiveTranslateConfig {
  const LiveTranslateConfig({
    this.lidMode = LiveLidMode.auto,
    this.fixedSource = 'de',
    this.routes = const {
      'de': ['en'],
      'en': ['de'],
    },
    this.defaultTargets = const ['en'],
    this.asrModel,
    this.translatorModel,
    this.lidModel,
    this.audioSource = LiveAudioSource.microphone,
    this.layout = LiveLayout.stacked,
    this.fontSize = 34,
    this.showSource = true,
    this.showDrafts = true,
    this.darkBackground = true,
    this.hiddenLanguages = const {},
    this.finalSilenceMs = 800,
  });

  final LiveLidMode lidMode;
  final String fixedSource;
  final Map<String, List<String>> routes;
  final List<String> defaultTargets;

  /// Catalog name of the recogniser; null = the app's default ASR model.
  final String? asrModel;

  /// Catalog name of the translator (m2m100 / madlad / a translation chat
  /// LLM); null = transcription only.
  final String? translatorModel;

  /// Catalog name of the LID model to prefer; null = best available.
  final String? lidModel;

  final LiveAudioSource audioSource;
  final LiveLayout layout;
  final double fontSize;

  /// Show the transcript of the spoken language, not only translations.
  final bool showSource;

  /// Show the dimmed open sentence and its draft translation.
  final bool showDrafts;
  final bool darkBackground;

  /// Languages hidden from the display (e.g. a German-only screen).
  final Set<String> hiddenLanguages;

  /// Trailing silence that closes an utterance.
  final int finalSilenceMs;

  static const minFont = 16.0;
  static const maxFont = 120.0;

  /// The languages the spoken language is expected to be one of. Audio /
  /// text LID results outside this set are only accepted when confident.
  Set<String> get expectedSources =>
      lidMode == LiveLidMode.fixed ? {fixedSource} : routes.keys.toSet();

  /// Translation targets for speech in [lang] (never [lang] itself).
  List<String> targetsFor(String lang) {
    final t = routes[lang] ?? defaultTargets;
    return [
      for (final x in t)
        if (x != lang) x
    ];
  }

  /// Every language that can appear on screen, in a stable order: the
  /// spoken languages first, then the targets. Drives the column layout.
  List<String> get displayLanguages {
    final out = <String>[];
    void add(String l) {
      if (!out.contains(l)) out.add(l);
    }

    if (lidMode == LiveLidMode.fixed) {
      add(fixedSource);
      targetsFor(fixedSource).forEach(add);
    } else {
      routes.keys.forEach(add);
      for (final v in routes.values) {
        v.forEach(add);
      }
      defaultTargets.forEach(add);
    }
    return out;
  }

  bool get needsTranslator => lidMode == LiveLidMode.fixed
      ? targetsFor(fixedSource).isNotEmpty
      : routes.values.any((v) => v.isNotEmpty) || defaultTargets.isNotEmpty;

  LiveTranslateConfig copyWith({
    LiveLidMode? lidMode,
    String? fixedSource,
    Map<String, List<String>>? routes,
    List<String>? defaultTargets,
    String? asrModel,
    bool clearAsrModel = false,
    String? translatorModel,
    bool clearTranslatorModel = false,
    String? lidModel,
    bool clearLidModel = false,
    LiveAudioSource? audioSource,
    LiveLayout? layout,
    double? fontSize,
    bool? showSource,
    bool? showDrafts,
    bool? darkBackground,
    Set<String>? hiddenLanguages,
    int? finalSilenceMs,
  }) =>
      LiveTranslateConfig(
        lidMode: lidMode ?? this.lidMode,
        fixedSource: fixedSource ?? this.fixedSource,
        routes: routes ?? this.routes,
        defaultTargets: defaultTargets ?? this.defaultTargets,
        asrModel: clearAsrModel ? null : (asrModel ?? this.asrModel),
        translatorModel: clearTranslatorModel
            ? null
            : (translatorModel ?? this.translatorModel),
        lidModel: clearLidModel ? null : (lidModel ?? this.lidModel),
        audioSource: audioSource ?? this.audioSource,
        layout: layout ?? this.layout,
        fontSize: (fontSize ?? this.fontSize).clamp(minFont, maxFont),
        showSource: showSource ?? this.showSource,
        showDrafts: showDrafts ?? this.showDrafts,
        darkBackground: darkBackground ?? this.darkBackground,
        hiddenLanguages: hiddenLanguages ?? this.hiddenLanguages,
        finalSilenceMs: finalSilenceMs ?? this.finalSilenceMs,
      );

  Map<String, Object?> toJson() => {
        'lidMode': lidMode.name,
        'fixedSource': fixedSource,
        'routes': routes,
        'defaultTargets': defaultTargets,
        'asrModel': asrModel,
        'translatorModel': translatorModel,
        'lidModel': lidModel,
        'audioSource': audioSource.name,
        'layout': layout.name,
        'fontSize': fontSize,
        'showSource': showSource,
        'showDrafts': showDrafts,
        'darkBackground': darkBackground,
        'hiddenLanguages': hiddenLanguages.toList(),
        'finalSilenceMs': finalSilenceMs,
      };

  /// Lenient: unknown or malformed fields fall back to the defaults, so a
  /// config saved by a newer build never crashes an older one.
  factory LiveTranslateConfig.fromJson(Map<String, Object?>? j) {
    const d = LiveTranslateConfig();
    if (j == null) return d;
    T pick<T extends Enum>(List<T> values, Object? v, T fallback) =>
        values.firstWhere((e) => e.name == v, orElse: () => fallback);
    List<String> strList(Object? v, List<String> fallback) =>
        v is List ? [for (final x in v) if (x is String) x] : fallback;
    Map<String, List<String>> routes = d.routes;
    final r = j['routes'];
    if (r is Map) {
      routes = {
        for (final e in r.entries)
          if (e.key is String) e.key as String: strList(e.value, const [])
      };
    }
    return LiveTranslateConfig(
      lidMode: pick(LiveLidMode.values, j['lidMode'], d.lidMode),
      fixedSource: j['fixedSource'] as String? ?? d.fixedSource,
      routes: routes,
      defaultTargets: strList(j['defaultTargets'], d.defaultTargets),
      asrModel: j['asrModel'] as String?,
      translatorModel: j['translatorModel'] as String?,
      lidModel: j['lidModel'] as String?,
      audioSource:
          pick(LiveAudioSource.values, j['audioSource'], d.audioSource),
      layout: pick(LiveLayout.values, j['layout'], d.layout),
      fontSize: ((j['fontSize'] as num?)?.toDouble() ?? d.fontSize)
          .clamp(minFont, maxFont),
      showSource: j['showSource'] as bool? ?? d.showSource,
      showDrafts: j['showDrafts'] as bool? ?? d.showDrafts,
      darkBackground: j['darkBackground'] as bool? ?? d.darkBackground,
      hiddenLanguages:
          strList(j['hiddenLanguages'], const []).toSet(),
      finalSilenceMs: (j['finalSilenceMs'] as num?)?.toInt() ?? d.finalSilenceMs,
    );
  }

  /// One-tap starting points for the routing table.
  static const presets = <String, Map<String, List<String>>>{
    'de ⇄ en': {
      'de': ['en'],
      'en': ['de'],
    },
    'de · en · fr': {
      'de': ['en'],
      'en': ['de'],
      'fr': ['de', 'en'],
    },
    'en ⇄ es': {
      'en': ['es'],
      'es': ['en'],
    },
    'en ⇄ fr': {
      'en': ['fr'],
      'fr': ['en'],
    },
  };
}

/// Stable, distinguishable colours per language, so a viewer learns
/// "blue is English" once and can read a mixed screen at a glance.
///
/// Hues are fixed for the languages most likely to share a screen and
/// hashed for the rest; lightness depends on the background so the same
/// language keeps its hue on dark and light displays.
class LanguageColors {
  static const _hues = <String, double>{
    'de': 42, // amber
    'en': 205, // sky blue
    'fr': 335, // rose
    'es': 22, // orange
    'it': 125, // green
    'pt': 165, // sea green
    'nl': 275, // violet
    'pl': 0, // red
    'ru': 245, // indigo
    'uk': 55, // yellow
    'zh': 12, // vermilion
    'ja': 315, // magenta
    'ko': 225, // blue
    'ar': 150, // emerald
    'tr': 295, // purple
    'cs': 185, // cyan
    'sv': 195,
    'da': 350,
    'hi': 30,
    'el': 215,
  };

  static double hueFor(String lang) {
    final h = _hues[lang];
    if (h != null) return h;
    var x = 0;
    for (final c in lang.codeUnits) {
      x = (x * 31 + c) & 0x7fffffff;
    }
    return (x % 360).toDouble();
  }

  static Color of(String lang, {required bool dark}) => HSLColor.fromAHSL(
        1,
        hueFor(lang),
        dark ? 0.85 : 0.75,
        dark ? 0.70 : 0.33,
      ).toColor();
}

/// ISO 639-3 (GlotLID's `deu_Latn`) → ISO 639-1 for the common languages,
/// so text-LID labels compare against the routing table's two-letter codes.
String normaliseLangCode(String raw) {
  var c = raw.trim().toLowerCase();
  if (c.startsWith('__label__')) c = c.substring(9);
  final us = c.indexOf('_');
  if (us > 0) c = c.substring(0, us);
  final dash = c.indexOf('-');
  if (dash > 0) c = c.substring(0, dash);
  const three = {
    'deu': 'de', 'eng': 'en', 'fra': 'fr', 'spa': 'es', 'ita': 'it',
    'por': 'pt', 'nld': 'nl', 'pol': 'pl', 'rus': 'ru', 'ukr': 'uk',
    'zho': 'zh', 'cmn': 'zh', 'jpn': 'ja', 'kor': 'ko', 'ara': 'ar',
    'arb': 'ar', 'tur': 'tr', 'ces': 'cs', 'swe': 'sv', 'dan': 'da',
    'hin': 'hi', 'ell': 'el', 'fin': 'fi', 'hun': 'hu', 'ron': 'ro',
    'bul': 'bg', 'hrv': 'hr', 'srp': 'sr', 'slk': 'sk', 'slv': 'sl',
    'nor': 'no', 'nob': 'no', 'cat': 'ca', 'heb': 'he', 'vie': 'vi',
    'ind': 'id', 'tha': 'th', 'fas': 'fa', 'pes': 'fa', 'est': 'et',
    'lit': 'lt', 'lav': 'lv', 'ekk': 'et', 'lvs': 'lv',
  };
  return three[c] ?? c;
}

/// The language's own name for itself — what an audience reads fastest
/// next to a caption ("Deutsch", "English", "Français"). Falls back to the
/// upper-cased code.
String languageAutonym(String code) => _autonyms[code] ?? code.toUpperCase();

const _autonyms = {
  'af': 'Afrikaans', 'ar': 'العربية', 'az': 'Azərbaycan', 'be': 'Беларуская',
  'bg': 'Български', 'bn': 'বাংলা', 'bs': 'Bosanski', 'ca': 'Català',
  'cs': 'Čeština', 'cy': 'Cymraeg', 'da': 'Dansk', 'de': 'Deutsch',
  'el': 'Ελληνικά', 'en': 'English', 'es': 'Español', 'et': 'Eesti',
  'fa': 'فارسی', 'fi': 'Suomi', 'fr': 'Français', 'ga': 'Gaeilge',
  'gl': 'Galego', 'gu': 'ગુજરાતી', 'he': 'עברית', 'hi': 'हिन्दी',
  'hr': 'Hrvatski', 'hu': 'Magyar', 'id': 'Bahasa Indonesia',
  'is': 'Íslenska', 'it': 'Italiano', 'ja': '日本語', 'ka': 'ქართული',
  'kk': 'Қазақ', 'km': 'ខ្មែរ', 'kn': 'ಕನ್ನಡ', 'ko': '한국어',
  'lt': 'Lietuvių', 'lv': 'Latviešu', 'mk': 'Македонски', 'ml': 'മലയാളം',
  'mn': 'Монгол', 'mr': 'मराठी', 'ms': 'Bahasa Melayu', 'mt': 'Malti',
  'my': 'မြန်မာ', 'ne': 'नेपाली', 'nl': 'Nederlands', 'no': 'Norsk',
  'pa': 'ਪੰਜਾਬੀ', 'pl': 'Polski', 'ps': 'پښتو', 'pt': 'Português',
  'ro': 'Română', 'ru': 'Русский', 'si': 'සිංහල', 'sk': 'Slovenčina',
  'sl': 'Slovenščina', 'so': 'Soomaali', 'sq': 'Shqip', 'sr': 'Српски',
  'sv': 'Svenska', 'sw': 'Kiswahili', 'ta': 'தமிழ்', 'te': 'తెలుగు',
  'th': 'ไทย', 'tl': 'Tagalog', 'tr': 'Türkçe', 'uk': 'Українська',
  'ur': 'اردو', 'vi': 'Tiếng Việt', 'xh': 'isiXhosa', 'yi': 'ייִדיש',
  'zh': '中文', 'zu': 'isiZulu',
};
