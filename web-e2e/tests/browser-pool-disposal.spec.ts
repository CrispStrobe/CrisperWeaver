import { test, expect } from '@playwright/test';
import { bootRuntime } from './runtime-page';
import { TARGET } from './target';
import { attachJson } from './evidence';

test('cancellation stops a busy nested worker and cancels a deferred reload', async ({ page }, info) => {
  await bootRuntime(page);
  const result = await page.evaluate(async ({ target }) => {
    const counter = new Int32Array(new SharedArrayBuffer(16));
    const childCode = "self.onmessage=({data})=>{const a=new Int32Array(data);while(!Atomics.load(a,1)){Atomics.add(a,0,1);Atomics.wait(a,2,0,10)}}";
    const engine = `self.onmessage=async({data})=>{
      if(data.payload.counter){
        const child=new Worker(URL.createObjectURL(new Blob([${JSON.stringify(childCode)}],{type:'application/javascript'})));
        child.postMessage(data.payload.counter);
        const a=new Int32Array(data.payload.counter);
        while(!Atomics.load(a,0)) await new Promise(r=>setTimeout(r,10));
      }
      self.postMessage({id:data.id,result:{loaded:true}});
    };`;
    // Use the actual shipped wrapper with a tiny controlled computation,
    // avoiding AI downloads while exercising real nested-worker termination.
    const source = (await (await fetch(target + '/speech/worker.js')).text())
      .replace("importScripts('./compat.js');", `importScripts(${JSON.stringify(target + '/speech/compat.js')});`)
      .replace("importScripts('./engine-worker.js');", engine);
    const rootUrl = URL.createObjectURL(new Blob([source], { type: 'application/javascript' }));
    const NativeWorker = window.Worker;
    (window as any).Worker = class extends NativeWorker {
      constructor(url: string | URL, options?: WorkerOptions) {
        super(String(url).includes('/speech/worker.js') ? rootUrl : url, options);
      }
    };
    localStorage.setItem('flutter.browser_cpu_threads', '4');
    const client = (window as any).CrisperBrowserSpeech.create('crispasr', false);
    try {
      await client.request('load', { model: 'control', counter: counter.buffer });
      client.cancel();
      const cleanup = client.teardown;
      const pending = client.request('load', { model: 'control' }).then(() => '', (error: Error) => error.message);
      client.cancel();
      const cancellation = await pending;
      const disposal = await cleanup;
      const workerAbsent = client.worker === null;
      // Chromium allows a two-second grace period before forcibly stopping
      // an active script; acknowledgement confirms dispatch, not interruption.
      await new Promise(resolve => setTimeout(resolve, 3_000));
      const after = Atomics.load(counter, 0);
      await new Promise(resolve => setTimeout(resolve, 100));
      const later = Atomics.load(counter, 0);
      await client.request('load', { model: 'control' });
      await client.dispose();
      return { disposal, cancellation, workerAbsent, after, later };
    } finally {
      Atomics.store(counter, 1, 1); Atomics.notify(counter, 2);
      await client.dispose();
      (window as any).Worker = NativeWorker;
      URL.revokeObjectURL(rootUrl);
    }
  }, { target: TARGET });
  await attachJson(info, 'pool-disposal.json', result);
  expect(result.disposal.children).toBe(1);
  expect(result.disposal.forced).not.toBe(true);
  expect(result.cancellation).toContain('cancelled');
  expect(result.workerAbsent).toBe(true);
  expect(result.after).toBeGreaterThan(0);
  expect(result.later).toBe(result.after);
});

test('pthread mailbox messages wake the root servicer and preserve peer targets', async ({ page }, info) => {
  await bootRuntime(page);
  const result = await page.evaluate(async ({ target }) => {
    const childCode = "self.onmessage=()=>{self.postMessage({cmd:3});self.postMessage({cmd:4,targetThread:11});self.postMessage({cmd:4,targetThread:22})}";
    const engine = `self.CW_ROOT_PTHREAD=11;
      self.onmessage=({data:request})=>{
        const childUrl=URL.createObjectURL(new Blob([${JSON.stringify(childCode)}],{type:'application/javascript'}));
        const child=new Worker(childUrl);
        let received=0, drained=0;
        const forwarded=[];
        // Model the generated handler's routing order. The shipped wrapper's
        // earlier listener must remove only the root target before this runs.
        child.onmessage=({data})=>{
          received++;
          if(data.targetThread) forwarded.push(data.targetThread);
          else if(data.cmd===4) drained++;
          if(received===3){
            child.terminate(); URL.revokeObjectURL(childUrl);
            self.postMessage({id:request.id,result:{drained,forwarded}});
          }
        };
        child.postMessage('wake');
      };`;
    const source = (await (await fetch(target + '/speech/worker.js')).text())
      .replace("importScripts('./compat.js');", `importScripts(${JSON.stringify(target + '/speech/compat.js')});`)
      .replace("importScripts('./engine-worker.js');", engine);
    const rootUrl = URL.createObjectURL(new Blob([source], { type: 'application/javascript' }));
    const NativeWorker = window.Worker;
    (window as any).Worker = class extends NativeWorker {
      constructor(url: string | URL, options?: WorkerOptions) {
        super(String(url).includes('/speech/worker.js') ? rootUrl : url, options);
      }
    };
    localStorage.setItem('flutter.browser_cpu_threads', '4');
    const client = (window as any).CrisperBrowserSpeech.create('crispasr', false);
    try {
      const routing = await client.request('load', { model: 'mailbox-control' });
      return { routing, stage: client.workerStage };
    } finally {
      await client.dispose();
      (window as any).Worker = NativeWorker;
      URL.revokeObjectURL(rootUrl);
    }
  }, { target: TARGET });
  await attachJson(info, 'mailbox-routing.json', result);
  expect(result.routing.drained).toBe(1);
  expect(result.routing.forwarded).toEqual([22]);
  expect(result.stage).toBe('pthread-workers-ready-1');
});
