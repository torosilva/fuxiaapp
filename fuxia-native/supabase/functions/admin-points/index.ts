import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================================
// admin-points — buscar clientas y ajustar puntos manualmente (solo admin).
// ----------------------------------------------------------------------------
// SEGURIDAD: verify-jwt ACTIVADO (default). Además, adentro validamos que quien
// llama tenga customers.role = 'admin'. Las lecturas/escrituras usan service
// role (bypassa RLS) — por eso el chequeo de admin es obligatorio.
//
// Acciones (body.action):
//   'search'  { query }                     → lista de clientas que matchean
//   'adjust'  { customer_id, delta, reason } → suma/resta puntos (delta puede ser
//                                              negativo). Gatilla realtime → la
//                                              app muestra la celebración sola.
// ============================================================================

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...CORS } });
}

function computeTier(points: number): 'bronze' | 'silver' | 'gold' {
  if (points >= 900) return 'gold';
  if (points >= 300) return 'silver';
  return 'bronze';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'No autorizado' }, 401);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // 1. Verificar sesión y que sea ADMIN.
  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: 'Sesión inválida' }, 401);
  const { data: caller } = await supabase
    .from('customers').select('role').eq('auth_user_id', userData.user.id).maybeSingle();
  if (!caller || caller.role !== 'admin') return json({ error: 'Requiere admin' }, 403);

  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: 'Body inválido' }, 400); }
  const action = body.action;

  // 2a. BUSCAR clientas.
  if (action === 'search') {
    const q = String(body.query ?? '').trim();
    if (!q) return json({ customers: [] });
    const like = `%${q}%`;
    const { data, error } = await supabase
      .from('customers')
      .select('id, name, phone, email, created_at, loyalty_cards(total_points, tier)')
      .or(`name.ilike.${like},phone.ilike.${like},email.ilike.${like}`)
      .limit(25);
    if (error) return json({ error: error.message }, 500);
    const customers = (data ?? []).map((c: any) => ({
      id: c.id, name: c.name, phone: c.phone, email: c.email, created_at: c.created_at,
      total_points: c.loyalty_cards?.[0]?.total_points ?? 0,
      tier: c.loyalty_cards?.[0]?.tier ?? 'bronze',
    }));
    return json({ customers });
  }

  // 2b. AJUSTAR puntos.
  if (action === 'adjust') {
    const customerId = body.customer_id;
    const delta = Math.trunc(Number(body.delta));
    const reason = String(body.reason ?? '').trim();
    if (!customerId || !Number.isFinite(delta) || delta === 0) {
      return json({ error: 'customer_id y delta (≠0) son requeridos' }, 400);
    }

    const { data: card } = await supabase
      .from('loyalty_cards').select('id, total_points').eq('customer_id', customerId).single();
    if (!card) return json({ error: 'La clienta no tiene tarjeta' }, 404);

    const newPoints = Math.max(0, card.total_points + delta);
    const newTier = computeTier(newPoints);
    const appliedDelta = newPoints - card.total_points; // por si se topó en 0

    await supabase.from('loyalty_cards').update({
      total_points: newPoints, tier: newTier, updated_at: new Date().toISOString(),
    }).eq('id', card.id);

    // Registrar el movimiento en el ledger (queda auditable con quién y por qué).
    await supabase.from('transactions').insert({
      loyalty_card_id: card.id, points_earned: appliedDelta, pairs_in_order: 0,
      channel: 'manual', notes: `ajuste_admin|by:${userData.user.id}|${reason}`,
    });

    return json({ ok: true, new_total: newPoints, tier: newTier, applied: appliedDelta });
  }

  return json({ error: 'action inválida (search|adjust)' }, 400);
});
