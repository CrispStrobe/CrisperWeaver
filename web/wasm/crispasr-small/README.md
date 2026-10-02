CrispASR single-thread WASM, initial memory 128 MiB (grows as needed).
Source: 70e15c9a0 (feat/cw-browser-threads)
CI: https://github.com/CrispStrobe/CrispASR/actions/runs/37004439151
Artifact: crispasr-wasm-single-thread-lowheap

The threaded integration starts its compute thread outside message handlers and
uses async model-open/transcription/synthesis bindings. Keep the original
single-thread runtime as the default until correctness/performance comparison
passes. Browser worker termination cancels the complete runtime and its pool.
Native Dart package pins are independent.

SHA256:
c839006d538677ac8cfc3e5ca177cc2c99ee1b0d8574d3f8342bf25c3e1ae378  libwhisper.js
567ee14e2d0a85aebc07e51e08e71fca437a7c3630acb68bcc7357760970edc9  libwhisper.wasm

License: MIT; see LICENSE and upstream dependency notices.
