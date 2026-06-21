## v0.8.0 — Full three-surface parity + CrispASR 0.8.0

Major release: CrisperWeaver's CLI, HTTP server, and GUI now offer near-complete feature parity. Paired with CrispASR v0.8.0 which brings performance optimisations (bucket cache, cross-KV F16, BPE DRY) and critical GPU bug fixes (Vulkan F16 conv_transpose_1d, LFM2-Audio GPU backbone, non-power-of-two FFT heap overflow).

### CLI generation controls

The `transcribe` command gained 13 new flags for full parity with the GUI's Advanced Options:

```
--temperature    Decoder temperature (0.0 = greedy)
--best-of        Best-of-N decoding
--hotwords       Comma-separated contextual biasing words
--hotwords-boost Boost factor for CTC/TDT backends
--seed           RNG seed for reproducible sampling
--max-new-tokens Token generation cap (LLM backends)
--frequency-penalty  Frequency penalty (LLM backends)
--beam-size      Beam search width
--ask            Audio Q&A prompt (instruct LLM backends)
--translate      Translate to English (whisper)
--vad            Enable Silero VAD pre-filtering
--word-timestamps Per-word timings
--vtt            WebVTT output format
--target-language Target language for translation
--initial-prompt Vocabulary hint / initial prompt
```

`stream` gained `--hotwords`, `--hotwords-boost`, `--temperature`.
`synthesize` gained `--temperature`, `--seed`.

### Server enhancements

- **WebSocket streaming** — new `ws://host:port/v1/audio/stream` endpoint. Send a JSON config message, then binary 16-bit LE mono 16 kHz PCM frames; receive JSON `{text, start, end}` transcript segments in real time.
- **`GET /backends`** — lists all CrispASR backends linked into the dylib.
- **Transcriptions endpoint** (`POST /v1/audio/transcriptions`) now accepts: `temperature`, `best_of`, `prompt`/`initial_prompt`, `hotwords`, `hotwords_boost`, `translate`, `vad`, `diarize`, `punctuation`, `ask`/`ask_prompt`, `target_language`.
- **TTS voice cloning** — `/v1/audio/speech` now accepts `multipart/form-data` with a `voice_file` part (WAV/FLAC/MP3 reference) for voice cloning, alongside the existing JSON body path.

### Watermark detection GUI

New "Verify Watermark" button in the transcription screen toolbar. Pick any WAV file to check whether it contains the CrisperWeaver AI watermark — shows the embedded timestamp and synthetic-content flag if found.

### Audio format support (GitHub issue #26)

All file pickers now accept `.opus`, `.webm`, and `.m4a` alongside `.wav`/`.mp3`/`.flac`/`.ogg`. CrispASR's miniaudio backend decodes all of these natively.

### Model selector UX (GitHub issue #27)

The model picker on the transcription screen now starts expanded when no model is loaded, so first-time users discover it immediately.

### CrispASR 0.8.0 engine upgrades

Rebuilt against CrispASR v0.8.0 which includes:

- **Bucket KV cache optimisation** — 1.86x speedup on parakeet/parler (8 backends)
- **Cross-attention KV F16** — 50% memory savings on 5 encoder-decoder backends
- **BPE DRY consolidation** — 6 copy-pasted GPT-2 byte decoders merged into shared `core_bpe`
- **BLAS acceleration** — 40%+ speedup on 9 backends
- **Chatterbox CFM 10→6 steps** — 46% faster TTS, perceptually identical
- **Vulkan F16 conv_transpose_1d** — fixes piper TTS crashes on Android (issue #21)
- **Pocket-TTS weight residency fix** — fixes noise/crash on Android (issue #20)
- **TTS error surfacing** — Qwen3-TTS base model error now shown in UI (issue #22)
- **Non-power-of-two FFT** — fixes CUDA heap overflow on chatterbox/CosyVoice3
- **LFM2-Audio GPU fix** — GPU backbone no longer crashes on CUDA

### CrispEmbed blocker resolved

The §9.7 CrispEmbed path dependency blocker (unterminated class in upstream repo) is resolved. The full `flutter test` suite now runs — **905 tests passed, 0 failures**.

### Test fixes

- Fixed API mismatches in `canary_ctc_aligner_live_test.dart` and `lid_dispatch_live_test.dart` (lib→libPath, .word→.text, DecodedAudio handling, TextLanguage→.code)
- All 5 previously-untracked test files verified clean and included

### Parity matrix

| Capability | GUI | CLI | Server |
|---|---|---|---|
| File ASR | ✅ | ✅ | ✅ |
| Streaming ASR | ✅ | ✅ | ✅ WebSocket |
| VAD | ✅ | ✅ | ✅ |
| Language ID | ✅ | ✅ | ✅ |
| Diarization | ✅ | ✅ | ✅ |
| Forced alignment | ✅ | ✅ | ✅ |
| Punctuation | ✅ | ✅ | ✅ |
| TTS synthesis | ✅ | ✅ | ✅ |
| Voice cloning | ✅ | ✅ | ✅ |
| Text translation | ✅ | ✅ | ✅ |
| Speech-to-speech | ✅ | ✅ | ✅ |
| Watermark embed | ✅ | ✅ | ✅ |
| Watermark detect | ✅ | ✅ | ✅ |
| Denoise | ✅ | ✅ | ✅ |
| Hotwords | ✅ | ✅ | ✅ |
| Audio Q&A | ✅ | ✅ | ✅ |
| List backends | ✅ | ✅ | ✅ |
| Generation controls | ✅ | ✅ | ✅ |

**Full changelog:** https://github.com/CrispStrobe/CrisperWeaver/compare/v0.7.9...v0.8.0
