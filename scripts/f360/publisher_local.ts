// LOCAL ONLY: serves the f360-woo-publish handler on http://127.0.0.1:8787 so admin-web (localhost) can publish
// to the throwaway Docker WooCommerce, using the STAGING Supabase project. Nothing is deployed.
// Run: scripts/s00a/run.sh ../f360/publisher_local.ts        (run.sh + loadEnv refuse any production target)
// P2.3A: also serves /f360-woo-orders (Woo webhooks) and /f360-woo-sync, and drains the stock queue every 3 s.
// Test-only extra: GET /__deliveries (last raw webhooks, for exact replay). POST /__faults {"faults":["photo","product_crash","variation","stock"]} arms one-shot failures.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { loadEnv } from '../s00a/lib.mjs';
import { handle } from '../../fuxia-native/supabase/functions/f360-woo-publish/handler.ts';
import { withFaults, type Fault } from '../../fuxia-native/supabase/functions/_shared/f360-woo/faults.ts';
import { handleOrders } from '../../fuxia-native/supabase/functions/f360-woo-orders/handler.ts';
import { handleSync, syncAdapter } from '../../fuxia-native/supabase/functions/f360-woo-sync/handler.ts';
import { pushStock } from '../../fuxia-native/supabase/functions/_shared/f360-woo/sync.ts';
import { serviceRpc } from '../../fuxia-native/supabase/functions/_shared/f360-woo/supabase.ts';

const staging = loadEnv();
// Re-read on every request: tools/woo-docker/reset.sh recreates the store with a new application password.
function localWoo() {
  const woo = Object.fromEntries(readFileSync('tools/woo-docker/.env.local', 'utf8').split('\n').filter((l) => l.includes('='))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
  if (!/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(woo.WOO_BASE_URL ?? '')) throw new Error('ABORT: the local publisher only talks to the local Docker Woo.');
  return woo;
}
localWoo();
const env = () => { const woo = localWoo(); return {
  SUPABASE_URL: staging.api, SUPABASE_ANON_KEY: staging.anon, SUPABASE_SERVICE_ROLE_KEY: staging.service,
  WOO_TARGET_KEY: 'woo_local', WOO_BASE_URL: woo.WOO_BASE_URL, WOO_USER: woo.WOO_USER, WOO_SECRET: woo.WOO_SECRET,
  // WordPress runs inside Docker; it downloads photos from the public staging Storage URL (HTTPS), like a real store.
  STORAGE_PUBLIC_BASE: staging.api,
  WOO_WEBHOOK_SECRET: woo.WOO_WEBHOOK_SECRET ?? '',
}; };
const armed = new Set<Fault>();
const wrap = { wrapAdapter: (a: Parameters<typeof withFaults>[0]) => withFaults(a, armed) };
const deliveries: { at: string; headers: Record<string, string>; body: string }[] = [];

// Automatic Fuxia → Woo stock sync (what a scheduler does in a deployed environment).
let draining = false;
async function drain() {
  if (draining) return;
  draining = true;
  try {
    const e = env();
    const r = await pushStock(serviceRpc(e), syncAdapter(e, wrap), 'woo_local');
    if (r.claimed) console.log(`${new Date().toISOString()} stock-sync claimed=${r.claimed} ok=${r.ok} failed=${r.failed}`);
  } catch (err) { console.log(`${new Date().toISOString()} stock-sync error ${(err as Error).message}`); }
  finally { draining = false; }
}
setInterval(drain, 3000);

createServer(async (req, res) => {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  const body = Buffer.concat(chunks);
  if (req.url === '/__faults' && req.method === 'POST') {
    const { faults = [] } = JSON.parse(body.toString() || '{}') as { faults?: Fault[] };
    armed.clear(); for (const f of faults) armed.add(f);
    res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ armed: [...armed] }));
    return;
  }
  if (req.url === '/__deliveries' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(deliveries)); return;
  }
  if (req.url === '/f360-woo-orders' || req.url === '/f360-woo-sync') {
    const headers = Object.fromEntries(Object.entries(req.headers).map(([k, v]) => [k, String(v)]));
    if (req.url === '/f360-woo-orders') { deliveries.unshift({ at: new Date().toISOString(), headers, body: body.toString() }); deliveries.length = Math.min(deliveries.length, 30); }
    const request = new Request(`http://127.0.0.1:8787${req.url}`, { method: req.method, headers, body: req.method === 'POST' ? body : undefined });
    const response = req.url === '/f360-woo-orders' ? await handleOrders(request, env(), { afterApplied: drain }) : await handleSync(request, env(), wrap);
    const text = await response.text();
    console.log(`${new Date().toISOString()} ${req.url} ${headers['x-wc-webhook-topic'] ?? ''} ${response.status} ${text.slice(0, 160)}`);
    res.writeHead(response.status, { 'Content-Type': 'application/json' }); res.end(text);
    return;
  }
  if (req.url !== '/f360-woo-publish') { res.writeHead(404); res.end(); return; }
  const request = new Request(`http://127.0.0.1:8787${req.url}`, { method: req.method, headers: req.headers as Record<string, string>, body: req.method === 'POST' ? body : undefined });
  const t0 = Date.now();
  const response = await handle(request, env(), wrap);
  const text = await response.text();
  let status = '';
  try { const j = JSON.parse(text); status = j.outcome ? `${j.outcome.status}${j.outcome.error ? ` — ${j.outcome.error}` : ''}` : j.error; } catch { /* ignore */ }
  console.log(`${new Date().toISOString()} publish ${response.status} ${status} (${Date.now() - t0} ms)`);
  res.writeHead(response.status, { 'Content-Type': 'application/json' }); res.end(text);
}).listen(8787, '127.0.0.1', () => console.log('f360-woo-publish (LOCAL) on http://127.0.0.1:8787 → staging Supabase + local Docker Woo'));
