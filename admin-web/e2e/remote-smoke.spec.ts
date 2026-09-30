import { expect, test } from '@playwright/test';

// REMOTE smoke (read-only) of Fuxia 360 staging on Vercel: every screen Mario listed, as Carolina (owner).
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = 'e2e-screenshots/remote';

test('Fuxia 360 staging (Vercel): pantallas principales', async ({ page, baseURL }) => {
  test.setTimeout(240_000);
  expect(baseURL).toContain('fuxia360-staging.vercel.app');
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.setViewportSize({ width: 1280, height: 900 });
  const ok = async (name: string, path: string, check: () => Promise<void>) => {
    const r = await page.goto(path);
    expect(r?.status(), path).toBeLessThan(400);
    await expect(page.getByText(/Application error|Something went wrong/i)).toHaveCount(0);
    await check();
    await page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });
  };
  // Login
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/01-inicio.png`, fullPage: true });
  await expect(page.getByTestId('available-pairs')).toBeVisible();
  await expect(page.getByTestId('in-transit-pairs')).toBeVisible();
  await ok('02-productos', '/productos', async () => { await expect(page.getByRole('link', { name: /Macarena/ }).first()).toBeVisible(); });
  await page.getByRole('link', { name: /Macarena/ }).first().click();
  await expect(page.getByRole('heading', { name: 'Macarena' })).toBeVisible();
  await expect(page.getByTestId('price-MXN')).toContainText('2,800');
  await expect(page.getByTestId('price-COP').getByLabel('Precio en COP')).toHaveValue('420000');
  await expect(page.getByTestId('price-USD').getByLabel('Precio en USD')).toHaveValue('');
  await page.screenshot({ path: `${SHOTS}/03-macarena-precios.png`, fullPage: true });
  await ok('04-inventario', '/inventario', async () => { await expect(page.getByRole('heading', { name: 'Inventario' })).toBeVisible(); });
  await ok('05-mover', '/mover', async () => { await expect(page.getByRole('heading', { name: /De dónde sale/ })).toBeVisible(); });
  await ok('06-transferencias', '/transferencias', async () => { await expect(page.getByRole('heading', { name: 'Transferencias' })).toBeVisible(); });
  await ok('07-ventas', '/ventas', async () => { await expect(page.getByTestId('sales-summary')).toBeVisible(); });
  await ok('08-clientes', '/clientes', async () => { await expect(page.locator('h1').first()).toBeVisible(); });
  await ok('09-growth', '/growth', async () => { await expect(page.locator('h1').first()).toBeVisible(); });
  await ok('10-monedas', '/monedas', async () => { await expect(page.getByTestId('currency-COP')).toContainText('_price_cop'); await expect(page.getByTestId('currency-USD')).toContainText('_price_usd'); });
  expect(errors, errors.join(' | ')).toEqual([]);
});
