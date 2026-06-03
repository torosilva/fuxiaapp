import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')!;
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')!;
const TWILIO_WHATSAPP_FROM = Deno.env.get('TWILIO_WHATSAPP_FROM')!; // e.g. whatsapp:+14155238886 (sandbox)
const TWILIO_CONTENT_SID = Deno.env.get('TWILIO_CONTENT_SID')!; // approved WhatsApp template SID
// Optional SMS sender. When set, OTP is sent via SMS first; WhatsApp is only used as fallback.
// Format: a Twilio-purchased SMS-capable number, e.g. "+15551234567".
const TWILIO_SMS_FROM = Deno.env.get('TWILIO_SMS_FROM') ?? '';

// App Store reviewer bypass — lets Apple log in without any messaging app installed.
// Reviewer selects México 🇲🇽 in the country picker, enters 5555555555 on phone screen,
// then REVIEW_BYPASS_CODE on verify. Authenticates as REVIEW_DEMO_PHONE (seeded user).
const REVIEW_BYPASS_PHONE = Deno.env.get('REVIEW_BYPASS_PHONE') ?? '+525555555555';
const REVIEW_BYPASS_CODE = Deno.env.get('REVIEW_BYPASS_CODE') ?? '555555';
const REVIEW_DEMO_PHONE = Deno.env.get('REVIEW_DEMO_PHONE') ?? '+525543412939';

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
  return Math.floor(100000 + Math.random() * 900000).toString();
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
  console.log(`[otp] sending SMS from=${TWILIO_SMS_FROM} to=${to}`);
  const { ok, status, text } = await twilioRequest(body);
  console.log(`[otp] twilio SMS status=${status} body=${text}`);
  if (!ok) throw new Error(`Twilio SMS ${status}: ${text}`);
}

async function sendWhatsApp(to: string, code: string): Promise<void> {
  const toWhatsApp = `whatsapp:${normalizeForWhatsApp(to)}`;
  const body = new URLSearchParams({
    From: TWILIO_WHATSAPP_FROM,
    To: toWhatsApp,
    ContentSid: TWILIO_CONTENT_SID,
    ContentVariables: JSON.stringify({ '1': code }),
  });
  console.log(`[otp] sending WhatsApp from=${TWILIO_WHATSAPP_FROM} to=${toWhatsApp}`);
  const { ok, status, text } = await twilioRequest(body);
  console.log(`[otp] twilio WhatsApp status=${status} body=${text}`);
  if (!ok) throw new Error(`Twilio WhatsApp ${status}: ${text}`);
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

    // Bypass for App Store review: report demo user as existing.
    const lookupPhone = phone === REVIEW_BYPASS_PHONE ? REVIEW_DEMO_PHONE : phone;

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

    // Bypass for App Store review: short-circuit without calling Twilio.
    if (phone === REVIEW_BYPASS_PHONE) {
      console.log('[whatsapp-otp] review bypass: send acknowledged for', phone);
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
      console.error(`[otp] send failed for phone=${phone}: ${message}`);
      return json({ error: 'No se pudo enviar el código. Verifica el número.', debug: message }, 502);
    }
  }

  // ── VERIFY OTP ────────────────────────────────────────────────────────────
  if (body.action === 'verify') {
    const phone = body.phone?.trim();
    const code = body.code?.trim();

    if (!phone || !code) {
      return json({ error: 'phone y code son requeridos' }, 400);
    }

    // Bypass for App Store review: skip OTP lookup, authenticate as the demo user.
    const isReviewBypass = phone === REVIEW_BYPASS_PHONE && code === REVIEW_BYPASS_CODE;
    if (phone === REVIEW_BYPASS_PHONE && code !== REVIEW_BYPASS_CODE) {
      return json({ error: 'Código incorrecto o expirado' }, 401);
    }

    const authPhone = isReviewBypass ? REVIEW_DEMO_PHONE : phone;

    if (!isReviewBypass) {
      const { data: otpRow } = await supabase
        .from('otp_verifications')
        .select('*')
        .eq('phone', phone)
        .eq('code', code)
        .eq('used', false)
        .gt('expires_at', new Date().toISOString())
        .order('created_at', { ascending: false })
        .limit(1)
        .single();

      if (!otpRow) {
        return json({ error: 'Código incorrecto o expirado' }, 401);
      }

      // Mark OTP as used
      await supabase.from('otp_verifications').update({ used: true }).eq('id', otpRow.id);
    } else {
      console.log('[whatsapp-otp] review bypass: authenticating as', authPhone);
    }

    // Get or create Supabase auth user (email derived from phone for internal use)
    const fakeEmail = `${authPhone.replace('+', '')}@fuxia.app`;
    const password = `fuxia_${authPhone}_${Deno.env.get('OTP_SALT') ?? 'salt'}`;

    // Try to sign in first; if credentials are invalid the user doesn't exist yet.
    let { data: session, error: signInErr } = await supabase.auth.signInWithPassword({
      email: fakeEmail,
      password,
    });

    if (signInErr || !session.session) {
      const { error: createErr } = await supabase.auth.admin.createUser({
        email: fakeEmail,
        password,
        email_confirm: true,
        user_metadata: { phone: authPhone },
      });
      if (createErr) {
        console.error(`[whatsapp-otp] createUser failed: ${createErr.message}`);
        return json({ error: 'Error creando usuario', debug: createErr.message }, 500);
      }

      const retry = await supabase.auth.signInWithPassword({
        email: fakeEmail,
        password,
      });
      if (retry.error || !retry.data.session) {
        console.error(`[whatsapp-otp] signIn after create failed: ${retry.error?.message}`);
        return json({ error: 'Error iniciando sesión', debug: retry.error?.message }, 500);
      }
      session = retry.data;
    }

    // Check if customer profile exists
    const { data: customer } = await supabase
      .from('customers')
      .select('id, name')
      .eq('phone', authPhone)
      .single();

    return json({
      success: true,
      session: session.session,
      isNewUser: !customer,
      customer: customer ?? null,
    });
  }

  return json({ error: 'action debe ser "send" o "verify"' }, 400);
});
