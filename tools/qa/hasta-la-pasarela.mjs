#!/usr/bin/env node
// Fuxia 360 · "Hasta la pasarela" (Mario 2026-10-27: "métete a /co y haz una compra hasta llegar a epayco; no inventes").
// Anonymous phone browser: /<pais>/producto → colour + size → cart → checkout → lists the payment methods the CUSTOMER sees
// (screenshot). With --pedir it also fills the form, picks the gateway and clicks "Realizar el pedido" up to the gateway page,
// NEVER pays, and prints the order number so it can be cancelled.
// Usage: node tools/qa/hasta-la-pasarela.mjs <co|mx> <out-dir> [--pedir] [--pasarela epayco]
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../admin-web/package.json', import.meta.url));
const { chromium, devices } = require('@playwright/test');
const [pais = 'co', out = '.'] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const PEDIR = process.argv.includes('--pedir');
const pi = process.argv.indexOf('--pasarela'); const PASARELA = pi > 0 ? process.argv[pi + 1] : (pais === 'co' ? 'epayco' : 'woo-mercado-pago-custom');
const BASE = 'https://fuxiaballerinas.com', P = `${BASE}/${pais}`;
const prods = await (await fetch(`${BASE}/wp-json/wc/store/v1/products?per_page=20&catalog_visibility=catalog`)).json();
const prod = prods.find((p) => p.is_in_stock) || prods[0];
const browser = await chromium.launch();
// Instagram in-app browser on iPhone (same profile as docs/fuxia360/cro/05_MOBILE_IAB_RESULTS.md): real IG user agent, IAB viewport 390x620
const IG_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 400.0.0.32.92 (iPhone14,5; iOS 18_5; es_MX; es; scale=3.00; 1170x2532; 750123456)';
const ctx = await browser.newContext({ ...devices['iPhone 13'], viewport: { width: 390, height: 620 }, userAgent: process.argv.includes('--safari') ? devices['iPhone 13'].userAgent : IG_UA, locale: 'es-' + pais.toUpperCase() });
await ctx.addCookies([{ name: 'fuxia_geo_country', value: pais.toUpperCase(), domain: 'fuxiaballerinas.com', path: '/' },
                      { name: 'fuxia_geo_redirect_done', value: '1', domain: 'fuxiaballerinas.com', path: '/' }]);
const page = await ctx.newPage();
const errores = []; page.on('pageerror', (e) => errores.push(String(e.message || e).slice(0, 160)));
const log = (...a) => console.log(...a);
await page.goto(`${P}/producto/${prod.slug}/`, { waitUntil: 'domcontentloaded', timeout: 60000 });
log('producto:', prod.name, page.url());
await page.waitForSelector('form.variations_form, form.cart', { state: 'attached', timeout: 30000 });
const c = await page.$('.f360-color'); if (c) await c.click();
const t = await page.$('.fuxia-talla:not([disabled]):not(.agotada)'); if (t) await t.click();
await page.waitForFunction(() => { const b = document.querySelector('.single_add_to_cart_button'); return b && !b.classList.contains('disabled'); }, null, { timeout: 15000 });
const real = await page.$('.single_add_to_cart_button');
if (real && await real.isVisible()) await real.click(); else await page.click('.f360-fc-btn');
await page.waitForTimeout(4000);
const precio = await page.evaluate(() => (document.querySelector('.woocommerce-variation-price .amount, p.price .amount') || {}).textContent || '');
log('precio en la ficha:', precio.trim());
await page.goto(`${P}/finalizar-compra/`, { waitUntil: 'networkidle', timeout: 90000 });
log('checkout:', page.url());
await page.waitForSelector('form.checkout, .wc-block-checkout', { timeout: 30000 });
await page.waitForFunction(() => document.querySelectorAll('input[name="payment_method"], input[name="radio-control-wc-payment-method-options"]').length > 0 || /no hay métodos|no payment/i.test(document.body.innerText), null, { timeout: 45000 }).catch(() => log('las formas de pago no cargaron en 45 s'));
const items = await page.evaluate(async (b) => { const r = await fetch(`${b}/wp-json/wc/store/v1/cart`, { credentials: 'include' }); const j = await r.json(); return { n: j.items_count, total: j.totals && j.totals.total_price, moneda: j.totals && j.totals.currency_code, pagos: j.payment_methods }; }, BASE);
log('carrito (Store API):', JSON.stringify(items));
const sel = await page.$('#billing_country'); if (sel) { await page.selectOption('#billing_country', pais.toUpperCase()).catch(() => {}); await page.waitForTimeout(4000); }
const metodos = await page.$$eval('input[name="payment_method"], input[name="radio-control-wc-payment-method-options"]', (xs) => xs.map((x) => ({ id: x.value, visible: !!x.offsetParent || !!x.closest('li, label')?.offsetParent, etiqueta: (x.closest('li, label, .wc-block-components-radio-control__option')?.innerText || '').trim().slice(0, 80) })));
log('formas de pago que ve la clienta:', JSON.stringify(metodos, null, 1));
const total = await page.evaluate(() => (document.querySelector('.order-total .amount, .wc-block-components-totals-footer-item .wc-block-formatted-money-amount') || {}).textContent || '');
log('total:', total.trim());
await page.screenshot({ path: `${out}/${pais}-checkout.png`, fullPage: true });
if (PEDIR) {
  // block checkout (wc-block-checkout): shipping-* fields, radio-control-wc-payment-method-options, button "Realizar el pedido"
  const co = pais === 'co';
  const fill = async (id, v) => { const el = await page.$('#' + id); if (el && await el.isVisible()) { await el.fill(v); await el.press('Tab'); } };
  await fill('email', 'qa+pasarela@fuxiaballerinas.com');
  await fill('shipping-first_name', 'Prueba'); await fill('shipping-last_name', 'Fuxia360 NO ENVIAR');
  await fill('shipping-address_1', co ? 'Calle 1 # 2-3' : 'Calle Uno 123'); await fill('shipping-city', co ? 'Bogotá' : 'Ciudad de México');
  const st = await page.$('#shipping-state'); if (st) { const opts = await st.$$eval('option', (os) => os.map((o) => o.value).filter(Boolean)); await page.selectOption('#shipping-state', opts.includes(co ? 'DC' : 'CMX') ? (co ? 'DC' : 'CMX') : opts[0]).catch(() => {}); }
  await fill('shipping-postcode', co ? '110111' : '06700'); await fill('shipping-phone', co ? '3000000000' : '5500000000');
  await fill('shipping-fuxia-cedula', '1000000000');
  await page.waitForTimeout(4000);
  const radio = await page.$(`#radio-control-wc-payment-method-options-${PASARELA}`) || await page.$(`input[name="payment_method"][value="${PASARELA}"]`);
  if (!radio) log(`NO aparece la pasarela ${PASARELA} en el checkout`);
  else {
    await radio.check({ force: true }); await page.waitForTimeout(2000);
    await page.screenshot({ path: `${out}/${pais}-antes-de-pedir.png`, fullPage: true });
    const btn = page.getByRole('button', { name: /realizar el pedido/i }).first();
    const nav = page.waitForURL((u) => !/finalizar-compra\/?$/.test(u.pathname), { timeout: 60000 }).catch(() => null);
    await btn.click();
    await nav; await page.waitForTimeout(12000);
    log('después de "Realizar el pedido":', page.url());
    const avisos = await page.$$eval('.wc-block-components-notice-banner, .woocommerce-error li, .wc-block-components-validation-error', (xs) => xs.map((x) => x.innerText.trim()).filter(Boolean).slice(0, 6));
    if (avisos.length) log('avisos en pantalla:', avisos);
    const m = page.url().match(/order-pay\/(\d+)|order-received\/(\d+)|[?&]order(?:_id)?=(\d+)/); if (m) log('PEDIDO DE PRUEBA:', m[1] || m[2] || m[3]);
    log('texto visible:', (await page.evaluate(() => document.body.innerText)).replace(/\s+/g, ' ').slice(0, 400));
    await page.screenshot({ path: `${out}/${pais}-despues.png`, fullPage: false });
    const frames = page.frames().map((fr) => fr.url()).filter((u) => /payco|mercadopago|paypal/i.test(u)); if (frames.length) log('pasarela cargada:', frames.slice(0, 3));
  }
}
log('errores JS:', errores.length ? errores : 'ninguno');
await browser.close();
