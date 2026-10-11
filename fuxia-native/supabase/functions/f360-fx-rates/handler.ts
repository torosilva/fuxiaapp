// f360-fx-rates — reads official daily exchange rates into f360.fx_observations through public.f360_fx_observations_record
// (service role) and proposes the monthly rate (f360_fx_month_propose). Approval stays with a person (f360.fx_approvers).
// Callers: pg_cron daily (Bearer F360_SYNC_SECRET) or an owner.
//   {"action":"daily"}                               → the last 10 days (sources publish late / revise) + reference + propose last month
//   {"action":"backfill","from":"YYYY-MM-DD","to":…}  → history (max 400 days)
//   {"action":"propose","month":"YYYY-MM-01"}        → propose that (closed) month again if it has no live rate
import { f360User, serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { safeEqual } from '../_shared/f360-woo/orders.ts';
import { addDays, buildPrimary, fetchDof, fetchReference, fetchTrm, mxToday } from './fx.ts';

export type FxEnv = SupabaseEnv & { F360_SYNC_SECRET?: string };
type Deps = { fetch?: typeof fetch; rpc?: <T>(fn: string, args: Record<string, unknown>) => Promise<T>; now?: Date };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const isDay = (d: unknown): d is string => typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d) && !Number.isNaN(Date.parse(d));

export async function handleFx(req: Request, env: FxEnv, deps: Deps = {}) {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!(env.F360_SYNC_SECRET && token && safeEqual(token, env.F360_SYNC_SECRET))) {
    const u = await f360User(env, token);
    if (!u) return json({ error: 'Tu sesión no es válida.' }, 401);
    if (u.role !== 'owner') return json({ error: 'Tu cuenta no tiene permiso para esta acción.' }, 403);
  }
  const body = (await req.json().catch(() => ({}))) as { action?: string; from?: unknown; to?: unknown; month?: unknown };
  const today = mxToday(deps.now);
  const rpc = deps.rpc ?? serviceRpc(env);
  const f = (deps.fetch ?? fetch) as unknown as Parameters<typeof fetchDof>[0];
  const action = body.action ?? 'daily';

  if (action === 'propose') {
    if (!isDay(body.month) || body.month.slice(8) !== '01') return json({ error: 'Mes no válido (YYYY-MM-01).' }, 400);
    return json({ ok: true, proposed: await rpc('f360_fx_month_propose', { p_month: body.month }) });
  }
  let from: string; let to = today;
  if (action === 'daily') from = addDays(today, -10);
  else if (action === 'backfill' && isDay(body.from) && body.from >= '2020-01-01' && body.from <= today) {
    from = body.from; to = isDay(body.to) && body.to <= today && body.to >= from ? body.to : today;
    if (Date.parse(to) - Date.parse(from) > 400 * 864e5) return json({ error: 'Máximo 400 días por llamada.' }, 400);
  } else return json({ error: 'Acción no válida.' }, 400);

  try {
    const rows = buildPrimary(await fetchDof(f, from, to), await fetchTrm(f, from, to));
    let reference: unknown[] = []; let refError: string | null = null;
    if (action === 'daily') { try { reference = await fetchReference(f); } catch (e) { refError = (e as Error).message.slice(0, 200); } }
    const recorded = await rpc('f360_fx_observations_record', { p_from: from, p_to: to, p_rows: [...rows, ...reference] });
    // on the first days of a month, propose the month that just closed (idempotent: skips a month that already has a live rate)
    const proposed = action === 'daily' && Number(today.slice(8)) <= 5
      ? await rpc('f360_fx_month_propose', { p_month: `${addDays(`${today.slice(0, 8)}01`, -1).slice(0, 8)}01` }) : null;
    return json({ ok: true, from, to, primary: rows.length, reference: reference.length, reference_error: refError, recorded, proposed });
  } catch (e) {
    const msg = (e instanceof Error ? e.message : String(e)).slice(0, 400);
    await rpc('f360_measurement_run_failed', { p_source_key: 'fx_rates', p_from: from, p_to: to, p_error: msg }).catch(() => undefined);
    return json({ ok: false, error: msg }, 502);
  }
}
