// GA4 Data API (read-only) → f360.ga4_funnel rows. Company service account (fuxia360-lectura@fuxia360-datos), Lector on property
// 519011849. Signs its own JWT with WebCrypto (Deno and Node), no SDK. People per funnel step for the last 14 complete days and the
// 14 before, per market (country) and GA4 channel group; a second report without the channel gives the distinct total ('TODOS').
type Fetch = (url: string, init?: { method?: string; headers?: Record<string, string>; body?: string }) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;
export type SaKey = { client_email: string; private_key: string };
export type FunnelRow = { period: 'actual' | 'anterior'; date_from: string; date_to: string; market: 'MX' | 'CO' | 'ROW'; channel: string; step: string; users: number };

export const STEPS = ['session_start', 'view_item', 'add_to_cart', 'begin_checkout', 'purchase'];
export const marketOf = (country: string): 'MX' | 'CO' | 'ROW' => (country === 'Mexico' ? 'MX' : country === 'Colombia' ? 'CO' : 'ROW');
export const addDays = (d: string, n: number) => new Date(Date.parse(`${d}T00:00:00Z`) + n * 864e5).toISOString().slice(0, 10);

/** Windows ending yesterday (CDMX): actual = 14 days, anterior = the 14 before. */
export function windows(today: string) {
  const to = addDays(today, -1);
  return { actual: { from: addDays(to, -13), to }, anterior: { from: addDays(to, -27), to: addDays(to, -14) } };
}

/** The secret is the key JSON, or the same JSON in base64 (one line, as deploy_prod_function.sh stores it). */
export function parseKey(raw: string): SaKey {
  const t = raw.trim();
  const k = JSON.parse(t.startsWith('{') ? t : new TextDecoder().decode(Uint8Array.from(atob(t), (c) => c.charCodeAt(0)))) as Partial<SaKey>;
  if (!k.client_email || !k.private_key?.includes('PRIVATE KEY')) throw new Error('GA4: la llave de la cuenta de servicio no es válida.');
  return { client_email: k.client_email, private_key: k.private_key };
}

const b64url = (b: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof b === 'string' ? new TextEncoder().encode(b) : new Uint8Array(b as ArrayBuffer);
  let s = ''; for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

export async function accessToken(f: Fetch, key: SaKey, now = Date.now()): Promise<string> {
  const iat = Math.floor(now / 1000);
  const unsigned = `${b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64url(JSON.stringify({ iss: key.client_email,
    scope: 'https://www.googleapis.com/auth/analytics.readonly', aud: 'https://oauth2.googleapis.com/token', iat, exp: iat + 3600 }))}`;
  const der = Uint8Array.from(atob(key.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')), (c) => c.charCodeAt(0));
  const k = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', k, new TextEncoder().encode(unsigned));
  const r = await f('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${unsigned}.${b64url(sig)}` });
  const j = (await r.json().catch(() => ({}))) as { access_token?: string; error?: string };
  if (!r.ok || !j.access_token) throw new Error(`GA4: Google no dio acceso (HTTP ${r.status}${j.error ? `, ${j.error}` : ''}).`);
  return j.access_token;
}

type Report = { dimensionHeaders?: { name: string }[]; rows?: { dimensionValues: { value: string }[]; metricValues: { value: string }[] }[] };

export async function runReport(f: Fetch, token: string, property: string, body: unknown): Promise<Report> {
  const r = await f(`https://analyticsdata.googleapis.com/v1beta/properties/${property}:runReport`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const j = (await r.json().catch(() => ({}))) as Report & { error?: { message?: string } };
  if (!r.ok) throw new Error(`GA4 HTTP ${r.status}: ${(j.error?.message ?? 'sin detalle').slice(0, 200)}`);
  return j;
}

export function reportBody(w: ReturnType<typeof windows>, withChannel: boolean) {
  return {
    dateRanges: [{ startDate: w.actual.from, endDate: w.actual.to, name: 'actual' }, { startDate: w.anterior.from, endDate: w.anterior.to, name: 'anterior' }],
    dimensions: [{ name: 'country' }, ...(withChannel ? [{ name: 'sessionDefaultChannelGroup' }] : []), { name: 'eventName' }],
    metrics: [{ name: 'totalUsers' }],
    dimensionFilter: { filter: { fieldName: 'eventName', inListFilter: { values: STEPS } } },
    limit: 10000,
  };
}

/** Report → rows. Countries outside MX/CO are summed into ROW per channel (people from different countries are different people). */
export function toRows(rep: Report, w: ReturnType<typeof windows>, withChannel: boolean): FunnelRow[] {
  const names = (rep.dimensionHeaders ?? []).map((h) => h.name);
  const acc = new Map<string, FunnelRow>();
  for (const row of rep.rows ?? []) {
    const d = Object.fromEntries(names.map((n, i) => [n, row.dimensionValues[i]?.value ?? '']));
    const period = d.dateRange === 'anterior' ? 'anterior' : 'actual';
    if (!STEPS.includes(d.eventName)) continue;
    const channel = withChannel ? (d.sessionDefaultChannelGroup || 'Unassigned').replace(/[^A-Za-zÁÉÍÓÚáéíóúñ /()-]/g, '').slice(0, 60) || 'Unassigned' : 'TODOS';
    const market = marketOf(d.country);
    const key = [period, market, channel, d.eventName].join('|');
    const users = Math.max(0, Math.trunc(Number(row.metricValues[0]?.value) || 0));
    const prev = acc.get(key);
    if (prev) prev.users += users;
    else acc.set(key, { period, date_from: w[period].from, date_to: w[period].to, market, channel, step: d.eventName, users });
  }
  return [...acc.values()];
}
