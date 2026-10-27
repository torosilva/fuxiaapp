// Instagram Graph API (read-only) → Fuxia 360 rows. Pure helpers + paginated GETs; no SDK (Deno and Node).
// Needs a token whose system user has the Instagram account assigned and the permissions instagram_basic +
// instagram_manage_insights (+ pages_read_engagement). Without them every call answers "missing permissions" and nothing is stored.
// What is stored is what the API returns: a metric it does not return stays null (never 0).

type Fetch = (url: string) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;
export type IgCfg = { token: string; igUserId: string; version: string };
export type Kind = 'post' | 'carousel' | 'reel' | 'story';
export type AccountDay = { date: string; followers_count?: number | null; reach?: number | null; views?: number | null; profile_views?: number | null;
  website_clicks?: number | null; accounts_engaged?: number | null; total_interactions?: number | null; follows?: number | null; unfollows?: number | null };
export type Metrics = Partial<Record<'reach' | 'views' | 'likes' | 'comments' | 'saves' | 'shares' | 'total_interactions' | 'replies' | 'profile_visits' | 'follows' | 'avg_watch_ms', number | null>>;
export type MediaRow = { media_id: string; kind: Kind; media_type: string | null; media_product_type: string | null; posted_at: string;
  permalink: string | null; shortcode: string | null; caption: string | null; metrics?: Metrics };
type RawMedia = { id: string; media_type?: string; media_product_type?: string; timestamp: string; permalink?: string; caption?: string };
type RawInsight = { name: string; values?: { value: unknown; end_time?: string }[]; total_value?: { value?: unknown; breakdowns?: { results?: { dimension_values?: string[]; value?: unknown }[] }[] } };

export const ACCOUNT_METRICS = ['reach', 'views', 'profile_views', 'website_clicks', 'accounts_engaged', 'total_interactions', 'follows_and_unfollows'];
// Per kind; Meta refuses a request that names a metric the media type does not support, so each set is the documented one.
export const MEDIA_METRICS: Record<Kind, string[]> = {
  post: ['reach', 'views', 'likes', 'comments', 'saved', 'shares', 'total_interactions', 'profile_visits', 'follows'],
  carousel: ['reach', 'views', 'likes', 'comments', 'saved', 'shares', 'total_interactions'],
  reel: ['reach', 'views', 'likes', 'comments', 'saved', 'shares', 'total_interactions', 'ig_reels_avg_watch_time'],
  story: ['reach', 'views', 'replies', 'shares', 'total_interactions', 'profile_visits', 'follows'],
};
const RENAME: Record<string, keyof Metrics> = { saved: 'saves', ig_reels_avg_watch_time: 'avg_watch_ms' };

export const addDays = (d: string, n: number) => new Date(Date.parse(`${d}T00:00:00Z`) + n * 864e5).toISOString().slice(0, 10);
export const mxToday = (now = new Date()) => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Mexico_City' }).format(now);
const unix = (d: string) => Math.floor(Date.parse(`${d}T00:00:00-06:00`) / 1000);   // CDMX midnight (no DST since 2022)
const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.trunc(v) : null);

export function kindOf(m: Pick<RawMedia, 'media_type' | 'media_product_type'>): Kind {
  if (m.media_product_type === 'STORY') return 'story';
  if (m.media_product_type === 'REELS') return 'reel';
  if (m.media_type === 'CAROUSEL_ALBUM') return 'carousel';
  return 'post';
}

export function shortcodeOf(permalink?: string | null): string | null {
  const m = /instagram\.com\/(?:[\w.]+\/)?(?:p|reel|reels|tv|stories\/[\w.]+)\/([A-Za-z0-9_-]{5,40})/.exec(permalink ?? '');
  return m ? m[1] : null;
}

export function toMediaRow(m: RawMedia, metrics?: Metrics): MediaRow {
  const permalink = m.permalink && /^https:\/\/(www\.)?instagram\.com\//.test(m.permalink) ? m.permalink : null;
  return { media_id: String(m.id), kind: kindOf(m), media_type: m.media_type ?? null, media_product_type: m.media_product_type ?? null,
    posted_at: m.timestamp, permalink, shortcode: shortcodeOf(permalink), caption: m.caption ? m.caption.slice(0, 2200) : null, metrics };
}

/** Insights of one media → our metric names. Watch time comes in ms already. Unknown names are ignored. */
export function toMetrics(data: RawInsight[]): Metrics {
  const out: Metrics = {};
  for (const x of data) {
    const key = (RENAME[x.name] ?? x.name) as keyof Metrics;
    const v = num(x.total_value?.value ?? x.values?.[0]?.value);
    if (['reach', 'views', 'likes', 'comments', 'saves', 'shares', 'total_interactions', 'replies', 'profile_visits', 'follows', 'avg_watch_ms'].includes(key)) out[key] = v;
  }
  return out;
}

/** One day of account insights (metric_type=total_value) → AccountDay. follows_and_unfollows splits by follow type. */
export function toAccountDay(date: string, data: RawInsight[]): AccountDay {
  const day: AccountDay = { date };
  for (const x of data) {
    if (x.name === 'follows_and_unfollows') {
      for (const b of x.total_value?.breakdowns ?? []) for (const r of b.results ?? []) {
        const t = (r.dimension_values ?? [])[0];
        if (t === 'FOLLOWER') day.follows = num(r.value);
        if (t === 'NON_FOLLOWER') day.unfollows = num(r.value);
      }
    } else if (ACCOUNT_METRICS.includes(x.name)) {
      (day as Record<string, unknown>)[x.name] = num(x.total_value?.value ?? x.values?.[0]?.value);
    }
  }
  return day;
}

async function get(fetchFn: Fetch, url: string): Promise<Record<string, unknown>> {
  const r = await fetchFn(url);
  const j = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  if (!r.ok) {   // Meta's message never contains the token; the URL (which does) is never echoed
    const err = (j.error ?? {}) as { message?: string; code?: number };
    const hint = err.code === 10 || err.code === 100 || err.code === 190 || err.code === 200 ? ' · revisa que el usuario del sistema tenga la cuenta de Instagram y los permisos instagram_basic + instagram_manage_insights' : '';
    throw new Error(`Instagram HTTP ${r.status}${err.code ? ` (code ${err.code})` : ''}: ${(err.message ?? 'sin detalle').slice(0, 160)}${hint}`);
  }
  return j;
}
const base = (cfg: IgCfg) => `https://graph.facebook.com/${cfg.version}`;

export async function fetchFollowers(f: Fetch, cfg: IgCfg): Promise<number | null> {
  const j = await get(f, `${base(cfg)}/${cfg.igUserId}?${new URLSearchParams({ fields: 'followers_count', access_token: cfg.token })}`);
  return num(j.followers_count);
}

export async function fetchAccountDay(f: Fetch, cfg: IgCfg, date: string): Promise<AccountDay> {
  const q = new URLSearchParams({ metric: ACCOUNT_METRICS.join(','), metric_type: 'total_value', period: 'day', breakdown: 'follow_type',
    since: String(unix(date)), until: String(unix(addDays(date, 1))), access_token: cfg.token });
  const j = await get(f, `${base(cfg)}/${cfg.igUserId}/insights?${q}`);
  return toAccountDay(date, (j.data as RawInsight[]) ?? []);
}

/** Feed media newest first, down to `since` (YYYY-MM-DD, CDMX). */
export async function fetchMedia(f: Fetch, cfg: IgCfg, since: string): Promise<RawMedia[]> {
  const q = new URLSearchParams({ fields: 'id,media_type,media_product_type,timestamp,permalink,caption', limit: '50', access_token: cfg.token });
  let url: string | undefined = `${base(cfg)}/${cfg.igUserId}/media?${q}`;
  const out: RawMedia[] = []; const stop = unix(since) * 1000;
  for (let page = 0; url; page++) {
    if (page > 100) throw new Error('Instagram: demasiadas páginas.');
    const j = await get(f, url);
    const data = (j.data as RawMedia[]) ?? [];
    for (const m of data) { if (Date.parse(m.timestamp) < stop) return out; out.push(m); }
    url = (j.paging as { next?: string } | undefined)?.next;
  }
  return out;
}

export async function fetchStories(f: Fetch, cfg: IgCfg): Promise<RawMedia[]> {
  const q = new URLSearchParams({ fields: 'id,media_type,media_product_type,timestamp,permalink,caption', access_token: cfg.token });
  return ((await get(f, `${base(cfg)}/${cfg.igUserId}/stories?${q}`)).data as RawMedia[]) ?? [];
}

/** Lifetime insights of one media. A media Meta refuses (too old, copyright, deleted) keeps no metrics instead of failing the run. */
export async function fetchMediaMetrics(f: Fetch, cfg: IgCfg, m: RawMedia): Promise<Metrics | undefined> {
  const q = new URLSearchParams({ metric: MEDIA_METRICS[kindOf(m)].join(','), access_token: cfg.token });
  try { return toMetrics(((await get(f, `${base(cfg)}/${m.id}/insights?${q}`)).data as RawInsight[]) ?? []); }
  catch (e) { if (/\(code (10|190|200)\)/.test(String(e))) throw e; return undefined; }   // permission errors stop the run
}
