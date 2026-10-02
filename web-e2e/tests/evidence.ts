import type { TestInfo } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

export async function attachJson(info: TestInfo, name: string, value: unknown) {
  const file = info.outputPath(name);
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(value, null, 2));
  await info.attach(name, { path: file, contentType: 'application/json' });
}
