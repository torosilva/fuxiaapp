// S-G0 · D3 marketing spend — CSV → rows for public.f360_marketing_spend_upload. Pure (no I/O), shared by the client preview
// and the tests. It only MAPS columns: it never invents a value, never reformats a number and never guesses a missing day.
// The database validates every row again (dates, ids, numbers, currency) and rejects the whole file on any error.
export type SpendRow = {
  date: string; market: string; platform: string; account_id: string; campaign_id: string; campaign_name: string | null;
  adset_id: string | null; adset_name: string | null; ad_id: string | null; ad_name: string | null; creative_id: string | null;
  currency: string; spend: string; impressions: string | null; clicks: string | null;
};
export type ParseResult = { rows: SpendRow[]; errors: string[]; mapped: Record<string, string>; summary: { from: string | null; to: string | null; spend: Record<string, number> } };
/** Values the owner declares for the whole file when the export has no such column (shown in the preview, audited by file). */
export type FileDefaults = { platform: string; account_id?: string; currency?: string; market?: string };

const norm = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
const ALIASES: Record<keyof SpendRow, string[]> = {
  date: ['date', 'day', 'dia', 'fecha', 'reporting starts', 'inicio del informe'],
  market: ['market', 'mercado'],
  platform: ['platform', 'plataforma'],
  account_id: ['account_id', 'account id', 'identificador de la cuenta', 'id de la cuenta'],
  campaign_id: ['campaign_id', 'campaign id', 'identificador de la campana', 'id de la campana'],
  campaign_name: ['campaign_name', 'campaign name', 'nombre de la campana'],
  adset_id: ['adset_id', 'ad set id', 'identificador del conjunto de anuncios', 'id del conjunto de anuncios'],
  adset_name: ['adset_name', 'ad set name', 'nombre del conjunto de anuncios'],
  ad_id: ['ad_id', 'ad id', 'identificador del anuncio', 'id del anuncio'],
  ad_name: ['ad_name', 'ad name', 'nombre del anuncio'],
  creative_id: ['creative_id', 'creative id', 'identificador del contenido', 'identificador del creativo'],
  currency: ['currency', 'moneda', 'divisa'],
  spend: ['spend', 'amount spent', 'importe gastado', 'gasto', 'cost', 'costo'],
  impressions: ['impressions', 'impresiones', 'impr.'],
  clicks: ['clicks', 'clicks (all)', 'clics (todos)', 'link clicks', 'clics en el enlace', 'clics'],
};

/** RFC-4180-ish CSV: quotes, escaped quotes, commas / semicolons / tabs, CRLF, BOM. */
export function parseCsv(text: string): string[][] {
  const src = text.replace(/^﻿/, '');
  const firstLine = src.split(/\r?\n/, 1)[0] ?? '';
  const delim = [',', ';', '\t'].map((d) => ({ d, n: firstLine.split(d).length })).sort((a, b) => b.n - a.n)[0].d;
  const out: string[][] = []; let row: string[] = []; let cell = ''; let q = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (q) {
      if (c === '"' && src[i + 1] === '"') { cell += '"'; i++; } else if (c === '"') q = false; else cell += c;
    } else if (c === '"') q = true;
    else if (c === delim) { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && src[i + 1] === '\n') i++; row.push(cell); out.push(row); row = []; cell = ''; }
    else cell += c;
  }
  if (cell !== '' || row.length) { row.push(cell); out.push(row); }
  return out.filter((r) => r.some((x) => x.trim() !== ''));
}

export function spendRowsFromCsv(text: string, defaults: FileDefaults): ParseResult {
  const errors: string[] = [];
  const table = parseCsv(text);
  const mapped: Record<string, string> = {};
  const empty: ParseResult = { rows: [], errors, mapped, summary: { from: null, to: null, spend: {} } };
  if (table.length < 2) { errors.push('El archivo no tiene filas de datos.'); return empty; }
  const header = table[0].map(norm);
  const col: Partial<Record<keyof SpendRow, number>> = {};
  let headerCurrency: string | null = null;
  for (const key of Object.keys(ALIASES) as (keyof SpendRow)[]) {
    const idx = header.findIndex((h) => ALIASES[key].some((a) => h === a || (key === 'spend' && h.startsWith(a + ' ('))));
    if (idx >= 0) { col[key] = idx; mapped[key] = table[0][idx]; }
  }
  if (col.spend !== undefined) {
    const m = /\(([A-Z]{3})\)\s*$/.exec(table[0][col.spend].trim());
    if (m) headerCurrency = m[1];                                         // "Amount spent (MXN)": the currency is in the file
  }
  for (const req of ['date', 'campaign_id', 'spend'] as const) if (col[req] === undefined) errors.push(`Falta la columna “${req}”.`);
  if (col.account_id === undefined && !defaults.account_id) errors.push('Falta la cuenta publicitaria (columna account_id o el campo “Cuenta”).');
  if (col.currency === undefined && !headerCurrency && !defaults.currency) errors.push('Falta la moneda (columna currency o el campo “Moneda”).');
  if (col.market === undefined && !defaults.market) errors.push('Falta el mercado (columna market o el campo “Mercado”).');
  if (errors.length) return empty;
  const cell = (r: string[], k: keyof SpendRow) => (col[k] === undefined ? '' : (r[col[k]!] ?? '').trim());
  const opt = (r: string[], k: keyof SpendRow) => cell(r, k) || null;
  const rows: SpendRow[] = table.slice(1).map((r) => ({
    date: cell(r, 'date'), market: cell(r, 'market') || defaults.market || '', platform: cell(r, 'platform') || defaults.platform,
    account_id: cell(r, 'account_id') || defaults.account_id || '', campaign_id: cell(r, 'campaign_id'), campaign_name: opt(r, 'campaign_name'),
    adset_id: opt(r, 'adset_id'), adset_name: opt(r, 'adset_name'), ad_id: opt(r, 'ad_id'), ad_name: opt(r, 'ad_name'), creative_id: opt(r, 'creative_id'),
    currency: cell(r, 'currency') || headerCurrency || defaults.currency || '', spend: cell(r, 'spend'),
    impressions: opt(r, 'impressions'), clicks: opt(r, 'clicks'),
  }));
  const dates = rows.map((r) => r.date).filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d)).sort();
  const spend: Record<string, number> = {};
  for (const r of rows) if (/^\d+(\.\d{1,2})?$/.test(r.spend)) spend[r.currency] = Math.round(((spend[r.currency] ?? 0) + Number(r.spend)) * 100) / 100;
  rows.forEach((r, i) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(r.date)) errors.push(`Fila ${i + 1}: fecha “${r.date}” (usa AAAA-MM-DD).`);
    if (!/^\d+(\.\d{1,2})?$/.test(r.spend)) errors.push(`Fila ${i + 1}: gasto “${r.spend}” (número sin símbolos ni comas).`);
  });
  return { rows, errors: errors.slice(0, 20), mapped, summary: { from: dates[0] ?? null, to: dates.at(-1) ?? null, spend } };
}
