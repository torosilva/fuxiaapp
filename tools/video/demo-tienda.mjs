// Demo video · staging4 storefront (phone). Captions + tap marks are injected into the page only for the recording.
import { chromium, devices } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs';
const OUT = process.argv[2];
const compra = fs.readFileSync('/Users/bullsilva/Documents/GitHub/fuxiaapp/tools/storefront/f360-compra.html', 'utf8').replace(/<!--[\s\S]*?-->/, '');
const W = 390, H = 844;
const b = await chromium.launch();
const ctx = await b.newContext({ ...devices['iPhone 13'], viewport: { width: W, height: H }, deviceScaleFactor: 2 });
await ctx.route(/staging4\.fuxiaballerinas\.com\/(?!wp-json|wp-admin|wp-content|\?wc-ajax).*/, async (route) => {
  const req = route.request(); if (req.resourceType() !== 'document') return route.continue();
  const resp = await route.fetch(); if (!/text\/html/.test(resp.headers()['content-type'] || '')) return route.fulfill({ response: resp });
  let body = await resp.text();
  body = body.replace(/5 a 7 días hábiles/g, '10 días hábiles');                                   // latest copy
  body = body.replace(/<div class="f360-ag"[\s\S]*?<script>\s*\/\* Fuxia 360 · CRO-CHECKOUT[\s\S]*?<\/script>/, '');   // the installed copy (markup + code)
  const k = body.lastIndexOf('</body>'); if (k > 0) body = body.slice(0, k) + compra + body.slice(k);
  route.fulfill({ response: resp, body });
});
await ctx.addInitScript(() => {
  try { sessionStorage.setItem('fx_pop_visto', '1'); } catch (e) {}
  const css = `#f360cap{position:fixed;left:12px;right:12px;top:12px;z-index:2147483647;padding:12px 16px;border-radius:14px;background:rgba(29,29,27,.92);color:#fff;
    font:600 16px/1.35 -apple-system,Montserrat,sans-serif;text-align:center;box-shadow:0 8px 24px rgba(0,0,0,.25);transition:opacity .3s;pointer-events:none}
    #f360cap small{display:block;margin-top:3px;font-weight:400;font-size:13px;opacity:.85}
    #f360card{position:fixed;inset:0;z-index:2147483647;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;background:#fffdf9;color:#242424;
    font:500 28px/1.2 -apple-system,Montserrat,sans-serif;text-align:center;padding:30px}
    #f360card b{color:#83734C;font-size:14px;letter-spacing:.2em;text-transform:uppercase}
    #f360card p{font-size:16px;color:#6B6B68;margin:0;line-height:1.45}
    .f360tap{position:fixed;z-index:2147483646;width:44px;height:44px;margin:-22px 0 0 -22px;border-radius:50%;background:rgba(184,150,110,.45);border:2px solid #B8966E;pointer-events:none;animation:f360tap .7s ease-out forwards}
    @keyframes f360tap{from{transform:scale(.4);opacity:1}to{transform:scale(1.4);opacity:0}}
    .f360-blur{filter:blur(6px) !important}`;
  addEventListener('DOMContentLoaded', () => { const s = document.createElement('style'); s.textContent = css; document.head.appendChild(s); });
  addEventListener('pointerdown', (e) => { const d = document.createElement('div'); d.className = 'f360tap'; d.style.left = e.clientX + 'px'; d.style.top = e.clientY + 'px'; document.body.appendChild(d); setTimeout(() => d.remove(), 800); }, true);
  window.__cap = (t, sub) => { let c = document.getElementById('f360cap'); if (!c) { c = document.createElement('div'); c.id = 'f360cap'; document.body.appendChild(c); }
    if (!t) { c.style.opacity = 0; return; } c.style.opacity = 1; c.innerHTML = ''; c.appendChild(document.createTextNode(t)); if (sub) { const s = document.createElement('small'); s.textContent = sub; c.appendChild(s); } };
  window.__card = (kicker, title, text) => { let c = document.getElementById('f360card'); if (!kicker) { if (c) c.remove(); return; }
    if (!c) { c = document.createElement('div'); c.id = 'f360card'; document.body.appendChild(c); } c.innerHTML = '<b></b><div></div><p></p>';
    c.children[0].textContent = kicker; c.children[1].textContent = title; c.children[2].textContent = text || ''; };
});
const p = await ctx.newPage();
fs.rmSync(OUT + '/shots', { recursive: true, force: true }); fs.mkdirSync(OUT + '/shots');
const cdp = await ctx.newCDPSession(p);
cdp.on('Page.screencastFrame', async (f) => {
  fs.writeFileSync(`${OUT}/shots/${f.metadata.timestamp.toFixed(3)}.jpg`, Buffer.from(f.data, 'base64'));
  cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }).catch(() => {});
});
await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 92, everyNthFrame: 1 });
const wait = (ms) => p.waitForTimeout(ms);
const cap = (t, sub) => p.evaluate(([t, sub]) => window.__cap(t, sub), [t, sub || '']);
const card = (k, t, x) => p.evaluate(([k, t, x]) => window.__card(k, t, x), [k, t, x || '']);
const scrollTo = (y, ms = 900) => p.evaluate(([y, ms]) => new Promise((r) => { const s = scrollY, t0 = performance.now();
  const f = (n) => { const k = Math.min(1, (n - t0) / ms), e = k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2; scrollTo(0, s + (y - s) * e); k < 1 ? requestAnimationFrame(f) : r(); }; requestAnimationFrame(f); }), [y, ms]);
const tap = async (sel, opts = {}) => { const l = typeof sel === 'string' ? p.locator(sel).first() : sel; await l.scrollIntoViewIfNeeded().catch(() => {}); await wait(250); await l.click(opts); };
const go = async (url) => { await p.goto(url, { waitUntil: 'networkidle', timeout: 90000 }); await p.evaluate(() => { document.querySelector('#fx-pop-overlay')?.classList.remove('fx-visible'); }); };
const BASE = 'https://staging4.fuxiaballerinas.com/mx/';

// 0 · intro
await go(BASE);
await card('Fuxia 360', 'La tienda en línea de Fuxia', 'Así compra una clienta desde su celular (ambiente de pruebas)');
await wait(3500); await card();
// 1 · home + welcome popup
await cap('Llega desde Instagram', 'Portada de la tienda'); await wait(2500);
await scrollTo(900, 1500); await wait(800);
await p.evaluate(() => document.getElementById('fx-pop-overlay')?.classList.add('fx-visible'));
await cap('Bienvenida: 10% en su primera compra', '+50 puntos Club Fuxia si deja su WhatsApp'); await wait(4000);
await p.evaluate(() => document.getElementById('fx-pop-overlay')?.classList.remove('fx-visible')); await wait(600);
// 2 · shop: search + filters
await go(BASE + 'tienda/');
await cap('Encuentra su modelo', 'Buscador con sugerencias'); await wait(1500);
await tap('.f360-t-buscar'); await p.keyboard.type('bot', { delay: 180 }); await wait(2500);
await p.keyboard.press('Escape'); await p.fill('.f360-t-buscar', ''); await p.evaluate(() => document.activeElement.blur()); await wait(500);
await cap('Filtros por color, talla mexicana y entrega inmediata'); await tap('.f360-t-toggle'); await wait(1500);
await tap('.f360-t-colores .f360-t-chip'); await wait(900);
await tap(p.locator('.f360-t-tallas .f360-t-chip').nth(2)); await wait(1500);
await tap('.f360-t-ver'); await wait(2200);
await tap('.f360-t-res button').catch(() => {}); await wait(800);
// 3 · best sellers / new
await cap('Más vendidas y Nuevas', 'Ventas de tiendas + en línea, calculadas por Fuxia 360');
const railY = await p.evaluate(() => { const r = document.querySelector('.f360-t-rails'); return r ? r.getBoundingClientRect().top + scrollY - 120 : 0; });
await scrollTo(railY, 2200); await wait(3500);
// 4 · product page
await go(BASE + 'producto/botas-largas/');
await cap('Ficha de producto', 'Fotos, precio y colores que carga Carolina en Fuxia 360'); await wait(3000);
const tallasY = await p.evaluate(() => { const t = document.querySelector('.f360-colores') || document.querySelector('.fuxia-tallas'); return t ? t.getBoundingClientRect().top + scrollY - 160 : 600; });
await scrollTo(tallasY, 1400);
await cap('Tallas mexicanas', 'Elige color y talla'); await wait(1200);
await tap('.f360-colores-botones .f360-color'); await wait(900);
await tap(p.locator('.fuxia-tallas-botones .fuxia-talla:visible').nth(2)); await wait(1200);
await cap('Entrega inmediata en Zona Metropolitana', 'Las tiendas también son bodegas'); await wait(1000);
const inmY = await p.evaluate(() => { const t = document.querySelector('.f360-inmediata:not([hidden]), .f360-sobrepedido:not([hidden])'); return t ? t.getBoundingClientRect().top + scrollY - 260 : scrollY; });
await scrollTo(inmY, 1000); await wait(4000);
// 5 · Hilo
await cap('Hilo, asesora con inteligencia artificial', 'Responde 24/7 y recomienda modelos reales');
await p.evaluate(() => window.FuxiaHilo && window.FuxiaHilo.open()); await wait(1500);
const chip = p.locator('#fh-root .fh-chips button', { hasText: 'Qué talla me queda' }).first();
await chip.waitFor({ timeout: 10000 }); await chip.click(); await wait(1500);
await p.waitForFunction(() => { const ps = [...document.querySelectorAll('#fh-root .fh-log p')]; const l = ps[ps.length - 1]; return ps.length >= 3 && l && !/escribiendo/i.test(l.textContent) && l.className !== 'c'; }, null, { timeout: 60000 }).catch(() => console.log('hilo sin respuesta'));
await wait(5000);
await p.evaluate(() => { const l = document.querySelector('#fh-root .fh-log'); if (l) l.scrollTop = 0; }); await wait(800);
await tap('#fh-root .fh-x'); await wait(800);
// 6 · sticky ATC + added panel
await scrollTo(0, 1200);
console.log('antes sticky', await p.evaluate(() => [document.querySelector('.f360-sticky-btn')?.textContent, document.querySelector('.cart-count')?.textContent]));
await cap('Botón de compra siempre a la mano'); await wait(2500);
console.log('sticky:', await p.evaluate(() => [document.querySelector('.f360-sticky-btn')?.textContent, document.querySelector('.single_add_to_cart_button')?.className, !!document.querySelector('#fh-root .fh-panel:not([hidden])')]));
await tap('.f360-sticky-btn'); await p.waitForSelector('.f360-ag:not([hidden])', { timeout: 10000 }).catch(async () => { console.log('no panel; real button'); await p.locator('.single_add_to_cart_button').click(); await p.waitForSelector('.f360-ag:not([hidden])', { timeout: 10000 }); }); await wait(1200);
await cap('Confirmación clara', 'Modelo, color, talla y precio · Pagar ahora'); await wait(3500);

// 7 · checkout
await tap('.f360-ag-pagar'); await p.waitForSelector('.wc-block-checkout', { timeout: 60000 }); await wait(2500);
await p.evaluate(() => document.querySelector('#fx-pop-overlay')?.classList.remove('fx-visible'));
await cap('Checkout Fuxia', 'Resumen del pedido arriba, se abre con un toque'); await wait(1500);
await p.evaluate(() => document.querySelector('.f360-resumen')?.click()); await wait(3000);
await p.evaluate(() => document.querySelector('.f360-resumen')?.click()); await wait(600);
const payY = await p.evaluate(() => { const t = document.querySelector('.wc-block-checkout__payment-method'); return t ? t.getBoundingClientRect().top + scrollY - 140 : 1500; });
await scrollTo(payY, 1800);
await cap('3 formas de pago con Mercado Pago', 'Tarjeta · cuenta de Mercado Pago · sin tarjeta'); await wait(3500);
await tap(p.locator('.wc-block-checkout__payment-method label', { hasText: /^\s*Mercado Pago\s*$/ })); await wait(2000);
const confY = await p.evaluate(() => { const t = document.querySelector('.f360-confianza'); return t ? t.getBoundingClientRect().top + scrollY - 300 : scrollY; });
await scrollTo(confY, 1200);
await cap('Confianza junto al botón de pago', 'Envío gratis · pago seguro · cambios'); await wait(3000);
// 8 · payment link rescue
await cap('¿Algo falla al pagar?', 'Le generamos un link de pago y el equipo lo ve en Fuxia 360');
await tap('.f360-rescate-link'); await wait(4500);
await p.evaluate(() => document.querySelector('.f360-r-x')?.click()); await wait(800);
// 9 · thank you page (a paid test order; personal data blurred)
await go('https://staging4.fuxiaballerinas.com/mx/finalizar-compra/order-received/4114/?key=wc_order_gk6mZmhsH5f6c');
if (await p.locator('input[name="email"]:visible, #email:visible').count()) {   // guest order opened in another browser: Woo asks for the order e-mail (staging test buyer)
  await p.fill('input[name="email"]:visible, #email:visible', 'TESTUSER7629515265114848053@testuser.com');
  await Promise.all([p.waitForLoadState('networkidle'), p.locator('button:has-text("Verificar"), input[value="Verificar"]').first().click()]); await wait(1500);
  await p.evaluate(() => document.querySelector('#fx-pop-overlay')?.classList.remove('fx-visible'));
}
await p.evaluate(() => document.querySelectorAll('.woocommerce-customer-details address, .f360-gracias h2, .woocommerce-order-overview__email').forEach((e) => e.classList.add('f360-blur')));
await cap('Pedido confirmado', 'Próximos pasos, WhatsApp y la app de puntos'); await wait(4500);
await scrollTo(900, 1800); await wait(2500);
// 10 · outro
await cap(); await card('Fuxia 360', 'Todo en un solo lugar', 'Inventario de bodega y tiendas, pedidos, clientas, Hilo y la tienda en línea, conectados.');
await wait(4500);
await cdp.send('Page.stopScreencast').catch(() => {}); await wait(300);
await ctx.close(); await b.close();
console.log('ok');
