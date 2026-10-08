<?php
/**
 * Plugin Name: Fuxia 360 · Selector de color (producción)
 * Description: Botones de Color arriba de las tallas en la ficha de producto (productos con atributo Color), con el círculo de Fuxia 360.
 *              GENERADO por scripts/f360/build_prod_storefront_mu.mjs desde tools/storefront/f360-selector-color.html — no editar a mano.
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only

add_action('wp_footer', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST)) return;
  if (!function_exists('is_product') || !is_product()) return;
  echo <<<'F360SNIP'
<div class="f360-colores" hidden>
  <div class="f360-colores-header"><span>Color</span><span class="f360-color-nombre"></span></div>
  <div class="f360-colores-botones"></div>
</div>
<style>
.f360-colores { margin: 28px 0 8px; font-family: inherit; }
.f360-colores-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
.f360-colores-header span:first-child { font-weight: 600; font-size: 14px; text-transform: uppercase; letter-spacing: .1em; }
.f360-color-nombre { font-size: 13px; color: #666; }
.f360-colores-botones { display: flex; flex-wrap: wrap; gap: 10px; }
.f360-color { display: inline-flex; align-items: center; gap: 8px; height: 44px; padding: 0 14px; border: 1px solid #ccc; background: #fff;
  cursor: pointer; font-size: 14px; border-radius: 4px; transition: all .25s ease; }
.f360-color:hover { border-color: #B8966E; }
.f360-color.selected { border: 2px solid #B8966E; color: #B8966E; font-weight: 600; }
.f360-color .f360-punto { width: 16px; height: 16px; border-radius: 50%; border: 1px solid rgba(0,0,0,.15); }
.fuxia-talla.agotada, .fuxia-talla[disabled] { text-decoration: line-through; color: #ccc !important; cursor: not-allowed; }
</style>
<script>
(function () {
  function init() {
    var form = document.querySelector('form.variations_form');
    var colorSelect = form && form.querySelector('select[name="attribute_pa_color"]');
    var box = document.querySelector('.f360-colores');
    if (!form || !colorSelect || !box) return;            // producto sin color: no se toca nada
    var tallasBox = document.querySelector('.fuxia-tallas');   // el color va siempre ARRIBA de las tallas
    if (tallasBox && tallasBox.parentNode) tallasBox.parentNode.insertBefore(box, tallasBox);

    var variations = [];
    try { variations = JSON.parse(form.getAttribute('data-product_variations') || '[]') || []; } catch (e) { variations = []; }
    if (!Array.isArray(variations)) variations = [];      // (más de 30 variaciones: Woo las carga por AJAX; entonces no se tachan tallas)

    var HEX = { negro: '#1C1A17', nude: '#D8B9A0', rojo: '#9E2A2B', blanco: '#F4F1EA', camel: '#B07A4A', rosa: '#E3A6B4',
      'azul-marino': '#1F2A44', dorado: '#B8860B', plata: '#B9B9B9', cafe: '#6F4E37', taupe: '#8B7D6B', verde: '#4F6B4A', vino: '#6D1A2A' };
    var ENDPOINT = 'https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-store-reserve';   // PRODUCCIÓN: endpoint de staging.
    var norm = function (x) { return String(x || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().toLowerCase(); };
    var botones = box.querySelector('.f360-colores-botones');
    var nombre = box.querySelector('.f360-color-nombre');
    var $ = window.jQuery;

    function disponible(color, talla) {
      if (!variations.length) return true;
      return variations.some(function (v) {
        var a = v.attributes || {};
        var okColor = !a.attribute_pa_color || a.attribute_pa_color === color;
        var okTalla = !a.attribute_pa_medida || a.attribute_pa_medida === talla;
        return okColor && okTalla && v.is_in_stock && v.is_purchasable && v.variation_is_active !== false;
      });
    }

    function marcarTallas(color) {
      var sizeSelect = form.querySelector('select[name="attribute_pa_medida"]');
      document.querySelectorAll('.fuxia-talla').forEach(function (t) {
        var ok = !color || disponible(color, t.dataset.co);
        t.classList.toggle('agotada', !ok);
        t.disabled = !ok;
        if (!ok && t.classList.contains('selected')) {
          t.classList.remove('selected');
          if (sizeSelect) { sizeSelect.value = ''; if ($) $(sizeSelect).val('').trigger('change'); }
        }
      });
    }

    // Galería de Bricks (flexslider): se mueve a la foto del color, igual que al tocar su miniatura. No finge una variación
    // (el carrito no cambia). Sin galería de Bricks se usa la función estándar de WooCommerce.
    function cambiarFoto(color) {
      var v = variations.find(function (x) { return (x.attributes || {}).attribute_pa_color === color && x.image && x.image.full_src; });
      if (!v || !$) return;
      var galerias = document.querySelectorAll('.woocommerce-product-gallery.images.bricks-product-gallery-for-' + form.getAttribute('data-product_id'));
      if (!galerias.length) { if ($.fn.wc_variations_image_update) $(form).wc_variations_image_update(v); return; }
      galerias.forEach(function (g) {
        var fs = $(g).data('flexslider');
        if (!fs || !fs.slides) return;
        for (var i = 0; i < fs.slides.length; i++) {
          var img = fs.slides[i].querySelector('img');
          if (img && img.getAttribute('data-large_image') === v.image.full_src) { if (fs.currentSlide !== i) $(g).flexslider(i); break; }
        }
      });
    }

    function elegir(btn) {
      var color = btn.dataset.color;
      botones.querySelectorAll('.f360-color').forEach(function (b) { b.classList.remove('selected'); });
      btn.classList.add('selected');
      nombre.textContent = btn.dataset.nombre;
      colorSelect.value = color;
      if ($) $(colorSelect).val(color).trigger('change'); else colorSelect.dispatchEvent(new Event('change', { bubbles: true }));
      marcarTallas(color);
      cambiarFoto(color);
    }

    Array.prototype.forEach.call(colorSelect.options, function (o) {
      if (!o.value) return;
      var b = document.createElement('button');
      b.type = 'button'; b.className = 'f360-color'; b.dataset.color = o.value; b.dataset.nombre = o.text;
      var hex = HEX[o.value];
      b.innerHTML = (hex ? '<span class="f360-punto" style="background:' + hex + '"></span>' : '') + '<span></span>';
      b.lastChild.textContent = o.text;
      b.addEventListener('click', function () { elegir(b); });
      botones.appendChild(b);
    });

    // una talla agotada no se puede elegir (se intercepta antes del script de tallas existente)
    var contTallas = document.querySelector('.fuxia-tallas-botones');
    if (contTallas) contTallas.addEventListener('click', function (e) {
      var t = e.target.closest('.fuxia-talla');
      if (t && t.classList.contains('agotada')) { e.stopImmediatePropagation(); e.preventDefault(); }
    }, true);

    // Con color sin talla (p. ej. un color agotado) WooCommerce dispara reset_image y Bricks regresa la galería a la foto 1.
    // Después de ese regreso se vuelve a poner la foto del color elegido.
    if ($) $(form).on('reset_image', function () { if (colorSelect.value) setTimeout(function () { cambiarFoto(colorSelect.value); }, 60); });

    // the colour circle Carolina chose in Fuxia 360 (same catalog the shop search reads; one request, never blocks the page)
    var punto = function (b, hex) {
      var d = b.querySelector('.f360-punto');
      if (!d) { d = document.createElement('span'); d.className = 'f360-punto'; b.insertBefore(d, b.firstChild); }
      d.style.background = hex;
    };
    try {
      fetch(ENDPOINT, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'catalog' }) })
        .then(function (r) { return r.json(); })
        .then(function (cat) {
          var id = Number(form.getAttribute('data-product_id'));
          var it = (cat.items || []).filter(function (x) { return Number(x.woo_product_id) === id; })[0];
          (it && it.colors || []).forEach(function (c) {
            if (!c.hex) return;
            Array.prototype.forEach.call(botones.children, function (b) { if (norm(b.dataset.nombre) === norm(c.name)) punto(b, c.hex); });
          });
        }).catch(function () {});
    } catch (e) {}

    box.hidden = false;
    var inicial = colorSelect.value && botones.querySelector('[data-color="' + colorSelect.value + '"]');
    if (inicial) elegir(inicial);
    else if (botones.children.length === 1) elegir(botones.firstChild);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
</script>
F360SNIP;
  echo "\n";
}, 99);
