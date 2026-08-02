# EU AI Act Risk Classification — CrisperWeaver

**Date:** 2026-08-01 (revised; originally 2026-07-16)
**Regulation:** Regulation (EU) 2024/1689 (EU AI Act)
**Application:** CrisperWeaver v0.9.6+

---

## 1. System Overview

CrisperWeaver is a cross-platform application for on-device audio
transcription, speech synthesis, speaker identification, document
analysis, LLM-backed text processing, and semantic search.

**Data flow, stated precisely.** Every AI subsystem runs locally on the
user's device by default, and the app has no backend of its own. Two
features are exceptions once the user enables them, and both are off
until they do:

- **Cloud transcription** (§2.1) — audio to a CrispASR HuggingFace Space.
- **Cloud text processing** (§2.7) — transcript text to a user-configured
  OpenAI-compatible endpoint.

Earlier revisions of this document asserted flatly that "no data is
transmitted to external servers". That was inaccurate for those two paths
and is corrected here; the app's first-use notice and `PRIVACY.md` §3.3
have been corrected to match. Biometric data — speaker embeddings, voice
profiles — is transmitted under **no** configuration.

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

### 2.7 Text Generation (LLM) — translation, summarisation, cleanup

| Property | Value |
|---|---|
| Function | Translates text, summarises transcripts into action items / topics / decisions, and cleans up transcripts. Runs against an on-device GGUF model, or — opt-in and off by default — a user-configured OpenAI-compatible endpoint |
| Annex III category | Not listed |
| Art. 50(2) applicability | **Yes for translation and summarisation** — these generate or substantially restate content |
| Risk level | **Not high-risk; subject to Art. 50(2) transparency** |
| Mitigations | Disclosure attached on screen and on copy/export; `x-content-ai-generated` header plus a `_disclosure` field on the HTTP translation endpoint |

Three points this subsystem raises that the others do not:

- **It is the only subsystem whose data can leave the device.** The cloud
  mode sends transcript text — which routinely contains personal data
  about people other than the user — to a third party the user chooses.
  The app cannot make privacy commitments on that provider's behalf and
  does not try to; it discloses the flow (`PRIVACY.md` §3.3, first-use
  notice) and defaults to the local model.
- **Cleanup is deliberately excluded from the marking duty, and the
  exclusion is enforced in the prompt rather than merely asserted.**
  Art. 50(2) carves out systems performing "an assistive function for
  standard editing" that do not substantially alter the input data or its
  semantics. The deterministic pass — filler removal, sentence casing,
  punctuation repair, whitespace normalisation — is plainly within that.
  The optional LLM pass is held to the same standard by its system prompt
  (`cloud_llm_cleanup_service.dart`), which instructs the model to
  *"preserve the speaker's words, meaning, and language"*, to *"never
  paraphrase, expand, or summarise"* and to *"never add information not
  present in the input"*. Should that prompt ever be loosened toward
  rewriting, the carve-out stops applying and the output needs marking —
  so the prompt is a compliance boundary, not a quality setting. LLM
  summarisation and translation are outside the carve-out and are marked.
- **Text has no container.** Audio carries three independent marks
  (watermark, C2PA manifest, container metadata); text can carry only the
  disclosure itself, which a recipient can trivially delete. That is a
  limitation of the medium rather than of the implementation, and is why
  the disclosure is attached at every point where text leaves the app
  rather than only where it is displayed.

### 2.8 Emotion Recognition — **removed** (2026-08-02)

| Property | Value |
|---|---|
| Function | **None.** The app performs no emotion recognition |
| Annex III category | Would have been **1(c)**; not engaged, because the feature no longer exists |
| Art. 50(3) applicability | **No** — nothing to disclose |
| Risk level | **Out of scope** |
| Enforcement | `EmotionInference.isEmotionTag` in `lib/utils/emotion_inference.dart` is a discard list; `CrispasrEngine` drops every listed tag at the parse boundary, before it can reach segment metadata, the UI, or an export, and the CLI drops it on every output format. Pinned by `test/synthetic_compliance_test.dart` |

**What was there, and why it went.** SenseVoice backends emit inline
`<\|HAPPY\|>` / `<\|SAD\|>` / `<\|ANGRY\|>` / `<\|SURPRISED\|>` /
`<\|FEARFUL\|>` / `<\|DISGUSTED\|>` / `<\|NEUTRAL\|>` tags alongside the
transcript. The engine parsed them into `metadata['emotion']` and the
transcript widget rendered a per-segment badge. That is inferring the
emotional state of a natural person from biometric data — an emotion
recognition system under Art. 3(39), listed at Annex III **1(c)**.

**This subsystem was undeclared until the audit of 2026-08-02.** §3.3 of
this document read "No emotion recognition and no biometric categorisation
is performed" and concluded Art. 50(3) was not engaged. That was true of
the Chatterbox `[angry]` / `[whispering]` tags on the *generation* side —
which is all the earlier analysis looked at — and false of the SenseVoice
*recognition* side, which had been shipping since the backend was
catalogued. The error is recorded rather than quietly corrected because
two previous audits both re-read §3.3 and both missed it: the claim was
being checked against the synthesis screen and never against the ASR
engine.

**Why removal rather than compliance.** Art. 50(3) transparency was the
cheap part and was in fact implemented first. The expensive part is
Annex III 1(c), which has no verification-style carve-out to fall outside
of: from 2 Dec 2027 it brings risk management, logging, human oversight and
conformity assessment, plus Art. 49(2) EU-database registration if the
Art. 6(3) derogation were relied on — and the derogation argument was weak
here, because the app parsed the tags deliberately, classified them with a
dedicated helper, and rendered a labelled badge, which reads as intent.

Set against that: the badge was display-only. It never reached an export, a
share payload, or a history record. Art. 5(1)(f) compounded the imbalance —
inferring emotions in workplaces and schools is prohibited outright, the
app cannot detect deployment context, and a policy line was the only
control available for a feature that shipped enabled.

A permanent high-risk obligation for a per-segment badge that nothing
persisted was not a trade worth making, so the feature was deleted.

**What is *not* removed.** SenseVoice remains a fully supported
transcription backend. Its acoustic *event* tags (`SPEECH`, `BGM`,
`LAUGHTER`, `APPLAUSE`, …) are still parsed and badged: classifying
laughter as an audio event describes the recording, not the speaker's inner
state, and is not an inference about a natural person.

**Re-opens if** any model's output is surfaced as an emotional, affective,
or intent-bearing attribute of a speaker — including via a new backend, a
plugin, or an LLM prompt that asks for tone or mood. The discard list is
the control, and it only works for tags it names.

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

No biometric **categorisation** is performed: nothing infers or assigns
sensitive attributes — race, political opinion, trade-union membership,
religion, sex life, sexual orientation — from anyone's biometric data.
Art. 5(1)(g) is not engaged.

**No emotion recognition is performed either** — but that claim now holds
for a different reason than earlier revisions of this section supposed, and
the difference matters if anyone re-derives it.

Those revisions rested the claim on the Chatterbox `[angry]` /
`[whispering]` tags being generation-side prosody controls. That much
remains true: they steer TTS output and infer nothing about any person. But
it was never the whole picture — the SenseVoice ASR backends were running
emotion inference on the recognition side, and the claim was false in
practice from the day that backend was catalogued until 2026-08-02, when
the feature was removed (§2.8). It is true today because the capability was
deleted, not because it never existed.

The distinction to keep hold of is **direction**. A tag that *tells the
model how to sound* is a rendering instruction. A tag that *reports how the
speaker sounded* is an inference about a natural person. Only the second is
Art. 3(39). Any future audit of this section should check the ASR side as
well as the synthesis side — checking only the latter is precisely how this
was missed twice.

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
- (f) No emotion inference in workplace or educational contexts — the app
  performs no emotion inference in **any** context since the capability was
  removed on 2026-08-02 (§2.8). Between the SenseVoice backend being
  catalogued and that date, the app could be pointed at this limb, and
  nothing but the acceptable-use policy stood in the way; removal is what
  makes this an absence rather than a restriction
- (g) No biometric categorisation for sensitive attributes (§3.3)
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
| 50(3) emotion recognition / biometric categorisation notice | **Deployer** | n/a — emotion recognition removed (§2.8), no biometric categorisation (§3.3) |
| 50(4) deep fake + public-interest text disclosure | **Deployer** | **the end user**, not CrisperWeaver |

CrisperWeaver cannot discharge a deployer's Art. 50(4) duty. What it
does is make compliance the default and non-compliance deliberate: the
beep disclaimer is applied automatically to every cloned and
voice-converted output, and suppressing it requires a written
attestation that is logged for audit.

### 5.2 Implementation status

| Obligation | Implementation | Status |
|---|---|---|
| Art. 50(1): Users informed of AI interaction | First-use transparency dialog (EN/DE/ZH), enumerating every AI subsystem and which of them can use the network once enabled | Done |
| Art. 50(2): Machine-readable AI marking — audio | Spread-spectrum watermark, verified post-embed by probing the PCM; C2PA COSE/X.509 manifest; WAV LIST/INFO + ID3v2 tags | Done |
| Art. 50(2): Machine-readable AI marking — text | Transcript exports carry a synthetic-content disclosure by default; OCR, LLM summaries and translations carry one on screen and on copy; the HTTP translation endpoint sets `x-content-ai-generated` and a `_disclosure` field | Done |
| Art. 50(4): Deep fake disclosure — voice cloning | Mandatory beep disclaimer; suppression requires a logged attestation. Applies on the GUI, server (`/v1/audio/speech`) and CLI (`synthesize --voice`) paths | Done |
| Art. 50(4): Deep fake disclosure — speech-to-speech | Same beep path via `voiceConverted` / `_writeMarkedWav(deepfake: true)`; `/v1/audio/s2s` consent-gated; CLI `s2s` marked | Done |
| Art. 50(3): Emotion recognition notice | Not applicable — the capability was removed rather than disclosed (§2.8). Emotion tags are discarded at the engine's parse boundary and on every CLI output format | n/a |
| Art. 50(2): Marking survives editing | Trim / cut / split carry the source C2PA manifest into the derived file as a `c2pa.edited` action and re-emit the LIST/INFO tags, instead of re-encoding a bare 44-byte WAV; MP3 re-encode carries ID3v2 provenance, and containers that cannot carry a manifest are logged as watermark-only | Done |

**Scope note — every generating path, not just the GUI.** The audit of
2026-08-02 found the marking pipeline was implemented on the Flutter side
only: `bin/crisperweaver.dart` wrote bare 44-byte WAVs from both
`synthesize` and `s2s`, so headless output carried no beep, no manifest,
no provenance chunk and no watermark verification. The WAV encoder now
lives in `lib/utils/marked_wav.dart` and is shared by the app and the CLI
so the two cannot drift apart again.

The audit of 2026-08-02 found the same shape of gap twice more, in
directions the first pass did not look: the CLI was inside the *audio*
marking scope but still wrote machine-translated *text* to stdout bare
(fixed — `translate` and `transcribe --translate` now attach the shared
`AiTextDisclosure`, with `--no-disclosure` as the explicit opt-out), and
`AudioEditService` decoded to PCM and re-encoded a bare 44-byte WAV, so
trimming a generated clip stripped the manifest and the LIST/INFO tags the
app had itself written (fixed — provenance is carried across the edit). In
both cases the watermark survived and the *machine-readable* mark did not,
which is precisely the layer that container metadata is supposed to supply.

### 5.3 Art. 50(5) — clarity and accessibility

Art. 50(5) requires the information owed under 50(1)–(4) to be given "in a
clear and distinguishable manner at the latest at the time of the first
interaction or exposure", and to "conform to the applicable accessibility
requirements". Earlier revisions of this document did not address the
second clause at all.

| Disclosure | Timing | Accessibility |
|---|---|---|
| 50(1) first-use notice | Blocking dialog on first launch, before any use | Native `AlertDialog` — traversable and readable by the platform screen reader; scrollable so it is not truncated on small displays |
| 50(4) beep disclaimer | Prepended to the audio | Audible only — **deliberately redundant** with the C2PA manifest and container tags, which are the channel available to a deaf recipient or an automated checker |
| 50(2) text disclosure | Prefixed to the text itself | Plain text, so it inherits whatever the reading tool provides |

The one place the mark is single-channel is a container that can carry
neither manifest nor tags, where the spread-spectrum watermark stands alone
(§7.4). That is a machine-readable channel with no human-readable or
accessible counterpart, and it is logged as such at the point it happens
rather than assumed adequate.

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
| Code of Practice on Transparency of AI-generated Content | **Closed — decided not to sign** (2026-08-02). Technically conformant on every limb; adherence declined while the generating surface is still moving. Reasoning and re-open triggers in §7.2 |
| Art. 49(2) EU-database registration — speaker ID | **Not applicable** on the operative analysis — see §7.3 |
| Annex III 1(c) — emotion recognition | **Closed — capability removed** (2026-08-02); see §2.8 |
| C2PA signing for MP3 exports | **Done** — ID3v2 provenance on the MP3 path; AAC/Opus are watermark-only and warn. §7.4's "no MP3 export exists" was incorrect |
| Art. 53 GPAI obligations for republished GGUFs | **Assessed** — mostly exempt, one limb to watch; see §7.5 |

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

Note the benefit precisely: signatories can *demonstrate* compliance and
have enforcement focused on monitoring adherence rather than individual
assessment by each national market surveillance authority. This is **not**
an Art. 40 "presumption of conformity" — that concept attaches to
harmonised standards, not codes of practice.

**Decision (2026-08-02): not signing, for now.** This is a judgement call
rather than a technical gap, and the reasoning is recorded here so it can
be revisited on its merits rather than re-argued from scratch.

Adherence is an **ongoing** commitment to the Code's measures across
whatever the software becomes, not a one-time attestation about the
version that exists today. CrisperWeaver is under active development and
its surface keeps moving — the last two audits alone added an LLM text
subsystem to the marking scope, brought the CLI inside it, and closed two
consent gates on paths that did not exist a few releases earlier.
Committing a moving target to a fixed set of measures invites a worse
position than never signing: diverging after signing reads as breaking a
commitment, whereas a non-signatory is simply assessed on the merits.

The benefit accrues mainly to providers who expect to be assessed by
national market surveillance authorities — a posture that does not fit an
AGPL project with no accounts, no servers, and no commercial deployment.

What this costs is small and stated plainly: no ability to *demonstrate*
compliance by reference to the Code, so the technical measures have to
stand on their own. They do — every limb in the table above is met, and
the robustness limb is arguably exceeded. **Art. 50 is binding either way
and is met either way**; the Code is a route to showing that, not a
source of the obligation.

**Revisit if** the project stabilises its generating surface, gains a
commercial or institutional deployment, or is contacted by a market
surveillance authority. Signing remains open at any time (the
initial-signatories list closed 22 July 2026, which affects listing order
and nothing else): complete the Signatory Form and email it to
`CNECT-AIOFFICE-CODE-OF-PRACTICE-TRANSPARENCY@ec.europa.eu`, signed by
someone with authority to bind the provider.

### 7.3 Art. 49(2) registration

Art. 49(2) obliges a provider who considers an **Annex III** system not
high-risk under the Art. 6(3) derogation to register it in the EU
database before placing it on the market.

On the operative analysis (§3.1) the speaker-identification subsystem is
biometric **verification**, which Annex III 1(a) expressly excludes — so
it is not an Annex III system at all, Art. 6(3) is never reached, and
Art. 49(2) does not bite.

**A second Annex III subsystem briefly existed and was removed.** The audit
of 2026-08-02 found emotion recognition (§2.8), listed at Annex III
**1(c)** with no verification-style carve-out to fall outside of. Rather
than argue the Art. 6(3) derogation — which would have required documenting
the assessment before placing on the market *and* registering under
Art. 49(2), since invoking the derogation is not an escape from
registration — the capability was **deleted**. Annex III 1(c) is therefore
not engaged, and no registration question arises from it.

| Subsystem | Annex III | Registration |
|---|---|---|
| Speaker identification | Outside 1(a) — verification (§3.1) | Not applicable |
| Emotion recognition | Removed 2026-08-02 (§2.8) | Not applicable |

The speaker-identification conclusion depends on the closed-roster
architecture and fails if that changes. **Re-open registration for that
subsystem if any of these become true:**

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

### 7.4 C2PA for MP3 and the compressed containers

Carried over from PLAN §13.3g. The 2026-08-01 revision recorded this as
"not applicable — no MP3 export exists". **That was wrong**, and the
2026-08-02 audit corrected it: `AudioEditService.exportEncoded` encodes
MP3, AAC-LC and Opus through the bundled libglint. It has no UI caller, so
nothing in the shipped app can reach it today — but a marking gap that
exists only in unreachable code is a gap waiting for the day someone wires
a button to it, and "no export path exists" was a claim about the codebase
that the codebase did not support.

Now implemented rather than deferred:

- **MP3** carries ID3v2 `AI_GENERATED` provenance via
  `AudioWatermarkService.injectMp3Metadata`, applied when the source
  carried a provenance manifest.
- **AAC / Opus** cannot carry a manifest through this path. The watermark
  in the samples is the only mark that survives, and that is **logged as a
  warning at the point of export** rather than passing silently — the same
  posture as the post-embed watermark verification failure.

The remaining open question is whether the AAC/Opus case should be
**fail-closed** (refuse to export AI-generated audio to a container that
cannot carry the machine-readable mark) rather than mark-and-warn. It is
left as mark-and-warn while the path is UI-unreachable; revisit when it is
wired up, because that is when the watermark floor (PLAN §15.8) starts
carrying real weight on its own.

### 7.5 Art. 53 — GPAI obligations for the republished GGUFs

This concerns the maintainer rather than the app, but it arises from the
same activity and is recorded here so it is not overlooked.

The project converts third-party models to GGUF and publishes them under
`cstr/*` on HuggingFace (`miotts`, `moss-tts-local`, `gigaam`,
`titanet-large`, among others) so the catalogue has something to point at.
Making a model available on the Union market can bring the entity doing so
within the definition of a *provider* of that model, and quantisation plus
format conversion is a modification — so the question is live rather than
obviously inapplicable.

Assessment:

- **Art. 53(2) exempts free and open-source GPAI models** from the
  technical-documentation duties in 53(1)(a) and (b), provided the model is
  released under a licence allowing access, use, modification and
  distribution, with parameters and architecture publicly available. The
  republished GGUFs meet that; the exemption falls away only for models
  with **systemic risk** (Art. 51: ~10²⁵ FLOP training compute), which
  nothing in this catalogue approaches — these are 0.5–2 B parameter
  speech models.
- **What survives the exemption** is 53(1)(c) — a policy to comply with
  Union copyright law — and 53(1)(d) — a sufficiently detailed public
  summary of training content. Both attach to whoever counts as the
  model's provider.
- **The strongest argument is that this project is not that provider.**
  Format conversion changes the numeric representation, not the model:
  no training, no fine-tuning, no change to architecture or capability.
  The upstream research teams remain the providers, and the model cards
  attribute upstream. A quantiser is closer to a distributor than to a
  provider of a new model.

That is an argument rather than a settled reading, so the practical step
is cheap insurance: each republished repo's card should name the upstream
model and licence, state that only quantisation/format conversion was
applied, and point at the upstream training-data documentation. Where the
upstream publishes no such summary, that gap should be visible rather than
papered over. **Re-open this** if the project ever fine-tunes, merges, or
distils a model rather than converting one.

## 8. Applicable Dates

| Provision | Applies from | Relevance |
|---|---|---|
| Art. 5 prohibited practices | 2 Feb 2025 | In force; none performed (§4). The Art. 5(1)(f) exposure closed when emotion recognition was removed (§2.8) |
| Art. 4 AI literacy | 2 Feb 2025 | In force (§6) |
| **Art. 50 transparency** | **2 Aug 2026** | **In force.** Explicitly excluded from the Digital Omnibus deferral |
| Art. 50(2) marking — systems already on market | 2 Dec 2026 | Grace period; v0.9.5 qualifies, but the marking is already implemented |
| Annex III high-risk obligations | 2 Dec 2027 | Deferred by the Digital Omnibus from the original 2 Aug 2026. Not engaged: no Annex III system remains after the removal in §2.8 |

## 9. Document History

| Date | Change |
|---|---|
| 2026-07-16 | Initial risk classification document |
| 2026-08-01 | Audit revision. Reframed speaker ID as biometric **verification** under the closed-roster API (§3.1) with Art. 6(3) demoted to a fallback argument and its registration/profiling caveats stated (§3.2). Added Art. 2(12) open-source scope note (§3a), provider/deployer split (§5.1), Art. 4 (§6), open items (§7), and post-Digital-Omnibus dates (§8). |
| 2026-08-02 | **Third audit.** Found the app performed **emotion recognition** (SenseVoice emotion tags rendered as a per-segment badge) — a subsystem §3.3 had expressly denied across two prior audits, because the claim was checked against the synthesis screen and never against the ASR engine. **The capability was removed** rather than disclosed: Annex III 1(c) would have brought high-risk obligations from 2 Dec 2027 for a badge nothing persisted. Rewrote §2.8 as a removal record with a re-open trigger, corrected §3.3 to explain why the no-emotion-recognition claim is true now for a different reason than before, and closed the Annex III limb of §7.3. Added §5.3 for the previously unaddressed Art. 50(5) accessibility clause. Corrected §7.4, which claimed no MP3 export path existed when `AudioEditService.exportEncoded` has one. Recorded the CLI text-disclosure and edit-strips-provenance gaps as fixed (§5.2). |
| 2026-08-02 | Second audit. Corrected the inaccurate "no data is transmitted" claim in §1 and classified the previously unclassified LLM text subsystem (§2.7) — the only one whose data can leave the device. Recorded that Art. 50(2) text marking now covers LLM summaries and translations, not only OCR, and that the CLI is inside the marking scope (§5.2). Added the GPAI note (§7.5). Closed the Code of Practice item as a decision not to sign, with reasoning and re-open triggers (§7.2). |
