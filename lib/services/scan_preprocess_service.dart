// §12.6c — Scan/document preprocessing service.
//
// Wraps CrispEmbed's scan cleanup pipeline: deskew, border crop,
// background whitening (classical, no model), and optional CNN
// denoising (NAFNet GGUF). Runs as a preprocessing step before OCR.
//
// Platform: native only (requires libcrispembed).

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/scan_cleanup_import.dart';
import 'log_service.dart';

/// Result of scan preprocessing.
class ScanPreprocessResult {
  /// Processed image pixels (RGB uint8, row-major).
  final Uint8List pixels;

  /// Output width after preprocessing.
  final int width;

  /// Output height after preprocessing.
  final int height;

  /// Processing time.
  final Duration processingTime;

  /// Which steps were applied.
  final List<String> appliedSteps;

  const ScanPreprocessResult({
    required this.pixels,
    required this.width,
    required this.height,
    this.processingTime = Duration.zero,
    this.appliedSteps = const [],
  });
}

/// Preprocessing steps that can be applied to scanned documents.
enum ScanPreprocessStep {
  /// Correct page rotation / skew.
  deskew,

  /// Remove black borders and excess margins.
  borderCrop,

  /// Whiten background for cleaner OCR.
  backgroundWhiten,

  /// CNN-based denoising (requires NAFNet GGUF model).
  denoise,
}

/// Configuration for the scan preprocessing pipeline.
class ScanPreprocessConfig {
  /// Steps to apply, in order.
  final List<ScanPreprocessStep> steps;

  /// Path to the NAFNet GGUF model for denoising (optional).
  /// Required if [ScanPreprocessStep.denoise] is in [steps].
  final String? denoiseModelPath;

  const ScanPreprocessConfig({
    this.steps = const [
      ScanPreprocessStep.deskew,
      ScanPreprocessStep.borderCrop,
      ScanPreprocessStep.backgroundWhiten,
    ],
    this.denoiseModelPath,
  });

  /// Full pipeline including denoising.
  const ScanPreprocessConfig.full({required this.denoiseModelPath})
      : steps = const [
          ScanPreprocessStep.deskew,
          ScanPreprocessStep.borderCrop,
          ScanPreprocessStep.backgroundWhiten,
          ScanPreprocessStep.denoise,
        ];
}

/// Scan preprocessing service.
///
/// The classical steps (deskew, crop, whitening) require no model and
/// run via CrispEmbed's `crispembed_scan_cleanup_*` C API. The denoise
/// step requires a NAFNet GGUF model.
class ScanPreprocessService {
  ScanPreprocessService();

  CrispScanCleanup? _cleanup;

  /// Process a scanned image through the configured pipeline.
  ///
  /// [pixels] — RGB uint8 pixel data, row-major.
  /// [width], [height] — image dimensions.
  /// [config] — preprocessing steps to apply.
  ScanPreprocessResult process(
    Uint8List pixels,
    int width,
    int height, {
    ScanPreprocessConfig config = const ScanPreprocessConfig(),
  }) {
    if (pixels.isEmpty || width <= 0 || height <= 0) {
      return ScanPreprocessResult(
          pixels: Uint8List(0), width: 0, height: 0);
    }

    final sw = Stopwatch()..start();
    try {
      _cleanup ??= CrispScanCleanup(modelPath: config.denoiseModelPath);

      final result = _cleanup!.process(
        pixels,
        width,
        height,
        deskew: config.steps.contains(ScanPreprocessStep.deskew),
        cropBorders: config.steps.contains(ScanPreprocessStep.borderCrop),
        whitenBackground:
            config.steps.contains(ScanPreprocessStep.backgroundWhiten),
      );
      sw.stop();

      return ScanPreprocessResult(
        pixels: result.pixels,
        width: result.width,
        height: result.height,
        processingTime: sw.elapsed,
        appliedSteps: config.steps.map((s) => s.name).toList(),
      );
    } catch (e, st) {
      sw.stop();
      Log.instance.w('scan', 'preprocessing failed', error: e, stack: st);
      return ScanPreprocessResult(
        pixels: pixels,
        width: width,
        height: height,
        processingTime: sw.elapsed,
      );
    }
  }

  void dispose() {
    _cleanup?.dispose();
    _cleanup = null;
  }

  /// Validate a preprocessing config.
  static List<String> validateConfig(ScanPreprocessConfig config) {
    final errors = <String>[];
    if (config.steps.contains(ScanPreprocessStep.denoise) &&
        (config.denoiseModelPath == null ||
            config.denoiseModelPath!.isEmpty)) {
      errors.add('Denoise step requires a NAFNet model path');
    }
    if (config.steps.isEmpty) {
      errors.add('At least one preprocessing step is required');
    }
    return errors;
  }

  /// Build a human-readable description of the pipeline.
  static String describeSteps(List<ScanPreprocessStep> steps) {
    return steps.map((s) {
      switch (s) {
        case ScanPreprocessStep.deskew:
          return 'Deskew';
        case ScanPreprocessStep.borderCrop:
          return 'Border crop';
        case ScanPreprocessStep.backgroundWhiten:
          return 'Background whitening';
        case ScanPreprocessStep.denoise:
          return 'CNN denoise';
      }
    }).join(' → ');
  }
}

final scanPreprocessServiceProvider =
    Provider<ScanPreprocessService>((_) => ScanPreprocessService());
