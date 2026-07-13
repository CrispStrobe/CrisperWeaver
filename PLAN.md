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
8. [Codebase optimisation plan](#8-codebase-optimisation-plan)

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

#### 5.1.11 On-device compressed codec via glint — ✅ shipped

The sibling **glint** repo (`../glint`, MIT, clean-room, dependency-free)
is bundled as `libglint` so the app encodes/decodes **MP3 / AAC-LC /
Opus** on-device without an external ffmpeg binary — closing the
long-standing "WAV-only export, ffmpeg-punt decode" gap.

- **Dart layer:** `lib/native/glint_native{,_stub,_import}.dart` (the same
  conditional-import pattern as `vad_native`; web → stub) →
  `GlintCodecService` (`isAvailable`, `encodePcm[ToFile]`, `decodeBytes`,
  `canDecodePath`). `dart:ffi` stays inside the wrapper so web still
  compiles.
- **Decode:** `AudioService` tries glint for `.mp3/.aac/.opus/.ogg`
  *before* the ffmpeg + Android-MediaCodec fallbacks; any failure falls
  through unchanged.
- **Encode:** `AudioEditService.exportEncoded(...)` writes a compressed
  file (optionally a `[startSec,endSec)` slice); WAV output paths are
  untouched.
- **Native bundling:** `libglint.{dylib,so,dll}` / `glint.xcframework`
  built + shipped per platform by `scripts/build_{macos,linux,windows}.sh`,
  the `bundle_*` scripts, and `scripts/build_ios_glint_xcframework.sh` +
  `wire_ios_glint.rb`. Release CI (`.github/workflows/release.yml`) checks
  out `../glint` and rebuilds the lib fresh for all five platforms,
  mirroring the CrispASR steps. Everything degrades gracefully — when the
  lib isn't present, `isAvailable` is false and callers keep the WAV path.
- iOS uses `DynamicLibrary.process()`, so the framework is *linked* into
  Runner (wire script) rather than dlopen'd by name.

Verified end-to-end on macOS: MP3 + Opus encode→decode round-trips against
the real `libglint.dylib` (`test/glint_codec_test.dart`). Other platforms
build in CI.

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

**E. Process.** Each new engine backend follows: CrispASR dispatch (in a
worktree) → app `ModelDefinition` + `BackendRepo` → drop from guard
`pending` after the dylib rebuild → release. The guard test fails any
catalogue entry whose backend has no dispatch arm, so catalogue and
engine can't silently drift.

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

## 8. Codebase optimisation plan

Audit performed June 2026 against 111 Dart source files (~63 K
LOC), 67 test files (~13 K LOC), 51 widget/screen classes, and
259 `setState` call sites across 22 files.

### 8.1 Split oversized files — ✅ done (June 2026)

The four largest non-generated files concentrate too much logic in
single compilation units, making navigation, review, and
incremental rebuilds harder.

| File | Lines | Problem | Proposed split |
|------|------:|---------|----------------|
| `lib/services/model_service.dart` | 5 696 | Static model catalog + download/verify/delete logic + language lists all in one class | **`model_catalog.dart`** (static `const` model definitions + language lists), **`model_download_service.dart`** (download, checksum, unzip, resume), **`model_service.dart`** (thin public API facade) |
| `lib/screens/transcription_screen.dart` | 3 858 | 29 `setState` calls, 3 inner widget classes (`_PresetsDialog`, `_NarrowTabbedBody`, plus the main state), complex init/load/transcribe state machine | Extract `_PresetsDialog` → `lib/widgets/presets_dialog.dart`, `_NarrowTabbedBody` → `lib/widgets/narrow_tabbed_body.dart`. Break `_TranscriptionScreenState` build method into composable sub-widgets |
| `lib/services/baked_models_catalog.dart` | 3 746 | Auto-generated static catalog data compiled into the binary | Move to a bundled JSON asset (`assets/models/catalog.json`) loaded at runtime. Keeps binary smaller, enables OTA catalog updates without a code release. Update `scripts/bake_models_catalog.dart` to emit JSON instead of Dart |
| `lib/widgets/transcription_output_widget.dart` | 2 372 | 21 `setState` calls, 2 inner dialog classes (`_CleanupDialog`, `_SummarizeDialog`) | Extract `_CleanupDialog` → `lib/widgets/cleanup_dialog.dart`, `_SummarizeDialog` → `lib/widgets/summarize_dialog.dart` |

**Results (June 2026):**

| File | Before | After | Extracted to |
|------|-------:|------:|--------------|
| `model_service.dart` | 5 696 | 1 396 | `model_catalog.dart` (4 318) |
| `transcription_output_widget.dart` | 2 372 | 1 770 | `cleanup_dialog.dart` (295), `summarize_dialog.dart` (334) |
| `transcription_screen.dart` | 3 858 | 3 533 | `presets_dialog.dart` (237), `narrow_tabbed_body.dart` (93) |
| `baked_models_catalog.dart` | 3 746 | — | Deferred — generated data, low risk, JSON migration is separate work |

### 8.2 Reduce `setState` blast radius — ✅ done (June 2026)

Migrated the 7 worst-offender screens/widgets from `setState` to
Riverpod `Notifier` providers with immutable state classes +
`copyWith()`. Total `setState` calls: 288 → 116 (−60%).

| Screen / Widget | Before | After | Provider file |
|----------------|-------:|------:|---------------|
| `synthesize_screen.dart` | 39 | 0 | `synthesize_screen_provider.dart` |
| `settings_screen.dart` | 30 | 3 | *(uses SettingsService directly)* |
| `transcription_screen.dart` | 28 | 0 | `transcription_screen_provider.dart` |
| `audio_recorder_widget.dart` | 18 | 0 | `audio_recorder_provider.dart` |
| `speaker_management_screen.dart` | 17 | 16 | `speaker_management_provider.dart` |
| `edit_audio_screen.dart` | 16 | 0 | `edit_audio_provider.dart` |
| `translate_screen.dart` | 14 | 3 | `translate_screen_provider.dart` |

Remaining 116 `setState` calls are in smaller files not in scope
(voice_clone_wizard, model_management, history, dialogs, etc.) and
the `_EnrolSpeakerScreen` inner widget (kept as local dialog flow).

**Tests:** 7 new unit test files (143 tests total) covering all
provider notifiers via `ProviderContainer`. Full suite: 838 pass,
0 fail, 63 skipped (live).

### 8.3 `const` constructor coverage — ✅ already enforced

Widget files under `lib/widgets/` have reasonable `const` usage
(363 occurrences) but screens do not. Key patterns to fix:

- Padding, SizedBox, Divider, Icon, and Text literals inside
  `build()` that never change should use `const`.
- Extracted child widgets (from 8.2) should declare `const`
  constructors wherever possible.
- Static decoration objects (`BoxDecoration`, `InputDecoration`
  templates) should be `static const` class members, not rebuilt
  every frame.

Run `dart fix --apply` after each batch — the
`prefer_const_constructors` lint catches most of these
automatically.

`analysis_options.yaml` already enables `prefer_const_constructors`,
`prefer_const_declarations`, and `prefer_const_literals_to_create_immutables`
as lint rules. `dart fix --dry-run` reports 0 fixable issues. No action
needed.

### 8.4 Model catalog as data, not code — ✅ done (June 2026)

`baked_models_catalog.dart` was 3 746 lines of compiled-in static
`ModelDefinition` data. Migrated to a JSON asset loaded at runtime.

**Changes:**

| Action | Files |
|--------|-------|
| Added `fromJson`/`toJson` to `ModelDefinition` | `lib/services/model_catalog.dart` |
| Bake script now emits JSON | `scripts/bake_models_catalog.dart` → `assets/models/catalog.json` |
| New async loader with caching | `lib/services/baked_catalog_loader.dart` |
| Wired into `ModelService` + startup | `lib/services/model_service.dart`, `lib/main.dart` |
| Deleted old compiled catalog | `lib/services/baked_models_catalog.dart` (−3 746 LOC) |

**Tests:** 13 unit tests in `test/baked_catalog_json_test.dart` (JSON
round-trip, enum serde, defaults, full catalog load, key consistency,
loader lifecycle) + 2 live tests in `test/baked_catalog_live_test.dart`
(HF probe parity, catalog entry verification).

Language-list constants stay in Dart (small, compile-time referenced).
OTA catalog updates are now feasible as a future enhancement.

### 8.5 Service layer — lazy initialisation — ✅ verified (June 2026)

49 service files. Most are accessed via `ref.read()` from
screens, but some niche services may be eagerly initialised:

- `AudioFingerprintService` — only needed when watch-folder or
  dedup is active.
- `AudioWatermarkService` — only needed in the audio editor.
- `SystemAudioCaptureService` — only needed when system-audio
  recording is toggled on.
- `ChapterDetectionService` — only needed on export.
- `AbTestService` — only needed when the user runs a model
  comparison.

**Audit:** verify these are behind lazy `Provider`s (not
`ref.read()` in `initState` of always-mounted widgets). If
any are eager, wrap them in `Provider.autoDispose` or gate
behind a feature flag check.

**Result:** all five services are standard Riverpod `Provider`s
(lazy by default). None are referenced in `main.dart` or
eagerly initialized. No action needed.

### 8.6 Consolidate HTTP clients — deferred

The app depends on both `dio` (model downloads with progress +
resume) and `http` (lighter requests). This doubles the HTTP
stack in the dependency tree.

**Options (pick one):**

- **Keep `dio` only** — replace the ~5 `http` call sites with
  `dio` equivalents. `dio` already handles the hard cases
  (progress, resume, interceptors).
- **Keep `http` only** — rewrite the `dio` download logic with
  `http.Client` + manual byte-stream progress. More work,
  smaller dependency.

Recommendation: keep `dio`, drop `http`. The download-resume
logic in `model_service.dart` is the critical path and `dio`
handles it natively.

**Priority:** low — small binary-size win, reduces dependency
surface.

**Status (June 2026):** deferred. Only 3 files use `http`
(`audio_service.dart`, `cloud_llm_cleanup_service.dart`,
`transcript_summarize_service.dart`) with well-tested `MockClient`
infrastructure (20+ test cases). Migrating to `dio` would require
rewriting all mock infrastructure for modest gain. Not worth the
churn.

### 8.7 Test coverage — partially done (June 2026)

Started at 595 tests across 67 files. Added 100 new tests in 8
files, reaching 695 tests across 75 files (+17%).

**New test files added:**

| File | Tests | Covers |
|------|------:|--------|
| `model_service_lookup_test.dart` | 18 | Model resolution chain, catalog data classes, kindForBackend, resolveLanguageCodes |
| `ab_test_service_test.dart` | 11 | A/B result wins/ties/overallWinner, ModelRatings leaderboard + accumulation |
| `speaker_vocab_test.dart` | 12 | JSON round-trip, mergeForSpeakers, file save/load/delete/listAll |
| `segment_tag_test.dart` | 8 | Enum JSON serialization, list round-trip, unknown/null handling |
| `watch_folder_service_test.dart` | 7 | start/stop lifecycle, extension filter, debounce detection |
| `log_service_test.dart` | 11 | LogEntry formatting, LogLevel ranking, singleton stream/snapshot |
| `audio_utils_test.dart` | 25 | Audio math (RMS, peak, silence, normalize, stereo→mono, sine wave, float32↔bytes) |
| `file_utils_test.dart` | 8 | sanitizeFilename, generateUniqueFilename |

**Remaining gaps** (widget tests for screens — higher effort,
lower priority than the pure-logic coverage above):

| File | Risk | Notes |
|------|------|-------|
| `transcription_screen.dart` | Medium | Complex state machine; needs full Riverpod + l10n scaffolding |
| `synthesize_screen.dart` | Medium | 39 setState calls; speaker selection logic is unit-tested |
| Extracted dialogs | Low | Services behind them are well-tested |

### 8.8 Build performance — ✅ CI caching shipped (June 2026)

The C++ native layer (CrispASR) dominates build time. Beyond
the existing `CCACHE_DIR=/mnt/volume1/.ccache ninja` convention:

- **Pre-built native binaries for CI** — the `analyze-and-test`
  job checks out CrispASR for the path dependency but does not
  build it. Release jobs build from source. Consider caching the
  built `libcrispasr` artifact between CI runs (keyed on
  CrispASR commit hash) to skip redundant rebuilds.
- **Incremental builds** — verify `build_all.sh` does not clean
  before building. A `cmake --build` with ninja already does
  incremental; only clean on toolchain or CMake-variable changes.
- **Dart side** — `flutter build` is already incremental. The
  main Dart-side build cost is the generated localizations
  (`flutter gen-l10n`) and the `build_runner` JSON serialization;
  both are fast (<5 s).

**Result:** `actions/cache@v4` added to both macOS and Linux build
jobs in `ci.yml`, keyed on `CrispASR` commit hash. Cache hit skips
the full native rebuild (~15-30 min saved).

### 8.9 Asset optimisation — ✅ done (June 2026)

| Directory | Size | Action |
|-----------|------|--------|
| `assets/images/` | 1.4 MB | Verify images are compressed (WebP for raster, SVG where possible). Check for unused splash/icon variants |
| `assets/vad/` | 872 KB | Silero GGUF — already minimal |
| `assets/espeak-ng-data/` | 4 KB (placeholder) | No action — real data extracted at runtime on Android |
| `assets/models/` | 4 KB | Metadata only — no action |

**Result:** `optipng -o2` lossless compression applied:
`app_logo.png` 1.4 MB → 883 KB (37%), `AppLogo.png` 1.8 MB → 1.2 MB
(31%). Both are the only images; no unused variants found.

### Recommended execution order (remaining)

**Done:** 8.1 (file splits), 8.2 (setState reduction — 288→116,
+143 tests), 8.3 (const — already enforced), 8.4 (catalog as
JSON — −3 746 LOC, +13 tests), 8.5 (lazy init — verified),
8.7 (test coverage — +100 tests), 8.8 (CI caching),
8.9 (asset compression).
**Deferred:** 8.6 (HTTP consolidation — not worth test churn).

## 9. CrispASR parity + full test coverage + CLI/server parity (June 2026)

Goal (from owner): match CrispASR's capabilities where feasible;
**unit + live tests for every feature**; achieve **CLI + HTTP-server
feature parity with the GUI**; and **map/resolve code paths reachable
from neither surface** (orphans). Live tests must use only `q4_k`
models already on disk under `/Volumes/backups/ai/crispasr/` — never
download anything >500 MB. This section is the canonical task tracker:
if work breaks, resume from the unchecked boxes.

**Ground truth established (2026-06-20):** the live-test chain works on
this machine — `crispasr_live_test` passes against the locally-built
`../CrispASR/build/src/libcrispasr.dylib` (v0.7.1) + on-disk
`ggml-tiny.bin`. So every gap below is fillable now with existing
models; no downloads needed.

### 9.1 Foundation — shared live-test infra
- [x] `test/support/crispasr_models.dart` — single locator: resolves
      the dylib (`CRISPASR_LIB` → `../CrispASR/build*/src/lib*.dylib`)
      and the smallest `q4_k` model per family from
      `CRISPASR_MODELS_DIR` (default `/Volumes/backups/ai/crispasr`),
      with `CRISPASR_TEST_<X>_MODEL` overrides. Returns null → tests
      self-skip. Replaces the per-file `_resolveLibPath` copies.
- [x] `scripts/run_live_tests.sh` — exports `CRISPASR_LIB` +
      `CRISPASR_MODELS_DIR` and runs `flutter test --tags slow`
      (TMPDIR on the external volume per disk policy).
- [x] Exemplar live test `test/vad_live_test.dart` — **green** (3/3:
      decode, Silero dispatcher, whisper-vad q4_k). Pattern locked.
      Two gotchas surfaced & encoded for all live tests:
      1. The `CrispASR(modelPath)` ctor loads `modelPath` as a *whisper
         ASR context*. Open the ctx on a real ASR model (tiny); pass
         auxiliary models (VAD/LID/punc) only as method args, else
         `dispose()` SIGABRTs.
      2. Verify the *entrypoint* against the C source — `vad()` (legacy
         `crispasr_vad_segments`) fails -2 on Silero/whisper-vad; the
         working call is `vadSlices()` (`crispasr_vad_slices`).

### 9.2 Live-test gaps (parallel agents, one new file each)
Each uses the 9.1 locator + smallest q4_k on disk; self-skips when
absent. Validate with `flutter analyze` + skip-mode run; the heavy
live decode pass is run serially afterward (no concurrent GPU thrash).
- [x] LID live — `test/lid_live_test.dart` (audio LID → 'en' via
      whisper tiny ctx; text LID → English via GlotLID/CLD3). Green.
- [x] VAD live — `test/vad_live_test.dart` (Silero asset + whisper-vad
      q4_k via `vadSlices`). Green.
- [x] Diarization live — `test/diarization_live_test.dart` (pyannote-seg
      labels tiny-ASR segments). Green after fixing a `lib: null` bug
      (diarizeSegments is a top-level fn taking a `DynamicLibrary`, not a
      libPath string — must pass `DynamicLibrary.open(lib)`).
- [x] Aligner live — `test/aligner_live_test.dart` (canary-ctc-aligner
      q4_k; forced word timings, monotonic, in-bounds). Green.
- [x] Punctuation / PCS / truecase live — `test/punc_live_test.dart`
      (fireredpunc q4_k; truecase/PCS self-skip — models not on disk).
      Green.
- [x] Streaming ASR live — `test/streaming_asr_live_test.dart`
      (`crispasr_stream_*` 1 s chunks → committed transcript w/ JFK
      keyword). Green (dropped a brittle window-time upper bound — the
      rolling-buffer t1 isn't bounded by clip duration).
- [x] Alt-ASR-backend roundtrips — `test/alt_asr_backends_live_test.dart`
      (moonshine-tiny, sensevoice, parakeet-tdt_ctc-110m, fastconformer-
      ctc, wav2vec2-xlsr — all 5 transcribe jfk.wav). Green (6/6).
- [x] Translation live — `test/translation_live_test.dart` (madlad q4_k
      EN→DE + EN→FR). Green — but **~42 min wall-clock** (madlad 3B q4_k
      beam-decode is very heavy; didn't OOM, just slow). Impractical for
      routine CI; consider the lighter m2m100 q8 (502 MB) as the default
      and keep madlad as an opt-in — owner call (m2m100 is q8, which
      bends the "q4_k-only" rule, but there's no small q4_k MT on disk).
- [x] Watermark *detect* live — `test/watermark_live_test.dart` (pure
      DSP, no model: embed→detect margin + threshold). Green. Covers the
      §9.5 orphaned watermark-detect capability.
- [x] Local-LLM cleanup/summarize live — `gemma4-e2b-it-q4_k` (2.6 G,
      heavy; lower priority)
- [x] Speech-to-speech live — lfm2-audio-1.5b-q5_k on Kaggle P100 (27.4x RT,
      lower priority)

### 9.3 Unit-test gaps
- [~] Audit each `lib/services/*.dart` for pure-Dart logic lacking a
      unit test; add tests (no model) for the untested ones.
      Done so far: `audio_watermark_format_test.dart` (12),
      `audio_utils_dsp_test.dart` (16), `audio_fingerprint_coarse_test`
      (10) — 38 new leaf-level tests, all green.
      **BLOCKED for the rest:** see §9.7 — the broken CrispEmbed path
      dep makes any test that imports the engine graph fail to compile
      (multilingual grouping, file_utils generators, server SRT/VTT,
      note_export, etc. are written-able but not runnable until fixed).
- [x] Widget tests for the two flagged screens (§8.7): transcription,
      synthesize.

### 9.7 CrispEmbed path dependency — RESOLVED (2026-06-21)
The broken class in CrispEmbed (`CrispSwinirSr` unterminated body) has
been fixed upstream. `flutter analyze` passes clean with the path dep.
The full `flutter test` suite is now runnable. CrispASR rebuilt to
v0.8.0 (`libcrispasr.so.0.8.0`).

### 9.4 CLI + server parity (owner chose: build BOTH)
- [x] `bin/crisperweaver.dart` — first-class CLI over `package:crispasr`
      (no Flutter coupling; runs via `dart run`). COMPLETE, smoke-tested
      live: `backends`, `transcribe` (+`--srt`/`--vtt`, `--temperature`,
      `--best-of`, `--hotwords`, `--seed`, `--max-new-tokens`,
      `--frequency-penalty`, `--beam-size`, `--ask`, `--translate`,
      `--vad`, `--word-timestamps`, `--target-language`), `stream`
      (+`--hotwords`, `--temperature`), `vad`, `lid` (audio+`--text`),
      `diarize`, `align`, `speaker` (enroll/match), `punctuate`,
      `translate`, `synthesize` (+`--voice`, `--temperature`, `--seed`),
      `s2s`, `watermark` (embed/`--detect`). Verified e.g. `align` word
      timings, `speaker match → jfk 1.000`, `stream` full JFK quote.
- [~] Expand `lib/services/server_service.dart` beyond the 4 original
      endpoints. ADDED + tested (`test/server_service_test.dart`):
      `POST /v1/audio/vad`, `/v1/audio/language` (LID), `/v1/text/punctuate`,
      `/v1/audio/diarize`, `/v1/audio/watermark` (detect + embed),
      `/v1/audio/align` (§10, forced alignment with language-aware model
      selection), `/v1/text/language` (§10, text-LID via
      CLD3/GlotLID/FastText-176), `/v1/audio/denoise` (RNNoise),
      `/v1/audio/s2s` (speech-to-speech via lfm2-audio/mini-omni2).
      **WebSocket streaming** (`/v1/audio/stream`) — shipped: binary PCM
      in → JSON transcript segments out. **Generation controls** on the
      transcription endpoint — shipped: `temperature`, `best_of`, `prompt`,
      `hotwords`, `translate`, `vad`, `diarize`, `punctuation` form fields.
      Remaining: speaker (stateful device DB).
- [x] Unit/smoke test for the CLI — `test/cli_test.dart` (help lists all
      commands, usage-error exit codes). Per-capability behaviour is
      covered by the `*_live_test.dart` files (same binding the CLI wraps).
- [x] `docs/PARITY.md` — capability × {GUI, CLI, server} matrix +
      orphan notes + remaining-work list.

### 9.5 Orphan / under-wired paths — verify & resolve
Reachability audit flagged these as reachable from no surface; grep
showed several were false positives (hotwords, system-audio-capture,
text-LID, S2S, aligner are referenced). Confirm each and either wire
it or document it as intentionally internal:
- [x] Watermark **detect** — resolved: reachable via CLI
      (`watermark --detect`) + server (`/v1/audio/watermark`) + live test.
      Only remaining gap is an optional GUI "verify" button (minor UX).
- [x] Speech-to-speech — verified reachable: `synthesize_screen.dart`
      has an `s2sMode` toggle + audio input and calls
      `tts.speechToSpeech()`. Plus CLI `s2s`. Not orphaned.
- [x] Aligner — verified reachable: the Settings **word-timestamps**
      toggle (`settings_screen.dart`) drives `enableWordTimestamps`, and
      `crispasr_engine.dart` runs `AlignerService.addWordTimestamps` when
      the backend emits no word timing. Plus CLI `align`. Not orphaned.
- [x] **VadService silent no-op — FIXED (2026-06-20).** Now calls
      `vadSlicesNative` (new `lib/native/vad_native.dart`, conditional
      web stub) → the free `crispasr_vad_slices` dispatcher, with no
      whisper context at all. Regression-tested in `vad_live_test.dart`
      ("vadSlicesNative … without a ctx"). Original two defects were:
      1. **Wrong entrypoint** — it calls `CrispASR.vad()` =
         `crispasr_vad_segments` (whisper's *native* VAD loader), which
         returns **-2 "model init failed"** for the bundled Silero
         v6.2.0 asset AND the whisper-vad q4_k model. The exception is
         caught and `const []` returned → no spans, ever. The working
         path is `CrispASR.vadSlices()` = `crispasr_vad_slices` (the
         unified dispatcher that handles Silero/FireRed/MarbleNet/
         whisper-vad). **Fix: switch VadService to vadSlices().**
      2. **Unsafe dispose** — it does `CrispASR(vadModelPath)` then
         `.dispose()`; the ctor loads `modelPath` as a *whisper ctx*, so
         `whisper_free` over a non-whisper ctx SIGABRTs (reproduced in
         flutter_tester). Open the ctx on the ASR model and pass the VAD
         model only to `vadSlices(modelPath:)`.
      Confirm both against the app's actually-bundled dylib before
      shipping a fix (the in-app lib may predate this behaviour).
- [x] Final orphan list recorded in `docs/PARITY.md` (§9.5 "Orphan audit
      — resolved"). Net result: no true orphans; only an optional GUI
      watermark-verify button remains as minor UX.

### 9.6 New CrispASR capabilities to consider surfacing
From CrispASR HISTORY (May–Jun 2026), not yet in CrisperWeaver:
- [x] Streaming token callbacks for LLM-based ASR backends (#157) — per-segment (§12.8i) + per-token (12 backends)
- [x] Wyoming protocol server (Home Assistant) (#172) — shipped §12.8h
- [x] Local TTS speaker playback (#173) — preview button on speaker dropdown
- [x] Global-scope diarization (pyannote/sherpa) (#110) — `diarizeFullAudio()` method
- [x] SenseVoice emotion/event tags — parsed from `<|HAPPY|>` etc. in
      transcript text, stripped from display, surfaced as `emotion` /
      `audio_event` in segment metadata + orange/teal badges in
      TranscriptionOutputWidget.
- [x] Paraformer-zh — live test added (`paraformer_zh_live_test.dart`).
      Already in catalog; now validated end-to-end.
- [x] WMT21 translation — live test added to `translation_live_test.dart`
      (EN→DE, EN→FR via wmt21-dense-24-wide-en-x).
(Surface + test only if owner prioritises; otherwise leave tracked.)
- [x] §10 catalog + aligner pipeline (canary-ctc-aligner + 10 wav2vec2
      language variants + language-aware AlignerService + GUI aligner
      picker + CLI `--language` + server `aligner` param) — archived
      to HISTORY.md 2026-06-21.
- [x] CLI `denoise` command (RNNoise pre-processing, matches GUI's
      enhanceAudio toggle).
- [x] Server `/v1/audio/align` + `/v1/text/language` endpoints.
- [x] SenseVoice tag unit tests (13 tests) + aligner map unit tests.
- [x] Server endpoint validation tests (3 new, 11 total).

---

## 10. CrispASR 0.7.x parity sweep (June 2026)

Gap analysis performed 2026-06-21 by diffing every `k_registry[]` entry
in `../CrispASR/src/crispasr_model_registry.cpp` (v0.7.1, 129 entries)
against every `ModelDefinition` + `BackendRepo` in
`lib/services/model_catalog.dart`.

**Outcome:** CrisperWeaver already covers 118/129 registry entries —
the Dart FFI bindings are at 149/149 C-ABI symbol parity. Only 11
downloadable GGUFs have no catalog entry. Everything else (nemotron,
parakeet variants, chatterbox-turbo, kartoffelbox-turbo, kartoffel-
orpheus, gemma4-e2b, mega-asr, qwen3-1.7b ASR, qwen3-tts-customvoice,
voxcpm2-tts, cosyvoice3, pocket-tts, tada, gwen-tts, melotts-v3,
moonshine-de, omniasr-ctc-300m, etc.) was already present under slightly
different catalog keys.

### 10.1 Missing catalog entries — DONE

| # | Backend (CrispASR) | GGUF file | Kind | Gap |
|---|---|---|---|---|
| 1 | `canary-ctc-aligner` | `canary-ctc-aligner-q4_k.gguf` (~442 MB) | ASR (aligner) | No ModelDefinition or BackendRepo |
| 2 | `wav2vec2-aligner-fr` | `wav2vec2-large-xlsr-53-french-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 FR entry at all |
| 3 | `wav2vec2-aligner-es` | `wav2vec2-large-xlsr-53-spanish-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 ES entry |
| 4 | `wav2vec2-aligner-it` | `wav2vec2-large-xlsr-53-italian-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 IT entry |
| 5 | `wav2vec2-aligner-ja` | `wav2vec2-large-xlsr-53-japanese-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 JA entry |
| 6 | `wav2vec2-aligner-zh` | `wav2vec2-large-xlsr-53-chinese-zh-cn-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 ZH entry |
| 7 | `wav2vec2-aligner-nl` | `wav2vec2-large-xlsr-53-dutch-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 NL entry |
| 8 | `wav2vec2-aligner-pt` | `wav2vec2-large-xlsr-53-portuguese-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 PT entry |
| 9 | `wav2vec2-aligner-ar` | `wav2vec2-large-xlsr-53-arabic-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 AR entry |
| 10 | `wav2vec2-aligner-cs` | `wav2vec2-xls-r-300m-cs-250-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 CS entry |
| 11 | `wav2vec2-aligner-uk` | `wav2vec2-xls-r-300m-uk-with-small-lm-q4_k.gguf` (~300 MB) | ASR | No wav2vec2 UK entry |

**Not gaps (confirmed present under different catalog keys):**
- wav2vec2-aligner / wav2vec2-aligner-en → same GGUF as existing `wav2vec2` entry
- wav2vec2-aligner-de → same GGUF as existing `wav2vec2-de` entry
- LID backends (lid-cld3/ecapa/firered/silero/glotlid/fasttext176) →
  already catalogued with generic `backend: 'lid'` (cld3-f16, ecapa-lid-107-f16, etc.)

### 10.2 New tests — DONE
- [x] `test/crispasr_07x_parity_catalog_test.dart` — pins the 11 new entries
      (canary-ctc-aligner + 10 wav2vec2 language variants)
- [x] `test/lid_dispatch_live_test.dart` — exercises each LID dispatcher
      backend (Silero audio-LID, ECAPA, CLD3 text-LID, GlotLID, FastText176)
      via `detectTextLanguage` and `detectLanguage`; self-skips when model
      not on disk
- [x] `test/canary_ctc_aligner_live_test.dart` — forced alignment via the
      new canary-ctc-aligner catalog entry; validates monotonic word onsets

### 10.3 LFM2-Audio GPU default change
CrispASR §206 changed LFM2-Audio to default to CPU (GPU backbone had
Metal miscomputes). CrisperWeaver has no per-backend GPU override UI,
so the engine-side default is authoritative — no CrisperWeaver change
needed. Documented here for awareness.

---

## 11. CrispASR 0.8.x parity sweep (June 2026)

Gap analysis performed 2026-06-30 by diffing the full 246-commit history
between CrispASR v0.8.0 (2026-06-22) and HEAD (8fd9db8f). CrisperWeaver
v0.8.4 shipped against CrispASR 0.8.0; since then CrispASR has added 4
entirely new backends, 3 new model variants for existing backends, and
~15 new capabilities/API surfaces not yet wired through the Dart layer.

### 11.1 New model catalog entries

Seven backends/variants exist in CrispASR but have no `ModelDefinition`
or `BackendRepo` in `lib/services/model_catalog.dart`:

| # | Backend | Type | GGUF | HF repo | Size | Companions | Notes |
|---|---------|------|------|---------|------|------------|-------|
| 1 | `dots-tts` | TTS | `dots-tts-soar-f16.gguf` | `cstr/dots-tts-soar-GGUF` | ~4.4 GB | vocoder `dots-tts-soar-vocoder-f16.gguf` (~345 MB), spk encoder `dots-tts-soar-spk-f16.gguf` (~15 MB) | CAM++ voice cloning, 48 kHz, Metal GPU |
| 2 | `higgs-stt` | ASR | `higgs-stt-q4_k.gguf` | `cstr/higgs-audio-v3-stt-GGUF` | ~2.3 GB | none | Whisper-v3 enc + Qwen3-1.7B dec, internal chunking, beam search, `--ask` |
| 3 | `ark-asr` | ASR | `ark-asr-3b-q4_k.gguf` | `cstr/ark-asr-3b-GGUF` | ~2.2 GB | none | Whisper-RoPE enc + Qwen2.5-3B dec, 19 langs, cross-chunk lang conditioning. **NB: registry says placeholder URL** |
| 4 | `moss-transcribe` | ASR | `moss-transcribe-preview-2b-q4_k.gguf` | `cstr/MOSS-Transcribe-preview-2B-GGUF` | ~1.6 GB | none | Qwen3-Omni enc + Qwen3-1.7B dec, native punctuation, beam search, streaming |
| 5 | `gemma4-e4b` | ASR | `gemma4-e4b-it-q4_k.gguf` | `cstr/gemma4-e4b-it-GGUF` | ~4.1 GB | none | Larger Gemma4 decoder (42L×2560), reuses `gemma4-e2b` backend |
| 6 | `reazonspeech` | ASR | `reazonspeech-nemo-v2-q8_0.gguf` | `cstr/reazonspeech-nemo-v2-GGUF` | ~704 MB | none | Japanese RNNT (619M), reuses `parakeet` backend, Q8_0 (quant-sensitive) |
| 7 | `parakeet-ctc-1.1b-ja` | ASR | `parakeet-ctc-1.1b-ja-q8_0.gguf` | `cstr/parakeet-ctc-1.1b-ja-GGUF` | ~1.2 GB | none | Japanese FastConformer-CTC 1.1B, reuses `parakeet` backend, Q8_0 |

Each needs: `ModelDefinition` entry, `BackendRepo` entry (if new backend),
`kCanonicalModel` entry, language list, and a catalog unit test.

- [x] dots-tts (ModelDefinition + vocoder + spk-encoder companions + BackendRepo)
- [x] higgs-stt
- [x] ark-asr
- [x] moss-transcribe
- [x] gemma4-e4b (shares gemma4-e2b BackendRepo — add variant ModelDefinition only)
- [x] reazonspeech (shares parakeet BackendRepo — add variant ModelDefinition only)
- [x] parakeet-ctc-1.1b-ja (shares parakeet BackendRepo — add variant ModelDefinition only)
- [x] Unit test: `test/crispasr_08x_parity_catalog_test.dart`

### 11.2 New capability wiring — ASR engine

Capabilities added to CrispASR backends since 0.8.0 that need Dart-side
FFI stubs + engine/UI wiring:

| # | Capability | Backends | FFI stub? | Engine call? | UI? | Work needed |
|---|-----------|----------|-----------|-------------|-----|-------------|
| 1 | `setBeamSize(n)` (beam width int) | whisper, canary, cohere, higgs-stt, ark-asr, moss-transcribe | ✅ stub exists | ✅ transcription_worker calls it | ❌ no UI slider | Add beam-width slider in advanced options, gated on `beamSearch == true` |
| 2 | `diarized_json` response format | server endpoint (`POST /v1/audio/transcriptions`) | N/A (server) | N/A | ❌ | Add `response_format=diarized_json` option to server_service |
| 3 | `--diarize-speakers` / consent-gated speaker DB | diarize | N/A | N/A | ❌ | Wire `--diarize-speakers` alias in CLI; consider consent UI for speaker DB |
| 4 | Granite KWB (keyword biasing) | granite-plus | ✅ via existing `setHotwords` | ✅ | ❌ boost slider missing | Add hotwords boost slider in advanced options (0.0–5.0) |
| 5 | Granite `prefix_text` (incremental decode) | granite-plus | ❌ no C API setter yet | ❌ | ❌ | Blocked on CrispASR adding a `crispasr_session_set_prefix_text` C ABI. Track only. |

- [x] Beam-size slider in advanced options
- [x] Hotwords-boost slider in advanced options
- [x] `diarized_json` server response format
- [x] Unit tests for all

### 11.3 New capability wiring — TTS engine

| # | Capability | Backends | FFI stub? | TTS service call? | UI? | Work needed |
|---|-----------|----------|-----------|-------------------|-----|-------------|
| 1 | `setTopK(int)` | qwen3-tts, chatterbox, orpheus, dots-tts | ❌ | ❌ | ❌ | Add FFI stub + TTS service call + synthesize screen slider |
| 2 | `setDoSample(bool)` | all TTS | ❌ | ❌ | ❌ | Add FFI stub + TTS service call + synthesize screen toggle |
| 3 | `setTtsNumCandidates(int)` | chatterbox, kokoro, tada | ❌ | ❌ | ❌ | Add FFI stub + TTS service call + synthesize screen slider |
| 4 | `setSpeakerId(int)` | melotts, piper, fastpitch | ❌ | ❌ | ❌ | Add FFI stub + TTS service call + adapt speaker picker for int IDs |
| 5 | `setG2pDict(String)` | kokoro, vibevoice, speecht5 | ❌ | ❌ | ❌ | Add FFI stub + TTS service call + file picker in synthesize screen |
| 6 | `setTtsNoiseTemp(double)` | kokoro, vibevoice | ❌ | ❌ | ❌ | Add FFI stub + TTS service call + synthesize screen slider |
| 7 | TADA per-request voice switch | tada | ✅ `setVoice` exists | ✅ | ✅ already wired | Verify works without session restart (CrispASR #201 fix) |
| 8 | TADA flow-matching knobs (top_k, do_sample, num_candidates) | tada | covered by items 1-3 above | — | — | Same FFI stubs as items 1-3 |
| 9 | TADA `--make-ref` (C++ voice ref creation) | tada | ❌ no C API | ❌ | ❌ | Blocked on C ABI for make-ref. Track only. |
| 10 | TADA auto-download language voice refs on `-l <lang>` | tada | ✅ auto-download is C-side | ✅ automatic | N/A | No Dart work — C-side handles it |
| 11 | TADA GPU runtime (Metal, quantized FM fallback) | tada | ✅ uses existing GPU toggle | ✅ automatic | N/A | No Dart work — C-side handles it |
| 12 | CosyVoice3 GPU + lazy-load cloning | cosyvoice3-tts | ✅ C-side | ✅ automatic | N/A | No Dart work |

- [x] `setTopK` FFI stub + TTS service + UI
- [x] `setDoSample` FFI stub + TTS service + UI
- [x] `setTtsNumCandidates` FFI stub + TTS service + UI
- [x] `setSpeakerId` FFI stub + TTS service + UI
- [x] `setG2pDict` FFI stub + TTS service + UI
- [x] `setTtsNoiseTemp` FFI stub + TTS service + UI
- [x] Unit tests for all new FFI stubs + TTS service calls

### 11.4 Server + CLI parity

| # | Feature | Status | Work needed |
|---|---------|--------|-------------|
| 1 | `diarized_json` response format (#206) | ❌ | Add to server_service transcription endpoint |
| 2 | `--diarize-speakers` CLI alias | ❌ | Add to CLI diarize command |
| 3 | New backends in CLI `backends` list | ✅ automatic | Dynamic from `availableBackends()` |

- [x] `diarized_json` server support
- [x] `--diarize-speakers` CLI alias
- [x] Unit tests

### 11.5 Execution order

1. Model catalog entries (11.1) — pure data, no FFI changes
2. TTS FFI stubs (11.3) — add all 6 missing setters to `crispasr_stub.dart`
3. TTS service wiring — call new setters from `tts_service.dart`
4. Synthesize screen UI — expose new TTS controls
5. ASR advanced options UI (11.2) — beam-size slider, hotwords-boost slider
6. Server + CLI (11.4) — `diarized_json`, `--diarize-speakers`
7. Unit tests for everything

---

## 12. CrispASR 0.8.7 + CrispEmbed 0.13.0 integration sweep (July 2026)

Gap analysis performed 2026-07-04 by comparing CrispASR v0.8.7 (1541
commits in June) and CrispEmbed v0.13.0 (1568 commits since May 20)
against CrisperWeaver HEAD (95c4e26). §11 covered catalog + TTS FFI +
server parity; this section targets capabilities that landed since.

### 12.1 Quick wins

- [x] **a. `.amr` in file picker + constants.** `app_constants.dart`
      has `.au` but not `.amr`. `file_utils.dart:getAudioFiles()` is
      out of sync with `supportedAudioExtensions` (missing `.amr`,
      `.mp4`, `.wma`, `.aiff`, `.au`, `.ra`). Fix: sync both lists +
      add `.amr`.
      Files: `lib/constants/app_constants.dart`,
      `lib/utils/file_utils.dart`
      Tests: unit test asserting both lists are equal

- [x] **b. Qwen3-ASR-1.7B-JA catalog entry.** Japanese anime/galgame
      fine-tune (dual -hf / non-hf format). Not in catalog.
      Files: `lib/services/model_catalog.dart`
      Tests: catalog invariant test

- [x] **c. Chatterbox emotion tag insert buttons.** Chatterbox TTS
      supports `[laugh]`, `[whispering]`, `[angry]` inline emotion
      tags. Add quick-insert buttons on the synthesize screen when
      chatterbox backend is selected.
      Files: `lib/providers/synthesize_screen_provider.dart`
      Tests: unit test for tag insertion logic

- [x] **d. Engine version string bump.** `crispasr_engine.dart`
      reports `version => '0.8.0'`; should be `0.8.7`.
      Files: `lib/engines/crispasr_engine.dart`

- [x] **e. VAD empty-result guard.** CrispASR now returns empty on
      silent audio (was hallucinating). Verify CrisperWeaver engine
      handles empty transcription result → "no speech detected" UX.
      Files: `lib/engines/crispasr_engine.dart`
      Tests: unit test for empty result path

### 12.2 CrispEmbed stub parity

The CrispEmbed Dart binding (v0.13.0) has grown significantly.
`crispembed_stub.dart` (web fallback) is missing most new APIs.
`crispembed_web.dart` is also incomplete. Both need updating to
match the real binding's API surface.

- [x] **a. Stub: add reranker APIs.** `rerank(query, doc)` → double,
      `rerankBiencoder(query, docs, {topN})` → List<RerankResult>,
      `isReranker` → bool. Plus `RerankResult` class.
      Files: `lib/native/crispembed_stub.dart`
      Tests: unit test importing stub on web

- [x] **b. Stub: add sparse + ColBERT APIs.** `encodeSparse(text)` →
      Map<int,double>, `encodeMultivec(text)` → List<Float32List>,
      `colbertScore(...)` → double, `hasSparse` → bool,
      `hasColbert` → bool.
      Files: `lib/native/crispembed_stub.dart`

- [x] **c. Stub: add vision APIs.** `encodeImage(...)`,
      `encodeImageRaw(...)`, `encodeImageFile(path)`,
      `encodeTextWithImageFile(text, path)`.
      Files: `lib/native/crispembed_stub.dart`,
      `lib/native/crispembed_web.dart`

- [x] **d. Stub: add config APIs.** `setDim(int)`, `setPrefix(String)`,
      `dim` getter, `ctxQueryPrefix`, `ctxPassagePrefix`.
      Files: `lib/native/crispembed_stub.dart`,
      `lib/native/crispembed_web.dart`

### 12.3 Semantic search upgrades

- [x] **a. Reranker integration.** When CrispEmbed model `isReranker`
      or a secondary reranker model is loaded, run a cross-encoder
      reranking pass on the top-k cosine results. Falls back to
      bi-encoder reranking via `rerankBiencoder()` otherwise.
      Files: `lib/services/semantic_search_service.dart`
      Tests: unit test with mock embedder verifying reorder

- [x] **b. BidirLM-Omni audio embedding.** Wire `encodeAudio(pcm)`
      into `SemanticSearchService._embeddingSearch` for cross-modal
      scoring (already stubbed in history_service.dart). When the
      embedder `hasAudio`, encode the audio segment and compare
      against the query vector.
      Files: `lib/services/semantic_search_service.dart`
      Tests: unit test for audio embedding path

### 12.4 imatrix embed model defaults

- [x] CrispEmbed's registry now recommends imatrix quantizations
      (IQ4_XS, Q4_K+imatrix) over plain quants. Update the embed
      `ModelDefinition` entries to point at the imatrix variants.
      Files: `lib/services/model_catalog.dart`
      Tests: catalog invariant test

### 12.5 TADA standalone alignment

- [x] Expose a "Re-align timestamps" action in the transcript detail
      screen. Uses `CrispASR.alignWords()` (already in Dart binding)
      to run CTC forced alignment on existing transcript + audio
      without a full ASR pass.
      Files: `lib/engines/crispasr_engine.dart`,
      `lib/services/aligner_service.dart`,
      `lib/widgets/transcription_output_widget.dart`
      Tests: unit test for alignment-only path; live test

### 12.6 Strategic (higher effort)

- [x] **a. LoRA hot-swap for embeddings.** Dart FFI binding added to CrispEmbed (setLora, getLora, listLora); CrisperWeaver stubs updated. CrispEmbed supports
      dynamic adapter switching. Needs: Dart binding for LoRA load,
      UI for adapter file selection alongside base model.
      Files: `lib/services/semantic_search_service.dart`,
      `lib/native/crispembed_stub.dart`
      Tests: unit test for adapter path propagation

- [x] **b. VLM OCR engine integration.** CrispEmbed added 6 new VLM
      OCR backends. Expose an OCR action that runs document OCR on
      images via a new `OcrService`.
      Files: new `lib/services/ocr_service.dart`
      Tests: unit + live test

- [x] **c. Scan/document preprocessing.** CrispEmbed has deskew,
      denoise, dewarping, super-resolution. Add preprocessing step
      before OCR.
      Files: new `lib/services/scan_preprocess_service.dart`
      Tests: unit test for pipeline orchestration

- [x] **d. WASM CrispEmbed IndexedDB caching.** New WASM build caches
      models in IndexedDB. Improve web target's embedding experience.
      Files: `lib/native/crispembed_web.dart`
      Tests: integration test for WASM path

### 12.7 Additional items (July 2026, round 2)

- [x] LoRA Dart FFI binding added to CrispEmbed (`setLora`, `getLora`,
      `listLora`); CrisperWeaver stubs + web stubs updated.
- [x] OCR service wired to real CrispEmbed FFI via conditional import
      (`ocr_import.dart` + `ocr_stub.dart`); `recognizeMath` + `recognizeRaw`.
- [x] Scan preprocessing wired to CrispEmbed `CrispScanCleanup` FFI
      (`scan_cleanup_import.dart` + `scan_cleanup_stub.dart`); `process()`.
- [x] 6 OCR model catalog entries (pix2tex, HMER, BTTR, PosFormer,
      Granite Vision, DeepSeek-OCR2) + `ModelKind.ocr` enum.
- [x] 3 reranker catalog entries (MS MARCO MiniLM, mxbai XSmall, BGE M3)
      + `ModelKind.reranker` enum + 3 BackendRepos.
- [x] 3 larger embed catalog entries (Nomic v1.5, E5 Small, Qwen3 0.6B)
      + 3 BackendRepos.
- [x] 3 OCR BackendRepos (pix2tex, HMER, Granite Vision).
- [x] `main.dart` embed provider fix: searches `crispasrBackendModels`
      (where imatrix entries live) in addition to `whisperCppModels`.
- [x] "OCR image" action in transcript output widget menu.
- [x] Live tests: re-alignment, VAD silence, reranker scoring.
- [x] Full regression: 1089 pass, 23 skip, 0 fail.

### 12.8 Ship + follow-up (July 2026, round 3)

#### Ship-ready (do now)

- [x] **a. Rebake catalog JSON.** Run `scripts/bake_models_catalog.dart`
      to regenerate `assets/models/catalog.json` with the ~15 new
      ModelDefinitions (OCR, reranker, embed, Qwen3-JA). Without this
      the Model Manager won't show the new entries.
      Files: `scripts/bake_models_catalog.dart` → `assets/models/catalog.json`
      Tests: `baked_catalog_json_test.dart` round-trip check

- [x] **b. Commit + tag release.** v0.9.0 tagged, CI green, release built.
      Commit all §12 work, tag as v0.8.8 or similar.

#### High-impact

- [x] **c. Reranker auto-load in search.** Wire a `rerankerProvider`
      (like `crispEmbedProvider`) that probes for downloaded
      `ModelKind.reranker` GGUFs and loads one as a second CrispEmbed
      instance. Pass it as `reranker:` to `SemanticSearchService.search()`.
      This makes the reranker catalog entries actually functional.
      Files: `lib/main.dart`, `lib/services/semantic_search_service.dart`
      Tests: unit test for provider logic; live test with real model

- [x] **d. Rebuild libcrispembed with LoRA symbols.** Built locally (v0.13.0), LoRA + reranker symbols verified. The Dart binding
      is ready but the bundled `.so`/`.dylib` predates it. Until rebuilt,
      `hasLora` returns false at runtime.
      Files: CrispEmbed build system
      Tests: live test verifying `hasLora` on rebuilt lib

#### Medium-impact

- [x] **e. OCR image picker flow.** Finish the "OCR image" menu action:
      pick image via file_picker, decode to pixels, call
      `ocrService.recognizeMath()`, show result in a dialog with
      copy-to-clipboard.
      Files: `lib/widgets/transcription_output_widget.dart`
      Tests: widget test for dialog

- [x] **f. BidirLM-Omni audio embedding end-to-end.** Verify the
      `HistoryService.computeAudioEmbedding()` → `encodeAudio()` path
      works when the omni model is downloaded. Add a live test.
      Files: `lib/services/history_service.dart`
      Tests: live test with BidirLM model

- [x] **g. Scan preprocessing UI.** "Clean scan" button on the image
      import path that runs deskew + whitening before OCR. Wraps
      `ScanPreprocessService.process()`.
      Files: `lib/widgets/transcription_output_widget.dart` or new widget
      Tests: widget test

#### Lower priority

- [x] **h. Wyoming protocol server.** Home Assistant integration —
      exposes CrispASR as a Wyoming STT provider over TCP. Niche.
      Files: new `lib/services/wyoming_service.dart`

- [x] **i. Streaming segment callbacks for LLM-ASR.** C-ABI added to CrispASR
      (`crispasr_segment_callback` + polling via `drain_streamed_segments`).
      CrisperWeaver engine polls during transcription and fires `onSegment`. Live partial results
      from Qwen3/ARK/MOSS backends during decode. Needs UI for
      progressive text display.
      Files: `lib/engines/crispasr_engine.dart`

- [x] **j. Widget tests for transcription + synthesize screens.**
      Remaining test coverage gap (§8.7/§9.3). High effort, lower
      priority than service/provider tests already covering the logic.
