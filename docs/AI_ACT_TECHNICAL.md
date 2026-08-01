# EU AI Act Technical Documentation (Annex IV)

**Application:** CrisperWeaver
**Date:** 2026-08-01 (revised; originally 2026-07-16)
**Regulation:** Regulation (EU) 2024/1689, Annex IV

---

## 1. General Description (Annex IV, 1)

### 1.1 Intended Purpose

CrisperWeaver is a cross-platform application for on-device audio
transcription, speech synthesis, speaker identification, document
analysis (OCR), and semantic search. It enables users to convert
speech to text, generate speech from text, identify speakers in
recordings, and search their transcription history.

### 1.2 Provider

Open-source project maintained at
[github.com/CrispStrobe/CrisperWeaver](https://github.com/CrispStrobe/CrisperWeaver).

### 1.3 Version

Current release: v0.9.1+
Engine dependency: CrispASR 0.8.12, CrispEmbed 0.15.1

### 1.4 Interaction with Other Systems

- **CrispASR** (path dependency): C++ speech recognition and synthesis
  engine, accessed via Dart FFI.
- **CrispEmbed** (path dependency): C++ text/vision embedding engine,
  accessed via Dart FFI.
- **HuggingFace** (optional network): GGUF model downloads over HTTPS.
- No other external system interactions in default configuration.

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

- **Unit tests:** 1164 tests covering services, providers, utilities,
  engines, compliance, and catalog integrity.
- **Live tests:** Integration tests against real ASR/TTS models on
  developer hardware (tagged `@slow`, run separately from CI).
- **Compliance tests:** 53 dedicated tests for EU AI Act compliance
  (watermark round-trip, C2PA manifest, disclosure defaults, consent
  records, privacy constants).
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
| AI-generated audio misattributed as human | Art. 50 | Automatic watermark + C2PA signing + metadata tags |
| Voice cloning for impersonation | Art. 50(4) | Consent gate + mandatory beep disclaimer + audit logging |
| Biometric data misuse | GDPR Art. 9 | Explicit consent + on-device only + right to erasure |
| Transcription errors affecting decisions | Accuracy | Word-level confidence scores; user can verify and edit |
| Model bias in ASR | Fairness | Multiple model families available; user chooses |

## 6. Post-Market Monitoring (Annex IV, 6)

### 6.1 Feedback Channels

- GitHub Issues: [CrispStrobe/CrisperWeaver/issues](https://github.com/CrispStrobe/CrisperWeaver/issues)
- Users can report accuracy issues, compliance concerns, or bugs.

### 6.2 Update Mechanism

- App updates via GitHub Releases and platform app stores.
- Model updates via HuggingFace (user-initiated downloads).
- No automatic updates without user action.

### 6.3 Monitoring Metrics

- Test suite pass rate (1164 tests, CI-enforced)
- Compliance test coverage (53 tests for EU AI Act requirements)
- GitHub issue tracking for reported problems

## 7. Instructions for Use (Art. 13)

### 7.1 Capabilities and Limitations

- CrisperWeaver performs AI-based speech recognition, speech synthesis,
  speaker identification, and document analysis.
- Accuracy depends on the selected model, audio quality, language, and
  domain. No model achieves 100% accuracy.
- Speaker identification is probabilistic; false matches are possible.
- Voice cloning produces synthetic audio that may closely resemble the
  reference voice but is not identical.

### 7.2 Intended Users

General-purpose consumers and professionals who need on-device audio
transcription and speech synthesis. Not intended for law enforcement,
border control, employment decisions, or critical infrastructure.

### 7.3 Foreseeable Misuse

- Using voice cloning to impersonate individuals without consent
  (mitigated by consent gate, watermark, and beep disclaimer).
- Using speaker identification for unauthorized surveillance
  (mitigated by on-device-only architecture and Art. 5 compliance).
- Relying on transcriptions for high-stakes decisions without human
  review (mitigated by confidence scores and user editing capability).

## 8. Document History

| Date | Change |
|---|---|
| 2026-07-16 | Initial Annex IV technical documentation |
