import { test, expect } from '@playwright/test';
import { bootRuntime } from './runtime-page';

test('GPU inference failure preserves owned audio and restarts on CPU', async ({ page }) => {
  await bootRuntime(page);
  const result = await page.evaluate(async () => {
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
      return { output, attempts, workers };
    } finally { client.dispose(); window.Worker = NativeWorker; }
  });
  expect(result.workers).toBe(2);
  const inferences = result.attempts.filter((attempt: any) => attempt.op === 'transcribe');
  expect(inferences.map((attempt: any) => attempt.preference)).toEqual(['webgpu', 'wasm']);
  expect(inferences[0].audio).toEqual([0.25, -0.5, 0.75]);
  expect(inferences[1].audio).toEqual(inferences[0].audio);
  expect(result.output.diagnostics.provider).toBe('wasm');
  expect(result.output.diagnostics.fallbackReason).toContain('GPU operator failure');
});
