// Official daily FX → Fuxia 360 observations (base MXN = pesos per 1 unit). Pure helpers + plain GETs; no SDK (Deno and Node).
// Mario 2026-10-11: USD/MXN from Banxico, COP/MXN from a documented public source, captured daily, monthly rate approved by Mario.
//   · USD: Banxico's FIX as published in the Diario Oficial (DOF indicator 158, sidof.segob.gob.mx) — official, no key.
//   · COP: cross via USD = FIX (DOF) ÷ TRM of Banco de la República (datos.gov.co dataset 32sa-8pi3) — both official, no key.
//   · Reference only (never used for a monthly rate): ExchangeRate-API open access, to detect inconsistencies.

export type Obs = { obs_date: string; currency: 'USD' | 'COP'; rate: string; role: 'primary' | 'reference'; method: 'DIRECT' | 'CROSS_USD';
  source: string; source_reference: string; inputs: Record<string, unknown> };
type Fetch = (url: string) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

export const DOF_URL = 'https://sidof.segob.gob.mx/dof/sidof/indicadores/158';
export const TRM_URL = 'https://www.datos.gov.co/resource/32sa-8pi3.json';
export const REF_URL = 'https://open.er-api.com/v6/latest/MXN';
export const SRC_USD = 'FIX de Banxico publicado en el DOF';
export const SRC_COP = 'FIX de Banxico (DOF) ÷ TRM del Banco de la República';
export const SRC_REF = 'ExchangeRate-API (acceso abierto, referencia)';

const dmy = (iso: string) => `${iso.slice(8, 10)}-${iso.slice(5, 7)}-${iso.slice(0, 4)}`;
const iso = (d: string) => (/^\d{2}-\d{2}-\d{4}$/.test(d) ? `${d.slice(6, 10)}-${d.slice(3, 5)}-${d.slice(0, 2)}` : d.slice(0, 10));
const num = (v: unknown) => { const n = Number(v); return Number.isFinite(n) && n > 0 ? n : null; };

export function mxToday(now = new Date()) { return new Date(now.getTime() - 6 * 3600e3).toISOString().slice(0, 10); }
export function addDays(day: string, n: number) { const d = new Date(`${day}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }

async function getJson(f: Fetch, url: string, what: string) {
  const r = await f(url);
  if (!r.ok) throw new Error(`${what} respondió HTTP ${r.status}`);
  return r.json();
}

/** DOF indicator 158 (USD FIX) between two days → [{date, value}] (business days only). */
export async function fetchDof(f: Fetch, from: string, to: string) {
  const url = `${DOF_URL}/${dmy(from)}/${dmy(to)}`;
  const j = (await getJson(f, url, 'DOF')) as { messageCode?: number; ListaIndicadores?: { fecha: string; valor: string; codTipoIndicador: number }[] };
  if (j.messageCode !== 200 || !Array.isArray(j.ListaIndicadores)) throw new Error('DOF: respuesta inesperada');
  return { url, rows: j.ListaIndicadores.filter((x) => x.codTipoIndicador === 158 && num(x.valor)).map((x) => ({ date: iso(x.fecha), value: Number(x.valor) })) };
}

/** TRM (COP per 1 USD) periods overlapping [from, to]. */
export async function fetchTrm(f: Fetch, from: string, to: string) {
  const where = encodeURIComponent(`vigenciahasta >= '${from}' AND vigenciadesde <= '${to}T23:59:59'`);
  const url = `${TRM_URL}?$where=${where}&$order=vigenciadesde&$limit=1000`;
  const j = (await getJson(f, url, 'TRM')) as { valor: string; vigenciadesde: string; vigenciahasta: string }[];
  if (!Array.isArray(j)) throw new Error('TRM: respuesta inesperada');
  return { url, rows: j.filter((x) => num(x.valor)).map((x) => ({ from: iso(x.vigenciadesde), to: iso(x.vigenciahasta), value: Number(x.valor) })) };
}

/** Primary observations: USD on every DOF day; COP on DOF days that have a TRM in force that same day. */
export function buildPrimary(dof: { url: string; rows: { date: string; value: number }[] }, trm: { url: string; rows: { from: string; to: string; value: number }[] }): Obs[] {
  const out: Obs[] = [];
  for (const d of dof.rows) {
    out.push({ obs_date: d.date, currency: 'USD', rate: d.value.toFixed(6), role: 'primary', method: 'DIRECT', source: SRC_USD,
      source_reference: dof.url, inputs: { dof_fecha: d.date, usd_mxn: d.value } });
    const t = trm.rows.find((x) => x.from <= d.date && d.date <= x.to);
    if (t) out.push({ obs_date: d.date, currency: 'COP', rate: (d.value / t.value).toFixed(10), role: 'primary', method: 'CROSS_USD', source: SRC_COP,
      source_reference: `${dof.url} ; ${TRM_URL}`, inputs: { dof_fecha: d.date, usd_mxn: d.value, trm_cop_por_usd: t.value, trm_vigencia: [t.from, t.to] } });
  }
  return out;
}

/** Reference observations (latest only) from ExchangeRate-API: MXN-based, inverted to pesos per unit. */
export async function fetchReference(f: Fetch): Promise<Obs[]> {
  const j = (await getJson(f, REF_URL, 'Referencia')) as { result?: string; time_last_update_unix?: number; rates?: Record<string, number> };
  if (j.result !== 'success' || !j.rates || !j.time_last_update_unix) throw new Error('Referencia: respuesta inesperada');
  const day = new Date(j.time_last_update_unix * 1000).toISOString().slice(0, 10);
  return (['USD', 'COP'] as const).filter((c) => num(j.rates![c])).map((c) => ({ obs_date: day, currency: c, rate: (1 / j.rates![c]).toFixed(10),
    role: 'reference' as const, method: 'DIRECT' as const, source: SRC_REF, source_reference: REF_URL, inputs: { mxn_a_moneda: j.rates![c] } }));
}
