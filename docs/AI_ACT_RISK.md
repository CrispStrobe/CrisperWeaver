# EU AI Act Risk Classification — CrisperWeaver

**Date:** 2026-08-01 (revised; originally 2026-07-16)
**Regulation:** Regulation (EU) 2024/1689 (EU AI Act)
**Application:** CrisperWeaver v0.9.6+

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
| Function | Confirms a **claimed** participant against a closed, consent-derived roster of enrolled profiles using TitaNet neural embeddings |
| Annex III category | **Outside 1(a)** — biometric *verification*, which 1(a) expressly excludes |
| Risk level | **Not high-risk** (fallback argument under Art. 6(3) if that reading is rejected) |
| Rationale | See §3 below |
| Mitigations | Closed-roster API (`expectedNames` + `consentAttested`, throws without consent), explicit GDPR Art. 9(2)(a) consent gate on every enrolment path, roster derived from consent records so withdrawal removes the speaker from matching, on-device-only processing, right to erasure, data portability |

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
database.

### 3.1 Primary argument — this is verification, not identification

Annex III, Section 1(a) covers **remote biometric identification
systems** and expressly **excludes** "AI systems intended to be used for
biometric verification whose sole purpose is to confirm that a specific
natural person is the person he or she claims to be."

Since v0.9.6 the subsystem is architecturally constrained to exactly
that. `CrispasrSpeakerDB` is opened as a **closed roster**: the caller
must declare, up front, the list of claimed participants
(`expectedNames`) plus an explicit consent attestation
(`consentAttested`); construction throws without the latter. Matching
confirms a claimed participant. It is **never an open 1:N search**
against the full profile database.

CrisperWeaver derives that roster from consent records on disk: a
profile without a persisted GDPR Art. 9(2)(a) consent record is excluded
from the roster and can never be matched. Withdrawal of consent (erasing
the record) therefore removes the speaker from matching automatically.

On this basis the subsystem is **outside Annex III 1(a)** rather than
being a high-risk system that benefits from a derogation.

### 3.2 Secondary argument — Art. 6(3), and its limits

Were a supervisory authority to characterise the subsystem as falling
within Annex III 1(a) anyway, the Art. 6(3) derogation would be argued
on these facts:

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

**Two caveats that the earlier revision of this document omitted:**

- **Art. 6(3) is not self-executing.** A provider relying on the
  derogation must *document* the assessment before placing the system on
  the market, and — under Art. 49(2) — **register the system in the EU
  database**. Invoking the derogation is not the same as escaping
  registration. This matters only if §3.2 ever becomes the operative
  reading: on the §3.1 analysis the subsystem is outside Annex III, so
  Art. 6(3) is never reached and Art. 49(2) does not bite. See §7.3 for
  the four changes that would re-open it.
- **The derogation is void where the system performs profiling** of
  natural persons. CrisperWeaver does not profile: it resolves a
  diarisation label to a name and stores no behavioural, inferential, or
  categorical attributes about any speaker.

### 3.3 What is *not* claimed

No emotion recognition and no biometric **categorisation** is performed.
The Chatterbox `[angry]` / `[whispering]` tags in the synthesis screen
are generation-side prosody controls — they steer TTS output and infer
nothing about any person. Art. 50(3) is therefore not engaged on the
emotion-recognition limb.

## 3a. Free and open-source status (Art. 2(12))

CrisperWeaver is released under AGPL-3.0. Art. 2(12) exempts AI systems
released under free and open-source licences from parts of the
Regulation — but that exemption **does not extend to Art. 50**, nor to
prohibited practices or high-risk systems. The transparency obligations
in §5 below apply in full and are not mitigated by the licence. This is
recorded here to prevent the exemption being over-read.

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

### 5.1 Who is bound by what

Art. 50 splits its duties between two roles, and CrisperWeaver occupies
only one of them. Conflating the two — as the earlier revision of this
document did — overstates what the software can discharge on the user's
behalf.

| Para | Binds | Who that is here |
|---|---|---|
| 50(1) interaction disclosure | **Provider** | CrisperWeaver |
| 50(2) machine-readable marking of synthetic content | **Provider** | CrisperWeaver |
| 50(3) emotion recognition / biometric categorisation notice | **Deployer** | n/a — not performed (§3.3) |
| 50(4) deep fake + public-interest text disclosure | **Deployer** | **the end user**, not CrisperWeaver |

CrisperWeaver cannot discharge a deployer's Art. 50(4) duty. What it
does is make compliance the default and non-compliance deliberate: the
beep disclaimer is applied automatically to every cloned and
voice-converted output, and suppressing it requires a written
attestation that is logged for audit.

### 5.2 Implementation status

| Obligation | Implementation | Status |
|---|---|---|
| Art. 50(1): Users informed of AI interaction | First-use transparency dialog (EN/DE/ZH) | Done |
| Art. 50(2): Machine-readable AI marking — audio | Spread-spectrum watermark, verified post-embed by probing the PCM; C2PA COSE/X.509 manifest; WAV LIST/INFO + ID3v2 tags | Done |
| Art. 50(2): Machine-readable AI marking — text | Transcript exports carry a synthetic-content disclosure by default; OCR output carries a disclosure on screen and on copy | Done |
| Art. 50(4): Deep fake disclosure — voice cloning | Mandatory beep disclaimer; suppression requires a logged attestation | Done |
| Art. 50(4): Deep fake disclosure — speech-to-speech | Same beep path via `voiceConverted`; `/v1/audio/s2s` consent-gated | Done |

## 6. Art. 4 — AI Literacy

Art. 4 has applied since 2 February 2025 and obliges providers and
deployers to take measures ensuring a sufficient level of AI literacy
among staff and others operating the system on their behalf.

CrisperWeaver is developed by a single maintainer with no staff, so the
staff-training limb is inapplicable. The obligation is discharged toward
users by:

- the first-use transparency notice enumerating every AI subsystem in
  use and stating that all processing is on-device;
- `docs/AI_ACT_TECHNICAL.md` §"Instructions for use" (Art. 13), which
  documents capabilities and known limitations;
- explicit accuracy caveats where output is most likely to be
  over-trusted — the OCR disclosure tells the user to verify before
  relying on the text.

## 7. Open Items

| Item | Status |
|---|---|
| Anti-impersonation policy / acceptable use | **Done** — [`ACCEPTABLE_USE.md`](../ACCEPTABLE_USE.md) v1.0 |
| Third-party abuse-reporting channel | **Done** — see §7.1 |
| Code of Practice on Transparency of AI-generated Content | **Assessed** — see §7.2. Technically conformant; *signing* is an outstanding decision for the maintainer |
| Art. 49(2) EU-database registration | **Not applicable** on the operative analysis — see §7.3 |
| C2PA signing for MP3 exports | **Not applicable** — no MP3 export exists; see §7.4 |

### 7.1 Abuse-reporting channel

The recipient of a synthetic clip is the person most likely to notice
misuse, and they typically have no idea what produced it. A policy
published only on a website is unreachable to someone holding a WAV, so
the reporting channel is embedded **in the C2PA manifest of every file
the app generates** (`crisperweaver.abuse-reporting` assertion:
acceptable-use policy URL, reporting URL, and a plain-language note).
It therefore travels with the audio. A GitHub issue template backs the
URL.

The channel is deliberately honest about its limits. CrisperWeaver is
offline software with no accounts, no servers and no kill switch: the
project can confirm whether a file carries our watermark and manifest,
help interpret that, and harden the marking — it **cannot** identify who
generated a file, disable an installation, or take content down. The
template says so up front and redirects urgent harm to law enforcement
and national DPAs.

### 7.2 Code of Practice on Transparency of AI-generated Content

Final since 10 June 2026; adherence is voluntary while the underlying
Art. 50 duties are binding. Signatories gain predictability and legal
certainty across Member States and avoid individual compliance
assessments by market surveillance authorities.

Its core commitment — outputs marked in a machine-readable format and
detectable as artificially generated, by means that are "effective,
interoperable, robust and reliable as far as technically feasible" — is
already met, and on the robustness limb arguably exceeded:

| CoP expectation | CrisperWeaver |
|---|---|
| Machine-readable marking | C2PA manifest (COSE-signed where available) + WAV `LIST`/`INFO` + ID3v2 tags |
| Detectable as AI-generated | Spread-spectrum watermark, **verified after embedding** by probing the PCM, not assumed |
| Interoperable | C2PA is the industry standard; the watermark is cross-compatible with the CrispASR / CrispTTS detectors |
| Robust | Watermark survives re-encoding; container metadata does not, and that limit is disclosed to users rather than glossed |
| "As far as technically feasible" | Sub-100 ms and digitally silent audio cannot carry a spectral watermark; the app **reports** this instead of claiming a mark it did not make |

**Outstanding:** signing the Code is an organisational act only the
maintainer can perform — complete the Signatory Form and email it to
`CNECT-AIOFFICE-CODE-OF-PRACTICE-TRANSPARENCY@ec.europa.eu`, signed by
someone with authority to bind the provider. Open at any time; the
initial-signatories list closed 22 July 2026.

Note the benefit precisely: signatories can *demonstrate* compliance and
have enforcement focused on monitoring adherence rather than individual
assessment by each national market surveillance authority. This is **not**
an Art. 40 "presumption of conformity" — that concept attaches to
harmonised standards, not codes of practice.

Signing is a judgement call rather than a technical gap. It commits the
project to the code's measures on an ongoing basis, so diverging later is
a worse position than never having signed, and the benefit mainly accrues
to providers who expect to be assessed. Art. 50 itself is met either way.

### 7.3 Art. 49(2) registration

Art. 49(2) obliges a provider who considers an **Annex III** system not
high-risk under the Art. 6(3) derogation to register it in the EU
database before placing it on the market.

On the operative analysis (§3.1) the speaker-identification subsystem is
biometric **verification**, which Annex III 1(a) expressly excludes — so
it is not an Annex III system at all, Art. 6(3) is never reached, and
Art. 49(2) does not bite. That is why this is marked *not applicable*
rather than *not done*.

This conclusion depends on the closed-roster architecture and fails if
that changes. **Re-open registration if any of these become true:**

- matching stops being roster-constrained (an open 1:N search over the
  profile database);
- the roster stops being consent-derived, so speakers can be matched
  without a recorded lawful basis;
- the subsystem is used to profile speakers rather than resolve a
  diarisation label to a name;
- the app gains a deployment context in Annex III terms (employment,
  law enforcement, access control, education).

Deadline if it ever applies: the Annex III obligations bind from
**2 December 2027**.

### 7.4 C2PA for MP3

Carried over from PLAN §13.3g. Re-verified 2026-08-01: MP3 is an **input**
format only — the app decodes it for transcription and there is no MP3
export path, so there is no unmarked MP3 output to worry about. The
ID3v2 `AI_GENERATED` helper exists and `CrispasrC2pa.sign` already
accepts `audio/mpeg`, so the pieces are in place.

If MP3 export is ever added, that is also the point to revisit
**fail-closed** marking: unlike WAV, a container that cannot carry a
manifest leaves the watermark as the only mark, which is precisely the
case CrispASR's watermark floor exists for (PLAN §15.8).

## 8. Applicable Dates

| Provision | Applies from | Relevance |
|---|---|---|
| Art. 5 prohibited practices | 2 Feb 2025 | In force; none performed (§4) |
| Art. 4 AI literacy | 2 Feb 2025 | In force (§6) |
| **Art. 50 transparency** | **2 Aug 2026** | **In force.** Explicitly excluded from the Digital Omnibus deferral |
| Art. 50(2) marking — systems already on market | 2 Dec 2026 | Grace period; v0.9.5 qualifies, but the marking is already implemented |
| Annex III high-risk obligations | 2 Dec 2027 | Deferred by the Digital Omnibus from the original 2 Aug 2026 |

## 9. Document History

| Date | Change |
|---|---|
| 2026-07-16 | Initial risk classification document |
| 2026-08-01 | Audit revision. Reframed speaker ID as biometric **verification** under the closed-roster API (§3.1) with Art. 6(3) demoted to a fallback argument and its registration/profiling caveats stated (§3.2). Added Art. 2(12) open-source scope note (§3a), provider/deployer split (§5.1), Art. 4 (§6), open items (§7), and post-Digital-Omnibus dates (§8). |
