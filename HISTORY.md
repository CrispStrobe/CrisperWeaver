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
