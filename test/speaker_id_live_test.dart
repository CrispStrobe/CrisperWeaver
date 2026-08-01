// §5.8.1 — Live integration tests for the TitaNet speaker
// embedding extractor + the file-per-speaker SpeakerDB. Tagged
// `slow` and gated on the dylib + GGUF so default `flutter test`
// runs skip them. Contributors without the artefacts can still
// run `flutter test --tags slow` without a hard failure.
//
// What's pinned:
//   * The SpeakerDB filesystem round-trip — enrol a synthetic
//     192-d embedding into a temp dir, close, re-open, observe
//     count == 1. Exercises the on-disk format the binding owns
//     without going through TitaNet.
//   * The end-to-end TitaNet pipeline — embed jfk-2s.wav, enrol
//     the result as "jfk", re-embed the same clip, match against
//     the DB, assert score >= 0.7 (the upstream default
//     confidence threshold).
//
// Running locally on macOS:
//   flutter test --tags slow test/speaker_id_live_test.dart
//
//   # explicit overrides:
//   CRISPASR_LIB=/abs/path/libwhisper.dylib \
//   CRISPASR_TITANET_MODEL=/abs/path/titanet-large.gguf \
//     flutter test --tags slow test/speaker_id_live_test.dart

@Tags(['slow'])
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';

String? _resolveLibPath() {
  final env = Platform.environment['CRISPASR_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return env;
  }
  const candidates = [
    '../CrispASR/build-flutter-bundle/src/libwhisper.dylib',
    '../CrispASR/build/src/libwhisper.dylib',
    '../CrispASR/build-flutter-bundle/src/libcrispasr.dylib',
    '../CrispASR/build/src/libcrispasr.dylib',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return File(c).absolute.path;
  }
  return null;
}

String? _resolveTitanetModel() {
  final env = Platform.environment['CRISPASR_TITANET_MODEL'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return File(env).absolute.path;
  }
  const candidates = [
    '../CrispASR/models/titanet-large.gguf',
    '../CrispASR/build-flutter-bundle/models/titanet-large.gguf',
  ];
  for (final c in candidates) {
    final f = File(c);
    if (f.existsSync()) return f.absolute.path;
  }
  return null;
}

/// Deterministic length-[dim] L2-normalised vector for the round-trip
/// test. Doesn't represent any real speaker — we only need it to
/// survive the on-disk format intact.
Float32List _syntheticEmbedding(int dim, int seed) {
  final rng = math.Random(seed);
  final out = Float32List(dim);
  double norm = 0.0;
  for (var i = 0; i < dim; i++) {
    final v = rng.nextDouble() * 2 - 1;
    out[i] = v;
    norm += v * v;
  }
  final scale = norm > 0 ? 1.0 / math.sqrt(norm) : 1.0;
  for (var i = 0; i < dim; i++) {
    out[i] = out[i] * scale;
  }
  return out;
}

void main() {
  final libPath = _resolveLibPath();
  final titanetPath = _resolveTitanetModel();
  final libSkip = libPath == null
      ? 'libwhisper / libcrispasr dylib not found — build CrispASR or set CRISPASR_LIB.'
      : null;
  final titanetSkip = titanetPath == null
      ? 'titanet-large.gguf not found — drop it at ../CrispASR/models/ or set CRISPASR_TITANET_MODEL.'
      : null;
  // When the lib is present but predates the TitaNet/SpeakerDB ABI,
  // skip rather than fail — that's an environment state matching the
  // "dylib not found" case, not a regression in this codebase.
  String? symbolSkip;
  if (libSkip == null) {
    final probe = DynamicLibrary.open(libPath!);
    if (!probe.providesSymbol('crispasr_speaker_db_load') ||
        !probe.providesSymbol('crispasr_titanet_init')) {
      symbolSkip =
          'libcrispasr at $libPath predates the TitaNet/SpeakerDB ABI — '
          'rebuild upstream CrispASR.';
    }
  }
  final dbSkip = libSkip ?? symbolSkip;
  final e2eSkip = libSkip ?? symbolSkip ?? titanetSkip;

  group('CrispASR SpeakerDB (filesystem round-trip)', () {
    test('enrol → reopen → count == 1, match same vector → score>0.9',
        () async {
      final lib = DynamicLibrary.open(libPath!);
      final tmp = await Directory.systemTemp.createTemp('spkdb_');
      try {
        // Closed-roster open: the DB confirms claimed participants, so
        // 'alice' has to be on the roster for dbB.match to resolve her.
        // An EMPTY roster is refused outright by
        // `crispasr_speaker_db_open` (open 1:N is unsupported), which
        // returns a null handle — so roster on 'alice' from the start.
        // Enrollment writes via dirPath, so it works before she exists.
        final dbA = crispasr.CrispasrSpeakerDB(lib, tmp.path,
            expectedNames: 'alice', consentAttested: true);
        expect(dbA.count, 0, reason: 'fresh dir starts empty');
        final emb = _syntheticEmbedding(192, 1);
        expect(dbA.enroll('alice', emb), isTrue);
        dbA.close();

        // Re-open to verify the profile persisted across handles.
        final dbB = crispasr.CrispasrSpeakerDB(lib, tmp.path,
            expectedNames: 'alice', consentAttested: true);
        expect(dbB.count, 1, reason: 'profile should survive reopen');
        final (name, score) = dbB.match(emb, threshold: 0.5);
        expect(name, 'alice',
            reason: 'identical vector should match the enrolled name');
        expect(score, greaterThan(0.9),
            reason: 'identical L2-normalised vectors score near 1.0');
        dbB.close();
      } finally {
        await tmp.delete(recursive: true);
      }
    }, skip: dbSkip);
  }, skip: dbSkip);

  group('CrispASR TitaNet end-to-end (JFK fixture)', () {
    test('embed → enrol → match the same WAV → score >= 0.7', () async {
      final wav = File('test/jfk-2s.wav');
      expect(wav.existsSync(), isTrue,
          reason: 'fixture missing from the repo — re-add test/jfk-2s.wav');

      final lib = DynamicLibrary.open(libPath!);

      final decoded =
          crispasr.decodeAudioFile(wav.absolute.path, libPath: libPath);
      expect(decoded.sampleRate, 16000);

      final titanet = crispasr.CrispasrTitaNet(lib, titanetPath!);
      final tmp = await Directory.systemTemp.createTemp('spkdb_e2e_');
      try {
        final emb1 = titanet.embed(decoded.samples);
        expect(emb1.length, 192,
            reason: 'TitaNet should emit 192-d embeddings');

        final db = crispasr.CrispasrSpeakerDB(lib, tmp.path,
            expectedNames: 'jfk', consentAttested: true);
        expect(db.enroll('jfk', emb1), isTrue);

        // Re-embed the same clip and match. Self-cosine on TitaNet
        // is essentially 1.0 (the model is deterministic); we
        // assert ≥ the upstream 0.7 confidence floor for a wide
        // margin against floating-point drift on any platform.
        final emb2 = titanet.embed(decoded.samples);
        final (name, score) = db.match(emb2);
        expect(name, 'jfk',
            reason: 'same speaker should resolve to the enrolled name');
        expect(score, greaterThanOrEqualTo(0.7),
            reason: 'self-match should clear the upstream threshold');
        db.close();
      } finally {
        titanet.close();
        await tmp.delete(recursive: true);
      }
    },
        skip: e2eSkip,
        timeout: const Timeout(Duration(minutes: 2)));
  }, skip: e2eSkip);
}
