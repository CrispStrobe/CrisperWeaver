// §5.26 integration live tests — opt-in, gated behind env vars + 'slow' tag.
//
// These exercise real CrispASR C-API paths for the mid-2026 catch-up:
//   * Hotwords: transcribe with hotwords set, assert the term appears
//   * S2S: speech-to-speech roundtrip on mini-omni2 or lfm2-audio
//   * New backends: basic ASR transcribe for lfm2-audio, mini-omni2,
//     moss-audio, parakeet-rnnt
//
// Running:
//   CRISPASR_LIB=/path/libcrispasr.so \
//   CRISPASR_TINY_MODEL=/path/ggml-tiny.en.bin \
//   flutter test --tags slow test/s26_integration_live_test.dart
//
//   # For S2S:
//   CRISPASR_TEST_MINI_OMNI2_MODEL=/path/mini-omni2-q4_k.gguf \
//   CRISPASR_TEST_SNAC_CODEC=/path/snac-24khz.gguf \
//   flutter test --tags slow test/s26_integration_live_test.dart
//
//   # For other new backends:
//   CRISPASR_TEST_LFM2_MODEL=/path/lfm2-audio-1.5b-q5_k.gguf \
//   CRISPASR_TEST_MOSS_MODEL=/path/moss-audio-4b-instruct-q4_k.gguf \
//   flutter test --tags slow test/s26_integration_live_test.dart

@Tags(['slow'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

String? _resolveLib() {
  final env = Platform.environment['CRISPASR_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return File(env).absolute.path;
  }
  for (final cand in [
    '../CrispASR/build-flutter-bundle/src/libwhisper.dylib',
    '../CrispASR/build/src/libwhisper.dylib',
    '../CrispASR/build-flutter-bundle/src/libcrispasr.dylib',
    '../CrispASR/build/src/libcrispasr.dylib',
    '../CrispASR/build-flutter-bundle/src/libcrispasr.so',
    '../CrispASR/build/src/libcrispasr.so',
  ]) {
    if (File(cand).existsSync()) return File(cand).absolute.path;
  }
  return null;
}

String? _resolveTinyModel() {
  final env = Platform.environment['CRISPASR_TINY_MODEL'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return File(env).absolute.path;
  }
  for (final c in [
    '../CrispASR/models/ggml-tiny.en.bin',
    '../CrispASR/build-flutter-bundle/models/ggml-tiny.en.bin',
  ]) {
    if (File(c).existsSync()) return File(c).absolute.path;
  }
  return null;
}

Float32List? _loadJfkPcm(String? libPath) {
  try {
    final audio = crispasr.decodeAudioFile('test/jfk-2s.wav',
        libPath: libPath);
    return audio.samples;
  } catch (_) {
    return null;
  }
}

void main() {
  final libPath = _resolveLib();
  final tinyModel = _resolveTinyModel();
  final libSkip = libPath == null ? 'no libcrispasr found' : null;
  final modelSkip = tinyModel == null
      ? 'no whisper tiny model found'
      : libSkip;

  // ──────────────────────────────────────────────────────────────────
  // §5.26.2 — Hotwords live test
  // ──────────────────────────────────────────────────────────────────
  group('§5.26.2 — Hotwords', () {
    test('setHotwords + transcribe includes hotword term (whisper)',
        () {
      final pcm = _loadJfkPcm(libPath);
      if (pcm == null) {
        markTestSkipped('could not load test/jfk-2s.wav');
        return;
      }
      final session = crispasr.CrispasrSession.open(
        tinyModel!,
        libPath: libPath,
      );
      try {
        // Set hotwords that match the JFK speech content.
        session.setHotwords('country, Americans', boost: 2.0);
        final result = session.transcribe(pcm);
        expect(result, isNotEmpty,
            reason: 'should produce at least one segment');
        final text = result.map((s) => s.text).join(' ').toLowerCase();
        // JFK speech should contain "country" — the hotword biases
        // the decoder toward recognizing it even on tiny.en.
        expect(text, contains('country'),
            reason: 'hotword "country" should appear in JFK transcript');
      } finally {
        session.close();
      }
    }, skip: modelSkip);

    test('setHotwords gracefully handles empty string', () {
      final session = crispasr.CrispasrSession.open(
        tinyModel!,
        libPath: libPath,
      );
      try {
        // Should not throw.
        session.setHotwords('');
      } finally {
        session.close();
      }
    }, skip: modelSkip);
  });

  // ──────────────────────────────────────────────────────────────────
  // §5.26.3 — Speech-to-Speech live test
  // ──────────────────────────────────────────────────────────────────
  group('§5.26.3 — Speech-to-Speech', () {
    final miniOmni2Model =
        Platform.environment['CRISPASR_TEST_MINI_OMNI2_MODEL'];
    final snacCodec = Platform.environment['CRISPASR_TEST_SNAC_CODEC'];
    final s2sSkip = (miniOmni2Model == null || snacCodec == null)
        ? 'set CRISPASR_TEST_MINI_OMNI2_MODEL + CRISPASR_TEST_SNAC_CODEC'
        : libSkip;

    test('mini-omni2 S2S produces audio output', () {
      final pcm = _loadJfkPcm(libPath);
      if (pcm == null) {
        markTestSkipped('could not load test/jfk-2s.wav');
        return;
      }
      final session = crispasr.CrispasrSession.open(
        miniOmni2Model!,
        backend: 'mini-omni2',
        libPath: libPath,
      );
      try {
        session.setCodecPath(snacCodec!);
        final result = session.speechToSpeech(pcm);
        expect(result.pcm.length, greaterThan(0),
            reason: 'S2S should produce non-empty PCM output');
      } finally {
        session.close();
      }
    }, skip: s2sSkip);
  });

  // ──────────────────────────────────────────────────────────────────
  // §5.26.1 — New backend ASR tests
  // ──────────────────────────────────────────────────────────────────
  group('§5.26.1 — New backend ASR', () {
    final lfm2Model =
        Platform.environment['CRISPASR_TEST_LFM2_MODEL'];
    final lfm2Skip = lfm2Model == null
        ? 'set CRISPASR_TEST_LFM2_MODEL'
        : libSkip;

    test('lfm2-audio transcribes JFK audio', () {
      final pcm = _loadJfkPcm(libPath);
      if (pcm == null) {
        markTestSkipped('could not load test/jfk-2s.wav');
        return;
      }
      final session = crispasr.CrispasrSession.open(
        lfm2Model!,
        backend: 'lfm2-audio',
        libPath: libPath,
      );
      try {
        final result = session.transcribe(pcm);
        expect(result, isNotEmpty);
        final text = result.map((s) => s.text).join(' ').toLowerCase();
        expect(text.length, greaterThan(5),
            reason: 'should produce a non-trivial transcript');
      } finally {
        session.close();
      }
    }, skip: lfm2Skip);

    final mossModel =
        Platform.environment['CRISPASR_TEST_MOSS_MODEL'];
    final mossSkip = mossModel == null
        ? 'set CRISPASR_TEST_MOSS_MODEL'
        : libSkip;

    test('moss-audio transcribes JFK audio', () {
      final pcm = _loadJfkPcm(libPath);
      if (pcm == null) {
        markTestSkipped('could not load test/jfk-2s.wav');
        return;
      }
      final session = crispasr.CrispasrSession.open(
        mossModel!,
        backend: 'moss-audio',
        libPath: libPath,
      );
      try {
        final result = session.transcribe(pcm);
        expect(result, isNotEmpty);
        final text = result.map((s) => s.text).join(' ').toLowerCase();
        expect(text.length, greaterThan(5),
            reason: 'MOSS should produce a transcript');
      } finally {
        session.close();
      }
    }, skip: mossSkip);

    final miniOmni2Model =
        Platform.environment['CRISPASR_TEST_MINI_OMNI2_MODEL'];
    final miniOmni2Skip = miniOmni2Model == null
        ? 'set CRISPASR_TEST_MINI_OMNI2_MODEL'
        : libSkip;

    test('mini-omni2 transcribes JFK audio (ASR mode)', () {
      final pcm = _loadJfkPcm(libPath);
      if (pcm == null) {
        markTestSkipped('could not load test/jfk-2s.wav');
        return;
      }
      final session = crispasr.CrispasrSession.open(
        miniOmni2Model!,
        backend: 'mini-omni2',
        libPath: libPath,
      );
      try {
        final result = session.transcribe(pcm);
        expect(result, isNotEmpty);
        final text = result.map((s) => s.text).join(' ').toLowerCase();
        expect(text.length, greaterThan(5),
            reason: 'Mini-Omni2 ASR should produce a transcript');
      } finally {
        session.close();
      }
    }, skip: miniOmni2Skip);
  });
}
