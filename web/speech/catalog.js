// Download-only URLs. No audio or text is sent to these hosts.
globalThis.CW_SPEECH_MODELS = {
  crispasr: [
    { id: 'tiny.en', name: 'Whisper tiny English (CrispASR WASM)', sizeBytes: 32166155, languages: ['en'], url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q5_1.bin' },
    { id: 'tiny', name: 'Whisper tiny multilingual (CrispASR WASM)', sizeBytes: 32152673, languages: ['en', 'de', 'zh', 'es', 'fr', 'ja'], url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin' },
    { id: 'base', name: 'Whisper base multilingual (CrispASR WASM)', sizeBytes: 59707625, languages: ['en', 'de', 'zh', 'es', 'fr', 'ja'], url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin' },
  ],
  onnx: [
    { id: 'onnx-tiny.en', name: 'Whisper tiny English (ONNX WASM)', sizeBytes: 41000000, languages: ['en'], repo: 'onnx-community/whisper-tiny.en' },
    { id: 'onnx-tiny', name: 'Whisper tiny multilingual (ONNX WASM)', sizeBytes: 41000000, languages: ['en', 'de', 'zh', 'es', 'fr', 'ja'], repo: 'onnx-community/whisper-tiny' },
  ],
};
