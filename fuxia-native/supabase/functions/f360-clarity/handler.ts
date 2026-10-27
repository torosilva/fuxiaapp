// f360-clarity — daily capture of the Clarity export API into f360.clarity_snapshots (public.f360_clarity_import, service role).
// Callers: pg_cron once a day (Bearer F360_SYNC_SECRET) or an owner. {"action":"daily"} → last 24 h by Source, Device and URL.
// Without CLARITY_API_TOKEN → 503 and no call (so a second environment never spends the shared 10 calls a day).
import { f360User, serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { safeEqual } from '../_shared/f360-woo/orders.ts';
import { DAILY_DIMENSIONS, fetchClarity } from './clarity.ts';

export type ClarityEnv = SupabaseEnv & { CLARITY_API_TOKEN?: string; F360_SYNC_SECRET?: string };
type Deps = { fetch?: typeof fetch; rpc?: <T>(fn: string, args: Record<string, unknown>) => Promise<T>; now?: Date };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
export const mxToday = (now = new Date()) => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Mexico_City' }).format(now);

export async function handleClarity(req: Request, env: ClarityEnv, deps: Deps = {}) {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!(env.F360_SYNC_SECRET && bearer && safeEqual(bearer, env.F360_SYNC_SECRET))) {
    const u = await f360User(env, bearer);
    if (!u) return json({ error: 'Tu sesión no es válida.' }, 401);
    if (u.role !== 'owner') return json({ error: 'Tu cuenta no tiene permiso para esta acción.' }, 403);
  }
  if (!env.CLARITY_API_TOKEN) return json({ error: 'Clarity no está configurado.' }, 503);
  const body = (await req.json().catch(() => ({}))) as { action?: string };
  if ((body.action ?? 'daily') !== 'daily') return json({ error: 'Acción no válida.' }, 400);

  const f = (deps.fetch ?? fetch) as unknown as Parameters<typeof fetchClarity>[0];
  const rpc = deps.rpc ?? serviceRpc(env);
  const day = mxToday(deps.now);
  const done: unknown[] = [];
  for (const dim of DAILY_DIMENSIONS) {
    try {
      const metrics = await fetchClarity(f, env.CLARITY_API_TOKEN, 1, dim);
      done.push({ dimension: dim, result: await rpc('f360_clarity_import', { p_window_end: day, p_num_days: 1, p_dimension: dim, p_metrics: metrics }) });
    } catch (e) {
      const msg = `${dim}: ${(e instanceof Error ? e.message : String(e)).slice(0, 380)}`;
      await rpc('f360_measurement_run_failed', { p_source_key: 'clarity', p_from: day, p_to: day, p_error: msg }).catch(() => undefined);
      return json({ ok: false, error: msg, done }, 502);
    }
  }
  return json({ ok: true, day, done });
}
