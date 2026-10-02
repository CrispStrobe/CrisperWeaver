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
