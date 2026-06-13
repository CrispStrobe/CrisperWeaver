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

**F. bidirlm-omni embedding — TODO (pending).**
`bidirlm-omni-2.5b` (`cstr/bidirlm-omni-2.5b-GGUF`) — an **omnimodal
embedding** model (text + audio + vision → one shared 2048-d space),
run by **CrispEmbed** (sibling repo, ggml). Its **audio tower**
(Whisper-shape, 16 kHz PCM → 2048-d) is built on CrispASR's shared
`crisp_audio` lib — so it genuinely aligns with CrispASR. Enables
cross-modal use (semantic transcript search, audio-clip retrieval,
text↔audio matching). TODO to make it usable in-app: (a) link/embed
CrispEmbed (or expose an embedding C-ABI from CrispASR), (b) a Dart
binding, (c) a search/retrieval feature to consume embeddings. Bigger
than a catalogue entry — it's a new capability.

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

### 8.2 Reduce `setState` blast radius

259 `setState` calls rebuild entire subtrees. The worst offenders:

| File | `setState` count |
|------|----------------:|
| `synthesize_screen.dart` | 39 |
| `settings_screen.dart` | 30 |
| `transcription_screen.dart` | 29 |
| `transcription_output_widget.dart` | 21 |
| `audio_recorder_widget.dart` | 18 |

**Approach:**

1. **Fine-grained Riverpod providers** — move local UI state
   (toggle flags, filter strings, pending booleans like
   `_transcribePending` / `_loadCancelled`) into `Notifier`
   providers. Widgets `watch()` only the slice they need.
2. **`ValueNotifier` + `ValueListenableBuilder`** for truly
   local state that doesn't need cross-widget sharing (e.g.
   `_showAdvancedOptions`, `_dropHover`).
3. **Extract `const`-constructable child widgets** — subtrees
   that don't depend on mutable state should be separate
   `StatelessWidget`s with `const` constructors so Flutter's
   element tree short-circuits their rebuild.

**Priority:** high — directly reduces per-frame work on the
main screens.

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

### 8.4 Model catalog as data, not code

`model_service.dart` + `baked_models_catalog.dart` together are
~9 400 lines, mostly `static const` data (language lists, URL
patterns, model definitions). This:

- Inflates compile time (Dart AOT must process 9 K lines of
  constant initializers).
- Enlarges the app binary with data that could be a bundled asset.
- Prevents catalog updates without a code release.

**Proposed migration:**

1. Emit the bake script output as `assets/models/catalog.json`
   instead of `baked_models_catalog.dart`.
2. Add a `ModelCatalog` class that loads + caches the JSON on
   first access (lazy, off the main isolate for large catalogs).
3. Language-list constants stay in Dart (they're small and
   referenced at compile time by other code).
4. Later: fetch a remote catalog manifest with a local-cache
   fallback, enabling OTA catalog updates.

**Priority:** medium — high payoff for binary size and release
velocity, but requires updating every caller of the current
static catalog API.

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

### 8.7 Test coverage

67 test files / ~13 K lines against 111 source files / ~63 K
lines = roughly 20% coverage by LOC. The riskiest gaps:

| File | Lines | Current coverage | Risk |
|------|------:|------------------|------|
| `model_service.dart` | 5 696 | Catalog invariant tests only; download/verify/resume untested | High — model downloads are the #1 user-facing failure mode |
| `transcription_screen.dart` | 3 858 | No widget tests | High — complex state machine (`_transcribePending` / `_loadCancelled` / `_engineReady` / `_initFuture`) |
| `baked_models_catalog.dart` | 3 746 | Covered by invariant tests | Medium — generated code, but the generator itself is untested |
| `transcription_output_widget.dart` | 2 372 | `replaceFirstWholeWord` + alt-picker tested; dialog flows untested | Medium |
| `synthesize_screen.dart` | 1 417 | Speaker-selection unit tests only | Medium — 39 `setState` calls with no widget test |

**Approach:** prioritise widget tests for the state-machine
screens (transcription, synthesize) and integration tests for
the model-download happy path + resume-after-interrupt.

**Priority:** medium — does not change runtime performance but
prevents regressions during the refactors above.

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

1. **8.2** Reduce `setState` blast radius (large behavioral refactor)
2. **8.4** Model catalog as data (binary size + release velocity)
3. **8.7** Test coverage for refactored code

**Already done:** 8.1 (file splits), 8.3 (const — already enforced),
8.5 (lazy init — verified), 8.8 (CI caching), 8.9 (asset compression).
**Deferred:** 8.6 (HTTP consolidation — not worth test churn).
