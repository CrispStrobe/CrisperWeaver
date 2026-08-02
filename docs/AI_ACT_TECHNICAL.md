# EU AI Act Technical Documentation (Annex IV)

**Application:** CrisperWeaver
**Date:** 2026-08-04 (revised; originally 2026-07-16)
**Regulation:** Regulation (EU) 2024/1689, Annex IV

---

## 1. General Description (Annex IV, 1)

### 1.1 Intended Purpose

CrisperWeaver is a cross-platform application for on-device audio
transcription, speech synthesis, speaker identification, document
analysis (OCR), LLM-backed text processing, and semantic search. It
enables users to convert speech to text, generate speech from text,
identify speakers in recordings, translate and summarise transcripts,
and search their transcription history.

**No emotion recognition is performed**, and this is enforced on two
distinct routes because it was reached by two.

- **Model-emitted tags.** SenseVoice transcription backends emit inline
  emotion tags and the app rendered them as a per-segment badge until
  2026-08-02; that made it an emotion recognition system under Art. 3(39)
  and an Annex III 1(c) high-risk system, so the capability was removed.
  The tags are discarded at the engine's parse boundary and on every CLI
  output format. See `AI_ACT_RISK.md` §2.8.
- **User-written prompts.** The audio-Q&A field passes a free-text question
  to an instruct-tuned backend, and until 2026-08-03 its placeholder
  recommended *"What's the speaker's tone?"* in all three shipped
  languages. `AffectivePromptGuard` now refuses emotion, mood, prosody,
  intent and veracity prompts at the engine, the HTTP server and the CLI.
  See `AI_ACT_RISK.md` §2.9.

The two controls are not equivalent and the difference is worth stating: the
first is an absence, the second is a keyword filter over free text that a
determined user can rephrase past. It is a control against the app
*affording* emotion inference — which is what supplies intended purpose
under Art. 3(39) — not a guarantee about every sentence a model can emit.

**Corrected 2026-08-04.** The tag filter was described above as covering "the
engine's parse boundary", singular, and that is what it was: the code lived
inside `CrispasrEngine`. `HfSpaceEngine` — the cloud path, offered on every
platform and the only engine in the web build — parsed the remote server's
text into segments with no tag handling on either of its two routes. Nothing
reachable exercised it, since that engine's backend list offers no
SenseVoice-family model, so this was latent rather than live. The filter now
lives in `EmotionInference.strip`; both engines call it, and the compliance
suite asserts that every engine parsing model text does.

### 1.2 Provider

Open-source project maintained at
[github.com/CrispStrobe/CrisperWeaver](https://github.com/CrispStrobe/CrisperWeaver).

### 1.3 Version

Current release: v0.9.6 (build 76).
Engine dependencies, pinned to release tags in CI (`.github/workflows/`)
rather than tracking a moving branch: CrispASR v0.8.25, CrispEmbed
v0.16.1, glint_audio v0.11.0.

### 1.4 Interaction with Other Systems

- **CrispASR** (path dependency): C++ speech recognition and synthesis
  engine, accessed via Dart FFI.
- **CrispEmbed** (path dependency): C++ text/vision embedding engine,
  accessed via Dart FFI.
- **glint_audio** (path dependency): C codec suite for MP3/AAC/Opus
  decode, accessed via Dart FFI.
- **HuggingFace** (optional network): GGUF model downloads over HTTPS.
  Also hosts the optional cloud-transcription Space.
- **User-configured OpenAI-compatible LLM endpoint** (optional network,
  opt-in, off by default): receives transcript text for cleanup or
  summarisation when the user enables cloud mode and supplies a URL and
  key. The endpoint is chosen entirely by the user — the app has no
  default and no relationship with any provider. See `AI_ACT_RISK.md`
  §2.7 and `PRIVACY.md` §3.3.
- No other external system interactions. In the **default**
  configuration the only network traffic is model downloads.

CrisperWeaver also *exposes* two interfaces of its own, both bound to
localhost and both off unless started by the user: an OpenAI-compatible
HTTP server (`server_service.dart`) and a Wyoming-protocol ASR socket.
Generated output crossing either carries the same marking as the GUI's —
`x-content-ai-generated` on generating endpoints, watermark and manifest
in the audio bytes.

**This claim was false when first written (2026-08-02) and is true as of
2026-08-03.** `/v1/audio/transcriptions` also translates (`translate`,
`target_language`) and answers questions (`ask`), and returned both
unmarked under a hardcoded `"task": "transcribe"` — while the sibling
`/v1/translations` set the header and a `_disclosure` field. The endpoint
now marks all five response formats and reports the actual task. Recorded
rather than silently fixed, because the claim was checked against the
endpoints that looked like generators and not against the one whose name
says "transcriptions".

## 2. Design Specifications (Annex IV, 2)

### 2.1 Architecture

```
┌─────────────────────────────────────────────────┐
│                  Flutter UI Layer                │
│  (Screens, Widgets, Providers, GoRouter)        │
├─────────────────────────────────────────────────┤
│               Service Layer (Dart)               │
│  TranscriptionService, TtsService, SpeakerIdSvc │
│  SemanticSearchSvc, OcrService, ServerService   │
├─────────────────────────────────────────────────┤
│            FFI Bridge (dart:ffi)                 │
│  CrispASR binding, CrispEmbed binding           │
├─────────────────────────────────────────────────┤
│         Native C++ Engines                       │
│  libcrispasr (43 ASR + 48 TTS backends)         │
│  libcrispembed (embeddings, OCR, NER, vision)   │
└─────────────────────────────────────────────────┘
```

### 2.2 AI Model Format

All models use the GGUF (GGML Universal Format) binary format.
Models are quantized (Q4_K, Q5_K, Q8_0) for efficient on-device
inference. No training occurs on-device — inference only.

### 2.3 Key Design Decisions

- **On-device only:** All inference runs locally. No cloud processing
  in default configuration.
- **Privacy by design:** No telemetry, no analytics, no user accounts.
- **Model-agnostic:** Users choose from 40+ ASR and 20+ TTS model
  families; the app is not coupled to any single model.
- **Provenance by default:** All AI-generated audio is watermarked
  and C2PA-signed automatically.

## 3. Development Methodology (Annex IV, 3)

### 3.1 Development Process

- Open-source development on GitHub with public commit history.
- Flutter (Dart) for cross-platform UI; C++17 for native engines.
- Continuous integration via GitHub Actions (build, analyze, test).
- Code review for all changes.

### 3.2 Testing

- **Unit tests:** ~1200 tests covering services, providers, utilities,
  engines, compliance, and catalog integrity.
- **Live tests:** Integration tests against real ASR/TTS models on
  developer hardware (tagged `@slow`, run separately from CI).
- **Compliance tests:** dedicated tests for EU AI Act compliance in
  `test/synthetic_compliance_test.dart` (watermark round-trip and
  measured detector floor, C2PA manifest, export and text disclosure
  defaults, consent records and consent-derived speaker roster, privacy
  constants). The count is deliberately not quoted here — it moved
  53 → 62 → 66 → 71 over three audits, and a number in prose goes stale
  faster than the suite does.
- **Widget tests:** Screen-level tests for transcription and synthesis
  UI flows.

### 3.3 Quality Management

- `flutter analyze` enforced in CI with zero-error policy.
- Lint rules: `prefer_const_constructors`, `prefer_const_declarations`,
  `curly_braces_in_flow_control_structures`.
- Automated model catalog consistency checks (backend dispatch parity
  guard prevents catalog/engine drift).

## 4. Data Governance (Annex IV, 4)

### 4.1 Training Data

CrisperWeaver does not train AI models. All models are pre-trained
by their respective research teams and distributed as GGUF files.
The app performs inference only.

### 4.2 User Data

| Data Type | Storage | Retention | Transmission |
|---|---|---|---|
| Audio recordings | App documents dir | Until user deletes | Never |
| Transcripts | JSON in app docs dir | Until user deletes | Never |
| Speaker embeddings | `.spk` files in app docs dir | Until user deletes | Never |
| Consent records | `.consent.json` alongside `.spk` | Until speaker deleted | Never |
| Settings | SharedPreferences | Until app uninstalled | Never |
| Downloaded models | App models dir | Until user deletes | Never |

### 4.3 Data Processing

All data processing occurs on-device. The only network traffic is:
- HTTPS GET requests to HuggingFace CDN for model downloads (user-initiated)
- Optional cloud transcription via user-configured HuggingFace Space (opt-in, off by default)

## 5. Risk Management (Annex IV, 5)

See `docs/AI_ACT_RISK.md` for the full risk classification under
Annex III and Art. 5, including the provider/deployer split of the
Art. 50 duties (§5.1 there) and the applicable dates (§8 there).

**Applicable dates in short:** Art. 5 and Art. 4 have applied since
2 Feb 2025. **Art. 50 transparency applies from 2 Aug 2026** and was
excluded from the Digital Omnibus deferral. Annex III high-risk
obligations were deferred to **2 Dec 2027**. A grace period to
2 Dec 2026 covers Art. 50(2) marking for systems already on market.

See `docs/DPIA.md` for the Data Protection Impact Assessment covering
biometric data processing risks.

### 5.1 Known Risks and Mitigations

| Risk | Category | Mitigation |
|---|---|---|
| AI-generated audio misattributed as human | Art. 50 | Automatic watermark + C2PA signing + metadata tags, on every generating path (GUI, HTTP server, CLI) |
| AI-generated text mistaken for authored text | Art. 50(2) | Disclosure attached to OCR, LLM summaries and translations on screen and on copy/export; `x-content-ai-generated` on the HTTP translation endpoint |
| Voice cloning for impersonation | Art. 50(4) | Consent gate on **every** cloning path (wizard, voice-bake screen, CLI `--i-have-rights`) + mandatory beep disclaimer + audit logging |
| Biometric data misuse | GDPR Art. 9 | Explicit consent + on-device only + right to erasure |
| Transcript text disclosed to a third party | GDPR | Cloud LLM is opt-in and off by default; local model is the default path; flow disclosed in the first-use notice and `PRIVACY.md` §3.3 |
| Transcription errors affecting decisions | Accuracy | Word-level confidence scores; user can verify and edit |
| Model bias in ASR | Fairness | Multiple model families available; user chooses |
| Emotion inference reaching a user or an export — model-emitted tags | Art. 5(1)(f), Annex III 1(c) | Capability removed. Emotion tags are discarded at the single point they enter the app (`CrispasrEngine`) and on every CLI output format, driven by one shared discard list and pinned by the compliance suite |
| Emotion inference elicited by a user prompt | Art. 5(1)(f), Annex III 1(c) | `AffectivePromptGuard` refuses affective audio-Q&A prompts at the engine, the HTTP server and the CLI; a locale test asserts no shipped UI string suggests one. Defeatable by rephrasing — stated in `AI_ACT_RISK.md` §2.9, not claimed away |
| Generated Q&A answers mistaken for transcripts | Art. 50(2) | Segments flagged `generated: audio-qa` at the engine; every export, the transcriptions endpoint and CLI stdout pick their disclosure from the flag |
| **A mark that does not survive being saved** | Art. 50(2) | `HistoryEntry` round-trips segment `metadata` through the history JSON. Written as already-true above until 2026-08-04, when the audit found `toJson` enumerating segment fields by hand with `metadata` not among them — so the flag died on save and a re-export from History called an answer a transcript. Pinned by a round-trip test, a back-compat test for older history files, and a test that an unencodable value is dropped rather than thrown |
| Machine translation mistaken for a transcript | Art. 50(2) | `CrispasrEngine` stamps `generated: translation`, so the GUI exporters reach what the CLI and the HTTP server already read off the request. Exports say "machine translation", not "produced by AI speech recognition" |
| A transcript export implying the recording was faked | Art. 50(2) | The transcript notice said the content "contains AI-generated synthetic speech" — false for a recording of a real person, and in the direction that misleads. Both exporters now use the same "machine-generated transcript" wording |
| Chapter exports escaping the notice | Art. 50(2) | Chapter titles are verbatim transcript text written to a shared file; the YouTube and Podcasting 2.0 exports carry the notice their segments earned |
| Cloud TTS returning unmarked audio | Art. 50(2) | `HfSpaceTtsService` probes remote output for a watermark and embeds one locally when absent, verifying the result rather than assuming it |
| Generated audio loses its mark when edited | Art. 50(2) | Trim/cut/split carry the C2PA manifest across as a `c2pa.edited` action and re-emit LIST/INFO; MP3 re-encode carries ID3v2; containers that cannot carry a manifest are logged as watermark-only |
| Headless output escapes text marking | Art. 50(2) | CLI `translate` and `transcribe --translate` attach the shared `AiTextDisclosure`; suppression requires an explicit `--no-disclosure` |

## 6. Post-Market Monitoring (Annex IV, 6)

### 6.1 Feedback Channels

- GitHub Issues: [CrispStrobe/CrisperWeaver/issues](https://github.com/CrispStrobe/CrisperWeaver/issues)
- Users can report accuracy issues, compliance concerns, or bugs.

### 6.2 Update Mechanism

- App updates via GitHub Releases and platform app stores.
- Model updates via HuggingFace (user-initiated downloads).
- No automatic updates without user action.

### 6.3 Monitoring Metrics

- Test suite pass rate (CI-enforced, zero-error `flutter analyze`)
- Compliance test coverage (`test/synthetic_compliance_test.dart`)
- GitHub issue tracking for reported problems
- Abuse reports via the channel embedded in every generated file's C2PA
  manifest (`AI_ACT_RISK.md` §7.1)

## 7. Instructions for Use (Art. 13)

### 7.1 Capabilities and Limitations

- CrisperWeaver performs AI-based speech recognition, speech synthesis,
  speaker identification, and document analysis.
- Accuracy depends on the selected model, audio quality, language, and
  domain. No model achieves 100% accuracy.
- Speaker identification is probabilistic; false matches are possible.
- Voice cloning produces synthetic audio that may closely resemble the
  reference voice but is not identical.
- CrisperWeaver does **not** infer emotions, mood, intent, or any other
  affective or personal attribute from a voice. Where a model emits such a
  label, it is discarded rather than shown (`AI_ACT_RISK.md` §2.8); where a
  user asks for one via the audio-Q&A field, the prompt is refused rather
  than answered (`AI_ACT_RISK.md` §2.9).
- Audio Q&A ("ask the audio") produces a **language model's answer, not a
  transcript**. It can assert things the recording does not contain, and
  there is no transcript beside it to check against. Its output is marked
  as AI-generated wherever it leaves the app.
- Spoken-language identification classifies the audio, not the speaker; the
  result is a decode hint and is never stored as an attribute of a person
  (`AI_ACT_RISK.md` §2.10).
- Speech **translation** output is the model's words, not the speaker's. It
  is marked as a machine translation wherever it leaves the app, and it
  should not be quoted as if it were what someone said
  (`AI_ACT_RISK.md` §5.2).
- **Diarisation** separates voices within one recording; it does not
  identify anyone. Its labels are positional until the user renames them,
  and the speaker embeddings it derives are transient and never written to
  disk (`AI_ACT_RISK.md` §2.12).

### 7.2 Intended Users

General-purpose consumers and professionals who need on-device audio
transcription and speech synthesis. Not intended for law enforcement,
border control, employment decisions, or critical infrastructure.

### 7.3 Foreseeable Misuse

- Using voice cloning to impersonate individuals without consent
  (mitigated by consent gate, watermark, and beep disclaimer).
- Using speaker identification for unauthorized surveillance
  (mitigated by on-device-only architecture and Art. 5 compliance).
- Inferring emotions to assess staff or students — **prohibited under
  Art. 5(1)(f)**. Mitigated structurally on the model-emitted route (no such
  output exists, `AI_ACT_RISK.md` §2.8) and by an input-side refusal on the
  prompt route (`AI_ACT_RISK.md` §2.9). The second is the weaker of the two
  and is the one to re-examine if this document is ever relied on.
- Relying on transcriptions for high-stakes decisions without human
  review (mitigated by confidence scores and user editing capability).

## 8. Document History

| Date | Change |
|---|---|
| 2026-08-04 | **Fifth audit.** Corrected §1.1, which described the emotion filter as sitting at "the engine's parse boundary" when it sat inside one of three engines. Added six rows to §5.1 — the largest being that the fourth audit's `generated` flag was discarded on save, so every claim about history re-exports was false. Added §7.1 limitations for machine translation and diarisation. See `AI_ACT_RISK.md` §9 for the full finding list, and §2.12/§2.13 there for the two newly classified subsystem groups. |
| 2026-08-03 | **Fourth audit.** Corrected §1.4, which claimed all generated output crossing the HTTP server was marked — `/v1/audio/transcriptions` returned machine translation and audio-Q&A answers bare. Rewrote §1.1 to cover both routes to emotion recognition and to state the difference in strength between the two controls. Added three rows to §5.1 (prompt-elicited emotion inference, Q&A answers mismarked as transcripts) and three limitations to §7.1. |
| 2026-07-16 | Initial Annex IV technical documentation |
| 2026-08-01 | Audit revision: applicable dates refreshed for the Digital Omnibus; §5 cross-referenced to the provider/deployer split in `AI_ACT_RISK.md` §5.1. (Recorded retrospectively — the 2026-08-02 audit found this row had been omitted when the revision was made.) |
| 2026-08-02 | **Third audit.** Found a previously undeclared emotion-recognition capability (SenseVoice emotion badges); it was **removed** rather than disclosed, since Annex III 1(c) would have made it high-risk from 2 Dec 2027. §1.1, §7.1 and §7.3 now record the absence and how it is enforced. Added three rows to §5.1 covering the removal, provenance survival across edits, and CLI text marking. |
| 2026-08-02 | Second audit. Corrected version and engine pins in §1.3, which had drifted three releases; added the LLM text subsystem and the localhost server/Wyoming interfaces to §1.4; replaced hard-coded test counts with pointers in §3.2/§6.3; added text-marking, cloud-disclosure and every-cloning-path rows to §5.1. |
