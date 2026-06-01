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
    test('availableBackends() does NOT list piper on current dylib', () {
      // This confirms the guard in TtsService.prepare() is actually
      // necessary on the shipped dylib. When piper IS wired, this test
      // should be updated to expect it present and the guard auto-passes.
      final backends = crispasr.CrispasrSession.availableBackends();
      // The list should be non-empty (kokoro, qwen3-tts, etc. are wired).
      expect(backends, isNotEmpty,
          reason: 'dylib should report at least one TTS backend');
      // Piper is NOT yet wired in the unified session dispatch.
      expect(backends.contains('piper'), isFalse,
          reason: 'piper should NOT be in availableBackends yet — '
              'if this fails, the piper support landed and the guard '
              'in TtsService is no longer blocking; update the test');
    }, skip: libSkip);

    test('opening a piper model without the guard would crash', () {
      // We can't actually test the crash (it's a segfault), but we
      // verify the catalog entry exists and backend is 'piper', so the
      // TtsService guard path is exercised.
      final def =
          ModelService.crispasrBackendModels['piper-en-libritts-r-medium'];
      expect(def, isNotNull);
      expect(def!.backend, 'piper');

      final backends = crispasr.CrispasrSession.availableBackends();
      expect(backends.contains('piper'), isFalse,
          reason: 'confirms TtsService.prepare() would return unsupported');
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
}
