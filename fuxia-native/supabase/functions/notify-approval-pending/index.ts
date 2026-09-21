import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================================
// notify-approval-pending — se llama justo después de insertar una request en
// inventory_change_requests. Manda push a todas las cuentas con role='admin'
// para que revisen la cola.
//
// Body: { request_id: uuid }
//
// El cliente lo llama con la anon key + su JWT (no admin obligatorio: cualquier
// staff válido puede disparar el notify de su propia request). Adentro
// verificamos que la request exista y esté pending; si no, no mandamos push.
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

function summarize(action: string, payload: any): string {
  if (action === 'bulk_add') {
    const combos = (payload?.colors?.length || 1) * (payload?.sizes?.length || 0);
    return `${combos} combinaciones de "${payload?.product_name ?? '¿?'}"`;
  }
  if (action === 'adjust_stock') {
    const delta = (payload?.target_stock ?? 0) - (payload?.current_stock ?? 0);
    const sign = delta > 0 ? '+' : '';
    return `${sign}${delta} pares de "${payload?.product_name ?? '¿?'}" (talla ${payload?.size ?? ''})`;
  }
  if (action === 'delete') {
    return `eliminar "${payload?.product_name ?? '¿?'}" talla ${payload?.size ?? ''}`;
  }
  return 'cambio de inventario';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: 'Body inválido' }, 400); }
  const { request_id } = body;
  if (!request_id) return json({ error: 'request_id requerido' }, 400);

  // 1. Traer request + nombre de canal para armar el mensaje.
  const { data: reqRow } = await supabase
    .from('inventory_change_requests')
    .select('id, channel_id, action, payload, status, requested_by_name, channels(name)')
    .eq('id', request_id)
    .single();
  if (!reqRow) return json({ error: 'Request no encontrada' }, 404);
  if ((reqRow as any).status !== 'pending') {
    // Ya fue resuelta, no molestamos.
    return json({ ok: true, skipped: 'not-pending' });
  }

  const channelName = (reqRow as any).channels?.name ?? 'un canal';
  const staffName = (reqRow as any).requested_by_name ?? 'Una vendedora';
  const summary = summarize((reqRow as any).action, (reqRow as any).payload);

  // 2. Buscar todos los admin con push_token registrado.
  //     Hacemos 2 queries en vez de un join embed: PostgREST no siempre
  //     detecta la relación push_tokens.customer_id → customers.id sin FK
  //     explícita, y con embed volvía vacío. Simpler y más resiliente así.
  const { data: admins, error: adminsErr } = await supabase
    .from('customers')
    .select('id, name')
    .eq('role', 'admin');

  if (adminsErr) {
    console.error(`[notify-approval-pending] admins fetch failed: ${adminsErr.message}`);
    return json({ error: adminsErr.message }, 500);
  }

  const adminIds = ((admins ?? []) as { id: string }[]).map((a) => a.id);
  if (adminIds.length === 0) {
    return json({ ok: true, notified_count: 0, note: 'No hay cuentas con role=admin' });
  }

  const { data: tokenRows, error: tokensErr } = await supabase
    .from('push_tokens')
    .select('expo_token, customer_id')
    .in('customer_id', adminIds);

  if (tokensErr) {
    console.error(`[notify-approval-pending] tokens fetch failed: ${tokensErr.message}`);
    return json({ error: tokensErr.message }, 500);
  }

  const rawRows = (tokenRows ?? []) as { expo_token: string; customer_id: string }[];
  console.log(`[notify-approval-pending] raw_rows=${rawRows.length}`);
  for (const r of rawRows) {
    const preview = (r.expo_token ?? '').slice(0, 22) + '…' + (r.expo_token ?? '').slice(-6);
    console.log(`[notify-approval-pending]  · customer=${r.customer_id.slice(0, 8)} token=${preview}`);
  }
  const tokens = rawRows
    .map((t) => t.expo_token)
    .filter((t) => !!t && t.startsWith('ExponentPushToken'));
  console.log(`[notify-approval-pending] admins=${adminIds.length} tokens_after_filter=${tokens.length}`);

  if (tokens.length === 0) {
    return json({ ok: true, notified_count: 0, note: 'No hay admins con push_token registrado' });
  }

  // 3. Armar mensajes y enviar al Expo Push API en un solo POST.
  const messages = tokens.map((to) => ({
    to,
    sound: 'default',
    title: `Nueva solicitud de inventario`,
    body: `${staffName} pidió ${summary} en ${channelName}. Toca para revisar.`,
    data: { type: 'inventory_approval', request_id, channel_id: (reqRow as any).channel_id },
  }));

  let expoStatus = 0;
  let expoBodyPreview = '';
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
    expoStatus = res.status;
    const text = await res.text();
    expoBodyPreview = text.slice(0, 400);
    console.log(`[notify-approval-pending] expo status=${res.status} body=${expoBodyPreview}`);
  } catch (err) {
    console.error(`[notify-approval-pending] push send threw: ${(err as Error).message}`);
  }

  return json({
    ok: true,
    notified_count: tokens.length,
    expo_status: expoStatus,
    expo_body_preview: expoBodyPreview,
  });
});
