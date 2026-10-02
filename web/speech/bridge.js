// A client owns its worker: terminating it cancels blocked WASM computation
// and rejects every outstanding operation rather than leaving promises hanging.
(() => {
  class Client {
    constructor(engine, allowDownloads = true) {
      if (!['crispasr', 'onnx'].includes(engine)) throw new Error('Unknown browser speech engine');
      this.engine = engine; this.allowDownloads = allowDownloads;
      this.pending = new Map(); this.sequence = 0; this.worker = null;
      this.loadedModel = null;
      this.loadedPreference = null;
      this.loadedCpuThreads = null;
      this.loadedLowHeap = null;
    }
    request(op, payload = {}, progress, forcedPreference, forcedThreads) {
      const executionPreference = forcedPreference || localStorage.getItem('flutter.browser_execution_provider')?.replaceAll('"', '') || 'wasm';
      const requestedThreads = forcedThreads ?? Number(localStorage.getItem('flutter.browser_cpu_threads') || 1);
      const cpuThreads = this.engine === 'crispasr' && !['models', 'clearCache', 'deleteCache', 'unload'].includes(op) && crossOriginIsolated && typeof SharedArrayBuffer !== 'undefined'
        ? ([2, 4].includes(requestedThreads) ? requestedThreads : 1) : 1;
      const lowHeap = localStorage.getItem('cw.browserLowMemoryRuntime') === 'true';
      if (op === 'unload') { this.cancel(); return Promise.resolve(true); }
      if (['load', 'import'].includes(op) && (payload.model !== this.loadedModel || executionPreference !== this.loadedPreference || cpuThreads !== this.loadedCpuThreads || lowHeap !== this.loadedLowHeap)) this.cancel();
      if (!this.worker) {
        const workerUrl = new URL('speech/worker.js', document.baseURI);
        if (lowHeap) workerUrl.searchParams.set('heap', 'small');
        if (cpuThreads > 1) { workerUrl.searchParams.set('runtime', 'threaded'); workerUrl.searchParams.set('threads', String(cpuThreads)); }
        this.worker = new Worker(workerUrl);
        this.worker.onmessage = ({ data }) => {
          const entry = this.pending.get(data.id);
          if (!entry) return;
          if (data.progress != null) { entry.progress?.(data.progress); return; }
          clearTimeout(entry.timer); this.pending.delete(data.id);
          if (data.error) { if (!this.retryGpuInference(entry, data.error) && !this.retryCpu(entry, data.error)) entry.reject(new Error(data.error)); }
          else {
            if (entry.model) { this.loadedModel = entry.model; this.loadedPreference = entry.preference; this.loadedCpuThreads = entry.cpuThreads; this.loadedLowHeap = entry.lowHeap; }
            if (data.result?.diagnostics) {
              const measurement = data.result.diagnostics;
              measurement.observedJsHeapBytes = performance.memory?.usedJSHeapSize ?? null;
              try {
                const parsed = JSON.parse(localStorage.getItem('cw.browserMeasurements') || '[]');
                const previous = Array.isArray(parsed) ? parsed : [];
                localStorage.setItem('cw.browserMeasurements', JSON.stringify([...previous.slice(-19), measurement]));
              } catch (_) {}
            }
            if (entry.op === 'models') {
              let measurements = [];
              try { const parsed = JSON.parse(localStorage.getItem('cw.browserMeasurements') || '[]'); if (Array.isArray(parsed)) measurements = parsed; } catch (_) {}
              data.result = data.result.map(model => ({ ...model, observedWasmBytes: measurements.filter(m => m?.model === model.id).reduce((max, m) => Math.max(max, m.peakWasmBytes || 0), 0) || null }));
            }
            entry.resolve(data.result);
          }
        };
        this.worker.onerror = e => {
          const reason = e.message || 'Browser speech worker failed';
          const entry = Array.from(this.pending.values()).find(item => item.op === 'load');
          if (entry) {
            const key = Array.from(this.pending.entries()).find(([, value]) => value === entry)?.[0];
            this.pending.delete(key);
            if (this.retryCpu(entry, reason)) return;
            clearTimeout(entry.timer); entry.reject(new Error(reason));
          }
          this.cancel(reason);
        };
      }
      const id = ++this.sequence;
      // Preserve one bounded audio copy only when GPU inference may need a
      // fresh-worker CPU retry; CPU requests retain the zero-copy path.
      if (this.engine === 'onnx' && op === 'transcribe' && this.loadedPreference !== 'wasm' && payload.audio instanceof Float32Array) payload = { ...payload, audio: payload.audio.slice(), transferAudio: false };
      return new Promise((resolve, reject) => {
        // The main thread can terminate a GPU initialization that blocks its
        // worker event loop. A worker-local Promise timeout cannot do that.
        const retryCpu = this.engine === 'onnx' && op === 'load' && executionPreference !== 'wasm';
        const retrySingle = this.engine === 'crispasr' && op === 'load' && cpuThreads > 1;
        const timer = setTimeout(() => {
          if (!retryCpu && !retrySingle) { this.cancel('Browser inference timed out'); return; }
          const entry = this.pending.get(id);
          if (!entry) return;
          this.pending.delete(id);
          this.retryCpu(entry, 'Parallel runtime stalled; worker restarted with single-thread CPU');
        }, (retryCpu || retrySingle) ? 120000 : 900000);
        this.pending.set(id, { resolve, reject, progress, timer, op, payload, cpuThreads, lowHeap, preference: executionPreference, model: ['load', 'import'].includes(op) ? payload.model : null });
        const allowExperimentalModels = localStorage.getItem('flutter.browser_allow_experimental_models') === 'true';
        const transfer = [];
        if (payload.audio instanceof Float32Array) {
          // Only detach explicitly owned buffers. Other callers keep their
          // input; one bounded copy is transferred instead of cloned again.
          const input = payload.audio;
          const owned = payload.transferAudio === true && input.buffer instanceof ArrayBuffer && !input.buffer.resizable;
          const audio = owned ? input : input.slice();
          payload = { ...payload, audio }; transfer.push(audio.buffer);
        }
        this.worker.postMessage({ id, op, payload: { ...payload, executionPreference }, engine: this.engine, allowDownloads: this.allowDownloads, allowExperimentalModels }, transfer);
      });
    }
    retryGpuInference(entry, reason) {
      if (entry.op !== 'transcribe' || !reason.startsWith('CW_GPU_RESTART: ') || !this.loadedModel) return false;
      const model = this.loadedModel;
      clearTimeout(entry.timer);
      this.cancel('Restarting failed GPU inference on local CPU');
      this.request('load', { model }, entry.progress, 'wasm', 1).then(() =>
        this.request('transcribe', entry.payload, entry.progress, 'wasm', 1)
      ).then(result => {
        if (result?.diagnostics) result.diagnostics.fallbackReason = reason.slice(16);
        entry.resolve(result);
      }, entry.reject);
      return true;
    }
    retryCpu(entry, reason) {
      if (entry.op !== 'load' || !(this.engine === 'onnx' && entry.preference !== 'wasm' || this.engine === 'crispasr' && entry.cpuThreads > 1)) return false;
      clearTimeout(entry.timer);
      this.cancel('Restarting model load with single-thread CPU');
      this.request('load', entry.payload, entry.progress, 'wasm', 1).then(result => {
        if (result?.diagnostics) result.diagnostics.fallbackReason = reason;
        entry.resolve(result);
      }, entry.reject);
      return true;
    }
    cancel(message = 'Browser inference cancelled') {
      this.worker?.terminate(); this.worker = null;
      this.loadedModel = null;
      this.loadedPreference = null;
      this.loadedCpuThreads = null;
      this.loadedLowHeap = null;
      for (const entry of this.pending.values()) { clearTimeout(entry.timer); entry.reject(new Error(message)); }
      this.pending.clear();
    }
    dispose() { this.cancel(); }
  }
  async function decode(bytes) {
    const context = new AudioContext();
    try {
      const decoded = await context.decodeAudioData(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      const length = Math.ceil(decoded.duration * 16000);
      const offline = new OfflineAudioContext(1, length, 16000);
      const source = offline.createBufferSource(); source.buffer = decoded; source.connect(offline.destination); source.start();
      return (await offline.startRendering()).getChannelData(0).slice();
    } finally { await context.close(); }
  }
  const audioUrl = bytes => URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' }));
  const fetchBytes = async url => {
    const parsed = new URL(url, document.baseURI);
    if (!['https:', 'http:', 'blob:'].includes(parsed.protocol)) throw new Error('Unsupported audio URL');
    const result = await fetch(parsed, { credentials: 'omit' });
    if (!result.ok) throw new Error(`Audio download failed: HTTP ${result.status}`);
    return new Uint8Array(await result.arrayBuffer());
  };
  const download = (url, filename) => {
    const link = document.createElement('a'); link.href = url; link.download = filename; link.click();
  };
  const history = async (op, key, value) => {
    const database = await new Promise((resolve, reject) => {
      const request = indexedDB.open('crisperweaver-history-v1', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('entries');
      request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
    });
    try {
      return await new Promise((resolve, reject) => {
        const tx = database.transaction('entries', ['get', 'list'].includes(op) ? 'readonly' : 'readwrite');
        const store = tx.objectStore('entries'); let request;
        if (op === 'get') request = store.get(key);
        else if (op === 'list') request = store.getAll();
        else if (op === 'put') request = store.put(value, key);
        else if (op === 'delete') request = store.delete(key);
        else if (op === 'clear') request = store.clear();
        else { reject(new Error('Unknown browser history operation')); return; }
        tx.oncomplete = () => resolve(request.result ?? null);
        tx.onerror = () => reject(tx.error); tx.onabort = () => reject(tx.error || new Error('History transaction aborted'));
      });
    } finally { database.close(); }
  };
  globalThis.CrisperBrowserSpeech = { create: (engine, downloads) => new Client(engine, downloads),
    decode, fetchBytes, audioUrl, download, history, revokeUrl: url => URL.revokeObjectURL(url) };
})();
