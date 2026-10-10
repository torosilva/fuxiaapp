#!/usr/bin/env node
// P0D PRE-IMPORT RECONCILIATION — READ ONLY. Nothing is written to WooCommerce, to production or to staging.
//   · WooCommerce production: GET /orders with `_fields` limited to id, status, currency, totals, dates, payment method id and
//     refund totals (no billing / shipping / customer data ever requested).
//   · Fuxia 360 production: one read-only SELECT through scripts/f360/prod_read.sh (BEGIN READ ONLY).
//   · Fuxia 360 staging: read-only SELECT (staging4 copy) for comparison.
// Output: per country/currency/status counts and money, and one line per order with the expected P0D action.
// Usage (repo root): node scripts/f360/p0d_preflight.mjs [--since 2026-06-01] > docs/fuxia360/growth/P0D_PREFLIGHT.md
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const SINCE = arg('--since', '2026-06-01');
const env = Object.fromEntries(readFileSync(`${homedir()}/.fuxia-woo-prod.env`, 'utf8').split('\n')
  .map((l) => l.replace(/^export\s+/, '').match(/^([A-Z_]+)=(.*)$/)).filter(Boolean).map((m) => [m[1], m[2].replace(/^['"]|['"]$/g, '')]));
const base = env.WOO_PROD_BASE_URL.replace(/\/+$/, '');
if (!/^https:\/\/(www\.)?fuxiaballerinas\.com$/.test(base)) throw new Error('ABORT: the production store is not the expected host');
const auth = 'Basic ' + Buffer.from(`${env.WOO_PROD_USER}:${env.WOO_PROD_SECRET}`).toString('base64');
const FIELDS = 'id,status,currency,total,date_created_gmt,date_paid_gmt,payment_method,created_via,refunds';

async function wooGet(path) {   // GET only, by construction
  const r = await fetch(`${base}/wp-json/wc/v3${path}`, { method: 'GET', headers: { Authorization: auth, Accept: 'application/json' }, signal: AbortSignal.timeout(60_000) });
  if (!r.ok) throw new Error(`Woo HTTP ${r.status}`);
  return r.json();
}
const woo = [];
for (let page = 1; page < 50; page++) {
  const rows = await wooGet(`/orders?status=any&orderby=id&order=asc&per_page=100&page=${page}&after=${SINCE}T00:00:00&dates_are_gmt=true&_fields=${FIELDS}`);
  woo.push(...rows);
  if (rows.length < 100) break;
}

const sh = (file, sql) => execFileSync(file, [], { input: sql, encoding: 'utf8' });
const prodRaw = sh('scripts/f360/prod_read.sh', `SELECT coalesce(jsonb_agg(jsonb_build_object('id', o.woo_order_id, 'status', o.woo_status, 'total', o.order_total, 'via', o.first_captured_via)), '[]') AS facts,
  (SELECT orders_since_id FROM f360.sales_targets WHERE key = 'woo_production') AS cutover
  FROM f360.commerce_woo_orders o JOIN f360.sales_targets t ON t.id = o.target_id AND t.key = 'woo_production'`);
const prod = JSON.parse(prodRaw)[0];
const prodFacts = new Map(prod.facts.map((o) => [o.id, o]));
const psql = process.env.PSQL ?? '/opt/homebrew/opt/libpq/bin/psql';
const stagingRows = execFileSync(psql, [process.env.STAGING_DB_URL, '-At', '-F', '|', '-c',
  "select o.woo_order_id, o.woo_status, o.order_total from f360.commerce_woo_orders o join f360.sales_targets t on t.id = o.target_id and t.key = 'woo_staging4'"], { encoding: 'utf8' });
const staging = new Map(stagingRows.trim().split('\n').filter(Boolean).map((l) => { const [id, st, tot] = l.split('|'); return [Number(id), { status: st, total: Number(tot) }]; }));

const MARKET = { MXN: 'MX', COP: 'CO', USD: 'ROW' };
const PAID = new Set(['processing', 'completed', 'on-hold', 'refunded']);
const cutover = prod.cutover ?? null;
const lines = woo.map((o) => {
  const refund = (o.refunds ?? []).reduce((s, r) => s + Math.abs(Number(r.total) || 0), 0);
  const inFacts = prodFacts.get(o.id);
  const st = staging.get(o.id);
  const action = cutover !== null && o.id > cutover ? 'después del corte: lo captura el tiempo real'
    : inFacts ? (inFacts.status === o.status ? 'ya está en producción (sin cambio)' : 'ya está; se actualizaría el estado')
    : 'P0D lo importaría';
  return { id: o.id, date: (o.date_created_gmt ?? '').slice(0, 10), market: MARKET[o.currency] ?? '¿?', currency: o.currency, status: o.status,
    paid: !!o.date_paid_gmt || PAID.has(o.status), total: Number(o.total) || 0, refund, method: o.payment_method || '—', via: o.created_via || '—',
    staging: st ? (st.status === o.status && Math.abs(st.total - Number(o.total)) < 0.01 ? 'igual' : `distinto (${st.status} ${st.total})`) : 'no está', action };
});

const money = (n, c) => `${c} ${n.toLocaleString('es-MX', { maximumFractionDigits: 2 })}`;
const out = [];
out.push(`# P0D · Conciliación previa a la importación del historial (SOLO LECTURA)`, '',
  `> Generado ${new Date().toISOString()} con \`scripts/f360/p0d_preflight.mjs --since ${SINCE}\`. WooCommerce producción: solo GET con campos sin datos personales.`,
  `> Fuxia 360 producción: SELECT de solo lectura. **Nada se importó.** Corte de tiempo real (orders_since_id): ${cutover ?? 'sin corte'}.`, '',
  `## Resumen por país, moneda y estado`, '', '| País | Moneda | Estado Woo | Pedidos | Con pago | Total | Reembolsos | P0D importaría |', '|---|---|---|---|---|---|---|---|');
const key = (l) => `${l.market}|${l.currency}|${l.status}`;
const groups = new Map();
for (const l of lines) { const g = groups.get(key(l)) ?? { ...l, n: 0, paid: 0, total: 0, refund: 0, imp: 0 }; g.n++; g.paid += l.paid ? 1 : 0; g.total += l.total; g.refund += l.refund; g.imp += l.action === 'P0D lo importaría' ? 1 : 0; groups.set(key(l), g); }
for (const g of [...groups.values()].sort((a, b) => key(a).localeCompare(key(b))))
  out.push(`| ${g.market} | ${g.currency} | ${g.status} | ${g.n} | ${g.paid} | ${money(g.total, g.currency)} | ${money(g.refund, g.currency)} | ${g.imp} |`);
const byCur = {};
for (const l of lines) { const c = (byCur[l.currency] ??= { n: 0, paidTotal: 0 }); c.n++; if (l.paid && !['cancelled', 'failed'].includes(l.status)) c.paidTotal += l.total - l.refund; }
out.push('', `**Totales:** ${lines.length} pedidos en Woo desde ${SINCE} · ${lines.filter((l) => l.action === 'P0D lo importaría').length} los importaría P0D · ${lines.filter((l) => l.action.startsWith('ya está')).length} ya están en producción · ${lines.filter((l) => l.action.startsWith('después')).length} posteriores al corte.`,
  `**Pagado neto aproximado por moneda (pagados no cancelados − reembolsos; referencia, no es la métrica de Growth):** ${Object.entries(byCur).map(([c, v]) => money(v.paidTotal, c)).join(' · ')}`,
  `**Comparación con la copia de staging4:** ${lines.filter((l) => l.staging === 'igual').length} iguales · ${lines.filter((l) => l.staging.startsWith('distinto')).length} distintos · ${lines.filter((l) => l.staging === 'no está').length} no están en staging.`,
  '', `> País por moneda (MXN→MX, COP→CO, USD→resto). Commerce Facts además usa la ruta de la tienda; si difieren, el import lo marca como "market_conflict".`,
  '', '## Pedido por pedido', '', '| Pedido | Fecha (UTC) | País | Moneda | Estado | Con pago | Total | Reembolso | Método | Creado por | En staging | Acción P0D |', '|---|---|---|---|---|---|---|---|---|---|---|---|');
for (const l of lines) out.push(`| ${l.id} | ${l.date} | ${l.market} | ${l.currency} | ${l.status} | ${l.paid ? 'sí' : 'no'} | ${money(l.total, l.currency)} | ${l.refund ? money(l.refund, l.currency) : '—'} | ${l.method} | ${l.via} | ${l.staging} | ${l.action} |`);
console.log(out.join('\n'));
