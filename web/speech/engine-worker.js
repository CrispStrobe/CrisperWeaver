// All processing happens in this worker; network requests only retrieve models.
importScripts('./catalog.js');
importScripts('./chunks.js', './downloads.js');
const networkFetch = self.fetch.bind(self);
let lockReady, locks, downloadsAllowed = true, downloadProgress = () => {};
async function lock() {
  if (!lockReady) lockReady = (async () => {
    const response = await networkFetch(new URL('./model-lock.json', self.location.href));
    if (!response.ok) throw new Error('Model integrity lock is unavailable');
    locks = (await response.json()).repositories;
  })();
  await lockReady;
}
async function resource(url) {
  await lock();
  const match = /^https:\/\/huggingface.co\/(datasets\/)?([^/]+\/[^/]+)\/resolve\/([^/]+)\/(.+)$/.exec(url);
  if (!match) throw new Error('Unrecognized model download URL');
  const repo = locks[(match[1] || '') + match[2]], file = decodeURIComponent(match[4]);
  if (!repo || !repo.files[file] || !['main', repo.revision].includes(decodeURIComponent(match[3]))) throw new Error('Model resource is not in the integrity lock');
  return repo.files[file];
}
// Transformers.js 3.8.1 uses global fetch. Route its model requests through
// the same verified/resumable downloader; unknown optional files are 404.
self.fetch = async (input, options) => {
  const url = String(input instanceof Request ? input.url : input);
  if (!url.startsWith('https://huggingface.co/')) {
    const parsed = new URL(url, self.location.href);
    if (parsed.origin !== self.location.origin) throw new Error('Speech workers only retrieve locked models and self-hosted runtimes');
    return networkFetch(input, options);
  }
  if ((options?.method || 'GET') !== 'GET') throw new Error('Model hosts only accept downloads');
  let file;
  try { file = await resource(url); } catch (_) { return new Response('', { status: 404 }); }
  await CW_DOWNLOADS.ensure(file, downloadsAllowed, downloadProgress, networkFetch);
  return CW_DOWNLOADS.verifiedResponse(file);
};
const runtimeParameters = new URL(self.location.href).searchParams;
const threaded = runtimeParameters.get('runtime') === 'threaded';
const cpuThreads = threaded ? Math.max(2, Math.min(4, Number(runtimeParameters.get('threads')) || 4)) : 1;
let runtime, runtimeReady, pipeline, transformerEnv, asr, modelId, ttsReady = false;
let provider = 'wasm', fallbackReason = '', activeModel, executionPreference = 'wasm', diagnostics;
const sampleMemory = () => {
  if (diagnostics && runtime) diagnostics.peakWasmBytes = Math.max(diagnostics.peakWasmBytes || 0, runtime.HEAPU8.byteLength);
};
const progress = (id, value) => { sampleMemory(); postMessage({ id, progress: value }); };
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
  await lock();
  return Promise.all(CW_SPEECH_MODELS[engine].map(async m => ({ ...m,
    ...(m.url ? { url: (await resource(m.url)).url, sizeBytes: (await resource(m.url)).size,
      companions: await Promise.all((m.companions || []).map(async c => ({ ...c, url: (await resource(c.url)).url }))) }
      : { revision: locks[m.repo].revision }),
    experimental: !m.recommended,
    browserReason: m.recommended ? 'Small model supported by the browser adapter.'
      : 'Not validated in this browser. May require unsupported features or more memory than the browser can allocate.',
  })));
}

async function modelBytes(url, allowDownloads, id) {
  return CW_DOWNLOADS.read(await resource(url), allowDownloads, value => progress(id, value * 0.85), networkFetch);
}
async function modelResources(model) {
  if (model.url) return Promise.all([model.url, ...(model.companions || []).map(c => c.url)].map(resource));
  return Object.values(locks[model.repo].files);
}
async function modelCached(model, device = 'wasm') {
  const files = await modelResources(model);
  // Optional ONNX configuration files do not determine model readiness.
  const required = model.url ? files : files.filter(file => (device === 'webgpu' ? /onnx\/(encoder_model|decoder_model_merged)\.onnx$/ : /onnx\/(encoder_model_quantized|decoder_model_merged_quantized)\.onnx$/).test(file.url));
  return required.length > 0 && (await Promise.all(required.map(file => CW_DOWNLOADS.cached(file)))).every(Boolean);
}
async function crisp() {
  if (!runtimeReady) {
    runtimeReady = (async () => {
      const directory = threaded ? '../wasm/crispasr-threaded/' : runtimeParameters.get('heap') === 'small' ? '../wasm/crispasr-small/' : '../wasm/crispasr/';
      importScripts(new URL(directory + 'libwhisper.js', self.location.href).href);
      const url = new URL(directory + 'libwhisper.wasm', self.location.href);
      const response = await fetch(url);
      if (!response.ok) throw new Error(`Speech runtime unavailable: HTTP ${response.status}`);
      const compiled = await WebAssembly.compile(await response.arrayBuffer());
      const options = { locateFile: file => new URL(directory + file, self.location.href).href, print: () => {}, printErr: m => console.debug(m),
        instantiateWasm(imports, receive) {
          const instance = new WebAssembly.Instance(compiled, imports);
          const memory = Object.values(instance.exports).find(value => value instanceof WebAssembly.Memory)
            || Object.values(imports).flatMap(namespace => Object.values(namespace)).find(value => value instanceof WebAssembly.Memory);
          if (!memory) throw new Error('Speech runtime did not expose its memory');
          // The session JS binding accesses Module.HEAPU8, which recent
          // Emscripten no longer exports by default. Expose a current view.
          Object.defineProperty(options, 'HEAPU8', { get: () => new Uint8Array(memory.buffer) });
          receive(instance, compiled); return instance.exports;
        },
      };
      runtime = await whisper_factory(options);
      if (threaded) {
        const deadline = performance.now() + 15000;
        while (!runtime.browserComputeReady?.()) {
          if (performance.now() > deadline) throw new Error('Threaded compute startup timed out');
          await new Promise(resolve => setTimeout(resolve, 10));
        }
      }
      return runtime;
    })();
  }
  return runtimeReady;
}
async function nativeCall(module, operation, ...args) {
  if (!threaded) return module[operation](...args);
  const method = module[operation + 'Async'];
  if (!method) throw new Error('Threaded runtime lacks async ' + operation);
  return new Promise((resolve, reject) => method(...args, result => {
    if (result?.error) reject(new Error(result.error)); else resolve(result);
  }));
}
// Start the pthread pool outside any message handler. A rejected startup is
// reported when inference requests await it, without an unhandled rejection.
if (threaded) crisp().catch(() => {});

async function transformers() {
  if (!pipeline) {
    const module = await import('../vendor/transformers.web.js');
    module.env.allowLocalModels = false;
    module.env.useBrowserCache = true;
    module.env.useCustomCache = true;
    module.env.customCache = {
      async match(url) {
        try { return await CW_DOWNLOADS.verifiedResponse(await resource(String(url))); }
        catch (_) { return undefined; }
      },
      async put(url, response) {
        const file = await resource(String(url));
        // The fetch adapter already verified and stored downloaded files.
        if (!(await CW_DOWNLOADS.cached(file))) await CW_DOWNLOADS.put(file, new Uint8Array(await response.arrayBuffer()));
      },
    };
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
  activeModel = model;
  diagnostics.cachedLoad = await modelCached(model);
  downloadsAllowed = allowDownloads;
  downloadProgress = value => progress(id, value * 0.85);
  if (engine === 'crispasr') {
    provider = 'wasm'; fallbackReason = '';
    const m = await crisp();
    if (!m.availableBackends().split(',').map(x => x.trim()).includes(model.backend)) throw new Error('This backend is not compiled into the browser runtime: ' + model.backend);
    const data = bytes || await modelBytes(model.url, allowDownloads, id);
    m.asrClose();
    for (const companion of model.companions || []) {
      const contents = await modelBytes(companion.url, allowDownloads, id);
      try { m.FS_unlink(companion.path); } catch (_) {}
      m.FS_createDataFile('/', companion.path.slice(1), contents, true, true, true);
    }
    try { m.FS_unlink('/model.bin'); } catch (_) {}
    m.FS_createDataFile('/', 'model.bin', data, true, true, true);
    try {
      if (bytes) await CW_DOWNLOADS.verify(await resource(model.url), bytes);
      if (!(await nativeCall(m, 'asrOpen', '/model.bin', model.backend, cpuThreads))) throw new Error('CrispASR could not open this model');
    } finally {
      m.FS_unlink('/model.bin');
      for (const companion of model.companions || []) m.FS_unlink(companion.path);
    }
  } else {
    await transformers();
    transformerEnv.allowLocalModels = !allowDownloads;
    transformerEnv.allowRemoteModels = allowDownloads;
    await asr?.dispose(); asr = null;
    provider = 'wasm'; fallbackReason = '';
    if (executionPreference !== 'wasm') {
      try {
        const adapter = navigator.gpu && await gpuDeadline(navigator.gpu.requestAdapter(), 8000, 'WebGPU adapter');
        if (!adapter) throw new Error('WebGPU is unavailable on this device');
        const adapterDescription = `${adapter.info?.architecture || ''} ${adapter.info?.description || ''}`;
        if (/swiftshader|software/i.test(adapterDescription)) throw new Error('Software WebGPU adapter is unreliable for speech models; using local CPU processing');
        diagnostics.cachedLoad = await modelCached(model, 'webgpu');
        asr = await gpuDeadline(onnxSession(model, 'webgpu', allowDownloads, id), 90000, 'WebGPU model initialization'); provider = 'webgpu';
      } catch (error) { fallbackReason = String(error.message || error).slice(0, 400); }
    }
    if (!asr) asr = await onnxSession(model, 'wasm', allowDownloads, id);
  }
  modelId = selected; progress(id, 1); return { loaded: true, local: true };
}
async function onnxSession(model, device, allowDownloads, id) {
  return pipeline('automatic-speech-recognition', model.repo, {
    device, dtype: device === 'webgpu' ? 'fp32' : 'q8', revision: model.revision, local_files_only: !allowDownloads,
    progress_callback: data => { if (data.progress != null) progress(id, data.progress / 100 * 0.85); },
  });
}
async function gpuDeadline(promise, milliseconds, label) {
  let timer, expired = false;
  const cleanup = promise.then(value => { if (expired) value?.dispose?.(); return value; });
  try {
    return await Promise.race([cleanup, new Promise((_, reject) => {
      timer = setTimeout(() => { expired = true; reject(new Error(label + ' timed out; using local CPU processing')); }, milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}
async function inferOnnx(audio, args, id) {
  try { return provider === 'webgpu' ? await gpuDeadline(asr(audio, args), 60000, 'WebGPU inference') : await asr(audio, args); }
  catch (error) {
    if (provider !== 'webgpu') throw error;
    // A failed GPU session can poison ORT's WASM state. The main bridge
    // retains GPU-request audio and retries in a fresh CPU worker.
    throw new Error('CW_GPU_RESTART: ' + String(error.message || error).slice(0, 400));
  }
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
    for (const window of CW_CHUNKS.plan(audio, selected.backend === 'moonshine' ? 15 : 30)) {
      const candidates = Array.from(await nativeCall(runtime, 'asrTranscribe', audio.subarray(window.start, window.end), options.language || ''),
        segment => ({ text: segment.text, start: segment.t0 / 100 + window.start / 16000, end: segment.t1 / 100 + window.start / 16000 }));
      CW_CHUNKS.append(segments, candidates, window);
      progress(id, Math.min(0.99, window.coreEnd / audio.length));
    }
  } else {
    const selected = (await catalogue(engine)).find(m => m.id === modelId);
    if (selected.backend !== 'whisper') {
      if (options.translate) throw new Error('This browser model does not support speech translation');
      // Moonshine does not return token timestamps. Keep honest chunk boundaries.
      for (const window of CW_CHUNKS.plan(audio, 15)) {
        const result = await inferOnnx(audio.subarray(window.start, window.end), { max_new_tokens: 128 }, id);
        CW_CHUNKS.append(segments, [{ text: result.text, start: window.start / 16000, end: window.end / 16000 }], window);
        progress(id, Math.min(0.99, window.coreEnd / audio.length));
      }
      return { segments, model: modelId, engine, local: true, timestampPrecision: 'chunk' };
    }
    const args = { return_timestamps: true, chunk_length_s: 30, stride_length_s: 5 };
    if (!modelId.endsWith('.en')) {
      if (options.language && options.language !== 'auto') args.language = options.language;
      args.task = options.translate ? 'translate' : 'transcribe';
    } else if (options.translate) throw new Error('Use a multilingual model for translation');
    for (const window of CW_CHUNKS.plan(audio)) {
      const result = await inferOnnx(audio.subarray(window.start, window.end), args, id);
      const candidates = (result.chunks || []).map(chunk => ({ text: chunk.text,
        start: (chunk.timestamp[0] || 0) + window.start / 16000,
        end: (chunk.timestamp[1] ?? (window.end - window.start) / 16000) + window.start / 16000 }));
      if (!candidates.length && result.text) candidates.push({ text: result.text, start: window.start / 16000, end: window.end / 16000 });
      CW_CHUNKS.append(segments, candidates, window);
      progress(id, Math.min(0.99, window.coreEnd / audio.length));
    }
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
      m.FS_createDataFile(dir, path.slice(slash + 1), bytes, true, true, true);
    }
    if (!(await nativeCall(m, 'ttsOpenExplicit', '/tts.gguf', 'kokoro', cpuThreads))) throw new Error('Could not load the browser TTS model');
    if (m.ttsSetVoice('/voice.gguf', '') !== 0) throw new Error('Could not load the browser voice');
    m.FS_unlink('/tts.gguf'); m.FS_unlink('/voice.gguf');
    ttsReady = true;
  }
  if (!payload.text?.trim() || payload.text.length > 1000) throw new Error('Enter between 1 and 1000 characters');
  const audio = Float32Array.from(await nativeCall(m, 'ttsSynthesize', payload.text));
  if (!audio.length) throw new Error('Synthesis returned no audio');
  return { audio, sampleRate: m.sessionOutputSampleRate() || 24000, local: true };
}
async function handle({ id, op, payload, engine, allowDownloads, allowExperimentalModels = false }) {
  const started = performance.now();
  diagnostics = { operation: op, model: payload.model || modelId, engine, peakWasmBytes: null };
  executionPreference = payload.executionPreference || 'wasm';
  let result;
  if (op === 'models') {
    const models = (await catalogue(engine)).filter(m => !m.experimental || allowExperimentalModels);
    result = await Promise.all(models.map(async m => ({ ...m, cached: await modelCached(m),
      resumeBytes: (await Promise.all((await modelResources(m)).map(file => CW_DOWNLOADS.meta(file.url)))).reduce((sum, part) => sum + (part?.verified ? 0 : part?.offset || 0), 0) })));
  } else if (op === 'load') result = await load(engine, payload.model, allowDownloads, id, payload.bytes, allowExperimentalModels);
  else if (op === 'import') {
    if (engine !== 'crispasr') throw new Error('Import is currently supported for CrispASR model files');
    const model = (await catalogue(engine)).find(m => m.id === payload.model);
    if (!model) throw new Error('Unknown model');
    await load(engine, payload.model, false, id, payload.bytes, allowExperimentalModels);
    await CW_DOWNLOADS.put(await resource(model.url), payload.bytes); result = true;
  } else if (op === 'transcribe') {
    const selected = (await catalogue(engine)).find(m => m.id === modelId);
    if (selected?.experimental && !allowExperimentalModels) throw new Error('This model is filtered out. Enable experimental browser models in Settings after accepting the warning.');
    result = await transcribe(engine, payload.audio, payload, id);
  }
  else if (op === 'synthesize') result = await synthesize(payload, allowDownloads, id);
  else if (op === 'unload') {
    runtime?.asrClose(); await asr?.dispose(); asr = null; modelId = null; result = true;
  } else if (op === 'storage') result = await CW_DOWNLOADS.stats();
  else if (op === 'delete') {
    const model = (await catalogue(engine)).find(m => m.id === payload.model);
    if (!model) throw new Error('Unknown browser model');
    await CW_DOWNLOADS.remove(await modelResources(model)); result = true;
  } else if (op === 'clearCache') { await CW_DOWNLOADS.clear(); result = true; }
  else if (op === 'clearIncomplete') { await CW_DOWNLOADS.clearIncomplete(); result = true; }
  else throw new Error('Unknown browser speech operation');
  sampleMemory();
  if (['load', 'transcribe', 'synthesize'].includes(op)) {
    diagnostics.elapsedMs = performance.now() - started;
    diagnostics.runtimeMode = engine === 'crispasr' ? (threaded ? 'threaded' : 'single') : 'onnx';
    diagnostics.cpuThreads = engine === 'crispasr' ? cpuThreads : 1;
    diagnostics.dtype = engine === 'onnx' ? (provider === 'webgpu' ? 'fp32' : 'q8') : null;
    diagnostics.provider = provider; diagnostics.fallbackReason = fallbackReason || null;
    if (op === 'transcribe') diagnostics.audioSeconds = payload.audio.length / 16000;
    result = { ...result, diagnostics };
  }
  const transfer = result?.audio?.buffer instanceof ArrayBuffer ? [result.audio.buffer] : [];
  postMessage({ id, result }, transfer);
}
let queue = Promise.resolve();
self.onmessage = ({ data }) => {
  queue = queue.then(() => handle(data)).catch(error => postMessage({ id: data.id, error: error.message || String(error) }));
};
