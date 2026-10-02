import { test, expect, type Page } from '@playwright/test';
import { TARGET } from './target';

test.skip(process.env.CW_FLAVOR !== 'lite', 'Only the separate Lite deployment');

async function semantics(page: Page) {
  await expect(page.locator('flt-semantics-placeholder')).toBeAttached({ timeout: 60_000 });
  await page.evaluate(() => {
    const placeholder = document.querySelector('flt-semantics-placeholder') as HTMLElement;
    placeholder.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    placeholder.click();
  });
  await expect(page.locator('flt-semantics-host flt-semantics').first()).toBeAttached();
}

test('Lite branding, local speech disclosure, and no remote AI requests on boot', async ({ page, request }, info) => {
  const flavor = await (await request.get(`${TARGET}/flavor.json`)).json();
  expect(flavor).toMatchObject({ flavor: 'lite', remoteAi: false, modelDownloads: true, browserSpeech: true });
  const manifest = await (await request.get(`${TARGET}/manifest.json`)).json();
  expect(manifest.name).toBe('CrisperWeaver Lite');
  const outgoing: string[] = [];
  page.on('request', req => {
    const url = new URL(req.url());
    if (['http:', 'https:'].includes(url.protocol) && url.origin !== new URL(TARGET).origin) {
      // Flutter downloads fallback font files; these are static assets.
      const staticFont = req.method() === 'GET' && url.hostname === 'fonts.gstatic.com'
        && /^\/s\/(roboto|notosanssymbols)\//.test(url.pathname) && url.pathname.endsWith('.woff2');
      if (!staticFont) outgoing.push(`${req.method()} ${req.url()}`);
    }
  });
  await page.goto(TARGET, { waitUntil: 'domcontentloaded' });
  await semantics(page);
  await expect(page).toHaveTitle('CrisperWeaver Lite');
  await expect.poll(() => page.evaluate(() => document.body.innerText)).toContain('locally in your browser');
  const notice = await page.evaluate(() => document.body.innerText);
  expect(notice).toContain('ONNX Runtime Web');
  expect(notice).toContain('Remote AI services are disabled');
  await page.waitForTimeout(3_000);
  expect(outgoing).toEqual([]);
  await page.screenshot({ path: info.outputPath('lite-notice.png') });
});

test('saved cloud settings are suppressed and remote endpoints cannot be saved', async ({ page }, info) => {
  const remote: string[] = [];
  page.on('request', req => {
    if (/hf\.space|huggingface\.co|api\.openai\.com|chat\/completions/.test(req.url())) remote.push(req.url());
  });
  await page.addInitScript(() => {
    localStorage.setItem('flutter.ai_transparency_notice_seen', 'true');
    localStorage.setItem('flutter.onboarding_completed', 'true');
    localStorage.setItem('flutter.preferred_engine', JSON.stringify('hfspace'));
    localStorage.setItem('flutter.cloud_llm_api_url', JSON.stringify('https://api.openai.com/v1/chat/completions'));
    localStorage.setItem('flutter.cloud_llm_model', JSON.stringify('gpt-4o-mini'));
  });
  await page.goto(`${TARGET}/#/settings/cloud-llm`, { waitUntil: 'domcontentloaded' });
  await semantics(page);
  await expect.poll(() => page.evaluate(() => document.body.innerText)).toContain('Local model server (Ollama)');
  const fields = page.getByRole('textbox');
  await expect(fields).toHaveCount(3);
  await expect(fields.nth(0)).toHaveValue('');
  await fields.nth(0).click();
  await fields.nth(0).pressSequentially('https://api.openai.com/v1/chat/completions', { delay: 15 });
  await fields.nth(0).press('Tab');
  await page.getByRole('button', { name: 'SAVE', exact: true }).click();
  await expect.poll(() => page.evaluate(() => document.body.innerText)).toContain('Cloud models are unavailable');
  await expect(fields.nth(0)).toHaveValue('https://api.openai.com/v1/chat/completions');
  expect(remote).toEqual([]);
  await page.screenshot({ path: info.outputPath('lite-endpoint-rejected.png') });
});
