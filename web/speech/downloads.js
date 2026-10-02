// Verified, resumable model downloads. Only immutable, locked resources reach
// this downloader. IndexedDB checkpoints survive worker termination/restarts.
(() => {
  const CACHE = 'crisperweaver-speech-models-v2', PART = 4 * 1024 * 1024;
  let database, hashing;
  const hash = async () => (hashing ||= import('../vendor/sha256.js')).then(m => m.sha256.create());
  const hex = bytes => Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  function db() {
    return database ||= new Promise((resolve, reject) => {
      const request = indexedDB.open('crisperweaver-model-downloads-v1', 1);
      request.onupgradeneeded = () => {
        request.result.createObjectStore('meta'); request.result.createObjectStore('parts');
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  async function transaction(stores, mode, action) {
    const connection = await db();
    return new Promise((resolve, reject) => {
      const tx = connection.transaction(stores, mode), request = action(tx);
      tx.oncomplete = () => resolve(request?.result);
      tx.onerror = tx.onabort = () => reject(tx.error || new Error('Model storage transaction failed'));
    });
  }
  const meta = url => transaction(['meta'], 'readonly', tx => tx.objectStore('meta').get(url));
  const range = url => IDBKeyRange.bound([url, 0], [url, Number.MAX_SAFE_INTEGER]);
  async function discard(url) {
    await transaction(['meta', 'parts'], 'readwrite', tx => {
      tx.objectStore('meta').delete(url); tx.objectStore('parts').delete(range(url));
    });
  }
  async function checkpoint(resource, bytes, from, end) {
    await transaction(['meta', 'parts'], 'readwrite', tx => {
      tx.objectStore('parts').put(bytes.slice(from, end), [resource.url, Math.floor(from / PART)]);
      tx.objectStore('meta').put({ url: resource.url, sha256: resource.sha256, size: resource.size, offset: end }, resource.url);
    });
  }
  async function cached(resource) {
    const response = await (await caches.open(CACHE)).match(resource.url);
    if (response?.headers.get('x-cw-sha256') === resource.sha256 && Number(response.headers.get('content-length')) === resource.size) return response;
    if (response) await (await caches.open(CACHE)).delete(resource.url);
    return undefined;
  }
  async function verify(resource, bytes) {
    if (bytes.length !== resource.size) throw new Error('Model size mismatch: ' + resource.url);
    const digest = await hash(); digest.update(bytes);
    if (hex(digest.digest()) !== resource.sha256) throw new Error('Model checksum mismatch: ' + resource.url);
  }
  async function verifiedResponse(resource) {
    const response = await cached(resource);
    if (!response) return undefined;
    const digest = await hash(); let length = 0;
    return new Response(response.body.pipeThrough(new TransformStream({
      transform(chunk, controller) { length += chunk.length; digest.update(chunk); controller.enqueue(chunk); },
      async flush() {
        if (length !== resource.size || hex(digest.digest()) !== resource.sha256) {
          await (await caches.open(CACHE)).delete(resource.url);
          throw new Error('Cached model checksum mismatch; corrupt cache was removed.');
        }
      },
    })), { headers: response.headers });
  }
  async function put(resource, bytes) {
    await verify(resource, bytes);
    await (await caches.open(CACHE)).put(resource.url, new Response(bytes, { headers: {
      'content-length': String(bytes.length), 'x-cw-sha256': resource.sha256,
    } }));
  }
  async function readLocked(resource, downloads, progress = () => {}, networkFetch = fetch) {
    const existing = await cached(resource);
    if (existing) {
      const bytes = new Uint8Array(await existing.arrayBuffer());
      try { await verify(resource, bytes); return bytes; }
      catch (error) {
        await (await caches.open(CACHE)).delete(resource.url);
        // Corrupt data never reaches inference. A subsequent user retry can
        // redownload, but this request explicitly reports the failed check.
        throw error;
      }
    }
    if (!downloads) throw new Error('Model downloads are disabled. Download or import this model first.');
    if (!Number.isSafeInteger(resource.size) || resource.size <= 0 || !/^[a-f0-9]{64}$/.test(resource.sha256)) throw new Error('Model has no valid size/checksum lock');
    const storage = await navigator.storage?.estimate?.();
    if (storage?.quota && storage.quota - storage.usage < resource.size * 2) throw new Error('Not enough browser storage for a resumable download and verified cache. Delete cached models or incomplete downloads first.');
    let saved = await meta(resource.url);
    if (saved && (saved.sha256 !== resource.sha256 || saved.size !== resource.size || saved.offset > resource.size)) { await discard(resource.url); saved = null; }
    let offset = saved?.offset || 0;
    const bytes = new Uint8Array(resource.size);
    let digest = await hash();
    for (let index = 0, position = 0; position < offset; index++) {
      const part = await transaction(['parts'], 'readonly', tx => tx.objectStore('parts').get([resource.url, index]));
      if (!part || part.length !== Math.min(PART, offset - position)) { await discard(resource.url); throw new Error('Incomplete download checkpoint is corrupt; retry the download.'); }
      bytes.set(part, position); digest.update(part); position += part.length;
    }
    let checkpointStart = offset;
    progress(offset / resource.size);
    if (offset < resource.size) {
      const response = await networkFetch(resource.url, { credentials: 'omit', cache: 'no-store', headers: offset ? { Range: `bytes=${offset}-` } : {} });
      if (offset && response.status === 200) {
        // Server ignored Range: replace, never append a complete response.
        await discard(resource.url); offset = checkpointStart = 0; digest = await hash();
      } else if (offset) {
        const contentRange = response.headers.get('content-range');
        if (response.status !== 206 || contentRange !== `bytes ${offset}-${resource.size - 1}/${resource.size}`) throw new Error('Server returned an invalid download range; saved progress was retained.');
      }
      if (!response.ok) throw new Error(`Model download failed: HTTP ${response.status}`);
      const reader = response.body.getReader();
      try {
        while (true) {
          const { done, value } = await reader.read(); if (done) break;
          if (offset + value.length > resource.size) throw new Error('Model response exceeds its locked size');
          bytes.set(value, offset); digest.update(value); offset += value.length;
          while (offset - checkpointStart >= PART) {
            await checkpoint(resource, bytes, checkpointStart, checkpointStart + PART); checkpointStart += PART;
          }
          progress(offset / resource.size);
        }
      } catch (error) {
        await reader.cancel().catch(() => {});
        throw error;
      }
      if (offset !== resource.size) throw new Error('Model download was interrupted; retry to resume saved progress.');
      if (checkpointStart < offset) await checkpoint(resource, bytes, checkpointStart, offset);
    }
    if (hex(digest.digest()) !== resource.sha256) { await discard(resource.url); throw new Error('Model checksum mismatch; incomplete download was removed.'); }
    // Stream checkpointed parts into CacheStorage instead of cloning another
    // complete large buffer during promotion to the verified cache.
    let index = 0, position = 0;
    const stream = new ReadableStream({ async pull(controller) {
      try {
        if (position === resource.size) { controller.close(); return; }
        const part = await transaction(['parts'], 'readonly', tx => tx.objectStore('parts').get([resource.url, index++]));
        if (!part) throw new Error('Download checkpoint disappeared');
        position += part.length; controller.enqueue(part);
      } catch (error) { controller.error(error); }
    } });
    await (await caches.open(CACHE)).put(resource.url, new Response(stream, { headers: {
      'content-length': String(resource.size), 'x-cw-sha256': resource.sha256,
    } }));
    await discard(resource.url);
    return bytes;
  }
  const guarded = (name, mode, action) => navigator.locks
    ? navigator.locks.request(name, { mode }, action) : action();
  const read = (resource, ...args) => guarded('cw.model-storage', 'shared', () =>
    guarded('cw.model:' + resource.url, 'exclusive', () => readLocked(resource, ...args)));
  async function remove(resources) {
    const cache = await caches.open(CACHE);
    for (const resource of resources) { await cache.delete(resource.url); await discard(resource.url); }
  }
  async function stats() {
    const estimate = await navigator.storage?.estimate?.() || {};
    const incomplete = await transaction(['meta'], 'readonly', tx => tx.objectStore('meta').getAll());
    return { usage: estimate.usage ?? null, quota: estimate.quota ?? null, persistent: await navigator.storage?.persisted?.() || false,
      incompleteBytes: incomplete.reduce((sum, part) => sum + part.offset, 0), incompleteCount: incomplete.length };
  }
  async function clearIncomplete() {
    await transaction(['meta', 'parts'], 'readwrite', tx => { tx.objectStore('meta').clear(); tx.objectStore('parts').clear(); });
  }
  async function clear() {
    await clearIncomplete();
    for (const name of [CACHE, 'crisperweaver-speech-models-v1', 'transformers-cache']) await caches.delete(name);
  }
  globalThis.CW_DOWNLOADS = { read, cached, verifiedResponse, verify, put,
    remove: resources => guarded('cw.model-storage', 'exclusive', () => remove(resources)), stats,
    clear: () => guarded('cw.model-storage', 'exclusive', clear),
    clearIncomplete: () => guarded('cw.model-storage', 'exclusive', clearIncomplete), meta, CACHE };
})();
