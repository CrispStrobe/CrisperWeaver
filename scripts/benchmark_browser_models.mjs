// Real cold-cache / warm-cache inference with local diagnostics and, on
// Linux, sampled aggregate RSS of this benchmark's Chromium process tree.
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
const require = createRequire(import.meta.url);
const { chromium, firefox, webkit } = require('../web-e2e/node_modules/playwright');
const target = process.env.BASE_URL || 'https://crisperweaver-lite-web.vercel.app';
const models = (process.env.BENCHMARK_MODELS || 'crispasr:tiny.en,crispasr:base,crispasr:moonshine-tiny-q4_k,crispasr:stt-en-fastconformer-ctc-large-q4_k,onnx:onnx-moonshine-tiny,onnx:onnx-tiny.en').split(',');
const hardware = process.env.REQUIRE_HARDWARE_GPU === '1';
const repetitions = Math.max(3, Number(process.env.BENCHMARK_REPETITIONS) || 3);
const runtime = { chromium, firefox, webkit }[process.env.BENCHMARK_BROWSER || 'chromium'];
if (!runtime) throw new Error('Unknown benchmark browser');
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
function gpuMemory() {
  if (!hardware) return null;
  try {
    return execFileSync('nvidia-smi', ['--query-gpu=index,name,uuid,memory.used,memory.total', '--format=csv,noheader,nounits'], { encoding: 'utf8', timeout: 1000 }).trim().split('\n').map(row => {
      const [index, name, uuid, used, total] = row.split(',').map(value => value.trim());
      return { index, name, uuid, usedBytes: Number(used) * 1024 * 1024, totalBytes: Number(total) * 1024 * 1024 };
    });
  } catch (_) { return null; }
}
report.gpuMemoryScope = 'Optional NVIDIA device-wide memory usage, includes other processes; null when unavailable. Unified-memory GPU allocation is not inferred from RSS.';
const extraArgs = JSON.parse(process.env.BENCHMARK_BROWSER_ARGS || '[]');
if (!Array.isArray(extraArgs) || !extraArgs.every(value => typeof value === 'string')) throw new Error('BENCHMARK_BROWSER_ARGS must be a JSON string array');
for (const entry of models) {
  const [engine, model] = entry.split(':');
  for (const mode of engine === 'onnx' ? (process.env.BENCHMARK_PROVIDERS || 'wasm,webgpu').split(',').map(preference => ({ preference, cpuThreads: 1, lowHeap: false })) : (process.env.BENCHMARK_CPU_MODES || 'baseline,lowheap,threaded').split(',').map(name => ({ preference: 'wasm', cpuThreads: name === 'threaded' ? 4 : 1, lowHeap: name === 'lowheap' }))) {
    const { preference, cpuThreads, lowHeap } = mode;
    const server = await runtime.launchServer({ headless: process.env.BENCHMARK_HEADED !== '1', args: runtime === chromium ? ['--disable-dev-shm-usage', '--enable-unsafe-webgpu', ...(hardware ? [] : ['--use-angle=swiftshader']), ...extraArgs] : [] });
    const browser = await runtime.connect(server.wsEndpoint());
    const measurement = { engine, model, preference, cpuThreads, lowHeap, runs: [] };
    try {
      const page = await browser.newPage();
      const uploads = [];
      page.context().on('request', request => {
        if (new URL(request.url()).origin !== new URL(target).origin && !['GET', 'HEAD'].includes(request.method())) uploads.push(request.url());
      });
      await page.addInitScript(() => { localStorage.setItem('flutter.ai_transparency_notice_seen', 'true'); localStorage.setItem('flutter.onboarding_completed', 'true'); });
      await page.goto(target, { waitUntil: 'domcontentloaded' });
      if (model.startsWith('phonon2')) {
        await page.goto(`${target}/#/models`);
        await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 60_000 });
        await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
        await page.getByRole('switch', { name: /Allow experimental browser models/ }).click();
        await page.getByRole('button', { name: 'I understand; show models', exact: true }).click();
      }
      await page.evaluate(({ preference, cpuThreads, lowHeap }) => { localStorage.setItem('flutter.browser_execution_provider', preference); localStorage.setItem('flutter.browser_cpu_threads', String(cpuThreads)); localStorage.setItem('cw.browserLowMemoryRuntime', String(lowHeap)); }, mode);
      measurement.gpu = await page.evaluate(async () => {
        const adapter = await Promise.race([navigator.gpu?.requestAdapter(), new Promise(resolve => setTimeout(() => resolve(null), 8000))]);
        return adapter ? { description: adapter.info?.description, vendor: adapter.info?.vendor, architecture: adapter.info?.architecture } : null;
      });
      if (hardware && (!measurement.gpu || ![measurement.gpu.vendor, measurement.gpu.architecture, measurement.gpu.description].some(Boolean) || /swiftshader|software|llvmpipe|lavapipe/i.test(JSON.stringify(measurement.gpu)))) throw new Error('Physical GPU adapter was not identified; hardware validation cannot pass');
      for (const temperature of ['cold', ...Array.from({ length: repetitions }, (_, index) => `warm-${index + 1}`)]) {
        console.log(`Assessing ${entry} / ${preference} / threads=${cpuThreads} / smallHeap=${lowHeap} / ${temperature}`);
        let peak = rss(server.process().pid), baseline = peak;
        const baselineGpuMemory = gpuMemory();
        const peakGpuMemory = baselineGpuMemory?.map(device => ({ ...device }));
        const timer = setInterval(() => {
          const current = rss(server.process().pid); if (current !== null) peak = Math.max(peak || 0, current);
          for (const device of gpuMemory() || []) {
            const previous = peakGpuMemory?.find(item => item.uuid === device.uuid);
            if (previous) previous.usedBytes = Math.max(previous.usedBytes, device.usedBytes);
          }
        }, hardware ? 1000 : 250);
        try {
          const result = await page.evaluate(async ({ engine, model, fixture, cold }) => {
            const bridge = window.CrisperBrowserSpeech, client = bridge.create(engine, true);
            try {
              if (cold) await client.request('clearCache', {});
              const loaded = await client.request('load', { model });
              const audio = await bridge.decode(new Uint8Array(fixture));
              const result = await client.request('transcribe', { audio, transferAudio: true });
              const transcript = result.segments.map(segment => segment.text).join(' ');
              return { loaded: loaded.diagnostics, inference: result.diagnostics, transcript, local: result.local };
            } finally { await client.dispose(); }
          }, { engine, model, fixture, cold: temperature === 'cold' });
          measurement.runs.push({ cache: temperature, ...result, baselineBrowserRssBytes: baseline, peakBrowserRssBytes: peak, baselineGpuMemory, peakGpuMemory });
          if (!result.local || !result.transcript.toLowerCase().includes('country')) throw new Error('Known local transcript check failed');
          if (hardware && preference === 'webgpu' && result.inference.provider !== 'webgpu') throw new Error('Hardware GPU inference fell back to CPU: ' + result.inference.fallbackReason);
          if (cpuThreads > 1 && result.inference.runtimeMode !== 'threaded') throw new Error('Requested threaded inference used the single-thread fallback');
          if (uploads.length) throw new Error('Unexpected off-origin upload during local inference');
        } finally { clearInterval(timer); }
      }
      const warm = measurement.runs.filter(run => run.cache !== 'cold').map(run => run.inference.elapsedMs).sort((a, b) => a - b);
      measurement.medianWarmInferenceMs = warm[Math.floor(warm.length / 2)];
      console.log(JSON.stringify(measurement));
    } catch (error) { measurement.error = String(error); process.exitCode = 1; console.log(JSON.stringify(measurement)); }
    finally {
      const normalized = text => text.toLowerCase().normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
      const baseline = report.results.find(item => item.engine === engine && item.model === model && item.preference === 'wasm' && item.cpuThreads === 1 && !item.lowHeap);
      if (baseline && measurement.runs.length && baseline.runs.length) {
        measurement.transcriptParity = measurement.runs.every(run => normalized(run.transcript) === normalized(baseline.runs[0].transcript));
        if (!measurement.transcriptParity) { measurement.error = 'Decoded transcript differs from the same-model CPU baseline'; process.exitCode = 1; }
      }
      report.results.push(measurement);
      await browser.close(); await server.close();
      await mkdir(directory, { recursive: true });
      await writeFile(new URL('results.json', directory), JSON.stringify(report, null, 2));
    }
  }
}
