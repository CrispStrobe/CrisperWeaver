/// Smoke test for the deployed CrisperWeaver web PWA.
///
/// Scope is deliberately the app *shell*, not inference: the web build has no
/// on-device engine (`EngineFactory` routes ASR/TTS to the `cstr/CrispASR`
/// HuggingFace Space), so exercising transcription here would test someone
/// else's uptime. What this suite proves is that a production deploy actually
/// serves a bundle that boots and paints — the failure mode a broken
/// `deploy-web.yml`, a bad `--base-href`, or a missing `vercel.json` rewrite
/// produces, and the one nothing else in CI covers.
///
/// Flutter web paints into a `<canvas>`, so there is no DOM text to assert on
/// until the accessibility tree is built. Flutter only builds it on demand,
/// behind an off-screen `<flt-semantics-placeholder>` button; clicking that is
/// how a screen-reader user opts in, and it is how these tests read the UI.
///
/// The three browser tests share one cold boot (a worker-scoped fixture).
/// Fetching a ~5 MB dart2js bundle plus CanvasKit costs ~25s, and paying that
/// three times bought no extra coverage — only a suite too slow to keep.

import { test as base, expect, type Page } from '@playwright/test';
import { TARGET } from './target';

/// Console/uncaught-error messages we tolerate, each with the reason it is not
/// a regression. Anything not matched here fails the run.
const CONSOLE_ERROR_ALLOWLIST: { pattern: RegExp; why: string }[] = [
  {
    // Verified against the live deploy: the uncaught exception's
    // `dartException` stringifies to exactly this, on every load.
    pattern: /MissingPluginException\(No implementation found for method \w+ on channel plugins\.flutter\.io\/path_provider\)/,
    why: 'path_provider has no web implementation; main.dart catches it, logs "Failed to initialize services" and falls back to browser storage — expected on every web boot, not a deploy regression.',
  },
  {
    // CanvasKit ships from gstatic; `vercel.json` sets COEP: require-corp, so
    // a cross-origin asset arriving without CORP is reported here.
    pattern: /(canvaskit|gstatic\.com\/flutter-canvaskit)/i,
    why: 'CanvasKit is fetched cross-origin from gstatic.com under COEP require-corp; a transient CDN 4xx or CORP complaint is an upstream fetch problem, and a fatal one is already caught by the boot assertion, which fails when no canvas ever paints.',
  },
  {
    // The HF Space is cold-started on demand and is not part of the shell.
    pattern: /(huggingface\.co|hf\.space)/i,
    why: 'the HuggingFace Space backing ASR/TTS may be asleep or rate-limited; the shell must render regardless, and Space availability is explicitly out of scope for a shell smoke test.',
  },
];

interface PageErrors {
  /// Console messages Chromium classified as `error`.
  console: string[];
  /// Uncaught exceptions, captured in-page so dart2js errors stringify to
  /// their Dart `toString()`. Playwright's `pageerror` event reports only the
  /// useless wrapper message "Error" for these.
  uncaught: string[];
}

declare global {
  interface Window {
    __smokeUncaught?: string[];
  }
}

interface BootedApp {
  page: Page;
  errors: PageErrors;
  /// HTTP status of the initial document request.
  status: number;
}

/// Wait until the Flutter engine has attached a view and painted into it.
async function waitForFlutterBoot(page: Page): Promise<void> {
  // `flutter-view > flt-glass-pane` is the host element; the canvas lives in
  // its shadow root, so a plain `canvas` locator cannot see it.
  await expect(page.locator('flutter-view flt-glass-pane')).toBeAttached({ timeout: 60_000 });
  await expect
    .poll(
      () =>
        page.evaluate(() => {
          const pane = document.querySelector('flutter-view flt-glass-pane');
          const canvas = pane?.shadowRoot?.querySelector('canvas') as HTMLCanvasElement | null;
          return canvas ? canvas.width * canvas.height : 0;
        }),
      { timeout: 60_000, message: 'CanvasKit never painted a sized canvas' },
    )
    .toBeGreaterThan(0);
}

/// Set by the `app` fixture so `afterEach` can screenshot a failure without
/// *declaring* a dependency on it — declaring one would force the browserless
/// asset test to boot a browser it does not need.
let booted: BootedApp | undefined;

/// One cold boot of the deployed app, shared by every browser test in the
/// worker. Error capture is installed before any app script runs.
const test = base.extend<Record<string, never>, { app: BootedApp }>({
  app: [
    async ({ browser }, use) => {
      const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
      const page = await context.newPage();

      const errors: PageErrors = { console: [], uncaught: [] };
      page.on('console', (m) => {
        if (m.type() === 'error') errors.console.push(m.text());
      });
      await page.addInitScript(() => {
        window.__smokeUncaught = [];
        window.addEventListener('error', (ev) => {
          // dart2js hangs the real Dart object off `.dartException`.
          const err = ev.error as { dartException?: unknown } | undefined;
          window.__smokeUncaught!.push(String(err?.dartException ?? err ?? ev.message));
        });
        window.addEventListener('unhandledrejection', (ev) => {
          const r = ev.reason as { dartException?: unknown } | undefined;
          window.__smokeUncaught!.push(String(r?.dartException ?? r));
        });
      });

      // Published before navigating, so that a boot that never completes is
      // still screenshotted by `afterEach` rather than failing blind.
      booted = { page, errors, status: 0 };
      const response = await page.goto(`${TARGET}/`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
      booted.status = response!.status();
      await waitForFlutterBoot(page);

      await use(booted);
      booted = undefined;
      await context.close();
    },
    { scope: 'worker' },
  ],
});

// The three browser tests read one shared page in declaration order, so a
// failed boot should stop the block rather than report three copies of it.
test.describe.configure({ mode: 'serial' });

test.afterEach(async ({}, testInfo) => {
  if (testInfo.status !== testInfo.expectedStatus && booted) {
    await booted.page
      .screenshot({ path: testInfo.outputPath('failure.png'), fullPage: false })
      .catch(() => {});
  }
});

test.describe('CrisperWeaver web PWA — deployed shell', () => {
  test('serves the bootstrap files the app shell needs', async ({ request }) => {
    // Cheap and browserless: catches an empty deploy or a bundle whose
    // bootstrap assets never uploaded.
    //
    // Status alone would prove nothing here: `vercel.json` rewrites
    // `/(.*)` to `/index.html`, so a *missing* asset also answers 200 — with
    // the HTML shell. Every check below therefore asserts the content type
    // too, which the rewrite cannot fake.
    const index = await request.get(`${TARGET}/`);
    expect(index.status()).toBe(200);
    expect(await index.text()).toContain('flutter_bootstrap.js');

    const bootstrap = await request.get(`${TARGET}/flutter_bootstrap.js`);
    expect(bootstrap.status()).toBe(200);
    expect(bootstrap.headers()['content-type']).toContain('javascript');
    expect(await bootstrap.text()).toContain('main.dart.js');

    // A 64-byte range request, not a GET: the dart2js bundle is ~5 MB and its
    // size is the only thing worth asserting — a rewrite-served index.html
    // would be ~2 KB. `content-range` carries the true total; `content-length`
    // is absent on HEAD here because Vercel answers brotli-encoded.
    const bundle = await request.get(`${TARGET}/main.dart.js`, { headers: { Range: 'bytes=0-63' } });
    expect(bundle.status()).toBe(206);
    expect(bundle.headers()['content-type']).toContain('javascript');
    const total = Number(bundle.headers()['content-range']?.split('/')[1]);
    expect(total, 'main.dart.js should be the real bundle, not the SPA fallback').toBeGreaterThan(
      1_000_000,
    );

    for (const asset of ['/manifest.json', '/version.json']) {
      const res = await request.get(`${TARGET}${asset}`);
      expect(res.status(), `${asset} should be served`).toBe(200);
      expect(res.headers()['content-type'], `${asset} should be JSON`).toContain('json');
    }

    const version = await (await request.get(`${TARGET}/version.json`)).json();
    expect(version.app_name).toBe('crisper_weaver');
    // Reported, not asserted against a literal: pinning the version here would
    // make every release bump a red build.
    console.log(`deployed ${TARGET} → version ${version.version}+${version.build_number}`);
  });

  test('boots Flutter and paints the CanvasKit surface', async ({ app }) => {
    expect(app.status).toBe(200);
    await expect(app.page).toHaveTitle('CrisperWeaver');
    // The fixture already waited for a sized canvas; re-assert so this test
    // fails for its own reason rather than only through fixture teardown.
    await waitForFlutterBoot(app.page);
  });

  test('renders the AI-transparency notice in the accessibility tree', async ({ app }, testInfo) => {
    const { page } = app;

    // Opt into Flutter's accessibility tree. The placeholder sits off-viewport,
    // so Playwright's actionability check refuses a normal click; dispatching
    // the event in-page is what an assistive technology's activation amounts
    // to anyway.
    await expect(page.locator('flt-semantics-placeholder')).toBeAttached({ timeout: 60_000 });
    await page.evaluate(() => {
      const ph = document.querySelector('flt-semantics-placeholder') as HTMLElement | null;
      ph?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      ph?.click();
    });
    await expect(page.locator('flt-semantics-host flt-semantics').first()).toBeAttached({
      timeout: 30_000,
    });

    // On a fresh browser profile the EU AI Act Art. 50 notice is the first
    // thing shown (main.dart `_showFirstRunExperienceIfNeeded`); once
    // acknowledged, the app screen is there instead. Accept either, so this
    // asserts "the UI rendered" rather than "this exact route".
    await expect
      .poll(() => page.evaluate(() => document.body.innerText), {
        timeout: 30_000,
        message: 'no semantic text ever appeared — the app rendered nothing readable',
      })
      .toMatch(/AI-Powered Application|CrisperWeaver/);

    // When it is the notice, it must carry the web-specific disclosure that
    // inference leaves the device — the one legally load-bearing string that
    // differs between this build and the native ones.
    const text = await page.evaluate(() => document.body.innerText);
    if (text.includes('AI-Powered Application')) {
      await expect(page.locator('flt-semantics[role="alertdialog"]')).toBeAttached();
      expect(text).toContain('the browser build has no on-device engine');
    }

    // Keep one always-on artefact of what the deploy actually looks like.
    await page.screenshot({ path: testInfo.outputPath('shell.png') });
  });

  test('booted without unexpected console errors', async ({ app }) => {
    // Give late boot work (CanvasKit fonts, the HF engine probe) a chance to
    // fail loudly before we read the tally.
    await app.page.waitForTimeout(3_000);
    const uncaught = await app.page.evaluate(() => window.__smokeUncaught ?? []);

    const unexpected = [...app.errors.console, ...uncaught].filter(
      (m) => !CONSOLE_ERROR_ALLOWLIST.some(({ pattern }) => pattern.test(m)),
    );
    // Spell out what *is* tolerated, so a failing run tells whoever reads the
    // log whether the new error belongs on the list or is a real regression.
    const tolerated = CONSOLE_ERROR_ALLOWLIST.map(({ pattern, why }) => `  - ${pattern} — ${why}`);
    expect(
      unexpected,
      `unexpected browser errors:\n${unexpected.join('\n')}\n\nallowed, and why:\n${tolerated.join('\n')}`,
    ).toEqual([]);
  });
});
