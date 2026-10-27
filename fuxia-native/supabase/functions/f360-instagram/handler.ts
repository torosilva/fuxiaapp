// f360-instagram — reads Instagram organic insights (read-only Graph API) into f360.ig_* through public.f360_instagram_import
// (service role). Callers: pg_cron (Bearer F360_SYNC_SECRET) or an owner.
//   {"action":"daily"}    → account insights of the last 3 days + followers today + metrics of the posts of the last 60 days
//   {"action":"stories"}  → the stories live right now with their insights (they disappear after 24 h; cron every 4 h)
//   {"action":"backfill","from":"YYYY-MM-DD"} → account days from `from` (max 120 per call) + every post since then with its
//      current lifetime metrics. How far back the API answers is recorded as it comes; nothing is invented for older days.
// Without a token (INSTAGRAM_TOKEN, else META_ADS_TOKEN) → 503 and no call to Meta.
import { f360User, serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { safeEqual } from '../_shared/f360-woo/orders.ts';
import { addDays, fetchAccountDay, fetchFollowers, fetchMedia, fetchMediaMetrics, fetchStories, mxToday, toMediaRow, type AccountDay, type MediaRow } from './ig.ts';

export type IgEnv = SupabaseEnv & { INSTAGRAM_TOKEN?: string; META_ADS_TOKEN?: string; INSTAGRAM_USER_ID?: string; META_API_VERSION?: string; F360_SYNC_SECRET?: string };
type Deps = { fetch?: typeof fetch; rpc?: <T>(fn: string, args: Record<string, unknown>) => Promise<T>; now?: Date };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const isDay = (d: unknown): d is string => typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d) && !Number.isNaN(Date.parse(d));
const FUXIA_IG = '17841400765862195';   // @fuxiaballerinas, the instagram_user_id on every Fuxia ad creative (not a secret)

export async function handleInstagram(req: Request, env: IgEnv, deps: Deps = {}) {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!(env.F360_SYNC_SECRET && bearer && safeEqual(bearer, env.F360_SYNC_SECRET))) {
    const u = await f360User(env, bearer);
    if (!u) return json({ error: 'Tu sesión no es válida.' }, 401);
    if (u.role !== 'owner') return json({ error: 'Tu cuenta no tiene permiso para esta acción.' }, 403);
  }
  const token = env.INSTAGRAM_TOKEN || env.META_ADS_TOKEN || '';
  const igUserId = env.INSTAGRAM_USER_ID || FUXIA_IG;
  if (!token || !/^\d{5,25}$/.test(igUserId)) return json({ error: 'Instagram no está configurado.' }, 503);

  const body = (await req.json().catch(() => ({}))) as { action?: string; from?: unknown };
  const action = body.action ?? 'daily';
  const today = mxToday(deps.now);
  const yesterday = addDays(today, -1);
  let from: string; let mediaSince: string; let stories = false;
  if (action === 'daily') { from = addDays(today, -3); mediaSince = addDays(today, -60); }
  else if (action === 'stories') { from = today; mediaSince = today; stories = true; }
  else if (action === 'backfill' && isDay(body.from) && body.from <= yesterday && body.from >= '2020-01-01') {
    from = body.from; mediaSince = body.from;
    if (Date.parse(yesterday) - Date.parse(from) > 119 * 864e5) return json({ error: 'Máximo 120 días por llamada (repite con otra fecha).' }, 400);
  } else return json({ error: 'Acción no válida.' }, 400);

  const f = (deps.fetch ?? fetch) as unknown as Parameters<typeof fetchMedia>[0];
  const rpc = deps.rpc ?? serviceRpc(env);
  const cfg = { token, igUserId, version: env.META_API_VERSION || 'v24.0' };
  const to = stories ? today : yesterday;
  try {
    const account: AccountDay[] = [];
    let oldestAnswered: string | null = null; let refusedBefore: string | null = null;
    if (!stories) {
      for (let d = yesterday; d >= from; d = addDays(d, -1)) {   // newest first: stop at the first day the API refuses (out of its range)
        try { account.push(await fetchAccountDay(f, cfg, d)); oldestAnswered = d; }
        catch (e) { if (/\(code (10|190|200)\)/.test(String(e)) || account.length === 0) throw e; refusedBefore = d; break; }
      }
      const followers = await fetchFollowers(f, cfg);
      account.push({ date: today, followers_count: followers });
    }
    const raw = stories ? await fetchStories(f, cfg) : await fetchMedia(f, cfg, mediaSince);
    const media: MediaRow[] = [];
    for (const m of raw) media.push(toMediaRow(m, await fetchMediaMetrics(f, cfg, m)));
    const res = await rpc('f360_instagram_import', { p_ig_user_id: igUserId, p_from: stories ? today : (account.length ? account.map((a) => a.date).sort()[0] : today),
      p_to: today, p_account: account, p_media: media });
    return json({ ok: true, action, from, to, oldest_day_answered: oldestAnswered, api_refused_from: refusedBefore, result: res });
  } catch (e) {
    const msg = (e instanceof Error ? e.message : String(e)).slice(0, 400);
    await rpc('f360_measurement_run_failed', { p_source_key: 'instagram', p_from: from, p_to: to, p_error: msg }).catch(() => undefined);
    return json({ ok: false, error: msg }, 502);
  }
}
