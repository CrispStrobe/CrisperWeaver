CrispASR proxy-to-pthread WASM, initial memory 128 MiB (grows as needed).
Source: 70e15c9a0 (feat/cw-browser-threads)
CI: https://github.com/CrispStrobe/CrispASR/actions/runs/37004439151
Artifact: crispasr-wasm-proxy-to-pthread-lowheap

The threaded integration starts its compute thread outside message handlers and
uses async model-open/transcription/synthesis bindings. Keep the original
single-thread runtime as the default until correctness/performance comparison
passes. Browser worker termination cancels the complete runtime and its pool.
Native Dart package pins are independent.

SHA256:
71810d57aa03826eb3740b9f4a7030e80d19954ca05efe1fae2d344e67ee2cbc  libwhisper.js
6fd2cc60dd6e4dafde37c49a082ce65be04fd0c45a8d80fd94f9bba542cb6a72  libwhisper.wasm

License: MIT; see LICENSE and upstream dependency notices.
