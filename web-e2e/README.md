# web-e2e — smoke test for the deployed web PWA

Covers the **app shell** of https://crisperweaver-web.vercel.app: bootstrap assets are
really served (not the SPA rewrite's `index.html`), Flutter boots and CanvasKit paints a
sized canvas, the EU AI Act transparency notice renders (read through Flutter's
accessibility tree, since the UI is a canvas), and the boot produces no console or uncaught
errors outside a justified allowlist in `tests/smoke.spec.ts`. It does **not** test
inference — the web build has no on-device engine and routes ASR/TTS to the CrispASR
HuggingFace Space.

Run: `npm ci && npx playwright install --with-deps chromium && npx playwright test`
(~1.5 min). Point it elsewhere with `BASE_URL=https://my-preview.vercel.app npx playwright
test`. CI runs it from the `smoke` job in `.github/workflows/deploy-web.yml`, after a
successful production deploy.

For the separate Lite preview, dispatch Deploy Web from the Lite branch:

```sh
gh workflow run deploy-web.yml --ref feat/macos-lite-ci -f flavor=lite
BASE_URL=https://crisperweaver-lite-web.vercel.app CW_FLAVOR=lite npx playwright test
```

The workflow creates/reuses the `crisperweaver-lite-web` Vercel project with
existing CI credentials and deploys there. It never targets the full web project.
Lite self-hosts CanvasKit, identifies itself in its title/manifest, and displays
an explicit browser preview notice: desktop ASR/TTS/ONNX engines are unavailable,
so speech uses a mock engine for UI testing. Browser tests also reject external
requests at startup except static fallback-font downloads, suppress saved cloud settings, and reject remote endpoints.
Screenshots from successful and failed runs are retained as CI artifacts.
