import { readFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';

// P2.2 LOCAL ACCEPTANCE — Fuxia 360 (staging Supabase) → throwaway local Docker WooCommerce. Prerequisites:
//   scripts/f360/p22_local_prepare.sh          (fresh local Woo, staging demo reset, woo_local target)
//   scripts/s00a/run.sh ../f360/publisher_local.ts   (local publisher on :8787)
//   admin-web on :3000
// No external WooCommerce, no production credentials, no production writes.
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/p22';
const PUBLISHER = 'http://127.0.0.1:8787';
const WOO = Object.fromEntries(readFileSync('../tools/woo-docker/.env.local', 'utf8').split('\n').filter((l) => l.includes('='))
  .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
if (!/^http:\/\/localhost:\d+$/.test(WOO.WOO_BASE_URL)) throw new Error('local Woo only');
const HEX: Record<string, string> = { Nude: '#D8B9A0', Negro: '#1C1A17', Rojo: '#9E2A2B' };
const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });

// ── Woo REST (read-only checks of the local store) ──
const auth = 'Basic ' + Buffer.from(`${WOO.WOO_USER}:${WOO.WOO_SECRET}`).toString('base64');
async function woo<T>(path: string): Promise<T> {
  const r = await fetch(`${WOO.WOO_BASE_URL}/wp-json/wc/v3${path}`, { headers: { Authorization: auth } });
  return r.json() as Promise<T>;
}
type WP = { id: number; sku: string; status: string; type: string; name: string; categories: { id: number; slug: string }[]; images: { id: number; name: string }[]; attributes: { name: string; options: string[] }[] };
type WV = { id: number; sku: string; regular_price: string; stock_quantity: number | null; manage_stock: boolean; image: { id: number } | null; attributes: { name: string; option: string }[] };
const macarenas = () => woo<WP[]>(`/products?sku=F360-MACARENA&status=any`);
const allVariations = (id: number) => woo<WV[]>(`/products/${id}/variations?per_page=100`);
const arm = (faults: string[]) => fetch(`${PUBLISHER}/__faults`, { method: 'POST', body: JSON.stringify({ faults }) });

async function photo(page: Page, color: string, n: number) {
  const p = await page.context().newPage();
  await p.setContent(`<div id="ph" style="width:600px;height:750px;display:flex;align-items:center;justify-content:center;background:${n === 1 ? '#F4F1EA' : '#E9E3D8'};font-family:Georgia,serif">
    <div style="text-align:center"><div style="width:360px;height:150px;margin:auto;border-radius:180px 180px 60px 60px;background:${HEX[color]};box-shadow:0 30px 40px -20px rgba(0,0,0,.35);transform:rotate(${n === 1 ? -8 : 6}deg)"></div>
    <p style="margin-top:60px;font-size:30px;letter-spacing:.25em;color:#3a342c">MACARENA · ${color.toUpperCase()} · ${n}</p></div></div>`);
  const buffer = await p.locator('#ph').screenshot();
  await p.close();
  return { name: `macarena-${color.toLowerCase()}-${n}.png`, mimeType: 'image/png', buffer };
}

async function publishAndWait(page: Page, button: string, expected: 'publicado' | 'error') {
  await page.getByRole('button', { name: button, exact: true }).click();
  if (button === 'Publicar en tienda online') await page.getByRole('button', { name: 'Sí, publicar oculto' }).click();
  await expect(page.getByTestId('publish-panel')).toHaveAttribute('data-state', expected, { timeout: 180_000 });
}

test('P2.2 · Carolina publishes Macarena to the local Woo (draft), failures converge, re-sync never duplicates', async ({ page }) => {
  test.setTimeout(600_000);
  expect(PASSWORD).not.toBe('');
  await page.setViewportSize({ width: 1280, height: 900 });
  expect(await macarenas()).toHaveLength(0);

  // ── Setup exactly like the P2.1 acceptance: Macarena, Nude/Negro/Rojo, 35–40, 2 photos each, price, category, stock
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  await page.goto('/productos/nuevo');
  await page.getByPlaceholder('Ej. Macarena').fill('Macarena');
  for (const c of ['Nude', 'Negro', 'Rojo']) await page.getByRole('button', { name: c }).click();
  await page.getByRole('button', { name: /Guardar producto/ }).click();
  await expect(page.getByText('Producto creado.')).toBeVisible();
  const productUrl = page.url().split('?')[0];
  for (const c of ['Nude', 'Negro', 'Rojo']) {
    const fotos = page.locator('#fotos');
    await fotos.getByRole('link', { name: new RegExp(c) }).click();
    await page.waitForURL(/color=/);
    await page.getByLabel(`Fotos de ${c}`).setInputFiles([await photo(page, c, 1), await photo(page, c, 2)]);
    await expect(fotos.getByRole('link', { name: new RegExp(`${c}\\s*2 fotos`) })).toBeVisible({ timeout: 30_000 });
  }
  await page.getByLabel('Precio (MXN)').fill('2800');
  await page.getByRole('button', { name: 'Ballerinas' }).click();
  await page.getByLabel('Descripción', { exact: true }).fill('Ballerina de piel hecha a mano en Colombia.');
  await page.getByRole('button', { name: 'Guardar', exact: true }).click();
  await expect(page.getByText('Listo para publicar', { exact: true })).toBeVisible();
  for (const [color, sizes] of [['Nude', { 35: 4, 37: 4, 39: 4 }], ['Negro', { 37: 2 }]] as const) {
    await page.goto(productUrl);
    await page.locator('#fotos').getByRole('link', { name: new RegExp(color) }).click();
    await expect(page.getByLabel(`Fotos de ${color}`)).toBeAttached();
    await page.getByRole('link', { name: 'Recibir mercancía', exact: true }).click();
    await page.waitForURL(/\/recibir/);
    await expect(page.getByText(color, { exact: true })).toBeVisible();
    let total = 0;
    for (const [size, n] of Object.entries(sizes)) { total += n; for (let i = 0; i < n; i++) await page.getByRole('button', { name: `Más talla ${size}`, exact: true }).click(); }
    await page.getByRole('button', { name: new RegExp(`Recibir ${total} pares`, 'i') }).click();
    await expect(page.getByText(`Carolina recibió ${total} pares en Bodega CDMX`)).toBeVisible({ timeout: 30_000 });
  }

  // ── 1 · Carolina opens Macarena: "Tienda en línea" = listo
  await page.goto(productUrl);
  await expect(page.getByTestId('publish-panel')).toHaveAttribute('data-state', 'listo');
  await page.locator('#tienda').scrollIntoViewIfNeeded();
  await shot(page, '01-listo-para-publicar');

  // ── 2 · Intentional failures mid-process, each followed by "Reintentar"
  await arm(['photo']);
  await page.getByRole('button', { name: 'Publicar en tienda online', exact: true }).click();
  await shot(page, '02-confirmar');
  await page.getByRole('button', { name: 'Sí, publicar oculto' }).click();
  await expect(page.getByTestId('publish-panel')).toHaveAttribute('data-state', 'error', { timeout: 180_000 });
  await expect(page.getByTestId('publish-error')).toContainText('imagen');
  expect(await macarenas()).toHaveLength(0);                           // photo failure → nothing created
  await shot(page, '03-falla-foto');

  await arm(['product_crash']);
  await publishAndWait(page, 'Reintentar', 'error');
  expect(await macarenas()).toHaveLength(1);                           // created in Woo, answer lost
  await shot(page, '04-falla-creacion-producto');

  await arm(['variation']);
  await publishAndWait(page, 'Reintentar', 'error');
  const [afterVarFault] = await macarenas();
  expect(await macarenas()).toHaveLength(1);                           // recovered by SKU, not duplicated
  expect(await allVariations(afterVarFault.id)).toHaveLength(17);      // one variation failed
  await expect(page.getByTestId('publish-error')).toContainText('falta F360-MACARENA-');
  await shot(page, '05-falla-variacion');

  await arm(['stock']);
  await publishAndWait(page, 'Reintentar', 'error');
  await shot(page, '06-falla-stock');

  // ── 3 · Retry without faults → converges
  await arm([]);
  await publishAndWait(page, 'Reintentar', 'publicado');
  await expect(page.getByText(/oculto — 18 variaciones/)).toBeVisible();
  await shot(page, '07-publicado');

  // ── 4 · The exact store result, read back from the local Woo REST API
  const check = async () => {
    const list = await macarenas();
    expect(list, '1 Woo product').toHaveLength(1);
    const p = list[0];
    expect(p.type).toBe('variable');
    expect(p.status).toBe('draft');
    expect(p.name).toBe('Macarena');
    expect(p.categories.map((c) => c.slug)).toEqual(['ballerinas']);
    expect([...p.attributes.find((a) => a.name === 'Color')!.options].sort()).toEqual(['Negro', 'Nude', 'Rojo']);
    expect(p.attributes.find((a) => a.name === 'Medida')!.options).toEqual(['35', '36', '37', '38', '39', '40']);
    expect(p.images).toHaveLength(6);
    const vars = await allVariations(p.id);
    expect(vars, '18 variations').toHaveLength(18);
    expect(new Set(vars.map((v) => v.sku)).size, '0 duplicate SKUs').toBe(18);
    const sku = Object.fromEntries(vars.map((v) => [v.sku, v]));
    for (const c of ['NUDE', 'NEGRO', 'ROJO']) for (const s of ['35', '36', '37', '38', '39', '40']) {
      const v = sku[`F360-MACARENA-${c}-${s}`];
      expect(v, `F360-MACARENA-${c}-${s}`).toBeTruthy();
      expect(v.regular_price).toBe('2800');
      expect(v.manage_stock).toBe(true);
    }
    const stock = (k: string) => sku[`F360-MACARENA-${k}`].stock_quantity;
    expect([stock('NUDE-35'), stock('NUDE-36'), stock('NUDE-37'), stock('NUDE-38'), stock('NUDE-39'), stock('NUDE-40')]).toEqual([4, 0, 4, 0, 4, 0]);
    expect([stock('NEGRO-35'), stock('NEGRO-37')]).toEqual([0, 2]);
    expect(['35', '36', '37', '38', '39', '40'].map((s) => stock(`ROJO-${s}`))).toEqual([0, 0, 0, 0, 0, 0]);
    const imgOf = (c: string) => new Set(vars.filter((v) => v.sku.includes(`-${c}-`)).map((v) => v.image?.id));
    for (const c of ['NUDE', 'NEGRO', 'ROJO']) expect(imgOf(c).size, `${c}: one main photo for all its sizes`).toBe(1);
    expect(new Set(['NUDE', 'NEGRO', 'ROJO'].map((c) => [...imgOf(c)][0])).size, 'each color has its own photo').toBe(3);
    return { p, vars };
  };
  const first = await check();

  // ── 5 · Publish/sync again → still 1 product, 18 variations, 0 duplicates
  await publishAndWait(page, 'Sincronizar de nuevo', 'publicado');
  const second = await check();
  expect(second.p.id).toBe(first.p.id);
  expect(second.p.images.map((i) => i.id)).toEqual(first.p.images.map((i) => i.id));   // photos not re-uploaded
  const history = page.getByTestId('publish-history').locator(':scope > li');
  await expect(history).toHaveCount(6);   // 4 intentional failures + recovery + re-sync
  await page.getByText(/Ver los \d+ pasos/).first().click();
  await shot(page, '08-sincronizado-historial');

  // ── 6 · Fuxia 360 codes are now frozen
  await page.getByText('Códigos para la tienda en línea').click();
  await expect(page.getByText('Fijos: ya se usaron para publicar')).toBeVisible();

  // ── 7 · Inside the local WooCommerce (admin + draft preview), for the screenshots only
  const wp = await page.context().newPage();
  await wp.setViewportSize({ width: 1400, height: 1000 });
  await wp.goto(`${WOO.WOO_BASE_URL}/wp-login.php`);
  await wp.fill('#user_login', WOO.WP_ADMIN_USER);
  await wp.fill('#user_pass', WOO.WP_ADMIN_PASSWORD);
  await wp.click('#wp-submit');
  await wp.waitForURL(/wp-admin/);
  await wp.goto(`${WOO.WOO_BASE_URL}/wp-admin/edit.php?post_type=product`);
  await shot(wp, 'woo-01-lista-productos');
  await wp.goto(`${WOO.WOO_BASE_URL}/wp-admin/post.php?post=${first.p.id}&action=edit`);
  await wp.waitForLoadState('networkidle');
  await shot(wp, 'woo-02-producto-borrador');
  const varTab = wp.locator('.variations_tab a');
  if (await varTab.count()) { await varTab.click(); await wp.waitForSelector('.woocommerce_variation', { timeout: 30_000 }).catch(() => {}); await shot(wp, 'woo-03-variaciones'); }
  await wp.goto(`${WOO.WOO_BASE_URL}/?post_type=product&p=${first.p.id}&preview=true`);
  await wp.waitForLoadState('networkidle');
  await shot(wp, 'woo-04-vista-previa-borrador');
  const colorSel = wp.locator('select[name="attribute_pa_color"]');
  if (await colorSel.count()) {
    await colorSel.selectOption({ label: 'Negro' });
    await wp.locator('select[name="attribute_pa_medida"]').selectOption('37');
    await wp.waitForTimeout(1500);
    await shot(wp, 'woo-05-vista-previa-negro-37');
  }
  // Not public: an anonymous visitor cannot see it
  const anon = await page.context().browser()!.newContext();
  const visitor = await anon.newPage();
  const res = await visitor.goto(`${WOO.WOO_BASE_URL}/?post_type=product&p=${first.p.id}`);
  expect(res?.status(), 'draft product is not public').toBe(404);
  await anon.close();
});
