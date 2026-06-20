# CrisperWeaver — capability parity matrix (GUI · CLI · Server)

Tracks which user-facing surface reaches each on-device speech capability.
Surfaces:

- **GUI** — Flutter screens/widgets (`lib/screens`, `lib/widgets`).
- **CLI** — `bin/crisperweaver.dart` (`dart run crisper_weaver:crisperweaver`),
  a thin wrapper over `package:crispasr` (the engine the GUI uses). It has no
  Flutter bindings, so it reaches engine *capabilities*, not GUI orchestration.
- **Server** — the built-in HTTP server (`lib/services/server_service.dart`).

Legend: ✅ reached · ➖ partial · ❌ not yet · — n/a.

| Capability | GUI | CLI | Server | Notes |
|---|---|---|---|---|
| List backends | ✅ (implicit) | ✅ `backends` | ➖ `/health` shows engine | |
| File ASR (transcribe) | ✅ | ✅ `transcribe` (+`--srt`) | ✅ `/v1/audio/transcriptions` | |
| Live / streaming ASR | ✅ | ❌ | ❌ | CLI/server streaming TODO |
| VAD | ✅ | ✅ `vad` | ✅ `/v1/audio/vad` | |
| Language ID (audio+text) | ✅ | ✅ `lid` (`--text`) | ➖ `/v1/audio/language` | server: audio only |
| Diarization | ✅ | ❌ | ❌ | CLI/server TODO |
| Speaker enroll / match | ✅ | ❌ | ❌ | CLI/server TODO |
| Forced alignment | ✅ (engine) | ❌ | ❌ | CLI/server TODO |
| Punctuation / PCS / truecase | ✅ | ✅ `punctuate` | ✅ `/v1/text/punctuate` | |
| TTS synthesis | ✅ | ✅ `synthesize` | ✅ `/v1/audio/speech` | |
| Voice cloning | ✅ | ➖ `synthesize --voice` | ❌ | |
| Voice baking | ✅ | ❌ | ❌ | desktop Python subprocess; GUI-only |
| Text translation | ✅ | ✅ `translate` | ✅ `/v1/translations` | |
| Speech-to-speech | ➖ | ❌ | ❌ | partial in GUI; verify (§9.5) |
| Watermark embed | ✅ | ✅ `watermark` | ❌ | |
| Watermark **detect** | ❌→test | ✅ `watermark --detect` | ❌ | was orphaned (§9.5); CLI + live test now cover it |
| RNNoise denoise | ✅ | ❌ | ❌ | CLI TODO |

## GUI-only by design (orchestration, not engine capabilities)

These wrap higher-level app state (history, files, network keys, Riverpod) and
are intentionally **not** mirrored to the CLI/server:

- Local / cloud LLM transcript cleanup & summarization
- Semantic search, A/B model compare, presets, batch queue, watch folder
- System audio capture, subtitle overlay, note/chapter export, model catalog/download

## Remaining parity work (PLAN §9.4)

- **CLI**: add `diarize`, `align`, `speaker` (enroll/match), `stream`, `s2s`.
- **Server**: `vad`, `lid` (audio), `punctuate` added. Still TODO: text-LID,
  `diarize`, `speaker`, `watermark`, `s2s`.
- Keep this file honest with a test that fails when a capability lands on one
  surface but not the matrix.
