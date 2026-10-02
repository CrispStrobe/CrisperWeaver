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
worker termination, owned-buffer transfer, long repeated speech across quiet
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
software GPU execution, not a physical-GPU speed claim. Linux RSS is sampled
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
IndexedDB checkpoints use 4 MB parts, and verified cache promotion streams
those parts. Storage temporarily needs both checkpoints and verified cache.
Web Locks serialize a model's downloads and protect cleanup where supported.
