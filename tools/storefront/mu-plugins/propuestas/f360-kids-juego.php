<?php
/**
 * Plugin Name: Fuxia 360 · Fuxia Kids · juegos (producción)
 * Description: Mario 2026-10-24: "hacer los 2 juegos y que ellas puedan seleccionar cuál jugar, y cuando Carolina suba el inventario
 *              que se vea algo así". On the Kids category page:
 *                · no products yet → a large menu replaces Woo's "no products" box;
 *                · with products  → a compact "Juega con Fuxia Kids" strip above the product grid (the games open inside it).
 *              Two games: "Atrapa las estrellas" (50 s, three levels, weekly top 10 per market — names from a FIXED list of dancer
 *              names, never free text, nothing personal; only to show off, NO prizes) and "Diseña tus ballerinas" (a step-by-step
 *              atelier: leather, strap, adornment; a gift box with her dancer name; "Guardar para mamá" makes a PNG in the browser
 *              and shares it or downloads it; "El par Fuxia Kids más parecido" from the Kids category of the store, or "Muy
 *              pronto"). No music, no accounts, no coupon. The board goes through Fuxia 360's public store function (CORS-limited);
 *              the device is a random id kept in the browser and stored only as a hash. The prize is NOT decided (Mario).
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only
function f360_kids_juego_here() {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST) || isset($_GET['bricks'])) return false;
  return function_exists('is_product_category') && is_product_category('kids');
}
add_action('wp_head', function () {
  if (!f360_kids_juego_here()) return;
  echo '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Fredoka:wght@700&display=swap">' . "\n";
}, 5);
add_action('wp_footer', function () {
  if (!f360_kids_juego_here()) return;
  echo <<<'F360SNIP'
<style>
.f360k{--marfil:#FBF6F1;--blush:#F6E4E2;--rosa:#E2A6B0;--rosa2:#C97F8D;--oro:#B8966E;--oro2:#857652;--tinta:#3A2E2A;--gris:#8B7F78;
  box-sizing:border-box;max-width:640px;margin:8px auto 48px;padding:24px 16px 8px;text-align:center;color:var(--tinta)}
.f360k *,.f360k *::before,.f360k *::after{box-sizing:border-box}
.f360k button{font-family:inherit;-webkit-tap-highlight-color:transparent}
.f360k__kids{margin:0;font-family:Fredoka,system-ui,sans-serif;font-weight:700;font-size:72px;line-height:.95;letter-spacing:.03em;color:var(--rosa);
  text-shadow:0 1px 0 #fff,0 4px 0 var(--oro),0 14px 26px rgba(133,118,82,.25)}
.f360k__sub{margin:16px auto 22px;max-width:400px;font-family:"Cormorant Garamond",Georgia,serif;font-style:italic;font-size:21px;line-height:1.3}
.f360k__lab{font-size:10.5px;font-weight:500;letter-spacing:.32em;text-transform:uppercase;color:var(--oro2)}
.f360k__serif{margin:0;font-family:"Cormorant Garamond",Georgia,serif;font-style:italic;font-weight:500;font-size:34px;line-height:1.05;color:var(--tinta)}
.f360k__txt{margin:0;max-width:320px;font-size:14px;line-height:1.55;color:var(--gris)}
.f360k__btn{min-height:48px;padding:0 30px;border:0;border-radius:999px;background:var(--tinta);color:#F7E7C4;font-weight:600;font-size:12.5px;letter-spacing:.18em;text-transform:uppercase;cursor:pointer}
.f360k__btn:hover{background:#4a3c37}
.f360k__btn--ghost{background:transparent;color:var(--tinta);box-shadow:inset 0 0 0 1px var(--oro)}
.f360k__btn--ghost:hover{background:rgba(184,150,110,.1)}
.f360k button:focus-visible,.f360k select:focus-visible,.f360k a:focus-visible{outline:2px solid var(--oro2);outline-offset:3px}
.f360k__menu{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:6px 0 22px}
.f360k__card{position:relative;display:flex;flex-direction:column;align-items:center;gap:10px;padding:18px 14px 20px;border:0;border-radius:22px;background:#fff;cursor:pointer;
  color:var(--tinta);box-shadow:0 0 0 1px rgba(184,150,110,.5),0 0 0 6px #fff,0 0 0 7px rgba(184,150,110,.25),0 18px 34px rgba(133,118,82,.13);transition:transform .25s}
.f360k__card:hover{transform:translateY(-2px)}
.f360k__card:hover,.f360k__card:focus,.f360k__card:active{background:#fff;color:var(--tinta)}
.f360k__btn:focus,.f360k__btn:active{background:var(--tinta);color:#F7E7C4}.f360k__btn--ghost:focus,.f360k__btn--ghost:active{background:transparent;color:var(--tinta)}
.f360k__back:hover,.f360k__back:focus{background:none;color:var(--oro2)}
.f360k__card svg{width:100%;max-width:150px;height:auto;max-height:130px}
.f360k__card b{font-family:"Cormorant Garamond",Georgia,serif;font-style:italic;font-weight:500;font-size:25px;line-height:1.05}
.f360k__card span{font-size:12.5px;line-height:1.45;color:var(--gris)}
.f360k__board{margin:4px auto 0;max-width:420px;padding:18px 18px 10px;border-radius:20px;background:rgba(255,255,255,.7);box-shadow:0 0 0 1px rgba(184,150,110,.35)}
.f360k__board ol{list-style:none;margin:10px 0 6px;padding:0;text-align:left}
.f360k__board li{display:flex;justify-content:space-between;gap:10px;padding:7px 4px;border-bottom:1px dashed rgba(184,150,110,.35);font-size:14px}
.f360k__board li:last-child{border-bottom:0}
.f360k__board li em{font-style:normal;color:var(--oro2);font-weight:600;min-width:22px;display:inline-block}
.f360k__board li.is-me{background:rgba(226,166,176,.16);border-radius:10px}
.f360k__board p{margin:8px 0;font-size:13px;color:var(--gris)}
.f360k__view[hidden]{display:none}
.f360k__bar{display:flex;align-items:center;justify-content:space-between;margin:0 0 12px}
.f360k__back{border:0;background:none;color:var(--oro2);font-size:12px;letter-spacing:.2em;text-transform:uppercase;cursor:pointer;padding:10px 4px}
.f360k__play{position:relative;width:min(100%,calc((100vh - 240px) * .75));aspect-ratio:3/4;margin:0 auto;border-radius:22px;overflow:hidden;outline:none;scroll-margin:130px 0 96px;
  background:linear-gradient(#FBF6F1,#F8EBE8 60%,#F1D6D8);box-shadow:0 0 0 1px rgba(184,150,110,.55),0 0 0 7px #fff,0 0 0 8px rgba(184,150,110,.3),0 24px 44px rgba(133,118,82,.16)}
.f360k__play:focus-visible{box-shadow:0 0 0 2px var(--oro2),0 0 0 7px #fff,0 0 0 9px var(--oro),0 24px 44px rgba(133,118,82,.16)}
.f360k__cv{position:absolute;inset:0;width:100%;height:100%;display:block;touch-action:none}
.f360k__over{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:11px;padding:22px;overflow:auto;
  background:rgba(251,246,241,.9);-webkit-backdrop-filter:blur(3px);backdrop-filter:blur(3px)}
.f360k__over[hidden],.f360k [hidden]{display:none!important}
.f360k__score{font-family:"Cormorant Garamond",Georgia,serif;font-weight:500;font-size:76px;line-height:1;color:var(--rosa2);font-variant-numeric:lining-nums}
.f360k__pause{position:absolute;top:12px;right:12px;width:40px;height:40px;border:1px solid var(--oro);border-radius:50%;background:rgba(255,255,255,.75);color:var(--oro2);font-size:12px;cursor:pointer}
.f360k__sel{min-height:44px;max-width:100%;padding:0 14px;border:1px solid var(--oro);border-radius:999px;background:#fff;color:var(--tinta);font:500 15px/1 "Cormorant Garamond",Georgia,serif}
.f360k__row{display:flex;flex-wrap:wrap;gap:10px;justify-content:center;align-items:center}
.f360k__live{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
/* atelier */
.f360k__atelier{border-radius:24px;background:linear-gradient(#FBF6F1,#F7ECE9);padding:18px 14px 22px;box-shadow:0 0 0 1px rgba(184,150,110,.45),0 0 0 7px #fff,0 0 0 8px rgba(184,150,110,.25)}
.f360k__steps{display:flex;justify-content:center;gap:6px;margin:0 0 6px;font-size:10px;letter-spacing:.22em;text-transform:uppercase;color:#B9ADA5}
.f360k__steps span.is-on{color:var(--oro2)}
.f360k__steps span+span::before{content:"·";margin-right:6px;color:#D8CFC6}
.f360k__shoe{display:block;width:100%;max-width:330px;height:auto;margin:4px auto 6px}
.f360k__opts{display:flex;flex-wrap:wrap;justify-content:center;gap:10px;margin:12px 0 16px}
.f360k__opt,.f360k__opt:hover,.f360k__opt:focus,.f360k__opt:active{background:#fff;color:var(--tinta)}
.f360k__opt{-webkit-tap-highlight-color:transparent;display:flex;align-items:center;gap:9px;min-height:46px;padding:6px 16px 6px 8px;border:0;border-radius:999px;background:#fff;color:var(--tinta);cursor:pointer;
  font:500 17px/1 "Cormorant Garamond",Georgia,serif;box-shadow:0 0 0 1px rgba(184,150,110,.45)}
.f360k__opt[aria-pressed="true"]{box-shadow:0 0 0 2px var(--oro2),0 8px 18px rgba(133,118,82,.18)}
.f360k__opt i{width:30px;height:30px;border-radius:50%;flex:none;box-shadow:inset 0 0 0 1px rgba(0,0,0,.08)}
.f360k__par{margin:22px auto 0;max-width:420px;padding:16px;border-radius:20px;background:#fff;box-shadow:0 0 0 1px rgba(184,150,110,.4)}
.f360k__par img{display:block;width:100%;max-width:260px;aspect-ratio:1;object-fit:cover;border-radius:14px;margin:10px auto}
.f360k__par a.f360k__btn{display:inline-flex;align-items:center;text-decoration:none}
/* strip (Kids has products) */
.f360k--franja{max-width:1100px;margin:4px auto 26px;padding:18px 16px}
.f360k--franja .f360k__head{display:flex;align-items:center;justify-content:center;gap:16px;flex-wrap:wrap;margin-bottom:12px}
.f360k--franja .f360k__kids{font-size:40px}
.f360k--franja .f360k__menu{max-width:620px;margin:0 auto}
.f360k--franja .f360k__card{flex-direction:row;text-align:left;padding:12px 14px;gap:12px}
.f360k--franja .f360k__card svg{width:64px;max-height:60px;flex:none}
.f360k--franja .f360k__card b{font-size:20px}
.f360k--franja .f360k__card span{display:none}
.f360k--franja .f360k__board{display:none}
.f360k--franja .f360k__view:not(.f360k__home){max-width:640px;margin:14px auto 0}
@media (max-width:480px){.f360k__kids{font-size:58px}.f360k__menu{grid-template-columns:1fr}.f360k--franja .f360k__menu{grid-template-columns:1fr 1fr}
  .f360k--franja .f360k__card{flex-direction:column;text-align:center}.f360k__sub{font-size:19px}}
</style>
<script>
(function () {
  if (!window.HTMLCanvasElement || document.querySelector('.f360k')) return;
  var host = location.hostname, MKT = /^\/co(\/|$)/.test(location.pathname) ? 'co' : 'mx', BASE = '/' + MKT + '/';
  var F360 = host === 'staging4.fuxiaballerinas.com' ? 'https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-store-reserve'
                                                      : 'https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-store-reserve';
  var KIDS_CAT = 96;
  // the fixed list (same as f360.kids_dancer_names() in Fuxia 360): the only "names" in the game
  var NAMES = ['Estrellita Dorada','Luna de Plata','Perla Rosa','Brillo de Oro','Bailarina de Cristal','Rosa de Seda','Lucero Rosa','Nube de Tul',
    'Princesa Pointe','Mariposa Dorada','Gota de Rocío','Lirio Blanco','Flor de Tutú','Cometa Rosa','Hada de Satén','Estrella Fugaz','Coral de Mar',
    'Azucena','Violeta Brillante','Aurora Rosa','Copito de Nieve','Lunita','Chispita Dorada','Arabesque'];
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  function ls(k, v) { try { if (v !== undefined) localStorage.setItem(k, v); return localStorage.getItem(k); } catch (e) { return null; } }
  function uuid() { if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16); (window.crypto || {}).getRandomValues ? crypto.getRandomValues(b) : b.forEach(function (_, i) { b[i] = Math.random() * 256; });
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128; var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20); }
  var DEV = ls('f360k_dev'); if (!/^[0-9a-f-]{36}$/i.test(DEV || '')) DEV = ls('f360k_dev', uuid()) || uuid();
  var NUM = +(ls('f360k_num') || 0); if (!(NUM >= 1 && NUM <= 99)) { NUM = 1 + Math.floor(Math.random() * 99); ls('f360k_num', String(NUM)); }
  var myName = NAMES.indexOf(ls('f360k_name')) >= 0 ? ls('f360k_name') : '';
  function api(body) {
    return fetch(F360, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      .then(function (r) { return r.json(); }).catch(function () { return { ok: false }; });
  }
  function el(tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function nameOptions(sel) { return '<option value="">Elige tu nombre…</option>' + NAMES.map(function (n) { return '<option' + (n === sel ? ' selected' : '') + '>' + esc(n) + '</option>'; }).join(''); }

  // ── where it goes: no products → replaces Woo's box (large); products → a strip above the grid
  var empty = document.querySelector('.woocommerce-no-products-found');
  var grid = empty ? null : document.querySelector('.brxe-woocommerce-products, ul.products');
  var anchor = empty || grid || document.querySelector('#brx-content');
  if (!anchor) return;
  var franja = !empty;
  var root = el('section', 'f360k' + (franja ? ' f360k--franja' : ''));
  root.setAttribute('aria-labelledby', 'f360k-t');

  // ── the ballerina PAIR seen from above (lookbook illustration): wide round toe, oval opening with a finely gathered edge and light
  //    top-stitching, Mary Jane strap across the instep, sole edge just peeking, small gold mark on the outer heel. No black outlines.
  var PIEL = {
    nude:   { n: 'Nude', met: false, g: [['0', '#F3DCCA'], ['.55', '#DDB89C'], ['1', '#BB937A']], lin: '#F5E8DC', sw: 'linear-gradient(135deg,#EBCDB6,#C9A389)', w: ['nude', 'beige', 'taupe', 'camel', 'natural', 'arena', 'piel'] },
    plata:  { n: 'Plata metálico', met: true, g: [['0', '#8E949A'], ['.16', '#EEF1F4'], ['.3', '#A6ACB2'], ['.48', '#F8FAFB'], ['.64', '#9CA2A8'], ['.82', '#E3E6E9'], ['1', '#80868C']], lin: '#EEF0F2', sw: 'linear-gradient(135deg,#F4F6F8,#8A9096 55%,#E1E4E7)', w: ['plata', 'silver', 'plateado', 'metal'] },
    dorado: { n: 'Dorado metálico', met: true, g: [['0', '#8C6A2C'], ['.16', '#F6E3A6'], ['.3', '#B88E45'], ['.48', '#FBEDC0'], ['.64', '#A9803C'], ['.82', '#EFD48F'], ['1', '#8A672B']], lin: '#F6EBD2', sw: 'linear-gradient(135deg,#F6E3A6,#B58A3E 55%,#F1D894)', w: ['dorado', 'oro', 'gold', 'dorada'] },
    rosa:   { n: 'Rosa empolvado', met: false, g: [['0', '#F7D7DC'], ['.55', '#E4A9B3'], ['1', '#C08791']], lin: '#F8E9EB', sw: 'linear-gradient(135deg,#F2C9CF,#CC8E99)', w: ['rosa', 'pink', 'palo', 'blush', 'empolvado'] },
  };
  var TIRA = { fruncido: { n: 'Elástico fruncido', w: ['mary jane', 'maryjane', 'fruncid', 'elástic', 'elastic'] },
               doble: { n: 'Doble tira', w: ['doble', 'double', 'dos tiras'] },
               esferas: { n: 'Tira de esferas', w: ['esfera', 'bolita', 'perlitas doradas', 'cuentas'] } };
  var ADORNO = { taches: { n: 'Taches dorados', w: ['tache', 'stud', 'estoperol'] }, perlas: { n: 'Perlas', w: ['perla', 'pearl'] }, ninguno: { n: 'Sin adorno', w: [] } };
  var OUT = 'M0 0 C30 0 46.5 22 48.5 58 C50 100 45 150 41.5 180 C38 204 22 215 0 215 C-22 215 -38 204 -41.5 180 C-45 150 -50 100 -48.5 58 C-46.5 22 -30 0 0 0 Z';
  var gid = 0;
  function f(n) { return n.toFixed(1); }
  function strapY(x, y0) { return y0 - 7 * (1 - (x * x) / (48 * 48)); }       // the strap bows slightly toward the toe
  function shoeDefs(k, P) {
    var mat = P.met
      ? '<linearGradient id="' + k + 'm" x1="0" y1="0" x2="1" y2=".32">' + P.g.map(function (s) { return '<stop offset="' + s[0] + '" stop-color="' + s[1] + '"/>'; }).join('') + '</linearGradient>'
      : '<radialGradient id="' + k + 'm" cx=".42" cy=".22" r=".95">' + P.g.map(function (s) { return '<stop offset="' + s[0] + '" stop-color="' + s[1] + '"/>'; }).join('') + '</radialGradient>';
    return mat +
      '<radialGradient id="' + k + 'o" cx=".34" cy=".3" r=".8"><stop offset="0" stop-color="#FFF7D6"/><stop offset=".45" stop-color="#E2BC6E"/><stop offset=".8" stop-color="#A97F35"/><stop offset="1" stop-color="#7E5E25"/></radialGradient>' +
      '<radialGradient id="' + k + 'p" cx=".35" cy=".3" r=".85"><stop offset="0" stop-color="#FFFFFF"/><stop offset=".45" stop-color="#F7EEF1"/><stop offset=".75" stop-color="#E4E6F1"/><stop offset="1" stop-color="#CFC6CC"/></radialGradient>' +
      '<radialGradient id="' + k + 'i" cx=".5" cy=".7" r=".8"><stop offset="0" stop-color="#EFE2D3"/><stop offset="1" stop-color="#D8C3AC"/></radialGradient>' +
      '<radialGradient id="' + k + 'h" cx=".38" cy=".18" r=".6"><stop offset="0" stop-color="#fff" stop-opacity="' + (P.met ? .55 : .32) + '"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>' +
      '<filter id="' + k + 'b" x="-40%" y="-20%" width="180%" height="140%"><feGaussianBlur stdDeviation="6"/></filter>';
  }
  function sphere(k, x, y, r, pearl) {
    return '<circle cx="' + f(x) + '" cy="' + f(y + r * .25) + '" r="' + f(r) + '" fill="rgba(80,60,40,.22)"/>' +
      '<circle cx="' + f(x) + '" cy="' + f(y) + '" r="' + f(r) + '" fill="url(#' + k + (pearl ? 'p' : 'o') + ')"/>' +
      '<ellipse cx="' + f(x - r * .32) + '" cy="' + f(y - r * .36) + '" rx="' + f(r * .3) + '" ry="' + f(r * .2) + '" fill="#fff" opacity="' + (pearl ? .9 : .75) + '"/>';
  }
  function oneShoe(o, k, side) {      // local coords: toe up at (0,0), heel at (0,215); side = -1 left foot, 1 right foot
    var P = PIEL[o.piel] || PIEL.nude, M = 'url(#' + k + 'm)', s = '';
    s += '<ellipse cx="' + (4 * side) + '" cy="116" rx="51" ry="110" fill="rgba(110,86,62,.30)" filter="url(#' + k + 'b)"/>';
    s += '<path d="' + OUT + '" transform="translate(0 108) scale(1.035 1.02) translate(0 -105)" fill="#B48F70"/>';                       // sole edge
    s += '<path d="' + OUT + '" fill="' + M + '"/><path d="' + OUT + '" fill="url(#' + k + 'h)"/>';
    s += '<path d="' + OUT + '" transform="translate(0 107) scale(.9) translate(0 -107)" fill="none" stroke="rgba(255,255,255,.55)" stroke-width=".8" stroke-dasharray="2.2 2"/>';
    // opening: gathered binding (fine pleats), lining, insole with a tiny gold FUXIA
    s += '<ellipse cx="0" cy="148" rx="35.5" ry="62" fill="' + M + '"/>';
    var tk = ''; for (var i = 0; i < 110; i++) { var a = i / 110 * 6.2832, cx = Math.cos(a), cy = Math.sin(a), l = 3.2 + 1.6 * Math.abs(Math.sin(i * 2.3));
      tk += 'M' + f(cx * 31) + ' ' + f(148 + cy * 56.5) + 'L' + f(cx * (31 + l)) + ' ' + f(148 + cy * (56.5 + l)); }
    s += '<path d="' + tk + '" stroke="rgba(70,50,35,.17)" stroke-width=".6" fill="none"/>';
    s += '<ellipse cx="0" cy="148" rx="38.5" ry="65" fill="none" stroke="rgba(255,255,255,.5)" stroke-width=".7" stroke-dasharray="2 2"/>';
    s += '<ellipse cx="0" cy="149" rx="30" ry="55.5" fill="' + P.lin + '"/><ellipse cx="0" cy="154" rx="25.5" ry="48" fill="url(#' + k + 'i)"/>';
    s += '<text x="0" y="186" text-anchor="middle" font-family="Montserrat, system-ui, sans-serif" font-size="5.6" letter-spacing="1.6" fill="#B08A4E">FUXIA</text>';
    // strap across the instep
    var path = function (y0) { return 'M-47 ' + f(y0) + ' Q0 ' + f(y0 - 14) + ' 47 ' + f(y0); }, pts = function (n, y0, x0) { var r = []; for (var j = 0; j < n; j++) { var x = -x0 + 2 * x0 * j / (n - 1); r.push([x, strapY(x, y0)]); } return r; };
    if (o.tira === 'fruncido') {
      s += '<path d="' + path(129) + '" stroke="rgba(70,50,35,.25)" stroke-width="17" fill="none"/><path d="' + path(128) + '" stroke="' + M + '" stroke-width="15" fill="none"/>';
      var z = ''; for (var x = -44; x <= 44; x += 2.75) { var yy = strapY(x, 128), up = Math.round((x + 44) / 2.75) % 2; z += (x === -44 ? 'M' : 'L') + f(x) + ' ' + f(yy + (up ? -6 : 6)); }
      s += '<path d="' + z + '" stroke="rgba(70,50,35,.28)" stroke-width=".8" fill="none"/>';
    } else if (o.tira === 'doble') {
      [121, 137].forEach(function (y0) { s += '<path d="' + path(y0 + 1) + '" stroke="rgba(70,50,35,.25)" stroke-width="7.5" fill="none"/><path d="' + path(y0) + '" stroke="' + M + '" stroke-width="6" fill="none"/>' +
        '<path d="' + path(y0) + '" stroke="rgba(255,255,255,.45)" stroke-width=".6" stroke-dasharray="1.8 1.8" fill="none"/>'; });
    } else {
      s += '<path d="' + path(128) + '" stroke="#9C7634" stroke-width="2.6" fill="none"/>';
      pts(6, 128, 37).forEach(function (q) { s += sphere(k, q[0], q[1], 7.8); });
    }
    s += '<circle cx="' + (46 * side) + '" cy="' + (o.tira === 'doble' ? 121 : 128) + '" r="3.6" fill="url(#' + k + 'o)"/>' + (o.tira === 'doble' ? '<circle cx="' + (46 * side) + '" cy="137" r="3.2" fill="url(#' + k + 'o)"/>' : '');
    // adornment
    if (o.adorno !== 'ninguno') {
      var pearl = o.adorno === 'perlas', r = pearl ? 3.4 : 2.6;
      if (o.tira === 'fruncido') pts(7, 128, 32).forEach(function (q) { s += sphere(k, q[0], q[1], r, pearl); });
      else if (o.tira === 'doble') [121, 137].forEach(function (y0) { pts(5, y0, 28).forEach(function (q) { s += sphere(k, q[0], q[1], r * .9, pearl); }); });
      else for (var j = 0; j < 7; j++) { var a2 = Math.PI * (1.18 + .64 * j / 6); s += sphere(k, Math.cos(a2) * 39.5, 148 + Math.sin(a2) * 66, r, pearl); }
    }
    s += '<g transform="translate(' + (41 * side) + ' 194) rotate(' + (side * -18) + ')"><circle r="4.6" fill="none" stroke="#C9A25A" stroke-width=".9"/>' +
      '<text y="2.2" text-anchor="middle" font-family="Cormorant Garamond, Georgia, serif" font-style="italic" font-size="6.6" fill="#C9A25A">F</text></g>';
    return s;
  }
  function shoeSVG(o, single) {
    var k = 's' + (++gid), P = PIEL[o.piel] || PIEL.nude;
    var label = 'Ballerinas ' + P.n + ', ' + TIRA[o.tira].n + ', ' + ADORNO[o.adorno].n;
    if (single) return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-66 -10 132 240" width="132" height="240"><defs>' + shoeDefs(k, P) + '</defs>' + oneShoe(o, k, 1) + '</svg>';
    return '<svg class="f360k__shoe" viewBox="0 0 300 262" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="' + esc(label) + '"><defs>' + shoeDefs(k, P) + '</defs>' +
      '<g transform="translate(97 22) rotate(-6 0 108)">' + oneShoe(o, k, -1) + '</g><g transform="translate(203 26) rotate(6 0 108)">' + oneShoe(o, k, 1) + '</g></svg>';
  }
  function boxSVG(o, name) {        // her pair in an open gold gift box, seen from above like the shoes
    var pair = shoeSVG(o).replace('<svg class="f360k__shoe" viewBox="0 0 300 262"', '<svg x="70" y="64" width="280" height="245" viewBox="0 0 300 262"');
    return '<svg class="f360k__shoe" viewBox="0 0 420 400" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Su par en un estuche dorado">' +
      '<defs><linearGradient id="bxg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F3DFA8"/><stop offset=".4" stop-color="#C9A25A"/><stop offset=".62" stop-color="#EBD08F"/><stop offset="1" stop-color="#A98443"/></linearGradient>' +
      '<radialGradient id="bxt" cx=".5" cy=".45" r=".75"><stop offset="0" stop-color="#FBF1EF"/><stop offset="1" stop-color="#F0D9D8"/></radialGradient>' +
      '<filter id="bxs" x="-10%" y="-10%" width="120%" height="130%"><feGaussianBlur stdDeviation="8"/></filter></defs>' +
      '<rect x="292" y="10" width="112" height="230" rx="10" transform="rotate(12 348 125)" fill="url(#bxg)" opacity=".95"/>' +
      '<rect x="42" y="52" width="336" height="300" rx="14" fill="rgba(110,86,62,.32)" filter="url(#bxs)"/>' +
      '<rect x="40" y="44" width="340" height="300" rx="14" fill="url(#bxg)"/>' +
      '<rect x="56" y="58" width="308" height="272" rx="8" fill="url(#bxt)"/>' +
      '<path d="M56 58 L150 120 L56 200 Z M364 58 L270 124 L364 210 Z" fill="#F7E6E4" opacity=".8"/>' + pair +
      '<rect x="40" y="300" width="340" height="18" fill="#E2A6B0" opacity=".9"/>' +
      '<rect x="128" y="286" width="164" height="58" rx="6" fill="#FFFDF9" stroke="#C9A25A" stroke-width="1"/>' +
      '<text x="210" y="314" text-anchor="middle" font-family="Cormorant Garamond, Georgia, serif" font-style="italic" font-size="19" fill="#3A2E2A">' + esc(name || '') + '</text>' +
      '<text x="210" y="333" text-anchor="middle" font-family="Montserrat, system-ui, sans-serif" font-size="7.5" letter-spacing="3" fill="#857652">FUXIA KIDS</text></svg>';
  }
  var starIcon = '<svg viewBox="0 0 190 120" aria-hidden="true"><defs><linearGradient id="mst" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F6E4B5"/><stop offset="1" stop-color="#CFAE72"/></linearGradient></defs>' +
    [[50, 34, 15], [140, 26, 11], [98, 62, 22], [160, 82, 9], [34, 92, 8]].map(function (s) { var p = ''; for (var i = 0; i < 10; i++) { var a = i * Math.PI / 5 - Math.PI / 2, r = i % 2 ? s[2] * .44 : s[2]; p += (i ? 'L' : 'M') + (s[0] + Math.cos(a) * r).toFixed(1) + ' ' + (s[1] + Math.sin(a) * r).toFixed(1); }
      return '<path d="' + p + 'Z" fill="url(#mst)" stroke="#A9874F" stroke-width="1.2"/>'; }).join('') + '</svg>';

  // ── skeleton
  root.innerHTML =
    '<div class="f360k__view f360k__home">' +
      (franja ? '<div class="f360k__head"><h2 id="f360k-t" class="f360k__kids">KIDS</h2><span class="f360k__serif" style="font-size:24px">Juega con Fuxia Kids</span></div>'
              : '<h2 id="f360k-t" class="f360k__kids">KIDS</h2><p class="f360k__sub">Muy pronto, las primeras ballerinas para pequeñas bailarinas.<br>Mientras tanto… ¿jugamos?</p>') +
      '<div class="f360k__menu">' +
        '<button type="button" class="f360k__card" data-go="estrellas">' + starIcon + '<b>Atrapa las estrellas</b><span>50 segundos, tres niveles y el tablero de la semana.</span></button>' +
        '<button type="button" class="f360k__card" data-go="disena">' + shoeSVG({ piel: 'dorado', tira: 'esferas', adorno: 'ninguno' }) + '<b>Diseña tus ballerinas</b><span>Elige la piel, la tira y el adorno; guárdalas para mamá.</span></button>' +
      '</div>' +
      '<div class="f360k__board" aria-live="polite"><span class="f360k__lab">Las mejores de la semana</span><ol></ol><p class="f360k__boardnote">Cargando…</p></div>' +
    '</div>' +
    '<div class="f360k__view f360k__estrellas" hidden>' +
      '<div class="f360k__bar"><button type="button" class="f360k__back" data-go="home">‹ Menú</button><span class="f360k__lab">Atrapa las estrellas</span><span style="width:60px"></span></div>' +
      '<div class="f360k__play" tabindex="0" aria-label="Juego Atrapa las estrellas. Usa las flechas o arrastra para mover la ballerina.">' +
        '<canvas class="f360k__cv" role="img" aria-label="Una ballerina atrapa estrellas doradas que caen"></canvas>' +
        '<button type="button" class="f360k__pause" aria-label="Pausar" hidden>❚❚</button>' +
        '<div class="f360k__over" data-k="inicio"><span class="f360k__lab">Un juego Fuxia Kids</span><h3 class="f360k__serif">Atrapa las estrellas</h3>' +
          '<p class="f360k__txt">Arrastra la ballerina —o usa las flechas— y atrapa todas las estrellas que puedas en 50 segundos.</p>' +
          '<button type="button" class="f360k__btn" data-a="jugar">Jugar</button><span class="f360k__txt f360k__best" hidden></span></div>' +
        '<div class="f360k__over" data-k="pausa" hidden><h3 class="f360k__serif">En pausa</h3><button type="button" class="f360k__btn" data-a="seguir">Seguir jugando</button></div>' +
        '<div class="f360k__over" data-k="fin" hidden><span class="f360k__lab">Tus estrellas</span><b class="f360k__score">0</b><span class="f360k__txt f360k__best"></span>' +
          '<div class="f360k__row"><label class="f360k__live" for="f360k-n1">Tu nombre de bailarina</label><select id="f360k-n1" class="f360k__sel f360k__name">' + nameOptions(myName) + '</select>' +
          '<button type="button" class="f360k__btn" data-a="subir">Subir al tablero</button></div>' +
          '<p class="f360k__txt f360k__sent" aria-live="polite"></p>' +
          '<div class="f360k__board f360k__board--fin" hidden><span class="f360k__lab">Las mejores de la semana</span><ol></ol></div>' +
          '<p class="f360k__txt">Guarda tus estrellas: muy pronto podrás cambiarlas por un regalo.</p>' +
          '<div class="f360k__row"><button type="button" class="f360k__btn" data-a="jugar">Jugar otra vez</button><button type="button" class="f360k__btn f360k__btn--ghost" data-go="home">Menú</button></div></div>' +
      '</div>' +
    '</div>' +
    '<div class="f360k__view f360k__disena" hidden>' +
      '<div class="f360k__bar"><button type="button" class="f360k__back" data-go="home">‹ Menú</button><span class="f360k__lab">Diseña tus ballerinas</span><span style="width:60px"></span></div>' +
      '<div class="f360k__atelier"><div class="f360k__steps"></div><div class="f360k__stage"></div></div>' +
    '</div>' +
    '<p class="f360k__live" aria-live="polite"></p>';
  if (empty) empty.replaceWith(root); else anchor.parentNode.insertBefore(root, anchor);
  var live = root.querySelector('p.f360k__live:last-child');
  function say(t) { live.textContent = t; }
  var views = { home: root.querySelector('.f360k__home'), estrellas: root.querySelector('.f360k__estrellas'), disena: root.querySelector('.f360k__disena') };
  var current = 'home';
  function go(v) {
    if (current === 'estrellas' && v !== 'estrellas') stars.stop();
    current = v;
    for (var n in views) views[n].hidden = franja ? (n !== 'home' && n !== v) : n !== v;
    if (v === 'home') loadBoard();
    if (v === 'estrellas') stars.ready();
    if (v === 'disena') atelier.open();
    var tgt = views[v === 'home' ? 'home' : v]; if (v !== 'home' && tgt.scrollIntoView) tgt.scrollIntoView({ block: 'start', behavior: reduce ? 'auto' : 'smooth' });
  }

  // ── weekly board
  function renderBoard(list, data, mineScore) {
    var ol = list.querySelector('ol'), note = list.querySelector('.f360k__boardnote');
    var me = myName ? myName + ' ' + NUM : null, top = (data && data.top) || [];
    ol.innerHTML = top.map(function (r, i) { return '<li class="' + (r.name === me && (mineScore == null || r.score === mineScore) ? 'is-me' : '') + '"><span><em>' + (i + 1) + '</em>' + esc(r.name) + '</span><span>' + (+r.score) + ' ✦</span></li>'; }).join('');
    if (note) note.textContent = !data || data.ok === false ? 'El tablero no está disponible por ahora.' : top.length ? '' : '¡Sé la primera de la semana!';
  }
  function loadBoard() { var b = views.home.querySelector('.f360k__board'); if (!franja) api({ action: 'kids_top', market: MKT }).then(function (d) { renderBoard(b, d); }); }

  // ── game 1 · Atrapa las estrellas
  var stars = (function () {
    var v = views.estrellas, play = v.querySelector('.f360k__play'), cv = v.querySelector('.f360k__cv'), g = cv.getContext('2d'), pauseBtn = v.querySelector('.f360k__pause');
    var over = {}; v.querySelectorAll('.f360k__over').forEach(function (c) { over[c.getAttribute('data-k')] = c; });
    var ROUND = 50, W = 0, H = 0, dpr = 1, SPR = {}, last = 0, sized = false;
    function best(x) { var b = +(ls('f360k_best') || 0); if (x != null && x > b) { ls('f360k_best', String(x)); b = x; } return b; }
    function sprite(r, big) { var c = document.createElement('canvas'), s = Math.ceil(r * 2.6 * dpr); c.width = c.height = s; var x = c.getContext('2d'); x.scale(dpr, dpr); x.translate(r * 1.3, r * 1.3);
      x.beginPath(); for (var k = 0; k < 10; k++) { var a = k * Math.PI / 5 - Math.PI / 2, rr = k % 2 ? r * .44 : r; x.lineTo(Math.cos(a) * rr, Math.sin(a) * rr); } x.closePath();
      var gr = x.createLinearGradient(0, -r, 0, r); gr.addColorStop(0, big ? '#F6E4B5' : '#F1DDAB'); gr.addColorStop(1, big ? '#D9B36A' : '#CFAE72'); x.fillStyle = gr; x.fill(); x.lineWidth = 1.3; x.strokeStyle = '#A9874F'; x.stroke(); return c; }
    function resize() { var r = play.getBoundingClientRect(); if (!r.width) return; dpr = Math.min(window.devicePixelRatio || 1, 2); W = r.width; H = r.height; sized = true;
      cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr); g.setTransform(dpr, 0, 0, dpr, 0, 0);
      var u = Math.min(W, H * .75); SPR.s = sprite(u * .045); SPR.b = sprite(u * .07, true); SPR.u = u; if (!st.running) draw(); }
    var pieza = new Image(); pieza.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(shoeSVG({ piel: 'rosa', tira: 'fruncido', adorno: 'perlas' }, true));
    function shoe(x, y, w, tilt) {
      if (pieza.complete && pieza.naturalWidth) { var ih = w * 1.15, iw = ih * 132 / 240; g.save(); g.translate(x, y + ih * .22); g.rotate(tilt * .6); g.drawImage(pieza, -iw / 2, -ih / 2, iw, ih); g.restore(); return; }
      var h = w * .42; g.save(); g.translate(x, y); g.rotate(tilt);
      g.fillStyle = 'rgba(133,118,82,.16)'; g.beginPath(); g.ellipse(0, h * .55, w * .46, h * .12, 0, 0, 7); g.fill();
      g.beginPath(); g.moveTo(-w * .48, h * .1); g.bezierCurveTo(-w * .5, -h * .45, -w * .1, -h * .5, w * .05, -h * .32); g.bezierCurveTo(w * .25, -h * .42, w * .5, -h * .3, w * .5, h * .05);
      g.bezierCurveTo(w * .48, h * .42, -w * .4, h * .5, -w * .48, h * .1); g.closePath();
      var gr = g.createLinearGradient(0, -h * .5, 0, h * .5); gr.addColorStop(0, '#F0C3CB'); gr.addColorStop(1, '#D6919E'); g.fillStyle = gr; g.fill(); g.lineWidth = 1.6; g.strokeStyle = '#B8966E'; g.stroke();
      g.beginPath(); g.ellipse(-w * .12, -h * .2, w * .25, h * .17, -.08, 0, 7); g.fillStyle = '#FBEDEA'; g.fill(); g.lineWidth = 1.2; g.stroke();
      g.fillStyle = '#B8966E'; g.beginPath(); g.moveTo(w * .1, -h * .3); g.lineTo(w * .02, -h * .4); g.lineTo(w * .02, -h * .2); g.closePath(); g.fill();
      g.beginPath(); g.moveTo(w * .1, -h * .3); g.lineTo(w * .18, -h * .4); g.lineTo(w * .18, -h * .2); g.closePath(); g.fill(); g.beginPath(); g.arc(w * .1, -h * .3, w * .022, 0, 7); g.fill(); g.restore(); }
    var st = fresh(false);
    function fresh(run) { return { running: run, paused: false, t: 0, score: 0, level: 1, px: .5, tx: .5, vx: 0, stars: [], parts: [], pops: [], spawn: 0, banner: -9, keys: {}, sent: false }; }
    function levelAt(t) { return t < 18 ? 1 : t < 36 ? 2 : 3; }
    function show(k) { for (var n in over) over[n].hidden = n !== k; var b = k && over[k].querySelector('button,select'); if (b) b.focus({ preventScroll: true }); }
    function start() { st = fresh(true); show(null); pauseBtn.hidden = false; play.focus({ preventScroll: true });
      play.scrollIntoView({ block: 'end', behavior: reduce ? 'auto' : 'smooth' }); last = 0; requestAnimationFrame(loop); say('Empieza el juego. Nivel 1.'); }
    function end() { st.running = false; pauseBtn.hidden = true; var b = best(st.score);
      over.fin.querySelector('.f360k__score').textContent = st.score;
      over.fin.querySelector('.f360k__best').textContent = st.score >= b ? '¡Tu mejor marca!' : 'Tu mejor marca: ' + b + ' estrellas';
      over.fin.querySelector('.f360k__sent').textContent = ''; over.fin.querySelector('.f360k__board--fin').hidden = true;
      over.fin.querySelector('[data-a="subir"]').disabled = false; show('fin'); say('Se acabó el tiempo. Atrapaste ' + st.score + ' estrellas.'); }
    function pause(on) { if (!st.running || st.paused === on) return; st.paused = on; show(on ? 'pausa' : null); if (!on) { last = 0; play.focus({ preventScroll: true }); requestAnimationFrame(loop); } }
    function loop(now) { if (!st.running || st.paused) return; var dt = last ? Math.min((now - last) / 1000, 1 / 20) : 0; last = now; step(dt); draw();
      if (st.t >= ROUND) { end(); return; } requestAnimationFrame(loop); }
    function step(dt) { st.t += dt; var lv = levelAt(st.t); if (lv !== st.level) { st.level = lv; st.banner = st.t; say('¡Nivel ' + lv + '!'); }
      var u = SPR.u, k = st.keys;
      if (k.l || k.r) { st.vx += ((k.r ? 1 : 0) - (k.l ? 1 : 0)) * 3.2 * dt; st.vx *= .86; st.tx = Math.max(.08, Math.min(.92, st.px + st.vx)); }
      st.px += (st.tx - st.px) * Math.min(1, dt * 14);
      var rate = [1.3, 1.9, 2.6][lv - 1], speed = [.24, .32, .42][lv - 1]; st.spawn += dt * rate;
      while (st.spawn >= 1) { st.spawn -= 1; st.stars.push({ x: .08 + Math.random() * .84, y: -.06, v: speed * (.85 + Math.random() * .3), r: Math.random() * 6.3, w: (Math.random() - .5) * 1.4, big: Math.random() < .1 }); }
      var sx = st.px * W, sy = H * .8, sw = u * .26;
      for (var i = st.stars.length - 1; i >= 0; i--) { var s = st.stars[i]; s.y += s.v * dt; s.r += s.w * dt; var x = s.x * W, y = s.y * H, rr = (s.big ? .07 : .045) * u;
        if (y > sy - sw * .38 && y < sy + sw * .25 && Math.abs(x - sx) < sw * .6 + rr * .6) { var p = s.big ? 5 : 1; st.score += p; st.stars.splice(i, 1); st.pops.push({ x: x, y: y, t: 0, p: p });
          if (!reduce) for (var j = 0; j < (s.big ? 12 : 7); j++) { var a = Math.random() * 6.3, vv = 40 + Math.random() * 90; st.parts.push({ x: x, y: y, vx: Math.cos(a) * vv, vy: Math.sin(a) * vv - 30, t: 0 }); }
        } else if (s.y > 1.08) st.stars.splice(i, 1); }
      for (i = st.parts.length - 1; i >= 0; i--) { var q = st.parts[i]; q.t += dt; q.x += q.vx * dt; q.y += q.vy * dt; q.vy += 120 * dt; if (q.t > .7) st.parts.splice(i, 1); }
      for (i = st.pops.length - 1; i >= 0; i--) { st.pops[i].t += dt; if (st.pops[i].t > .9) st.pops.splice(i, 1); } }
    function draw() { if (!sized) return; var u = SPR.u || 1; g.clearRect(0, 0, W, H); g.fillStyle = 'rgba(201,168,111,.35)';
      for (var d = 0; d < 26; d++) { var dx = ((Math.sin(d * 12.9) * 43758.5) % 1 + 1) % 1 * W, dy = ((Math.sin(d * 78.2) * 12345.6) % 1 + 1) % 1 * H * .8; g.beginPath(); g.arc(dx, dy, 1 + (d % 3) * .5, 0, 7); g.fill(); }
      for (var i = 0; i < st.stars.length; i++) { var s = st.stars[i], sp = s.big ? SPR.b : SPR.s, w = sp.width / dpr; g.save(); g.translate(s.x * W, s.y * H); if (!reduce) g.rotate(s.r); g.drawImage(sp, -w / 2, -w / 2, w, w); g.restore(); }
      for (i = 0; i < st.parts.length; i++) { var q = st.parts[i]; g.globalAlpha = 1 - q.t / .7; g.fillStyle = '#C9A86F'; g.beginPath(); g.arc(q.x, q.y, 2.2 * (1 - q.t), 0, 7); g.fill(); }
      g.globalAlpha = 1; shoe(st.px * W, H * .8, u * .26, reduce ? 0 : (st.tx - st.px) * 1.2); g.textAlign = 'center';
      for (i = 0; i < st.pops.length; i++) { var o = st.pops[i]; g.globalAlpha = 1 - o.t / .9; g.fillStyle = '#857652'; g.font = 'italic 500 ' + Math.round(u * .075) + 'px "Cormorant Garamond", Georgia, serif'; g.fillText('+' + o.p, o.x, o.y - 30 - o.t * 40); }
      g.globalAlpha = 1;
      if (st.running) { g.textAlign = 'left'; g.fillStyle = '#857652'; g.font = '500 ' + Math.round(u * .034) + 'px system-ui, sans-serif'; g.fillText('NIVEL ' + st.level, 18, 30);
        g.textAlign = 'center'; g.font = 'italic 500 ' + Math.round(u * .085) + 'px "Cormorant Garamond", Georgia, serif'; g.fillStyle = '#3A2E2A';
        var sc = String(st.score), tw = g.measureText(sc).width; g.fillText(sc, W / 2 + u * .03, 42); g.fillStyle = '#B8966E'; g.fillText('✦', W / 2 - tw / 2 - u * .03, 42);
        g.fillStyle = 'rgba(184,150,110,.25)'; g.fillRect(18, H - 14, W - 36, 2); g.fillStyle = '#B8966E'; g.fillRect(18, H - 14, (W - 36) * (1 - st.t / ROUND), 2);
        var b = st.t - st.banner; if (b >= 0 && b < 1.4) { var al = reduce ? 1 : Math.min(1, b * 4, (1.4 - b) * 3), scl = reduce ? 1 : .85 + .15 * Math.min(1, b * 4);
          g.save(); g.globalAlpha = al; g.translate(W / 2, H * .42); g.scale(scl, scl); g.font = '700 ' + Math.round(u * .12) + 'px Fredoka, system-ui, sans-serif';
          g.fillStyle = '#B8966E'; g.fillText('¡Nivel ' + st.level + '!', 0, 4); g.fillStyle = '#E2A6B0'; g.fillText('¡Nivel ' + st.level + '!', 0, 0); g.restore(); } } }
    function toX(e) { var r = cv.getBoundingClientRect(); st.tx = Math.max(.08, Math.min(.92, (e.clientX - r.left) / r.width)); st.vx = 0; }
    cv.addEventListener('pointerdown', function (e) { if (!st.running) return; try { cv.setPointerCapture(e.pointerId); } catch (x) {} toX(e); });
    cv.addEventListener('pointermove', function (e) { if (st.running && (e.buttons || e.pointerType === 'touch')) toX(e); });
    play.addEventListener('keydown', function (e) { var k = e.key; if (k === 'ArrowLeft' || k === 'a' || k === 'A') { st.keys.l = 1; e.preventDefault(); }
      else if (k === 'ArrowRight' || k === 'd' || k === 'D') { st.keys.r = 1; e.preventDefault(); }
      else if ((k === 'Escape' || k === 'p' || k === 'P') && st.running) { pause(!st.paused); e.preventDefault(); } });
    play.addEventListener('keyup', function (e) { var k = e.key; if (k === 'ArrowLeft' || k === 'a' || k === 'A') st.keys.l = 0; if (k === 'ArrowRight' || k === 'd' || k === 'D') st.keys.r = 0; });
    pauseBtn.addEventListener('click', function () { pause(true); });
    document.addEventListener('visibilitychange', function () { if (document.hidden) pause(true); });
    if (window.ResizeObserver) new ResizeObserver(resize).observe(play); else window.addEventListener('resize', resize);
    function submit() {
      var sel = over.fin.querySelector('.f360k__name'), msg = over.fin.querySelector('.f360k__sent'), btn = over.fin.querySelector('[data-a="subir"]');
      if (NAMES.indexOf(sel.value) < 0) { msg.textContent = 'Primero elige tu nombre de bailarina.'; sel.focus(); return; }
      myName = sel.value; ls('f360k_name', myName); btn.disabled = true; msg.textContent = 'Subiendo…';
      api({ action: 'kids_score', market: MKT, name: myName, num: NUM, score: st.score, anon_id: DEV }).then(function (d) {
        if (!d || d.ok === false) { btn.disabled = false; msg.textContent = d && d.error === 'limite' ? 'Ya subiste muchas veces por hoy. ¡Vuelve mañana!' : 'No se pudo subir por ahora.'; return; }
        st.sent = true; msg.textContent = 'Subiste como ' + myName + ' ' + NUM + '. Tu mejor de la semana: ' + d.mine + ' ✦';
        var b = over.fin.querySelector('.f360k__board--fin'); b.hidden = false; renderBoard(b, d, d.mine); say(msg.textContent);
      });
    }
    v.addEventListener('click', function (e) { var b = e.target.closest('[data-a]'); if (!b) return; var a = b.getAttribute('data-a');
      if (a === 'jugar') start(); else if (a === 'seguir') pause(false); else if (a === 'subir') submit(); });
    return {
      ready: function () { resize(); var b = best(), bs = over.inicio.querySelector('.f360k__best'); bs.hidden = !b; if (b) bs.textContent = 'Tu mejor marca: ' + b + ' estrellas'; if (!st.running) { show('inicio'); draw(); } },
      stop: function () { if (st.running) { st.running = false; pauseBtn.hidden = true; } },
      start: start, state: function () { return st; }
    };
  })();

  // ── game 2 · Diseña tus ballerinas (atelier)
  var atelier = (function () {
    var v = views.disena, steps = v.querySelector('.f360k__steps'), stage = v.querySelector('.f360k__stage');
    var o = { piel: 'nude', tira: 'fruncido', adorno: 'taches' }, step = 0, name = myName;
    var STEPS = [{ k: 'piel', t: 'La piel', q: '¿De qué piel son tus ballerinas?', m: PIEL }, { k: 'tira', t: 'La tira', q: 'Elige la tira', m: TIRA },
                 { k: 'adorno', t: 'El adorno', q: 'Un último detalle', m: ADORNO }, { k: 'estuche', t: 'Su estuche' }];
    function swatch(k, id) { if (k === 'piel') return '<i style="background:' + PIEL[id].sw + '"></i>';
      if (k === 'tira') return '<i style="background:#fff;display:grid;place-items:center">' + (id === 'esferas' ? '<svg viewBox="0 0 30 30" width="26"><g fill="#C9A25A">' + [6, 11, 16, 21, 26].map(function (x, i) { return '<circle cx="' + x + '" cy="' + (17 - Math.sin(i / 4 * 3.14) * 7) + '" r="2.6"/>'; }).join('') + '</g></svg>'
        : '<svg viewBox="0 0 30 30" width="26"><path d="M4 22 C6 6 24 6 26 22" fill="none" stroke="#D9B59A" stroke-width="' + (id === 'doble' ? 2.6 : 4.5) + '"/>' + (id === 'doble' ? '<path d="M9 23 C11 11 22 11 24 23" fill="none" stroke="#D9B59A" stroke-width="2.6"/>' : '<path d="M4 22 C6 6 24 6 26 22" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="4.5" stroke-dasharray="1 1.8"/>') + '</svg>') + '</i>';
      return '<i style="background:#fff;display:grid;place-items:center">' + (id === 'ninguno' ? '<span style="color:#C9BDB3;font-size:16px">–</span>' : '<svg viewBox="0 0 30 30" width="22"><g fill="' + (id === 'perlas' ? '#F3ECE6' : '#C9A25A') + '" stroke="#B8A890" stroke-width=".6">' + [[9, 12], [21, 12], [15, 20]].map(function (p) { return '<circle cx="' + p[0] + '" cy="' + p[1] + '" r="' + (id === 'perlas' ? 4.4 : 3) + '"/>'; }).join('') + '</g></svg>') + '</i>'; }
    function render() {
      steps.innerHTML = STEPS.map(function (s, i) { return '<span class="' + (i === step ? 'is-on' : '') + '">' + (i + 1) + ' ' + s.t + '</span>'; }).join('');
      var S = STEPS[step];
      if (S.k !== 'estuche') {
        stage.innerHTML = '<span class="f360k__lab">Paso ' + (step + 1) + ' de 4</span><h3 class="f360k__serif" style="margin-top:6px">' + S.q + '</h3>' + shoeSVG(o) +
          '<div class="f360k__opts" role="group" aria-label="' + S.t + '">' + Object.keys(S.m).map(function (id) { return '<button type="button" class="f360k__opt" data-o="' + id + '" aria-pressed="' + (o[S.k] === id) + '">' + swatch(S.k, id) + esc(S.m[id].n) + '</button>'; }).join('') + '</div>' +
          '<div class="f360k__row">' + (step ? '<button type="button" class="f360k__btn f360k__btn--ghost" data-s="-1">Atrás</button>' : '') + '<button type="button" class="f360k__btn" data-s="1">' + (step === 2 ? 'Ponerlas en su estuche' : 'Siguiente') + '</button></div>';
      } else {
        stage.innerHTML = '<span class="f360k__lab">Tu diseño</span><h3 class="f360k__serif" style="margin-top:6px">Las ballerinas de…</h3>' +
          '<div class="f360k__row" style="margin:10px 0 4px"><label class="f360k__live" for="f360k-n2">Tu nombre de bailarina</label><select id="f360k-n2" class="f360k__sel f360k__name2">' + nameOptions(name) + '</select></div>' +
          '<div class="f360k__box">' + boxSVG(o, name) + '</div>' +
          '<p class="f360k__txt" style="margin:4px auto 12px">' + esc(PIEL[o.piel].n) + ' · ' + esc(TIRA[o.tira].n) + ' · ' + esc(ADORNO[o.adorno].n) + '</p>' +
          '<div class="f360k__row"><button type="button" class="f360k__btn f360k__btn--ghost" data-s="-1">Cambiar algo</button><button type="button" class="f360k__btn" data-a="guardar">Guardar para mamá</button></div>' +
          '<p class="f360k__txt f360k__saved" aria-live="polite" style="margin:10px auto 0"></p>' +
          '<div class="f360k__par"><span class="f360k__lab">El par Fuxia Kids más parecido</span><div class="f360k__parbody"><p class="f360k__txt" style="margin:10px auto">Buscando…</p></div></div>';
        similar();
      }
    }
    var products = null;
    function similar() {
      var body = stage.querySelector('.f360k__parbody');
      (products ? Promise.resolve(products) : fetch(BASE + 'wp-json/wc/store/v1/products?category=' + KIDS_CAT + '&per_page=50', { credentials: 'same-origin' })
        .then(function (r) { return r.ok ? r.json() : []; }).catch(function () { return []; })).then(function (list) {
        products = Array.isArray(list) ? list : [];
        if (!products.length) { body.innerHTML = '<p class="f360k__serif" style="font-size:24px;margin:12px 0 4px">Muy pronto en Fuxia Kids</p><p class="f360k__txt" style="margin:0 auto 6px">Estamos preparando las primeras ballerinas para pequeñas bailarinas.</p>'; return; }
        var best = null, bs = -1;
        products.forEach(function (p) {
          var colors = []; (p.attributes || []).forEach(function (a) { if (/color/i.test(a.taxonomy || a.name || '')) (a.terms || []).forEach(function (t) { colors.push(String(t.name || t.slug).toLowerCase()); }); });
          var text = (String(p.name || '') + ' ' + String(p.short_description || '')).toLowerCase(), all = text + ' ' + colors.join(' ');
          var sc = 0; PIEL[o.piel].w.forEach(function (w) { if (colors.join(' ').indexOf(w) >= 0) sc += 3; else if (all.indexOf(w) >= 0) sc += 2; });
          TIRA[o.tira].w.forEach(function (w) { if (all.indexOf(w) >= 0) sc += 2; }); ADORNO[o.adorno].w.forEach(function (w) { if (all.indexOf(w) >= 0) sc += 1; });
          if (sc > bs) { bs = sc; best = p; } });
        var img = best.images && best.images[0] ? best.images[0] : null;
        body.innerHTML = (img ? '<img src="' + esc(img.thumbnail || img.src) + '" alt="' + esc(img.alt || best.name) + '" loading="lazy">' : '') +
          '<p class="f360k__serif" style="font-size:24px;margin:2px 0 10px">' + esc(best.name) + '</p><a class="f360k__btn" href="' + esc(best.permalink) + '">Verlo</a>';
      });
    }
    function save() {
      var msg = stage.querySelector('.f360k__saved'), who = name || 'una pequeña bailarina';
      var svg = boxSVG(o, name || '').replace('<svg class="f360k__shoe"', '<svg width="860" height="819"');
      var img = new Image(), c = document.createElement('canvas'); c.width = 1080; c.height = 1350; var x = c.getContext('2d');
      msg.textContent = 'Preparando tu imagen…';
      img.onload = function () {
        var gr = x.createLinearGradient(0, 0, 0, 1350); gr.addColorStop(0, '#FBF6F1'); gr.addColorStop(1, '#F3DADB'); x.fillStyle = gr; x.fillRect(0, 0, 1080, 1350);
        x.strokeStyle = 'rgba(184,150,110,.6)'; x.lineWidth = 2; x.strokeRect(40, 40, 1000, 1270);
        x.textAlign = 'center'; x.fillStyle = '#857652'; x.font = '500 26px Montserrat, system-ui, sans-serif'; x.fillText('F U X I A   K I D S', 540, 150);
        x.fillStyle = '#3A2E2A'; x.font = 'italic 500 64px "Cormorant Garamond", Georgia, serif'; x.fillText('Las ballerinas de', 540, 250);
        x.fillStyle = '#C97F8D'; x.font = 'italic 600 84px "Cormorant Garamond", Georgia, serif'; x.fillText(who, 540, 350);
        x.drawImage(img, 110, 372, 860, 819);
        x.fillStyle = '#8B7F78'; x.font = '500 28px Montserrat, system-ui, sans-serif'; x.fillText(PIEL[o.piel].n + ' · ' + TIRA[o.tira].n + ' · ' + ADORNO[o.adorno].n, 540, 1236);
        x.fillStyle = '#857652'; x.font = '500 22px Montserrat, system-ui, sans-serif'; x.fillText('Diseñadas por ella en fuxiaballerinas.com', 540, 1284);
        c.toBlob(function (blob) {
          if (!blob) { msg.textContent = 'No se pudo crear la imagen.'; return; }
          var file = window.File ? new File([blob], 'ballerinas-fuxia-kids.png', { type: 'image/png' }) : null;
          if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
            navigator.share({ files: [file], title: 'Mis ballerinas Fuxia Kids', text: 'Las ballerinas que diseñé en Fuxia Kids ✦' })
              .then(function () { msg.textContent = '¡Listo! Ya la compartiste.'; }).catch(function () { msg.textContent = ''; });
          } else { var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'ballerinas-fuxia-kids.png'; document.body.appendChild(a); a.click();
            setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1500); msg.textContent = 'Listo: la imagen se descargó para que se la mandes a mamá.'; }
          root.f360kLastPng = blob;                            // QA hook (read only)
        }, 'image/png');
      };
      img.onerror = function () { msg.textContent = 'No se pudo crear la imagen.'; };
      img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    }
    v.addEventListener('click', function (e) {
      var b = e.target.closest('[data-o],[data-s],[data-a]'); if (!b) return;
      if (b.hasAttribute('data-o')) { o[STEPS[step].k] = b.getAttribute('data-o'); var svg = stage.querySelector('.f360k__shoe'); svg.outerHTML = shoeSVG(o);
        stage.querySelectorAll('.f360k__opt').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); }); say(STEPS[step].m[o[STEPS[step].k]].n); return; }
      if (b.hasAttribute('data-s')) { step = Math.max(0, Math.min(3, step + +b.getAttribute('data-s'))); render(); var h = stage.querySelector('h3'); if (h) { h.setAttribute('tabindex', '-1'); h.focus({ preventScroll: true }); } return; }
      if (b.getAttribute('data-a') === 'guardar') save();
    });
    v.addEventListener('change', function (e) { if (!e.target.classList.contains('f360k__name2')) return; name = NAMES.indexOf(e.target.value) >= 0 ? e.target.value : '';
      if (name) { myName = name; ls('f360k_name', name); } stage.querySelector('.f360k__box').innerHTML = boxSVG(o, name); });
    return { open: function () { step = 0; render(); }, state: function () { return { o: o, step: step, name: name }; } };
  })();

  root.addEventListener('click', function (e) { var b = e.target.closest('[data-go]'); if (b) go(b.getAttribute('data-go')); });
  go('home');
  root.f360k = { go: go, stars: stars, atelier: atelier };      // QA hook (no effect for visitors)
})();
</script>
F360SNIP;
});
