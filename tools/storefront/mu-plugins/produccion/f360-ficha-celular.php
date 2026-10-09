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
  .brxe-product-title + .brxe-product-price,.brxe-product-title + .brxe-product-price .price{font-size:22px!important;color:#1d1a16!important;font-weight:700!important}
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
  function init() {
    var form = document.querySelector('form.variations_form') || document.querySelector('form.cart');
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
      if (m && m.value) {                             // the size as the page's own size buttons show it (MX = cm on /mx/)
        var tb = document.querySelector('.fuxia-talla[data-co="' + m.value + '"]');
        partes.push('Talla ' + (mexico && tb && tb.getAttribute('data-cm') ? tb.getAttribute('data-cm') : texto(m)));
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
    var visible = false;
    new IntersectionObserver(function (es) {
      var ver = !es[0].isIntersecting;
      if (ver === visible) return; visible = ver;
      bar.classList.toggle('on', ver); bar.setAttribute('aria-hidden', String(!ver));
      html.classList.toggle('f360-fc-visible', ver && window.matchMedia('(max-width: 900px)').matches);
      html.style.setProperty('--f360-fc-h', bar.offsetHeight + 'px');
    }, { threshold: 0 }).observe(real);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
</script>
F360SNIP;
  echo "\n";
}, 99);
