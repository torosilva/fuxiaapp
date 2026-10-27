// Microsoft Clarity data export API (read-only). Verified 2026-10-27: numOfDays only 1–3 (4 and 30 → HTTP 400), no date parameter,
// 10 calls per project per day. So history exists only if each day is captured; one call per breakdown.
type Fetch = (url: string, init?: { headers?: Record<string, string> }) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;
export type ClarityMetric = { metricName: string; information: Record<string, unknown>[] };

export const URL_BASE = 'https://www.clarity.ms/export-data/api/v1/project-live-insights';
/** Daily breakdowns: 3 of the 10 calls a day, leaving 7 for manual questions. */
export const DAILY_DIMENSIONS = ['Source', 'Device', 'URL'] as const;

// Clarity returns full URLs: order-pay links carry the order key (?key=wc_order_…, which opens the order) and ad links carry click
// ids (fbclid, gclid…). Only the path and the utm_* campaign parameters are kept; anything else in the query string is dropped.
const KEEP = new Set(['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term', 'utm_id']);
export function cleanUrl(v: string): string {
  if (!/^https?:\/\//i.test(v)) return v;
  try {
    const u = new URL(v);
    const q = new URLSearchParams([...u.searchParams].filter(([k]) => KEEP.has(k.toLowerCase())));
    return `${u.origin}${u.pathname}${q.size ? `?${q}` : ''}`;
  } catch { return ''; }
}
const clean = (row: Record<string, unknown>) => Object.fromEntries(Object.entries(row).map(([k, v]) => [k, typeof v === 'string' ? cleanUrl(v) : v]));

export function validMetrics(j: unknown): ClarityMetric[] {
  if (!Array.isArray(j)) throw new Error('Clarity: respuesta inesperada.');
  return j.filter((m): m is ClarityMetric => typeof m?.metricName === 'string' && /^[A-Za-z]{2,60}$/.test(m.metricName) && Array.isArray(m.information))
    .map((m) => ({ metricName: m.metricName, information: m.information.slice(0, 2000).map(clean) }));
}

export async function fetchClarity(f: Fetch, token: string, numOfDays: 1 | 2 | 3, dimension: string): Promise<ClarityMetric[]> {
  const q = new URLSearchParams({ numOfDays: String(numOfDays) });
  if (dimension) q.set('dimension1', dimension);
  const r = await f(`${URL_BASE}?${q}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) throw new Error(`Clarity HTTP ${r.status}${r.status === 429 ? ' (se acabaron las 10 llamadas del día)' : r.status === 401 ? ' (token no válido)' : ''}`);
  return validMetrics(await r.json());
}
