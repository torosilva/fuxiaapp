import { expect, test } from '@playwright/test';

// STAGING4 PUBLIC ACCEPTANCE · what Carolina does from her own computer, in Fuxia 360 on Vercel (no localhost, no Woo admin).
// WRITES ONE REAL STAGING MOVE: 1 pair Macarena Nude 35, Bodega CDMX → "Demo · Tienda" (goes "En camino").
// The pair is returned to Bodega afterwards by scripts/f360/carolina_acceptance_restore.mjs (audited, not deleted).
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = 'e2e-screenshots/carolina';

test('Carolina: Macarena en Fuxia 360 (Vercel) — revisar, inventario, mover, En camino, historial, ventas', async ({ page, baseURL }) => {
  test.setTimeout(300_000);
  expect(baseURL).toContain('fuxia360-staging.vercel.app');
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.setViewportSize({ width: 1280, height: 900 });
  const shot = (n: string) => page.screenshot({ path: `${SHOTS}/${n}.png`, fullPage: true });

  await test.step('1 · Entrar', async () => {
    await page.goto('/login');
    await page.getByLabel('Correo').fill(EMAIL);
    await page.getByLabel('Contraseña').fill(PASSWORD);
    await page.getByRole('button', { name: 'Entrar', exact: true }).click();
    await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  });
  const inTransit = async () => Number((await page.getByTestId('in-transit-pairs').innerText()).replace(/\D+/g, ' ').trim().split(' ')[0] || 0);
  const transitBefore = await inTransit();
  await shot('01-inicio');

  await test.step('2 · Revisar Macarena: precios e inventario por ubicación', async () => {
    await page.goto('/productos');
    await page.getByRole('link', { name: /Macarena/ }).first().click();
    await expect(page.getByRole('heading', { name: 'Macarena' })).toBeVisible();
    await expect(page.getByTestId('price-MXN')).toContainText('2,800');
    await expect(page.getByTestId('price-COP').getByLabel('Precio en COP')).toHaveValue('420000');
    await expect(page.getByRole('heading', { name: /tallas por ubicación/ })).toBeVisible();
    await expect(page.getByRole('cell', { name: 'Bodega CDMX' })).toBeVisible();
    await expect(page.getByText(/Pedido en línea #3654/)).toBeVisible();          // the online sale is in the product history
    await shot('02-macarena');
  });
  const productUrl = page.url();

  await test.step('3 · Total físico vs Disponible online (vista de tienda)', async () => {
    await page.goto(`${productUrl.replace(/\?.*$/, '')}/tienda`);
    await expect(page.getByText(/El inventario en línea sale de/)).toContainText('Bodega CDMX');
    await shot('03-vista-tienda');
  });

  await test.step('4 · Mover 1 par Nude 35: Bodega CDMX → Demo · Tienda (Enviar ahora)', async () => {
    await page.goto('/mover');
    await page.getByRole('button', { name: /Bodega CDMX/ }).click();
    await page.getByRole('button', { name: /Demo · Tienda/ }).click();
    await page.getByRole('button', { name: /Macarena/ }).click();
    await page.getByRole('button', { name: /Nude/ }).click();
    await page.getByRole('button', { name: 'Más talla 35' }).click();
    await page.getByRole('button', { name: /Agregar 1 par/ }).click();
    await shot('04-mover-resumen');
    await page.getByRole('button', { name: /Enviar ahora 1 par/ }).click();
    await expect(page.getByRole('heading', { name: 'Enviado: va en camino' })).toBeVisible();
    await shot('05-enviado');
  });

  await test.step('5 · En camino +1 en Inicio y en Transferencias', async () => {
    await page.goto('/');
    await expect.poll(inTransit).toBe(transitBefore + 1);
    await page.goto('/transferencias?vista=en-camino');
    await expect(page.getByText(/Demo · Tienda/).first()).toBeVisible();
    await shot('06-en-camino');
  });

  await test.step('6 · Ventas', async () => {
    await page.goto('/ventas');
    await expect(page.getByTestId('sales-summary')).toBeVisible();
    await shot('07-ventas');
  });
  expect(errors, errors.join(' | ')).toEqual([]);
});
