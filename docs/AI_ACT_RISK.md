# EU AI Act Risk Classification — CrisperWeaver

**Date:** 2026-07-16
**Regulation:** Regulation (EU) 2024/1689 (EU AI Act)
**Application:** CrisperWeaver v0.9.0+

---

## 1. System Overview

CrisperWeaver is a cross-platform application for on-device audio
transcription, speech synthesis, speaker identification, document
analysis, and semantic search. All processing runs locally on the
user's device — no data is transmitted to external servers.

## 2. AI Subsystems and Risk Classification

### 2.1 Speech Recognition (ASR)

| Property | Value |
|---|---|
| Function | Converts audio to text |
| Annex III category | Not listed |
| Risk level | **Not high-risk** |
| Rationale | General-purpose transcription does not fall under any Annex III category. Not used for law enforcement, border control, employment, or critical infrastructure. |

### 2.2 Speech Synthesis (TTS)

| Property | Value |
|---|---|
| Function | Generates spoken audio from text |
| Annex III category | Not listed directly |
| Art. 50(4) applicability | **Yes** — generates synthetic audio that could constitute a "deep fake" |
| Risk level | **Subject to Art. 50 transparency obligations** |
| Mitigations | Spread-spectrum watermark (auto-embedded), C2PA COSE-signed provenance manifest, beep disclaimer on voice-cloned output, AI_GENERATED ID3v2/LIST INFO metadata, consent gate for voice cloning |

### 2.3 Voice Cloning (TTS with reference voice)

| Property | Value |
|---|---|
| Function | Generates speech replicating a specific person's voice |
| Art. 50(4) applicability | **Yes** — deep fake audio |
| GDPR Art. 9 applicability | **Yes** — processes biometric characteristics |
| Risk level | **Subject to Art. 50 + GDPR Art. 9** |
| Mitigations | Mandatory consent attestation, beep disclaimer (mandatory, override requires legal attestation), watermark + C2PA signing, consent audit logging |

### 2.4 Speaker Identification

| Property | Value |
|---|---|
| Function | Matches a voice against enrolled speaker profiles using TitaNet neural embeddings |
| Annex III category | **1(a): Biometric identification and categorisation of natural persons** |
| Risk level | **Potentially high-risk, but exempt from most obligations** |
| Rationale for exemption | See §3 below |
| Mitigations | Explicit GDPR Art. 9(2)(a) consent, on-device-only processing, right to erasure, consent record persistence |

### 2.5 Document Analysis (OCR)

| Property | Value |
|---|---|
| Function | Recognizes text in images using neural OCR engines |
| Annex III category | Not listed |
| Risk level | **Not high-risk** |
| Rationale | General-purpose text recognition, not used for surveillance, law enforcement, or access control |

### 2.6 Semantic Search

| Property | Value |
|---|---|
| Function | Dense vector similarity search over transcription history |
| Annex III category | Not listed |
| Risk level | **Not high-risk** |
| Rationale | Local search over user's own data, no profiling or scoring of natural persons |

## 3. Speaker Identification — Detailed Risk Assessment

CrisperWeaver's speaker identification subsystem uses TitaNet voice
embeddings to match audio segments against a locally-stored speaker
database. This falls under Annex III, Section 1(a): "AI systems
intended to be used for biometric identification and categorisation
of natural persons."

However, the system is **exempt from most high-risk obligations**
under Art. 6(3) because:

1. **No remote biometric identification.** All processing occurs
   exclusively on the user's device. No biometric data is transmitted
   to any server, database, or third party.

2. **No real-time identification.** The system matches pre-enrolled
   speakers against audio files, not against live camera/microphone
   feeds in real time.

3. **No publicly accessible spaces.** The system does not operate in
   publicly accessible physical spaces. It processes audio files
   selected by the user on their personal device.

4. **User-controlled enrollment.** Speakers are enrolled by the user
   with explicit consent. The user has full control over which voices
   are enrolled and can delete any profile at any time.

5. **Not used for law enforcement, border control, or access control.**
   The system has no integration with any surveillance, law enforcement,
   or access control infrastructure.

## 4. Art. 5 Compliance Statement (Prohibited Practices)

CrisperWeaver does **NOT** perform any of the practices prohibited
under Art. 5:

- (a) No subliminal, manipulative, or deceptive techniques
- (b) No exploitation of vulnerabilities of specific groups
- (c) No social scoring
- (d) No individual risk assessment for criminal offending prediction
- (e) No untargeted facial image scraping
- (f) No emotion inference in workplace or educational contexts
- (g) No biometric categorisation for sensitive attributes
- (h) **No real-time remote biometric identification in publicly
  accessible spaces** — all processing is on-device, user-initiated,
  on user-selected files

## 5. Art. 50 Compliance Summary (Transparency)

| Obligation | Implementation | Status |
|---|---|---|
| Art. 50(1): Users informed of AI interaction | First-use transparency dialog | Done |
| Art. 50(2): Machine-readable AI marking | Watermark + C2PA + metadata tags | Done |
| Art. 50(4): Deep fake disclosure | Beep disclaimer + watermark + signing | Done |

## 6. Document History

| Date | Change |
|---|---|
| 2026-07-16 | Initial risk classification document |
