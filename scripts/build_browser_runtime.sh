#!/usr/bin/env bash
# Self-host the pinned ONNX runtime and Transformers.js assets.
set -euo pipefail
cd "$(dirname "$0")/.."
npm ci --ignore-scripts --no-audit --no-fund --prefix web-runtime
mkdir -p build/web/vendor/ort
cp web-runtime/node_modules/@huggingface/transformers/dist/transformers.min.js build/web/vendor/transformers.web.js
cp web-runtime/node_modules/onnxruntime-web/dist/ort-wasm-simd-threaded*.wasm build/web/vendor/ort/
cp web-runtime/node_modules/onnxruntime-web/dist/ort-wasm-simd-threaded*.mjs build/web/vendor/ort/
cp web-runtime/node_modules/@huggingface/transformers/LICENSE build/web/vendor/TRANSFORMERS_LICENSE
cp web-runtime/node_modules/onnxruntime-web/README.md build/web/vendor/ort/README.md
python3 scripts/build_browser_catalog.py
node --input-type=module <<'JS'
import { build } from './web-runtime/node_modules/esbuild/lib/main.js';
await build({ stdin: { contents: "export { sha256 } from '@noble/hashes/sha256';", resolveDir: 'web-runtime' },
  bundle: true, format: 'esm', minify: true, outfile: 'build/web/vendor/sha256.js' });
JS
cp web-runtime/node_modules/@noble/hashes/LICENSE build/web/vendor/NOBLE_LICENSE
