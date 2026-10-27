import { expect, test, type Page } from '@playwright/test';

// Growth P0 E2E (STAGING ONLY): Instagram tab (not connected yet → says so, still shows the Instagram sales from Woo) and the
// experiments register (draft → approve → run → close, as Mario demo/owner). Writes one experiment labelled "Prueba e2e" in staging
// (experiments cannot be deleted; the nightly prod→staging copy removes it). Desktop + phone shots, no horizontal scroll.
// Run: F360_BASE_URL=http://localhost:3100 npx playwright test e2e/growth-p0.spec.ts
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/growth-p0';
const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });
const noOverflow = async (page: Page) => expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(1);

async function login(page: Page) {
  await page.addInitScript(() => { try { sessionStorage.setItem('f360-staging-notice', '1'); } catch { /* notice stays */ } });
  await page.goto('/login');
  await page.getByLabel('Correo').fill('mario.demo@staging.invalid');
  await page.getByLabel('Contraseña').fill(process.env.STAGING_DEMO_MARIO_PASSWORD ?? '');
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await page.waitForURL((u) => !u.pathname.startsWith('/login'));
}

test('Growth · Instagram: honest about the missing connection, July Instagram sales from Woo', async ({ page }) => {
  test.setTimeout(120_000);
  await page.setViewportSize({ width: 1280, height: 900 });
  await login(page);
  await page.goto('/growth');
  await expect(page.getByRole('link', { name: 'War Room' })).toBeVisible();   // existing tabs kept
  await expect(page.getByRole('link', { name: 'Campañas' })).toBeVisible();
  await page.getByRole('link', { name: 'Instagram', exact: true }).click();
  await expect(page.getByTestId('growth-instagram')).toBeVisible();
  await expect(page.getByTestId('ig-not-configured')).toContainText('Instagram todavía no está conectado');
  await expect(page.getByTestId('ig-not-configured')).toContainText('instagram_manage_insights');
  await page.getByRole('link', { name: 'Julio (Summer Sale)' }).click();
  await expect(page.getByText('Ventas pagadas desde Instagram').locator('..')).toContainText('9');
  await expect(page.getByTestId('ig-day')).toHaveCount(17);
  await expect(page.getByText('Lo que Instagram no deja saber')).toBeVisible();
  await shot(page, '01-instagram-julio');
  await page.setViewportSize({ width: 390, height: 844 });
  await noOverflow(page);
  await shot(page, '02-instagram-telefono');
});

test('Growth · Experimentos: rules fixed before starting, verdict from paid orders', async ({ page }) => {
  test.setTimeout(180_000);
  await page.setViewportSize({ width: 1280, height: 900 });
  await login(page);
  await page.goto('/growth?vista=experimentos');
  await expect(page.getByTestId('growth-experimentos')).toBeVisible();
  await page.getByTestId('exp-new').click();
  const f = page.getByTestId('exp-form');
  await f.locator('input[name=name]').fill('Prueba e2e · retargeting MX');
  await f.locator('textarea[name=hypothesis]').fill('Si volvemos a mostrar anuncios a quien visitó la tienda en México, las ventas pagadas suben a 3 o más en 7 días.');
  await f.locator('input[name=primary_variable]').fill('audiencia (retargeting)');
  await f.locator('select[name=proposed_by]').selectOption('ia');
  await f.locator('select[name=responsible]').selectOption('agencia');
  await f.locator('input[name=start_date]').fill('2026-10-20');
  await f.locator('input[name=end_date]').fill('2026-10-26');
  await f.locator('input[name=budget]').fill('700');
  await f.locator('input[name=success]').fill('>= 3 · muestra 1');
  await f.locator('input[name=kill]').fill('<= 0 · muestra 1');
  await f.getByRole('button', { name: 'Guardar borrador' }).click();
  const card = page.getByTestId('exp-card').filter({ hasText: 'Prueba e2e · retargeting MX' }).first();
  await expect(card).toContainText('Borrador');
  await card.getByRole('button', { name: 'Aprobar (fija todo)' }).click();
  await expect(card).toContainText('Aprobado por');
  await card.getByRole('button', { name: 'Empezar' }).click();
  await expect(card.getByTestId('exp-result')).toContainText('Hasta hoy');
  // the register refuses a "won" without meeting the goal, and says why
  await card.getByRole('textbox').fill('Intento de cerrar como ganador sin cumplir.');
  await card.getByRole('button', { name: 'Cerrar: ganó' }).click();
  await expect(card.getByText(/No cumplió la meta de éxito|Cumplió la meta/)).toBeVisible();
  await shot(page, '03-experimento-corriendo');
  await expect(page.getByTestId('exp-track')).toContainText('IA (Claude)');
  await page.setViewportSize({ width: 390, height: 844 });
  await noOverflow(page);
  await shot(page, '04-experimentos-telefono');
});
