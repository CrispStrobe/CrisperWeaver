import type { Page } from '@playwright/test';
import { TARGET } from './target';

// These checks exercise shipped workers. Flutter rendering and uploads are
// covered separately, keeping runtime checks independent of UI allocation.
export async function bootRuntime(page: Page) {
  // Use a real same-origin response so WebKit applies the server's isolation
  // headers. Route-fulfilled synthetic HTML can lose isolation on later pages.
  await page.goto(`${TARGET}/speech/bridge.js`);
  await page.evaluate(() => {
    const base = document.createElement('base'); base.href = location.origin + '/';
    document.head.appendChild(base);
  });
  await page.addScriptTag({ url: `${TARGET}/speech/bridge.js` });
}
