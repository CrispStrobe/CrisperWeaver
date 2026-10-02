import type { Page } from '@playwright/test';
import { TARGET } from './target';

// These checks exercise shipped workers. Flutter rendering and uploads are
// covered separately, keeping runtime checks independent of UI allocation.
export async function bootRuntime(page: Page) {
  const url = `${TARGET}/cw-browser-runtime-tests.html`;
  await page.route(url, route => route.fulfill({
    contentType: 'text/html',
    headers: { 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' },
    body: '<!doctype html><html><head><script src="/speech/bridge.js"></script></head><body>Local speech runtime check</body></html>',
  }));
  await page.goto(url);
}
