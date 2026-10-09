// f360-store-reserve — public endpoint for the store's product page: "Entrega inmediata" + "Apártalas 3 horas" (any customer,
// Mario 2026-10-09; the phone is proven by a one-time code sent by WhatsApp).
// Actions (POST JSON): availability {woo_variation_id} · send_code {phone, country?} · reserve {phone, code, name?, woo_variation_id, location_id, country?}
// · scarcity {woo_variation_id} (CRO-5a) · catalog {} (shop page filters) · favorite {event, market, anon_id, woo_product_id, woo_variation_id?, color?} (♡, anonymous) · a_la_medida {phone, name, color, size?, store_size?, foot_cm?, note?, woo_product_id, product_name, country} (Hilo chat).
// Codes are created, hashed, rate-limited and checked in the database (f360_reserve_code_issue / f360_reserve_with_code); this
// function only sends them by WhatsApp (same Twilio template as the app's login code). TEST_PHONES (staging only) get the code back
// in the answer instead of a WhatsApp. Every rule (2 pairs, 3 hours, free pair) is enforced in the database. CORS limited to
// ALLOWED_ORIGINS. Runtime-agnostic (Deno / Node).
// · pay_link {phone, name, email, items:[{id, quantity}], coupons?, address?, country} (checkout rescue: Woo order + Woo's payment page).
export type ReserveEnv = { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string; ALLOWED_ORIGINS: string; TEST_PHONES: string; TEST_CODE: string;
  WOO_BASE_URL?: string; WOO_USER?: string; WOO_SECRET?: string; TARGET_KEY?: string;   // TARGET_KEY: from configuration, never the browser
  TWILIO_ACCOUNT_SID?: string; TWILIO_AUTH_TOKEN?: string; TWILIO_WHATSAPP_FROM?: string; TWILIO_CONTENT_SID?: string };

/** Mexican mobiles on WhatsApp need the "1" after +52 (same rule as the app's whatsapp-otp). */
export function whatsappNumber(phone: string): string {
  return phone.startsWith('+52') && !phone.startsWith('+521') && phone.length === 13 ? '+521' + phone.slice(3) : phone;
}

export function normalizePhone(raw: unknown): string | null {
  const s = String(raw ?? '').trim();
  const d = s.replace(/\D/g, '');
  if (!d) return null;
  if (s.startsWith('+')) return d.length >= 10 && d.length <= 15 ? `+${d}` : null;
  if (d.length === 10) return `+52${d}`;                       // Mexican 10-digit number
  if (d.length === 12 && d.startsWith('52')) return `+${d}`;
  return d.length >= 11 && d.length <= 15 ? `+${d}` : null;
}

/** A legacy service-role key is a JWT (apikey + Bearer); a new secret key (sb_secret_…) goes ONLY as apikey — it is not a JWT. */
export function serviceHeaders(key: string): Record<string, string> {
  return key.split('.').length === 3 ? { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' } : { apikey: key, 'Content-Type': 'application/json' };
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
    const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers: serviceHeaders(env.SUPABASE_SERVICE_ROLE_KEY), body: JSON.stringify(args) });
    const data = await r.json().catch(() => null);
    if (!r.ok) console.error(`f360-store-reserve rpc ${fn} → ${r.status}`, JSON.stringify(data)?.slice(0, 300));
    return r.ok ? { ok: true, data: data as T } : { ok: false, error: (data as { message?: string } | null)?.message ?? 'No se pudo completar.' };
  };
  const testPhones = new Set(env.TEST_PHONES.split(',').map((p) => normalizePhone(p)).filter(Boolean) as string[]);
  const variation = Number(body.woo_variation_id);

  // Shop search terms (no personal data) → "Más buscados"
  if (body.action === 'search_log') {
    const term = String(body.term ?? '').replace(/[<>]/g, '').trim().slice(0, 60);
    if (term.length >= 3) await rpc('f360_log_search', { p_term: term, p_country: String(body.country ?? '').slice(0, 8) });
    return json({ ok: true });
  }

  // ♡ Favoritos V1 (Mario 2026-10-06): anonymous intent signal. The browser keeps the list; Fuxia 360 records the event with a
  // random visitor id (never personal data) and resolves the canonical model itself. The channel comes from configuration.
  if (body.action === 'favorite') {
    const ev = String(body.event ?? ''), market = String(body.market ?? '').toLowerCase(), anon = String(body.anon_id ?? '');
    const wp = Number(body.woo_product_id), wv = body.woo_variation_id == null ? null : Number(body.woo_variation_id);
    if (!['favorite_added', 'favorite_removed', 'favorite_add_to_cart'].includes(ev) || !['mx', 'co'].includes(market)
      || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(anon)
      || !Number.isInteger(wp) || wp <= 0 || (wv !== null && (!Number.isInteger(wv) || wv <= 0))) return json({ error: 'Solicitud no válida.' }, 400);
    if (!env.TARGET_KEY) return json({ error: 'Canal no configurado.' }, 500);
    const color = String(body.color ?? '').replace(/[<>]/g, '').trim().slice(0, 80);
    const r = await rpc<{ ok: boolean; identified?: boolean; limited?: boolean }>('f360_favorite_record', { p: { target_key: env.TARGET_KEY, event: ev, market,
      anon_id: anon, woo_product_id: wp, woo_variation_id: wv, color: color || null } });
    return r.ok ? json({ ok: r.data.ok !== false }) : json({ error: r.error }, 400);
  }

  // Shop page (Mario 2026-10-03): colours, sizes and availability states per store product + best sellers / new.
  // No quantities or prices. Cached 2 minutes per function instance.
  if (body.action === 'catalog') {
    const now = Date.now();
    if (!catalogCache || now - catalogCache.at > 120_000) {
      if (!env.TARGET_KEY) return json({ error: 'Canal no configurado.' }, 500);
      const r = await rpc<{ items: unknown[] }>('f360_storefront_catalog', { p_target_key: env.TARGET_KEY });
      if (!r.ok) return json({ error: r.error }, 400);
      const top = await rpc<string[]>('f360_top_searches', { p_days: 30, p_limit: 6 });
      catalogCache = { at: now, data: { ...r.data, top_searches: top.ok ? top.data : [] } };
    }
    return json(catalogCache.data);
  }

  // CRO-5a: may the store show a stock COUNT for this variation? Only when every location behind the online ATS is
  // certified (opening count / cutover). Boolean only; unknown variation ⇒ false.
  if (body.action === 'scarcity') {
    if (!Number.isInteger(variation) || variation <= 0) return json({ reliable: false });
    const r = await rpc<{ reliable: boolean }>('f360_scarcity_state', { p_woo_variation_id: variation });
    return json({ reliable: r.ok ? r.data.reliable === true : false });
  }

  if (body.action === 'availability') {
    if (!Number.isInteger(variation) || variation <= 0) return json({ error: 'Talla no válida.' }, 400);
    const r = await rpc<{ variant_id: string | null; stores: { location_id: string; name: string }[] }>('f360_store_availability', { p_woo_variation_id: variation });
    return r.ok ? json({ stores: r.data.stores ?? [] }) : json({ error: r.error }, 400);
  }

  const phone = normalizePhone(body.phone);
  if (!phone) return json({ error: 'Escribe tu teléfono a 10 dígitos.' }, 400);

  // Contact left in the web chat after Hilo escalated (Bandeja de clientas): completes the case of that conversation.
  if (body.action === 'contacto') {
    const text = (v: unknown, max: number) => String(v ?? '').replace(/[<>]/g, '').trim().slice(0, max);
    if ((body as { website?: unknown }).website) return json({ ok: true });                 // honeypot
    const conv = text(body.conversation_id, 100), name = text(body.name, 80);
    if (!conv) return json({ error: 'Falta la conversación.' }, 400);
    if (!name) return json({ error: 'Dinos tu nombre.' }, 400);
    const r = await rpc<{ id: string }>('f360_case_upsert', { p: { conversation_id: conv, source: 'hilo_web', name, phone,
      product: text(body.product_name, 200) || null, color: text(body.color, 80) || null, size: text(body.size, 20) || null,
      country: text(body.country, 8) || null, page_url: text(body.page_url, 300) || null } });
    return r.ok ? json({ ok: true }) : json({ error: r.error }, 400);
  }

  // "¿No encontraste tu color y talla? Lo hacemos a la medida" (Mario 2026-10-03): Hilo's chat on the product page
  // leaves a request for the team. Any phone (it is a lead, not a sale); the DB caps it at 3 per phone per day.
  if (body.action === 'a_la_medida') {
    const text = (v: unknown, max: number) => String(v ?? '').replace(/[<>]/g, '').trim().slice(0, max);
    if ((body as { website?: unknown }).website) return json({ ok: true });                 // honeypot: bots fill hidden fields
    const color = text(body.color, 80), name = text(body.name, 80);
    if (!color) return json({ error: 'Dinos qué color te gustaría.' }, 400);
    if (!name) return json({ error: 'Dinos tu nombre.' }, 400);
    const foot = Number(String(body.foot_cm ?? '').replace(',', '.'));
    if (!env.TARGET_KEY) return json({ error: 'Canal no configurado.' }, 500);   // the channel comes from configuration, never from the browser
    const r = await rpc<{ id: string; product: string }>('f360_custom_request_create', { p: {
      target_key: env.TARGET_KEY, woo_product_id: String(Number(body.woo_product_id) || ''),
      product_name: text(body.product_name, 200), color, size: text(body.size, 20), store_size: text(body.store_size, 10),
      foot_cm: Number.isFinite(foot) && foot >= 18 && foot <= 32 ? String(foot) : '', name, phone, note: text(body.note, 500), country: text(body.country, 8) } });
    return r.ok ? json({ ok: true, product: r.data.product }) : json({ error: r.error }, 400);
  }

  // "Link de pago" (Mario 2026-10-04): the checkout failed (Instagram's browser, rejected card…). We create a PENDING Woo order
  // with the cart's product ids and quantities only — Woo prices it, applies (and validates) the coupons — and return Woo's own
  // payment page. Mexico only for now (free shipping there; Colombia has its own currency and gateway). The case goes to the Bandeja.
  if (body.action === 'pay_link') {
    const text = (v: unknown, max: number) => String(v ?? '').replace(/[<>]/g, '').trim().slice(0, max);
    if ((body as { website?: unknown }).website) return json({ ok: true });                 // honeypot
    if (text(body.country, 8).toLowerCase() !== 'mx') return json({ error: 'Por ahora el link de pago es para México. Escríbenos por WhatsApp y te ayudamos.' }, 400);
    if (!env.WOO_BASE_URL || !env.WOO_USER || !env.WOO_SECRET) return json({ error: 'Ahorita no podemos generar el link. Escríbenos por WhatsApp.' }, 503);
    const name = text(body.name, 80), email = text(body.email, 120);
    if (!name) return json({ error: 'Dinos tu nombre.' }, 400);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: 'Escribe tu correo: ahí te llega la confirmación.' }, 400);
    const raw = Array.isArray(body.items) ? body.items.slice(0, 10) : [];
    const items = raw.map((x) => ({ id: Number((x as { id?: unknown }).id), quantity: Number((x as { quantity?: unknown }).quantity) }))
      .filter((x) => Number.isInteger(x.id) && x.id > 0 && Number.isInteger(x.quantity) && x.quantity >= 1 && x.quantity <= 5);
    if (!items.length) return json({ error: 'Tu carrito está vacío.' }, 400);
    const coupons = (Array.isArray(body.coupons) ? body.coupons.slice(0, 3) : []).map((c) => text(c, 40)).filter(Boolean);
    const a = (body.address ?? {}) as Record<string, unknown>;
    const parts = name.split(/\s+/), first = parts.shift() ?? name, last = parts.join(' ');
    const addr = { first_name: first, last_name: last, address_1: text(a.address_1, 200), address_2: text(a.address_2, 200), city: text(a.city, 80),
      state: text(a.state, 40), postcode: text(a.postcode, 12), country: 'MX', phone };
    const open = await rpc<{ id: string }>('f360_pay_link_open', { p: { name, phone, email, country: 'mx', products: text(body.products, 200),
      reason: text(body.reason, 120), page_url: text(body.page_url, 300) } });
    if (!open.ok) return json({ error: open.error }, 429);
    const auth = 'Basic ' + btoa(`${env.WOO_USER}:${env.WOO_SECRET}`);
    const base = env.WOO_BASE_URL.replace(/\/+$/, '');
    const crear = (withCoupons: boolean) => fetchImpl(`${base}/wp-json/wc/v3/orders`, { method: 'POST',
      headers: { Authorization: auth, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ status: 'pending', set_paid: false, created_via: 'f360_pay_link', billing: { ...addr, email }, shipping: addr,
        line_items: items.map((x) => ({ product_id: x.id, quantity: x.quantity })),
        shipping_lines: [{ method_id: 'free_shipping', method_title: 'Envío gratuito', total: '0' }],
        coupon_lines: withCoupons ? coupons.map((code) => ({ code })) : [],
        customer_note: 'Link de pago generado porque el checkout falló (Fuxia 360).', meta_data: [{ key: '_f360_pay_link_case', value: open.data.id }] }) });
    let r = await crear(coupons.length > 0);
    if (!r.ok && coupons.length) r = await crear(false);                    // a coupon Woo rejects never blocks the link
    const o = await r.json().catch(() => null) as { id?: number; total?: string; currency_symbol?: string; payment_url?: string; message?: string } | null;
    if (!r.ok || !o?.id || !o.payment_url) {
      await rpc('f360_pay_link_done', { p_id: open.data.id, p_order: 0, p_total: null, p_url: null, p_error: o?.message ?? `HTTP ${r.status}` });
      return json({ error: 'No pudimos crear tu link. Escríbenos por WhatsApp y te ayudamos.' }, 502);
    }
    // keep the customer in the Mexican store (/mx/): prices, gateways and copy follow the country prefix
    const url = o.payment_url.replace(/^(https?:\/\/[^/]+)(?!\/mx\/)\//, '$1/mx/');
    const total = `${o.currency_symbol ?? '$'}${Number(o.total ?? 0).toLocaleString('es-MX')}`;
    await rpc('f360_pay_link_done', { p_id: open.data.id, p_order: o.id, p_total: total, p_url: url, p_error: null });
    return json({ ok: true, order: o.id, total, url });
  }

  if (body.action === 'send_code') {
    const country = String(body.country ?? '').toUpperCase() === 'CO' ? 'CO' : 'MX';
    const issued = await rpc<{ ok: boolean; error?: string; phone?: string; code?: string }>('f360_reserve_code_issue', { p_phone: phone, p_country: country });
    if (!issued.ok) return json({ error: 'No pudimos mandar el código. Intenta de nuevo.' }, 400);
    if (!issued.data.ok || !issued.data.code) return json({ error: issued.data.error ?? 'No pudimos mandar el código.' }, 429);
    if (testPhones.has(phone)) return json({ sent: true, test: true, test_code: issued.data.code });   // staging test phones only
    if (!env.TWILIO_ACCOUNT_SID || !env.TWILIO_AUTH_TOKEN || !env.TWILIO_WHATSAPP_FROM || !env.TWILIO_CONTENT_SID) {
      return json({ error: 'Por ahora no pudimos mandar el código. Escríbenos por WhatsApp.' }, 503);
    }
    const tw = await fetchImpl(`https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', Authorization: `Basic ${btoa(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`)}` },
      body: new URLSearchParams({ From: env.TWILIO_WHATSAPP_FROM, To: `whatsapp:${whatsappNumber(issued.data.phone ?? phone)}`,
        ContentSid: env.TWILIO_CONTENT_SID, ContentVariables: JSON.stringify({ '1': issued.data.code }) }),
    });
    if (!tw.ok) {
      console.error('f360-store-reserve twilio', tw.status, (await tw.text().catch(() => '')).slice(0, 200));
      return json({ error: 'No pudimos mandar el WhatsApp. Revisa tu número.' }, 502);
    }
    return json({ sent: true });
  }

  if (body.action === 'reserve') {
    if (!/^[0-9]{6}$/.test(String(body.code ?? '').trim())) return json({ error: 'Escribe el código de 6 números.' }, 400);
    if (!Number.isInteger(variation) || variation <= 0) return json({ error: 'Talla no válida.' }, 400);
    const a = await rpc<{ variant_id: string | null }>('f360_store_availability', { p_woo_variation_id: variation });
    if (!a.ok || !a.data.variant_id) return json({ error: 'Esa talla no se puede apartar.' }, 400);
    const name = String(body.name ?? '').replace(/[<>]/g, '').trim().slice(0, 80);
    const r = await rpc<{ ok: boolean; error?: string; created?: boolean; first_name?: string; reservation?: { id: string; store: string; variant: string; expires_at: string } }>(
      'f360_reserve_with_code', { p_phone: phone, p_code: String(body.code).trim(), p_name: name, p_location_id: String(body.location_id ?? ''),
        p_variant_id: a.data.variant_id, p_country: String(body.country ?? '').toUpperCase() === 'CO' ? 'CO' : 'MX' });
    if (!r.ok) return json({ error: r.error }, 400);                    // e.g. "Ya no hay ese par disponible en …", "Ya tienes 2 pares apartados…"
    if (!r.data.ok) return json({ error: r.data.error ?? 'No se pudo apartar.' }, 400);
    return json({ reservation: r.data.reservation, first_name: r.data.first_name ?? null, created: !!r.data.created });
  }

  return json({ error: 'Acción no válida.' }, 400);
}
