import { defineConfig, devices } from '@playwright/test';
import { TARGET } from './tests/target';

export default defineConfig({
  testDir: './tests',
  // Failure screenshots and the always-on shell screenshot land here.
  // Gitignored — see web-e2e/.gitignore.
  outputDir: './artifacts',
  fullyParallel: false,
  // One worker: the browser tests share a single cold boot through a
  // worker-scoped fixture, and a second worker would only re-download the
  // 5 MB bundle for nothing.
  workers: 1,
  forbidOnly: !!process.env.CI,
  // A cold CDN edge plus a 5 MB dart2js bundle plus CanvasKit is slow but not
  // flaky; one retry absorbs a genuinely dropped connection without hiding a
  // real regression.
  retries: process.env.CI ? 1 : 0,
  timeout: 90_000,
  expect: { timeout: 45_000 },
  reporter: process.env.CI ? [['list'], ['github']] : [['list']],

  use: {
    // Only the browserless asset test reads this; the app fixture builds its
    // own context and navigates to TARGET directly, so screenshots there are
    // taken explicitly rather than by the built-in `screenshot` option.
    baseURL: TARGET,
    // CanvasKit needs real WebGL; the bundled Chromium's SwiftShader provides
    // it headlessly. `--disable-dev-shm-usage` keeps a 64 MB /dev/shm (the
    // GitHub runner default) from crashing the GPU process mid-boot.
    launchOptions: { args: ['--disable-dev-shm-usage'] },
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
