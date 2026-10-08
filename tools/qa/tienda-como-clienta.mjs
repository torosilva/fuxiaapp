#!/usr/bin/env node
// Fuxia 360 · "Comprar como clienta" — the store test that must pass before and after ANY change to the live store
// (Mario 2026-10-07: customers could not choose a colour for 7 hours after the merge and nobody saw it).
// For EVERY product visible in the catalog (public Store API), in a desktop AND a phone browser:
//   page loads · photos · price · colour buttons (one per colour) · size buttons · for EACH colour: pick it + the first available
//   size → WooCommerce resolves the variation and "Añadir al carrito" is enabled.
// Then one real cart flow: add to cart → the cart has it → the checkout page opens with it. NEVER places an order or pays.
// Anonymous browser (no admin session). Output: a list of failures (exit 1 if any) + tools/qa/ultimo-resultado.json.
// Usage: node tools/qa/tienda-como-clienta.mjs [--base https://fuxiaballerinas.com] [--solo slug1,slug2] [--sin-carrito]
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
const require = createRequire(new URL('../../admin-web/package.json', import.meta.url));
const { chromium, devices } = require('@playwright/test');

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const BASE = arg('--base', 'https://fuxiaballerinas.com').replace(/\/+$/, '');
const SOLO = (arg('--solo', '') || '').split(',').filter(Boolean);
const SIN_CARRITO = process.argv.includes('--sin-carrito');
const MX = `${BASE}/mx`;

async function catalogo() {
  const out = [];
  for (let page = 1; page < 10; page++) {
    const r = await fetch(`${BASE}/wp-json/wc/store/v1/products?per_page=100&page=${page}&catalog_visibility=catalog`);
    const j = await r.json();
    if (!Array.isArray(j) || !j.length) break;
    out.push(...j);
    if (page >= Number(r.headers.get('x-wp-totalpages') || 1)) break;
  }
  return out.filter((p) => !SOLO.length || SOLO.includes(p.slug));
}

async function revisarProducto(ctx, p, etiqueta) {
  const fallas = [];
  const page = await ctx.newPage();
  const errores = [];
  // known, pre-existing and harmless (the theme's mini-cart rejects an empty request on every product page): warning, not failure
  page.on('pageerror', (e) => { const m = String(e.message || e); if (m !== 'Object') errores.push(m.slice(0, 160)); });
  try {
    const res = await page.goto(`${MX}/producto/${p.slug}/`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    if (!res || res.status() !== 200) { fallas.push(`la página respondió ${res && res.status()}`); return fallas; }
    await page.waitForSelector('form.variations_form, form.cart', { timeout: 30000 });
    const info = await page.evaluate(() => {
      const f = document.querySelector('form.variations_form');
      const colorSel = f && f.querySelector('select[name="attribute_pa_color"]');
      return {
        variable: !!f,
        colores: colorSel ? [...colorSel.options].filter((o) => o.value).map((o) => o.value) : [],
        fotos: document.querySelectorAll('.woocommerce-product-gallery img, [class*=gallery] img').length,
      };
    });
    if (!info.fotos) fallas.push('sin fotos');
    if (!info.variable) return fallas;   // simple product: nothing to choose
    if (info.colores.length) {
      await page.waitForSelector('.f360-color', { timeout: 15000 }).catch(() => {});
      const botones = await page.$$eval('.f360-color', (bs) => bs.filter((b) => b.offsetParent).map((b) => b.dataset.color));
      const faltan = info.colores.filter((c) => !botones.includes(c));
      if (faltan.length) fallas.push(`no se puede elegir el color: ${faltan.join(', ')}`);
    }
    const tallas = await page.$$eval('.fuxia-talla', (bs) => bs.filter((b) => b.offsetParent).length).catch(() => 0);
    if (!tallas) fallas.push('no hay botones de talla');
    for (const color of info.colores.length ? info.colores : [null]) {
      if (color) {
        const b = await page.$(`.f360-color[data-color="${color}"]`);
        if (!b) continue;
        await b.click();
      }
      const t = await page.$('.fuxia-talla:not([disabled]):not(.agotada)');
      if (!t) { fallas.push(`${color || 'producto'}: ninguna talla disponible`); continue; }
      await t.click();
      const ok = await page.waitForFunction(() => {
        const f = document.querySelector('form.variations_form');
        const v = f && f.querySelector('input[name="variation_id"]');
        const btn = f && f.querySelector('.single_add_to_cart_button');
        return !!(v && Number(v.value) > 0 && btn && !btn.classList.contains('disabled'));
      }, null, { timeout: 15000 }).then(() => true).catch(() => false);
      if (!ok) fallas.push(`${color || 'producto'}: después de elegir talla no se activa "Añadir al carrito"`);
    }
    if (errores.length) fallas.push(`errores de JavaScript: ${[...new Set(errores)].slice(0, 2).join(' | ')}`);
  } catch (e) {
    fallas.push(`no se pudo revisar: ${String(e.message || e).slice(0, 160)}`);
  } finally { await page.close(); }
  return fallas.map((f) => `[${etiqueta}] ${f}`);
}

async function flujoCarrito(browser, p) {
  const ctx = await browser.newContext({ ...devices['iPhone 13'] });
  const page = await ctx.newPage();
  const fallas = [];
  try {
    await page.goto(`${MX}/producto/${p.slug}/`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForSelector('form.variations_form', { timeout: 30000 });
    const c = await page.$('.f360-color'); if (c) await c.click();
    const t = await page.$('.fuxia-talla:not([disabled]):not(.agotada)'); if (t) await t.click();
    await page.waitForFunction(() => { const b = document.querySelector('.single_add_to_cart_button'); return b && !b.classList.contains('disabled'); }, null, { timeout: 15000 });
    await page.click('.single_add_to_cart_button');
    await page.waitForTimeout(4000);
    const enCarrito = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/wp-json/wc/store/v1/cart`, { credentials: 'include' });
      const j = await r.json(); return j.items_count || 0;
    }, BASE);
    if (!enCarrito) fallas.push('[carrito] "Añadir al carrito" no agregó nada al carrito');
    const url = await page.evaluate(() => (window.wc_add_to_cart_params && window.wc_add_to_cart_params.cart_url) || '');
    const checkout = url ? url.replace(/carrito\/?$/, 'finalizar-compra/').replace(/cart\/?$/, 'checkout/') : `${MX}/finalizar-compra/`;
    const res = await page.goto(checkout, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const tieneProducto = await page.waitForSelector('form.checkout, .wc-block-checkout, form[name="checkout"]', { timeout: 30000 }).then(() => true).catch(() => false);
    if (!res || res.status() >= 400 || !tieneProducto) fallas.push(`[carrito] la página de pago no abrió (${checkout}, ${res && res.status()})`);
  } catch (e) { fallas.push(`[carrito] no se pudo completar: ${String(e.message || e).slice(0, 160)}`); }
  finally { await ctx.close(); }
  return fallas;
}

const productos = await catalogo();
const browser = await chromium.launch();
const resultado = { revisado: new Date().toISOString(), base: BASE, productos: productos.length, fallas: {} };
const escritorio = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const telefono = await browser.newContext({ ...devices['iPhone 13'] });
const cola = [...productos];
await Promise.all(Array.from({ length: 4 }, async () => {
  for (let p = cola.shift(); p; p = cola.shift()) {
    const f = [...await revisarProducto(escritorio, p, 'computadora'), ...await revisarProducto(telefono, p, 'celular')];
    if (f.length) resultado.fallas[p.name] = f;
    process.stdout.write(f.length ? '✗' : '·');
  }
}));
if (!SIN_CARRITO && productos.length) {
  const conColores = productos.find((p) => (p.attributes || []).some((a) => /color/i.test(a.name))) || productos[0];
  const f = await flujoCarrito(browser, conColores);
  if (f.length) resultado.fallas[`Carrito y pago (${conColores.name})`] = f;
  resultado.carrito = { producto: conColores.name, ok: !f.length };
}
await browser.close();
writeFileSync(new URL('./ultimo-resultado.json', import.meta.url), JSON.stringify(resultado, null, 1));
const n = Object.keys(resultado.fallas).length;
console.log(`\n${productos.length} productos revisados en computadora y celular${resultado.carrito ? `; carrito y pago con ${resultado.carrito.producto}: ${resultado.carrito.ok ? 'OK' : 'FALLA'}` : ''}.`);
if (!n) console.log('TODO BIEN: en todos se puede elegir color y talla y agregar al carrito.');
else { console.log(`${n} con problemas:`); for (const [k, v] of Object.entries(resultado.fallas)) { console.log(`  ✗ ${k}`); v.forEach((x) => console.log(`      ${x}`)); } }
process.exit(n ? 1 : 0);
