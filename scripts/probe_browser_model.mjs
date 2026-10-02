// Optional CI assessment of a model exposed by the warned browser override.
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { chromium } = require('../web-e2e/node_modules/playwright');
const target = process.env.BASE_URL || 'https://crisperweaver-lite-web.vercel.app';
const model = process.env.PROBE_MODEL || 'phonon2-q4_k';
const directory = new URL('../web-e2e/artifacts/model-probe/', import.meta.url);
await mkdir(directory, { recursive: true });
const browser = await chromium.launch({ args: ['--disable-dev-shm-usage'] });
const report = { model, target, supported: false };
try {
  const page = await browser.newPage();
  const uploads = [];
  page.context().on('request', request => {
    if (new URL(request.url()).origin !== new URL(target).origin && !['GET', 'HEAD'].includes(request.method())) uploads.push(request.url());
  });
  await page.addInitScript(() => {
    localStorage.setItem('flutter.ai_transparency_notice_seen', 'true');
    localStorage.setItem('flutter.onboarding_completed', 'true');
  });
  await page.goto(`${target}/#/models`, { waitUntil: 'domcontentloaded' });
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 60_000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
  await page.getByRole('switch', { name: /Allow experimental browser models/ }).click();
  await page.getByRole('button', { name: 'I understand; show models', exact: true }).click();
  const fixture = Array.from(await readFile(new URL('../web-e2e/fixtures/jfk.wav', import.meta.url)));
  const result = await page.evaluate(async ({ model, fixture }) => {
    const bridge = window.CrisperBrowserSpeech, client = bridge.create('crispasr', true);
    const started = performance.now();
    try {
      await client.request('load', { model });
      const loadedMs = performance.now() - started;
      const result = await client.request('transcribe', { audio: await bridge.decode(new Uint8Array(fixture)), language: 'en' });
      return { ...result, loadedMs, elapsedMs: performance.now() - started };
    } finally { client.dispose(); }
  }, { model, fixture });
  const text = result.segments.map(segment => segment.text).join(' ').toLowerCase();
  if (!result.local || !text.includes('country') || uploads.length) throw new Error('Known local speech inference or no-upload check failed');
  Object.assign(report, { supported: true, result });
} catch (error) {
  report.error = String(error);
  process.exitCode = 1;
} finally {
  await browser.close();
  await writeFile(new URL('result.json', directory), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}
