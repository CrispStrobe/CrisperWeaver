CrispASR single-thread WASM, downloaded from the successful upstream CI run:
https://github.com/CrispStrobe/CrispASR/actions/runs/36969566593
Artifact: crispasr-wasm-single-thread
Source: b33138b057268f573757ded8258e4afef2461ea8

Single-thread is deliberate: the upstream default pthread build can deadlock
when invoked synchronously from a browser worker. Computation here runs in a
dedicated worker, leaving the Flutter UI responsive. This is independent of
the existing pinned native Dart package and does not change native builds.

SHA256:
c839006d538677ac8cfc3e5ca177cc2c99ee1b0d8574d3f8342bf25c3e1ae378  libwhisper.js
ad949d2d1146725aab5878b63062fd871c93b7ca3b3f5aee9b336237a246194d  libwhisper.wasm

License: MIT (see LICENSE and upstream repository for dependency notices).
