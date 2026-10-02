import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { TARGET } from './target';

test('browser model filtering rejects a saved large model before download', async ({ page }) => {
  await page.goto(TARGET, { waitUntil: 'domcontentloaded' });
  const requests: string[] = [];
  page.context().on('request', request => {
    if (new URL(request.url()).origin !== new URL(TARGET).origin) requests.push(request.url());
  });
  const result = await page.evaluate(async () => {
    const client = (window as any).CrisperBrowserSpeech.create('crispasr', true);
    try {
      const normal = await client.request('models', {});
      let error = '';
      try { await client.request('load', { model: 'phonon2-q4_k' }); }
      catch (e) { error = String(e); }
      // Simulate the persisted preference after the UI's acknowledgement.
      localStorage.setItem('flutter.browser_allow_experimental_models', 'true');
      const expanded = await client.request('models', {});
      localStorage.setItem('flutter.browser_allow_experimental_models', 'false');
      const filtered = await client.request('models', {});
      return { normal, expanded, filtered, error };
    } finally { client.dispose(); }
  });
  expect(result.normal.some((m: any) => m.id === 'moonshine-tiny-q4_k')).toBe(true);
  expect(result.normal.some((m: any) => m.id.startsWith('phonon2'))).toBe(false);
  expect(result.error).toContain('filtered out');
  expect(result.expanded.find((m: any) => m.id === 'phonon2-q4_k').experimental).toBe(true);
  expect(result.expanded.length).toBeGreaterThan(result.normal.length + 50);
  expect(result.filtered.length).toEqual(result.normal.length);
  expect(requests.filter(url => url.includes('huggingface.co'))).toEqual([]);
});

for (const [engine, model] of [['crispasr', 'moonshine-tiny-q4_k'], ['crispasr', 'stt-en-fastconformer-ctc-large-q4_k'], ['onnx', 'onnx-moonshine-tiny'], ['onnx', 'onnx-whisper-base']]) {
  test(`${engine} ${model} transcribes real speech and reuses the full cached bundle`, async ({ page }, info) => {
    test.setTimeout(600_000);
    await page.goto(TARGET, { waitUntil: 'domcontentloaded' });
    const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures/jfk.wav')));
    const infer = async (downloads: boolean) => page.evaluate(async ({ engine, model, fixture, downloads }) => {
      const bridge = (window as any).CrisperBrowserSpeech, client = bridge.create(engine, downloads);
      try {
        await client.request('load', { model });
        const models = await client.request('models', {});
        if (!models.find((m: any) => m.id === model)?.cached) throw new Error('Incomplete model cache');
        return await client.request('transcribe', { audio: await bridge.decode(new Uint8Array(fixture)), language: 'en' });
      } finally { client.dispose(); }
    }, { engine, model, fixture, downloads });
    const result = await infer(true);
    expect(result.local).toBe(true);
    expect(result.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
    await page.context().route('**/*', route => new URL(route.request().url()).origin === new URL(TARGET).origin ? route.continue() : route.abort());
    const cached = await infer(false);
    expect(cached.segments.map((s: any) => s.text).join(' ').toLowerCase()).toContain('country');
    await info.attach('moonshine-transcription.json', { body: Buffer.from(JSON.stringify(result)), contentType: 'application/json' });
  });
}

test('experimental browser catalogue requires explicit warning acceptance', async ({ page }, info) => {
  await page.addInitScript(() => {
    localStorage.setItem('flutter.ai_transparency_notice_seen', 'true');
    localStorage.setItem('flutter.onboarding_completed', 'true');
  });
  await page.goto(`${TARGET}/#/models`, { waitUntil: 'domcontentloaded' });
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 60_000 });
  await page.evaluate(() => (document.querySelector('flt-semantics-placeholder') as HTMLElement).click());
  const override = page.getByRole('switch', { name: /Allow experimental browser models/ });
  await expect(override).not.toBeChecked();
  await override.click();
  await expect(page.getByRole('button', { name: 'Keep filtering', exact: true })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('flutter.browser_allow_experimental_models'))).not.toBe('true');
  await page.getByRole('button', { name: 'Keep filtering', exact: true }).click();
  await expect(override).not.toBeChecked();
  await override.click();
  await page.getByRole('button', { name: 'I understand; show models', exact: true }).click();
  await expect(override).toBeChecked();
  await page.mouse.move(900, 500);
  await page.mouse.wheel(0, 700);
  await expect.poll(() => page.evaluate(() => Array.from(document.querySelectorAll('[aria-label]')).map(e => e.getAttribute('aria-label')).join(' ') + document.body.innerText)).toContain('Phonon-2');
  await page.screenshot({ path: info.outputPath('experimental-browser-catalogue.png') });
  await page.mouse.wheel(0, -1200);
  await expect(override).toBeVisible();
  await override.click();
  await expect(override).not.toBeChecked();
  await expect.poll(() => page.evaluate(async () => {
    const client = (window as any).CrisperBrowserSpeech.create('crispasr', false);
    try { return (await client.request('models', {})).some((m: any) => m.id.startsWith('phonon2')); }
    finally { client.dispose(); }
  })).toBe(false);
});
