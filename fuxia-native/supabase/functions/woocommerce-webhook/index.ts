import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { normalizePhone } from '../_shared/phone.ts';

// ============================================================================
// WooCommerce → Fuxia loyalty sync (Fase 0 hardened)
// ----------------------------------------------------------------------------
// Cambios clave vs. versión anterior:
//   • Firma HMAC OBLIGATORIA (antes: si no venía header, se procesaba igual).
//   • Acredita al confirmar pago ('processing') o al completar; idempotente.
//   • Reversa de puntos en 'refunded' / 'cancelled' / 'failed'.
//   • Umbrales de nivel leídos de tier_config (no hardcodeados).
//   • Regla oficial: 100 puntos por par.
//   • Órdenes sin clienta → unmatched_orders (retro-crédito via link-orders).
//   • Sin funciones duplicadas (la versión previa no compilaba).
// ============================================================================

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WC_WEBHOOK_SECRET = Deno.env.get('WC_WEBHOOK_SECRET')!;
const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')!;
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')!;
const TWILIO_WHATSAPP_FROM = Deno.env.get('TWILIO_WHATSAPP_FROM')!;
const TWILIO_WELCOME_CONTENT_SID = Deno.env.get('TWILIO_WELCOME_CONTENT_SID') ?? '';
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';

const APP_STORE_URL = 'https://apps.apple.com/app/id6764388920';
const POINTS_PER_PAIR = 100;

// Estados que acreditan puntos y estados que los revierten.
const CREDIT_STATUSES = new Set(['processing', 'completed']);
const REVERSE_STATUSES = new Set(['refunded', 'cancelled', 'failed']);

type Tier = 'bronze' | 'silver' | 'gold';
const TIER_LABEL: Record<Tier, string> = { bronze: 'Bronce', silver: 'Plata', gold: 'Oro' };

interface WCLineItem {
  id: number; name: string; sku: string; quantity: number;
  price: number; total: string; meta_data?: { key: string; value: string }[];
}
interface WCOrder {
  id: number; status: string; total: string; currency: string;
  billing: { email?: string; phone?: string; country?: string };
  customer_id?: number; line_items: WCLineItem[];
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
}

async function verifySignature(body: string, signatureB64: string): Promise<boolean> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(WC_WEBHOOK_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  const computed = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return computed === signatureB64;
}

/** Umbrales desde tier_config (fuente de verdad). Fallback a 300/900 si falla. */
async function computeTier(
  supabase: ReturnType<typeof createClient>,
  points: number,
): Promise<Tier> {
  const { data } = await supabase.from('tier_config').select('tier, min_points');
  const rows = (data ?? []) as { tier: string; min_points: number }[];
  const thresholds = rows.length
    ? rows
    : [{ tier: 'bronze', min_points: 0 }, { tier: 'silver', min_points: 300 }, { tier: 'gold', min_points: 900 }];
  let result: Tier = 'bronze';
  for (const r of thresholds.sort((a, b) => a.min_points - b.min_points)) {
    if (points >= r.min_points) result = r.tier as Tier;
  }
  return result;
}

function normalizeForWhatsApp(phone: string): string {
  if (phone.startsWith('+52') && !phone.startsWith('+521')) return `+521${phone.slice(3)}`;
  return phone;
}

function extractMeta(item: WCLineItem, keys: string[]): string | null {
  if (!item.meta_data) return null;
  for (const m of item.meta_data) { if (keys.includes(m.key)) return m.value; }
  return null;
}

async function sendPushToCustomer(
  supabase: ReturnType<typeof createClient>,
  customerId: string, customerName: string | null,
  title: string, body: string, data: Record<string, unknown> = {},
): Promise<void> {
  const { data: tokens } = await supabase.from('push_tokens').select('expo_token').eq('customer_id', customerId);
  if (!tokens || tokens.length === 0) return;
  const messages = tokens.map((t: { expo_token: string }) => ({
    to: t.expo_token, sound: 'default', title,
    body: customerName ? body.replace('{name}', customerName) : body.replace('{name}', 'Hola'),
    data,
  }));
  try {
    const res = await fetch('https://exp.host/--/api/v2/push/send', {
      method: 'POST',
      headers: { 'Accept': 'application/json', 'Accept-encoding': 'gzip, deflate', 'Content-Type': 'application/json' },
      body: JSON.stringify(messages),
    });
    console.log(`[wc-webhook] push sent status=${res.status}`);
  } catch (err) {
    console.error(`[wc-webhook] push send threw: ${(err as Error).message}`);
  }
}

async function sendWhatsAppWelcome(phone: string, name: string, points: number): Promise<void> {
  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_WHATSAPP_FROM) return;
  const to = `whatsapp:${normalizeForWhatsApp(phone)}`;
  const from = TWILIO_WHATSAPP_FROM.startsWith('whatsapp:') ? TWILIO_WHATSAPP_FROM : `whatsapp:${TWILIO_WHATSAPP_FROM}`;
  const firstName = name?.split(' ')[0] ?? 'Hola';
  const auth = btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`);
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`;

  const body: Record<string, string> = TWILIO_WELCOME_CONTENT_SID
    ? { From: from, To: to, ContentSid: TWILIO_WELCOME_CONTENT_SID, ContentVariables: JSON.stringify({ '1': firstName, '2': String(points) }) }
    : { From: from, To: to, Body: `¡Hola ${firstName}! 👋\n\nBienvenida al *Club Fuxia*. Tu primera compra te dio *${points} puntos* 🎉\n\nDescarga la app para ver tu tarjeta de lealtad:\n📱 ${APP_STORE_URL}\n\n— Equipo Fuxia Ballerinas` };

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Authorization': `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(body).toString(),
    });
    console.log(`[wc-webhook] whatsapp welcome status=${res.status}`);
  } catch (err) {
    console.error(`[wc-webhook] whatsapp welcome threw: ${(err as Error).message}`);
  }
}

async function sendEmailWelcome(email: string, name: string, points: number, tier: Tier): Promise<void> {
  if (!RESEND_API_KEY || !email) return;
  const firstName = name?.split(' ')[0] ?? 'Bienvenida';
  const tierLabel = TIER_LABEL[tier] ?? 'Bronce';
  const html = `<!DOCTYPE html><html lang="es"><body style="margin:0;padding:0;background:#f4f0eb;font-family:-apple-system,Segoe UI,sans-serif;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f0eb;padding:40px 0;"><tr><td align="center">
    <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">
    <tr><td style="background:#0D0D0D;border-radius:16px 16px 0 0;padding:40px;text-align:center;">
      <p style="margin:0 0 4px;font-size:11px;color:#B8860B;letter-spacing:3px;text-transform:uppercase;font-weight:700;">CLUB FUXIA</p>
      <h1 style="margin:0;font-size:32px;font-weight:300;color:#fff;">Fuxia Ballerinas</h1></td></tr>
    <tr><td style="background:#1A1A1A;padding:40px;text-align:center;">
      <h2 style="margin:0 0 16px;font-size:28px;font-weight:400;color:#fff;">${firstName}, ya eres parte del Club Fuxia ✨</h2>
      <p style="margin:0;font-size:15px;color:rgba(255,255,255,0.5);">Tienes <strong style="color:#fff;">${points} puntos</strong> · Nivel <strong style="color:#fff;">${tierLabel}</strong></p></td></tr>
    <tr><td style="background:#fff;padding:40px;text-align:center;">
      <a href="${APP_STORE_URL}" style="display:inline-block;background:#B8860B;color:#fff;text-decoration:none;font-size:14px;font-weight:700;padding:16px 40px;border-radius:30px;">📱 Descargar en App Store</a></td></tr>
    <tr><td style="background:#0D0D0D;border-radius:0 0 16px 16px;padding:24px 40px;text-align:center;">
      <p style="margin:0;font-size:12px;color:rgba(255,255,255,0.3);">© 2026 Fuxia Ballerinas · México</p></td></tr>
    </table></td></tr></table></body></html>`;
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: 'Fuxia Ballerinas <hola@fuxiaballerinas.com>', to: [email], subject: `¡Bienvenida al Club Fuxia, ${firstName}! 🎉`, html }),
    });
    console.log(`[wc-webhook] email welcome status=${res.status}`);
  } catch (err) {
    console.error(`[wc-webhook] email welcome threw: ${(err as Error).message}`);
  }
}

async function insertPurchaseItems(
  supabase: ReturnType<typeof createClient>, txId: string, items: WCLineItem[],
): Promise<void> {
  if (!items.length) return;
  await supabase.from('purchase_items').insert(items.map((it) => ({
    transaction_id: txId,
    sku: it.sku || `WC-${it.id}`,
    product_name: it.name,
    size: extractMeta(it, ['pa_size', 'Size', 'Talla']),
    color: extractMeta(it, ['pa_color', 'Color']),
    category: null,
    quantity: it.quantity,
    unit_price: it.quantity > 0 ? parseFloat(it.total) / it.quantity : parseFloat(it.total),
  })));
}

serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const rawBody = await req.text();
  const signature = req.headers.get('x-wc-webhook-signature') ?? '';
  const topic = req.headers.get('x-wc-webhook-topic') ?? '';

  // WooCommerce manda un ping de validación SIN firma al crear el webhook.
  // Lo aceptamos solo si el body no es una orden (no tiene puntos que otorgar).
  let order: WCOrder | null = null;
  try {
    const parsed = JSON.parse(rawBody);
    if (parsed?.status && parsed?.id) order = parsed as WCOrder;
  } catch {
    return json({ ok: true, skipped: 'non-json-ping', topic });
  }
  if (!order) return json({ ok: true, skipped: 'ping', topic });

  // Firma OBLIGATORIA para cualquier request que traiga una orden.
  if (!signature || !(await verifySignature(rawBody, signature))) {
    console.warn(`[wc-webhook] rejected: missing/invalid signature order=${order.id}`);
    return json({ error: 'Invalid signature' }, 401);
  }

  console.log(`[wc-webhook] topic=${topic} order=${order.id} status=${order.status}`);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const status = order.status.toLowerCase();

  // ── REVERSA: reembolso / cancelación ───────────────────────────────────
  if (REVERSE_STATUSES.has(status)) {
    const { data: tx } = await supabase
      .from('transactions')
      .select('id, loyalty_card_id, points_earned, pairs_in_order, reversed_at')
      .eq('wc_order_id', order.id).maybeSingle();
    if (!tx || tx.reversed_at) return json({ ok: true, skipped: 'nothing_to_reverse' });

    const { data: card } = await supabase
      .from('loyalty_cards').select('id, total_points, pairs_count')
      .eq('id', tx.loyalty_card_id).single();
    if (card) {
      const newPoints = Math.max(0, card.total_points - tx.points_earned);
      const newPairs = Math.max(0, card.pairs_count - tx.pairs_in_order);
      await supabase.from('loyalty_cards').update({
        total_points: newPoints, pairs_count: newPairs,
        tier: await computeTier(supabase, newPoints), updated_at: new Date().toISOString(),
      }).eq('id', card.id);
    }
    await supabase.from('transactions').update({ reversed_at: new Date().toISOString(), wc_status: status }).eq('id', tx.id);
    console.log(`[wc-webhook] reversed order=${order.id} pts=-${tx.points_earned}`);
    return json({ ok: true, reversed: true, order_id: order.id });
  }

  // Solo acreditamos en processing/completed.
  if (!CREDIT_STATUSES.has(status)) {
    return json({ ok: true, skipped: `status=${status}` });
  }

  // Idempotencia: si ya hay transacción para esta orden, no duplicar.
  const { data: existing } = await supabase.from('transactions').select('id').eq('wc_order_id', order.id).maybeSingle();
  if (existing) {
    await supabase.from('transactions').update({ wc_status: status }).eq('id', existing.id);
    return json({ ok: true, skipped: 'already_processed' });
  }

  const phone = normalizePhone(order.billing.phone, order.billing.country);
  const email = order.billing.email?.toLowerCase() ?? null;
  const amount = parseFloat(order.total);
  const pairs = order.line_items.reduce((sum, it) => sum + it.quantity, 0);
  const points = pairs * POINTS_PER_PAIR;

  // Buscar clienta por teléfono, luego email.
  let customer: { id: string; name: string | null } | null = null;
  if (phone) {
    const { data } = await supabase.from('customers').select('id, name').eq('phone', phone).maybeSingle();
    customer = data;
  }
  if (!customer && email) {
    const { data } = await supabase.from('customers').select('id, name').ilike('email', email).maybeSingle();
    customer = data;
  }

  // ── ÓRDEN HUÉRFANA: guardar para retro-crédito ─────────────────────────
  if (!customer) {
    console.log(`[wc-webhook] no customer match order=${order.id} → unmatched_orders`);
    await supabase.from('unmatched_orders').upsert({
      wc_order_id: order.id, phone, email, total: amount, currency: order.currency ?? 'MXN',
      pairs, points, wc_status: status,
      items: order.line_items.map((it) => ({
        sku: it.sku || `WC-${it.id}`, product_name: it.name, quantity: it.quantity,
        size: extractMeta(it, ['pa_size', 'Size', 'Talla']), color: extractMeta(it, ['pa_color', 'Color']),
        unit_price: it.quantity > 0 ? parseFloat(it.total) / it.quantity : parseFloat(it.total),
      })),
    }, { onConflict: 'wc_order_id' });
    return json({ ok: true, unmatched: true, order_id: order.id });
  }

  if (order.customer_id) {
    await supabase.from('customers').update({ wc_customer_id: order.customer_id }).eq('id', customer.id).is('wc_customer_id', null);
  }

  const { data: card } = await supabase
    .from('loyalty_cards').select('id, total_points, pairs_count, tier').eq('customer_id', customer.id).single();
  if (!card) return json({ error: 'Loyalty card missing for customer' }, 500);

  const isFirstPurchase = card.total_points === 0 && card.pairs_count === 0;

  const { data: tx, error: txErr } = await supabase.from('transactions').insert({
    loyalty_card_id: card.id, wc_order_id: order.id, amount, currency: order.currency ?? 'MXN',
    points_earned: points, pairs_in_order: pairs, channel: 'web', wc_status: status,
  }).select('id').single();
  if (txErr || !tx) {
    console.error(`[wc-webhook] insert tx failed: ${txErr?.message}`);
    return json({ error: 'Insert transaction failed', debug: txErr?.message }, 500);
  }

  await insertPurchaseItems(supabase, tx.id, order.line_items);

  const newPoints = card.total_points + points;
  const newPairs = card.pairs_count + pairs;
  const newTier = await computeTier(supabase, newPoints);

  await supabase.from('loyalty_cards').update({
    total_points: newPoints, pairs_count: newPairs, tier: newTier, updated_at: new Date().toISOString(),
  }).eq('id', card.id);

  if (isFirstPurchase) {
    await Promise.all([
      phone ? sendWhatsAppWelcome(phone, customer.name ?? '', newPoints) : Promise.resolve(),
      email ? sendEmailWelcome(email, customer.name ?? '', newPoints, newTier) : Promise.resolve(),
    ]);
  } else if (newTier !== card.tier) {
    const { data: tierCfg } = await supabase.from('tier_config').select('reward_description, reward_sku').eq('tier', newTier).maybeSingle();
    await supabase.from('rewards').insert({
      loyalty_card_id: card.id, type: 'tier_upgrade', threshold_points: newPoints,
      product_sku: tierCfg?.reward_sku ?? null,
      description: tierCfg?.reward_description ?? `Subiste a nivel ${TIER_LABEL[newTier]}`,
    });
    await sendPushToCustomer(supabase, customer.id, customer.name,
      `¡Subiste a nivel ${TIER_LABEL[newTier]}! ✨`,
      `{name}, tu recompensa de ${TIER_LABEL[newTier]} te espera. ${tierCfg?.reward_description ?? ''}`.trim(),
      { type: 'tier_upgrade', tier: newTier });
  } else if (points > 0) {
    await sendPushToCustomer(supabase, customer.id, customer.name,
      `¡Ganaste ${points} puntos! 🎉`, `{name}, ya tienes ${newPoints} puntos acumulados.`,
      { type: 'points_earned', points_earned: points, total_points: newPoints });
  }

  return json({ ok: true, order_id: order.id, points_earned: points, pairs_added: pairs, new_total_points: newPoints, tier: newTier, is_first_purchase: isFirstPurchase });
});
