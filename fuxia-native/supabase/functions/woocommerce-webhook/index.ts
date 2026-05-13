import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WC_WEBHOOK_SECRET = Deno.env.get('WC_WEBHOOK_SECRET')!;
const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')!;
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')!;
const TWILIO_WHATSAPP_FROM = Deno.env.get('TWILIO_WHATSAPP_FROM')!;
const TWILIO_WELCOME_CONTENT_SID = Deno.env.get('TWILIO_WELCOME_CONTENT_SID') ?? '';
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';

const APP_STORE_URL = 'https://apps.apple.com/app/id6764388920';
const TIER_LABEL: Record<string, string> = { bronze: 'Bronce', silver: 'Plata', gold: 'Oro' };

type Tier = 'bronze' | 'silver' | 'gold';

interface WCLineItem {
  id: number; name: string; sku: string; quantity: number;
  price: number; total: string; meta_data?: { key: string; value: string }[];
}
interface WCOrder {
  id: number; status: string; total: string; currency: string;
  billing: { email?: string; phone?: string };
  customer_id?: number; line_items: WCLineItem[];
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
}

async function verifySignature(body: string, signatureB64: string): Promise<boolean> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(WC_WEBHOOK_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  const computed = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return computed === signatureB64;
}

function computeTier(points: number): Tier {
  if (points >= 900) return 'gold';
  if (points >= 300) return 'silver';
  return 'bronze';
}

function normalizePhone(raw?: string): string | null {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, '');
  if (!digits) return null;
  if (digits.length === 10) return `+52${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+52${digits.slice(1)}`;
  if (digits.length === 12 && digits.startsWith('52')) return `+${digits}`;
  if (digits.length === 13 && digits.startsWith('521')) return `+52${digits.slice(3)}`;
  return `+${digits}`;
}

function normalizeForWhatsApp(phone: string): string {
  // Mexico needs +521 for WhatsApp (not +52)
  if (phone.startsWith('+52') && !phone.startsWith('+521')) {
    return `+521${phone.slice(3)}`;
  }
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

  let body: Record<string, string>;

  if (TWILIO_WELCOME_CONTENT_SID) {
    // Template aprobado por Meta (recomendado)
    body = {
      From: from,
      To: to,
      ContentSid: TWILIO_WELCOME_CONTENT_SID,
      ContentVariables: JSON.stringify({ '1': firstName, '2': String(points) }),
    };
  } else {
    // Mensaje libre (funciona dentro de ventana de 24h post-OTP)
    body = {
      From: from,
      To: to,
      Body: `¡Hola ${firstName}! 👋\n\nBienvenida al *Club Fuxia*. Tu primera compra te dio *${points} puntos* 🎉\n\nDescarga la app para ver tu tarjeta de lealtad y tus recompensas:\n📱 ${APP_STORE_URL}\n\nEste número también es tu canal de soporte directo. Escríbenos cuando quieras.\n\n— Equipo Fuxia Ballerinas`,
    };
  }

  try {
    const params = new URLSearchParams(body);
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Authorization': `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });
    const text = await res.text();
    console.log(`[wc-webhook] whatsapp welcome status=${res.status} body=${text}`);
  } catch (err) {
    console.error(`[wc-webhook] whatsapp welcome threw: ${(err as Error).message}`);
  }
}

async function sendEmailWelcome(email: string, name: string, points: number, tier: Tier): Promise<void> {
  if (!RESEND_API_KEY || !email) return;

  const firstName = name?.split(' ')[0] ?? 'Bienvenida';
  const tierLabel = TIER_LABEL[tier] ?? 'Bronce';

  const html = `<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Bienvenida al Club Fuxia</title></head>
<body style="margin:0;padding:0;background:#f4f0eb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f0eb;padding:40px 0;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">

        <!-- Header -->
        <tr><td style="background:#0D0D0D;border-radius:16px 16px 0 0;padding:40px 40px 32px;text-align:center;">
          <p style="margin:0 0 4px;font-size:11px;color:#B8860B;letter-spacing:3px;text-transform:uppercase;font-weight:700;">CLUB FUXIA</p>
          <h1 style="margin:0;font-size:32px;font-weight:300;color:#fff;letter-spacing:1px;">Fuxia Ballerinas</h1>
        </td></tr>

        <!-- Hero -->
        <tr><td style="background:#1A1A1A;padding:40px 40px 32px;text-align:center;">
          <p style="margin:0 0 8px;font-size:13px;color:#B8860B;letter-spacing:2px;text-transform:uppercase;">BIENVENIDA</p>
          <h2 style="margin:0 0 16px;font-size:28px;font-weight:400;color:#fff;">${firstName}, ya eres parte<br>del Club Fuxia ✨</h2>
          <p style="margin:0;font-size:15px;color:rgba(255,255,255,0.5);line-height:1.6;">Tu primera compra ya está registrada.<br>Empieza a acumular y escala de nivel.</p>
        </td></tr>

        <!-- Points card -->
        <tr><td style="background:#1A1A1A;padding:0 40px 40px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:#0D0D0D;border:1px solid #333;border-radius:16px;overflow:hidden;">
            <tr>
              <td style="padding:28px;text-align:center;border-right:1px solid #333;">
                <p style="margin:0 0 4px;font-size:11px;color:#B8860B;letter-spacing:2px;text-transform:uppercase;">Puntos</p>
                <p style="margin:0;font-size:40px;font-weight:700;color:#fff;">${points}</p>
              </td>
              <td style="padding:28px;text-align:center;">
                <p style="margin:0 0 4px;font-size:11px;color:#B8860B;letter-spacing:2px;text-transform:uppercase;">Nivel</p>
                <p style="margin:0;font-size:40px;font-weight:700;color:#fff;">${tierLabel}</p>
              </td>
            </tr>
          </table>
        </td></tr>

        <!-- How it works -->
        <tr><td style="background:#fff;padding:40px;">
          <p style="margin:0 0 24px;font-size:13px;color:#B8860B;letter-spacing:2px;text-transform:uppercase;font-weight:700;">Cómo funciona</p>
          <table width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td style="width:40px;vertical-align:top;padding-top:2px;font-size:20px;">🥉</td>
              <td style="padding-bottom:20px;"><strong style="color:#1A1A1A;">Bronce</strong> — tu nivel de entrada con beneficios exclusivos</td>
            </tr>
            <tr>
              <td style="width:40px;vertical-align:top;padding-top:2px;font-size:20px;">🥈</td>
              <td style="padding-bottom:20px;"><strong style="color:#1A1A1A;">Plata</strong> — un par de ballerinas básicas de regalo</td>
            </tr>
            <tr>
              <td style="width:40px;vertical-align:top;padding-top:2px;font-size:20px;">🥇</td>
              <td style="padding-bottom:20px;"><strong style="color:#1A1A1A;">Oro</strong> — un par premium de regalo + beneficios VIP</td>
            </tr>
          </table>
        </td></tr>

        <!-- CTA -->
        <tr><td style="background:#fff;padding:0 40px 40px;text-align:center;">
          <p style="margin:0 0 24px;font-size:15px;color:#666;line-height:1.6;">Descarga la app para ver tu tarjeta de lealtad,<br>tu historial de compras y tus recompensas.</p>
          <a href="${APP_STORE_URL}" style="display:inline-block;background:#B8860B;color:#fff;text-decoration:none;font-size:14px;font-weight:700;letter-spacing:1px;padding:16px 40px;border-radius:30px;">📱 Descargar en App Store</a>
        </td></tr>

        <!-- Footer -->
        <tr><td style="background:#0D0D0D;border-radius:0 0 16px 16px;padding:32px 40px;text-align:center;">
          <p style="margin:0 0 8px;font-size:13px;color:rgba(255,255,255,0.4);">¿Dudas? Escríbenos a <a href="mailto:soporte@fuxiaballerinas.com" style="color:#B8860B;">soporte@fuxiaballerinas.com</a></p>
          <p style="margin:0;font-size:12px;color:rgba(255,255,255,0.2);">© 2026 Fuxia Ballerinas · México</p>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Fuxia Ballerinas <hola@fuxiaballerinas.com>',
        to: [email],
        subject: `¡Bienvenida al Club Fuxia, ${firstName}! 🎉`,
        html,
      }),
    });
    console.log(`[wc-webhook] email welcome status=${res.status}`);
  } catch (err) {
    console.error(`[wc-webhook] email welcome threw: ${(err as Error).message}`);
  }
}

serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const rawBody = await req.text();
  const signature = req.headers.get('x-wc-webhook-signature') ?? '';
  const topic = req.headers.get('x-wc-webhook-topic') ?? '';

  if (signature && !(await verifySignature(rawBody, signature))) {
    console.warn('[wc-webhook] invalid signature');
    return json({ error: 'Invalid signature' }, 401);
  }

  let order: WCOrder;
  try {
    order = JSON.parse(rawBody);
  } catch {
    console.log(`[wc-webhook] ping/non-JSON topic=${topic}`);
    return json({ ok: true, skipped: 'ping' });
  }

  if (!order?.status) {
    console.log(`[wc-webhook] no order status, likely ping topic=${topic}`);
    return json({ ok: true, skipped: 'ping' });
  }

  console.log(`[wc-webhook] topic=${topic} order=${order.id} status=${order.status}`);

  if (order.status !== 'completed') {
    return json({ ok: true, skipped: `status=${order.status}` });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Idempotency: skip if already processed
  const { data: existing } = await supabase.from('transactions').select('id').eq('wc_order_id', order.id).maybeSingle();
  if (existing) return json({ ok: true, skipped: 'already_processed' });

  const phone = normalizePhone(order.billing.phone);
  const email = order.billing.email?.toLowerCase() ?? null;

  let customer: { id: string; name: string | null } | null = null;

  if (phone) {
    const { data } = await supabase.from('customers').select('id, name').eq('phone', phone).maybeSingle();
    customer = data;
  }
  if (!customer && email) {
    const { data } = await supabase.from('customers').select('id, name').eq('email', email).maybeSingle();
    customer = data;
  }

  if (!customer) {
    console.log(`[wc-webhook] no customer match for order=${order.id} phone=${phone} email=${email}`);
    return json({ ok: true, skipped: 'customer_not_found' });
  }

  if (order.customer_id) {
    await supabase.from('customers').update({ wc_customer_id: order.customer_id }).eq('id', customer.id).is('wc_customer_id', null);
  }

  const { data: card } = await supabase.from('loyalty_cards').select('id, total_points, pairs_count, tier').eq('customer_id', customer.id).single();
  if (!card) return json({ error: 'Loyalty card missing for customer' }, 500);

  // Detectar si es primera compra ANTES de insertar
  const isFirstPurchase = card.total_points === 0 && card.pairs_count === 0;

  const amount = parseFloat(order.total);
  const pairs = order.line_items.reduce((sum, it) => sum + it.quantity, 0);
  const points = pairs * 100;

  const { data: tx, error: txErr } = await supabase.from('transactions').insert({
    loyalty_card_id: card.id,
    wc_order_id: order.id,
    amount,
    currency: order.currency ?? 'MXN',
    points_earned: points,
    pairs_in_order: pairs,
    channel: 'web',
  }).select('id').single();

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

  await supabase.from('loyalty_cards').update({
    total_points: newPoints, pairs_count: newPairs, tier: newTier, updated_at: new Date().toISOString(),
  }).eq('id', card.id);

  if (isFirstPurchase) {
    // Bienvenida: WhatsApp + Email en paralelo
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
      { type: 'tier_upgrade', tier: newTier },
    );
  } else if (points > 0) {
    await sendPushToCustomer(supabase, customer.id, customer.name,
      `¡Ganaste ${points} puntos! 🎉`,
      `{name}, ya tienes ${newPoints} puntos acumulados.`,
      { type: 'points_earned', points_earned: points, total_points: newPoints },
    );
  }

  return json({ ok: true, order_id: order.id, points_earned: points, pairs_added: pairs, new_total_points: newPoints, tier: newTier, is_first_purchase: isFirstPurchase });
});
