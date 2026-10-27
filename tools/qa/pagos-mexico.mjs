#!/usr/bin/env node
// Fuxia 360 · Formas de pago que ve una clienta en México (Mario 2026-10-27: "hazlo como una mexicana y ve todo lo habilitado").
// Instagram (iPhone 390x620), Safari iPhone y computadora: Vaca → talla → carrito → checkout con dirección CDMX → lista formas de pago,
// botón PayPal exprés (tamaño), y meses que ofrece Mercado Pago tecleando la tarjeta de PRUEBA de MP (no se envía nada).
// Uso: node tools/qa/pagos-mexico.mjs <carpeta-capturas> [solo]
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../admin-web/package.json', import.meta.url));
const { chromium, devices } = require('@playwright/test');
const OUT = process.argv[2];
const IG_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 400.0.0.32.92 (iPhone14,5; iOS 18_5; es_MX; es; scale=3.00; 1170x2532; 750123456)';
const perfiles = process.argv[3]==='solo' ? { instagram: { ...devices['iPhone 13'], viewport: { width: 390, height: 620 }, userAgent: IG_UA } } : {
  instagram: { ...devices['iPhone 13'], viewport: { width: 390, height: 620 }, userAgent: IG_UA },
  safari: { ...devices['iPhone 13'] },
  computadora: { viewport: { width: 1440, height: 900 } },
};
const b = await chromium.launch();
for (const [nombre, perfil] of Object.entries(perfiles)) {
  const ctx = await b.newContext({ ...perfil, locale: 'es-MX', timezoneId: 'America/Mexico_City', geolocation: { latitude: 19.43, longitude: -99.13 } });
  await ctx.addCookies([{ name: 'fuxia_geo_country', value: 'MX', domain: 'fuxiaballerinas.com', path: '/' }, { name: 'fuxia_geo_redirect_done', value: '1', domain: 'fuxiaballerinas.com', path: '/' }]);
  const p = await ctx.newPage(); const err = []; p.on('pageerror', e => err.push(String(e.message).slice(0, 120)));
  await p.goto('https://fuxiaballerinas.com/mx/producto/vaca/', { waitUntil: 'domcontentloaded' });
  await p.waitForSelector('form.variations_form', { state: 'attached' });
  const c = await p.$('.f360-color'); if (c) await c.click();
  const t = await p.$('.fuxia-talla:not([disabled]):not(.agotada)'); if (t) await t.click();
  await p.waitForFunction(() => { const x = document.querySelector('.single_add_to_cart_button'); return x && !x.classList.contains('disabled'); });
  const real = await p.$('.single_add_to_cart_button'); if (real && await real.isVisible()) await real.click(); else await p.click('.f360-fc-btn');
  await p.waitForTimeout(4000);
  await p.goto('https://fuxiaballerinas.com/mx/finalizar-compra/', { waitUntil: 'networkidle', timeout: 90000 });
  await p.waitForSelector('.wc-block-checkout, form.checkout', { timeout: 30000 });
  const fill = async (id, v) => { const el = await p.$('#' + id); if (el && await el.isVisible()) { await el.fill(v); await el.press('Tab'); } };
  const pais = await p.$eval('#shipping-country', s => s.value).catch(() => '?');
  await fill('email', 'clienta.prueba.mx@gmail.com'); await fill('shipping-first_name', 'Ana'); await fill('shipping-last_name', 'López');
  await fill('shipping-address_1', 'Av. Álvaro Obregón 120'); await fill('shipping-city', 'Ciudad de México');
  const st = await p.$('#shipping-state'); if (st) { const op = await st.$$eval('option', os => os.map(o => [o.value, o.textContent])); const cdmx = op.find(o => /ciudad de m|distrito/i.test(o[1])); if (cdmx) await p.selectOption('#shipping-state', cdmx[0]); console.log('estado elegido:', cdmx); }
  await fill('shipping-postcode', '06700'); await fill('shipping-phone', '5512345678');
  await p.waitForTimeout(8000);
  const metodos = await p.$$eval('input[name="radio-control-wc-payment-method-options"], input[name="payment_method"]', xs => xs.map(x => ({ id: x.value, etiqueta: (x.closest('label, li, .wc-block-components-radio-control__option')?.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 90) })));
  const expres = await p.$$eval('.wc-block-components-express-payment *[id], .wc-block-components-express-payment iframe, #express-payment-method-ppcp-gateway, [class*=express] iframe', xs => xs.map(x => x.id || x.title || x.src?.slice(0, 60)).filter(Boolean).slice(0, 10));
  const iframes = p.frames().map(f => f.url()).filter(u => /paypal|mercadopago|mercadolibre|payco/i.test(u)).map(u => u.slice(0, 90));
  // open Mercado Pago and read what it offers inside (installments, brands)
  const mp = await p.$('#radio-control-wc-payment-method-options-woo-mercado-pago-custom'); if (mp) { await mp.check({ force: true }); await p.waitForTimeout(5000); }
  const dentro = await p.evaluate(() => { const el = document.querySelector('[class*=mp-checkout], #mp-custom-checkout-form-container, .mp-checkout-custom-container, [id*=mp-custom]'); return el ? el.innerText.replace(/\s+/g, ' ').slice(0, 600) : ''; });
  const pp = await p.evaluate(() => { const e = document.querySelector('#express-payment-method-ppcp-gateway-paypal'); if (!e) return 'no existe'; const r = e.getBoundingClientRect(); return { alto: Math.round(r.height), ancho: Math.round(r.width), iframes: e.querySelectorAll('iframe').length, html: e.innerHTML.length }; });
  console.log('botón PayPal exprés:', JSON.stringify(pp));
  const card = p.frames().find(f => /mercadopago|mercadolibre/.test(f.url()) && /card|secure|number/i.test(f.url()));
  console.log('iframes MP:', p.frames().map(f => f.url()).filter(u => /mercadopago|mlstatic|mercadolibre/.test(u)).map(u => u.slice(0, 80)));
  for (const f of p.frames()) { const inp = await f.$('input[name=cardNumber], input#cardNumber, input[autocomplete=cc-number]').catch(() => null); if (inp) { await inp.click(); await inp.type('4075595716483764', { delay: 60 }); console.log('escribí tarjeta de prueba de MP en', f.url().slice(0, 60)); break; } }
  await p.waitForTimeout(6000);
  const cuotas = await p.evaluate(() => { const out = []; document.querySelectorAll('select, [class*=installment], [id*=installment]').forEach(e => { const t = (e.innerText || '').trim().replace(/\s+/g, ' '); if (t && /mes|cuota|pago|installment|x \$/i.test(t)) out.push(t.slice(0, 300)); }); return [...new Set(out)].slice(0, 5); });
  console.log('meses / cuotas que ofrece:', JSON.stringify(cuotas));
  const total = await p.evaluate(() => (document.querySelector('.wc-block-components-totals-footer-item .wc-block-formatted-money-amount') || {}).textContent || '');
  console.log(`\n=== ${nombre} === país en checkout: ${pais} · total: ${total}`);
  console.log('formas de pago:', JSON.stringify(metodos));
  console.log('pago exprés / botones:', JSON.stringify(expres));
  console.log('ventanas de pasarela cargadas:', JSON.stringify([...new Set(iframes)]));
  console.log('dentro de Mercado Pago:', dentro || '(no se encontró el formulario)');
  console.log('errores JS:', err.length ? err : 'ninguno');
  await p.screenshot({ path: `${OUT}/mx-${nombre}.png`, fullPage: true });
  await ctx.close();
}
await b.close();
