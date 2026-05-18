import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

type Tier = 'bronze' | 'silver' | 'gold';

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function computeTier(points: number): Tier {
  if (points >= 900) return 'gold';
  if (points >= 300) return 'silver';
  return 'bronze';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  let body: { code?: string; phone?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const { code, phone } = body;

  if (!code || !phone) {
    return json({ error: 'code y phone son requeridos' }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // 1. Find the offline_sale by code
  const { data: sale, error: saleErr } = await supabase
    .from('offline_sales')
    .select('id, code, channel_id, staff_id, customer_phone, customer_id, items, total, points_earned, claimed_at')
    .eq('code', code.toUpperCase().trim())
    .maybeSingle();

  if (saleErr) {
    console.error('[claim-sale] error fetching sale:', saleErr.message);
    return json({ error: 'Error buscando la venta' }, 500);
  }

  if (!sale) {
    return json({ error: 'Código no válido' }, 404);
  }

  // 2. If already claimed → return error
  if (sale.claimed_at) {
    return json({ error: 'Ya fue reclamado' }, 409);
  }

  // 3. Find customer by phone
  const { data: customer, error: customerErr } = await supabase
    .from('customers')
    .select('id, name, phone')
    .eq('phone', phone)
    .maybeSingle();

  if (customerErr) {
    console.error('[claim-sale] error fetching customer:', customerErr.message);
    return json({ error: 'Error buscando cliente' }, 500);
  }

  if (!customer) {
    return json({ error: 'Número no registrado en la app' }, 404);
  }

  // 4. Get loyalty card
  const { data: card, error: cardErr } = await supabase
    .from('loyalty_cards')
    .select('id, total_points, pairs_count, tier')
    .eq('customer_id', customer.id)
    .single();

  if (cardErr || !card) {
    console.error('[claim-sale] loyalty card not found for customer:', customer.id);
    return json({ error: 'Tarjeta de lealtad no encontrada' }, 500);
  }

  // 5. Calculate points: 100 points per pair (same as woocommerce-webhook)
  const items: Array<{ product_name: string; size: string; color?: string; quantity: number; unit_price: number }> =
    sale.items as any;
  const pairs = items.reduce((sum, it) => sum + (it.quantity ?? 1), 0);
  const pointsEarned = pairs * 100;

  // 6. Insert transaction (channel: 'store')
  const { data: tx, error: txErr } = await supabase
    .from('transactions')
    .insert({
      loyalty_card_id: card.id,
      wc_order_id: null,
      amount: sale.total,
      currency: 'MXN',
      points_earned: pointsEarned,
      pairs_in_order: pairs,
      channel: 'store',
    })
    .select('id')
    .single();

  if (txErr || !tx) {
    console.error('[claim-sale] insert transaction failed:', txErr?.message);
    return json({ error: 'Error registrando transacción' }, 500);
  }

  // 7. Insert purchase_items from sale.items
  if (items.length > 0) {
    const purchaseItems = items.map((it) => ({
      transaction_id: tx.id,
      sku: null,
      product_name: it.product_name,
      size: it.size ?? null,
      color: it.color ?? null,
      category: null,
      quantity: it.quantity ?? 1,
      unit_price: it.unit_price ?? 0,
    }));
    await supabase.from('purchase_items').insert(purchaseItems);
  }

  // 8. Update loyalty_cards total_points + pairs_count + tier
  const newPoints = card.total_points + pointsEarned;
  const newPairs = card.pairs_count + pairs;
  const newTier = computeTier(newPoints);

  const { error: updateCardErr } = await supabase
    .from('loyalty_cards')
    .update({
      total_points: newPoints,
      pairs_count: newPairs,
      tier: newTier,
      updated_at: new Date().toISOString(),
    })
    .eq('id', card.id);

  if (updateCardErr) {
    console.error('[claim-sale] update loyalty card failed:', updateCardErr.message);
    return json({ error: 'Error actualizando puntos' }, 500);
  }

  // 9. Mark offline_sale as claimed
  const { error: claimErr } = await supabase
    .from('offline_sales')
    .update({
      claimed_at: new Date().toISOString(),
      customer_id: customer.id,
      customer_phone: phone,
      points_earned: pointsEarned,
    })
    .eq('id', sale.id);

  if (claimErr) {
    console.error('[claim-sale] mark claimed failed:', claimErr.message);
    return json({ error: 'Error marcando como reclamado' }, 500);
  }

  console.log(`[claim-sale] success code=${code} customer=${customer.id} points=${pointsEarned} total=${newPoints} tier=${newTier}`);

  // 10. Return result
  return json({
    ok: true,
    points_earned: pointsEarned,
    new_total_points: newPoints,
    tier: newTier,
  });
});
