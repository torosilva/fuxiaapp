// f360-woo-sync — drains the stock push queue and/or reconciles Fuxia 360 ↔ Woo for ONE target.
// Callers: a scheduler (Bearer F360_SYNC_SECRET) or an owner/operator from Fuxia 360 ("Revisar ahora", user JWT).
import { restAdapter } from '../_shared/f360-woo/rest.ts';
import { applyVisibility, pushStock, reconcile } from '../_shared/f360-woo/sync.ts';
import { pushContent } from '../_shared/f360-woo/content.ts';
import { f360User, serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { safeEqual } from '../_shared/f360-woo/orders.ts';
import type { WooAdapter } from '../_shared/f360-woo/types.ts';
import { commerceReconcile, commerceWoo, type CommerceWoo } from '../_shared/f360-woo/commerce.ts';

export type SyncEnv = SupabaseEnv & { WOO_TARGET_KEY: string; WOO_BASE_URL: string; WOO_USER: string; WOO_SECRET: string; F360_SYNC_SECRET?: string };
export type SyncOptions = { wrapAdapter?: (a: WooAdapter) => WooAdapter; commerceWoo?: CommerceWoo };

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
    // Store links of some products (owners): old per-colour product → new single product, for the redirect list.
    if (action === 'permalinks') {
      if (role !== 'owner') return json({ error: 'Solo una dueña.' }, 403);
      const ids = (((body as { ids?: unknown }).ids as unknown[]) ?? []).map(Number).filter((n) => Number.isInteger(n) && n > 0).slice(0, 200);
      const out: Record<string, { permalink: string | null; status: string | null }> = {};
      for (const id of ids) {
        try { const p = await woo.getProduct(id) as (Awaited<ReturnType<typeof woo.getProduct>> & { permalink?: string }) | null; out[id] = { permalink: p?.permalink ?? null, status: p?.status ?? null }; }
        catch { out[id] = { permalink: null, status: null }; }
      }
      return json({ items: out });
    }
    if (action === 'content_list' || action === 'content') {
      if (role !== 'owner') return json({ error: 'Solo una dueña puede mandar contenido a la tienda.' }, 403);
      if (action === 'content_list') return json({ items: await rpc('f360_legacy_content_list', { p_target_key: env.WOO_TARGET_KEY, p_product_ids: body.product_ids ?? null }) });
      if (!Number.isInteger(body.woo_product_id)) return json({ error: 'Falta el producto de la tienda.' }, 400);
      return json(await pushContent(rpc, woo, env.WOO_TARGET_KEY, body.woo_product_id!, env.SUPABASE_URL, who));
    }
    // G1 Commerce Facts heartbeat (cron every 15 min, or owner/operator): captures economics of orders modified since
    // the cursor. Its success is what makes the online source fresh (STALE never depends on order activity).
    // U2: what this channel allows (production: stock / orders / visibility only when switched on)
    const mode = await rpc('f360_channel_mode', { p_target_key: env.WOO_TARGET_KEY }) as { catalog_mode?: string; stock_sync_mode?: string; orders_mode?: string | null } | null;
    const stockOn = (mode?.stock_sync_mode ?? 'on') === 'on', catalogOn = (mode?.catalog_mode ?? 'on') === 'on';
    // S-G0 D2: the order reconciliation follows the ORDER path (orders_mode = 'on'), not the stock push (production runs
    // with stock off and orders on). Channels without orders_mode keep the previous rule (stock on).
    const ordersOn = mode?.orders_mode === 'on' || (mode?.orders_mode == null && stockOn);
    if (action === 'commerce_poll' || action === 'commerce_reconcile') {
      if (!ordersOn) return json({ skipped: 'Este canal no manda pedidos a Fuxia 360 (pedidos apagados).' });
      // the cron tick sends commerce_poll; an owner/operator may ask for a deeper look back ("Revisar ahora")
      const raw = Number((body as { lookback_hours?: unknown }).lookback_hours);
      const lookbackHours = role !== 'system' && action === 'commerce_reconcile' && Number.isInteger(raw) && raw >= 1 && raw <= 24 * 800 ? raw : null;
      const cw = opts.commerceWoo ?? commerceWoo({ baseUrl: env.WOO_BASE_URL, user: env.WOO_USER, secret: env.WOO_SECRET });
      return json(await commerceReconcile(rpc, cw, env.WOO_TARGET_KEY, { lookbackHours }));
    }
    if (action === 'reconcile') {
      if (!stockOn) return json({ error: 'Este canal no sincroniza existencias; no hay nada que conciliar.' }, 409);
      const pushedBefore = await pushStock(rpc, woo, env.WOO_TARGET_KEY);
      const run = await reconcile(rpc, woo, env.WOO_TARGET_KEY, who);
      const pushedAfter = run.drifted || run.missing ? await pushStock(rpc, woo, env.WOO_TARGET_KEY) : null;
      return json({ reconcile: run, pushedBefore, pushedAfter });
    }
    // every tick: push queued stock, then hide/show store products as requested (D4)
    return json({ push: stockOn ? await pushStock(rpc, woo, env.WOO_TARGET_KEY) : { skipped: 'stock apagado en este canal' },
      visibility: catalogOn ? await applyVisibility(rpc, woo, env.WOO_TARGET_KEY) : { skipped: 'catálogo apagado en este canal' } });
  } catch (e) {
    return json({ error: `No se pudo completar: ${(e as Error).message}` }, 502);
  }
}
