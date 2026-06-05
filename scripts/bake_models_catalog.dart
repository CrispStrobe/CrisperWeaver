// Bake the HF-discovered model catalogue into a static Dart file so
// the Models screen is fully populated at first launch without
// waiting on the live HF probe. Run this before every release and
// commit the regenerated `lib/services/baked_models_catalog.dart`.
//
// Usage (from repo root):
//
//     dart run scripts/bake_models_catalog.dart
//
// Wire into CI before `flutter build` so release tarballs ship with
// the catalogue pre-populated.
//
// The repo list below is the single source of truth for the script
// — keep it in sync with `BackendRepo`'s `backendRepos` map in
// `lib/services/model_service.dart`. When you add a new
// BackendRepo there, mirror the entry here OR re-run the script
// after the change and commit the new output.
//
// Pure-Dart, no Flutter deps — invoke with `dart run`, no SDK init.

import 'dart:convert';
import 'dart:io';

class RepoSpec {
  final String backend;
  final String repoId;
  final String baseName;
  final String displayPrefix;
  final String description;
  final String kind; // ModelKind.<value>
  final String? voicepackBaseName;
  final String extension;

  const RepoSpec({
    required this.backend,
    required this.repoId,
    required this.baseName,
    required this.displayPrefix,
    required this.description,
    this.kind = 'asr',
    this.voicepackBaseName,
    this.extension = '.gguf',
  });
}

// Keep in sync with lib/services/model_service.dart::backendRepos.
const _repos = <RepoSpec>[
  RepoSpec(
    backend: 'whisper',
    repoId: 'ggerganov/whisper.cpp',
    baseName: 'ggml-',
    displayPrefix: 'Whisper',
    description: 'Whisper (quantised GGML)',
    extension: '.bin',
  ),
  RepoSpec(
    backend: 'parakeet',
    repoId: 'cstr/parakeet-tdt-0.6b-v3-GGUF',
    baseName: 'parakeet-tdt-0.6b-v3',
    displayPrefix: 'Parakeet TDT 0.6B v3',
    description: 'Fast English ASR (NVIDIA Parakeet)',
  ),
  RepoSpec(
    backend: 'canary',
    repoId: 'cstr/canary-1b-v2-GGUF',
    baseName: 'canary-1b-v2',
    displayPrefix: 'Canary 1B v2',
    description: 'NVIDIA Canary — speech translation',
  ),
  RepoSpec(
    backend: 'cohere',
    repoId: 'cstr/cohere-transcribe-03-2026-GGUF',
    baseName: 'cohere-transcribe',
    displayPrefix: 'Cohere Transcribe',
    description: 'Cohere high-accuracy ASR',
  ),
  RepoSpec(
    backend: 'voxtral',
    repoId: 'cstr/voxtral-mini-3b-2507-GGUF',
    baseName: 'voxtral-mini-3b-2507',
    displayPrefix: 'Voxtral Mini 3B 2507',
    description: 'Mistral Voxtral — speech translation + ASR',
  ),
  RepoSpec(
    backend: 'voxtral4b',
    repoId: 'cstr/voxtral-mini-4b-realtime-GGUF',
    baseName: 'voxtral-mini-4b-realtime',
    displayPrefix: 'Voxtral Mini 4B realtime',
    description: 'Voxtral realtime variant',
  ),
  RepoSpec(
    backend: 'qwen3',
    repoId: 'cstr/qwen3-asr-0.6b-GGUF',
    baseName: 'qwen3-asr-0.6b',
    displayPrefix: 'Qwen3-ASR 0.6B',
    description: 'Multilingual (30+ langs incl. Chinese dialects)',
  ),
  RepoSpec(
    backend: 'granite',
    repoId: 'cstr/granite-speech-4.0-1b-GGUF',
    baseName: 'granite-speech-4.0-1b',
    displayPrefix: 'Granite 4.0 1B Speech',
    description: 'IBM Granite speech (instruction-tuned)',
  ),
  RepoSpec(
    backend: 'fastconformer-ctc',
    repoId: 'cstr/stt-en-fastconformer-ctc-large-GGUF',
    baseName: 'stt-en-fastconformer-ctc-large',
    displayPrefix: 'FastConformer CTC (en)',
    description: 'Low-latency CTC ASR (English)',
  ),
  RepoSpec(
    backend: 'wav2vec2',
    repoId: 'cstr/wav2vec2-large-xlsr-53-english-GGUF',
    baseName: 'wav2vec2-xlsr-en',
    displayPrefix: 'Wav2Vec2 base (en)',
    description: 'Self-supervised (facebook/wav2vec2)',
  ),
  RepoSpec(
    backend: 'omniasr-llm',
    repoId: 'cstr/omniasr-llm-300m-v2-GGUF',
    baseName: 'omniasr-llm-300m-v2',
    displayPrefix: 'OmniASR LLM 300M v2',
    description: 'Multilingual LLM-based ASR with `lang=` hint',
  ),
  RepoSpec(
    backend: 'firered-asr',
    repoId: 'cstr/firered-asr2-aed-GGUF',
    baseName: 'firered-asr2-aed',
    displayPrefix: 'FireRed ASR2 AED',
    description: 'FireRed AED ASR (Chinese + English)',
  ),
  RepoSpec(
    backend: 'kyutai-stt',
    repoId: 'cstr/kyutai-stt-1b-GGUF',
    baseName: 'kyutai-stt-1b',
    displayPrefix: 'Kyutai STT 1B',
    description: 'Kyutai streaming STT',
  ),
  RepoSpec(
    backend: 'glm-asr',
    repoId: 'cstr/glm-asr-nano-GGUF',
    baseName: 'glm-asr-nano',
    displayPrefix: 'GLM-ASR Nano',
    description: 'GLM-family multilingual ASR',
  ),
  RepoSpec(
    backend: 'vibevoice',
    repoId: 'cstr/vibevoice-asr-GGUF',
    baseName: 'vibevoice-asr',
    displayPrefix: 'VibeVoice ASR',
    description: 'Multilingual large ASR (~4.5 GB)',
  ),
  RepoSpec(
    backend: 'vibevoice-tts',
    repoId: 'cstr/vibevoice-realtime-0.5b-GGUF',
    baseName: 'vibevoice-realtime-0.5b',
    displayPrefix: 'VibeVoice Realtime 0.5B',
    description: 'VibeVoice realtime TTS',
    kind: 'tts',
    voicepackBaseName: 'vibevoice-voice',
  ),
  RepoSpec(
    backend: 'mimo-asr',
    repoId: 'cstr/mimo-asr-GGUF',
    baseName: 'mimo-asr',
    displayPrefix: 'MiMo ASR',
    description: 'XiaomiMiMo MiMo-Audio ASR',
  ),
  RepoSpec(
    backend: 'mimo-asr',
    repoId: 'cstr/mimo-tokenizer-GGUF',
    baseName: 'mimo-tokenizer',
    displayPrefix: 'MiMo audio tokenizer',
    description: 'MiMo audio tokenizer (PCM → 8-channel codes)',
    kind: 'codec',
  ),
  RepoSpec(
    backend: 'kokoro',
    repoId: 'cstr/kokoro-82m-GGUF',
    baseName: 'kokoro-82m',
    displayPrefix: 'Kokoro 82M TTS',
    description: 'Kokoro multilingual TTS (~100 MB)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'kokoro',
    repoId: 'cstr/kokoro-voices-GGUF',
    baseName: '',
    displayPrefix: 'Kokoro 82M TTS',
    description: 'Kokoro voicepacks',
    kind: 'voice',
    voicepackBaseName: 'kokoro-voice',
  ),
  RepoSpec(
    backend: 'orpheus',
    repoId: 'cstr/orpheus-3b-base-GGUF',
    baseName: 'orpheus-3b-base',
    displayPrefix: 'Orpheus 3B TTS',
    description: 'Orpheus Llama-3.2-3B TTS (~3.5 GB)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'firered-punc',
    repoId: 'cstr/fireredpunc-GGUF',
    baseName: 'fireredpunc',
    displayPrefix: 'FireRedPunc (post-processor)',
    description: 'Punctuation restoration for CTC ASR output',
    kind: 'punc',
  ),
  RepoSpec(
    backend: 'gemma4-e2b',
    repoId: 'cstr/gemma4-e2b-it-GGUF',
    baseName: 'gemma4-e2b-it',
    displayPrefix: 'Gemma4-E2B-it',
    description: 'Multilingual ASR (140+ languages, instruction-tuned)',
  ),
  RepoSpec(
    backend: 'omniasr-llm-unlimited',
    repoId: 'cstr/omniasr-llm-unlimited-300m-v2-GGUF',
    baseName: 'omniasr-llm-unlimited-300m-v2',
    displayPrefix: 'OmniASR LLM unlimited 300M v2',
    description: 'Streaming OmniASR (unlimited audio)',
  ),
  RepoSpec(
    backend: 'granite-4.1',
    repoId: 'cstr/granite-speech-4.1-2b-GGUF',
    baseName: 'granite-speech-4.1-2b',
    displayPrefix: 'Granite Speech 4.1 2B',
    description: 'IBM Granite Speech 4.1 (2B)',
  ),
  RepoSpec(
    backend: 'granite-4.1-plus',
    repoId: 'cstr/granite-speech-4.1-2b-plus-GGUF',
    baseName: 'granite-speech-4.1-2b-plus',
    displayPrefix: 'Granite Speech 4.1 2B+',
    description: 'Granite Speech 4.1+ (instruction-tuned)',
  ),
  RepoSpec(
    backend: 'granite-4.1-nar',
    repoId: 'cstr/granite-speech-4.1-2b-nar-GGUF',
    baseName: 'granite-speech-4.1-2b-nar',
    displayPrefix: 'Granite Speech 4.1 2B NAR',
    description: 'Granite Speech 4.1 NAR (parallel-decode)',
  ),
  RepoSpec(
    backend: 'chatterbox',
    repoId: 'cstr/chatterbox-GGUF',
    baseName: 'chatterbox-t3',
    displayPrefix: 'Chatterbox T3',
    description: 'Chatterbox TTS T3 (AR transformer)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'chatterbox',
    repoId: 'cstr/chatterbox-GGUF',
    baseName: 'chatterbox-s3gen',
    displayPrefix: 'Chatterbox S3Gen',
    description: 'Chatterbox S3Gen flow-matching vocoder',
    kind: 'codec',
  ),
  RepoSpec(
    backend: 'indextts',
    repoId: 'cstr/indextts-1.5-GGUF',
    baseName: 'indextts-gpt',
    displayPrefix: 'IndexTTS 1.5 GPT',
    description: 'IndexTTS 1.5 GPT (ZH+EN)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'fullstop-punc',
    repoId: 'cstr/fullstop-punc-multilang-GGUF',
    baseName: 'fullstop-punc',
    displayPrefix: 'Fullstop-punc multilang',
    description: 'Punctuation restoration (EN/DE/FR/IT)',
    kind: 'punc',
  ),
  RepoSpec(
    backend: 'pyannote',
    repoId: 'cstr/pyannote-v3-segmentation-GGUF',
    baseName: 'pyannote-seg-3.0',
    displayPrefix: 'Pyannote v3 segmentation',
    description: 'Pyannote ML diarisation model',
    kind: 'diarize',
  ),
  RepoSpec(
    backend: 'm2m100',
    repoId: 'cstr/m2m100-418m-GGUF',
    baseName: 'm2m100-418m',
    displayPrefix: 'M2M-100 418M',
    description: 'Text-to-text translation (100 languages, any-to-any)',
    kind: 'translate',
  ),
  RepoSpec(
    backend: 'm2m100-wmt21',
    repoId: 'cstr/wmt21-dense-24-wide-en-x-GGUF',
    baseName: 'wmt21-dense-24-wide-en-x',
    displayPrefix: 'WMT21 Dense 24-wide en→X',
    description: 'WMT21 News winner — English to 7 target languages',
    kind: 'translate',
  ),
  RepoSpec(
    backend: 'm2m100-wmt21',
    repoId: 'cstr/wmt21-dense-24-wide-x-en-GGUF',
    baseName: 'wmt21-dense-24-wide-x-en',
    displayPrefix: 'WMT21 Dense 24-wide X→en',
    description: 'WMT21 News winner — 7 source languages to English',
    kind: 'translate',
  ),
  RepoSpec(
    backend: 'madlad',
    repoId: 'cstr/madlad400-3b-mt-GGUF',
    baseName: 'madlad400-3b-mt',
    displayPrefix: 'MADLAD-400 3B-MT',
    description: 'T5 translator, 419 languages',
    kind: 'translate',
  ),
  // ---- synced 2026-05-30 with backendRepos (issue #18) ----------------
  // These repos existed in `backendRepos` but were absent from the list
  // above, so their quants never made it into the baked snapshot — they
  // only appeared after a Model-Management "deep refresh". Mirrored here so
  // a re-bake ships them and they list on a fresh launch.
  RepoSpec(
    backend: 'parakeet',
    repoId: 'cstr/parakeet-tdt-0.6b-v2-GGUF',
    baseName: 'parakeet-tdt-0.6b-v2',
    displayPrefix: 'Parakeet TDT 0.6B v2',
    description: 'Parakeet TDT 0.6B v2 (earlier vocab)',
  ),
  RepoSpec(
    backend: 'parakeet',
    repoId: 'cstr/parakeet-tdt-1.1b-GGUF',
    baseName: 'parakeet-tdt-1.1b',
    displayPrefix: 'Parakeet TDT 1.1B',
    description: 'Larger Parakeet TDT, 42-layer encoder',
  ),
  RepoSpec(
    backend: 'qwen3',
    repoId: 'cstr/qwen3-asr-1.7b-GGUF',
    baseName: 'qwen3-asr-1.7b',
    displayPrefix: 'Qwen3-ASR 1.7B',
    description: 'Qwen3-ASR 1.7B (29 langs)',
  ),
  RepoSpec(
    backend: 'mega-asr',
    repoId: 'cstr/mega-asr-GGUF',
    baseName: 'mega-asr-1.7b',
    displayPrefix: 'Mega-ASR 1.7B',
    description: 'Qwen3-ASR 1.7B + robustness LoRA (29 langs)',
  ),
  RepoSpec(
    backend: 'omniasr-llm',
    repoId: 'cstr/omniasr-llm-1b-GGUF',
    baseName: 'omniasr-llm-1b',
    displayPrefix: 'OmniASR LLM 1B',
    description: 'OmniASR LLM 1B (multilingual)',
  ),
  RepoSpec(
    backend: 'funasr',
    repoId: 'cstr/funasr-nano-GGUF',
    baseName: 'funasr-nano-2512',
    displayPrefix: 'FunASR Nano 2512',
    description: 'FunASR Nano (zh/en/ja/ko/yue)',
  ),
  RepoSpec(
    backend: 'funasr',
    repoId: 'cstr/funasr-mlt-nano-GGUF',
    baseName: 'funasr-mlt-nano-2512',
    displayPrefix: 'FunASR MLT Nano 2512',
    description: 'FunASR multilingual Nano (30 langs)',
  ),
  RepoSpec(
    backend: 'paraformer',
    repoId: 'cstr/paraformer-zh-GGUF',
    baseName: 'paraformer-zh',
    displayPrefix: 'Paraformer ZH',
    description: 'Paraformer Mandarin + English NAR-ASR',
  ),
  RepoSpec(
    backend: 'sensevoice',
    repoId: 'cstr/sensevoice-small-GGUF',
    baseName: 'sensevoice-small',
    displayPrefix: 'SenseVoice Small',
    description: 'SenseVoice Small (zh/en/ja/ko/yue) with built-in LID',
  ),
  RepoSpec(
    backend: 'wav2vec2',
    repoId: 'cstr/data2vec-audio-960h-GGUF',
    baseName: 'data2vec-audio-base-960h',
    displayPrefix: 'Data2Vec-Audio base 960h (en)',
    description: 'Data2Vec-Audio CTC ASR (facebook, en)',
  ),
  RepoSpec(
    backend: 'whisper',
    repoId: 'cstr/distil-large-v3-GGUF',
    baseName: 'distil-large-v3',
    displayPrefix: 'Distil-Whisper Large v3',
    description: 'Distilled Whisper Large v3 (English) — ~6x faster',
    extension: '.bin',
  ),
  RepoSpec(
    backend: 'moonshine',
    repoId: 'cstr/moonshine-tiny-GGUF',
    baseName: 'moonshine-tiny',
    displayPrefix: 'Moonshine tiny',
    description: 'Moonshine tiny ASR (English, lightweight)',
  ),
  RepoSpec(
    backend: 'moonshine',
    repoId: 'cstr/moonshine-base-GGUF',
    baseName: 'moonshine-base',
    displayPrefix: 'Moonshine base',
    description: 'Moonshine base ASR (English, lightweight)',
  ),
  RepoSpec(
    backend: 'moonshine-streaming',
    repoId: 'cstr/moonshine-streaming-tiny-GGUF',
    baseName: 'moonshine-streaming-tiny',
    displayPrefix: 'Moonshine streaming tiny',
    description: 'Moonshine streaming ASR for live mic input',
  ),
  RepoSpec(
    backend: 'chatterbox',
    repoId: 'cstr/chatterbox-turbo-GGUF',
    baseName: 'chatterbox-turbo-t3',
    displayPrefix: 'Chatterbox turbo T3',
    description: 'Chatterbox turbo TTS T3 — pair with chatterbox-turbo-s3gen',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'chatterbox',
    repoId: 'cstr/chatterbox-turbo-GGUF',
    baseName: 'chatterbox-turbo-s3gen',
    displayPrefix: 'Chatterbox turbo S3Gen',
    description: 'Chatterbox turbo S3Gen vocoder (English)',
    kind: 'codec',
  ),
  RepoSpec(
    backend: 'chatterbox',
    repoId: 'cstr/kartoffelbox-turbo-GGUF',
    baseName: 'kartoffelbox-turbo-t3',
    displayPrefix: 'Kartoffelbox turbo T3 (DE)',
    description: 'Kartoffelbox-turbo German T3 — pair with chatterbox-s3gen',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'orpheus',
    repoId: 'cstr/kartoffel-orpheus-3b-german-natural-GGUF',
    baseName: 'kartoffel-orpheus-3b-german-natural',
    displayPrefix: 'Kartoffel-Orpheus 3B natural (DE)',
    description: 'Orpheus 3B German finetune (natural voices)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'orpheus',
    repoId: 'cstr/kartoffel-orpheus-3b-german-synthetic-GGUF',
    baseName: 'kartoffel-orpheus-3b-german-synthetic',
    displayPrefix: 'Kartoffel-Orpheus 3B synthetic (DE)',
    description: 'Orpheus 3B German finetune (synthetic voices)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'qwen3-tts',
    repoId: 'cstr/qwen3-tts-0.6b-base-GGUF',
    baseName: 'qwen3-tts-12hz-0.6b-base',
    displayPrefix: 'Qwen3-TTS 0.6B base',
    description: 'Qwen3-TTS base talker — needs qwen3-tts-tokenizer-12hz codec',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'qwen3-tts',
    repoId: 'cstr/qwen3-tts-0.6b-customvoice-GGUF',
    baseName: 'qwen3-tts-12hz-0.6b-customvoice',
    displayPrefix: 'Qwen3-TTS 0.6B custom-voice',
    description: 'Qwen3-TTS 0.6B with ICL voice cloning (9 langs, no Russian)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'qwen3-tts',
    repoId: 'cstr/qwen3-tts-1.7b-customvoice-GGUF',
    baseName: 'qwen3-tts-12hz-1.7b-customvoice',
    displayPrefix: 'Qwen3-TTS 1.7B custom-voice',
    description: 'Qwen3-TTS 1.7B with ICL voice cloning (9 langs, no Russian)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'qwen3-tts',
    repoId: 'cstr/qwen3-tts-1.7b-voicedesign-GGUF',
    baseName: 'qwen3-tts-12hz-1.7b-voicedesign',
    displayPrefix: 'Qwen3-TTS 1.7B voice-design',
    description: 'Qwen3-TTS 1.7B — natural-language voice description',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'qwen3-tts',
    repoId: 'cstr/qwen3-tts-tokenizer-12hz-GGUF',
    baseName: 'qwen3-tts-tokenizer-12hz',
    displayPrefix: 'Qwen3-TTS codec',
    description: 'Qwen3-TTS 12 Hz audio codec — companion to every Qwen3-TTS talker',
    kind: 'codec',
  ),
  RepoSpec(
    backend: 'voxcpm2-tts',
    repoId: 'cstr/voxcpm2-GGUF',
    baseName: 'voxcpm2',
    displayPrefix: 'VoxCPM2',
    description: 'VoxCPM2 diffusion TTS (29 languages, zero-shot)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'f5-tts',
    repoId: 'cstr/f5-tts-GGUF',
    baseName: 'f5-tts-v1-base',
    displayPrefix: 'F5-TTS',
    description: 'F5-TTS DiT flow-matching TTS — zero-shot voice clone (English)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'cosyvoice3-tts',
    repoId: 'cstr/cosyvoice3-0.5b-2512-GGUF',
    baseName: 'cosyvoice3-llm',
    displayPrefix: 'CosyVoice3 0.5B',
    description: 'CosyVoice3 streaming multilingual TTS (11 languages)',
    kind: 'tts',
  ),
  RepoSpec(
    backend: 'piper',
    repoId: 'cstr/piper-voices-GGUF',
    baseName: 'piper',
    displayPrefix: 'Piper',
    description: 'Piper VITS TTS — tiny single-file voices',
    kind: 'tts',
  ),
  // ----- Phase 2 parity: new TTS backends -----
  RepoSpec(backend: 'bark', repoId: 'cstr/bark-small-GGUF', baseName: 'bark-small',
    displayPrefix: 'Bark', description: 'Bark 3-stage GPT-2 TTS (multilingual)', kind: 'tts'),
  RepoSpec(backend: 'csm', repoId: 'cstr/csm-1b-GGUF', baseName: 'csm-1b',
    displayPrefix: 'CSM', description: 'Sesame CSM-1B conversational TTS (EN)', kind: 'tts'),
  RepoSpec(backend: 'dia', repoId: 'cstr/dia-1.6b-GGUF', baseName: 'dia-1.6b',
    displayPrefix: 'Dia', description: 'Dia 1.6B dialogue TTS ([S1]/[S2])', kind: 'tts'),
  RepoSpec(backend: 'fastpitch', repoId: 'cstr/fastpitch-en-GGUF', baseName: 'fastpitch-en',
    displayPrefix: 'FastPitch', description: 'NVIDIA FastPitch deterministic TTS (EN)', kind: 'tts'),
  RepoSpec(backend: 'melotts', repoId: 'cstr/melotts-en-v2-GGUF', baseName: 'melotts-en-v2',
    displayPrefix: 'MeloTTS v2', description: 'MeloTTS VITS2 TTS (4 EN speakers)', kind: 'tts'),
  RepoSpec(backend: 'melotts', repoId: 'cstr/melotts-en-v3-GGUF', baseName: 'melotts-en-v3',
    displayPrefix: 'MeloTTS v3', description: 'MeloTTS v3 newest checkpoint', kind: 'tts'),
  RepoSpec(backend: 'outetts', repoId: 'cstr/outetts-0.3-1b-GGUF', baseName: 'outetts-0.3-1b',
    displayPrefix: 'OuteTTS', description: 'OuteTTS 0.3 1B — OLMo + WavTokenizer (EN)', kind: 'tts'),
  RepoSpec(backend: 'parler-tts', repoId: 'cstr/parler-tts-mini-v1.1-GGUF', baseName: 'parler-mini-v1.1',
    displayPrefix: 'Parler-TTS', description: 'Parler-TTS Mini — text voice description (EN)', kind: 'tts'),
  RepoSpec(backend: 'pocket-tts', repoId: 'cstr/pocket-tts-GGUF', baseName: 'pocket-tts-english',
    displayPrefix: 'Pocket TTS', description: 'Kyutai Pocket TTS 100M (EN)', kind: 'tts'),
  RepoSpec(backend: 'speecht5', repoId: 'cstr/speecht5-tts-GGUF', baseName: 'speecht5-tts',
    displayPrefix: 'SpeechT5', description: 'Microsoft SpeechT5 80M TTS (EN)', kind: 'tts'),
  RepoSpec(backend: 'kugelaudio', repoId: 'cstr/kugelaudio-0-open-GGUF', baseName: 'kugelaudio-0-open',
    displayPrefix: 'KugelAudio', description: 'KugelAudio 0 Open TTS', kind: 'tts'),
  RepoSpec(backend: 'zonos', repoId: 'cstr/zonos-v0.1-transformer-GGUF', baseName: 'zonos-v0.1-transformer',
    displayPrefix: 'Zonos', description: 'Zonos v0.1 TTS — emotion/pitch/rate/voice-clone', kind: 'tts'),
  // ----- Phase 2 parity: TTS variants -----
  RepoSpec(backend: 'chatterbox', repoId: 'cstr/lahgtna-chatterbox-v1-GGUF', baseName: 'chatterbox-t3',
    displayPrefix: 'Lahgtna Chatterbox', description: 'Arabic Chatterbox finetune', kind: 'tts'),
  RepoSpec(backend: 'orpheus', repoId: 'lex-au/Orpheus-3b-German-FT-Q8_0.gguf', baseName: 'Orpheus-3b-German-FT',
    displayPrefix: 'Orpheus DE (lex-au)', description: 'German Orpheus-3B finetune', kind: 'tts'),
  RepoSpec(backend: 'qwen3-tts', repoId: 'cstr/gwen-tts-0.6b-GGUF', baseName: 'gwen-tts-0.6b',
    displayPrefix: 'Gwen-TTS', description: 'Vietnamese Qwen3-TTS finetune', kind: 'tts'),
  RepoSpec(backend: 'qwen3-tts', repoId: 'cstr/qwen3-tts-1.7b-base-GGUF', baseName: 'qwen3-tts-12hz-1.7b-base',
    displayPrefix: 'Qwen3-TTS 1.7B base', description: 'Qwen3-TTS 1.7B base voice clone', kind: 'tts'),
  RepoSpec(backend: 'vibevoice-tts', repoId: 'cstr/vibevoice-1.5b-GGUF', baseName: 'vibevoice-1.5b-tts',
    displayPrefix: 'VibeVoice 1.5B', description: 'VibeVoice 1.5B TTS', kind: 'tts'),
  // ----- Phase 2 parity: new ASR models -----
  RepoSpec(backend: 'moonshine', repoId: 'cstr/moonshine-base-de-fidoriel-GGUF', baseName: 'moonshine-base-de-fidoriel',
    displayPrefix: 'Moonshine DE', description: 'Moonshine base German (6.9% WER)'),
  RepoSpec(backend: 'moonshine', repoId: 'cstr/moonshine-tiny-de-fidoriel-GGUF', baseName: 'moonshine-tiny-de-fidoriel',
    displayPrefix: 'Moonshine tiny DE', description: 'Moonshine tiny German (11.4% WER)'),
  RepoSpec(backend: 'wav2vec2', repoId: 'cstr/hubert-large-ls960-ft-GGUF', baseName: 'hubert-large-ls960-ft',
    displayPrefix: 'HuBERT Large', description: 'HuBERT Large LS960 fine-tuned (EN CTC)'),
  RepoSpec(backend: 'wav2vec2', repoId: 'cstr/wav2vec2-large-xlsr-53-german-GGUF', baseName: 'wav2vec2-large-xlsr-53-german',
    displayPrefix: 'Wav2Vec2 DE', description: 'Wav2Vec2 XLSR-53 German CTC'),
  RepoSpec(backend: 'omniasr', repoId: 'cstr/omniASR-CTC-300M-v2-GGUF', baseName: 'omniasr-ctc-300m-v2',
    displayPrefix: 'OmniASR CTC 300M', description: 'OmniASR CTC 300M — 1600+ languages'),
  RepoSpec(backend: 'moss-audio', repoId: 'cstr/MOSS-Audio-4B-Instruct-GGUF', baseName: 'moss-audio-4b-instruct',
    displayPrefix: 'MOSS-Audio 4B', description: 'ASR + audio QA (Whisper enc + Qwen3 LLM)'),
  RepoSpec(backend: 'parakeet', repoId: 'cstr/parakeet-tdt-0.6b-ja-GGUF', baseName: 'parakeet-tdt-0.6b-ja',
    displayPrefix: 'Parakeet JA', description: 'Parakeet TDT 0.6B Japanese'),
  RepoSpec(backend: 'fastconformer-ctc', repoId: 'cstr/parakeet-ctc-0.6b-GGUF', baseName: 'parakeet-ctc-0.6b',
    displayPrefix: 'Parakeet CTC 0.6B', description: 'Parakeet CTC-only 0.6B (EN)'),
  RepoSpec(backend: 'fastconformer-ctc', repoId: 'cstr/parakeet-ctc-1.1b-GGUF', baseName: 'parakeet-ctc-1.1b',
    displayPrefix: 'Parakeet CTC 1.1B', description: 'Parakeet CTC-only 1.1B (EN)'),
  RepoSpec(backend: 'parakeet', repoId: 'cstr/parakeet-tdt_ctc-110m-GGUF', baseName: 'parakeet-tdt_ctc-110m',
    displayPrefix: 'Parakeet TDT+CTC 110M', description: 'Parakeet tiny hybrid (EN)'),
  RepoSpec(backend: 'parakeet', repoId: 'cstr/parakeet-tdt_ctc-1.1b-GGUF', baseName: 'parakeet-tdt_ctc-1.1b',
    displayPrefix: 'Parakeet TDT+CTC 1.1B', description: 'Parakeet large hybrid (multilingual)'),
  RepoSpec(backend: 'parakeet', repoId: 'cstr/parakeet-rnnt-0.6b-GGUF', baseName: 'parakeet-rnnt-0.6b',
    displayPrefix: 'Parakeet RNNT 0.6B', description: 'Parakeet RNN-Transducer 0.6B (EN)'),
  RepoSpec(backend: 'parakeet', repoId: 'cstr/parakeet-rnnt-1.1b-GGUF', baseName: 'parakeet-rnnt-1.1b',
    displayPrefix: 'Parakeet RNNT 1.1B', description: 'Parakeet RNN-Transducer 1.1B (EN)'),
  // ----- Truecaser (non-GGUF .bin format) -----
  RepoSpec(backend: 'truecaser', repoId: 'cstr/truecaser-de', baseName: 'truecaser',
    displayPrefix: 'Truecaser', description: 'BiLSTM truecaser (DE/EN/ES/RU)', kind: 'punc', extension: '.bin'),
];

String _formatSize(int bytes) {
  if (bytes <= 0) return '?';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String _escape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll(r"'", r"\'");

Future<Map<String, dynamic>?> _fetch(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) {
      stderr.writeln('  HTTP ${resp.statusCode} for $url');
      return null;
    }
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> main() async {
  final buf = StringBuffer();
  buf.writeln('// GENERATED FILE — DO NOT EDIT BY HAND.');
  buf.writeln('// Regenerate with: dart run scripts/bake_models_catalog.dart');
  buf.writeln('//');
  buf.writeln('// Baked snapshot of every quant + voicepack discovered via');
  buf.writeln('// the HF API for each `BackendRepo` in `model_service.dart`.');
  buf.writeln('// Loaded at app boot via `getWhisperCppModels()` so the model');
  buf.writeln('// picker is fully populated without a network probe.');
  buf.writeln('//');
  buf.writeln('// Sizes are real (from HF), so the existence-check in');
  buf.writeln('// `_isModelDownloaded` is unaffected.');
  buf.writeln();
  buf.writeln("// ignore_for_file: lines_longer_than_80_chars");
  buf.writeln();
  buf.writeln("import 'model_service.dart';");
  buf.writeln();
  buf.writeln('const Map<String, ModelDefinition> bakedDiscoveredModels = {');

  int totalEntries = 0;
  int totalRepos = 0;
  int failedRepos = 0;
  final emittedKeys = <String>{};

  for (final repo in _repos) {
    totalRepos++;
    stdout.write('${repo.repoId} … ');
    final url = 'https://huggingface.co/api/models/${repo.repoId}?blobs=true';
    Map<String, dynamic>? json;
    try {
      json = await _fetch(url);
    } catch (e) {
      stderr.writeln('  threw: $e');
    }
    if (json == null) {
      stdout.writeln('skipped');
      failedRepos++;
      continue;
    }
    final siblings = (json['siblings'] as List?) ?? const [];
    final voicepackPrefix = repo.voicepackBaseName == null
        ? null
        : '${repo.voicepackBaseName}-';
    int repoEntries = 0;
    for (final sib in siblings) {
      if (sib is! Map) continue;
      final fname = sib['rfilename'] as String? ?? '';
      if (!fname.endsWith(repo.extension)) continue;
      final stem = fname.substring(0, fname.length - repo.extension.length);
      final sizeBytes = (sib['size'] as num?)?.toInt() ?? 0;

      // Voicepack file?
      if (voicepackPrefix != null && stem.startsWith(voicepackPrefix)) {
        final voiceId = stem.substring(voicepackPrefix.length);
        final key = '${repo.voicepackBaseName}-$voiceId';
        if (emittedKeys.add(key)) {
          buf.writeln("  '$key': ModelDefinition(");
          buf.writeln("    name: '$key',");
          buf.writeln(
              "    displayName: '${_escape(repo.displayPrefix)} voice — ${_escape(voiceId)}',");
          buf.writeln("    fileName: '$fname',");
          buf.writeln(
              "    url: 'https://huggingface.co/${repo.repoId}/resolve/main/$fname',");
          buf.writeln('    sizeBytes: $sizeBytes,');
          buf.writeln("    checksum: '',");
          buf.writeln(
              "    description: '${_escape(repo.displayPrefix)} voicepack — ${_formatSize(sizeBytes)}',");
          buf.writeln("    quantization: 'f16',");
          buf.writeln("    backend: '${repo.backend}',");
          buf.writeln('    kind: ModelKind.voice,');
          buf.writeln('  ),');
          repoEntries++;
          totalEntries++;
        }
        continue;
      }

      // Main-model variant — skip when this is a voicepack-only repo.
      if (repo.baseName.isEmpty) continue;
      String quant;
      String key;
      if (stem == repo.baseName) {
        quant = 'f16';
        key = '${repo.baseName}-f16';
      } else if (stem.startsWith('${repo.baseName}-')) {
        quant = stem.substring(repo.baseName.length + 1);
        key = '${repo.baseName}-$quant';
      } else {
        continue;
      }
      if (!emittedKeys.add(key)) continue;
      buf.writeln("  '$key': ModelDefinition(");
      buf.writeln("    name: '$key',");
      buf.writeln(
          "    displayName: '${_escape(repo.displayPrefix)} ($quant)',");
      buf.writeln("    fileName: '$fname',");
      buf.writeln(
          "    url: 'https://huggingface.co/${repo.repoId}/resolve/main/$fname',");
      buf.writeln('    sizeBytes: $sizeBytes,');
      buf.writeln("    checksum: '',");
      buf.writeln(
          "    description: '${_escape(repo.description)} — ${_formatSize(sizeBytes)}',");
      buf.writeln("    quantization: '$quant',");
      buf.writeln("    backend: '${repo.backend}',");
      buf.writeln('    kind: ModelKind.${repo.kind},');
      buf.writeln('  ),');
      repoEntries++;
      totalEntries++;
    }
    stdout.writeln('$repoEntries entries');
  }

  buf.writeln('};');

  final out = File('lib/services/baked_models_catalog.dart');
  await out.writeAsString(buf.toString());

  stdout.writeln('---');
  stdout.writeln('Wrote ${out.path}');
  stdout.writeln(
      '$totalRepos repos probed, $failedRepos skipped, $totalEntries entries baked');
  if (failedRepos > 0) {
    exitCode = 1; // surface to CI but the file is still written
  }
}
