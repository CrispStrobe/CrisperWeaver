// Emscripten uses resizable WASM memory views. Chromium's TextDecoder rejects
// such views; copy only the bounded string slice before decoding. Keep the
// vendored runtime unchanged so its upstream checksum remains verifiable.
const decodeText = TextDecoder.prototype.decode;
TextDecoder.prototype.decode = function (input, options) {
  if (ArrayBuffer.isView(input) && (input.buffer.resizable || (typeof SharedArrayBuffer !== 'undefined' && input.buffer instanceof SharedArrayBuffer))) input = new Uint8Array(input.buffer, input.byteOffset, input.byteLength).slice();
  return decodeText.call(this, input, options);
};
// Web Crypto also rejects resizable WASM views. Fill a fixed buffer, then
// copy back into the original view; preserve native type and size validation.
const randomValues = crypto.getRandomValues.bind(crypto);
crypto.getRandomValues = function (input) {
  if (ArrayBuffer.isView(input) && (input.buffer.resizable || (typeof SharedArrayBuffer !== 'undefined' && input.buffer instanceof SharedArrayBuffer))) {
    const fixed = new input.constructor(input.length);
    randomValues(fixed); input.set(fixed); return input;
  }
  return randomValues(input);
};
