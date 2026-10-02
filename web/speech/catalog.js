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
for (const models of Object.values(CW_SPEECH_MODELS)) {
  for (const model of models) { model.backend = 'whisper'; model.recommended = true; }
}
CW_SPEECH_MODELS.crispasr.push(
  { id: 'moonshine-tiny-q4_k', name: 'Moonshine tiny (q4_k, CrispASR WASM)', sizeBytes: 21199840, languages: ['en'], backend: 'moonshine', recommended: true, url: 'https://huggingface.co/cstr/moonshine-tiny-GGUF/resolve/main/moonshine-tiny-q4_k.gguf', companions: [{ path: '/tokenizer.bin', url: 'https://huggingface.co/cstr/moonshine-tiny-GGUF/resolve/main/tokenizer.bin' }] },
);
// Phonon-2 uses the existing Parakeet architecture. Its compressed upstream
// transport size is not the GGUF download size or its working memory.
for (const [quant, sizeBytes] of [['q4_k', 402000000], ['q8_0', 674000000], ['f16', 1255000000]]) {
  CW_SPEECH_MODELS.crispasr.push({ id: 'phonon2-' + quant, name: 'Phonon-2 (' + quant + ', English)',
    sizeBytes, languages: ['en'], backend: 'parakeet', recommended: false,
    license: 'CC-BY-4.0 · Fermion Research · derived from NVIDIA Parakeet TDT v3',
    url: 'https://huggingface.co/cstr/phonon2-GGUF/resolve/3ed3e6ad6e7ce63affffeede37328ff756efaa2f/phonon2-' + quant + '.gguf' });
}
CW_SPEECH_MODELS.onnx.push(
  { id: 'onnx-moonshine-tiny', name: 'Moonshine tiny (ONNX WASM)', sizeBytes: 31000000, languages: ['en'], backend: 'moonshine', recommended: true, repo: 'onnx-community/moonshine-tiny-ONNX' },
  { id: 'onnx-whisper-base', name: 'Whisper base (ONNX WASM)', sizeBytes: 80000000, languages: ['en', 'de', 'zh', 'es', 'fr', 'ja'], backend: 'whisper', recommended: true, repo: 'onnx-community/whisper-base' },
  { id: 'onnx-whisper-small', name: 'Whisper small (ONNX WASM)', sizeBytes: 270000000, languages: ['en', 'de', 'zh', 'es', 'fr', 'ja'], backend: 'whisper', recommended: false, repo: 'onnx-community/whisper-small' },
);
