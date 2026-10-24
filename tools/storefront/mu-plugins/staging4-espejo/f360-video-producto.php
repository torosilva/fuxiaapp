<?php
// GENERADO por scripts/f360/build_staging4_mirror_mu.mjs desde tools/storefront/mu-plugins/produccion/f360-video-producto.php — no editar a mano.
/**
 * Plugin Name: Fuxia 360 · Video en la ficha (producción)
 * Description: Muestra debajo de la galería el video del color elegido (sin sonido, en bucle). Los videos vienen de Fuxia 360
 *              (metadato _fuxia360_videos que escribe el publicador) y se sirven desde el bucket público de Fuxia 360.
 *              Producto sin videos: no se imprime nada.
 * Apagar: borrar este archivo de wp-content/mu-plugins/ (los videos dejan de verse; nada más cambia).
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'staging4.fuxiaballerinas.com') return;   // ESPEJO: solo staging4

add_action('wp_footer', function () {
  if (is_admin() || !function_exists('is_product') || !is_product()) return;
  $product = wc_get_product(get_queried_object_id());
  if (!$product) return;
  $raw = json_decode((string) $product->get_meta('_fuxia360_videos'), true);
  if (!is_array($raw) || !$raw) return;
  // Only Fuxia 360's own public bucket, only video types: the meta can never inject another host or a script.
  $base = 'https://faltxpkaicwpnlqaxrdu.supabase.co/storage/v1/object/public/product-images/f360/';
  $ok_mime = array('video/mp4', 'video/quicktime', 'video/webm');
  $videos = array();
  foreach ($raw as $v) {
    if (!is_array($v) || empty($v['url']) || strpos((string) $v['url'], $base) !== 0) continue;
    if (preg_match('/[\s"\'<>]/', (string) $v['url'])) continue;
    $mime = in_array($v['mime'] ?? '', $ok_mime, true) ? $v['mime'] : 'video/mp4';
    $videos[] = array('url' => (string) $v['url'], 'mime' => $mime, 'color' => sanitize_text_field((string) ($v['color'] ?? '')));
    if (count($videos) >= 12) break;
  }
  if (!$videos) return;
  ?>
<style>
.f360-video { margin: 12px 0 0; border-radius: 6px; overflow: hidden; background: #F4EFE8; }
.f360-video[hidden] { display: none; }
.f360-video video { display: block; width: 100%; max-height: 80vh; aspect-ratio: 3 / 4; object-fit: cover; background: #F4EFE8; }
.f360-video-tabs { display: flex; gap: 6px; padding: 8px; }
.f360-video-tabs[hidden] { display: none; }
.f360-video-tabs button { height: 30px; padding: 0 12px; border: 1px solid #ccc; background: #fff; border-radius: 15px; font-size: 12px; cursor: pointer; }
.f360-video-tabs button.on { border-color: #B8966E; color: #B8966E; font-weight: 600; }
</style>
<script>
(function () {
  var VIDEOS = <?php echo wp_json_encode($videos, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT); ?>;
  var norm = function (x) { return String(x || '').normalize('NFD').replace(/[̀-ͯ]/g, '').trim().toLowerCase(); };
  function init() {
    var gallery = document.querySelector('.brxe-product-gallery') || document.querySelector('.woocommerce-product-gallery');
    if (!gallery || !gallery.parentNode || document.querySelector('.f360-video')) return;
    var form = document.querySelector('form.variations_form');
    var colorSelect = form && form.querySelector('select[name="attribute_pa_color"]');
    var variations = [];
    try { variations = JSON.parse((form && form.getAttribute('data-product_variations')) || '[]') || []; } catch (e) { variations = []; }
    if (!Array.isArray(variations)) variations = [];

    var box = document.createElement('div');
    box.className = 'f360-video'; box.hidden = true;
    var video = document.createElement('video');
    video.muted = true; video.loop = true; video.playsInline = true; video.autoplay = true;
    video.setAttribute('muted', ''); video.setAttribute('playsinline', ''); video.setAttribute('preload', 'none');
    var tabs = document.createElement('div'); tabs.className = 'f360-video-tabs'; tabs.hidden = true;
    box.appendChild(video); box.appendChild(tabs);
    gallery.parentNode.insertBefore(box, gallery.nextSibling);

    // colour name (from Fuxia 360) → the store's colour slug and that colour's variation photo (poster)
    function slugOf(name) {
      if (!colorSelect) return null;
      var o = Array.prototype.find.call(colorSelect.options, function (x) { return x.value && norm(x.text) === norm(name); });
      return o ? o.value : null;
    }
    // poster: that colour's variation photo; with more than 30 variations Woo does not print them, so the colour's first
    // gallery photo (the publisher names every photo "{Modelo} {Color}") is used instead.
    function posterOf(slug, name) {
      var v = variations.find(function (x) { return (x.attributes || {}).attribute_pa_color === slug && x.image && (x.image.src || x.image.full_src); });
      if (v) return v.image.src || v.image.full_src;
      var want = norm(name);
      var g = Array.prototype.find.call(gallery.querySelectorAll('.woocommerce-product-gallery__image'), function (el) {
        var alt = norm(el.getAttribute('data-thumb-alt'));
        return want && alt.slice(-want.length) === want;
      });
      var img = g && g.querySelector('img');
      return img ? (img.getAttribute('data-src') || img.getAttribute('src') || '') : '';
    }
    var visible = false;
    function play(item) {
      if (video.getAttribute('src') !== item.url) {
        video.setAttribute('src', item.url); video.setAttribute('type', item.mime);
        var p = posterOf(slugOf(item.color), item.color); if (p)video.setAttribute('poster', p); else video.removeAttribute('poster');
      }
      if (visible) { var r = video.play(); if (r && r.catch) r.catch(function () {}); }
    }
    function show() {
      var slug = colorSelect ? colorSelect.value : '';
      var list = slug ? VIDEOS.filter(function (v) { return slugOf(v.color) === slug; }) : VIDEOS.slice(0, 2);
      tabs.innerHTML = '';
      if (!list.length) { box.hidden = true; video.pause(); return; }
      box.hidden = false;
      tabs.hidden = list.length < 2;
      list.forEach(function (item, i) {
        var b = document.createElement('button'); b.type = 'button'; b.textContent = 'Video ' + (i + 1);
        if (i === 0) b.className = 'on';
        b.addEventListener('click', function () {
          tabs.querySelectorAll('button').forEach(function (x) { x.className = ''; }); b.className = 'on'; play(item);
        });
        tabs.appendChild(b);
      });
      play(list[0]);
    }
    // Only download / play while on screen (phones on data).
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (es) {
        visible = es[0].isIntersecting;
        if (visible) { video.setAttribute('preload', 'metadata'); var r = video.play(); if (r && r.catch) r.catch(function () {}); } else video.pause();
      }, { threshold: 0.25 }).observe(box);
    } else visible = true;
    if (colorSelect) {
      if (window.jQuery) window.jQuery(colorSelect).on('change', show); else colorSelect.addEventListener('change', show);
    }
    show();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
</script>
<?php
}, 30);
