import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { TARGET } from './target';
import { bootRuntime } from './runtime-page';
import { attachJson } from './evidence';

for (const threads of [2, 4]) {
  test(`CrispASR ${threads} threads finish real ASR, retain cache and cancel cleanly`, async ({ page }, info) => {
    test.setTimeout(600_000);
    await bootRuntime(page);
    expect(await page.evaluate(() => crossOriginIsolated)).toBe(true);
    const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures/jfk.wav')));
    const result = await page.evaluate(async ({ fixture, threads }) => {
      localStorage.setItem('flutter.browser_cpu_threads', String(threads));
      const bridge = (window as any).CrisperBrowserSpeech;
      const client = bridge.create('crispasr', true);
      let beats = 0;
      const heartbeat = setInterval(() => beats++, 20);
      try {
        const loaded = await client.request('load', { model: 'moonshine-tiny-q4_k' });
        const output = await client.request('transcribe', { audio: await bridge.decode(new Uint8Array(fixture)), transferAudio: true, language: 'en' });
        const pending = client.request('transcribe', { audio: new Float32Array(16000 * 60), transferAudio: true }).then(() => '', (error: Error) => error.message);
        client.cancel();
        const cancellation = await pending;
        await client.request('unload');
        client.allowDownloads = false;
        await client.request('load', { model: 'moonshine-tiny-q4_k' });
        const cached = await client.request('transcribe', { audio: await bridge.decode(new Uint8Array(fixture)), language: 'en' });
        return { loaded, output, cached, beats, cancellation };
      } finally { clearInterval(heartbeat); client.dispose(); }
    }, { fixture, threads });
    await attachJson(info, 'threaded-asr.json', result);
    for (const output of [result.output, result.cached]) {
      expect(output.local).toBe(true);
      expect(output.diagnostics.runtimeMode).toBe('threaded');
      expect(output.diagnostics.cpuThreads).toBe(threads);
      expect(output.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
    }
    expect(result.loaded.diagnostics.peakWasmBytes).toBeLessThan(512 * 1024 * 1024);
    expect(result.beats).toBeGreaterThan(10);
    expect(result.cancellation).toContain('cancelled');
  });
}

test('threaded TTS produces speech that threaded ASR recognizes', async ({ page }, info) => {
  test.setTimeout(900_000);
  await bootRuntime(page);
  const result = await page.evaluate(async () => {
    localStorage.setItem('flutter.browser_cpu_threads', '4');
    const client = (window as any).CrisperBrowserSpeech.create('crispasr', true);
    try {
      const spoken = await client.request('synthesize', { text: 'Hello, this speech is generated locally in your browser.' });
      const context = new OfflineAudioContext(1, Math.ceil(spoken.audio.length * 16000 / spoken.sampleRate), 16000);
      const buffer = context.createBuffer(1, spoken.audio.length, spoken.sampleRate); buffer.copyToChannel(spoken.audio, 0);
      const source = context.createBufferSource(); source.buffer = buffer; source.connect(context.destination); source.start();
      const audio = (await context.startRendering()).getChannelData(0).slice();
      await client.request('load', { model: 'moonshine-tiny-q4_k' });
      const output = await client.request('transcribe', { audio, transferAudio: true, language: 'en' });
      return { output, ttsDiagnostics: spoken.diagnostics, samples: spoken.audio.length, sampleRate: spoken.sampleRate, local: spoken.local };
    } finally { client.dispose(); }
  });
  expect(result.local).toBe(true);
  expect(result.samples).toBeGreaterThan(result.sampleRate);
  expect(result.ttsDiagnostics.runtimeMode).toBe('threaded');
  expect(result.ttsDiagnostics.cpuThreads).toBe(4);
  expect(result.output.diagnostics.runtimeMode).toBe('threaded');
  const text = result.output.segments.map((s: any) => s.text).join(' ').toLowerCase();
  expect(text).toContain('speech'); expect(text).toContain('browser');
  await attachJson(info, 'threaded-roundtrip.json', result);
});

test('threaded startup failure recovers with single-thread CPU inference', async ({ page }) => {
  test.setTimeout(600_000);
  // Worker subresource interception differs by browser. An actual crashing
  // Blob worker gives a portable startup-failure control on the main bridge.
  await page.addInitScript(() => {
    const NativeWorker = window.Worker;
    const failedUrl = URL.createObjectURL(new Blob(["throw new Error('Threaded startup failed for recovery control');"], { type: 'application/javascript' }));
    (window as any).Worker = class extends NativeWorker {
      constructor(url: string | URL, options?: WorkerOptions) {
        super(new URL(String(url), document.baseURI).searchParams.get('runtime') === 'threaded' ? failedUrl : url, options);
      }
    };
  });
  await bootRuntime(page);
  const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures/jfk.wav')));
  const result = await page.evaluate(async fixture => {
    localStorage.setItem('flutter.browser_cpu_threads', '4');
    const bridge = (window as any).CrisperBrowserSpeech, client = bridge.create('crispasr', true);
    try {
      const loaded = await client.request('load', { model: 'moonshine-tiny-q4_k' });
      const output = await client.request('transcribe', { audio: await bridge.decode(new Uint8Array(fixture)), language: 'en' });
      return { loaded, output };
    } finally { client.dispose(); }
  }, fixture);
  expect(result.loaded.diagnostics.fallbackReason).toContain('Threaded startup failed');
  expect(result.output.diagnostics.runtimeMode).toBe('single');
  expect(result.output.diagnostics.cpuThreads).toBe(1);
  expect(result.output.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
});
