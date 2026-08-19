import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================================
// link-orders — retro-crédito de órdenes huérfanas (Fase 0)
// ----------------------------------------------------------------------------
// Cuando una clienta se registra (o agrega su email), busca en unmatched_orders
// las compras web que llegaron ANTES de que existiera su perfil y las acredita
// a su tarjeta. Convierte "compré antes de bajar la app" en "+300 pts al abrir".
//
// Llamar desde la app justo después de createProfile (con el JWT del usuario).
// Deploy con verify-jwt ACTIVADO (default).
// ============================================================================

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

type Tier = 'bronze' | 'silver' | 'gold';

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...CORS } });
}

async function computeTier(supabase: ReturnType<typeof createClient>, points: number): Promise<Tier> {
  const { data } = await supabase.from('tier_config').select('tier, min_points');
  const rows = (data ?? []) as { tier: string; min_points: number }[];
  const thresholds = rows.length ? rows
    : [{ tier: 'bronze', min_points: 0 }, { tier: 'silver', min_points: 300 }, { tier: 'gold', min_points: 900 }];
  let result: Tier = 'bronze';
  for (const r of thresholds.sort((a, b) => a.min_points - b.min_points)) {
    if (points >= r.min_points) result = r.tier as Tier;
  }
  return result;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'No autorizado' }, 401);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: 'Sesión inválida' }, 401);

  const authUserId = userData.user.id;
  const metaPhone = (userData.user.user_metadata as any)?.phone ?? null;

  let { data: customer } = await supabase
    .from('customers').select('id, phone, email').eq('auth_user_id', authUserId).maybeSingle();
  if (!customer && metaPhone) {
    const r = await supabase.from('customers').select('id, phone, email').eq('phone', metaPhone).maybeSingle();
    customer = r.data;
  }
  if (!customer) return json({ error: 'Perfil no encontrado' }, 404);

  // Órdenes huérfanas que matchean por teléfono o email, aún sin acreditar.
  const orFilters: string[] = [];
  if (customer.phone) orFilters.push(`phone.eq.${customer.phone}`);
  if (customer.email) orFilters.push(`email.eq.${customer.email.toLowerCase()}`);
  if (!orFilters.length) return json({ ok: true, linked: 0, points: 0 });

  const { data: orphans } = await supabase
    .from('unmatched_orders').select('*').is('matched_at', null).or(orFilters.join(','));
  if (!orphans || orphans.length === 0) return json({ ok: true, linked: 0, points: 0 });

  const { data: card } = await supabase
    .from('loyalty_cards').select('id, total_points, pairs_count').eq('customer_id', customer.id).single();
  if (!card) return json({ error: 'Tarjeta no encontrada' }, 500);

  let addedPoints = 0, addedPairs = 0, linked = 0;

  for (const o of orphans) {
    // Idempotencia: si ya existe transacción para esa wc_order_id, solo marcar.
    const { data: existing } = await supabase.from('transactions').select('id').eq('wc_order_id', o.wc_order_id).maybeSingle();
    if (!existing) {
      const { data: tx } = await supabase.from('transactions').insert({
        loyalty_card_id: card.id, wc_order_id: o.wc_order_id, amount: o.total, currency: o.currency ?? 'MXN',
        points_earned: o.points, pairs_in_order: o.pairs, channel: 'web', wc_status: o.wc_status,
      }).select('id').single();
      if (tx && Array.isArray(o.items) && o.items.length) {
        await supabase.from('purchase_items').insert(o.items.map((it: any) => ({
          transaction_id: tx.id, sku: it.sku ?? null, wc_product_id: it.product_id ?? null,
          product_name: it.product_name ?? 'Producto',
          size: it.size ?? null, color: it.color ?? null, category: null,
          quantity: it.quantity ?? 1, unit_price: it.unit_price ?? 0,
        })));
      }
      addedPoints += o.points; addedPairs += o.pairs; linked += 1;
    }
    await supabase.from('unmatched_orders').update({ matched_at: new Date().toISOString() }).eq('id', o.id);
  }

  if (addedPoints > 0 || addedPairs > 0) {
    const newPoints = card.total_points + addedPoints;
    const newPairs = card.pairs_count + addedPairs;
    await supabase.from('loyalty_cards').update({
      total_points: newPoints, pairs_count: newPairs,
      tier: await computeTier(supabase, newPoints), updated_at: new Date().toISOString(),
    }).eq('id', card.id);
    return json({ ok: true, linked, points: addedPoints, pairs: addedPairs, new_total_points: newPoints });
  }

  return json({ ok: true, linked: 0, points: 0 });
});
