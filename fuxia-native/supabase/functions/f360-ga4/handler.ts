// f360-ga4 — daily capture of the GA4 customer path into f360.ga4_funnel (public.f360_ga4_import, service role).
// Callers: pg_cron once a day (Bearer F360_SYNC_SECRET) or an owner. Without GA4_SA_KEY_JSON → 503 and no call.
import { f360User, serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { safeEqual } from '../_shared/f360-woo/orders.ts';
import { accessToken, parseKey, reportBody, runReport, toRows, windows } from './ga4.ts';

export type Ga4Env = SupabaseEnv & { GA4_SA_KEY_JSON?: string; GA4_PROPERTY_ID?: string; F360_SYNC_SECRET?: string };
type Deps = { fetch?: typeof fetch; rpc?: <T>(fn: string, args: Record<string, unknown>) => Promise<T>; now?: Date };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
export const mxToday = (now = new Date()) => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Mexico_City' }).format(now);

export async function handleGa4(req: Request, env: Ga4Env, deps: Deps = {}) {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!(env.F360_SYNC_SECRET && bearer && safeEqual(bearer, env.F360_SYNC_SECRET))) {
    const u = await f360User(env, bearer);
    if (!u) return json({ error: 'Tu sesión no es válida.' }, 401);
    if (u.role !== 'owner') return json({ error: 'Tu cuenta no tiene permiso para esta acción.' }, 403);
  }
  if (!env.GA4_SA_KEY_JSON) return json({ error: 'Google Analytics no está configurado.' }, 503);
  const body = (await req.json().catch(() => ({}))) as { action?: string };
  if ((body.action ?? 'daily') !== 'daily') return json({ error: 'Acción no válida.' }, 400);

  const f = (deps.fetch ?? fetch) as unknown as Parameters<typeof runReport>[0];
  const rpc = deps.rpc ?? serviceRpc(env);
  const today = mxToday(deps.now);
  const w = windows(today);
  const property = env.GA4_PROPERTY_ID || '519011849';
  try {
    const token = await accessToken(f, parseKey(env.GA4_SA_KEY_JSON), deps.now?.getTime());
    const byChannel = toRows(await runReport(f, token, property, reportBody(w, true)), w, true);
    const total = toRows(await runReport(f, token, property, reportBody(w, false)), w, false);
    const result = await rpc('f360_ga4_import', { p_captured_on: today, p_rows: [...total, ...byChannel] });
    return json({ ok: true, today, rows: total.length + byChannel.length, result });
  } catch (e) {
    const msg = (e instanceof Error ? e.message : String(e)).slice(0, 400);
    await rpc('f360_measurement_run_failed', { p_source_key: 'ga4', p_from: w.anterior.from, p_to: w.actual.to, p_error: msg }).catch(() => undefined);
    return json({ ok: false, error: msg }, 502);
  }
}
