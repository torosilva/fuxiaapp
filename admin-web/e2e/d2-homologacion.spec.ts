import { expect, test } from '@playwright/test';

// Track D · D2 — Carolina's homologation screen (STAGING), READ-ONLY: nothing is confirmed, marked or reopened here.
// Decisions in the real homologation belong to Carolina; this only checks that the screen explains itself and loads.
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = 'e2e-screenshots/d2-homologacion';

test('D2 · homologación (woo_staging4): solo lectura', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();

  await page.getByRole('link', { name: 'Homologación' }).first().click();
  await expect(page.getByRole('heading', { name: 'Homologación' })).toBeVisible();
  await expect(page.getByTestId('homologation-summary')).toContainText('792');
  await expect(page.getByTestId('homologation-summary')).toContainText('129 productos Woo');
  await expect(page.getByTestId('how-to')).toBeVisible();
  await expect(page.getByTestId('progress')).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/01-resumen.png` });

  // open the detail of the first Woo product shown (variation ids, sizes, F360 proposal) — looking only
  await page.getByRole('button', { name: /Ver detalle/ }).first().click();
  await expect(page.getByTestId(/^variations-/).first()).toBeVisible();
  await page.getByTestId('filter-requiere_revision').click();
  await expect(page.locator('[data-testid^="group-"]').first()).toBeVisible();
  expect(errors).toEqual([]);
});
