# TTS Backend Audio Verification Checklist

Structured test plan for all TTS backends added in v0.7.x. Each row
is a manual smoke test: download the model, synthesise the test text,
verify the output plays and sounds correct.

**Status legend**: pass / fail / untested / skip (no GGUF published)

## Test setup

1. Build CrisperWeaver with `scripts/build_linux.sh release`
2. Launch the app
3. For each row: download via Model Management, switch to Synthesize screen

## Previously verified (pre-v0.7.0)

| Backend | Model | Status | Notes |
|---------|-------|--------|-------|
| kokoro | kokoro-82m-q8_0 | pass | Multilingual, voice-pack required |
| vibevoice-tts | vibevoice-realtime-0.5b-tts-f16 | pass | Needs voicepack |
| qwen3-tts | qwen3-tts-12hz-0.6b-base-q8_0 | pass | Needs codec + voice/speaker |
| orpheus | orpheus-3b-base-q8_0 | pass | Needs SNAC codec |
| chatterbox | chatterbox-en-q8_0 | pass | Needs S3Gen companion |
| indextts | indextts-q8_0 | pass | Needs BigVGAN companion |
| voxcpm2-tts | voxcpm2-q4_k | pass | Zero-shot, no companion |
| f5-tts | f5-tts-v1-base-f16 | pass | Verified in v0.6.49 |
| cosyvoice3-tts | cosyvoice3-llm-q4_k | pass | Needs flow+hift+voices+s3tok+campplus |
| piper | piper-en-cori | pass | Single-file voice |

## New backends (v0.7.x) — to verify

### Bark

| Field | Value |
|-------|-------|
| Model | `bark-small-q8_0.gguf` (~500 MB) |
| Companion | none |
| Test text (EN) | `Hello, this is a test of the Bark text to speech system.` |
| Test text (DE) | `Hallo, das ist ein Test des Bark Sprachsynthesesystems.` |
| Expected | Intelligible speech, ~5-10 s. Try `--voice v2/de_speaker_0` for German. |
| Backend quirks | 3-stage GPT-2 (semantic + coarse + fine). Slow. Temperature 0.7 recommended. |
| Status | untested |

### CSM (Sesame)

| Field | Value |
|-------|-------|
| Model | `csm-1b-q4_k.gguf` (~1.4 GB) |
| Companion | none |
| Test text | `Hey there, how's it going? I've been thinking about what to say.` |
| Expected | Conversational English, single built-in voice. Natural prosody. |
| Backend quirks | Single voice, no voice selection. Llama-3.2 backbone. |
| Status | untested |

### Dia

| Field | Value |
|-------|-------|
| Model | `dia-1.6b-f16.gguf` (~3.0 GB) |
| Companion | `dac-44khz.gguf` (shared with Zonos) |
| Test text | `[S1] Good morning, how are you today? [S2] I'm doing great, thanks for asking! [S1] That's wonderful to hear.` |
| Expected | Two distinct speakers in dialogue. 44.1 kHz output. Use 100+ chars for best results. |
| Backend quirks | Requires [S1]/[S2] tags. UI shows hint when Dia is active. F16 only (Q4_K loops). |
| Status | untested |

### FastPitch

| Field | Value |
|-------|-------|
| Model | `fastpitch-en-q8_0.gguf` (~120 MB) |
| Companion | none |
| Test text | `The quick brown fox jumps over the lazy dog.` |
| Expected | Clean, deterministic English speech. Same input always produces identical output. 22 kHz. |
| Backend quirks | Non-autoregressive, no sampling controls. Single speaker. Very fast. |
| Status | untested |

### MeloTTS

| Field | Value |
|-------|-------|
| Model | `melotts-en-v2-f16.gguf` (~102 MB) |
| Companion | `bert-base-uncased-q4k.gguf` (~52 MB) — set as codec |
| Test text | `Welcome to MeloTTS, a high quality text to speech system.` |
| Expected | 44.1 kHz English speech. 4 speakers available (v2). |
| Backend quirks | Needs BERT companion via setCodecPath. Speakers not yet selectable via UI (numbered, not named). |
| Status | untested |

### OuteTTS

| Field | Value |
|-------|-------|
| Model | `outetts-0.3-1b-q8_0.gguf` (~1.3 GB) |
| Companion | `wavtokenizer-decoder-f16.gguf` (~130 MB) — set as codec |
| Test text | `This is OuteTTS, an open source text to speech model based on language modeling.` |
| Expected | English speech, 24 kHz. Voice clone via JSON speaker file (advanced). |
| Backend quirks | OLMo-1B backbone. Needs WavTokenizer decoder companion. |
| Status | untested |

### Parler-TTS

| Field | Value |
|-------|-------|
| Model | `parler-mini-v1.1-q8_0.gguf` (~900 MB) |
| Companion | none |
| Test text | `This is a demonstration of Parler TTS with voice description.` |
| Instruct field | `A female speaker with a warm, expressive voice, speaking clearly at a moderate pace in a quiet studio.` |
| Expected | Voice matching the text description. Uses setInstruct() path. |
| Backend quirks | T5 encoder + MusicGen decoder + DAC 44.1 kHz. Voice via natural-language description. |
| Status | untested |

### Pocket TTS

| Field | Value |
|-------|-------|
| Model | `pocket-tts-english-f16.gguf` (~220 MB) |
| Companion | none |
| Test text | `Pocket TTS is a tiny but capable text to speech model.` |
| Expected | English speech, 24 kHz. 100M params — small and fast. |
| Backend quirks | Continuous-latent AR. Voice clone via reference WAV (F16 variant only). |
| Status | untested |

### SpeechT5

| Field | Value |
|-------|-------|
| Model | `speecht5-tts-f16.gguf` (~300 MB) |
| Companion | none |
| Test text | `Microsoft SpeechT5 produces natural sounding English speech.` |
| Expected | English speech, ~16 kHz (mel decoder + HiFi-GAN). |
| Backend quirks | Needs x-vector for speaker conditioning. Default speaker if no voice set. |
| Status | untested |

### KugelAudio

| Field | Value |
|-------|-------|
| Model | `kugelaudio-0-open-f16.gguf` (~14 GB) |
| Companion | none |
| Test text | `KugelAudio is a large neural text to speech model.` |
| Expected | High quality speech output. |
| Backend quirks | Very large model (14 GB F16). May need GPU for reasonable speed. |
| Status | untested |

### Zonos

| Field | Value |
|-------|-------|
| Model | `zonos-v0.1-transformer-q4_k.gguf` (~872 MB) |
| Companion | `dac-44khz.gguf` (shared with Dia) — set as codec |
| Test text | `Zonos is a text to speech model with emotion and pitch control.` |
| Expected | 44.1 kHz output. Test emotion by varying temperature / CFG scale. |
| Backend quirks | 8-axis emotion control, pitch/rate tuning, voice cloning (via pre-computed embeddings). CFG scale default 2.0. |
| Status | untested |

## TTS variants (use parent backend's test procedure)

| Variant | Parent backend | Model | Key difference |
|---------|----------------|-------|----------------|
| chatterbox-turbo | chatterbox | chatterbox-turbo-t3-q8_0 + turbo-s3gen-q8_0 | Faster (GPT-2 T3 + 2-step S3Gen) |
| kartoffelbox-turbo | chatterbox | kartoffelbox-turbo-t3-q8_0 + turbo-s3gen-f16 | German |
| lahgtna-chatterbox | chatterbox | lahgtna chatterbox-t3-f16 + s3gen-q8_0 | Arabic |
| lex-au-orpheus-de | orpheus | Orpheus-3b-German-FT-Q8_0 + snac-24khz | German |
| kartoffel-orpheus-de-natural | orpheus | kartoffel-orpheus-de-natural-q8_0 + snac-24khz | German (natural voices) |
| kartoffel-orpheus-de-synthetic | orpheus | kartoffel-orpheus-de-synthetic-q8_0 + snac-24khz | German (emotion control) |
| qwen3-tts-1.7b-base | qwen3-tts | qwen3-tts-12hz-1.7b-base-q8_0 + tokenizer | Higher quality, larger |
| qwen3-tts-1.7b-customvoice | qwen3-tts | qwen3-tts-12hz-1.7b-customvoice-q8_0 + tokenizer | 9 baked speakers (1.7B) |
| qwen3-tts-1.7b-voicedesign | qwen3-tts | qwen3-tts-12hz-1.7b-voicedesign-q8_0 + tokenizer | Voice description (1.7B) |
| gwen-tts | qwen3-tts | gwen-tts-0.6b-q8_0 + tokenizer | Vietnamese-optimised |
| vibevoice-1.5b | vibevoice-tts | vibevoice-1.5b-tts-q4_k | Larger, runtime WAV cloning |

## Post-processor verification

| Model | Test input | Expected output |
|-------|-----------|-----------------|
| PCS (pcs-xlmr-base-q4_k) | `hello how are you doing today i am fine` | `Hello, how are you doing today? I am fine.` |
| Truecaser LSTM DE | `hallo mein name ist max und ich komme aus berlin` | `Hallo mein Name ist Max und ich komme aus Berlin` |
| Truecaser LSTM EN | `the united states of america is in north america` | `The United States of America is in North America` |
