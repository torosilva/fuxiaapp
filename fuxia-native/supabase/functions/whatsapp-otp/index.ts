import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')!;
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')!;
const TWILIO_WHATSAPP_FROM = Deno.env.get('TWILIO_WHATSAPP_FROM')!; // e.g. whatsapp:+14155238886 (sandbox)

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

function normalizeMexicanPhone(phone: string): string {
  // Mexico: +521XXXXXXXXXX → +52XXXXXXXXXX (Twilio expects 10-digit local number)
  if (phone.startsWith('+521') && phone.length === 14) {
    return '+52' + phone.slice(4);
  }
  return phone;
}

async function sendWhatsApp(to: string, code: string): Promise<void> {
  const normalizedTo = normalizeMexicanPhone(to);
  const toWhatsApp = `whatsapp:${normalizedTo}`;

  console.log(`[whatsapp-otp] sending from=${TWILIO_WHATSAPP_FROM} to=${toWhatsApp}`);

  const body = new URLSearchParams({
    From: TWILIO_WHATSAPP_FROM,
    To: toWhatsApp,
    Body: `Tu código de verificación Fuxia Ballerinas es: *${code}*\n\nVálido por 10 minutos. No lo compartas con nadie.`,
  });

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

  const responseText = await res.text();
  console.log(`[whatsapp-otp] twilio status=${res.status} body=${responseText}`);

  if (!res.ok) {
    throw new Error(`Twilio ${res.status}: ${responseText}`);
  }

  try {
    const parsed = JSON.parse(responseText);
    console.log(`[whatsapp-otp] twilio sid=${parsed.sid} status=${parsed.status}`);
  } catch {
    // non-JSON response, already logged above
  }
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

  // ── SEND OTP ──────────────────────────────────────────────────────────────
  if (body.action === 'send') {
    const phone = body.phone?.trim();
    if (!phone || !/^\+\d{7,15}$/.test(phone)) {
      return json({ error: 'Número de teléfono inválido. Usa formato E.164: +521234567890' }, 400);
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
      await sendWhatsApp(phone, code);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`[whatsapp-otp] send failed for phone=${phone}: ${message}`);
      return json({ error: 'No se pudo enviar el mensaje. Verifica el número.', debug: message }, 502);
    }

    return json({ success: true, message: 'Código enviado por WhatsApp' });
  }

  // ── VERIFY OTP ────────────────────────────────────────────────────────────
  if (body.action === 'verify') {
    const phone = body.phone?.trim();
    const code = body.code?.trim();

    if (!phone || !code) {
      return json({ error: 'phone y code son requeridos' }, 400);
    }

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

    // Get or create Supabase auth user (email derived from phone for internal use)
    const fakeEmail = `${phone.replace('+', '')}@fuxia.app`;
    const password = `fuxia_${phone}_${Deno.env.get('OTP_SALT') ?? 'salt'}`;

    let userId: string;

    const { data: existingUser } = await supabase.auth.admin.getUserByEmail(fakeEmail);

    if (existingUser?.user) {
      userId = existingUser.user.id;
    } else {
      const { data: newUser, error: createErr } = await supabase.auth.admin.createUser({
        email: fakeEmail,
        password,
        email_confirm: true,
        user_metadata: { phone },
      });
      if (createErr || !newUser.user) {
        return json({ error: 'Error creando usuario' }, 500);
      }
      userId = newUser.user.id;
    }

    // Sign in to get a session token the app can use
    const { data: session, error: signInErr } = await supabase.auth.signInWithPassword({
      email: fakeEmail,
      password,
    });

    if (signInErr || !session.session) {
      return json({ error: 'Error iniciando sesión' }, 500);
    }

    // Check if customer profile exists
    const { data: customer } = await supabase
      .from('customers')
      .select('id, name')
      .eq('phone', phone)
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
