# CrisperWeaver v0.9.1 — On-device codecs, MOSS + 5 more backends, #30 fix

**Released:** 2026-07-14
**Engines:** CrispASR 0.8.10 · CrispEmbed 0.14.0

This release adds an on-device compressed-audio codec (no more ffmpeg
dependency), catches the model catalog up to the CrispASR 0.8.10 engine
(seven new ASR/TTS backends), lands the iOS App Store signing pipeline,
and fixes a backend-routing crash reported in #30 — including a latent
FFI binding bug that had silently disabled GGUF backend auto-detection.

---

## Highlights

### Audio — on-device MP3 / AAC-LC / Opus (no ffmpeg)
- **Compressed export & import via bundled `libglint`** (the clean-room,
  MIT, dependency-free codec suite). CrisperWeaver now encodes to
  **MP3 / AAC-LC / Opus** and decodes `.mp3` / `.aac` / `.opus` / `.ogg`
  **entirely on-device**, closing the long-standing "WAV-only export,
  ffmpeg-punt decode" gap.
  - `GlintCodecService` — `encodePcm[ToFile]`, `decodeBytes`,
    `isAvailable`, `canDecodePath`.
  - `AudioService` tries glint before the ffmpeg / Android-MediaCodec
    fallbacks; `AudioEditService.exportEncoded()` writes a compressed
    file (optionally a time-slice). All paths degrade gracefully to WAV
    when the lib isn't present.
  - Native `libglint` is built + bundled per platform (macOS dylib,
    Linux `.so`, Windows `.dll`, Android `jniLibs`, iOS xcframework) and
    rebuilt fresh for every platform in release CI.

### ASR / TTS — new backends (CrispASR 0.8.10 catch-up)
- **MOSS-Diarize** (`moss-diarize`) — single-pass ASR **+ native speaker
  diarization + timestamps** in one 0.9B model; surfaces as an ASR model
  with the Ask + source-language fields enabled.
- **MOSS-TTS v1.5** (`moss-tts`) — voice-cloning TTS (Qwen3-8B backbone +
  RVQ codec) from a reference WAV, no Python bake step. Desktop-class.
- **OmniVoice** (`omnivoice`) — Qwen3-0.6B multi-codebook TTS (600+
  languages) with its audio-tokenizer companion.
- **Irodori-TTS** (`irodori-tts`) — Japanese 500M TTS + DAC-VAE codec.
- **Voxtral-4B-TTS** (`voxtral-tts`) — Mistral TTS (flagged non-commercial,
  CC-BY-NC-4.0).
- **Canary-Qwen 2.5B** (`canary-qwen`) — NVIDIA Canary encoder + Qwen
  decoder ASR.
- **Nemotron 3.5 streaming ASR** (`nemotron`) — completed its catalog
  wiring (repo + recommended default).
- Fixed **CosyVoice3-TTS** kind misclassification so probe-discovered
  quants render as TTS.

### Fixes
- **#30 — HuggingFace-linked non-Whisper GGUFs no longer crash.** A
  Cohere ASR GGUF added via "Add from HuggingFace repo" was force-routed
  to the whisper pipeline (`Model uses the whisper backend … built with
  {}`). The engine now reads the GGUF's architecture metadata at load
  time and routes to the real backend (e.g. `cohere`), skips the
  front-door gate when the dylib reports an *empty* backend list
  ("unknown" ≠ "nothing linked"), and the HF-repo dialog always offers a
  concrete backend override.
- **Latent FFI bug fixed** — `detectBackendFromGguf` in the `crispasr`
  binding had an inverted return-code check (`rc != 0`) and was returning
  null for **every** successfully-detected backend, which silently
  disabled the auto-routing above *and* ModelService's post-download
  backend correction. CrisperWeaver now uses a corrected helper
  (`lib/native/crispasr_detect_native.dart`). Verified live against the
  real `cohere-transcribe-arabic-q4_k.gguf`.

### iOS — App Store signing pipeline
- API-key-driven signing + archive/export for the release IPA
  (`flutter build ipa`), Distribution `.p12` imported into a dedicated
  build keychain, App Store Connect API key handling.

### Testing & CI
- Widget tests for the transcription + synthesize screens (§8.7).
- Live tests: #30 Cohere auto-detect end-to-end, the new Nemotron ASR
  backend transcribing, and a deterministic VAD-silence test (Silero
  finds no speech in silence — replacing a flaky raw-whisper assertion).
- The `backend_dispatch` catalog↔engine parity guard is green against a
  freshly-built 0.8.10 dylib.
- CI robustness: capped the Linux CrispASR build parallelism to avoid
  OOM (exit 143), and the web-deploy workflow now checks out the glint
  sibling for `flutter pub get`.

---

## Notes
- **MOSS-TTS**, **Voxtral-TTS**, and **Canary-Qwen** are large
  (desktop-class) downloads; they're cataloged but their live
  synth/transcribe runs are unverified on this release.
- The upstream `crispasr` `detectBackendFromGguf` binding bug is worked
  around in CrisperWeaver; a proper upstream fix is a follow-up.
