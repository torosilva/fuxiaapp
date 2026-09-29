import { expect, test, type Page } from '@playwright/test';

// Track B E2E (staging): Clientes + Growth are honest (no invented numbers) and the 2027 plan works.
// Writes ONLY the 2027 North Star ($15,000,000, defined by Mario). Scenario assumptions are typed to check the live
// math but NOT saved; no reported figures are created.
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/b';
const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });

test('Track B · Clientes and Growth: honest data status + Plan 2027 model', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill('carolina.demo@staging.invalid');
  await page.getByLabel('Contraseña').fill(process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '');
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();

  // Navigation order
  const nav = await page.locator('aside nav a').allInnerTexts();
  expect(nav.map((t) => t.split('\n')[0].trim()).slice(0, 6)).toEqual(['Inicio', 'Productos', 'Inventario', 'Pedidos', 'Clientes', 'Growth']);

  // Clientes: no customer list, clear status, pending identity decisions, segment definitions
  await page.getByRole('link', { name: 'Clientes', exact: true }).first().click();
  await expect(page.getByTestId('clientes-status')).toContainText('Todavía no hay datos suficientes');
  for (const d of ['D-C1', 'D-C2', 'D-C3', 'D-C4', 'D-C5']) await expect(page.getByRole('list').getByText(d, { exact: true })).toBeVisible();
  await expect(page.locator('[data-segment]')).toHaveCount(12);
  expect(await page.locator('main').innerText()).not.toMatch(/\$\s?\d/);   // no money figures anywhere
  await shot(page, '01-clientes');

  // Growth · intelligence: honest, no numbers
  await page.getByRole('link', { name: 'Growth', exact: true }).first().click();
  await expect(page.getByTestId('growth-status')).toContainText('Todavía no hay datos suficientes');
  expect(await page.locator('main').innerText()).not.toMatch(/\$\s?\d/);
  await expect(page.locator('[data-status="confiable"]')).toHaveCount(2);
  await shot(page, '02-growth-inteligencia');

  // Growth · Plan 2027
  await page.getByRole('link', { name: 'Plan 2027' }).click();
  const ns = page.getByTestId('north-star');
  if (!(await ns.innerText()).includes('$15,000,000')) {
    await page.getByLabel('Objetivo anual').fill('15000000');
    await page.getByRole('button', { name: /Guardar objetivo|Actualizar objetivo/ }).click();
  }
  await expect(ns).toContainText('$15,000,000');
  await expect(ns).toContainText('Es un objetivo, no un pronóstico');
  await expect(ns).toContainText('$1,250,000');
  await expect(page.getByTestId('actual')).toContainText('Sin datos confiables todavía');
  await shot(page, '03-plan-objetivo');

  // Live math with typed (unsaved) assumptions
  await page.getByRole('button', { name: /^Base/ }).click();
  await page.getByLabel('Clientas activas en el año').fill('3000');
  await page.getByLabel('Compras por clienta al año').fill('1.5');
  await page.getByLabel('Ticket promedio (AOV, MXN)').fill('2800');
  await page.getByLabel('% ecommerce').fill('70');
  const res = page.getByTestId('scenario-results');
  await expect(res).toContainText('$12,600,000');
  await expect(res).toContainText('Faltan $2,400,000 para el objetivo');
  await expect(res).toContainText('3,571');        // clientas necesarias
  await expect(res).toContainText('$3,333');       // ticket requerido
  await expect(res).toContainText('Sin asignar');   // 30% of channel not assigned
  await shot(page, '04-plan-escenario-calculo');
  await page.getByLabel('% tiendas físicas').fill('40');
  await expect(page.locator('[role="alert"]').filter({ hasText: 'suman más de 100%' })).toBeVisible();   // 70 + 40
  await expect(page.getByRole('button', { name: /Guardar escenario/ })).toBeDisabled();

  // Nothing typed was saved
  await page.reload();
  await expect(page.getByRole('button', { name: /^Base/ })).toContainText('vacío');
  await expect(page.getByTestId('reported-figures')).toContainText('Ninguna cifra registrada');

  // Phone
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/growth?vista=plan');
  await shot(page, 'm1-plan-movil');
  await page.goto('/clientes');
  await shot(page, 'm2-clientes-movil');
});
