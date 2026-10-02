CrispASR proxy-to-pthread WASM, initial memory 128 MiB (grows as needed).
Source: 70e15c9a0 (tag cw-browser-wasm-2026-10-02)
CI: https://github.com/CrispStrobe/CrispASR/actions/runs/37004439151
Artifact: crispasr-wasm-proxy-to-pthread-lowheap

The threaded integration starts its compute thread outside message handlers and
uses async model-open/transcription/synthesis bindings. The smaller SIMD single-thread runtime is the default after five-model
decoded parity and three-warm-run comparisons. Threading stays opt-in because
it slows some models; the original 512 MiB runtime remains for rollback. The application wrapper initiates explicit pool shutdown and coordinates
reloads. It captures the servicer pointer through the initialization import
and preserves root mailbox wakeups on the generated postMessage path.
Threaded WebKit selects that path automatically. The tiny worker entry
script uses no-store on Vercel to preserve isolation across worker restarts.
Native Dart package pins are independent.

SHA256:
71810d57aa03826eb3740b9f4a7030e80d19954ca05efe1fae2d344e67ee2cbc  libwhisper.js
6fd2cc60dd6e4dafde37c49a082ce65be04fd0c45a8d80fd94f9bba542cb6a72  libwhisper.wasm

License: MIT; see LICENSE and upstream dependency notices.
