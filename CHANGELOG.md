# Changelog

Notable user-facing changes per release. Full diff per version on
the [GitHub releases page](https://github.com/CrispStrobe/CrisperWeaver/releases).

## [Unreleased]

### Added — On-device MP3 / AAC-LC / Opus codec (v0.9.1)

Compressed audio encode + decode via the bundled clean-room `libglint`
codec suite — export to MP3/AAC/Opus and decode `.mp3`/`.aac`/`.opus`
on-device, no external ffmpeg. `GlintCodecService` +
`AudioEditService.exportEncoded`; `AudioService` prefers glint before the
ffmpeg/MediaCodec fallbacks. Native `libglint` built + bundled per
platform in release CI. Graceful WAV fallback where absent.

### Added — CrispASR 0.8.10 backend catch-up (v0.9.1)

Cataloged the engine backends the app had fallen behind on:
**MOSS-Diarize** (single-pass ASR + speaker diarization), **MOSS-TTS
v1.5** (voice-cloning TTS), **OmniVoice** (600+ lang TTS), **Irodori-TTS**
(Japanese), **Voxtral-4B-TTS** (non-commercial), **Canary-Qwen 2.5B**,
and completed **Nemotron** streaming ASR. Fixed CosyVoice3-TTS
classification. The `backend_dispatch` catalog↔engine parity guard is
green against the built 0.8.10 dylib.

### Fixed — #30 non-Whisper GGUFs from "Add from HuggingFace repo"

A Cohere ASR GGUF linked via the HF-repo dialog was force-routed to the
whisper pipeline and crashed. The engine now recovers the real backend
from the GGUF architecture metadata at load, no longer hard-rejects when
the dylib reports an empty backend list, and the dialog offers a concrete
backend override. Also fixed the underlying `detectBackendFromGguf` FFI
binding bug (inverted return-code check) that had silently disabled GGUF
backend auto-detection entirely. Verified live against the reporter's
model.

Follow-up (v0.9.1): on Windows the fix surfaced the *real* underlying
failure — `crispasr.dll` couldn't load at all (Windows error 126), which
is why `availableBackends()` had returned `{}`. With
`CRISPASR_OPUS_FETCH=ON` + `BUILD_SHARED_LIBS=ON`, libopus/libogg build as
`opus.dll` / `ogg.dll` that `crispasr.dll` imports (opusfile, for native
`.opus` decode) but the Windows bundler never copied. Now bundled, plus a
`dumpbin`-based guard that fails the build if any non-system DLL
`crispasr.dll` imports is missing from the runner dir.

### Added — iOS App Store signing pipeline (v0.9.1)

API-key-driven signing + archive/export for the release IPA
(`flutter build ipa`, Distribution `.p12` into a build keychain).

### Fixed — .opus file support on Android (#26)

WhatsApp `.opus` audio files (and `.webm` with Opus audio) now decode
natively on Android. The CrispASR Android build was missing
`-DCRISPASR_OPUS_FETCH=ON`, so libopus/opusfile were silently disabled
and the ffmpeg fallback doesn't exist on Android. Fixed in both the
standalone `build-android.sh` and the CI release workflow. Added an
Android `MediaCodec` platform-channel fallback as belt-and-suspenders
for older builds.

### Added — Test coverage, CLI & HTTP-server parity (§9)

**CLI** — a first-class headless CLI over the on-device engine
(`bin/crisperweaver.dart`, run via `dart run crisper_weaver:crisperweaver`):
`backends`, `transcribe` (+`--srt`), `vad`, `lid` (audio/`--text`),
`punctuate`, `translate`, `synthesize` (+`--voice`), `watermark`
(embed/`--detect`).

**HTTP server** — new endpoints toward capability parity with the
GUI/CLI: `POST /v1/audio/vad`, `POST /v1/audio/language` (LID),
`POST /v1/text/punctuate`. Matrix tracked in `docs/PARITY.md`.

**Tests** — live tests covering VAD, language ID, punctuation, forced
alignment, diarization, streaming ASR, five non-Whisper ASR backends,
translation, and watermark detection (each self-skips unless opted in
via `scripts/run_live_tests.sh`), plus pure-Dart unit tests for audio
DSP, fingerprinting, watermark metadata, the CLI, and the server. Shared
model locator: `test/support/crispasr_models.dart`.

### Fixed — VAD was a silent no-op (§9.5)

`VadService` called the legacy `vad()` entrypoint, which fails
("model init failed") for the bundled Silero and whisper-vad models and
SIGABRT'd on dispose (it loaded a non-whisper model as a whisper
context). It now calls the unified `crispasr_vad_slices` dispatcher
directly (`lib/native/vad_native.dart`, web-stubbed) with no whisper
context — speech-span detection works again, regression-tested.

### Added — CrispASR mid-2026 catch-up (§5.26)

**New backends (4):**
- **LFM2-Audio 1.5B** — LiquidAI hybrid ASR + TTS + Speech-to-Speech.
  English (Q5_K ~1.6 GB) + Japanese variant (Q4_K ~1.5 GB). LFM Open License.
- **Mini-Omni2** — Whisper-small + Qwen2-0.5B multimodal: ASR + TTS + S2S
  in one 1 GB model. Needs SNAC 24 kHz codec companion (~80 MB).
- **MOSS-Audio 4B** — Audio understanding: ASR + audio Q&A + scene
  description via Whisper encoder + Qwen3 LLM (~3.8 GB).
- **Parakeet-RNNT 0.6B/1.1B** — Standard RNN-Transducer English ASR,
  complementing the existing TDT variants.

**Hotwords / contextual biasing (§5.26.2):**
- New "Hotwords" text field in Advanced Options — comma-separated words
  or phrases the model should expect in the audio.
- For LLM backends (Voxtral, Qwen3, Granite, etc.): merged into the ask
  prompt as "The following words may appear in the audio: ...".
- For CTC/TDT backends (Parakeet): applied to the Aho-Corasick trie via
  the new `crispasr_session_set_hotwords()` C API.
- Wired through all transcription paths: single-file, batch, pool dispatch.

**Speech-to-Speech mode (§5.26.3):**
- New S2S toggle on the Synthesize screen (visible for LFM2-Audio and
  Mini-Omni2). When enabled, user picks/records audio input instead of
  typing text — the engine transforms audio → audio in a single model pass.
- Full pipeline: audio file picker → decode → S2S via background isolate →
  WAV output → playback.
- New `crispasr_session_speech_to_speech()` C API + Dart FFI binding.

**Free upgrades from latest CrispASR:**
- **Global diarization** (#110) — sherpa/ECAPA runs once on full audio,
  consistent speaker IDs across chunks.
- **Long-form chunking** (#89/#114) — per-backend chunked-encode + dedup.
- **Beam search expansion** (#139) — 18/24 backends now beam-capable.
- **Permissive G2P** (#156) — replaces espeak-ng GPL dep with IPA dicts.

**Baked catalog:** 310 entries (was 300). LFM2-Audio, Mini-Omni2, and all
their quant variants available on cold start without HF probe.

### Changed — Codebase optimization (§8)

**File splits (§8.1):**
- `model_service.dart` split: 5696 → 1396 lines. Static catalog data,
  language lists, data classes (ModelDefinition, BackendRepo, ModelInfo,
  ModelKind, etc.) extracted to `model_catalog.dart` (4318 lines).
  `model_service.dart` re-exports it for backward compatibility.
- `transcription_output_widget.dart`: `CleanupDialog` and `SummarizeDialog`
  extracted to own files (2372 → 1770 lines).
- `transcription_screen.dart`: `PresetsDialog` and `NarrowTabbedBody`
  extracted to own files (3858 → 3533 lines).

**Asset optimization (§8.9):**
- `app_logo.png` losslessly compressed: 1.4 MB → 883 KB (37% reduction).
- `AppLogo.png` losslessly compressed: 1.8 MB → 1.2 MB (31% reduction).

**CI build caching (§8.8):**
- CrispASR native build cached between CI runs via `actions/cache@v4`,
  keyed on the sibling repo's commit hash. Saves ~15-30 min on cache hit.

**Test coverage (§8.7):**
- 100 new tests in 8 files: model lookup, A/B testing, speaker vocab,
  segment tags, watch folder, log service, audio utils, file utils.
  Total: 595 → 695 tests (+17%).

**Analyzer:**
- 0 issues across `lib/` and `test/` (2 info-level lint hits fixed).

### Fixed — Pre-existing CI analyze errors
- `crispembed_web.dart`: `dynamic` → `int` cast for WASM ctxPtr/dim.
- `translate_screen.dart`: deprecated `value:` → `initialValue:`.
- `hfspace_live_test.dart`: explicit `<Map<String, dynamic>>` type args
  on `dio.get()` calls.
- `hfspace_engine_test.dart`: explicit `<dynamic>[]` type arg on empty list.

### Added — HF Space engine: Gradio-API fallback mode
- `HfSpaceEngine` gains an `HfSpaceApiMode` toggle (`setApiMode`). Default
  `openai` uses the Space's OpenAI-compatible `/v1` REST API (now exposed by
  the CrispASR space's FastAPI proxy); `gradio` drives the Space's
  auto-generated Gradio call API (`/gradio_api/upload` + `/call/transcribe`,
  SSE result) instead — a portable fallback that works against any Gradio
  space even without a `/v1` proxy. (Pairs with the CrispASR `hf-space`
  `/v1` proxy change.)

### Added — Client-side WASM text embeddings
- **CrispEmbed WASM** — the CrispEmbed C++ library (ggml) now compiles to
  WebAssembly via Emscripten. On web, `crispembed_web.dart` loads the WASM
  module, fetches a Q4_K model (~19 MB) from HuggingFace, and runs text
  embedding inference client-side in the browser (~50-100ms per sentence).
  Enables semantic search over transcripts without a server roundtrip.
- **`deploy-web.yml`** GitHub Actions workflow — auto-builds Flutter web
  and deploys to Vercel on every push to main. Requires `VERCEL_TOKEN`,
  `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` secrets.
- **`platform_utils.dart`** — web-safe `Platform.*` wrappers used across
  23 files to prevent `UnsupportedError` crashes on web.

### Added — Web text translation via HF Space
- **Translate screen on web** — routes text-to-text translation through the
  CrispASR HF Space's new Translate tab (M2M-100, WMT21, MADLAD-400) via
  Gradio call API. No local NMT models needed on web.
- **Transcription params** — `translate`, `vad`, `diarize`, `punctuation`
  fields now forwarded to the HF Space `/v1/audio/transcriptions` endpoint.
- **Text LID** — `detectTextLanguage()` method on HfSpaceEngine calls the
  Space's `crispasr-lid` via Gradio API.

### Added — Unit + live tests for web/HF Space features
- 32 unit tests (mock Dio): `hfspace_engine_test`, `hfspace_tts_service_test`,
  `platform_utils_test`. Covers init, model load, transcribe, TTS, WAV parse,
  cancel, translate/VAD/diarize/punct param forwarding.
- 13 live integration tests (`@Tags(['live'])`, `RUN_LIVE_TESTS=1`): real
  HF Space API calls — health, backends, whisper load, JFK transcription,
  kokoro TTS synthesize (with readiness poll), Gradio transcribe/LID/translate.
  All 13 pass, 0 skip.

### Changed — CrispASR HF Space infrastructure
- **Kokoro g2p dict fallback** (CrispASR): wired §156 permissive G2P dicts
  into kokoro's `phonemize_cached()`. Kokoro now tries EN/DE/FR/ES IPA dicts
  (auto-download from HF, permissive license) before falling back to espeak-ng.
- **Pre-built binaries**: HF Space Dockerfile now downloads pre-built linux
  x64 binaries from GitHub Releases instead of compiling from source (avoids
  6+ min build timeout on HF free tier).
- **Dedicated Vercel project**: `crisperweaver-web` at
  `crisperweaver-web.vercel.app` (was sharing the `web` project with CrispCloud).

## 0.7.8 — 2026-06-10

### Fixed — iOS release build (device_info_plus needs the iOS 26.1 SDK)
- The iOS job now runs on **`macos-26`** (Xcode 26 / iOS 26.1 SDK) instead of
  `macos-latest` (Xcode 16.4). `device_info_plus 13.1.0` calls
  `-[NSProcessInfo isiOSAppOnVision]` guarded by `@available(iOS 26.1, *)`,
  which still must *compile* against the 26.1 SDK — undeclared on the older
  SDK, this broke the v0.7.7 iOS build (`No visible @interface … isiOSAppOnVision`).
  No dependency change (a downgrade is blocked by the plus_plugins win32 ^6 set).

## 0.7.7 — 2026-06-09

### Added — Web/PWA HF Space cloud engine
- **`HfSpaceEngine`** (new `EngineType.hfspace`) — on web/PWA, where on-device
  FFI is unavailable, transcription + TTS route to the `cstr/CrispASR`
  Hugging Face Space (`/v1/audio/transcriptions`, `/v1/audio/speech`,
  `/load`, `/v1/voices`, `/health`). Adds `hfspace_tts_service.dart`,
  web byte-stream file picking, and a `vercel.json` for the web deploy.
- Lint cleanup across the new web/PWA code so the analyze gate is green
  (explicit Dio type args, `PlatformFile.readAsBytes()`, unused imports).

### Fixed — iOS + macOS release builds (regressed in v0.7.6)
- **iOS** — bump the app's iOS deployment target 13.0 → **15.0** (Podfile
  `platform`/`post_install`, `AppframeworkInfo.plist`, Xcode project). The
  `crispembed` plugin raised its podspec minimum to 15.0 on its `main`, so
  `pod install` failed at release time; aligning the app fixes it.
- **macOS** — the heavier CrispASR `main` (Zonos, TADA-TTS, …) OOM-killed the
  7 GB M1 runner during an unbounded `cmake --build --parallel` (`exit 143`).
  Bound the dylib build to `--parallel 2` and add a 120 min job timeout.
- (Android / Linux / Windows were unaffected — v0.7.6 already shipped those.)

## 0.7.6 — 2026-06-09

### Fixed — TTS reliability on Android (#20–#23)
- **Synthesis runs in a background isolate (#23)** — `TtsService.synthesize()`
  now runs the long native FFI call via `Isolate.run()`, so the UI thread
  stays responsive during synthesis. Fixes the freeze / ANR on models that
  take >10 s (Orpheus, Chatterbox, IndexTTS, CosyVoice3).
- **No-output feedback (#22)** — the Synthesize screen now shows an error
  with a backend-specific diagnostic when synthesis returns no audio
  (qwen3-tts quantisation, kokoro phonemizer, pocket-tts Mimi decoder)
  instead of silently doing nothing.
- Unit + live test suite covering pocket-tts / piper / orpheus / qwen3-tts.
- Native side (#20 pocket noise, #21 piper crash) is rebuilt fresh from
  CrispASR v0.7.1 at release time — includes the pocket-tts ggml GPU/sched
  migration and the conv_transpose_1d kernel fix.

### Added — Licence surfacing + newer TTS voices
- **Non-commercial licence warning** — `ModelDefinition` now carries an
  upstream `license` string mirrored from the CrispASR registry. Models
  under a non-commercial / research-only licence (CC-BY-NC; currently the
  German `moonshine-de` / `moonshine-tiny-de`) require an explicit
  confirmation before download.
- **Newer TTS backends in the catalogue** — added CrispASR-registry
  RepoSpecs for `tada`, `lex-au-orpheus-de`, the German
  `kartoffel-orpheus-de-*` voices, `chatterbox-turbo` / `kartoffelbox-turbo`,
  `vibevoice-1.5b`, and the `qwen3-tts` 1.7B / custom-voice variants
  (fixing the previously-broken kartoffel-orpheus entries). Built against
  CrispASR v0.7.1.

### Changed — TTS watermark & disclaimer (2026-06-09)
- **Auto-watermark from C API** — `crispasr_session_synthesize()` now
  auto-embeds the spread-spectrum / AudioSeal watermark. Removed the
  explicit `CrispasrWatermark.embed()` call in `writeWav()` to avoid
  double-watermarking. Falls back to Dart LSB watermark only when
  native symbols are unavailable (web builds).
- **Spoken disclaimer opt-out** — `writeWav()` accepts `spokenDisclaimer:
  false` to skip the beep-based AI disclaimer on voice-cloned output.
  Machine-readable provenance (watermark + WAV metadata) always applied.
  Server endpoint `/v1/audio/speech` accepts `"spoken_disclaimer": false`.

### Fixed — CI, web compilation, Windows Zen3 crash (2026-06-09)
- **CrispEmbed in CI/release workflows** — added `CRISPEMBED_REPO`/`REF`
  env vars and checkout steps in all 8 jobs (3 CI + 5 release). Fixes
  "could not find package crispembed" pub-get failure that broke CI since
  the crispembed dependency was added.
- **Web compilation via conditional imports** — `dart:ffi` is unavailable
  on web; all `package:crispasr`, `package:crispembed`, and direct ffi
  imports gated behind conditional barrel files in `lib/native/`. Stubs
  provide the same type surface with `UnsupportedError` constructors.
  `flutter build web --release` succeeds; deployed to Vercel.
- **Windows AVX-512 crash on Zen3** (fixes #19) — release workflow's
  Windows cmake used `GGML_NATIVE=ON` (default), baking AVX-512 from
  GitHub Actions runners into `whisper.dll`. AMD Zen3 CPUs only support
  AVX2, causing crash on model load. Fixed by setting `GGML_NATIVE=OFF`
  and pinning to AVX2+FMA+F16C.

### Fixed — Mobile UX: file picker, adaptive icon, iOS alpha, PWA (2026-06-09)
- **Android file picker greyed-out files** — `pickFilesRobust()` now accepts
  an optional `FileType` parameter. All audio-picking call sites pass
  `FileType.audio` so Android's native picker uses `audio/*` MIME (all audio
  files selectable). Results are post-filtered by `allowedExtensions`.
  `FileType` re-exported from `file_picker_util.dart` for caller convenience.
- **Android adaptive icon** — added `adaptive_icon_foreground` /
  `adaptive_icon_background` (#1d325f) to `flutter_launcher_icons` config.
  Android 8+ (API 26) now applies its configured mask (rounded rect, circle,
  squircle) instead of displaying a raw square PNG.
- **iOS icon alpha channel** — added `remove_alpha_ios: true` and
  regenerated all iOS icons as RGB (no alpha). Fixes App Store rejection for
  icons with transparency.
- **Web / PWA platform** — scaffolded Flutter web target. `manifest.json`
  with branded 192 + 512 px icons (+ maskable), standalone display mode,
  navy theme. Installable as PWA on mobile browsers. Feature set limited to
  mock engine / remote server mode (no FFI on web).

### Added — Split-on-punct, audio embeddings, Notifier migration (2026-06-08)
- **Split-on-punct subtitle formatting** (§5.8) — Dart-side post-processing
  that splits segments at sentence-ending punctuation (. ! ?). Works with any
  backend. Toggle in Advanced Options. i18n (EN/DE).
- **Cross-modal audio embedding** (§5.25.2) — `audioEmbedding` persisted per
  history entry via `crispembed_encode_audio`. Search ranks entries by
  `max(text_score, audio_score)`. `bidirlm-omni-2.5b` (2048-d) catalogued.
  6 new tests.
- **Riverpod Notifier migration** — 3 of 4 `StateNotifier` subclasses
  migrated to modern `Notifier` pattern. `legacy.dart` imports reduced
  from 4 files to 2.

### Added — Riverpod 3, embedding persistence, SDK upgrade (2026-06-08)
- **Riverpod 2→3** — bumped `flutter_riverpod` to 3.3.1. Legacy
  `StateNotifier`/`StateProvider` classes moved to `legacy.dart` import
  in 4 files. No functional changes; full `Notifier` migration deferred.
- **Embedding persistence** (§5.25.2) — segment embeddings pre-computed
  at history save time and stored in JSON. Search loads persisted vectors
  first, falls back to in-memory cache, then on-the-fly encoding.
  "Reindex embeddings" button on History screen backfills old entries.

### Added — Flutter SDK upgrade + CrispEmbed integration (2026-06-08)
- **Flutter SDK 3.35.1 → 3.44.1** (Dart 3.9.0 → 3.12.1). 36 tier-2
  packages bumped (§5.9): `device_info_plus` 13.1, `share_plus` 13.1,
  `package_info_plus` 10.1, `win32` 6.3, `file_picker` 12.0.0-beta.5.
  Three files fixed for API changes.
- **Real semantic transcript search** (§5.25.2) — `crispembed` path
  dependency wired via `crispEmbedProvider`. History screen semantic search
  now uses real vector embeddings (cosine similarity) when `all-MiniLM-L6-v2`
  GGUF is downloaded (~23 MB). TF-IDF fallback preserved when no model/lib
  available. Embedding cache avoids re-encoding on repeated searches.
- **`ModelKind.embed`** added to the model catalogue. `all-MiniLM-L6-v2-Q8_0`
  catalogued as the first embedding model with `BackendRepo` entry.

## 0.7.5 — 2026-06-08

### Wired — §5.25 completion pass
- **Segment tag filter chips on History screen** (§5.25.10) — horizontal
  scrollable `FilterChip` row for all 7 tag types. Active tags narrow the
  displayed entries to those containing at least one matching tagged segment.
  Combines with text search (substring or semantic).
- **Settings UX** — Speakers + Speaker Vocabulary tiles moved from the
  Debugging section to the Diarization section where they logically belong.
- **Memory fix** — retained PCM audio buffer (~230 MB/hr) is now freed
  immediately after multilingual tagging instead of held until the next
  transcription starts.
- Verified §5.25.12 keyboard nav, §5.25.9 lexicon editor, §5.25.4 speaker
  vocab editor, and §5.25.6 chapter export are all fully wired (previously
  marked as "remaining" in PLAN.md but implementation was already in place).
- Four new test files: chapter detection, history screen widget,
  pronunciation lexicon, semantic search service.

### Added — §5.25 next-generation features (14 features)
- **Subtitle overlay / teleprompter mode** (§5.25.3) — fullscreen dark-transparent
  screen (`/subtitle-overlay`) showing live streaming transcription as large
  subtitle text. On macOS the window is set to always-on-top + reduced opacity
  via a new platform channel. Controls for font size, position, and background.
- **Transcript diff / comparison view** (§5.25.7) — side-by-side comparison of
  two history entries with LCS-based word-level diff highlighting and Jaccard
  similarity stats. Route: `/compare?left=ID&right=ID`.
- **Note-taking tool exports** (§5.25.14) — Obsidian (YAML frontmatter +
  timestamped bullets), Notion (speaker H2 headers), Logseq (indented bullet
  blocks with properties), YouTube chapters (HH:MM:SS title lines). All four
  wired into the transcript share menu.
- **Watch-folder transcription** (§5.25.8) — `WatchFolderService` monitors a
  user-configured directory for new audio files (2 s debounce) and auto-enqueues
  them into the batch queue. Desktop-only. Settings → "Watch folder" section.
- **Segment annotation tags** (§5.25.10) — 7 tag types (bookmark, action-item,
  question, important, highlight, decision, follow-up) with emoji badges.
  Tag picker in segment long-press menu. Tags persist in history JSON.
- **Keyboard-driven transcript navigation** (§5.25.12) — J/K segment nav,
  Space play/pause, Enter edit, Tab jump-to-low-confidence, Escape deselect.
  Focus ring on active segment card. Desktop power-user feature.
- **Confidence heatmap enhanced** (§5.25.1) — background-color gradient
  (transparent → yellow → orange → red) instead of text-color-only. Low-
  confidence words (<0.5) additionally get colored text + underline.
- **TTS pronunciation lexicon** (§5.25.9) — user-editable word → pronunciation
  override table (respelling or IPA) applied before TTS synthesis. JSON
  persistence at `<app-docs>/lexicon.json`.
- **Audio fingerprint deduplication** (§5.25.11) — SHA-256 fingerprinting (PCM-
  based + lightweight file-based) for detecting duplicate audio in the batch
  queue. `audioFingerprint` field on `HistoryEntry`.
- **Speaker-adaptive vocabulary** (§5.25.4) — per-speaker vocab profiles
  persisted alongside `.spk` enrollment files. `mergeForSpeakers()` computes
  the union of active speakers' terms for injection into `initial_prompt`.
- **Multilingual simultaneous transcription** (§5.25.5) — per-segment language
  detection via LID, tagging each segment with `metadata['lang']`.
  `groupByLanguage()` for optional per-language re-transcription.
- **Semantic transcript search** (§5.25.2) — TF-IDF relevance scorer (word
  overlap + IDF weighting) as a scaffold for CrispEmbed vector search.
- **Chapter detection** (§5.25.6) — topic-shift detection via sliding-window
  Jaccard vocabulary distance. Exports to YouTube chapters and Podcasting 2.0
  JSON.
- **Model A/B testing** (§5.25.13) — `AbTestResult` with per-segment winner
  picks. `ModelRatings` leaderboard aggregates results across tests.

### Wired — §5.25 post-wiring handover (2026-06-08, commit be6526f)
- **Parallel A/B model comparison** (§5.25.13) — `_showModelComparison` now
  spawns two single-worker pools via `Future.wait` instead of running models
  sequentially. `ModelRatings` persisted to `<app-docs>/model_ratings.json`.
- **Speaker-adaptive vocab auto-injection** (§5.25.4) — after diarisation
  resolves speaker names, `SpeakerVocab.mergeForSpeakers()` injects domain
  terms into `advancedOptionsProvider` vocabulary for subsequent transcriptions
  (both single-file and batch paths).
- **Fingerprint dedup before enqueue** (§5.25.11) — watch folder auto-skips
  duplicates; batch enqueue silently skips; single-file drag-drop shows a
  confirmation dialog before re-processing.
- **i18n migration** — 33 hardcoded strings migrated to ARB files (866 total
  keys, full EN/DE parity). `flutter gen-l10n` succeeds with Flutter 3.35.1;
  generated classes at `lib/l10n/generated/` are up to date.

### Added — previous unreleased
- MP3 ID3v2 AI-provenance tags (`AI_GENERATED`, `GENERATOR`, `AI_CONTENT_NOTICE`) via `AudioWatermarkService.injectMp3Metadata()`
- Beep-based AI disclaimer prepended to voice-cloned TTS output (3× 880 Hz, EU AI Act Art. 50(4)) via `AudioWatermarkService.generateBeepDisclaimer()`
- Post-embed watermark verification — `detectWatermark()` called after embedding, warns if null
- Consent attestation audit logging (`[CONSENT] ts=ISO8601 model=X voice=Y attestation="user consent"`) matching CrispASR/CrispTTS format, via `_logConsentAttestation()`
- 14 new synthetic compliance tests in `test/synthetic_compliance_test.dart`

## 0.7.4 — 2026-06-06

- **Synthetic content compliance** — TTS audio is now watermarked and carries
  LIST INFO provenance metadata (ISFT, ICMT, IART, ICRD) in every WAV file.
  Two-tier watermarking: native CrispASR spread-spectrum (frequency-domain,
  survives re-encoding + compression; upgradeable to AudioSeal neural
  watermark via GGUF) when the dylib exports `crispasr_watermark_*`, with a
  pure-Dart LSB fallback on older builds. The `/v1/audio/speech` endpoint
  returns an `X-Content-AI-Generated: true` header.
- **Biometric consent for speaker enrollment** — enrolling a speaker profile
  now shows an explicit consent dialog (GDPR Art. 9). Consent is persisted
  as a companion `.consent.json` alongside the `.spk` embedding file and
  is deleted together on erasure.
- **AI-Generated Audio chip** on the Synthesize screen after playback.
- **Export disclosure** — SRT, VTT, JSON, and Markdown export formats accept
  an optional `syntheticDisclosure` flag to prepend a machine-readable notice.
- **About screen** — new "Synthetic Content Compliance" section.
- **Speaker data export** — `SpeakerIdService.exportSpeakerData()` for GDPR
  Art. 20 data portability.
- **MeloTTS v3 static catalogue** — v3 model now appears on fresh launch
  without a deep refresh; companion reference fixed (`bert-base-uncased-q4k`).
- **CI fixes** — smart-quote JSON delimiters in `app_de.arb`, deprecated
  `DropdownButtonFormField.value`, cmake target rename `crispasr-lib`.

## 0.7.3 — 2026-06-05

- **PCS post-processor** — all-in-one punctuation + capitalization + sentence
  boundary detection in a single pass, 47 languages via XLM-RoBERTa-base.
  Published at [cstr/pcs-xlmr-base-GGUF](https://huggingface.co/cstr/pcs-xlmr-base-GGUF)
  (Q4_K ~155 MB, F16 ~903 MB). Third option in the Advanced Options punctuation
  family picker alongside FireRedPunc and fullstop-punc.
- **Punctuation family picker** now has three options: PCS (all-in-one, 47 langs),
  FireRedPunc (ZH+EN), fullstop-punc (EN/DE/FR/IT). PCS routes to `PcsModel`
  directly; others chain `PuncModel` + truecaser.
- **Baked catalog regenerated** — 95 repos probed, 287 entries baked. All new
  quant variants for v0.7.x backends are now available offline.
- **TTS verification checklist** added at `docs/tts-verify-checklist.md`.

## 0.7.1 — 2026-06-05

- **Zonos v0.1 TTS** — Zyphra 500M-param transformer TTS with 8-axis emotion
  control (happiness, sadness, fear, anger...), pitch/speaking-rate tuning,
  speaker cloning from reference audio, and native 44.1 kHz output. Q4_K
  (~872 MB) + F16 (~3.1 GB) published at
  [cstr/zonos-v0.1-transformer-GGUF](https://huggingface.co/cstr/zonos-v0.1-transformer-GGUF).
  Shares the DAC 44.1 kHz codec companion with Dia.
- **MOSS-Audio 4B** — new ASR + audio QA backend (Whisper encoder + Qwen3 LLM,
  ~3.8 GB Q4_K). Supports instruction-tuned audio understanding: transcription,
  audio question answering, and scene description.
- **Backend capability sets expanded** — Audio Q&A prompt field, temperature
  slider, vocabulary chips, and source-language picker now appear for all
  applicable backends: moss-audio, mimo-asr, gemma4-e2b, granite-4.1-nar,
  sensevoice, funasr, paraformer, vibevoice.
- **Bake script synced** — `bake_models_catalog.dart` now has RepoSpecs for all
  31 new backends added in v0.7.0/0.7.1.

## 0.7.0 — 2026-06-05

**Full CrispASR parity release** — CrisperWeaver now leverages every backend
CrispASR supports, jumping from ~30 to 60+ compiled backend targets and from
8 to 20+ TTS families.

### New TTS backends (10)

- **Bark** — 3-stage GPT-2 TTS, multilingual, 10 German speakers (~500 MB)
- **CSM** — Sesame CSM-1B conversational TTS, single EN voice (~1.4 GB)
- **Dia** — Nari Labs 1.6B dialogue TTS with `[S1]`/`[S2]` speaker tags + DAC codec (~3 GB). Synthesize screen shows dialogue-mode hint when Dia is active.
- **FastPitch** — NVIDIA deterministic parallel TTS, English, 60M params (~120 MB)
- **MeloTTS** — VITS2, 4 English speakers, 44.1 kHz; v2 + v3 variants with BERT companion (~102 MB + ~52 MB)
- **OuteTTS** — OLMo-1B + WavTokenizer VQ-GAN, voice clone via JSON speaker (~1.3 GB + ~130 MB decoder)
- **Parler-TTS** — prompt-conditioned TTS: describe the voice in natural language via the Instruct field (~900 MB)
- **Pocket TTS** — Kyutai 100M continuous-latent AR TTS, voice clone from WAV (~220 MB)
- **SpeechT5** — Microsoft 80M AR mel decoder + HiFi-GAN (~300 MB)
- **KugelAudio** — large TTS model (~14 GB F16)

### New TTS variants

- **Qwen3-TTS 1.7B Base** — higher-quality variant with runtime voice cloning
- **Gwen-TTS** — Vietnamese-optimised Qwen3-TTS finetune
- **Lahgtna Chatterbox** — Arabic T3 finetune
- **lex-au Orpheus DE** — German Orpheus-3B fine-tune
- **VibeVoice 1.5B** — larger VibeVoice variant

### New ASR models

- **Moonshine German** — base (6.9% WER) + tiny (11.4% WER) fidoriel fine-tunes
- **HuBERT Large** — wav2vec2-family English CTC (~200 MB)
- **Wav2Vec2 German** — XLSR-53 German CTC (~222 MB)
- **OmniASR CTC 300M** — 1600+ languages, tiny variant (~194 MB)
- **Parakeet Japanese** — TDT 0.6B JA fine-tune (F16 recommended)
- **Parakeet CTC** — 0.6B + 1.1B CTC-only English models
- **Parakeet TDT+CTC** — 110M tiny hybrid + 1.1B multilingual hybrid
- **Parakeet RNNT** — 0.6B + 1.1B RNN-Transducer variants

### Post-processing

- **Truecaser** — BiLSTM character-level truecasing models for DE/EN/ES/RU from `cstr/truecaser-de`. Chained automatically after punctuation restoration; auto-selects the right language model. German model achieves 97.9% F1.
- **Native punctuation** — session-level `setPunctuation(true)` now fires on every dispatch. Canary, Cohere, and LLM-style backends produce punctuated + capitalised output natively without requiring a separate FireRedPunc model.
- **Token generation cap** — `setMaxNewTokens(4096)` on every session dispatch prevents runaway generation on LLM-style ASR backends.

### Text language identification

- **GlotLID v3** — 2102 languages (ISO 639-3), ~250 MB
- **FastText LID-176** — 176 languages, ~63 MB (CC-BY-SA-3.0)

### Build & infrastructure

- Build scripts (Linux/macOS/Windows) expanded from ~30 to ~60 backend targets, covering all ASR, TTS, translation, and post-processing backends.
- Instruct field label updated: "VoiceDesign / Parler-TTS" (was "qwen3-tts VoiceDesign only").
- Dia dialogue hint in Synthesize text input explains `[S1]`/`[S2]` tag syntax.

## 0.6.50 — 2026-06-01

- **Fix — Qwen3-TTS 1.7B CustomVoice now visible on fresh launch.** The
  parity guard test we added caught a fourth instance of the #18 root cause:
  `qwen3-tts-1.7b-customvoice` had a HuggingFace probe entry but no static
  catalogue entry, making it invisible in the Synthesize picker until the user
  visited Model Management. Fixed.
- **CI fix — macOS test flake resolved.** The `batch_queue_service_test`
  intermittently failed on macOS CI with "Directory not empty" because
  fire-and-forget persistence writes from secondary notifiers raced the temp
  directory cleanup. Writes are now drained deterministically before dispose.
- **Structural guard against #18 recurrence.** New CI test validates that
  every `BackendRepo` with kind=asr/tts has at least one matching static
  catalogue entry. The three independently-maintained lists (BackendRepo,
  crispasrBackendModels, bake script) can no longer silently drift — adding
  a new HF repo without a static entry now fails CI.
- **Expanded regression tests for #16/#17/#18.** Unit tests now cover the
  exact crash-report model (Piper en_US LibriTTS-R), all piper catalogue
  invariants, single-speaker edge cases, CustomVoice companion codec wiring,
  and the qwen3-tts base model. New live FFI tests (tag-gated `slow`)
  exercise the actual native paths: `availableBackends()` gate, CustomVoice
  speaker enumeration + synthesis, and session-open for all #18 models.

## 0.6.49 — 2026-05-31

- **F5-TTS** — added F5-TTS v1 Base to the model catalogue: a DiT
  flow-matching text-to-speech model with zero-shot voice cloning from a
  short reference clip + its transcript (English, single ~953 MB download,
  no companion). Listed in the Synthesize / Model Management pickers.
  Audio-verified end-to-end. Heads-up: synthesis is currently very slow.
- **cosyvoice3 verified** — the catalogued CosyVoice3 TTS (LLM → flow →
  HiFT) is now confirmed to synthesise intelligible audio end-to-end.
- **Piper TTS now dispatches through the engine.** The crash-guard added in
  0.6.47 self-heals: builds carrying the rebuilt engine now list `piper`
  among the available backends, so Piper voices synthesise instead of being
  refused as unsupported.
- **Engine refresh** — bundled CrispASR engine rebuilt off the latest
  upstream, which (among other things) wires beam search through the
  canary/cohere decoders. No UI change.

## 0.6.48 — 2026-05-30

- **Quick start** — Model Management has a new 🚀 action that opens a
  one-tap starter sheet: a small curated set (Whisper base for transcription,
  Kokoro for speech synthesis, a compact chat LLM for Tidy/Summarize) you can
  grab individually or all at once. Companions download automatically.
- **Detect transcript language** — the transcript output menu (⋮) now has a
  **Detect language** action that runs the on-device CLD3 text language-ID
  model over the transcript and reports the detected language, outside the
  Translate flow. Prompts to download CLD3 if it isn't present.

## 0.6.47 — 2026-05-30

- **Fix (#16) — Piper TTS no longer crashes the app.** Tapping Synthesize
  with a Piper voice instantly killed the app on Android & Windows: the
  bundled engine can't yet dispatch Piper through the unified session API,
  and the native open segfaulted. The Synthesize screen now refuses
  unsupported backends with a clear message instead of crashing, and will
  start working automatically once an engine build that lists the backend
  ships.
- **Fix (#17) — Qwen3-TTS CustomVoice now produces audio.** CustomVoice
  needs one of its built-in speakers selected; the Synthesize screen had
  no speaker picker, so it always synthesised silence ("synthesis returned
  no audio"). There's now a **Speaker** dropdown for voices with built-in
  speakers (Qwen3-TTS CustomVoice, Orpheus), auto-filled with the first
  speaker so one-tap synthesis just works.
- **Fix (#18) — more TTS models show up without a deep refresh.** Qwen3-TTS
  0.6B CustomVoice and Chatterbox turbo T3 were only listed after opening
  Model Management and waiting for the HuggingFace probe. They're now in
  the built-in catalogue, so they appear in the Synthesize picker on a
  fresh launch like every other model.

## 0.6.46 — 2026-05-30

- **Fix (alt-token picker)** — picking an alternative candidate for a
  word now swaps that whole word only. Previously it replaced the first
  substring match, so picking the alt for e.g. "cat" could rewrite
  inside an earlier "category".
- **Cleanup** — removed a dead "Export" entry from the transcript output
  overflow menu that only ever showed a "not implemented" dialog. Export
  is unaffected: the transcript Save/Share menu (plain text / SRT / VTT /
  JSON / audio bundle) remains the single working path.
- **Dependency refresh** — in-constraint bumps of 25 packages
  (desktop_drop, go_router, permission_handler, record, build_runner,
  json_serializable, and transitives). No behaviour change; major
  upgrades (device_info_plus 13, share_plus 13, riverpod 3, …) remain
  deferred pending migration.

## 0.6.45 — 2026-05-30

- **Recommended models + one-tap setup** — each backend now flags its
  recommended "start here" model with a **Recommended** badge (Model
  Management) and a ⭐ in the Transcribe model picker. When you filter
  the picker to a backend you haven't downloaded anything for yet, a
  one-tap **Download recommended** row appears at the top — it fetches
  the right model *and* its companions (voicepacks/codecs) in a single
  step, so the backend is immediately runnable.
- **German localization completed** — the Model Management
  HuggingFace-repo dialogs (add / manage), the model filter chips and
  status messages, the Synthesize companion-download messages, and the
  "Enroll speaker from this segment" flow are now fully translated. The
  `en`/`de` string tables are at full parity.

## 0.6.44 — 2026-05-29

- **Piper VITS TTS** — a new `piper` synthesis backend with 10 small,
  permissively-licensed single-file VITS voices (~15–60 MB each), all
  redistributable:
  - **German** — Thorsten (medium / high / emotional), Kerstin, MLS,
    Eva K, Karlsson, Ramona.
  - **English** — Cori (en-GB), LibriTTS-R.

  Each voice's upstream licence (CC0 / public-domain / BSD-style /
  CC-BY 4.0) is recorded in its catalogue entry; the Blizzard
  research-only voices are deliberately excluded. The voices appear in
  the Synthesize model picker once downloaded.

## 0.6.43 — 2026-05-29

Catalogue additions on top of the 0.6.42 engine rebuild:

- **CosyVoice3 TTS** — new multilingual (10 languages) synthesis backend
  on the Synthesize screen; downloads its flow / HiFT / voice-pack
  companions automatically alongside the LLM weights.
  **Experimental** — output not yet end-to-end audio-verified.
- **Translate → Auto-detect source language** — a new button on the
  Translate screen runs on-device text language-ID (CLD3, ~430 KB) over
  the typed text and sets the source-language dropdown. Prompts to
  download CLD3 if it isn't present.
- **Enroll a named speaker from a transcript segment** — long-press a
  segment → *Enroll speaker from this segment…* to name a speaker from a
  result. Future recordings then re-identify that speaker when *Identify
  speakers* is on (closes the speaker re-ID loop; matching already
  existed).
- **data2vec-audio** — English ASR model catalogued (runs on the
  existing wav2vec2 backend, no engine change).

## 0.6.42 — 2026-05-29

Four catalogued backends that previously errored at load now actually
run — this release rebuilds the bundled CrispASR engine with their
dispatch arms:

- **WMT21 Dense translation** (en↔X) — the `m2m100-wmt21` entries on the
  Translate screen now load and translate (they route through the
  WMT21-capable m2m100 engine).
- **MADLAD-400 translation** (419 languages) — the `madlad` entry now
  loads and translates via CrispASR's T5 engine (target language picked
  from the `<2xx>` tag, wired to the Translate screen's language picker).
- **IndexTTS** — now synthesizes on the Synthesize screen.
  **Experimental:** it's a reference-cloning voice (pick a reference WAV
  under *Custom voice*); the clone-audio quality hasn't been
  end-to-end-verified yet.
- **VoxCPM2 voice cloning** — supply a reference WAV under *Custom voice*
  to clone a speaker (zero-shot synthesis already shipped in 0.6.41).
  **Experimental** — clone audio not yet end-to-end-verified.

Under the hood: a catalogue↔dispatch guard test (so a catalogued backend
can't silently ship without an engine arm) and an opt-in TTS→ASR
roundtrip live test (synthesize → transcribe → verify the words survive).

## 0.6.41 — 2026-05-29

Follow-up batch — a new TTS backend, persistence + UX fixes, and an
Android responsiveness pass on the whisper path:

- **VoxCPM2 TTS** — new tokenizer-free diffusion-AR synthesis backend
  (`openbmb/VoxCPM2`), zero-shot, 29 languages, 48 kHz native (down-mixed
  to the app's 24 kHz playback in the engine). Ships as `voxcpm2-q4_k`
  (1.6 GB default) + `voxcpm2-f16`; appears in the Synthesize model
  picker once downloaded. Wired end-to-end through CrispASR's unified
  session API.
- **HuggingFace repos now persist** — repos added via "Add from
  HuggingFace repo…" survive an app restart (previously runtime-only and
  lost on relaunch). A new "Manage added HuggingFace repos…" action on
  the Models screen lists them and lets you forget one.
- **Cancel during model load** — the Transcribe screen's loading row
  gains a Cancel button so a long (~10 s) model open no longer traps you
  behind an indeterminate bar. The model finishes loading in the
  background, so a later Transcribe runs against it immediately.
- **Faster first transcribe on Android (whisper)** — the blocking model
  open is deferred off the platform isolate, so the first Transcribe tap
  on whisper-base no longer freezes the UI for ~10 s. Long (>60 s) files
  also stream through the worker isolate instead of freezing per chunk.
  Word-timestamp / SRT output is unchanged (kept on the proven path).
- **Models screen** — the backend filter is now a type-ahead Autocomplete
  (matching the Transcribe screen's language picker) instead of a plain
  dropdown.
- **iOS groundwork** — `scripts/build_ios_xcframework.sh` can now
  cross-build libespeak-ng for iOS (`ESPEAK_NG=1`), the first step toward
  Kokoro phonemisation on iOS. Off by default; existing builds unchanged.

## 0.6.0 — 2026-05-17

Big shipping release after a long week of feature work +
live-testing-driven bugfix runs:

- **iOS Share Extension** — fully wired (build script +
  vendored RSIShareViewController + App Group container for
  models so they survive `flutter install`). Codesigned device
  build verified.
- **Windows MSIX** — packaging + file-type associations
  (audio + subtitle extensions). Release workflow now uploads
  `.msix` alongside the portable `.zip`.
- **Speakers** — TitaNet 192-d enrollment + on-disk
  SpeakerDB; diariser segments resolve to enrolled names.
- **Models screen** — search bar + backend dropdown mirroring
  the transcribe screen, plus a Translate kind filter chip
  and HF probe failure visibility (the cstr/* repo coverage
  expands now that probe failures are surfaced instead of
  silenced).
- **Auto-switch model** when the persisted default isn't
  downloaded but other compatible models are.
- **Kokoro / TTS** — works end-to-end on macOS (with a CPU
  workaround for the upstream Metal regression — see
  `handover-prompts/crispasr-kokoro-gpu-metal-regression.md`).
  Voice / codec dropdowns trigger inline download. Empty-state
  cards link straight into the right Models filter.
- **Tons of small UX fixes** — close-X on every snackbar,
  collapsible Model section on the Transcribe screen, friendly
  first-launch "model not downloaded" snackbar, file picker
  uses document picker (not Apple Music) on iOS, TTS screen
  doesn't overflow when the keyboard opens, decoder-output
  formats now i18n'd ("Segments" / "Full Text" / "Bitte wähle
  eine Audiodatei…"), …

Full diff vs v0.5.0 is in the GitHub Releases page once the
tag is pushed.

### Windows — MSIX packaging + Explorer file associations

Closes the long-standing "Windows is the only desktop without
Open-With integration" gap.

What landed:

- New `msix_config:` block in `pubspec.yaml` (uses the
  `msix: ^3.16` dev_dependency) declaring publisher /
  identity / version / logo, and the file-extension list
  `.wav / .mp3 / .m4a / .flac / .ogg / .aac / .opus / .wma /
  .srt / .vtt`. Capabilities pruned to `internetClient` —
  `runFullTrust` (auto-added for non-UWP Flutter apps) gives
  normal Win32 file access without needing UWP-style
  `removableStorage` etc.
- Windows job in `.github/workflows/release.yml` runs
  `flutter pub run msix:create --verbose` after the standard
  Windows build + DLL bundle step, then uploads
  `crisper_weaver-windows-x64.msix` (+ sha256) alongside the
  existing portable `.zip`.
- Sideload-only for now (`store: false`, unsigned). README's
  CI & releases section gained an "Installing on Windows"
  block walking users through Unblock → double-click →
  Install → Open With. Microsoft Store registration is on
  the roadmap; flipping `store: true` + Partner Center
  publisher is what's left for that.

Manual `.msix` smoke test on a real Windows machine remains
pending.

### iOS Share Extension — fully wired (smoke test pending)

The ShareExtension target now lands end-to-end via
`scripts/wire_ios_share_extension.rb`. Codesigned debug build
verified locally: `Runner.app/PlugIns/ShareExtension.appex` is
present, signed by team N9XSJ4M3GT under bundle id
`com.crispstrobe.crisperweaver.ShareExtension`, and both
Runner.app and the .appex carry the
`com.apple.security.application-groups =
[group.com.crispstrobe.crisperweaver]` entitlement so the
extension-side App Group write / main-app-side read interop is
intact.

What the script does:

- Adds a PBXNativeTarget `ShareExtension` with
  app-extension product type, Debug / Release / Profile build
  configurations mirroring Runner (incl. Runner's
  DEVELOPMENT_TEAM for automatic codesigning), and the
  checked-in `ShareExtension/Info.plist` +
  `ShareExtension/ShareExtension.entitlements` wired via
  `CODE_SIGN_ENTITLEMENTS`.
- Adds Sources phase with `ShareViewController.swift` +
  `RSIShareViewController.swift` (vendored, see below).
- Adds an Embed App Extensions copy-files phase on Runner
  pointing at the .appex, placed immediately after the
  Frameworks phase to avoid the new build system's cycle
  detection through `ProcessInfoPlistFile`.
- **Fixes a pre-existing gap on the Runner side**: the
  checked-in `Runner/Runner.entitlements` was never wired to
  Runner's `CODE_SIGN_ENTITLEMENTS`, so Runner.app shipped
  without the App Group entitlement. Diagnosed via
  `codesign -d --entitlements -`. Script now sets that build
  setting (idempotent: skips if already set).
- Adds `com.apple.ApplicationGroups.iOS` SystemCapability on
  both targets so Signing & Capabilities reflects the
  enabled checkbox.

`ios/ShareExtension/RSIShareViewController.swift` is a 280-line
vendor of the extension-safe subset of `receive_sharing_intent`
v1.8.1. Vendored (not pod-linked) because the upstream plugin
calls `FlutterPluginRegistrar.addApplicationDelegate`, which is
`@available(iOSApplicationExtension, unavailable)` — strict
extension link fails. The main Runner target keeps the pod
normally; App Group `UserDefaults` round-trip is byte-compatible
because both sides serialise `[SharedMediaFile]` under the same
`kUserDefaultsKey`.

Companion Podfile change: dropped the `target 'ShareExtension'`
block (extension is framework-free now).

Pending: on-device tap-Share smoke test (open Voice Memos →
Share → CrisperWeaver should appear in the half-sheet).

### §5.8.1 — Named speaker recognition (TitaNet + SpeakerDB)

Closes the "Speaker 0 / Speaker 1" gap in diarisation output:
users can now enrol voices once and see every future
transcription replace the numeric labels with the real names
when there's a confident match.

What landed:

- New `SpeakerIdService` wraps the upstream `CrispasrTitaNet`
  (192-d L2-normalised embeddings) + `CrispasrSpeakerDB`
  (file-per-speaker on-disk profile DB, stored under
  `<app-docs>/speakers/` — nothing leaves the device).
- New `titanet-large-f16` entry in the model registry
  (`cstr/titanet-large-GGUF`, ~43 MB) — shows up under the LID
  filter chip in Model Management.
- Diarisation post-process: when `enableSpeakerRecognition` is
  on, after the numeric labels come back from
  `crispasr.diarizeSegments` we pick the longest segment per
  cluster, extract a centred ~3 s PCM slice, run one TitaNet
  match per cluster, and rewrite the segment `speaker` field
  with the enrolled name when score ≥ 0.7 (upstream default).
  Silently falls through to numeric labels otherwise.
- New Settings → Speakers screen (`/settings/speakers`): list,
  delete, and enrol via either a 10-second live recording or
  any decodeable audio file. Privacy note pinned prominently
  in the screen header.
- New AdvancedOptions toggle ("Identify enrolled speakers"),
  hidden when the diarisation method is `energy` (stereo
  channel IDs already disambiguate). Preset round-trip pinned;
  default off so users without TitaNet downloaded pay zero
  cost.
- Tests: filesystem round-trip (enrol → reopen → match) and
  end-to-end TitaNet pipeline (embed → enrol → re-match the
  same WAV → score ≥ 0.7) — both tag-gated under `slow` and
  skip cleanly when the dylib / GGUF aren't on disk. Preset
  round-trip + AdvancedOptions default tests run in the
  default suite.

### §5.8 — Whisper alt-token capture (`--alt N` parity, May 2026)

Closes out the last open `whisper-cli`-equivalent gap. Power-user
feature for technical / proper-noun-heavy recordings where the
Whisper first-choice token is plausible but wrong (`kubectl` →
`cubicle`); off by default.

Upstream (CrispASR 0.5.13):

- Whisper internals capture top-N runners-up at each greedy
  decode step into a parallel `alts` vector on the segment,
  mirrored through fallback retries, `result_len` truncation,
  and the `max_len` wrap-segment splitter. New
  `wparams.alt_n` (default 0 = off; beam search excluded
  because siblings are beam-conditional, not greedy
  alternatives).
- Six new public whisper getters
  (`whisper_full_get_token_n_alts` / `_alt_id` / `_alt_p`
  + `_from_state` variants).
- New C-ABI: `crispasr_params_set_alt_n` (low-level), sticky
  `crispasr_session_set_alt_n` (session), per-token accessors
  (`crispasr_token_n_alts` / `_alt_id` / `_alt_p` /
  `_alt_text`), and per-word session-result accessors
  (`crispasr_session_result_word_n_alts` / `_alt_text` /
  `_alt_p`).
- The whisper session-transcribe path (which previously
  returned only segment-level text) now populates `seg.words`
  via the unified `emit_words_from_tokens` helper —
  side-benefit aligning whisper's session API with what
  parakeet / canary already produced.
- Dart binding: new `AltToken` value class + `Word.alts`
  (default `const []`); `TranscribeOptions.altN`;
  `CrispasrSession.setAltN(int)`. Pre-0.5.13 dylibs raise
  `UnsupportedError` so apps graceful-degrade. Pubspec
  → 0.5.13. Smoke-test pins all nine new symbols.

CrisperWeaver:

- New `AdvancedOptions.altN` — 0..5 slider in the Whisper-only
  section. UI caps at 5 because Whisper's tail past the top few
  candidates is vanishingly small (memory ≈ 50 KB/min at the
  cap). Mirrored on `AdvancedTranscribeOptions` + preset JSON
  round-trip.
- `TranscriptionWord` grows an `alts` field (new
  `TranscriptionWordAlt` value class). Both
  `_mapWhisperSegments` (low-level whisper path) and
  `_mapSessionSegments` (unified session API) project the alts
  through to the engine boundary.
- `CrispasrEngine` and the isolate worker pool fire
  `session.setAltN` on every dispatch; `UnsupportedError` is
  swallowed so old dylibs still work (alts UI just stays
  hidden).
- **Transcript editor**: when a segment's words have alts, a
  Wrap of dotted-underline chips renders beneath the
  TextField — one chip per word with non-empty alts. Tap a
  chip → popup menu of "alt text + percent" descending by p;
  pick an entry → `replaceFirst` the original word in the
  working buffer. Editable text stays a plain TextField so
  cursor / undo / multi-line keep working. Off-by-default —
  empty alts collapse the suggestions block, leaving the
  dialog indistinguishable from the pre-feature version.
- Whisper sub-word BPE means a multi-token word like
  "kubectl" → ["kub","ect","l"] surfaces alts for the first
  content token ("kub") only. Full word-level enumeration
  would need a per-word token-tree expansion; deferred. The
  UI help string flags the caveat.
- l10n: EN + DE strings for the slider + the editor
  suggestions block.

Tests:

- `test/advanced_options_test.dart` — new "§5.1.11
  alt-token capture (altN)" group: default 0, `copyWith`
  preserves / mutates / clears, neighbouring sliders
  unaffected.
- `test/preset_service_test.dart` — `altN = 3` round-trips
  through the JSON cycle alongside the other non-default
  fields.
- CrispASR smoke test pins all nine new symbols against the
  freshly-built dylib.
- CrispASR live test
  (`flutter/crispasr/test/alt_tokens_live_test.dart`,
  tagged `live`) drives the full stack against
  `ggml-tiny.en.bin` + `samples/jfk.wav`. Asserts ≥1 word
  has alts, p ∈ [0, 1] descending, chosen token excluded
  from own alts, and `setAltN(0)` actually clears on
  re-decode. Whisper-tiny on JFK produces 22/22 words with
  runner-ups in practice ("Americans → America(4.85%),
  americ(3.84%), American(3.35%)"). macOS debug binary
  builds clean.

Post-merge polish (same release window):

- Alt-picker popup now renders probabilities at 1 decimal
  precision (`0.0%` / `3.4%`) instead of 0 decimals (which
  rounded most sub-1% alts to `0%`, useless for picking the
  real candidate out of noise).

Full suite: 376 pass / 16 skip / 0 fail. Deferred follow-ups
tracked in [PLAN.md → §5.8 `--alt N`](PLAN.md): beam-search alt
capture (different semantics), full word-level alt enumeration,
and a widget test for the alt-picker popover. The live-tagged
end-to-end test that was originally on this list shipped in
the same release.

### §5.1.10 — Audio enhancement before transcribe (May 2026)

Field-recording quality was bottlenecked by Whisper's noise
tolerance on HVAC / fan / keyboard backgrounds. A one-switch
RNNoise pre-step now denoises the loaded PCM before any backend
sees it. Off by default; toggled from Advanced Options.

Upstream (CrispASR 0.5.12):

- xiph/rnnoise v0.1 vendored under `src/rnnoise/` (BSD-3,
  ~425 KB GRU weights baked into `rnn_data.c` — no separate
  model download). Compiled into libcrispasr alongside
  grammar-parser, same "vendored C utility in src/" pattern.
- New `src/crispasr_enhance.{h,cpp}`: 16 kHz mono float32 in →
  miniaudio resampler up to 48 kHz → RNNoise 480-sample frame
  loop → miniaudio resampler back to 16 kHz → out. State is
  allocated and freed per call so worker isolates can invoke
  enhancement concurrently. Same "consume PCM → produce PCM"
  layering as `crispasr_lid.{h,cpp}`.
- New C-ABI `crispasr_enhance_audio_rnnoise(in_pcm, n_samples,
  out_pcm, out_cap)`. Returns 0 on success, -1 on invalid
  args, -2 on init / processing failure.
- Dart: top-level `enhanceAudioRnnoise(Float32List pcm)`
  returns a fresh same-length buffer. Pre-0.5.12 dylibs raise
  `UnsupportedError` so callers graceful-degrade.

CrisperWeaver:

- New `AdvancedOptions.enhanceAudio` (default false). Mirrored
  on `AdvancedTranscribeOptions` + preset JSON round-trip.
- UI: one `SwitchListTile` in Advanced Options ("Enhance
  audio (noise reduction)"), backend-agnostic — placed above
  the whisper-only fallback / decode-extras tiles so it's
  visible regardless of active backend. Localised en + de.
- Wired through both transcribe paths
  (`TranscriptionService.transcribeFile` + the parallel-pool
  dispatch in `_runJobOnPool`). Enhancement runs BEFORE the
  §5.8 window slice — order matters: slicing first would lose
  the boundary context RNNoise's ~10 ms look-ahead state
  needs. Both paths catch `UnsupportedError` on pre-0.5.12
  libcrispasr and fall through silently to the un-enhanced
  PCM so toggling the switch never breaks transcription.

Tests:

- `preset_service_test.dart` "non-default values round-trip"
  pins `enhanceAudio=true` through the JSON cycle.
- New `test/audio_enhancement_live_test.dart` (slow-tagged):
  synthetic 440 Hz tone + AWGN PCM, run through
  `enhanceAudioRnnoise` against the locally-built libcrispasr,
  assert (a) same length and (b) RMS drops ≥20%. Passes on the
  dev box; silently skipped when the dylib is absent or
  pre-0.5.12. Full suite: 372 pass / 14 skip / 0 fail.

### Whisper text-suppression + prompt-carry extras (May 2026)

Three more whisper-only `wparams` knobs the CLI exposes
(`--suppress-nst`, `--suppress-regex`, `--carry-initial-prompt`)
now have CrisperWeaver UI. Power-user controls; defaults
reproduce stock whisper.cpp.

Upstream (CrispASR 0.5.11):

- New crispasr_session fields whisper_suppress_nst (false),
  whisper_suppress_regex (""), whisper_carry_initial_prompt
  (false). Whisper transcribe dispatch writes them into
  wparams on every call; empty regex → nullptr to wparams
  (whisper's "no suppression" sentinel).
- New C-ABI crispasr_session_set_whisper_decode_extras(s,
  nst, regex, carry).
- Dart binding: CrispasrSession.setWhisperDecodeExtras({...})
  with named params; pre-0.5.11 dylibs raise UnsupportedError.

CrisperWeaver:

- New AdvancedOptions fields (whisper-only):
  suppressNonSpeechTokens, suppressTokensRegex,
  carryInitialPrompt. Mirrored on AdvancedTranscribeOptions +
  preset round-trip.
- UI: ExpansionTile "Whisper text suppression" in the
  Whisper-only section with 2 switches + 1 regex TextField.
- Wired through both the pool dispatch path AND the
  engine-direct path; pre-0.5.11 dylibs swallow
  UnsupportedError and run with stock defaults.

Tests: preset_service_test.dart round-trip extended to pin all
three fields against non-default values. Upstream symbol-pin
added to bindings_smoke_test.dart. Full suite: 372 pass / 14
skip / 0 fail.

### §5.1.6 v3.1 — Curated chat-model catalogue (May 2026)

The §5.1.6 v3 file-picker MVP shipped with no curation — users
had to know where to find a chat-capable GGUF and how to
choose one. This pass adds a curated list so the common case
becomes "pick a model from a dropdown, hit Download".

Model catalogue:

- 5 curated entries spanning small / medium / large size
  buckets and ≥ 2 architectures so users on every hardware tier
  can pick something that fits:
    * SmolLM2 360M Instruct (Q4_K_M, ~270 MB) — low-resource
    * Qwen2.5 0.5B Instruct (Q4_K_M, ~400 MB) — tight memory
    * Llama 3.2 1B Instruct (Q4_K_M, ~770 MB) — balanced
    * Qwen2.5 3B Instruct (Q4_K_M, ~2 GB) — recommended default
    * Llama 3.2 3B Instruct (Q4_K_M, ~2 GB) — strong alternative
- New ModelKind.chatLlm enum value; entries live in
  ModelService.crispasrBackendModels alongside the other
  non-Whisper GGUF families. backend tag = 'chat' so the
  existing download / progress UI plumbs through unchanged.
- URLs point at bartowski's GGUF repos — stable, active, and
  the de-facto-canonical small-model GGUF source.

Settings → Local LLM:

- New "Suggested chat models" section above the existing
  Browse… button. Each row shows display name + size + status
  icon (radio-button-checked when selected, check-circle when
  downloaded, cloud-download otherwise) and is tappable:
    * Downloaded → selects that path (commit on Save)
    * Not downloaded → opens Model Management deep-linked to
      the Chat-LLM filter

Model Management:

- New "Chat LLM" filter chip alongside ASR / TTS / Voices /
  Codecs / Post-processors. Routes `?kind=chatLlm` to
  pre-select on open via a new `initialKindFilter` param on
  the screen + a GoRoute branch in main.dart.

Localisation: 9 new strings × 2 locales (en + de).

Tests (test/chat_llm_catalogue_test.dart): 4 structural-pin
cases — ≥5 entries, populated required fields per row,
size-bucket coverage, family diversity. A regression that
drops or mistypes a row lands here before it ships.

Full suite: 372 pass / 14 skip / 0 fail (was 368).

### Whisper decoder-fallback thresholds (May 2026)

The four CLI flags `--entropy-thold`, `--logprob-thold`,
`--no-speech-thold`, `--temperature-inc` (which doubles as
`--no-fallback`) now exist as CrisperWeaver sliders. Tunable
parameters that control when the decoder retries at a higher
temperature (hard / noisy audio) or treats a segment as
silence; defaults reproduce whisper.cpp's stock behaviour, so
sliders left alone change nothing.

Upstream (CrispASR 0.5.10):

- New crispasr_session fields entropy_thold (2.4),
  logprob_thold (-1.0), no_speech_thold (0.6), temperature_inc
  (0.2). Whisper transcribe dispatch writes them into
  whisper_full_params on every call.
- New C-ABI crispasr_session_set_fallback_thresholds(s,
  entropy, logprob, nospeech, tinc). temperature_inc clamped
  to [0,1]; 0 disables the fallback loop entirely.
- Dart binding: CrispasrSession.setFallbackThresholds(...)
  with named params; pre-0.5.10 dylibs raise UnsupportedError.

CrisperWeaver:

- New AdvancedOptions fields (whisper-only): entropyThold,
  logprobThold, noSpeechThold, temperatureInc. Wired through
  AdvancedTranscribeOptions, preset JSON round-trip, both the
  pool dispatch path AND the engine-direct path.
- UI: ExpansionTile in the Whisper-only section with four
  sliders + a "Reset to defaults" link. Title subtitle flags
  when any override is active; temperature_inc shows
  "(fallback disabled)" when set to 0.

Tests: preset_service_test.dart round-trip extended to pin
all four thresholds. Symbol-presence pin added to upstream
bindings_smoke_test.dart. Full suite: 368 pass / 14 skip / 0
fail.

### §5.8 — Transcribe-window controls (`--offset-t / --duration`) (May 2026)

CrispASR CLI's `--offset-t` + `--duration` flags now exist in
CrisperWeaver. The user can pick a `[start, start+duration)`
slice of any audio file and get only that range transcribed —
useful for "minute 5..10 of this 2-hour podcast" without
round-tripping through the audio editor's trim flow.

- New AdvancedOptions fields `transcribeWindowStartSec` +
  `transcribeWindowDurationSec` (both seconds, both default 0
  = no window).
- UI: ExpansionTile in AdvancedOptions widget — two
  decimal-keyboard TextField widgets for start + duration.
  Auto-expands when a window is set. Backend-agnostic (works
  with every engine, since the slice happens at PCM level
  before dispatch).
- New static helper `CrispASREngine.sliceTranscribeWindow(buf,
  sr, startSec, durationSec)` — bounds-safe, sample-rate
  aware, identity short-circuit on no-window.
- Wiring: both the serial `TranscriptionService.transcribeFile`
  path AND the parallel pool dispatch in
  `transcription_screen.dart` slice the PCM, then shift the
  returned segment timestamps by the window start so they're
  absolute in file time. The streaming `onSegment` callback is
  wrapped on both paths so checkpointed segments also come
  back absolute.
- A user-set window overrides any resume offset (the explicit
  pick wins over a checkpoint).
- Preset round-trip persists the two new fields so "transcribe
  the intro" presets survive app restart.

Localisation: 8 new strings × 2 locales.

Tests: 10 new sliceTranscribeWindow cases + a
shiftSegmentForResume re-pin (offset arithmetic + zero-offset
identity short-circuit). Full suite: 368 pass / 14 skip / 0 fail
(was 358).

### §5.8 — GBNF grammar-constrained sampling (May 2026)

Closes the long-deferred §5.8 plan item. Whisper transcripts
can now be forced into a structured shape — JSON, SKU patterns,
phone numbers, or any other context-free grammar the user can
write in GBNF.

Upstream (CrispASR 0.5.9):

- `examples/grammar-parser.{h,cpp}` promoted to `src/` so
  libcrispasr links the GBNF parser.
- New C ABI `crispasr_session_set_grammar_text(session,
  gbnf_text, root_rule, penalty)` parses the source once at
  setter time, stores the rule graph on the session, and the
  whisper transcribe dispatch threads it through
  `wparams.grammar_rules` / `n_grammar_rules` / `i_start_rule`
  / `grammar_penalty`. Auto-switches to beam search
  (grammar-constrained sampling requires beam ≥ 2); beam_size
  defaults to 5 when the user left it at default 1.
- Dart binding: `CrispasrSession.setGrammar(text, rootRule:,
  penalty:)` plus a convenience `clearGrammar()`. Invalid
  GBNF / unknown root rules raise ArgumentError; pre-0.5.9
  dylibs raise UnsupportedError for graceful fallback.

CrisperWeaver:

- New AdvancedOptions fields — `grammarText`, `grammarRootRule`,
  `grammarPenalty` — surfaced as an ExpansionTile in the
  Whisper-only section of the Advanced Options widget. Multi-
  line monospace TextField for the GBNF source plus sliders
  for the root-rule name + penalty value (0..200, slider
  divisions every 5).
- Transcription worker + worker pool dispatch fire
  `session.setGrammar(text, rootRule, penalty)` on every
  transcribe call (empty text clears any prior grammar from
  the session). Invalid GBNF surfaces as a worker error reply
  so the user gets an actionable snackbar.
- Preset round-trip persists the new fields so a "force JSON"
  preset survives app restart.

Tests: +1 round-trip case in preset_service_test.dart pins the
grammar fields, plus 3 upstream Dart smoke tests in
`CrispASR/flutter/crispasr/test/grammar_test.dart` exercising
parse / re-set / clear / invalid-source / unknown-root paths
against a real libcrispasr + ggml-tiny.en.bin. Full
CrisperWeaver suite: 358 pass / 14 skip.

### Match CrispASR upstream — LID picker Firered + Ecapa (May 2026)

Closes the LID picker gap from the previous TTS-sampling pass.
CrispASR 0.5.8 (the upstream bump that ships in parallel)
extends `LidMethod` from `{whisper, silero}` to all four
methods the C side has supported since 0.4.6 — `firered` and
`ecapa`. CrisperWeaver now exposes the full set in the
Advanced Options LID picker, registers their canonical GGUFs
in the model catalogue, and routes LidService's filename
detection accordingly.

- `LidMethod.firered` (FireRed-LID, 120 languages, ~300 MB
  GGUF — highest language coverage)
- `LidMethod.ecapa` (ECAPA-TDNN, 107 languages, ~42 MB GGUF —
  strong on noisy / accented speech)
- Model registry gets new entries: `ecapa-lid-107-f16`,
  `firered-lid-f16`, both routed to the canonical
  `huggingface.co/cstr/<name>-GGUF` repos.
- `LidService.methodForFilename` is now a public static helper
  that maps any downloaded LID GGUF basename to the right
  `LidMethod`. Catches mismatches between the user's picker
  selection and what's actually on disk (the C side returns
  rc=-2 on mismatch, so the file is the source of truth).
- 7 new unit tests pin every basename → method mapping the
  registry can produce (legacy `silero-lang95-*`, canonical
  `silero-lid-*` / `firered-lid-*` / `ecapa-lid-*`, every
  whisper variant, plus the regression guard that
  `LidMethod.values.length == 4` and indexes line up with the
  C-side `CrispasrLidMethod` enum).

Total suite: 358 pass / 14 skip.

### Match CrispASR upstream — TTS sampling + phoneme cache (May 2026)

Audited the 85-surface CrispASR Dart binding against
CrisperWeaver's actual call sites and closed the remaining
user-impacting gaps:

- **Three chatterbox sampling controls** added to the Synthesize
  screen's Advanced section — `min-p`, `repetition penalty`,
  `max speech tokens`. Previously the service accepted these
  via `TtsService.synthesize(...)` but the UI never sourced
  them, so users couldn't tune chatterbox beyond the four
  knobs already on screen (temperature / top-p / CFG /
  exaggeration).
- **`Clear phoneme cache` button** in the same Advanced section
  routes to a new `TtsService.clearPhonemeCache()` →
  `CrispasrSession.clearPhonemeCache()`. Kokoro builds an
  unbounded per-speaker phoneme cache over a long session;
  this gives long-running daemon use-cases an explicit memory
  knob. No-op on non-kokoro backends (the upstream session
  setter silently drops).

Wired-but-already-shipping surfaces: 60 of 85 upstream calls.
Genuinely upstream-pending: GBNF grammar-constrained sampling
(§5.8), audio enhancement (§5.1.10) — both since shipped.
TitaNet / SpeakerDB also shipped via §5.8.1 in Unreleased.
`LidMethod.firered` / `.ecapa` are reachable through the
integer-typed `CrispasrSession.detectLanguage`, but the
enum-typed top-level `detectLanguagePcm` still only covers
`whisper` + `silero` — extending CrisperWeaver's picker waits
on an upstream enum bump.

Tests: new `test/crispasr_live_test.dart` — tag-gated under
`slow`, runs an end-to-end decode + Whisper-tiny.en transcribe
of `test/jfk-2s.wav` against the real libcrispasr dylib. Skips
silently when the model file isn't on disk so CI stays green.
Full suite: 351 pass / 14 skip / 0 fail.



## v0.5.0 — 2026-05-12

Post-v0.4.1 sweep — closes Tier A + B + most of Tier C of the
§5.1 competitor-gap audit, ships the §5.1.6 v3 local on-device
LLM cleanup + summarisation that was gated on upstream CrispASR
work, adds a four-layer responsive-UI pass for phones / narrow
windows + Settings sub-screens on mobile, fills out platform-
native share / receive on every OS (tiered transcript shares,
multi-file inbound, transcript-file intake, Linux .desktop,
iOS Share Extension template, macOS Open-With + Services menu),
plus an assortment of macOS Tahoe / Swift 6 fixes. 17 commits,
~16k lines added.

Full per-section write-ups follow.

### §5.1 competitor-gap features — Tier A + B + most of C closed (May 2026)

The post-v0.4.1 sweep. Audited against the common feature set of
comparable local GUI tools (whisper-based desktop apps for macOS /
Linux / Windows) plus the cloud meeting-transcription category.
Twelve features land in this batch; full write-ups in
[HISTORY.md](HISTORY.md#post-v041-51-competitor-gap-sweep--may-2026).

- **System audio capture** (§5.1.1) — "Transcribe what's playing
  in Zoom / YouTube / any app." Per-platform native paths:
  ScreenCaptureKit on macOS 13+, `parec` on Linux, ffmpeg-WASAPI
  loopback on Windows, MediaProjection on Android 10+. iOS is
  permanently unsupported by Apple's sandbox.
- **Custom vocabulary / dictionary boost** (§5.1.2) — Persistent
  chip list in Advanced Options. Routed per-backend-class via
  `initial_prompt` (whisper / moonshine), `setAsk` prefix (audio-
  LLM backends), or no-op (CTC-style, with explanatory helper
  text).
- **Inline transcript editing + history persistence** (§5.1.3) —
  Long-press a segment → edit dialog. Edits update AppState AND
  the on-disk history JSON so they survive a reload.
- **History search** (§5.1.4) — Substring filter on title +
  transcript with yellow-highlighted matches and auto-expand of
  matching entries.
- **Audio waveform editor + bidirectional transcript sync**
  (§5.1.5) — Dedicated `EditAudioScreen` with trim / cut middle
  / split into chapters + an optional collapsible transcript pane
  on the same screen. Tap segment → seek; long-press segment →
  Select / Trim to / Mark for split; tap waveform → matching
  segment highlights. Entry points on the transcript output's
  segment long-press menu. Pure-Dart, no FFmpeg.
- **"Tidy transcript" deterministic pass** (§5.1.6 v1) — Pure-
  Dart cleanup: remove fillers (per-language + custom), collapse
  repeats, fix punctuation, capitalise sentence starts, optional
  annotation-tag strip. Before/after preview of the first three
  segments in the dialog.
- **BYOK cloud LLM cleanup pass** (§5.1.6 v2) — Optional opt-in
  LLM pass against any OpenAI-compatible endpoint (OpenAI,
  Anthropic via proxy, OpenRouter, Groq, Cerebras, Together,
  local llama-server). Key stays on device.
- **Local on-device LLM cleanup + summarisation** (§5.1.6 v3) —
  Point at a GGUF chat model on disk and every Tidy / Summarize
  pass routes through it via libcrispasr's chat ABI. No network,
  no API key, no per-token billing. Metal / CUDA acceleration
  used when available; one-time model-load amortised across
  every pass in the session via a dedicated worker isolate. A
  three-mode selector (Off / Cloud / Local) replaces the
  cloud-only LLM-pass checkbox; defaults respect the
  user's persisted preference and configured paths.
- **Templates / presets** (§5.1.7) — Save current `(backend,
  modelId, language, AdvancedOptions)` tuple as a named preset.
  One-tap Apply restores all four atomically.
- **Meeting-style summarisation** (§5.1.8) — Action Items / Key
  Topics / Decisions sections via structured Markdown over the
  same cloud-LLM endpoint as the cleanup pass.
- **Global hotkey for push-to-transcribe** (§5.1.11) — Desktop-
  only system shortcut. Push-to-talk OR toggle modes. Combo
  parser handles modifier aliases (cmd / command / win / super
  → meta; ctrl → control; option → alt).
- **Voice clone wizard** (§5.1.12) — 3-step guided flow on top of
  the existing chatterbox / indextts / qwen3-tts-base / vibevoice
  runtime cloning. Capture (10s mic OR file pick) → reference
  text → hand-off to Synthesize with both pre-populated.
- **Whisper subtitle formatting** (§5.8) — Two new Advanced
  Options rows: tokens-per-segment cap + split-on-word-boundary.
  Yields SRT-friendly short subtitle lines.

### Responsive UI — phone / narrow-window fit (May 2026)

The app was designed-for-desktop primary and had no first-class
phone story. This pass adds four layers of mobile-fit polish
without rewriting the existing layouts:

- **Responsive dialog widths** — every `showDialog` call clamps
  to `min(designedWidth, screenWidth - 32)` via a new
  `responsiveDialogWidth(context)` helper. Same for height where
  bounded. Dialogs no longer overflow on 360-wide phones; the
  Tidy / Summarize / Local LLM / Cloud LLM / Hotkey / Presets /
  inline-edit / rename-speaker dialogs all now adapt. Bonus:
  optional fullscreen-on-phone `showResponsiveDialog` helper for
  future dialogs that want to feel native on mobile.
- **AppBar tightening** — home screen drops the tagline subtitle
  below 600 px width; below 480 px it keeps only Settings as a
  visible action and folds History / Models / Synthesize /
  Translate / Presets into a `PopupMenuButton` overflow.
- **`AdaptiveSegmentedButton<T>`** — drop-in replacement for
  `SegmentedButton` that falls back to `DropdownButtonFormField`
  on compact widths. Applied to the new Tidy + Summarize
  three-mode selectors so localised long labels don't overflow.
- **Tabs in the main screen on phones** — below 600 px the
  transcription screen renders a 3-tab `TabBar` (Input / Run /
  Output) instead of the stacked-column layout, so each pane
  gets the full viewport one at a time. Tabs default to Output
  when the transcript already has segments, Input otherwise; the
  existing wide / extra-wide reflows (≥700, ≥1300) are
  untouched.
- **Bottom `NavigationBar` on phones** — Home / History /
  Settings get a Material 3 NavigationBar at the bottom when
  width < 480. Uses `context.go()` so bouncing between primary
  destinations doesn't pile up the back stack. Secondary
  destinations (Models / Synthesize / Translate / Logs / About)
  stay reachable via the AppBar overflow menu.

### Responsive UI — Settings sub-screens on mobile (May 2026)

Follow-up to the responsive-UI pass above: the Cloud LLM /
Local LLM / Hotkey *dialogs* now convert to pushable sub-screens
on phone-width viewports, matching iOS / Android Settings
conventions. Wide layouts still see the original dialogs.

- Three new form widgets — `CloudLlmSettingsForm`,
  `LocalLlmSettingsForm`, `HotkeySettingsForm` — own the
  TextEditingControllers + slider state and expose `save()` /
  `clear()` via a GlobalKey<…FormState>. Both the wide-layout
  AlertDialog and the new phone-form Scaffold consume the same
  form widget, so behaviour stays identical across surfaces.
- Three new sub-screen routes: `/settings/cloud-llm`,
  `/settings/local-llm`, `/settings/hotkey`. Save/Clear actions
  live in the AppBar; the leading back button discards in-flight
  edits (matches the dialogs' Cancel).
- Each Settings ListTile branches on `isPhoneWidth(context)` —
  push the route on phones, show the dialog on wide. The branch
  is the only call-site change; the rest of the refactor is
  pure widget-extraction.
- The Hotkey form keeps its commit-time validation: an invalid
  combo while enabled returns a `HotkeySaveResult.invalidCombo`
  instead of silently committing. Both containers surface the
  rejection as a SnackBar.

8 new widget tests cover the form-widget contracts
(value rendering, save-time trimming, clear-and-fire, hotkey
validation gating). Full test suite: 333 pass (was 325, +8).

### Platform-native share / receive (May 2026)

Filled out the OS-level send/receive surfaces so CrisperWeaver
talks to neighbouring apps on every platform.

**Outbound — share transcripts to other apps:**

- New **Share as Markdown** entry in the transcript Share menu
  — bullet-list with `HH:MM:SS → HH:MM:SS` timestamps and bold
  speaker labels, ready to paste into Slack / Discord / Notion /
  GitHub. Adds `TranscriptFormat.md` to the export enum.
- New **Share audio + transcript** entry — sends the source
  audio AND an SRT transcript as a two-file bundle in a single
  share. Wraps both files with `SharePlus.share(files: [...])`.
- Pre-existing **Save as SRT / VTT / TXT / JSON / CSV / LRC / WTS**
  entries already auto-open the share sheet after saving — no
  change to those paths.

**Inbound — receive shares into CrisperWeaver:**

- **Multi-file share intake** — `ShareIntakeService` no longer
  drops everything past the first file. First usable audio goes
  to the selected-source slot, subsequent audio files enqueue
  into the batch queue. Closes a silent data-loss bug for
  Android `SEND_MULTIPLE` and macOS multi-file drag-drop.
- **Transcript-file intake** — sharing a `.srt` or `.vtt` (or
  opening one with CrisperWeaver) parses it into segments and
  loads "review mode". New `TranscriptParsers` module handles
  SubRip + WebVTT grammars (CRLF tolerant, optional cue
  identifiers, NOTE/STYLE/REGION skipping, speaker-prefix
  extraction). 13 unit tests pin the grammar handling.
- **Android intent-filters** for `application/x-subrip` and
  `text/vtt` on both VIEW (Open With) and SEND (Share Sheet)
  intents. `.txt` is intentionally left off the VIEW filter to
  avoid CrisperWeaver appearing for every random plaintext file.
- **iOS / macOS UTI declarations** — proper exported UTIs for
  `com.crispstrobe.crisperweaver.srt` (conforms to
  public.plain-text, extension `srt`, MIME
  `application/x-subrip` + `text/srt`) and `…vtt` (extension
  `vtt`, MIME `text/vtt`). A new "Subtitle Files" entry in
  `CFBundleDocumentTypes` references those UTIs so Finder /
  Files Open With surfaces CrisperWeaver for them.

**Desktop integration:**

- **Linux `.desktop` file** — `linux/com.crispstrobe.crisperweaver.desktop`
  with audio + subtitle MimeTypes, `Exec=crisper_weaver %F` so
  `Open With CrisperWeaver` passes files as positional argv.
- **Argv-based intake on desktop** — `main()` now takes
  `List<String> args` and forwards them to
  `ShareIntakeService.acceptPaths` after the provider graph is
  up. Audio + transcript triage happens in the same code path
  as Android / iOS shares.

**iOS Share Extension (template files only, target wiring is
the tracked follow-up):**

- Swift / Info.plist / entitlements template under
  `ios/ShareExtension/` plus the matching
  `ios/Runner/Runner.entitlements` with the
  `group.com.crispstrobe.crisperweaver` App Group identifier.
- Step-by-step Xcode target-creation guide in
  `docs/ios-share-extension-setup.md`. Once the target is wired
  in `Runner.xcodeproj`, CrisperWeaver appears in iOS's system
  Share Sheet from Voice Memos / Mail / Files etc. with no
  further code changes.

Tracked PLAN.md follow-ups: macOS NSServices / Open-With wiring
(needs an NSPasteboard → MethodChannel bridge in
`AppDelegate.swift`), Windows file association (installer /
MSIX work), and the iOS Share Extension Xcode target setup
itself.

Tests: +13 transcript-parser tests. Full suite: 346 pass (was
333, +13).

### macOS Open-With bridge (May 2026)

Finishing the macOS half of the share/receive story:

- New `macos/Runner/OpenWithReceiver.swift` — singleton that
  buffers incoming file paths until the Flutter side binds the
  MethodChannel, then live-forwards subsequent opens.
- `AppDelegate.swift` overrides `application(_:open:)` plus the
  legacy `openFile:` / `openFiles:` hooks so every macOS
  delegate-method entry point funnels into the receiver.
  Finder "Open With", `open foo.wav` from the terminal, and
  drag-onto-dock-icon all land here.
- `MainFlutterWindow.awakeFromNib` binds the channel
  (`crisperweaver/open_with`) alongside the existing system-
  audio-capture channel.
- New `DesktopOpenWithBridge` Dart service drains the Swift
  buffer (`consumePending`) at boot and listens for live
  `onFiles` calls afterwards; both flows feed
  `ShareIntakeService.acceptPaths` so the existing audio /
  transcript triage runs unchanged.
- `OpenWithReceiver.swift` wired into `Runner.xcodeproj`'s
  Sources build phase via four `project.pbxproj` edits
  (PBXBuildFile + PBXFileReference + Runner group + Sources
  phase), matching the existing `SystemAudioCapture.swift`
  pattern.

Pre-flight: 3 hermetic channel-contract tests via
`TestDefaultBinaryMessengerBinding`. Total: 349 tests pass (was
346, +3).

### macOS Services menu (May 2026)

Finishing macOS-share polish: right-click any audio or
SRT / VTT file in Finder (or any other app that respects the
Services menu) and **Services → Transcribe with CrisperWeaver**
now does the obvious thing — launches CrisperWeaver if needed,
brings it forward, and lands the file in the transcription pane.

- `Info.plist` declares an `NSServices` entry with
  `NSSendFileTypes = [public.audio, com.crispstrobe.crisperweaver.srt,
  com.crispstrobe.crisperweaver.vtt]`. macOS uses these UTIs
  to decide which files the menu item appears for.
- `AppDelegate.transcribeAudio(_:userData:error:)` reads file
  URLs off `NSPasteboard`, feeds them to the same
  `OpenWithReceiver.shared.enqueue(urls:)` the Open-With
  bridge uses, then `NSApp.activate()`s so the user sees the
  file land.
- `applicationDidFinishLaunching` registers the AppDelegate
  as `NSApp.servicesProvider` and calls
  `NSUpdateDynamicServices()` to nudge macOS into refreshing
  the Services menu so fresh installs / version bumps surface
  the entry without a logout.

### Performance — Metal cold start (CrispASR upstream)

* **38× faster ASR / TTS cold starts** via the persistent
  `MTLBinaryArchive` pipeline cache (CrispASR commit
  [`2665b1e5`](https://github.com/CrispStrobe/CrispASR/commit/2665b1e5)).
  Compiled Metal compute pipeline state objects (PSOs) now serialise
  to `~/Library/Caches/ggml-metal/<device>.archive` (~683 KB per
  device) on shutdown and reload on the next launch. Real-machine
  benchmark (M1 Max, whisper-tiny + jfk.mp3): cold 22.5 s → second
  warm run 0.6 s. Every CrispASR consumer benefits: CLI,
  CrisperWeaver, test sweep, OpenAI server. Override path via
  `GGML_METAL_PIPELINE_CACHE`; opt out via
  `GGML_METAL_PIPELINE_CACHE_DISABLE=1`.

## v0.4.1 — 2026-05-10

Conservative patch over v0.4.0 covering six rounds of CrispASR-0.6.2
parity work. Pairs with [`CrispASR v0.6.2`][crispasr-062]. No
breaking app-side changes; new screens are additive, every new
toggle defaults to "behaves like v0.4.0".

[crispasr-062]: https://github.com/CrispStrobe/CrispASR/releases/tag/v0.6.2

### Highlights

* **3 new screens** — Translate (text-to-text via M2M-100 / WMT21 /
  MADLAD-400), Voice Bake (Chatterbox WAV-to-GGUF via the
  bake-chatterbox-voice-from-wav.py script), Local HTTP server
  (OpenAI-compatible on 127.0.0.1:8765).
* **4 new ASR backends + 4 new TTS backends in the model catalog**:
  gemma4-e2b (140 langs), omniasr-llm-unlimited (streaming),
  granite-speech 4.1 family, chatterbox / kartoffelbox / indextts /
  qwen3-tts-voicedesign / vibevoice-1.5b. Plus pyannote-v3-seg,
  silero-LID, FireRed/MarbleNet/Whisper-VAD GGUFs, fullstop-punc,
  m2m100-418m / 1.2b, WMT21 (both directions), MADLAD-400.
* **Streaming for non-Whisper backends** — kyutai-stt,
  moonshine-streaming, voxtral4b live mic transcription via the
  new session-level openStream binding.
* **Custom-WAV picker on Synthesize** with reference-transcript
  field for runtime cloning (qwen3-tts Base, vibevoice-1.5b,
  indextts, chatterbox without a baked GGUF).
* **Advanced Options blossomed**: VAD picker (silero / firered /
  marblenet / whisper-vad-encdec) + threshold + min-speech +
  min-silence + speech-pad sliders, diarisation method picker
  (vad-turns / pyannote / energy / xcorr), LID method picker
  (whisper / silero), tdrz toggle, token-timestamps toggle,
  punctuation-family picker, Performance section (ASR-on-GPU,
  flash-attn, n_gpu_layers, n_threads, LID-on-GPU).
* **Synthesize advanced section**: ref-text / instruct fields,
  trim-silence toggle, speed slider (0.25× – 4.00×, drives both
  client-side resample AND the new kokoro length_scale), 5
  sampling sliders (temperature, diffusion-steps, CFG weight,
  exaggeration, top-p).
* **3 new export formats**: CSV (RFC-4180), LRC (lyrics, mm:ss.cs),
  WTS (Whisper Text Segments debug).

### CrispASR 0.6 parity sweep — round 6 (May 2026)
- **PLAN #89 — flash_attn fields on every backend's
  `*_context_params`** — mechanical struct-field plumbing across
  the 12 backends with `use_gpu`. The runtime toggle now reaches
  per-backend init code; per-backend kernel wiring (PLAN #86) lands
  incrementally.
- **PLAN #88 — kokoro length-scale + vibevoice diffusion-step
  runtime knobs.** Kokoro has a new `length_scale` field on
  `kokoro_context_params` that multiplies the duration-predictor
  output before banker's-rounding; CrisperWeaver's existing TTS
  *speed* slider now drives BOTH the C-side scalar (clean stretch
  via the duration model) AND the client-side resample (fallback
  on every other TTS backend). VibeVoice's pre-existing `tts_steps`
  field gets a runtime setter, routed through the unified
  `crispasr_session_set_tts_steps` so the existing
  *Diffusion steps* slider works on it as well as chatterbox.

### CrispASR 0.6 parity sweep — round 5 (May 2026)
- **Flash-attention + n_gpu_layers** — bumped the open-params struct
  to v2 with `flash_attn` (bool, default true) and `n_gpu_layers`
  (int, default -1 = max). Whisper now honours flash-attn natively;
  other backends accept the toggle and will branch on it as the
  per-backend kernel work lands. Surfaced as the *ASR flash-attention*
  toggle and *GPU layers (LLM)* slider in the Performance section.
- **Qwen3-TTS sampling temperature is now runtime-tunable** — was
  hardcoded `temperature=0.9f` inside the code-predictor's top-k
  sampler; now reads `c->params.temperature` (still defaulting to
  0.9 when unset). New `qwen3_tts_set_temperature` runtime setter,
  routed through `crispasr_session_set_temperature` so the existing
  Synthesize-screen Temperature slider Just Works on qwen3-tts now
  too.
- **Local OpenAI-compatible HTTP server** — toggle in Settings →
  *Local HTTP server* spins up a `shelf` HTTP server on
  `127.0.0.1:8765` exposing `POST /v1/audio/transcriptions`
  (multipart, OpenAI-shaped JSON / text / SRT / VTT response),
  `POST /v1/audio/speech` (JSON body → 24 kHz mono WAV bytes),
  `POST /v1/translations` (JSON body → translated text), and `GET
  /health`. External scripts that previously hit
  `https://api.openai.com/v1/audio/...` now work unchanged when
  pointed at the local URL. No auth — bound to loopback only.

### CrispASR 0.6 parity sweep — round 4 (May 2026)
- **ASR-side GPU toggle is now a runtime knob.** New
  `crispasr_session_open_with_params` C-ABI on the CrispASR side
  takes a versioned struct (`abi_version`, `n_threads`, `use_gpu`,
  `verbosity`) and threads `use_gpu` into every backend whose
  context_params accepts it (parakeet, canary, qwen3, cohere,
  granite, voxtral, vibevoice, qwen3-tts, orpheus, kokoro,
  chatterbox). Surfaced as the *ASR on GPU* toggle in the
  Performance section of Advanced Options. Takes effect on the
  next model load (not retroactive to the currently-open session).
* **Chatterbox sampling knobs** — diffusion-step count, top-p,
  min-p, repetition penalty, CFG weight, exaggeration, max speech
  tokens. New runtime setters in `chatterbox.cpp` mutate the
  context's `params` struct between synth calls. Exposed via new
  per-knob session setters (`crispasr_session_set_tts_steps`,
  `_set_top_p`, `_set_min_p`, `_set_repetition_penalty`,
  `_set_cfg_weight`, `_set_exaggeration`,
  `_set_max_speech_tokens`) on the C-ABI, mapped through the Dart
  binding (`setTtsSteps`, `setTopP`, …) and surfaced on the
  Synthesize screen as labelled sliders.
* **Orpheus runtime temperature** — new `orpheus_set_temperature`
  C export; `crispasr_session_set_temperature` now routes to
  orpheus and chatterbox in addition to canary / cohere /
  parakeet / moonshine, so the existing temperature slider works
  on those TTS backends too without UI changes.

### CrispASR 0.6 parity sweep — round 3 (May 2026)
- **Custom voice (WAV reference)** card on the *Synthesize* screen.
  Pick a WAV from disk for runtime cloning on backends that take a
  reference (qwen3-tts Base, vibevoice-1.5b, indextts, chatterbox).
  Pairs with the Reference transcript field; overrides the catalog
  voicepack dropdown when set.
- **Streaming for non-Whisper backends.** New `openStream()` on
  `CrispasrSession` in the Dart binding wraps
  `crispasr_session_stream_open`; the engine's `transcribeStream`
  now picks the right path automatically. Live mic transcription
  works end-to-end on whisper / kyutai-stt / moonshine-streaming /
  voxtral4b. The "Stream" toggle on the recorder surfaces a
  backend-specific error when the active model has no streaming
  arm.
- **Voice baking flow.** New *Bake voice (WAV → GGUF)* screen
  (launched from the cake icon in the *Synthesize* app-bar) drives
  CrispASR's `models/bake-chatterbox-voice-from-wav.py` via
  `Process.start`. Pick a WAV, set output filename, optional
  Python interpreter / script-path overrides, run. Stdout + stderr
  stream into a live tail panel + the in-app log viewer; the
  resulting GGUF is dropped into the user's models dir so it
  shows up in the voicepack picker on the next open.
- Desktop-only — mobile sandboxes have no Python runtime, so the
  Bake button hides itself on iOS / Android.

### CrispASR 0.6 parity sweep — round 2 (May 2026)
- New **Translate** screen — text-to-text translation via M2M-100,
  WMT21 Dense (en→X **and** X→en, both checkpoints catalogued), and
  MADLAD-400 (419 languages). Source/target dropdowns with a swap
  button, max-tokens slider, copy-to-clipboard. New
  `TextTranslationService` + `translateText()` exposed on
  `CrispasrSession` in the Dart binding.
- LID accelerator knobs in Advanced Options — toggle GPU offload,
  flash-attention, and CPU thread count for the
  `crispasr_detect_language_pcm` call. Threaded through
  `LidService` + `AdvancedTranscribeOptions`.
- New `ModelKind.translate` filter so the Model Manager can group
  text translation models away from the speech-translation backends
  (canary, voxtral, …).
- CrispASR README + cli docs corrected — WMT21 ships **two** Dense
  24-wide checkpoints (`en-x` and `x-en`), not one en→X-only.

### CrispASR 0.6 parity sweep — round 1 (May 2026)
- 4 new ASR backends in the catalog: **gemma4-e2b** (USM Conformer +
  Gemma-4, 140+ languages), **omniasr-llm-unlimited** (streaming, 15 s
  protocol), **granite-speech-4.1** (2B, 4.1+, 4.1-nar variants),
  rounding out the Granite Speech family.
- 4 new TTS backends: **chatterbox** (T3 AR + S3Gen flow-matching),
  **kartoffelbox** (Chatterbox German finetune), **indextts** (GPT-2 AR
  + BigVGAN, zero-shot WAV cloning), **qwen3-tts-voicedesign** (natural-
  language voice description via the new `synthInstruct` field),
  **vibevoice-1.5b** (runtime WAV cloning via `setVoice(wav, refText:)`).
- New diarisation method picker — pick between vad-turns (mono,
  bundled), pyannote (ML, downloadable GGUF), stereo energy, stereo
  cross-correlation. Pyannote v3 segmentation GGUF added to the model
  catalog.
- New LID method picker — Silero 95-langs joins the Whisper-encoder
  default. The new `silero-lang95-v1-f16.gguf` GGUF is downloadable
  through Model Management.
- VAD picker + tuning sliders — choose between Silero (bundled),
  FireRedVAD (F1 97.57%), MarbleNet, Whisper-VAD-EncDec. Threshold,
  min-speech-ms, min-silence-ms, speech-pad-ms exposed as sliders
  when VAD is enabled.
- Multilingual punctuation: new fullstop-punc post-processor
  (EN/DE/FR/IT) alongside the existing FireRedPunc (ZH+EN). Toggle
  in Advanced Options chooses which family runs.
- Whisper-only: tinydiarize speaker-turn markers (`tdrz`) and token-
  level DTW timestamps now available in Advanced Options.
- Three new export formats — **CSV** (segment-level, RFC-4180 quoted),
  **LRC** (lyrics, mm:ss.cs), **WTS** (Whisper Text Segments debug
  format).
- TTS knobs: trim-silence (post-process under -72 dBFS), speed slider
  (0.25×–4.00×, nearest-neighbour resample), reference-transcript
  field for runtime voice cloning, natural-language voice-design
  prompt for qwen3-tts VoiceDesign.
- Capability sets in `AdvancedOptions` extended — Granite 4.1 family,
  GLM-ASR, Gemma4, OmniASR LLM all now eligible for source/target
  language hints, audio Q&A, and the temperature slider.

**Decoder controls**
- Best-of-N slider in Advanced Options (1–10, always visible).
  Whisper consumes via `wparams.greedy.best_of`; other backends
  loop N decodes externally and pick the highest-mean-confidence
  transcript. Cost is N× per-call decode time.
- Decoder temperature slider for sampling-capable backends
  (canary, cohere, parakeet, moonshine). 0.0 = greedy / reproducible
  (default); >0.0 = stochastic sampling, useful when greedy
  hallucinates a repetition.
- Source-language override paired with the existing target-language
  picker; lets you pin the source for translation when whisper's
  autodetect is unreliable on noisy audio.

**Quality of life**
- Storage breakdown screen (Settings → Storage breakdown) — per-
  backend disk usage with one-click "delete all of X" action.
- Mic-streaming live transcript on the recorder (Whisper-only) —
  toggle the "Stream" switch and partial transcripts appear in the
  output card while you talk.
- Real-time partial display during long file transcribe — Whisper
  files >60 s are split into 30 s chunks; each chunk's segments
  stream into the UI as they finish instead of all arriving at the
  end.
- Speaker rename — tap a speaker chip in the output to override the
  diariser's auto-assigned label. The mapping persists into history
  JSON and survives restarts.

**iOS**
- v0.4.0 was the first release to ship a real iOS IPA. The unsigned
  IPA (15 MB) bundles `crispasr.framework` with all 30 backends
  statically linked into a single dynamic library; the previous
  v0.3.0 IPA was an empty Flutter shell with no native backend.
- `audio_session` configured at startup with the `speech()` preset
  so playback / recording / silent-mode interact correctly.
- `PrivacyInfo.xcprivacy` covering NSUserDefaults, FileTimestamp,
  DiskSpace, SystemBootTime — the four required-reason API
  categories the app touches via shared_preferences, path_provider,
  dart:io, and DateTime.now(). Required for App Store submission
  since May 2024.
- CoreML companion download (`.mlmodelc` next to whisper GGUFs)
  now also fires on iOS — every modern iPhone has the Apple
  Neural Engine, so the .mlmodelc is just as load-bearing on iOS
  as it has been on macOS.

**i18n**
- 40+ user-facing strings moved from hardcoded English to
  `AppLocalizations`. EN+DE entries in lockstep, guarded by a new
  `arb_consistency_test` that fails CI if a key is added to one
  locale and not the other or if ICU placeholders ({count}, {size},
  …) drift between translations.

**Tests**
- Default suite: 6 → 87 tests. Coverage for HistoryEntry round-
  trip + back-compat, AppStateNotifier full lifecycle, AdvancedOptions
  copyWith + capability sets, storage formatters + grouping +
  deletion, subtitle export (SRT/VTT/JSON formatters + content),
  chunked-whisper segment offset shifter, HistoryService persistence,
  SettingsService SharedPreferences round-trip, ARB consistency.
- Default `flutter test` runs in ~5 s; opt-in heavy e2e backend
  roundtrips stay env-var-gated.

**CI**
- macOS + Linux CI jobs aligned to the same build scripts devs run
  locally (`scripts/build_macos.sh`, `scripts/build_linux.sh`).
  Earlier hand-rolled `cmake … --target crispasr-lib` invocations
  diverged from the local scripts in two load-bearing ways:
  (a) skipped `-DCRISPASR_BUILD_TESTS=OFF` so cmake configure pulled
  in unrelated source trees and tripped on the OBJCXX language
  requirement that comes in via the CoreML wrappers; (b) only built
  the `crispasr-lib` target without first building the 30 per-backend
  STATIC archives, so the resulting libwhisper.dylib was missing
  every backend except whisper at runtime.
- iOS release job updated to call `scripts/build_ios_xcframework.sh`
  + `scripts/wire_ios_xcframework.rb` before `flutter build ios`,
  so the released IPA contains the native backends.

## v0.4.0 — 2026-05-03

- iOS xcframework wiring (the launch blocker) — Runner.app now
  embeds `crispasr.framework` (4.8 MB stripped, 322+ exported
  symbols), `install_name = @rpath/crispasr.framework/crispasr`
  matches the Dart loader's third candidate exactly. Both iOS
  device + simulator builds green.
- Storage breakdown screen + per-backend "delete all" action.
- Speaker rename + persistence across history loads.
- Chunked Whisper for incremental segment display on long files.
- Audio Q&A `--ask` field for instruct-tuned LLM backends.
- Segment editing + karaoke-style segment playback.

## v0.3.0 and earlier

See the [GitHub releases page](https://github.com/CrispStrobe/CrisperWeaver/releases)
for v0.3.0 (streaming mic + translation UI + 33-voice gallery +
CoreML for Whisper), v0.2.x (TTS scaffold + 3 new ASR backends +
build automation), and the v0.1.x series (initial Flutter shell,
batch transcription, model auto-download, diarization, history).
