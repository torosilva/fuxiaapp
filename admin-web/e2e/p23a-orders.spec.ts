import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';

// P2.3A LOCAL ACCEPTANCE — Fuxia 360 (staging) ↔ local Docker WooCommerce: stock authority, paid orders → SALE,
// idempotency, out-of-order, duplicates, legacy, unknown SKU, concurrency/oversell, temporary Woo failure, cancellation,
// reconciliation. NO resets: works on the current Macarena (Negro 37 must start at 2 in Fuxia and in Woo).
// Prereqs: local runner (scripts/f360/publisher_local.ts) on :8787 and admin-web on :3000.
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/p23a';
const RUNNER = 'http://127.0.0.1:8787';
const kv = (f: string) => Object.fromEntries(readFileSync(f, 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const WOO = kv('../tools/woo-docker/.env.local');
const APP = kv('.env.local');
if (!/^http:\/\/localhost:\d+$/.test(WOO.WOO_BASE_URL)) throw new Error('local Woo only');
if (!APP.NEXT_PUBLIC_SUPABASE_URL.includes('faltxpkaicwpnlqaxrdu')) throw new Error('staging only');
const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });

// ── local Woo REST ──
const auth = 'Basic ' + Buffer.from(`${WOO.WOO_USER}:${WOO.WOO_SECRET}`).toString('base64');
async function woo<T>(path: string, method = 'GET', body?: unknown): Promise<T> {
  const r = await fetch(`${WOO.WOO_BASE_URL}/wp-json/wc/v3${path}`, { method, headers: { Authorization: auth, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const j = await r.json();
  if (!r.ok) throw new Error(`${method} ${path} → ${r.status} ${JSON.stringify(j).slice(0, 200)}`);
  return j as T;
}
type WV = { id: number; sku: string; stock_quantity: number | null };
let macarenaWooId = 0;
async function wooStock(): Promise<Record<string, WV>> {
  const vars = await woo<WV[]>(`/products/${macarenaWooId}/variations?per_page=100`);
  return Object.fromEntries(vars.map((v) => [v.sku, v]));
}
const order = (lines: { product_id: number; variation_id?: number; quantity: number }[]) =>
  woo<{ id: number; status: string }>('/orders', 'POST', { status: 'processing', set_paid: true, payment_method: 'bacs', payment_method_title: 'Prueba local',
    billing: { first_name: 'Prueba', last_name: 'Local', email: 'prueba@local.invalid' }, line_items: lines });

// ── Fuxia 360 as Carolina (same RPCs the app uses) ──
const sb = createClient(APP.NEXT_PUBLIC_SUPABASE_URL, APP.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
type Prod = { id: string; online_location: { id: string }; colors: { name: string; variants: { id: string; size: string; sku: string }[]; balances: { location_id: string; size: string; on_hand: number }[] }[] };
let macarenaId = '';
async function fuxia(): Promise<Record<string, { stock: number; variantId: string }>> {
  const { data, error } = await sb.rpc('f360_get_product', { p_product_id: macarenaId });
  if (error) throw error;
  const p = data as Prod;
  const out: Record<string, { stock: number; variantId: string }> = {};
  for (const c of p.colors) for (const v of c.variants) out[v.sku] = { variantId: v.id, stock: c.balances.find((b) => b.size === v.size && b.location_id === p.online_location.id)?.on_hand ?? 0 };
  return out;
}
async function overview() { const { data } = await sb.rpc('f360_list_sync_issues', { p_status: 'open' }); return data as { issues: { kind: string; woo_order_id: number | null; id: string }[]; recent_pushes: { ok: boolean; label: string; error: string | null }[]; recent_orders: { order: number; result: string; lines: { outcome: string }[] | null }[] }; }
async function until<T>(what: string, fn: () => Promise<T>, ok: (x: T) => boolean, ms = 45_000): Promise<T> {
  const end = Date.now() + ms; let last: T;
  do { last = await fn(); if (ok(last)) return last; await new Promise((r) => setTimeout(r, 1000)); } while (Date.now() < end);
  throw new Error(`timeout waiting for ${what}: ${JSON.stringify(last!).slice(0, 300)}`);
}

// ── webhook replay helpers (runner keeps the last raw deliveries) ──
type Delivery = { headers: Record<string, string>; body: string };
const parse = (b: string) => { try { return JSON.parse(b); } catch { return null; } };   // Woo "ping" bodies are not JSON
const deliveriesFor = async (orderId: number) => ((await (await fetch(`${RUNNER}/__deliveries`)).json()) as Delivery[]).filter((d) => parse(d.body)?.id === orderId);
const post = (body: string, headers: Record<string, string>) =>
  fetch(`${RUNNER}/f360-woo-orders`, { method: 'POST', headers: { 'content-type': 'application/json', ...Object.fromEntries(Object.entries(headers).filter(([k]) => k.startsWith('x-wc-'))) }, body })
    .then(async (r) => ({ status: r.status, json: await r.json() }));
const sign = (body: string) => createHmac('sha256', WOO.WOO_WEBHOOK_SECRET).update(body).digest('base64');

test('P2.3A · Macarena: stock authority, paid order → sale, replay/duplicates/out-of-order, legacy, unknown, concurrency, failure, cancel, reconcile', async ({ page }) => {
  test.setTimeout(600_000);
  expect(PASSWORD).not.toBe('');
  const { error } = await sb.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
  expect(error).toBeNull();
  const { data: list } = await sb.rpc('f360_list_products', { p_query: 'Macarena' });
  macarenaId = (list as { id: string; name: string }[]).find((p) => p.name === 'Macarena')!.id;
  macarenaWooId = (await woo<{ id: number }[]>('/products?sku=F360-MACARENA&status=any'))[0].id;
  const N37 = 'F360-MACARENA-NEGRO-37';

  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();

  // ── 1 · Baseline: Fuxia 2, Woo 2 — or RESUME: if an earlier run already sold it (2 → 1), reuse that order (no reset).
  const events = async () => (await sb.rpc('f360_list_events', { p_limit: 50, p_product_id: macarenaId, p_location_id: null })).data as { type: string; reference_id: string | null; lines: { sku: string }[] }[];
  const priorSale = (await events()).find((e) => e.type === 'SALE' && e.lines.some((l) => l.sku === N37));
  let o1: { id: number };
  if ((await fuxia())[N37].stock === 2) {
    expect((await wooStock())[N37].stock_quantity, 'Woo Negro 37 starts at 2').toBe(2);
    await page.goto(`/productos/${macarenaId}`);
    await shot(page, '01-macarena-antes');
    // ── 2 · Paid order of 1 pair in Woo → webhook → SALE in Fuxia → Fuxia 1, Woo 1
    o1 = await order([{ product_id: macarenaWooId, variation_id: (await wooStock())[N37].id, quantity: 1 }]);
    await until('Fuxia Negro 37 = 1', fuxia, (f) => f[N37].stock === 1);
    await until('Woo Negro 37 = 1', wooStock, (w) => w[N37].stock_quantity === 1);
  } else {
    expect(priorSale, 'resume only if the earlier run recorded the sale').toBeTruthy();
    o1 = { id: Number(priorSale!.reference_id!.split(':').pop()) };
    console.log(`RESUMED: steps 1–2 were executed by an earlier run (order #${o1.id}); Negro 37 already 2 → 1.`);
    expect((await fuxia())[N37].stock).toBe(1);
    expect((await wooStock())[N37].stock_quantity).toBe(1);
  }
  expect((await events()).filter((e) => e.type === 'SALE' && e.reference_id === `woo_local:${o1.id}`), 'exactly one auditable SALE for the order').toHaveLength(1);
  await page.goto(`/productos/${macarenaId}`);
  await expect(page.getByText(`Pedido en línea #${o1.id}`).first()).toBeVisible();
  await shot(page, '02-venta-en-historial');

  // ── 3 · Exactly the same webhook again → no change
  let [d1] = await deliveriesFor(o1.id);
  if (!d1) {   // runner restarted since the sale: ask Woo to send the order again (a real "order.updated" webhook)
    await woo(`/orders/${o1.id}`, 'PUT', { customer_note: '' });
    [d1] = await until('webhook captured', () => deliveriesFor(o1.id), (x) => x.length > 0);
  }
  expect(d1, 'the webhook reached Fuxia 360').toBeTruthy();
  const replay = await post(d1.body, d1.headers);
  expect(replay.status).toBe(200);
  expect(replay.json.result).toBe('duplicate_delivery');
  // same content, new delivery id → still nothing
  const dup = await post(d1.body, { ...d1.headers, 'x-wc-webhook-delivery-id': `dup-${Date.now()}` });
  expect(['duplicate', 'duplicate_delivery']).toContain(dup.json.result);
  // out of order: an OLDER version (pending) arriving late
  const old = JSON.parse(d1.body); old.status = 'pending';
  old.date_modified_gmt = new Date(new Date(old.date_modified_gmt + 'Z').getTime() - 3600_000).toISOString().slice(0, 19);
  const oldBody = JSON.stringify(old);
  const stale = await post(oldBody, { ...d1.headers, 'x-wc-webhook-delivery-id': `old-${Date.now()}`, 'x-wc-webhook-signature': sign(oldBody) });
  expect(stale.json.result).toBe('stale');
  // forged signature → rejected
  const forged = await post(d1.body, { ...d1.headers, 'x-wc-webhook-delivery-id': `forged-${Date.now()}`, 'x-wc-webhook-signature': 'AAAA' });
  expect(forged.status).toBe(401);
  expect((await fuxia())[N37].stock).toBe(1);
  expect((await wooStock())[N37].stock_quantity).toBe(1);

  // ── 4 · Reconciliation from the Avisos screen: everything in sync
  await page.goto('/avisos');
  await page.getByRole('button', { name: 'Revisar ahora' }).click();
  await expect(page.getByRole('status')).toContainText('coinciden', { timeout: 60_000 });
  await expect(page.getByTestId('reconciliation')).toContainText('Todo coincide: 18 de 18');
  await shot(page, '03-avisos-reconciliacion-ok');

  // ── 5 · Legacy product (not Fuxia 360) sold → ignored, no alert; unknown F360 SKU → alert
  const ts = Date.now().toString(36).toUpperCase();
  const legacy = await woo<{ id: number }>('/products', 'POST', { name: `Slingback legacy ${ts}`, type: 'simple', sku: `LEG-${ts}`, regular_price: '1500', status: 'publish' });
  const ghost = await woo<{ id: number }>('/products', 'POST', { name: `Fantasma ${ts}`, type: 'simple', sku: `F360-FANTASMA-${ts}`, regular_price: '1500', status: 'publish' });
  const oL = await order([{ product_id: legacy.id, quantity: 1 }]);
  const oG = await order([{ product_id: ghost.id, quantity: 1 }]);
  const ov = await until('legacy + unknown processed', overview, (o) => o.recent_orders.some((r) => r.order === oG.id && r.result === 'applied') && o.recent_orders.some((r) => r.order === oL.id && r.result === 'applied'));
  expect(ov.recent_orders.find((r) => r.order === oL.id && r.result === 'applied')!.lines![0].outcome).toBe('legacy');
  expect(ov.issues.some((i) => i.woo_order_id === oL.id), 'legacy line never raises an alert').toBe(false);
  expect(ov.issues.some((i) => i.kind === 'unknown_sku' && i.woo_order_id === oG.id)).toBe(true);

  // ── 6 · Fuxia → Woo automatic sync: Carolina receives 1 Rojo 38 → the store shows 1 by itself
  const R38 = 'F360-MACARENA-ROJO-38';
  const r38Before = (await fuxia())[R38].stock;
  await page.goto(`/recibir?producto=${macarenaId}`);
  await page.getByRole('button', { name: /Rojo/ }).click();
  await page.getByRole('button', { name: 'Más talla 38', exact: true }).click();
  await page.getByRole('button', { name: /Recibir 1 par/i }).click();
  await expect(page.getByText('Carolina recibió 1 par en Bodega CDMX')).toBeVisible({ timeout: 30_000 });
  await until('Woo Rojo 38 follows Bodega', wooStock, (w) => w[R38].stock_quantity === r38Before + 1);
  await shot(page, '04-recibir-rojo-38-sincroniza');

  // ── 7 · Concurrency: two paid orders race for the LAST pair of Rojo 38 → one sale, one oversell alert, never negative
  expect((await fuxia())[R38].stock).toBe(1);
  const r38 = (await wooStock())[R38].id;
  const [oA, oB] = await Promise.all([order([{ product_id: macarenaWooId, variation_id: r38, quantity: 1 }]), order([{ product_id: macarenaWooId, variation_id: r38, quantity: 1 }])]);
  const ov2 = await until('both racing orders processed', overview, (o) => [oA.id, oB.id].every((id) => o.recent_orders.some((r) => r.order === id && r.result === 'applied')));
  const outcomes = [oA.id, oB.id].map((id) => ov2.recent_orders.find((r) => r.order === id && r.result === 'applied')!.lines![0].outcome).sort();
  expect(outcomes).toEqual(['oversold', 'sold']);
  expect((await fuxia())[R38].stock, 'Bodega never negative').toBe(0);
  expect(ov2.issues.some((i) => i.kind === 'oversell' && [oA.id, oB.id].includes(i.woo_order_id!))).toBe(true);
  await until('Woo Rojo 38 corrected to 0', wooStock, (w) => w[R38].stock_quantity === 0);

  // ── 8 · Temporary Woo failure while syncing → retried automatically → recovers
  const N36 = 'F360-MACARENA-NUDE-36';
  const n36Before = (await fuxia())[N36].stock;
  await fetch(`${RUNNER}/__faults`, { method: 'POST', body: JSON.stringify({ faults: ['stock'] }) });
  const rcv = await sb.rpc('f360_receive_inventory', { p_idempotency_key: crypto.randomUUID(), p_location_id: (await sb.rpc('f360_get_product', { p_product_id: macarenaId })).data.online_location.id,
    p_lines: [{ variant_id: (await fuxia())[N36].variantId, quantity: 1 }], p_note: 'Prueba P2.3A: falla temporal de Woo' });
  expect(rcv.error).toBeNull();
  await until('a failed push is logged', overview, (o) => o.recent_pushes.some((p) => !p.ok && /Nude · 36/.test(p.label)));
  await until('Woo Nude 36 recovered after retry', wooStock, (w) => w[N36].stock_quantity === n36Before + 1, 60_000);

  // ── 9 · Cancellation after sale → alert (DW4 pending), NO automatic restock; reconciliation re-aligns Woo
  const soldOrder = [oA.id, oB.id].find((id) => ov2.recent_orders.find((r) => r.order === id && r.result === 'applied')!.lines![0].outcome === 'sold')!;
  await woo(`/orders/${soldOrder}`, 'PUT', { status: 'cancelled' });
  await until('cancellation alert', overview, (o) => o.issues.some((i) => i.kind === 'cancel_after_sale' && i.woo_order_id === soldOrder));
  expect((await fuxia())[R38].stock, 'no automatic restock in Fuxia').toBe(0);
  await page.goto('/avisos');
  await page.getByRole('button', { name: 'Revisar ahora' }).click();
  await expect(page.getByRole('status')).toBeVisible({ timeout: 60_000 });
  await until('Woo Rojo 38 re-aligned to Fuxia (0)', wooStock, (w) => w[R38].stock_quantity === 0);
  await page.reload();
  await page.getByRole('button', { name: 'Revisar ahora' }).click();
  await expect(page.getByRole('status')).toContainText('18 de 18 coinciden', { timeout: 60_000 });
  await page.reload();
  await shot(page, '05-avisos-alertas');

  // ── 10 · Operator resolves the technical alerts with a note; business decisions stay open
  for (const kind of ['webhook_rejected', 'unknown_sku']) {
    const before = Number((await page.getByRole('heading', { name: /Pendientes \(\d+\)/ }).innerText()).match(/\d+/)![0]);
    const card = page.locator(`article[data-kind="${kind}"]`).first();
    await card.getByRole('button', { name: 'Marcar como resuelto' }).click();
    await card.getByLabel('Qué se hizo').fill(kind === 'unknown_sku' ? 'Producto de prueba local, no existe en Fuxia 360' : 'Prueba de firma inválida (E2E)');
    await card.getByRole('button', { name: 'Guardar' }).click();
    // really saved: the pending counter goes down (not just the button hidden by the open form)
    await expect(page.getByRole('heading', { name: `Pendientes (${before - 1})` })).toBeVisible({ timeout: 15_000 });
  }
  await shot(page, '06-avisos-pendientes-de-negocio');
  await page.goto('/avisos?ver=resueltos');
  await shot(page, '07-avisos-resueltos');

  // ── 11 · Final state: Macarena Negro 37 = 1 in Fuxia and in Woo; history readable
  expect((await fuxia())[N37].stock).toBe(1);
  expect((await wooStock())[N37].stock_quantity).toBe(1);
  await page.goto('/inventario?vista=historial');
  await shot(page, '08-historial-inventario');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/avisos');
  await shot(page, 'm1-avisos-movil');
  await page.goto('/mas');
  await shot(page, 'm2-mas-movil');
});
