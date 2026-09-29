import { expect, test, type Locator, type Page } from '@playwright/test';

// P2.1 acceptance (product master, no Woo). STAGING ONLY — start from a clean demo (scripts/f360/demo_reset.mjs).
// Carolina creates Macarena (Nude + Negro, Colombian 35–40), adds photos per color, price + sale price, category,
// descriptions → Listo para publicar; receives by color + size into Bodega CDMX; adds Rojo later without
// recreating the model; previews ONE storefront product with color/size selectors and online stock.
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/p21';
const HEX: Record<string, string> = { Nude: '#D8B9A0', Negro: '#1C1A17', Rojo: '#9E2A2B' };

const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });

// Generated product photos (no real assets needed): a simple ballerina silhouette on the color.
async function photo(page: Page, color: string, n: number) {
  const p = await page.context().newPage();
  await p.setContent(`<div id="ph" style="width:600px;height:750px;display:flex;align-items:center;justify-content:center;
    background:${n === 1 ? '#F4F1EA' : '#E9E3D8'};font-family:Georgia,serif">
    <div style="text-align:center"><div style="width:360px;height:150px;margin:auto;border-radius:180px 180px 60px 60px;background:${HEX[color]};
      box-shadow:0 30px 40px -20px rgba(0,0,0,.35);transform:rotate(${n === 1 ? -8 : 6}deg)"></div>
    <p style="margin-top:60px;font-size:30px;letter-spacing:.25em;color:#3a342c">MACARENA · ${color.toUpperCase()} · ${n}</p></div></div>`);
  const buffer = await p.locator('#ph').screenshot();
  await p.close();
  return { name: `macarena-${color.toLowerCase()}-${n}.png`, mimeType: 'image/png', buffer };
}

async function addPhotos(page: Page, color: string) {
  const fotos = page.locator('#fotos');
  await fotos.getByRole('link', { name: new RegExp(color) }).click();
  await page.waitForURL(/color=/);
  const input = page.getByLabel(`Fotos de ${color}`);
  await expect(input).toBeAttached();
  await input.setInputFiles([await photo(page, color, 1), await photo(page, color, 2)]);
  await expect(fotos.getByRole('link', { name: new RegExp(`${color}\\s*2 fotos`) })).toBeVisible({ timeout: 30_000 });
}

async function tap(button: Locator, times: number) { for (let i = 0; i < times; i++) await button.click(); }

test('P2.1 · Carolina creates Macarena and previews it as ONE storefront product', async ({ page }) => {
  test.setTimeout(240_000);
  expect(PASSWORD, 'STAGING_DEMO_CAROLINA_PASSWORD must be set').not.toBe('');
  await page.setViewportSize({ width: 1280, height: 900 });

  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();

  // 1 · New product: name, two colors, Colombian sizes 35–40 preselected
  await page.goto('/productos/nuevo');
  await page.getByPlaceholder('Ej. Macarena').fill('Macarena');
  await page.getByRole('button', { name: 'Nude' }).click();
  await page.getByRole('button', { name: 'Negro' }).click();
  for (const s of ['35', '36', '37', '38', '39', '40']) await expect(page.getByRole('button', { name: s, exact: true })).toHaveAttribute('aria-pressed', 'true');
  await shot(page, '01-nuevo-producto');
  await page.getByRole('button', { name: /Guardar producto/ }).click();
  await expect(page.getByText('Producto creado.')).toBeVisible();
  await expect(page.getByText('Borrador', { exact: true })).toBeVisible();
  await expect(page.getByText('Para la tienda en línea falta:')).toBeVisible();
  await shot(page, '02-borrador-checklist');

  // 2 · Two photos per color
  await addPhotos(page, 'Nude');
  await addPhotos(page, 'Negro');
  await shot(page, '03-fotos-por-color');

  // 3 · Price + sale price, category, descriptions
  await page.getByLabel('Precio (MXN)').fill('2800');
  await page.getByRole('button', { name: '+ Agregar precio de oferta' }).click();
  await page.getByLabel('Precio de oferta').fill('2400');
  await page.getByRole('button', { name: 'Ballerinas' }).click();
  await page.getByLabel('Descripción', { exact: true }).fill('Ballerina de piel hecha a mano en Colombia. Suela flexible y plantilla acolchada para usar todo el día.');
  await page.getByRole('button', { name: '+ Agregar descripción corta' }).click();
  await page.getByLabel(/Descripción corta/).fill('La ballerina clásica de Fuxia.');
  await shot(page, '04-info-tienda');
  await page.getByRole('button', { name: 'Guardar', exact: true }).click();

  // 4 · Ready
  await expect(page.getByText('Listo para publicar', { exact: true })).toBeVisible();
  await expect(page.getByText('Todo listo para la tienda en línea.')).toBeVisible();
  await page.getByText('Códigos para la tienda en línea').click();
  await expect(page.getByText('F360-MACARENA-NUDE-37')).toBeVisible();
  await shot(page, '05-listo-para-publicar');

  // 5 · Receive by color + size into Bodega CDMX: Nude 35/37/39 = 4 each, then Negro 37 = 2
  await page.locator('#fotos').getByRole('link', { name: /Nude/ }).click();
  await expect(page.getByLabel('Fotos de Nude')).toBeAttached();
  await page.getByRole('link', { name: 'Recibir mercancía', exact: true }).click();
  await page.waitForURL(/\/recibir/);
  await expect(page.getByText('Nude', { exact: true })).toBeVisible();   // the wizard states the color being received
  await expect(page.getByRole('button', { name: /Bodega CDMX/ })).toHaveAttribute('aria-pressed', 'true');
  for (const s of ['35', '37', '39']) await tap(page.getByRole('button', { name: `Más talla ${s}`, exact: true }), 4);
  await shot(page, '06-recibir-nude');
  await page.getByRole('button', { name: /Recibir 12 pares/i }).click();
  await expect(page.getByText('Carolina recibió 12 pares en Bodega CDMX')).toBeVisible();
  await page.getByRole('button', { name: 'Recibir otro color de Macarena' }).click();
  await page.getByRole('button', { name: /Negro/ }).click();
  await expect(page.getByText('Negro', { exact: true })).toBeVisible();
  await tap(page.getByRole('button', { name: 'Más talla 37', exact: true }), 2);
  await page.getByRole('button', { name: /Recibir 2 pares/i }).click();
  await expect(page.getByText('Carolina recibió 2 pares en Bodega CDMX')).toBeVisible();
  await shot(page, '07-recibido-negro');

  // 6 · Add Rojo later — same model, no recreation; product goes back to draft until Rojo has photos
  await page.getByRole('link', { name: 'Ver inventario del producto' }).click();
  await page.waitForURL(/\/productos\/[0-9a-f-]+/);
  const productUrl = page.url().split('?')[0];
  await page.getByRole('button', { name: 'Agregar color' }).click();
  await page.getByRole('button', { name: 'Rojo' }).click();
  await expect(page.getByLabel('Fotos de Rojo')).toBeAttached();
  await expect(page.getByText('Borrador', { exact: true })).toBeVisible();
  await shot(page, '08-rojo-agregado');
  await addPhotos(page, 'Rojo');
  await expect(page.getByText('Listo para publicar', { exact: true })).toBeVisible();
  expect(page.url().split('?')[0]).toBe(productUrl);
  await shot(page, '09-rojo-con-fotos');

  // 7 · Storefront preview: ONE Macarena, color selector, sizes by online stock
  await page.getByRole('link', { name: 'Así se verá en la tienda' }).click();
  await expect(page.getByRole('heading', { name: 'Macarena' })).toBeVisible();
  await expect(page.getByText('$2,400').first()).toBeVisible();
  await expect(page.getByTestId('preview-selected-color')).toHaveText('Nude');
  await expect(page.getByTestId('preview-main-photo')).toHaveAttribute('data-path', /\/NUDE\//);
  for (const s of ['35', '37', '39']) await expect(page.getByRole('button', { name: `Talla ${s}`, exact: true })).toBeEnabled();
  for (const s of ['36', '38', '40']) await expect(page.getByRole('button', { name: `Talla ${s} agotada` })).toBeDisabled();
  await page.getByRole('button', { name: 'Talla 37', exact: true }).click();
  await expect(page.getByTestId('preview-variation')).toContainText('F360-MACARENA-NUDE-37');
  await expect(page.getByTestId('preview-variation')).toContainText('4 disponibles en línea');
  await shot(page, '10-tienda-nude-37');

  await page.getByRole('button', { name: 'Color Negro' }).click();
  await expect(page.getByTestId('preview-main-photo')).toHaveAttribute('data-path', /\/NEGRO\//);
  await expect(page.getByRole('button', { name: 'Talla 37', exact: true })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Talla 35 agotada' })).toBeDisabled();
  await page.getByRole('button', { name: 'Talla 37', exact: true }).click();
  await expect(page.getByTestId('preview-variation')).toContainText('2 disponibles en línea');
  await expect(page.getByTestId('preview-variation')).toContainText('F360-MACARENA-NEGRO-37');
  await shot(page, '11-tienda-negro-37');

  await page.getByRole('button', { name: 'Color Rojo' }).click();
  await expect(page.getByTestId('preview-main-photo')).toHaveAttribute('data-path', /\/ROJO\//);
  for (const s of ['35', '36', '37', '38', '39', '40']) await expect(page.getByRole('button', { name: `Talla ${s} agotada` })).toBeDisabled();
  await expect(page.getByTestId('preview-variation')).toContainText('Sin existencia en línea para Rojo');
  await page.getByText(/Variaciones que tendrá la tienda: 18/).click();
  await shot(page, '12-tienda-rojo-variaciones');

  // 8 · Product list shows one Macarena, ready, with price
  await page.goto('/productos');
  await expect(page.getByRole('link', { name: /Macarena/ })).toHaveCount(1);
  await expect(page.getByRole('link', { name: /Macarena/ })).toContainText('Listo');
  await shot(page, '13-productos');
});

test('P2.1 · storefront preview on a phone', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  await page.goto('/productos');
  await page.getByRole('link', { name: /Macarena/ }).click();
  await shot(page, 'm1-producto');
  await page.getByRole('link', { name: 'Así se verá en la tienda' }).click();
  await page.getByRole('button', { name: 'Talla 39', exact: true }).click();
  await expect(page.getByTestId('preview-variation')).toContainText('F360-MACARENA-NUDE-39');
  await shot(page, 'm2-tienda');
});
