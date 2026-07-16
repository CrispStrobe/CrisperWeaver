# Privacy Policy — CrisperWeaver

**Effective date:** 2026-07-10
**Last updated:** 2026-07-16

CrisperWeaver is an offline-first audio transcription and speech
synthesis app. This policy explains what data the app accesses, how
it is used, and your rights.

---

## 1. Data We Collect

**We do not collect, transmit, or store any personal data on our
servers.** CrisperWeaver is designed to run entirely on your device.

### 1.1 Audio Data

The app records audio through your device's microphone or processes
audio files you provide. All audio data stays on your device and is
never uploaded to any server unless you explicitly choose to use the
optional cloud transcription feature (HuggingFace Space), in which
case audio is sent to the third-party endpoint you configure.

### 1.2 Transcription Data

Transcripts, history entries, speaker profiles, and embeddings are
stored locally on your device in the app's documents directory. They
are never transmitted off-device.

### 1.3 Model Files

When you download speech recognition, text-to-speech, or embedding
models, the app fetches GGUF files from HuggingFace
(huggingface.co). These downloads are standard HTTPS requests. No
personal data is sent — only the model URL is accessed. Downloaded
models are cached locally on your device.

### 1.4 Crash Data and Analytics

CrisperWeaver does **not** include any analytics SDKs, crash
reporters, or tracking libraries. No usage data, device
identifiers, or telemetry is collected.

## 2. Permissions

The app requests the following permissions:

| Permission | Purpose | When |
|---|---|---|
| Microphone | Record audio for transcription | When you tap Record |
| Storage / Files | Save and load audio files, models, transcripts | When you import/export files or download models |
| Internet | Download models from HuggingFace; optional cloud transcription | When you download a model or use cloud ASR |
| Background Audio | Continue recording when the app is backgrounded | When recording with the screen locked |
| Local Network | Flutter debugging (development only) | Debug builds only |

The app does **not** use the camera. The camera permission
declaration in the iOS build is a placeholder inherited from
Flutter's default template and will be removed.

## 3. Third-Party Services

### 3.1 HuggingFace (huggingface.co)

Model downloads are fetched from HuggingFace's CDN. HuggingFace's
own privacy policy applies to their servers. CrisperWeaver sends no
personal data — only standard HTTPS GET requests for model files.

### 3.2 Optional Cloud Transcription

If you enable cloud transcription (Settings > Engine > CrispASR
Cloud), audio is sent to a CrispASR HuggingFace Space for
processing. This is **opt-in** and **off by default**. The default
engine is fully on-device.

## 4. Data Storage and Retention

All data is stored locally on your device:

- **Audio recordings:** in the app's documents directory
- **Transcripts and history:** JSON files in the app's documents
  directory
- **Downloaded models:** in the app's models directory
- **Settings:** via platform-standard preferences (NSUserDefaults
  on iOS, SharedPreferences on Android)

You can delete all data at any time by:
- Deleting individual transcripts from the History screen
- Deleting models from the Models screen
- Uninstalling the app (removes all app data)

## 5. Biometric Data (GDPR Art. 9 / EU AI Act)

CrisperWeaver's speaker identification feature processes **biometric
data** in the form of voice embeddings (TitaNet neural speaker
representations).

### 5.1 What We Process

When you enroll a speaker, the app extracts a fixed-length voice
embedding vector from the reference audio. This embedding is
biometric data under GDPR Art. 9 because it uniquely identifies a
natural person by their voice characteristics.

### 5.2 Legal Basis

Processing is based on **explicit consent** (GDPR Art. 9(2)(a)). The
app displays a consent dialog before any biometric processing that
explains:

- Voice embeddings are biometric data under GDPR Art. 9
- Data is stored on-device only and never transmitted
- You can delete your data at any time (GDPR Art. 17 right to
  erasure)

A consent record (`.consent.json`) is saved alongside each speaker
profile, documenting: speaker name, consent timestamp, purpose,
lawful basis, and storage location.

### 5.3 Storage and Security

- Voice embeddings (`.spk` files) are stored **exclusively on your
  device** in the app's documents directory.
- No biometric data is transmitted to any server, cloud service,
  or third party.
- No remote biometric identification is performed.
- No real-time biometric identification in publicly accessible
  spaces is performed (EU AI Act Art. 5 compliance).

### 5.4 Your Rights

- **Right to erasure (Art. 17):** Delete any speaker profile and its
  consent record from the Speaker Management screen. Both the
  embedding file and the consent record are permanently deleted.
- **Right to data portability (Art. 20):** Export all stored data for
  any speaker via the export function.
- **Right to withdraw consent:** Delete the speaker profile at any
  time. Processing ceases immediately.

### 5.5 Voice Cloning

Voice cloning (TTS with a reference voice) generates synthetic audio
that replicates a voice's characteristics. Under EU AI Act Art. 50(4),
synthetic audio that resembles a specific person's voice must be
disclosed as AI-generated. CrisperWeaver:

- Automatically watermarks all synthesized audio (spread-spectrum +
  C2PA signed provenance metadata)
- Prepends an audible beep disclaimer to voice-cloned output
- Requires explicit attestation that the user has rights to clone
  the voice before proceeding
- Logs all voice-cloning consent attestations for audit

## 6. Children's Privacy

CrisperWeaver is not directed at children under 13. We do not
knowingly collect data from children.

## 7. Your Rights

Since all data stays on your device, you have full control:

- **Access:** All your data is visible in the app (History, Models)
- **Deletion:** Delete any transcript, model, or recording at any
  time
- **Portability:** Export transcripts as TXT, SRT, VTT, or JSON
- **No account required:** The app does not require registration or
  login

## 8. Changes to This Policy

We may update this policy when new features are added. The
"Last updated" date at the top reflects the most recent revision.

## 9. Contact

For questions about this privacy policy:

- GitHub Issues:
  [CrispStrobe/CrisperWeaver](https://github.com/CrispStrobe/CrisperWeaver/issues)
- Email: See the repository's profile page

---

**Summary:** CrisperWeaver processes everything locally on your
device. No data is collected, no analytics are used, no accounts are
required. The only network traffic is model downloads from
HuggingFace (your choice) and optional cloud transcription (opt-in,
off by default).
