import { test, expect } from '@playwright/test';
import { bootRuntime } from './runtime-page';

for (const failure of ['operator', 'worker crash']) test(`GPU ${failure} failure preserves owned audio and restarts on CPU`, async ({ page }) => {
  await bootRuntime(page);
  const result = await page.evaluate(async failure => {
    const NativeWorker = window.Worker;
    const attempts: any[] = [];
    let workers = 0;
    class WorkerControl {
      onmessage: any;
      onerror: any;
      constructor() { workers++; }
      terminate() {}
      postMessage(message: any, transfer: any[]) {
        const data = structuredClone(message, { transfer });
        attempts.push({ op: data.op, preference: data.payload.executionPreference,
          audio: data.payload.audio ? Array.from(data.payload.audio) : null });
        if (failure === 'worker crash' && data.op === 'transcribe' && data.payload.executionPreference !== 'wasm') {
          queueMicrotask(() => this.onerror?.({ message: 'simulated GPU operator failure' }));
          return;
        }
        queueMicrotask(() => this.onmessage?.({ data: data.op === 'transcribe' && data.payload.executionPreference !== 'wasm'
          ? { id: data.id, error: 'CW_GPU_RESTART: simulated GPU operator failure' }
          : { id: data.id, result: { local: true, segments: [{ text: 'country' }], diagnostics: { provider: data.payload.executionPreference } } } }));
      }
    }
    (window as any).Worker = WorkerControl;
    localStorage.setItem('flutter.browser_execution_provider', 'webgpu');
    const client = (window as any).CrisperBrowserSpeech.create('onnx', true);
    try {
      await client.request('load', { model: 'onnx-tiny.en' });
      const audio = new Float32Array([0.25, -0.5, 0.75]);
      const output = await client.request('transcribe', { audio, transferAudio: true });
      return { output, attempts, workers, detached: audio.byteLength === 0 };
    } finally { client.dispose(); window.Worker = NativeWorker; }
  }, failure);
  expect(result.workers).toBe(2);
  expect(result.detached).toBe(true);
  const inferences = result.attempts.filter((attempt: any) => attempt.op === 'transcribe');
  expect(inferences.map((attempt: any) => attempt.preference)).toEqual(['webgpu', 'wasm']);
  expect(inferences[0].audio).toEqual([0.25, -0.5, 0.75]);
  expect(inferences[1].audio).toEqual(inferences[0].audio);
  expect(result.output.diagnostics.provider).toBe('wasm');
  expect(result.output.diagnostics.fallbackReason).toContain('GPU operator failure');
});

test('GPU watchdog allows progress and recovers an inactive inference', async ({ page }) => {
  await bootRuntime(page);
  await page.clock.install();
  await page.evaluate(async () => {
    const state: any = { workers: 0, attempts: [] };
    (window as any).gpuWatchdog = state;
    class WorkerControl {
      onmessage: any;
      constructor() { state.workers++; }
      terminate() {}
      postMessage(message: any, transfer: any[]) {
        const data = structuredClone(message, { transfer });
        if (data.op === 'transcribe' && data.payload.executionPreference !== 'wasm') {
          state.progress = () => this.onmessage?.({ data: { id: data.id, progress: 0.5 } });
          return;
        }
        state.attempts.push({ op: data.op, audio: data.payload.audio ? Array.from(data.payload.audio) : null });
        queueMicrotask(() => this.onmessage?.({ data: { id: data.id, result: {
          local: true, diagnostics: { provider: data.payload.executionPreference },
        } } }));
      }
    }
    (window as any).Worker = WorkerControl;
    localStorage.setItem('flutter.browser_execution_provider', 'webgpu');
    const client = (window as any).CrisperBrowserSpeech.create('onnx', true);
    await client.request('load', { model: 'onnx-tiny.en' });
    state.outcome = client.request('transcribe', { audio: new Float32Array([0.5]), transferAudio: true })
      .finally(() => client.dispose());
  });
  await page.clock.fastForward(119_000);
  expect(await page.evaluate(() => (window as any).gpuWatchdog.workers)).toBe(1);
  await page.evaluate(() => (window as any).gpuWatchdog.progress());
  await page.clock.fastForward(119_000);
  expect(await page.evaluate(() => (window as any).gpuWatchdog.workers)).toBe(1);
  await page.clock.fastForward(1_001);
  const result = await page.evaluate(async () => {
    const state = (window as any).gpuWatchdog;
    return { output: await state.outcome, workers: state.workers, attempts: state.attempts };
  });
  expect(result.workers).toBe(2);
  expect(result.output.diagnostics.provider).toBe('wasm');
  expect(result.output.diagnostics.fallbackReason).toContain('stalled');
  expect(result.attempts.find((attempt: any) => attempt.op === 'transcribe').audio).toEqual([0.5]);
});
