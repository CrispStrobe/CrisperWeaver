# Store Listing Metadata — CrisperWeaver

Use this file to fill in Google Play Console and App Store Connect
fields. All text is pre-formatted to fit character limits.

---

## App Name
**CrisperWeaver** (14 chars — fits 30-char limit on both stores)

## Short Description (80 chars — Google Play)
Offline speech-to-text & text-to-speech. 40+ ASR models, no cloud required.

## Subtitle (30 chars — App Store)
Offline Transcription & TTS

## Promotional Text (170 chars — App Store, editable without review)
Transcribe audio to text on your own device. 40+ speech recognition models,
20+ text-to-speech voices, real-time streaming, word timestamps, and more.

## Full Description (4000 chars — both stores)

CrisperWeaver is an offline-first audio transcription and speech synthesis
app. Transcription and synthesis run on your device — no accounts, no
analytics, no tracking. Models are downloaded once from HuggingFace, and
two optional features use the network only if you switch them on (see
PRIVACY below).

SPEECH RECOGNITION
- 40+ ASR model families: Whisper, Parakeet, Canary, Qwen3-ASR, Voxtral,
  Granite Speech, FastConformer, Wav2Vec2, SenseVoice, Moonshine, and more
- Word-level timestamps with CTC forced alignment
- Voice activity detection (Silero, FireRed, MarbleNet)
- Speaker diarization (energy, cross-correlation, Pyannote)
- Language detection (99+ languages via Whisper, CLD3, GlotLID)
- Punctuation restoration (FireRedPunc)
- Real-time streaming transcription
- Batch processing with watch-folder automation

TEXT-TO-SPEECH
- 20+ TTS engines: Kokoro, VibeVoice, Qwen3-TTS, Orpheus, Chatterbox,
  DOTS-TTS, CSM, and more
- Voice cloning from a single audio sample
- Emotion control tags for Chatterbox ([laugh], [whispering], [angry])
- Speed, temperature, and sampling controls

SEARCH & ORGANIZATION
- Semantic transcript search with embedding models
- Cross-encoder reranker for precision search
- Cross-modal audio+text search (BidirLM-Omni)
- Full transcript history with export (TXT, SRT, VTT, JSON)
- Meeting summarization via local or cloud LLMs
- Transcript cleanup and tidying

DOCUMENT PROCESSING
- Math formula OCR (pix2tex, HMER, BTTR, PosFormer)
- Document OCR (Granite Vision, DeepSeek-OCR2)
- Scan preprocessing (deskew, crop, whitening, denoising)

INTEGRATION
- OpenAI-compatible HTTP server (local network)
- Wyoming protocol server for Home Assistant
- Command-line interface (dart run)

PRIVACY
- Transcription, synthesis, speaker profiles and voice embeddings stay
  on your device
- No analytics, no tracking, no accounts, no ads
- Models are downloaded once from HuggingFace and cached locally
- Two optional features send data off-device, and only once you turn them
  on. Cloud transcription sends audio to a HuggingFace Space. Cloud
  cleanup and summarisation send transcript text to an endpoint you
  configure yourself, under that provider's privacy policy. Both are
  off by default; speaker profiles, voice embeddings and audio are never
  sent to a cloud language model
- Open source (GitHub: CrispStrobe/CrisperWeaver)

Available on macOS, Linux, Windows, Android, iOS, and Web.

## Keywords (100 chars — App Store)
transcription,speech-to-text,offline,whisper,tts,voice,audio,dictation,ASR,captions

## Category
- **Google Play:** Tools (or Productivity)
- **App Store:** Productivity (LSApplicationCategoryType already set)

## Content Rating
- **Violence:** None
- **Sexual content:** None
- **Language:** None
- **Controlled substance:** None
- **User-generated content:** No (all content is user's own audio)
- **In-app purchases:** None
- **Ads:** None
- **Account creation:** Not required

**Recommended rating:** Everyone / 4+ (iOS)

## App Privacy questionnaire (App Store Connect) / Data safety (Play)

Answer these from the PRIVACY section above, not from "it's an offline
app". The developer collects nothing, but two opt-in features transmit
data to third parties, and both consoles ask about transmission rather
than about who ends up holding it.

- **Data collected by the developer:** None. There is no backend, no
  account system and no analytics SDK.
- **Data transmitted off-device:** Only via the two opt-in features.
  Cloud transcription transmits **audio** to a HuggingFace Space; cloud
  cleanup/summarisation transmits **transcript text** to a user-supplied
  endpoint. Neither is enabled by default, and neither routes through
  infrastructure this project operates.
- **Tracking:** None. `NSPrivacyTracking` is false and there are no
  tracking domains.
- **Third-party SDKs:** None that collect data. Model downloads are
  plain HTTPS GETs to HuggingFace with no personal data attached.

If either opt-in feature is ever made reachable by default, both console
answers and the PRIVACY section have to be revisited in the same change.

## Screenshots Required

### Google Play (min 2, max 8 per device type)
- Phone: 1080x1920 or 1440x2560
- 7" tablet: 1200x1920
- 10" tablet: 1600x2560

### App Store (required per device)
- iPhone 6.7" (1290x2796) — iPhone 15 Pro Max
- iPhone 6.5" (1284x2778) — iPhone 14 Pro Max
- iPhone 5.5" (1242x2208) — iPhone 8 Plus
- iPad Pro 12.9" (2048x2732)

### Suggested screenshot content
1. Main transcription screen with audio waveform
2. Transcript output with word timestamps highlighted
3. Model management screen showing available models
4. Synthesize screen with TTS controls
5. History screen with search results
6. Settings screen showing engine options

## What's New (release notes for store update)
- Semantic search with cross-encoder reranking
- Chatterbox emotion tags ([laugh], [whispering], [angry])
- Math formula & document OCR
- Wyoming server for Home Assistant
- Streaming partial results during transcription
- 369 models in catalog from 120 HuggingFace repos

## Support URL
https://github.com/CrispStrobe/CrisperWeaver/issues

## Privacy Policy URL
https://github.com/CrispStrobe/CrisperWeaver/blob/main/PRIVACY.md
