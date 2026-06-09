import 'dart:io';

import '../native/crispasr_import.dart' as crispasr;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../main.dart' show modelServiceProvider;
import 'log_service.dart';
import 'model_service.dart';

/// Text-to-text translation via CrispASR's `crispasr_session_translate_text`
/// (M2M-100, MAD-LAD, gemma4-e2b's translation head). Sessions are cached
/// per-model so a 1.4 GB GGUF doesn't reopen on every keystroke.
///
/// Lifecycle:
///   final svc = ref.read(textTranslationServiceProvider);
///   final out = await svc.translate(
///     modelName: 'm2m100-418m-q4_k',
///     text: 'Hello world',
///     srcLang: 'en',
///     tgtLang: 'de',
///   );
class TextTranslationService {
  final ModelService modelService;
  TextTranslationService(this.modelService);

  // Cached session keyed by `<modelPath>` so the next call reuses it.
  String? _loadedPath;
  crispasr.CrispasrSession? _session;

  /// Resolve a downloaded model path. Returns null when the file
  /// hasn't been fetched yet — the caller should surface a "download
  /// first" hint.
  Future<String?> _resolvePath(String modelName) async {
    final path = await modelService.getWhisperCppModelPath(modelName);
    if (path == null) return null;
    return await File(path).exists() ? path : null;
  }

  /// Translate [text] from [srcLang] to [tgtLang] using the m2m100
  /// (or other translation-capable) GGUF named [modelName].
  ///
  /// [maxTokens] caps output length; pass 0 to use the C-side default
  /// of 200.
  ///
  /// Throws [TextTranslationException] on every failure mode (model
  /// missing, session open failed, lib too old, C side returned null).
  /// The caller can catch + surface a single SnackBar.
  Future<String> translate({
    required String modelName,
    required String text,
    required String srcLang,
    required String tgtLang,
    int maxTokens = 0,
  }) async {
    final modelPath = await _resolvePath(modelName);
    if (modelPath == null) {
      throw TextTranslationException(
        'Translation model "$modelName" is not downloaded yet. '
        'Open Models → Translate to fetch it first.',
      );
    }

    if (_session == null || _loadedPath != modelPath) {
      _session?.close();
      _session = null;
      _loadedPath = null;
      try {
        // m2m100 / madlad / translate are all the same backend slot
        // on the C side. Pass an explicit hint so loading a file with
        // ambiguous metadata still routes correctly.
        final def = modelService.lookupDefinition(modelName);
        _session = crispasr.CrispasrSession.open(
          modelPath,
          backend: def?.backend,
        );
        _loadedPath = modelPath;
        Log.instance.i('translate', 'session opened', fields: {
          'model': p.basename(modelPath),
          'backend': _session!.backend,
        });
      } catch (e, st) {
        Log.instance
            .e('translate', 'session open failed', error: e, stack: st);
        throw TextTranslationException(
            'Failed to load translation model: $e');
      }
    }

    if (text.trim().isEmpty) return '';

    try {
      final out = _session!.translateText(
        text,
        srcLang,
        tgtLang,
        maxTokens: maxTokens,
      );
      if (out == null) {
        throw const TextTranslationException(
          'CrispASR returned no translation — is the loaded model '
          'actually translation-capable? Re-check the Models screen.',
        );
      }
      Log.instance.i('translate', 'translate done', fields: {
        'src': srcLang,
        'tgt': tgtLang,
        'in_chars': text.length,
        'out_chars': out.length,
      });
      return out;
    } on UnsupportedError catch (e) {
      throw TextTranslationException(
          'libcrispasr is too old: $e — rebuild against CrispASR 0.6+');
    } catch (e, st) {
      Log.instance
          .e('translate', 'translateText threw', error: e, stack: st);
      throw TextTranslationException(e.toString());
    }
  }

  void dispose() {
    _session?.close();
    _session = null;
    _loadedPath = null;
  }

  /// Languages M2M-100 supports as ISO 639-1 codes. Used by the
  /// Translate screen's source/target dropdowns. Pulled from the
  /// upstream M2M-100 paper; superset of `madlad` and `gemma4-e2b`.
  static const List<MapEntry<String, String>> supportedLanguages = [
    MapEntry('af', 'Afrikaans'),
    MapEntry('ar', 'Arabic'),
    MapEntry('az', 'Azerbaijani'),
    MapEntry('be', 'Belarusian'),
    MapEntry('bg', 'Bulgarian'),
    MapEntry('bn', 'Bengali'),
    MapEntry('bs', 'Bosnian'),
    MapEntry('ca', 'Catalan'),
    MapEntry('cs', 'Czech'),
    MapEntry('cy', 'Welsh'),
    MapEntry('da', 'Danish'),
    MapEntry('de', 'German'),
    MapEntry('el', 'Greek'),
    MapEntry('en', 'English'),
    MapEntry('es', 'Spanish'),
    MapEntry('et', 'Estonian'),
    MapEntry('fa', 'Persian'),
    MapEntry('fi', 'Finnish'),
    MapEntry('fr', 'French'),
    MapEntry('ga', 'Irish'),
    MapEntry('gl', 'Galician'),
    MapEntry('gu', 'Gujarati'),
    MapEntry('he', 'Hebrew'),
    MapEntry('hi', 'Hindi'),
    MapEntry('hr', 'Croatian'),
    MapEntry('hu', 'Hungarian'),
    MapEntry('id', 'Indonesian'),
    MapEntry('is', 'Icelandic'),
    MapEntry('it', 'Italian'),
    MapEntry('ja', 'Japanese'),
    MapEntry('ka', 'Georgian'),
    MapEntry('kk', 'Kazakh'),
    MapEntry('km', 'Khmer'),
    MapEntry('kn', 'Kannada'),
    MapEntry('ko', 'Korean'),
    MapEntry('lt', 'Lithuanian'),
    MapEntry('lv', 'Latvian'),
    MapEntry('mk', 'Macedonian'),
    MapEntry('ml', 'Malayalam'),
    MapEntry('mn', 'Mongolian'),
    MapEntry('mr', 'Marathi'),
    MapEntry('ms', 'Malay'),
    MapEntry('mt', 'Maltese'),
    MapEntry('my', 'Burmese'),
    MapEntry('ne', 'Nepali'),
    MapEntry('nl', 'Dutch'),
    MapEntry('no', 'Norwegian'),
    MapEntry('pa', 'Punjabi'),
    MapEntry('pl', 'Polish'),
    MapEntry('ps', 'Pashto'),
    MapEntry('pt', 'Portuguese'),
    MapEntry('ro', 'Romanian'),
    MapEntry('ru', 'Russian'),
    MapEntry('si', 'Sinhala'),
    MapEntry('sk', 'Slovak'),
    MapEntry('sl', 'Slovenian'),
    MapEntry('so', 'Somali'),
    MapEntry('sq', 'Albanian'),
    MapEntry('sr', 'Serbian'),
    MapEntry('sv', 'Swedish'),
    MapEntry('sw', 'Swahili'),
    MapEntry('ta', 'Tamil'),
    MapEntry('te', 'Telugu'),
    MapEntry('th', 'Thai'),
    MapEntry('tl', 'Tagalog'),
    MapEntry('tr', 'Turkish'),
    MapEntry('uk', 'Ukrainian'),
    MapEntry('ur', 'Urdu'),
    MapEntry('vi', 'Vietnamese'),
    MapEntry('xh', 'Xhosa'),
    MapEntry('yi', 'Yiddish'),
    MapEntry('zh', 'Chinese'),
    MapEntry('zu', 'Zulu'),
  ];
}

/// Surfaced to the UI when translation fails — the message is
/// already user-readable, so the screen can drop it straight into a
/// SnackBar.
class TextTranslationException implements Exception {
  final String message;
  const TextTranslationException(this.message);
  @override
  String toString() => 'TextTranslationException: $message';
}

final textTranslationServiceProvider = Provider<TextTranslationService>((ref) {
  final svc = TextTranslationService(ref.watch(modelServiceProvider));
  ref.onDispose(svc.dispose);
  return svc;
});
