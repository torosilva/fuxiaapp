import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { normalizePhone } from '../_shared/phone.ts';

// ============================================================================
// backfill-orders — acredita puntos por ventas históricas de WooCommerce que
// nunca dispararon el webhook (Fase 0, uso único).
// ----------------------------------------------------------------------------
// Recorre las órdenes PAGADAS (processing/completed) de WooCommerce y, por cada
// una que no esté ya registrada, aplica la MISMA lógica del webhook:
//   • match clienta por teléfono → email
//   • acredita 100 pts/par a su tarjeta (+ transacción + items), o
//   • si no hay clienta, la guarda en unmatched_orders (retro-crédito futuro).
//
// Idempotente: si el wc_order_id ya está en transactions, se salta.
// Modo simulación: body { "dry_run": true } NO escribe nada, solo reporta.
//
// SEGURIDAD: protegido por verify-jwt (default). Invocar con el service key o
// un JWT válido. Borrar la función después del backfill.
// ============================================================================

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WC_URL = Deno.env.get('WC_URL')!;
const WC_CONSUMER_KEY = Deno.env.get('WC_CONSUMER_KEY')!;
const WC_CONSUMER_SECRET = Deno.env.get('WC_CONSUMER_SECRET')!;

const POINTS_PER_PAIR = 100;
const PAID_STATUSES = ['processing', 'completed'];

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data, null, 2), { status, headers: { 'Content-Type': 'application/json' } });
}

function extractMeta(item: any, keys: string[]): string | null {
  if (!item.meta_data) return null;
  for (const m of item.meta_data) { if (keys.includes(m.key)) return m.value; }
  return null;
}

async function computeTier(supabase: any, points: number): Promise<string> {
  const { data } = await supabase.from('tier_config').select('tier, min_points');
  const rows = (data ?? []) as { tier: string; min_points: number }[];
  const thresholds = rows.length
    ? rows
    : [{ tier: 'bronze', min_points: 0 }, { tier: 'silver', min_points: 300 }, { tier: 'gold', min_points: 900 }];
  let result = 'bronze';
  for (const r of thresholds.sort((a, b) => a.min_points - b.min_points)) {
    if (points >= r.min_points) result = r.tier;
  }
  return result;
}

// Trae TODAS las órdenes de un estado, paginando.
async function fetchAllOrders(status: string): Promise<any[]> {
  const basicAuth = btoa(`${WC_CONSUMER_KEY}:${WC_CONSUMER_SECRET}`);
  const all: any[] = [];
  for (let page = 1; page <= 50; page++) {
    const params = new URLSearchParams({
      per_page: '100', page: String(page), orderby: 'date', order: 'asc', status,
    });
    const res = await fetch(`${WC_URL}/orders?${params.toString()}`, { headers: { Authorization: `Basic ${basicAuth}` } });
    if (!res.ok) throw new Error(`WC ${status} page ${page} → ${res.status} ${await res.text()}`);
    const batch = await res.json();
    if (!Array.isArray(batch) || batch.length === 0) break;
    all.push(...batch);
    if (batch.length < 100) break;
  }
  return all;
}

serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  let dryRun = true;
  try {
    const body = await req.json();
    if (body?.dry_run === false) dryRun = false;
  } catch { /* body opcional → dry-run por defecto */ }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // 1. Traer todas las órdenes pagadas.
  let orders: any[] = [];
  try {
    for (const st of PAID_STATUSES) orders.push(...(await fetchAllOrders(st)));
  } catch (err) {
    return json({ error: String(err) }, 502);
  }

  const summary = {
    dry_run: dryRun,
    scanned: orders.length,
    already_credited: 0,
    credited: 0,
    credited_points: 0,
    unmatched: 0,
    skipped_no_card: 0,
    detail_credit: [] as any[],
    detail_unmatched: [] as any[],
  };

  for (const order of orders) {
    const wcOrderId = order.id;

    // Idempotencia: si ya existe una transacción para esta orden, saltar.
    const { data: existingTx } = await supabase
      .from('transactions').select('id').eq('wc_order_id', wcOrderId).maybeSingle();
    if (existingTx) { summary.already_credited++; continue; }

    const phone = normalizePhone(order.billing?.phone, order.billing?.country);
    const email = order.billing?.email?.toLowerCase() ?? null;
    const amount = parseFloat(order.total ?? '0');
    const pairs = (order.line_items ?? []).reduce((s: number, it: any) => s + (it.quantity ?? 0), 0);
    const points = pairs * POINTS_PER_PAIR;
    const status = String(order.status).toLowerCase();

    // Match clienta por teléfono → email.
    let customer: { id: string; name: string | null } | null = null;
    if (phone) {
      const { data } = await supabase.from('customers').select('id, name').eq('phone', phone).maybeSingle();
      customer = data;
    }
    if (!customer && email) {
      const { data } = await supabase.from('customers').select('id, name').ilike('email', email).maybeSingle();
      customer = data;
    }

    const items = (order.line_items ?? []).map((it: any) => ({
      sku: it.sku || `WC-${it.id}`, product_id: it.product_id ?? null,
      product_name: it.name, quantity: it.quantity,
      size: extractMeta(it, ['pa_size', 'Size', 'Talla']), color: extractMeta(it, ['pa_color', 'Color']),
      unit_price: it.quantity > 0 ? parseFloat(it.total) / it.quantity : parseFloat(it.total ?? '0'),
    }));

    if (!customer) {
      summary.unmatched++;
      summary.detail_unmatched.push({ wc_order_id: wcOrderId, phone, email, points, status });
      if (!dryRun) {
        await supabase.from('unmatched_orders').upsert({
          wc_order_id: wcOrderId, phone, email, total: amount, currency: order.currency ?? 'MXN',
          pairs, points, wc_status: status, items,
        }, { onConflict: 'wc_order_id' });
      }
      continue;
    }

    // Tarjeta de la clienta.
    const { data: card } = await supabase
      .from('loyalty_cards').select('id, total_points, pairs_count').eq('customer_id', customer.id).single();
    if (!card) { summary.skipped_no_card++; continue; }

    summary.credited++;
    summary.credited_points += points;
    summary.detail_credit.push({ wc_order_id: wcOrderId, customer: customer.name, phone, email, points, pairs, status });

    if (!dryRun) {
      const { data: tx } = await supabase.from('transactions').insert({
        loyalty_card_id: card.id, wc_order_id: wcOrderId, amount, currency: order.currency ?? 'MXN',
        points_earned: points, pairs_in_order: pairs, channel: 'web', wc_status: status,
      }).select('id').single();

      if (tx && items.length) {
        await supabase.from('purchase_items').insert(items.map((it: any) => ({
          transaction_id: tx.id, sku: it.sku, wc_product_id: it.product_id ?? null,
          product_name: it.product_name ?? 'Producto',
          size: it.size, color: it.color, category: null, quantity: it.quantity ?? 1, unit_price: it.unit_price ?? 0,
        })));
      }

      const newPoints = card.total_points + points;
      const newPairs = card.pairs_count + pairs;
      await supabase.from('loyalty_cards').update({
        total_points: newPoints, pairs_count: newPairs,
        tier: await computeTier(supabase, newPoints), updated_at: new Date().toISOString(),
      }).eq('id', card.id);

      // Si estaba como huérfana, marcarla acreditada.
      await supabase.from('unmatched_orders').update({ matched_at: new Date().toISOString() })
        .eq('wc_order_id', wcOrderId).is('matched_at', null);
    }
  }

  return json(summary);
});
