CrispASR proxy-to-pthread WASM, initial memory 128 MiB (grows as needed).
Source: ed2fdda49 (feat/cw-browser-threads)
CI: https://github.com/CrispStrobe/CrispASR/actions/runs/36999311622
Artifact: crispasr-wasm-proxy-to-pthread-lowheap

The threaded integration starts its compute thread outside message handlers and
uses async model-open/transcription/synthesis bindings. Keep the original
single-thread runtime as the default until correctness/performance comparison
passes. Browser worker termination cancels the complete runtime and its pool.
Native Dart package pins are independent.

SHA256:
11849c6cec1a6c4a9de1f1ea383bc3dd97fbf035095e67476182da4d50c63994  libwhisper.js
554aaae0a99f597c732c0b2755a602f58445a6f98ce3b0094137cc80eb4fb011  libwhisper.wasm

License: MIT; see LICENSE and upstream dependency notices.
