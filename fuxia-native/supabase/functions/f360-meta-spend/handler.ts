// f360-meta-spend — reads Meta Ads spend (read-only Marketing API) into f360.marketing_spend_rows through
// public.f360_marketing_spend_api_import (service role). Callers: pg_cron daily (Bearer F360_SYNC_SECRET) or an owner.
//   {"action":"daily"}                              → the last 7 full days (Meta restates recent days; the newest import wins)
//   {"action":"backfill","from":"YYYY-MM-DD","to":…} → history, in windows of 31 days (owner or scheduler secret)
import { f360User, serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { safeEqual } from '../_shared/f360-woo/orders.ts';
import { accountCurrency, addDays, fetchInsights, mxToday, toSpendRows, windows } from './meta.ts';

export type MetaEnv = SupabaseEnv & { META_ADS_TOKEN: string; META_AD_ACCOUNT_ID: string; META_API_VERSION?: string; F360_SYNC_SECRET?: string };
type Deps = { fetch?: typeof fetch; rpc?: <T>(fn: string, args: Record<string, unknown>) => Promise<T>; now?: Date };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const isDay = (d: unknown): d is string => typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d) && !Number.isNaN(Date.parse(d));

export async function handleMetaSpend(req: Request, env: MetaEnv, deps: Deps = {}) {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!(env.F360_SYNC_SECRET && token && safeEqual(token, env.F360_SYNC_SECRET))) {
    const u = await f360User(env, token);
    if (!u) return json({ error: 'Tu sesión no es válida.' }, 401);
    if (u.role !== 'owner') return json({ error: 'Tu cuenta no tiene permiso para esta acción.' }, 403);
  }
  if (!env.META_ADS_TOKEN || !/^\d{5,20}$/.test(env.META_AD_ACCOUNT_ID ?? '')) return json({ error: 'Meta no está configurado.' }, 503);

  const body = (await req.json().catch(() => ({}))) as { action?: string; from?: unknown; to?: unknown };
  const today = mxToday(deps.now);
  const yesterday = addDays(today, -1);
  let from: string; let to: string;
  if ((body.action ?? 'daily') === 'daily') { from = addDays(today, -7); to = yesterday; }
  else if (body.action === 'backfill' && isDay(body.from) && isDay(body.to) && body.from <= body.to && body.to <= yesterday && body.from >= '2020-01-01') {
    from = body.from; to = body.to;
    if (Date.parse(to) - Date.parse(from) > 800 * 864e5) return json({ error: 'Máximo 800 días por llamada.' }, 400);
  } else return json({ error: 'Acción no válida.' }, 400);

  const f = (deps.fetch ?? fetch) as unknown as Parameters<typeof fetchInsights>[0];
  const rpc = deps.rpc ?? serviceRpc(env);
  const cfg = { token: env.META_ADS_TOKEN, accountId: env.META_AD_ACCOUNT_ID, version: env.META_API_VERSION || 'v24.0' };
  const done: unknown[] = [];
  for (const [a, b] of windows(from, to)) {
    try {
      const currency = await accountCurrency(f, cfg);
      const rows = toSpendRows(await fetchInsights(f, cfg, a, b), cfg.accountId, currency);
      done.push(await rpc('f360_marketing_spend_api_import',
        { p_platform: 'meta', p_account_id: cfg.accountId, p_currency: currency, p_from: a, p_to: b, p_rows: rows }));
    } catch (e) {
      const msg = (e instanceof Error ? e.message : String(e)).slice(0, 400);
      await rpc('f360_measurement_run_failed', { p_source_key: 'meta_ads', p_from: a, p_to: b, p_error: msg }).catch(() => undefined);
      return json({ ok: false, error: msg, window: [a, b], done }, 502);
    }
  }
  return json({ ok: true, from, to, windows: done });
}
