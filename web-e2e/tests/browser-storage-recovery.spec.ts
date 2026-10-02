import { test, expect } from '@playwright/test';
import { TARGET } from './target';
import { bootRuntime } from './runtime-page';
async function boot(page: any) {
  await bootRuntime(page);
  await page.addScriptTag({ url: `${TARGET}/speech/downloads.js` });
}
async function interrupt(page: any, name: string, fill: number) {
  await page.evaluate(async ({ name, fill }) => {
    const m = (window as any).CW_DOWNLOADS, bytes = new Uint8Array(8 * 1024 * 1024 + 13).fill(fill);
    const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), x => x.toString(16).padStart(2, '0')).join('');
    const resource = { url: `${location.origin}/${name}.bin`, size: bytes.length, sha256 };
    sessionStorage.setItem('recovery-resource', JSON.stringify(resource));
    let sent = false;
    try { await m.read(resource, true, () => {}, async () => new Response(new ReadableStream({ pull(c) {
      if (!sent) { sent = true; c.enqueue(bytes.slice(0, 4 * 1024 * 1024)); } else c.error(new Error('Lost connection'));
    } }))); } catch (_) {}
  }, { name, fill });
}

test('checkpoint survives reload and quota failure, then resumes without duplicate bytes', async ({ page }) => {
  await boot(page); await interrupt(page, 'reload-model', 19); await boot(page);
  const result = await page.evaluate(async () => {
    const m = (window as any).CW_DOWNLOADS, resource = JSON.parse(sessionStorage.getItem('recovery-resource')!);
    const saved = (await m.meta(resource.url)).offset;
    const originalStorage = navigator.storage;
    const storage = originalStorage || {} as StorageManager;
    const estimate = storage.estimate?.bind(storage);
    if (!originalStorage) Object.defineProperty(navigator, 'storage', { configurable: true, value: storage });
    Object.defineProperty(storage, 'estimate', { configurable: true, value: async () => ({ quota: 1, usage: 0 }) });
    let error = '', requests = 0;
    try { await m.read(resource, true, () => {}, () => { requests++; throw new Error('Unexpected fetch'); }); }
    catch (failure) { error = String(failure); }
    if (originalStorage) Object.defineProperty(storage, 'estimate', { configurable: true, value: estimate });
    else delete (navigator as any).storage;
    const retained = (await m.meta(resource.url)).offset;
    let range = '';
    const bytes = await m.read(resource, true, () => {}, async (_url: string, options: any) => {
      range = options.headers.Range;
      return new Response(new Uint8Array(resource.size - saved).fill(19), { status: 206,
        headers: { 'content-range': `bytes ${saved}-${resource.size - 1}/${resource.size}` } });
    });
    return { saved, retained, error, requests, range, size: bytes.length, last: bytes.at(-1) };
  });
  expect(result.saved).toBe(4 * 1024 * 1024);
  expect(result.retained).toBe(result.saved);
  expect(result.error).toContain('Not enough browser storage');
  expect(result.requests).toBe(0);
  expect(result.range).toBe('bytes=4194304-');
  expect(result.size).toBe(8 * 1024 * 1024 + 13);
  expect(result.last).toBe(19);
});

test('evicted checkpoint restarts cleanly and evicted cache downloads again', async ({ page }) => {
  await boot(page); await interrupt(page, 'evicted-model', 23);
  const result = await page.evaluate(async () => {
    const m = (window as any).CW_DOWNLOADS, resource = JSON.parse(sessionStorage.getItem('recovery-resource')!);
    const bytes = new Uint8Array(resource.size).fill(23);
    const connection: IDBDatabase = await new Promise(resolve => {
      const request = indexedDB.open('crisperweaver-model-downloads-v1'); request.onsuccess = () => resolve(request.result);
    });
    await new Promise<void>((resolve, reject) => {
      const tx = connection.transaction('parts', 'readwrite'); tx.objectStore('parts').delete([resource.url, 0]);
      tx.oncomplete = () => resolve(); tx.onerror = () => reject(tx.error);
    }); connection.close();
    let range: string | undefined;
    await m.read(resource, true, () => {}, async (_url: string, options: any) => { range = options.headers.Range; return new Response(bytes); });
    await caches.delete(m.CACHE);
    let offlineError = '';
    try { await m.read(resource, false); } catch (failure) { offlineError = String(failure); }
    let fetched = 0;
    await m.read(resource, true, () => {}, async () => { fetched++; return new Response(bytes); });
    return { range: range || '', offlineError, fetched, cached: !!await m.cached(resource) };
  });
  expect(result.range).toBe('');
  expect(result.offlineError).toContain('downloads are disabled');
  expect(result.fetched).toBe(1);
  expect(result.cached).toBe(true);
});

test('storage write failure retains the committed checkpoint for retry', async ({ page }) => {
  await boot(page); await interrupt(page, 'write-quota-model', 29);
  const result = await page.evaluate(async () => {
    const m = (window as any).CW_DOWNLOADS, resource = JSON.parse(sessionStorage.getItem('recovery-resource')!);
    const bytes = new Uint8Array(resource.size).fill(29), put = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function(...args: any[]) {
      if (this.name === 'parts' && (args[1] as any[])?.[1] === 1) throw new DOMException('Simulated full disk', 'QuotaExceededError');
      return (put as any).apply(this, args);
    };
    let error = '';
    try { await m.ensure(resource, true, () => {}, async () => new Response(bytes.subarray(4 * 1024 * 1024), { status: 206,
      headers: { 'content-range': `bytes 4194304-${bytes.length - 1}/${bytes.length}` } })); } catch (failure) { error = String(failure); }
    finally { IDBObjectStore.prototype.put = put; }
    const saved = (await m.meta(resource.url)).offset;
    await m.ensure(resource, true, () => {}, async () => new Response(bytes.subarray(saved), { status: 206,
      headers: { 'content-range': `bytes ${saved}-${bytes.length - 1}/${bytes.length}` } }));
    const loaded = await m.read(resource, false);
    return { error, saved, size: loaded.length, cached: !!await m.cached(resource) };
  });
  expect(result.error).toContain('Browser storage is full');
  expect(result.saved).toBe(4 * 1024 * 1024);
  expect(result.size).toBe(8 * 1024 * 1024 + 13);
  expect(result.cached).toBe(true);
});

test('missing verified chunk invalidates streaming cache and allows a clean retry', async ({ page }) => {
  await boot(page);
  const result = await page.evaluate(async () => {
    const m = (window as any).CW_DOWNLOADS, bytes = new Uint8Array(4 * 1024 * 1024 + 13).fill(31);
    const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), x => x.toString(16).padStart(2, '0')).join('');
    const resource = { url: `${location.origin}/missing-verified.bin`, size: bytes.length, sha256 };
    await m.meta(resource.url); // Initialize the downloader's stores first.
    const connection: IDBDatabase = await new Promise(resolve => {
      const request = indexedDB.open('crisperweaver-model-downloads-v1'); request.onsuccess = () => resolve(request.result);
    });
    // Use the same verified-chunk representation as a large model, with a
    // small fixture. Simulate the browser having evicted one stored part.
    await new Promise<void>((resolve, reject) => {
      const tx = connection.transaction(['parts', 'meta'], 'readwrite');
      tx.objectStore('parts').put(bytes.slice(0, 4 * 1024 * 1024), [resource.url, 0]);
      tx.objectStore('meta').put({ ...resource, offset: resource.size, verified: true }, resource.url);
      tx.oncomplete = () => resolve(); tx.onerror = () => reject(tx.error);
    }); connection.close();
    let error = '';
    try { await (await m.verifiedResponse(resource)).arrayBuffer(); } catch (failure) { error = String(failure); }
    const cleared = !(await m.meta(resource.url)) && !(await m.cached(resource));
    let fetched = 0;
    const restored = await m.read(resource, true, () => {}, async () => { fetched++; return new Response(bytes); });
    return { error, cleared, fetched, size: restored.length };
  });
  // Firefox wraps a Response body stream failure in AbortError; rejection,
  // invalidation and a fresh verified download are the portable guarantees.
  expect(result.error).not.toBe('');
  expect(result.cleared).toBe(true); expect(result.fetched).toBe(1);
  expect(result.size).toBe(4 * 1024 * 1024 + 13);
});
