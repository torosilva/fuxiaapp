import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WC_WEBHOOK_SECRET = Deno.env.get('WC_WEBHOOK_SECRET')!;

type Tier = 'bronze' | 'silver' | 'gold';

interface WCLineItem {
  id: number;
  name: string;
  sku: string;
  quantity: number;
  price: number;
  total: string;
  meta_data?: { key: string; value: string }[];
  // category info isn't in line items by default; we use `categories` via a lookup if needed
  // but for MVP we treat every physical item as a pair.
}

interface WCOrder {
  id: number;
  status: string;
  total: string;
  currency: string;
  billing: {
    email?: string;
    phone?: string;
  };
  customer_id?: number;
  line_items: WCLineItem[];
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function verifySignature(body: string, signatureB64: string): Promise<boolean> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(WC_WEBHOOK_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  const computed = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return computed === signatureB64;
}

function computeTier(points: number): Tier {
  if (points >= 900) return 'gold';
  if (points >= 300) return 'silver';
  return 'bronze';
}

const TIER_LABEL: Record<Tier, string> = { bronze: 'Bronze', silver: 'Silver', gold: 'Gold' };

async function sendPushToCustomer(
  supabase: ReturnType<typeof createClient>,
  customerId: string,
  customerName: string | null,
  title: string,
  body: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  const { data: tokens } = await supabase
    .from('push_tokens')
    .select('expo_token')
    .eq('customer_id', customerId);

  if (!tokens || tokens.length === 0) return;

  const messages = tokens.map((t: { expo_token: string }) => ({
    to: t.expo_token,
    sound: 'default',
    title,
    body: customerName ? body.replace('{name}', customerName) : body.replace('{name}', 'Hola'),
    data,
  }));

  try {
    const res = await fetch('https://exp.host/--/api/v2/push/send', {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Accept-encoding': 'gzip, deflate',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(messages),
    });
    const text = await res.text();
    console.log(`[wc-webhook] push sent status=${res.status} body=${text}`);
  } catch (err) {
    console.error(`[wc-webhook] push send threw: ${(err as Error).message}`);
  }
}

function normalizePhone(raw?: string): string | null {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, '');
  if (!digits) return null;
  // Assume MX if 10 digits, prefix +52 to match how the app stores phones.
  if (digits.length === 10) return `+52${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+52${digits.slice(1)}`;
  if (digits.length === 12 && digits.startsWith('52')) return `+${digits}`;
  if (digits.length === 13 && digits.startsWith('521')) return `+52${digits.slice(3)}`;
  return `+${digits}`;
}

function extractMeta(item: WCLineItem, keys: string[]): string | null {
  if (!item.meta_data) return null;
  for (const m of item.meta_data) {
    if (keys.includes(m.key)) return m.value;
  }
  return null;
}

serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const rawBody = await req.text();
  const signature = req.headers.get('x-wc-webhook-signature') ?? '';
  const topic = req.headers.get('x-wc-webhook-topic') ?? '';

  if (!(await verifySignature(rawBody, signature))) {
    console.warn('[wc-webhook] invalid signature');
    return json({ error: 'Invalid signature' }, 401);
  }

  const order: WCOrder = JSON.parse(rawBody);
  console.log(`[wc-webhook] topic=${topic} order=${order.id} status=${order.status}`);

  // Only act when the order reaches "completed"
  if (order.status !== 'completed') {
    return json({ ok: true, skipped: `status=${order.status}` });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Idempotency: skip if this order was already processed
  const { data: existing } = await supabase
    .from('transactions')
    .select('id')
    .eq('wc_order_id', order.id)
    .maybeSingle();
  if (existing) {
    return json({ ok: true, skipped: 'already_processed' });
  }

  // Match customer by phone first, then email
  const phone = normalizePhone(order.billing.phone);
  const email = order.billing.email?.toLowerCase() ?? null;

  let customer: { id: string; name: string | null } | null = null;

  if (phone) {
    const { data } = await supabase
      .from('customers')
      .select('id, name')
      .eq('phone', phone)
      .maybeSingle();
    customer = data;
  }

  if (!customer && email) {
    const { data } = await supabase
      .from('customers')
      .select('id, name')
      .eq('email', email)
      .maybeSingle();
    customer = data;
  }

  if (!customer) {
    console.log(`[wc-webhook] no customer match for order=${order.id} phone=${phone} email=${email}`);
    return json({ ok: true, skipped: 'customer_not_found' });
  }

  // Link wc_customer_id if missing
  if (order.customer_id) {
    await supabase
      .from('customers')
      .update({ wc_customer_id: order.customer_id })
      .eq('id', customer.id)
      .is('wc_customer_id', null);
  }

  const { data: card } = await supabase
    .from('loyalty_cards')
    .select('id, total_points, pairs_count, tier')
    .eq('customer_id', customer.id)
    .single();

  if (!card) {
    return json({ error: 'Loyalty card missing for customer' }, 500);
  }

  const amount = parseFloat(order.total);
  const pairs = order.line_items.reduce((sum, it) => sum + it.quantity, 0);
  const points = pairs * 100; // 100 pts per pair — Programa Hilo

  const { data: tx, error: txErr } = await supabase
    .from('transactions')
    .insert({
      loyalty_card_id: card.id,
      wc_order_id: order.id,
      amount,
      currency: order.currency ?? 'MXN',
      points_earned: points,
      pairs_in_order: pairs,
      channel: 'web',
    })
    .select('id')
    .single();

  if (txErr || !tx) {
    console.error(`[wc-webhook] insert transaction failed: ${txErr?.message}`);
    return json({ error: 'Insert transaction failed', debug: txErr?.message }, 500);
  }

  if (order.line_items.length) {
    const items = order.line_items.map((it) => ({
      transaction_id: tx.id,
      sku: it.sku || `WC-${it.id}`,
      product_name: it.name,
      size: extractMeta(it, ['pa_size', 'Size', 'Talla']),
      color: extractMeta(it, ['pa_color', 'Color']),
      category: null,
      quantity: it.quantity,
      unit_price: it.quantity > 0 ? parseFloat(it.total) / it.quantity : parseFloat(it.total),
    }));
    await supabase.from('purchase_items').insert(items);
  }

  const newPoints = card.total_points + points;
  const newPairs = card.pairs_count + pairs;
  const newTier = computeTier(newPoints);

  await supabase
    .from('loyalty_cards')
    .update({
      total_points: newPoints,
      pairs_count: newPairs,
      tier: newTier,
      updated_at: new Date().toISOString(),
    })
    .eq('id', card.id);

  if (newTier !== card.tier) {
    const { data: tierCfg } = await supabase
      .from('tier_config')
      .select('reward_description, reward_sku')
      .eq('tier', newTier)
      .maybeSingle();

    await supabase.from('rewards').insert({
      loyalty_card_id: card.id,
      type: 'tier_upgrade',
      threshold_points: newPoints,
      product_sku: tierCfg?.reward_sku ?? null,
      description: tierCfg?.reward_description ?? `Subiste a nivel ${TIER_LABEL[newTier]}`,
    });

    await sendPushToCustomer(
      supabase,
      customer.id,
      customer.name,
      `¡Subiste a nivel ${TIER_LABEL[newTier]}! ✨`,
      `{name}, tu recompensa de ${TIER_LABEL[newTier]} te espera. ${tierCfg?.reward_description ?? ''}`.trim(),
      { type: 'tier_upgrade', tier: newTier },
    );
  } else if (points > 0) {
    await sendPushToCustomer(
      supabase,
      customer.id,
      customer.name,
      `¡Ganaste ${points} puntos! 🎉`,
      `{name}, ya tienes ${newPoints} puntos acumulados.`,
      { type: 'points_earned', points_earned: points, total_points: newPoints },
    );
  }

  return json({
    ok: true,
    order_id: order.id,
    points_earned: points,
    pairs_added: pairs,
    new_total_points: newPoints,
    tier: newTier,
    tier_upgraded: newTier !== card.tier,
  });
});
