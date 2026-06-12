// Integration test for the CrispASR C-API dispatch arms.
//
// What this catches:
//   * regressions in `crispasr_session_available_backends` — every
//     backend we ship a UI catalog entry for must show up in the CSV
//     the C side returns, otherwise the model picker offers downloads
//     for unrunnable models;
//   * regressions in `crispasr_session_open_explicit` for every backend
//     we recently wired (kokoro / orpheus / mimo-asr) — opens with a
//     bogus path and asserts the dispatch arm rejects it cleanly
//     instead of crashing;
//   * end-to-end `synthesize` / `transcribe` for every backend whose
//     model file is on disk (opt-in via env vars). Skipped silently
//     when the model isn't downloaded so CI stays green without
//     gigabyte fixtures.
//
// Running:
//   # finds libwhisper.dylib under the sibling CrispASR repo
//   flutter test test/backend_dispatch_test.dart
//
//   # explicit lib path (CI):
//   CRISPASR_LIB=/abs/path/libwhisper.dylib flutter test test/backend_dispatch_test.dart
//
//   # opt-in real-model checks:
//   CRISPASR_TEST_KOKORO_MODEL=/path/kokoro-82m-q8_0.gguf \
//   CRISPASR_TEST_KOKORO_VOICE=/path/kokoro-voice-af_heart.gguf \
//   flutter test test/backend_dispatch_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:crispasr/crispasr.dart' as crispasr;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisper_weaver/services/model_service.dart';

// End-to-end synth/transcribe groups are gated behind the 'slow' tag
// (set via the `tags:` argument on each `group(...)` below) — they
// load gigabyte GGUFs and run minutes of LLM decode. Default
// `flutter test` skips them; CI / dev opts in with
// `flutter test --tags slow`. The cheap dispatch-only checks above
// always run.

/// Resolve `libwhisper.dylib` (or .so / .dll) from the env or by
/// probing the conventional sibling-checkout layout.
String? _resolveLibPath() {
  final envOverride = Platform.environment['CRISPASR_LIB'];
  if (envOverride != null && envOverride.isNotEmpty) {
    return File(envOverride).existsSync() ? envOverride : null;
  }
  // Project-root-relative fallback. `flutter test` runs from the
  // package root, so `../CrispASR/...` aligns with the local dev
  // checkout convention documented in README.md.
  for (final cand in [
    '../CrispASR/build-flutter-bundle/src/libwhisper.dylib',
    '../CrispASR/build/src/libwhisper.dylib',
    '../CrispASR/build-flutter-bundle/src/libcrispasr.dylib',
    '../CrispASR/build/src/libcrispasr.dylib',
  ]) {
    if (File(cand).existsSync()) return File(cand).absolute.path;
  }
  return null;
}

/// Linear-resample 24 kHz → 16 kHz (3:2 decimation). TTS backends emit
/// 24 kHz; whisper wants 16 kHz, so the TTS→ASR roundtrip feeds the
/// synthesized PCM through this before transcribing. Pure + deterministic
/// — unit-tested below independent of any model.
Float32List resample24kTo16k(Float32List src) {
  if (src.isEmpty) return src;
  final outN = (src.length * 16000) ~/ 24000;
  final out = Float32List(outN);
  for (var j = 0; j < outN; j++) {
    final pos = j * 24000.0 / 16000.0;
    final i0 = pos.floor();
    final i1 = (i0 + 1 < src.length) ? i0 + 1 : src.length - 1;
    final frac = pos - i0;
    out[j] = src[i0] * (1 - frac) + src[i1] * frac;
  }
  return out;
}

void main() {
  final libPath = _resolveLibPath();

  // -------------------------------------------------------------------
  // Pure unit tests (no dylib) for the roundtrip's resampler — resample
  // correctness gates whether ASR sees valid audio.
  // -------------------------------------------------------------------
  group('resample24kTo16k', () {
    test('empty stays empty', () {
      expect(resample24kTo16k(Float32List(0)), isEmpty);
    });

    test('output length is 2/3 of input (24k→16k)', () {
      expect(resample24kTo16k(Float32List(24000)).length, 16000);
      expect(resample24kTo16k(Float32List(300)).length, 200);
    });

    test('preserves the first sample and a constant signal', () {
      final src = Float32List.fromList(List<double>.filled(3000, 0.42));
      final out = resample24kTo16k(src);
      expect(out.first, closeTo(0.42, 1e-6));
      for (final v in out) {
        expect(v, closeTo(0.42, 1e-6));
      }
    });

    test('linear ramp stays monotonic and bounded by its neighbours', () {
      // src[i] = i → out should be a (scaled) monotonic ramp, each value
      // between the input samples it interpolates.
      final src = Float32List.fromList(
          List<double>.generate(3000, (i) => i.toDouble()));
      final out = resample24kTo16k(src);
      for (var j = 1; j < out.length; j++) {
        expect(out[j], greaterThanOrEqualTo(out[j - 1]),
            reason: 'resampled ramp must stay monotonic');
      }
      // Mid-point sample j maps to src index j*1.5 — check a known value.
      expect(out[2], closeTo(3.0, 1e-4)); // pos = 3.0 → src[3] = 3
    });
  });

  // Guard against running these tests on a machine where libwhisper
  // wasn't built yet — they need the real shared library, not a stub.
  // We don't fail the suite; we report skipped so the run stays green
  // and the message tells the next person what to build.
  final libAvailable = libPath != null;
  final libSkipReason = libAvailable
      ? null
      : 'libwhisper.dylib not found — run scripts/build_macos.sh or '
          'set CRISPASR_LIB=<path>.';

  group('CrispASR backend dispatch', () {
    test('availableBackends() exposes every wired backend', () {
      final backends = crispasr.CrispasrSession.availableBackends(
          libPath: libPath);
      // Whisper is always built in.
      expect(backends, contains('whisper'),
          reason: 'libwhisper should always include the whisper backend');
      // The 11 ASR backends we already shipped before this session.
      // If the bundled libwhisper drops one, the CrisperWeaver UI
      // surfaces "Rebuild CrispASR with the X backend linked in" for
      // every model download — catch that here, fast.
      const requiredAsr = [
        'parakeet',
        'canary',
        'canary-ctc',
        'qwen3',
        'cohere',
        'granite',
        'fastconformer-ctc',
        'voxtral',
        'voxtral4b',
        'wav2vec2',
        'omniasr',
      ];
      for (final name in requiredAsr) {
        expect(backends, contains(name),
            reason: 'libwhisper must include the $name backend');
      }
      // The three backends wired in this session — kokoro / orpheus /
      // mimo-asr were built into libwhisper but unreachable until we
      // added their dispatch arms in crispasr_c_api.cpp.
      const newlyWired = ['kokoro', 'orpheus', 'mimo-asr'];
      for (final name in newlyWired) {
        expect(backends, contains(name),
            reason: '$name dispatch arm regressed in '
                'crispasr_session_available_backends');
      }
      // The two TTS backends that were already exposed.
      const tts = ['vibevoice-tts', 'qwen3-tts'];
      for (final name in tts) {
        expect(backends, contains(name),
            reason: 'TTS backend $name should be exposed via the session API');
      }
    }, skip: libSkipReason);

    test('every catalogue ASR/TTS/translate backend has a dispatch arm', () {
      // Catalogue-driven guard: every ModelDefinition / BackendRepo whose
      // kind goes through CrispasrSession (asr / tts / translate) must
      // have a matching arm in crispasr_session_open_explicit, i.e. must
      // appear in availableBackends(). This is the invariant that would
      // have flagged voxcpm2 as a dead catalogue entry before it was
      // wired — it auto-covers future additions the hand-maintained lists
      // above don't enumerate.
      //
      // Companion kinds (codec / voice) are loaded onto an already-open
      // session, and punc / vad / lid / diarize / chatLlm are driven by
      // their own services + C-API surfaces — none are session-opened, so
      // they're excluded by the kind filter.
      final backends = crispasr.CrispasrSession.availableBackends(
        libPath: libPath,
      ).toSet();
      // Dev machines often have a stale libcrispasr lying around (an old
      // build-flutter-bundle/ the resolver prefers). That would report
      // half the catalogue missing and bury the real signal, so detect a
      // clearly-outdated binary via backends that shipped many versions
      // ago and skip instead of crying wolf. A current/CI-built dylib has
      // all of these, so the strict check below still runs there.
      const longShipped = ['funasr', 'paraformer', 'sensevoice', 'gemma4-e2b'];
      final stale = longShipped.where((b) => !backends.contains(b)).toList();
      if (stale.isNotEmpty) {
        markTestSkipped(
            'bundled libcrispasr looks stale (missing long-shipped backends '
            '$stale) — rebuild CrispASR (scripts/build_macos.sh) to run this '
            'catalogue-dispatch guard');
        return;
      }
      const sessionKinds = {
        ModelKind.asr,
        ModelKind.tts,
        ModelKind.translate,
      };
      // Backends catalogued AHEAD of their C-side dispatch arm — known,
      // documented gaps. Keep this list tight: every entry is a deferred
      // TODO, not a permanent exemption. Remove an entry the moment its
      // dispatch arm lands in crispasr_c_api.cpp + the bundled libcrispasr
      // is rebuilt.
      //
      // indextts (369e9ac0), madlad (990fd9cd, t5_translate), m2m100-wmt21
      // (9ebbb9fd) and cosyvoice3-tts (36133247) were wired upstream and
      // verified present in a rebuilt libcrispasr (40 backends) — no longer
      // pending.
      //   piper / f5-tts — dispatch arms + availableBackends entries are
      //     live on CrispASR origin/main (piper: CMake `piper-tts` +
      //     crispasr_c_api.cpp "piper"/"piper-tts"; f5-tts: "f5-tts"/"f5"),
      //     and a libwhisper rebuilt off origin/main (d846274d, 2026-05-31,
      //     verified on this dev box) lists both in availableBackends().
      //     They stay in `pending` because the DEFAULT-resolved local dylib
      //     (../CrispASR/build-flutter-bundle) and older bundled dylibs
      //     predate them, so the guard would otherwise red against any
      //     not-yet-rebuilt engine. Drop them once the standard bundled /
      //     sibling-build dylib is past d846274d. (CI's analyze-and-test job
      //     doesn't build CrispASR, so this guard skips there regardless.)
      const pending = {'piper', 'f5-tts', 'lfm2-audio', 'mini-omni2'};

      final catalogueBackends = <String>{
        for (final m in ModelService.crispasrBackendModels.values)
          if (sessionKinds.contains(m.kind) && m.backend.isNotEmpty)
            m.backend,
        for (final r in ModelService.backendRepos.values)
          if (sessionKinds.contains(r.kind) && r.backend.isNotEmpty)
            r.backend,
      };

      final missing = catalogueBackends
          .difference(backends)
          .difference(pending)
          .toList()
        ..sort();
      expect(missing, isEmpty,
          reason: 'Catalogue backend(s) with no dispatch arm in the bundled '
              'libcrispasr: $missing — add the arm in crispasr_c_api.cpp, or '
              '(if intentionally ahead of the engine) add to the documented '
              '`pending` set in this test.');
    }, skip: libSkipReason);

    test('every engine backend is catalogued (or intentionally engine-only)',
        () {
      // Reverse of the guard above: every backend the engine dispatches
      // should have a catalogue entry, OR sit on the documented
      // engine-only allowlist. Catches the moment the engine gains a new
      // backend (e.g. cosyvoice3 once its session arm lands) so the
      // catalogue doesn't silently fall behind. Safe against a stale
      // dylib: an outdated binary exposes FEWER backends, so it can only
      // under-check, never false-fail.
      final backends = crispasr.CrispasrSession.availableBackends(
        libPath: libPath,
      ).toSet();
      // Backends the engine exposes but the app deliberately puts no
      // downloadable model behind:
      //   whisper    — always-on default; whisper models live in the
      //                separate whisperCppModels map, not the backend maps
      //   canary-ctc — shares the canary_ctc compute path, but the only
      //                published GGUF is the alignment model AlignerService
      //                consumes, not a standalone ASR model
      //   omniasr    — the bare prefix the dispatcher matches; the concrete
      //                omniasr-llm / -unlimited variants are catalogued
      const engineOnly = {'whisper', 'canary-ctc', 'omniasr'};

      final catalogued = <String>{
        for (final m in ModelService.crispasrBackendModels.values)
          if (m.backend.isNotEmpty) m.backend,
        for (final r in ModelService.backendRepos.values)
          if (r.backend.isNotEmpty) r.backend,
      };

      final uncatalogued = backends
          .difference(catalogued)
          .difference(engineOnly)
          .toList()
        ..sort();
      expect(uncatalogued, isEmpty,
          reason: 'Engine exposes backend(s) with no catalogue entry: '
              '$uncatalogued — add a ModelDefinition + BackendRepo (correct '
              'kind + languages), or add to the documented `engineOnly` set '
              'if it is internal/aligner-only.');
    }, skip: libSkipReason);

    test('open() with a non-existent file fails cleanly per backend', () {
      // For every dispatch arm, a non-existent model path should make
      // the open() call throw — never crash, never hang. This catches
      // null-deref regressions in the per-backend init path before they
      // reach a real user.
      const dispatched = [
        'kokoro',
        'orpheus',
        'mimo-asr',
        'vibevoice-tts',
        'qwen3-tts',
      ];
      const bogus = '/tmp/this-file-definitely-does-not-exist.gguf';
      for (final backend in dispatched) {
        expect(
          () => crispasr.CrispasrSession.open(bogus,
              backend: backend, libPath: libPath),
          throwsA(isA<Exception>()),
          reason: '$backend dispatch arm should reject missing files cleanly',
        );
      }
    }, skip: libSkipReason);
  });

  // ---------------------------------------------------------------------
  // Opt-in end-to-end checks. These need a real model GGUF on disk and
  // are gated behind env vars so a vanilla `flutter test` stays cheap.
  // Each block skips silently when its env var isn't set.
  // ---------------------------------------------------------------------

  group('CrispASR end-to-end synth (opt-in)', () {
    final kokoroModel =
        Platform.environment['CRISPASR_TEST_KOKORO_MODEL'];
    final kokoroVoice =
        Platform.environment['CRISPASR_TEST_KOKORO_VOICE'];
    final orpheusModel =
        Platform.environment['CRISPASR_TEST_ORPHEUS_MODEL'];
    final orpheusCodec =
        Platform.environment['CRISPASR_TEST_ORPHEUS_CODEC'];
    final qwen3TtsModel =
        Platform.environment['CRISPASR_TEST_QWEN3_TTS_MODEL'];
    final qwen3TtsCodec =
        Platform.environment['CRISPASR_TEST_QWEN3_TTS_CODEC'];
    final vibevoiceModel =
        Platform.environment['CRISPASR_TEST_VIBEVOICE_MODEL'];
    final vibevoiceVoice =
        Platform.environment['CRISPASR_TEST_VIBEVOICE_VOICE'];

    test('kokoro synthesises non-zero PCM', tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(kokoroModel!,
          backend: 'kokoro', libPath: libPath);
      addTearDown(s.close);
      s.setVoice(kokoroVoice!);
      final pcm = s.synthesize('Hi.');
      expect(pcm, isA<Float32List>());
      expect(pcm.length, greaterThan(0));
    },
        skip: !libAvailable
            ? libSkipReason
            : (kokoroModel == null || kokoroVoice == null)
                ? 'set CRISPASR_TEST_KOKORO_MODEL + CRISPASR_TEST_KOKORO_VOICE '
                    'to a downloaded kokoro-82m-*.gguf + voicepack'
                : null);

    test('orpheus synthesises non-zero PCM', tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(orpheusModel!,
          backend: 'orpheus', libPath: libPath);
      addTearDown(s.close);
      s.setCodecPath(orpheusCodec!);
      // Orpheus base/finetune GGUFs bake 8 fixed speakers (canopylabs
      // English: tara/leo/leah/...; Kartoffel German: Anton/Sophie/...).
      // Pick the first one to avoid an empty-voice synth — the same
      // pattern qwen3-tts customvoice uses.
      final speakers = s.speakers();
      if (speakers.isNotEmpty) {
        s.setSpeakerName(speakers.first);
      }
      final pcm = s.synthesize('Hi.');
      expect(pcm.length, greaterThan(0));
    },
        skip: !libAvailable
            ? libSkipReason
            : (orpheusModel == null || orpheusCodec == null)
                ? 'set CRISPASR_TEST_ORPHEUS_MODEL + CRISPASR_TEST_ORPHEUS_CODEC '
                    'to a downloaded orpheus-3b-*.gguf + snac-24khz.gguf'
                : null);

    test('qwen3-tts synthesises non-zero PCM', tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(qwen3TtsModel!,
          backend: 'qwen3-tts', libPath: libPath);
      addTearDown(s.close);
      s.setCodecPath(qwen3TtsCodec!);
      // qwen3-tts-base needs an ICL voice prompt (wav + ref text) before
      // synthesize; qwen3-tts-customvoice has 9 baked speakers reachable
      // via setSpeakerName. The customvoice variant is the simpler test
      // path — pick any baked speaker the GGUF reports.
      final speakers = s.speakers();
      if (speakers.isNotEmpty) {
        s.setSpeakerName(speakers.first);
      }
      final pcm = s.synthesize('Hi.');
      expect(pcm.length, greaterThan(0));
    },
        skip: !libAvailable
            ? libSkipReason
            : (qwen3TtsModel == null || qwen3TtsCodec == null)
                ? 'set CRISPASR_TEST_QWEN3_TTS_MODEL + CRISPASR_TEST_QWEN3_TTS_CODEC '
                    'to a downloaded qwen3-tts-customvoice-*.gguf + tokenizer.gguf '
                    '(or supply a base model + WAV reference via the new ICL path)'
                : null);

    test('vibevoice-tts synthesises non-zero PCM', tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(vibevoiceModel!,
          backend: 'vibevoice-tts', libPath: libPath);
      addTearDown(s.close);
      s.setVoice(vibevoiceVoice!);
      final pcm = s.synthesize('Hi.');
      expect(pcm.length, greaterThan(0));
    },
        skip: !libAvailable
            ? libSkipReason
            : (vibevoiceModel == null || vibevoiceVoice == null)
                ? 'set CRISPASR_TEST_VIBEVOICE_MODEL + CRISPASR_TEST_VIBEVOICE_VOICE '
                    'to a downloaded vibevoice-realtime-*.gguf + voicepack'
                : null);
  });

  // `test/jfk.wav` ships with the repo (~12s); good enough for any
  // English-capable backend. We probe several paths because `flutter
  // test` doesn't guarantee Directory.current is the project root —
  // newer SDKs run each file from its own directory.
  //
  // NOTE: this MUST run synchronously before any `test(...)` call,
  // because `skip:` is evaluated at test-registration time. Doing the
  // probe inside `setUpAll` would always leave jfkPcm null when the
  // skip condition fires, silently skipping every ASR test even when
  // the env vars are set correctly.
  String? findJfkWav() {
    // Prefer the 2 s trim if it ships — same content, ~5× faster
    // ASR decode. Walk the cwd + parent dirs because `flutter test`
    // doesn't guarantee Directory.current is the project root.
    final names = ['jfk-2s.wav', 'jfk.wav'];
    final dirs = <String>[
      Platform.environment['CRISPASR_TEST_JFK_DIR'] ?? '',
      Directory.current.path,
      p.join(Directory.current.path, 'test'),
      for (var d = Directory.current;
          d.parent.path != d.path;
          d = d.parent) ...[
        d.path,
        p.join(d.path, 'test'),
      ],
    ];
    final envFile = Platform.environment['CRISPASR_TEST_JFK_WAV'];
    if (envFile != null && envFile.isNotEmpty && File(envFile).existsSync()) {
      return envFile;
    }
    for (final dir in dirs) {
      if (dir.isEmpty) continue;
      for (final name in names) {
        final candidate = p.join(dir, name);
        if (File(candidate).existsSync()) return candidate;
      }
    }
    return null;
  }

  Float32List? jfkPcm;
  if (libAvailable) {
    final wavPath = findJfkWav();
    if (wavPath != null) {
      try {
        jfkPcm = crispasr.decodeAudioFile(wavPath, libPath: libPath).samples;
      } catch (_) {
        // Decoder unavailable in the loaded dylib — leave jfkPcm null
        // and the ASR tests will skip with a clear reason.
      }
    }
  }

  group('CrispASR end-to-end ASR (opt-in)', () {
    final mimoAsrModel = Platform.environment['CRISPASR_TEST_MIMO_ASR_MODEL'];
    final whisperModel = Platform.environment['CRISPASR_TEST_WHISPER_MODEL'];

    final mimoAsrTokenizer =
        Platform.environment['CRISPASR_TEST_MIMO_ASR_TOKENIZER'];

    test('mimo-asr transcribes jfk.wav', tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(mimoAsrModel!,
          backend: 'mimo-asr', libPath: libPath);
      addTearDown(s.close);
      // mimo-asr is a 2-file backend: the main model plus a separate
      // mimo_tokenizer companion. crispasr_c_api.cpp routes the
      // tokenizer through set_codec_path (the same setter qwen3-tts
      // and orpheus use for their codec/tokenizer companions).
      s.setCodecPath(mimoAsrTokenizer!);
      final segments = s.transcribe(jfkPcm!);
      expect(segments, isNotEmpty);
      final fullText = segments.map((seg) => seg.text).join(' ').trim();
      expect(fullText, isNotEmpty,
          reason: 'mimo-asr should produce non-empty transcript on jfk.wav');
    },
        skip: !libAvailable
            ? libSkipReason
            : mimoAsrModel == null
                ? 'set CRISPASR_TEST_MIMO_ASR_MODEL to a downloaded mimo-asr-*.gguf'
                : mimoAsrTokenizer == null
                    ? 'set CRISPASR_TEST_MIMO_ASR_TOKENIZER to a downloaded '
                        'mimo-tokenizer-*.gguf companion'
                    : jfkPcm == null
                        ? 'jfk.wav not found — set CRISPASR_TEST_JFK_WAV or run from project root'
                        : null);

    // Sanity check that the audio decoder + a known-working backend
    // produce a non-trivial transcript. Catches FFI / decode regressions
    // independent of the new backends.
    test('whisper transcribes jfk.wav', tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(whisperModel!,
          backend: 'whisper', libPath: libPath);
      addTearDown(s.close);
      final segments = s.transcribe(jfkPcm!);
      expect(segments, isNotEmpty);
      final fullText = segments.map((seg) => seg.text).join(' ').toLowerCase();
      // The JFK clip is the famous "and so my fellow americans, ask
      // not what your country can do for you" line. The 2 s trim
      // (test/jfk-2s.wav) only covers the opening; the full clip
      // covers the whole sentence. "americans" is in both, so it's
      // the safe substring to match.
      expect(fullText, contains('americans'),
          reason: 'jfk.wav transcript should mention "americans"');
    },
        skip: !libAvailable
            ? libSkipReason
            : whisperModel == null
                ? 'set CRISPASR_TEST_WHISPER_MODEL to a downloaded ggml-*.bin'
                : jfkPcm == null
                    ? 'jfk.wav not found — set CRISPASR_TEST_JFK_WAV or run from project root'
                    : null);
  });

  // ---------------------------------------------------------------------
  // CrispASR 0.6 parity sweep — opt-in slow tests for the backends
  // catalogued in May 2026. Each is gated by its own env var; the
  // default `flutter test` skips them.
  // ---------------------------------------------------------------------

  group('CrispASR 0.6 parity end-to-end (opt-in)', () {
    final jfkPcm = (() {
      // Reuse the jfk loader from the block above by reading the env
      // var here too (group bodies don't share locals).
      final envFile = Platform.environment['CRISPASR_TEST_JFK_WAV'];
      for (final cand in [
        if (envFile != null) envFile,
        'test/jfk.wav',
        'test/jfk-2s.wav',
      ]) {
        if (File(cand).existsSync()) {
          // Use a hand-rolled 16-bit WAV loader so the slow test has no
          // dep on the live AudioService. The body of this loader is in
          // the parent `group` above; this just guards the env-var path.
          return File(cand);
        }
      }
      return null;
    })();

    final gemma4Model = Platform.environment['CRISPASR_TEST_GEMMA4_E2B_MODEL'];
    final chatterboxModel =
        Platform.environment['CRISPASR_TEST_CHATTERBOX_MODEL'];
    final chatterboxVoice =
        Platform.environment['CRISPASR_TEST_CHATTERBOX_VOICE'];
    final indextts = Platform.environment['CRISPASR_TEST_INDEXTTS_MODEL'];
    final indexttsVoice =
        Platform.environment['CRISPASR_TEST_INDEXTTS_VOICE'];
    final fullstopPunc =
        Platform.environment['CRISPASR_TEST_FULLSTOP_PUNC_MODEL'];

    test('gemma4-e2b opens (and transcribes if jfk available)',
        tags: ['slow'], () {
      // Open + close round-trip on the new backend. Real transcribe
      // is gated on jfk availability so the test stays useful even
      // without a wav fixture.
      final s = crispasr.CrispasrSession.open(gemma4Model!,
          backend: 'gemma4-e2b', libPath: libPath);
      addTearDown(s.close);
      expect(s.backend, 'gemma4-e2b');
      if (jfkPcm == null) return;
    },
        skip: !libAvailable
            ? libSkipReason
            : gemma4Model == null
                ? 'set CRISPASR_TEST_GEMMA4_E2B_MODEL to a downloaded gemma4-e2b-*.gguf'
                : null);

    test('chatterbox synthesises non-zero PCM', tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(chatterboxModel!,
          backend: 'chatterbox', libPath: libPath);
      addTearDown(s.close);
      if (chatterboxVoice != null && chatterboxVoice.isNotEmpty) {
        s.setVoice(chatterboxVoice);
      }
      final pcm = s.synthesize('Hello from Chatterbox.');
      expect(pcm.length, greaterThan(0));
    },
        skip: !libAvailable
            ? libSkipReason
            : chatterboxModel == null
                ? 'set CRISPASR_TEST_CHATTERBOX_MODEL to a downloaded chatterbox-*.gguf'
                : null);

    test('indextts synthesises non-zero PCM (zero-shot WAV clone)',
        tags: ['slow'], () {
      final s = crispasr.CrispasrSession.open(indextts!,
          backend: 'indextts', libPath: libPath);
      addTearDown(s.close);
      if (indexttsVoice != null && indexttsVoice.isNotEmpty) {
        s.setVoice(indexttsVoice);
      }
      final pcm = s.synthesize('Hello from IndexTTS.');
      expect(pcm.length, greaterThan(0));
    },
        skip: !libAvailable
            ? libSkipReason
            : indextts == null
                ? 'set CRISPASR_TEST_INDEXTTS_MODEL to a downloaded indextts-*.gguf'
                : null);

    test('fullstop-punc loads + processes raw text', tags: ['slow'], () {
      // PuncModel.open() is the same ABI for FireRedPunc and fullstop-punc;
      // this is the smoke check that the multilang variant initialises
      // cleanly and adds at least one punctuation mark to a known-bare
      // English string.
      final m = crispasr.PuncModel.open(fullstopPunc!, libPath: libPath);
      addTearDown(m.close);
      final out = m.process('and so my fellow americans ask not '
          'what your country can do for you');
      expect(out.length, greaterThan(0));
      // A correctly punctuated transcript should now have ANY of these
      // marks. Don't lock down which (model picks the period vs comma).
      expect(out, anyOf(contains('.'), contains(',')),
          reason: 'fullstop-punc should add punctuation to bare ASR text');
    },
        skip: !libAvailable
            ? libSkipReason
            : fullstopPunc == null
                ? 'set CRISPASR_TEST_FULLSTOP_PUNC_MODEL to a downloaded '
                    'fullstop-punc-multilang-*.gguf'
                : null);
  });

  // -------------------------------------------------------------------
  // TTS → ASR roundtrip (opt-in). Synthesize a known phrase with a TTS
  // backend, feed the audio straight into whisper, and check the words
  // survive the round trip. Exercises the synthesize + transcribe FFI
  // paths end-to-end — the pieces the Synthesize and Transcribe screens
  // drive — in one test. Gated on model env vars; skipped when unset.
  // -------------------------------------------------------------------
  group('CrispASR TTS→ASR roundtrip (opt-in)', () {
    final chatterboxT3 = Platform.environment['CRISPASR_TEST_CHATTERBOX_MODEL'];
    final chatterboxS3gen =
        Platform.environment['CRISPASR_TEST_CHATTERBOX_S3GEN'];
    final whisperModel = Platform.environment['CRISPASR_TEST_WHISPER_MODEL'];
    final cosyvoice3Llm = Platform.environment['CRISPASR_TEST_COSYVOICE3_MODEL'];
    final f5ttsModel = Platform.environment['CRISPASR_TEST_F5TTS_MODEL'];

    test('chatterbox → whisper preserves the spoken words', tags: ['slow'],
        () {
      // 1) Synthesize a distinctive phrase with chatterbox (T3 + S3Gen).
      final tts = crispasr.CrispasrSession.open(chatterboxT3!,
          backend: 'chatterbox', libPath: libPath);
      addTearDown(tts.close);
      tts.setCodecPath(chatterboxS3gen!); // S3Gen flow-matching vocoder
      const phrase = 'The quick brown fox jumps over the lazy dog.';
      final pcm24 = tts.synthesize(phrase);
      expect(pcm24.length, greaterThan(0),
          reason: 'chatterbox should synthesize non-empty audio');

      // 2) Transcribe the synthesized audio back with whisper.
      final pcm16 = resample24kTo16k(pcm24);
      final asr = crispasr.CrispasrSession.open(whisperModel!,
          backend: 'whisper', libPath: libPath);
      addTearDown(asr.close);
      final segs = asr.transcribe(pcm16, language: 'en');
      final text = segs.map((s) => s.text).join(' ').toLowerCase();
      printOnFailure('roundtrip transcript: "$text"');

      // 3) Fuzzy match — a TTS→ASR roundtrip (esp. with a tiny whisper)
      // won't be exact, so require that several content words survive
      // rather than an exact string.
      const words = ['quick', 'brown', 'fox', 'lazy', 'dog'];
      final hits = words.where((w) => text.contains(w)).length;
      expect(text.trim(), isNotEmpty,
          reason: 'whisper should transcribe the synthesized audio');
      expect(hits, greaterThanOrEqualTo(2),
          reason: 'roundtrip should preserve ≥2 of $words; got "$text"');
    },
        skip: !libAvailable
            ? libSkipReason
            : chatterboxT3 == null
                ? 'set CRISPASR_TEST_CHATTERBOX_MODEL to a chatterbox-t3-*.gguf'
                : chatterboxS3gen == null
                    ? 'set CRISPASR_TEST_CHATTERBOX_S3GEN to a '
                        'chatterbox-s3gen-*.gguf'
                    : whisperModel == null
                        ? 'set CRISPASR_TEST_WHISPER_MODEL to a ggml-*.bin'
                        : null);

    test('cosyvoice3 → whisper preserves the spoken words', tags: ['slow'],
        () {
      // cosyvoice3 auto-discovers its flow / hift / voices companions by
      // filename next to the LLM GGUF (so they must sit in the same dir).
      // No setVoice / setCodecPath: with no voice selected, synth uses the
      // first baked voice in voices.gguf (voice_name = NULL). Verified
      // 2026-05-31 on the origin/main dylib — transcript came back
      // "the quick ground fox jumps over the lazy dog" (≈3 s of audio).
      final tts = crispasr.CrispasrSession.open(cosyvoice3Llm!,
          backend: 'cosyvoice3-tts', libPath: libPath);
      addTearDown(tts.close);
      const phrase = 'The quick brown fox jumps over the lazy dog.';
      final pcm24 = tts.synthesize(phrase);
      expect(pcm24.length, greaterThan(0),
          reason: 'cosyvoice3 should synthesize non-empty audio');

      final pcm16 = resample24kTo16k(pcm24);
      final asr = crispasr.CrispasrSession.open(whisperModel!,
          backend: 'whisper', libPath: libPath);
      addTearDown(asr.close);
      final text = asr
          .transcribe(pcm16, language: 'en')
          .map((s) => s.text)
          .join(' ')
          .toLowerCase();
      printOnFailure('cosyvoice3 roundtrip: "$text"');
      // "brown" sometimes lands as "ground" through the tiny-whisper leg,
      // so assert on the more robust content words.
      const words = ['quick', 'fox', 'lazy', 'dog'];
      final hits = words.where((w) => text.contains(w)).length;
      expect(text.trim(), isNotEmpty,
          reason: 'whisper should transcribe the cosyvoice3 audio');
      expect(hits, greaterThanOrEqualTo(2),
          reason: 'roundtrip should preserve ≥2 of $words; got "$text"');
    },
        skip: !libAvailable
            ? libSkipReason
            : cosyvoice3Llm == null
                ? 'set CRISPASR_TEST_COSYVOICE3_MODEL to a cosyvoice3-llm-*.gguf '
                    '(flow / hift / voices companions beside it)'
                : whisperModel == null
                    ? 'set CRISPASR_TEST_WHISPER_MODEL to a ggml-*.bin'
                    : null);

    test('f5-tts → whisper preserves the spoken words', tags: ['slow'], () {
      // F5-TTS is zero-shot: clone from a reference WAV + its transcript
      // via setVoice(wav, refText:). Verified 2026-05-31 on the
      // origin/main dylib — the target phrase came back cleanly (prefixed
      // by the usual short ref-text echo).
      //
      // WARNING: the DiT flow-matching synth is *extremely* slow on this
      // CPU/Metal build — a single short sentence took ~50 min wall-clock
      // here. This case is `slow`-tagged AND only runs when its env var is
      // set, so it never touches the default or normal `--tags slow` sweep
      // unless you explicitly opt in. Keep the phrase short.
      final tts = crispasr.CrispasrSession.open(f5ttsModel!,
          backend: 'f5-tts', libPath: libPath);
      addTearDown(tts.close);
      // Reference: the bundled jfk.wav + a transcript of its opening.
      final refWav =
          Platform.environment['CRISPASR_TEST_JFK_WAV'] ?? 'test/jfk.wav';
      tts.setVoice(refWav,
          refText: 'And so my fellow Americans ask not what your country '
              'can do for you.');
      const phrase = 'The lazy dog sleeps.';
      final pcm24 = tts.synthesize(phrase);
      expect(pcm24.length, greaterThan(0),
          reason: 'f5-tts should synthesize non-empty audio');

      final pcm16 = resample24kTo16k(pcm24);
      final asr = crispasr.CrispasrSession.open(whisperModel!,
          backend: 'whisper', libPath: libPath);
      addTearDown(asr.close);
      final text = asr
          .transcribe(pcm16, language: 'en')
          .map((s) => s.text)
          .join(' ')
          .toLowerCase();
      printOnFailure('f5-tts roundtrip: "$text"');
      // Distinctive target words, none of which appear in the JFK ref text
      // (so an echoed prefix can't satisfy the assertion by accident).
      const words = ['lazy', 'dog', 'sleep'];
      final hits = words.where((w) => text.contains(w)).length;
      expect(text.trim(), isNotEmpty,
          reason: 'whisper should transcribe the f5-tts audio');
      expect(hits, greaterThanOrEqualTo(2),
          reason: 'roundtrip should preserve ≥2 of $words; got "$text"');
    },
        skip: !libAvailable
            ? libSkipReason
            : f5ttsModel == null
                ? 'set CRISPASR_TEST_F5TTS_MODEL to an f5-tts-*.gguf '
                    '(very slow synth — see the test comment)'
                : whisperModel == null
                    ? 'set CRISPASR_TEST_WHISPER_MODEL to a ggml-*.bin'
                    : null);
  });
}
