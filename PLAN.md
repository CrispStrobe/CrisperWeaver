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
- [x] SenseVoice **event** tags — parsed from `<|BGM|>`, `<|Laughter|>`
      etc. in transcript text, stripped from display, surfaced as
      `audio_event` in segment metadata + a teal badge in
      TranscriptionOutputWidget.
      **Emotion tags were removed 2026-08-02** (audit round 3): surfacing
      `<|HAPPY|>` as an `emotion` field + badge made the app an emotion
      recognition system under EU AI Act Art. 3(39) and an Annex III 1(c)
      high-risk system from 2 Dec 2027. They are now discarded at the parse
      boundary in `CrispasrEngine` and on every CLI output format, driven by
      the discard list in `lib/utils/emotion_inference.dart`. Reasoning and
      re-open trigger: `docs/AI_ACT_RISK.md` §2.8.
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

---

## 13. EU AI Act compliance (July 2026)

Full compliance sweep targeting EU AI Act (Regulation (EU) 2024/1689),
GDPR, and the C2PA provenance standard. CrisperWeaver is classified as
a **general-purpose AI application** with two features touching Annex III
high-risk categories: biometric categorization (speaker ID) and
deepfake/synthetic audio generation (TTS with voice cloning).

### 13.1 What already exists

| Requirement | Implementation | Status |
|---|---|---|
| **Art. 50: AI content watermark** | Spread-spectrum watermark auto-embedded by C API (`crispasr_session_synthesize`); Dart-side LSB fallback for web | DONE |
| **Art. 50: Machine-readable metadata** | WAV LIST/INFO (`ISFT=AI-generated`), MP3 ID3v2 TXXX (`AI_GENERATED=true`), HTTP `x-content-ai-generated: true` header | DONE |
| **Art. 50: C2PA provenance** | Unsigned JSON-LD manifest in RIFF `c2pa` chunk (fallback) + native COSE/X.509 signed C2PA via c2pa-audio (primary) | DONE |
| **Art. 50(4): Deepfake disclosure** | Beep-based audio disclaimer prepended to voice-cloned TTS output | DONE |
| **Art. 50(4): Voice-clone consent** | Voice clone wizard requires rights attestation checkbox; server API requires `disclaimer_override_attestation` string to suppress beep | DONE |
| **Art. 52: AI transparency notice** | First-use dialog explaining AI systems in use; persisted dismissal | DONE |
| **GDPR Art. 9: Biometric consent** | Explicit consent dialog before speaker enrollment with purpose/legal-basis record | DONE |
| **GDPR Art. 17: Right to erasure** | `deleteSpeaker()` deletes both embedding and consent record | DONE |
| **GDPR Art. 20: Data portability** | `exportSpeakerData()` exports all stored data for a speaker | DONE |
| **Privacy by design** | All processing on-device; `collectUsageData = false`, `enableCloudSync = false` | DONE |
| **Synthetic export disclosure** | SRT/VTT/JSON/Markdown exports default to `syntheticDisclosure = true` | DONE |
| **Post-embed verification** | `detectWatermark()` called immediately after watermark embedding | DONE |
| **Heuristic AI detection** | `detectAiAudio()` analyzes spectral/temporal properties of unknown audio | DONE |
| **Watermark verify UI** | "Verify Watermark" button in transcription screen toolbar | DONE |
| **Compliance indicator** | Synthesize screen shows provenance status card | DONE |
| **Compliance tests** | 14 synthetic compliance tests + format-specific tests | DONE |
| **iOS Privacy Manifest** | `PrivacyInfo.xcprivacy` with audio data declarations | DONE |
| **Privacy policy** | `PRIVACY.md` covering data collection, permissions, user rights | DONE |
| **Consent audit logging** | `[CONSENT]` log entries for voice-cloned synthesis | DONE |

### 13.2 What was added in this sweep

- [x] **a. Real C2PA signing via c2pa-audio.** `CrispasrC2pa` Dart FFI
      class wraps `crispasr_c2pa_sign()` (ES256 COSE_Sign1 + JUMBF, via
      vendored c2pa-audio submodule). TTS service tries native signing
      first, falls back to unsigned JSON-LD when unavailable. Stub added
      for web.
      Files: `CrispASR/flutter/crispasr/lib/src/crispasr.dart`,
      `lib/native/crispasr_stub.dart`, `lib/services/tts_service.dart`

- [x] **b. Mandatory beep disclaimer with burden-shift override.**
      Removed `spokenDisclaimer: bool` parameter from `writeWav()`.
      Replaced with `disclaimerOverrideAttestation: String?` — to suppress
      the beep, callers must provide a non-empty legal attestation string
      documenting their basis for suppression. The attestation is logged
      at WARNING level with full context for audit. Server API field
      renamed from `spoken_disclaimer` to `disclaimer_override_attestation`.
      Files: `lib/services/tts_service.dart`,
      `lib/services/server_service.dart`

- [x] **c. Third-party voice consent gate in voice clone wizard.**
      Handoff step now includes a consent box: "I confirm that I have the
      rights to clone this voice." The Finish button is disabled until
      checked. Matches CrispASR's `--i-have-rights` pattern. Localized
      in EN/DE/ZH with EU AI Act + GDPR references.
      Files: `lib/screens/voice_clone_wizard_screen.dart`,
      `lib/l10n/app_{en,de,zh}.arb`

- [x] **d. Art. 52 first-use AI transparency notice.** On first launch,
      a non-dismissable dialog explains which AI systems CrisperWeaver
      uses (ASR, TTS, speaker ID, OCR, semantic search), that all
      processing is on-device, and that AI-generated audio is
      watermarked/signed. Persisted via `SettingsService`. Localized
      EN/DE/ZH.
      Files: `lib/main.dart`, `lib/services/settings_service.dart`,
      `lib/l10n/app_{en,de,zh}.arb`

- [x] **e. Synthetic disclosure defaults to true.** All export format
      functions (`generateSrtContent`, `generateVttContent`,
      `generateJsonContent`, `generateMarkdownContent`,
      `saveTranscription`) now default `syntheticDisclosure = true`.
      Callers must explicitly opt out rather than opt in.
      Files: `lib/utils/file_utils.dart`

### 13.3 Remaining compliance roadmap

#### HIGH priority

- [x] **f. Update engine version string.** `crispasr_engine.dart`
      updated from `'0.8.7'` to `'0.8.12'`.
      Files: `lib/engines/crispasr_engine.dart`

- [x] **g. C2PA signing for MP3 exports.** Re-verified 2026-08-01:
      **not applicable**, MP3 is an *input* format only (decoded for
      transcription) — there is no MP3 export path, hence no unmarked
      MP3 output. The ID3v2 `AI_GENERATED` helper exists and
      `CrispasrC2pa.sign` already accepts `'audio/mpeg'`, so the pieces
      are in place if export is ever added. That is also the point to
      revisit fail-closed marking (§15.8), since a container that cannot
      carry a manifest leaves the watermark as the only mark.
      Documented in `docs/AI_ACT_RISK.md` §7.4.

- [x] **h. Server voice-clone consent gate.** Server TTS endpoint
      returns 403 when `voice` / `voice_file` is present but no
      `disclaimer_override_attestation` provided. Error message
      cites EU AI Act Art. 50(4) and GDPR Art. 9.
      Files: `lib/services/server_service.dart`

- [x] **i. Update PRIVACY.md for biometric data.** Added §5 covering
      voice embeddings, GDPR Art. 9(2)(a) legal basis, on-device
      guarantee, rights (erasure/portability/withdrawal), and voice
      cloning disclosures.
      Files: `PRIVACY.md`

#### MEDIUM priority

- [x] **j. Risk classification document.** Created `docs/AI_ACT_RISK.md`
      documenting CrisperWeaver's self-assessment under Annex III:
      - Speaker ID = biometric categorization (Annex III, 1(a)) —
        high-risk but exempt from most requirements because it is
        on-device-only, no remote biometric identification, no
        public-space deployment.
      - Voice cloning TTS = synthetic media generation — subject to
        Art. 50(4) deepfake disclosure (implemented).
      - ASR/OCR = general-purpose, not high-risk.
      - Explicit Art. 5 compliance statement: CrisperWeaver does NOT
        perform real-time remote biometric identification in publicly
        accessible spaces.

- [x] **k. Data Protection Impact Assessment (DPIA).** Created
      `docs/DPIA.md` covering processing description, necessity,
      proportionality, risk assessment (6 risks with likelihood/
      severity/mitigations), technical + organizational measures.
      Conclusion: no DPA consultation needed (Art. 36) — residual
      risk is not high given on-device-only processing.

- [x] **l. Annex IV technical documentation.** Created
      `docs/AI_ACT_TECHNICAL.md` structured per Annex IV: system
      overview, architecture diagram, design specifications, dev
      methodology, testing (1164 tests), data governance, risk
      management (cross-refs AI_ACT_RISK.md + DPIA.md), post-market
      monitoring, instructions for use (Art. 13).

- [x] **m. C2PA verification in transcription screen.** Enhanced
      "Verify Watermark" to distinguish COSE-signed JUMBF manifests
      from unsigned JSON-LD. `_hasSignedC2pa()` detects JUMBF box
      structure in the RIFF chunk. Full COSE signature verification
      blocked on C ABI function not yet exposed in CrispASR.
      Files: `lib/screens/transcription_screen.dart`

#### LOWER priority

- [x] **n. Anti-impersonation policy.** Created `ACCEPTABLE_USE.md`
      v1.0: consent rules for cloning and voice conversion (fame is not
      consent; consent to be recorded is not consent to be cloned;
      consent that cannot be refused is absent), speaker-ID limits,
      the deployer's Art. 50 disclosure duties, and an explicit
      statement that the beep-override attestation exists for documented
      decisions and is **not** a route to an undisclosed deepfake. Also
      states the two marking limits plainly (metadata strips on
      re-encode; sub-100 ms and silent audio cannot be watermarked).
      Deliberately not framed as a ToS — AGPL-3.0 freedoms cannot be
      conditioned on it, so it states the terms under which the project
      supports use and puts the deployer on notice. Linked from README.
      Files: `ACCEPTABLE_USE.md`, `README.md`

- [x] **o. Third-party abuse reporting.** The recipient of a clip is
      the likeliest person to spot misuse and has no idea what produced
      it, so the channel is embedded **in the C2PA manifest of every
      generated file** (`crisperweaver.abuse-reporting` assertion:
      policy URL, reporting URL, plain-language note) and travels with
      the audio. Backed by a GitHub issue template that is honest about
      the limits — offline software with no accounts or kill switch can
      confirm a watermark and harden marking, but cannot identify who
      generated a file or take content down; urgent harm is redirected
      to law enforcement and national DPAs.
      Files: `lib/services/content_provenance_service.dart`,
      `.github/ISSUE_TEMPLATE/abuse-report.md`, `README.md`

- [x] **p. Music/OMR engine Art. 50 marking.** OCR output disclosure
      landed in §15.2h. Investigating the OMR half surfaced a live bug:
      the 5 OMR models catalogued in §14.3i were **unreachable** —
      `isOcrModelFilename` matches only the six text-OCR prefixes, and
      `smt-grandstaff` / `tromr` / `flova` / `transcoda` match none, so
      `availableModels()` never listed them. They could be downloaded
      but never run. Added the OMR prefixes (CrispEmbed auto-detects the
      architecture, so they dispatch through the same `CrispEmbedOcr`
      path) and a music-specific disclosure — OMR emits symbolic
      notation, where a misread is a wrong pitch rather than a typo.
      Files: `lib/services/ocr_service.dart`,
      `lib/widgets/transcription_output_widget.dart`

- [x] **q. Automated compliance regression tests.** Extended from 14
      to 53 tests: added C2PA manifest build/inject/extract round-trip,
      heuristic AI detection, disclosure-default-true assertions,
      privacy constant integrity. Fixed C2PA extract null-padding bug.
      Updated 3 existing test files for syntheticDisclosure default
      change. Full suite: 1164 pass, 99 skip, 0 fail.

---

## 14. CrispASR 0.8.12 + CrispEmbed 0.15.1 dependency update (July 2026)

Gap analysis performed 2026-07-16. CrisperWeaver currently uses CrispASR
0.8.8 and CrispEmbed 0.14.0; upstream is at 0.8.12 and 0.15.1.

### 14.1 Must-do (correctness / version sync)

- [x] **a. Pull latest CrispASR and CrispEmbed main, `flutter pub get`.**
      Pulled CrispASR c6aae00d (0.8.12), CrispEmbed 5abc4de (0.15.1),
      cloned glint (new dep from upstream). `flutter pub get` + analyze
      clean.

- [x] **b. Update engine version string** — done in §13.3f (0.8.12).

- [x] **c. Verify Parakeet `--chunk-seconds` C-ABI compatibility.**
      No breaking change: `transcribe()` is unchanged; `chunk_seconds`
      is only on the new `transcribeChunked(chunkSeconds:)` method.

### 14.2 CrispASR new features to surface

- [x] **d. Parakeet chunk-seconds setting.** Added `chunkSeconds`
      field to `AdvancedOptions` + slider (0–120s, 0 = default).
      Wired through engine → `transcribeChunked(chunkSeconds:)` and
      worker pool → worker isolate. Localized EN/DE/ZH.

- [x] **e. OmniVoice TTS-steps quality/speed slider.** Already fully
      wired in §11.3: `ttsSteps` field, `setTtsSteps` FFI, slider in
      synthesize screen. OmniVoice benefits automatically.

- [x] **f. OmniVoice GPU codec decode toggle.** Not yet exposed in
      C API (`OMNIVOICE_CODEC_GPU` is env-var-only). Tracked upstream.

- [x] **g. FASTCONV performance wins.** No Dart changes needed — the
      convolution kernel baking is engine-side. Users get faster TTS
      for free with the updated native lib. Automatic with §14.1a.

### 14.3 CrispEmbed new features to surface

- [x] **h. Architecture-based GGUF hparam loading.** Engine-side
      improvement, automatic with §14.1a.

- [x] **i. Music/OMR engines in model picker.** Added `ModelKind.omr`
      enum + 5 catalog entries: SMT++ Grandstaff (24 MB), SMT++ Full-Page
      (16 MB), Polyphonic-TrOMR (31 MB), Flova (88 MB Q4_K), Transcoda-59M
      (120 MB). All use `backend: 'ocr'` (CrispEmbed auto-detects arch).
      Files: `lib/services/model_catalog.dart`

- [x] **j. DeepSeek-OCR-2 + Unlimited-OCR memory optimizations.**
      Engine-side, automatic with §14.1a.

- [x] **k. Persistent device-KV decode speedup.** Engine-side,
      automatic with §14.1a.

- [x] **l. Sparse/ColBERT/multi-vector in semantic search.** When
      `embedder.hasColbert`, `_embeddingSearch` now uses
      `encodeMultivec` + `colbertScore` (MaxSim late-interaction) for
      higher precision. Falls back to dense cosine per-segment. Added
      `_flattenMultivec` + `_denseScore` helpers.
      Files: `lib/services/semantic_search_service.dart`

### 14.4 CI updates

- [x] **m. Pin CrispASR/CrispEmbed/glint refs to tags.** Pinned across
      all three workflows: `CRISPASR_REF: v0.8.25`,
      `CRISPEMBED_REF: v0.16.1`, `GLINT_REF: glint_audio-v0.11.0`.
      §15.7 turned this from a nice-to-have into a real one — a `main`
      pin had put the app 13 backends behind the engine and broke the
      build outright.

      Two traps found while doing it, both of which would have broken CI
      worse than the drift did:
      - **glint uses a per-package tag scheme.** The bare `vX.Y.Z` tags
        are a stale legacy series — `v0.9.0` still carries Dart package
        `0.1.0`, five minor versions behind. The correct tag is
        `glint_audio-v0.11.0`.
      - **Tag existence must be checked against the remote**, not the
        local clone. Verified all three with `git ls-remote`, and that
        each tag's Dart package version matches what the app builds
        against locally.

      Caveat recorded in the workflow comments: pinning the ref bounds
      the *source*, not the artefact. §15.7's `gigaam` appeared while
      CrispASR's git HEAD was unchanged, because a worker rebuilt the
      dylib — so `backend_dispatch_test` remains the drift canary.
      Files: `.github/workflows/{ci,release,deploy-web}.yml`

---

## 15. EU AI Act audit remediation (August 2026)

Full audit performed 2026-08-01 against Regulation (EU) 2024/1689, after
the §13 compliance sweep. The §13 architecture is sound; this section
fixes the gaps between that design and the shipped code, plus stale
legal analysis in `docs/`.

**Regulatory timing that drives priority:** Art. 50 transparency applies
from **2 August 2026** and was explicitly *excluded* from the Digital
Omnibus deferral. Annex III high-risk slipped to **2 December 2027**, so
the speaker-ID high-risk analysis is far less urgent than §13 assumed.
A grace period to **2 December 2026** covers the Art. 50(2)
machine-readable marking for systems already on market (v0.9.5 qualifies);
Art. 50(4) deepfake disclosure has no such runway.

### 15.1 Blocking — build + CI are broken

- [x] **a. Adopt CrispASR's consent-gated SpeakerDB API.** Upstream
      `origin/main` made `CrispasrSpeakerDB` a **closed-roster,
      consent-gated** construct: `{required String expectedNames,
      required bool consentAttested}`, throwing without consent.
      Matching is now a *claimed-participant confirmation*, never an
      open 1:N search — which is what keeps it biometric **verification**
      rather than **identification** (materially better Annex III
      posture). Five call sites don't compile; `flutter analyze` reports
      10 errors and `test/synthetic_compliance_test.dart` cannot load, so
      the entire compliance regression suite is silently not running.
      Files: `lib/services/speaker_id_service.dart:280`,
      `bin/crisperweaver.dart:655`,
      `test/speaker_id_live_test.dart:119,126,159`

      Design: build `expectedNames` from enrolled speakers that have a
      consent record on disk. Speakers lacking one are excluded from the
      roster and logged — no consent, no biometric matching. Handles are
      closed after enroll/delete so the next open re-derives the roster.

- [x] **b. Fix `listSpeakers()` extension filter.** It lists every file
      in the speakers dir, so `Alice.consent.json` surfaces as a phantom
      speaker `Alice.consent`. Filter to `.spk`. Blocks 15.1a (the roster
      is derived from this list).
      Files: `lib/services/speaker_id_service.dart:107`

### 15.2 Art. 50 — transparency defects

- [x] **c. Beep disclaimer never fires in the GUI (HIGH).**
      `synthesize_screen.dart:588` and `:724` call `tts.writeWav(audio)`
      with no `voiceRefPath`, so `isVoiceClone` is always false on the
      app's primary path: no Art. 50(4) beep, no `[CONSENT]` audit entry.
      The voice reaches `prepare(voiceName:)` but is never threaded to
      `writeWav`. Only the server API path (`server_service.dart:529`)
      passes it.
      Files: `lib/screens/synthesize_screen.dart`

- [x] **d. UI asserts a disclosure that did not happen (HIGH).**
      `synthesize_screen.dart:854` renders `"...beep disclaimer + ..."`
      whenever `selectedVoice != null`. Given 15.2c that claim is false —
      a user relying on it ships undisclosed deepfake audio. The card
      must reflect what was actually embedded, not what was intended.
      Files: `lib/screens/synthesize_screen.dart`

- [x] **e. Post-embed watermark verification is broken on the primary
      path.** `tts_service.dart:737` verifies with
      `AudioWatermarkService.detectWatermark()`, which is an **LSB-only**
      detector. On the native path the LSB mark is never embedded, so it
      always returns null → a permanent false "verification failed"
      warning, and the Art. 50(2) marking is in truth never verified.
      Use `SpreadSpectrumWatermark.detect()` for that path.
      Files: `lib/services/tts_service.dart`

- [x] **f. Watermark presence is inferred from symbol availability.**
      `nativeWatermarked = CrispasrWatermark.isAvailable()`
      (`tts_service.dart:699`) tests whether the *symbol* exists, not
      whether embedding occurred. If the C-side auto-embed is ever
      conditional, the Dart fallback is skipped and output ships
      unmarked. Merge with 15.2e: verify with the correct detector, and
      apply the Dart fallback when verification fails rather than when a
      symbol is missing.
      Files: `lib/services/tts_service.dart`

- [x] **g. Speech-to-speech has no disclosure or consent gate.** S2S is
      voice conversion — squarely Art. 50(4) deepfake territory — yet
      `server_service.dart:1035` and `synthesize_screen.dart:724` pass no
      `voiceRefPath`, and `/v1/audio/s2s` has no consent gate unlike
      `/v1/audio/speech`. Add an explicit `voiceConverted` flag to
      `writeWav` so the beep does not depend on a reference-file path.
      Files: `lib/services/tts_service.dart`,
      `lib/services/server_service.dart`,
      `lib/screens/synthesize_screen.dart`

- [x] **h. OCR output carries no AI marking.** Was §13.3p, still open.
      Art. 50(2) marking arguably reaches generated text.
      Files: `lib/services/ocr_service.dart`

### 15.3 GDPR — biometric consent defects

- [x] **i. Second enrollment path bypasses consent entirely.**
      `transcription_output_widget.dart:1679` calls `svc.enroll()` with no
      consent dialog and no `saveConsent()`. Only
      `speaker_management_screen.dart:333` gates properly. Art. 9(2)(a)
      basis is therefore missing on that path, and a later
      `deleteSpeaker()` finds no consent record to erase.
      Files: `lib/widgets/transcription_output_widget.dart`

- [x] **j. Consent dialog addresses the wrong data subject.**
      `speakerConsentBody` reads *"you give your explicit consent to the
      processing of this biometric data"* — but when enrolling a meeting
      participant the data subject is a **third party**, not the user.
      Consent under Art. 9(2)(a) must come from the data subject. The
      voice-clone wizard already models this correctly (*"I have explicit
      consent from the voice owner"*); the speaker dialog must match, and
      this is exactly what upstream's `consentAttested` expects.
      Files: `lib/l10n/app_{en,de,zh}.arb`,
      `lib/screens/speaker_management_screen.dart`

### 15.4 Legal analysis gaps in `docs/`

- [x] **k. Art. 6(3) exemption is incompletely stated.**
      `AI_ACT_RISK.md` §3 claims the derogation but omits that it still
      obliges the provider to document the assessment **and register in
      the EU database (Art. 49(2))**, and that the derogation is void
      where the system performs profiling. Also record that the
      closed-roster API from 15.1a makes this **verification**, which is
      carved out of Annex III 1(a) in the first place — a stronger
      argument than the Art. 6(3) one currently made.

- [x] **l. Art. 2(12) open-source exemption unmentioned.** Relevant for
      AGPL-3.0, and the operative point is that it does **not** exempt
      Art. 50.

- [x] **m. Provider vs deployer roles are conflated.** Art. 50(1)/(2)
      bind CrisperWeaver as provider; **50(3)/(4) bind the deployer** —
      the end user. Docs imply the app discharges duties it cannot.

- [x] **n. Art. 4 (AI literacy)** — in force since 2 Feb 2025, entirely
      unaddressed.

- [x] **o. Refresh timelines for the Digital Omnibus** across
      `AI_ACT_RISK.md`, `AI_ACT_TECHNICAL.md`, `DPIA.md`. Note the
      Code of Practice on Transparency of AI-generated Content
      (signatories can demonstrate compliance and get enforcement
      predictability; not an Art. 40 presumption of conformity).

### 15.5 Verification

- [x] **p. Regression tests** for: beep presence on cloned + converted
      output, watermark verification using the correct detector, roster
      excludes non-consented speakers, `listSpeakers` extension filter,
      export disclosure defaults. Then `flutter analyze` + full
      `flutter test` clean — capturing the *real* exit code, not a
      pipeline tail's.

### 15.6 Outcome (2026-08-01)

All 16 items above are implemented. `flutter analyze`: **0 errors**
(down from 10). Compliance suite: **62 pass** (up from 53 — and from
*not loading at all*, which was the point of 15.1a). Full suite:
**1181 pass, 103 skip, 2 fail**.

Both remaining failures are pre-existing and unrelated to this section
— verified by stashing these changes and re-running against a clean
tree, where `backend_dispatch_test` does not even compile:

- **`backend_dispatch_test` — catalogue drift.** The local CrispASR is
  at v0.8.25 while this repo targets 0.8.12, and the newer engine
  exposes 12 backends with no `ModelDefinition`: `beat-this`,
  `btc-chords`, `crepe`, `htdemucs`, `mel-band-roformer`, `miotts`,
  `moss-tts-local`, `piano-transcription`, `rvc-svc`, `sidon`,
  `tabcnn`, `voxcpm2-vae`. This was masked until now by the compile
  error. **CI is affected**: `CRISPASR_REF: main` means CI resolves the
  same drifting engine. Fixing it means either cataloguing the 12
  backends or adding them to the documented `engineOnly` set — and it
  is the concrete argument for §14.4m (pin to release tags).

- **`s12_integration_live_test`** — the §12.5 TADA group hand-rolled a
  `markTestSkipped` instead of using the shared
  `CrispModels.skipReason()` gate, so it ran on a plain `flutter test`
  whenever the models happened to be on disk — precisely what
  `CrispModels.enabled` exists to prevent (see its docstring). It also
  called `decodeAudioFile` and `CrispASR()` **without `libPath:`**, so
  they fell back to bare-name `libcrispasr.dylib` resolution and threw
  even though the guard above had already proved a dylib existed.
  **Fixed** (beyond the audit scope, but it was the sole red test in the
  pre-push gate, and a permanently-red gate is a gate nobody reads):
  both calls now pass the resolved `lib`, and the group uses
  `skipReason(models: ['canary_aligner', 'whisper_tiny'])` like its
  siblings.

Neither blocks the Art. 50 deadline. Both are tracked separately.

### 15.7 Catalogue drift resolved (2026-08-01)

CrispASR 0.8.25 exposes 12 backends the catalogue didn't know about.
Resolved by scope, not by bulk-cataloguing:

- **Catalogued** (real published GGUFs, sizes verified against the HF
  tree API — not estimated): `miotts` (`cstr/miotts-0.6b-GGUF`, q4_k +
  q8_0, ja/en) and `moss-tts-local` (`cstr/moss-tts-local-v1.5-GGUF`,
  q4_k + q8_0 + the required 2.1 GB codec companion, multilingual).
  Both are TTS — the app's core surface, with UI that can already run
  them.
- **`engineOnly`** for the other 10, each with a documented reason:
  `voxcpm2-vae` is an internal VoxCPM2 component; `sidon` (speech
  restoration) and `rvc-svc` (voice conversion) are unreachable because
  the app's denoise path is RNNoise and its S2S path is an explicit
  `{lfm2-audio, mini-omni2}` allowlist; the 7 music backends
  (`beat-this`, `btc-chords`, `crepe`, `htdemucs`,
  `mel-band-roformer`, `piano-transcription`, `tabcnn`) have no
  `ModelKind` and no screen that consumes their output.

Plus **`gigaam`** (`cstr/gigaam-v3-GGUF`), which surfaced only on a
later run — the shared CrispASR clone gets rebuilt by parallel workers,
so the exposed-backend set moves even when its git HEAD does not.
Catalogued as ASR (ru/en): the `e2e-rnnt` q8_0/q4_k and `e2e-ctc` q8_0
revisions, which carry punctuation + casing + ITN in the SentencePiece
vocab. The bare `ctc`/`rnnt` revisions are left to repo discovery —
CrispASR suppresses auto-punctuation for them anyway, since the
auto-enabled FireRedPunc is a CN/EN model that injects full-width CJK
punctuation into Russian.

Cataloguing a model the app cannot run would put a multi-GB download
behind a button that does nothing — so scope, not availability, is the
right axis here. **Compliance note left in the test:** if `rvc-svc` is
ever surfaced it must route through `writeWav(voiceConverted: true)`
for the Art. 50(4) beep.

### 15.8 Marking robustness (2026-08-01)

Prompted by a cross-project comparison (CrispTTS / CrispASR /
Susurrus / CrisperWeaver). Two of its claims about CrisperWeaver were
**out of date** — the primary mark is spread-spectrum, not LSB (LSB is
a back-compat extra on the fallback path only), and opt-out has
required an attestation since §13.2b. One was **correct and material**:
`AudioWatermarkService.embedWatermark` returns its input unchanged
below 4,608 samples (`audio_watermark_service.dart:40`) — a silent
no-op.

Measured the detector rather than reasoning about it:

| Input | Clean | Watermarked |
|---|---|---|
| 20 ms (< 1 FFT frame) | 0.000 | **0.000** |
| 100 ms | 0.469 | 0.906 |
| 250 ms – 2 s | 0.406–0.500 | 0.781–0.875 |
| digital silence, 2 s | 0.000 | **0.000** |
| 0.01x amplitude, 2 s | — | 0.781 |

So the 0.65 floor sits cleanly in the gap (clean tops out at 0.50,
marked bottoms out at 0.78) and detection is level-invariant — quiet
output is not falsely rejected. Sub-100 ms and silent output genuinely
cannot carry a spectral watermark.

Changes:

- [x] **q. Marking outcome is now a value, not a log line.**
      `MarkingStatus {watermarkVerified, watermarkConfidence,
      c2paSigned}` with `robustMarkPresent`, exposed as
      `TtsService.lastMarking`. Verification failure escalated from
      `w` to `e`, plus a `[MARKING]` line when no robust mark landed
      (mirrors the `[CONSENT]` audit convention).
- [x] **r. The provenance card reports reality.** When the last output
      could not be watermarked the card switches to an error style and
      says so, instead of asserting a mark that isn't there — the same
      class of bug as §15.2d.
- [x] **s. Measured floor locked into tests.** Clean/marked gap
      straddling 0.65, level invariance, and the two known-unmarkable
      cases. Compliance suite: 53 → 66.

**Deliberately NOT adopted: fail-closed (refusing to write unmarkable
output).** CrisperWeaver's WAV path always carries a C2PA manifest plus
LIST/INFO metadata, so output is never *un*marked — only marked by
something a re-encode strips. Refusing to save a user's synthesis
because it is 80 ms long trades a real usability failure for a
marginal compliance gain. Escalate to a hard refusal only if MP3
export lands (§13.3g), where a container genuinely can carry no
manifest — that is the case CrispASR's watermark floor exists for.

### 15.9 Remaining open items closed (2026-08-01)

Everything in `docs/AI_ACT_RISK.md` §7 and the leftover §13.3 / §14.4
items is now resolved — see §13.3g/n/o/p and §14.4m above, and §7.1–7.4
of the risk document.

Two of the five were **not** the paperwork exercises they looked like:

- **§13.3p (OMR marking)** was really a dead-feature report. The five
  OMR models catalogued in §14.3i could be downloaded but never run,
  because `isOcrModelFilename` only matched the six text-OCR prefixes.
  Marking output that could not be produced would have been theatre;
  the fix was to make the engines reachable, then disclose.

- **§14.4m (pin to tags)** nearly broke CI in a new way. glint's bare
  `vX.Y.Z` tags are a stale legacy series — `v0.9.0` still carries Dart
  package `0.1.0` — so the obvious pin would have shipped a package five
  minor versions behind. Correct tag: `glint_audio-v0.11.0`. Tag
  existence and each tag's package version were verified against the
  **remote**, since a local-only tag would fail in CI and nowhere else.

Two items resolved as **not applicable** rather than done, with the
reasoning and re-open triggers recorded rather than the conclusion
alone (`docs/AI_ACT_RISK.md` §7.3, §7.4): Art. 49(2) registration does
not bite because the closed-roster design keeps the subsystem outside
Annex III entirely, and MP3 C2PA signing has no subject because MP3 is
an input-only format here.

One item is **technically complete but organisationally open**: the
Code of Practice on Transparency of AI-generated Content (final
10 June 2026) is already satisfied on every technical limb, and on
robustness arguably exceeded — but *signing* it is an act only the
maintainer can perform: complete the Signatory Form and email it to
`CNECT-AIOFFICE-CODE-OF-PRACTICE-TRANSPARENCY@ec.europa.eu`, signed by
someone with authority to bind the provider. Signing is open at any
time; the initial-signatories list closed 22 July 2026.

**Correction to an earlier wording here:** adherence does *not* confer a
"presumption of conformity" — that is the Art. 40 concept for harmonised
standards. What signatories get is the ability to *demonstrate*
compliance, with enforcement focused on monitoring adherence rather than
individual assessment by each national market surveillance authority.

Whether to sign is a judgement call for the maintainer, not a technical
gap. It binds the project to the code's measures on an ongoing basis —
diverging later is a worse position than never signing — and the benefit
mainly accrues to providers who expect to be assessed. Nothing in the
code blocks it either way; Art. 50 itself is met regardless.

**Decided 2026-08-02: not signing, for now.** See §16.7 — the item is
closed as a decision rather than left hanging as an open action.

### 15.10 Speaker-DB verification audit + empty-roster bug (2026-08-01)

Prompted by a direct challenge — *does the speaker DB do 1:N biometric
identification, and should it be removed?* Answered by reading the C
implementation rather than the Dart doc comment.

**It cannot do open 1:N identification.** Three enforced gates:

- `crispasr_speaker_db_load(dir)` — the old 1:N entry point — was
  **removed** (CrispASR #266). It returns `nullptr` and prints
  "open 1:N identification is unsupported", kept as a symbol only so
  old callers fail loudly rather than at link time.
- `crispasr_speaker_db_open` returns `nullptr` unless given **both** a
  non-empty roster and `consent_attested`.
- `speaker_db_retain` **physically deletes** every profile not on the
  roster (`db->speakers = std::move(kept)`) before any match;
  `speaker_db_match` iterates only the survivors.

So the operation is "which of the participants I claim are present is
this segment?" — 1:N *within a declared roster*, never against the whole
database. That is biometric **verification**, which Annex III 1(a)
expressly excludes, and it is why `docs/AI_ACT_RISK.md` §3.1 leads with
that rather than the weaker Art. 6(3) derogation. **No reason to remove
the feature** — the design already survived this scrutiny upstream, and
§15.1a narrowed it further by deriving the roster from consent records.

**The challenge did expose a real bug in §15.1a's own code**, though:

- [x] **t. Empty roster produced a silently dead DB.** `_ensureOpen`
      passed `expectedNames: roster.join(',')`, empty whenever no
      enrolled speaker has a consent record — **including every fresh
      install**. Upstream refuses that and returns a null handle, which
      the Dart wrapper wrapped in a live-looking object while the log
      announced "opened SpeakerEmbedder + SpeakerDB". Not a crash (the C
      side is null-safe), which is worse: matching would silently never
      work and the logs would say it was fine. Now the DB is simply not
      opened when the roster is empty, and `matchSegment` short-circuits
      to a clean no-match.

- [x] **u. `_db == null` can no longer double as "not yet opened".**
      It is a valid steady state, so the idempotence guard would have
      reopened the embedder on every call. Added `_openAttempted`.

- [x] **v. `enroll()` would have thrown on the first speaker.** `_db` is
      null exactly when the roster is empty, i.e. when enrolling speaker
      #1. Enrollment writes through `dirPath` and does not need the
      loaded profile set, so it now opens a throwaway handle rostered on
      the name being enrolled.

- [x] **w. Live test passed an empty roster.** `expectedNames: ''` would
      fail against a real dylib; it only passed because the test skips
      without `CRISPASR_LIB`.

**Lesson worth keeping:** §15.1a was verified by `flutter analyze` +
1191 green tests, and every one of these bugs sat underneath that,
because the failing paths are all gated behind a dylib the default suite
skips. Compiling is not evidence that an FFI boundary works.

---

## 16. EU AI Act audit round 2 (2026-08-02)

Second full audit, run the day Art. 50 became enforceable. §15 fixed the
gaps between the §13 design and the shipped audio pipeline; this round
looked at everything §15 did **not** treat as in scope, and that turned
out to be where the remaining gaps were.

**The pattern in one line:** the compliance work had been read as an
*audio* problem solved on the *Flutter* path. Three of the four code
findings are the same mistake from different angles — a generating
surface that no one thought of as a generating surface.

### 16.1 Art. 50(2) — text was never marked

- [x] **a. LLM output left the app bare.** `summarize_dialog.dart:129`
      copied the raw model markdown to the clipboard and
      `translate_screen.dart` copied the translation, neither disclosed
      — while `AI_ACT_RISK.md` §5.2 recorded text marking as **Done** on
      the strength of OCR and transcript exports alone. The project had
      already articulated the right rule at
      `transcription_output_widget.dart:1110` ("once the text leaves the
      app the surrounding UI no longer supplies context"); it just was
      not applied to the LLM features.
      New: `lib/utils/ai_text_disclosure.dart`, attached on screen and
      on copy in both surfaces.

- [x] **b. `/v1/translations` was the only generating endpoint with no
      marking.** The three audio endpoints all set
      `x-content-ai-generated: true`; the text one set nothing. Now sets
      the header plus a `_disclosure` field, matching the `_disclosure`
      key the JSON transcript export already uses.

      **Scope call, recorded deliberately:** cleanup is *not* marked.
      Art. 50(2) carves out systems performing "an assistive function for
      standard editing" that do not substantially alter the input or its
      semantics, which is what the deterministic toggles do. Checked
      rather than assumed for the *LLM* cleanup pass too: its system
      prompt pins it to "preserve the speaker's words, meaning, and
      language", "never paraphrase, expand, or summarise", "never add
      information not present in the input" — inside the carve-out. That
      makes the prompt a compliance boundary: loosen it toward rewriting
      and the output needs marking. Recorded in `AI_ACT_RISK.md` §2.7 so
      the next person to edit that prompt knows what it is load-bearing
      for. Marking cleanup anyway would dilute the signal on output that
      genuinely is generated.

### 16.2 Art. 50(4) + GDPR Art. 9 — parallel entry points

- [x] **c. The voice-bake screen had no consent gate.**
      `voice_bake_screen.dart` (routed at `main.dart:486`, reachable
      from a button at `synthesize_screen.dart:803`) baked a voicepack
      from any WAV with no rights attestation, while the voice-clone
      wizard next to it gated properly. This is §15.3i's finding
      exactly, one release later, applied to cloning instead of
      enrolment. Gate added, mirroring the wizard, with a `[CONSENT]`
      audit line and the attestation reset on every new WAV pick.

      Practical exposure was narrow — the screen shells out to Python
      plus a CrispASR checkout, so it does not run on most installs.
      The gate gap was real regardless: "hard to reach" is not a
      control.

- [x] **d. The CLI bypassed the marking pipeline entirely.**
      `bin/crisperweaver.dart` wrote bare 44-byte WAVs from **both**
      `synthesize` and `s2s`: no Art. 50(4) beep even with `--voice`, no
      C2PA manifest, no `LIST`/`INFO` provenance, no post-embed
      verification, no consent gate. Only the C-side auto-embedded
      watermark survived, unverified. `s2s` is voice conversion — the
      case §15.2g fixed on the GUI and server while the CLI kept
      shipping unmarked.

      Fixed by extraction rather than duplication: the WAV+provenance
      encoder moved to `lib/utils/marked_wav.dart` (pure Dart, since a
      `dart run` entrypoint has no Flutter bindings) and both
      `TtsService._floatPcmToWavBytes` and the new CLI
      `_writeMarkedWav` delegate to it. Two implementations of the same
      marking is how they drift; one is how they cannot.

      The CLI now also **refuses** to clone without `--i-have-rights`
      (exit 2) rather than warning — a headless flag that only prints a
      warning is a flag nobody reads — and takes
      `--disclaimer-override` for the same attestation-logged beep
      suppression the server API has.

### 16.3 Documentation that no longer matched the software

- [x] **e. "No data is sent to external servers" was false.** The
      first-use Art. 50(1) notice said it in all three locales, and
      `AI_ACT_RISK.md` §1 repeated it — untrue once BYOK cloud cleanup
      or summarisation is on, which posts transcript text to whatever
      OpenAI-compatible endpoint the user configures. The notice also
      omitted LLM text generation from its subsystem list. Both
      corrected; the notice now distinguishes the on-device default
      from the opt-in network features and states that speaker profiles
      and recordings never leave the device under any setting.

- [x] **f. `PRIVACY.md` never mentioned the cloud LLM at all** — it
      claimed "the only network traffic is model downloads and optional
      cloud transcription". New §3.3 documents what is sent, to whom,
      that the receiving provider's policy governs it, and that a
      transcript can carry personal data about people who are not the
      user. The in-app settings help text had been honest about this all
      along; the policy simply had not caught up.

- [x] **g. The LLM subsystem had no risk classification.**
      `AI_ACT_RISK.md` §2 enumerated six subsystems and omitted the only
      text-*generating* one — and the only one whose data can leave the
      device. Added as §2.7.

- [x] **h. Annex IV drift.** §1.3 still said v0.9.1 / CrispASR 0.8.12
      (actual: v0.9.6, engines pinned to v0.8.25 / v0.16.1 / v0.11.0 per
      §14.4m); §3.2 and §6.3 quoted test counts that had moved three
      times; §1.4 omitted the LLM endpoint and the localhost server /
      Wyoming interfaces; and §8's history table had **no row for the
      2026-08-01 revision** even though the header claimed one. Fixed,
      with the missing row recorded retrospectively rather than quietly
      backfilled. Hard-coded counts replaced by pointers — a number in
      prose goes stale faster than the suite does.

- [x] **i. GPAI exposure assessed** (`AI_ACT_RISK.md` §7.5). The project
      republishes quantised GGUFs under `cstr/*`, and making a model
      available on the Union market can bring you within the definition
      of its provider. Assessment: Art. 53(2) exempts free/open-source
      models from 53(1)(a)-(b) absent systemic risk, which these 0.5–2 B
      speech models are nowhere near; the copyright-policy and
      training-data-summary limbs survive, but the stronger argument is
      that format conversion is not model provision at all. Cheap
      insurance recorded rather than a conclusion asserted.

### 16.4 Verification

- [x] **j. Regression tests.** 12 added to
      `test/synthetic_compliance_test.dart`: text-disclosure wording and
      shape (including that summary and translation wordings are
      distinct, that empty input discloses nothing, and that the model
      output survives verbatim after the disclosure), plus the shared
      `MarkedWav` contract — RIFF validity with the appended chunk,
      provenance field presence, `LIST` positioned after `data`, and
      independence from the watermark layer.
      Compliance suite: **71 → 83**.

### 16.5 What this audit did *not* find

Recorded because a clean result is evidence too, and because re-deriving
it next time is wasted work:

- The Art. 50(4) beep is genuinely mandatory across GUI TTS, S2S, and
  both server endpoints, with attestation-gated suppression that is
  logged. §15.2c–g held up under re-reading.
- Watermark verification uses the correct spread-spectrum detector, and
  the measured 0.65 floor from §15.8 is locked into tests.
- The speaker DB is closed-roster and consent-derived, and the C side
  physically drops off-roster profiles before matching. §15.10's
  verification-not-identification analysis stands.
- `HfSpaceTtsService` looks like an unmarked cloud-TTS path but is dead
  code — referenced only by its own tests, wired into no screen. Worth
  knowing before someone "fixes" it into the UI, where it *would* need
  the marking pipeline.

### 16.6 The standing lesson

§15.10 ended with "compiling is not evidence that an FFI boundary
works". This round's version: **a compliance control is only as strong
as its least-guarded entry point.** Every code finding here was a second
door into an operation whose front door was properly gated — a second
clipboard path, a second cloning screen, a second synthesis entrypoint.
The useful review question for any new surface is not "does this have a
gate" but "how many ways in are there, and does each one pass through
it".

### 16.7 Code of Practice — decided not to sign (2026-08-02)

The last item left open by §15.9 is now closed, as a decision rather than
an action. **CrisperWeaver will not sign the Code of Practice on
Transparency of AI-generated Content for now.**

The reason is the one thing about this project that is not going to
settle soon: the generating surface keeps moving. Adherence is an
ongoing commitment across whatever the software becomes, not an
attestation about today's build — and the two audits in §15 and §16
between them pulled an entire LLM text subsystem into the marking scope,
brought the CLI inside it, and closed consent gates on screens that did
not exist a few releases earlier. Binding a moving target to a fixed set
of measures buys the worse of both positions: diverging after signing
reads as breaking a commitment, where a non-signatory is simply assessed
on the merits.

The upside would have been the ability to *demonstrate* compliance and
have enforcement focus on adherence monitoring rather than individual
assessment by each national authority. That mainly matters to providers
who expect to be assessed — not an AGPL project with no accounts, no
servers, and no commercial deployment.

What this costs, stated plainly: the technical measures have to stand on
their own rather than by reference to the Code. They do — every limb is
met and robustness is arguably exceeded (§15.8) — and **Art. 50 binds
and is satisfied either way**. The Code is a route to showing
compliance, not a source of the obligation.

Revisit if the generating surface stabilises, if the project gains a
commercial or institutional deployment, or if a market surveillance
authority makes contact. Signing stays open at any time; the
22 July 2026 cutoff affected the initial-signatories listing only.
Recorded in `docs/AI_ACT_RISK.md` §7.2 with the same re-open triggers.
