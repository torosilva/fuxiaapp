import { readFileSync } from 'node:fs';
import { expect, test, type Browser, type Page } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';

// TRACK C · TRANSFERS — staging acceptance of the web flow with SYNTHETIC fixtures only:
// locations 'ZZ PRUEBA T Bodega' / 'ZZ PRUEBA T Tienda', lab user C1 as seller 'ZZ PRUEBA Vendedora', and stock of the
// existing staging test product "Demo · Paula" received into the synthetic bodega. Remove everything afterwards with:
//   scripts/s00a/run.sh ../f360/transfers_cleanup.mjs
const OWNER = 'carolina.demo@staging.invalid';
const OWNER_PW = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SELLER_PHONE = '+15550100011';
const SELLER = `${SELLER_PHONE.slice(1)}@fuxia.app`;
const SELLER_PW = `fuxia_${SELLER_PHONE}_${process.env.STAGING_OTP_SALT ?? ''}`;
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/transfers';
const kv = (f: string) => Object.fromEntries(readFileSync(f, 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const APP = kv('.env.local');
if (!APP.NEXT_PUBLIC_SUPABASE_URL.includes('faltxpkaicwpnlqaxrdu')) throw new Error('staging only');
const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });

const sb = createClient(APP.NEXT_PUBLIC_SUPABASE_URL, APP.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await sb.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}
type Prod = { id: string; colors: { name: string; variants: { id: string; size: string }[]; balances: { location_id: string; size: string; on_hand: number }[]; in_transit: { size: string; on_hand: number }[] }[] };
let bodega = '', tienda = '', paulaId = '';
async function camel() {
  const p = await call<Prod>('f360_get_product', { p_product_id: paulaId });
  const c = p.colors.find((x) => x.name === 'Camel')!;
  const at = (loc: string, size: string) => c.balances.find((b) => b.location_id === loc && b.size === size)?.on_hand ?? 0;
  const transit = (size: string) => c.in_transit.find((b) => b.size === size)?.on_hand ?? 0;
  return { at, transit, variant: (size: string) => c.variants.find((v) => v.size === size)!.id };
}
async function login(browser: Browser, email: string, pw: string, name: RegExp) {
  const page = await (await browser.newContext({ locale: 'es-MX', timezoneId: 'America/Mexico_City', viewport: { width: 1280, height: 900 } })).newPage();
  await page.goto('/login');
  await page.getByLabel('Correo').fill(email);
  await page.getByLabel('Contraseña').fill(pw);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name })).toBeVisible();
  return page;
}

test.beforeAll(async () => {
  expect(OWNER_PW).not.toBe('');
  expect(process.env.STAGING_OTP_SALT ?? '').not.toBe('');
  await sb.auth.signInWithPassword({ email: OWNER, password: OWNER_PW });
  const seller = createClient(APP.NEXT_PUBLIC_SUPABASE_URL, APP.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  const s = await seller.auth.signInWithPassword({ email: SELLER, password: SELLER_PW });
  if (s.error) throw s.error;
  bodega = (await call<{ id: string }>('f360_create_location', { p_name: 'ZZ PRUEBA T Bodega', p_type: 'warehouse' })).id;
  tienda = (await call<{ id: string }>('f360_create_location', { p_name: 'ZZ PRUEBA T Tienda', p_type: 'store' })).id;
  await call('f360_set_user_role', { p_auth_user_id: s.data.user!.id, p_role: 'seller', p_display_name: 'ZZ PRUEBA Vendedora' });
  await call('f360_set_location_assignment', { p_auth_user_id: s.data.user!.id, p_location_id: tienda, p_active: true });
  paulaId = (await call<{ id: string; name: string }[]>('f360_list_products', { p_query: 'Paula' })).find((p) => p.name === 'Demo · Paula')!.id;
  const c = await camel();
  await call('f360_receive_inventory', { p_idempotency_key: crypto.randomUUID(), p_location_id: bodega,
    p_lines: [{ variant_id: c.variant('35'), quantity: 3 }, { variant_id: c.variant('36'), quantity: 2 }], p_note: 'ZZ PRUEBA transferencias' });
});

test('transfers: send → en camino → partial receipt → difference resolved; seller request', async ({ browser }) => {
  test.setTimeout(300_000);
  const owner = await login(browser, OWNER, OWNER_PW, /Carolina/);
  await expect(owner.getByTestId('in-transit-pairs')).toBeVisible();
  const transitStart = await camel().then((c) => c.transit('35'));
  await shot(owner, '01-inicio-disponible-vs-en-camino');

  // Mover inventario (owner): origen → destino → producto/color/talla/cantidad → resumen → enviar
  await owner.getByRole('link', { name: /Mover inventario/ }).first().click();
  await owner.getByRole('button', { name: /ZZ PRUEBA T Bodega/ }).click();
  await owner.getByRole('button', { name: /ZZ PRUEBA T Tienda/ }).click();
  await owner.getByPlaceholder('Busca el producto').fill('Paula');
  await owner.getByRole('button', { name: /Paula/ }).first().click();
  const camelBtn = owner.getByRole('button', { name: /Camel/ });
  if (await camelBtn.count()) await camelBtn.first().click();
  await owner.getByLabel('Cantidad talla 35').fill('2');
  await owner.getByLabel('Cantidad talla 36').fill('1');
  await shot(owner, '02-mover-tallas');
  await owner.getByRole('button', { name: /Agregar 3 pares/ }).click();
  await expect(owner.getByRole('heading', { name: 'Resumen' })).toBeVisible();
  await shot(owner, '03-mover-resumen');
  await owner.getByRole('button', { name: /Enviar ahora 3 pares/ }).click();
  await expect(owner.getByRole('heading', { name: /Enviado: va en camino/ })).toBeVisible();
  await shot(owner, '04-enviado');
  let c = await camel();
  expect([c.at(bodega, '35'), c.at(bodega, '36'), c.at(tienda, '35'), c.transit('35') - transitStart]).toEqual([1, 1, 0, 2]);

  await owner.goto('/');
  await expect(owner.getByTestId('in-transit-pairs')).toContainText(String(transitStart + 3));
  await shot(owner, '05-inicio-en-camino');
  await owner.goto('/transferencias?vista=en-camino');
  await shot(owner, '06-transferencias-en-camino');

  // Seller (assigned to the destination): confirm receipt with one pair missing
  const seller = await login(browser, SELLER, SELLER_PW, /ZZ PRUEBA Vendedora/);
  await shot(seller, '07-vendedora-inicio');
  await seller.goto('/transferencias?vista=en-camino');
  await seller.getByTestId('transfer-card').first().click();
  await expect(seller.getByRole('button', { name: 'Preparar y enviar' })).toHaveCount(0);   // a seller never sends
  await seller.getByRole('button', { name: 'Confirmar recepción' }).click();
  await seller.getByLabel('Cantidad talla 35').fill('1');
  await expect(seller.getByText(/quedará con diferencia/)).toBeVisible();
  await shot(seller, '08-recepcion-parcial');
  await seller.getByRole('button', { name: /Recibí 2 pares/ }).click();
  await expect(seller.getByRole('button', { name: /Recibí/ })).toHaveCount(0);
  await expect(seller.getByText('Con diferencia', { exact: true }).first()).toBeVisible();
  await shot(seller, '09-con-diferencia');
  c = await camel();
  expect([c.at(tienda, '35'), c.at(tienda, '36'), c.transit('35') - transitStart]).toEqual([1, 1, 1]);   // the missing pair is still En camino

  // Seller asks for more (request only: nothing moves)
  await seller.goto('/mover');
  await seller.getByRole('button', { name: /ZZ PRUEBA T Bodega/ }).click();
  await seller.getByRole('button', { name: /ZZ PRUEBA T Tienda/ }).click();
  await seller.getByPlaceholder('Busca el producto').fill('Paula');
  await seller.getByRole('button', { name: /Paula/ }).first().click();
  if (await seller.getByRole('button', { name: /Camel/ }).count()) await seller.getByRole('button', { name: /Camel/ }).first().click();
  await seller.getByLabel('Cantidad talla 36').fill('1');
  await seller.getByRole('button', { name: /Agregar 1 par/ }).click();
  await expect(seller.getByRole('button', { name: /Enviar ahora/ })).toHaveCount(0);
  await shot(seller, '10-vendedora-resumen-solicitar');
  await seller.getByRole('button', { name: /Solicitar 1 par/ }).click();
  await expect(seller.getByRole('heading', { name: 'Solicitud registrada' })).toBeVisible();
  await shot(seller, '11-vendedora-solicitud');
  c = await camel();
  expect(c.at(bodega, '36')).toBe(1);   // a request reserves nothing

  // Owner: resolve the difference (returns to origin, with reason)
  await owner.goto('/transferencias?vista=diferencias');
  await shot(owner, '12-transferencias-con-diferencia');
  await owner.getByTestId('transfer-card').first().click();
  await expect(owner.getByRole('button', { name: 'Resolver diferencia' })).toBeVisible();
  await shot(owner, '13-detalle-con-diferencia');
  await owner.getByRole('button', { name: 'Resolver diferencia' }).click();
  await owner.getByLabel('Motivo').fill('Se quedó en la bodega al empacar');
  await shot(owner, '14-resolver');
  await owner.getByRole('button', { name: /Resolver 1 par/ }).click();
  await expect(owner.getByRole('button', { name: /Resolver 1 par/ })).toHaveCount(0);
  await expect(owner.getByText('Cerrada', { exact: true }).first()).toBeVisible();
  await shot(owner, '15-cerrada-historial');
  c = await camel();
  expect([c.at(bodega, '35'), c.transit('35') - transitStart]).toEqual([2, 0]);

  // Owner: send the seller's request
  await owner.goto('/transferencias?vista=solicitadas');
  await shot(owner, '16-transferencias-solicitadas');
  await owner.getByTestId('transfer-card').first().click();
  await owner.getByRole('button', { name: 'Preparar y enviar' }).click();
  await expect(owner.getByRole('button', { name: /Enviar 1 par/ })).toBeVisible();
  await shot(owner, '17-preparar-enviar');
  await owner.getByRole('button', { name: /Enviar 1 par/ }).click();
  await expect(owner.getByRole('button', { name: /Enviar 1 par/ })).toHaveCount(0);
  await expect(owner.getByText('En camino', { exact: true }).first()).toBeVisible();
  await seller.goto('/transferencias?vista=en-camino');
  await seller.getByTestId('transfer-card').first().click();
  await seller.getByRole('button', { name: 'Confirmar recepción' }).click();
  await seller.getByRole('button', { name: /Recibí 1 par/ }).click();
  await expect(seller.getByRole('button', { name: /Recibí 1 par/ })).toHaveCount(0);
  await expect(seller.getByText('Recibida', { exact: true }).first()).toBeVisible();
  await owner.goto('/transferencias?vista=recibidas');
  await shot(owner, '18-transferencias-recibidas');
  c = await camel();
  expect([c.at(bodega, '36'), c.at(tienda, '36'), c.transit('36')]).toEqual([0, 2, 0]);
  await owner.goto('/inventario?vista=historial');
  await shot(owner, '19-historial');
});
