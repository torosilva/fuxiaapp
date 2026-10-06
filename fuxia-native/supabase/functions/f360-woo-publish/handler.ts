// f360-woo-publish — runs ONE publish job created by public.f360_request_publish.
// Security:
//   · the caller's Supabase JWT is verified (auth/v1/user) and must belong to an f360 OWNER (DW8), checked here AND
//     again inside f360_pub_claim, which also requires the caller to be the person who requested the job;
//   · Woo credentials come only from this function's environment and are used ONLY for the target they belong to
//     (WOO_TARGET_KEY + WOO_BASE_URL must match the job's target), so ids of one store never mix with another;
//   · production targets are refused in P2.2.
// Runtime-agnostic: index.ts serves it on Deno (Edge Functions); scripts/f360/publisher_local.ts serves it on Node.
import { publish } from '../_shared/f360-woo/publisher.ts';
import { restAdapter } from '../_shared/f360-woo/rest.ts';
import type { PublishOutcome, Recorder, Snapshot, WooAdapter } from '../_shared/f360-woo/types.ts';

export type PublisherEnv = {
  SUPABASE_URL: string; SUPABASE_ANON_KEY: string; SUPABASE_SERVICE_ROLE_KEY: string;
  WOO_TARGET_KEY: string; WOO_BASE_URL: string; WOO_USER: string; WOO_SECRET: string;
  /** Public base for product photos (defaults to SUPABASE_URL). */
  STORAGE_PUBLIC_BASE?: string;
};
export type HandlerOptions = { wrapAdapter?: (a: WooAdapter) => WooAdapter; storeHome?: (baseUrl: string) => Promise<string | null> };

/** U2: ask the store who it is (WordPress REST index) before writing anything. */
async function storeHome(baseUrl: string): Promise<string | null> {
  try {
    const r = await fetch(`${baseUrl.replace(/\/+$/, '')}/wp-json/`, { headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(15_000) });
    if (!r.ok) return null;
    const j = await r.json() as { home?: string; url?: string };
    return String(j.home || j.url || '') || null;
  } catch { return null; }
}
const hostOf = (u: string) => { try { return new URL(u).host.toLowerCase(); } catch { return ''; } };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const trimUrl = (u: string) => u.trim().replace(/\/+$/, '').toLowerCase();

async function rpc<T>(env: PublisherEnv, fn: string, args: Record<string, unknown>, token: string): Promise<T> {
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: token === env.SUPABASE_SERVICE_ROLE_KEY ? env.SUPABASE_SERVICE_ROLE_KEY : env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error((body && (body.message as string)) || `rpc ${fn} → ${res.status}`);
  return body as T;
}

export async function handle(req: Request, env: PublisherEnv, opts: HandlerOptions = {}): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  for (const k of ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'WOO_TARGET_KEY', 'WOO_BASE_URL', 'WOO_USER', 'WOO_SECRET'] as const) {
    if (!env[k]) return json({ error: 'El publicador no está configurado.' }, 500);
  }
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'Falta la sesión.' }, 401);
  let body: { job_id?: string; action?: string; product_id?: string; status?: string };
  try { body = (await req.json()) as typeof body; } catch { return json({ error: 'Solicitud no válida.' }, 400); }
  const visibility = body.action === 'visibility';
  const jobId = String(body.job_id ?? '');
  if (visibility ? !/^[0-9a-f-]{36}$/i.test(String(body.product_id ?? '')) || !['publish', 'draft'].includes(String(body.status)) : !/^[0-9a-f-]{36}$/i.test(jobId)) {
    return json({ error: 'Solicitud no válida.' }, 400);
  }

  // 1 · Who is calling? (verified by Supabase Auth, not by anything the client says)
  const u = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, { headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` } });
  if (!u.ok) return json({ error: 'Tu sesión no es válida. Vuelve a entrar.' }, 401);
  const user = (await u.json()) as { id: string };
  let me: { role: string };
  try { me = await rpc<{ role: string }>(env, 'f360_me', {}, token); } catch { return json({ error: 'Esta cuenta no tiene acceso a Fuxia 360.' }, 403); }
  if (me.role !== 'owner') return json({ error: 'Solo una dueña puede publicar.' }, 403);

  // "Publicar en vivo" / "Ocultar de la tienda": only the product's status in its store; owner re-checked in the database
  if (visibility) return setVisibility(env, opts, user.id, String(body.product_id), body.status as 'publish' | 'draft');

  // 2 · Claim (re-checks owner + requester + readiness in the database; locks the codes)
  const svc = env.SUPABASE_SERVICE_ROLE_KEY;
  let snap: Snapshot;
  try { snap = await rpc<Snapshot>(env, 'f360_pub_claim', { p_job_id: jobId, p_caller: user.id }, svc); }
  catch (e) { return json({ error: (e as Error).message }, 409); }

  const rec: Recorder = {
    step: (s) => rpc(env, 'f360_pub_step', { p_job_id: jobId, p_step: s.step, p_object_ref: s.ref ?? null, p_action: s.action,
      p_woo_id: s.wooId ?? null, p_ok: s.ok, p_message: s.message ?? null, p_detail: s.detail ?? null }, svc).then(() => undefined),
    link: (kind, id, wooId, extra) => rpc(env, 'f360_pub_link', { p_job_id: jobId, p_kind: kind, p_f360_id: id, p_woo_id: wooId, p_extra: extra ?? {} }, svc).then(() => undefined),
  };

  // 3 · The credentials in this environment must belong to the job's target.
  let outcome: PublishOutcome;
  if (snap.target.key !== env.WOO_TARGET_KEY || trimUrl(snap.target.base_url) !== trimUrl(env.WOO_BASE_URL)) {
    const message = `Este publicador está configurado para otra tienda (${env.WOO_TARGET_KEY}); no se tocó nada.`;
    await rec.step({ step: 'preflight', action: 'error', ok: false, message });
    outcome = { status: 'failed', error: message, summary: { woo_product_id: null, woo_status: null, variations: 0, created: 0, updated: 0, hidden: 0, stock_pushed: 0, mismatches: [] } };
  } else {
    // U2: the store itself must confirm it is the job's store (a wrong secret / DNS / copy can never receive a production publish)
    const home = await (opts.storeHome ?? storeHome)(env.WOO_BASE_URL);
    if (!home || hostOf(home) !== hostOf(snap.target.base_url)) {
      const message = home ? `La tienda respondió como ${hostOf(home)}, no como ${hostOf(snap.target.base_url)}; no se tocó nada.` : 'La tienda no confirmó quién es; no se tocó nada.';
      await rec.step({ step: 'preflight', action: 'error', ok: false, message });
      outcome = { status: 'failed', error: message, summary: { woo_product_id: null, woo_status: null, variations: 0, created: 0, updated: 0, hidden: 0, stock_pushed: 0, mismatches: [] } };
    } else {
      let adapter = restAdapter({ baseUrl: env.WOO_BASE_URL, user: env.WOO_USER, secret: env.WOO_SECRET, timeoutMs: 140_000 });   // creating a product with many photos: the store sideloads each one
      if (opts.wrapAdapter) adapter = opts.wrapAdapter(adapter);
      // production is allowed only by the channel's catalog switch (checked in publish() from the snapshot), never by a flag here
      outcome = await publish(snap, adapter, rec, { storageBase: env.STORAGE_PUBLIC_BASE || env.SUPABASE_URL });
    }
  }

  // 4 · Close the job (only a read-back-verified run records the published hash)
  const job = await rpc(env, 'f360_pub_finish', { p_job_id: jobId, p_status: outcome.status, p_error: outcome.error, p_summary: outcome.summary }, svc);
  return json({ job, outcome: { status: outcome.status, error: outcome.error, summary: outcome.summary } });
}

async function setVisibility(env: PublisherEnv, opts: HandlerOptions, caller: string, productId: string, status: 'publish' | 'draft'): Promise<Response> {
  const svc = env.SUPABASE_SERVICE_ROLE_KEY;
  let link: { woo_product_id: number; woo_status: string | null; legacy_woo_product_ids?: number[]; target: { key: string; base_url: string } };
  try { link = await rpc(env, 'f360_pub_visibility_begin', { p_product_id: productId, p_target_key: env.WOO_TARGET_KEY, p_status: status, p_caller: caller }, svc); }
  catch (e) { return json({ error: (e as Error).message }, 409); }
  const finish = (ok: boolean, wooStatus: string | null, message: string | null) => rpc<{ ok: boolean; woo_status: string | null }>(env, 'f360_pub_visibility_finish',
    { p_product_id: productId, p_target_key: env.WOO_TARGET_KEY, p_status: status, p_caller: caller, p_ok: ok, p_woo_status: wooStatus, p_message: message }, svc);
  if (link.target.key !== env.WOO_TARGET_KEY || trimUrl(link.target.base_url) !== trimUrl(env.WOO_BASE_URL)) {
    const m = `Este publicador está configurado para otra tienda (${env.WOO_TARGET_KEY}); no se tocó nada.`;
    await finish(false, null, m); return json({ error: m }, 409);
  }
  const home = await (opts.storeHome ?? storeHome)(env.WOO_BASE_URL);
  if (!home || hostOf(home) !== hostOf(link.target.base_url)) {
    const m = 'La tienda no confirmó quién es; no se tocó nada.';
    await finish(false, null, m); return json({ error: m }, 502);
  }
  let adapter = restAdapter({ baseUrl: env.WOO_BASE_URL, user: env.WOO_USER, secret: env.WOO_SECRET, timeoutMs: 60_000 });
  if (opts.wrapAdapter) adapter = opts.wrapAdapter(adapter);
  try {
    await adapter.updateProduct(link.woo_product_id, { status });
    const after = await adapter.getProduct(link.woo_product_id);              // read back: report what the store REALLY shows
    const ok = after?.status === status;
    // Old store products of the model: out of the catalog when the new one goes live (URL keeps working), back when it is hidden.
    const legacy = ok ? (link.legacy_woo_product_ids ?? []) : [];
    const failedLegacy: number[] = [];
    for (const id of legacy) {
      // _f360_redirect_to: the production mu-plugin 301-redirects the old product URL to the new product while it is live
      try { await adapter.updateProduct(id, { catalog_visibility: status === 'publish' ? 'hidden' : 'visible',
        meta_data: [{ key: '_f360_redirect_to', value: status === 'publish' ? String(link.woo_product_id) : '' }] }); }
      catch { failedLegacy.push(id); }
    }
    const note = legacy.length ? `${status === 'publish' ? 'Fuera del catálogo' : 'De vuelta en el catálogo'}: ${legacy.length - failedLegacy.length} producto(s) viejo(s)` +
      (failedLegacy.length ? `; no se pudo: ${failedLegacy.join(', ')}` : '') : null;
    const r = await finish(ok, after?.status ?? null, ok ? note : `La tienda quedó en ${after?.status ?? 'desconocido'}.`);
    return ok ? json({ ok: true, woo_status: r.woo_status, legacy_changed: legacy.length - failedLegacy.length, legacy_failed: failedLegacy })
      : json({ error: `La tienda quedó en ${after?.status ?? 'desconocido'}.` }, 502);
  } catch (e) {
    const m = `Error de la tienda: ${(e as Error).message}`;
    await finish(false, null, m); return json({ error: m }, 502);
  }
}
