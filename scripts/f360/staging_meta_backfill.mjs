// STAGING ONLY: re-reads Meta Ads (read-only Marketing API, same code as the f360-meta-spend function) for a date range and
// imports it into STAGING through public.f360_marketing_spend_api_import (service role). Used to verify "Meta dice" with real
// numbers and to rehearse a gap backfill (e.g. 2026-10-11..13). Token: ~/.fuxia-meta-ads.token (never printed).
// Run: scripts/s00a/run.sh ../f360/staging_meta_backfill.mjs 2026-10-01 2026-10-23
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { loadEnv } from '../s00a/lib.mjs';
import { accountCurrency, fetchInsights, toSpendRows, windows } from '../../fuxia-native/supabase/functions/f360-meta-spend/meta.ts';

const env = loadEnv();
const [from, to] = process.argv.slice(2);
if (!/^\d{4}-\d{2}-\d{2}$/.test(from ?? '') || !/^\d{4}-\d{2}-\d{2}$/.test(to ?? '') || from > to) throw new Error('uso: staging_meta_backfill.mjs AAAA-MM-DD AAAA-MM-DD');
const cfg = { token: readFileSync(`${homedir()}/.fuxia-meta-ads.token`, 'utf8').trim(), accountId: '966161362834783', version: 'v24.0' };
for (const [a, b] of windows(from, to)) {
  const currency = await accountCurrency(fetch, cfg);
  const rows = toSpendRows(await fetchInsights(fetch, cfg, a, b), cfg.accountId, currency);
  const r = await fetch(`${env.api}/rest/v1/rpc/f360_marketing_spend_api_import`, {
    method: 'POST', headers: { apikey: env.service, Authorization: `Bearer ${env.service}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_platform: 'meta', p_account_id: cfg.accountId, p_currency: currency, p_from: a, p_to: b, p_rows: rows }) });
  const j = await r.json().catch(() => null);
  const buys = rows.reduce((s, x) => s + Number(x.meta_purchases), 0);
  console.log(`${a}..${b}: ${rows.length} filas, Meta dice ${buys} compras →`, r.status, j?.result ?? j?.message ?? j);
}
