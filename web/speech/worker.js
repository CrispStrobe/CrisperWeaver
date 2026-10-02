// WebKit's waitAsync path intermittently stalls real cached model opening.
// Use Emscripten's postMessage mailbox path in both servicer and pthreads.
// The explicit URL mode supports controlled comparison without changing WASM.
{
  const parameters = new URL(self.location.href).searchParams;
  const webkit = /AppleWebKit/.test(navigator.userAgent) && !/(?:Chrome|Chromium|Edg|OPR)\//.test(navigator.userAgent);
  if ((parameters.get('runtime') === 'threaded' || self.name === 'em-pthread') &&
      (parameters.get('mailbox') === 'message' || webkit && parameters.get('mailbox') !== 'waitAsync')) Atomics.waitAsync = undefined;
}
// The Emscripten pthread workers reuse this URL. They only bootstrap the
// runtime; they must never run the speech protocol or recursively start a pool.
importScripts('./compat.js');
if (self.name === 'em-pthread') {
  importScripts(new URL('../wasm/crispasr-threaded/libwhisper.js', self.location.href).href);
} else {
  // Initiate pool shutdown explicitly while the asynchronous servicer can
  // still handle messages, then acknowledge disposal before a new load.
  const children = new Set();
  let ready = 0;
  const NativeWorker = self.Worker;
  self.Worker = class extends NativeWorker {
    constructor(...args) {
      super(...args); children.add(this);
      this.addEventListener('message', ({ data }) => {
        // The servicer is not a pool pthread. Let the generated handler's
        // case 4 drain its mailbox instead of discarding the root target.
        if (data?.cmd === 4 && data.targetThread === self.CW_ROOT_PTHREAD) delete data.targetThread;
        if (data?.cmd === 3 || data?.cmd === 'loaded') self.postMessage({ runtimeStage: `pthread-workers-ready-${++ready}` });
      });
    }
    terminate() { children.delete(this); super.terminate(); }
  };
  self.addEventListener('message', event => {
    if (event.data?.op !== 'cw-dispose-pool') return;
    event.stopImmediatePropagation();
    const count = children.size;
    for (const child of children) child.terminate();
    self.postMessage({ cwPoolDisposed: true, children: count });
    self.close();
  });
  importScripts('./engine-worker.js');
}
