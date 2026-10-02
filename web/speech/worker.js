// All processing happens in this worker; network requests only retrieve models.
importScripts('./catalog.js');
// Emscripten uses resizable WASM memory views. Chromium's TextDecoder rejects
// such views; copy only the bounded string slice before decoding. Keep the
// vendored runtime unchanged so its upstream checksum remains verifiable.
const decodeText = TextDecoder.prototype.decode;
TextDecoder.prototype.decode = function (input, options) {
  if (ArrayBuffer.isView(input) && input.buffer.resizable) input = new Uint8Array(input.buffer, input.byteOffset, input.byteLength).slice();
  return decodeText.call(this, input, options);
};
// Web Crypto also rejects resizable WASM views. Fill a fixed buffer, then
// copy back into the original view; preserve native type and size validation.
const randomValues = crypto.getRandomValues.bind(crypto);
crypto.getRandomValues = function (input) {
  if (ArrayBuffer.isView(input) && input.buffer.resizable) {
    const fixed = new input.constructor(input.length);
    randomValues(fixed); input.set(fixed); return input;
  }
  return randomValues(input);
};
let runtime, runtimeReady, pipeline, transformerEnv, asr, modelId, ttsReady = false;
const CACHE = 'crisperweaver-speech-models-v1';
const progress = (id, value) => postMessage({ id, progress: value });
let catalogueReady;
async function catalogue(engine) {
  if (!catalogueReady) catalogueReady = (async () => {
    const response = await fetch(new URL('./native-models.json', self.location.href));
    if (!response.ok) throw new Error('Browser model catalogue unavailable');
    const candidates = await response.json();
    const known = new Set(CW_SPEECH_MODELS.crispasr.map(m => m.id));
    CW_SPEECH_MODELS.crispasr.push(...candidates.filter(m => !known.has(m.id)));
  })();
  await catalogueReady;
  return CW_SPEECH_MODELS[engine].map(m => ({ ...m,
    experimental: !m.recommended,
    estimatedMemoryMB: Math.ceil((m.sizeBytes * 6 + 128 * 1024 * 1024) / 1024 / 1024),
    browserReason: m.recommended ? 'Small model supported by the browser adapter.'
      : 'Not validated in this browser. May require unsupported features or more memory than the browser can allocate.',
  }));
}

async function modelBytes(url, allowDownloads, id) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(url);
  if (cached) return new Uint8Array(await cached.arrayBuffer());
  if (!allowDownloads) throw new Error('Model downloads are disabled. Import a model first.');
  const res = await fetch(url, { credentials: 'omit' });
  if (!res.ok) throw new Error(`Model download failed: HTTP ${res.status}`);
  const stored = res.clone();
  // Consume the cache branch concurrently so Response.clone() does not buffer
  // a second complete large model while inference waits for the first branch.
  const cacheWrite = cache.put(url, stored).catch(e => console.warn('Model cache unavailable:', e.message));
  const reader = res.body.getReader(), chunks = []; let length = 0;
  const total = Number(res.headers.get('content-length'));
  let preallocated = total > 0 && !res.headers.get('content-encoding') ? new Uint8Array(total) : null;
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    if (preallocated && length + value.length > preallocated.length) {
      chunks.push(preallocated.subarray(0, length)); preallocated = null;
    }
    if (preallocated) preallocated.set(value, length); else chunks.push(value);
    length += value.length;
    progress(id, total > 0 ? Math.min(0.85, length / total * 0.85) : 0.1);
  }
  const bytes = preallocated ? preallocated.subarray(0, length) : new Uint8Array(length); let offset = 0;
  if (!preallocated) for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  await cacheWrite;
  return bytes;
}
async function crisp() {
  if (!runtimeReady) {
    runtimeReady = (async () => {
      importScripts('../wasm/crispasr/libwhisper.js');
      const url = new URL('../wasm/crispasr/libwhisper.wasm', self.location.href);
      const response = await fetch(url);
      if (!response.ok) throw new Error(`Speech runtime unavailable: HTTP ${response.status}`);
      const compiled = await WebAssembly.compile(await response.arrayBuffer());
      const options = { print: () => {}, printErr: m => console.debug(m),
        instantiateWasm(imports, receive) {
          const instance = new WebAssembly.Instance(compiled, imports);
          const memory = Object.values(instance.exports).find(value => value instanceof WebAssembly.Memory);
          // The session JS binding accesses Module.HEAPU8, which recent
          // Emscripten no longer exports by default. Expose a current view.
          Object.defineProperty(options, 'HEAPU8', { get: () => new Uint8Array(memory.buffer) });
          receive(instance); return instance.exports;
        },
      };
      runtime = await whisper_factory(options); return runtime;
    })();
  }
  return runtimeReady;
}
async function transformers() {
  if (!pipeline) {
    const module = await import('../vendor/transformers.web.js');
    module.env.allowLocalModels = false;
    module.env.useBrowserCache = true;
    module.env.backends.onnx.wasm.wasmPaths = new URL('../vendor/ort/', self.location.href).href;
    module.env.backends.onnx.wasm.numThreads = 1;
    transformerEnv = module.env;
    pipeline = module.pipeline;
  }
  return pipeline;
}
async function load(engine, selected, allowDownloads, id, bytes, allowExperimentalModels = false) {
  const model = (await catalogue(engine)).find(m => m.id === selected);
  if (!model) throw new Error('Unknown browser model: ' + selected);
  if (model.experimental && !allowExperimentalModels) throw new Error('This model is filtered out for browsers. Enable experimental browser models in Settings after accepting the warning.');
  if (modelId === selected) return true;
  modelId = null;
  if (engine === 'crispasr') {
    const m = await crisp();
    if (!m.availableBackends().split(',').map(x => x.trim()).includes(model.backend)) throw new Error('This backend is not compiled into the browser runtime: ' + model.backend);
    const data = bytes || await modelBytes(model.url, allowDownloads, id);
    m.asrClose();
    for (const companion of model.companions || []) {
      const contents = await modelBytes(companion.url, allowDownloads, id);
      try { m.FS_unlink(companion.path); } catch (_) {}
      m.FS_createDataFile('/', companion.path.slice(1), contents, true, true);
    }
    try { m.FS_unlink('/model.bin'); } catch (_) {}
    m.FS_createDataFile('/', 'model.bin', data, true, true, true);
    try {
      if (!m.asrOpen('/model.bin', model.backend, 1)) throw new Error('CrispASR could not open this model');
    } finally { m.FS_unlink('/model.bin'); }
  } else {
    const factory = await transformers();
    transformerEnv.allowLocalModels = !allowDownloads;
    transformerEnv.allowRemoteModels = allowDownloads;
    await asr?.dispose(); asr = null;
    asr = await factory('automatic-speech-recognition', model.repo, {
      device: 'wasm', dtype: 'q8', local_files_only: !allowDownloads,
      progress_callback: data => { if (data.progress != null) progress(id, data.progress / 100 * 0.85); },
    });
  }
  modelId = selected; progress(id, 1); return true;
}
async function transcribe(engine, audio, options, id) {
  if (!modelId) throw new Error('Load a speech model first');
  if (!audio.length) throw new Error('Audio is empty');
  if (audio.length > 16000 * 1800) throw new Error('Browser transcription supports up to 30 minutes per file');
  if (options.diarize) throw new Error('Speaker diarization is not supported by these browser models');
  const segments = [];
  const selected = (await catalogue(engine)).find(m => m.id === modelId);
  if (options.translate && selected.backend !== 'whisper') throw new Error('This browser model does not support speech translation');
  if (engine === 'crispasr') {
    runtime.asrSetTranslate(!!options.translate);
    runtime.asrSetSourceLanguage(options.language || 'auto');
    // Bounded windows prevent long recordings from retaining a large encoder graph.
    const size = 16000 * 30;
    for (let offset = 0; offset < audio.length; offset += size) {
      for (const segment of runtime.asrTranscribe(audio.subarray(offset, offset + size), options.language || '')) {
        segments.push({ text: segment.text, start: segment.t0 / 100 + offset / 16000, end: segment.t1 / 100 + offset / 16000 });
      }
      progress(id, Math.min(0.99, (offset + size) / audio.length));
    }
  } else {
    const selected = (await catalogue(engine)).find(m => m.id === modelId);
    if (selected.backend !== 'whisper') {
      if (options.translate) throw new Error('This browser model does not support speech translation');
      // Moonshine does not return token timestamps. Keep honest chunk boundaries.
      for (let offset = 0; offset < audio.length; offset += 16000 * 15) {
        const window = audio.subarray(offset, offset + 16000 * 15);
        const result = await asr(window, { max_new_tokens: 128 });
        if (result.text) segments.push({ text: result.text, start: offset / 16000, end: (offset + window.length) / 16000 });
        progress(id, Math.min(0.99, (offset + window.length) / audio.length));
      }
      return { segments, model: modelId, engine, local: true, timestampPrecision: 'chunk' };
    }
    const args = { return_timestamps: true, chunk_length_s: 30, stride_length_s: 5 };
    if (!modelId.endsWith('.en')) {
      if (options.language && options.language !== 'auto') args.language = options.language;
      args.task = options.translate ? 'translate' : 'transcribe';
    } else if (options.translate) throw new Error('Use a multilingual model for translation');
    const result = await asr(audio, args);
    for (const chunk of result.chunks || []) segments.push({ text: chunk.text, start: chunk.timestamp[0] || 0,
      end: chunk.timestamp[1] ?? audio.length / 16000 });
    if (!segments.length && result.text) segments.push({ text: result.text, start: 0, end: audio.length / 16000 });
  }
  progress(id, 1); return { segments, model: modelId, engine, local: true };
}
async function synthesize(payload, allowDownloads, id) {
  const m = await crisp();
  if (!ttsReady) {
    const resources = [
      ['/tts.gguf', 'https://huggingface.co/cstr/kokoro-82m-GGUF/resolve/main/kokoro-82m-q8_0.gguf'],
      ['/voice.gguf', 'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main/kokoro-voice-af_heart.gguf'],
      ['/home/web_user/.cache/crispasr/cmudict.dict', 'https://huggingface.co/datasets/cstr/g2p-dicts/resolve/main/cmudict.dict'],
    ];
    for (const [path, url] of resources) {
      const bytes = await modelBytes(url, allowDownloads, id);
      const slash = path.lastIndexOf('/'), dir = path.slice(0, slash) || '/';
      m.FS_createPath('/', dir, true, true);
      try { m.FS_unlink(path); } catch (_) {}
      m.FS_createDataFile(dir, path.slice(slash + 1), bytes, true, true);
    }
    if (!m.ttsOpenExplicit('/tts.gguf', 'kokoro', 1)) throw new Error('Could not load the browser TTS model');
    if (m.ttsSetVoice('/voice.gguf', '') !== 0) throw new Error('Could not load the browser voice');
    ttsReady = true;
  }
  if (!payload.text?.trim() || payload.text.length > 1000) throw new Error('Enter between 1 and 1000 characters');
  const audio = Float32Array.from(m.ttsSynthesize(payload.text));
  if (!audio.length) throw new Error('Synthesis returned no audio');
  return { audio, sampleRate: m.sessionOutputSampleRate() || 24000, local: true };
}
async function handle({ id, op, payload, engine, allowDownloads, allowExperimentalModels = false }) {
  let result;
  if (op === 'models') {
    const cache = await caches.open(CACHE);
    const onnxCache = await caches.open('transformers-cache');
    const models = (await catalogue(engine)).filter(m => !m.experimental || allowExperimentalModels);
    result = await Promise.all(models.map(async m => ({ ...m,
      cached: m.url ? !!(await cache.match(m.url)) && (await Promise.all((m.companions || []).map(c => cache.match(c.url)))).every(Boolean) : !!(await onnxCache.match('https://huggingface.co/' + m.repo + '/resolve/main/onnx/encoder_model_quantized.onnx'))
        && !!(await onnxCache.match('https://huggingface.co/' + m.repo + '/resolve/main/onnx/decoder_model_merged_quantized.onnx')) })));
  } else if (op === 'load') result = await load(engine, payload.model, allowDownloads, id, payload.bytes, allowExperimentalModels);
  else if (op === 'import') {
    if (engine !== 'crispasr') throw new Error('Import is currently supported for CrispASR model files');
    const model = (await catalogue(engine)).find(m => m.id === payload.model);
    if (!model) throw new Error('Unknown model');
    await load(engine, payload.model, false, id, payload.bytes, allowExperimentalModels);
    await (await caches.open(CACHE)).put(model.url, new Response(payload.bytes)); result = true;
  } else if (op === 'transcribe') {
    const selected = (await catalogue(engine)).find(m => m.id === modelId);
    if (selected?.experimental && !allowExperimentalModels) throw new Error('This model is filtered out. Enable experimental browser models in Settings after accepting the warning.');
    result = await transcribe(engine, payload.audio, payload, id);
  }
  else if (op === 'synthesize') result = await synthesize(payload, allowDownloads, id);
  else if (op === 'unload') {
    runtime?.asrClose(); await asr?.dispose(); asr = null; modelId = null; result = true;
  } else throw new Error('Unknown browser speech operation');
  postMessage({ id, result });
}
let queue = Promise.resolve();
self.onmessage = ({ data }) => {
  queue = queue.then(() => handle(data)).catch(error => postMessage({ id: data.id, error: error.message || String(error) }));
};
