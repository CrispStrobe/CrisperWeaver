# Data Protection Impact Assessment (DPIA)

**Regulation:** GDPR Art. 35
**Application:** CrisperWeaver
**Date:** 2026-07-16
**Assessor:** CrisperWeaver development team

---

## 1. Description of Processing

### 1.1 Nature of Processing

CrisperWeaver processes biometric data in the form of voice embeddings
(TitaNet neural speaker representations) for the purpose of speaker
identification — matching audio segments against locally-enrolled
speaker profiles.

### 1.2 Scope

- **Data subjects:** Users who voluntarily enroll their voice, and
  speakers whose voices appear in audio files processed by the user.
- **Data types:** Voice embeddings (256-dimensional float vectors
  derived from audio via TitaNet), stored as `.spk` files.
- **Volume:** Typically 1–20 enrolled speakers per user installation.
- **Geography:** Worldwide (app distributed via app stores and GitHub).

### 1.3 Context

- All processing occurs exclusively on the user's personal device.
- No data is transmitted to any server, cloud service, or third party.
- The user has full control over enrollment, deletion, and export.
- The app is not deployed in any workplace, educational, law
  enforcement, or public-space context by the developer.

### 1.4 Purpose

Enable the user to label audio transcription segments with speaker
names (e.g., "Alice said X, Bob said Y") by matching voice
characteristics against voluntarily enrolled profiles.

## 2. Necessity and Proportionality

### 2.1 Lawful Basis

**Explicit consent** (GDPR Art. 9(2)(a)). Before any biometric
processing, the app presents a consent dialog explaining:

- That voice embeddings are biometric data under GDPR Art. 9
- That data is stored on-device only and never transmitted
- That the user can delete their data at any time
- The specific purpose (speaker identification)
- The legal basis (GDPR Art. 9(2)(a))

Consent must be actively given (checkbox/button). A consent record
(`.consent.json`) is persisted alongside each speaker profile.

### 2.2 Necessity

Voice embeddings are the minimum viable representation for speaker
matching. Raw audio is not stored for speaker profiles — only the
derived embedding vector, which cannot be reversed to reconstruct
the original audio.

### 2.3 Proportionality

- **Data minimization:** Only a 256-float vector is stored, not raw
  audio. The embedding is a lossy one-way transform.
- **Purpose limitation:** Embeddings are used solely for speaker
  label assignment in transcriptions.
- **Storage limitation:** Users can delete profiles at any time.
  No automatic retention or archival.
- **No profiling:** The system does not score, rank, or profile
  data subjects beyond speaker label assignment.

## 3. Risk Assessment

### 3.1 Risks to Data Subjects

| Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|
| Unauthorized access to voice embeddings | Low | Medium | On-device only; OS-level file permissions; no network transmission |
| Re-identification from embeddings | Very Low | Medium | Embeddings are lossy transforms; cannot reconstruct audio; no centralized database to match against |
| Enrollment without subject consent | Medium | High | Consent gate in both GUI (wizard checkbox) and API (403 without attestation); consent record logged |
| Use for surveillance or law enforcement | Very Low | Very High | App is consumer software with no integrations to surveillance systems; Art. 5 compliance documented |
| Third-party voice cloning without consent | Medium | High | Voice clone wizard requires rights attestation; server requires consent_attestation; beep disclaimer mandatory |
| Data breach via device theft | Low | Medium | Standard device security (screen lock, encryption) is the user's responsibility; app does not add extra encryption layer |

### 3.2 Overall Risk Level

**Moderate.** The primary risk is enrollment without the voice
owner's explicit consent. This is mitigated by the consent dialog,
consent records, and the voice-clone consent gate. The on-device-only
architecture eliminates network-borne data breach risks.

## 4. Mitigations

### 4.1 Technical Measures

- **On-device processing:** No biometric data leaves the device.
- **Consent gate:** Explicit consent dialog before enrollment;
  consent record persisted with timestamp and legal basis.
- **Right to erasure:** `deleteSpeaker()` removes both embedding and
  consent record.
- **Data portability:** `exportSpeakerData()` exports all data.
- **Voice-clone consent:** Attestation required before cloning;
  403 on server API without attestation.
- **Mandatory watermarking:** All synthesized audio is watermarked
  and C2PA-signed.
- **Audit logging:** Consent attestations logged with timestamps.

### 4.2 Organizational Measures

- Privacy policy (PRIVACY.md §5) explicitly covers biometric data.
- Risk classification document (AI_ACT_RISK.md) documents the
  Annex III self-assessment.
- First-use transparency notice informs users of all AI systems.
- Open-source codebase enables public audit.

## 5. Consultation

This DPIA was prepared by the development team. No DPA consultation
under Art. 36 is required because the residual risk after mitigations
is not high — no biometric data is transmitted, no centralized
database exists, and processing is entirely under the data subject's
control.

## 6. Review Schedule

This DPIA should be reviewed:
- When new biometric processing features are added
- When the data flow changes (e.g., cloud sync, server-side processing)
- Annually as part of the compliance review cycle

## 7. Document History

| Date | Change |
|---|---|
| 2026-07-16 | Initial DPIA |
