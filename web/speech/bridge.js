// A client owns its worker: terminating it cancels blocked WASM computation
// and rejects every outstanding operation rather than leaving promises hanging.
(() => {
  class Client {
    constructor(engine, allowDownloads = true) {
      if (!['crispasr', 'onnx'].includes(engine)) throw new Error('Unknown browser speech engine');
      this.engine = engine; this.allowDownloads = allowDownloads;
      this.pending = new Map(); this.sequence = 0; this.worker = null;
    }
    request(op, payload = {}, progress) {
      if (!this.worker) {
        this.worker = new Worker(new URL('speech/worker.js', document.baseURI));
        this.worker.onmessage = ({ data }) => {
          const entry = this.pending.get(data.id);
          if (!entry) return;
          if (data.progress != null) { entry.progress?.(data.progress); return; }
          clearTimeout(entry.timer); this.pending.delete(data.id);
          if (data.error) entry.reject(new Error(data.error)); else entry.resolve(data.result);
        };
        this.worker.onerror = e => this.cancel(e.message || 'Browser speech worker failed');
      }
      const id = ++this.sequence;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => this.cancel('Browser inference timed out'), 900000);
        this.pending.set(id, { resolve, reject, progress, timer });
        this.worker.postMessage({ id, op, payload, engine: this.engine, allowDownloads: this.allowDownloads });
      });
    }
    cancel(message = 'Browser inference cancelled') {
      this.worker?.terminate(); this.worker = null;
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
