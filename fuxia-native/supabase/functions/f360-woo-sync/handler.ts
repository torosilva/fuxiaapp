// f360-woo-sync — drains the stock push queue and/or reconciles Fuxia 360 ↔ Woo for ONE target.
// Callers: a scheduler (Bearer F360_SYNC_SECRET) or an owner/operator from Fuxia 360 ("Revisar ahora", user JWT).
import { restAdapter } from '../_shared/f360-woo/rest.ts';
import { applyVisibility, pushStock, reconcile } from '../_shared/f360-woo/sync.ts';
import { pushContent } from '../_shared/f360-woo/content.ts';
import { f360User, serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { safeEqual } from '../_shared/f360-woo/orders.ts';
import type { WooAdapter } from '../_shared/f360-woo/types.ts';

export type SyncEnv = SupabaseEnv & { WOO_TARGET_KEY: string; WOO_BASE_URL: string; WOO_USER: string; WOO_SECRET: string; F360_SYNC_SECRET?: string };
export type SyncOptions = { wrapAdapter?: (a: WooAdapter) => WooAdapter };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });

export function syncAdapter(env: SyncEnv, opts: SyncOptions = {}) {
  const a = restAdapter({ baseUrl: env.WOO_BASE_URL, user: env.WOO_USER, secret: env.WOO_SECRET });
  return opts.wrapAdapter ? opts.wrapAdapter(a) : a;
}

export async function handleSync(req: Request, env: SyncEnv, opts: SyncOptions = {}): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  let who = 'Sistema'; let role = 'system';
  if (!(env.F360_SYNC_SECRET && token && safeEqual(token, env.F360_SYNC_SECRET))) {
    const u = await f360User(env, token);
    if (!u) return json({ error: 'Tu sesión no es válida.' }, 401);
    if (u.role !== 'owner' && u.role !== 'operator') return json({ error: 'Tu cuenta no tiene permiso para esta acción.' }, 403);
    who = u.display_name; role = u.role;
  }
  let action = 'push'; let body: { action?: string; woo_product_id?: number; product_ids?: string[] } = {};
  try { body = (await req.json()) as typeof body; action = String(body.action ?? 'push'); } catch { /* default */ }
  const rpc = serviceRpc(env);
  const woo = syncAdapter(env, opts);
  try {
    // Fuxia 360 content → the current store's products (owners only, one store product per call; the DB refuses production)
    if (action === 'content_list' || action === 'content') {
      if (role !== 'owner') return json({ error: 'Solo una dueña puede mandar contenido a la tienda.' }, 403);
      if (action === 'content_list') return json({ items: await rpc('f360_legacy_content_list', { p_target_key: env.WOO_TARGET_KEY, p_product_ids: body.product_ids ?? null }) });
      if (!Number.isInteger(body.woo_product_id)) return json({ error: 'Falta el producto de la tienda.' }, 400);
      return json(await pushContent(rpc, woo, env.WOO_TARGET_KEY, body.woo_product_id!, env.SUPABASE_URL, who));
    }
    if (action === 'reconcile') {
      const pushedBefore = await pushStock(rpc, woo, env.WOO_TARGET_KEY);
      const run = await reconcile(rpc, woo, env.WOO_TARGET_KEY, who);
      const pushedAfter = run.drifted || run.missing ? await pushStock(rpc, woo, env.WOO_TARGET_KEY) : null;
      return json({ reconcile: run, pushedBefore, pushedAfter });
    }
    // every tick: push queued stock, then hide/show store products as requested (D4)
    return json({ push: await pushStock(rpc, woo, env.WOO_TARGET_KEY), visibility: await applyVisibility(rpc, woo, env.WOO_TARGET_KEY) });
  } catch (e) {
    return json({ error: `No se pudo completar: ${(e as Error).message}` }, 502);
  }
}
