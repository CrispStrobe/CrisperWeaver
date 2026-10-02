import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { TARGET } from './target';
import { bootRuntime } from './runtime-page';
const normalize = (text: string) => text.toLowerCase().normalize('NFKD').replace(/\p{M}/gu, '').replace(/[^\p{L}\p{N}]+/gu, ' ').trim().split(/\s+/);
function wordErrorRate(expected: string, actual: string) {
  const a = normalize(expected), b = normalize(actual);
  let row = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const next = [i];
    for (let j = 1; j <= b.length; j++) next[j] = Math.min(next[j - 1] + 1, row[j] + 1, row[j - 1] + Number(a[i - 1] !== b[j - 1]));
    row = next;
  }
  return row[b.length] / a.length;
}
async function infer(page: any, fixture: number[], model: string, language: string, repeat: number, snr: number | null) {
  await bootRuntime(page);
  return page.evaluate(async ({ fixture, model, language, repeat, snr }: any) => {
    const bridge = (window as any).CrisperBrowserSpeech, client = bridge.create('onnx', true);
    try {
      await client.request('load', { model });
      const clip = await bridge.decode(new Uint8Array(fixture));
      const audio = new Float32Array(clip.length * repeat);
      for (let i = 0; i < repeat; i++) audio.set(clip, i * clip.length);
      if (snr !== null) {
        let seed = 192837;
        const rms = Math.sqrt(clip.reduce((sum: number, x: number) => sum + x * x, 0) / clip.length);
        const amplitude = Math.sqrt(3) * rms / 10 ** (snr / 20);
        for (let i = 0; i < audio.length; i++) {
          seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
          audio[i] = Math.max(-1, Math.min(1, audio[i] + (seed / 4294967296 * 2 - 1) * amplitude));
        }
      }
      // Measure this small model's isolated noisy-clip accuracy too. Long
      // recording loss must not be mistaken for its existing acoustic errors.
      const baseline = repeat > 1 && snr !== null
        ? await client.request('transcribe', { audio: audio.slice(0, clip.length), transferAudio: true, language }) : null;
      const result = await client.request('transcribe', { audio, transferAudio: true, language });
      return { ...result, baseline, duration: clip.length * repeat / 16000 };
    } finally { client.dispose(); }
  }, { fixture, model, language, repeat, snr });
}
function timestamps(result: any) {
  expect(result.local).toBe(true);
  expect(result.segments.length).toBeGreaterThan(1);
  let previous = 0;
  for (const s of result.segments) {
    expect(s.start).toBeGreaterThanOrEqual(previous - 0.02);
    expect(s.end).toBeGreaterThan(s.start);
    expect(s.end).toBeLessThanOrEqual(result.duration + 0.02);
    previous = s.end;
  }
}

test('continuous English recording retains all six utterances across window cuts', async ({ page }, info) => {
  test.setTimeout(900_000);
  const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures/jfk.wav')));
  const result = await infer(page, fixture, 'onnx-tiny.en', 'en', 6, null);
  const text = result.segments.map((s: any) => s.text).join(' ');
  const expected = Array(6).fill('And so my fellow Americans ask not what your country can do for you ask what you can do for your country').join(' ');
  const wer = wordErrorRate(expected, text);
  await info.attach('continuous-english.json', { body: Buffer.from(JSON.stringify({ result, wer })), contentType: 'application/json' });
  timestamps(result);
  expect(text.toLowerCase().match(/country/g)?.length).toBe(12);
  expect(wer).toBeLessThanOrEqual(0.15);
});

for (const language of ['fr', 'de']) {
  test(`real ${language} noisy speech retains utterances and isolated-clip quality over a long recording`, async ({ page }, info) => {
    test.setTimeout(1200_000);
    const manifest = JSON.parse(await readFile(path.join(__dirname, '../fixtures/fleurs.json'), 'utf8'));
    const entry = manifest.find((entry: any) => entry.language === language);
    const fixture = Array.from(await readFile(path.join(__dirname, '../fixtures', entry.file)));
    const result = await infer(page, fixture, 'onnx-whisper-base', language, 8, 20);
    const text = result.segments.map((s: any) => s.text).join(' ');
    const expected = Array(8).fill(entry.expected).join(' ');
    const wer = wordErrorRate(expected, text);
    const baselineText = result.baseline.segments.map((s: any) => s.text).join(' ');
    const baselineWer = wordErrorRate(entry.expected, baselineText);
    console.log(`${language}: isolated noisy WER=${baselineWer}, long WER=${wer}, text=${text}`);
    await info.attach(`continuous-${language}.json`, { body: Buffer.from(JSON.stringify({ result, wer, baselineWer, snrDb: 20, source: entry.source })), contentType: 'application/json' });
    timestamps(result);
    expect(result.duration).toBeGreaterThan(30);
    expect(wer).toBeLessThanOrEqual(baselineWer + 0.1);
    expect(wer).toBeLessThanOrEqual(0.6);
    // Count a recognizable marker per source utterance. This failed for the
    // former five-second boundary search (six of eight German starts survived).
    const marker = language === 'fr' ? /trentaine/g : /niederschlage/g;
    expect(normalize(text).join(' ').match(marker)?.length || 0).toBeGreaterThanOrEqual(7);
    expect(normalize(text).length / normalize(expected).length).toBeGreaterThanOrEqual(0.8);
    expect(normalize(text).length / normalize(expected).length).toBeLessThanOrEqual(1.2);
  });
}
