// f360-store-reserve — public endpoint for the store's product page: "Entrega inmediata" + "Apártalo 2 horas" (Fuxia Gold).
// Actions (POST JSON): availability {woo_variation_id} · send_code {phone} · reserve {phone, code, woo_variation_id, location_id}
// · catalog {} (shop page filters) · a_la_medida {phone, name, color, size?, store_size?, foot_cm?, note?, woo_product_id, product_name, country} (Hilo chat).
// STAGING / testing: only TEST_PHONES can reserve, with TEST_CODE (no WhatsApp is sent). Every rule (Gold, 2 pairs,
// 2 hours, free pair) is enforced again in the database. CORS limited to ALLOWED_ORIGINS. Runtime-agnostic (Deno / Node).
export type ReserveEnv = { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string; ALLOWED_ORIGINS: string; TEST_PHONES: string; TEST_CODE: string };

export function normalizePhone(raw: unknown): string | null {
  const s = String(raw ?? '').trim();
  const d = s.replace(/\D/g, '');
  if (!d) return null;
  if (s.startsWith('+')) return d.length >= 10 && d.length <= 15 ? `+${d}` : null;
  if (d.length === 10) return `+52${d}`;                       // Mexican 10-digit number
  if (d.length === 12 && d.startsWith('52')) return `+${d}`;
  return d.length >= 11 && d.length <= 15 ? `+${d}` : null;
}

function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let x = 0; for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return x === 0;
}

let catalogCache: { at: number; data: unknown } | null = null;

export async function handleReserve(req: Request, env: ReserveEnv, fetchImpl: typeof fetch = fetch): Promise<Response> {
  const origin = req.headers.get('Origin') ?? '';
  const allowed = env.ALLOWED_ORIGINS.split(',').map((o) => o.trim()).filter(Boolean);
  const cors: Record<string, string> = allowed.includes(origin)
    ? { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type', Vary: 'Origin' } : {};
  const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...cors } });
  if (req.method === 'OPTIONS') return new Response(null, { status: allowed.includes(origin) ? 204 : 403, headers: cors });
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  if (!allowed.includes(origin)) return json({ error: 'Origen no permitido.' }, 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'Solicitud no válida.' }, 400); }
  const rpc = async <T>(fn: string, args: Record<string, unknown>): Promise<{ ok: true; data: T } | { ok: false; error: string }> => {
    const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST',
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
    const data = await r.json().catch(() => null);
    return r.ok ? { ok: true, data: data as T } : { ok: false, error: (data as { message?: string } | null)?.message ?? 'No se pudo completar.' };
  };
  const testPhones = new Set(env.TEST_PHONES.split(',').map((p) => normalizePhone(p)).filter(Boolean) as string[]);
  const variation = Number(body.woo_variation_id);

  // Shop page (Mario 2026-10-03): colours, sizes and availability states per store product + best sellers / new.
  // No quantities or prices. Cached 2 minutes per function instance.
  if (body.action === 'catalog') {
    const now = Date.now();
    if (!catalogCache || now - catalogCache.at > 120_000) {
      const r = await rpc<{ items: unknown[] }>('f360_storefront_catalog', { p_target_key: 'woo_staging4' });
      if (!r.ok) return json({ error: r.error }, 400);
      catalogCache = { at: now, data: r.data };
    }
    return json(catalogCache.data);
  }

  if (body.action === 'availability') {
    if (!Number.isInteger(variation) || variation <= 0) return json({ error: 'Talla no válida.' }, 400);
    const r = await rpc<{ variant_id: string | null; stores: { location_id: string; name: string }[] }>('f360_store_availability', { p_woo_variation_id: variation });
    return r.ok ? json({ stores: r.data.stores ?? [] }) : json({ error: r.error }, 400);
  }

  const phone = normalizePhone(body.phone);
  if (!phone) return json({ error: 'Escribe tu teléfono a 10 dígitos.' }, 400);

  // "¿No encontraste tu color y talla? Lo hacemos a la medida" (Mario 2026-10-03): Hilo's chat on the product page
  // leaves a request for the team. Any phone (it is a lead, not a sale); the DB caps it at 3 per phone per day.
  if (body.action === 'a_la_medida') {
    const text = (v: unknown, max: number) => String(v ?? '').replace(/[<>]/g, '').trim().slice(0, max);
    if ((body as { website?: unknown }).website) return json({ ok: true });                 // honeypot: bots fill hidden fields
    const color = text(body.color, 80), name = text(body.name, 80);
    if (!color) return json({ error: 'Dinos qué color te gustaría.' }, 400);
    if (!name) return json({ error: 'Dinos tu nombre.' }, 400);
    const foot = Number(String(body.foot_cm ?? '').replace(',', '.'));
    const r = await rpc<{ id: string; product: string }>('f360_custom_request_create', { p: {
      target_key: text(body.target_key, 40) || 'woo_staging4', woo_product_id: String(Number(body.woo_product_id) || ''),
      product_name: text(body.product_name, 200), color, size: text(body.size, 20), store_size: text(body.store_size, 10),
      foot_cm: Number.isFinite(foot) && foot >= 18 && foot <= 32 ? String(foot) : '', name, phone, note: text(body.note, 500), country: text(body.country, 8) } });
    return r.ok ? json({ ok: true, product: r.data.product }) : json({ error: r.error }, 400);
  }

  if (body.action === 'send_code') {
    const g = await rpc<{ exists: boolean; gold: boolean; first_name?: string }>('f360_gold_check', { p_phone: phone });
    if (!g.ok) return json({ error: g.error }, 400);
    if (!g.data.exists) return json({ error: 'No encontramos una cuenta Fuxia con ese teléfono.' }, 404);
    if (!g.data.gold) return json({ error: 'El apartado de 2 horas es un beneficio Fuxia Gold.' }, 403);
    if (!testPhones.has(phone)) return json({ error: 'Por ahora el apartado en línea está en pruebas.' }, 403);
    return json({ sent: true, first_name: g.data.first_name ?? null, test: true });    // test phones: fixed TEST_CODE, nothing is sent
  }

  if (body.action === 'reserve') {
    if (!testPhones.has(phone) || !env.TEST_CODE || !safeEqual(String(body.code ?? '').trim(), env.TEST_CODE)) return json({ error: 'Código incorrecto.' }, 401);
    if (!Number.isInteger(variation) || variation <= 0) return json({ error: 'Talla no válida.' }, 400);
    const a = await rpc<{ variant_id: string | null }>('f360_store_availability', { p_woo_variation_id: variation });
    if (!a.ok || !a.data.variant_id) return json({ error: 'Esa talla no se puede apartar.' }, 400);
    const r = await rpc<{ id: string; store: string; variant: string; expires_at: string }>('f360_reserve_for_phone',
      { p_phone: phone, p_location_id: String(body.location_id ?? ''), p_variant_id: a.data.variant_id });
    return r.ok ? json({ reservation: r.data }) : json({ error: r.error }, 400);
  }
  return json({ error: 'Acción no válida.' }, 400);
}
