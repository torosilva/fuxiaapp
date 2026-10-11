import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')!;
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')!;
const TWILIO_WHATSAPP_FROM = Deno.env.get('TWILIO_WHATSAPP_FROM')!; // e.g. whatsapp:+14155238886 (sandbox)
const TWILIO_CONTENT_SID = Deno.env.get('TWILIO_CONTENT_SID')!; // approved WhatsApp template SID
// Optional SMS sender. When set, OTP is sent via SMS first; WhatsApp is only used as fallback.
// Format: a Twilio-purchased SMS-capable number, e.g. "+15551234567".
const TWILIO_SMS_FROM = Deno.env.get('TWILIO_SMS_FROM') ?? '';

// App Store / Play reviewer login (P0-6.3, 2026-10-11). OFF unless REVIEW_BYPASS_ENABLED='true' AND the three values are set:
// no hard-coded defaults. Turn it on only during a store review window, pointing at a plain customer account.
const REVIEW_BYPASS_ENABLED = Deno.env.get('REVIEW_BYPASS_ENABLED') === 'true';
const REVIEW_BYPASS_PHONE = Deno.env.get('REVIEW_BYPASS_PHONE') ?? '';
const REVIEW_BYPASS_CODE = Deno.env.get('REVIEW_BYPASS_CODE') ?? '';
const REVIEW_DEMO_PHONE = Deno.env.get('REVIEW_DEMO_PHONE') ?? '';
const REVIEW_ACTIVE = REVIEW_BYPASS_ENABLED && /^\+\d{7,15}$/.test(REVIEW_BYPASS_PHONE) && REVIEW_BYPASS_CODE.length >= 6 && /^\+\d{7,15}$/.test(REVIEW_DEMO_PHONE);
const isReviewPhone = (p: string | undefined) => REVIEW_ACTIVE && p === REVIEW_BYPASS_PHONE;

const tail = (p: string) => `…${p.slice(-4)}`;   // phones are never logged in full

function sameCode(a: string, b: string): boolean {   // constant-time comparison
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

function generateCode(): string {
  // CSPRNG en vez de Math.random (predecible). 6 dígitos.
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return (100000 + (buf[0] % 900000)).toString();
}

function normalizeForWhatsApp(phone: string): string {
  // Mexico mobile on WhatsApp requires the "1" after +52. Insert it if missing.
  if (phone.startsWith('+52') && !phone.startsWith('+521') && phone.length === 13) {
    return '+521' + phone.slice(3);
  }
  return phone;
}

async function twilioRequest(body: URLSearchParams): Promise<{ ok: boolean; status: number; text: string }> {
  const res = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `Basic ${btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`)}`,
      },
      body,
    },
  );
  const text = await res.text();
  return { ok: res.ok, status: res.status, text };
}

async function sendSMS(to: string, code: string): Promise<void> {
  const body = new URLSearchParams({
    From: TWILIO_SMS_FROM,
    To: to,
    Body: `Tu código Fuxia Ballerinas: ${code}\n\nNo lo compartas con nadie.`,
  });
  const { ok, status, text } = await twilioRequest(body);
  console.log(`[otp] SMS to=${tail(to)} status=${status}`);
  if (!ok) throw new Error(`Twilio SMS ${status}: ${text.slice(0, 200)}`);
}

async function sendWhatsApp(to: string, code: string): Promise<void> {
  const toWhatsApp = `whatsapp:${normalizeForWhatsApp(to)}`;
  const body = new URLSearchParams({
    From: TWILIO_WHATSAPP_FROM,
    To: toWhatsApp,
    ContentSid: TWILIO_CONTENT_SID,
    ContentVariables: JSON.stringify({ '1': code }),
  });
  const { ok, status, text } = await twilioRequest(body);
  console.log(`[otp] WhatsApp to=${tail(to)} status=${status}`);
  if (!ok) throw new Error(`Twilio WhatsApp ${status}: ${text.slice(0, 200)}`);
}

// Sends the OTP via SMS when TWILIO_SMS_FROM is configured. Falls back to WhatsApp on SMS failure
// or when no SMS sender is available, so existing users keep working.
async function sendOtp(to: string, code: string): Promise<{ channel: 'sms' | 'whatsapp' }> {
  if (TWILIO_SMS_FROM) {
    try {
      await sendSMS(to, code);
      return { channel: 'sms' };
    } catch (err) {
      console.warn(`[otp] SMS failed, falling back to WhatsApp: ${err instanceof Error ? err.message : err}`);
    }
  }
  await sendWhatsApp(to, code);
  return { channel: 'whatsapp' };
}

// One-time server-side session for the account {phone}@fuxia.app. Creates the account (random, never-stored password) if needed.
async function issueSession(admin: ReturnType<typeof createClient>, authPhone: string) {
  const email = `${authPhone.replace('+', '')}@fuxia.app`;
  // Create first (an existing account answers "already registered", which is fine), then ask for ONE link: Auth rate-limits
  // repeated link requests for the same email, so a second generateLink right after a failed one would be refused.
  const random = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const created = await admin.auth.admin.createUser({ email, password: random, email_confirm: true, user_metadata: { phone: authPhone } });
  if (created.error && !/already|exists|registered/i.test(created.error.message ?? '')) return { error: 'create' as const };
  const link = await admin.auth.admin.generateLink({ type: 'magiclink', email });
  if (link.error || !link.data?.properties?.hashed_token) return { error: 'link' as const };
  const user = link.data.user;
  if (user && !user.user_metadata?.phone) {
    await admin.auth.admin.updateUserById(user.id, { user_metadata: { ...(user.user_metadata ?? {}), phone: authPhone } });
  }
  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const v = await anon.auth.verifyOtp({ type: 'magiclink', token_hash: link.data.properties.hashed_token });
  if (v.error || !v.data?.session) return { error: 'verify' as const };
  return { session: v.data.session };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let body: { action: string; phone?: string; code?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  // ── CHECK PHONE ───────────────────────────────────────────────────────────
  if (body.action === 'check_phone') {
    const phone = body.phone?.trim();
    if (!phone) return json({ error: 'phone requerido' }, 400);

    // Store review login (only when enabled): report the demo user as existing.
    const lookupPhone = isReviewPhone(phone) ? REVIEW_DEMO_PHONE : phone;

    const { data } = await supabase
      .from('customers')
      .select('id')
      .eq('phone', lookupPhone)
      .maybeSingle();

    return json({ exists: !!data });
  }

  // ── SEND OTP ──────────────────────────────────────────────────────────────
  if (body.action === 'send') {
    const phone = body.phone?.trim();
    if (!phone || !/^\+\d{7,15}$/.test(phone)) {
      return json({ error: 'Número de teléfono inválido. Usa formato E.164: +521234567890' }, 400);
    }

    // Store review login (only when enabled): short-circuit without calling Twilio.
    if (isReviewPhone(phone)) {
      console.log('[whatsapp-otp] review login: send acknowledged');
      return json({ success: true, message: 'Código enviado por WhatsApp' });
    }

    // Rate-limit: max 3 codes per phone in the last 10 minutes
    const { count } = await supabase
      .from('otp_verifications')
      .select('*', { count: 'exact', head: true })
      .eq('phone', phone)
      .gt('created_at', new Date(Date.now() - 10 * 60 * 1000).toISOString());

    if ((count ?? 0) >= 3) {
      return json({ error: 'Demasiados intentos. Espera 10 minutos.' }, 429);
    }

    const code = generateCode();
    const expires_at = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    await supabase.from('otp_verifications').insert({ phone, code, expires_at });

    try {
      const result = await sendOtp(phone, code);
      return json({ success: true, channel: result.channel });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`[otp] send failed for phone=${tail(phone)}: ${message.slice(0, 200)}`);
      return json({ error: 'No se pudo enviar el código. Verifica el número.' }, 502);
    }
  }

  // ── VERIFY OTP ────────────────────────────────────────────────────────────
  if (body.action === 'verify') {
    const phone = body.phone?.trim();
    const code = body.code?.trim();

    if (!phone || !code) {
      return json({ error: 'phone y code son requeridos' }, 400);
    }

    // Store review login (only when enabled): skip the OTP lookup, authenticate as the demo user.
    const isReviewBypass = isReviewPhone(phone) && sameCode(code, REVIEW_BYPASS_CODE);
    if (isReviewPhone(phone) && !isReviewBypass) {
      return json({ error: 'Código incorrecto o expirado' }, 401);
    }

    const authPhone = isReviewBypass ? REVIEW_DEMO_PHONE : phone;

    if (!isReviewBypass) {
      // Traer el código vigente más reciente para este teléfono (sin filtrar por
      // code) para poder contar intentos fallidos y frenar fuerza bruta.
      const { data: otpRow } = await supabase
        .from('otp_verifications')
        .select('*')
        .eq('phone', phone)
        .eq('used', false)
        .gt('expires_at', new Date().toISOString())
        .order('created_at', { ascending: false })
        .limit(1)
        .single();

      if (!otpRow) {
        return json({ error: 'Código incorrecto o expirado' }, 401);
      }

      // Límite de intentos: máx 5 por código. Al excederse, se invalida.
      if ((otpRow.attempts ?? 0) >= 5) {
        await supabase.from('otp_verifications').update({ used: true }).eq('id', otpRow.id);
        return json({ error: 'Demasiados intentos. Solicita un código nuevo.' }, 429);
      }

      if (!sameCode(String(otpRow.code), code)) {
        await supabase.from('otp_verifications')
          .update({ attempts: (otpRow.attempts ?? 0) + 1 })
          .eq('id', otpRow.id);
        return json({ error: 'Código incorrecto o expirado' }, 401);
      }

      // Correcto → marcar como usado.
      await supabase.from('otp_verifications').update({ used: true }).eq('id', otpRow.id);
    } else {
      console.log('[whatsapp-otp] review login used');
    }

    // Session WITHOUT a password (P0-6.2, 2026-10-11): the OTP was verified above, so the server issues a one-time magic-link
    // token for the phone's internal account and redeems it at once. No password is derived, stored or returned; the response
    // keeps the same shape ({ success, session, isNewUser, customer }), so the published app needs no change.
    const issued = await issueSession(supabase, authPhone);
    if ('error' in issued) {
      console.error(`[whatsapp-otp] session failed (${issued.error}) for ${tail(authPhone)}`);
      return json({ error: 'No pudimos iniciar tu sesión. Intenta de nuevo.' }, 500);
    }
    const session = { session: issued.session };

    // Check if customer profile exists
    const { data: customer } = await supabase
      .from('customers')
      .select('id, name, auth_user_id')
      .eq('phone', authPhone)
      .single();

    // Vincular customer ↔ auth user si aún no lo está (requerido por RLS).
    if (customer && !customer.auth_user_id && session.session?.user?.id) {
      await supabase.from('customers')
        .update({ auth_user_id: session.session.user.id })
        .eq('id', customer.id);
    }

    return json({
      success: true,
      session: session.session,
      isNewUser: !customer,
      customer: customer ?? null,
    });
  }

  return json({ error: 'action debe ser "send" o "verify"' }, 400);
});
