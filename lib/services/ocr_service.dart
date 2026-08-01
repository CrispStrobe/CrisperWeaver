// §12.6b — OCR service wrapping CrispEmbed's VLM OCR engines.
//
// Provides a unified interface for document and math formula OCR
// using CrispEmbed's on-device GGUF models. Each engine is loaded
// lazily on first use and cached for the session lifetime.
//
// Platform: native only (requires libcrispembed). On web, all
// methods return empty results.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../main.dart' show modelServiceProvider;
import '../native/ocr_import.dart';
import 'log_service.dart';
import 'model_service.dart';

/// Result of an OCR operation.
class OcrResult {
  /// Recognized text (e.g. LaTeX for math OCR, plain text for document OCR).
  final String text;

  /// Confidence score (0.0–1.0) if the engine reports one, else null.
  final double? confidence;

  /// Processing time.
  final Duration processingTime;

  const OcrResult({
    required this.text,
    this.confidence,
    this.processingTime = Duration.zero,
  });

  /// EU AI Act Art. 50(2): OCR output is AI-generated text and has to be
  /// marked as such when it leaves the app (clipboard, export, share).
  /// Kept as a separate getter rather than baked into [text] so callers
  /// that only render it on screen — where the surrounding UI already
  /// makes the provenance obvious — aren't forced to strip it out.
  static const String disclosure =
      'AI-generated: recognised by an on-device OCR model. Verify before '
      'relying on it.';

  /// [text] prefixed with the Art. 50(2) disclosure. Empty when there is
  /// no recognised text to disclose.
  String get textWithDisclosure =>
      text.trim().isEmpty ? '' : '[$disclosure]\n\n$text';
}

/// Known OCR model filenames and their engine type.
enum OcrEngine {
  mathOcr('pix2tex'),
  hmerOcr('hmer'),
  bttrOcr('bttr'),
  posformerOcr('posformer'),
  graniteVision('granite-vision'),
  deepseekOcr('deepseek-ocr');

  final String backendPrefix;
  const OcrEngine(this.backendPrefix);
}

/// High-level OCR service backed by CrispEmbed GGUF models.
class OcrService {
  final ModelService modelService;
  OcrService(this.modelService);

  // Cached OCR contexts — one per model path.
  CrispEmbedOcr? _mathOcr;
  CrispEmbedHmerOcr? _hmerOcr;

  /// Recognize math formulas from a grayscale float image.
  ///
  /// [grayPixels] — row-major grayscale float32 values (0.0–1.0).
  /// [width], [height] — image dimensions.
  /// [modelPath] — explicit GGUF path. Required.
  ///
  /// Returns the LaTeX string, or empty text if recognition fails.
  OcrResult recognizeMath(
    Float32List grayPixels,
    int width,
    int height, {
    required String modelPath,
  }) {
    if (grayPixels.isEmpty || width <= 0 || height <= 0) {
      return const OcrResult(text: '');
    }

    final engine = engineForModel(modelPath);
    final sw = Stopwatch()..start();

    try {
      String? text;
      switch (engine) {
        case OcrEngine.hmerOcr:
          _hmerOcr ??= CrispEmbedHmerOcr(modelPath);
          text = _hmerOcr!.recognizeGray(grayPixels, width, height);
        case OcrEngine.mathOcr:
        case null:
        default:
          _mathOcr ??= CrispEmbedOcr(modelPath);
          text = _mathOcr!.recognizeGray(grayPixels, width, height);
      }
      sw.stop();
      Log.instance.i('ocr', 'recognized', fields: {
        'model': p.basename(modelPath),
        'engine': engine?.name ?? 'mathOcr',
        'w': width,
        'h': height,
        'ms': sw.elapsedMilliseconds,
        'len': text?.length ?? 0,
      });
      return OcrResult(
        text: text ?? '',
        processingTime: sw.elapsed,
      );
    } catch (e, st) {
      sw.stop();
      Log.instance.w('ocr', 'recognize failed', error: e, stack: st);
      return OcrResult(text: '', processingTime: sw.elapsed);
    }
  }

  /// Recognize from raw RGB/RGBA pixel bytes.
  OcrResult recognizeRaw(
    Uint8List bytes,
    int width,
    int height,
    int channels, {
    required String modelPath,
  }) {
    if (bytes.isEmpty || width <= 0 || height <= 0) {
      return const OcrResult(text: '');
    }

    final sw = Stopwatch()..start();
    try {
      _mathOcr ??= CrispEmbedOcr(modelPath);
      final text = _mathOcr!.recognizeRaw(bytes, width, height, channels);
      sw.stop();
      return OcrResult(text: text ?? '', processingTime: sw.elapsed);
    } catch (e, st) {
      sw.stop();
      Log.instance.w('ocr', 'recognizeRaw failed', error: e, stack: st);
      return OcrResult(text: '', processingTime: sw.elapsed);
    }
  }

  /// List downloaded OCR model paths from the models directory.
  Future<List<String>> availableModels() async {
    final modelsDir = modelService.whisperCppDir();
    final dir = Directory(modelsDir);
    if (!await dir.exists()) return [];

    final results = <String>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (isOcrModelFilename(name)) {
        results.add(e.path);
      }
    }
    return results;
  }

  /// Release cached OCR contexts.
  void dispose() {
    _mathOcr?.dispose();
    _mathOcr = null;
    _hmerOcr?.dispose();
    _hmerOcr = null;
  }

  /// Check if a filename looks like an OCR model.
  static bool isOcrModelFilename(String filename) {
    final f = filename.toLowerCase();
    if (!f.endsWith('.gguf')) return false;
    for (final engine in OcrEngine.values) {
      if (f.contains(engine.backendPrefix)) return true;
    }
    return false;
  }

  /// Detect which OCR engine a model file belongs to.
  static OcrEngine? engineForModel(String filename) {
    final f = p.basename(filename).toLowerCase();
    for (final engine in OcrEngine.values) {
      if (f.contains(engine.backendPrefix)) return engine;
    }
    return null;
  }
}

final ocrServiceProvider = Provider<OcrService>(
    (ref) => OcrService(ref.watch(modelServiceProvider)));
