# CrisperWeaver — Acceptable Use Policy

**Version 1.0 · 2026-08-01 · applies to CrisperWeaver v0.9.6+**

CrisperWeaver runs entirely on your device. Nothing you transcribe or
synthesise is sent to us, and there is no account, no telemetry and no
server-side moderation. That design is deliberate — it is also why this
policy matters. Because we cannot see what you generate, **you** are the
only safeguard against misuse, and under the EU AI Act you are the
*deployer* of the AI systems in this app. The legal duties that attach to
deploying them are yours, not ours.

This policy states what the software may be used for. It is not a
substitute for the law where you are.

---

## 1. Voice cloning and voice conversion

CrisperWeaver can synthesise speech in a specific person's voice, from a
short reference recording, and can convert one voice into another.

**You may clone a voice when:**

- it is your own voice; or
- you have the explicit, informed and current consent of the person whose
  voice it is, for the specific use you intend; or
- the voice is wholly synthetic and does not appreciably resemble any
  real person.

**You may not:**

- clone or convert any person's voice without their explicit consent —
  including public figures, politicians, journalists, celebrities and
  the deceased, whose fame is not consent;
- represent synthetic speech as an authentic recording of a real person;
- use synthetic speech to impersonate someone in order to obtain money,
  credentials, personal data or authorisation — this includes "family
  emergency" and CEO-fraud scams, and voice-authentication bypass;
- generate speech placing real, identifiable people in contexts they did
  not consent to, including sexual, degrading, criminal or extremist
  contexts;
- remove, suppress, corrupt or obscure the disclosures described in §3;
- generate synthetic speech of a minor's voice, except your own child's
  where you hold parental responsibility and the use is private.

**Consent must be real.** It must be specific to the use, freely given,
and revocable. Consent to be recorded is not consent to be cloned.
Consent for one project is not consent for another. If the person cannot
meaningfully refuse — an employee, a child, someone dependent on you —
treat consent as absent.

## 2. Speaker identification

CrisperWeaver can match voices in a recording against speaker profiles
you enrol. Voice embeddings are **biometric data** under GDPR Art. 9.

**You may not** enrol a person without their explicit consent, use
speaker identification for surveillance, covert monitoring, workplace or
educational monitoring, or to identify people in recordings they did not
know were being made. Where recording itself requires consent — most of
the EU, including all-party-consent jurisdictions — obtain it first.

The app enforces what it can: enrolment is gated on an explicit consent
attestation, and only speakers with a stored consent record are ever
matched. Erasing that record removes them from matching immediately.
Those are technical guardrails, not a legal opinion about your situation.

## 3. Disclosure obligations (EU AI Act Art. 50)

If you are in the EU, or your audience is, Art. 50 applies to you as the
deployer **from 2 August 2026**.

CrisperWeaver makes compliance the default:

| Measure | Applied to |
|---|---|
| Spread-spectrum watermark, verified after embedding | all synthesised audio |
| C2PA provenance manifest (COSE-signed where available) | all synthesised audio |
| WAV `LIST`/`INFO` and ID3v2 `AI_GENERATED` tags | all synthesised audio |
| Audible beep disclaimer | cloned and voice-converted output |

Suppressing the beep requires a written attestation that is recorded in
the log. That mechanism exists so an informed, documented decision is
possible — for example, output that will carry its own visible label in
a finished production. **It is not a way to make an undisclosed deepfake
compliant.** Using it to avoid disclosure violates both this policy and,
in the EU, Art. 50(4).

Note the limits, so you do not over-rely on the automation:

- Container marking (C2PA, ID3, `LIST`/`INFO`) is **stripped by
  re-encoding**. Convert the WAV to MP3 with an ordinary tool and it is
  gone. The watermark survives; the metadata does not.
- Audio shorter than about 100 ms, and digitally silent audio, **cannot
  carry the watermark at all** — there is no spectrum to modulate. The
  app tells you when this happens rather than claiming a mark it did not
  make. Such output is marked only by the strippable container metadata.

Where the automated marking is insufficient for your use, disclose
explicitly and in a way your audience will actually perceive.

## 4. Transcription and other outputs

Transcripts, translations, OCR and music-recognition output are
AI-generated and imperfect. Do not present them as verbatim records
without checking them, and do not rely on them for decisions with legal,
medical, financial or safety consequences without human review. Exports
carry a synthetic-content notice by default; leave it in place when the
output leaves your hands.

## 5. Prohibited regardless of consent

No consent makes these acceptable: child sexual abuse material; content
promoting terrorism or mass violence; targeted harassment; disinformation
designed to interfere with an election or a public-health response;
evading sanctions or export controls; or any use prohibited under EU AI
Act Art. 5 — notably emotion inference in workplaces or schools, social
scoring, and real-time remote biometric identification in public spaces.

## 6. Reporting misuse

**If you have received audio you believe was generated with
CrisperWeaver and used to impersonate you or someone else:**

→ **https://github.com/CrispStrobe/CrisperWeaver/issues/new?labels=abuse-report**

This reporting address is embedded in the C2PA manifest of every file the
app generates, so it travels with the audio.

Please include the file if you can share it, and how it reached you. The
`Verify Watermark` button in the app checks any WAV for a CrisperWeaver
watermark and provenance manifest — useful for establishing whether a
clip is synthetic.

**What we can and cannot do.** We can confirm whether a file carries our
watermark and manifest, help you interpret them, and fix weaknesses in
the marking. We **cannot** identify who generated a file, disable
anyone's installation, or remove content — the app is offline,
open-source software with no account system and no kill switch. For
impersonation causing harm, contact your local law enforcement and, for
personal-data misuse in the EU, your national data protection authority;
a watermark verification can support such a report.

For a security vulnerability in the app itself, see `SECURITY.md` if
present, or open a normal issue.

## 7. Enforcement and licence

CrisperWeaver is AGPL-3.0. This policy does not add restrictions to that
licence, and it does not — and legally cannot — condition your software
freedoms on it. Being free and open-source also does **not** exempt the
software from EU AI Act Art. 50 (Art. 2(12) expressly carves transparency
out of the open-source exemption).

What this policy does is state the terms under which the project supports
use of the software, and put you on notice of duties that are yours as a
deployer. Reports of misuse inform how the project hardens its
safeguards — which is the enforcement mechanism genuinely available to
offline software.

## 8. Changes

Material changes will be noted here with a version bump and recorded in
`PLAN.md`. Current version: **1.0 (2026-08-01)**.

---

**Related:** [`PRIVACY.md`](PRIVACY.md) ·
[`docs/AI_ACT_RISK.md`](docs/AI_ACT_RISK.md) ·
[`docs/DPIA.md`](docs/DPIA.md) ·
[`docs/AI_ACT_TECHNICAL.md`](docs/AI_ACT_TECHNICAL.md)
