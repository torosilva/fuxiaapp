import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';

// C3 CLOSED LOOP (staging, synthetic): migrated store → sale through the same RPC the app calls → inventory −1 →
// loyalty → Customer 360 / Growth fact → the SAME sale in Fuxia 360 Web · Ventas.
// Prereq: scripts/s00a/run.sh ../f360/c3_e2e_prepare.mjs   (synthetic store, C2, cutover by verified count)
// Cleanup: scripts/s00a/run.sh ../f360/c3_cleanup.mjs
const OWNER = 'carolina.demo@staging.invalid';
const OWNER_PW = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SELLER_PHONE = '+15550100011';
const SELLER_PW = `fuxia_${SELLER_PHONE}_${process.env.STAGING_OTP_SALT ?? ''}`;
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/c3';
const FIX = JSON.parse(readFileSync(process.env.C3_E2E_FILE ?? '/tmp/c3_e2e.json', 'utf8')) as { location_id: string; location: string; v35: string; qr: string; status: string };
const kv = (f: string) => Object.fromEntries(readFileSync(f, 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const APP = kv('.env.local');
if (!APP.NEXT_PUBLIC_SUPABASE_URL.includes('faltxpkaicwpnlqaxrdu')) throw new Error('staging only');

const ownerDb = createClient(APP.NEXT_PUBLIC_SUPABASE_URL, APP.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const sellerDb = createClient(APP.NEXT_PUBLIC_SUPABASE_URL, APP.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
async function call<T>(db: typeof ownerDb, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}
type Loc = { id: string; products: { colors: { name: string; sizes: { size: string; on_hand: number }[] }[] }[] };
async function stock35(): Promise<number> {
  const [loc] = await call<Loc[]>(ownerDb, 'f360_inventory_by_location', { p_location_id: FIX.location_id });
  return loc?.products.flatMap((p) => p.colors).find((c) => c.name === 'Negro')?.sizes.find((s) => s.size === '35')?.on_hand ?? 0;
}

test('closed loop: app sale → inventory −1 → loyalty → C360/Growth → Ventas', async ({ page }) => {
  test.setTimeout(180_000);
  expect(FIX.status).toBe('completed');
  await ownerDb.auth.signInWithPassword({ email: OWNER, password: OWNER_PW });
  const s = await sellerDb.auth.signInWithPassword({ email: `${SELLER_PHONE.slice(1)}@fuxia.app`, password: SELLER_PW });
  expect(s.error).toBeNull();

  // 1 · the seller's app: shift with PIN at the migrated store, catalog, sale with a customer QR (same RPCs as the app)
  const shift = await call<{ token: string }>(sellerDb, 'f360_start_seller_shift', { p_location_id: FIX.location_id, p_pin: '2468' });
  const catalog = await call<{ ledger: string; items: { variant_id: string; price: number; available: number }[] }>(sellerDb, 'f360_shift_catalog', { p_token: shift.token });
  expect(catalog.ledger).toBe('f360');
  const before = await stock35();
  const key = crypto.randomUUID();
  const sale = await call<{ ok: boolean; sale_id: string; total: number; points: number; ledger: string }>(sellerDb, 'f360_record_store_sale',
    { p_token: shift.token, p_idempotency_key: key, p_lines: [{ variant_id: FIX.v35, quantity: 1 }], p_payment_method: 'card', p_customer_qr: FIX.qr });
  expect([sale.ok, sale.ledger, sale.points]).toEqual([true, 'f360', 100]);
  const retry = await call<{ replayed: boolean; sale_id: string }>(sellerDb, 'f360_record_store_sale',
    { p_token: shift.token, p_idempotency_key: key, p_lines: [{ variant_id: FIX.v35, quantity: 1 }], p_payment_method: 'card', p_customer_qr: FIX.qr });
  expect([retry.replayed, retry.sale_id]).toEqual([true, sale.sale_id]);

  // 2 · inventory −1 (exactly once), loyalty, and the Customer 360 / Growth fact
  expect(await stock35()).toBe(before - 1);
  const detail = await call<{ loyalty: { state: string; points: number }; inventory: { kind: string }; customer: { name: string } | null }>(ownerDb, 'f360_get_sale', { p_sale_id: sale.sale_id });
  expect([detail.loyalty.state, detail.loyalty.points, detail.inventory.kind, detail.customer?.name]).toEqual(['credited', 100, 'f360', 'ZZ PRUEBA C3 clienta']);
  const list = await call<{ items: { id: string }[] }>(ownerDb, 'f360_list_sales', { p_location_id: FIX.location_id });
  expect(list.items.filter((i) => i.id === sale.sale_id)).toHaveLength(1);

  // 3 · the same sale in Fuxia 360 Web · Ventas
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(OWNER);
  await page.getByLabel('Contraseña').fill(OWNER_PW);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  await page.goto(`/inventario?ubicacion=${FIX.location_id}`);
  await page.screenshot({ path: `${SHOTS}/01-inventario-tienda-migrada.png`, fullPage: true });
  await page.getByRole('link', { name: 'Ventas' }).first().click();
  await expect(page.getByRole('heading', { name: 'Ventas' })).toBeVisible();
  await page.getByLabel('Ubicación').selectOption({ label: FIX.location });
  await page.getByRole('button', { name: 'Filtrar' }).click();
  await expect(page.getByTestId('sale-row')).toHaveCount(1);
  await expect(page.getByTestId('sales-summary')).toContainText('$2,800');
  await expect(page.getByTestId('sale-row').first()).toContainText('ZZ PRUEBA C3 clienta');
  await page.screenshot({ path: `${SHOTS}/02-ventas-lista.png`, fullPage: true });
  await page.getByTestId('sale-row').first().getByRole('link').click();
  await expect(page.getByTestId('sale-item')).toContainText('Macarena');
  await expect(page.getByTestId('sale-loyalty')).toContainText('100 puntos');
  await expect(page.getByText(/vendió 1 par de ZZ PRUEBA C3 Tienda/)).toBeVisible();
  await page.getByText('Datos para soporte').click();
  await page.screenshot({ path: `${SHOTS}/03-venta-detalle.png`, fullPage: true });

  // 4 · an anonymous sale shows "Sin identificar" and why no points
  const anon = await call<{ sale_id: string }>(sellerDb, 'f360_record_store_sale',
    { p_token: shift.token, p_idempotency_key: crypto.randomUUID(), p_lines: [{ variant_id: FIX.v35, quantity: 1 }], p_payment_method: 'cash' });
  await page.goto(`/ventas/${anon.sale_id}`);
  await expect(page.getByTestId('sale-customer')).toContainText('Sin identificar');
  await expect(page.getByTestId('sale-loyalty')).toContainText('reclamar');
  await page.screenshot({ path: `${SHOTS}/04-venta-sin-clienta.png`, fullPage: true });
  await page.goto(`/ventas?ubicacion=${FIX.location_id}`);
  await expect(page.getByTestId('sale-row')).toHaveCount(2);
  await expect(page.getByTestId('sales-summary')).toContainText('$5,600');
  await page.screenshot({ path: `${SHOTS}/05-ventas-resumen.png`, fullPage: true });
  expect(await stock35()).toBe(before - 2);
});
