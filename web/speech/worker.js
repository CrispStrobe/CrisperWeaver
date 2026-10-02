// The Emscripten pthread workers reuse this URL. They only bootstrap the
// runtime; they must never run the speech protocol or recursively start a pool.
importScripts('./compat.js');
if (self.name === 'em-pthread') {
  importScripts(new URL('../wasm/crispasr-threaded/libwhisper.js', self.location.href).href);
} else {
  importScripts('./engine-worker.js');
}
