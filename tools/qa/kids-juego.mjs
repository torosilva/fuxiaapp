// QA · Fuxia Kids games (mu-plugin f360-kids-juego.php). Phone (iPhone 13) + desktop, MX + CO: menu, "Atrapa las estrellas"
// (touch play, end screen, sends ONE score to the weekly board with a fixed QA device id), "Diseña tus ballerinas" (every step,
// options change the drawing, gift box, "Guardar para mamá" PNG), "El par más parecido", keyboard + pause. Fails on any JS error.
// It buys nothing. Board rows of the QA device are removed with scripts/f360/kids_qa_cleanup.mjs (staging).
// Usage: node tools/qa/kids-juego.mjs <out-dir> [--base https://staging4.fuxiaballerinas.com] [--no-board] [--franja]
import { chromium, devices } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'node:fs';
const OUT = process.argv[2];
const i = process.argv.indexOf('--base'); const BASE = i > 0 ? process.argv[i + 1] : 'https://staging4.fuxiaballerinas.com';
const BOARD = !process.argv.includes('--no-board'), FRANJA = process.argv.includes('--franja');
const QA_DEV = '00000000-0000-4000-8000-0000000000aa';
const b = await chromium.launch();
const errs = []; let fail = 0; const ok = (c, m) => { console.log((c ? '✓ ' : '✗ ') + m); if (!c) fail++; };
const watch = (p) => { p.on('pageerror', (e) => errs.push(String(e))); p.on('console', (m) => { if (m.type() === 'error' && !/favicon|Failed to load resource/.test(m.text())) errs.push(m.text()); }); };
const init = (ctx) => ctx.addInitScript((dev) => { try { sessionStorage.setItem('fx_pop_visto', '1'); localStorage.setItem('f360k_dev', dev); localStorage.setItem('f360k_num', '42'); } catch (e) {} }, QA_DEV);
const tag = FRANJA ? 'franja-' : '';
// the step's main button must not be covered by any fixed element: scroll it just into view (bottom edge, where floating
// buttons live) and ask the browser what is on top at its centre
const libre = async (pg, sel, label) => {
  const r = await pg.locator(sel).first().evaluate((el) => { el.scrollIntoView({ block: 'nearest' }); const b = el.getBoundingClientRect();
    const top = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2); return { free: !!top && (top === el || el.contains(top)), on: top ? (top.id || top.className || top.tagName) : 'nada' }; });
  ok(r.free, `${label}: el botón no queda tapado` + (r.free ? '' : ` (encima: ${String(r.on).slice(0, 40)})`));
};
const flotante = (pg) => pg.evaluate(() => { const b = document.getElementById('fx-app-btn'); return b ? getComputedStyle(b).display !== 'none' : null; });

const ctx = await b.newContext({ ...devices['iPhone 13'], acceptDownloads: true }); await init(ctx);
const p = await ctx.newPage(); watch(p);
for (const pais of ['co', 'mx']) {
  await p.goto(`${BASE}/${pais}/categoria-producto/kids/?nc=${Date.now()}`, { waitUntil: 'networkidle' });
  ok(await p.locator('.f360k').count() === 1, `${pais}: juegos montados (${FRANJA ? 'franja arriba de los productos' : 'menú grande'})`);
  ok(await p.locator('.f360k__card').count() === 2, `${pais}: dos tarjetas para elegir juego`);
  if (FRANJA) ok(await p.locator('.f360k--franja').count() === 1 && await p.locator('ul.products li, .brxe-woocommerce-products .product').count() > 0, `${pais}: franja compacta y debajo los productos de Woo`);
  else ok(await p.locator('.woocommerce-no-products-found').count() === 0, `${pais}: la caja "sin productos" ya no se ve`);
}
await p.locator('.f360k').scrollIntoViewIfNeeded(); await p.waitForTimeout(900);
await p.screenshot({ path: `${OUT}/${tag}1-menu.png` });
const fl0 = await flotante(p); if (fl0 !== null) ok(fl0, 'menú: el botón "Descarga la app" se ve en el menú');

// ── Atrapa las estrellas
await p.locator('.f360k__card[data-go="estrellas"]').tap();
await libre(p, '.f360k__over[data-k="inicio"] [data-a="jugar"]', 'estrellas · Jugar');
const fl1 = await flotante(p); if (fl0 !== null) ok(fl1 === false, 'juego abierto: el botón flotante de la app se oculta');
await p.locator('.f360k__estrellas [data-a="jugar"]').first().tap();
const box = await p.locator('.f360k__cv').boundingBox();
const t0 = Date.now(); let shot = false;
while (Date.now() - t0 < 7000) {
  const x = await p.evaluate(() => { const s = document.querySelector('.f360k').f360k.stars.state(); const q = s.stars.filter((z) => z.y < .9).sort((a, c) => c.y - a.y)[0]; return q ? q.x : .5; });
  await p.touchscreen.tap(box.x + x * box.width, box.y + box.height * .8);
  if (!shot && Date.now() - t0 > 4000) { await p.screenshot({ path: `${OUT}/${tag}2-estrellas.png` }); shot = true; }
  await p.waitForTimeout(100);
}
const st = await p.evaluate(() => { const s = document.querySelector('.f360k').f360k.stars.state(); return { t: +s.t.toFixed(1), score: s.score, running: s.running }; });
ok(st.running && st.t > 5, `estrellas: se juega (${st.t} s, ${st.score} estrellas)`);
await p.evaluate(() => { document.querySelector('.f360k').f360k.stars.state().t = 49.95; });
await p.waitForTimeout(700);
ok(await p.locator('.f360k__over[data-k="fin"]:not([hidden])').count() === 1, 'estrellas: pantalla final');
await libre(p, '.f360k__over[data-k="fin"] [data-a="subir"]', 'estrellas · Subir al tablero');
if (BOARD) {
  await p.locator('.f360k__name').selectOption('Perla Rosa');
  await p.locator('[data-a="subir"]').tap();
  await p.waitForFunction(() => /Subiste|No se pudo|muchas/.test(document.querySelector('.f360k__sent').textContent), null, { timeout: 15000 });
  const sent = await p.locator('.f360k__sent').textContent();
  ok(/Subiste como Perla Rosa 42/.test(sent), `tablero: ${sent}`);
  ok(await p.locator('.f360k__board--fin li.is-me').count() >= 1, 'tablero: su nombre aparece resaltado en el top 10');
}
await p.locator('.f360k__over[data-k="fin"]').evaluate((e) => e.scrollTo(0, 0));
await p.screenshot({ path: `${OUT}/${tag}3-fin-tablero.png` });

// ── Diseña tus ballerinas
await p.locator('.f360k__over[data-k="fin"] [data-go="home"]').tap();
await p.locator('.f360k__card[data-go="disena"]').tap(); await p.waitForTimeout(500);
const shoeHtml = () => p.locator('.f360k__stage .f360k__shoe').first().evaluate((e) => e.outerHTML.length + ':' + e.getAttribute('aria-label'));
const a0 = await shoeHtml();
await p.locator('.f360k__opt[data-o="plata"]').tap(); const a1 = await shoeHtml();
ok(a0 !== a1 && /Plata/.test(a1), 'diseña: la piel cambia el dibujo en vivo (plata metálico)');
await p.screenshot({ path: `${OUT}/${tag}4-disena-piel.png` });
await libre(p, '.f360k__stage [data-s="1"]', 'diseña paso 1 · Siguiente');
await p.locator('[data-s="1"]').tap(); await p.waitForTimeout(200);
for (const tira of ['fruncido', 'doble', 'esferas']) {
  await p.locator(`.f360k__opt[data-o="${tira}"]`).tap(); await p.waitForTimeout(150);
  await p.locator('.f360k__stage').evaluate((e) => window.scrollTo(0, e.getBoundingClientRect().top + window.scrollY - 130));
  await p.screenshot({ path: `${OUT}/${tag}4b-paso2-${tira}.png` });
}
ok(/esferas/i.test(await shoeHtml()), 'diseña: tira de esferas');
await libre(p, '.f360k__stage [data-s="1"]', 'diseña paso 2 · Siguiente');
await p.screenshot({ path: `${OUT}/${tag}4c-paso2-botones.png` });
await p.locator('[data-s="1"]').tap(); await p.locator('.f360k__opt[data-o="perlas"]').tap();
ok(/Perlas/.test(await shoeHtml()), 'diseña: adorno perlas');
await p.locator('.f360k__stage').evaluate((e) => window.scrollTo(0, e.getBoundingClientRect().top + window.scrollY - 130));
await p.screenshot({ path: `${OUT}/${tag}5-disena-adorno.png` });
await libre(p, '.f360k__stage [data-s="1"]', 'diseña paso 3 · Ponerlas en su estuche');
await p.locator('[data-s="1"]').tap(); await p.waitForTimeout(300);
await p.locator('.f360k__name2').selectOption('Luna de Plata');
ok(/Luna de Plata/.test(await p.locator('.f360k__box').innerHTML()), 'diseña: el estuche lleva su nombre de bailarina');
await p.waitForFunction(() => !/Buscando/.test(document.querySelector('.f360k__parbody').textContent), null, { timeout: 15000 });
const par = (await p.locator('.f360k__parbody').innerText()).replace(/\s+/g, ' ');
ok(FRANJA ? /Verlo/i.test(par) : /Muy pronto en Fuxia Kids/.test(par), `diseña: el par más parecido → "${par.slice(0, 80)}"`);
await libre(p, '.f360k__stage [data-a="guardar"]', 'estuche · Guardar para mamá');
const [dl] = await Promise.all([p.waitForEvent('download', { timeout: 15000 }).catch(() => null), p.locator('[data-a="guardar"]').tap()]);
if (dl) { await dl.saveAs(`${OUT}/${tag}guardar-para-mama.png`); const sz = fs.statSync(`${OUT}/${tag}guardar-para-mama.png`).size; ok(sz > 50000, `guardar para mamá: PNG descargado (${Math.round(sz / 1024)} KB)`); }
else ok(false, 'guardar para mamá: no se descargó el PNG');
await p.locator('.f360k__stage').evaluate((e) => window.scrollTo(0, e.getBoundingClientRect().top + window.scrollY - 130));
await p.screenshot({ path: `${OUT}/${tag}6-estuche.png` });
await p.locator('[data-a="guardar"]').first().evaluate((el) => el.scrollIntoView({ block: 'nearest' }));
await p.screenshot({ path: `${OUT}/${tag}6b-estuche-botones.png` });
await p.locator('.f360k__disena [data-go="home"]').first().tap(); await p.waitForTimeout(300);
if (fl0 !== null) ok(await flotante(p) === true, 'de vuelta en el menú: el botón de la app vuelve a aparecer');

// ── desktop: keyboard + pause
const dctx = await b.newContext({ viewport: { width: 1280, height: 900 } }); await init(dctx);
const d = await dctx.newPage(); watch(d);
await d.goto(`${BASE}/mx/categoria-producto/kids/?nc=${Date.now()}`, { waitUntil: 'networkidle' });
await d.locator('.f360k').scrollIntoViewIfNeeded(); await d.waitForTimeout(600);
await d.screenshot({ path: `${OUT}/${tag}7-escritorio-menu.png` });
await d.locator('.f360k__card[data-go="estrellas"]').click();
await d.locator('.f360k__estrellas [data-a="jugar"]').first().click(); await d.waitForTimeout(300);
const x0 = await d.evaluate(() => document.querySelector('.f360k').f360k.stars.state().px);
await d.keyboard.down('ArrowRight'); await d.waitForTimeout(700); await d.keyboard.up('ArrowRight');
const x1 = await d.evaluate(() => document.querySelector('.f360k').f360k.stars.state().px);
await d.keyboard.press('Escape'); await d.waitForTimeout(250);
ok(x1 > x0 + .05 && await d.locator('.f360k__over[data-k="pausa"]:not([hidden])').count() === 1, `escritorio: flechas mueven (${x0.toFixed(2)}→${x1.toFixed(2)}) y Esc pausa`);
await d.locator('.f360k__estrellas [data-go="home"]').first().click();
await d.locator('.f360k__card[data-go="disena"]').click(); await d.waitForTimeout(400);
await d.locator('.f360k__disena').scrollIntoViewIfNeeded();
await d.screenshot({ path: `${OUT}/${tag}8-escritorio-disena.png` });
ok(errs.length === 0, 'sin errores de JavaScript' + (errs.length ? ': ' + errs.join(' | ').slice(0, 300) : ''));
await b.close();
console.log(fail ? `FALLÓ ${fail}` : 'OK');
process.exit(fail ? 1 : 0);
