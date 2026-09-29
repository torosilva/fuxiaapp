import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';

// P2.3A concurrency: N webhooks fired AT THE SAME TIME for the LAST pair of one variant.
// Expect exactly one sale, N−1 oversell alerts, Bodega never negative, Woo converges to 0.
// Synthetic order ids (not in Woo), correctly signed. Precondition: Macarena Nude 36 = 1 in Fuxia (else skipped — no reset).
const kv = (f: string) => Object.fromEntries(readFileSync(f, 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const WOO = kv('../tools/woo-docker/.env.local');
const APP = kv('.env.local');
const RUNNER = 'http://127.0.0.1:8787';
const SKU = 'F360-MACARENA-NUDE-36';
const N = 5;

test('P2.3A · 5 simultaneous paid orders for the last pair → 1 sale, 4 oversell alerts, never negative', async () => {
  test.setTimeout(120_000);
  const sb = createClient(APP.NEXT_PUBLIC_SUPABASE_URL, APP.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  expect((await sb.auth.signInWithPassword({ email: 'carolina.demo@staging.invalid', password: process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '' })).error).toBeNull();
  const id = ((await sb.rpc('f360_list_products', { p_query: 'Macarena' })).data as { id: string; name: string }[]).find((p) => p.name === 'Macarena')!.id;
  const stock = async () => {
    const p = (await sb.rpc('f360_get_product', { p_product_id: id })).data as { online_location: { id: string }; colors: { variants: { size: string; sku: string }[]; balances: { size: string; location_id: string; on_hand: number }[] }[] };
    const c = p.colors.find((x) => x.variants.some((v) => v.sku === SKU))!;
    return c.balances.find((b) => b.size === '36' && b.location_id === p.online_location.id)?.on_hand ?? 0;
  };
  test.skip((await stock()) !== 1, 'precondition: Nude 36 must have exactly 1 pair (no reset is done to force it)');

  const auth = 'Basic ' + Buffer.from(`${WOO.WOO_USER}:${WOO.WOO_SECRET}`).toString('base64');
  const [prod] = await (await fetch(`${WOO.WOO_BASE_URL}/wp-json/wc/v3/products?sku=F360-MACARENA&status=any`, { headers: { Authorization: auth } })).json();
  const vars = await (await fetch(`${WOO.WOO_BASE_URL}/wp-json/wc/v3/products/${prod.id}/variations?per_page=100`, { headers: { Authorization: auth } })).json() as { id: number; sku: string; stock_quantity: number }[];
  const variation = vars.find((v) => v.sku === SKU)!;

  const base = 8_000_000 + Math.floor(Date.now() / 1000) % 1_000_000;
  const now = new Date().toISOString().slice(0, 19);
  const send = (i: number) => {
    const body = JSON.stringify({ id: base + i, status: 'processing', date_modified_gmt: now, currency: 'MXN', refunds: [],
      billing: { first_name: 'Sintético', email: 'x@local.invalid' },
      line_items: [{ id: 1, product_id: prod.id, variation_id: variation.id, sku: SKU, quantity: 1 }] });
    return fetch(`${RUNNER}/f360-woo-orders`, { method: 'POST', body, headers: { 'content-type': 'application/json', 'x-wc-webhook-topic': 'order.updated',
      'x-wc-webhook-delivery-id': `conc-${base}-${i}`, 'x-wc-webhook-signature': createHmac('sha256', WOO.WOO_WEBHOOK_SECRET).update(body).digest('base64') } })
      .then((r) => r.json() as Promise<{ result: string; lines: { outcome: string }[] }>);
  };
  const results = await Promise.all(Array.from({ length: N }, (_, i) => send(i)));   // all in flight at once
  const outcomes = results.map((r) => r.lines?.[0]?.outcome).sort();
  console.log('outcomes:', outcomes.join(', '));
  expect(results.every((r) => r.result === 'applied')).toBe(true);
  expect(outcomes.filter((o) => o === 'sold')).toHaveLength(1);
  expect(outcomes.filter((o) => o === 'oversold')).toHaveLength(N - 1);
  expect(await stock(), 'Bodega never negative').toBe(0);

  // Woo converges to Bodega (0) through the automatic push
  const end = Date.now() + 30_000; let w = -1;
  while (Date.now() < end) {
    const vv = await (await fetch(`${WOO.WOO_BASE_URL}/wp-json/wc/v3/products/${prod.id}/variations/${variation.id}`, { headers: { Authorization: auth } })).json() as { stock_quantity: number };
    w = vv.stock_quantity; if (w === 0) break; await new Promise((r) => setTimeout(r, 1000));
  }
  expect(w, 'Woo converges to 0').toBe(0);

  // Close the synthetic oversell alerts (they are test artifacts, not real orders)
  const issues = ((await sb.rpc('f360_list_sync_issues', { p_status: 'open' })).data as { issues: { id: string; kind: string; woo_order_id: number }[] }).issues
    .filter((i) => i.kind === 'oversell' && i.woo_order_id >= base && i.woo_order_id < base + N);
  expect(issues).toHaveLength(N - 1);
  for (const i of issues) expect((await sb.rpc('f360_resolve_sync_issue', { p_id: i.id, p_note: 'Prueba de concurrencia E2E (pedidos sintéticos, no existen en Woo)' })).error).toBeNull();
});
