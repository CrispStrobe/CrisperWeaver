// Real cold-cache / warm-cache inference with local diagnostics and, on
// Linux, sampled aggregate RSS of this benchmark's Chromium process tree.
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
const require = createRequire(import.meta.url);
const { chromium } = require('../web-e2e/node_modules/playwright');
const target = process.env.BASE_URL || 'https://crisperweaver-lite-web.vercel.app';
const models = (process.env.BENCHMARK_MODELS || 'crispasr:moonshine-tiny-q4_k,crispasr:stt-en-fastconformer-ctc-large-q4_k,onnx:onnx-moonshine-tiny,onnx:onnx-tiny.en').split(',');
const fixture = Array.from(await readFile(new URL('../web-e2e/fixtures/jfk.wav', import.meta.url)));
const directory = new URL('../web-e2e/artifacts/model-benchmark/', import.meta.url);
await mkdir(directory, { recursive: true });
const report = { target, created: new Date().toISOString(), platform: process.platform,
  memoryScope: 'Sampled sum of Chromium process-tree RSS, including browser baseline and shared pages counted per process; not live tensor memory or device VRAM.', results: [] };
function rss(root) {
  if (process.platform !== 'linux') return null;
  try {
    const rows = execFileSync('ps', ['-eo', 'pid=,ppid=,rss='], { encoding: 'utf8' }).trim().split('\n').map(row => row.trim().split(/\s+/).map(Number));
    const children = new Set([root]); let previous;
    do { previous = children.size; for (const [pid, parent] of rows) if (children.has(parent)) children.add(pid); } while (children.size !== previous);
    return rows.reduce((sum, [pid, , memory]) => sum + (children.has(pid) ? memory * 1024 : 0), 0);
  } catch (_) { return null; }
}
for (const entry of models) {
  const [engine, model] = entry.split(':');
  for (const preference of engine === 'onnx' ? (process.env.BENCHMARK_PROVIDERS || 'wasm,webgpu').split(',') : ['wasm']) {
    const server = await chromium.launchServer({ args: ['--disable-dev-shm-usage', '--enable-unsafe-webgpu', '--use-angle=swiftshader'] });
    const browser = await chromium.connect(server.wsEndpoint());
    const measurement = { engine, model, preference, runs: [] };
    try {
      const page = await browser.newPage();
      const uploads = [];
      page.context().on('request', request => {
        if (new URL(request.url()).origin !== new URL(target).origin && !['GET', 'HEAD'].includes(request.method())) uploads.push(request.url());
      });
      await page.goto(target, { waitUntil: 'domcontentloaded' });
      if (model.startsWith('phonon2')) {
        await page.goto(`${target}/#/models`);
        await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 60_000 });
        await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
        await page.getByRole('switch', { name: /Allow experimental browser models/ }).click();
        await page.getByRole('button', { name: 'I understand; show models', exact: true }).click();
      }
      await page.evaluate(preference => localStorage.setItem('flutter.browser_execution_provider', preference), preference);
      measurement.gpu = await page.evaluate(async () => {
        const adapter = await Promise.race([navigator.gpu?.requestAdapter(), new Promise(resolve => setTimeout(() => resolve(null), 8000))]);
        return adapter ? { description: adapter.info?.description, vendor: adapter.info?.vendor, architecture: adapter.info?.architecture } : null;
      });
      for (const temperature of ['cold', 'warm']) {
        console.log(`Assessing ${entry} / ${preference} / ${temperature}`);
        let peak = rss(server.process().pid), baseline = peak;
        const timer = setInterval(() => { const current = rss(server.process().pid); if (current !== null) peak = Math.max(peak || 0, current); }, 250);
        try {
          const result = await page.evaluate(async ({ engine, model, fixture, cold }) => {
            const bridge = window.CrisperBrowserSpeech, client = bridge.create(engine, true);
            try {
              if (cold) await client.request('clearCache', {});
              const loaded = await client.request('load', { model });
              const audio = await bridge.decode(new Uint8Array(fixture));
              const result = await client.request('transcribe', { audio, transferAudio: true });
              const transcript = result.segments.map(segment => segment.text).join(' ');
              if (!result.local || !transcript.toLowerCase().includes('country')) throw new Error('Known local transcript check failed');
              return { loaded: loaded.diagnostics, inference: result.diagnostics, transcript };
            } finally { client.dispose(); }
          }, { engine, model, fixture, cold: temperature === 'cold' });
          measurement.runs.push({ cache: temperature, ...result, baselineBrowserRssBytes: baseline, peakBrowserRssBytes: peak });
          if (uploads.length) throw new Error('Unexpected off-origin upload during local inference');
        } finally { clearInterval(timer); }
      }
      console.log(JSON.stringify(measurement));
    } catch (error) { measurement.error = String(error); process.exitCode = 1; console.log(JSON.stringify(measurement)); }
    finally {
      report.results.push(measurement);
      await browser.close(); await server.close();
      await mkdir(directory, { recursive: true });
      await writeFile(new URL('results.json', directory), JSON.stringify(report, null, 2));
    }
  }
}
