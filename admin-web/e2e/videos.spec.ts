import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';

// Videos en el producto (20261101000100). STAGING ONLY. Carolina (demo) adds a video to a colour from the product page,
// sees it, the "Agregar video" tile disappears at the limit of 2, and removes it again (the colour ends as it started).
// Needs: STAGING_DEMO_CAROLINA_PASSWORD, F360_VIDEO_FILE (a small mp4), F360_VIDEO_PRODUCT (default Cucarron).
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const FILE = process.env.F360_VIDEO_FILE ?? '';
const PRODUCT = process.env.F360_VIDEO_PRODUCT ?? 'Cucarron';
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/videos';

test('Carolina sube y quita un video de un color', async ({ page }) => {
  test.setTimeout(180_000);
  expect(PASSWORD, 'STAGING_DEMO_CAROLINA_PASSWORD must be set').not.toBe('');
  expect(FILE, 'F360_VIDEO_FILE must be set').not.toBe('');
  await page.setViewportSize({ width: 1280, height: 900 });
  // "Este no es el sistema real" (staging only) appears after hydration: mark it as seen before any page loads.
  await page.addInitScript(() => { try { sessionStorage.setItem('f360-staging-notice', '1'); } catch { /* ignore */ } });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();

  await page.goto(`/productos?q=${encodeURIComponent(PRODUCT)}`);
  await page.getByRole('link', { name: new RegExp(PRODUCT) }).first().click();
  await page.waitForURL(/\/productos\/[0-9a-f-]{36}/);
  const section = page.getByTestId('color-videos');
  await expect(section).toBeVisible();
  const before = await section.locator('video').count();
  test.skip(before >= 2, 'este color ya tiene 2 videos');

  await section.locator('input[type="file"]').setInputFiles({ name: 'prueba.mp4', mimeType: 'video/mp4', buffer: readFileSync(FILE) });
  await expect(section.locator('video')).toHaveCount(before + 1, { timeout: 60_000 });
  if (before + 1 === 2) await expect(section.getByRole('button', { name: /Agregar video/ })).toHaveCount(0);
  await page.screenshot({ path: `${SHOTS}/01-video-agregado.png`, fullPage: true });

  await section.getByRole('button', { name: 'Quitar video' }).last().click();
  await expect(section.locator('video')).toHaveCount(before, { timeout: 30_000 });
  await expect(section.getByRole('button', { name: /Agregar video/ })).toBeVisible();
});
