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

Dispatch either deployment from a branch containing this workflow:

```sh
gh workflow run deploy-web.yml --ref feat/macos-lite-ci -f flavor=full
gh workflow run deploy-web.yml --ref feat/macos-lite-ci -f flavor=lite
```

Lite targets its own `crisperweaver-lite-web` Vercel project. Full targets the
existing `crisperweaver-web` project. CI self-hosts runtime assets and retains
screenshots, inference results, and failure traces.

To test a local production bundle, first build Flutter web and run
`scripts/build_browser_runtime.sh`, then from the repo root run
`node web-e2e/serve.mjs build/web`. Use `BASE_URL=http://127.0.0.1:8765` for tests.
