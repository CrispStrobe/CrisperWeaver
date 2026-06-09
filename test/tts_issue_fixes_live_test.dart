// Live integration tests for the May 2026 TTS bug-fix batch (GitHub
// issues #16 / #17 / #18). These require a real libcrispasr dylib and
// downloaded model files — they exercise the actual FFI paths that the
// pure-Dart unit tests in tts_issue_fixes_test.dart can't reach.
//
// Tag-gated under `slow` so `flutter test` (and CI) skips them.
// They silently skip (not fail) when the lib or model files are absent.
//
// Running locally (macOS example):
//   CRISPASR_LIB=/path/to/libcrispasr.dylib \
//     flutter test --tags slow test/tts_issue_fixes_live_test.dart
//
// What's pinned:
//   * #16 — availableBackends() does NOT list 'piper' on the current
//     dylib, confirming the guard in TtsService.prepare() is needed.
//   * #17 — opening a qwen3-tts CustomVoice GGUF actually exposes
//     preset speakers, and setSpeakerName + synthesize produces audio.
//   * #18 — the static catalog models resolve to real on-disk GGUFs
//     (when downloaded) and open successfully.

@Tags(['slow'])
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

import 'package:crisper_weaver/services/model_service.dart';

/// Resolve the libcrispasr dylib path from env or sibling repo build.
String? _resolveLibPath() {
  final env = Platform.environment['CRISPASR_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  const candidates = [
    '../CrispASR/build-flutter-bundle/src/libwhisper.dylib',
    '../CrispASR/build/src/libwhisper.dylib',
    '../CrispASR/build-flutter-bundle/src/libcrispasr.dylib',
    '../CrispASR/build/src/libcrispasr.dylib',
    // Linux .so
    '../CrispASR/build-flutter-bundle/src/libwhisper.so',
    '../CrispASR/build/src/libwhisper.so',
    '../CrispASR/build-flutter-bundle/src/libcrispasr.so',
    '../CrispASR/build/src/libcrispasr.so',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return File(c).absolute.path;
  }
  return null;
}

/// Resolve a model file by catalog name. Checks:
///   1. CRISPASR_MODELS_DIR env var + fileName
///   2. ../CrispASR/models/ + fileName
String? _resolveModel(String catalogName) {
  final def = ModelService.crispasrBackendModels[catalogName];
  if (def == null) return null;
  final fileName = def.fileName;

  final envDir = Platform.environment['CRISPASR_MODELS_DIR'];
  if (envDir != null && envDir.isNotEmpty) {
    final f = File('$envDir/$fileName');
    if (f.existsSync()) return f.absolute.path;
  }
  const dirs = [
    '../CrispASR/models',
    '../CrispASR/build-flutter-bundle/models',
  ];
  for (final d in dirs) {
    final f = File('$d/$fileName');
    if (f.existsSync()) return f.absolute.path;
  }
  return null;
}

void main() {
  final libPath = _resolveLibPath();
  final libSkip = libPath == null
      ? 'libcrispasr dylib not found — build CrispASR or set CRISPASR_LIB.'
      : null;

  group('#16 — piper backend gate (live)', () {
    test('availableBackends() lists piper on current dylib', () {
      // Piper is now wired in the unified session dispatch
      // (CA_HAVE_PIPER). The TtsService guard auto-passes.
      final backends =
          crispasr.CrispasrSession.availableBackends(libPath: libPath);
      expect(backends, isNotEmpty,
          reason: 'dylib should report at least one TTS backend');
      expect(backends.contains('piper'), isTrue,
          reason: 'piper should be in availableBackends — '
              'if this fails, the dylib was built without CA_HAVE_PIPER');
    }, skip: libSkip);

    test('piper catalog entry exists and backend matches', () {
      final def =
          ModelService.crispasrBackendModels['piper-en-libritts-r-medium'];
      expect(def, isNotNull);
      expect(def!.backend, 'piper');
    }, skip: libSkip);
  });

  group('#17 — qwen3-tts CustomVoice speaker enumeration (live)', () {
    final customVoicePath =
        _resolveModel('qwen3-tts-12hz-0.6b-customvoice-q8_0');
    final codecPath = _resolveModel('qwen3-tts-tokenizer-12hz');
    final modelSkip = customVoicePath == null
        ? 'qwen3-tts CustomVoice GGUF not found on disk.'
        : codecPath == null
            ? 'qwen3-tts-tokenizer-12hz codec not found on disk.'
            : null;
    final skip = libSkip ?? modelSkip;

    test('session opens and reports preset speakers', () {
      final session = crispasr.CrispasrSession.open(
        customVoicePath!,
        backend: 'qwen3-tts',
        libPath: libPath,
      );
      try {
        session.setCodecPath(codecPath!);
        expect(session.isCustomVoice(), isTrue,
            reason: 'CustomVoice GGUF should report isCustomVoice=true');
        final speakers = session.speakers();
        expect(speakers, isNotEmpty,
            reason: 'CustomVoice should expose preset speaker names');
        // Verify speaker names are non-empty strings.
        for (final s in speakers) {
          expect(s.trim(), isNotEmpty,
              reason: 'speaker name should not be blank');
        }
      } finally {
        session.close();
      }
    }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

    test('setSpeakerName + synthesize produces non-empty audio', () {
      final session = crispasr.CrispasrSession.open(
        customVoicePath!,
        backend: 'qwen3-tts',
        libPath: libPath,
      );
      try {
        session.setCodecPath(codecPath!);
        final speakers = session.speakers();
        expect(speakers, isNotEmpty);
        session.setSpeakerName(speakers.first);
        final pcm = session.synthesize('Hello, this is a test.');
        expect(pcm.length, greaterThan(0),
            reason: 'CustomVoice with a speaker set should produce audio');
        // Sanity: at least 0.1 seconds of audio at 24 kHz.
        expect(pcm.length, greaterThan(2400));
      } finally {
        session.close();
      }
    }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

    test('synthesize WITHOUT setSpeakerName produces empty or no audio', () {
      // This is the actual bug from #17 — without a speaker, CustomVoice
      // returns nothing. Documenting the behaviour so future devs know
      // the guard is necessary.
      final session = crispasr.CrispasrSession.open(
        customVoicePath!,
        backend: 'qwen3-tts',
        libPath: libPath,
      );
      try {
        session.setCodecPath(codecPath!);
        // Deliberately skip setSpeakerName.
        try {
          final pcm = session.synthesize('Hello, this is a test.');
          // The backend either throws or returns empty/silent audio.
          // Either outcome confirms the bug #17 described.
          expect(pcm.length, lessThan(2400),
              reason: 'without a speaker, CustomVoice should produce '
                  'little or no audio (the #17 bug)');
        } catch (e) {
          // Expected — "synthesis returned no audio" is the #17 error.
          expect(e.toString(), contains('no audio'));
        }
      } finally {
        session.close();
      }
    }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('#18 — statically catalogued models open successfully (live)', () {
    const modelsToTest = [
      'qwen3-tts-12hz-0.6b-base-q8_0',
      'qwen3-tts-12hz-0.6b-customvoice-q8_0',
      'chatterbox-turbo-t3-q8_0',
    ];

    for (final modelName in modelsToTest) {
      test('$modelName opens a valid session', () {
        final modelPath = _resolveModel(modelName);
        final def = ModelService.crispasrBackendModels[modelName]!;
        final session = crispasr.CrispasrSession.open(
          modelPath!,
          backend: def.backend,
          libPath: libPath,
        );
        try {
          // If the model needs a codec companion, set it.
          for (final companion in def.companions) {
            final compDef =
                ModelService.crispasrBackendModels[companion];
            if (compDef != null && compDef.kind == ModelKind.codec) {
              final compPath = _resolveModel(companion);
              if (compPath != null) {
                session.setCodecPath(compPath);
              }
            }
          }
          expect(session.backend, isNotEmpty,
              reason: '$modelName should report a backend');
        } finally {
          session.close();
        }
      },
          skip: libSkip ??
              (_resolveModel(modelName) == null
                  ? '$modelName GGUF not found on disk.'
                  : null),
          timeout: const Timeout(Duration(minutes: 3)));
    }
  });

  // ================================================================
  // June 2026 batch — issues #20 / #21 / #22 / #23
  // ================================================================

  group('#20 — pocket-tts Mimi CPU scheduler (live)', () {
    final pocketPath = _resolveModel('pocket-tts-english-f16');
    final modelSkip = pocketPath == null
        ? 'pocket-tts-english-f16 GGUF not found.'
        : null;
    final skip = libSkip ?? modelSkip;

    test('pocket-tts synthesize produces valid PCM (not noise)', () {
      final session = crispasr.CrispasrSession.open(
        pocketPath!,
        backend: 'pocket-tts',
        libPath: libPath,
      );
      try {
        final pcm = session.synthesize('Hello.');
        expect(pcm.length, greaterThan(2400),
            reason: 'should produce >0.1s at 24 kHz');
        // All samples should be finite (no NaN from GPU corruption).
        int finite = 0;
        double maxAbs = 0;
        for (final s in pcm) {
          if (s.isFinite) {
            finite++;
            final a = s.abs();
            if (a > maxAbs) maxAbs = a;
          }
        }
        expect(finite, pcm.length,
            reason: 'all samples must be finite — NaN means GPU corruption');
        expect(maxAbs, greaterThan(0.001),
            reason: 'output should contain audible signal');
      } finally {
        session.close();
      }
    }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('#21 — piper HiFi-GAN CPU scheduler (live)', () {
    final piperPath = _resolveModel('piper-en-libritts-r-medium');
    final modelSkip = piperPath == null
        ? 'piper GGUF not found.'
        : null;
    final skip = libSkip ?? modelSkip;

    test('piper synthesize produces valid PCM', () {
      final session = crispasr.CrispasrSession.open(
        piperPath!,
        backend: 'piper',
        libPath: libPath,
      );
      try {
        final pcm = session.synthesize('Hello world.');
        expect(pcm.length, greaterThan(2400),
            reason: 'should produce audio');
        int finite = 0;
        for (final s in pcm) {
          if (s.isFinite) finite++;
        }
        expect(finite, pcm.length,
            reason: 'all samples must be finite');
      } finally {
        session.close();
      }
    }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('#22 — qwen3-tts q8_0 produces audio (live)', () {
    final qwenPath = _resolveModel('qwen3-tts-12hz-0.6b-base-q8_0');
    final codecPath = _resolveModel('qwen3-tts-tokenizer-12hz');
    final modelSkip = qwenPath == null
        ? 'qwen3-tts base GGUF not found.'
        : codecPath == null
            ? 'qwen3-tts tokenizer not found.'
            : null;
    final skip = libSkip ?? modelSkip;

    test('qwen3-tts q8_0 synthesize produces non-empty audio', () {
      final session = crispasr.CrispasrSession.open(
        qwenPath!,
        backend: 'qwen3-tts',
        libPath: libPath,
      );
      try {
        session.setCodecPath(codecPath!);
        final pcm = session.synthesize('Hello.');
        expect(pcm.length, greaterThan(2400),
            reason: 'q8_0 should reliably produce audio');
      } finally {
        session.close();
      }
    }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('#23 — orpheus synthesis via Isolate.run (live)', () {
    final orpheusPath = _resolveModel('orpheus-3b-base-q8_0');
    final snacPath = _resolveModel('snac-24khz');
    final modelSkip = orpheusPath == null
        ? 'orpheus GGUF not found.'
        : snacPath == null
            ? 'snac-24khz codec not found.'
            : null;
    final skip = libSkip ?? modelSkip;

    test('orpheus synthesis in background isolate returns valid PCM',
        () async {
      // Mirrors the production Isolate.run path in TtsService.
      final oPath = orpheusPath!;
      final sPath = snacPath!;
      final pcm = await Isolate.run<Float32List>(() {
        final s = crispasr.CrispasrSession.open(oPath, backend: 'orpheus');
        try {
          s.setCodecPath(sPath);
          final speakers = s.speakers();
          if (speakers.isNotEmpty) s.setSpeakerName(speakers.first);
          return s.synthesize('Hello.');
        } finally {
          s.close();
        }
      });
      expect(pcm.length, greaterThan(2400));
      for (int i = 0; i < pcm.length && i < 1000; i++) {
        expect(pcm[i].isFinite, isTrue);
      }
    }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
  });
}
