<?php
/**
 * Plugin Name: Fuxia 360 · Ficha de producto en celular, paso 1 (producción)
 * Description: Mario 2026-10-09 ("mejoremos el UX de producto sobre todo en móvil… la gran mayoría son señoras"; propuesta
 *              https://claude.ai/artifact/D1SHyjvk21R5sQUBJ6RFYR, decisiones 1–3 aprobadas). Product pages only:
 *              · the reviews block (CusRev #reviews + Woo's star line) is hidden while the product has fewer than 3 reviews;
 *              · the "Precios en MXN / COP / USD" selector is hidden: the price is already the visitor's country's (/mx/, /co/);
 *              · "Descarga la app" does not float over the product page;
 *              · the button reads "Agregar al carrito";
 *              · on phones (≤ 900 px): bigger, darker title / price / description, 48 px colour and size buttons, and a bar fixed
 *                at the bottom with model, colour, size, price and "Agregar al carrito". The bar has NO purchase logic: it mirrors
 *                Woo's own button (missing colour / size / unavailable) and clicks it, so price, stock and validation stay Woo's.
 *                It shows only while Woo's button is off screen.
 *              Paso 2 (same date, phones ≤ 900 px only, the approved mockup): name + price ABOVE the photos; no breadcrumb and no
 *              thumbnail strip; dots and a "1 / 8" counter on Woo's own slider (swipe); the first colour comes pre-chosen; big pill colours and a 6-column size grid
 *              with "¿Cuál es mi talla?" (no size conversion: the bar repeats the number on the tapped button); no quantity box; the bottom bar is THE buy button (always visible, "Camel · 24 · $2,800"; Woo's button is hidden and clicked by it); three
 *              trust tiles; description and "Envíos y cambios" in closed sections; the WhatsApp size help as a card. The delivery promise is NOT here: production Woo
 *              has no real stock and f360-storefront is not deployed there yet, so a promise would be a guess.
 *              Promise + knowledge (Mario: "sí instala lo de entrega inmediata"): the chosen size's delivery promise from Fuxia 360
 *              (real inventory; rule texts from f360.delivery_promise_rules), sizes that are made to order drawn dashed, fit advice and
 *              "Materiales y cuidados" from Carolina's validated product knowledge — via f360-storefront action pdp (read-only).
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only

add_filter('woocommerce_product_single_add_to_cart_text', function () { return 'Agregar al carrito'; }, 99);

add_action('wp_head', function () {
  if (is_admin() || isset($_GET['bricks']) || !function_exists('is_product') || !is_product()) return;
  $product = wc_get_product(get_queried_object_id());
  $few_reviews = !$product || (int) $product->get_review_count() < 3;
  echo "<style id=\"f360-ficha-celular\">\n";
  if ($few_reviews) echo "#reviews,.woocommerce-product-rating,.cr-all-reviews-shortcode{display:none!important}\n";
  echo <<<'F360CSS'
#fx-paisprice{display:none!important}
#fx-app-btn{display:none!important}
@media (max-width:900px){
  .brxe-product-title{font-size:24px!important;line-height:1.25!important;color:#1d1a16!important;font-weight:500!important}
  .f360-fc-top .brxe-product-price,.brxe-product-title + .brxe-product-price,.brxe-product-title + .brxe-product-price .price{font-size:22px!important;color:#1d1a16!important;font-weight:700!important}
  .brxe-product-content,.brxe-product-content p,.brxe-product-short-description p{font-size:16px!important;line-height:1.6!important;color:#3d3730!important}
  .fuxia-talla,.f360-colores-botones button,.f360-colores-botones a{min-height:48px!important;min-width:48px!important;font-size:16px!important}
  .fuxia-guia-link{display:inline-block;padding:10px 0;font-size:15px!important}
  .single_add_to_cart_button{min-height:54px!important;font-size:16px!important}
}
.f360-fc{display:none}
@media (max-width:900px){
  .f360-fc{position:fixed;left:0;right:0;bottom:0;z-index:9990;display:flex;gap:12px;align-items:center;box-sizing:border-box;
    padding:10px 14px calc(10px + env(safe-area-inset-bottom));background:#fff;border-top:1px solid #ece6db;box-shadow:0 -6px 18px rgba(0,0,0,.08);
    transform:translateY(110%);transition:transform .2s ease;pointer-events:none}
  .f360-fc.on{transform:none;pointer-events:auto}
  .f360-fc-info{flex:1;min-width:0;line-height:1.25}
  .f360-fc-det{display:block;font-size:13px;color:#6b6257;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .f360-fc-precio{display:block;font-size:17px;font-weight:700;color:#1d1a16;white-space:nowrap}
  .f360-fc-btn{flex:0 0 auto;height:52px;padding:0 20px!important;border:0!important;border-radius:14px!important;background:#1d1a16!important;color:#fff!important;
    font:inherit;font-size:16px!important;font-weight:700;cursor:pointer}
  .f360-fc-btn.no{background:#cfc8bc!important}
  html.f360-fc-visible #fh-root{--fh-lift:calc(var(--f360-fc-h,74px) - 6px)!important}   /* Hilo sube encima de la barra */
  .f360-fc-pulso{animation:f360fcp 1.2s ease 1;border-radius:8px}
  @keyframes f360fcp{0%,100%{box-shadow:0 0 0 0 rgba(156,122,69,0)}30%{box-shadow:0 0 0 6px rgba(156,122,69,.45)}}
}
@media (max-width:900px){
  /* Paso 2 · the page in the order and look of the approved mockup */
  main#brx-content > .brxe-section:first-child > .brxe-container,main#brx-content #brxe-ifvsvi{margin-top:6px!important}
  .f360-fc-top{padding:6px 16px 14px}
  .f360-fc-top .brxe-product-title{margin:0!important;font-family:'Montserrat',system-ui,sans-serif!important;font-size:23px!important;font-weight:600!important;line-height:1.25!important}
  .f360-fc-top .brxe-product-price,.f360-fc-top .brxe-product-price *{font-family:'Montserrat',system-ui,sans-serif!important;font-size:21px!important;font-weight:700!important;color:#1d1a16!important}
  .f360-fc-top .brxe-product-price{margin:4px 0 0!important}
  nav.fuxia-breadcrumb{display:none!important}
  .brxe-product-gallery .flex-control-thumbs{display:none!important}
  .woocommerce-product-gallery{position:relative}
  .f360-fc-cnt{position:absolute;right:12px;bottom:12px;z-index:5;background:rgba(17,17,17,.72);color:#fff;font-size:13px;font-weight:600;padding:4px 10px;border-radius:999px;pointer-events:none}
  .f360-fc-dots{display:flex;gap:6px;justify-content:center;padding:12px 0 2px}
  .f360-fc-dots i{width:8px;height:8px;border-radius:50%;background:#d6cec1}
  .f360-fc-dots i.on{width:22px;border-radius:4px;background:#1d1a16}
  /* colour */
  .f360-colores{margin:18px 0 6px!important}
  .f360-colores-header{justify-content:flex-start!important;gap:6px;margin-bottom:10px!important}
  .f360-colores-header span:first-child{text-transform:none!important;letter-spacing:0!important;font-size:16px!important;color:#1d1a16}
  .f360-colores-header span:first-child::after{content:':'}
  .f360-color-nombre{font-size:16px!important;color:#6b6257!important}
  .f360-color{height:48px!important;padding:0 16px!important;border-radius:999px!important;border:1.5px solid #d9d1c4!important;font-size:15px!important;color:#1d1a16!important}
  .f360-color.selected{border:2px solid #1d1a16!important;color:#1d1a16!important;box-shadow:inset 0 0 0 1px #1d1a16}
  .f360-color .f360-punto{width:22px!important;height:22px!important}
  /* colours with their Fuxia 360 circle: just the circle, like the mockup (a colour without one keeps its name) */
  .f360-colores-botones{gap:12px!important}
  .f360-colores-botones .f360-color:has(.f360-punto[style*="background"]){width:58px!important;height:58px!important;padding:3px!important;border-radius:50%!important;font-size:0!important;gap:0!important;border:0!important;box-shadow:0 0 0 1.5px #d9d1c4!important;background:#fff!important}
  .f360-colores-botones .f360-color:has(.f360-punto[style*="background"]) .f360-punto{width:100%!important;height:100%!important;border:0!important}
  .f360-colores-botones .f360-color.selected:has(.f360-punto[style*="background"]){box-shadow:0 0 0 3px #1d1a16!important}
  .f360-color-nombre{font-weight:500!important}
  .f360-fc-tsel{font-weight:500;color:#6b6257;margin-left:4px}
  /* size */
  .fuxia-tallas{margin:18px 0 0!important}
  .fuxia-tallas-header{margin-bottom:10px!important}
  .fuxia-tallas-header > span{text-transform:none!important;letter-spacing:0!important;font-size:16px!important;font-weight:600!important;color:#1d1a16}
  .f360-fc-cual{font-size:15px;color:#8a6a35;text-decoration:underline;text-underline-offset:3px;background:none;border:0;padding:8px 0;cursor:pointer;font-family:inherit}
  .fuxia-tallas-botones{display:grid!important;grid-template-columns:repeat(6,1fr);gap:8px!important;margin-bottom:0!important}
  .fuxia-talla{width:auto!important;height:52px!important;min-width:0!important;border:1.5px solid #d9d1c4!important;border-radius:12px!important;font-size:17px!important;font-weight:600!important;color:#1d1a16!important;background:#fff!important}
  .fuxia-tallas-botones .fuxia-talla.selected{background:#1d1a16!important;color:#fff!important;border:1.5px solid #1d1a16!important}
  .fuxia-talla.agotada,.fuxia-talla[disabled]{border-style:dashed!important;color:#b0a79a!important}
  .fuxia-guia-link{display:none!important}
  /* buy */
  form.variations_form .quantity,form.cart .quantity{display:none!important}
  /* the buy button is the bar at the bottom (always visible); Woo's own button stays in the form, hidden, and the bar clicks it */
  form.variations_form .single_add_to_cart_button,form.cart .single_add_to_cart_button{display:none!important}
  .woocommerce-variation-add-to-cart{margin:0!important}
  #fx-trust{display:none!important}
  .f360-fc-trust{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin:14px 0 0}
  .f360-fc-trust div{background:#f6f2ea;border-radius:12px;padding:10px 6px;text-align:center;font-size:13px;line-height:1.3;color:#1d1a16}
  .f360-fc-trust span{display:block;font-size:18px;margin-bottom:2px}
  /* details */
  .f360-fc-acc{margin:18px 0 0;border-top:1px solid #ece6db}
  .f360-fc-acc details{border-bottom:1px solid #ece6db}
  .f360-fc-acc summary{list-style:none;display:flex;justify-content:space-between;align-items:center;padding:16px 0;font-size:16px;font-weight:600;color:#1d1a16;cursor:pointer}
  .f360-fc-acc summary::-webkit-details-marker{display:none}
  .f360-fc-acc summary::after{content:'+';font-size:22px;font-weight:400;color:#6b6257}
  .f360-fc-acc details[open] summary::after{content:'\2212'}
  .f360-fc-acc .f360-fc-acc-body{padding:0 0 16px;font-size:16px;line-height:1.6;color:#3d3730}
  .f360-fc-acc .f360-fc-acc-body p{margin:0 0 8px}
  /* delivery promise of the chosen size + Carolina's knowledge (Fuxia 360, f360-storefront action pdp) */
  .f360-fc-prom{margin:14px 0 0;border-radius:12px;padding:12px 14px;font-size:16px;font-weight:600;line-height:1.35}
  .f360-fc-prom.in_stock{background:#e6f0e8;color:#235236}
  .f360-fc-prom.made_to_order{background:#f6efe2;color:#6b4f22}
  .f360-fc-prom.unavailable{background:#eeeae4;color:#5c554c}
  .f360-fc-prom small{display:block;font-weight:500;font-size:14px;margin-top:2px}
  .fuxia-tallas-botones .fuxia-talla.f360-fc-mto:not(.selected){border-style:dashed!important;color:#9a9083!important}
  .f360-fc-acc dl{margin:0;display:grid;grid-template-columns:auto 1fr;gap:6px 14px}
  .f360-fc-acc dt{color:#6b6257}
  .f360-fc-acc dd{margin:0;color:#1d1a16}
  /* help */
  .joinchat__woo-btn__wrapper.f360-fc-help{margin:16px 0 8px!important}
  .f360-fc-help .joinchat__woo-btn{display:flex!important;align-items:center;gap:10px;width:100%;background:#f6f2ea!important;color:#1d1a16!important;border-radius:14px!important;padding:14px!important;font-size:14px!important;line-height:1.35;text-align:left;box-shadow:none!important}
  .f360-fc-help .joinchat__woo-btn::before,.f360-fc-help .joinchat__woo-btn::after{display:none!important}
  .f360-fc-help b{display:block;font-size:15px}
  .f360-fc-help .f360-fc-wa{margin-left:auto;background:#25D366;color:#fff;font-weight:700;border-radius:999px;padding:9px 14px;white-space:nowrap}
}
@media (prefers-reduced-motion:reduce){.f360-fc{transition:none}}
F360CSS;
  echo "</style>\n";
}, 99);

add_action('wp_footer', function () {
  if (is_admin() || isset($_GET['bricks']) || !function_exists('is_product') || !is_product()) return;
  echo <<<'F360SNIP'
<script>
/* Fuxia 360 · ficha en celular, paso 1 (mu-plugin f360-ficha-celular.php): barra fija "Agregar al carrito". */
(function () {
  var form = null;
  function init() {
    form = document.querySelector('form.variations_form') || document.querySelector('form.cart');
    try { paso2(); } catch (e) { /* layout tweaks never block buying */ }
    var real = form && form.querySelector('.single_add_to_cart_button');
    if (!real || !('IntersectionObserver' in window)) return;
    var mexico = !/^\/co\//.test(location.pathname);
    var bar = document.createElement('div');
    bar.className = 'f360-fc'; bar.setAttribute('aria-hidden', 'true');
    bar.innerHTML = '<div class="f360-fc-info"><span class="f360-fc-det"></span><span class="f360-fc-precio"></span></div><button type="button" class="f360-fc-btn">Agregar al carrito</button>';
    document.body.appendChild(bar);
    var btn = bar.querySelector('.f360-fc-btn'), html = document.documentElement;
    var h1 = document.querySelector('h1.brxe-product-title, h1.product_title, h1');
    var nombre = h1 ? h1.textContent.trim() : '';
    var limpio = function (t) { return (t || '').trim().replace(/\s+/g, ' '); };
    var precioBase = limpio((document.querySelector('.brxe-product-price .price, .summary .price, p.price') || {}).textContent);
    var precio = precioBase;
    var sel = function (n) { return form.querySelector('select[name="attribute_pa_' + n + '"]'); };
    var texto = function (s) { return s && s.value ? limpio((s.options[s.selectedIndex] || {}).text || s.value) : ''; };
    var falta = function () {
      var c = sel('color'), m = sel('medida');
      return c && !c.value ? 'color' : (m && !m.value ? 'talla' : (real.classList.contains('wc-variation-selection-needed') ? 'opcion' : ''));
    };
    var estado = function () {
      var f = falta(), noDisp = real.classList.contains('wc-variation-is-unavailable');
      var c = sel('color'), m = sel('medida'), partes = [];
      if (c && c.value) partes.push(texto(c));
      if (m && m.value) {                             // exactly the number on the size button the customer tapped
        var tb = document.querySelector('.fuxia-talla[data-co="' + m.value + '"]');
        partes.push(tb ? tb.textContent.trim() : texto(m));
      }
      bar.querySelector('.f360-fc-det').textContent = partes.length ? partes.join(' · ') : nombre;
      bar.querySelector('.f360-fc-precio').textContent = precio;
      btn.classList.toggle('no', !f && noDisp);
      btn.textContent = f === 'color' ? 'Elige tu color' : f === 'talla' ? 'Elige tu talla' : f ? 'Elige una opción' : noDisp ? 'No disponible' : 'Agregar al carrito';
    };
    var ir = function (cual) {
      var dest = cual === 'color' ? document.querySelector('.f360-colores') : document.querySelector('.fuxia-tallas');
      if (!dest || !dest.offsetParent) dest = form;
      dest.scrollIntoView({ behavior: 'smooth', block: 'center' });
      dest.classList.remove('f360-fc-pulso'); void dest.offsetWidth; dest.classList.add('f360-fc-pulso');
    };
    btn.addEventListener('click', function () {
      var f = falta();
      if (f) { ir(f); return; }
      if (real.classList.contains('wc-variation-is-unavailable') || real.disabled) { ir('talla'); return; }
      real.click();                                   // Woo's own button: same form, same server rules
    });
    if (window.jQuery) {
      window.jQuery(form).on('found_variation', function (e, v) {
        var t = '';
        if (v && v.price_html) { var d = document.createElement('div'); d.innerHTML = v.price_html; t = limpio(d.textContent); }
        precio = t || precioBase; setTimeout(estado, 0);
      });
      window.jQuery(form).on('reset_data hide_variation woocommerce_variation_has_changed', function () { precio = precioBase; setTimeout(estado, 0); });
    }
    if (window.MutationObserver) new MutationObserver(estado).observe(real, { attributes: true, attributeFilter: ['class', 'disabled'] });
    form.addEventListener('change', function () { setTimeout(estado, 0); });
    estado();
    if (window.matchMedia('(max-width: 900px)').matches) {      // phones: the bar IS the buy button, always there
      bar.classList.add('on'); bar.setAttribute('aria-hidden', 'false'); html.classList.add('f360-fc-visible');
      html.style.setProperty('--f360-fc-h', bar.offsetHeight + 'px');
      document.body.style.paddingBottom = (bar.offsetHeight + 8) + 'px';
      return;
    }
    var visible = false;
    new IntersectionObserver(function (es) {
      var ver = !es[0].isIntersecting;
      if (ver === visible) return; visible = ver;
      bar.classList.toggle('on', ver); bar.setAttribute('aria-hidden', String(!ver));
      html.classList.toggle('f360-fc-visible', ver && window.matchMedia('(max-width: 900px)').matches);
      html.style.setProperty('--f360-fc-h', bar.offsetHeight + 'px');
    }, { threshold: 0 }).observe(real);
  }

  // ── Paso 2 (phones only) ──
  function paso2() {
    if (!window.matchMedia('(max-width: 900px)').matches) return;
    var mexico = !/^\/co\//.test(location.pathname);   // only for the trust tiles (6 MSI is Mexico's)
    // name + price above the photos (the real nodes move, so Woo keeps updating them)
    var gal = document.querySelector('.brxe-product-gallery');
    var h1 = document.querySelector('h1.brxe-product-title');
    // the price is the first price block next to the name (some models have a rating block in between)
    var hermanos = h1 ? [].slice.call(h1.parentNode.children) : [];
    var price = hermanos.filter(function (e) { return e.classList.contains('brxe-product-price'); })[0] || null;
    var rating = hermanos.filter(function (e) { return e.classList.contains('brxe-product-rating'); })[0] || null;
    if (gal && h1) {
      var top = document.createElement('div'); top.className = 'f360-fc-top';
      gal.parentNode.insertBefore(top, gal);
      top.appendChild(h1); if (price) top.appendChild(price); if (rating) top.appendChild(rating);
    }
    // gallery: counter + arrows on Woo's own slider
    var g = document.querySelector('.woocommerce-product-gallery');
    var slides = g ? g.querySelectorAll('.woocommerce-product-gallery__image') : [];
    if (g && slides.length > 1) {
      var cnt = document.createElement('span'); cnt.className = 'f360-fc-cnt'; g.appendChild(cnt);
      var dots = document.createElement('div'); dots.className = 'f360-fc-dots';
      var nd = Math.min(slides.length, 6);
      for (var k = 0; k < nd; k++) dots.appendChild(document.createElement('i'));
      g.parentNode.insertBefore(dots, g.nextSibling);
      var pinta = function () {
        var i = 0; slides.forEach(function (s, k) { if (s.classList.contains('flex-active-slide')) i = k; });
        cnt.textContent = (i + 1) + ' / ' + slides.length;
        var on = Math.min(i, nd - 1);
        [].forEach.call(dots.children, function (d, k) { d.classList.toggle('on', k === on); });
      };
      pinta();
      if (window.MutationObserver) slides.forEach(function (s) { new MutationObserver(pinta).observe(s, { attributes: true, attributeFilter: ['class'] }); });
    }
    // like the mockup, the page opens with a colour already chosen (the first one), so she only picks her size
    var tries = 0, preelige = function () {
      var cs = form && form.querySelector('select[name="attribute_pa_color"]'), b = document.querySelector('.f360-colores-botones .f360-color');
      if (cs && cs.value) return;
      if (cs && b) { b.click(); return; }
      if (++tries < 30) setTimeout(preelige, 100);
    };
    preelige();
    // "Talla: 24" — the number of the tapped button, next to the label
    var tlab = document.querySelector('.fuxia-tallas-header > span');
    if (tlab && form) {
      var tsel = document.createElement('span'); tsel.className = 'f360-fc-tsel'; tlab.appendChild(tsel);
      var pon = function () { var b = document.querySelector('.fuxia-talla.selected'); tsel.textContent = b ? b.textContent.trim() : ''; tlab.firstChild.nodeValue = b ? 'Talla:' : 'Talla'; };
      document.addEventListener('click', function (e) { if (e.target.closest && e.target.closest('.fuxia-talla')) setTimeout(pon, 0); });
      if (window.jQuery) window.jQuery(form).on('reset_data', function () { setTimeout(pon, 0); });
      pon();
    }
    // "¿Cuál es mi talla?" next to the size label (opens the size guide window)
    var guia = document.querySelector('a.fuxia-guia-link'), th = document.querySelector('.fuxia-tallas-header');
    if (guia && th) {
      var cual = document.createElement('button'); cual.type = 'button'; cual.className = 'f360-fc-cual'; cual.textContent = '¿Cuál es mi talla?';
      cual.addEventListener('click', function () { guia.click(); });
      var sis = th.querySelector('.fuxia-sistema');
      if (sis && sis.offsetParent) th.parentNode.insertBefore(cual, th.nextSibling); else th.appendChild(cual);
    }
    // after the buy button: three trust tiles, then the details in closed sections, then the WhatsApp help
    var bloque = form && (form.closest('.brxe-product-add-to-cart') || form);
    if (bloque) {
      var trust = document.createElement('div'); trust.className = 'f360-fc-trust';
      trust.innerHTML = mexico
        ? '<div><span>\uD83D\uDE9A</span>Envío gratis</div><div><span>\uD83D\uDCB3</span>6 meses sin intereses</div><div><span>\u21BA</span>Cambios en 30 días</div>'
        : '<div><span>\uD83D\uDE9A</span>Envío gratis</div><div><span>\uD83D\uDD12</span>Pago seguro</div><div><span>\u21BA</span>Cambios en 30 días</div>';
      var acc = document.createElement('div'); acc.className = 'f360-fc-acc';
      var sec = function (titulo, nodo) {
        var d = document.createElement('details'), sm = document.createElement('summary'), body = document.createElement('div');
        sm.textContent = titulo; body.className = 'f360-fc-acc-body'; body.appendChild(nodo); d.appendChild(sm); d.appendChild(body); acc.appendChild(d);
      };
      var desc = document.querySelector('.brxe-product-content');
      if (desc && desc.textContent.trim()) sec('Cómo es este zapato', desc);
      var pol = document.createElement('div');
      pol.innerHTML = '<p><b>Envío gratis</b> en México y Colombia.</p><p><b>Cambios en 30 días</b> por otra talla, color o modelo, sin uso y con su caja. No hacemos devoluciones ni reembolsos.</p><p>Los pares con descuento directo en el precio no tienen cambio; si usaste un cupón, sí.</p>';
      sec('Envíos y cambios', pol);
      pdp(acc);
      var despues = bloque.nextSibling;
      bloque.parentNode.insertBefore(trust, despues);
      bloque.parentNode.insertBefore(acc, despues);
      var wa = document.querySelector('.joinchat__woo-btn__wrapper'), wb = wa && wa.querySelector('.joinchat__woo-btn');
      if (wa && wb) {
        wa.classList.add('f360-fc-help');
        wb.innerHTML = '<span><b>¿Dudas con tu talla?</b>Te contestamos por WhatsApp</span><span class="f360-fc-wa">Escríbenos</span>';
        bloque.parentNode.insertBefore(wa, despues);
      }
    }
  }

  // Fuxia 360: promise per size (real inventory: Bodega + stores − Gold holds) and Carolina's validated knowledge. Read-only.
  function pdp(acc) {
    var pidAttr = form && Number(form.getAttribute('data-product_id'));
    if (!pidAttr) return;
    var market = /^\/co\//.test(location.pathname) ? 'CO' : 'MX';
    var vars = []; try { vars = JSON.parse(form.getAttribute('data-product_variations') || '[]') || []; } catch (e) { vars = []; }
    fetch('https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-storefront', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'pdp', woo_product_id: pidAttr, market: market }) })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) {
        if (!d) return;
        var P = d.variations || {}, k = d.knowledge;
        // promise box under the sizes
        var botones = document.querySelector('.fuxia-tallas-botones');
        var box = document.createElement('div'); box.className = 'f360-fc-prom'; box.hidden = true;
        if (botones) botones.parentNode.insertBefore(box, botones.nextSibling);
        var colorSel = form.querySelector('select[name="attribute_pa_color"]'), m = form.querySelector('select[name="attribute_pa_medida"]');
        var vid = function (color, size) {
          for (var i = 0; i < vars.length; i++) { var a = vars[i].attributes || {};
            if ((!colorSel || a.attribute_pa_color === color || a.attribute_pa_color === '') && String(a.attribute_pa_medida) === String(size)) return vars[i].variation_id; }
          return null;
        };
        var pinta = function () {
          var color = colorSel ? colorSel.value : '';
          document.querySelectorAll('.fuxia-talla').forEach(function (b) {
            var pr = (colorSel && !color) ? null : P[String(vid(color, b.getAttribute('data-co')))];
            b.classList.toggle('f360-fc-mto', !!pr && pr.case !== 'in_stock');
          });
          // the variation Woo resolved (also for models with > 30 combinations, whose list Woo loads on demand)
          var vInput = form.querySelector('input.variation_id, input[name="variation_id"]');
          var chosen = vInput && Number(vInput.value) > 0 ? vInput.value : (m && m.value ? vid(color, m.value) : null);
          var pr = m && m.value && chosen ? P[String(chosen)] : null;
          if (!pr || !pr.headline) { box.hidden = true; return; }
          box.className = 'f360-fc-prom ' + (pr.case || '');
          box.textContent = (pr.case === 'in_stock' ? '\u2713 ' : '') + pr.headline;
          if (pr.detail) { var sm = document.createElement('small'); sm.textContent = pr.detail; box.appendChild(sm); }
          box.hidden = false;
        };
        form.addEventListener('change', function () { setTimeout(pinta, 0); });
        document.addEventListener('click', function (e) { if (e.target.closest && e.target.closest('.fuxia-talla, .f360-color')) setTimeout(pinta, 30); });
        if (window.jQuery) window.jQuery(form).on('woocommerce_variation_has_changed reset_data found_variation', function () { setTimeout(pinta, 0); });
        pinta();
        // knowledge: fit advice at the top of "Cómo es este zapato"; materials + care in their own section
        if (!k || !acc) return;
        var esc = function (t) { var x = document.createElement('span'); x.textContent = String(t); return x.innerHTML; };
        var first = acc.querySelector('details .f360-fc-acc-body');
        var fit = [k.fit && k.fit.advice, k.fit && k.fit.between_sizes, k.last ? 'Horma: ' + k.last : ''].filter(Boolean);
        if (first && fit.length) { var fp = document.createElement('p'); fp.innerHTML = '<b>' + esc(fit.join(' ')) + '</b>'; first.insertBefore(fp, first.firstChild); }
        var rows = [], mt = k.materials || {};
        if (mt.upper) rows.push(['Exterior', mt.upper]); if (mt.lining) rows.push(['Forro', mt.lining]); if (mt.sole) rows.push(['Suela', mt.sole]);
        if (k.toe) rows.push(['Punta', k.toe]); if (k.heel_height_cm != null) rows.push(['Tacón', k.heel_height_cm + ' cm']);
        if (!rows.length && !k.care) return;
        var d2 = document.createElement('details'), s2 = document.createElement('summary'), b2 = document.createElement('div');
        s2.textContent = 'Materiales y cuidados'; b2.className = 'f360-fc-acc-body';
        b2.innerHTML = (rows.length ? '<dl>' + rows.map(function (r) { return '<dt>' + esc(r[0]) + '</dt><dd>' + esc(r[1]) + '</dd>'; }).join('') + '</dl>' : '')
          + (k.care ? '<p style="margin-top:10px">' + esc(k.care) + '</p>' : '');
        d2.appendChild(s2); d2.appendChild(b2);
        var after = acc.querySelector('details');
        acc.insertBefore(d2, after ? after.nextSibling : acc.firstChild);
      })
      .catch(function () { /* no promise shown; buying is unaffected */ });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
</script>
F360SNIP;
  echo "\n";
}, 99);
