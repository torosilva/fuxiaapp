<?php
/**
 * Plugin Name: Fuxia 360 · Guía de tallas en ventana (producción)
 * Description: Mario 2026-10-09: "cuando le doy click en guía de tallas no hay cómo cerrarlo". The "Guía de tallas" link of the
 *              product page (Bricks template, tallas y color) opened the bare JPG in another tab. Now it opens in a window over the
 *              page with an ✕; clicking outside or pressing Esc also closes it. The link itself is unchanged, so without
 *              JavaScript it still opens the image as before.
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only
add_action('wp_footer', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST) || isset($_GET['bricks'])) return;
  if (!function_exists('is_product') || !is_product()) return;
  echo <<<'F360SNIP'
<style>
.f360-guia{position:fixed;inset:0;z-index:2147483000;display:none;align-items:center;justify-content:center;padding:16px;background:rgba(13,13,13,.72)}
.f360-guia.is-open{display:flex}
.f360-guia__box{position:relative;max-width:min(720px,100%);max-height:100%;overflow:auto;border-radius:14px;background:#fff;box-shadow:0 20px 60px rgba(0,0,0,.35)}
.f360-guia__box img{display:block;width:100%;height:auto}
.f360-guia__x{position:sticky;top:10px;float:right;margin:10px 10px -54px 0;width:44px;height:44px;border:0;border-radius:50%;background:rgba(13,13,13,.85);color:#fff;font-size:22px;line-height:44px;text-align:center;cursor:pointer;z-index:1}
.f360-guia__x:focus-visible{outline:2px solid #CD7F32;outline-offset:2px}
body.f360-guia-open{overflow:hidden}
</style>
<script>
/* Fuxia 360 · Guía de tallas en ventana (mu-plugin f360-guia-tallas.php) */
(function () {
  var box = null, last = null;
  function close() {
    if (!box) return;
    box.classList.remove('is-open'); document.body.classList.remove('f360-guia-open');
    if (last) { try { last.focus(); } catch (e) {} }
  }
  function open(src, from) {
    if (!box) {
      box = document.createElement('div');
      box.className = 'f360-guia'; box.setAttribute('role', 'dialog'); box.setAttribute('aria-modal', 'true'); box.setAttribute('aria-label', 'Guía de tallas');
      box.innerHTML = '<div class="f360-guia__box"><button type="button" class="f360-guia__x" aria-label="Cerrar">✕</button><img alt="Guía de tallas"></div>';
      box.addEventListener('click', function (e) { if (e.target === box || e.target.closest('.f360-guia__x')) close(); });
      document.body.appendChild(box);
    }
    box.querySelector('img').src = src;
    last = from;
    box.classList.add('is-open'); document.body.classList.add('f360-guia-open');
    box.querySelector('.f360-guia__x').focus();
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a.fuxia-guia-link');
    if (!a || !a.href || e.metaKey || e.ctrlKey || e.shiftKey) return;
    e.preventDefault();
    open(a.href, a);
  }, true);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && box && box.classList.contains('is-open')) close(); });
})();
</script>
F360SNIP;
  echo "\n";
}, 99);
