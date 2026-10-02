import { expect, type Locator } from '@playwright/test';

// Flutter's semantics input and editing controller settle asynchronously.
// Use real editing events; DOM fill can leave the controller unchanged.
export async function typeFlutterText(field: Locator, value: string) {
  await field.click();
  await expect(field).toBeFocused();
  await expect(async () => {
    await field.press('ControlOrMeta+A');
    await field.press('Backspace');
    await expect(field).toHaveValue('', { timeout: 1_000 });
    await field.pressSequentially(value, { delay: 30 });
    await expect(field).toHaveValue(value, { timeout: 1_000 });
  }).toPass({ timeout: 15_000 });
  await field.press('Tab');
  await expect(field).toHaveValue(value);
}
