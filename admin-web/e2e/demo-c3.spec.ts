import { expect, test } from '@playwright/test';

// C3 DEMO WALKTHROUGH (staging) — exactly what Carolina sees after the live sale (scripts/f360/demo_c3_sale.mjs):
// Ventas → Hoy → $2,800 → Macarena Nude 37 → vendedora → clienta → +100 puntos → inventario −1.
// Read-only: it only opens screens.
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/demo-c3';

test('demo: la venta de hoy en Fuxia 360', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/01-inicio.png`, fullPage: true });

  // Ventas → Hoy
  await page.getByRole('link', { name: 'Ventas' }).first().click();
  await page.getByRole('link', { name: 'Hoy', exact: true }).click();
  await expect(page.getByTestId('sales-summary')).toContainText('$2,800');
  const row = page.getByTestId('sale-row').filter({ hasText: 'Demo · Tienda' }).first();
  await expect(row).toContainText('$2,800');
  await expect(row).toContainText('Demo · Vendedora');
  await expect(row).toContainText('Demo · Clienta');
  await page.screenshot({ path: `${SHOTS}/02-ventas-hoy.png`, fullPage: true });

  // → the sale: Macarena Nude 37, seller, customer, +100 points, inventory movement
  await row.getByRole('link').click();
  await expect(page.getByTestId('sale-item')).toContainText('Macarena');
  await expect(page.getByTestId('sale-item')).toContainText('Nude · Talla 37');
  await expect(page.getByTestId('sale-customer')).toContainText('Demo · Clienta');
  await expect(page.getByTestId('sale-loyalty')).toContainText('100 puntos');
  await expect(page.getByText(/Demo · Vendedora vendió 1 par de Demo · Tienda/)).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/03-la-venta.png`, fullPage: true });

  // → inventory −1 at the store (3 → 2)
  await page.goto('/inventario');
  await page.getByRole('link', { name: /Demo · Tienda/ }).first().click();
  const nude = page.locator('div', { has: page.getByText('Nude', { exact: true }) }).filter({ hasText: 'Talla 37' }).last();
  await expect(nude).toContainText('Talla 37');
  await page.screenshot({ path: `${SHOTS}/04-inventario-tienda.png`, fullPage: true });
});
