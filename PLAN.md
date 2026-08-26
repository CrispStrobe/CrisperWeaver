# CrisperWeaver — PLAN

Live work only. Completed sections are in [HISTORY.md](HISTORY.md);
technical learnings in [LEARNINGS.md](LEARNINGS.md); the EU AI Act risk
analysis, which is **live and not archived**, in
[docs/AI_ACT_RISK.md](docs/AI_ACT_RISK.md).

**Section numbering is load-bearing.** 436 comments across 86 files in
`lib/`, `bin/` and `macos/Runner/` cite `§`-numbers from this file
(`§5.25.8`, `§12.8h`, …). Never renumber an existing section. New
forward-looking sections use letters (§A, §B, …) precisely so the numeric
space stays stable. If you cannot find a cited section here, it has been
archived to HISTORY.md under its original number.

## Table of contents

**Start here**
- [A. Current state](#a-current-state)
- [B. What to do next](#b-what-to-do-next)
- [C. How to work in this repo](#c-how-to-work-in-this-repo)

**Reference (stable numbering — cited from code)**
1. [Engine status](#1-engine-status)
2. [Model-family status](#2-model-family-status)
3. [Platform status](#3-platform-status)
4. [Feature status](#4-feature-status)
5. [Open roadmap items](#5-open-roadmap-items)
6. [Adding a new backend](#6-adding-a-new-backend)
7. [Server modes — built-in vs CrispASR-CLI](#7-server-modes--built-in-vs-crispasr-cli)

Archived to HISTORY.md: §0, §8–§17.

---

## A. Current state

**Version:** 0.9.8+78. `main` is clean and pushed.

**Where the ship is.** The app is feature-complete and the current work is
store submission, not features.

| Track | State |
|---|---|
| iOS App Store | Building and uploading. First valid build was 75 / v0.9.5. Signing is **manual**, not `flutter build ipa` — see the auto-memory note on iOS signing before touching it. |
| macOS App Store | First build delivered 2026-08-03 (`crisper_weaver-macos-appstore.pkg`). Sandboxed target = `AppStore.entitlements`. |
| TestFlight | Builds are uploading and processing. No evidence in the repo that **external** Beta App Review has been submitted — confirm in App Store Connect before assuming either way. |
| Google Play | Not started. |
| Compliance | EU AI Act: seven audit rounds, all closed. 155 compliance tests green. |

**Health, as of 2026-08-03:** `flutter analyze` 0 errors (44 info lints);
full suite **1304 passed, 104 skipped, 0 failures**; `scripts/build_macos.sh`
builds clean.

**The one thing to know before believing any status claim here.** Seven
audits have now found the same defect shape: a duty or a claim implemented
on the surface where the feature was designed, and missed on a second route
to the same thing. It has never once been an error — always an omission. So
when this document says something is done, the useful question is not "is
that true?" but **"on which surfaces?"** `docs/AI_ACT_RISK.md` §5.2 tells
the whole story; round 7 (HISTORY.md §17) extended it from code paths to
build targets and to public claims that are not code at all.

---

## B. What to do next

Ordered. Each item states what "done" means, so it can be picked up cold.

### B1. Ship the external TestFlight beta — **the critical path**

Everything else is optional next to this. The build works; what is missing
is the submission around it.

- [ ] **Fill App Store Connect metadata from `STORE_LISTING.md`.** It was
      corrected on 2026-08-03 and is now the single source for both stores.
      Use its *App Privacy questionnaire* section for the privacy answers
      rather than reasoning from "it's an offline app" — the app is
      offline-*first*, and two opt-in features transmit.
      `test/store_listing_claims_test.dart` guards the wording; if it fails,
      reword against `PRIVACY.md` §3.1–3.3 rather than relaxing the test.
- [ ] **Screenshots.** Required sizes are listed in `STORE_LISTING.md`.
      None have been produced yet. This is the largest single blocker.
- [ ] **Submit for external Beta App Review**, then address whatever comes
      back. Two things most likely to be questioned, both already handled
      but worth having the answer ready: the local server (off by default,
      loopback-bound, behind *Show advanced features*) and the model
      downloads (data, not executable code — no Guideline 2.5.2 issue).
- **Done when:** an external tester who is not the author installs from
      TestFlight, records audio, and reads a transcript.

### B2. On-device verification passes that need real hardware

Two long-standing gaps, both blocked on a device rather than on code. See
§5.22 for the full iOS checklist and §5.24 D for the backend matrix. Both
are quality issues that only surface in use — which is exactly what a beta
is for, so B1 partly discharges them.

- [ ] iOS: mic permission, streaming mic, record↔playback transitions,
      background audio, share intake, file picker, CoreML companion load.
- [ ] Android ANR check (lazy whisper load + chunked pool).
- [ ] Backend matrix: indextts / voxcpm2 clone-audio round-trips, madlad +
      m2m100-wmt21 translation live test.
- **Done when:** §5.22 items 1–7 are ticked with a device model recorded
      against each.

### B3. Kokoro is multilingual in the catalogue and EN/DE/FR/ES in the build

Found in audit round 7 and **not yet fixed** — scoped here rather than
silently carried.

Every shipped build is deliberately GPL-free: espeak-ng (GPL-3.0) is
compiled `WITH_ESPEAK_NG=AUTO` (dlopen, never linked) and its data is not
staged into any bundle, so `assets/espeak-ng-data.tar.gz` is a 156-byte
placeholder everywhere. That decision is correct and should stand — it is
what keeps App Store distribution clean. The consequence is that Kokoro
falls back to the built-in non-GPL G2P, which covers **EN/DE/FR/ES only**.

Kokoro is also the **top curated TTS starter pick** (`StarterModels`), and
its catalogue description reads "Kokoro multilingual TTS". A first-run
tester who picks it for, say, Japanese gets a degraded result with no
explanation.

- [ ] Decide between: (a) narrow the catalogue description and gate the
      language list to what the built-in G2P actually supports, or (b) ship
      a permissively-licensed phonemizer for more languages.
- (a) is roughly an hour and is the right beta answer; (b) is real work and
      can wait for demand.
- **Done when:** the language set the UI advertises for Kokoro matches the
      set that actually synthesises on a shipped build.

### B4. Release polish (§5.10)

Not blocking the beta. Notarised macOS signing, a signed Android APK, and a
Windows MSI/EXE installer. Details in §5.10.

### B5. Standing compliance duties — no action, but do not let them rot

- **Re-run the audit when the generating surface moves.** Any new engine,
  export format, exit, or build target re-opens the round-7 question. The
  tripwires (`test/compliance_boundaries_test.dart`,
  `test/store_listing_claims_test.dart`) are deliberately brittle; a
  failure means *look*, not *relax the test*.
- **Weakest control, stated honestly:** `AffectivePromptGuard` is a keyword
  list over free text (Art. 5(1)(f)). It is now structurally unforgettable —
  `ScreenedAskPrompt` cannot be constructed unscreened — but it is
  semantically defeatable, and there is no structural move left. See
  `docs/AI_ACT_RISK.md` §2.9.
- **Load-bearing legal call:** speaker ID is classified as biometric
  *verification*, not *identification* (`AI_ACT_RISK.md` §3.1). It is well
  argued but it is an argument. If it were read the other way, Annex III
  1(a) attaches from 2 Dec 2027. Revisit if the closed-roster API changes.
- **Code of Practice on Transparency:** deliberately not signed, with
  recorded re-open triggers (`AI_ACT_RISK.md` §7.2) — stabilised generating
  surface, commercial deployment, or contact from a market surveillance
  authority.

---

## C. How to work in this repo

- **Sync before you commit, in every repo.** These clones are shared with
  parallel workers and the remote is frequently ahead. `git fetch` +
  fast-forward first; never force-push.
- **Run `flutter analyze` and the full test suite before pushing.** The
  suite takes ~100 s and is the only gate this project has. Capture the real
  exit code — piping `flutter test` into `grep`/`tail` returns the *tail's*
  status and will happily report success over a failure.
- **The gate has two blind spots**, both of which have hidden real bugs:
  dylib-gated FFI paths are skipped without `CRISPASR_LIB`, and the web stub
  is never compiled. Check those by hand when you touch them.
- **CrispASR edits go in a separate `git worktree`** off `origin/main` —
  never edit that clone's working tree.
- **macOS builds need the dylib bundler.** Bare `flutter build macos` skips
  it; use `scripts/build_macos.sh`. Symptom of getting this wrong: an empty
  "Available backends in libwhisper:" line.
- **New Swift files must be registered in all four `project.pbxproj`
  sections.** A Flutter macOS target lists its sources explicitly, so an
  unregistered file compiles to nothing and its channel is simply absent at
  runtime — with no build error.

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
| Higgs-STT            | ✅       | ✅ via `CrispasrSession`          | Whisper-v3 enc + Qwen3-1.7B dec             |
| ARK-ASR 3B           | ✅       | ✅ via `CrispasrSession`          | Whisper-RoPE + Qwen2.5-3B, 19 langs        |
| MOSS-Transcribe 2B   | ✅       | ✅ via `CrispasrSession`          | Qwen3-Omni enc + Qwen3 dec, streaming       |
| Gemma4-E4B           | ✅       | ✅ via `CrispasrSession`          | Larger Gemma4 variant (4B dec)               |
| ReazonSpeech v2      | ✅       | ✅ via `CrispasrSession`          | Japanese RNNT (619M, parakeet backend)       |
| Parakeet-CTC JA      | ✅       | ✅ via `CrispasrSession`          | Japanese CTC 1.1B (parakeet backend)         |
| DoTs-TTS             | ✅       | ✅ via `CrispasrSession`          | 2B AR + flow-matching TTS, voice cloning     |

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
| Compressed decode (MP3 / AAC / Opus)       | ✅ on-device via bundled `libglint` (§5.1.11) — tried before the ffmpeg/MediaCodec fallbacks, graceful WAV fallback when absent |
| Compressed export (MP3 / AAC / Opus)       | ✅ `GlintCodecService` / `AudioEditService.exportEncoded` via `libglint` — no external ffmpeg (§5.1.11) |
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

> **Archived 2026-06-12:** Shipped sections (§5.1 shipped items,
> §5.8 shipped items, §5.9, §5.23, §5.24 A/B/C/F-text-LID/G,
> §5.25, §5.26) moved to
> [HISTORY.md → "June 2026 — Shipped items archived from PLAN.md"](HISTORY.md).
> Earlier §5.2–§5.7, §5.11–§5.21 write-ups were already in HISTORY.md.

### 5.1 Competitor-gap features — remaining open items

Most of §5.1 is shipped — full write-ups in
[HISTORY.md](HISTORY.md). Only pending items below.

* **Platform-native share / receive — remaining tail:**
  - Windows file association: manual smoke test on a real Windows
    machine still pending.

* **5.1.9 Subtitle burning into video** — User selects a video
  file + transcript, gets a video with hardcoded subs. FFmpeg
  subprocess. ~1 day desktop-only. Misaligned with the
  cross-platform "no FFmpeg on the editing path" line we've
  held everywhere else — would need a Dart-side ffmpeg-kit
  wrapper or a pure-Dart muxer to fit. Deferred until either
  exists.

#### Tier D — skip / wait for demand

* Cloud sync (high effort, splits the privacy story)
* Web UI on top of the HTTP server (desktop app covers this
  audience already)
* Final Cut / Premiere XML export (real niche)
* Voice commands during recording (low value vs. UX complexity)

### 5.8 Advanced-Options — remaining open items

Most of §5.8 is shipped — see [HISTORY.md](HISTORY.md).
What's still pending (low priority — v1 covers the common case):

* **Alt-token follow-ups:**
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

### 5.18 Test-suite speed — CoreML for whisper still pending

MTLBinaryArchive pipeline cache shipped (38× cold-start speedup)
— see [HISTORY.md](HISTORY.md).

**Still pending**:

| Win | Projected speedup | Status |
|---|---|---|
| CoreML for whisper on Apple Silicon (`WHISPER_USE_COREML=1` + paired `.mlmodelc`) | Whisper-tiny already 6 s; large-v3 → 2–3× | Deferred to a future CrispASR cycle |
| Re-download q4_k variants for vibevoice / orpheus | vibevoice 17:22 → ~4 min projected; orpheus 11:50 → ~5 min | **vibevoice q4_k available** (636 MB, baked June 2026); orpheus q4_k still pending on HF |

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
8. ~~**`PrivacyInfo.xcprivacy`**~~ — **shipped**. Full manifest
   at `ios/Runner/PrivacyInfo.xcprivacy` declaring
   NSUserDefaults (CA92.1), FileTimestamp (C617.1), DiskSpace
   (E174.1), SystemBootTime (35F9.1). Audio data declared as
   AppFunctionality, not linked, not tracked.

**Risk:** medium-high. Item 1 (xcframework bundling) was the
only launch-blocker and is done. The rest are quality issues
that surface in use.

**Pre-existing detail on the xcframework bundling +
auto-fix audit:** [HISTORY.md → "iOS feature parity"](HISTORY.md).

### 5.10 Release polish

- Tag-based code signing for macOS + notarization (currently ad-hoc sign only).
- Signed Android APK.
- Windows MSI / EXE installer.

### 5.24 Backend wiring — remaining open items

Shipped items (A, B, C, F text-LID, G) archived to
[HISTORY.md](HISTORY.md) on 2026-06-12.

**D. Verification matrix — still pending:**
- indextts clone audio — roundtrip with indextts as the TTS leg +
  a reference WAV.
- voxcpm2 clone audio — roundtrip with voxcpm2 + a reference WAV.
- madlad + m2m100-wmt21 translation — add an opt-in translate live test
  (translate a known phrase, assert target-language keywords); confirm
  output is sane.
- Android ANR (lazy whisper load + chunked pool) and iOS kokoro
  (espeak-ng) still need on-device runs (see §5.22).

**G. CrispASR 110fd5ce integration backlog (surveyed 2026-08-26).**
The pin moved v0.8.25 → `110fd5ce` (534 commits). Behavioural fixes we
inherit without writing any Dart:

- **#350** — `transcribe_chunked` on non-JA Parakeet. Between 0.8.24 and
  0.8.28 (i.e. in shipped v0.9.9) a `chunk_seconds = 0` call collapsed to
  ONE full-length decode that silently dropped whole spans of speech. The
  app calls `transcribeChunked` with `chunkSeconds: 0` by default, so
  every Parakeet long-form transcript in v0.9.9 is suspect.
- **#385** — session progress never moved on the unified long-form
  dispatch, so the app's progress bar and `getTranscriptionProgress()`
  poll sat still for the whole decode on those routes.
- **#393** — the Windows cache probe missed GGUFs larger than 2 GiB and
  re-downloaded them every launch.
- **#384** — bare voice names now resolve against the voice dir in five
  TTS adapters.
- **punc** — XLM-R punctuation models returned EMPTY output on the
  default path; `PuncService` gets that back for free.
- **#388** — inter-utterance pause preserved (whisper.cpp#2279 backport).
- **#324** — WeSpeaker/spectral diarization now reaches Accelerate and
  has an opt-in GPU embedder.

New Dart-visible surface, not yet wired, in rough value order:

1. `session.outputSampleRate` / `inputSampleRate` (#332) — **DONE**,
   `TtsService._probeOutputSampleRate`. Was the fix for playing every
   backend at an assumed 24 kHz.
2. `setSensitivity(...)` — **DONE**. Preset picker at the head of the
   fallback-thresholds tile. Preset and the four sliders are mutually
   exclusive by construction: the C side treats a later
   `set_fallback_thresholds()` as overriding a preset, and we fire those
   unconditionally, so sending both would discard the preset every time.
   Wired on BOTH arms — `CrispASREngine` and `transcription_worker` — the
   pooled one being the default route.
   *Also fixed in passing:* the pool never forwarded the four thresholds
   at all, so those sliders were inert on the default path.
3. Diarization `minSpeakers` / `maxSpeakers` / `numSpeakers` +
   `foxnoseEmbedderPath` (#324) — **DONE**. `wespeaker-resnet34-lm`
   catalogued (23 MB, `ModelKind.diarize`), `_findFoxnoseEmbedder()`
   mirrors the pyannote resolver and degrades to vad-turns on a miss.
   The three hints had been accepted-but-ignored since the API was
   written; foxNose is the first method that consumes them.
4. `setSpeakerIdentity(...)` — **PARTLY DONE**. `TtsService.prepare`
   declares `real_person` for a user-supplied reference WAV and
   `synthetic` otherwise. The other half is per-voice provenance: a baked
   preset speaker MAY be a named donor or a corpus speaker (VCTK p225),
   and Art. 3(60) attaches to the audio resembling that person — but the
   catalogue carries no provenance per voice, and asserting `real_person`
   for every preset would make the Art. 50(4) reminder meaningless.
   Needs a provenance field on the voice entries. See §15.2g.
5. `setTtsReferenceLanguage` (#329) — **DONE**, `TtsService.prepare`
   (`referenceLanguage:`). No UI yet: callers pass it, the synthesize
   screen does not ask for it.
6. `setMinSpeechTokens` (#360) — **DONE**, `TtsService.prepare`
   (`minSpeechTokens:`). No UI; MOSS TTS is the only consumer.
7. Chat C ABI abort — **DONE**, `LlmAbortFlag` +
   `local_llm_cleanup_service.cleanupBatch`. A SendPort cannot deliver a
   cancel to the worker: its event loop is blocked inside the synchronous
   native `generate` for the whole generation. So the flag is one `Int32`
   on the shared native heap — isolates share no Dart heap but do share a
   process — polled by the `shouldContinue` predicate from inside the
   native call. `CleanupCancelToken` was previously only read BETWEEN
   segments. **Unverified on a real model**: needs a chat-capable
   libcrispasr plus a 3B GGUF; the shared-word mechanism itself is
   covered by `test/llm_abort_flag_test.dart` across a real isolate
   boundary.
   `countTokens` is still unwired — it would let the summarize/cleanup
   services check a transcript against `nCtx` before starting.

Held back deliberately: **confucius4-tts** is in `engineOnly` — see the
reasoning in `test/backend_dispatch_test.dart`. Short version: zero-shot
only (unintelligible without `--voice`, the #22 failure shape), the
session `set_voice` arm still wants `CRISPASR_CONFUCIUS4_COND_DIR`
externally-computed w2v-BERT features, and it needs three GGUFs.

**E. Process.** Each new engine backend follows: CrispASR dispatch (in a
worktree) → app `ModelDefinition` + `BackendRepo` → drop from guard
`pending` after the dylib rebuild → release. The guard test fails any
catalogue entry whose backend has no dispatch arm, so catalogue and
engine can't silently drift.

**G. MOSS-Diarize + MOSS-TTS — DONE (2026-07).**
Both already compiled into the CrispASR flutter-bundle lib (unconditional
`add_library` + auto-pulled into crispasr-lib), so this was pure catalog
wiring: `moss-diarize` (backend `moss-diarize`, repo
`cstr/MOSS-Transcribe-Diarize-GGUF`) — single-pass ASR + speaker
diarization + timestamps, surfaces as an ASR model with the Ask +
source-language fields enabled; and `moss-tts` (backend `moss-tts`, repo
`cstr/moss-tts-v1.5-GGUF`) — voice-cloning TTS (Qwen3-8B) with the
`moss-tts-v1.5-codec` companion (loaded via setCodecPath) + a reference
voice WAV. Added: 3 `ModelDefinition`s, 2 `recommendedDefaultModels`, 2
`BackendRepo`s, `kindForBackend` tts entry, capability sets, and the
build-script `BACKEND_TARGETS` for early-error parity. Live download +
run validation pending (moss-tts is desktop-class: ~5 GB + ~3.4 GB codec).

**H. CrispASR 0.8.10 backend catch-up — DONE (2026-07, v0.9.1).**
The `backend_dispatch` guard (runs only with the real dylib) flagged
engine backends the catalog had drifted behind on. Added `omnivoice`
(TTS, +tokenizer companion), `irodori-tts` (TTS-JA, +DAC-VAE companion),
`voxtral-tts` (TTS, CC-BY-NC-4.0), `canary-qwen` (ASR), and completed the
partial `nemotron` (ASR) entry; fixed `cosyvoice3-tts` `kindForBackend`
classification. The dispatch guard's allowlists were reconciled:
`tada-1b`/`tada-tts-1b`/`tada-3b-ml` + `reazonspeech` are engine dispatch
aliases (→ `engineOnly`), and `canary-ctc-aligner` is an
AlignerService-consumed forced-aligner, never session-dispatched (→
permanent `pending` exemption). Nemotron ASR live-verified on jfk.wav.

**I. detectBackendFromGguf binding bug — FIXED (2026-07, v0.9.1).**
The `crispasr` package's `detectBackendFromGguf` checked `if (rc != 0)
return null`, but the C ABI returns `strlen(name)` (>0) on a match / 0 on
no-match — so it returned null for EVERY detected backend, silently
killing the #30 GGUF auto-routing and ModelService's post-download
correction. CrisperWeaver now calls the ABI directly with the correct
contract via `lib/native/crispasr_detect_native.dart`; the engine +
ModelService use it. Verified live: the real `cohere-transcribe-arabic`
GGUF resolves to `cohere` and transcribes through the cohere arm (#30).

**F. bidirlm-omni embedding — DONE (§12.3b, §12.8f).**
`bidirlm-omni-2.5b` wired end-to-end: catalog entry, CrispEmbed
stub parity (`encodeAudio`, `hasAudio`), `SemanticSearchService`
cross-modal scoring, `HistoryService.computeAudioEmbedding()` path
verified with JSON round-trip test. Live validation pending on a
machine with the 1.7 GB omni model downloaded.

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

---



---

## Archived sections

§0 and §8–§17 lived here until 2026-08-03 and are now in
[HISTORY.md](HISTORY.md) under their original numbers:

| § | What it was |
|---|---|
| 0 | CrispASR 0.6.x parity sweep (May 2026) |
| 8 | Codebase optimisation plan |
| 9 | CrispASR parity + full test coverage + CLI/server parity |
| 10–12 | CrispASR 0.7.x / 0.8.x / 0.8.7 parity + integration sweeps |
| 13 | EU AI Act compliance (July 2026) — the original sweep |
| 14 | CrispASR 0.8.12 + CrispEmbed 0.15.1 dependency update |
| 15–17 | EU AI Act audit remediation; audit round 2; store-readiness round 7 |

Audit rounds 3–6 were written up in `docs/AI_ACT_RISK.md` §9 rather than
here, and that document stays **live**.
