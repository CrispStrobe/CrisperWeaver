import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { TARGET } from './target';

// Exercise the actual shipped workers, actual downloaded weights, and known
// speech. No fake network responses or mocked inference results.
for (const backend of ['crispasr', 'onnx']) {
  test(`${backend} transcribes known speech locally and reuses cached models`, async ({ page }, info) => {
    test.setTimeout(600_000);
    const uploaded: string[] = [];
    page.context().on('request', req => {
      if (new URL(req.url()).origin !== new URL(TARGET).origin && !['GET', 'HEAD'].includes(req.method())) {
        uploaded.push(`${req.method()} ${req.url()}`);
      }
    });
    await page.goto(TARGET, { waitUntil: 'domcontentloaded' });
    const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures/jfk.wav')));
    const model = backend === 'onnx' ? 'onnx-tiny.en' : 'tiny.en';
    const result = await page.evaluate(async ({ backend, model, fixture }) => {
      const bridge = (window as any).CrisperBrowserSpeech;
      const client = bridge.create(backend, true);
      await client.request('load', { model });
      const audio = await bridge.decode(new Uint8Array(fixture));
      const started = performance.now();
      const output = await client.request('transcribe', { audio, language: 'en' });
      client.dispose();
      return { ...output, ms: performance.now() - started };
    }, { backend, model, fixture });
    const text = result.segments.map((s: any) => s.text).join(' ');
    console.log(`${backend} (${TARGET}) → ${text} (${Math.round(result.ms)}ms)`);
    expect(text.toLowerCase()).toContain('country');
    expect(text.toLowerCase()).toContain('ask');
    expect(result.local).toBe(true);
    expect(result.segments.some((s: any) => s.end > s.start)).toBe(true);
    expect(uploaded).toEqual([]);

    // A fresh worker must still infer with all off-origin requests blocked.
    // This tests durable browser caching, rather than reuse of a loaded model.
    await page.context().route('**/*', route => {
      if (new URL(route.request().url()).origin !== new URL(TARGET).origin) return route.abort();
      return route.continue();
    });
    const cached = await page.evaluate(async ({ backend, model, fixture }) => {
      const bridge = (window as any).CrisperBrowserSpeech;
      const client = bridge.create(backend, false);
      const models = await client.request('models', {});
      if (!models.find((m: any) => m.id === model)?.cached) throw new Error('Downloaded model is missing from the cached model catalogue');
      await client.request('load', { model });
      const audio = await bridge.decode(new Uint8Array(fixture));
      const output = await client.request('transcribe', { audio, language: 'en' });
      client.dispose(); return output;
    }, { backend, model, fixture });
    expect(cached.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
    await info.attach('local-transcription.json', { body: Buffer.from(JSON.stringify(result, null, 2)), contentType: 'application/json' });
  });

  test(`${backend} renders a real transcript through the app's upload flow`, async ({ page }, info) => {
    test.setTimeout(600_000);
    await page.addInitScript(({ backend }) => {
      localStorage.setItem('flutter.ai_transparency_notice_seen', 'true');
      localStorage.setItem('flutter.onboarding_completed', 'true');
      localStorage.setItem('flutter.preferred_engine', JSON.stringify(backend === 'onnx' ? 'onnxweb' : 'crispasr'));
      localStorage.setItem('flutter.default_model', JSON.stringify(backend === 'onnx' ? 'onnx-tiny.en' : 'tiny.en'));
    }, { backend });
    const uploads: string[] = [];
    page.context().on('request', req => {
      if (new URL(req.url()).origin !== new URL(TARGET).origin && !['GET', 'HEAD'].includes(req.method())) uploads.push(req.url());
    });
    await page.goto(TARGET, { waitUntil: 'domcontentloaded' });
    await expect(page.locator('flt-semantics-placeholder')).toBeAttached({ timeout: 60_000 });
    await page.evaluate(() => {
      const element = document.querySelector('flt-semantics-placeholder') as HTMLElement;
      element.dispatchEvent(new MouseEvent('click', { bubbles: true })); element.click();
    });
    const chooserPromise = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Browse', exact: true }).click();
    await (await chooserPromise).setFiles(path.join(__dirname, '../fixtures/jfk.wav'));
    await page.getByRole('button', { name: 'Transcribe', exact: true }).click();
    await expect.poll(() => page.evaluate(() => (document.body.innerText + ' ' + Array.from(document.querySelectorAll('[aria-label]')).map(e => e.getAttribute('aria-label')).join(' ') + ' ' + Array.from(document.querySelectorAll('input, textarea')).map(e => (e as HTMLInputElement).value).join(' ')).toLowerCase()), { timeout: 480_000 }).toContain('country');
    await expect.poll(() => page.evaluate(async () => {
      const entries = await (window as any).CrisperBrowserSpeech.history('list');
      return entries.join(' ').toLowerCase();
    })).toContain('country');
    expect(uploads).toEqual([]);
    await page.screenshot({ path: info.outputPath(`${backend}-real-transcript.png`) });
  });
}

test('CrispASR synthesizes non-silent speech locally', async ({ page }, info) => {
  // Two separate cold workers run serially; Firefox's CPU Kokoro path is slow.
  test.setTimeout(900_000);
  await page.addInitScript(() => {
    localStorage.setItem('flutter.ai_transparency_notice_seen', 'true');
    localStorage.setItem('flutter.onboarding_completed', 'true');
  });
  const uploaded: string[] = [];
  page.context().on('request', req => {
    if (new URL(req.url()).origin !== new URL(TARGET).origin && !['GET', 'HEAD'].includes(req.method())) uploaded.push(req.url());
  });
  await page.goto(TARGET, { waitUntil: 'domcontentloaded' });
  const result = await page.evaluate(async () => {
    const client = (window as any).CrisperBrowserSpeech.create('crispasr', true);
    const { audio, sampleRate, local } = await client.request('synthesize', { text: 'Hello from your browser.' });
    const rms = Math.sqrt(audio.reduce((sum: number, v: number) => sum + v * v, 0) / audio.length);
    client.dispose(); return { samples: audio.length, sampleRate, rms, local };
  });
  expect(result.local).toBe(true);
  expect(result.samples).toBeGreaterThan(result.sampleRate);
  expect(result.rms).toBeGreaterThan(0.005);
  expect(uploaded).toEqual([]);
  await info.attach('local-synthesis.json', { body: Buffer.from(JSON.stringify(result)), contentType: 'application/json' });
  await page.context().route('**/*', route => {
    if (new URL(route.request().url()).origin !== new URL(TARGET).origin) return route.abort();
    return route.continue();
  });
  await page.goto(`${TARGET}/#/synthesize`, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('flt-semantics-placeholder')).toBeAttached({ timeout: 60_000 });
  await page.evaluate(() => {
    const element = document.querySelector('flt-semantics-placeholder') as HTMLElement;
    element.dispatchEvent(new MouseEvent('click', { bubbles: true })); element.click();
  });
  const field = page.getByRole('textbox');
  await field.click(); await expect(field).toBeFocused();
  await field.press('ArrowLeft');
  await field.pressSequentially('Hello browser.', { delay: 30 });
  await expect(field).toHaveValue('Hello browser.');
  await field.press('Tab');
  await page.getByRole('button', { name: 'Generate speech', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Download WAV', exact: true })).toBeVisible({ timeout: 480_000 });
  const downloadEvent = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download WAV', exact: true }).click();
  const download = await downloadEvent;
  const wav = await readFile((await download.path())!);
  expect(wav.subarray(0, 4).toString()).toBe('RIFF');
  expect(wav.toString('latin1')).toContain('AI-generated synthetic speech');
  expect(uploaded).toEqual([]);
  await page.screenshot({ path: info.outputPath('local-synthesis-wav.png') });
});
