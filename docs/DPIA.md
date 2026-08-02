# Data Protection Impact Assessment (DPIA)

**Regulation:** GDPR Art. 35
**Application:** CrisperWeaver
**Date:** 2026-08-04 (revised; originally 2026-07-16)
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
- **A second, transient population of the same vector type.** Scoped
  explicitly on 2026-08-04, having previously been left out. Speaker
  **diarisation** also derives TitaNet embeddings — one per segment, for
  *every* speaker in any recording the user processes, enrolled or not,
  consented or not — when re-clustering to a requested speaker count. Two
  earlier revisions assessed the enrolment path in detail without asking
  what else computes an embedding.

  These are held in memory for the duration of the run and never written to
  disk, matched against the profile database, or linked to a name. On the
  assessment at `AI_ACT_RISK.md` §2.12 that keeps them outside Art. 9(1),
  which bites on biometric data processed *for the purpose of uniquely
  identifying* a natural person — diarisation asks only whether two
  utterances in one file are the same voice. **The conclusion is
  conditional on that.** Persisting, caching across runs, or matching a
  diarisation embedding against anything outside its own file would make it
  the processing §2.4 describes, and it would need §2.4's consent gate.
- **Volume:** Typically 1–20 enrolled speakers per user installation.
- **Geography:** Worldwide (app distributed via app stores and GitHub).

### 1.3 Context

- All processing occurs exclusively on the user's personal device.
- **No biometric data is transmitted to any server, cloud service, or
  third party** under any configuration. This holds even where the user
  enables the app's two optional cloud features (transcription,
  LLM cleanup/summarisation): those carry audio and transcript text
  respectively, never speaker embeddings or voice profiles. The scoping
  matters — an earlier revision stated the "no transmission" point
  unqualified, which read as a claim about the whole app rather than
  about the biometric processing this DPIA assesses.
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
| Third-party voice cloning without consent | Medium | High | Rights attestation required on **every** cloning path — voice-clone wizard, voice-bake screen, and the CLI's `--i-have-rights`; server requires consent_attestation; beep disclaimer mandatory on all of them |
| Data breach via device theft | Low | Medium | Standard device security (screen lock, encryption) is the user's responsibility; app does not add extra encryption layer |
| Diarisation embeddings outliving the run that made them | Low | Medium | Held in memory only, never persisted, never matched outside their own file. This is the assumption §1.2 and `AI_ACT_RISK.md` §2.12 rest on, so it is listed as a risk to keep true rather than as a fact already secured |

### 3.2 Overall Risk Level

**Moderate.** The primary risk is enrollment without the voice
owner's explicit consent. This is mitigated by the consent dialog,
consent records, and the voice-clone consent gate. The on-device-only
architecture for biometric data eliminates network-borne data breach
risks for that category.

Both audits that have run against this assessment found the same
failure mode, and it is worth naming rather than burying: the gates
themselves were sound, but a *parallel entry point* reached the same
operation without passing through one. In August 2026 it was a second
speaker-enrolment path (PLAN §15.3i); in the follow-up audit it was the
voice-bake screen and the CLI, neither of which asked for a rights
attestation while the wizard did. Consent architecture is only as good
as its least-guarded entrance, so the review question for any new
feature is not "does it have a gate" but "how many ways in are there".

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
database exists, and processing is confined to a single device under
the user's control.

**Correction (2026-08-01).** The earlier revision said processing was
"entirely under the data subject's control". That was wrong in the
common case. When a user enrols another participant from a recording,
the **user and the data subject are different people**, and the data
subject has no direct control over the device holding their embedding.
The mitigations that actually bear on this are:

- every enrolment path now presents a consent gate that asks the user
  to confirm the voice is their own **or** that they hold the explicit
  consent of the person it belongs to (GDPR Art. 9(2)(a));
- the match roster is derived from consent records, so a profile
  without recorded consent is never matched;
- erasure of the consent record removes the speaker from matching, so
  withdrawal of consent takes effect without any further user action.

The residual risk — a user who falsely attests consent — is a
misuse risk borne by the user as controller, not one the software can
eliminate. It is disclosed rather than mitigated away.

## 6. Review Schedule

This DPIA should be reviewed:
- When new biometric processing features are added
- When the data flow changes (e.g., cloud sync, server-side processing)
- Annually as part of the compliance review cycle

## 7. Document History

| Date | Change |
|---|---|
| 2026-08-04 | **Third audit.** Scoped §1.2 to the transient TitaNet embeddings derived by **diarisation**, which two prior revisions omitted entirely while assessing the enrolment path in detail — the same failure mode §3.2 already names, one level up: the question asked was "is the gate sound?" and never "what else derives this vector?". Added the corresponding risk row to §3.1, framed as an assumption to keep true rather than a fact already secured, since the Art. 9 analysis depends on it. |
| 2026-07-16 | Initial DPIA |
| 2026-08-01 | Audit revision: corrected the third-party data-subject assumption in §5; recorded the consent gate on every enrolment path and the consent-derived match roster. |
| 2026-08-02 | Second audit: scoped the "no transmission" statement in §1.3 to biometric data and named the two optional cloud flows it does not cover; extended the cloning-consent mitigation to the voice-bake screen and CLI, which had no attestation; recorded the recurring parallel-entry-point failure mode in §3.2. |
