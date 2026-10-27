// STAGING ONLY · Growth P0: runs the f360-instagram / f360-clarity handlers locally (same code as the Edge Functions) against the
// real APIs and writes into STAGING (service role). Tokens: ~/.fuxia-meta-ads.token, ~/.fuxia-clarity.token (never printed).
// Why local: staging has no API tokens on purpose (Clarity allows 10 calls a day per project, shared by every environment), and the
// nightly prod→staging copy wipes staging tables — so each Clarity answer is ALSO kept as a file and re-imported after the copy.
//   scripts/s00a/run.sh ../f360/staging_growth_p0_capture.mjs instagram         → one daily read (records the API answer, ok or not)
//   scripts/s00a/run.sh ../f360/staging_growth_p0_capture.mjs clarity           → today's capture (3 calls) → files + staging
//   scripts/s00a/run.sh ../f360/staging_growth_p0_capture.mjs clarity-reimport  → every saved file back into staging (0 calls)
// Files: ~/fuxia360-respaldos/clarity/<YYYY-MM-DD>/<Source|Device|URL>.json (the history until the prod pase; then imported there).
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { loadEnv } from '../s00a/lib.mjs';
import { handleInstagram } from '../../fuxia-native/supabase/functions/f360-instagram/handler.ts';
import { handleClarity, mxToday } from '../../fuxia-native/supabase/functions/f360-clarity/handler.ts';
import { validMetrics } from '../../fuxia-native/supabase/functions/f360-clarity/clarity.ts';

const env = loadEnv();
const mode = process.argv[2];
const DIR = `${homedir()}/fuxia360-respaldos/clarity`;
const base = { SUPABASE_URL: env.api, SUPABASE_SERVICE_ROLE_KEY: env.service, F360_SYNC_SECRET: 'local-run' };
const req = (body) => new Request('http://local', { method: 'POST', headers: { Authorization: 'Bearer local-run' }, body: JSON.stringify(body) });
const rpc = async (fn, args) => {
  const r = await fetch(`${env.api}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: env.service, Authorization: `Bearer ${env.service}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw new Error(`${fn}: ${j?.message ?? r.status}`);
  return j;
};

if (mode === 'instagram') {
  const token = readFileSync(`${homedir()}/.fuxia-meta-ads.token`, 'utf8').trim();
  const r = await handleInstagram(req({ action: 'daily' }), { ...base, META_ADS_TOKEN: token }, { rpc });
  console.log(r.status, JSON.stringify(await r.json()));
} else if (mode === 'clarity') {
  const token = readFileSync(`${homedir()}/.fuxia-clarity.token`, 'utf8').trim();
  const day = mxToday();
  mkdirSync(`${DIR}/${day}`, { recursive: true });
  const saving = async (url, init) => {   // keep the answer (already cleaned: no order keys / click ids) as a file
    const r = await fetch(url, init);
    const body = await r.json().catch(() => null);
    const dim = new URL(url).searchParams.get('dimension1') ?? 'total';
    if (r.ok) writeFileSync(`${DIR}/${day}/${dim}.json`, JSON.stringify({ captured_at: new Date().toISOString(), num_days: 1, dimension: dim, metrics: validMetrics(body) }));
    return { ok: r.ok, status: r.status, json: async () => body };
  };
  const r = await handleClarity(req({ action: 'daily' }), { ...base, CLARITY_API_TOKEN: token }, { rpc, fetch: saving });
  console.log(r.status, JSON.stringify(await r.json()));
} else if (mode === 'clarity-reimport') {
  if (!existsSync(DIR)) { console.log('Sin archivos todavía.'); process.exit(0); }
  for (const day of readdirSync(DIR).filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d)).sort()) {
    for (const f of readdirSync(`${DIR}/${day}`).filter((x) => x.endsWith('.json'))) {
      const s = JSON.parse(readFileSync(`${DIR}/${day}/${f}`, 'utf8'));
      s.metrics = validMetrics(s.metrics);   // files are re-cleaned on every import
      const res = await rpc('f360_clarity_import', { p_window_end: day, p_num_days: s.num_days, p_dimension: s.dimension === 'total' ? '' : s.dimension, p_metrics: s.metrics });
      console.log(day, s.dimension, JSON.stringify(res));
    }
  }
} else {
  throw new Error('uso: staging_growth_p0_capture.mjs instagram | clarity | clarity-reimport');
}
