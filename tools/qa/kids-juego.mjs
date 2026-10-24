// QA · Fuxia Kids "Atrapa las estrellas" (mu-plugin f360-kids-juego.php). Plays it on a phone (touch drags chasing stars),
// jumps to the end screen, checks the keyboard + pause on desktop, and fails on any JS error. Reads only; buys nothing.
// Usage: node tools/qa/kids-juego.mjs <out-dir> [--base https://staging4.fuxiaballerinas.com]
import { chromium, devices } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
const OUT = process.argv[2];
const i = process.argv.indexOf('--base'); const BASE = i > 0 ? process.argv[i + 1] : 'https://staging4.fuxiaballerinas.com';
const b = await chromium.launch();
const errs = []; let fail = 0;
const watch = (p) => { p.on('pageerror', (e) => errs.push(String(e))); };
const ctx = await b.newContext({ ...devices['iPhone 13'] });
await ctx.addInitScript(() => { try { sessionStorage.setItem('fx_pop_visto', '1'); } catch (e) {} });
const p = await ctx.newPage(); watch(p);
for (const pais of ['co', 'mx']) {
  await p.goto(`${BASE}/${pais}/categoria-producto/kids/?nc=${Date.now()}`, { waitUntil: 'networkidle' });
  const n = await p.locator('.f360k').count();
  console.log(pais, '· juego montado:', n, '· caja "sin productos" restante:', await p.locator('.woocommerce-no-products-found').count());
  if (n !== 1) fail++;
}
await p.locator('.f360k').scrollIntoViewIfNeeded(); await p.waitForTimeout(800);
await p.screenshot({ path: `${OUT}/1-inicio.png` });
await p.locator('.f360k [data-a="jugar"]').first().tap();
const box = await p.locator('.f360k__cv').boundingBox();
const t0 = Date.now(); let shot = false;
while (Date.now() - t0 < 8000) {
  const x = await p.evaluate(() => { const s = document.querySelector('.f360k').f360k.state(); const q = s.stars.filter((z) => z.y < .9).sort((a, c) => c.y - a.y)[0]; return q ? q.x : .5; });
  await p.touchscreen.tap(box.x + x * box.width, box.y + box.height * .8);
  if (!shot && Date.now() - t0 > 4500) { await p.screenshot({ path: `${OUT}/2-jugando.png` }); shot = true; }
  await p.waitForTimeout(100);
}
const st = await p.evaluate(() => { const s = document.querySelector('.f360k').f360k.state(); return { t: +s.t.toFixed(1), score: s.score, level: s.level, running: s.running }; });
console.log('tras 8 s jugando:', JSON.stringify(st));
if (!st.running || st.t < 6) fail++;
await p.evaluate(() => { document.querySelector('.f360k').f360k.state().t = 49.95; });
await p.waitForTimeout(700);
const fin = await p.locator('.f360k__card[data-k="fin"]:not([hidden])').count();
console.log('pantalla final:', fin, '· estrellas:', await p.locator('.f360k__score').textContent(), '·', await p.locator('.f360k__card[data-k="fin"] .f360k__best').textContent());
if (fin !== 1) fail++;
await p.screenshot({ path: `${OUT}/3-fin.png` });
const d = await (await b.newContext({ viewport: { width: 1280, height: 900 } })).newPage(); watch(d);
await d.goto(`${BASE}/mx/categoria-producto/kids/?nc=${Date.now()}`, { waitUntil: 'networkidle' });
await d.locator('.f360k [data-a="jugar"]').first().click();
await d.waitForTimeout(300);
const x0 = await d.evaluate(() => document.querySelector('.f360k').f360k.state().px);
await d.keyboard.down('ArrowRight'); await d.waitForTimeout(700); await d.keyboard.up('ArrowRight');
const x1 = await d.evaluate(() => document.querySelector('.f360k').f360k.state().px);
await d.keyboard.press('Escape'); await d.waitForTimeout(250);
const pz = await d.locator('.f360k__card[data-k="pausa"]:not([hidden])').count();
console.log('teclado: x', x0.toFixed(2), '→', x1.toFixed(2), '· pausa con Esc:', pz);
if (!(x1 > x0 + .05) || pz !== 1) fail++;
await d.locator('.f360k').scrollIntoViewIfNeeded();
await d.screenshot({ path: `${OUT}/4-escritorio-pausa.png` });
console.log('errores JS:', errs.length ? errs : 'ninguno');
await b.close();
if (errs.length || fail) { console.log('FALLÓ', fail); process.exit(1); }
console.log('OK');
