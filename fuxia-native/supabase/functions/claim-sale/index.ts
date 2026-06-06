import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

type Tier = 'bronze' | 'silver' | 'gold';
type SaleItem = { product_name: string; size: string; color?: string; quantity: number; unit_price: number; inventory_id?: string };

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

function computeTier(points: number): Tier {
  if (points >= 900) return 'gold';
  if (points >= 300) return 'silver';
  return 'bronze';
}

async function creditPoints(
  supabase: ReturnType<typeof createClient>,
  customerId: string,
  items: SaleItem[],
  total: number,
  saleId: string,
  customerPhone: string,
) {
  const { data: card } = await supabase
    .from('loyalty_cards')
    .select('id, total_points, pairs_count, tier')
    .eq('customer_id', customerId)
    .single();

  if (!card) return { error: 'Tarjeta de lealtad no encontrada' };

  const pairs = items.reduce((sum, it) => sum + (it.quantity ?? 1), 0);
  const pointsEarned = pairs * 100;

  const { data: tx, error: txErr } = await supabase
    .from('transactions')
    .insert({
      loyalty_card_id: card.id,
      wc_order_id: null,
      amount: total,
      currency: 'MXN',
      points_earned: pointsEarned,
      pairs_in_order: pairs,
      channel: 'store',
    })
    .select('id')
    .single();

  if (txErr || !tx) return { error: 'Error registrando transacción' };

  if (items.length > 0) {
    await supabase.from('purchase_items').insert(
      items.map((it) => ({
        transaction_id: tx.id,
        sku: null,
        product_name: it.product_name,
        size: it.size ?? null,
        color: it.color ?? null,
        category: null,
        quantity: it.quantity ?? 1,
        unit_price: it.unit_price ?? 0,
      })),
    );
  }

  const newPoints = card.total_points + pointsEarned;
  const newPairs = card.pairs_count + pairs;
  const newTier = computeTier(newPoints);

  await supabase.from('loyalty_cards').update({
    total_points: newPoints,
    pairs_count: newPairs,
    tier: newTier,
    updated_at: new Date().toISOString(),
  }).eq('id', card.id);

  await supabase.from('offline_sales').update({
    claimed_at: new Date().toISOString(),
    customer_id: customerId,
    customer_phone: customerPhone,
    points_earned: pointsEarned,
  }).eq('id', saleId);

  // ── Referral bonus: if this is the customer's first transaction,
  //    give the referrer double points (same amount again) ──────────────────
  const { count: txCount } = await supabase
    .from('transactions')
    .select('id', { count: 'exact', head: true })
    .eq('loyalty_card_id', card.id);

  if ((txCount ?? 0) === 1) {
    const { data: cust } = await supabase
      .from('customers')
      .select('referred_by')
      .eq('id', customerId)
      .single();

    if (cust?.referred_by) {
      const { data: referrerCard } = await supabase
        .from('loyalty_cards')
        .select('id, total_points, pairs_count, tier')
        .eq('customer_id', cust.referred_by)
        .single();

      if (referrerCard) {
        const bonusPoints = pointsEarned;
        const referrerNewPoints = referrerCard.total_points + bonusPoints;
        await supabase.from('transactions').insert({
          loyalty_card_id: referrerCard.id,
          wc_order_id: null,
          amount: 0,
          currency: 'MXN',
          points_earned: bonusPoints,
          pairs_in_order: 0,
          channel: 'store',
          notes: `referral_bonus|phone:${customerPhone}|before:${referrerCard.total_points}|after:${referrerNewPoints}|pts:${bonusPoints}`,
        });
        await supabase.from('loyalty_cards').update({
          total_points: referrerNewPoints,
          tier: computeTier(referrerNewPoints),
          updated_at: new Date().toISOString(),
        }).eq('id', referrerCard.id);
      }
    }
  }

  return { ok: true, points_earned: pointsEarned, new_total_points: newPoints, tier: newTier };
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

  let body: Record<string, any>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const action = body.action ?? 'claim_code';

  // ── Acción: escaneo de QR por vendedora → puntos inmediatos ──────────────
  if (action === 'scan_qr') {
    const { qr_code, items, total, channel_id, staff_id } = body;

    if (!qr_code || !items || !total) {
      return json({ error: 'qr_code, items y total son requeridos' }, 400);
    }

    // Buscar loyalty_card por qr_code
    const { data: card } = await supabase
      .from('loyalty_cards')
      .select('id, customer_id, total_points, pairs_count, tier')
      .eq('qr_code', qr_code)
      .maybeSingle();

    if (!card) return json({ error: 'QR no válido o cliente no encontrado' }, 404);

    // Obtener datos del cliente
    const { data: customer } = await supabase
      .from('customers')
      .select('id, name, phone')
      .eq('id', card.customer_id)
      .single();

    if (!customer) return json({ error: 'Cliente no encontrado' }, 404);

    // Crear offline_sale ya reclamada
    const { data: sale, error: saleErr } = await supabase
      .from('offline_sales')
      .insert({
        code: `QR-${Date.now().toString(36).toUpperCase()}`,
        channel_id: channel_id ?? null,
        staff_id: staff_id ?? null,
        customer_phone: customer.phone,
        customer_id: customer.id,
        items,
        total,
        claimed_at: new Date().toISOString(),
      })
      .select('id')
      .single();

    if (saleErr || !sale) {
      console.error('[claim-sale] scan_qr insert sale failed:', saleErr?.message);
      return json({ error: 'Error registrando venta' }, 500);
    }

    const result = await creditPoints(supabase, customer.id, items, total, sale.id, customer.phone);
    if ('error' in result) return json(result, 500);

    console.log(`[claim-sale] scan_qr success customer=${customer.id} points=${result.points_earned}`);
    return json({ ...result, customer_name: customer.name?.split(' ')[0] ?? 'Clienta' });
  }

  // ── Acción: reclamo de código por la clienta ──────────────────────────────
  const { code, phone } = body;

  if (!code || !phone) {
    return json({ error: 'code y phone son requeridos' }, 400);
  }

  const { data: sale } = await supabase
    .from('offline_sales')
    .select('id, channel_id, staff_id, customer_phone, customer_id, items, total, claimed_at')
    .eq('code', code.toUpperCase().trim())
    .maybeSingle();

  if (!sale) return json({ error: 'Código no válido' }, 404);
  if (sale.claimed_at) return json({ error: 'Ya fue reclamado' }, 409);

  const { data: customer } = await supabase
    .from('customers')
    .select('id, name, phone')
    .eq('phone', phone)
    .maybeSingle();

  if (!customer) return json({ error: 'Número no registrado en la app' }, 404);

  const result = await creditPoints(supabase, customer.id, sale.items, sale.total, sale.id, phone);
  if ('error' in result) return json(result, 500);

  console.log(`[claim-sale] claim_code success code=${code} customer=${customer.id} points=${result.points_earned}`);
  return json(result);
});
