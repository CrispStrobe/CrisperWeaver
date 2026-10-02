import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { TARGET } from './target';
import { bootRuntime } from './runtime-page';
import { attachJson } from './evidence';

for (const { threads, mailbox } of [{ threads: 2, mailbox: '' }, { threads: 4, mailbox: '' }, { threads: 2, mailbox: 'message' }]) {
  const label = mailbox ? 'CrispASR postMessage mailboxes finish real ASR, retain cache and cancel cleanly' : `CrispASR ${threads} threads finish real ASR, retain cache and cancel cleanly`;
  test(label, async ({ page }, info) => {
    test.setTimeout(600_000);
    await bootRuntime(page);
    if (mailbox === 'message' || process.env.CW_BROWSER_MAILBOX_CONTROL === 'message') await page.evaluate(() => localStorage.setItem('cw.browserMailboxPostMessage', 'true'));
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
        const audio = await bridge.decode(new Uint8Array(fixture));
        const repeated = new Float32Array(audio.length * 6);
        for (let index = 0; index < 6; index++) repeated.set(audio, index * audio.length);
        const output = await client.request('transcribe', { audio, transferAudio: true, language: 'en' });
        let firstWindow, timer;
        const started = new Promise(resolve => { firstWindow = resolve; });
        let cancellationProgress = null;
        const pending = client.request('transcribe', { audio: repeated, transferAudio: true, language: 'en' }, (value: number) => {
          if (value > 0 && value < 1) { cancellationProgress = value; firstWindow(); }
        }).then(() => '', (error: Error) => error.message);
        try {
          await Promise.race([started, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Native cancellation window did not finish')), 90_000); })]);
        } finally { clearTimeout(timer); }
        client.cancel();
        const cancellation = await pending;
        await client.request('unload');
        client.allowDownloads = false;
        await client.request('load', { model: 'moonshine-tiny-q4_k' });
        const cached = await client.request('transcribe', { audio: await bridge.decode(new Uint8Array(fixture)), language: 'en' });
        return { loaded, output, cached, beats, cancellation, cancellationProgress };
      } finally { clearInterval(heartbeat); await client.dispose(); }
    }, { fixture, threads });
    await attachJson(info, 'threaded-asr.json', result);
    for (const output of [result.output, result.cached]) {
      expect(output.local).toBe(true);
      expect(output.diagnostics.runtimeMode).toBe('threaded');
      expect(output.diagnostics.cpuThreads).toBe(threads);
      if (mailbox === 'message') expect(output.diagnostics.mailboxMode).toBe('postMessage');
      expect(output.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
    }
    expect(result.loaded.diagnostics.peakWasmBytes).toBeLessThan(512 * 1024 * 1024);
    expect(result.beats).toBeGreaterThan(10);
    expect(result.cancellation).toContain('cancelled');
    expect(result.cancellationProgress).toBeGreaterThan(0);
    expect(result.cancellationProgress).toBeLessThan(1);
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
    } finally { await client.dispose(); }
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
    } finally { await client.dispose(); }
  }, fixture);
  expect(result.loaded.diagnostics.fallbackReason).toContain('Threaded startup failed');
  expect(result.output.diagnostics.runtimeMode).toBe('single');
  expect(result.output.diagnostics.cpuThreads).toBe(1);
  expect(result.output.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
});
