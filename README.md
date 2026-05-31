# CrisperWeaver

**On-device speech recognition + text-to-speech. No cloud. 30+ model families, one app.**

CrisperWeaver is a cross-platform Flutter app for fully-offline audio transcription and speech synthesis. Drop in a file, paste a URL, or record with the mic — audio never leaves the device. 29+ open-weight ASR families and 8 TTS families are supported through a single unified engine ([CrispASR][crispasr]): Whisper (+ Distil-Whisper), Parakeet, Canary, Voxtral, Qwen3-ASR (+ Mega-ASR LoRA), Cohere, Granite (3.x + 4.1 family), FastConformer-CTC, Canary-CTC, Wav2Vec2, OmniASR (+ streaming "unlimited" variant), FireRed, Kyutai-STT, GLM-ASR, Moonshine, VibeVoice ASR, MiMo ASR, **Gemma4-E2B** (140+ languages), **FunASR** (Mandarin + EN), **Paraformer-ZH**, **SenseVoice** (built-in language ID) — plus Kokoro / VibeVoice / Qwen3-TTS / Orpheus / **Chatterbox** / **Kartoffelbox** / **IndexTTS** / **VoxCPM2** for synthesis, **Pyannote v3** for ML diarisation, FireRedPunc + **fullstop-punc** for punctuation restoration, **Silero LID** for language detection, and FireRed/MarbleNet/Whisper-VAD-EncDec VAD options.

[crispasr]: https://github.com/CrispStrobe/CrispASR

![AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue) ![Flutter 3.38](https://img.shields.io/badge/flutter-3.38-blue) ![macOS · Linux · Windows · iOS · Android](https://img.shields.io/badge/platforms-macOS%20·%20Linux%20·%20Windows%20·%20iOS%20·%20Android-lightgrey)

### Part of the Crisp ecosystem

| Project | Role |
|---|---|
| **[CrispASR](https://github.com/CrispStrobe/CrispASR)** | C++ ASR + TTS engine powering this app — 24+ backends, CLI + C-ABI, 3.8x faster than voxtral.c |
| **CrisperWeaver** | This app — Flutter GUI for CrispASR |
| **[CrispEmbed](https://github.com/CrispStrobe/CrispEmbed)** | Text embedding engine (ggml) — XLM-R, Qwen3-Embed, Gemma3, dense + sparse + ColBERT |
| **[Susurrus](https://github.com/CrispStrobe/Susurrus)** | Python ASR GUI with 9 backends (faster-whisper, mlx-whisper, voxtral, ...) |

---

## What you can do

- **Transcribe any audio file** — WAV / MP3 / FLAC decoded on-device, no ffmpeg required.
- **Batch-process multiple files** — drop many onto the window or onto the Batch Queue card, "Transcribe all" drains serially; each run lands in History.
- **Record from the mic** and transcribe live.
- **Paste a URL** to a remote file; CrisperWeaver downloads and processes it.
- **Drag and drop** files onto the transcription screen (desktop) or directly on the batch queue.
- **Receive shared audio** from the OS share sheet (Android / iOS / macOS).
- **Choose your model family and quantisation** — q4_0 / q5_0 / q4_k / q5_k / q6_k / q8_0 variants plus f16 originals. Model picker filters by name + backend; Model Management screen auto-probes HuggingFace to discover every available quant.
- **Add from HuggingFace repo** — link-icon button on the Models screen accepts any `OWNER/NAME` HF repo (e.g. `cstr/voxtral-mini-3b-2507-GGUF`), lists the GGUF / .bin files under your chosen backend, and registers them as downloadable models. Mirror of `crispasr --hf-repo` on the CLI side; escape hatch for repos not yet in the baked catalogue.
- **Download and manage models** from a built-in browser — parallel queue, resume, SHA-1 verify, cancel, delete. Companion files (codec / voice / tokenizer GGUFs) auto-download alongside their parent model, including for runtime-discovered HF quants.
- **Advanced decoding knobs** — translate-to-English (Whisper), beam search, initial-prompt vocabulary bias (huge win for domain audio), audio Q&A prompt for instruct-tuned LLM backends (Voxtral / Qwen3), source + target language pickers for true speech translation.
- **Tune the decoder live** — best-of-N slider (1–10, picks the highest-scoring of N decodes; works on every backend) and decoder temperature slider for every backend `crispasr_session_set_temperature` honours (canary, cohere, parakeet, moonshine, voxtral, qwen3, granite, glm-asr, gemma4, omniasr-llm, kyutai-stt).
- **Tune the VAD** — pick between Silero (bundled), FireRedVAD (F1 97.57%), MarbleNet, Whisper-VAD-EncDec; live sliders for threshold, min-speech-ms, min-silence-ms, speech-pad-ms.
- **Pick the diarisation method** — vad-turns (default, mono-friendly), pyannote (ML, GGUF), stereo energy, stereo cross-correlation.
- **Pick the language-detection method** — Whisper-encoder LID (reuses an existing model) or Silero 95-langs (faster + smaller).
- **See live performance numbers** — real-time factor, words per second, wall-clock.
- **Get word-level timestamps** and language auto-detection (via Whisper).
- **Stream transcription** from long-running mic input — partial transcripts appear in the output card while you talk (10 s sliding window / 3 s step).
- **Watch long files transcribe in real time** — chunked Whisper splits >60 s files into 30 s windows and streams segments through as each finishes, instead of waiting until the end.
- **Export** to `.txt`, `.srt`, `.vtt`, `.json`, `.csv`, `.lrc` (lyrics), or `.wts` (Whisper Text Segments debug) through the system share sheet.
- **Review history** — every run is persisted as JSON and browseable / re-exportable, with speaker renames preserved across launches.
- **Rename diariser speakers** — tap a speaker chip in the output to override the auto-assigned label ("Speaker 1" → "Alice"); the new name persists in history.
- **See where storage went** — Settings → Storage breakdown lists per-backend disk usage with a one-click "delete all of X" action.
- **Diagnose with logs** — in-app viewer with filter / search / copy / export, optional file sink.
- **Synthesize speech (TTS)** — pick a downloaded TTS model + voice + codec on the *Synthesize* screen, type text, hit *Synthesize*; output plays in-app and saves as WAV. Advanced section adds trim-silence, 0.25×–4× speed slider, reference-transcript field for runtime voice cloning, and natural-language voice-design prompts (qwen3-tts VoiceDesign).
- **Translate text** — dedicated *Translate* screen wired to CrispASR's `crispasr_session_translate_text`. Pick from M2M-100 (100 langs, any-to-any), WMT21 Dense (en↔X, two separate checkpoints), or MADLAD-400 (419 langs); source/target language dropdowns with one-click swap, max-tokens slider, copy-to-clipboard.
- **Bake your own voice** — *Bake voice* screen drives CrispASR's `bake-chatterbox-voice-from-wav.py` via `Process.start`: pick a WAV reference, set the output filename, hit *Bake*. Stdout + stderr stream into a live tail panel + the in-app Log viewer; the resulting GGUF is dropped straight into the models directory so it shows up in the voicepack picker on the next open. Desktop-only — mobile has no Python runtime. Available from the cake icon in the *Synthesize* app-bar.
- **Restore punctuation** — FireRedPunc (ZH+EN) or fullstop-punc (EN/DE/FR/IT) toggle in Advanced Options; turns `wav2vec2 / fastconformer-ctc / firered-asr` lowercase output into properly punctuated text. Picker chooses which family runs when both are downloaded.
- **Use CrisperWeaver in English or German** — full i18n scaffold via `flutter_localizations`, every user-facing string covered (guarded by an ARB-consistency test).
- **Capture system audio** — "Transcribe what's playing in Zoom / YouTube / any app." ScreenCaptureKit on macOS 13+, `parec` on Linux, ffmpeg-WASAPI loopback on Windows, MediaProjection on Android 10+; iOS deliberately unsupported (Apple's sandbox forbids it).
- **Boost custom vocabulary** — chip list in Advanced Options; routed per-backend-class via `initial_prompt` (whisper / moonshine), `setAsk` prefix (audio-LLM backends), or no-op (CTC-style with explanatory helper text).
- **Edit any segment inline** — long-press → edit dialog. Edits update both AppState AND the on-disk history JSON so they survive a reload. Edited segments get a pencil-icon marker.
- **Search history** — substring filter on title + transcript with yellow-highlighted matches; auto-expand of matching entries.
- **Edit audio with waveform sync** — dedicated audio editor screen with trim / cut middle / split into chapters + an optional collapsible transcript pane on the same screen. Tap a segment → playhead jumps. Long-press a segment → Select / Trim to / Mark for split. Tap the waveform → matching segment highlights. Pure-Dart, no FFmpeg, identical on every platform.
- **Tidy any transcript** — pure-Dart deterministic pass (filler removal, repeat collapsing, sentence-case, punctuation fix, optional annotation strip) with a before/after preview of the first three segments. Optional opt-in LLM pass on top via a three-mode selector: **Off** (deterministic only), **Cloud** (bring your own OpenAI-compatible endpoint — OpenAI / Anthropic via proxy / OpenRouter / Groq / Cerebras / Together / local llama-server; key stays on device), or **Local** (point at a GGUF chat model on disk and run it on-device via Metal / CUDA / CPU through libcrispasr's chat ABI — no network, no API key, model stays warm across passes).
- **Summarise meetings** — Action Items / Key Topics / Decisions as structured Markdown, via either the cloud BYOK endpoint or the on-device chat model — same three-mode chooser as the cleanup pass.
- **Save presets** — bundle `(backend, modelId, language, AdvancedOptions)` into a named preset. One tap restores all four atomically. JSON-backed with schema-versioned migration so a stale preset on a newer build doesn't crash.
- **Push-to-transcribe from anywhere** — desktop-only system hotkey (macOS / Linux / Windows). Push-to-talk OR toggle behaviour; combo parser handles modifier aliases (cmd / command / win / super → meta, ctrl → control, option → alt).
- **Clone a voice in three steps** — guided wizard launched from the *Synthesize* screen: record 10 s OR pick a WAV → type the reference transcript → hand off to *Synthesize* with everything pre-populated. Runs on top of the existing chatterbox / indextts / qwen3-tts-base / vibevoice runtime-cloning surface.
- **Whisper subtitle formatting** — tokens-per-segment cap + split-on-word toggle in Advanced Options. Produces SRT-friendly short subtitle lines instead of long-paragraph segments.

## Supported models

One dispatcher (`CrispasrSession`) handles every backend; bundled `libcrispasr` reports at startup which are linked in the current build, and the *Models* screen filter chips group them by kind (`ASR / TTS / Voices / Codecs / Post-processors`). The Model Management screen also probes CrispASR's built-in C-side registry on every open, so any backend the bundled libcrispasr knows about appears even if it isn't hardcoded in the app catalog.

### ASR

| Family                | Sizes                               | Languages                   | Notes                                |
| --------------------- | ----------------------------------- | --------------------------- | ------------------------------------ |
| **Whisper**           | tiny → large-v3 + q4_0/q5_0/q8_0    | 99                          | Word-level ts, lang-detect, streaming |
| **Distil-Whisper**    | distil-large-v3 (f16 / q5_0 / q4_k) | 99                          | ~6× faster than large-v3, ~50% smaller |
| **Parakeet** (NVIDIA) | tdt-0.6b-v3, v2, 1.1b               | 25 EU (auto-detect)         | Fast, native word timestamps          |
| **Canary** (NVIDIA)   | 1b-v2                               | 25 EU (explicit src/tgt)    | Speech translation X ↔ en             |
| **Qwen3-ASR**         | 0.6b, 1.7b                          | 30 + 22 Chinese dialects    | Multilingual                          |
| **Mega-ASR**          | 1.7b (Qwen3-ASR + robustness LoRA)  | 30 + 22 Chinese dialects    | LoRA merged offline, qwen3 runtime    |
| **Cohere**            | 03-2026                             | 13                          | High-accuracy Conformer decoder       |
| **Granite Speech**    | 3.2-8b, 3.3-2b/8b, 4.0-1b, 4.1-2b   | en fr de es pt ja           | Instruction-tuned                     |
| **Granite Speech 4.1**| 2B / 4.1+ / 4.1-NAR                 | en fr de es pt ja           | Instruction-tuned + parallel decode  |
| **FastConformer-CTC** | small → xxlarge                     | en                          | Low-latency CTC                       |
| **Canary-CTC**        | 1b                                  | 25 EU                       | CTC variant of canary                 |
| **Voxtral Mini**      | 3B (2507), 4B realtime (2602)       | 8 / 13                      | Speech translation; realtime 4B       |
| **Wav2Vec2**          | large-xlsr-53-english + variants    | per-model (en, de, multi)   | Self-supervised CTC                   |
| **OmniASR LLM**       | 300M v2, 1B                         | multilingual                | LLM-based ASR with `lang=` hint       |
| **OmniASR LLM unlim.**| 300M v2 streaming                   | 1600+ languages             | Streaming, 15 s protocol, unlimited audio |
| **FireRed ASR2**      | aed-2b                              | zh / en                     | AED-style                             |
| **Kyutai STT**        | 1b                                  | en                          | Streaming-style                       |
| **GLM-ASR Nano**      | nano                                | multilingual                | GLM-family                            |
| **Moonshine**         | tiny / base + streaming             | en                          | Tiny CPU-friendly, BPE tokenizer companion |
| **VibeVoice ASR**     | large                               | multilingual                | Large multilingual ASR (~4.5 GB)      |
| **MiMo ASR**          | 2.5B + tokenizer companion          | en zh                       | XiaomiMiMo, two-file (model + codec)  |
| **Gemma4-E2B**        | 2B (q4_k)                           | 140+ languages              | USM Conformer + Gemma-4 35L          |
| **FunASR Nano**       | 2512 (f16 / q4_k), MLT 2512         | zh + en (nano) / multi (mlt)| Alibaba's compact ASR, 70-block SANM  |
| **Paraformer-ZH**     | base (f16 / q4_k / q8_0)            | zh                          | FunASR family, NAR Mandarin ASR       |
| **SenseVoice**        | small (f16 / q4_k / q8_0)           | zh en ja ko yue             | Built-in LID + use_itn punctuation    |

### TTS

| Family            | Sizes                          | Notes                                       |
| ----------------- | ------------------------------ | ------------------------------------------- |
| **Kokoro**        | 82M + voicepacks               | Multilingual, espeak-ng phonemiser bundled  |
| **VibeVoice**     | realtime 0.5B (f32 + tokenizer), 1.5B base | + voicepack via `setVoice`; 1.5B supports runtime WAV cloning |
| **Qwen3-TTS**     | 0.6B base + customvoice + codec, 1.7B VoiceDesign | Customvoice has 9 baked speakers; VoiceDesign accepts natural-language voice descriptions via `setInstruct` |
| **Orpheus**       | 3B + SNAC codec                 | 8 baked English speakers; SNAC via `setCodecPath` |
| **Chatterbox**    | 850 MB base + turbo / Kartoffelbox (DE) | T3 AR + S3Gen flow-matching; voice cloning via baked GGUF |
| **IndexTTS**      | 1.6 GB                          | GPT-2 AR + BigVGAN; zero-shot WAV cloning, ZH+EN |
| **VoxCPM2**       | q4_k (1.6 GB) + f16             | Tokenizer-free diffusion AR; zero-shot, 29 languages, 48 kHz native |

### Post-processors

| Family            | Languages          | Notes                                       |
| ----------------- | ------------------ | ------------------------------------------- |
| **FireRedPunc**   | ZH + EN            | BERT-based punctuation + capitalisation     |
| **Fullstop-punc** | EN / DE / FR / IT  | Multilingual punctuation restoration        |

### Diarisation / LID / VAD GGUFs

| Family                | Role                | Notes                                                       |
| --------------------- | ------------------- | ----------------------------------------------------------- |
| **Pyannote v3 seg**   | Diarisation         | ML segmentation, up to 3 speakers per slice                 |
| **Silero LID 95**     | Language ID         | 95-language classifier, ~16 MB GGUF — faster than Whisper LID |
| **FireRedVAD**        | VAD                 | F1 97.57%, ~3 MB                                            |
| **MarbleNet VAD**     | VAD                 | Small (~500 KB), EN/DE/FR/ES/RU/ZH                          |
| **Whisper-VAD-EncDec**| VAD (experimental)  | Japanese-trained (works on EN too), ~22 MB                  |

Downloads pull f16 from `ggerganov/whisper.cpp` and quantised variants from [`cstr/whisper-ggml-quants`][cstr] and other `cstr/*-GGUF` repos. Skip-checksum toggle in Settings for custom or mirrored GGUFs.

[cstr]: https://huggingface.co/cstr

## Platforms

| Platform | State                                                                 |
| -------- | --------------------------------------------------------------------- |
| macOS    | ✅ Released — `.app.zip`, Metal-enabled, all 24+ backend dylibs (incl. kokoro / orpheus / mimo-asr) bundled, espeak-ng auto-bundled for kokoro phonemisation |
| Linux    | ✅ Released — `.tar.gz` bundle                                         |
| Windows  | ✅ Released — portable `.zip` + installable `.msix` with Explorer "Open With" registration for audio + subtitle types |
| Android  | ✅ Released — real-ASR APK (`arm64-v8a`) with `libwhisper.so` cross-built in CI. External models dir picker requests "All files access" runtime permission (Android 11+) so reinstalls don't lose access to `/storage/emulated/0/...` paths. |
| iOS      | ⚠️ Unsigned IPA — sideload via [SideStore](https://sidestore.io/) / AltStore / Feather |

Roadmap and blockers: see [`PLAN.md`](PLAN.md).

---

## Building

### Prerequisites

- Flutter 3.38.x (`stable`)
- Xcode + CocoaPods for iOS / macOS
- JDK 17 + Android SDK for Android
- CMake + a C++ toolchain to build `libwhisper` from CrispASR
- Optional: Metal (macOS), CUDA / Vulkan (Linux/Windows), Core ML (iOS), NNAPI (Android)

### Clone the two repos side-by-side

```bash
mkdir crisperweaver && cd crisperweaver
git clone https://github.com/CrispStrobe/CrispASR.git
git clone https://github.com/CrispStrobe/CrisperWeaver.git
```

`pubspec.yaml` refers to the Dart FFI package via `path: ../CrispASR/flutter/crispasr`.

### Desktop one-shot (recommended)

Each desktop platform has an end-to-end script that configures + builds CrispASR's `libwhisper` / `whisper.dll`, runs `flutter build`, and bundles every needed dynamic library next to the runner. They expect the sibling `CrispASR` checkout described above.

```bash
# macOS
./scripts/build_macos.sh release

# Linux
./scripts/build_linux.sh release

# Windows (cmd.exe — picks up pwsh if installed, falls back to powershell.exe)
build_windows.bat release
# or directly:
pwsh -File scripts\build_windows.ps1 release
```

Pass `debug` instead of `release` for a debug build; add `--rebuild-cmake` (or `-RebuildCmake` on Windows) to force a fresh CrispASR cmake configure. Each script's output ends with a path to the runnable bundle / `.app` / `.exe`.

The bundlers can also be invoked standalone (`scripts/bundle_macos_dylibs.sh`, `scripts/bundle_linux_libs.sh`, `scripts/bundle_windows_dlls.ps1`) if you've already built CrispASR and `flutter build <platform>` separately and just want to drop the libs in place.

At runtime, `CrispASREngine` resolves the library by probing platform-specific names — `crispasr.dll` / `libcrispasr.dylib` / `libcrispasr.so` first, then the `whisper`-named alias — under the bundle, the user's CrispASR checkout, system lib dirs, and any user-supplied override path.

### Manual / iterative dev

```bash
cd CrispASR
cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON -DWHISPER_METAL=ON
cmake --build build --parallel --target crispasr

cd ../CrisperWeaver
flutter pub get
flutter run -d macos        # or: linux, windows, android, ios
```

`flutter run` picks up the freshly-built CrispASR shared library directly from `../CrispASR/build/src/` for fast inner-loop work.

---

## Using it

1. **First run**: open *Settings → Manage models* and download the model you want. Default pick is Whisper base (~140 MB, covers 99 languages).
2. **Transcribe a file**: back to the main screen, drop a file or click the picker. Language auto-detects by default.
3. **Record from the mic**: use the recorder card. Stop → transcribe.
4. **Stream from mic** (Whisper): toggle *Stream* in the recorder. Partial text arrives as you speak.
5. **Synthesize speech** (TTS): tap the *Synthesize* icon in the app-bar (next to *Models*). Pick a downloaded TTS model + voice + codec, type text, hit *Synthesize* — output plays in-app and can be saved as WAV via the share sheet.
6. **Export the result**: share-sheet button → pick TXT / SRT / VTT / JSON.
7. **Browse past runs**: *History* in the drawer — everything is persisted as JSON under `<app-docs>/history/`.

Useful Settings:
- **Preferred engine** — CrispASR is the default.
- **Default model / language** — pre-select across new transcriptions.
- **Custom models directory** — point CrisperWeaver at an existing GGUF
  library on an external disk (the *Models directory* picker), e.g.
  `/Volumes/backups/ai/crispasr`, to reuse already-downloaded models
  instead of re-fetching into the app sandbox. Cross-platform; the model
  picker reads flat GGUFs from that folder and "Use default" restores the
  sandbox `<app-docs>/models/whisper_cpp` location. (On Android 11+ an
  external/shared-storage path needs the one-time "All files access" grant.)
- **Skip checksum verification** — custom / mirrored GGUFs.
- **Log level + file sink** — `<app-docs>/logs/session.log` for bug reports.

---

## Testing

The default test pass is fast and offline:

```bash
flutter analyze    # 0 issues — see analysis_options.yaml for the strict rule set
flutter test       # 378 tests, ~20 s — widget unit + service / persistence / batch / dispatch
```

`test/backend_dispatch_test.dart` always runs the cheap dispatch
checks (every backend appears in `CrispasrSession.availableBackends()`,
opens with bogus paths fail cleanly). The expensive end-to-end synth /
transcribe roundtrips are tagged `slow` and skip themselves silently
unless their `CRISPASR_TEST_<BACKEND>_MODEL` env var points at a
downloaded GGUF. Opt in with:

```bash
M=/path/to/crispasr-models
CRISPASR_TEST_KOKORO_MODEL=$M/kokoro-82m-q8_0.gguf \
CRISPASR_TEST_KOKORO_VOICE=$M/kokoro-voice-af_heart.gguf \
CRISPASR_TEST_QWEN3_TTS_MODEL=$M/qwen3-tts-12hz-0.6b-customvoice-q8_0.gguf \
CRISPASR_TEST_QWEN3_TTS_CODEC=$M/qwen3-tts-tokenizer-12hz.gguf \
CRISPASR_TEST_VIBEVOICE_MODEL=$M/vibevoice-realtime-0.5b-tts-f32-tokenizer.gguf \
CRISPASR_TEST_VIBEVOICE_VOICE=$M/vibevoice-voice-en-Emma_woman.gguf \
CRISPASR_TEST_ORPHEUS_MODEL=$M/orpheus-3b-base-q8_0.gguf \
CRISPASR_TEST_ORPHEUS_CODEC=$M/snac-24khz.gguf \
CRISPASR_TEST_MIMO_ASR_MODEL=$M/mimo/mimo-asr-q4_k.gguf \
CRISPASR_TEST_MIMO_ASR_TOKENIZER=$M/mimo/mimo-tokenizer-q4_k.gguf \
CRISPASR_TEST_COSYVOICE3_MODEL=$M/cosyvoice3-llm-q4_k.gguf \
CRISPASR_TEST_WHISPER_MODEL=$M/ggml-tiny.bin \
flutter test --tags slow test/backend_dispatch_test.dart
```

The cosyvoice3 roundtrip needs its `flow` / `hift` / `voices` companions
sitting beside the LLM GGUF (auto-discovered by filename). There is also
an `f5-tts` roundtrip (`CRISPASR_TEST_F5TTS_MODEL=$M/f5-tts-v1-base-f16.gguf`,
zero-shot clone from `test/jfk.wav`) — left out of the line above on
purpose: its DiT synth is *extremely* slow (~50 min for one short sentence
on M1 Metal), so opt into it only deliberately and on its own.

A single sweep takes ~25 min on M1 Metal end-to-end (full sweep —
6 backends including a 3 B Llama and a 4 GB f32 vibevoice). Each
backend skips if its env var isn't set, so partial sweeps are cheap.
Coverage:

```bash
flutter test --coverage      # writes coverage/lcov.info
genhtml coverage/lcov.info -o coverage/html  # if lcov is installed
```

See `dart_test.yaml` for the tag config and `PLAN.md §5.18` for the
test-suite speed roadmap (the architectural win is a persistent
ggml-metal pipeline cache via `MTLBinaryArchive`, which would cut
the cold-start kernel-JIT cost from minutes to seconds).

---

## CI & releases

- **`ci.yml`** — on push / PR: `flutter analyze` + `flutter test` on Ubuntu and macOS, plus debug `.app` and Linux bundle uploaded as workflow artifacts. Checks out sibling `CrispStrobe/CrispASR` automatically. Slow tests (`--tags slow`) are skipped by default; CI can opt in by setting the `CRISPASR_TEST_*` env vars and adding `--tags slow` to the test command. Analyzer is configured to **error** on `use_build_context_synchronously`, `avoid_print`, `unused_*`, `inference_failure_*`, and `deprecated_member_use` — a regression fails the build instead of silently piling up.
- **`release.yml`** — on a `vX.Y.Z` tag (or manual dispatch): builds and uploads
    - `crisper_weaver-macos.zip` — Metal-enabled `.app`, ad-hoc signed, all 24+ backend dylibs (kokoro / orpheus / mimo-asr included as of CrispASR `ba7d6ed`) bundled.
    - `crisper_weaver-linux-x64.tar.gz` — GTK-3 desktop bundle with all backend `.so`'s.
    - `crisper_weaver-windows-x64.zip` — portable zip with `runner.exe` + `whisper.dll` + sibling backend DLLs.
    - `crisper_weaver-windows-x64.msix` — installable MSIX that registers "Open With → CrisperWeaver" for audio + subtitle types in Explorer. Unsigned for now (see Windows install below).
    - `crisper_weaver-android-arm64.apk` — real ASR. CrispASR cross-built via `build-android.sh --abi arm64-v8a`; `libwhisper.so` and sibling backend `.so`'s dropped into `jniLibs/arm64-v8a/`.
    - `crisper_weaver-ios-unsigned.ipa` — sideload-compatible (see below).

Both workflows honour `CRISPASR_REPO` / `CRISPASR_REF` env vars at the top of each file, in case you maintain a fork of CrispASR.

### Sideloading iOS

We don't pay for the Apple Developer Program yet, so the iOS IPA in releases is **unsigned**. To install it on your own device, use a sideload service:

- **[SideStore](https://sidestore.io/)** — iOS app installer that uses your own Apple ID for signing (free: 7-day re-sign; paid ADP: 1-year). Self-hosted via StosVPN or pair-with-computer.
- **[AltStore](https://altstore.io/)** — the original self-sign flow; requires a desktop-side companion (AltServer).
- **[Feather](https://github.com/khcrysalis/Feather)** — open-source alternative.

All three accept the `.ipa` directly: download `crisper_weaver-ios-unsigned.ipa` from the release page, open in SideStore (Files → share to SideStore), tap Install. The free-tier 7-day limit means you'll need to re-sign weekly unless you also have a paid Apple Developer account.

### Installing on Windows

Two artefacts ship per release; pick one:

- **`crisper_weaver-windows-x64.zip`** — portable. Unzip anywhere, run `crisper_weaver.exe`. No installer, no file associations, doesn't survive across machines cleanly. Good for quick trials and tech users.
- **`crisper_weaver-windows-x64.msix`** — installable. Lands in `Apps & features`, uninstalls cleanly, and **registers "Open With → CrisperWeaver" in Explorer** for `.wav` / `.mp3` / `.m4a` / `.flac` / `.ogg` / `.aac` / `.opus` / `.wma` / `.srt` / `.vtt`. Recommended for everyday use.

The MSIX is **not signed by a Microsoft Store-trusted CA yet** (Microsoft Store registration is on the roadmap), so the first install needs a one-time trust step:

1. Download `crisper_weaver-windows-x64.msix` from the release page.
2. Right-click → Properties → tick **Unblock** (under the General tab, bottom right).
3. Double-click the `.msix` → **Install**. Windows Security may warn ("Untrusted publisher") — accept once.
4. After install, right-click any audio file in Explorer → **Open With → CrisperWeaver**.

Once we publish to Microsoft Store, that warning goes away — `winget install CrisperWeaver` and the Store listing will both ship the same MSIX, signed.

---

## Roadmap

The short version:

- CoreML acceleration for Whisper on iOS/macOS (enable `WHISPER_USE_COREML` inside CrispASR, ship the paired `.mlmodelc` next to the `.bin`).
- Swap the MFCC/k-means diarization stopgap for the shared-lib `crispasr_diarize_segments_abi` introduced in CrispASR v0.4.5 (pyannote GGUF + energy/xcorr/vad-turns in one call).
- Wire the shared `crispasr_detect_language_pcm` (v0.4.6) for auto-language on backends that lack native LID.
- Wire `crispasr_align_words_abi` (v0.4.7) to give word-level timestamps to LLM-based backends (qwen3 / voxtral / granite) that don't emit them natively.
- Expose more CrispASR power-user knobs in the UI: beam search / best-of-N, temperature, source/target languages for translation backends, audio Q&A mode, streaming UI (see PLAN.md §5.8). VAD and `initialPrompt` already shipped in v0.1.7.
- Windows CI job (build script + DLL bundler shipped — `scripts/build_windows.ps1`; CI workflow still TODO).
- Android CI: cross-build `libwhisper.so` + sibling backends, drop into `jniLibs/`, ship a real-ASR APK.
- iOS `pod install` + device-build CI verification.
- Finish i18n migration for widgets + older Settings strings.
- Backend-specific UX (source/target language UI for Canary, Voxtral audio Q&A mode, Granite `--ask` flag, etc.).

Full per-item breakdown with file paths, risks, and verification steps: **[`PLAN.md`](PLAN.md)**.

Technical learnings collected during development (FFI quirks, dylib bundling, macOS chrome, CI patterns): **[`LEARNINGS.md`](LEARNINGS.md)**.

---

## License & author

CrisperWeaver is **GNU AGPL-3.0-or-later**. See [`LICENSE`](LICENSE) for full text and the in-app *About* screen for the auto-aggregated third-party license list (`showLicensePage`).

Copyright © Christian Ströbele · Stuttgart, Germany.
