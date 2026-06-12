# CrisperWeaver — Implementation plan & current status

What's done, what's partial, and what's next — with enough file paths and context that a fresh session can pick up any item.

---

## Table of contents

1. [Engine status](#1-engine-status)
2. [Model-family status](#2-model-family-status)
3. [Platform status](#3-platform-status)
4. [Feature status](#4-feature-status)
5. [Open roadmap items](#5-open-roadmap-items)
6. [Adding a new backend](#6-adding-a-new-backend)
7. [Server alternative (not used)](#7-server-alternative-not-used)

---

## 0. CrispASR 0.6.x parity sweep (May 2026) — ✅ shipped in v0.4.1

Six rounds of work between May 2026 brought CrisperWeaver up to
CrispASR 0.6.2 parity: 3 new screens (Translate, Voice Bake, Local
HTTP server), 8 new backends in the catalog, runtime-tunable
flash-attn / GPU layers / TTS sampling sliders, and 3 new export
formats. Released as
[v0.4.1](https://github.com/CrispStrobe/CrisperWeaver/releases/tag/v0.4.1)
paired with
[CrispASR v0.6.2](https://github.com/CrispStrobe/CrispASR/releases/tag/v0.6.2).

Full per-round write-up: **[HISTORY.md → "May 2026 parity sweep"](HISTORY.md)**.

**Still deferred** (each tracked upstream in `../CrispASR/PLAN.md`):

* **Wiring `flash_attn` into every backend's compute graph** — the
  toggle ships in the open-params struct (round 5) and threads
  through to each backend's session via the per-backend `flash_attn`
  field on context_params (round 6, closing CrispASR #89). Only
  whisper consumes it at the kernel level today. Tracked as
  **[CrispASR PLAN.md #86](https://github.com/CrispStrobe/CrispASR/blob/main/PLAN.md#86-per-backend-flash-attention-wiring-crisperweaver-driven)**
  — full per-backend status table, recipe, and recommended order
  (orpheus + chatterbox-T3 first; ~2–3 focused days for the full
  sweep).
* **`gpu_backend` selector** (metal / cuda / vulkan / cpu-only as a
  runtime string) — needs ggml-side multi-backend dispatch first.
  Tracked as
  **[CrispASR PLAN.md #87](https://github.com/CrispStrobe/CrispASR/blob/main/PLAN.md#87-gpu_backend-runtime-selector-multi-backend-ggml-build)**.

The OpenAI-compatible server item that was previously deferred is
SHIPPED as a Dart-side `shelf` server in round 5 (see HISTORY +
the §7 note below). The CrispASR-side `crispasr --server` binary
remains available as the desktop-only alternative.

---

## 1. Engine status

Two engines behind the `TranscriptionEngine` interface (`lib/engines/transcription_engine.dart`):

| Engine            | State                                                                      |
| ----------------- | -------------------------------------------------------------------------- |
| `CrispASREngine`  | ✅ Primary. Dart FFI to `libcrispasr` / `libwhisper`. Dispatches across all 10 backends via `CrispasrSession`. |
| `MockEngine`      | ✅ Deterministic fake responses — used for UI work and CI.                 |

Earlier prototypes had separate `WhisperCppEngine` and `CoreMLEngine` values (method-channel wrappers). Dropped: whisper.cpp ships inside CrispASR, and CoreML acceleration will land as an opt-in inside libwhisper (`WHISPER_USE_COREML`) rather than a separate engine. `EngineType.sherpaOnnx` was dropped earlier for being a placeholder.

## 2. Model-family status

All 10 CrispASR backends are runtime-ready through `CrispasrSession`. The bundled `libcrispasr` must be linked with each backend's shared library; `CrispasrSession.availableBackends()` reports live at startup which ones this build has.

| Family               | Download | Runtime FFI                      | Notes                                    |
| -------------------- | :------: | :------------------------------: | ---------------------------------------- |
| Whisper              | ✅       | ✅ (default path)                 | Full features (word-ts, lang-detect, streaming, VAD) |
| Parakeet             | ✅       | ✅ via `CrispasrSession`          | Fast English ASR, native word timestamps  |
| Canary               | ✅       | ✅ via `CrispasrSession`          | Speech translation X ↔ en                 |
| Qwen3-ASR            | ✅       | ✅ via `CrispasrSession`          | 30+ langs incl. Chinese dialects          |
| Cohere               | ✅       | ✅ via `CrispasrSession`          | High-accuracy Conformer decoder           |
| Granite Speech       | ✅       | ✅ via `CrispasrSession`          | Instruction-tuned                         |
| FastConformer-CTC    | ✅       | ✅ via `CrispasrSession`          | Low-latency CTC                           |
| Canary-CTC           | ✅       | ✅ via `CrispasrSession`          | Shared canary_ctc_* pipeline              |
| Voxtral Mini 3B      | ✅       | ✅ via `CrispasrSession`          | Shared VoxtralFamilyOps loop              |
| Voxtral Mini 4B      | ✅       | ✅ via `CrispasrSession`          | Realtime variant, same loop               |
| Wav2Vec2             | ✅       | ✅ via `CrispasrSession`          | Self-supervised, public C++ API sufficed  |
| OmniASR (LLM)        | ✅       | ✅ via `CrispasrSession`          | Multilingual LLM-based ASR (300M)         |
| FireRed ASR2         | ✅       | ✅ via `CrispasrSession`          | AED Mandarin/English                       |
| Kyutai STT 1B        | ✅       | ✅ via `CrispasrSession`          | Streaming-style STT                        |
| GLM-ASR Nano         | ✅       | ✅ via `CrispasrSession`          | GLM-family multilingual                    |
| VibeVoice ASR        | ✅       | ✅ via `CrispasrSession`          | Large multilingual (~4.5 GB)               |
| MiMo ASR             | ✅       | ✅ via `CrispasrSession`          | XiaomiMiMo MiMo-Audio                      |
| MOSS-Audio 4B        | ✅       | ✅ via `CrispasrSession`          | ASR + audio QA + scene description          |
| LFM2-Audio 1.5B      | ✅       | ✅ via `CrispasrSession`          | ASR + TTS + S2S (English + Japanese)        |
| Mini-Omni2           | ✅       | ✅ via `CrispasrSession`          | ASR + TTS + S2S (Whisper + Qwen2)           |
| Parakeet-RNNT        | ✅       | ✅ via `CrispasrSession`          | RNN-Transducer variants (0.6B/1.1B)        |

The same unified dispatcher is shared with the Python (`crispasr.Session`) and Rust (`crispasr::Session`) wrappers — one C-ABI, three languages.

## 3. Platform status

| Platform | State | Blocker                                                                                      |
| -------- | ----- | -------------------------------------------------------------------------------------------- |
| macOS    | ✅    | None. `flutter build macos` + `scripts/bundle_macos_dylibs.sh` produces a runnable `.app`.   |
| Linux    | ✅    | None. CI `build-linux` job bundles all `.so`'s; local build needs a Linux host.              |
| Windows  | ✅    | Released via `release.yml`; `.zip` with `whisper.dll` + sibling backend DLLs produced on every tag. AVX-512 disabled (`GGML_NATIVE=OFF`, pinned to AVX2+FMA) to avoid crash on Zen3 CPUs (#19). |
| Android  | ⚠️    | KTS gradle only (Groovy + legacy CMakeLists removed). APK builds with Mock engine out of the box; real ASR needs `libwhisper.so` cross-built via `CrispASR/build-android.sh` and dropped into `android/app/src/main/jniLibs/<abi>/`. That wiring isn't automated in CI. File picker uses `FileType.audio` (broad MIME) + post-filter for reliable extension display. Adaptive icon enabled (API 26+). |
| iOS      | ⚠️    | Podfile rewritten to a clean minimal Flutter template. `pod install` should now succeed, but hasn't been CI-verified; the Xcode project still contains a Runner-Bridging-Header.h reference that's now a no-op. App icons regenerated with `remove_alpha_ios: true` — App Store alpha-channel rejection fixed. |
| Web      | ✅    | **HfSpaceEngine** routes ASR + TTS through the `cstr/CrispASR` HF Space via OpenAI-compatible HTTP API. Auto-selected on web; configurable server URL in settings. File picker uses `PlatformFile.bytes` (no filesystem). **CrispEmbed WASM** (1.1 MB) runs text embeddings client-side (~50-100ms/sentence) with Q4_K model (~19 MB) fetched from HuggingFace. `platform_utils.dart` guards all `Platform.*` calls. `deploy-web.yml` auto-deploys to Vercel on push. Live at `crisperweaver-web.vercel.app`. |

## 4. Feature status

| Feature                                    | State                                                                 |
| ------------------------------------------ | --------------------------------------------------------------------- |
| Model download + resume + cancel + delete  | ✅                                                                    |
| Quantised variants (q4_0 / q5_0 / q8_0)    | ✅ from `cstr/whisper-ggml-quants`                                    |
| Checksum skip toggle                       | ✅ in *Settings → Debugging*                                           |
| History (persisted)                        | ✅ `<app-docs>/history/*.json`                                         |
| Exports (TXT / SRT / VTT / JSON)           | ✅ via share sheet                                                    |
| Performance readout (RTF, WPS)             | ✅                                                                    |
| Logging + log viewer                       | ✅ ring buffer + optional file sink                                   |
| Inbound share (audio → app)                | ✅ Android intent filters, iOS doc types, macOS UTI open-in           |
| Desktop drag-and-drop                      | ✅ `desktop_drop` on transcription screen                             |
| Audio decoding (WAV / MP3 / FLAC)          | ✅ `crispasr_audio_load` FFI via miniaudio — no ffmpeg dep            |
| Word-level timestamps (Whisper)            | ✅ via CrispASR 0.2.0                                                 |
| Language auto-detect (Whisper)             | ✅ via CrispASR 0.2.0 `crispasr_detect_language`                      |
| VAD (Silero) — end to end                  | ✅ shipped in v0.1.7 via CrispASR 0.4.4 `crispasr_session_transcribe_vad`; single Advanced Options toggle, Silero GGUF bundled as asset, whisper + session paths both wired |
| Streaming transcription (Whisper)          | ✅ via CrispASR 0.3.0 `crispasr_stream_*` — 10s window / 3s step       |
| i18n (en + de)                             | ✅ `flutter_localizations` + `lib/l10n/*.arb` (866 keys each, full en/de parity). All screens + widgets migrated, including the Model Management HF-repo dialogs and the speaker-enroll flow (May 2026) plus 33 newly-migrated strings for §5.25 features (June 2026). `flutter gen-l10n` succeeds on Flutter 3.35.1. Two paths stay deliberately inline (documented in-code): the Android-only "All files access" Settings dialog and the Translate auto-detect niche path — both carry an explicit "keep inline" rationale. |
| Real speaker diarization (library API)     | ✅ via CrispASR 0.4.5 `crispasr_diarize_segments_abi` — `lib/services/diarization_service.dart` now calls the shared lib (energy / xcorr / vad-turns / pyannote). MFCC/k-means stopgap removed. |
| Language auto-detect for non-Whisper backends | ✅ via CrispASR 0.4.6 `crispasr_detect_language_pcm` — `LidService` (`lib/services/lid_service.dart`) runs whisper-tiny LID before session backends when the user picks "auto" and any multilingual whisper model is downloaded. |
| Word timestamps for LLM backends           | ✅ via CrispASR 0.4.7 `crispasr_align_words_abi` — `AlignerService` (`lib/services/aligner_service.dart`) runs canary-CTC / qwen3-fa as a post-step for qwen3 / voxtral / granite when the user has word-timestamps enabled and an aligner GGUF is on disk. |
| Punctuation restoration (FireRedPunc)      | ✅ via CrispASR 0.5.x `PuncModel` — `PuncService` (`lib/services/punc_service.dart`) plus an "Restore punctuation" toggle in Advanced Options. Loads `fireredpunc-*.gguf` lazily; silently no-ops when the model isn't downloaded. |
| Dynamic backend discovery from libcrispasr | ✅ `ModelService.refreshFromCrispasrRegistry()` — calls `CrispasrSession.availableBackends()` + `crispasr.registryLookup` per backend, merges every linked backend's canonical GGUF into the model picker without any CrisperWeaver code change. Runs on every Model Management screen open. |

---

## 5. Open roadmap items

Earlier §5.1–§5.7, §5.11–§5.21, §5.23, and most of §5.8 are
shipped — see [HISTORY.md](HISTORY.md) for full per-section
write-ups. What follows is only the work that's still pending.

### 5.1 Competitor-gap features

Audited against the common feature set of comparable local
GUI tools (whisper-based desktop apps for macOS / Linux /
Windows) plus the cloud meeting-transcription category, in
May 2026. CrisperWeaver already does most of what they do AND
several things they don't (engine breadth, cross-platform, free /
OSS, multilingual UI, text translation, OpenAI-compatible HTTP
server, parallel batch pool with OOM pre-flight).

Most of §5.1 is shipped — full write-ups in [HISTORY.md → "Post-
v0.4.1 §5.1 competitor-gap sweep — May 2026"](HISTORY.md#post-v041-51-competitor-gap-sweep--may-2026).
Open items only below.

#### Shipped (see HISTORY.md)

- ✅ **5.1.1** System audio capture (macOS / Linux / Windows /
  Android; iOS deliberately unsupported).
- ✅ **5.1.2** Custom vocabulary / dictionary boost.
- ✅ **5.1.3** Inline transcript editing + history persistence.
- ✅ **5.1.4** History search.
- ✅ **5.1.5** Audio waveform editor + bidirectional transcript
  sync (Phases A → D).
- ✅ **5.1.6 v1** Deterministic "Tidy transcript" pass.
- ✅ **5.1.6 v2** BYOK cloud LLM cleanup pass.
- ✅ **5.1.6 v3** Local on-device LLM cleanup + summarisation.
- ✅ **5.1.7** Templates / presets.
- ✅ **5.1.8** Meeting-style summarisation.
- ✅ **5.1.11** Global hotkey for push-to-transcribe.
- ✅ **5.1.12** Voice clone wizard.

#### Open items

* ~~**LID picker — Firered / Ecapa methods**~~ —
  **shipped May 2026**. Upstream CrispASR 0.5.8 extended
  `LidMethod` to all four methods; CrisperWeaver's Advanced
  Options picker now offers all four, the model registry has
  catalogue entries for `firered-lid-f16` + `ecapa-lid-107-f16`,
  and `LidService.methodForFilename` routes by basename.

* ~~**5.1.6 v3.1 Curated chat-model catalogue**~~ —
  **shipped May 2026**. 5 entries spanning small/medium/large
  buckets + ≥ 2 families (SmolLM2-360M, Qwen2.5-0.5B,
  Llama-3.2-1B, Qwen2.5-3B, Llama-3.2-3B — all Q4_K_M via
  bartowski/* HF repos). Settings → Local LLM gets a
  "Suggested chat models" picker; Model Management gets a
  Chat-LLM filter chip. Recommended `nCtx` / `nGpuLayers`
  values live in the model description text — users tune via
  the existing Advanced section sliders.

* ~~**Responsive UI — phone sub-screens for Settings dialogs**~~
  — **shipped May 2026**. The Cloud LLM / Local LLM / Hotkey
  dialogs now route to dedicated sub-screens
  (`/settings/cloud-llm` / `/settings/local-llm` /
  `/settings/hotkey`) on phone-width viewports, sharing the
  same form-widget body with the wide-layout dialogs. See
  CHANGELOG → "Responsive UI — Settings sub-screens on mobile".

* **Platform-native share / receive — remaining tail** — the
  May 2026 pass shipped tiered transcript shares (MD + audio
  bundle), multi-file inbound enqueue, transcript-file intake
  (.srt / .vtt), Linux `.desktop` integration with argv intake,
  and iOS Share Extension *template files* + setup doc. What's
  still pending:

  - ~~**iOS Share Extension target wiring**~~ — **shipped
    (build side) May 2026**.
    `scripts/wire_ios_share_extension.rb` lands the
    PBXNativeTarget / build configurations / Embed App
    Extensions phase / Runner CODE_SIGN_ENTITLEMENTS /
    App Groups SystemCapability into `Runner.xcodeproj`.
    `ios/ShareExtension/RSIShareViewController.swift` vendors
    the extension-safe subset of receive_sharing_intent v1.8.1
    so the extension target doesn't link the upstream
    framework (which calls extension-disallowed
    `addApplicationDelegate`). End-to-end codesigned build
    verified: Runner.app + Runner.app/PlugIns/ShareExtension.appex
    both carry the
    `com.apple.security.application-groups =
    [group.com.crispstrobe.crisperweaver]` entitlement under
    team N9XSJ4M3GT. Only the on-device tap-Share smoke test
    in Voice Memos remains.
  - ~~**macOS Open-With handler**~~ — **shipped May 2026**.
    `OpenWithReceiver.swift` + Dart-side `DesktopOpenWithBridge`
    feed Finder's Open With / `open foo.wav` from the terminal
    / dock-drop into `ShareIntakeService.acceptPaths`.
  - ~~**macOS NSServices**~~ — **shipped May 2026**. Right-click
    a file in Finder → Services → "Transcribe with
    CrisperWeaver" routes the file URLs through the same
    OpenWithReceiver buffer as Open-With. Info.plist
    NSServices entry + `AppDelegate.transcribeAudio(_:userData:error:)`
    + `NSApp.servicesProvider = self` in
    `applicationDidFinishLaunching`.
  - ~~**Windows file association**~~ — **shipped (config
    side) May 2026**. MSIX packaging wired via the `msix` pub
    package + `msix_config:` block in `pubspec.yaml`. The
    Windows job in `release.yml` runs `flutter pub run
    msix:create` after the standard build and uploads the
    resulting `.msix` alongside the existing `.zip`; the MSIX
    declares file-type associations for audio + subtitle types
    (`.wav` / `.mp3` / `.m4a` / `.flac` / `.ogg` / `.aac` /
    `.opus` / `.wma` / `.srt` / `.vtt`). Sideload-only for now
    — Microsoft Store registration is on the roadmap; the
    `pubspec.yaml` block flips to `store: true` + Partner
    Center-issued publisher when that lands. Manual smoke
    test on a real Windows machine still pending.

* **5.1.9 Subtitle burning into video** — User selects a video
  file + transcript, gets a video with hardcoded subs. FFmpeg
  subprocess. ~1 day desktop-only. Misaligned with the
  cross-platform "no FFmpeg on the editing path" line we've
  held everywhere else — would need a Dart-side ffmpeg-kit
  wrapper or a pure-Dart muxer to fit. Deferred until either
  exists.

* ~~**5.8.1 Named speaker recognition (TitaNet + SpeakerDB)**~~ —
  **shipped May 2026**. See
  [HISTORY.md → "§5.8.1 Named speaker recognition"](HISTORY.md)
  for the full write-up.

* ~~**5.1.10 Audio enhancement before transcribe**~~ —
  **shipped May 2026 (CrispASR 0.5.12 + CrisperWeaver)**.
  RNNoise (xiph/rnnoise v0.1, BSD-3, ~425 KB GRU weights
  embedded in the binary) vendored under `CrispASR/src/rnnoise/`
  alongside grammar-parser; new C-ABI
  `crispasr_enhance_audio_rnnoise(in, n, out, out_cap)`
  upsamples 16 kHz → 48 kHz via miniaudio's resampler, runs
  RNNoise's 480-sample frame loop, downsamples back. State
  is per-call so worker isolates run concurrently with no
  coordination. Dart `enhanceAudioRnnoise(pcm)` wraps the
  ABI; pre-0.5.12 dylibs raise UnsupportedError so callers
  graceful-degrade. CrisperWeaver: one switch in Advanced
  Options ("Enhance audio (noise reduction)"), backend-
  agnostic, runs before the §5.8 window slice in both the
  single-file path (`TranscriptionService.transcribeFile`)
  and the parallel-pool dispatch (`_runJobOnPool`). Preset
  round-trip pinned; live test (slow-tagged) asserts ≥20%
  RMS drop on synthetic AWGN PCM.

  Dereverberation is still deferred — RNNoise covers the
  HVAC / fan / keyboard background-noise case, which is the
  common one; reverb removal needs a different model class
  (Demucs / WPE) at ~50–100× the compute. Revisit if user
  feedback flags reverb-heavy recordings.

#### Tier D — skip / wait for demand

* Cloud sync (high effort, splits the privacy story)
* Web UI on top of the HTTP server (desktop app covers this
  audience already)
* Final Cut / Premiere XML export (real niche)
* Voice commands during recording (low value vs. UX complexity)

### 5.8 Advanced-Options leftovers

Most of §5.8 is shipped — see [HISTORY.md → "Advanced Options
completeness — May 2026"](HISTORY.md). What's still pending:

* ~~**GBNF (grammar-constrained sampling)**~~ —
  **shipped May 2026 (CrispASR 0.5.9 + CrisperWeaver)**. All
  six steps landed:
  1. `grammar-parser.{h,cpp}` promoted to `CrispASR/src/`.
  2. C ABI `crispasr_session_set_grammar_text` added with
     parse + symbol-resolution + session-level storage.
  3. wparams.grammar_rules / n_grammar_rules / i_start_rule /
     grammar_penalty wired into the whisper transcribe path.
  4. Dart `CrispasrSession.setGrammar(text, rootRule:,
     penalty:)` + `clearGrammar()` with UnsupportedError /
     ArgumentError mapping.
  5. CrisperWeaver Advanced Options: ExpansionTile with the
     multi-line GBNF TextField + root-rule field + penalty
     slider; Whisper-only gating; wired through both the
     worker pool path AND the engine-direct path.
  6. Tests: upstream Dart smoke (parse / re-set / clear /
     invalid / unknown-root, 3/3 green against real
     libcrispasr + ggml-tiny.en.bin) plus a preset round-trip
     case in CrisperWeaver.

* **CrispASR CLI features missing from CrisperWeaver** — found
  during the §5.23 beam-search audit, listed here so the next
  parity pass doesn't have to rediscover them:
  - ✅ `--offset-t` / `--duration` — **shipped May 2026**.
    Two AdvancedOptions fields + UI in the widget; the screen +
    service layer slices the PCM and shifts segment timestamps
    back to absolute file time via the existing
    `shiftSegmentForResume` helper. New static
    `CrispASREngine.sliceTranscribeWindow` handles the
    sample-rate-aware slice math. 10 unit tests pin the edge
    cases.
  - ✅ `--alt N` / `--alt-n` — alternative-candidate tokens —
    **shipped May 2026 (CrispASR 0.5.13 + CrisperWeaver)**. Full
    write-up in [HISTORY.md → "§5.8 Whisper alt-token capture
    (`--alt N`)"](HISTORY.md). Four-layer landing: whisper
    internals capture top-N runners-up on each greedy step into
    a parallel `alts` vector on the segment; C-ABI exposes both
    low-level token accessors and per-word session-result
    accessors; Dart binding surfaces them as `Word.alts` (with
    a new `AltToken` value class) and a sticky
    `CrispasrSession.setAltN(int)`; CrisperWeaver wires `altN`
    through AdvancedOptions / preset round-trip / worker pool
    and renders a tap-to-pick chip row in the segment edit
    dialog. Closes out the §5.8 CLI-parity gap.

    Still-pending follow-ups (low priority — v1 covers the
    common case):
    - **Beam-search alt capture**. Beam siblings are
      beam-conditional, not greedy alternatives, so v1 only
      fires on greedy. A meaningful beam-aware "show the K
      sibling beams' divergence point" UX would need a different
      whisper-side capture path and a different chip shape
      (sibling-walk rather than tap-to-pick). Defer until a
      user actually asks.
    - **Full word-level alt enumeration**. Whisper tokens are
      sub-word BPE, so a multi-token word like "kubectl" →
      `["kub","ect","l"]` only surfaces alts for the first
      content token ("kub" → "cub" / "tu" / …). Computing
      alternative WHOLE words would require a per-word
      token-tree expansion — out of scope for v1; the
      first-token alts cover most real ambiguity in practice.
      Documented in the C-ABI helper comment + the UI help
      string.
    - ~~**Widget test for the alt-picker popover**~~ —
      **shipped May 2026** as `test/alt_picker_widget_test.dart`
      (commit `7a54e5b`). Pumps the transcript-editor edit dialog
      with the Riverpod + AppLocalizations scaffolding and exercises
      the tap-to-pick chip row. Unit + preset round-trip tests still
      cover the data plumbing underneath.
    - ~~**Live-tagged end-to-end test**~~ —
      **shipped May 2026** as
      `flutter/crispasr/test/alt_tokens_live_test.dart` on the
      CrispASR side. Real transcription with `altN: 3` against
      `ggml-tiny.en.bin` + `samples/jfk.wav`; asserts ≥1
      returned word has alts, every alt's p ∈ [0, 1] and the
      list is descending by p, chosen token is excluded from
      its own alts, and `setAltN(0)` on a re-decode clears
      them. Tagged `live` so `dart test` without
      `CRISPASR_LIB` + `CRISPASR_MODEL` skips silently. On
      the dev box whisper-tiny produces 22/22 words with
      runner-ups on the JFK clip (representative output:
      "Americans → America(4.85%), americ(3.84%),
      American(3.35%)").
  - ✅ Whisper decoder fallback thresholds (`--entropy-thold`,
    `--logprob-thold`, `--no-speech-thold`, `--temperature-inc`
    / `--no-fallback`) — **shipped May 2026 (CrispASR 0.5.10 +
    CrisperWeaver)**. PLAN's earlier claim that they were "in
    the Dart binding, just not in the UI" was wrong; the C ABI
    + Dart binding + UI all needed adding. `--word-thold` not
    surfaced — its CLI semantics (per-word print filter) don't
    map cleanly to a whisper_full_params field. `--no-fallback`
    is `temperature_inc = 0` (whisper.cpp's actual semantics).
  - ✅ Subtitle line formatting `--max-len` / `--split-on-word`
    (May 2026) — see HISTORY. ✅ `--split-on-punct` **shipped
    June 2026** — Dart-side post-processing, works with any backend.
  - ✅ Token suppression (`--suppress-nst`, `--suppress-regex`)
    and `--carry-initial-prompt` — **shipped May 2026 (CrispASR
    0.5.11 + CrisperWeaver)**. CrispASR's earlier claim that
    these were already in the binding was wrong; both the C-ABI
    setter + Dart wrapper had to be added. UI lives in the
    Advanced Options Whisper-only section as a 3-control
    ExpansionTile (2 switches + 1 regex field). `--print-
    confidence` not surfaced — it's a CLI output-formatting
    flag with no wparams analog.

* ~~**Auto-download default**~~ — CrispASR's `-m auto` per backend.
  **✅ Option (a) shipped (May 2026).** The three shapes sketched
  were (a) a per-backend recommended-default + "Recommended" badge,
  (b) "Quick start" AppBar bottom-sheet with a curated combo, (c)
  per-backend collapsible sections each with a "Download default"
  header button.

  **Shipped (a) as the v1 foundation; (b) layers on top later; (c)
  rejected.** What landed:
  - `ModelService.recommendedDefaultModels` — a `static const
    Map<String,String>` (backend → catalogue model name). A **Map**
    rather than the originally-sketched per-entry `bool` flag, so the
    "at most one default per backend" invariant is *structural*
    (unique keys) and curation lives in one auditable place. Covers
    every user-facing ASR / TTS / chat / m2m100 entry point;
    companions / post-proc / VAD / LID / diarisation are absent →
    `defaultForBackend` returns `null` and callers degrade.
  - `ModelService.defaultForBackend(backend)` resolves the pointer
    through `lookupDefinition` (so the full def, with `companions`,
    is ready for `downloadWhisperCppModel` — whose existing companion
    co-download makes the one-tap fetch a complete, runnable setup =
    `-m auto` parity with no new download plumbing).
  - `ModelInfo.recommendedDefault` + a "Recommended" badge on the
    Model Management card and a ⭐ on the Transcribe picker tile.
  - Transcribe picker: when a backend filter is active and nothing
    for it is downloaded, a top-of-list banner offers a one-tap
    "Download recommended: {name} ({size})" (reuses the existing
    download-confirm flow).
  - Guard test `test/model_recommended_default_test.dart`: every
    default resolves to a real entry whose backend matches the key;
    at-most-one-per-backend; `defaultForBackend` / `isRecommended
    Default` behaviour incl. `null` for unflagged backends.

  ~~Remaining: **(b) Quick-start bottom-sheet**~~ — **shipped May 2026
  (v0.6.48)**. A 🚀 action on the Model Management AppBar opens a
  bottom sheet with a curated starter set (Whisper base / Kokoro /
  small chat-LLM), resolved through `defaultForBackend` (curation
  stays in `recommendedDefaultModels`), with per-item + one-tap
  "download all". Reuses the companion-aware `_downloadModel` path.

  *Why (a) first.* `-m auto`'s real semantic is "load the smallest
  functional model for backend X, fetching it if absent." The data
  to express that is a single per-backend pointer. Crucially, the
  **one-click functional setup is already solved** for the hard
  case: a flagged entry's `companions` list is co-downloaded by the
  existing `_downloadModel` path (it pulls the full companion set
  into the models dir), so flagging `kokoro` / `qwen3-tts` /
  `vibevoice-tts` also pulls their voicepacks/codecs in the same tap.

  *Why not (c).* It would restructure Model Management from
  per-quant rows into per-backend collapsible groups — a large
  refactor of `_buildModelList` / the filter chips that fights the
  type-ahead backend filter already there. High effort, no
  capability (a)+(b) don't deliver.

### 5.18 Test-suite speed — CoreML for whisper still pending

MTLBinaryArchive pipeline cache shipped (38× cold-start speedup)
— see [HISTORY.md](HISTORY.md).

**Still pending**:

| Win | Projected speedup | Status |
|---|---|---|
| CoreML for whisper on Apple Silicon (`WHISPER_USE_COREML=1` + paired `.mlmodelc`) | Whisper-tiny already 6 s; large-v3 → 2–3× | Deferred to a future CrispASR cycle |
| Re-download q4_k variants for vibevoice / orpheus | vibevoice 17:22 → ~4 min projected; orpheus 11:50 → ~5 min | Blocked on HF availability |

### 5.22 iOS on-device verification — pending

Static audit + xcframework bundling + plist cleanup all shipped
— see [HISTORY.md](HISTORY.md). What's left needs an iPhone:

1. **Mic permission prompt** — First `record.hasPermission()` must
   show the system mic prompt (`NSMicrophoneUsageDescription`
   already set). Verify initial-grant + "denied → Settings →
   toggle on" recovery.
2. **Streaming mic** — `AudioRecorder.startStream` with PCM16 @
   16 kHz is documented as iOS-supported but only the macOS path
   has been exercised. Confirm sub-second chunk cadence + live
   heartbeat.
3. **Recording → playback transitions** — `just_audio` configured
   with `AudioSessionConfiguration.speech()`; needs on-device
   confirmation that switching mic → file → mic is smooth.
4. **Background audio continuation** — `UIBackgroundModes =
   [audio]` declared; verify streaming mic survives screen-lock.
5. **Share intake** — "Open in CrisperWeaver" from Files / Mail
   delivers a path through `receive_sharing_intent`; verify the
   path is readable (security-scoped) and picked up correctly.
6. **`FilePicker.pickFiles`** — UIDocumentPicker copies to temp;
   verify the returned path is openable by `just_audio`.
7. **CoreML companion `.mlmodelc`** — verify
   `getApplicationDocumentsDirectory()` is writable for the
   unzip target and that the companion actually loads ("Loading
   Core ML model" in libwhisper logs).
8. **`PrivacyInfo.xcprivacy`** — required for App Store Connect
   uploads from May 2024. NSUserDefaults + FileTimestamp APIs
   used; add the manifest before first TestFlight upload.

**Risk:** medium-high. Item 1 (xcframework bundling) was the
only launch-blocker and is done. The rest are quality issues
that surface in use.

**Pre-existing detail on the xcframework bundling +
auto-fix audit:** [HISTORY.md → "iOS feature parity"](HISTORY.md).
### 5.23 Batch transcription — scale-out, parallelism, save/resume

✅ **Shipped May 2026.** All four sub-questions (Q1 foundation,
Q1 grouping + duration probe, Q2 v1 pipeline prefetch, Q2 v2
N-way session pool with OOM pre-flight + worker-protocol
expansion + drain-loop integration, Q3 resume-from-checkpoint,
Q3 polish) shipped end-to-end. Full per-step write-up in
[HISTORY.md → §5.23](HISTORY.md).

**CrispASR-side beam follow-up — ✅ shipped upstream (CrispASR 0.6.11).**
The earlier "granite / voxtral / qwen3 still pending" note here was
**stale**. Verified 2026-05-30 against CrispASR `origin/main`: commit
`0c24178e` ("feat(session): wire beam_size through qwen3-asr, granite,
and voxtral", 2026-05-23) is an ancestor of tag `v0.6.11`, and the
bundled dylib is `libcrispasr.0.6.11` — so all three families now consult
`s->beam_size` in the unified session `transcribe_single` path
(qwen3-asr / granite via `core_beam_decode::run_with_probs`, voxtral via
`run_voxtral_family(…, beam_size)`). Together with the five previously
wired (whisper native + glm-asr / kyutai-stt / firered / moonshine /
omniasr-llm per-backend setters), **nine session backends are beam-wired**.
No CrisperWeaver code change was needed: the worker pool + engine already
drive `CrispasrSession.setBeamSize(...)` for beam-capable backends, so this
is live in the shipped build.

**Build-validated 2026-05-31** (this dev box, M1/Metal, CrispASR
`origin/main` worktree, `test-session-beam`): all three beam *mechanisms*
pass on real models — **whisper** (native BEAM_SEARCH: greedy
no-regression at beam=1, non-empty at beam 2/4), **qwen3-asr** (the
`0c24178e` `run_with_probs` replay path: no-regression + beam=2), and
**glm-asr** (per-backend `_set_beam_size` setter: no-regression + beam=2).
The exercise also caught two bugs in the upstream test suite, both fixed in
CrispASR (`fix/session-beam-test`): the qwen3 case opened backend
`"qwen3-asr"` (the dispatch string is `"qwen3"`) so it never opened a
session, and the no-regression cases passed *vacuously* on a tensorless
test-fixture model (added a `!text.empty()` stub-guard). Whisper beam still
wants an in-app beam-vs-greedy spot check on a real clip, but the engine
path is confirmed sound.

**canary / cohere beam — ✅ now BUILT + bundled (off `origin/main`); live
functional run still postponed.** Commit `52cfec83` ("feat(beam): wire
canary + cohere AED beam search via `run_with_probs_branched`") adds
`canary_set_beam_size` / `cohere_set_beam_size` and a per-decoder beam that
**shares the cross-attention KV across beams and snapshots only the
self-attention KV per beam** (the AED-correct shape), wired into the
`transcribe_single` dispatch behind `s->beam_size > 1`; greedy stays the
default branch. This brings the upstream count to **11 beam-wired session
backends**.

**Build-validated 2026-05-31** (this dev box, M1/Metal): a full libwhisper
rebuilt off `origin/main` (`d846274d`, which contains `52cfec83`) **compiles
clean** and ships both symbols — `nm -gU libwhisper.dylib` shows
`_canary_set_beam_size` + `_cohere_set_beam_size`. The rebuilt dylib is
bundled into the local macOS `.app` (via `scripts/build_macos.sh release`).
So the earlier "not in any tag / not in bundled 0.6.11 / unbuilt" caveat is
resolved on the build axis. **Note:** the source still self-identifies as
`0.6.11` (version string not bumped upstream), but the binary is 35 commits
ahead; CI/release build CrispASR from `CRISPASR_REF: main`, so this ships on
the next CrisperWeaver release automatically.

**Still postponed (deliberately, this session):** the greedy no-regression
+ beam-2/4 *functional* run on a real canary/cohere clip — i.e. confirming
beam actually changes/improves the decode, not just that the symbols link.
That AED live case remains the test gap. The session-beam regression suite
(`tests/test-session-beam.cpp`, commits `ef3c37e4` + `3a04b672`) covers
whisper (native) / qwen3-asr (replay) / glm-asr (setter); canary/cohere AED
is the one still needing a live assertion.

**Genuinely out of scope (no beam):** **voxtral4b** routes through the
streaming API (`voxtral4b_stream_*`), which has no beam hook; CTC/NAR
backends (parakeet-ctc, fastconformer-ctc, wav2vec2, funasr, paraformer,
sensevoice) don't take a token-AR beam either.

---

### 5.9 Dependency refresh — ✅ shipped (June 2026)

**Flutter SDK upgraded: 3.35.1 → 3.44.1** (Dart 3.9.0 → 3.12.1).
36 tier-2 packages bumped, including `device_info_plus` 13.1,
`share_plus` 13.1, `package_info_plus` 10.1, `win32` 6.3,
`file_picker` 12.0.0-beta.5. The `<12.4.0` Xcode pin on
`device_info_plus` was removed. Three files fixed for API changes
(`edit_audio_screen.dart`, `file_picker_util.dart`,
`transcript_summarize_service.dart`). `flutter analyze` 0 issues,
527 tests pass.

**Riverpod 2→3: shipped June 2026.** `flutter_riverpod` 3.3.1.
3 of 4 `StateNotifier` subclasses migrated to modern `Notifier`:
`AppStateNotifier`, `LocaleNotifier`, `EngineManagerNotifier`.
`BatchQueueNotifier` kept on legacy (tests construct directly).
2 `StateProvider` kept on legacy (50+ external `.state=` sites).
`file_picker` 12 is in beta — once stable, the constraint will
naturally pick it up.

### 5.10 Release polish

- Tag-based code signing for macOS + notarization (currently ad-hoc sign only).
- Signed Android APK.
- Windows MSI / EXE installer.

### 5.24 Backend wiring + catalogue follow-ups (post-0.6.42)

Tracks the remaining work to bring every catalogued backend to
fully-wired + verified, and to surface engine backends the app doesn't
list yet. CrispASR edits go through an isolated `git worktree` off
`origin/main` (parallel workers share that clone — see the
crispasr-use-worktree memory).

**A. Post-rebuild guard tightening — ✅ mostly done.**
- ✅ `indextts`, `madlad`, `m2m100-wmt21` (and `cosyvoice3-tts`) dropped
  from the `pending` set in `test/backend_dispatch_test.dart`. Verified
  2026-05-30 against the bundled `libcrispasr.0.6.11` dylib (the one app
  v0.6.44/0.6.45 ship): `availableBackends()` returns 40 backends and all
  four are present. The catalogue-dispatch guard runs green (not stale —
  funasr / paraformer / sensevoice / gemma4-e2b all present).
- ✅ `piper` **build-verified present** in a rebuilt engine. A libwhisper
  rebuilt off CrispASR `origin/main` (`d846274d`, 2026-05-31, this dev box)
  lists `piper` in `CrispasrSession.availableBackends()`: the unified-session
  dispatch arm (`crispasr_c_api.cpp`, `"piper"/"piper-tts"`) + the
  `availableBackends` entry + the CMake `piper-tts` static target are all
  live (piper synthesis also still ships through the separate standalone
  C-ABI, CrispASR `a3bb6586`). `scripts/build_macos.sh` was missing
  `piper-tts` from its explicit `BACKEND_TARGETS` list — fixed in the same
  change.
  - **Kept in `pending`** (alongside the new `f5-tts`, see C) rather than
    dropped: the guard auto-resolves the DEFAULT local dylib
    (`../CrispASR/build-flutter-bundle`), and older bundled / not-yet-rebuilt
    dylibs predate both backends, so emptying `pending` reds the forward
    guard against any stale engine. (CI's `analyze-and-test` job checks out
    CrispASR for the path-dependency but does **not** build it, so the
    `CRISPASR_LIB`-gated guard *skips* in CI; it only runs locally against a
    resolvable dylib.) Verified green both ways 2026-05-31:
    `CRISPASR_LIB=<rebuilt dylib> flutter test test/backend_dispatch_test.dart`
    (fresh engine, has piper+f5-tts) AND the default `flutter test` (stale
    local dylib, lacks them — `pending` covers it). Drop both once the
    standard sibling-build / bundled dylib is past `d846274d`. CI/release
    build CrispASR from `CRISPASR_REF: main`, so the runtime ships on the
    next release automatically.
  - **Runtime guard added (v0.6.48, issue #16):** tapping Synthesize with
    a piper voice used to crash the app — `CrispasrSession.open(backend:
    'piper')` segfaults natively on a dylib that can't dispatch it.
    `TtsService.prepare()` now checks `availableBackends()` and returns
    `TtsLoadStatus.unsupported` (clear message) before the native open;
    it self-heals once a rebuilt dylib lists the backend.

**B. cosyvoice3 catalogue — ✅ DONE.** The sibling landed the session
dispatch (CrispASR `36133247`); catalogued app-side: `cosyvoice3-llm-q4_k`
(default, `kind: tts`, backend `cosyvoice3-tts`, `langsCosyvoice10` —
cardData minus `yue`, folded under `zh`) + five `kind: codec` companions
(`flow-q8_0`, `hift-f16`, `voices`, `s3tok-q4_k`, `campplus-f16`) it
declares as `companions`/`defaultCompanions`, plus a `cosyvoice3-tts`
`BackendRepo`. The engine AUTO-DISCOVERS those siblings by filename next
to the LLM, and `_downloadModel` co-locates them (downloads the full
`companions` list into the models dir) — so listing them is what makes it
work; `setCodecPath` is a harmless no-op for cosyvoice3. `check_model_
languages`: 0 diffs. Verified present in the rebuilt libcrispasr
(40 backends) and **dropped from the forward-guard `pending` set** (see A
for the current `pending` contents).
- **✅ AUDIO-VERIFIED 2026-05-31** — real cosyvoice3 synth run (LLM →
  flow → HiFT) on the origin/main dylib + local models: a TTS→ASR
  roundtrip ("The quick brown fox…" → whisper-base) came back
  "the quick ground fox jumps over the lazy dog" (~3 s of 24 kHz audio,
  4/5 content words — only brown→ground, a tiny-whisper artefact). Voice
  selection: leave it unset → synth uses the first baked voice in
  `voices.gguf` (`voice_name = NULL`); no `setVoice`/`setCodecPath`
  needed. Codified as a `slow`-tagged roundtrip in
  `backend_dispatch_test.dart` (`CRISPASR_TEST_COSYVOICE3_MODEL`).
- Remaining: confirm the Synthesize-screen UX picks a sensible companion
  (it auto-selects the first `kind: codec` of the backend → some
  cosyvoice3 codec; the others are still on disk for auto-discovery, so
  it should be fine, but verify on a run).

**C. Reverse audit — engine backends not yet catalogued. ✅ done.**
Diffed `availableBackends()` (CrispASR origin/main) against the catalogue
backend set. Only two backend-level deltas, both intentionally
engine-only (no catalogue entry warranted):
- `canary-ctc` — shares the canary_ctc compute path, but the only
  published GGUF is `canary-ctc-aligner` (consumed by AlignerService for
  word timestamps); no standalone canary-ctc ASR model is published.
- `omniasr` (bare) — the dispatcher prefix; the concrete `omniasr-llm` /
  `omniasr-llm-unlimited` variants are catalogued.
**Update:** `data2vec-audio` IS dispatchable — its GGUF carries
arch="wav2vec2" and the C-side open accepts `"wav2vec2"/"hubert"/
"data2vec"`, so it runs through the existing `wav2vec2` backend. Now
catalogued as a `BackendRepo` (`cstr/data2vec-audio-960h-GGUF`, backend
`wav2vec2`, en) — no engine change needed. (`bidirlm-omni` is NOT an
audio backend — see F.)
Model-level CTC variants that ARE published (omniASR-CTC, parakeet-tdt_ctc,
fastconformer xlarge/xxlarge) map to already-catalogued backends and are
reachable via the Models-screen HF probe — no hardcoding needed.
Operationalised as a **reverse guard test** (`backend_dispatch_test.dart`:
"every engine backend is catalogued (or intentionally engine-only)") with
an `engineOnly = {whisper, canary-ctc, omniasr}` allowlist — it fails the
moment the engine gains a new backend (e.g. cosyvoice3) so the catalogue
can't silently fall behind.
**Update 2026-05-31:** this guard did its job — the libwhisper rebuilt off
`origin/main` (`d846274d`) exposed a new `f5-tts` backend (CrispASR landed
F5-TTS, a DiT flow-matching zero-shot voice-clone TTS) that the catalogue
didn't list, so the reverse guard went red. Now catalogued: a `BackendRepo`
+ `ModelDefinition` (`cstr/f5-tts-GGUF` → `f5-tts-v1-base-f16.gguf`,
~953 MB, single self-contained GGUF with a baked-in Vocos vocoder, English,
`kind: tts`, backend `f5-tts`), added to `_kindForBackend`'s TTS set, and
re-baked into `baked_models_catalog.dart` (206 → 207 entries). Both guards
green again. **✅ Audio-verified 2026-05-31** (see D): a TTS→ASR roundtrip
(zero-shot clone from `test/jfk.wav` via `setVoice(wav, refText:)`)
returned the target phrase cleanly. Caveat: the DiT synth is **extremely
slow** on the current CPU/Metal build (~50 min for one short sentence), so
the catalogue description warns users and the roundtrip test is opt-in only.

**D. Verification matrix (use the TTS→ASR roundtrip harness + a
translate live test).** Drop the "experimental" flags from CHANGELOG /
docs only once each is confirmed on a real model:
- ✅ **cosyvoice3** — audio-verified 2026-05-31 (see B); `slow` roundtrip
  test added (`CRISPASR_TEST_COSYVOICE3_MODEL`).
- ✅ **f5-tts** — audio-verified 2026-05-31; `slow` roundtrip test added
  (`CRISPASR_TEST_F5TTS_MODEL`). Zero-shot clone from `test/jfk.wav` via
  `setVoice(wav, refText:)`; target phrase round-tripped cleanly. Synth is
  extremely slow (~50 min/sentence on M1 Metal) — opt-in only.
- indextts clone audio — roundtrip with indextts as the TTS leg +
  a reference WAV.
- voxcpm2 clone audio — roundtrip with voxcpm2 + a reference WAV.
- madlad + m2m100-wmt21 translation — add an opt-in translate live test
  (translate a known phrase, assert target-language keywords); confirm
  output is sane.
- Android ANR (lazy whisper load + chunked pool) and iOS kokoro
  (espeak-ng) still need on-device runs (see §5.22).

**E. Process.** Each new engine backend follows: CrispASR dispatch (in a
worktree) → app `ModelDefinition` + `BackendRepo` → drop from guard
`pending` after the dylib rebuild → release. The guard test fails any
catalogue entry whose backend has no dispatch arm, so catalogue and
engine can't silently drift.

**F. Embedding + text-LID models — engine support exists, app binding +
feature do not (TODO).** These aren't ASR/TTS session backends, so they
don't belong in the transcribe catalogue — but the earlier "no app
surface / non-audio" framing was wrong: both touch CrispASR and have
real audio-adjacent uses. What's missing is the Dart FFI binding +
a CrisperWeaver feature, not the runtime.
- `bidirlm-omni-2.5b` (`cstr/bidirlm-omni-2.5b-GGUF`) — an **omnimodal
  embedding** model (text + audio + vision → one shared 2048-d space),
  run by **CrispEmbed** (sibling repo, ggml). Its **audio tower**
  (Whisper-shape, 16 kHz PCM → 2048-d) is built on CrispASR's shared
  `crisp_audio` lib — so it genuinely aligns with CrispASR. Enables
  cross-modal use (semantic transcript search, audio-clip retrieval,
  text↔audio matching). TODO to make it usable in-app: (a) link/embed
  CrispEmbed (or expose an embedding C-ABI from CrispASR), (b) a Dart
  binding, (c) a search/retrieval feature to consume embeddings. Bigger
  than a catalogue entry — it's a new capability.
- ~~Text-LID (`cld3` = `cstr/cld3-GGUF`, plus GlotLID)~~ —
  **shipped May 2026 (v0.6.43)**. C-ABI
  (`crispasr_text_detect_language`) + Dart wrapper
  `detectTextLanguage(text, modelPath)` → `TextLanguage(code,
  confidence)` (CrispASR `1332c5a1`, live-verified de/en/fr/es ≥ 0.99).
  Both app-side pieces landed: (a) `cld3-f16` is catalogued
  (`kind: ModelKind.lid`, `cstr/cld3-GGUF`, ~430 KB) in
  `model_service.dart`; (b) the Translate screen's *Auto-detect source
  language* button runs `detectTextLanguage` over the typed text and sets
  the source-language dropdown, prompting a CLD3 download if it isn't
  present (`translate_screen.dart`). `LidService` stays audio-only; this
  is a parallel text path. ~~Still open as a future idea: labelling a
  pasted transcript's language outside the Translate flow.~~ —
  **shipped May 2026 (v0.6.48)**: a "Detect language" action on the
  transcript output overflow menu runs `detectTextLanguage` over the
  current transcript and reports the language + confidence.
Both now have tracked `hf_readmes/` cards (added this session).

**G. User-reported TTS bug batch (GitHub #16/#17/#18) — ✅ fixed
(v0.6.47/0.6.48), on-device confirm pending.**
- **#16 piper crash (Android & Windows)** — see A: `TtsService.prepare()`
  now gates non-dispatchable backends via `availableBackends()` before the
  native open. *Native no-crash behaviour still wants an on-device run.*
- **#17 qwen3-tts CustomVoice = silence** — CustomVoice needs a
  `setSpeakerName()`; the Synthesize screen had no speaker picker so
  `_selectedSpeaker` was always null. Added a **Speaker** dropdown
  (`session.speakers()`), auto-selecting the first, + a fallback auto-pick
  in `_synthesize`. The selection decision was extracted to a pure static
  `SynthesizeScreen.resolveSpeakerSelection(speakers, current)` (empty→null,
  preserve a still-valid choice, else first) and is now locked by 4 unit
  tests in `test/tts_issue_fixes_test.dart` — the picker's *rendering* still
  sits behind a synchronous FFI session open, so it needs a real
  libcrispasr / on-device run; the *selection contract* no longer does.
  *Audio output still wants an on-device run.*
- **#18 TTS models hidden until deep refresh** — qwen3-tts custom-voice +
  chatterbox turbo T3 added to the static catalogue; the bake script was
  also synced with `backendRepos` (35→63 repos, 206 entries) so all
  drifted models list on a fresh launch. Fully verified by the catalogue
  tests. Re-run `scripts/bake_models_catalog.dart` whenever a `BackendRepo`
  is added — the script's `_repos` list is now in sync.

---

### 5.25 Next-generation features (June 2026)

Fourteen feature proposals spanning UX, intelligence, and workflow
automation. Grouped by projected impact; priority picks marked with ⚡.

#### Tier A — High impact, aligned with existing architecture

* **5.25.1 ⚡ Confidence heatmap on transcript** — ✅ **Enhanced
  June 2026.** The existing text-color confidence tint (green/orange/
  red) is upgraded to a proper background-color heatmap: transparent
  at ≥0.9, subtle yellow tint at 0.7–0.9, orange at 0.5–0.7, red
  at <0.5. Low-confidence words (<0.5) additionally get colored text
  + underline for accessibility. Toggle unchanged (transcript ⋮ menu).

  **Files:** `lib/widgets/transcription_output_widget.dart`
  (`_getConfidenceBackground`, `_buildConfidenceTintedText`).

  **Effort:** ~0.5 day. **Risk:** low — pure UI, no engine change.

* **5.25.2 ⚡ Semantic transcript search via CrispEmbed** — ✅
  **Scaffold shipped June 2026.** `SemanticSearchService` provides
  a TF-IDF fallback scorer that ranks segments by word-overlap
  relevance (better than substring matching for natural language
  queries). `cosineSimilarity()` helper ready for when real
  CrispEmbed vectors are available.

  **Files:** `lib/services/semantic_search_service.dart`.

  **Remaining:** none (v1 complete). CrispEmbed Dart FFI binding
  added as a path dependency. `crispEmbedProvider` lazy-loads the
  first downloaded `ModelKind.embed` GGUF. History screen passes
  the embedder to `SemanticSearchService.search()` for real cosine-
  similarity ranking. Embedding cache avoids re-encoding.
  `all-MiniLM-L6-v2` (384-dim, ~23 MB Q8_0) catalogued.

  **Follow-ups:** (a) ~~vector persistence~~ — **shipped June 2026**.
  (b) ~~audio embedding~~ — **shipped June 2026**. Cross-modal search
  via `crispembed_encode_audio`; `audioEmbedding` persisted per entry;
  `bidirlm-omni-2.5b-q4_k` (2048-d, ~1.7 GB) catalogued.
  (c) more model choices in the catalogue.

  **Effort:** done. **Risk:** n/a.

* **5.25.3 ⚡ Real-time subtitle overlay / teleprompter mode** — ✅
  **Shipped June 2026.** A dedicated fullscreen dark-transparent
  screen (`/subtitle-overlay`) showing the latest streaming
  transcription as large subtitle text. On macOS the window is set
  to always-on-top + reduced opacity via a new platform channel
  (`crisperweaver/window_overlay`). Controls: font size +/-, position
  top/bottom, background toggle. Accessible from the AppBar (wide)
  or overflow menu (phone).

  **Files:** `lib/screens/subtitle_overlay_screen.dart`,
  `macos/Runner/MainFlutterWindow.swift` (platform channel).
  Route: `/subtitle-overlay`.

  **Effort:** ~2–3 days. **Risk:** medium — platform-specific window
  management; Android overlay permission UX (deferred — Android uses
  the same screen in-app for now).

* **5.25.4 Speaker-adaptive vocabulary** — ✅ **Shipped
  June 2026.** `SpeakerVocab` model with per-speaker term lists,
  persisted as `<name>.vocab.json` alongside `.spk` profiles.
  `mergeForSpeakers(allVocabs, identifiedSpeakers)` computes the
  union of all active speakers' terms for injection into
  `initial_prompt`. **Wired (commit `be6526f`):** after diarisation
  resolves speaker names, `SpeakerVocab.mergeForSpeakers()` injects
  domain terms into `advancedOptionsProvider` vocabulary for
  subsequent transcriptions (both single-file and batch paths).

  **Files:** `lib/models/speaker_vocab.dart`.

  **Remaining:** none (v1 complete). Vocab editor dialog accessible
  from Settings → Diarization → Speaker Vocabulary with per-speaker
  term chips (add/delete).

  **Effort:** done. **Risk:** n/a.

* **5.25.5 Multilingual simultaneous transcription** — ✅ **Service
  shipped June 2026.** `MultilingualTranscriptionService` runs
  per-segment LID (via `LidService.detectIfModelAvailable`) on each
  segment's PCM slice and tags it with `metadata['lang']`. Static
  `groupByLanguage()` groups consecutive same-language segments for
  optional re-transcription with a language-specific model.

  **Files:** `lib/services/multilingual_transcription_service.dart`.

  **Remaining:** none (v1 complete). Toggle in Advanced Options
  ("Tag segment languages") runs LID on each segment's audio after
  transcription and tags `metadata['lang']`. Re-transcribe path
  (per-language-group dispatch) deferred until demand.

  **Effort:** done. **Risk:** n/a.

* **5.25.6 Audio chapter markers / podcast show notes** — ✅
  **Service shipped June 2026.** `ChapterDetectionService` detects
  topic shifts via sliding-window Jaccard distance between segment
  vocabularies. Exports to YouTube chapter format (`HH:MM:SS Title`)
  and Podcasting 2.0 `podcast:chapters` JSON. Title auto-generated
  from first segment text. Upgradeable to cosine-distance when
  CrispEmbed embeddings land.

  **Files:** `lib/services/chapter_detection_service.dart`.

  **Remaining:** none (v1 complete). Three export actions in the
  transcript share menu: YouTube chapters (speaker-based via
  NoteExportService), auto-detected chapters (topic-shift via
  ChapterDetectionService), and Podcasting 2.0 JSON. Optionally
  feed chapter boundaries to the Summarise LLM for better titles
  (deferred — current auto-titles from first segment text are
  serviceable).

  **Effort:** done. **Risk:** n/a.

#### Tier B — Medium impact, fills real user gaps

* **5.25.7 Transcript diff / comparison view** — ✅ **Shipped
  June 2026.** `TranscriptCompareScreen` accepts two history entry
  IDs, aligns segments by timestamp overlap, and renders a
  side-by-side view with LCS-based word-level diff highlighting.
  Stats row shows word counts + Jaccard similarity. Route:
  `/compare?left=ID&right=ID`. `HistoryService.loadEntry(id)` added
  to support loading by ID.

  **Files:** `lib/screens/transcript_compare_screen.dart`,
  `lib/services/history_service.dart` (`loadEntry`).

  **Effort:** ~1.5 days. **Risk:** low — pure UI.

* **5.25.8 Watch-folder / scheduled transcription** — ✅ **Shipped
  June 2026.** `WatchFolderService` monitors a user-configured
  directory via `FileSystemEntity.watch()`. New files with audio
  extensions (.wav/.mp3/.flac/etc.) trigger a 2-second debounce,
  then invoke the `onNewFile` callback. Settings → "Watch folder"
  section (desktop-only) with enable toggle + folder picker.
  `SettingsService` persists `watchFolderEnabled` + `watchFolderPath`.

  **Files:** `lib/services/watch_folder_service.dart`,
  `lib/screens/settings_screen.dart` (`_buildWatchFolderSettings`),
  `lib/services/settings_service.dart`.

  **Effort:** ~1 day. **Risk:** low — builds entirely on existing
  batch infrastructure.

* **5.25.9 TTS pronunciation lexicon** — ✅ **Shipped June 2026.**
  `PronunciationLexicon` model with word-boundary-aware text
  substitution (respelling or IPA entries), JSON persistence at
  `<app-docs>/lexicon.json`. Wired into `TtsService.synthesize()`
  — lexicon is applied to input text before the engine call.
  `LexiconEntry` supports both respelling and IPA modes.

  **Files:** `lib/models/pronunciation_lexicon.dart`,
  `lib/services/tts_service.dart`.

  **Remaining:** none (v1 complete). Lexicon editor card in the
  Synthesize screen's Advanced section with add/delete entries.

  **Effort:** done. **Risk:** n/a.

* **5.25.10 Transcript annotation / tagging system** — ✅ **Model
  shipped June 2026.** `SegmentTag` enum with 7 tag types (bookmark,
  action-item, question, important, highlight, decision, follow-up),
  each with label + emoji. JSON round-trip helpers (`toJson`,
  `fromJson`, `listToJson`, `listFromJson`). Integration with note
  exports (Obsidian/Notion/Logseq render tag emojis inline).

  **Files:** `lib/models/segment_tag.dart`.

  **Remaining:** none (v1 complete). Tags are in the long-press menu,
  persisted in history JSON, and filterable via tag chips on the
  History screen.

  **Effort:** done. **Risk:** n/a.

* **5.25.11 Audio fingerprint deduplication** — ✅ **Shipped
  June 2026.** `AudioFingerprintService` computes SHA-256 fingerprints
  from the first 30 s of PCM (8-bit quantized for exact match, 4-bit
  downsampled for coarse/tolerant match). Deterministic, no external
  deps. **Wired (commit `be6526f`):** watch folder auto-skips
  duplicates; batch enqueue silently skips; single-file drag-drop
  shows a confirmation dialog before re-processing.

  **Files:** `lib/services/audio_fingerprint_service.dart`.

  **Effort:** done. **Risk:** n/a.

#### Tier C — Lower effort, high polish

* **5.25.12 Keyboard-driven transcript navigation** — ✅ **Mixin
  shipped June 2026.** `TranscriptKeyboardNav` mixin provides J/K/↑/↓
  segment navigation, Space play/pause, Enter edit, Tab jump-to-next-
  low-confidence, Escape deselect. Includes `segmentFocusDecoration`
  for visual focus ring and `wrapWithKeyboardNav` widget wrapper.

  **Files:** `lib/widgets/transcript_keyboard_nav.dart`.

  **Remaining:** none (v1 complete). Keyboard nav is implemented
  directly in `TranscriptionOutputWidget` (not via the mixin scaffold
  which remains as an unused reference).

  **Effort:** done. **Risk:** n/a.

* **5.25.13 Model A/B testing mode** — ✅ **Shipped June 2026.**
  `AbTestResult` stores per-segment winner picks ('A', 'B', 'tie')
  with aggregate stats (winsA, winsB, overallWinner). `ModelRatings`
  aggregates results across tests into a win-rate leaderboard.
  Results feed into §5.25.7's diff view. **Wired (commit
  `be6526f`):** `_showModelComparison` now spawns two single-worker
  pools via `Future.wait` instead of running models sequentially.
  `ModelRatings` persisted to `<app-docs>/model_ratings.json`.

  **Files:** `lib/services/ab_test_service.dart`.

  **Remaining:** none (v1 complete).

  **Effort:** done. **Risk:** n/a.

* **5.25.14 Export to note-taking tools** — ✅ **Shipped June 2026.**
  `NoteExportService` with four pure formatters: `toObsidian` (YAML
  frontmatter + timestamped bullets), `toNotion` (speaker H2 headers),
  `toLogseq` (indented bullet blocks with `type::` / `timestamp::`
  properties), `toYouTubeChapters` (HH:MM:SS title lines). All
  support segment tags. Wired into the transcript share menu
  (Obsidian / Notion / Logseq / YouTube chapters after the divider).

  **Files:** `lib/services/note_export_service.dart`,
  `lib/screens/transcription_screen.dart` (`_saveAsNote` +
  PopupMenuItems).

  **Effort:** ~0.5 day. **Risk:** low.

### 5.26 CrispASR mid-2026 catch-up (June 2026) — ✅ shipped

Brings CrisperWeaver up to CrispASR `origin/main` as of June 2026.
Covers new backends, new capabilities (hotwords, speech-to-speech),
and free improvements from linking against the latest engine binary
(long-form chunking, global diarization, beam search expansion,
permissive G2P). Full write-up in [HISTORY.md](HISTORY.md).

#### 5.26.1 New backend catalog entries

Four new backends added upstream since the last parity sweep:

| Backend | Type | Size | Notes |
|---------|------|------|-------|
| **LFM2-Audio 1.5B** | ASR+TTS+S2S | ~1.6 GB (Q5_K) | LiquidAI hybrid conv+attention. Also has JP variant (~1.5 GB Q4_K). TTS + S2S via SNAC-like detokenizer baked in. LFM Open License (commercial OK <$10M). |
| **Mini-Omni2** | ASR+TTS+S2S | ~1.0 GB (Q4_K) + ~80 MB SNAC codec | Whisper-small encoder + Qwen2-0.5B LLM. Needs `snac-24khz.gguf` codec companion for TTS/S2S. |
| **MOSS-Audio 4B** | ASR (audio understanding) | ~3.8 GB (Q4_K) | First audio-understanding backend — transcribe + instruction-follow. Already cataloged in model_service.dart but not in baked catalog or model table. |
| **Parakeet-RNNT 0.6B/1.1B** | ASR | ~447 MB / ~770 MB (Q4_K) | Standard RNN-Transducer (no TDT). Runtime auto-detects RNNT. English only. Dispatched through `parakeet` backend. |

**Files:** `lib/services/model_service.dart` (ModelDefinition +
BackendRepo + recommendedDefaultModels + _kindForBackend),
`lib/services/baked_models_catalog.dart` (re-bake).

**Tests:** catalog invariant tests (`model_catalogue_invariants_test.dart`,
`model_recommended_default_test.dart`, `backend_dispatch_test.dart`).

**Effort:** ~0.5 day. **Risk:** low — catalog-only, no engine changes.

#### 5.26.2 Hotwords / contextual biasing UI

CrispASR #98 shipped hotword support at the CLI level:
- **CTC-WS trie** for Parakeet CTC/TDT (`parakeet_set_hotwords`)
- **LLM prompt injection** for Qwen3-ASR / Voxtral / Granite (via
  `--hotwords` → ask-prompt prepend)

For CrisperWeaver, hotwords are delivered through the existing
vocabulary mechanism extended with a dedicated hotwords field:
- A "Hotwords" text field in Advanced Options (comma-separated)
- For LLM backends: merged into the ask prompt via `setAsk()`
  (same path as vocabulary, but with explicit "the following words
  may appear" phrasing matching CrispASR's CLI behavior)
- For CTC backends: hotwords currently only work through the CLI
  binary; session-level `set_hotwords` not yet in the public C API.
  Track upstream CrispASR for a `crispasr_session_set_hotwords()`
  addition. Until then, LLM prompt injection covers 4 of 6
  hotword-capable backends.
- Preset round-trip for the new field.

**Files:** `lib/widgets/advanced_options_widget.dart`
(`AdvancedOptions.hotwords` field + UI), `lib/services/
transcription_service.dart` (merge hotwords into ask prompt).

**Tests:** unit (preset round-trip, hotwords merge into ask prompt),
live (opt-in, real model + hotword → transcript contains the term).

**Effort:** ~1 day. **Risk:** low — extends existing vocabulary
mechanism.

#### 5.26.3 Speech-to-Speech (S2S) mode

CrispASR now supports `--s2s` for LFM2-Audio and Mini-Omni2 —
audio in → audio out in a single model pass. The C API routes
through `crispasr_session_synthesize()` when the backend has
S2S capability and audio has been loaded.

CrisperWeaver surface:
- A "Speech-to-Speech" toggle on the Synthesize screen (visible
  only when the loaded model is S2S-capable: `lfm2-audio` or
  `mini-omni2`).
- When enabled: user picks/records audio input, the engine
  produces transformed audio output (voice conversion, style
  transfer, translation depending on model).
- The session loads the input audio via `transcribe()` internally,
  then `synthesize()` produces the output PCM.

**Files:** `lib/screens/synthesize_screen.dart` (S2S toggle + flow),
`lib/services/tts_service.dart` (S2S-aware synthesize path).

**Tests:** unit (S2S toggle visibility per backend), live (opt-in,
real S2S roundtrip with mini-omni2 or lfm2-audio).

**Effort:** ~1.5 days. **Risk:** medium — new UX flow, needs
careful session lifecycle management (load audio → synthesize in
same session).

#### 5.26.4 Global diarization timeline

CrispASR #110 shipped global diarization — sherpa/ECAPA runs once
on the full audio (not per-slice), giving consistent speaker IDs
across the entire recording. `CrispasrSherpaCache` mirrors the
pyannote global-cache pattern.

CrisperWeaver's `DiarizationService` already calls
`crispasr.diarizeSegments()` which routes through the C API.
**No code change needed** — linking against the latest libcrispasr
picks up the global timeline automatically. The improvement is
C-side: segments are split at speaker-turn boundaries via
word-level overlap scoring.

**Verification:** confirm speaker IDs are consistent across chunks
in a multi-minute test file. Add a live test.

**Effort:** ~0.5 day (verification + test only). **Risk:** none.

#### 5.26.5 Long-form chunking compatibility

CrispASR #89/#114 made chunked-encode + single-decode the default
for Parakeet/Canary/FastConformer. Voxtral/Cohere got proper
streamed-encode paths. Boundary-overlap dedup + splice-punct
cleanup are built in.

CrisperWeaver chunks audio at 30s in the Dart layer
(`TranscriptionService`). The C-side now also auto-chunks for
backends with `CAP_INTERNAL_CHUNKING` dropped. **Risk of double-
chunking:** low — CrisperWeaver's Dart-side chunking sends ≤30s
slices, and the C-side auto-chunking only fires for audio >30s.
Since each Dart slice is ≤30s, the C-side won't re-chunk.

**Verification:** confirm no truncation or duplication on a 60s+
test file with parakeet/canary/voxtral. Add a note to the
chunking code documenting the interaction.

**Effort:** ~0.5 day (verification + comment). **Risk:** low.

#### 5.26.6 Permissive G2P phonemizer

CrispASR #156 replaced the espeak-ng GPL dependency with
pre-generated IPA pronunciation dicts (EN 126K, DE 667K, FR 257K,
ES 600K). This is transparent to CrisperWeaver — Kokoro TTS uses
the new G2P automatically when linking against the latest
libcrispasr.

**No CrisperWeaver code change needed.** Build scripts already
pull the latest CrispASR; the G2P dicts are compiled into the
binary.

**Effort:** 0. **Risk:** none.

#### 5.26.7 Beam search expansion (free upgrade)

CrispASR #139 expanded beam search from 10 to 18 of 24 backends.
CrisperWeaver's Advanced Options already has a beam size slider
that wires through `CrispasrSession.setBeamSize()`. **No code
change needed** — the beam slider now works on 8 additional
backends (including Qwen3-ASR, Granite, Voxtral, Canary, Cohere)
automatically.

**Effort:** 0. **Risk:** none.

---

## 6. Adding a new backend

Three-step recipe:

1. In `CrispASR/src/CMakeLists.txt`, in the *Dart FFI multi-backend linkage* section, add:
   ```cmake
   if (TARGET canary) target_link_libraries(whisper PUBLIC canary) endif()
   ```
2. Add a `#if __has_include("canary.h")` block to `CrispASR/src/crispasr_dart_helpers.cpp`, plus a `case "canary":` arm in `crispasr_session_open_explicit` and `crispasr_session_transcribe`.
3. `cmake --build build --target whisper` and copy both `libwhisper.dylib` + `libcanary.dylib` into the app bundle's `Contents/Frameworks/`.

CrisperWeaver picks up new backends automatically through `CrispasrSession.availableBackends()` — no Dart changes needed. If the user picks a backend the bundled libwhisper wasn't linked with, the load error names exactly which backends ARE available.

## 7. Server modes — built-in vs CrispASR-CLI

**Built-in** (round 5, May 2026): CrisperWeaver ships its own
Dart-side `shelf` HTTP server, toggleable from *Settings → Local
HTTP server*. Bound to `127.0.0.1:8765` by default. Exposes:

- `POST /v1/audio/transcriptions` (multipart upload, OpenAI-shaped
  json/text/srt/vtt response) — routes through the loaded ASR.
- `POST /v1/audio/speech` (JSON in, 24 kHz mono WAV out) — routes
  through `TtsService`.
- `POST /v1/translations` (JSON in, JSON out) — routes through
  `TextTranslationService`.
- `GET /health` (liveness check).

This is the parity path for both desktop and mobile (iOS can't
spawn subprocesses), and avoids loading two copies of every backend
into RAM.

**CLI alternative** (still available for advanced users): CrispASR
ships an HTTP server binary (`examples/cli/crispasr_server.cpp`)
with `POST /inference`, `POST /v1/audio/transcriptions` (OpenAI-
compatible), `POST /load`, `GET /backends`. Desktop builds *could*
bundle the `crispasr` binary and spawn it in server mode for users
who want process isolation or fewer dylibs. We don't bundle it —
the in-app server already covers the use case end-to-end.
