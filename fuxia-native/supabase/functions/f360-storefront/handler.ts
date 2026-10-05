// f360-storefront — public endpoint for the store's product page: ONE delivery promise rule (CRO-6) and
// "Avísame cuando llegue" (CRO-5). Mario 2026-10-05, staging only.
// Actions (POST JSON):
//   promise   {woo_product_id, market}                     → { market, product_key, variations: {<woo_variation_id>: promise}, trust }
//   notify_me {woo_product_id, woo_variation_id, market, phone, name?, consent: true, page_url?, website? (honeypot)}
//   promise_lines {woo_variation_ids: number[], market} → { market, lines: {<woo_variation_id>: promise} }   (checkout, Pedido recibido)
//   review_sync {review: {woo_review_id, woo_product_id, rating, status, media_count, woo_verified, reviewed_at, claims}}  (server key only, CRO-3B1)
// Server-to-server callers (Hilo, the WordPress server) send header x-f360-key = SERVER_KEY instead of a browser Origin: they may read
// promises and report reviews (review_sync), never register intents (notify_me is browser-only).
// The rule, the texts and every check live in the database (f360.delivery_promise_rules, f360_storefront_promise,
// f360_stock_intent_create): this file only validates the shape, hashes the IP for rate limiting and forwards.
// The sales channel comes from configuration (F360_STOREFRONT_TARGET), never from the browser.
export type StorefrontEnv = { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string; ALLOWED_ORIGINS: string; TARGET_KEY: string; SERVER_KEY?: string };

const MARKETS = new Set(['MX', 'CO', 'US']);
const promiseCache = new Map<string, { at: number; data: unknown }>();
const PROMISE_TTL_MS = 30_000;

function timingSafeEqual(a: string, b: string) {
  let x = 0; for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return x === 0;
}

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function handleStorefront(req: Request, env: StorefrontEnv, fetchImpl: typeof fetch = fetch): Promise<Response> {
  const origin = req.headers.get('Origin') ?? '';
  const allowed = env.ALLOWED_ORIGINS.split(',').map((o) => o.trim()).filter(Boolean);
  const cors: Record<string, string> = allowed.includes(origin)
    ? { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type', Vary: 'Origin' } : {};
  const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...cors } });
  if (req.method === 'OPTIONS') return new Response(null, { status: allowed.includes(origin) ? 204 : 403, headers: cors });
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const serverKey = req.headers.get('x-f360-key') ?? '';
  const server = !!env.SERVER_KEY && env.SERVER_KEY.length >= 24 && serverKey.length === env.SERVER_KEY.length && timingSafeEqual(serverKey, env.SERVER_KEY);
  if (!allowed.includes(origin) && !server) return json({ error: 'Origen no permitido.' }, 403);
  if (!env.TARGET_KEY) return json({ error: 'Canal no configurado.' }, 500);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'Solicitud no válida.' }, 400); }
  const rpc = async <T>(fn: string, args: Record<string, unknown>): Promise<{ ok: true; data: T } | { ok: false; error: string }> => {
    const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST',
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
    const data = await r.json().catch(() => null);
    return r.ok ? { ok: true, data: data as T } : { ok: false, error: (data as { message?: string } | null)?.message ?? 'No se pudo completar.' };
  };
  const market = MARKETS.has(String(body.market ?? '').toUpperCase()) ? String(body.market).toUpperCase() : 'MX';

  if (body.action === 'promise_lines') {
    const ids = Array.isArray(body.woo_variation_ids) ? body.woo_variation_ids.map(Number) : [];
    if (!ids.length || ids.length > 50 || ids.some((n) => !Number.isInteger(n) || n <= 0)) return json({ error: 'Líneas no válidas.' }, 400);
    const r = await rpc('f360_storefront_promise_lines', { p_target_key: env.TARGET_KEY, p_woo_variation_ids: ids, p_market: market });
    return json(r.ok ? r.data : { market, lines: {} });                       // fail closed: no promise rather than a wrong one
  }

  if (body.action === 'review_sync') {
    // CRO-3B1: the WordPress server reports one CusRev review (no text, no author). Claims carry only a SHA-256 of the
    // reviewer's e-mail, her Woo account id and the paid orders WordPress found; Fuxia 360 verifies against its own facts.
    if (!server) return json({ error: 'Acción no permitida.' }, 403);
    const rv = (body.review ?? {}) as Record<string, unknown>;
    const id = Number(rv.woo_review_id), prod = Number(rv.woo_product_id), rating = Number(rv.rating);
    if (!Number.isInteger(id) || id <= 0 || !Number.isInteger(prod) || prod <= 0 || !Number.isInteger(rating) || rating < 1 || rating > 5) {
      return json({ error: 'Reseña no válida.' }, 400);
    }
    const c = (rv.claims ?? {}) as Record<string, unknown>;
    const orders = Array.isArray(c.woo_order_ids) ? c.woo_order_ids.map(Number).filter((n) => Number.isInteger(n) && n > 0).slice(0, 50) : [];
    const hash = typeof c.email_sha256 === 'string' && /^[0-9a-f]{64}$/i.test(c.email_sha256) ? c.email_sha256.toLowerCase() : null;
    const user = Number.isInteger(Number(c.woo_user_id)) && Number(c.woo_user_id) > 0 ? Number(c.woo_user_id) : null;
    const r = await rpc('f360_review_sync', { p_target_key: env.TARGET_KEY, p_review: {
      woo_review_id: id, woo_product_id: prod, rating, status: String(rv.status ?? ''), media_count: Number(rv.media_count) || 0,
      woo_verified: rv.woo_verified === true, reviewed_at: String(rv.reviewed_at ?? ''),
      claims: { woo_order_ids: orders, email_sha256: hash, woo_user_id: user } } });
    return r.ok ? json(r.data) : json({ error: r.error }, 400);
  }

  const product = Number(body.woo_product_id);
  if (!Number.isInteger(product) || product <= 0) return json({ error: 'Producto no válido.' }, 400);

  if (body.action === 'promise') {
    const key = `${product}:${market}`;
    const hit = promiseCache.get(key);
    if (hit && Date.now() - hit.at < PROMISE_TTL_MS) return json(hit.data);
    const r = await rpc('f360_storefront_promise', { p_target_key: env.TARGET_KEY, p_woo_product_id: product, p_market: market });
    if (!r.ok) return json({ variations: {}, trust: [] });                      // fail closed: the page keeps its own state
    promiseCache.set(key, { at: Date.now(), data: r.data });
    return json(r.data);
  }

  if (body.action === 'notify_me') {
    if (server) return json({ error: 'Acción no permitida.' }, 403);          // server callers only read promises
    if (body.website) return json({ ok: true });                                 // honeypot
    const variation = Number(body.woo_variation_id);
    if (!Number.isInteger(variation) || variation <= 0) return json({ error: 'Talla no válida.' }, 400);
    const text = (v: unknown, max: number) => String(v ?? '').replace(/[<>]/g, '').trim().slice(0, max);
    const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim();
    const ipHash = ip ? (await sha256(`${env.SUPABASE_SERVICE_ROLE_KEY.slice(-16)}:${ip}`)).slice(0, 32) : null;
    const r = await rpc<{ ok: boolean; already?: boolean; code?: string; error?: string }>('f360_stock_intent_create', {
      p_target_key: env.TARGET_KEY, p_woo_product_id: product, p_woo_variation_id: variation, p_market: market,
      p_phone: text(body.phone, 30), p_name: text(body.name, 80) || null, p_consent: body.consent === true, p_source: 'pdp',
      p_ip_hash: ipHash, p_page_url: text(body.page_url, 300) || null });
    if (!r.ok) return json({ error: 'No pudimos registrar tu aviso. Intenta de nuevo.' }, 400);
    return json(r.data, r.data.ok ? 200 : 400);
  }

  return json({ error: 'Acción no válida.' }, 400);
}
