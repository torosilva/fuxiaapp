<?php
/**
 * Plugin Name: Fuxia 360 · Favoritos V1 (STAGING4)
 * Description: ♡ en tarjetas, carruseles, ficha y header + "Mis favoritos"; captura anónima en Fuxia 360 (staging).
 *              GENERADO por scripts/f360/build_staging4_storefront_mu.mjs — no editar a mano.
 * Apagar: borrar este archivo de wp-content/mu-plugins/ en staging4.
 */
if (!defined('ABSPATH')) exit;
if (strpos((string) wp_parse_url(home_url(), PHP_URL_HOST), 'staging4.') !== 0) return;   // staging4 only, never production
add_action('wp_footer', function () {
  if (is_admin() || isset($_GET['bricks'])) return;
  echo <<<'F360SNIP'
<!--
  Fuxia 360 · ♡ Favoritos V1 (Mario 2026-10-06). STAGING. Fuente: tools/storefront/f360-favoritos.html
  · ♡ en cada tarjeta de producto (tienda, categorías, home, relacionados), en los carruseles de la Tienda y en la ficha.
  · ♡ con contador en el header (junto a Club Fuxia) → panel "Mis favoritos" (foto, nombre, precio del país, ver / quitar).
  · Sin cuenta: la lista vive en este dispositivo (localStorage) y se sincroniza entre pestañas; /mx/ y /co/ comparten la lista
    y cada uno muestra su precio. Producto que ya no existe o no se vende: "Ya no está disponible" + quitar.
  · Fuxia 360 recibe cada favorite_added / favorite_removed ANÓNIMO (id aleatorio del navegador, nunca datos personales) para
    el reporte "Favoritos / Intent". Nada se envía al cargar la página; el panel hace una sola consulta a la tienda al abrirse.
-->
<div id="f360-fav-root">
  <div class="f360-fav-velo" hidden></div>
  <aside class="f360-fav-panel" hidden role="dialog" aria-modal="true" aria-labelledby="f360-fav-titulo">
    <div class="f360-fav-top">
      <h2 id="f360-fav-titulo">Mis favoritos <span class="f360-fav-n"></span></h2>
      <button type="button" class="f360-fav-x" aria-label="Cerrar mis favoritos">✕</button>
    </div>
    <div class="f360-fav-lista" aria-live="polite"></div>
    <p class="f360-fav-pie">Se guardan en este dispositivo.</p>
  </aside>
</div>
<style>
#f360-fav-root [hidden] { display: none !important; }
.f360-fav-btn { position: absolute; top: 10px; right: 10px; z-index: 5; width: 38px; height: 38px; border-radius: 50%; border: 0; padding: 0;
  display: inline-flex; align-items: center; justify-content: center; background: rgba(255,255,255,.92); color: #242424; cursor: pointer;
  box-shadow: 0 2px 10px rgba(0,0,0,.12); transition: transform .15s ease; }
.f360-fav-btn:hover { transform: scale(1.06); }
.f360-fav-btn svg { width: 19px; height: 19px; fill: none; stroke: currentColor; stroke-width: 1.8; }
.f360-fav-btn[aria-pressed="true"] { color: #B23A48; }
.f360-fav-btn[aria-pressed="true"] svg { fill: currentColor; }
.f360-fav-btn.f360-fav-pdp { position: static; margin-left: 12px; vertical-align: middle; flex: 0 0 auto; }
.f360-fav-host { position: relative; }
.f360-fav-head { position: relative; display: inline-flex; align-items: center; justify-content: center; width: 34px; height: 34px; margin-right: 12px;
  border: 0; background: none; color: inherit; cursor: pointer; padding: 0; }
.f360-fav-head svg { width: 21px; height: 21px; fill: none; stroke: currentColor; stroke-width: 1.7; }
.f360-fav-head.lleno svg { fill: #B23A48; stroke: #B23A48; }
.f360-fav-head b { position: absolute; top: -2px; right: -4px; min-width: 17px; height: 17px; padding: 0 4px; border-radius: 9px; background: #B23A48; color: #fff;
  font: 600 10px/17px inherit; font-family: inherit; text-align: center; box-sizing: border-box; }
.f360-fav-velo { position: fixed; inset: 0; z-index: 99998; background: rgba(20,17,13,.35); }
.f360-fav-panel { position: fixed; top: 0; right: 0; bottom: 0; z-index: 99999; width: min(420px, 100vw); background: #fff; color: #242424;
  display: flex; flex-direction: column; box-shadow: -10px 0 30px rgba(0,0,0,.15); font-family: inherit; }
.f360-fav-top { display: flex; justify-content: space-between; align-items: center; padding: 18px 20px; border-bottom: 1px solid #f0e9df; }
.f360-fav-top h2 { margin: 0; font-size: 18px; font-weight: 600; letter-spacing: .02em; }
.f360-fav-n { color: #83734C; font-weight: 500; }
.f360-fav-x { border: 0; background: none; font-size: 20px; cursor: pointer; width: 40px; height: 40px; color: #242424; }
.f360-fav-lista { flex: 1; overflow-y: auto; padding: 8px 20px; overscroll-behavior: contain; }
.f360-fav-item { display: grid; grid-template-columns: 76px 1fr auto; gap: 14px; align-items: center; padding: 12px 0; border-bottom: 1px solid #f4efe7; }
.f360-fav-item img { width: 76px; height: 76px; object-fit: cover; border-radius: 6px; background: #f5f2ec; display: block; }
.f360-fav-item a { color: inherit; text-decoration: none; }
.f360-fav-item b { display: block; font-size: 14px; font-weight: 600; }
.f360-fav-item span { display: block; font-size: 13px; color: #6B6B68; margin-top: 3px; }
.f360-fav-item .f360-fav-no { color: #9b2c2c; }
.f360-fav-quitar { border: 0; background: none; color: #B23A48; cursor: pointer; width: 40px; height: 40px; }
.f360-fav-quitar svg { width: 19px; height: 19px; fill: currentColor; }
.f360-fav-vacio { padding: 40px 10px; text-align: center; color: #6B6B68; font-size: 14px; line-height: 1.6; }
.f360-fav-pie { margin: 0; padding: 14px 20px; border-top: 1px solid #f0e9df; font-size: 12px; color: #9A9A96; }
@media (prefers-reduced-motion: reduce) { .f360-fav-btn { transition: none; } }
</style>
<script>
/* Fuxia 360 · Favoritos V1. STAGING. Fuente: tools/storefront/f360-favoritos.html */
(function () {
  if (window.F360Fav || /[?&]bricks=run/.test(location.search)) return;
  var F360 = 'https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-store-reserve';   // STAGING
  var KEY = 'f360_favs_v1', ANON = 'f360_anon_v1';
  var pais = (location.pathname.match(/^\/(mx|co)\//) || [0, 'mx'])[1];
  var base = location.origin + '/' + pais + '/';
  var HEART = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20.3s-7.6-4.6-9.3-9.4C1.6 7.6 3.6 4.5 6.9 4.5c2 0 3.6 1.1 4.6 2.7 1-1.6 2.6-2.7 4.6-2.7 3.3 0 5.3 3.1 4.2 6.4-1.7 4.8-9.3 9.4-9.3 9.4z"/></svg>';
  var root = document.getElementById('f360-fav-root'); if (!root) return;
  document.body.appendChild(root);
  var q = function (s) { return root.querySelector(s); };
  var panel = q('.f360-fav-panel'), velo = q('.f360-fav-velo'), lista = q('.f360-fav-lista');

  // ── the list (this device) ──
  var leer = function () { try { var v = JSON.parse(localStorage.getItem(KEY) || '[]'); return Array.isArray(v) ? v.filter(function (x) { return x && x.id > 0; }) : []; } catch (e) { return []; } };
  var guardar = function (l) { try { localStorage.setItem(KEY, JSON.stringify(l.slice(0, 200))); } catch (e) {} };
  var favs = leer();
  var tiene = function (id) { return favs.some(function (x) { return x.id === id; }); };
  var anon = function () {
    var a = null; try { a = localStorage.getItem(ANON); } catch (e) {}
    if (!a || !/^[0-9a-f-]{36}$/i.test(a)) {
      a = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) { var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); });
      try { localStorage.setItem(ANON, a); } catch (e) {}
    }
    return a;
  };
  // anonymous intent event to Fuxia 360 (fire and forget; never blocks the page)
  var avisar = function (ev, it) {
    try {
      fetch(F360, { method: 'POST', keepalive: true, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'favorite',
        event: ev, market: pais, anon_id: anon(), woo_product_id: it.id, woo_variation_id: it.vid || null, color: it.color || null }) }).catch(function () {});
    } catch (e) {}
  };
  var cambiar = function (it, on) {
    favs = leer();
    if (on && !tiene(it.id)) { favs.unshift({ id: it.id, name: it.name || '', img: it.img || '', url: it.url || '', at: Date.now() }); guardar(favs); avisar('favorite_added', it); }
    else if (!on && tiene(it.id)) { favs = favs.filter(function (x) { return x.id !== it.id; }); guardar(favs); avisar('favorite_removed', it); }
    pintar();
  };

  // ── hearts on every product card, the shop carousels and the product page ──
  var boton = function (it, extra) {
    var b = document.createElement('button'); b.type = 'button'; b.className = 'f360-fav-btn' + (extra ? ' ' + extra : ''); b.innerHTML = HEART;
    b.dataset.favId = String(it.id);
    b.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation();
      var on = !tiene(it.id); if (it.pdp) { it.vid = pdpVar.vid; it.color = pdpVar.color; } cambiar(it, on); });
    return b;
  };
  var datosDe = function (el, id) {
    var a = el.tagName === 'A' ? el : el.querySelector('a[href]'), img = el.querySelector('img');
    var nombre = (a && (a.getAttribute('aria-label') || '').replace(/^Ver\s+/i, '')) || (el.querySelector('h2, h3, b') || {}).textContent || '';
    return { id: id, name: String(nombre).trim(), img: img ? (img.currentSrc || img.src) : '', url: a ? a.href : '' };
  };
  var tarjetas = function () {
    document.querySelectorAll('li.type-product[class*="post-"]:not([data-f360-fav]), [data-f360-product-id]:not([data-f360-fav])').forEach(function (el) {
      var id = Number(el.getAttribute('data-f360-product-id') || ((el.className.match(/\bpost-(\d+)\b/) || [])[1]));
      el.setAttribute('data-f360-fav', '1');
      if (!(id > 0)) return;
      if (getComputedStyle(el).position === 'static') el.classList.add('f360-fav-host');
      el.appendChild(boton(datosDe(el, id)));
    });
  };
  var pdpVar = { vid: null, color: null };
  var ficha = function () {
    if (!document.body.classList.contains('single-product')) return;
    var id = Number((document.body.className.match(/\bpostid-(\d+)\b/) || [])[1]);
    var h1 = document.querySelector('.brxe-product-title, h1.product_title, h1');
    if (!(id > 0) || !h1 || h1.querySelector('.f360-fav-btn')) return;
    var img = document.querySelector('.woocommerce-product-gallery img, .brxe-product-gallery img');
    var it = { id: id, name: h1.textContent.trim(), img: img ? (img.currentSrc || img.src) : '', url: location.href.split('?')[0].split('#')[0], pdp: true };
    var b = boton(it, 'f360-fav-pdp'); b.setAttribute('aria-label', 'Guardar ' + it.name + ' en mis favoritos');
    h1.style.display = 'flex'; h1.style.alignItems = 'center'; h1.style.justifyContent = 'space-between'; h1.appendChild(b);
    // the colour / size she is looking at travels with the ♡ (canonical colour / variant in Fuxia 360)
    var form = document.querySelector('form.variations_form');
    if (form && window.jQuery) {
      jQuery(form).on('found_variation', function (e, v) { pdpVar.vid = v && v.variation_id || null; })
        .on('reset_data', function () { pdpVar.vid = null; });
      var sel = form.querySelector('[name="attribute_pa_color"]');
      var col = function () { var o = sel && sel.selectedOptions && sel.selectedOptions[0]; pdpVar.color = o && o.value ? o.textContent.trim() : null; };
      if (sel) { sel.addEventListener('change', col); col(); }
    }
  };

  // ── header: ♡ with counter, next to Club Fuxia (or before the account icon) ──
  var head = null;
  var cabecera = function () {
    if (head && document.body.contains(head)) return;
    // always right before the account icon: with "★ Club Fuxia" in the header it reads  Club Fuxia ★ | ♡ 3 | 👤
    var cuenta = document.querySelector('#brx-header a[href*="/mi-cuenta"]');
    var ancla = cuenta, padre = cuenta && cuenta.parentNode;
    if (!padre) return;
    head = document.createElement('button'); head.type = 'button'; head.className = 'f360-fav-head'; head.innerHTML = HEART + '<b hidden></b>';
    head.addEventListener('click', abrir);
    padre.insertBefore(head, ancla || null);
  };

  var pintar = function () {
    favs = leer();
    var n = favs.length;
    document.querySelectorAll('.f360-fav-btn').forEach(function (b) {
      var on = tiene(Number(b.dataset.favId)); b.setAttribute('aria-pressed', String(on));
      if (!b.classList.contains('f360-fav-pdp')) b.setAttribute('aria-label', (on ? 'Quitar de mis favoritos' : 'Agregar a mis favoritos'));
    });
    if (head) { var c = head.querySelector('b'); c.hidden = !n; c.textContent = n > 99 ? '99+' : String(n); head.classList.toggle('lleno', n > 0);
      head.setAttribute('aria-label', 'Mis favoritos' + (n ? ': ' + n : '')); }
    q('.f360-fav-n').textContent = n ? '(' + n + ')' : '';
    if (!panel.hidden) listar();
  };

  // ── "Mis favoritos": current data from the store of THIS country (price, photo, link); gone products say so ──
  var cache = {};
  var listar = function () {
    var l = favs;
    if (!l.length) { lista.innerHTML = '<p class="f360-fav-vacio">Todavía no tienes favoritos.<br>Toca ♡ en los modelos que te gusten y aquí los verás juntos.</p>'; return; }
    var fila = function (x) {
      var p = cache[x.id], div = document.createElement('div'); div.className = 'f360-fav-item';
      var vivo = p && p.is_purchasable !== false;
      var img = document.createElement('img'); img.alt = ''; img.loading = 'lazy'; img.src = (p && p.images && p.images[0] && (p.images[0].thumbnail || p.images[0].src)) || x.img || '';
      var a = document.createElement('a'); a.href = (p && p.permalink) || x.url || '#';
      var b = document.createElement('b'); b.textContent = (p && p.name ? p.name.replace(/&amp;/g, '&') : x.name) || 'Modelo';
      var s = document.createElement('span');
      if (p === null) { s.textContent = 'Ya no está disponible'; s.className = 'f360-fav-no'; a.removeAttribute('href'); }
      else if (p) { var pr = p.prices || {}, dec = pr.currency_minor_unit || 0;
        s.textContent = !vivo ? 'Por ahora no está a la venta' : (pr.currency_prefix || '$') + Number(pr.price / Math.pow(10, dec)).toLocaleString('es-MX') + (pr.currency_suffix || ''); }
      a.appendChild(b); a.appendChild(s);
      var quitar = document.createElement('button'); quitar.type = 'button'; quitar.className = 'f360-fav-quitar'; quitar.innerHTML = HEART;
      quitar.setAttribute('aria-label', 'Quitar ' + b.textContent + ' de mis favoritos');
      quitar.onclick = function () { cambiar({ id: x.id }, false); };
      div.appendChild(img); div.appendChild(a); div.appendChild(quitar); return div;
    };
    lista.innerHTML = ''; l.forEach(function (x) { lista.appendChild(fila(x)); });
  };
  var cargar = function () {
    var ids = favs.map(function (x) { return x.id; }).filter(function (id) { return !(id in cache); });
    if (!ids.length) return;
    fetch(base + 'wp-json/wc/store/v1/products?per_page=100&include=' + ids.join(','), { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (prods) {
        var vistos = {}; (prods || []).forEach(function (p) { cache[p.id] = p; vistos[p.id] = 1; });
        ids.forEach(function (id) { if (!vistos[id]) cache[id] = null; });   // deleted / hidden / not for sale here
        listar();
      }).catch(function () {});
  };
  var ultimoFoco = null;
  function abrir() { ultimoFoco = document.activeElement; panel.hidden = false; velo.hidden = false; listar(); cargar(); q('.f360-fav-x').focus(); }
  function cerrar() { panel.hidden = true; velo.hidden = true; if (ultimoFoco && ultimoFoco.focus) ultimoFoco.focus(); }
  q('.f360-fav-x').onclick = cerrar; velo.onclick = cerrar;
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !panel.hidden) cerrar(); });
  window.addEventListener('storage', function (e) { if (e.key === KEY) pintar(); });   // other tabs

  var todo = function () { cabecera(); tarjetas(); ficha(); pintar(); };
  todo();
  // grids / carousels that appear later (filters, "Más vendidas", lazy sections)
  var pend = false;
  new MutationObserver(function () { if (pend) return; pend = true; setTimeout(function () { pend = false; cabecera(); tarjetas(); pintar(); }, 250); })
    .observe(document.body, { childList: true, subtree: true });
  window.F360Fav = { abrir: abrir, lista: function () { return leer(); } };
})();
</script>
F360SNIP;
  echo "\n";
}, 30);
// the shop search pasted in Bricks → the repo's version (carousel cards carry data-f360-product-id for the ♡)
add_action('template_redirect', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST) || isset($_GET['bricks'])) return;
  if (!function_exists('is_shop') || !(is_shop() || is_product_taxonomy())) return;
  ob_start(function ($page) {
    $start = strpos($page, '<div class="f360-tienda">');
    if ($start === false) return $page;
    $mark = strpos($page, 'filtros de la Tienda', $start);
    $end = $mark === false ? false : strpos($page, '</script>', $mark);
    if ($end === false) return $page;
    $c = strrpos(substr($page, 0, $start), '<!--');
    if ($c !== false && strpos(substr($page, $c, $start - $c), 'Fuxia 360 · Página de TIENDA') !== false) $start = $c;
    return substr($page, 0, $start) . <<<'F360SNIP'
<div class="f360-tienda">
  <div class="f360-t-filtros">
    <div class="f360-t-top">
      <div class="f360-t-bwrap">
        <input type="search" class="f360-t-buscar" placeholder="Busca tu modelo o color" aria-label="Buscar modelo o color" autocomplete="off" role="combobox" aria-expanded="false">
        <ul class="f360-t-sug" role="listbox" hidden></ul>
      </div>
      <button type="button" class="f360-t-toggle" aria-expanded="true">Ocultar filtros</button>
    </div>
    <div class="f360-t-cuerpo" role="dialog" aria-label="Filtros">
    <div class="f360-t-hoja-top"><b>Filtros</b><button type="button" class="f360-t-x" aria-label="Cerrar filtros">✕</button></div>
    <div class="f360-t-fila f360-t-fila-cat" hidden><span class="f360-t-et">Categoría</span><div class="f360-t-cats"></div></div>
    <div class="f360-t-fila"><span class="f360-t-et">Color</span><div class="f360-t-colores"></div></div>
    <div class="f360-t-fila"><span class="f360-t-et f360-t-et-talla">Talla</span><div class="f360-t-tallas"></div></div>
    <div class="f360-t-fila f360-t-fila-inm" hidden><label class="f360-t-inm"><input type="checkbox"> <b>Entrega inmediata</b> en Zona Metropolitana</label></div>
    <div class="f360-t-pie"><button type="button" class="f360-t-limpiar">Limpiar</button><button type="button" class="f360-t-ver">Ver modelos</button></div>
    </div>
    <div class="f360-t-velo" hidden></div>
    <p class="f360-t-res" role="status"></p>
  </div>
  <div class="f360-t-mas-res" hidden></div>
  <div class="f360-t-rails"></div>
</div>
<style>
.f360-tienda { margin: 8px 0 28px; background: #fff; font-family: inherit; color: #242424; }
.f360-tienda [hidden] { display: none !important; }
.f360-t-rail { margin: 0 0 28px; }
.f360-t-rails, .f360-t-mas-res { width: 100%; max-width: 100%; min-width: 0; overflow: hidden; box-sizing: border-box; }
.f360-t-rails { margin-top: 36px; }
.f360-tienda { max-width: 100%; min-width: 0; box-sizing: border-box; }
.f360-t-rail h3 { margin: 0 0 12px; font-size: 13px; font-weight: 700; letter-spacing: .16em; text-transform: uppercase; color: #83734C; }
.f360-t-rail { position: relative; max-width: 100%; overflow: hidden; }
.f360-t-cards { display: grid; grid-auto-flow: column; grid-auto-columns: calc((100% - 4 * 16px) / 5); gap: 16px; overflow-x: auto; scroll-snap-type: x mandatory; scroll-behavior: smooth; scrollbar-width: none; }
.f360-t-cards::-webkit-scrollbar { display: none; }
.f360-t-flecha { position: absolute; top: calc(50% - 10px); width: 40px; height: 40px; border-radius: 50%; border: 1px solid #e6dfd4; background: rgba(255,255,255,.92); cursor: pointer; font-size: 18px; color: #242424; box-shadow: 0 4px 14px rgba(0,0,0,.08); z-index: 2; }
.f360-t-flecha.izq { left: 6px; } .f360-t-flecha.der { right: 6px; }
@media (max-width: 900px) { .f360-t-cards { grid-auto-columns: calc((100% - 2 * 16px) / 3); } }
@media (max-width: 560px) { .f360-t-cards { grid-auto-columns: calc((100% - 16px) / 2); } }
.f360-t-card { scroll-snap-align: start; text-decoration: none; color: inherit; }
.f360-t-card img { width: 100%; aspect-ratio: 3 / 4; object-fit: cover; background: #f5f2ec; border-radius: 4px; display: block; }
.f360-t-card b { display: block; margin-top: 8px; font-size: 14px; font-weight: 500; }
.f360-t-card span { font-size: 13px; color: #6B6B68; }
.f360-tienda { position: sticky; top: var(--f360-sticky-top, 0px); z-index: 50; }
.f360-tienda { transition: transform .25s ease, opacity .25s ease; }
.f360-tienda.f360-t-escondido { transform: translateY(calc(-100% - var(--f360-sticky-top, 0px) - 12px)); opacity: 0; pointer-events: none; }
@media (prefers-reduced-motion: reduce) { .f360-tienda { transition: none; } }
.f360-t-filtros { box-shadow: 0 6px 18px rgba(0,0,0,.05); }
.f360-t-top { display: flex; gap: 10px; align-items: center; }
.f360-t-bwrap { position: relative; flex: 1; }
.f360-t-sug { position: absolute; left: 0; right: 0; top: 48px; margin: 0; padding: 6px 0; list-style: none; background: #fff; border: 1px solid #e6dfd4; border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,.12); max-height: 320px; overflow-y: auto; z-index: 60; }
.f360-t-sug li { padding: 9px 14px; font-size: 14px; cursor: pointer; display: flex; justify-content: space-between; gap: 10px; }
.f360-t-sug { max-height: 420px; }
.f360-t-sug li small { color: #9A9A96; font-size: 12px; }
.f360-t-sug li:hover, .f360-t-sug li[aria-selected="true"] { background: #f7f2ea; }
.f360-t-sug .f360-t-sug-h { cursor: default; font-size: 11px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; color: #83734C; background: none !important; }
.brxe-woocommerce-products-filter.f360-oculto { display: none !important; }
li.product.f360-fuera { display: none !important; }
.f360-t-toggle { flex: 0 0 auto; height: 44px; padding: 0 16px; border: 1px solid #d9d2c5; border-radius: 22px; background: #fff; cursor: pointer; font: inherit; font-size: 13px; color: #4a433a; }
.f360-t-filtros.cerrado .f360-t-cuerpo { display: none; }
.f360-t-hoja-top, .f360-t-pie { display: none; }
.f360-t-filtros.compacto { padding: 10px 14px; }
.f360-t-filtros.compacto .f360-t-res { margin-top: 6px; }
.f360-t-mas-res { margin: 28px 0 0; }
.f360-t-filtros { padding: 16px 18px; border: 1px solid #ece6db; border-radius: 6px; background: #fffdf9; }
.f360-t-buscar { width: 100%; height: 44px; padding: 0 14px; border: 1px solid #d9d2c5; border-radius: 22px; font-size: 15px; font-family: inherit; box-sizing: border-box; }
.f360-t-fila { display: flex; gap: 12px; align-items: flex-start; margin-top: 14px; }
.f360-t-et { flex: 0 0 72px; padding-top: 8px; font-size: 11px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; color: #83734C; }
.f360-t-colores, .f360-t-tallas, .f360-t-cats { display: flex; flex-wrap: wrap; gap: 8px; }
.f360-t-chip { display: inline-flex; align-items: center; gap: 7px; height: 36px; padding: 0 12px; border: 1px solid #d9d2c5; border-radius: 18px; background: #fff; cursor: pointer; font-size: 13px; font-family: inherit; color: #242424; }
.f360-t-chip i { width: 14px; height: 14px; border-radius: 50%; border: 1px solid rgba(0,0,0,.15); }
.f360-t-mas { border-style: dashed; color: #8c6414; }
.f360-t-chip[aria-pressed="true"] { border: 2px solid #B8966E; color: #8c6414; font-weight: 600; }
.f360-t-talla { width: 44px; justify-content: center; padding: 0; }
.f360-t-inm { display: flex; gap: 8px; align-items: center; font-size: 14px; cursor: pointer; }
.f360-t-res { margin: 12px 0 0; font-size: 13px; color: #6B6B68; }
.f360-t-res button { margin-left: 8px; border: 0; background: none; color: #8c6414; text-decoration: underline; cursor: pointer; font: inherit; }
.f360-t-vacio { padding: 28px; text-align: center; color: #6B6B68; }
@media (max-width: 640px) {
  .f360-t-filtros { padding: 10px 12px; }
  .f360-t-fila { flex-direction: column; gap: 6px; margin-top: 12px; }
  .f360-t-et { flex: none; padding-top: 0; }
  .f360-t-chip { flex: 0 0 auto; }
  /* mobile: the filters open as a bottom sheet with its own scroll; the page behind does not move */
  .f360-tienda.f360-hoja-abierta { z-index: 2147483000; }
  .f360-t-velo { position: fixed; inset: 0; background: rgba(0,0,0,.35); z-index: 1; }
  .f360-t-filtros:not(.cerrado) .f360-t-cuerpo { position: fixed; left: 0; right: 0; bottom: 0; top: 10vh; top: 10dvh; z-index: 2; background: #fff; border-radius: 16px 16px 0 0;
    padding: 0 16px; overflow-y: auto; overscroll-behavior: contain; -webkit-overflow-scrolling: touch; box-shadow: 0 -10px 30px rgba(0,0,0,.15); box-sizing: border-box; }
  .f360-t-hoja-top { position: sticky; top: 0; z-index: 1; display: flex; justify-content: space-between; align-items: center; margin: 0 -16px; padding: 14px 16px; background: #fff; border-bottom: 1px solid #f0ebe2; font-size: 16px; }
  .f360-t-x { width: 40px; height: 40px; border: 0 !important; background: none !important; font-size: 20px; color: #242424 !important; cursor: pointer; padding: 0 !important; }
  .f360-t-pie { position: sticky; bottom: 0; display: flex; gap: 10px; margin: 18px -16px 0; padding: 12px 16px calc(12px + env(safe-area-inset-bottom)); background: #fff; border-top: 1px solid #f0ebe2; }
  .f360-t-pie button { display: flex; align-items: center; justify-content: center; padding: 0 !important; text-align: center; height: 48px; border-radius: 24px; font: inherit; font-size: 15px; cursor: pointer; }
  .f360-t-limpiar { flex: 0 0 auto; padding: 0 18px !important; border: 1px solid #d9d2c5 !important; background: #fff !important; color: #4a433a !important; }
  .f360-t-ver { flex: 1; border: 0 !important; background: #242424 !important; color: #fff !important; font-weight: 600; }
  .f360-t-toggle { padding: 0 12px; }
  .f360-t-buscar { font-size: 16px; }   /* 16px: iPhone doesn't zoom in on focus */
}
</style>
<script>
/* Fuxia 360 · filtros de la Tienda. STAGING. Fuente: tools/storefront/f360-tienda.html */
(function () {
  var ENDPOINT = 'https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-store-reserve';   // STAGING
  var pais = (location.pathname.match(/^\/[a-z]{2}\//) || ['/'])[0];
  var mexico = pais === '/' || pais === '/mx/';
  var TALLAS = ['35', '36', '37', '38', '39', '40'];
  var mx = function (t) { return mexico ? String(Number(t) - 13) : t; };   // talla mexicana = talla − 13 (38 → 25)
  var norm = function (s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); };

  function init() {
    var box = document.querySelector('.f360-tienda');
    var grid = document.querySelector('.brxe-woocommerce-products ul.products') || document.querySelector('ul.products');
    if (!box) return;
    if (grid) {
      grid.parentNode.insertBefore(box, grid);
      // below the catalogue: "También te pueden gustar" (few results) and then Más vendidas / Nuevas
      var despues = grid.closest('.brxe-woocommerce-products') || grid;
      despues.parentNode.insertBefore(box.querySelector('.f360-t-rails'), despues.nextSibling);
      despues.parentNode.insertBefore(box.querySelector('.f360-t-mas-res'), despues.nextSibling);
    }
    // the search bar stays visible under the site's sticky header
    var header = document.querySelector('#brx-header');
    var fijar = function () {
      var pos = header ? getComputedStyle(header).position : '';
      var h = header && (pos === 'fixed' || pos === 'sticky') ? Math.max(0, header.getBoundingClientRect().bottom) : 0;
      box.style.setProperty('--f360-sticky-top', Math.round(h + 8) + 'px');
    };
    var pend = false;
    fijar(); window.addEventListener('resize', fijar);
    window.addEventListener('scroll', function () { if (!pend) { pend = true; requestAnimationFrame(function () { pend = false; fijar(); }); } }, { passive: true });
    fetch(ENDPOINT, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'catalog' }) })
      .then(function (r) { return r.json(); })
      .then(function (cat) { arrancar(box, grid, cat.items || [], cat.top_searches || []); })
      .catch(function () { box.hidden = true; });
  }

  // product cards from the store's own data (photo, name, price, link)
  function tarjetas(destino, titulo, ids) {
    destino.innerHTML = '';
    if (!ids.length) { destino.hidden = true; return Promise.resolve(); }
    return fetch(pais + 'wp-json/wc/store/v1/products?per_page=' + ids.length + '&include=' + ids.join(','))
      .then(function (r) { return r.json(); })
      .then(function (prods) {
        var byId = {}; (prods || []).forEach(function (p) { byId[p.id] = p; });
        var lista = ids.map(function (id) { return byId[id]; }).filter(Boolean);
        if (!lista.length) { destino.hidden = true; return; }
        var sec = document.createElement('section'); sec.className = 'f360-t-rail';
        var h = document.createElement('h3'); h.textContent = titulo; sec.appendChild(h);
        var row = document.createElement('div'); row.className = 'f360-t-cards'; sec.appendChild(row);
        lista.forEach(function (p) {
          var a = document.createElement('a'); a.className = 'f360-t-card'; a.href = p.permalink; a.setAttribute('data-f360-product-id', String(p.id));   // ♡ favoritos
          var img = document.createElement('img'); img.loading = 'lazy'; img.alt = p.name; img.src = (p.images && p.images[0] && (p.images[0].thumbnail || p.images[0].src)) || '';
          var b = document.createElement('b'); b.textContent = p.name.replace(/&amp;/g, '&');
          var s = document.createElement('span'); var pr = p.prices || {}; var dec = pr.currency_minor_unit || 0;
          s.textContent = (pr.currency_prefix || '$') + Number(pr.price / Math.pow(10, dec)).toLocaleString('es-MX') + (pr.currency_suffix || '');
          a.appendChild(img); a.appendChild(b); a.appendChild(s); row.appendChild(a);
        });
        // carousel: arrows + turns by itself every 4 s (pauses on hover/touch; respects "reduce motion")
        var paso = function (d) { var w = row.clientWidth; var fin = row.scrollLeft + w >= row.scrollWidth - 4;
          row.scrollTo({ left: d > 0 ? (fin ? 0 : row.scrollLeft + w) : Math.max(0, row.scrollLeft - w) }); };
        if (lista.length > 2) {
          [['izq', '‹', -1], ['der', '›', 1]].forEach(function (f) { var bt = document.createElement('button'); bt.type = 'button'; bt.className = 'f360-t-flecha ' + f[0];
            bt.setAttribute('aria-label', f[2] < 0 ? 'Anteriores' : 'Siguientes'); bt.textContent = f[1]; bt.onclick = function () { paso(f[2]); }; sec.appendChild(bt); });
          var pausa = false, quieto = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
          sec.addEventListener('mouseenter', function () { pausa = true; }); sec.addEventListener('mouseleave', function () { pausa = false; });
          sec.addEventListener('touchstart', function () { pausa = true; }, { passive: true });
          if (!quieto) setInterval(function () { if (!pausa && !document.hidden && row.scrollWidth > row.clientWidth + 4) paso(1); }, 4000);
        }
        destino.appendChild(sec); destino.hidden = false;
      }).catch(function () { destino.hidden = true; });
  }

  function arrancar(box, grid, items, buscados) {
    var porWoo = {};
    items.forEach(function (it) { (porWoo[it.woo_product_id] = porWoo[it.woo_product_id] || []).push(it); });
    var q = function (s) { return box.querySelector(s); };
    var masRes = document.querySelector('.f360-t-mas-res'), rails = document.querySelector('.f360-t-rails');
    var sel = { colores: {}, tallas: {}, texto: '', inm: false, cats: {} };
    var activos = function (o) { return Object.keys(o).filter(function (k) { return o[k]; }); };
    var uno = function (xs) { var seen = {}; return xs.filter(function (it) { if (seen[it.product_id]) return false; seen[it.product_id] = 1; return true; }); };

    var movil = window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
    // show / hide the filters (remembered on this device; on mobile they always start closed — they open as a sheet)
    var filtros = q('.f360-t-filtros'), tog = q('.f360-t-toggle');
    var velo = q('.f360-t-velo'), yHoja = 0, hoja = false;
    // mobile: lock the page behind the sheet (iOS ignores overflow:hidden on body, so pin it in place)
    var hojaMovil = function (abrir) {
      if (!movil || abrir === hoja) return;
      hoja = abrir; velo.hidden = !abrir; box.classList.toggle('f360-hoja-abierta', abrir);
      var b = document.body.style;
      if (abrir) { yHoja = window.scrollY; b.position = 'fixed'; b.top = -yHoja + 'px'; b.left = '0'; b.right = '0'; b.width = '100%'; b.overflow = 'hidden'; }
      else { b.position = b.top = b.left = b.right = b.width = b.overflow = ''; window.scrollTo(0, yHoja); }
    };
    var cerrar = function (c) { hojaMovil(!c); filtros.classList.toggle('cerrado', c); filtros.classList.toggle('compacto', c && compacto); tog.textContent = c ? 'Filtros' : 'Ocultar filtros'; tog.setAttribute('aria-expanded', String(!c)); };
    var prefCerrado = function () { var v = null; try { v = localStorage.getItem('f360-filtros'); } catch (e) {} return movil || (v ? v === 'cerrado' : false); };
    cerrar(prefCerrado());
    tog.onclick = function () { var c = !filtros.classList.contains('cerrado'); cerrar(c); abiertoAMano = !c; if (!compacto) { try { localStorage.setItem('f360-filtros', c ? 'cerrado' : 'abierto'); } catch (e) {} } };
    // while scrolling the catalogue the bar shrinks to the search box + "Filtros" (opens on demand); full again at the top
    var compacto = false, abiertoAMano = false, inicio = box.getBoundingClientRect().top + window.scrollY;
    velo.onclick = q('.f360-t-x').onclick = q('.f360-t-ver').onclick = function () { cerrar(true); if (movil && grid) window.scrollTo(0, Math.max(0, inicio - 10)); };
    q('.f360-t-limpiar').onclick = function () { limpiar(); };
    // Mario 2026-10-06 ("voy a la mitad y no se minimiza"): going DOWN the catalogue the bar gets out of the way; any
    // scroll UP brings it back (compact). Never while the customer is typing, choosing a suggestion or has filters open.
    var ultimoY = window.scrollY;
    window.addEventListener('scroll', function () {
      if (hoja) return;   // the sheet pins the page; ignore its scroll jumps
      var y = window.scrollY, c = y > inicio + 40;
      if (c !== compacto) { compacto = c; abiertoAMano = false; if (c) cerrar(true); else cerrar(prefCerrado()); }
      var baja = y > ultimoY + 6, sube = y < ultimoY - 6;
      if (!baja && !sube) return;
      ultimoY = y;
      var ocupado = !filtros.classList.contains('cerrado') || document.activeElement === input || (sug && !sug.hidden);
      box.classList.toggle('f360-t-escondido', compacto && baja && !ocupado);
    }, { passive: true });

    // colours: one chip per colour name, with its circle (most common first)
    var colores = {}, cuenta = {};
    items.forEach(function (it) { (it.colors || []).forEach(function (c) { var k = norm(c.name); if (!colores[k]) colores[k] = c; cuenta[k] = (cuenta[k] || 0) + 1; }); });
    var orden = Object.keys(colores).sort(function (a, b) { return cuenta[b] - cuenta[a] || a.localeCompare(b); });
    orden.forEach(function (k, i) {
      var b = document.createElement('button'); b.type = 'button'; b.className = 'f360-t-chip'; b.setAttribute('aria-pressed', 'false'); b.dataset.k = k;
      b.innerHTML = '<i></i><span></span>'; b.querySelector('i').style.background = colores[k].hex || '#ddd'; b.querySelector('span').textContent = colores[k].name;
      b.onclick = function () { sel.colores[k] = !sel.colores[k]; b.setAttribute('aria-pressed', String(!!sel.colores[k])); aplicar(); };
      if (i >= 12 && !movil) { b.hidden = true; b.classList.add('f360-t-extra'); }
      q('.f360-t-colores').appendChild(b);
    });
    if (orden.length > 12 && !movil) {
      var mas = document.createElement('button'); mas.type = 'button'; mas.className = 'f360-t-chip f360-t-mas'; mas.textContent = 'Más colores (' + (orden.length - 12) + ')';
      mas.onclick = function () { box.querySelectorAll('.f360-t-extra').forEach(function (b) { b.hidden = false; }); mas.hidden = true; };
      q('.f360-t-colores').appendChild(mas);
    }
    // categories inside the same bar (the separate Bricks category filter is hidden so customers don't get lost)
    var catDe = function (li) { var m = li.className.match(/\bproduct_cat-([a-z0-9-]+)/g) || []; return m.map(function (x) { return x.replace('product_cat-', ''); }); };
    var cats = {};
    if (grid) grid.querySelectorAll(':scope > li.product').forEach(function (li) { catDe(li).forEach(function (c) { cats[c] = (cats[c] || 0) + 1; }); });
    var etiqueta = function (slug) { var t = slug.replace(/-/g, ' '); return t.charAt(0).toUpperCase() + t.slice(1); };
    Object.keys(cats).sort().forEach(function (c) {
      var b = document.createElement('button'); b.type = 'button'; b.className = 'f360-t-chip'; b.setAttribute('aria-pressed', 'false'); b.textContent = etiqueta(c);
      b.onclick = function () { sel.cats[c] = !sel.cats[c]; b.setAttribute('aria-pressed', String(!!sel.cats[c])); aplicar(); };
      q('.f360-t-cats').appendChild(b);
    });
    if (Object.keys(cats).length > 1) {
      q('.f360-t-fila-cat').hidden = false;
      var bf = document.querySelector('.brxe-woocommerce-products-filter'); if (bf && !/[?&]b_product_cat/.test(location.search)) bf.classList.add('f360-oculto');
    }
    q('.f360-t-et-talla').textContent = mexico ? 'Talla MX' : 'Talla';
    TALLAS.forEach(function (t) {
      var b = document.createElement('button'); b.type = 'button'; b.className = 'f360-t-chip f360-t-talla'; b.textContent = mx(t); b.setAttribute('aria-pressed', 'false');
      b.onclick = function () { sel.tallas[t] = !sel.tallas[t]; b.setAttribute('aria-pressed', String(!!sel.tallas[t])); aplicar(); };
      q('.f360-t-tallas').appendChild(b);
    });
    if (mexico) { q('.f360-t-fila-inm').hidden = false; q('.f360-t-inm input').onchange = function (e) { sel.inm = e.target.checked; aplicar(); }; }

    // search with suggestions: models (from Fuxia 360 and the cards on the page) and colours
    var input = q('.f360-t-buscar'), sug = q('.f360-t-sug');
    // one entry per MODEL (Fuxia 360 name), plus store products Fuxia 360 doesn't know yet
    var modelos = {}, enF360 = {};
    items.forEach(function (it) { modelos[norm(it.name)] = it.name; enF360[it.woo_product_id] = 1; });
    if (grid) grid.querySelectorAll(':scope > li.product').forEach(function (li) {
      var m = li.className.match(/\bpost-(\d+)\b/); if (m && enF360[m[1]]) return;
      var h = li.querySelector('h2, h3, h4, h5'); var t = h && h.textContent.trim(); if (t && !modelos[norm(t)]) modelos[norm(t)] = t; });
    var populares = uno(items.filter(function (it) { return it.sold > 0; }).sort(function (a, b) { return b.sold - a.sold; })).slice(0, 5).map(function (it) { return it.name; });
    function sugerir() {
      var t = norm(input.value).trim();
      var ms = Object.keys(modelos).filter(function (k) { return !t || k.indexOf(t) >= 0; }).sort().map(function (k) { return modelos[k]; });
      var cs = orden.filter(function (k) { return t && k.indexOf(t) >= 0; }).slice(0, 5);
      sug.innerHTML = '';
      var add = function (txt, sub, fn, h) { var li = document.createElement('li'); if (h) li.className = 'f360-t-sug-h'; else { li.setAttribute('role', 'option'); li.onmousedown = function (e) { e.preventDefault(); fn(); }; }
        li.appendChild(document.createTextNode(txt)); if (sub) { var sm = document.createElement('small'); sm.textContent = sub; li.appendChild(sm); } sug.appendChild(li); };
      var elegir = function (m) { return function () { input.value = m; sel.texto = norm(m); cerrarSug(); aplicar(); registrar(m); }; };
      var cs0 = Object.keys(cats).sort().filter(function (c) { return !t || norm(etiqueta(c)).indexOf(t) >= 0; });
      if (cs0.length > 1 || (t && cs0.length)) { add('Categorías', '', null, true); cs0.forEach(function (c) { add(etiqueta(c), cats[c] + ' modelos', function () {
        input.value = ''; sel.texto = ''; sel.cats = {}; sel.cats[c] = true;
        box.querySelectorAll('.f360-t-cats .f360-t-chip').forEach(function (b) { b.setAttribute('aria-pressed', String(b.textContent === etiqueta(c))); });
        cerrarSug(); aplicar(); }); }); }
      if (!t && buscados.length) { add('Más buscados', '', null, true); buscados.forEach(function (m) { add(m, '', elegir(m)); }); }
      else if (!t && populares.length) { add('Populares', '', null, true); populares.forEach(function (m) { add(m, '', elegir(m)); }); }
      if (ms.length) { add(t ? 'Modelos' : 'Todos los modelos (' + ms.length + ')', '', null, true); ms.forEach(function (m) { add(m, '', elegir(m)); }); }
      if (cs.length) { add('Colores', '', null, true); cs.forEach(function (k) { add(colores[k].name, 'filtrar por color', function () {
        input.value = ''; sel.texto = ''; sel.colores[k] = true; var b = q('.f360-t-chip[data-k="' + k + '"]'); if (b) { b.hidden = false; b.setAttribute('aria-pressed', 'true'); } cerrarSug(); aplicar(); }); }); }
      sug.hidden = !sug.children.length; input.setAttribute('aria-expanded', String(!sug.hidden));
    }
    // what customers look for (to build "Más buscados"): sent once per term, no personal data
    var enviados = {};
    function registrar(t) {
      t = String(t || '').trim().slice(0, 60); var k = norm(t); if (k.length < 3 || enviados[k]) return; enviados[k] = 1;
      fetch(ENDPOINT, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'search_log', term: t, country: mexico ? 'mx' : pais.replace(/\//g, '') }), keepalive: true }).catch(function () {});
    }
    function cerrarSug() { sug.hidden = true; input.setAttribute('aria-expanded', 'false'); }
    input.addEventListener('focus', sugerir);
    input.addEventListener('blur', function () { setTimeout(cerrarSug, 120); });
    var tm; input.addEventListener('input', function () { sugerir(); clearTimeout(tm); tm = setTimeout(function () { sel.texto = norm(input.value).trim(); aplicar(); }, 150); });
    input.addEventListener('keydown', function (e) { if (e.key === 'Escape') { cerrarSug(); input.blur(); } if (e.key === 'Enter') { e.preventDefault(); cerrarSug(); registrar(input.value); } });
    input.addEventListener('change', function () { registrar(input.value); });

    function cumple(it, c, cols, tal, inm) {
      if (cols.length && cols.indexOf(norm(c.name)) < 0) return false;
      var ok = function (st) { return inm ? st === 'inmediata' : (st === 'inmediata' || st === 'pedido'); };
      if (tal.length) return tal.some(function (t) { return ok((c.sizes || {})[t]); });
      return Object.keys(c.sizes || {}).some(function (t) { return ok(c.sizes[t]); });
    }
    function pasa(woo, nombre) {
      var lista = porWoo[woo] || [];
      var cols = activos(sel.colores), tal = activos(sel.tallas);
      if (sel.texto) {
        var hay = norm(nombre).indexOf(sel.texto) >= 0 || lista.some(function (it) { return norm(it.name).indexOf(sel.texto) >= 0 ||
          (it.colors || []).some(function (c) { return norm(c.name).indexOf(sel.texto) >= 0; }); });
        if (!hay) return false;
      }
      if (!cols.length && !tal.length && !sel.inm) return true;
      if (!lista.length) return false;                       // without Fuxia 360 data we cannot promise colour/size
      return lista.some(function (it) { return (it.colors || []).some(function (c) { return cumple(it, c, cols, tal, sel.inm); }); });
    }
    function aplicar() {
      if (!grid) return;
      var cards = grid.querySelectorAll(':scope > li.product'), n = 0, visibles = {};
      cards.forEach(function (li) {
        var m = li.className.match(/\bpost-(\d+)\b/); var nombre = (li.querySelector('h2, h3, h4, h5') || {}).textContent || '';
        var cs = activos(sel.cats);
        var ver = (!cs.length || catDe(li).some(function (c) { return cs.indexOf(c) >= 0; })) && (!m || pasa(Number(m[1]), nombre));
        // inline + !important: the theme forces "display" on the cards (it beat a plain style on mobile)
        if (ver) li.style.removeProperty('display'); else li.style.setProperty('display', 'none', 'important');
        li.classList.toggle('f360-fuera', !ver); if (ver) { n++; if (m) visibles[m[1]] = 1; }
      });
      var cols = activos(sel.colores), tal = activos(sel.tallas);
      var activo = sel.texto || sel.inm || cols.length || tal.length || activos(sel.cats).length;
      q('.f360-t-ver').textContent = activo ? (n ? 'Ver ' + n + (n === 1 ? ' modelo' : ' modelos') : 'Sin resultados') : 'Ver todos los modelos';
      var res = q('.f360-t-res'); res.textContent = activo ? (n ? n + (n === 1 ? ' modelo' : ' modelos') : 'No encontramos ese color y talla.') : '';
      if (activo) {
        var b = document.createElement('button'); b.type = 'button'; b.textContent = 'Limpiar filtros'; b.onclick = limpiar; res.appendChild(b);
        if (!n) res.appendChild(document.createTextNode(' ¿Te lo hacemos a la medida? Abre cualquier modelo y pregúntale a Hilo.'));
      }
      // few results → "También te pueden gustar": same colour in 10 días hábiles / other sizes, or your size in other colours
      if (activo && n < 4 && (cols.length || tal.length || sel.inm)) {
        var cand = uno(items.filter(function (it) {
          if (visibles[it.woo_product_id]) return false;
          return (it.colors || []).some(function (c) { return (cols.length && cumple(it, c, cols, tal, false)) || (cols.length && cumple(it, c, cols, [], false)) || (tal.length && cumple(it, c, [], tal, false)); });
        }).sort(function (a, b) { return b.sold - a.sold; })).slice(0, 8);
        tarjetas(masRes, 'También te pueden gustar', cand.map(function (it) { return it.woo_product_id; }));
      } else { masRes.hidden = true; masRes.innerHTML = ''; }
    }
    function limpiar() {
      sel = { colores: {}, tallas: {}, texto: '', inm: false, cats: {} };
      box.querySelectorAll('.f360-t-chip:not(.f360-t-mas)').forEach(function (b) { b.setAttribute('aria-pressed', 'false'); });
      input.value = ''; var c = q('.f360-t-inm input'); if (c) c.checked = false;
      aplicar();
    }

    // after the catalogue: Más vendidas and Nuevas (main shop page only)
    if (/[?&]b_product_cat/.test(location.search)) return;
    var top = uno(items.filter(function (it) { return it.sold > 0; }).sort(function (a, b) { return b.sold - a.sold; })).slice(0, 10);
    var nuevas = uno(items.filter(function (it) { return it.is_new; })).slice(0, 10);
    var r1 = document.createElement('div'), r2 = document.createElement('div'); rails.appendChild(r1); rails.appendChild(r2);
    tarjetas(r1, 'Más vendidas', top.map(function (it) { return it.woo_product_id; }));
    tarjetas(r2, 'Nuevas', nuevas.map(function (it) { return it.woo_product_id; }));
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
</script>
F360SNIP
      . substr($page, $end + strlen('</script>'));
  });
}, 1);
