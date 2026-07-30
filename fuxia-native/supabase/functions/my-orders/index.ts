import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================================
// my-orders — rastreo de pedidos SEGURO (Fase 0)
// ----------------------------------------------------------------------------
// Reemplaza el patrón inseguro anterior: la app pedía TODAS las órdenes de la
// tienda via woocommerce-proxy y filtraba por email en el cliente (exponía
// pedidos de todas las clientas). Aquí exigimos el JWT del usuario, resolvemos
// SU customer, y consultamos WooCommerce server-side solo con su wc_customer_id
// / email. Devuelve estado + datos de guía (tracking).
//
// Deploy: npx supabase functions deploy my-orders --project-ref <ref>
//   (con verify-jwt ACTIVADO — es el default; NO usar --no-verify-jwt)
// ============================================================================

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WC_URL = Deno.env.get('WC_URL')!;
const WC_CONSUMER_KEY = Deno.env.get('WC_CONSUMER_KEY')!;
const WC_CONSUMER_SECRET = Deno.env.get('WC_CONSUMER_SECRET')!;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...CORS } });
}

function extractTracking(order: any) {
  const map = new Map<string, string>((order.meta_data ?? []).map((m: any) => [String(m.key).toLowerCase(), m.value]));
  return {
    tracking_number: map.get('_tracking_number') ?? map.get('tracking_number') ?? map.get('_aftership_tracking_number') ?? null,
    tracking_provider: map.get('_tracking_provider') ?? map.get('tracking_provider') ?? map.get('_aftership_tracking_provider') ?? null,
    tracking_url: map.get('_tracking_url') ?? map.get('tracking_url') ?? null,
  };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  // 1. Verificar el JWT del usuario.
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'No autorizado' }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: 'Sesión inválida' }, 401);

  // 2. Resolver el customer del usuario (por auth_user_id, fallback a phone en metadata).
  const authUserId = userData.user.id;
  const metaPhone = (userData.user.user_metadata as any)?.phone ?? null;

  let { data: customer } = await admin
    .from('customers').select('id, email, phone, wc_customer_id')
    .eq('auth_user_id', authUserId).maybeSingle();
  if (!customer && metaPhone) {
    const r = await admin.from('customers').select('id, email, phone, wc_customer_id').eq('phone', metaPhone).maybeSingle();
    customer = r.data;
  }
  if (!customer) return json({ error: 'Perfil no encontrado' }, 404);

  // 3. Parámetros opcionales.
  let statuses = 'pending,processing,on-hold,completed';
  let limit = 30;
  try {
    const body = await req.json();
    if (Array.isArray(body?.statuses) && body.statuses.length) statuses = body.statuses.join(',');
    if (Number.isFinite(body?.limit)) limit = Math.min(Math.max(1, body.limit), 100);
  } catch { /* body opcional */ }

  // 4. Consultar WooCommerce SOLO con la identidad de esta clienta.
  const params = new URLSearchParams({ per_page: String(limit), orderby: 'date', order: 'desc', status: statuses });
  if (customer.wc_customer_id) {
    params.set('customer', String(customer.wc_customer_id));
  } else if (customer.email) {
    params.set('search', customer.email); // WC search por email como fallback
  } else {
    return json({ orders: [] }); // sin forma de identificar en WC
  }

  const basicAuth = btoa(`${WC_CONSUMER_KEY}:${WC_CONSUMER_SECRET}`);
  const res = await fetch(`${WC_URL}/orders?${params.toString()}`, { headers: { Authorization: `Basic ${basicAuth}` } });
  if (!res.ok) {
    console.error(`[my-orders] WC ${res.status}`);
    return json({ error: 'No se pudieron obtener los pedidos' }, 502);
  }
  const raw = await res.json();

  // 5. Filtro de seguridad extra: si usamos search, garantizar que el email coincide.
  const mine = (Array.isArray(raw) ? raw : []).filter((o: any) => {
    if (customer!.wc_customer_id && o.customer_id === customer!.wc_customer_id) return true;
    if (customer!.email && o.billing?.email?.toLowerCase() === customer!.email.toLowerCase()) return true;
    return false;
  });

  const orders = mine.map((o: any) => ({
    id: o.id, number: o.number, status: o.status,
    date_created: o.date_created, date_modified: o.date_modified,
    date_paid: o.date_paid, date_completed: o.date_completed,
    total: o.total, currency: o.currency,
    line_items: (o.line_items ?? []).map((li: any) => ({
      id: li.id, name: li.name, sku: li.sku, quantity: li.quantity, total: li.total,
      image: li.image?.src ? { src: li.image.src } : undefined,
    })),
    shipping_lines: (o.shipping_lines ?? []).map((s: any) => ({ method_title: s.method_title, total: s.total })),
    tracking: extractTracking(o),
  }));

  return json({ orders });
});
