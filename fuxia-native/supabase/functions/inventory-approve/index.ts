import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================================
// inventory-approve — la admin aprueba o rechaza una request de cambio de
// inventario hecha por una vendedora. En aprobación, aplica el cambio real
// a channel_inventory con service_role (bypass RLS).
//
// Body:
//   { action: 'approve', request_id: uuid }
//   { action: 'reject',  request_id: uuid, reason?: string }
//
// Seguridad: verify-jwt activo + chequeo interno de customers.role='admin'.
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

interface BulkAddPayload {
  product_name: string;
  price: number;
  sku?: string | null;
  image_url?: string | null;
  colors: (string | null)[];
  sizes: string[];
  stock_per_combo: number;
}
interface AdjustStockPayload {
  channel_inventory_id: string;
  target_stock: number;
}
interface DeletePayload {
  channel_inventory_id: string;
}

async function applyChange(
  supabase: ReturnType<typeof createClient>,
  channelId: string,
  action: string,
  payload: any,
): Promise<{ error?: string }> {
  if (action === 'bulk_add') {
    const p = payload as BulkAddPayload;
    if (!p.product_name || !p.price || !Array.isArray(p.sizes) || p.sizes.length === 0) {
      return { error: 'payload bulk_add inválido' };
    }
    const colors: (string | null)[] = p.colors && p.colors.length > 0 ? p.colors : [null];
    const rows = colors.flatMap((color) =>
      p.sizes.map((size) => ({
        channel_id: channelId,
        product_name: p.product_name,
        sku: p.sku ?? null,
        color,
        size,
        price: p.price,
        stock: p.stock_per_combo ?? 0,
        sold: 0,
        image_url: p.image_url ?? null,
      })),
    );
    const { error } = await supabase.from('channel_inventory').insert(rows);
    if (error) return { error: error.message };
    return {};
  }

  if (action === 'adjust_stock') {
    const p = payload as AdjustStockPayload;
    if (!p.channel_inventory_id || typeof p.target_stock !== 'number') {
      return { error: 'payload adjust_stock inválido' };
    }
    // Releemos el sold para no bajar de lo ya vendido (ver cliente).
    const { data: row } = await supabase
      .from('channel_inventory')
      .select('sold')
      .eq('id', p.channel_inventory_id)
      .single();
    const soldNow = (row as any)?.sold ?? 0;
    const safeStock = Math.max(soldNow, p.target_stock);
    const { error } = await supabase
      .from('channel_inventory')
      .update({ stock: safeStock, updated_at: new Date().toISOString() })
      .eq('id', p.channel_inventory_id);
    if (error) return { error: error.message };
    return {};
  }

  if (action === 'delete') {
    const p = payload as DeletePayload;
    if (!p.channel_inventory_id) return { error: 'payload delete inválido' };
    const { error } = await supabase
      .from('channel_inventory')
      .delete()
      .eq('id', p.channel_inventory_id);
    if (error) return { error: error.message };
    return {};
  }

  return { error: `action desconocida: ${action}` };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'No autorizado' }, 401);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // 1. Verificar que quien llama sea admin.
  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: 'Sesión inválida' }, 401);
  const { data: caller } = await supabase
    .from('customers')
    .select('id, role')
    .eq('auth_user_id', userData.user.id)
    .maybeSingle();
  if (!caller || (caller as any).role !== 'admin') {
    return json({ error: 'Requiere admin' }, 403);
  }

  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: 'Body inválido' }, 400); }
  const { action, request_id, reason } = body;

  if (action !== 'approve' && action !== 'reject') {
    return json({ error: 'action inválida (approve|reject)' }, 400);
  }
  if (!request_id) return json({ error: 'request_id requerido' }, 400);

  // 2. Traer request y validar que esté pendiente.
  const { data: reqRow, error: reqErr } = await supabase
    .from('inventory_change_requests')
    .select('id, channel_id, action, payload, status')
    .eq('id', request_id)
    .single();
  if (reqErr || !reqRow) return json({ error: 'Request no encontrada' }, 404);
  if ((reqRow as any).status !== 'pending') {
    return json({ error: `Request ya está en estado ${(reqRow as any).status}` }, 409);
  }

  const nowIso = new Date().toISOString();

  // 3a. RECHAZO — simple marca de estado.
  if (action === 'reject') {
    const { error } = await supabase
      .from('inventory_change_requests')
      .update({
        status: 'rejected',
        reviewed_by_customer_id: (caller as any).id,
        reviewed_at: nowIso,
        rejection_reason: (reason ?? '').toString().slice(0, 500) || null,
      })
      .eq('id', request_id);
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true, status: 'rejected' });
  }

  // 3b. APROBACIÓN — aplicar el cambio y marcar aprobada.
  const applyResult = await applyChange(
    supabase,
    (reqRow as any).channel_id,
    (reqRow as any).action,
    (reqRow as any).payload,
  );
  if (applyResult.error) {
    // No marcamos como approved si falló la aplicación — queda pending para reintentar.
    return json({ error: `No se pudo aplicar el cambio: ${applyResult.error}` }, 500);
  }
  const { error: markErr } = await supabase
    .from('inventory_change_requests')
    .update({
      status: 'approved',
      reviewed_by_customer_id: (caller as any).id,
      reviewed_at: nowIso,
    })
    .eq('id', request_id);
  if (markErr) return json({ error: markErr.message }, 500);
  return json({ ok: true, status: 'approved' });
});
