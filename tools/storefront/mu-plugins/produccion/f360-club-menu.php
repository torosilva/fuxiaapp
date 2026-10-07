<?php
/**
 * Plugin Name: Fuxia 360 · Club Fuxia en el menú (producción)
 * Description: Mario 2026-10-06: "Club Fuxia del lado derecho, a lado del monito de iniciar sesión, para que la gente lo vea
 *              hasta arriba". Adds a "Club Fuxia" link in the header, before the account icon. It goes to the home's App /
 *              Club section (#descarga-app) of the visitor's country (/mx/ or /co/); on the home itself it scrolls there.
 *              Mario 2026-10-06 (2): lands BELOW the fixed header (it was covering the title); the section title reads
 *              "Club Fuxia" (not "Familia Fuxia"); on the phone the pill leaves the header (it overlapped the logo) and
 *              "Club Fuxia" becomes an option inside the hamburger menu; tapping outside the open menu closes it.
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only
// The App/Club section is a Code element pasted in Bricks: only its title changes ("Familia Fuxia," → "Club Fuxia,").
add_action('template_redirect', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST) || is_feed() || isset($_GET['bricks'])) return;
  ob_start(function ($page) {
    return str_replace('<h2 class="fx-app__title">Familia Fuxia,', '<h2 class="fx-app__title">Club Fuxia,', $page);
  });
});
add_action('wp_footer', function () {
  if (is_admin() || isset($_GET['bricks'])) return;
  ?>
<style>
.fx-club-link { display: inline-flex; align-items: center; gap: 6px; margin-right: 18px; padding: 7px 14px; border: 1px solid #83734C; border-radius: 999px;
  font-size: 12px; font-weight: 600; letter-spacing: .18em; text-transform: uppercase; color: #83734C !important; text-decoration: none; white-space: nowrap; line-height: 1; }
.fx-club-link:hover { background: #83734C; color: #fff !important; }
.fx-club-link svg { width: 13px; height: 13px; fill: currentColor; }
#brx-header .fx-club-mi { display: none !important; }
@media (max-width: 767px) {   /* = the nav's "mobile_landscape" toggle: the hamburger takes over */
  body #brx-header .fx-club-link { display: none !important; }   /* beats the header's own '#brxe-xgyyml a' rule */
  body #brx-header .fx-club-mi { display: flex !important; }
  #brx-header .fx-club-mi a { display: flex; align-items: center; gap: 10px; }
  #brx-header .fx-club-mi svg { width: .7em; height: .7em; fill: #83734C; flex: none; }
}
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
  var header = document.getElementById('brx-header');
  // the section must land BELOW the fixed header (it covered the title): a scroll-margin on the section itself, so the
  // browser's #hash jump, scrollIntoView and Bricks' own nav anchor scrolling all respect it
  function margen(s) {
    var tope = header && getComputedStyle(header).position === 'fixed' ? Math.max(0, header.getBoundingClientRect().bottom) : 0;
    var pad = parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) || 0;
    s.style.scrollMarginTop = Math.max(0, tope + 16 - pad) + 'px';
  }
  function irAlClub(suave) {
    var s = document.getElementById('descarga-app');
    if (!s) return false;
    margen(s);
    s.scrollIntoView({ behavior: suave ? 'smooth' : 'auto', block: 'start' });
    return true;
  }
  if (document.getElementById('descarga-app')) margen(document.getElementById('descarga-app'));
  function alClick(e) {
    if (!document.getElementById('descarga-app')) return;   // another page: the link navigates to the home
    e.preventDefault(); history.replaceState(null, '', '#descarga-app');
    var abierto = cerrarMenu();   // close the menu first: while open it locks the page scroll
    setTimeout(function () { irAlClub(true); }, abierto ? 80 : 0);
  }
  a.addEventListener('click', alClick);
  cuenta.parentNode.insertBefore(a, cuenta);
  var p = cuenta.parentNode; if (getComputedStyle(p).display.indexOf('flex') === -1) { p.style.display = 'flex'; p.style.alignItems = 'center'; }
  // arriving from another page with #descarga-app: correct the browser's jump once images have settled the layout
  if (location.hash === '#descarga-app') {
    var corrige = function () { irAlClub(false); };
    if (document.readyState === 'complete') setTimeout(corrige, 50); else window.addEventListener('load', function () { setTimeout(corrige, 50); });
  }

  // phone: "Club Fuxia" as an option of the hamburger menu (only shown ≤767px by the CSS above)
  var nav = header && header.querySelector('.brxe-nav-nested');
  var lista = nav && nav.querySelector('.brx-nav-nested-items');
  var cerrar = lista && lista.querySelector('.brxe-toggle');
  var abrir = nav && nav.querySelector(':scope > .brxe-toggle');
  function cerrarMenu() { if (nav && nav.classList.contains('brx-open') && cerrar) { cerrar.click(); return true; } return false; }
  if (lista && !lista.querySelector('.fx-club-mi')) {
    var li = document.createElement('li');
    li.className = 'menu-item fx-club-mi';
    var m = document.createElement('a');
    m.className = 'brxe-text-link';
    m.href = a.href;
    m.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 17.3l-5.8 3.1 1.1-6.5L2.6 9.3l6.5-.9z"/></svg>Club Fuxia';
    m.addEventListener('click', alClick);
    li.appendChild(m);
    var antes = cerrar ? cerrar.closest('li') : null;
    if (antes && antes.parentNode === lista) lista.insertBefore(li, antes); else lista.appendChild(li);
  }
  // tapping outside the open menu (the dimmed page) closes it
  document.addEventListener('click', function (e) {
    if (!nav || !lista || !nav.classList.contains('brx-open')) return;
    if (lista.contains(e.target) || (abrir && abrir.contains(e.target))) return;
    e.preventDefault(); e.stopPropagation();
    cerrarMenu();
  }, true);
})();
</script>
  <?php
}, 20);
