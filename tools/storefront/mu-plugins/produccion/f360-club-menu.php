<?php
/**
 * Plugin Name: Fuxia 360 · Club Fuxia en el menú (producción)
 * Description: Mario 2026-10-06: "Club Fuxia del lado derecho, a lado del monito de iniciar sesión, para que la gente lo vea
 *              hasta arriba". Adds a "Club Fuxia" link in the header, before the account icon. It goes to the home's App /
 *              Club section (#descarga-app) of the visitor's country (/mx/ or /co/); on the home itself it scrolls there.
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only
add_action('wp_footer', function () {
  if (is_admin() || isset($_GET['bricks'])) return;
  ?>
<style>
.fx-club-link { display: inline-flex; align-items: center; gap: 6px; margin-right: 18px; padding: 7px 14px; border: 1px solid #83734C; border-radius: 999px;
  font-size: 12px; font-weight: 600; letter-spacing: .18em; text-transform: uppercase; color: #83734C !important; text-decoration: none; white-space: nowrap; line-height: 1; }
.fx-club-link:hover { background: #83734C; color: #fff !important; }
.fx-club-link svg { width: 13px; height: 13px; fill: currentColor; }
@media (max-width: 767px) { .fx-club-link { margin-right: 10px; padding: 6px 10px; letter-spacing: .1em; font-size: 11px; } .fx-club-link .fx-club-t2 { display: none; } }
</style>
<script>
(function () {
  var cuenta = document.querySelector('#brx-header a[href*="/mi-cuenta"]');
  if (!cuenta || document.querySelector('.fx-club-link')) return;
  var pais = (location.pathname.match(/^\/([a-z]{2})\//) || [0, 'mx'])[1];
  var a = document.createElement('a');
  a.className = 'fx-club-link';
  a.href = '/' + pais + '/#descarga-app';
  a.setAttribute('aria-label', 'Club Fuxia: acumula puntos con cada par');
  a.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 17.3l-5.8 3.1 1.1-6.5L2.6 9.3l6.5-.9z"/></svg><span>Club<span class="fx-club-t2"> Fuxia</span></span>';
  a.addEventListener('click', function (e) {
    var s = document.getElementById('descarga-app');
    if (s) { e.preventDefault(); s.scrollIntoView({ behavior: 'smooth', block: 'start' }); history.replaceState(null, '', '#descarga-app'); }
  });
  cuenta.parentNode.insertBefore(a, cuenta);
  var p = cuenta.parentNode; if (getComputedStyle(p).display.indexOf('flex') === -1) { p.style.display = 'flex'; p.style.alignItems = 'center'; }
})();
</script>
  <?php
}, 20);
