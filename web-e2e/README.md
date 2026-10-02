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
gh workflow run deploy-web.yml --ref feat/macos-lite-ci -f flavor=full
gh workflow run deploy-web.yml --ref feat/macos-lite-ci -f flavor=lite
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

Lite targets its own `crisperweaver-lite-web` Vercel project. Full targets the
existing `crisperweaver-web` project. CI self-hosts runtime assets and retains
screenshots, inference results, and failure traces.

To test a local production bundle, first build Flutter web and run
`scripts/build_browser_runtime.sh`, then from the repo root run
`node web-e2e/serve.mjs build/web`. Use `BASE_URL=http://127.0.0.1:8765` for tests.
