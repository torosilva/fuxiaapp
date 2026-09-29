import { expect, test } from '@playwright/test';

// READ-ONLY regression smoke (staging): every screen renders for the owner, with no error page. Writes nothing.
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const PAGES = ['/', '/productos', '/inventario', '/inventario?vista=historial', '/transferencias', '/transferencias?vista=en-camino',
  '/transferencias?vista=recibidas', '/transferencias?vista=diferencias', '/mover', '/recibir', '/ventas', '/ventas?canal=store', '/avisos', '/growth', '/clientes', '/mas', '/pedidos', '/produccion'];

test('every screen renders (read-only)', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  for (const path of PAGES) {
    const res = await page.goto(path);
    expect(res?.status(), path).toBeLessThan(400);
    await expect(page.getByText(/Application error|Unhandled Runtime Error|Something went wrong/i), path).toHaveCount(0);
    await expect(page.locator('h1').first(), path).toBeVisible();
  }
  await page.goto('/productos');
  await page.locator('a[href^="/productos/"]').filter({ hasNotText: 'Nuevo' }).first().click();
  await expect(page.locator('h1').first()).toBeVisible();
});
