// P2.3B PREFLIGHT — READ-ONLY checks of a WooCommerce STAGING store before connecting Fuxia 360 to it.
// Never writes. Refuses production hosts. Prints no credentials.
//
//   node scripts/f360/p23b_preflight.mjs tools/siteground-staging.env      (real SiteGround staging, HTTPS)
//   node scripts/f360/p23b_preflight.mjs tools/woo-docker/.env.local --local   (self-test against the local Docker store)
//
// Env file keys: WOO_BASE_URL, WOO_USER (ck_… Woo REST key), WOO_SECRET (cs_…), STAGING_WOO_HOST (exact host expected),
//                PRODUCTION_WOO_HOSTS (comma list of the REAL store hosts — refused).
import { readFileSync } from 'node:fs';

const [file, flag] = process.argv.slice(2);
if (!file) { console.error('usage: p23b_preflight.mjs <env-file> [--local]'); process.exit(2); }
const local = flag === '--local';
const E = Object.fromEntries(readFileSync(file, 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
const url = new URL(E.WOO_BASE_URL);
const prodHosts = (E.PRODUCTION_WOO_HOSTS ?? '').split(',').map((h) => h.trim().toLowerCase()).filter(Boolean);

// ── Guards ──
if (local) {
  if (!['localhost', '127.0.0.1'].includes(url.hostname)) throw new Error('--local only for localhost');
} else {
  if (url.protocol !== 'https:') throw new Error('ABORT: staging store must use HTTPS');
  if (!prodHosts.length) throw new Error('ABORT: set PRODUCTION_WOO_HOSTS so production can be refused');
  if (prodHosts.includes(url.hostname.toLowerCase())) throw new Error('ABORT: this is a PRODUCTION host');
  if (!E.STAGING_WOO_HOST || url.hostname.toLowerCase() !== E.STAGING_WOO_HOST.toLowerCase()) throw new Error('ABORT: host does not match STAGING_WOO_HOST');
}

const auth = 'Basic ' + Buffer.from(`${E.WOO_USER}:${E.WOO_SECRET}`).toString('base64');
const base = `${E.WOO_BASE_URL.replace(/\/+$/, '')}/wp-json`;
async function get(path, withAuth = true) {
  const r = await fetch(`${base}${path}`, { headers: withAuth ? { Authorization: auth } : {}, signal: AbortSignal.timeout(30_000) });
  let j = null; try { j = await r.json(); } catch { /* not json */ }
  return { status: r.status, j, headers: r.headers };
}
const rows = [];
const out = (status, check, detail = '') => rows.push({ status, check, detail });

// 1 · Reachability + REST
const root = await get('/', false).catch((e) => ({ status: 0, j: null, error: e.message }));
out(root.status === 200 ? 'PASS' : 'FAIL', 'REST API reachable (/wp-json)', `HTTP ${root.status}`);
out(url.protocol === 'https:' ? 'PASS' : (local ? 'SKIP' : 'FAIL'), 'HTTPS', local ? 'local self-test over http (must be https on SiteGround)' : url.protocol);

// 2 · Authorization header reaches WordPress (SiteGround/Cloudflare sometimes strip it)
const sys = await get('/wc/v3/system_status');
out(sys.status === 200 ? 'PASS' : 'FAIL', 'Woo REST key accepted (Authorization header passes through)', `HTTP ${sys.status}${sys.status === 401 ? ' — key wrong or header stripped' : ''}`);
if (sys.status === 200) {
  const env = sys.j.environment ?? {}, settings = sys.j.settings ?? {}, theme = sys.j.theme ?? {};
  const plugins = (sys.j.active_plugins ?? []).map((p) => `${p.plugin}`.toLowerCase());
  const has = (re) => plugins.filter((p) => re.test(p));
  out('INFO', 'Versions', `WordPress ${env.wp_version} · WooCommerce ${env.version} · PHP ${env.php_version}`);
  out(/bricks/i.test(theme.name ?? '') ? 'PASS' : (local ? 'INFO' : 'WARN'), 'Theme', `${theme.name} ${theme.version ?? ''}`);
  out(has(/facebook-for-woocommerce|meta/).length ? 'FAIL' : 'PASS', 'Meta / Facebook for WooCommerce DISABLED (DW6)', has(/facebook|meta/).join(', ') || 'not active');
  out('INFO', 'Cache plugins', has(/sg-cachepress|speed-optimizer|cache|rocket|litespeed/).join(', ') || 'none detected');
  out('INFO', 'Swatch / variation plugins', has(/swatch|variation/).join(', ') || 'none detected');
  out('INFO', 'Country pricing (WCPBC, DW5)', has(/price-based-on-country|wcpbc/).join(', ') || 'none detected');
  out(env.wp_cron === false && !local ? 'WARN' : 'INFO', 'WP-Cron (webhooks are delivered by Action Scheduler/cron)', `wp_cron=${env.wp_cron}`);
  out(settings.currency === 'MXN' ? 'PASS' : 'WARN', 'Currency', `${settings.currency} · decimals ${settings.number_of_decimals ?? '?'}`);
}

// 3 · Catalog structure the publisher relies on
const attrs = await get('/wc/v3/products/attributes');
const color = attrs.j?.find?.((a) => a.slug === 'pa_color'), size = attrs.j?.find?.((a) => a.slug === 'pa_medida');
out(color ? 'PASS' : 'FAIL', 'Global attribute pa_color', color ? `id ${color.id}` : 'missing');
out(size ? 'PASS' : 'FAIL', 'Global attribute pa_medida', size ? `id ${size.id}` : 'missing');
if (size) {
  const t = await get(`/wc/v3/products/attributes/${size.id}/terms?per_page=100`);
  const names = (t.j ?? []).map((x) => x.name);
  const missing = ['35', '36', '37', '38', '39', '40'].filter((s) => !names.includes(s));
  out(missing.length ? 'WARN' : 'PASS', 'Size terms 35–40 exist', missing.length ? `missing ${missing.join(',')} (publisher would create them)` : 'all present');
}
if (color) {
  const t = await get(`/wc/v3/products/attributes/${color.id}/terms?per_page=100`);
  out('INFO', 'pa_color terms / order', `${(t.j ?? []).map((x) => x.name).join(', ')} (order_by=${color.order_by})`);
}
const cats = await get('/wc/v3/products/categories?per_page=100');
for (const slug of ['ballerinas', 'sandalia-plana', 'sandalia-alta', 'botas']) {
  const c = (cats.j ?? []).find((x) => x.slug === slug);
  out(c ? 'PASS' : 'FAIL', `Category ${slug}`, c ? `ID ${c.id} → record in f360.woo_category_links` : 'missing');
}

// 4 · Inventory settings that decide sold-out behavior on the PDP
const prodSettings = await get('/wc/v3/settings/products');
const val = (id) => (prodSettings.j ?? []).find?.((s) => s.id === id)?.value;
out(val('woocommerce_manage_stock') === 'yes' ? 'PASS' : 'FAIL', 'Stock management enabled', `woocommerce_manage_stock=${val('woocommerce_manage_stock')}`);
out('INFO', 'Hide out-of-stock items (affects sold-out sizes, L2)', `woocommerce_hide_out_of_stock_items=${val('woocommerce_hide_out_of_stock_items')}`);

// 5 · Webhooks for Fuxia 360 orders
const hooks = await get('/wc/v3/webhooks?per_page=100');
const f360 = (hooks.j ?? []).filter((h) => /f360-woo-orders/.test(h.delivery_url));
out(f360.length ? 'PASS' : 'WARN', 'Fuxia 360 order webhooks', f360.map((h) => `${h.topic} ${h.status} ${h.delivery_url.startsWith('https://') ? 'https' : (local ? 'http (local only)' : 'NOT-HTTPS')}`).join(' · ') || 'not created yet');
out('INFO', 'Other webhooks (loyalty etc.)', (hooks.j ?? []).filter((h) => !/f360-woo-orders/.test(h.delivery_url)).map((h) => `${h.topic}→${new URL(h.delivery_url).hostname} (${h.status})`).join(' · ') || 'none');

// 6 · Existing F360 products
const f = await get('/wc/v3/products?status=any&per_page=100&orderby=id&order=desc');
out('INFO', 'Products with F360 SKUs already in this store', (f.j ?? []).filter((p) => p.sku?.startsWith('F360-')).map((p) => `${p.sku} (${p.status})`).join(', ') || 'none');

const w = Math.max(...rows.map((r) => r.check.length));
for (const r of rows) console.log(`${r.status.padEnd(4)}  ${r.check.padEnd(w)}  ${r.detail}`);
const fails = rows.filter((r) => r.status === 'FAIL').length;
console.log(`\n${fails ? `${fails} FAIL — fix before connecting Fuxia 360` : 'No blocking failures'} (read-only; nothing was changed)`);
process.exit(fails ? 1 : 0);
