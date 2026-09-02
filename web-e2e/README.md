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
