import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================================
// admin-broadcast-push — la admin manda un push a un segmento de clientas.
//
// Segmentos:
//   'all'       → todas las clientas con push_token
//   'bronze'    → solo bronze
//   'silver'    → solo silver
//   'gold'      → solo gold
//   'inactive'  → sin compras en los ultimos 30 dias (con push_token)
//
// Body:
//   { segment, title, body, deep_link? }
//
// Rate limit: max 1 broadcast por segmento por 24h para no spammear.
// Auditoria: cada envio queda en la tabla `broadcasts`.
// ============================================================================

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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

const VALID_SEGMENTS = new Set(['all', 'bronze', 'silver', 'gold', 'inactive']);

async function resolveCustomerIds(
  supabase: ReturnType<typeof createClient>,
  segment: string,
): Promise<string[]> {
  if (segment === 'all') {
    const { data } = await supabase.from('customers').select('id');
    return ((data ?? []) as { id: string }[]).map((c) => c.id);
  }
  if (segment === 'bronze' || segment === 'silver' || segment === 'gold') {
    const { data } = await supabase.from('loyalty_cards')
      .select('customer_id')
      .eq('tier', segment);
    return ((data ?? []) as { customer_id: string }[]).map((c) => c.customer_id);
  }
  if (segment === 'inactive') {
    // Clientas cuya ultima transaccion es > 30 dias atras (o nunca).
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const iso = thirtyDaysAgo.toISOString();

    const [allCustsRes, activeRes] = await Promise.all([
      supabase.from('customers').select('id'),
      supabase.from('transactions')
        .select('loyalty_cards!inner(customer_id)')
        .gte('created_at', iso),
    ]);
    const activeIds = new Set(
      ((activeRes.data ?? []) as any[])
        .map((r) => r.loyalty_cards?.customer_id)
        .filter(Boolean),
    );
    return ((allCustsRes.data ?? []) as { id: string }[])
      .map((c) => c.id)
      .filter((id) => !activeIds.has(id));
  }
  return [];
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'No autorizado' }, 401);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // 1. Validar que sea admin.
  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: 'Sesión inválida' }, 401);
  const { data: caller } = await supabase
    .from('customers').select('id, name, role')
    .eq('auth_user_id', userData.user.id).maybeSingle();
  if (!caller || (caller as any).role !== 'admin') {
    return json({ error: 'Requiere admin' }, 403);
  }

  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: 'Body inválido' }, 400); }
  const { segment, title, body: msgBody, deep_link } = body;

  if (!VALID_SEGMENTS.has(segment)) {
    return json({ error: `segment invalido. Debe ser uno de: ${Array.from(VALID_SEGMENTS).join(', ')}` }, 400);
  }
  if (!title || String(title).trim().length === 0) return json({ error: 'title requerido' }, 400);
  if (!msgBody || String(msgBody).trim().length === 0) return json({ error: 'body requerido' }, 400);

  // 2. Rate limit: no permitir mas de 1 broadcast a este segmento en las
  //    ultimas 24 horas.
  const dayAgo = new Date();
  dayAgo.setHours(dayAgo.getHours() - 24);
  const { data: recent } = await supabase.from('broadcasts')
    .select('id, created_at')
    .eq('segment', segment)
    .gte('created_at', dayAgo.toISOString())
    .limit(1);
  if ((recent ?? []).length > 0) {
    return json({
      error: `Ya se envió un push al segmento "${segment}" en las últimas 24h. Espera un poco antes de mandar otro.`,
    }, 429);
  }

  // 3. Resolver destinatarios.
  const customerIds = await resolveCustomerIds(supabase, segment);
  if (customerIds.length === 0) {
    return json({ error: `Sin clientas en el segmento "${segment}"` }, 400);
  }

  // 4. Obtener sus push tokens.
  const { data: tokenRows } = await supabase
    .from('push_tokens')
    .select('expo_token')
    .in('customer_id', customerIds);
  const tokens = ((tokenRows ?? []) as { expo_token: string }[])
    .map((t) => t.expo_token)
    .filter((t) => !!t && t.startsWith('ExponentPushToken'));

  if (tokens.length === 0) {
    // Registramos igual para historial, pero avisamos que no se envio.
    await supabase.from('broadcasts').insert({
      sent_by_customer_id: (caller as any).id,
      sent_by_name: (caller as any).name ?? 'Admin',
      segment, title: String(title).trim(), body: String(msgBody).trim(),
      deep_link: deep_link ? String(deep_link) : null,
      recipients_count: 0, expo_status: 0, expo_body_preview: 'no_tokens',
    });
    return json({ ok: true, sent_count: 0, note: 'No hay tokens registrados en ese segmento' });
  }

  // 5. Enviar en batches de 100 al Expo Push API.
  const CHUNK = 100;
  const chunks: string[][] = [];
  for (let i = 0; i < tokens.length; i += CHUNK) chunks.push(tokens.slice(i, i + CHUNK));

  const data: Record<string, unknown> = { type: 'broadcast', segment };
  if (deep_link) data.deep_link = String(deep_link);

  let lastStatus = 0;
  let lastBodyPreview = '';
  for (const chunk of chunks) {
    const messages = chunk.map((to) => ({
      to, sound: 'default',
      title: String(title).trim(),
      body: String(msgBody).trim(),
      data,
    }));
    try {
      const res = await fetch('https://exp.host/--/api/v2/push/send', {
        method: 'POST',
        headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify(messages),
      });
      lastStatus = res.status;
      lastBodyPreview = (await res.text()).slice(0, 400);
    } catch (err) {
      console.error(`[admin-broadcast-push] chunk failed: ${(err as Error).message}`);
    }
  }

  // 6. Registrar en broadcasts para auditoria.
  await supabase.from('broadcasts').insert({
    sent_by_customer_id: (caller as any).id,
    sent_by_name: (caller as any).name ?? 'Admin',
    segment, title: String(title).trim(), body: String(msgBody).trim(),
    deep_link: deep_link ? String(deep_link) : null,
    recipients_count: tokens.length,
    expo_status: lastStatus,
    expo_body_preview: lastBodyPreview,
  });

  return json({ ok: true, sent_count: tokens.length, expo_status: lastStatus });
});
