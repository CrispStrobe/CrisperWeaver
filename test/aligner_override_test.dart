// Issue #35 — "broken workflows all over": the Advanced-options aligner
// dropdown stores catalogue KEYS ('canary-ctc-aligner-q4_k'), while
// AlignerService.findAligner treated `explicit` as a filesystem PATH.
// File(key).existsSync() was always false, so the service logged
// "explicit aligner path not found" and fell back to auto-detection —
// every non-Auto choice behaved exactly like Auto.
//
// These tests pin the resolution rules: an existing path still wins
// (CLI / older callers), a catalogue key resolves against the models
// dir, and a key whose GGUF isn't downloaded resolves to null so the
// caller can warn and fall back instead of pretending it worked.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisper_weaver/services/aligner_service.dart';
import 'package:crisper_weaver/widgets/advanced_options_widget.dart'
    show alignerModelLabels;

void main() {
  group('AlignerService.resolveAlignerOverride', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('aligner_override_test');
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('an existing file path is returned unchanged (back-compat)', () {
      final f = File(p.join(tmp.path, 'hand-picked-aligner.gguf'))
        ..writeAsStringSync('gguf');
      expect(
        AlignerService.resolveAlignerOverride(f.path, modelsDirPath: tmp.path),
        f.path,
      );
    });

    test('a catalogue key resolves to the downloaded file in the models dir',
        () {
      final fileName = AlignerService.catalogFileName('canary-ctc-aligner-q4_k');
      expect(fileName, isNotNull,
          reason: 'the catalogue must know the key the dropdown stores');
      File(p.join(tmp.path, fileName!)).writeAsStringSync('gguf');

      expect(
        AlignerService.resolveAlignerOverride('canary-ctc-aligner-q4_k',
            modelsDirPath: tmp.path),
        p.join(tmp.path, fileName),
      );
    });

    test('a catalogue key whose GGUF is missing resolves to null', () {
      // Nothing on disk → null, which is the caller's signal to warn
      // (naming the model) and fall back to auto-detection.
      expect(
        AlignerService.resolveAlignerOverride('canary-ctc-aligner-q4_k',
            modelsDirPath: tmp.path),
        isNull,
      );
    });

    test('a bare file name in the models dir is accepted, with or without '
        'the .gguf suffix', () {
      File(p.join(tmp.path, 'custom-forced-aligner.gguf'))
          .writeAsStringSync('gguf');

      expect(
        AlignerService.resolveAlignerOverride('custom-forced-aligner.gguf',
            modelsDirPath: tmp.path),
        p.join(tmp.path, 'custom-forced-aligner.gguf'),
      );
      expect(
        AlignerService.resolveAlignerOverride('custom-forced-aligner',
            modelsDirPath: tmp.path),
        p.join(tmp.path, 'custom-forced-aligner.gguf'),
      );
    });

    test('an empty override resolves to null', () {
      expect(
        AlignerService.resolveAlignerOverride('', modelsDirPath: tmp.path),
        isNull,
      );
    });

    test('resolution is pure when both probes are injected', () {
      final probed = <String>[];
      final resolved = AlignerService.resolveAlignerOverride(
        'some-aligner-key',
        modelsDirPath: '/models',
        fileNameFor: (name) =>
            name == 'some-aligner-key' ? 'some-aligner.gguf' : null,
        fileExists: (path) {
          probed.add(path);
          return path == p.join('/models', 'some-aligner.gguf');
        },
      );
      expect(resolved, p.join('/models', 'some-aligner.gguf'));
      // The raw override is probed first (path form), then the
      // catalogue-resolved file name.
      expect(probed.first, 'some-aligner-key');
      expect(probed, contains(p.join('/models', 'some-aligner.gguf')));
    });

    test('an unknown key with nothing on disk resolves to null', () {
      expect(
        AlignerService.resolveAlignerOverride(
          'no-such-model',
          modelsDirPath: '/models',
          fileNameFor: (_) => null,
          fileExists: (_) => false,
        ),
        isNull,
      );
    });
  });

  group('aligner picker offerings (#35)', () {
    test('every key the dropdown offers exists in the catalogue', () {
      // A key with no catalogue entry can never resolve to a file, so
      // it would silently behave as "Auto" — the exact bug this fixes.
      for (final key in alignerModelLabels.keys) {
        expect(AlignerService.catalogFileName(key), isNotNull,
            reason: 'aligner dropdown offers "$key", which the catalogue '
                'cannot map to a file name');
      }
    });
  });
}
