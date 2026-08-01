---
name: Abuse report — synthetic audio misuse
about: Report audio you believe was generated with CrisperWeaver and used to impersonate someone
title: "[abuse] "
labels: abuse-report
---

<!--
This template is linked from the C2PA manifest embedded in every audio
file CrisperWeaver generates, so you may have arrived here from a file
rather than from the repository.

Read this first — it sets expectations honestly:

CrisperWeaver is offline, open-source software. It has no accounts, no
servers and no telemetry. That means the project CANNOT identify who
generated a file, disable anyone's copy, or take content down. There is
no kill switch to pull.

What the project CAN do: confirm whether a file carries a CrisperWeaver
watermark and provenance manifest, help you interpret what it shows, and
harden the safeguards so the same misuse is harder next time.

If you are suffering harm right now, do not wait on this issue:
  - contact your local law enforcement;
  - in the EU, your national data protection authority (voice recordings
    are biometric personal data under GDPR Art. 9);
  - if the audio is hosted somewhere, use that platform's reporting flow.
A watermark verification can support any of those reports.

Do NOT paste sensitive personal information into this public issue.
Describe what happened; share files privately if asked.
-->

### What happened

<!-- What was the audio used for? Impersonation, fraud, harassment, something else? -->

### How did the audio reach you

<!-- Messaging app, social platform, email, phone call, ... -->

### Have you verified the watermark

<!--
Optional but very useful. In CrisperWeaver: Transcribe screen →
"Verify Watermark", with the file loaded. It reports whether the audio
carries a CrisperWeaver spread-spectrum watermark and whether the C2PA
manifest is COSE-signed or unsigned.

Paste the result here if you have it. Note that a NEGATIVE result does
not prove the audio is authentic — container metadata is stripped by
re-encoding, and very short or silent audio cannot carry a watermark.
-->

- [ ] Verified — watermark found
- [ ] Verified — no watermark found
- [ ] Not verified

### Anything else

<!-- Timeline, whether the impersonated person consented, prior reports. -->
