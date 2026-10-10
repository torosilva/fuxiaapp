import { expect, test, type Page } from '@playwright/test';

// Conciliación de Ventas E2E (STAGING ONLY, real staging4 orders). Logs in as the Mario demo account (customer_pii_viewer),
// queries read-only Woo evidence and records four example reviews (append-only, labelled as examples). Desktop + mobile shots.
// Run: F360_BASE_URL=https://fuxia360-staging.vercel.app npx playwright test e2e/conciliacion.spec.ts
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/conciliacion';
const TARGET = '347da3c0-7531-4eef-9cc4-5c4b9ba00780';   // woo_staging4
const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });
const open = (page: Page, order: number) => page.goto(`/growth?vista=conciliacion&conciliacion=todos&pedido=${TARGET}:${order}`);
const noOverflow = async (page: Page) => expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(1);

async function login(page: Page) {
  await page.addInitScript(() => { try { sessionStorage.setItem('f360-staging-notice', '1'); } catch { /* notice stays */ } });   // staging notice already answered
  await page.goto('/login');
  await page.getByLabel('Correo').fill('mario.demo@staging.invalid');
  await page.getByLabel('Contraseña').fill(process.env.STAGING_DEMO_MARIO_PASSWORD ?? '');
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await page.waitForURL((u) => !u.pathname.startsWith('/login'));
}
async function evidence(page: Page) {
  await page.getByRole('button', { name: 'Consultar evidencia en WooCommerce' }).click();
  await expect(page.getByTestId('rec-evidence').getByText(/Consulta #\d+/)).toBeVisible({ timeout: 60_000 });
}
async function decide(page: Page, label: string, comment: string) {
  const box = page.getByTestId('rec-decide');
  await box.getByRole('button', { name: label, exact: true }).click();
  await box.getByRole('textbox').last().fill(comment);
  await box.getByRole('button', { name: 'Guardar decisión' }).click();
  await expect(box.getByText(/^Guardado/)).toBeVisible({ timeout: 30_000 });
}

test('Conciliación · real staging orders: flags, evidence, decisions, desktop + mobile', async ({ page }) => {
  test.setTimeout(300_000);
  await page.setViewportSize({ width: 1440, height: 900 });
  await login(page);

  // List: summary per market + pending queue by default
  await page.goto('/growth?vista=conciliacion');
  await expect(page.getByTestId('rec-summary-MX')).toBeVisible();
  await expect(page.getByTestId('rec-summary-CO')).toBeVisible();
  await expect(page.getByTestId('rec-table')).toBeVisible();
  await shot(page, '01-lista-por-revisar-desktop');

  // 1 · #5351 paid then cancelled → evidence says Woo no longer has it → under investigation
  await open(page, 5351);
  await expect(page.getByTestId('rec-case')).toContainText('Pagado y cancelado');
  await evidence(page);
  await page.reload();
  await expect(page.getByTestId('rec-case')).toContainText('El pedido ya no existe en WooCommerce');
  await decide(page, 'Requiere investigación', 'Ejemplo de revisión (staging): pagado y cancelado y ya no existe en Woo; pedir a Carolina el movimiento en Mercado Pago.');
  await page.reload();
  await shot(page, '02-caso-5351-investigacion-desktop');

  // 2 · #3654 paid with the test gateway → Prueba
  await open(page, 3654);
  await evidence(page);
  await decide(page, 'Prueba', 'Ejemplo de revisión (staging): método "PRUEBA staging (sin cobro)", no es venta.');
  await page.reload();
  await expect(page.getByTestId('rec-case')).toContainText('Conflicto');   // paid in Woo, no refund → stays visible as conflict
  await shot(page, '03-caso-3654-prueba-desktop');

  // 3 · #3097 never paid, customer retried and paid in #3101 → No se concretó
  await open(page, 3097);
  await expect(page.getByTestId('rec-case')).toContainText('Posible reintento pagado');
  await decide(page, 'No se concretó', 'Ejemplo de revisión (staging): intento fallido sin cobro; posible reintento en #3101 (verificar misma clienta).');
  await page.reload();
  await expect(page.getByTestId('rec-case')).toContainText('Revisado');

  // 4 · #4114 Mercado Pago approved with payment id → Venta confirmada, consistent with the evidence
  await open(page, 4114);
  await evidence(page);
  await page.reload();
  await expect(page.getByTestId('rec-case')).toContainText('Pago con transacción de la pasarela');
  await decide(page, 'Venta confirmada', 'Ejemplo de revisión (staging): Mercado Pago aprobado con número de pago.');
  await page.reload();
  await expect(page.getByTestId('rec-case')).toContainText('Revisado');
  await shot(page, '04-caso-4114-confirmada-desktop');

  // Mobile (390 px): list as cards + case, no horizontal scroll
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/growth?vista=conciliacion&conciliacion=todos&marca=financiera');
  await expect(page.getByTestId('rec-cards')).toBeVisible();
  await noOverflow(page);
  await shot(page, '05-lista-discrepancias-movil');
  await open(page, 5351);
  await noOverflow(page);
  await shot(page, '06-caso-5351-movil');
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/growth?vista=conciliacion&conciliacion=todos');
  await shot(page, '07-lista-todos-desktop');
});

test('War Room · authorized exclusion shown apart from the original WooCommerce figures (desktop + mobile)', async ({ page }) => {
  test.setTimeout(180_000);
  await page.setViewportSize({ width: 1440, height: 900 });
  await login(page);
  const period = '/growth?mercado=MX&desde=2026-06-01&hasta=2026-10-10';
  await page.goto(period);
  const panel = page.getByTestId('cockpit-adjustments-MX');
  await expect(panel).toBeVisible();
  const revenueCard = await page.getByTestId('cockpit-MX').locator('.atelier-card').first().innerText();
  // example exclusion on #3654 (paid with the test gateway) — a separate, explicit, reasoned action
  await open(page, 3654);
  const ax = page.getByTestId('rec-analytics');
  if (await ax.getByRole('button', { name: 'Excluir de métricas' }).isVisible()) {
    await ax.getByRole('textbox').fill('Ejemplo de exclusión (staging): pedido pagado con el método de prueba, no es venta real.');
    await ax.getByRole('button', { name: 'Excluir de métricas' }).click();
    await expect(ax.getByRole('button', { name: 'Volver a incluir en métricas' })).toBeVisible({ timeout: 30_000 });
  }
  await page.goto(period);
  await expect(panel).toContainText('Excluidos por decisión autorizada');
  await expect(panel).toContainText('#3654');
  // the original KPI card did not change
  expect(await page.getByTestId('cockpit-MX').locator('.atelier-card').first().innerText()).toBe(revenueCard);
  await panel.scrollIntoViewIfNeeded();
  await panel.screenshot({ path: `${SHOTS}/09-warroom-ajustes-MX-desktop.png` });
  await shot(page, '10-warroom-MX-desktop');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(period);
  await noOverflow(page);
  await panel.scrollIntoViewIfNeeded();
  await panel.screenshot({ path: `${SHOTS}/11-warroom-ajustes-MX-movil.png` });
});

test('#2095 · commercial currency correction: Woo USD kept, reported as COP / Colombia, still unpaid (desktop + mobile)', async ({ page }) => {
  test.setTimeout(120_000);
  await page.setViewportSize({ width: 1440, height: 900 });
  await login(page);
  await open(page, 2095);
  const note = page.getByTestId('rec-currency-note');
  await expect(note).toContainText('USD');
  await expect(note).toContainText('COP');
  await expect(page.getByTestId('rec-case')).toContainText('Moneda corregida');
  await expect(page.getByTestId('rec-case')).toContainText('Sin cobro registrado');
  await page.getByTestId('rec-case').screenshot({ path: `${SHOTS}/12-caso-2095-moneda-desktop.png` });
  await page.goto('/growth?mercado=CO&desde=2026-06-01&hasta=2026-10-10');
  const cur = page.getByTestId('cockpit-currency-CO');
  await expect(cur).toContainText('#2095');
  await page.getByTestId('cockpit-adjustments-CO').screenshot({ path: `${SHOTS}/13-warroom-CO-moneda-desktop.png` });
  await page.setViewportSize({ width: 390, height: 844 });
  await open(page, 2095);
  await noOverflow(page);
  await note.screenshot({ path: `${SHOTS}/14-caso-2095-moneda-movil.png` });
});
