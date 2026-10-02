# Browser tests

Both web flavors run speech recognition locally with CrispASR WASM or ONNX
Runtime Web. Speech synthesis uses the local CrispASR WASM Kokoro backend.
Full additionally offers explicitly selected cloud processing; Lite blocks it.

```sh
npm ci
npx playwright install --with-deps chromium
BASE_URL=https://crisperweaver-web.vercel.app CW_FLAVOR=full npx playwright test
BASE_URL=https://crisperweaver-lite-web.vercel.app CW_FLAVOR=lite npx playwright test
```

The suite checks bootstrap assets, Flutter rendering, disclosures, and Lite's
endpoint restrictions. Real inference tests use the JFK speech fixture and
actual downloaded model weights, assert known transcript words and timestamps,
then create a fresh worker and repeat with off-origin requests blocked. The
upload-flow tests verify real text appears through Flutter. Local synthesis
must return non-silent PCM. Network checks reject off-origin uploads.

The expanded model suite also runs Moonshine through both runtimes, FastConformer, and ONNX
Whisper base, including fresh-worker cache reuse. It checks that hidden models
cannot load before the user enables the browser override, and that enabling
the setting requires accepting the crash warning. Phonon-2 GGUF variants and
the remaining native ASR catalogue are experimental candidates; they are not
part of the default supported-model list. Showing them does not establish that
their backend, extra files or working memory fit a particular browser.

Dispatch either deployment from a branch containing this workflow:

```sh
gh workflow run deploy-web.yml --ref main -f flavor=full
gh workflow run deploy-web.yml --ref main -f flavor=lite
```

For an isolated experimental-model assessment, add `-f probe_model=phonon2-q4_k`
(or `phonon2-q8_0`). The extra CI job accepts the actual UI warning, loads the
deployed model, transcribes known speech, checks for off-origin uploads, and
retains `browser-model-probe-<model>/result.json`. Assessment failures fail that
job while the normal model suite runs independently.

Phonon-2 Q4 passed this real Chromium assessment in
[run 36983351056](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/36983351056):
about 9 seconds to load, 47 seconds including transcription of the 11-second
fixture. The worker copies resizable WASM memory slices for TextDecoder and
Web Crypto calls that reject those views. Q4 remains opt-in because a
memory-constrained local host crashed during an earlier loading attempt;
Q8 and F16 have not been assessed successfully.

The same deployed worker passed the full production suites on 2026-10-02:
[Full: 15 passed, 2 Lite-only tests skipped](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/36983354146),
[Lite: 17 passed, plus the isolated Q4 assessment](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/36983351056).
These timings describe one Chromium runner and one fixture, not a speed or
memory guarantee for other devices. Pushes to `main` deploy Full; dispatch
`flavor=lite` separately to update Lite. Neither workflow submits to Apple.

Lite targets its own `crisperweaver-lite-web` Vercel project. Full targets the
existing `crisperweaver-web` project. CI self-hosts runtime assets and retains
screenshots, inference results, and failure traces.

To test a local production bundle, first build Flutter web and run
`scripts/build_browser_runtime.sh`, then from the repo root run
`node web-e2e/serve.mjs build/web`. Use `BASE_URL=http://127.0.0.1:8765` for tests.

## Browser optimization checks and benchmarks

`browser-optimizations.spec.ts` checks interrupted checkpoints, valid/invalid
HTTP ranges, servers that ignore ranges, download/cache checksum rejection,
large verified chunk storage and cleanup, worker termination, owned-buffer transfer, long repeated speech across quiet
boundaries, local WASM recovery after a GPU adapter failure, and resumption
against the actual pinned Hugging Face model host.

CPU is the production default. GPU selection requires its own acknowledgement;
it never bypasses the large-model warning or Lite network policy. Unsupported
GPU adapters/models/operators fall back to local WASM, while initialization
that stalls its worker is terminated and retried on CPU. Driver/tab crashes
cannot recover automatically. Browser backend coverage is not proof of GPU
support on every device.

To retain cold/warm measurements from an isolated deployed build:

```sh
gh workflow run deploy-web.yml --ref main -f flavor=lite -f benchmark_models=true
BASE_URL=http://127.0.0.1:8765 node scripts/benchmark_browser_models.mjs
```

The CI artifact `browser-model-benchmark-<flavor>/results.json` records known
speech results, actual execution provider, fallback reasons, load/inference
time and memory scope. `BENCHMARK_MODELS=onnx:onnx-moonshine-tiny` selects a
subset; `BENCHMARK_PROVIDERS=wasm,webgpu` chooses ONNX cases. Chromium is
launched with SwiftShader enabled to assess the GPU path on Linux CI; this is
software GPU execution, not a physical-GPU speed claim. Both tested ONNX
models crashed this renderer during the first assessment; detected software
adapters now use WASM and record the fallback reason. Linux RSS is sampled
every 250 ms across this benchmark's Chromium process tree, includes baseline
and per-process shared mappings, and can miss short peaks. Native WASM
allocated bytes are recorded separately; missing memory measurements are
`null`, never invented estimates. Keep benchmarks separate from local
Playwright runs, which clean their artifact directory.

The checked-in `web/speech/model-lock.json` contains immutable revisions,
exact sizes and SHA-256 hashes. Builds copy it without contacting Hub metadata.
Refresh deliberately with `python3 scripts/lock_browser_models.py`, then
review and rerun inference. Noble's pinned incremental SHA-256 implementation
is bundled locally, avoiding another full-model Web Crypto digest copy.
IndexedDB checkpoints use 4 MB parts. Models of every size retain verified
chunks as their persistent cache, avoiding giant-response promotion, duplicate
stored copies and WebKit's loss of dedicated-worker CacheStorage entries after
worker termination. Legacy CacheStorage entries remain readable until removed.
Web Locks serialize a model's downloads and protect cleanup where supported.

### Recorded measurements (2026-10-02)

[Isolated Chromium benchmark](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/36994514268/job/110798664233)
on `af53082`: all 12 cold/warm runs returned the expected local speech with
no off-origin uploads. These are single observations for an 11-second fixture,
not device guarantees or a before/after speed comparison. Peak RSS below is
the largest sampled whole-browser process-tree value across the two runs.

| Model / runtime | Cold load | Warm load | Inference cold / warm | Peak browser RSS |
|---|---:|---:|---:|---:|
| Moonshine Tiny Q4 / CrispASR | 2.90 s | 0.46 s | 2.62 / 2.34 s | 1.17 GB |
| FastConformer Q4 / CrispASR | 3.81 s | 1.05 s | 8.86 / 8.88 s | 1.58 GB |
| Moonshine Tiny / ONNX WASM | 4.62 s | 3.20 s | 0.94 / 0.89 s | 1.45 GB |
| Whisper Tiny English / ONNX WASM | 3.54 s | 2.46 s | 2.34 / 2.29 s | 1.56 GB |

The four requested-WebGPU runs used WASM after detecting SwiftShader and
recorded that reason. No hardware GPU acceleration was validated here.
[Phonon-2 Q4 assessment](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/36994514268/job/110798664231)
also passed through verified chunk storage: 12.14 s load, 31.10 s inference,
43.29 s total and 896 MB observed WASM allocation. The latter excludes other
browser allocations and is not comparable to whole-browser RSS above.


## Browser hardening validation (in progress)

Two/four-thread real ASR, cancellation and downloads-disabled reload pass in
Chromium, Firefox and WebKit. All three pass four-thread Kokoro→Moonshine
round trips. The 12 storage-recovery checks and the three fresh-worker GPU
recovery controls pass. Compiled Full/Lite CI is still running; build/export
checks alone do not prove inference. Evidence and benchmark scope are recorded
in [the report](../docs/browser-hardening-2026-10-02/README.md).

The browser matrix now includes Chromium, Firefox and WebKit for both flavors.
To validate a compiled artifact on isolated runners before changing production:

```sh
gh workflow run deploy-web.yml --ref feat/browser-hardening -f flavor=full -f validate_only=true -f benchmark_models=true
gh workflow run deploy-web.yml --ref feat/browser-hardening -f flavor=lite -f validate_only=true
```

Recording checks use continuous repeated English speech and real French/German
FLEURS recordings with deterministic 20 dB background noise. They measure word
error rate, missing/extra words, and monotonic bounded timestamps. Synthetic
noise and repetition are deliberate stress fixtures; these are not a claim of
accuracy on arbitrary real-world recordings. See fixtures/README.md for licenses.

Storage checks cover committed checkpoints after reload, insufficient quota,
failed writes, evicted parts/cache, and verified streaming cache invalidation.
ONNX downloads verify/persist using a 4 MiB staging buffer without allocating a
second full-model destination. A loader may still allocate full weight buffers.

CrispASR CPU settings offer one, two or four threads. One remains the default.
Parallel mode requires cross-origin isolation and SharedArrayBuffer. Startup
runs outside message handlers; model-open/ASR/TTS calls are proxied asynchronously
to the compute thread. Failed parallel loading retries on one-thread CPU. Tests
require actual threaded diagnostics, known speech, cancellation/reload, and a
TTS-to-ASR round trip. Passing a single-thread fallback does not count as proof.

The original 512 MiB runtime remains available. The new 128 MiB initial-heap
single-thread runtime is an A/B candidate (`cw.browserLowMemoryRuntime=true`),
not yet the default. Both grow as needed. Benchmarks compare all three modes,
report cold load plus median of at least three warm inferences, decoded parity,
WASM allocated bytes and sampled browser RSS. Phonon Q4 runs in its own CI job.

### Physical GPU evidence

`browser-hardware-gpu.yml` targets an existing GPU runner selected by JSON
labels. It rejects software adapters and CPU fallback, checks the real decoded
transcript against CPU, and records adapter identity and three warm runs. This
host has a virtual adapter; physical validation instead ran on Kaggle Tesla
T4 using the same Full/Lite worker assets. Moonshine tiny and Whisper tiny
English fp32 both complete actual WebGPU inference, match decoded CPU output
and have three warm runs. See the report linked above. CPU q8 remains default;
GPU fp32 downloads larger weights. Other GPUs/models remain experimental.

```sh
gh workflow run browser-hardware-gpu.yml --ref main \
  -f runner_labels='["self-hosted","browser-gpu"]' \
  -f base_url=https://crisperweaver-lite-web.vercel.app
```

For local driver setup the benchmark accepts `BENCHMARK_BROWSER_ARGS` as a
JSON string array and `BENCHMARK_HEADED=1` (use Xvfb if required on Linux).
Optional NVIDIA device-wide memory samples include other processes; missing
VRAM counters stay null. Apple unified GPU memory is not inferred from RSS.
