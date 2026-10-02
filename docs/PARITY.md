# CrisperWeaver — capability parity matrix (GUI · CLI · Server)

Tracks which user-facing surface reaches each on-device speech capability.
The main matrix below describes native builds. Browser support is narrower
and is recorded separately here rather than inferred from native parity.

## Browser support — Full and Lite (2026-10-02)

| Capability | Browser state |
|---|---|
| Local ASR | CrispASR WASM: Whisper tiny/base, Moonshine tiny, FastConformer Q4. ONNX WASM: Whisper tiny/base and Moonshine tiny. |
| Experimental ASR | Wider native catalogue and ONNX Whisper small require the separate warning-gated override. Phonon-2 Q4 passed Chromium CI; Q8/F16 remain unvalidated. Backend availability is checked before native-model download. |
| Microphone | Record, decode/resample to 16 kHz, then transcribe; no live streaming. |
| Local TTS | English Kokoro, `af_heart`, at most 1,000 characters per request. |
| CrispASR CPU execution | SIMD single-thread default with 128 MiB initial memory; opt-in two/four-thread async compute requires browser isolation. Worker termination cancels processing. |
| ONNX GPU | Warning-gated fp32 weights with fresh-worker CPU recovery. Physical Tesla T4 passes Moonshine tiny and Whisper tiny English; other devices/models remain unvalidated. |
| Timings | ASR segments; ONNX Moonshine and Whisper text-decoding fallback use chunk boundaries. No word timestamps or forced alignment. |
| History and model cache | IndexedDB history and SHA-256-verified chunked weights. Interrupted downloads resume checkpoints; eviction/corruption permits clean retry. Fresh-worker cached inference is tested with off-origin requests blocked. Browser eviction remains possible. |
| Diarization / voice cloning / native auxiliary tools | Not exposed by the browser speech adapter. |
| Remote AI | Full retains optional cloud processing. Lite disables it; the experimental-model override does not change that policy. |

Final compiled-artifact matrices pass without retries in Chromium, Firefox
and WebKit: Full 39 tests per browser (2 Lite-only skipped), Lite 41. Real
threaded ASR/TTS, cache recovery and Lite endpoint policy pass in every matrix.
The isolated Phonon-2 Q4
assessment and physical GPU results have separate evidence. See
[test results and deployment commands](../web-e2e/README.md).

## Native surfaces

Surfaces:

- **GUI** — Flutter screens/widgets (`lib/screens`, `lib/widgets`).
- **CLI** — `bin/crisperweaver.dart` (`dart run crisper_weaver:crisperweaver`),
  a thin wrapper over `package:crispasr` (the engine the GUI uses). It has no
  Flutter bindings, so it reaches engine *capabilities*, not GUI orchestration.
- **Server** — the built-in HTTP server (`lib/services/server_service.dart`).

Legend: ✅ reached · ➖ partial · ❌ not yet · — n/a.

| Capability | GUI | CLI | Server | Notes |
|---|---|---|---|---|
| List backends | ✅ (implicit) | ✅ `backends` | ✅ `GET /backends` | |
| File ASR (transcribe) | ✅ | ✅ `transcribe` (+`--srt`/`--vtt`) | ✅ `/v1/audio/transcriptions` | |
| Live / streaming ASR | ✅ | ✅ `stream` | ✅ WebSocket `/v1/audio/stream` | binary PCM → JSON segments |
| VAD | ✅ | ✅ `vad` · `transcribe --vad --vad-model` | ✅ `/v1/audio/vad` | CLI calls the free `crispasr_vad_slices`; `--vad` needs an explicit model path (#35) |
| Language ID (audio+text) | ✅ | ✅ `lid` (`--text`) | ✅ `/v1/audio/language` + `/v1/text/language` | |
| Diarization | ✅ | ✅ `diarize` | ✅ `/v1/audio/diarize` | |
| Speaker enroll / match | ✅ | ✅ `speaker` | ❌ | server: stateful device DB — deferred |
| Forced alignment | ✅ (engine) | ✅ `align` (`--language`) | ✅ `/v1/audio/align` | language-aware wav2vec2 selection |
| Punctuation / PCS / truecase | ✅ | ✅ `punctuate` | ✅ `/v1/text/punctuate` | |
| TTS synthesis | ✅ | ✅ `synthesize` | ✅ `/v1/audio/speech` | |
| Voice cloning | ✅ | ✅ `synthesize --voice` | ✅ `/v1/audio/speech` multipart `voice_file` | |
| Voice baking | ✅ | ❌ | ❌ | desktop Python subprocess; GUI-only |
| Text translation | ✅ | ✅ `translate` | ✅ `/v1/translations` | |
| Speech-to-speech | ➖ | ✅ `s2s` | ✅ `/v1/audio/s2s` | needs lfm2-audio / mini-omni2 |
| Watermark embed | ✅ | ✅ `watermark` | ✅ `/v1/audio/watermark` (`mode=embed`) | |
| Watermark **detect** | ✅ Verify Watermark button | ✅ `watermark --detect` | ✅ `/v1/audio/watermark` | GUI + CLI + server |
| RNNoise denoise | ✅ | ✅ `denoise` | ✅ `/v1/audio/denoise` | |
| Hotwords / contextual biasing | ✅ | ✅ `transcribe --hotwords` | ✅ `hotwords` form field | CTC trie + LLM prompt injection |
| Generation controls | ✅ | ✅ `--temperature/--best-of/--seed/…` | ✅ form fields | temperature, best-of, seed, beam-size, frequency-penalty, max-new-tokens |
| Audio Q&A (ask prompt) | ✅ | ✅ `transcribe --ask` | ✅ `ask` form field | instruct LLM backends |
| .opus / .webm / .m4a input | ✅ | ✅ (via CrispASR) | ✅ | CrispASR miniaudio decodes all |
| Synthetic content provenance | ✅ | ✅ | ✅ | Watermark + C2PA + WAV/MP3 metadata + export disclosure + heuristic AI detection |

## Orphan audit — resolved (§9.5)

The initial reachability sweep flagged several "orphaned" capabilities;
verification showed they are reachable:

- **Speech-to-speech** — fully GUI-wired: `synthesize_screen.dart` has an
  `s2sMode` toggle + audio input and calls `tts.speechToSpeech()`. Also CLI `s2s`.
- **Forced alignment** — triggered by the engine when the **word-timestamps**
  setting is on (`settings_screen.dart`) and the backend emits no word timing;
  `crispasr_engine.dart` runs `AlignerService.addWordTimestamps`. Also CLI `align`.
- **Watermark detect** — no GUI button, but reachable via CLI
  (`watermark --detect`) and server (`/v1/audio/watermark`); the only genuine
  gap is a GUI "verify watermark" action (minor UX, tracked).

## GUI-only by design (orchestration, not engine capabilities)

These wrap higher-level app state (history, files, network keys, Riverpod) and
are intentionally **not** mirrored to the CLI/server:

- Local / cloud LLM transcript cleanup & summarization
- Semantic search, A/B model compare, presets, batch queue, watch folder
- System audio capture, subtitle overlay, note/chapter export, model catalog/download

## Remaining parity work (PLAN §9.4)

- **CLI**: complete — `transcribe` (with `--temperature`, `--best-of`,
  `--hotwords`, `--seed`, `--max-new-tokens`, `--frequency-penalty`,
  `--beam-size`, `--ask`, `--translate`, `--vad`, `--word-timestamps`,
  `--vtt`), `stream` (with `--hotwords`, `--temperature`), `vad`, `lid`,
  `diarize`, `align`, `speaker`, `punctuate`, `translate`, `synthesize`
  (with `--temperature`, `--seed`), `s2s`, `watermark`, `denoise`, `backends`.
  Two CLI-specific rules, both from #35:
  - **`--vad` requires `--vad-model <silero .gguf>`.** The GUI auto-detects
    the VAD model because it ships Silero as a Flutter asset; a `dart run`
    entrypoint has no asset bundle, so the path cannot be inferred. Before
    #35 the flag was parsed and then ignored, which looked like parity in
    `--help` and decoded the silence anyway.
  - **Bad arguments are usage errors (exit 64), not stack traces.** Numeric
    options are validated and input files are checked for existence *before*
    the decode and the session open.
- **Server**: complete — all REST endpoints + WebSocket streaming
  (`/v1/audio/stream`). `GET /backends` lists available backends.
  The transcriptions endpoint now accepts `temperature`, `best_of`,
  `prompt`, `hotwords`, `translate`, `vad`, `diarize`, `punctuation`,
  `ask`, `target_language` form fields. TTS endpoint accepts multipart
  with `voice_file` for voice cloning.
  Still TODO: `speaker` (stateful device DB).
- Keep this file honest with a test that fails when a capability lands on one
  surface but not the matrix.
