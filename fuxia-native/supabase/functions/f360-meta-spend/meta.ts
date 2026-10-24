// Meta Marketing API (read-only, ads_read) → Fuxia 360 spend rows. Pure helpers + one paginated GET; no SDK (Deno and Node).
// Rows are campaign × day × market. Market = the country Meta reports for the impressions (MX, CO; any other → ROW).
// Also what META says it sold (pixel purchases, their value and add-to-carts, Meta's own attribution): shown next to the real paid
// orders in Growth → Campañas, never used as sales.

type Action = { action_type?: string; value?: string };
export type Insight = { date_start: string; campaign_id: string; campaign_name?: string; country?: string; spend?: string; impressions?: string; clicks?: string;
  actions?: Action[]; action_values?: Action[] };
export type SpendRow = { date: string; market: 'MX' | 'CO' | 'ROW' | 'UNKNOWN'; account_id: string; campaign_id: string; campaign_name: string | null;
  currency: string; spend: string; impressions: string; clicks: string; meta_purchases: string; meta_purchase_value: string; meta_add_to_cart: string };

const PURCHASE = 'offsite_conversion.fb_pixel_purchase';
const ADD_TO_CART = 'offsite_conversion.fb_pixel_add_to_cart';
const action = (list: Action[] | undefined, type: string) => (list ?? []).find((a) => a.action_type === type)?.value;
type Fetch = (url: string) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

export function marketOf(country?: string): SpendRow['market'] {
  const c = (country ?? '').toUpperCase();
  if (c === 'MX' || c === 'CO') return c;
  return /^[A-Z]{2}$/.test(c) ? 'ROW' : 'UNKNOWN';
}

const cents = (v?: string) => Math.round(Number(v ?? 0) * 100);
const int = (v?: string) => Math.trunc(Number(v ?? 0)) || 0;

/** Sums Meta's per-country rows into campaign × day × market; drops rows with no spend and no impressions. */
export function toSpendRows(insights: Insight[], accountId: string, currency: string): SpendRow[] {
  const by = new Map<string, { r: Omit<SpendRow, 'spend' | 'impressions' | 'clicks' | 'meta_purchases' | 'meta_purchase_value' | 'meta_add_to_cart'>;
    c: number; i: number; k: number; p: number; v: number; a: number }>();
  for (const x of insights) {
    const market = marketOf(x.country);
    const key = `${x.date_start}|${x.campaign_id}|${market}`;
    const e = by.get(key) ?? { r: { date: x.date_start, market, account_id: accountId, campaign_id: String(x.campaign_id),
      campaign_name: x.campaign_name?.slice(0, 300) || null, currency }, c: 0, i: 0, k: 0, p: 0, v: 0, a: 0 };
    e.c += cents(x.spend); e.i += int(x.impressions); e.k += int(x.clicks);
    e.p += int(action(x.actions, PURCHASE)); e.v += cents(action(x.action_values, PURCHASE)); e.a += int(action(x.actions, ADD_TO_CART));
    by.set(key, e);
  }
  return [...by.values()].filter((e) => e.c > 0 || e.i > 0 || e.p > 0)
    .map((e) => ({ ...e.r, spend: (e.c / 100).toFixed(2), impressions: String(e.i), clicks: String(e.k),
      meta_purchases: String(e.p), meta_purchase_value: (e.v / 100).toFixed(2), meta_add_to_cart: String(e.a) }))
    .sort((a, b) => a.date.localeCompare(b.date) || a.campaign_id.localeCompare(b.campaign_id) || a.market.localeCompare(b.market));
}

/** Today's date in Mexico City (the ad account's time zone) as YYYY-MM-DD. */
export const mxToday = (now = new Date()) => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Mexico_City' }).format(now);

export const addDays = (d: string, n: number) => new Date(Date.parse(`${d}T00:00:00Z`) + n * 864e5).toISOString().slice(0, 10);

/** Splits [from, to] into consecutive windows of at most `size` days. */
export function windows(from: string, to: string, size = 31): Array<[string, string]> {
  const out: Array<[string, string]> = [];
  for (let a = from; a <= to; a = addDays(a, size)) { const b = addDays(a, size - 1); out.push([a, b < to ? b : to]); }
  return out;
}

export type MetaCfg = { token: string; accountId: string; version: string };

async function get(fetchFn: Fetch, url: string): Promise<Record<string, unknown>> {
  const r = await fetchFn(url);
  const j = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  if (!r.ok) {   // Meta's message never contains the token; the URL (which does) is never echoed
    const err = (j.error ?? {}) as { message?: string; code?: number };
    throw new Error(`Meta HTTP ${r.status}${err.code ? ` (code ${err.code})` : ''}: ${(err.message ?? 'sin detalle').slice(0, 200)}`);
  }
  return j;
}

export async function accountCurrency(fetchFn: Fetch, cfg: MetaCfg): Promise<string> {
  const q = new URLSearchParams({ fields: 'currency', access_token: cfg.token });
  const j = await get(fetchFn, `https://graph.facebook.com/${cfg.version}/act_${cfg.accountId}?${q}`);
  const c = String(j.currency ?? '');
  if (!/^[A-Z]{3}$/.test(c)) throw new Error('Meta: la cuenta no reporta moneda.');
  return c;
}

export async function fetchInsights(fetchFn: Fetch, cfg: MetaCfg, from: string, to: string): Promise<Insight[]> {
  const q = new URLSearchParams({ level: 'campaign', time_increment: '1', breakdowns: 'country', limit: '500',
    time_range: JSON.stringify({ since: from, until: to }), fields: 'campaign_id,campaign_name,spend,impressions,clicks,actions,action_values', access_token: cfg.token });
  let url: string | undefined = `https://graph.facebook.com/${cfg.version}/act_${cfg.accountId}/insights?${q}`;
  const out: Insight[] = [];
  for (let page = 0; url; page++) {
    if (page > 200) throw new Error('Meta: demasiadas páginas.');
    const j = await get(fetchFn, url);
    out.push(...((j.data as Insight[]) ?? []));
    url = (j.paging as { next?: string } | undefined)?.next;
  }
  return out;
}
