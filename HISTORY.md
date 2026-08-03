# CrisperWeaver — History

Archive of completed roadmap items. Live work is in [PLAN.md](PLAN.md);
technical learnings sit in [LEARNINGS.md](LEARNINGS.md).

Cross-references to git commits and CrispASR's
[HISTORY.md](https://github.com/CrispStrobe/CrispASR/blob/main/HISTORY.md)
are linked inline where relevant. Each entry below was once an open
PLAN section; collapsing them here keeps PLAN.md focused on what's
pending.

---

## Releases

| Tag | Date | Highlights |
|---|---|---|
| [v0.7.5](https://github.com/CrispStrobe/CrisperWeaver/releases/tag/v0.7.5) | 2026-06-08 | §5.25 completion pass: tag filter chips on History, Settings UX fix, PCM memory leak fix, 4 new tests. All 14 §5.25 features fully wired. |
| [v0.7.4](https://github.com/CrispStrobe/CrisperWeaver/releases/tag/v0.7.4) | 2026-06-06 | Synthetic content compliance: two-tier TTS watermarking (native CrispASR spread-spectrum / AudioSeal + Dart LSB fallback), WAV provenance metadata, biometric consent, disclosure labels + exports, speaker data export. MeloTTS v3 catalogue fix. CI green on all 5 platforms. |
| [v0.7.2](https://github.com/CrispStrobe/CrisperWeaver/releases/tag/v0.7.2) | 2026-06-05 | Zonos v0.1 TTS (emotion/pitch/rate/voice-clone), MOSS-Audio 4B ASR, bake script sync. |
| [v0.7.1](https://github.com/CrispStrobe/CrisperWeaver/releases/tag/v0.7.1) | 2026-06-05 | MOSS-Audio backend, backend capability set expansion. |
| [v0.7.0](https://github.com/CrispStrobe/CrisperWeaver/releases/tag/v0.7.0) | 2026-06-05 | Full CrispASR parity — 10 new TTS backends (bark, csm, dia, fastpitch, melotts, outetts, parler-tts, pocket-tts, speecht5, kugelaudio), 8 new ASR model families, truecaser post-processing, native punctuation, text LID models. Build scripts expanded from ~30 to ~60 targets. |
| [v0.4.1](https://github.com/CrispStrobe/CrisperWeaver/releases/tag/v0.4.1) | 2026-05-10 | CrispASR-0.6.2 parity sweep (rounds 1–6) — see §"May 2026 parity sweep" below. Pairs with [CrispASR v0.6.2](https://github.com/CrispStrobe/CrispASR/releases/tag/v0.6.2). |
| v0.4.0 | 2026-05-03 | First iOS IPA. Real ASR everywhere (macOS / Linux / Windows / Android / iOS). xcframework wiring shipped. |
| v0.3.0 | 2026-05-02 | Windows release; mic-streaming live transcript; per-backend Storage tab. |
| v0.2.x — v0.1.x | 2026-04 → 2026-05 | Initial macOS / Linux / Android releases; batch transcription; VAD; Advanced Options block. |

---

## CrispASR feature parity + CLI/server generation controls (2026-06-21)

Brought CrisperWeaver to full three-surface parity with CrispASR's
latest capabilities:

**CLI (`bin/crisperweaver.dart`):**
- `transcribe` gained 13 new flags: `--temperature`, `--best-of`,
  `--hotwords`, `--hotwords-boost`, `--seed`, `--max-new-tokens`,
  `--frequency-penalty`, `--beam-size`, `--ask`, `--translate`, `--vad`,
  `--word-timestamps`, `--vtt`, `--target-language`, `--initial-prompt`.
- `stream` gained `--hotwords`, `--hotwords-boost`, `--temperature`.
- `synthesize` gained `--temperature`, `--seed`.

**Server (`lib/services/server_service.dart`):**
- `/v1/audio/transcriptions` now accepts: `temperature`, `best_of`,
  `prompt`/`initial_prompt`, `hotwords`, `hotwords_boost`, `translate`,
  `vad`, `diarize`, `punctuation` form fields.
- New WebSocket streaming endpoint: `ws://host:port/v1/audio/stream` —
  accepts a JSON config message then binary 16-bit LE mono 16 kHz PCM
  frames, pushes JSON `{text, start, end}` segments in real time.

**File format support (GitHub issue #26):**
- All file pickers now accept `.opus`, `.webm`, `.m4a` alongside
  `.wav`/`.mp3`/`.flac`/`.ogg`. CrispASR's miniaudio backend decodes
  all of these natively.

**Model selector UX (GitHub issue #27):**
- The transcription screen's model picker `ExpansionTile` now starts
  expanded when no model is loaded, so first-time users discover it
  immediately.

**Server continued:**
- `GET /backends` endpoint — lists all CrispASR backends linked into the
  dylib (`{"backends": ["whisper", "parakeet", ...]}`).
- `/v1/audio/transcriptions` gained `ask`/`ask_prompt` and
  `target_language` form fields for audio Q&A and speech translation.
- `/v1/audio/speech` now accepts **multipart/form-data** with a
  `voice_file` part (WAV/FLAC/MP3 reference) for voice cloning,
  alongside the existing JSON body path.

**Test fixes:**
- `test/canary_ctc_aligner_live_test.dart` — fixed `lib:` → `libPath:`,
  `.word` → `.text`, `DecodedAudio` handling.
- `test/lid_dispatch_live_test.dart` — fixed `lib:` → `libPath:`,
  `DecodedAudio` → `.samples`, `TextLanguage` → `.code`, removed
  unnecessary `!` operators.
- 3 remaining untracked tests (`crispasr_07x_parity_catalog_test`,
  `paraformer_zh_live_test`, `sensevoice_tag_parsing_test`) verified
  clean — no fixes needed.

**Synthetic content provenance + compliance (2026-06-22):**
- Export disclosure: `syntheticDisclosure` wired through `saveTranscription`
  to SRT/VTT/JSON/Markdown exports. Enabled by default.
- Synthesize screen: compliance indicator card shows embedded provenance
  markers (watermark, WAV metadata, beep disclaimer, MP3 ID3v2 tags).
- Enriched metadata: WAV LIST INFO gains voice identity (`IGNR` field).
  MP3 ID3v2 gains `AI_MODEL`, `AI_VOICE`, `AI_TIMESTAMP` TXXX frames.
- C2PA provenance manifest: JSON-LD `c2pa.created` assertion embedded as
  a RIFF `c2pa` chunk in WAV files. Includes `trainedAlgorithmicMedia`
  digital source type + training-mining restriction.
- Heuristic AI detection: spectral analysis (digital silence ratio, ZCR
  uniformity, energy uniformity) → 0.0–1.0 confidence score. Integrated
  into Verify Watermark dialog alongside watermark + C2PA.
- Windows CI fix: suppress MSVC `<experimental/coroutine>` deprecation
  in `windows/CMakeLists.txt`.
- iOS CI fix: content-hash dedup for xcframework static lib combining
  (nemotron.o cross-library collision).

**Docs:** `PARITY.md` and `PLAN.md` updated to reflect the above.

---

## June 2026 — CrispASR 0.7.x parity sweep (§10)

Gap analysis (2026-06-21) diffed every `k_registry[]` entry in
`../CrispASR/src/crispasr_model_registry.cpp` (v0.7.1, 129 entries)
against CrisperWeaver's catalog. Result: 118/129 already present;
11 missing GGUFs added.

**Catalog.** Added `canary-ctc-aligner-q4_k` (CTC forced aligner,
~442 MB) + 10 wav2vec2 XLSR language variants (FR/ES/IT/JA/ZH/NL/PT/
AR/CS/UK, ~300 MB each) — ModelDefinition + BackendRepo + recommended-
default for each. Existing 118 entries (nemotron, parakeet variants,
chatterbox-turbo, kartoffelbox, voxcpm2, cosyvoice3, etc.) confirmed
present under different catalog keys; no action needed.

**Language-aware alignment pipeline.** `AlignerService.findAligner()`
now accepts `language:` and prefers the matching wav2vec2 aligner
(e.g., `wav2vec2-large-xlsr-53-french` for `'fr'`) before falling back
to the generic canary-ctc-aligner. The language is threaded from
`CrispASREngine.transcribe()` → `addWordTimestamps(language:)`.
New `alignerModel` field on `AdvancedTranscribeOptions` and
`AdvancedOptions` lets users override the auto-selection.

**GUI.** New "Aligner" dropdown in the Advanced Options panel (after
Token Timestamps): Auto / Canary CTC / Wav2Vec2-FR / … / Wav2Vec2-UK.
Both TranscriptionScreen construction sites thread `alignerModel`.

**CLI.** `align` command: `--model` is now optional; new `--language`
flag auto-selects the language-matched wav2vec2 aligner. Falls back to
canary-ctc-aligner when no match.

**Server.** `POST /v1/audio/transcriptions` now accepts `aligner`
(model name) and `word_timestamps` (bool) form fields.

**Tests.** `crispasr_07x_parity_catalog_test.dart` (6 tests pinning
all 11 entries), `lid_dispatch_live_test.dart` (LID backend dispatch),
`canary_ctc_aligner_live_test.dart` (forced alignment via catalog
entry), `paraformer_zh_live_test.dart`, WMT21 translation tests added
to `translation_live_test.dart`. All 30 catalog tests green.

**Server parity.** Two new endpoints: `POST /v1/audio/align` (multipart
upload + `text` + optional `language`/`model` → per-word timestamps)
and `POST /v1/text/language` (JSON `{text}` → `{language, confidence}`
via CLD3/GlotLID/FastText-176 dispatcher).

**SenseVoice emotion/event tags.** The engine now parses SenseVoice's
inline tags (`<|HAPPY|>`, `<|Speech|>`, `<|BGM|>`, etc.), strips them
from display text, and surfaces them in `segment.metadata['emotion']`
and `segment.metadata['audio_event']`. The transcript output widget
shows orange emotion badges and teal audio-event badges.

**CLI `denoise`.** New `denoise` command wrapping
`crispasr.enhanceAudioRnnoise` — matches the GUI's "Enhance Audio"
toggle. Usage: `crisperweaver denoise -o clean.wav noisy.wav`.

**Server parity — round 2.** Three more endpoints:
`POST /v1/audio/denoise` (RNNoise), `POST /v1/audio/s2s`
(speech-to-speech via lfm2-audio/mini-omni2), and
`/v1/audio/watermark` now supports `mode=embed` (returns watermarked
WAV). Only `speaker` (stateful device DB) and streaming
(SSE/WebSocket) remain.

**CLI `denoise`.** Wraps `enhanceAudioRnnoise` — was the last CLI ❌
in PARITY.md.

**Total test count.** 57 non-live tests green (30 catalog + 13
SenseVoice/aligner + 14 server).

---

## June 2026 — Full test coverage + CLI/server parity (§9)

A sweep to bring CrisperWeaver's test coverage and non-GUI surfaces up to
the engine it wraps. See `PLAN.md` §9 for the live task tracker and
`docs/PARITY.md` for the capability × {GUI, CLI, server} matrix.

**Live-test harness.** Added a shared model locator
(`test/support/crispasr_models.dart`) that resolves the dylib + the
smallest `q4_k` model per family, plus `scripts/run_live_tests.sh`. Live
tests are opt-in (gated on `CRISPASR_LIB`/`RUN_LIVE_TESTS`) so the default
`flutter test` gate stays fast. New live tests, all validated green
locally against the on-disk q4_k models: VAD, language ID (audio+text),
punctuation, forced alignment, diarization (pyannote), streaming ASR,
five non-Whisper ASR backends (moonshine/sensevoice/parakeet-110m/
fastconformer/wav2vec2), translation (madlad q4_k — ~42 min, slow), and
watermark detection.

**Two FFI gotchas, now encoded in the exemplar + memory:** (1) the
`CrispASR(modelPath)` ctor loads the path as a *whisper* context, so
auxiliary models (VAD/LID/punc) must be passed as method args, not to the
ctor, or `dispose()` SIGABRTs; (2) verify the entrypoint against the C
source — the obvious one can fail (VAD's `vad()` returns -2; the working
call is `vadSlices()`).

**Bug fixed — VAD silent no-op (§9.5).** `VadService` used the legacy
`vad()` (which `-2`-fails on the Silero/whisper-vad models) and crashed on
dispose. Replaced with a direct call to the free `crispasr_vad_slices`
dispatcher (`lib/native/vad_native.dart` + web stub), no whisper context.
Regression-tested.

**CLI (`bin/crisperweaver.dart`).** A `dart run` entrypoint wrapping
`package:crispasr` directly (no Flutter/Riverpod/path_provider), so it
reaches the engine capabilities at parity with the GUI. Commands:
`backends`, `transcribe` (+`--srt`), `vad`, `lid` (audio/`--text`),
`punctuate`, `translate`, `synthesize` (+`--voice`), `watermark`
(embed/`--detect`). Smoke-tested (`lid jfk.wav → en 0.977`).

**HTTP server.** Added `POST /v1/audio/vad`, `POST /v1/audio/language`
(LID), and `POST /v1/text/punctuate`, routed through the app's Riverpod
services; routing + validation covered by `test/server_service_test.dart`.

**Unit tests.** Pure-Dart additions for audio DSP, coarse fingerprinting,
and watermark/ID3 metadata.

Remaining (tracked in §9): CLI `diarize`/`align`/`speaker`/`stream`/`s2s`;
server text-LID/diarize/speaker/watermark/s2s; more widget tests.

---

## June 2026 — CrispASR mid-2026 catch-up (§5.26)

Brings CrisperWeaver to CrispASR `origin/main` as of June 2026. Four new
backends, two new capabilities (hotwords + speech-to-speech), and five
free upgrades from the latest engine binary.

### §5.26.1 — New backend catalog entries
- **LFM2-Audio 1.5B** (EN Q5_K + JP Q4_K): ASR + TTS + S2S. LiquidAI
  hybrid conv+attention. `ModelDefinition` + `BackendRepo` + recommended
  default + baked catalog (4+3 quant entries from HuggingFace).
- **Mini-Omni2** (Q4_K + SNAC codec): Whisper + Qwen2 0.5B multimodal.
  `ModelDefinition` + `BackendRepo` + recommended default + baked catalog
  (3 quant entries).
- **MOSS-Audio 4B** was already catalogued — confirmed working (the
  upstream PLAN.md label "in progress" was stale; commit `fece86c2` says
  "TRANSCRIPTION WORKS").
- **Parakeet-RNNT 0.6B/1.1B** — already in baked catalog; added
  `BackendRepo` entries for HF probe.
- Bake script synced: 110 repos, 310 entries (was 107/300).

### §5.26.2 — Hotwords / contextual biasing
- **C API** (`crispasr_session_set_hotwords`): session-level setter that
  stores comma-separated hotwords + boost factor. Parakeet CTC/TDT gets
  Aho-Corasick trie immediately; LLM backends get ask-prompt injection at
  `transcribe_single` dispatch via a scoped guard.
- **Dart FFI** (`CrispasrSession.setHotwords`): `providesSymbol()` graceful
  degradation on older dylibs.
- **UI**: "Hotwords" text field in Advanced Options with backend-aware
  helper text (enabled for 15 backends, disabled for CTC-only).
- **Wiring**: all 3 transcription paths (single-file, batch, pool) pass
  hotwords through `AdvancedTranscribeOptions` → engine → `setHotwords()`.
- **Tests**: 13 unit tests (field roundtrip, capability sets, prompt merge,
  backend exclusion) + 2 live tests (setHotwords + transcribe, empty string).

### §5.26.3 — Speech-to-Speech mode
- **C API** (`crispasr_session_speech_to_speech`): wraps
  `lfm2_audio_speech_to_speech` + `mini_omni2_speech_to_speech`. Returns
  malloc'd PCM + optional intermediate transcript.
- **Dart FFI** (`CrispasrSession.speechToSpeech`): returns `({Float32List
  pcm, String transcript})`.
- **UI**: S2S toggle + audio file picker on Synthesize screen (visible only
  for lfm2-audio/mini-omni2). When S2S mode is on, text input is replaced
  by audio input. Synthesize button gated on `_s2sInputPath != null`.
- **Service**: `TtsService.speechToSpeech()` runs S2S in a background
  isolate.
- **Tests**: 3 unit tests (catalog entries, companion, kind) + 1 live test
  (mini-omni2 S2S roundtrip).

### §5.26.4–7 — Free upgrades (no CrisperWeaver code change)
- **Global diarization** (#110): sherpa/ECAPA runs once on full audio.
- **Long-form chunking** (#89/#114): per-backend chunked-encode + dedup.
- **Permissive G2P** (#156): replaces espeak-ng GPL dep with IPA dicts.
- **Beam search** (#139): 18/24 backends now beam-capable.

### CI fixes
- Fixed 5 pre-existing `flutter analyze` errors: `crispembed_web.dart`
  `dynamic` → `int`, `translate_screen.dart` deprecated `value:`,
  `hfspace_live_test.dart` type inference failures.

**Files touched** (22 modified, 1 new):
`PLAN.md`, `CHANGELOG.md`, `HISTORY.md`,
`model_service.dart`, `baked_models_catalog.dart`, `preset_service.dart`,
`advanced_options_widget.dart`, `synthesize_screen.dart`,
`transcription_screen.dart`, `transcription_service.dart`,
`transcription_worker.dart`, `transcription_worker_pool.dart`,
`tts_service.dart`, `crispasr_engine.dart`, `diarization_service.dart`,
`crispembed_web.dart`, `hfspace_engine.dart`, `translate_screen.dart`,
`app_en.arb`, `app_de.arb` + generated l10n,
`bake_models_catalog.dart` (script),
`advanced_options_test.dart`, `tts_issue_fixes_test.dart`,
`backend_dispatch_test.dart`, `hfspace_live_test.dart`,
`hfspace_engine_test.dart`,
new `s26_integration_live_test.dart`.

**Upstream CrispASR** (`feat/session-s2s-hotwords`, merged to main):
`include/crispasr.h`, `src/crispasr_c_api.cpp`,
`flutter/crispasr/lib/src/crispasr.dart`.

---

## June 2026 — Web/PWA with HF Space cloud engine + WASM embeddings

### Web/PWA deployment (v0.7.7+)
- **White screen fix**: `dart:io` `Platform.*` calls crash on web; replaced with
  `platform_utils.dart` web-safe wrappers across 23 files.
- **HfSpaceEngine**: new `TranscriptionEngine` implementation that routes ASR + TTS
  through the `cstr/CrispASR` HF Space via OpenAI-compatible HTTP endpoints.
  Engine factory auto-selects `hfspace` on web, `crispasr` on native.
- **File picker web path**: `RobustFilePick` gained `fileBytes`/`fileNames` fields;
  on web, raw bytes go directly to `TranscriptionService.transcribeBytes()` →
  `HfSpaceEngine.transcribeBytes()` → `POST /v1/audio/transcriptions`.
- **CrispEmbed WASM**: compiled CrispEmbed C++ to WebAssembly via Emscripten
  (1.1 MB WASM + 78 KB JS). `crispembed_web.dart` fetches Q4_K model (~19 MB)
  from HuggingFace and runs text embeddings client-side for semantic search.
- **Vercel deploy**: `deploy-web.yml` GitHub Actions workflow builds Flutter web
  and deploys to Vercel on every push to main.
- **HF Space updated**: added canary, hubert, data2vec ASR + vibevoice, orpheus,
  chatterbox, chatterbox-turbo TTS backends to `../CrispASR/hf-space/app.py`.
- **Text translation on web**: Translate screen routes through HF Space's new
  Translate tab (M2M-100, WMT21, MADLAD-400) via Gradio call API.
- **Transcription params**: translate, VAD, diarize, punctuation forwarded to
  the HF Space `/v1/audio/transcriptions` endpoint on web.
- **Text LID on web**: `detectTextLanguage()` via Gradio call API to `crispasr-lid`.
- **Test suite**: 32 unit tests (mock Dio) + 13 live integration tests (all pass)
  covering HfSpaceEngine, HfSpaceTtsService, platform_utils, kokoro TTS with
  readiness polling, and all Gradio API endpoints (transcribe, LID, translate).
- **Kokoro g2p dict fallback** (CrispASR §156): wired permissive IPA dicts into
  kokoro's phonemizer — EN/DE/FR/ES work without espeak-ng (GPL). Auto-downloads
  CMUdict (BSD) + pre-generated IPA dicts from HuggingFace.
- **HF Space pre-built binaries**: switched from compiling CrispASR in the Docker
  build (exceeded 6 min timeout) to downloading pre-built binaries from GitHub
  Releases. Ubuntu 24.04 base image with libomp5/libgomp1 for OpenMP.
- **Dedicated Vercel project**: `crisperweaver-web` at `crisperweaver-web.vercel.app`,
  separated from the shared `web` project that CrispCloud was also using.

### CI fix, web conditional imports, Windows Zen3 crash (#19)

### CrispEmbed checkout in CI/release workflows

`crispembed` was added as a path dependency but never checked out in
CI/release workflows (only CrispASR was). Added `CRISPEMBED_REPO` /
`CRISPEMBED_REF` env vars and checkout steps (with `submodules: recursive`
for the ggml submodule) in all 8 jobs across `ci.yml` and `release.yml`.

### Web compilation — conditional imports + stubs

`dart:ffi` is fundamentally unavailable on web. Created `lib/native/`
with 12 files (6 barrel conditional-import files + 6 stub files) covering
`package:crispasr`, `package:crispembed`, `dart:ffi`, `package:ffi`,
and two service files (`disk_space.dart`, `env_helpers.dart`) that use
FFI directly. All 29 source files updated to import through the barrels.

On native platforms the real packages load unchanged. On web the stubs
provide matching type surfaces (`UnsupportedError` for FFI-backed
constructors, functional data classes). The app already degrades
gracefully (MockEngine, null embedder → TF-IDF fallback), so the web
build runs with full UI minus native transcription.

`flutter build web --release` produces a 4.9 MB JS bundle. Deployed
to Vercel at `https://web-nu-peach-46.vercel.app`.

### Windows AVX-512 crash on Zen3 (fixes #19)

GitHub Actions `windows-latest` runners have AVX-512. With
`GGML_NATIVE=ON` (the default when not cross-compiling), ggml's
`FindSIMD.cmake` detects AVX-512 on the build host and compiles
`whisper.dll` with `/arch:AVX512`. At runtime on AMD Zen3 (AVX2-only),
`ggml_backend_cpu_x86_score()` checks for AVX-512F/CD/VL/DQ/BW, all
absent, and the backend fails to initialize → crash on model load.

Fix: set `GGML_NATIVE=OFF` and explicitly enable `GGML_AVX2=ON`,
`GGML_AVX=ON`, `GGML_FMA=ON`, `GGML_F16C=ON`, `GGML_AVX512=OFF`.
This gives near-optimal performance on Haswell+ / Zen2+ without
requiring AVX-512.

---

## June 2026 — Mobile UX: file picker, adaptive icon, iOS alpha, PWA

Three Android / iOS pain-points fixed plus web PWA scaffolding.

### Android file picker — greyed-out audio files

`pickFilesRobust()` used `FileType.custom` with extension lists, which
relies on Android's `MimeTypeMap` to resolve each extension to a MIME
type. Extensions like `.flac`, `.ogg`, `.m4a` frequently fail that
lookup, so the native picker rendered them greyed-out / unselectable
even though they're valid audio files.

Fix: added an optional `FileType? type` parameter. When callers pass
`FileType.audio`, the native picker receives `audio/*` (all audio
files selectable). Results are post-filtered by `allowedExtensions`
in Dart. `FileType` re-exported from `file_picker_util.dart` so
callers don't need a separate `package:file_picker` import.

Updated 5 screens: transcription, speaker management, voice bake,
voice clone wizard, synthesize.

### Android adaptive icon

Added `adaptive_icon_foreground` / `adaptive_icon_background` (#1d325f)
to `flutter_launcher_icons` in `pubspec.yaml`. Generated
`mipmap-anydpi-v26/ic_launcher.xml`, per-density foreground drawables,
and `values/colors.xml`. Android 8+ now applies its mask (rounded rect,
circle, squircle) instead of showing the raw square PNG.

### iOS icon alpha channel removal

All generated iOS icons were RGBA (with alpha), which Apple rejects
on App Store submission. Added `remove_alpha_ios: true` to
`flutter_launcher_icons` config and regenerated — icons are now RGB.

### Web / PWA platform

Scaffolded Flutter web target via `flutter create --platforms=web`.
Replaced default icons with `app_logo.png` at 192 px and 512 px
(plus maskable variants). `manifest.json` configured with app name,
navy theme (#1d325f), standalone display mode. Favicon regenerated
from logo. Feature set limited to mock engine / remote server mode
(no native FFI on web).

---

## June 2026 — Split-on-punct subtitle formatting (§5.8)

Dart-side post-processing that splits segments at sentence-ending
punctuation (`. ! ?`), creating natural subtitle lines from any backend's
output. Mirrors CrispASR CLI's `--split-on-punct` but runs in Dart so it
works with every backend, not just whisper.

`splitSegmentsOnPunct()` scans each segment's text for `[.!?]\s+` matches,
splits into sub-segments, and linearly interpolates timestamps by character
position. Wired as a toggle in Advanced Options (`splitOnPunct`), preset
serialization included, i18n EN/DE.

---

## June 2026 — Cross-modal audio embeddings (§5.25.2)

Extended semantic search with audio embeddings via CrispEmbed's
`encodeAudio(Float32List pcm)` (already present in the Dart binding).

* `HistoryEntry.audioEmbedding` — optional `List<double>`, single vector
  for the whole audio clip. Persisted in JSON, backwards-compatible.
* Computed at save time alongside segment text embeddings; all 4
  `historyService.save()` call sites pass `audioData`.
* Search: `max(text_score, audio_score)` per entry. Dimension mismatch
  (e.g. 384-d MiniLM text vs 2048-d BidirLM-Omni audio) silently
  yields audio_score=0.
* `bidirlm-omni-2.5b-q4_k` (2048-d, ~1.7 GB) catalogued as
  `ModelKind.embed` for audio-capable embedding search.
* 6 new tests (audio embedding round-trip, back-compat, dimension
  mismatch, null handling).

---

## June 2026 — Riverpod Notifier migration

Migrated 3 of 4 `StateNotifier` subclasses to modern Riverpod 3
`Notifier` pattern:

* `AppStateNotifier` → `Notifier<AppState>`, `build()` returns const
* `LocaleNotifier` → `Notifier<Locale?>`, reads settings via `ref`
* `EngineManagerNotifier` → `Notifier<EngineManagerState>`,
  `ref.onDispose()` replaces `dispose()` override

`BatchQueueNotifier` kept on legacy (18+ tests construct directly).
2 `StateProvider` kept on legacy (50+ external `.state=` call sites).
`app_state_test.dart` refactored to use `ProviderContainer`.

---

## June 2026 — Riverpod 2→3 migration

Bumped `flutter_riverpod` from 2.4.9 to 3.3.1 (riverpod 3.2.1).
In riverpod 3, `StateNotifier`, `StateNotifierProvider`, and
`StateProvider` moved to `package:flutter_riverpod/legacy.dart`.
Added the legacy import to the 4 files that use them:
`main.dart`, `engine_factory.dart`, `batch_queue_service.dart`,
`advanced_options_widget.dart`.

Future pass: migrate the 4 `StateNotifier` subclasses + 2
`StateProvider` declarations to the modern `Notifier` / `NotifierProvider`
API to eliminate the legacy imports entirely.

---

## June 2026 — Embedding persistence (§5.25.2 follow-up)

Pre-compute and persist CrispEmbed vectors alongside history JSON:

* `HistoryEntry.segmentEmbeddings` — optional `Map<int, List<double>>`
  stored as JSON (keys as strings). Backwards-compatible (old entries
  without embeddings load fine).
* All 4 `historyService.save()` call sites now pass
  `embedder: ref.read(crispEmbedProvider)`.
* `SemanticSearchService._embeddingSearch()` lookup order:
  (1) persisted embeddings from entry, (2) in-memory `_embeddingCache`,
  (3) on-the-fly encoding via embedder.
* "Reindex embeddings" button on History screen AppBar backfills
  entries without embeddings.

---

## June 2026 — CrispEmbed semantic search (§5.25.2)

Wired the CrispEmbed Dart FFI package (`../CrispEmbed/flutter/crispembed`)
as a path dependency. The existing C-ABI (`crispembed_encode`) and Dart
binding (`CrispEmbed.encode()` → `Float32List`) were ready to use —
no changes to the CrispEmbed repo needed.

* `crispEmbedProvider` (Riverpod, `lib/main.dart`) lazy-loads the first
  `ModelKind.embed` GGUF on disk. Returns `null` when the native lib or
  model is missing → callers degrade to TF-IDF silently.
* `SemanticSearchService.search()` accepts an optional `CrispEmbed?
  embedder`. When present: encode query + each segment's text, rank by
  cosine similarity. Static `_embeddingCache` (keyed by segment text)
  avoids re-encoding on every search.
* History screen passes `ref.read(crispEmbedProvider)` to the search call.
* `all-MiniLM-L6-v2-Q8_0` (384 dim, ~23 MB) catalogued as the first
  `ModelKind.embed` entry with a `BackendRepo` pointing at
  `cstr/all-MiniLM-L6-v2-GGUF`.

Follow-ups: vector persistence on history save, audio embeddings via
`crispembed_encode_audio`, more model choices.

---

## June 2026 — Flutter SDK upgrade + dependency refresh (§5.9)

Upgraded `/mnt/volume1/toolchain/flutter` from **3.35.1 → 3.44.1**
(Dart 3.9.0 → 3.12.1). 36 tier-2 packages bumped:

* `device_info_plus` 12.3 → 13.1 (removed the stale `<12.4.0` Xcode pin)
* `share_plus` 12 → 13.1, `package_info_plus` 9 → 10.1
* `file_picker` 11 → 12.0.0-beta.5 (needed for `win32` 6.x compat)
* `win32` 5 → 6.3, `material_color_utilities` → 0.13

Three files fixed for API changes:
* `edit_audio_screen.dart` — `FilePicker.saveFile` now requires `bytes:`
* `file_picker_util.dart` — migrated deprecated `allowMultiple`/`readStream`
* `transcript_summarize_service.dart` — removed unnecessary `!` (Dart 3.12
  flow analysis promotes final nullable fields)

Still pending: `riverpod` 2→3 migration (large, separate effort).

---

## June 2026 — §5.25 completion pass (v0.7.5)

Audit + wiring pass confirming all 14 §5.25 features are fully integrated.
Most features were already wired in prior sessions; this pass:

* Added **segment tag filter chips** to the History screen — horizontal
  scrollable `FilterChip` row (7 tag types), combinable with text search.
* Moved Speakers / Speaker Vocab settings tiles to the Diarization section.
* Fixed a **memory leak** — retained PCM buffer (~230 MB/hr) now freed
  after multilingual tagging instead of held until the next transcription.
* Verified and closed out the "Remaining" items for §5.25.4 (speaker vocab
  editor), §5.25.6 (chapter export), §5.25.9 (lexicon editor), §5.25.10
  (segment tags), and §5.25.12 (keyboard nav) — all already implemented.
* Added 4 new test files (chapter detection, history screen widget,
  pronunciation lexicon, semantic search).
* Deleted stale `feat/next-gen-features` branch (local + remote).

Updated PLAN.md: all §5.25 "Remaining" items now show "none (v1 complete)".

---

## June 2026 — §5.25 next-generation features (14 features)

Fourteen new features spanning UX, intelligence, and workflow automation.
Landed on `feat/next-gen-features` branch (3 commits, 27 files, ~2,800
lines). Grouped into three tiers by impact.

### Tier A — High impact

* **§5.25.1 Confidence heatmap** — enhanced existing text-color-only
  confidence tint to a proper background-color gradient (transparent at
  ≥0.9, yellow tint 0.7–0.9, orange 0.5–0.7, red <0.5). Low-confidence
  words additionally get colored text + underline for accessibility.
  `_getConfidenceBackground()` + updated `_buildConfidenceTintedText()`
  in `transcription_output_widget.dart`.

* **§5.25.2 Semantic search scaffold** — `SemanticSearchService` with
  TF-IDF fallback scorer (word overlap + IDF weighting) and
  `cosineSimilarity()` ready for CrispEmbed vectors. Upgradeable once
  CrispEmbed's Dart FFI binding lands.

* **§5.25.3 Subtitle overlay** — `SubtitleOverlayScreen` at route
  `/subtitle-overlay`. Fullscreen dark-transparent screen showing
  latest streaming transcription. macOS platform channel
  (`crisperweaver/window_overlay`) sets `NSWindow.level = .floating` +
  `alphaValue`. Font size +/-, top/bottom toggle, background toggle.
  Button in AppBar (wide) and overflow menu (phone).

* **§5.25.4 Speaker-adaptive vocabulary** — `SpeakerVocab` model
  persisted as `<name>.vocab.json` alongside `.spk` profiles.
  `mergeForSpeakers()` computes the union of active speakers' terms.

* **§5.25.5 Multilingual transcription** —
  `MultilingualTranscriptionService` runs per-segment LID via
  `LidService.detectIfModelAvailable`, tagging with
  `metadata['lang']`. `groupByLanguage()` groups consecutive
  same-language segments.

* **§5.25.6 Chapter detection** — `ChapterDetectionService` with
  sliding-window Jaccard vocabulary distance for topic-shift detection.
  Exports to YouTube chapters and Podcasting 2.0 JSON.

### Tier B — Medium impact

* **§5.25.7 Transcript diff** — `TranscriptCompareScreen` with
  LCS-based word-level diff, timestamp-aligned segment pairing, and
  Jaccard similarity stats. `HistoryService.loadEntry(id)` added.

* **§5.25.8 Watch folder** — `WatchFolderService` monitors a
  configured directory via `FileSystemEntity.watch()`. 2 s debounce,
  audio extension filtering. Settings UI + `SettingsService`
  persistence. Started on app init when enabled.

* **§5.25.9 Pronunciation lexicon** — `PronunciationLexicon` model
  with word-boundary-aware text substitution. Wired into
  `TtsService.synthesize()`.

* **§5.25.10 Segment tags** — `SegmentTag` enum (7 types) with `tags`
  field on `TranscriptionSegment`. Tag picker in segment long-press
  menu (FilterChip grid). Emoji badges in segment header. Tags persist
  in history JSON. `AppStateNotifier.replaceSegments()` added.

* **§5.25.11 Audio fingerprint dedup** — `AudioFingerprintService`
  with PCM-based (8-bit/4-bit quantized SHA-256) and file-based
  (size + head) fingerprinting. `audioFingerprint` field on
  `HistoryEntry`.

### Tier C — Polish

* **§5.25.12 Keyboard navigation** — integrated directly into
  `TranscriptionOutputWidget`: J/K/↑/↓ segment nav, Space play/pause,
  Enter edit, Tab jump-to-low-confidence, Escape deselect. Focus ring
  on active card. `_scrollToFocused()` with animated scroll.

* **§5.25.13 Model A/B testing** — `AbTestResult` with per-segment
  winner picks ('A'/'B'/'tie'). `ModelRatings` leaderboard.

* **§5.25.14 Note exports** — `NoteExportService` with four formatters
  (Obsidian, Notion, Logseq, YouTube chapters). Wired into the
  transcript share menu via `_saveAsNote()`.

### Tests

* `test/note_export_test.dart` — 10+ tests covering all 4 formats +
  SegmentTag round-trip.
* `test/audio_fingerprint_test.dart` — 6 tests (determinism,
  differentiation, edge cases).
* `test/watch_folder_test.dart` — 6 tests (lifecycle, file detection,
  extension filtering).

---

## June 2026 — §5.25 post-wiring handover (2026-06-08, commit be6526f)

Four partially-integrated §5.25 features wired end-to-end, plus an
i18n migration pass.

### Parallel A/B model comparison (§5.25.13)

`_showModelComparison` now spawns two single-worker pools via
`Future.wait` instead of running models sequentially. Both pools
transcribe the same audio in parallel; results feed into
`TranscriptCompareScreen` for side-by-side diff. `ModelRatings`
persisted to `<app-docs>/model_ratings.json`.

### Speaker-adaptive vocab auto-injection (§5.25.4)

After diarisation resolves speaker names,
`SpeakerVocab.mergeForSpeakers()` injects domain terms into
`advancedOptionsProvider` vocabulary for subsequent transcriptions.
Wired through both the single-file transcription path and the batch
queue drain loop.

### Fingerprint dedup before enqueue (§5.25.11)

`AudioFingerprintService` now gates three intake paths:
- **Watch folder** — auto-skips duplicates (no user interaction).
- **Batch enqueue** — silently skips files whose fingerprint
  already exists in history.
- **Single-file drag-drop** — shows a confirmation dialog before
  re-processing a duplicate.

### i18n migration

33 hardcoded strings migrated to ARB files, bringing the total to
866 keys with full EN/DE parity. `flutter gen-l10n` succeeds with
Flutter 3.35.1 (toolchain at `/mnt/volume1/toolchain/flutter`);
generated classes at `lib/l10n/generated/` are up to date.

---

## May 2026 parity sweep — six rounds, lands in v0.4.1

Brought CrisperWeaver's catalog, advanced-options surface, and post-
processor wiring up to CrispASR 0.6.0 → 0.6.2 parity. Net effect:
3 new screens, 8 new backends in the catalog, runtime tunable
flash-attn / GPU layers / TTS sampling, and 3 new export formats —
all without breaking the v0.4.0 app surface (every new toggle
defaults to "behaves like before").

### Round 1 — initial parity (catalog + dispatcher)

* New ASR backends: **gemma4-e2b** (USM Conformer + Gemma-4 35L,
  140+ languages), **omniasr-llm-unlimited** (streaming, 15 s
  protocol, unlimited audio), **granite-speech-4.1** (2B, 4.1+,
  4.1-nar variants).
* New TTS backends: **chatterbox / kartoffelbox** (T3 AR + S3Gen
  flow-matching), **indextts** (GPT-2 AR + BigVGAN, ZH+EN),
  **qwen3-tts-voicedesign** (1.7B, natural-language voice instruct),
  **vibevoice-1.5b** (runtime WAV cloning via
  `setVoice(wav, refText:)`).
* New post-processors: **fullstop-punc multilang** (EN/DE/FR/IT)
  alongside FireRedPunc (ZH+EN). Picker in Advanced Options.
* Diarisation method picker — vadTurns (default) / pyannote
  (downloadable GGUF) / energy / xcorr. `DiarizationService`
  auto-locates the pyannote GGUF and falls back to vad-turns when
  missing.
* LID method picker — whisper / silero. `LidService` honours the
  picked method, resolves the file, and falls back when mismatched.
* VAD picker — silero (bundled) / firered / marblenet /
  whisper-vad-encdec. Threshold, min-speech-ms, min-silence-ms,
  speech-pad-ms exposed as sliders, plumbed through
  `TranscribeOptions` / `SessionVadOptions`.
* Whisper-only knobs: tdrz (tinydiarize), token-level timestamps.
* Three new export formats: **CSV** (RFC-4180 quoting), **LRC**
  (lyrics, mm:ss.cs), **WTS** (Whisper Text Segments debug).
* TTS knobs in Synthesize screen: trim-silence, speed slider
  (0.25× – 4×, nearest-neighbour resample), reference-transcript
  field, voice-design instruct field.
* New `AdvancedTranscribeOptions` value class bundles the parity
  knobs so `transcribeFile`/`transcribeUrl` keep stable signatures.

Companion CrispASR commits: `5591ecfe` (translateText FFI),
`1518f477` (CrispasrSession.openStream), `95e2fdf7` (chatterbox
sampling knobs).

### Round 2 — text translation + LID accelerator

* ✅ **Text translation screen** — `TextTranslationService` +
  `TranslateScreen` shipped. Catalogue covers M2M-100 (418M, 1.2B),
  WMT21 Dense (en→X **and** X→en — both checkpoints), MADLAD-400 3B.
  New `translateText` method on `CrispasrSession`. Source/target
  dropdowns with one-click swap, max-tokens slider,
  copy-to-clipboard.
* ✅ **LID accelerator knobs** — `lidUseGpu` / `lidFlashAttn` /
  `nThreads` exposed in `AdvancedTranscribeOptions` and the
  Advanced Options "Performance" section, threaded through
  `crispasr_detect_language_pcm`.
* ✅ **`ModelKind.translate`** filter — Model Manager can now
  group text-translation models separately from speech-translation
  ASR backends.

### Round 3 — custom voice + non-Whisper streaming + voice baking

* ✅ **Custom voice WAV picker** on the Synthesize screen —
  surfaces the existing `voiceWavPath` parameter that
  `TtsService` already accepted. Pick a WAV, optionally pair with a
  Reference transcript for runtime cloning.
* ✅ **Streaming for non-Whisper backends** — new
  `CrispasrSession.openStream()` Dart helper wrapping
  `crispasr_session_stream_open`. Engine's `transcribeStream`
  routes through it whenever a session is loaded. Live mic
  transcription works on whisper / kyutai-stt / moonshine-streaming
  / voxtral4b end-to-end.
* ✅ **Voice baking flow** — `VoiceBakingService` spawns CrispASR's
  `bake-chatterbox-voice-from-wav.py` script via `Process.start`,
  streams stdout/stderr live, drops the resulting GGUF into the
  models directory. Bake screen launched from the cake icon in the
  Synthesize app-bar. Desktop-only (mobile has no Python runtime).

### Round 4 — ASR GPU toggle + chatterbox sampling

* ✅ **ASR-side GPU + perf toggles** — extended the C-ABI with
  `crispasr_session_open_with_params(path, backend, params_v1*)`.
  Threads `use_gpu` / `verbosity` / `n_threads` through every
  backend's `*_context_params` at session-open time. Surfaced in
  Advanced Options "Performance" as the *ASR on GPU* toggle.
  Takes effect on the next model load.
* ✅ **TTS sampling knobs** — chatterbox runtime setters for
  diffusion steps, top-p, min-p, repetition penalty, CFG weight,
  exaggeration, max speech tokens. Orpheus temperature too. New
  `crispasr_session_set_*` exports + Dart binding methods
  (`setTtsSteps`, `setTopP`, …). Synthesize screen surfaces five
  sliders in its Advanced section; setters silently no-op on
  backends that don't honour each field.

### Round 5 — flash-attn + n_gpu_layers plumbing + OpenAI server + qwen3-tts temp

* ✅ **Flash-attention + n_gpu_layers plumbing** — open-params
  struct bumped to v2 (additive — v1 callers keep working). Wired
  through the Dart binding's `CrispasrSession.openWithParams()` and
  into CrisperWeaver's Advanced Options Performance section.
  Whisper honours flash_attn at the kernel level today; per-backend
  kernel wiring tracked as
  [CrispASR PLAN #86](https://github.com/CrispStrobe/CrispASR/blob/main/PLAN.md#86-per-backend-flash-attention-wiring-crisperweaver-driven).
* ✅ **Qwen3-TTS sampling temperature** — was a hardcoded
  `temperature=0.9f` in the code-predictor's top-k sampler; now
  reads `c->params.temperature` so the existing Synthesize-screen
  temperature slider works on it. New `qwen3_tts_set_temperature`
  runtime setter routed via `crispasr_session_set_temperature`.
* ✅ **Local HTTP server (OpenAI-compatible)** — `shelf`-based,
  bound to 127.0.0.1 only. Endpoints:
  `POST /v1/audio/transcriptions`, `POST /v1/audio/speech`,
  `POST /v1/translations`, `GET /health`. Toggle in
  *Settings → Local HTTP server*. Lets external scripts drive
  CrisperWeaver locally without re-authoring against a different
  API.

### Round 6 — close CrispASR PLAN #88 and #89

* ✅ **CrispASR #89 — flash_attn fields on every backend** — 12
  of 12 backends (parakeet, canary, qwen3, cohere, granite_speech,
  voxtral, voxtral4b, vibevoice, qwen3_tts, orpheus, kokoro,
  chatterbox) now have `flash_attn` (or pre-existing `use_flash`)
  in their `*_context_params`. `crispasr_session_open_explicit`
  threads `g_open_flash_attn_tls` through. → CrispASR HISTORY §84.
* ✅ **CrispASR #88 — kokoro length-scale + vibevoice
  diffusion-step runtime knobs.** Kokoro: new `length_scale` field
  + `kokoro_set_length_scale` setter, applied before banker's-
  rounding in the duration predictor. VibeVoice: new
  `vibevoice_set_tts_steps` setter mutates the pre-existing
  `tts_steps` cparams field. Both routed through unified session
  setters. CrisperWeaver: TtsService's `synthesize` now drives
  `setLengthScale(1/speed)` so the speed slider stretches/squeezes
  via the duration model on kokoro (clean) AND the client-side
  resampler on backends without one (fallback). →
  CrispASR HISTORY §85.

---

## Post-v0.4.1 §5.1 competitor-gap sweep — May 2026

Closes Tier A + Tier B + most of Tier C of the §5.1 competitor-gap
backlog (PLAN.md). All twelve features below are pure-Dart and
fully cross-platform unless noted; no FFmpeg dependency on the
audio-editing path; no per-app native code beyond what the
hotkey_manager / record / file_picker packages already ship.

### §5.1.1 System audio capture — May 2026

"Transcribe what's playing in Zoom / YouTube / any app." Cross-
platform Dart interface + per-platform native implementations.

- **macOS 13+** — ScreenCaptureKit-based, `SystemAudioCapture.swift`
  registered from `MainFlutterWindow.swift`. AVAudioConverter
  resamples to 16 kHz mono Float32 inside the isolate; EventChannel
  delivers PCM frames to Dart. UI: new "screen-share" icon button
  in the audio recorder, greyed out on unsupported platforms.
  First use prompts for Screen Recording permission (TCC);
  `permission_denied` / `os_too_old` / `start_failed` rcs come back
  as typed exceptions (`SystemAudioPermissionException`,
  `SystemAudioUnsupportedException`) with localised snackbar
  messages in en + de.
- **Linux** — `parec` subprocess against `@DEFAULT_SINK@.monitor`,
  asking PulseAudio for 16 kHz mono float32-le PCM directly so
  no Dart-side resampling. Ships with `pulseaudio-utils` (Ubuntu
  / Debian / Fedora default install) or `pipewire-pulse`.
  `which parec` probe in `isSupported`; missing-tool case surfaces
  a typed `SystemAudioUnsupportedException` with an install hint.
- **Windows** — `ffmpeg` subprocess using the `-f wasapi -i default`
  loopback (FFmpeg 5+). Requires ffmpeg on PATH; `where ffmpeg`
  probe caches the answer. Missing-tool case surfaces a typed
  exception with `winget` / `choco` install hints. Native WASAPI
  plugin (~2 days) would remove the install dependency — deferred.
- **Android 10+** — `MediaProjection` + `AudioPlaybackCapture-
  Configuration` via a foreground service
  (`SystemAudioCaptureForegroundService.kt`). On `start()` the
  activity launches the system "screen + audio capture" permission
  dialog; on grant the foreground service spins up with a
  persistent `mediaProjection`-type notification (required by
  Android 14) and an `AudioRecord` configured at 16 kHz mono
  Float32. PCM frames flow back to Dart via a static frame-listener
  callback → EventChannel sink. Captures `USAGE_MEDIA` / `USAGE_GAME`
  / `USAGE_UNKNOWN` but deliberately excludes
  `USAGE_VOICE_COMMUNICATION`. New permission:
  `FOREGROUND_SERVICE_MEDIA_PROJECTION` in manifest.
- **iOS** — Apple sandbox forbids system audio capture entirely.
  Throws `SystemAudioUnsupportedException` permanently.

### §5.1.2 Custom vocabulary / dictionary boost — May 2026

Persistent chip list in Advanced Options. Per-backend-class
biasing mechanism:

| Class | Mechanism | Models |
|---|---|---|
| Whisper-style | `initial_prompt` prefill | whisper, moonshine |
| LLM-backend | `setAsk(prompt)` prefix | voxtral, voxtral4b, qwen3, granite, granite-4.1{,-plus}, glm-asr, kyutai-stt, gemma4-e2b, omniasr-llm{,-unlimited}, mimo-asr |
| CTC-style | Not supported (no token-prefill point) | parakeet, canary, cohere, fastconformer-ctc, wav2vec2, firered-asr, omniasr-CTC |

New `AdvancedOptions.vocabulary: List<String>` field with copyWith
roundtrip; new `vocabularyViaInitialPromptBackends` and
`vocabularyViaAskPromptBackends` capability sets; new static
`mergeVocabularyIntoPrompt(backend, vocab, existing)` helper that
prepends `"Vocabulary: term1, term2, …. "` to the existing prompt
iff the backend supports it.

The drain loop's three call sites (single-file, batch serial,
batch pool) resolve the active backend via `_resolveBackend(modelId)`
and call the merge separately for `initial_prompt` vs `askPrompt`.
UI helper text changes between three variants per backend class.

11 new tests pin the capability-set membership, CTC exclusion,
copyWith roundtrip, and the merge formatter's 6 edge cases.

### §5.1.3 Inline transcript editing — May 2026

Long-press on a segment in `transcription_output_widget.dart`
opens a bottom-sheet → "Edit segment" → dialog with a multiline
TextField pre-filled with the current text. On save:
`AppStateNotifier.editSegment(index, newText)` updates AppState
with `metadata['edited'] = true` (rendered as a tiny pencil icon
next to the segment), and if the transcription has a saved
history id we also fire `historyService.update(entry)` so the
edit survives a reload.

New `HistoryService.update(HistoryEntry)`; new
`AppState.historyEntryId` field stashed by the transcription
screen after the first save; `startTranscription()` rebuilds
AppState from scratch so a fresh run can't overwrite the previous
entry. 2 new HistoryService tests pin the update / missing-id-
noop contract.

### §5.1.4 History search — May 2026

Text field in the HistoryScreen AppBar. Filters entries client-
side by case-insensitive substring match against the entry's
title (source filename or URL) AND its full transcript. Matching
entries auto-expand so the user sees the hit without an extra
tap; matched substrings show a yellow highlight in both the title
row and the transcript body via `TextSpan.rich` +
`SelectableText.rich`. Per-search count strip ("N of M matched")
above the list when a query is active. ARB strings for hint /
no-results / match-count in en + de.

### §5.1.5 Audio waveform editor + bidirectional transcript sync — May 2026

Dedicated `EditAudioScreen` with a waveform painter, transport
(play/pause/scrub), three editing operations (trim / cut middle /
split into chapters), AND an optional collapsible transcript pane
on the same screen so bidirectional sync stays visible without
overlay-stacking. Output is 16 kHz mono PCM WAV (matches the
transcription input format so "crop then transcribe" is a single
hand-off).

**Phases:**

- **A. `AudioEditService` + WAV encoder + tests.** Pure-Dart service
  supporting `trim()` / `cut()` / `split()` with sample-accurate
  slicing via the existing `crispasr.decodeAudioFile` FFI decoder.
  WAV output is bit-perfect: Float32 PCM clipped to ±1.0, encoded
  as Int16 little-endian, standard RIFF/WAVE/fmt/data header.
  5 tests pin header bytes + clipping + DecodedSource.secondsToSample.

- **B. Waveform `CustomPainter` + `EditAudioScreen` shell.**
  Transport buttons, drag-out selection on the painter, three op
  buttons routed through the Phase A service. Cross-platform
  `FilePicker.saveFile` for the "save as" target. `WaveformBars.
  fromSamples` runs an O(samples) max-magnitude downsampler at
  layout time; cached per-width so window resizes don't re-traverse.

- **C. Collapsible transcript pane.** Bidirectional click-sync
  on the single screen: tap segment → seek playhead; long-press
  segment → bottom-sheet with "Select / Trim to / Mark for split";
  tap waveform → playhead moves and the matching segment is
  highlighted + scrolled into view. Pane visibility persists via
  `Settings.editAudioShowTranscript`.

- **D. Transcript-screen entry points.** "Edit this segment in
  audio editor" + "Mark for split in audio editor" actions in the
  transcript output's segment long-press menu. Push the
  `/edit-audio?path=…&start=…&end=…` or `&mark=…` route; the editor
  seeds the waveform selection / cut marker from the query params,
  force-opens the transcript pane, parks the playhead at the
  seeded start.

**No FFmpeg dependency anywhere in the editor flow.** Decoding via
miniaudio (bundled inside libcrispasr — handles WAV/MP3/FLAC/Ogg/
Opus natively across every supported platform); editing is pure
Dart on Float32 buffers; encoding is the hand-rolled WAV encoder;
rendering is a Flutter `CustomPainter`. All five platforms run
the identical code path.

### §5.1.6 v1 deterministic "Tidy transcript" pass — May 2026

Pure-Dart `TranscriptCleanupService` runs over every segment with
composable transforms in a stable order (annotations → fillers →
repeats → punctuation → whitespace → capitalisation):

- **removeFillers** — strips um / uh / ah / etc. per-language
  default set + custom additions. Word-boundary, case-insensitive;
  "Hummingbird" survives the "hum" filler.
- **collapseRepeats** — "the the cat" → "the cat", repeat-until-
  stable for runs.
- **normalizeWhitespace** — multi-space → one, trim, strip space
  before `.,;:!?`.
- **fixPunctuation** — `..` → `.` (preserves three-dot ellipsis
  via lookbehind), `,,` → `,`, `,.` → `.`.
- **sentenceCase** — unicode-aware (über → Über), skips content
  inside `[]` / `()` / `<>` so annotation tags stay lowercase.
- **stripAnnotations** — off by default (accessibility), strips
  `[laughter]` / `(applause)` / `<noise>` on opt-in.

UI: "Tidy transcript…" entry in the transcript more-actions popup
opens a dialog with toggles for each transform, a custom-fillers
field, and a before/after preview of the first three segments.
"Apply to all" runs the chosen transforms via
`AppState.editSegment` and persists to `HistoryService.update`.

33 hermetic tests pin each transform individually plus the
composed pipeline.

### §5.1.6 v2 BYOK cloud LLM cleanup pass — May 2026

Optional opt-in LLM pass that runs *after* the deterministic v1
on the same Tidy dialog. Pure-Dart `CloudLlmCleanupService` POSTs
each segment to a user-configured OpenAI-compatible
`/v1/chat/completions` endpoint with a conservative "transcript
editor" system prompt. Per-segment failures fall through unchanged
so one rate-limited call doesn't abort the batch.

Settings → Cloud LLM cleanup stores URL / key / model separately;
cleanupBatch reads them lazily so a settings edit takes effect on
the next pass without a restart. Works against OpenAI, Anthropic
via proxy, OpenRouter, Groq, Cerebras, Together, a local llama-
server, etc.

Tests: 13 hermetic via http's MockClient (request shape, Bearer
auth, OpenAI envelope, response parsing, non-2xx error,
TimeoutException, per-segment failure swallow, cancel-token early
exit, progress callback, empty batch) + 3 live tests against
Groq's real API in `test/cloud_llm_cleanup_live_test.dart`, gated
behind `RUN_LIVE_TESTS=1` + a key in `GROQ_API_KEY` (process env)
or in a dotenv file pointed at by `CRISPER_WEAVER_DOTENV`.

§5.1.6 v3 (local LLM via libcrispasr) requires upstream CrispASR
work to promote talk-llama's vendored llama.cpp to a public
sub-library — tracked in
[`docs/upstream-chat-abi.md`](docs/upstream-chat-abi.md) here and
`CrispASR/docs/prompts/chat-abi.md` in the CrispASR repo.

### §5.1.7 Templates / presets — May 2026

Saves the current `(backend, modelId, language, AdvancedOptions)`
tuple as a named preset. One-tap Apply restores all four
atomically; useful for users who jump between workflows.

`PresetService.all()` (oldest-first), `add()` (auto-disambiguates
name collisions with `(2)` suffix), `update()` (overwrites by id;
falls back to add when id is unknown), `remove()`, `clear()`.
AdvancedOptions ↔ JSON: 27 fields incl. three enums; toJson writes
the current shape with a `schemaVersion` stamp; fromJson is
defensive — unknown extra keys ignored (forward-compat), missing
keys fall through to ctor defaults (backward-compat), unknown
enum values pin to the safe default.

UI: bookmarks icon in transcription_screen AppBar opens a dialog
with "Save current as preset" + per-row Apply / Rename / Delete.
Apply uses the existing `_selectModel` reload path so the engine
swap is identical to a manual model change.

15 new hermetic tests cover round-trip of all 27 fields, defensive
fromJson edge cases, and PresetService end-to-end.

### §5.1.8 Meeting-style summarisation — May 2026

Reuses the §5.1.6 v2 BYOK endpoint to produce structured-Markdown
summaries with three optional sections: Action Items / Key Topics
/ Decisions. `TranscriptSummarizeService` sends a prompt asking
for exactly the requested H2 sections in a strict bullet format
("None" placeholder for empty sections so the parse is
unambiguous). Markdown is split back into per-section bullet lists
by splitting on case-insensitive H2 headers + bullet prefixes
(`- ` / `* ` / `1.`).

UI: "Summarize…" entry in the transcript more-actions popup opens
a dialog with three section checkboxes, a Run button gated on the
cloud config, and a result pane that renders the per-section
bullet lists + a Copy-all (raw Markdown) action.

Tests: 13 hermetic (Markdown parser, HTTP path) + 1 live test
against Groq's llama-3.3-70b-versatile.

§5.1.8 v2 (JSON-schema / tool-call structured output) deferred —
Markdown works identically across every OpenAI-compatible endpoint
without per-provider schema knobs.

### §5.1.11 Global hotkey for push-to-transcribe — May 2026

System-level keyboard shortcut for start / stop recording without
bringing the app to the foreground. Desktop only (macOS / Linux /
Windows); mobile is a no-op since iOS / Android don't expose a
global-shortcut surface. Pure Dart via the `hotkey_manager` package.

`HotkeyService`: broadcast-stream of `keyDown` / `keyUp` so
subscribers (`AudioRecorderWidget`) dispatch on the configured
action. Two modes: **pushToTalk** (key-down starts, key-up stops)
and **toggle** (key-down toggles). Action read fresh on each
event from settings.

Combo persisted as a canonical string in SharedPreferences
(`meta+shift+space`, `control+alt+r`). Parser handles aliases
(cmd / command / win / super → meta; ctrl → control; option → alt)
and canonicalises output (control → alt → shift → meta → key).
F1–F12, letters A–Z, digits 0–9, space / enter / tab / escape /
backspace / delete supported.

UI: Settings → Global hotkey dialog (enable switch + combo
TextField with validation snackbar + RadioGroup for action).
Re-registers with the OS on save. Hidden on mobile.

18 hermetic tests pin the parser (single key, single + multi
modifiers, case-insensitivity, all four modifier alias families,
function keys, digit keys, named keys, empty / unknown modifier /
unknown key error paths, duplicate-modifier dedup) and the
serializer (round-trip, canonical modifier order, idempotent
re-serialisation, case lowering, f-key round trip).

### §5.1.12 Voice clone wizard — May 2026

Linear 3-step guided flow on top of the existing runtime-cloning
surface in the synthesize screen:

1. **Capture** — 10 s mic recording OR file pick (wav/flac/mp3).
   Live countdown, auto-stop, playback preview.
2. **Reference text** — verbatim transcript of what was said.
   Required for backends that align against it (indextts /
   vibevoice-1.5b); empty allowed for audio-only cloners
   (chatterbox / qwen3-tts Base).
3. **Hand-off** — pushes `/synthesize` with the WAV path + ref
   text pre-populated via GoRouter `extra`. User picks the
   target text and a clone-capable model in the existing screen.

Reachable from the Synthesize screen's AppBar. Reuses
`AudioService.startRecording` for the mic path. 3 widget-smoke
tests pin the rendering + stepper labels + Cancel-on-step-1
popping back.

v2 deferred: auto-fill the reference transcript by running the
captured clip through the active ASR engine — saves one step but
bundles the transcription stack into the wizard.

### §5.8 Whisper subtitle formatting — May 2026

Surfaces two whisper-only `TranscribeOptions` fields that were
already in the CrispASR Dart binding but missing from the
CrisperWeaver UI: tokens-per-segment cap and split-on-word-
boundary. Produces SRT-friendly short subtitle lines.

`AdvancedOptions.maxLen` (int slider 0..200; 0 = whisper default,
no cap) + `splitOnWord` (switch gated on `maxLen > 0`). Plumbed
through `AdvancedTranscribeOptions` to `crispasr.TranscribeOptions`
on the whisper file path. Both fields round-trip through
PresetService JSON. Hidden on non-whisper backends.

### §5.8 Whisper alt-token capture (`--alt N`) — May 2026

Closes out the last open `whisper-cli`-equivalent gap. Whisper's
per-step softmax produces a full distribution over the vocab; the
existing API only surfaced the chosen token, which is plausible
but wrong often enough on technical / proper-noun-heavy audio
(`kubectl` → `cubicle`, `Ergodicity` → `Argo-disity`, …) that the
manual-edit workflow assumed users already knew the right text.
This pass exposes the top-N runner-up candidates per token so an
editor can offer tap-to-pick over ambiguous words — the workflow
Otter.ai shipped years ago and no local-first competitor has.

**Lands across four layers** (paired commits in CrispASR `0.5.13`
+ CrisperWeaver):

* **whisper internals** (`CrispASR/src/crispasr.cpp` +
  `include/crispasr.h`): new `whisper_alt_token` struct + a
  parallel `alts` vector on `whisper_sequence` and
  `whisper_segment`, mirrored at every
  `tokens.{clear,push_back,resize}` site so the per-step alts
  stay in lockstep with the chosen tokens through the
  fallback-temperature loop, the truncation-to-`result_len` pass,
  and the `max_len` wrap-segment splitter. Capture happens
  inside `whisper_sample_token` (greedy + sampled), reusing the
  already-computed `decoder.probs`. Beam search is deliberately
  excluded — siblings are beam-conditional rather than greedy
  alternatives. New params field `wparams.alt_n` (default 0 =
  off). Six new public getters
  (`whisper_full_get_token_n_alts` / `_alt_id` / `_alt_p` plus
  `_from_state` variants). The whisper *session* transcribe path
  (which previously returned only segment-level text) now
  populates `seg.words` via `emit_words_from_tokens` with
  `token_timestamps = true`, bringing it in line with
  parakeet / canary and unlocking session-level word alts as a
  side-effect.
* **C-ABI** (`CrispASR/src/crispasr_c_api.cpp`): new
  `crispasr_params_set_alt_n` (low-level), sticky
  `crispasr_session_set_alt_n` (session, matches the
  `setFallbackThresholds` / `setWhisperDecodeExtras` pattern),
  plus per-token accessors (`crispasr_token_n_alts` / `_alt_id`
  / `_alt_p` / `_alt_text`) and per-word session-result
  accessors (`crispasr_session_result_word_n_alts` / `_alt_text`
  / `_alt_p`). `crispasr_session_seg::word` grows a `word_alt`
  subtype + `alts` list; `emit_words_from_tokens` attaches the
  first content-bearing token's alts to the emitted word
  (whisper sub-word BPE means alts for "kubectl" cover the
  discriminating "kub" token only — full word-level enumeration
  would need a per-word token-tree expansion, deferred).
* **Dart binding** (`CrispASR/flutter/crispasr/`): new
  `AltToken` value class + `Word.alts` (defaults to `const []`
  so existing call-sites stay source-compatible), pumped through
  both the low-level `_collectSegments` path (via
  `crispasr_token_*` + `whisper_token_to_str`) and the unified
  `_readSegments` session path (via the new
  `_word_n_alts` / `_alt_text` / `_alt_p` getters). Sticky
  `CrispasrSession.setAltN(int)` raises `UnsupportedError` on
  pre-0.5.13 dylibs so apps can graceful-degrade.
  `TranscribeOptions.altN` (default 0) plumbs through the
  low-level path. Pubspec bumped to `0.5.13`;
  `bindings_smoke_test.dart` pins all nine new symbols.
* **CrisperWeaver**: `AdvancedOptions.altN` — a 0..5 slider in
  the Whisper-only section of Advanced Options. UI caps at 5
  because Whisper's distribution past the top few candidates is
  vanishingly small; memory is ~50 KB/min of audio at the cap.
  `TranscriptionWordAlt` value class + `TranscriptionWord.alts`
  field; both `_mapWhisperSegments` (low-level) and
  `_mapSessionSegments` (session) project the alts list through
  to the engine boundary. `CrispasrEngine` and the isolate
  worker pool both fire `session.setAltN` on every dispatch
  (swallowing `UnsupportedError` for pre-0.5.13 dylibs);
  AdvancedTranscribeOptions mirrors the field so the worker-pool
  payload carries it from the transcribe screen all the way to
  the FFI call. Preset round-trip pinned.

**Editor UI** (`lib/widgets/transcription_output_widget.dart`):
the segment-edit dialog now renders a Wrap of dotted-underline
chips beneath the TextField — one chip per word with non-empty
alts. Tap a chip → popup menu of "alt text + percent" descending
by probability; pick an entry → `replaceFirst` the original word
in the working buffer. The TextField stays a plain editable
buffer so cursor / undo / multi-line all keep working; the chips
are an additive affordance, not a replacement for free-edit.
Off-by-default: when `altN = 0` or the loaded libcrispasr is
pre-0.5.13, every `TranscriptionWord.alts` is empty and the
suggestions block collapses entirely — the dialog is
indistinguishable from the pre-feature version for every user
who doesn't opt in.

l10n: EN + DE strings for the slider + the editor suggestions
block.

**Live verification** —
`flutter/crispasr/test/alt_tokens_live_test.dart` on the
CrispASR side opens a session against `ggml-tiny.en.bin`,
sets `altN: 3`, transcribes `samples/jfk.wav`, and asserts
the four core invariants: ≥1 word has alts, every p ∈ [0, 1]
and the list descends, the chosen token is excluded from its
own alts, and `setAltN(0)` actually clears on a re-decode.
Tagged `live` so a normal `dart test` skips it; runs against
the freshly built dylib on dev boxes. Representative result
on the M1 dev box: 22/22 words on JFK get runner-ups
("Americans → America(4.85%), americ(3.84%),
American(3.35%)" — real morphological alternatives, real
case variants, real punctuation contenders). macOS debug
binary builds clean.

Post-merge polish: bumped the alt-picker popup precision
from 0 decimals (which rounded most sub-1% probabilities to
`0%`) to 1 decimal, so users see real values like `0.0%` vs
`3.4%` when picking between candidates.

**Still pending** — low-priority follow-ups, all tracked in
[PLAN.md → §5.8 `--alt N`](PLAN.md):

* Beam-search alt capture (different semantics; defer until
  asked).
* Full word-level alt enumeration via per-word token-tree
  expansion.
* Widget test for the alt-picker popover (Riverpod + l10n
  scaffolding nontrivial; the live test + the unit / preset
  tests already cover the data path end-to-end).

### §5.8.1 Named speaker recognition (TitaNet + SpeakerDB) — May 2026

Closes the "Speaker 0 / Speaker 1" gap in diarisation output.
Before this pass, recording every 1:1 with the same team
member gave you a transcript that called them "Speaker 0" on
Monday and "Speaker 1" on Tuesday — useless for search /
review. Now the user enrols a voice once and every future
transcription rewrites the numeric cluster labels to the real
name when there's a confident match.

**Pure CrisperWeaver wiring** — the upstream `CrispasrTitaNet`
(192-d L2-normalised speaker embedder) + `CrispasrSpeakerDB`
(file-per-speaker on-disk profile DB) bindings were already
exported through the public CrispASR Dart library; this pass
is the consumer side.

* `lib/services/speaker_id_service.dart`: lazy-opens TitaNet
  + SpeakerDB (multi-second load), serialises concurrent
  matchers with a `Completer` so two parallel diarisation
  passes can't double-init the C side, and exposes
  `isAvailable` / `matchSegment` / `enroll` / `listSpeakers`
  / `deleteSpeaker` / `dispose`. DB dir is
  `<app-docs>/speakers/` so the privacy story holds — nothing
  ever leaves the device. Resolves the TitaNet GGUF by
  basename prefix (`titanet*`) against
  `ModelService.getWhisperCppModels`, mirroring the LID
  service's lookup shape.
* `lib/services/model_service.dart`: new
  `titanet-large-f16` `ModelDefinition` pointing at
  `cstr/titanet-large-GGUF` (~43 MB). `kind: ModelKind.lid`
  so it groups under the LID filter chip in Model
  Management; `backend: 'titanet'` so it doesn't collide
  with the language-ID dispatch path. `_kindForBackend` also
  routes `titanet` → `ModelKind.lid` for any future
  auto-probed registry rows.
* `lib/services/diarization_service.dart`: optional second
  pass after `crispasr.diarizeSegments`. For each unique
  cluster, picks the **longest segment** as the
  representative (most stable TitaNet embedding — the model
  was trained on ≥3 s utterances), slices a centred
  3-second chunk of the loaded PCM, runs **one** TitaNet
  match per cluster (embeddings are roughly stable per
  speaker — re-running per segment would burn CPU for
  nothing), and builds a `Map<int, String>` of
  cluster → name. The final segment-rewrite loop only
  replaces `"Speaker N"` when the map has an entry; below-
  threshold clusters keep their numeric labels. Failure
  modes (TitaNet not downloaded, DB empty, embedding
  threw) all degrade silently to numeric labels.
* `AdvancedOptions.enableSpeakerRecognition` (default
  false): bool gate plumbed through
  `AdvancedTranscribeOptions` →
  `TranscriptionService.transcribeFile` and the standalone
  `TranscriptionService.diarize` (used by the §5.23 Q2 v2
  parallel-pool path). Hidden in the UI when
  `diarizeMethod == energy` (stereo channel IDs already
  disambiguate; speaker ID would add nothing). Preset
  round-trip pinned.
* `lib/screens/speaker_management_screen.dart` at
  `/settings/speakers`: list + delete + enrol. Enrol flow
  has two source modes (a 10-second live mic recording —
  mirrors the voice-clone wizard's capture step — or a file
  picker for any audio CrispASR can decode); name
  uniqueness validated against the on-disk list before
  enrol. Privacy note pinned to the screen header so users
  see "stays on-device" before they hand over a sample.

**Tests** —
`test/speaker_id_live_test.dart` (slow-tagged) pins two
invariants:

* SpeakerDB filesystem round-trip: enrol a synthetic
  L2-normalised vector into a temp dir, close, re-open,
  observe count == 1 and a near-1.0 cosine score on the
  same vector. Exercises the on-disk format the binding
  owns without going through TitaNet — keeps the test
  cheap to run.
* TitaNet end-to-end: embed `test/jfk-2s.wav`, enrol the
  result as "jfk", re-embed the same clip, match against
  the DB, assert score ≥ 0.7 (upstream default
  confidence threshold). Self-match is essentially 1.0 on
  TitaNet so the floor leaves wide margin against
  floating-point drift on any platform.

Both skip cleanly when the dylib / GGUF aren't on disk OR
when the locally built libcrispasr predates the TitaNet ABI
— that's environment state, not a regression in this
codebase. Default-suite coverage extends
`test/advanced_options_test.dart` and
`test/preset_service_test.dart` for the new toggle's default
+ copyWith + JSON round-trip.

**Privacy contract** — the SpeakerDB lives in app docs only.
No cloud sync, no telemetry, no opt-in remote enrolment.
This is intentional and load-bearing: CrisperWeaver's whole
positioning is on-device privacy, and a voice biometric
quietly uploaded somewhere would undo that overnight. Any
future "share enrolled speakers across devices" feature
would have to ship explicit user-controlled export /
import, not silent sync.

---

## Pre-sweep §5.x roadmap items — shipped

These were the original CrisperWeaver §5 items in PLAN.md; full
write-ups now live below. Each section was at one point an open
roadmap item; collapsing them here keeps PLAN.md focused on the
remaining work.

### 5.1 Finish i18n

Two sweeps moved 40+ hardcoded strings from `lib/widgets/` and
`lib/screens/` behind `AppLocalizations`: transcription share/save
menu (TXT/SRT/VTT/JSON), snackbars (load/save/playback/synthesize/
copy failures + success toasts), settings dialogs (Select Engine,
HF Token + label), download-model prompt body, audio-recorder /
diariser / log-viewer tooltips, log popup menu items, streaming
error dialogs. Only the brand string "CrisperWeaver" on the about
screen is intentionally left as a literal. EN+DE entries in
lockstep, guarded by `test/arb_consistency_test.dart`.

### 5.2 iOS build verification

* `cd ios && pod install` succeeds (16 pods).
* `ios/Flutter/Profile.xcconfig` added so CocoaPods stops warning
  about an unwired Profile config.
* `flutter build ios --debug --simulator` — green, 96.8 s.
* `flutter build ios --debug --no-codesign` (device) — green, 56.5 s.
* `PrivacyInfo.xcprivacy` lands in the .app bundle root; Info.plist
  is clean (MinimumOSVersion 13.0, microphone description present).
* Bridging header DON'T DROP IT — `AppDelegate.swift` calls
  `GeneratedPluginRegistrant.register(with: self)`; that class is
  declared in the auto-generated `GeneratedPluginRegistrant.h`
  (Objective-C). The bridging header is the only thing exposing
  the class to Swift.

### 5.3 Android native-lib CI wiring

`release.yml`'s `build-android` job runs
`CrispASR/build-android.sh --vulkan` to cross-build
`libcrispasr.so` + sibling backend `.so`'s for `arm64-v8a`,
drops them into `android/app/src/main/jniLibs/arm64-v8a/`,
then `flutter build apk --release`. v0.4.0 produced a 31 MB
real-ASR APK. Pending: an emulator smoke test.

### 5.4 Windows CI end-to-end validation

`release.yml`'s `build-windows` job runs the CMake shared-DLL
build of CrispASR on a Windows runner, drops DLLs next to
`runner.exe` via `scripts/bundle_windows_dlls.ps1`, zips. v0.4.0
produced a 25 MB `crisper_weaver-windows-x64.zip`. Green for
v0.3.0+. Pending: install on a real Windows box and transcribe
end-to-end.

### 5.5 Real speaker diarization

CrispASR 0.4.5 `crispasr_diarize_segments_abi` wired through
`DiarizationService` (`lib/services/diarization_service.dart`);
the MFCC/k-means stopgap is gone. Default method `vadTurns`
(mono-friendly, no extra model file). Pyannote GGUF + method
picker in Advanced Options shipped as part of round 1.

### 5.6 Backend-specific UX

All four sub-items landed:

- **Voxtral / Granite `--ask` Q&A** — Advanced Options → "Ask the
  audio" prompt field, gated on `askCapableBackends`.
- **Canary / Voxtral source + target language pickers** — paired
  Source/Target dropdowns in Advanced Options, both gated on
  `translationCapableBackends`. Source override falls back to the
  main language picker / autodetect when empty.
- **Beam search toggle** — for every backend that honours it.
- **Parakeet / FastConformer-CTC best-of-N** — slider 1–10 in
  Advanced Options, always visible.

### 5.7 Batch transcription (v0.1.4)

Multi-file drop / pick + serial queue + `BatchQueueCard`.
`TranscriptionJob` (filePath, status, progress, result) lives in
a Riverpod `StateNotifier`. Persistence via SharedPreferences so
a user can close the app mid-batch and resume.

Files: `lib/services/batch_queue_service.dart`,
`lib/widgets/batch_queue_card.dart`, mods to
`lib/screens/transcription_screen.dart`.

### 5.11 LID + forced aligner wiring

- **LID** — `LidService` (`lib/services/lid_service.dart`) reuses
  any multilingual whisper GGUF the user has already downloaded
  (preferring tiny → base → small) and runs it as a pre-step for
  session backends when `language` is "auto". Confidence-gated.
- **Forced aligner** — `AlignerService`
  (`lib/services/aligner_service.dart`) searches for
  `canary-ctc-aligner-*.gguf` / `qwen3-forced-aligner-*.gguf` and
  runs `alignWords` as a post-step when word timestamps are
  requested but the active session backend didn't emit any.

Both no-op silently when the model isn't on disk.

### 5.12 Punctuation restoration (FireRedPunc)

`PuncService` (`lib/services/punc_service.dart`) lazy-loads
CrispASR's `crispasr.PuncModel`, runs per-segment `process()`,
no-ops when no `fireredpunc-*.gguf` is on disk. "Restore
punctuation" toggle in Advanced Options. Catalogued under the
`firered-punc` backend so users can fetch from Model Management.
Round 1 added the `fullstop-punc` multilang variant alongside.

### 5.13 CrispASR registry discovery

`ModelService.refreshFromCrispasrRegistry()` queries the C-side
model registry baked into libcrispasr via FFI. Iterates every
backend `availableBackends()` reports, calls
`crispasr.registryLookup(backend)`, merges canonical entries into
`_discoveredModels`. Runs on every Model Management screen open;
offline-safe (no network).

### 5.14 TTS integration

`SynthesizeScreen`, `TtsService` wrapping
`CrispasrSession.synthesize / setVoice / setCodecPath`,
`ModelKind` discriminator + filter chips in Model Management.
Four TTS backends pre-sweep: vibevoice-tts, qwen3-tts, kokoro,
orpheus. Round 1 added chatterbox / kartoffelbox / indextts /
qwen3-tts-voicedesign / vibevoice-1.5b on top.

### 5.15 mimo-asr session dispatch

XiaomiMiMo MiMo-Audio ASR (two-file backend: main model +
`mimo_tokenizer` companion). Routes the tokenizer through
`crispasr_session_set_codec_path` — same shape as qwen3-tts and
orpheus's codec/tokenizer companions. Catalog ships both files
with `companions: ['mimo-tokenizer-q4_k']` on the main entry.

### 5.16 Build automation

`scripts/build_macos.sh` is the one-shot end-to-end macOS build:
configure cmake into `build-flutter-bundle/`, build all backend
static archives + relink `libwhisper.dylib`, `flutter pub get` +
`flutter build macos`, then `scripts/bundle_macos_dylibs.sh` to
copy + alias dylibs and rewrite install names. Reports linked
backends parsed from `nm` output.

### 5.17 Quality gate + integration tests

* `analysis_options.yaml` promotes lint categories that catch real
  defects to **errors**: `use_build_context_synchronously`,
  `avoid_print`, `unused_*`, `inference_failure_*`,
  `deprecated_member_use`. A regression fails the build.
* `flutter analyze` reports **0 issues**; `flutter test` is
  **green** at every commit.
* `test/backend_dispatch_test.dart` validates the C-API dispatch
  arms — `availableBackends()` shape, per-backend bogus-path
  open-failure path, plus opt-in env-var-gated end-to-end
  synth/transcribe roundtrips for whisper / kokoro / mimo-asr /
  qwen3-tts / vibevoice / orpheus.

### 5.19 Real-time partial display during file transcribe

The engine's `transcribeFile(..., onSegment: …)` hook now feeds
each finished segment into `AppStateNotifier.addSegment` as it
lands, so a 10-min file paints segments incrementally instead of
holding the screen blank for 30 s then dumping the whole transcript
at once. Final `completeTranscription(segments)` call still runs
for the persisted history entry, but the screen has already
rendered the rolling text.

### 5.20 Speaker name labels

Diariser labels ("Speaker 1", "Speaker 2", …) become editable
chips in `TranscriptionOutputWidget`. Tap → rename dialog →
mapping lives in `AppStateNotifier.speakerNames` for the session
and is persisted into history JSON under
`HistoryEntry.speakerNames: Map<String, String>`. Backward-compat
loader treats absent maps as empty so old history entries still
deserialise.

### 5.21 Background download manager + Storage tab

`lib/screens/storage_screen.dart` (Settings → "Storage breakdown")
shows per-backend disk usage with one-click "delete all of X"
action. `(other)` bucket is read-only — those files come from
manual drops or the per-row delete in Use/Manage Models. Throttled
`_downloadWithResume`'s progress callback from ~10 Hz to ~4 Hz
(250 ms) so multi-GB downloads no longer rebuild the UI hundreds
of times per second. ARB strings under `storage*` and
`settingsStorageBreakdown*` (en + de).

### 5.18 Test-suite speed — in-app side + MTLBinaryArchive

**In-app side**: default `flutter test` holds sub-5 s by tagging
slow e2e tests with `tags: ['slow']` (env-var-gated; vanilla CI
skips them). Single-process `--tags slow` sweep: ~46 min serial →
~25 min in one process (1.8× via Apple's intra-process MSL
pipeline cache). Test fixtures cut to minimum: `test/jfk-2s.wav`
instead of 11 s, `"Hi."` TTS prompt instead of `"Hello world."`.

**Persistent `MTLBinaryArchive` pipeline cache** (CrispASR commit
[`2665b1e5`](https://github.com/CrispStrobe/CrispASR/commit/2665b1e5)):
serialises compiled `MTLComputePipelineState` objects to disk and
reloads them on subsequent process spawns, eliminating the
~30–60 s shader-compile tax visible on every cold start.

Real-machine benchmark (M1 Max, whisper-tiny + samples/jfk.mp3):

| Run | Whisper time | Wall time |
|---|---:|---:|
| Cold start (cache empty) | 5888 ms | 22.5 s |
| Warm start 1 (cache present) | 4349 ms | 4.6 s |
| Warm start 2 (cache complete) | **370 ms** | **0.6 s** |

That's a 38× wall-clock speedup over the cold path. Storage is
~683 KB per device, auto-managed at
`~/Library/Caches/ggml-metal/<device>.archive`. Override path via
`GGML_METAL_PIPELINE_CACHE`; opt out via
`GGML_METAL_PIPELINE_CACHE_DISABLE=1`.

Implementation in `ggml/src/ggml-metal/ggml-metal-device.m`:
- New file-static helpers (`crispasr_metal_pipeline_cache_url /
  _open / _flush`) own the archive lifecycle.
- `ggml_metal_device_init` opens the archive BEFORE any PSO gets
  compiled, so even the tensor-API-probe `dummy_kernel` benefits.
- `ggml_metal_library_compile_pipeline` switches from
  `newComputePipelineStateWithFunction:error:` to the descriptor-
  based form so `binaryArchives:@[archive]` can be attached. Metal
  consults the archive first; cache hits skip the shader compiler.
  Cache misses fall through to JIT and call
  `addComputePipelineFunctionsWithDescriptor` to push the new PSO
  back into the archive.
- `ggml_metal_device_free` serialises the archive to disk via
  `serializeToURL`. No-op when nothing was added since the last
  serialise (typical for warm-only runs).
- Stale cache from a different ggml-metal build auto-recovers by
  deleting the file and starting fresh. `add-to-archive` failures
  are non-fatal — pipeline already compiled successfully.

Every CrispASR consumer benefits: the CLI, CrisperWeaver, the test
sweep, the OpenAI-compatible local server. CI sweep projected
~25 min → ~5 min after the cache warms on the first run of any
runner.

**Still open** (deferred): CoreML for whisper on Apple Silicon
(`WHISPER_USE_COREML=1` build flag + paired `.mlmodelc`) — next
CrispASR cycle. Re-download q4_k variants for vibevoice / orpheus
— blocked on HF availability.

---

## 5.22 iOS feature parity — static audit + xcframework bundling (shipped, on-device pass pending)

Static-audit fixes applied without an iPhone in hand:

* CoreML companion `.mlmodelc` download was gated `Platform.isMacOS`
  only; every modern iPhone has the Apple Neural Engine, so the
  ANE-targeted companion is just as load-bearing on iOS. Fixed in
  `lib/services/model_service.dart` near `_maybeFetchCoreMLCompanion`.
* `ios/Runner/Info.plist` had two booby-traps that would have made
  iOS launch noisy / unstable on first run, both removed:
  - `NSExtension { NSExtensionPointIdentifier =
    com.apple.widgetkit-extension }` at the host-app level — that
    key only belongs in an extension target's Info.plist; in the
    main app it tells iOS to treat the host bundle as an extension.
  - `UIApplicationSceneManifest` referencing
    `$(PRODUCT_MODULE_NAME).SceneDelegate`, but no
    `SceneDelegate.swift` exists in the target. iOS 13+ would log
    a scene-connection failure on every launch and fall back to
    AppDelegate. Re-introducing the manifest needs a real
    SceneDelegate.swift to land first.
* Custom-models-dir picker hidden on iOS
  (`lib/screens/settings_screen.dart`). The iOS sandbox makes
  arbitrary host paths meaningless without security-scoped
  bookmarks; the default `<app-docs>/models/whisper_cpp/` is the
  only sane location until that flow is built.

**Native library bundling — DONE end-to-end.** Two new scripts wire
the xcframework into the Flutter iOS build:

* `scripts/build_ios_xcframework.sh` — slim iOS-only build (device
  + simulator arm64 slices). The full upstream `build-xcframework.sh`
  builds 7 Apple platform slices in 30–60 min and 7–20 GB of disk;
  this slim variant produces just the two iOS slices in ~1.5 min
  once the cmake configure has run. Cmake flags discovered by trial:
  - `-DCRISPASR_WITH_ESPEAK_NG=OFF` — kokoro otherwise links
    against homebrew's macOS libespeak-ng which doesn't satisfy
    iOS arm64 at link time. Kokoro on iOS therefore can't
    phonemize (one of 30+ backends affected; the rest work).
  - Default `-DCRISPASR_COREML=OFF` when `IOS_MIN_OS_VERSION < 14`
    (CoreML needs iOS 14+). Bump the env var to enable.
  - Glob `src/${release_dir}/lib*.a` to pull in all 30 per-backend
    static archives plus `libcrisp_audio.a` from its sibling build
    dir; without those we get linker errors for
    `_voxtral_init_from_file`, `_kokoro_init_from_file`, etc.
  - Dedup `.o` files by basename across archives: `moonshine`
    and `moonshine_streaming` both ship `moonshine-tokenizer.o`,
    which would cause duplicate-symbol errors at the `clang++
    -dynamiclib -force_load combined.a` step. First lib wins
    (alphabetical order on the per-lib subdirs).
* `scripts/wire_ios_xcframework.rb` — uses the xcodeproj Ruby gem
  (already on disk via CocoaPods) to add the xcframework as a
  linked + embedded framework on the Runner target, with
  `CodeSignOnCopy` so Xcode signs it during build, and adds
  `$(PROJECT_DIR)/Frameworks` to `FRAMEWORK_SEARCH_PATHS`.
  Idempotent.

`flutter build ios --debug --no-codesign` produces
`Runner.app/Frameworks/crispasr.framework` (~4.8 MB stripped, dSYM
separate) with `install_name = @rpath/crispasr.framework/crispasr`,
matching the third candidate in `package:crispasr`'s
`_libCandidates()`. `xcrun dyld_info -exports` confirms 322+
exported symbols including `_crispasr_session_open`,
`_kokoro_init_from_file`, `_voxtral_init_from_file`,
`_whisper_init_from_file`. The xcframework itself is gitignored
(regenerate via the build script); CI wires it via release.yml.

`just_audio` playback configured — `_configureAudioSession()` in
`lib/main.dart` calls
`AudioSession.instance.configure(AudioSessionConfiguration.speech())`
at startup (iOS/Android only). `speech()` is just_audio's
recommended preset for transcription apps: `playAndRecord` +
speaker override + bluetooth allow.

Local rebuild after a CrispASR change:
`bash scripts/build_ios_xcframework.sh && flutter build ios`
(rerun `wire_ios_xcframework.rb` only if the pbxproj was wiped).

**Still pending — needs a real device** (tracked in PLAN.md):
mic permission prompt flow, streaming mic chunk cadence, recording-
→-playback transitions, screen-lock survival, share intake from
Files/Mail, FilePicker → openable path, CoreML mlmodelc loading
log line, `PrivacyInfo.xcprivacy` for App Store Connect (needed
before first TestFlight upload — NSPrivacy* keys in Info.plist
are ignored from May 2024 onwards).

---

## 5.8 Advanced Options completeness — May 2026

All toggles the CrispASR CLI exposes that map cleanly to a Flutter
widget are now in *Advanced Options* on the transcription screen.

* **Temperature** — slider 0.0–1.0, hidden on backends that don't
  honour `crispasr_session_set_temperature` (whisper / mimo-asr /
  wav2vec2 / …); shown for canary, cohere, parakeet, moonshine,
  voxtral, voxtral4b, qwen3, granite, glm-asr, gemma4-e2b,
  omniasr-llm. Threaded through TranscriptionService →
  TranscriptionEngine → CrispASREngine → `_session.setTemperature(t)`
  per-call so a previous non-zero value doesn't stick after the
  user drags back to 0.
* **Best-of-N** — slider 1–10, always visible. Whisper consumes
  via `wparams.greedy.best_of`; other backends loop externally and
  pick the highest-mean-confidence transcript (C-side
  implementation in `crispasr_session_transcribe_lang`).
* **Source-language picker** — paired with the existing target-
  language dropdown. New `AdvancedOptions.sourceLanguageCapableBackends`
  set (strict superset of `translationCapableBackends`) adds
  parakeet / mimo-asr / firered-asr / kyutai-stt / glm-asr /
  gemma4-e2b / omniasr-llm{,-unlimited} / moonshine. Hidden on
  English-only / non-ASR backends (wav2vec2, fastconformer-ctc,
  kokoro, orpheus, chatterbox, indextts, vibevoice-tts, pyannote,
  firered-punc, fullstop-punc). Flows through CrispASREngine →
  both the per-call `language:` arg AND
  `session.setSourceLanguage(lang)` for defense-in-depth.
* **Audio Q&A (`--ask`)** — multiline prompt field, gated on
  `askCapableBackends` (voxtral / voxtral4b / qwen3 / granite /
  glm-asr).
* **Beam search via session API** —
  `crispasr_session_set_beam_size` shipped (CrispASR commit
  `958e6bd7`). Whisper consumes it natively (switches sampling
  strategy to BEAM_SEARCH with the supplied width). Kyutai-STT /
  moonshine / omniasr-LLM wired via existing per-backend setters;
  glm-asr / firered wired via new per-backend
  `<backend>_set_beam_size` setters (commits `66c27c45` +
  `d6ecd1e0`). Six of eleven beam-capable session backends now
  parallel-pool-eligible with beam search ON. Granite / voxtral
  / qwen3 deferred — their beam decode lives in CLI wrappers
  using `core_beam_decode::run_with_probs`, not in the backend
  library; exposing it through the public C API needs per-backend
  refactor work tracked as CrispASR PLAN §90.
  **Update (2026-05-30): granite / voxtral / qwen3 shipped** in
  CrispASR `0c24178e` (an ancestor of tag `v0.6.11`, the bundled
  dylib) — all three now consult `s->beam_size` in the unified
  session path, bringing the wired count to nine. See PLAN §5.23
  for the current breakdown; canary / cohere (AED) remain the only
  genuine beam gap.

---

## 5.23 Batch transcription — scale-out, parallelism, save/resume (shipped May 2026)

What `BatchQueueService` did before this slice: held a
`List<TranscriptionJob>` in a Riverpod `StateNotifier`, serial
drain, no persistence. Worked for 5–20 files; collapsed at scale.
This slice rebuilt the whole batch tier — six commits across four
weeks of bench-side iteration — and turned it into a genuinely
overnight-batch-ready system.

### Q1 foundation — per-job JSON persistence

* Migrated storage to `<app-docs>/batch/default/job-<id>.json`.
  One small file per job; one rename per state mutation. Scales
  to 1000s of jobs without rewriting any per-progress-tick.
* New `BatchPersistenceService` (cross-platform `dart:io` +
  path_provider, same shape as `HistoryService`).
* `BatchQueueNotifier` mirrors every mutation to disk via
  unawaited futures.
* `main.dart`'s post-frame callback hydrates via `load()`.
  Running-when-killed jobs demoted back to `queued` so the next
  drain pass picks them up.
* Per-job filesystem-op serializer (`_serial` lock) keeps
  concurrent unawaited writes from racing each other's rename
  (real bug, caught by the load-test suite — fix: chain ops on
  the same job ID through a per-id future).
* 25 new tests.

### Q1 sub-bullet — backend grouping + duration probe

* Opt-in `Settings.groupBatchByBackend`. Drain loop calls
  `BatchQueueNotifier.reorderByGrouping()` at start, stable-sorting
  only queued jobs by `(backend, modelId, language, createdAt)`.
  Done / error / running rows stay put.
* `AudioService.probeDuration(File)` — header-only `just_audio`
  read via a throwaway player so we don't stomp the shared
  playback session. Sub-second on every supported codec.
* `BatchQueueNotifier` accepts an injectable `durationProbe`
  callback (production wiring fires the audio service; unit
  tests inject a closure for hermetic timing). Stamps
  `durationSec` on each job at enqueue.
* Queue card shows pending-audio sum as a `12m` / `1h12m` chip —
  prefixed `~` when some probes haven't returned yet.
* 12 new tests.

### Q3 — resume from checkpoint after crash

* Per-job append-only `<id>.ckpt.jsonl` written by the drain
  loop on every `onSegment`.
* `BatchQueueNotifier.load()` finds resumable jobs and stamps
  `resumeOffsetSec = lastCheckpointSegment.endTime` on each.
* `transcribeFile` / `engine.transcribe` gained an optional
  `startOffsetSec` parameter. Whisper: `_runChunkedWhisper` skips
  the first `floor(offset / chunkSec)` chunks and reports progress
  relative to the remaining work (no jump-to-30% on tick 1 after
  resume). Whisper non-chunked path + session path: trim leading
  samples + shift emitted segments via new
  `shiftSegmentForResume`.
* Drain loop replays the checkpoint segments into AppState before
  dispatch so the user sees the recovered prefix without a flash.
* `setDone` clears the `.ckpt` — successful runs leave no stale
  files behind.
* 9 new tests.

### Q3 deferred polish

* Mid-batch backend swap awareness — drain loop checks
  `next.modelId` against the engine's `currentModelId` before
  each job and reloads on mismatch. Falls back to the current
  session on load failure (logged warning) so a stale modelId
  from a deleted GGUF doesn't kill the queue.
* iCloud-backup exclusion — new `crisperweaver/ios_helpers`
  MethodChannel in `ios/Runner/AppDelegate.swift` exposes
  `excludeFromBackup(path)` which calls
  `URL.setResourceValues({isExcludedFromBackup: true})`. The Dart
  wrapper in `lib/services/ios_helpers.dart` is a no-op on every
  non-iOS platform, so `BatchPersistenceService._ensureDir`
  fires it unconditionally at first directory create.
* Localised resume snackbar — `BatchQueueNotifier` tracks
  `lastLoadResumedCount` from the most recent `load()`;
  `transcription_screen`'s post-frame callback reads it once and
  shows a `SnackBar` saying "Recovered N interrupted
  transcription(s) — hit Start to resume". Plural-aware ARBs in
  en + de.

### Q2 v1 — pipeline parallelism via audio prefetch

* `SettingsService.maxConcurrentTranscriptions` slider (1–4
  desktop/Android, 1–2 iOS, persisted+clamped).
* When > 1, drain loop kicks off
  `AudioPrefetchService.prefetch(nextFilePath)` — an
  `Isolate.run` worker decodes the audio in parallel with the
  current file's GPU transcription. `AudioService.loadAudioFile`
  consumes the cached PCM or falls through to a synchronous
  decode on cache miss. One session, one model copy in RAM,
  real-world 5–15% wall-time savings on batches of compressed
  audio.
* 9 new tests.

### Q2 v2 — N-way session pool with OOM pre-flight

* `MemoryEstimator` — cross-platform RAM probe (`sysctl
  hw.memsize` on macOS, `/proc/meminfo` on Linux, `wmic` on
  Windows; conservative platform-default constants on iOS /
  Android where shelling out isn't allowed). Computes projected
  RSS = `baseRss + N × on-disk-size × 1.6 overhead` and clamps
  N down to whatever fits in `physicalMemory × 50% − 400 MB`.
  9 hermetic tests.
* `TranscriptionWorker` — top-level isolate entry. Opens its
  own `CrispasrSession.openWithParams` (falls back to plain
  `open` for older builds), bidirectional SendPort protocol for
  `transcribe` / `shutdown` commands + segment streaming. Carries
  every sticky session-state setter (translate / targetLanguage /
  askPrompt / temperature / bestOf / beamSize) and supports
  `transcribeVad` when a VAD model path is supplied. Word
  timestamps round-trip across the SendPort wire. Float32List
  samples pass by transfer (no copy).
* `TranscriptionWorkerPool` — async `spawn(N, modelPath, ...)`
  brings N workers up in parallel, free-list dispatcher with
  completer-based waiters, per-worker `dead` flag for graceful
  degradation when a session crashes, idempotent `shutdown()`.
* `SettingsService.maxConcurrentSessions` slider (1–4 / 1–2 iOS),
  separate from the v1 prefetch knob. Settings UI shows live
  RAM projection ("Projected RAM: 2.4 GB of 16.0 GB (per-worker:
  320 MB)") against the currently-selected default model, with
  an orange "Clamped to N of M workers — model too big" hint
  when the estimator would refuse the slider value.
* Drain loop wiring (option (a) — aggregate batch view):
    1. fires `appStateNotifier.startTranscription()` ONCE at
       batch open (instead of per-job),
    2. dispatches pool-eligible jobs to the pool with the
       in-flight set capped at `pool.size`,
    3. handles pool-ineligible jobs (resume offset / beamSearch
       on non-whisper / tdrz) serially within the same loop
       (pool keeps running between them),
    4. drops the live `addSegment` → AppState path for pool
       jobs (segments still hit `.ckpt.jsonl`); the queue card
       is the source of truth in aggregate mode,
    5. on batch finish, fires one `completeTranscription` to
       settle the screen,
    6. tears the pool down in `finally` even on uncaught errors.
* Spawn failures gracefully degrade to the serial+prefetch path.
  Per-job pool dispatch failures mark the job's row as error and
  the drain loop continues; one bad worker doesn't kill the
  batch.
* `poolEligible(job, adv, enableDiarization)` top-level pure
  function — three genuine blockers left (resume offset / beam
  search on non-whisper / tdrz); everything else (VAD,
  diarization, punctuation, translate, target-lang, Q&A,
  temperature, bestOf, word timestamps) is handled inside or
  alongside the pool dispatch.
* 18 new tests (12 eligibility + 6 wire-format).

### Beam search via session API — six backends parallel-pool-eligible

Worker pool's beamSearch eligibility used to fall through to
serial. The fix was a CrispASR-side new C-ABI
`crispasr_session_set_beam_size` (commit `958e6bd7`) plus
per-backend wiring (commits `66c27c45` + `d6ecd1e0`):

* whisper — native consumption (switches `wparams.strategy =
  BEAM_SEARCH` with the supplied width).
* kyutai-stt, moonshine, omniasr-LLM — wired via existing
  per-backend `<backend>_set_beam_size` setters; just needed
  dispatch calls from `transcribe_single` in
  `crispasr_c_api.cpp`.
* glm-asr, firered — wired via NEW per-backend setters added
  in the same commit batch.

Granite / voxtral / qwen3 remain pending: their beam decode
lives in CLI wrappers using `core_beam_decode::run_with_probs`,
not in the backend library. Exposing it through the public C
API needs per-backend refactor work tracked as CrispASR PLAN
§90.

**Update (2026-05-30):** granite / voxtral / qwen3 shipped in
CrispASR `0c24178e` (ancestor of tag `v0.6.11` = the bundled
dylib). qwen3-asr / granite now run beam via
`core_beam_decode::run_with_probs` *inside* `transcribe_single`,
voxtral via `run_voxtral_family(…, beam_size)` — nine session
backends are beam-wired and no CrisperWeaver change was needed
(the pool already drives `setBeamSize`). canary / cohere (AED,
greedy-only) are now the sole remaining beam gap. See PLAN §5.23.

### Net result

A 100-file overnight batch with VAD + diarization + punctuation
restore + speech translation + temperature sampling now runs
N-way parallel on the pool, with crash-recovery via per-job
checkpoints and progress restoration via the resume snackbar.
The same batch would previously have run serially because each
of those features individually disqualified the job from the
pool. ~190 tests pass on every commit during the slice; stable
across 5 consecutive full-suite runs.

---

## June 2026 — Shipped items archived from PLAN.md

The following sections were completed and archived from PLAN.md on 2026-06-12.

### §5.1 Competitor-gap features — shipped items

#### Shipped (see earlier HISTORY.md entries for full write-ups)

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

#### Shipped open items (formerly listed as strikethrough in §5.1)

* **LID picker — Firered / Ecapa methods** —
  **shipped May 2026**. Upstream CrispASR 0.5.8 extended
  `LidMethod` to all four methods; CrisperWeaver's Advanced
  Options picker now offers all four, the model registry has
  catalogue entries for `firered-lid-f16` + `ecapa-lid-107-f16`,
  and `LidService.methodForFilename` routes by basename.

* **5.1.6 v3.1 Curated chat-model catalogue** —
  **shipped May 2026**. 5 entries spanning small/medium/large
  buckets + ≥ 2 families (SmolLM2-360M, Qwen2.5-0.5B,
  Llama-3.2-1B, Qwen2.5-3B, Llama-3.2-3B — all Q4_K_M via
  bartowski/* HF repos). Settings → Local LLM gets a
  "Suggested chat models" picker; Model Management gets a
  Chat-LLM filter chip. Recommended `nCtx` / `nGpuLayers`
  values live in the model description text — users tune via
  the existing Advanced section sliders.

* **Responsive UI — phone sub-screens for Settings dialogs**
  — **shipped May 2026**. The Cloud LLM / Local LLM / Hotkey
  dialogs now route to dedicated sub-screens
  (`/settings/cloud-llm` / `/settings/local-llm` /
  `/settings/hotkey`) on phone-width viewports, sharing the
  same form-widget body with the wide-layout dialogs. See
  CHANGELOG → "Responsive UI — Settings sub-screens on mobile".

* **Platform-native share / receive — shipped sub-items:**

  - **iOS Share Extension target wiring** — **shipped
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
  - **macOS Open-With handler** — **shipped May 2026**.
    `OpenWithReceiver.swift` + Dart-side `DesktopOpenWithBridge`
    feed Finder's Open With / `open foo.wav` from the terminal
    / dock-drop into `ShareIntakeService.acceptPaths`.
  - **macOS NSServices** — **shipped May 2026**. Right-click
    a file in Finder → Services → "Transcribe with
    CrisperWeaver" routes the file URLs through the same
    OpenWithReceiver buffer as Open-With. Info.plist
    NSServices entry + `AppDelegate.transcribeAudio(_:userData:error:)`
    + `NSApp.servicesProvider = self` in
    `applicationDidFinishLaunching`.
  - **Windows file association** — **shipped (config
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

* **5.8.1 Named speaker recognition (TitaNet + SpeakerDB)** —
  **shipped May 2026**. See earlier HISTORY.md entry for the
  full write-up.

* **5.1.10 Audio enhancement before transcribe** —
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

### §5.8 Advanced-Options — shipped items

* **GBNF (grammar-constrained sampling)** —
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

* **CrispASR CLI features — shipped items:**
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
    write-up in earlier HISTORY.md entry "§5.8 Whisper alt-token
    capture". Four-layer landing: whisper internals capture top-N
    runners-up on each greedy step; C-ABI exposes token + word
    accessors; Dart binding surfaces `Word.alts`; CrisperWeaver
    wires through AdvancedOptions / preset / worker pool and renders
    tap-to-pick chip row in the segment edit dialog.
    - ✅ Widget test for the alt-picker popover — **shipped May 2026**
      as `test/alt_picker_widget_test.dart`.
    - ✅ Live-tagged end-to-end test — **shipped May 2026** as
      `flutter/crispasr/test/alt_tokens_live_test.dart`.
  - ✅ Whisper decoder fallback thresholds (`--entropy-thold`,
    `--logprob-thold`, `--no-speech-thold`, `--temperature-inc`
    / `--no-fallback`) — **shipped May 2026 (CrispASR 0.5.10 +
    CrisperWeaver)**.
  - ✅ Subtitle line formatting `--max-len` / `--split-on-word`
    (May 2026). ✅ `--split-on-punct` **shipped June 2026**.
  - ✅ Token suppression (`--suppress-nst`, `--suppress-regex`)
    and `--carry-initial-prompt` — **shipped May 2026 (CrispASR
    0.5.11 + CrisperWeaver)**.

* **Auto-download default** — CrispASR's `-m auto` per backend.
  **✅ Option (a) shipped (May 2026).** Per-backend recommended-default
  + "Recommended" badge. `ModelService.recommendedDefaultModels` map,
  `defaultForBackend()`, one-tap download banner in Transcribe picker.
  **✅ Option (b) Quick-start bottom-sheet shipped May 2026 (v0.6.48).**
  Curated starter set with per-item + one-tap "download all".

### §5.9 Dependency refresh — shipped June 2026

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

### §5.23 Batch transcription — shipped May 2026

✅ **Shipped May 2026.** All four sub-questions (Q1 foundation,
Q1 grouping + duration probe, Q2 v1 pipeline prefetch, Q2 v2
N-way session pool with OOM pre-flight + worker-protocol
expansion + drain-loop integration, Q3 resume-from-checkpoint,
Q3 polish) shipped end-to-end. Full per-step write-up in
earlier HISTORY.md entry "§5.23 Batch transcription".

**CrispASR-side beam follow-up — ✅ shipped upstream (CrispASR 0.6.11).**
The earlier "granite / voxtral / qwen3 still pending" note was
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

### §5.24 Backend wiring — shipped items

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

**F. Text-LID — shipped May 2026 (v0.6.43).** C-ABI
(`crispasr_text_detect_language`) + Dart wrapper
`detectTextLanguage(text, modelPath)` → `TextLanguage(code,
confidence)` (CrispASR `1332c5a1`, live-verified de/en/fr/es ≥ 0.99).
Both app-side pieces landed: (a) `cld3-f16` is catalogued
(`kind: ModelKind.lid`, `cstr/cld3-GGUF`, ~430 KB) in
`model_service.dart`; (b) the Translate screen's *Auto-detect source
language* button runs `detectTextLanguage` over the typed text and sets
the source-language dropdown, prompting a CLD3 download if it isn't
present (`translate_screen.dart`). **shipped May 2026 (v0.6.48)**: a
"Detect language" action on the transcript output overflow menu runs
`detectTextLanguage` over the current transcript and reports the
language + confidence.

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

### §5.25 Next-generation features — all 14 shipped (June 2026)

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

* **5.25.2 ⚡ Semantic transcript search via CrispEmbed** — ✅
  **Scaffold shipped June 2026.** `SemanticSearchService` provides
  a TF-IDF fallback scorer that ranks segments by word-overlap
  relevance (better than substring matching for natural language
  queries). `cosineSimilarity()` helper ready for when real
  CrispEmbed vectors are available.

  **Files:** `lib/services/semantic_search_service.dart`.

  CrispEmbed Dart FFI binding added as a path dependency.
  `crispEmbedProvider` lazy-loads the first downloaded
  `ModelKind.embed` GGUF. History screen passes the embedder to
  `SemanticSearchService.search()` for real cosine-similarity ranking.
  Embedding cache avoids re-encoding. `all-MiniLM-L6-v2` (384-dim,
  ~23 MB Q8_0) catalogued.

  Follow-ups shipped: (a) vector persistence — **shipped June 2026**.
  (b) audio embedding — **shipped June 2026**. Cross-modal search
  via `crispembed_encode_audio`; `audioEmbedding` persisted per entry;
  `bidirlm-omni-2.5b-q4_k` (2048-d, ~1.7 GB) catalogued.

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

* **5.25.4 Speaker-adaptive vocabulary** — ✅ **Shipped
  June 2026.** `SpeakerVocab` model with per-speaker term lists,
  persisted as `<name>.vocab.json` alongside `.spk` profiles.
  `mergeForSpeakers(allVocabs, identifiedSpeakers)` computes the
  union of all active speakers' terms for injection into
  `initial_prompt`. Wired: after diarisation resolves speaker names,
  `SpeakerVocab.mergeForSpeakers()` injects domain terms into
  `advancedOptionsProvider` vocabulary for subsequent transcriptions.
  Vocab editor dialog accessible from Settings → Diarization →
  Speaker Vocabulary.

  **Files:** `lib/models/speaker_vocab.dart`.

* **5.25.5 Multilingual simultaneous transcription** — ✅ **Service
  shipped June 2026.** `MultilingualTranscriptionService` runs
  per-segment LID (via `LidService.detectIfModelAvailable`) on each
  segment's PCM slice and tags it with `metadata['lang']`. Static
  `groupByLanguage()` groups consecutive same-language segments for
  optional re-transcription with a language-specific model. Toggle in
  Advanced Options ("Tag segment languages").

  **Files:** `lib/services/multilingual_transcription_service.dart`.

* **5.25.6 Audio chapter markers / podcast show notes** — ✅
  **Service shipped June 2026.** `ChapterDetectionService` detects
  topic shifts via sliding-window Jaccard distance between segment
  vocabularies. Exports to YouTube chapter format (`HH:MM:SS Title`)
  and Podcasting 2.0 `podcast:chapters` JSON. Three export actions in
  the transcript share menu.

  **Files:** `lib/services/chapter_detection_service.dart`.

#### Tier B — Medium impact, fills real user gaps

* **5.25.7 Transcript diff / comparison view** — ✅ **Shipped
  June 2026.** `TranscriptCompareScreen` accepts two history entry
  IDs, aligns segments by timestamp overlap, and renders a
  side-by-side view with LCS-based word-level diff highlighting.
  Stats row shows word counts + Jaccard similarity.

  **Files:** `lib/screens/transcript_compare_screen.dart`,
  `lib/services/history_service.dart` (`loadEntry`).

* **5.25.8 Watch-folder / scheduled transcription** — ✅ **Shipped
  June 2026.** `WatchFolderService` monitors a user-configured
  directory via `FileSystemEntity.watch()`. New files with audio
  extensions trigger a 2-second debounce. Settings → "Watch folder"
  section (desktop-only) with enable toggle + folder picker.

  **Files:** `lib/services/watch_folder_service.dart`,
  `lib/screens/settings_screen.dart`, `lib/services/settings_service.dart`.

* **5.25.9 TTS pronunciation lexicon** — ✅ **Shipped June 2026.**
  `PronunciationLexicon` model with word-boundary-aware text
  substitution, JSON persistence at `<app-docs>/lexicon.json`. Wired
  into `TtsService.synthesize()`. Lexicon editor card in Synthesize
  screen's Advanced section.

  **Files:** `lib/models/pronunciation_lexicon.dart`,
  `lib/services/tts_service.dart`.

* **5.25.10 Transcript annotation / tagging system** — ✅ **Model
  shipped June 2026.** `SegmentTag` enum with 7 tag types. Tags in
  the long-press menu, persisted in history JSON, and filterable via
  tag chips on the History screen.

  **Files:** `lib/models/segment_tag.dart`.

* **5.25.11 Audio fingerprint deduplication** — ✅ **Shipped
  June 2026.** `AudioFingerprintService` computes SHA-256 fingerprints
  from the first 30 s of PCM. Wired: watch folder auto-skips
  duplicates; batch enqueue silently skips; single-file drag-drop
  shows a confirmation dialog.

  **Files:** `lib/services/audio_fingerprint_service.dart`.

#### Tier C — Lower effort, high polish

* **5.25.12 Keyboard-driven transcript navigation** — ✅ **Shipped
  June 2026.** J/K/↑/↓ segment navigation, Space play/pause, Enter
  edit, Tab jump-to-next-low-confidence, Escape deselect.
  Implemented directly in `TranscriptionOutputWidget`.

  **Files:** `lib/widgets/transcript_keyboard_nav.dart`.

* **5.25.13 Model A/B testing mode** — ✅ **Shipped June 2026.**
  `AbTestResult` stores per-segment winner picks. `ModelRatings`
  aggregates results into a win-rate leaderboard. Two single-worker
  pools run in parallel via `Future.wait`. Persisted to
  `<app-docs>/model_ratings.json`.

  **Files:** `lib/services/ab_test_service.dart`.

* **5.25.14 Export to note-taking tools** — ✅ **Shipped June 2026.**
  `NoteExportService` with four pure formatters: `toObsidian`,
  `toNotion`, `toLogseq`, `toYouTubeChapters`. All support segment
  tags. Wired into the transcript share menu.

  **Files:** `lib/services/note_export_service.dart`,
  `lib/screens/transcription_screen.dart`.

### §5.26 CrispASR mid-2026 catch-up — shipped June 2026

Brings CrisperWeaver up to CrispASR `origin/main` as of June 2026.
Covers new backends, new capabilities (hotwords, speech-to-speech),
and free improvements from linking against the latest engine binary
(long-form chunking, global diarization, beam search expansion,
permissive G2P). Full write-up in earlier HISTORY.md entry
"June 2026 — CrispASR mid-2026 catch-up (§5.26)".

#### 5.26.1 New backend catalog entries

Four new backends added upstream since the last parity sweep:

| Backend | Type | Size | Notes |
|---------|------|------|-------|
| **LFM2-Audio 1.5B** | ASR+TTS+S2S | ~1.6 GB (Q5_K) | LiquidAI hybrid conv+attention |
| **Mini-Omni2** | ASR+TTS+S2S | ~1.0 GB (Q4_K) + ~80 MB SNAC codec | Whisper + Qwen2 0.5B |
| **MOSS-Audio 4B** | ASR (audio understanding) | ~3.8 GB (Q4_K) | Audio-understanding backend |
| **Parakeet-RNNT 0.6B/1.1B** | ASR | ~447 MB / ~770 MB (Q4_K) | Standard RNN-Transducer |

#### 5.26.2 Hotwords / contextual biasing UI

Session-level `crispasr_session_set_hotwords` + Dart FFI + UI in
Advanced Options. All 3 transcription paths wired. 13 unit + 2 live tests.

#### 5.26.3 Speech-to-Speech mode

`crispasr_session_speech_to_speech` C API + Dart FFI + S2S toggle on
Synthesize screen (lfm2-audio/mini-omni2 only). 3 unit + 1 live test.

#### 5.26.4–7 Free upgrades (no code change)

- Global diarization, long-form chunking, permissive G2P, beam search 18/24.

---

# Archived from PLAN.md — 2026-08-03

Everything below was a completed PLAN.md section. It was moved here so
PLAN.md holds only what is still open; nothing was rewritten in the move.

**Section numbers are preserved deliberately.** 436 comments across 86
files in `lib/`, `bin/` and `macos/Runner/` cite these numbers (`§5.25.8`,
`§12.8h`, `§9.6` …), so renumbering would silently break every one of
them. A reference to a section you cannot find in PLAN.md is here.

| Archived section | What it was |
|---|---|
| §0 | CrispASR 0.6.x parity sweep (May 2026) — shipped in v0.4.1 |
| §8 | Codebase optimisation plan — 8.1–8.9 done, 8.6 deferred by decision |
| §9 | CrispASR parity + full test coverage + CLI/server parity (June 2026) |
| §10 | CrispASR 0.7.x parity sweep (June 2026) |
| §11 | CrispASR 0.8.x parity sweep (June 2026) |
| §12 | CrispASR 0.8.7 + CrispEmbed 0.13.0 integration sweep (July 2026) |
| §13 | EU AI Act compliance (July 2026) — the original sweep |
| §14 | CrispASR 0.8.12 + CrispEmbed 0.15.1 dependency update (July 2026) |
| §15 | EU AI Act audit remediation (August 2026) — rounds 1–2 write-up |
| §16 | EU AI Act audit round 2 (2026-08-02) |
| §17 | Store-readiness audit round 7 (2026-08-03) |

Audit rounds 3–6 were recorded in `docs/AI_ACT_RISK.md` §9 rather than in
PLAN.md, and stay there — that document remains live, not archived.

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

## 17. Store-readiness audit round 7 (2026-08-03)

Seventh audit, and the first driven by the App Store submission rather than
by Art. 50. Three findings. The AI Act controls themselves came through
clean: `synthetic_compliance_test.dart` and `compliance_boundaries_test.dart`
pass 155/155, every subsystem classification in `docs/AI_ACT_RISK.md` §2 was
re-read against the code, and no new route to a generating capability had
appeared since round 6. What had appeared was a **second platform** and a
**public-facing surface nobody had been enumerating at all**.

### 17.1 The watch folder was silently dead in the sandbox

`AppStore.entitlements` sandboxes the Mac App Store target, where
`files.user-selected.read-write` grants access only for the session in which
the open panel ran. `SettingsService.watchFolderPath` persisted a raw path
string and `main.dart` restarted the watcher from it on every launch, so from
the second launch onward the folder was unreadable.

What made it a defect rather than a known platform limit is *how* it failed. A
sandbox denial makes `stat` fail, so `Directory.existsSync()` returns false
exactly as it does for a deleted folder; `WatchFolderService.start` took its
"directory does not exist" branch and returned. Settings went on showing the
path with the toggle reading enabled, over a watch that was not running. The
feature is also one of the few **not** behind `experimentalFeatures`, so it
sits on the default surface a TestFlight tester reaches.

Fixed with real security-scoped bookmarks — `macos/Runner/SecurityScopedBookmarks.swift`
plus `lib/services/security_scoped_bookmarks.dart` — minted in the same session
as the open panel, which is the only moment macOS will grant one. Deferring
creation to the next launch is precisely the bug. Related changes:

- `com.apple.security.files.bookmarks.app-scope` added to
  `AppStore.entitlements`. Without it `bookmarkData(.withSecurityScope)`
  throws, `create()` returns null, and the whole fix reverts to the old
  behaviour silently — which is why the test asserts the entitlement.
- The Swift file registered in all four `project.pbxproj` sections. A Flutter
  macOS target lists its sources explicitly; an unregistered file compiles to
  nothing and the channel is simply absent at runtime.
- `start()` now returns `WatchFolderStartResult` instead of only logging, so
  the caller can tell "gone" from "no grant".
- `watchFolderAccessLost` records the failure so Settings can say the folder
  needs re-picking. Deliberately a stored flag and **not** an `existsSync()`
  probe in `build`: outside the launch path the app holds no scope on the
  folder, so probing would report every healthy sandboxed folder as missing.
- The bookmark follows a moved or renamed folder, so the resolved path wins
  over the stored one and is written back; a stale-but-resolvable bookmark is
  re-minted while access is still live.

Found while fixing it: the watch-folder Settings handlers had lost their
`setState`, so the UI did not refresh after toggling or picking a folder.

### 17.2 The store listing kept a claim the project retracted a day earlier

Round 2 (2026-08-02) corrected an inaccurate "no data is transmitted" claim in
`docs/AI_ACT_RISK.md` §1 and rewrote `PRIVACY.md` around the two opt-in network
features. `STORE_LISTING.md` was not part of that change and still read *"All
processing happens on your device — no cloud, no accounts, no data
collection"* and *"Everything runs on-device — no data leaves your phone or
computer"*.

This is the project's own recurring defect — a claim fixed where it was
noticed and missed on a surface reached by another route — landing on the most
public surface there is. Two things make it worse than an internal doc drift.
Store metadata is the copy a user reads *before* installing, and it is the text
the App Store Connect App Privacy and Play Data safety answers get filled in
from, so one absolute claim propagates into two console declarations that are
formally attested. The exposure is mostly **not** AI Act — Art. 50 governs
marking, not marketing — it is App Store Guideline 2.3.1 and consumer law, and
it undercuts the Art. 50(1) first-use notice, which correctly tells the user
which subsystems can use the network.

Rewritten against `PRIVACY.md` §3.1–3.3, which is the authority, and a console
questionnaire section added so the listing and the two store declarations are
answered from one place. `test/store_listing_claims_test.dart` pins it in both
directions: the retracted absolutes must not return, **and** the opt-in
features must stay named — banning phrases alone would pass on a listing that
simply deleted the disclosure.

That test carries one lesson worth keeping. Written the obvious way it did not
catch the original text: the claim read `no cloud, no accounts, no\ndata
collection`, wrapped across two lines by ordinary markdown reflow, and a plain
substring check for "no data collection" passes on that. Prose wraps; the
matcher collapses whitespace before comparing. Verified by running it against
`git show HEAD:STORE_LISTING.md` — 7 failures — rather than trusting a green
run on the fixed file.

### 17.3 The local-network purpose string described the developer's use

`NSLocalNetworkUsageDescription` read *"Allow CrisperWeaver to connect to its
development host on the same Wi-Fi for hot-reload and debugging"* — accurate
for the Dart VM service in debug, and text no shipping user can act on. The
release trigger is the optional OpenAI-compatible server, which binds a
listening socket and raises the prompt the moment it starts;
`settings_screen.dart` says so in a comment. Guideline 5.1.1 wants the string
to explain the access the person reading the alert is actually granting.
Rewritten around the server, with the debug consumer kept in the comment.

### 17.4 Checked and clean

Recorded because the scope of a negative result is part of the finding:

- **Guideline 2.5.2** — every `DynamicLibrary.open` in `lib/` uses a bundled
  name. The `--lib` / `CRISPASR_LIB` override lives only in
  `bin/crisperweaver.dart`, which is not in the bundle.
- **GPL / App Store** — `release.yml` deliberately does not bundle espeak-ng
  (GPL-3.0); it is `dlopen`-only and `otool -L` confirms no linkage on the
  shipped dylib, so the VLC-style conflict is not triggered. The bundled
  `espeak-ng-data.tar.gz` is a 156-byte placeholder on Apple builds; built-in
  G2P covers EN/DE/FR/ES.
- **AGPL** — sole copyright holder, so App Store distribution infringes no
  third party's licence.
- **First-run dead end** — `kokoro-82m-q8_0` declares
  `companions: ['kokoro-voice-af_heart']` and the Models screen queues
  companions with the main model, so the top TTS starter pick is usable.
- **Both self-hosted servers** still bind loopback by default (round 6, §7.6).

### 17.5 The generalisation, after seven

Round 6 landed on *"where can this text end up outside the app?"* — a question
about exits. All three findings here are outside that frame. The watch folder
is not an exit and marks nothing; it broke because a **second build target**
has different rules from the one the feature was written against. The store
listing is not code at all. The purpose string is a sentence in a plist.

So the extension is: a claim is a surface too, and a build target is a route.
The check that would have caught 17.1 is "which targets does this feature run
under, and do they grant the same things?" The one that would have caught 17.2
is "when a statement about the software changes, where else is that statement
written down?" — and the answer has to include the places that are not in
`lib/`.

---

## §5.1.11 On-device compressed codec via glint — shipped (archived from PLAN.md 2026-08-03)


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

