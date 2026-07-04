// Unit tests for ScanPreprocessService (§12.6c).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/scan_preprocess_service.dart';

void main() {
  group('ScanPreprocessResult', () {
    test('default has zero duration and empty steps', () {
      final r = ScanPreprocessResult(
        pixels: Uint8List(0),
        width: 0,
        height: 0,
      );
      expect(r.processingTime, Duration.zero);
      expect(r.appliedSteps, isEmpty);
    });
  });

  group('ScanPreprocessConfig', () {
    test('default config has 3 classical steps', () {
      const config = ScanPreprocessConfig();
      expect(config.steps.length, 3);
      expect(config.steps, contains(ScanPreprocessStep.deskew));
      expect(config.steps, contains(ScanPreprocessStep.borderCrop));
      expect(config.steps, contains(ScanPreprocessStep.backgroundWhiten));
      expect(config.denoiseModelPath, isNull);
    });

    test('full config includes denoise with model path', () {
      const config =
          ScanPreprocessConfig.full(denoiseModelPath: '/path/nafnet.gguf');
      expect(config.steps.length, 4);
      expect(config.steps, contains(ScanPreprocessStep.denoise));
      expect(config.denoiseModelPath, '/path/nafnet.gguf');
    });
  });

  group('ScanPreprocessService.validateConfig', () {
    test('valid classical config has no errors', () {
      const config = ScanPreprocessConfig();
      expect(ScanPreprocessService.validateConfig(config), isEmpty);
    });

    test('denoise without model path is an error', () {
      const config = ScanPreprocessConfig(
        steps: [ScanPreprocessStep.denoise],
      );
      final errors = ScanPreprocessService.validateConfig(config);
      expect(errors, isNotEmpty);
      expect(errors.first, contains('NAFNet'));
    });

    test('denoise with model path is valid', () {
      const config = ScanPreprocessConfig(
        steps: [ScanPreprocessStep.denoise],
        denoiseModelPath: '/path/nafnet.gguf',
      );
      expect(ScanPreprocessService.validateConfig(config), isEmpty);
    });

    test('empty steps is an error', () {
      const config = ScanPreprocessConfig(steps: []);
      final errors = ScanPreprocessService.validateConfig(config);
      expect(errors, isNotEmpty);
      expect(errors.first, contains('step'));
    });
  });

  group('ScanPreprocessService.describeSteps', () {
    test('describes classical pipeline', () {
      final desc = ScanPreprocessService.describeSteps(const [
        ScanPreprocessStep.deskew,
        ScanPreprocessStep.borderCrop,
        ScanPreprocessStep.backgroundWhiten,
      ]);
      expect(desc, 'Deskew → Border crop → Background whitening');
    });

    test('describes full pipeline', () {
      final desc = ScanPreprocessService.describeSteps(const [
        ScanPreprocessStep.deskew,
        ScanPreprocessStep.denoise,
      ]);
      expect(desc, 'Deskew → CNN denoise');
    });

    test('empty steps', () {
      expect(ScanPreprocessService.describeSteps(const []), isEmpty);
    });
  });
}
