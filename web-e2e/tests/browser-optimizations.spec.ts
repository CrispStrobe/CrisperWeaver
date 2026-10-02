import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { TARGET } from './target';

test('interrupted model download resumes a verified checkpoint and handles ignored ranges', async ({ page }) => {
  await page.goto(TARGET);
  await page.addScriptTag({ url: `${TARGET}/speech/downloads.js` });
  const result = await page.evaluate(async () => {
    const manager = (window as any).CW_DOWNLOADS, part = 4 * 1024 * 1024;
    const bytes = Uint8Array.from({ length: part * 2 + 19 }, (_, i) => i % 251);
    const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
    const run = async (ignored: boolean) => {
      const resource = { url: `${location.origin}/checkpoint-${ignored}.bin`, sha256, size: bytes.length };
      let sent = false;
      try {
        await manager.read(resource, true, () => {}, async () => new Response(new ReadableStream({ pull(controller) {
          if (!sent) { sent = true; controller.enqueue(bytes.slice(0, part)); }
          else controller.error(new Error('Connection interrupted'));
        } })));
      } catch (_) {}
      const checkpoint = await manager.meta(resource.url);
      let range = '';
      const restored = await manager.read(resource, true, () => {}, async (_url: string, options: any) => {
        range = options.headers.Range;
        return new Response(ignored ? bytes : bytes.subarray(part), { status: ignored ? 200 : 206,
          headers: { 'content-range': `bytes ${part}-${bytes.length - 1}/${bytes.length}` } });
      });
      await manager.read(resource, false, () => {}, () => { throw new Error('Unexpected network access'); });
      return { saved: checkpoint.offset, range, length: restored.length, last: restored.at(-1), cleared: !await manager.meta(resource.url) };
    };
    return { normal: await run(false), ignored: await run(true), expected: bytes.length, last: bytes.at(-1) };
  });
  for (const value of [result.normal, result.ignored]) {
    expect(value.saved).toBe(4 * 1024 * 1024);
    expect(value.range).toBe('bytes=4194304-');
    expect(value.length).toBe(result.expected);
    expect(value.last).toBe(result.last);
    expect(value.cleared).toBe(true);
  }
});

test('bad ranges retain progress and corrupted downloads/cache never reach inference', async ({ page }) => {
  await page.goto(TARGET);
  await page.addScriptTag({ url: `${TARGET}/speech/downloads.js` });
  const result = await page.evaluate(async () => {
    const manager = (window as any).CW_DOWNLOADS, size = 4 * 1024 * 1024;
    const bytes = new Uint8Array(size + 23).fill(7);
    const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
    const resource = { url: `${location.origin}/invalid-range.bin`, sha256, size: bytes.length };
    let sent = false;
    try { await manager.read(resource, true, () => {}, async () => new Response(new ReadableStream({ pull(controller) {
      if (!sent) { sent = true; controller.enqueue(bytes.slice(0, size)); }
      else controller.error(new Error('Interrupted'));
    } }))); } catch (_) {}
    let rangeError = '', checksumError = '', cacheError = '';
    try { await manager.read(resource, true, () => {}, async () => new Response(bytes.subarray(size), { status: 206, headers: { 'content-range': 'bytes 1-23/24' } })); }
    catch (error) { rangeError = String(error); }
    const retained = (await manager.meta(resource.url)).offset;
    await manager.remove([resource]);
    const bad = bytes.slice(); bad[0] = 8;
    try { await manager.read(resource, true, () => {}, async () => new Response(bad)); }
    catch (error) { checksumError = String(error); }
    const discarded = !await manager.meta(resource.url);
    await manager.put(resource, bytes);
    await (await caches.open(manager.CACHE)).put(resource.url, new Response(bad, { headers: { 'x-cw-sha256': sha256, 'content-length': String(bytes.length) } }));
    try { await manager.read(resource, false); } catch (error) { cacheError = String(error); }
    return { rangeError, retained, checksumError, discarded, cacheError, removed: !await manager.cached(resource) };
  });
  expect(result.rangeError).toContain('invalid download range');
  expect(result.retained).toBe(4 * 1024 * 1024);
  expect(result.checksumError).toContain('checksum mismatch');
  expect(result.discarded).toBe(true);
  expect(result.cacheError).toContain('checksum mismatch');
  expect(result.removed).toBe(true);
});

test('large verified chunk caches survive incomplete cleanup and reject corruption', async ({ page }) => {
  test.setTimeout(180_000);
  await page.goto(TARGET);
  await page.addScriptTag({ url: `${TARGET}/speech/downloads.js` });
  const result = await page.evaluate(async () => {
    const manager = (window as any).CW_DOWNLOADS;
    const bytes = new Uint8Array(64 * 1024 * 1024 + 3).fill(11);
    const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
    const resource = { url: `${location.origin}/large-chunk-cache.bin`, sha256, size: bytes.length };
    await manager.read(resource, true, () => {}, async () => new Response(bytes));
    const verified = (await manager.meta(resource.url)).verified;
    const cacheStorageCopy = !!await (await caches.open(manager.CACHE)).match(resource.url);
    await manager.clearIncomplete();
    const restored = await manager.read(resource, false, () => {}, () => { throw new Error('Unexpected network access'); });
    const incompleteCount = (await manager.stats()).incompleteCount;
    const connection: IDBDatabase = await new Promise((resolve, reject) => {
      const request = indexedDB.open('crisperweaver-model-downloads-v1');
      request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
    });
    await new Promise<void>((resolve, reject) => {
      const tx = connection.transaction('parts', 'readwrite');
      tx.objectStore('parts').put(new Uint8Array(4 * 1024 * 1024).fill(12), [resource.url, 0]);
      tx.oncomplete = () => resolve(); tx.onerror = () => reject(tx.error);
    });
    connection.close();
    let error = '';
    try { await manager.read(resource, false); } catch (failure) { error = String(failure); }
    return { verified, cacheStorageCopy, size: restored.length, expected: resource.size, incompleteCount, error, removed: !await manager.cached(resource) };
  });
  expect(result.verified).toBe(true);
  expect(result.cacheStorageCopy).toBe(false);
  expect(result.size).toBe(result.expected);
  expect(result.incompleteCount).toBe(0);
  expect(result.error).toContain('checksum mismatch');
  expect(result.removed).toBe(true);
});

test('worker unload releases inference state and owned audio is transferred', async ({ page }) => {
  test.setTimeout(600_000);
  await page.goto(TARGET);
  const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures/jfk.wav')));
  const result = await page.evaluate(async (fixture) => {
    const bridge = (window as any).CrisperBrowserSpeech, client = bridge.create('crispasr', true);
    try {
      const load = await client.request('load', { model: 'moonshine-tiny-q4_k' });
      const audio = await bridge.decode(new Uint8Array(fixture));
      const inference = client.request('transcribe', { audio, transferAudio: true });
      const detached = audio.byteLength === 0;
      const transcript = await inference;
      const oldWorker = client.worker;
      await client.request('unload', {});
      const unloaded = client.worker === null;
      let error = '';
      try { await client.request('transcribe', { audio: new Float32Array(16000) }); } catch (e) { error = String(e); }
      return { detached, unloaded, fresh: oldWorker !== client.worker, error, load: load.diagnostics, transcript };
    } finally { client.dispose(); }
  }, fixture);
  expect(result.detached).toBe(true);
  expect(result.unloaded).toBe(true);
  expect(result.fresh).toBe(true);
  expect(result.error).toContain('Load a speech model');
  expect(result.load.peakWasmBytes).toBeGreaterThan(0);
  expect(result.transcript.diagnostics.elapsedMs).toBeGreaterThan(0);
  expect(result.transcript.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
});

test('quiet overlapping windows cover the recording and deduplicate boundary context', async ({ page }) => {
  await page.goto(TARGET);
  await page.addScriptTag({ url: `${TARGET}/speech/chunks.js` });
  const result = await page.evaluate(() => {
    const chunks = (window as any).CW_CHUNKS;
    const audio = new Float32Array(16000 * 65).fill(0.1);
    audio.fill(0, 16000 * 25, 16000 * 26);
    const windows = chunks.plan(audio);
    const distantPause = new Float32Array(16000 * 65).fill(0.1);
    distantPause.fill(0, 16000 * 18, 16000 * 22);
    const distantWindows = chunks.plan(distantPause);
    const output: any[] = [{ text: 'ask what your country can do', start: 0, end: 25.5 }];
    chunks.append(output, [{ text: 'your country can do for you', start: 25, end: 30 }], { coreStart: 25.5 * 16000, coreEnd: 40 * 16000 });
    return { windows, distantWindows, output, length: audio.length };
  });
  expect(result.distantWindows[0].coreEnd / 16000).toBeGreaterThan(18);
  expect(result.distantWindows[0].coreEnd / 16000).toBeLessThan(22);
  expect(result.windows[0].coreEnd / 16000).toBeGreaterThan(25);
  expect(result.windows[0].coreEnd / 16000).toBeLessThan(26);
  expect(result.windows.at(-1)?.coreEnd).toBe(result.length);
  result.windows.forEach((window: any, i: number) => {
    expect(window.end - window.start).toBeLessThanOrEqual(16000 * 30);
    if (i) expect(window.coreStart).toBe(result.windows[i - 1].coreEnd);
  });
  expect(result.output.map((s: any) => s.text).join(' ')).toBe('ask what your country can do for you');
});

test('long Moonshine recording preserves repeated speech across quiet boundaries', async ({ page }, info) => {
  test.setTimeout(600_000);
  await page.goto(TARGET);
  const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures/jfk.wav')));
  const result = await page.evaluate(async fixture => {
    const bridge = (window as any).CrisperBrowserSpeech, client = bridge.create('crispasr', true);
    try {
      await client.request('load', { model: 'moonshine-tiny-q4_k' });
      const clip = await bridge.decode(new Uint8Array(fixture)), block = clip.length + 16000;
      const audio = new Float32Array(block * 4);
      for (let i = 0; i < 4; i++) audio.set(clip, i * block);
      return await client.request('transcribe', { audio, transferAudio: true });
    } finally { client.dispose(); }
  }, fixture);
  const transcript = result.segments.map((s: any) => s.text).join(' ').toLowerCase();
  await info.attach('long-recording.json', { body: Buffer.from(JSON.stringify(result)), contentType: 'application/json' });
  expect(transcript.match(/country/g)?.length).toBe(8);
  expect(result.segments.length).toBeGreaterThan(1);
  for (const segment of result.segments) {
    expect(segment.end).toBeGreaterThan(segment.start);
    expect(segment.start).toBeGreaterThanOrEqual(0);
    expect(segment.end).toBeLessThanOrEqual(48);
  }
});

test('a GPU adapter failure falls back to verified local WASM inference', async ({ page }) => {
  test.setTimeout(600_000);
  await page.route('**/speech/worker.js', async route => {
    const response = await route.fetch();
    await route.fulfill({ response, body: `Object.defineProperty(navigator, 'gpu', { value: { requestAdapter: async () => { throw new Error('Test adapter failure'); } } });\n` + await response.text() });
  });
  await page.goto(TARGET);
  const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures/jfk.wav')));
  const result = await page.evaluate(async fixture => {
    localStorage.setItem('flutter.browser_execution_provider', 'webgpu');
    const bridge = (window as any).CrisperBrowserSpeech, client = bridge.create('onnx', true);
    try {
      const loaded = await client.request('load', { model: 'onnx-moonshine-tiny' });
      const result = await client.request('transcribe', { audio: await bridge.decode(new Uint8Array(fixture)) });
      return { loaded, result };
    } finally { client.dispose(); }
  }, fixture);
  expect(result.loaded.diagnostics.provider).toBe('wasm');
  expect(result.loaded.diagnostics.fallbackReason).toContain('Test adapter failure');
  expect(result.result.local).toBe(true);
  expect(result.result.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
});

test('a real model download resumes from a checkpoint against the pinned host', async ({ page }) => {
  test.setTimeout(600_000);
  await page.goto(TARGET);
  await page.addScriptTag({ url: `${TARGET}/speech/downloads.js` });
  const result = await page.evaluate(async () => {
    const lock = await (await fetch(new URL('speech/model-lock.json', document.baseURI))).json();
    const resource = lock.repositories['cstr/moonshine-tiny-GGUF'].files['moonshine-tiny-q4_k.gguf'];
    const manager = (window as any).CW_DOWNLOADS, part = 4 * 1024 * 1024;
    const response = await fetch(resource.url, { headers: { Range: `bytes=0-${part - 1}` } });
    if (!response.ok) throw new Error('Pinned host did not return the model');
    const prefix = new Uint8Array(await response.arrayBuffer()).slice(0, part);
    let sent = false;
    try { await manager.read(resource, true, () => {}, async () => new Response(new ReadableStream({ pull(controller) {
      if (!sent) { sent = true; controller.enqueue(prefix); }
      else controller.error(new Error('Interrupted after checkpoint'));
    } }))); } catch (_) {}
    const saved = (await manager.meta(resource.url)).offset;
    let range = '';
    const bytes = await manager.read(resource, true, () => {}, (url: string, options: any) => {
      range = options.headers.Range; return fetch(url, options);
    });
    return { saved, range, size: bytes.length, expectedSize: resource.size, cached: !!await manager.cached(resource) };
  });
  expect(result.saved).toBe(4194304);
  expect(result.range).toBe('bytes=4194304-');
  expect(result.size).toBe(result.expectedSize);
  expect(result.cached).toBe(true);
});

test('model cache deletion requires confirmation and preserves transcript history', async ({ page }) => {
  test.setTimeout(600_000);
  await page.addInitScript(() => {
    localStorage.setItem('flutter.ai_transparency_notice_seen', 'true');
    localStorage.setItem('flutter.onboarding_completed', 'true');
  });
  await page.goto(TARGET);
  await page.evaluate(async () => {
    const bridge = (window as any).CrisperBrowserSpeech, client = bridge.create('crispasr', true);
    try { await client.request('load', { model: 'moonshine-tiny-q4_k' }); }
    finally { client.dispose(); }
    await bridge.history('put', 'cache-test-transcript', 'Preserve this transcript');
  });
  await page.goto(`${TARGET}/#/models`);
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 60_000 });
  await page.evaluate(() => (document.querySelector('flt-semantics-placeholder') as HTMLElement).click());
  await page.getByRole('button', { name: 'Delete cached speech models', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Keep models', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Delete', exact: true }).click();
  await expect.poll(() => page.evaluate(async () => {
    const client = (window as any).CrisperBrowserSpeech.create('crispasr', false);
    try {
      return (await client.request('models', {})).find((model: any) => model.id === 'moonshine-tiny-q4_k').cached;
    } finally { client.dispose(); }
  }), { timeout: 60_000 }).toBe(false);
  const result = await page.evaluate(async () => {
    const bridge = (window as any).CrisperBrowserSpeech, client = bridge.create('crispasr', false);
    try {
      return { models: await client.request('models', {}), history: await bridge.history('get', 'cache-test-transcript') };
    } finally { client.dispose(); }
  });
  expect(result.models.find((model: any) => model.id === 'moonshine-tiny-q4_k').cached).toBe(false);
  expect(result.history).toBe('Preserve this transcript');
});
