<?php
/**
 * Plugin Name: Fuxia 360 · Fuxia Kids · "Atrapa las estrellas" (producción)
 * Description: Mario 2026-10-24: "mientras en Fuxia Kids no hay nada, veme desarrollando el juego para que puedan jugar en lo que
 *              subimos los zapatos". On the Kids category page, while it has NO products (Woo prints its "no products" box), that
 *              box is replaced by a small game: a ballerina flat catches falling gold stars for 50 s, three levels. Look of the
 *              Fuxia Kids maquetas (ivory, dusty rose, gold; Cormorant + the KIDS lettering). No music, no accounts, no coupon,
 *              no personal data, nothing sent to any server: only the best score stays in the visitor's browser (localStorage).
 *              The prize for the stars is NOT decided (Mario): the end screen only says it is coming. As soon as Kids has
 *              products, Woo stops printing the "no products" box and the game simply does not appear.
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
  echo '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;1,500&family=Fredoka:wght@700&display=swap">' . "\n";
}, 5);
add_action('wp_footer', function () {
  if (!f360_kids_juego_here()) return;
  echo <<<'F360SNIP'
<template id="f360k-tpl">
<section class="f360k" aria-labelledby="f360k-t">
  <header class="f360k__head">
    <svg class="f360k__logo" role="img" aria-label="Fuxia Ballerinas" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="25.61 25.97 189.36 32.93"> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 64.25 47.59375 L 65.519531 47.59375 L 65.519531 42.832031 L 70.714844 42.832031 L 70.714844 41.609375 L 65.519531 41.609375 L 65.519531 37.703125 L 71.316406 37.703125 L 71.316406 36.480469 L 64.25 36.480469 Z M 64.25 47.59375 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 81.003906 43.019531 C 81.003906 45.179688 79.734375 46.4375 77.621094 46.4375 C 75.511719 46.4375 74.207031 45.179688 74.207031 43.019531 L 74.207031 36.480469 L 72.9375 36.480469 L 72.9375 43.019531 C 72.9375 45.910156 74.699219 47.65625 77.621094 47.65625 C 80.527344 47.65625 82.273438 45.910156 82.273438 43.019531 L 82.273438 36.480469 L 81.003906 36.480469 Z M 81.003906 43.019531 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 93.488281 36.480469 L 91.996094 36.480469 L 88.898438 40.765625 L 85.832031 36.480469 L 84.339844 36.480469 L 88.136719 41.878906 L 84.054688 47.59375 L 85.546875 47.59375 L 88.898438 42.941406 L 92.28125 47.59375 L 93.804688 47.59375 L 89.707031 41.816406 Z M 93.488281 36.480469 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 95.949219 47.59375 L 97.21875 47.59375 L 97.21875 36.480469 L 95.949219 36.480469 Z M 95.949219 47.59375 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 102.09375 43.5625 L 104.570312 37.921875 L 107.082031 43.5625 Z M 103.953125 36.480469 L 98.96875 47.59375 L 100.316406 47.59375 L 101.554688 44.785156 L 107.621094 44.785156 L 108.859375 47.59375 L 110.242188 47.59375 L 105.269531 36.480469 Z M 103.953125 36.480469 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 120.960938 46.386719 L 117.609375 46.386719 L 117.609375 42.480469 L 120.960938 42.480469 C 122.773438 42.480469 123.820312 43.195312 123.820312 44.402344 C 123.820312 45.671875 122.773438 46.386719 120.960938 46.386719 M 117.609375 37.703125 L 120.960938 37.703125 C 122.453125 37.703125 123.328125 38.335938 123.328125 39.464844 C 123.328125 40.625 122.453125 41.273438 120.960938 41.273438 L 117.609375 41.273438 Z M 122.566406 41.765625 C 123.867188 41.496094 124.613281 40.558594 124.613281 39.257812 C 124.613281 37.511719 123.261719 36.480469 121.023438 36.480469 L 116.339844 36.480469 L 116.339844 47.59375 L 121.105469 47.59375 C 123.613281 47.59375 125.105469 46.464844 125.105469 44.578125 C 125.105469 43.054688 124.167969 42.003906 122.566406 41.765625 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 129.21875 43.5625 L 131.695312 37.921875 L 134.207031 43.5625 Z M 131.078125 36.480469 L 126.09375 47.59375 L 127.441406 47.59375 L 128.679688 44.785156 L 134.746094 44.785156 L 135.984375 47.59375 L 137.367188 47.59375 L 132.394531 36.480469 Z M 131.078125 36.480469 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 140.382812 36.480469 L 139.113281 36.480469 L 139.113281 47.59375 L 145.257812 47.59375 L 145.257812 46.386719 L 140.382812 46.386719 Z M 140.382812 36.480469 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 148.59375 36.480469 L 147.324219 36.480469 L 147.324219 47.59375 L 153.46875 47.59375 L 153.46875 46.386719 L 148.59375 46.386719 Z M 148.59375 36.480469 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 156.804688 42.578125 L 162.410156 42.578125 L 162.410156 41.355469 L 156.804688 41.355469 L 156.804688 37.703125 L 163.078125 37.703125 L 163.078125 36.480469 L 155.535156 36.480469 L 155.535156 47.59375 L 163.285156 47.59375 L 163.285156 46.386719 L 156.804688 46.386719 Z M 156.804688 42.578125 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 170.097656 42.863281 L 167.144531 42.863281 L 167.144531 37.703125 L 170.097656 37.703125 C 172.113281 37.703125 173.257812 38.558594 173.257812 40.242188 C 173.257812 41.972656 172.113281 42.863281 170.097656 42.863281 M 174.480469 40.210938 C 174.480469 37.84375 172.875 36.480469 170.097656 36.480469 L 165.875 36.480469 L 165.875 47.59375 L 167.144531 47.59375 L 167.144531 44.085938 L 170.097656 44.085938 C 170.351562 44.085938 170.605469 44.070312 170.84375 44.054688 L 173.148438 47.59375 L 174.59375 47.59375 L 171.988281 43.816406 C 173.589844 43.292969 174.480469 42.050781 174.480469 40.210938 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 177.355469 47.59375 L 178.625 47.59375 L 178.625 36.480469 L 177.355469 36.480469 Z M 177.355469 47.59375 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 189.980469 45.417969 L 183.3125 36.480469 L 181.992188 36.480469 L 181.992188 47.59375 L 183.261719 47.59375 L 183.261719 38.671875 L 189.933594 47.59375 L 191.234375 47.59375 L 191.234375 36.480469 L 189.980469 36.480469 Z M 189.980469 45.417969 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 196.128906 43.5625 L 198.605469 37.921875 L 201.113281 43.5625 Z M 197.984375 36.480469 L 193 47.59375 L 194.347656 47.59375 L 195.589844 44.785156 L 201.652344 44.785156 L 202.894531 47.59375 L 204.273438 47.59375 L 199.304688 36.480469 Z M 197.984375 36.480469 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 206.753906 39.195312 C 206.753906 38.257812 207.6875 37.71875 209.117188 37.71875 C 210.007812 37.71875 211.183594 37.988281 212.183594 38.65625 L 212.722656 37.464844 C 211.800781 36.84375 210.484375 36.429688 209.199219 36.429688 C 206.894531 36.429688 205.355469 37.558594 205.355469 39.304688 C 205.355469 43.292969 211.613281 41.734375 211.597656 44.65625 C 211.597656 45.71875 210.59375 46.371094 208.992188 46.371094 C 207.738281 46.371094 206.324219 45.800781 205.292969 44.800781 L 204.71875 45.941406 C 205.769531 46.945312 207.355469 47.640625 208.976562 47.640625 C 211.359375 47.640625 212.992188 46.453125 212.992188 44.59375 C 213.007812 40.558594 206.753906 42.054688 206.753906 39.195312 "/> <path fill-rule="nonzero" fill="currentColor" fill-opacity="1" d="M 35.417969 28.21875 C 34.332031 29.796875 32.085938 33.59375 32.6875 37.207031 C 32.960938 38.851562 33.808594 40.289062 35.207031 41.484375 C 35.460938 41.027344 35.875 40.519531 36.410156 39.875 C 37.683594 38.332031 39.429688 36.226562 39.300781 33.703125 C 39.144531 30.660156 36.433594 28.808594 35.417969 28.21875 M 47.410156 28.21875 C 46.394531 28.808594 43.683594 30.664062 43.527344 33.703125 C 43.398438 36.226562 45.144531 38.335938 46.421875 39.875 C 46.953125 40.519531 47.367188 41.027344 47.621094 41.484375 C 49.019531 40.289062 49.867188 38.851562 50.140625 37.207031 C 50.742188 33.59375 48.496094 29.796875 47.410156 28.21875 M 42.050781 47.210938 C 42.925781 48.4375 43.453125 49.710938 43.621094 51 C 43.863281 52.871094 43.320312 54.421875 42.722656 55.492188 C 50.101562 52.097656 53.972656 46.738281 53.925781 39.964844 L 53.925781 39.800781 C 53.925781 36.191406 51.910156 32.90625 49.941406 30.558594 C 50.808594 32.449219 51.539062 34.910156 51.132812 37.371094 C 50.738281 39.738281 49.347656 41.703125 46.992188 43.203125 C 44.851562 44.480469 43.191406 45.828125 42.050781 47.210938 M 32.886719 30.558594 C 30.917969 32.90625 28.902344 36.191406 28.902344 39.800781 L 28.902344 39.964844 C 28.855469 46.738281 32.726562 52.097656 40.105469 55.492188 C 39.511719 54.421875 38.964844 52.871094 39.207031 51 C 39.375 49.710938 39.90625 48.4375 40.78125 47.210938 C 39.636719 45.824219 37.976562 44.480469 35.839844 43.207031 C 33.484375 41.703125 32.089844 39.738281 31.695312 37.371094 C 31.289062 34.910156 32.019531 32.449219 32.886719 30.558594 M 41.414062 48.0625 C 40.746094 49.066406 40.339844 50.09375 40.207031 51.121094 C 39.9375 53.171875 40.792969 54.800781 41.414062 55.675781 C 42.035156 54.800781 42.890625 53.175781 42.621094 51.121094 C 42.488281 50.09375 42.082031 49.066406 41.414062 48.0625 M 41.386719 57.167969 L 41.378906 57.171875 L 41.296875 57.097656 L 41.148438 57.046875 C 32.550781 53.585938 27.84375 47.519531 27.898438 39.960938 L 27.898438 39.800781 C 27.898438 32.71875 34.699219 27.183594 34.992188 26.953125 L 35.070312 26.886719 L 35.488281 27.109375 C 35.546875 27.140625 35.667969 27.199219 35.828125 27.292969 C 37.136719 28.03125 40.121094 30.085938 40.304688 33.652344 C 40.453125 36.566406 38.5625 38.847656 37.183594 40.515625 C 36.726562 41.066406 36.214844 41.683594 36.019531 42.109375 L 36.03125 42.117188 C 36.140625 42.195312 36.25 42.277344 36.367188 42.351562 C 38.507812 43.625 40.207031 44.988281 41.414062 46.398438 C 42.621094 44.988281 44.320312 43.625 46.464844 42.347656 C 46.578125 42.277344 46.683594 42.199219 46.792969 42.125 L 46.808594 42.109375 C 46.632812 41.71875 46.191406 41.175781 45.648438 40.515625 C 44.265625 38.847656 42.375 36.566406 42.523438 33.652344 C 42.707031 30.085938 45.691406 28.027344 46.964844 27.308594 C 47.164062 27.199219 47.28125 27.140625 47.34375 27.109375 L 47.757812 26.886719 L 47.839844 26.953125 C 48.128906 27.183594 54.929688 32.726562 54.929688 39.800781 L 54.929688 39.960938 C 54.984375 47.519531 50.277344 53.585938 41.679688 57.046875 L 41.488281 57.125 L 41.414062 57.203125 Z M 41.386719 57.167969 "/> </svg>
    <h2 id="f360k-t" class="f360k__kids">KIDS</h2>
    <p class="f360k__sub">Muy pronto, las primeras ballerinas para pequeñas bailarinas.<br>Mientras tanto… ¿jugamos?</p>
  </header>
  <div class="f360k__play" tabindex="0" aria-label="Juego Atrapa las estrellas. Usa las flechas o arrastra para mover la ballerina.">
    <canvas class="f360k__cv" role="img" aria-label="Una ballerina atrapa estrellas doradas que caen"></canvas>
    <button type="button" class="f360k__pause" aria-label="Pausar" hidden>❚❚</button>
    <div class="f360k__card" data-k="inicio">
      <span class="f360k__lab">Un juego Fuxia Kids</span>
      <h3 class="f360k__serif">Atrapa las estrellas</h3>
      <p class="f360k__txt">Arrastra la ballerina —o usa las flechas— y atrapa todas las estrellas que puedas en 50 segundos.</p>
      <button type="button" class="f360k__btn" data-a="jugar">Jugar</button>
      <span class="f360k__best" hidden></span>
    </div>
    <div class="f360k__card" data-k="pausa" hidden>
      <h3 class="f360k__serif">En pausa</h3>
      <button type="button" class="f360k__btn" data-a="seguir">Seguir jugando</button>
    </div>
    <div class="f360k__card" data-k="fin" hidden>
      <span class="f360k__lab">Tus estrellas</span>
      <b class="f360k__score">0</b>
      <span class="f360k__best" hidden></span>
      <p class="f360k__txt">Guarda tus estrellas: muy pronto podrás cambiarlas por un regalo.</p>
      <button type="button" class="f360k__btn" data-a="jugar">Jugar otra vez</button>
      <span class="f360k__lab f360k__pronto">Muy pronto · Fuxia Kids</span>
    </div>
  </div>
  <p class="f360k__live" aria-live="polite"></p>
</section>
</template>
<style>
.f360k{--marfil:#FBF6F1;--rosa:#E2A6B0;--rosa2:#C97F8D;--oro:#B8966E;--oro2:#857652;--tinta:#3A2E2A;--gris:#8B7F78;
  box-sizing:border-box;max-width:560px;margin:8px auto 48px;padding:28px 16px 8px;text-align:center;color:var(--tinta);font-family:inherit}
.f360k *,.f360k *::before,.f360k *::after{box-sizing:border-box}
.f360k__logo{display:block;width:170px;height:auto;margin:0 auto 10px;color:var(--oro2)}
.f360k__kids{margin:0;font-family:Fredoka,system-ui,sans-serif;font-weight:700;font-size:72px;line-height:.95;letter-spacing:.03em;color:var(--rosa);
  text-shadow:0 1px 0 #fff,0 4px 0 var(--oro),0 14px 26px rgba(133,118,82,.25)}
.f360k__sub{margin:18px auto 22px;max-width:380px;font-family:"Cormorant Garamond",Georgia,serif;font-style:italic;font-size:21px;line-height:1.3;color:var(--tinta)}
.f360k__play{position:relative;width:100%;aspect-ratio:3/4;max-height:78vh;margin:0 auto;border-radius:22px;overflow:hidden;outline:none;
  background:linear-gradient(#FBF6F1,#F8EBE8 60%,#F1D6D8);box-shadow:0 0 0 1px rgba(184,150,110,.55),0 0 0 7px #fff,0 0 0 8px rgba(184,150,110,.3),0 24px 44px rgba(133,118,82,.16)}
.f360k__play:focus-visible{box-shadow:0 0 0 2px var(--oro2),0 0 0 7px #fff,0 0 0 9px var(--oro),0 24px 44px rgba(133,118,82,.16)}
.f360k__cv{position:absolute;inset:0;width:100%;height:100%;display:block;touch-action:none}
.f360k__card{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;padding:24px;
  background:rgba(251,246,241,.86);-webkit-backdrop-filter:blur(3px);backdrop-filter:blur(3px)}
.f360k__card[hidden],.f360k__best[hidden],.f360k__pause[hidden]{display:none}
.f360k__lab{font-size:10.5px;font-weight:500;letter-spacing:.32em;text-transform:uppercase;color:var(--oro2)}
.f360k__serif{margin:0;font-family:"Cormorant Garamond",Georgia,serif;font-style:italic;font-weight:500;font-size:38px;line-height:1.05;color:var(--tinta)}
.f360k__txt{margin:0;max-width:300px;font-size:14px;line-height:1.55;color:var(--gris)}
.f360k__score{font-family:"Cormorant Garamond",Georgia,serif;font-weight:500;font-size:86px;line-height:1;color:var(--rosa2);font-variant-numeric:lining-nums}
.f360k__btn{margin-top:6px;min-height:48px;padding:0 34px;border:0;border-radius:999px;background:var(--tinta);color:#F7E7C4;font:600 13px/1 inherit;letter-spacing:.18em;text-transform:uppercase;cursor:pointer}
.f360k__btn:hover{background:#4a3c37}.f360k__btn:focus-visible{outline:2px solid var(--oro);outline-offset:3px}
.f360k__best{font-size:12px;letter-spacing:.08em;color:var(--gris)}
.f360k__pronto{margin-top:8px}
.f360k__pause{position:absolute;top:12px;right:12px;width:40px;height:40px;border:1px solid var(--oro);border-radius:50%;background:rgba(255,255,255,.75);color:var(--oro2);font-size:12px;cursor:pointer}
.f360k__pause:focus-visible{outline:2px solid var(--oro2);outline-offset:2px}
.f360k__live{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
@media (max-width:420px){.f360k__kids{font-size:60px}.f360k__sub{font-size:19px}}
</style>
<script>
(function () {
  var box = document.querySelector('.woocommerce-no-products-found'), tpl = document.getElementById('f360k-tpl');
  if (!box || !tpl || !window.HTMLCanvasElement) return;            // Kids has products: the store shows them, no game
  box.replaceWith(tpl.content.cloneNode(true));
  var root = document.querySelector('.f360k'), play = root.querySelector('.f360k__play'), cv = root.querySelector('.f360k__cv'),
      g = cv.getContext('2d'), live = root.querySelector('.f360k__live'), pauseBtn = root.querySelector('.f360k__pause');
  var cards = {}; root.querySelectorAll('.f360k__card').forEach(function (c) { cards[c.getAttribute('data-k')] = c; });
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  var ROUND = 50, W = 0, H = 0, dpr = 1, KEY = 'f360k_best';
  function best(v) { try { if (v != null) localStorage.setItem(KEY, String(v)); return +(localStorage.getItem(KEY) || 0); } catch (e) { return 0; } }

  // star sprite, drawn once (gold, thin outline) → cheap drawImage per frame
  function starSprite(r, big) {
    var c = document.createElement('canvas'), s = Math.ceil(r * 2.6 * dpr); c.width = c.height = s;
    var x = c.getContext('2d'); x.scale(dpr, dpr); x.translate(r * 1.3, r * 1.3);
    x.beginPath(); for (var k = 0; k < 10; k++) { var a = k * Math.PI / 5 - Math.PI / 2, rr = k % 2 ? r * .44 : r; x.lineTo(Math.cos(a) * rr, Math.sin(a) * rr); } x.closePath();
    var gr = x.createLinearGradient(0, -r, 0, r); gr.addColorStop(0, big ? '#F6E4B5' : '#F1DDAB'); gr.addColorStop(1, big ? '#D9B36A' : '#CFAE72');
    x.fillStyle = gr; x.fill(); x.lineWidth = 1.3; x.strokeStyle = '#A9874F'; x.stroke(); return c;
  }
  var SPR = {};
  function resize() {
    var r = play.getBoundingClientRect(); dpr = Math.min(window.devicePixelRatio || 1, 2); W = r.width; H = r.height;
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr); g.setTransform(dpr, 0, 0, dpr, 0, 0);
    var u = Math.min(W, H * .75); SPR.s = starSprite(u * .045, false); SPR.b = starSprite(u * .07, true); SPR.u = u;
    if (!st.running) draw(0);
  }

  // the ballerina flat (drawn, not a product): rose leather, gold piping, bow
  function shoe(x, y, w, tilt) {
    var h = w * .42; g.save(); g.translate(x, y); g.rotate(tilt);
    g.fillStyle = 'rgba(133,118,82,.16)'; g.beginPath(); g.ellipse(0, h * .55, w * .46, h * .12, 0, 0, 7); g.fill();
    g.beginPath(); g.moveTo(-w * .48, h * .1);
    g.bezierCurveTo(-w * .5, -h * .45, -w * .1, -h * .5, w * .05, -h * .32); g.bezierCurveTo(w * .25, -h * .42, w * .5, -h * .3, w * .5, h * .05);
    g.bezierCurveTo(w * .48, h * .42, -w * .4, h * .5, -w * .48, h * .1); g.closePath();
    var gr = g.createLinearGradient(0, -h * .5, 0, h * .5); gr.addColorStop(0, '#F0C3CB'); gr.addColorStop(1, '#D6919E'); g.fillStyle = gr; g.fill();
    g.lineWidth = 1.6; g.strokeStyle = '#B8966E'; g.stroke();
    g.beginPath(); g.ellipse(-w * .12, -h * .2, w * .25, h * .17, -.08, 0, 7); g.fillStyle = '#FBEDEA'; g.fill(); g.lineWidth = 1.2; g.stroke();
    g.fillStyle = '#B8966E'; g.beginPath(); g.moveTo(w * .1, -h * .3); g.lineTo(w * .02, -h * .4); g.lineTo(w * .02, -h * .2); g.closePath(); g.fill();
    g.beginPath(); g.moveTo(w * .1, -h * .3); g.lineTo(w * .18, -h * .4); g.lineTo(w * .18, -h * .2); g.closePath(); g.fill();
    g.beginPath(); g.arc(w * .1, -h * .3, w * .022, 0, 7); g.fill();
    g.restore();
  }

  var st = { running: false, paused: false, t: 0, score: 0, level: 1, px: .5, tx: .5, vx: 0, stars: [], parts: [], pops: [], spawn: 0, banner: -9, keys: {} };
  function levelAt(t) { return t < 18 ? 1 : t < 36 ? 2 : 3; }
  function start() {
    st = { running: true, paused: false, t: 0, score: 0, level: 1, px: .5, tx: .5, vx: 0, stars: [], parts: [], pops: [], spawn: 0, banner: -9, keys: {} };
    show(null); pauseBtn.hidden = false; play.focus({ preventScroll: true }); last = 0; requestAnimationFrame(loop); say('Empieza el juego. Nivel 1.');
  }
  function end() {
    st.running = false; pauseBtn.hidden = true;
    var b = Math.max(best(), st.score); best(b);
    cards.fin.querySelector('.f360k__score').textContent = st.score;
    var bb = cards.fin.querySelector('.f360k__best'); bb.hidden = false; bb.textContent = st.score >= b ? '¡Tu mejor marca!' : 'Tu mejor marca: ' + b + ' estrellas';
    show('fin'); say('Se acabó el tiempo. Atrapaste ' + st.score + ' estrellas.');
  }
  function show(k) { for (var n in cards) cards[n].hidden = n !== k; var btn = k && cards[k].querySelector('button'); if (btn) btn.focus({ preventScroll: true }); }
  function say(t) { live.textContent = t; }
  function pause(on) { if (!st.running || st.paused === on) return; st.paused = on; show(on ? 'pausa' : null); if (!on) { last = 0; play.focus({ preventScroll: true }); requestAnimationFrame(loop); } }

  var last = 0;
  function loop(now) {
    if (!st.running || st.paused) return;
    var dt = last ? Math.min((now - last) / 1000, 1 / 20) : 0; last = now; step(dt); draw(dt);
    if (st.t >= ROUND) { end(); return; } requestAnimationFrame(loop);
  }
  function step(dt) {
    st.t += dt; var lv = levelAt(st.t);
    if (lv !== st.level) { st.level = lv; st.banner = st.t; say('¡Nivel ' + lv + '!'); }
    var u = SPR.u, k = st.keys;                                    // movement: keys accelerate, drag sets a target
    if (k.l || k.r) { st.vx += ((k.r ? 1 : 0) - (k.l ? 1 : 0)) * 3.2 * dt; st.vx *= .86; st.tx = Math.max(.08, Math.min(.92, st.px + st.vx)); }
    st.px += (st.tx - st.px) * Math.min(1, dt * 14);
    var rate = [1.1, 1.7, 2.4][lv - 1], speed = [.24, .32, .42][lv - 1];
    st.spawn += dt * rate;
    while (st.spawn >= 1) { st.spawn -= 1; var big = Math.random() < .1;
      st.stars.push({ x: .08 + Math.random() * .84, y: -.06, v: speed * (.85 + Math.random() * .3), r: Math.random() * 6.3, w: (Math.random() - .5) * 1.4, big: big }); }
    var sx = st.px * W, sy = H * .86, sw = u * .26;
    for (var i = st.stars.length - 1; i >= 0; i--) {
      var s = st.stars[i]; s.y += s.v * dt; s.r += s.w * dt;
      var x = s.x * W, y = s.y * H, rr = (s.big ? .07 : .045) * u;
      if (y > sy - sw * .3 && y < sy + sw * .25 && Math.abs(x - sx) < sw * .55 + rr * .5) {
        var p = s.big ? 5 : 1; st.score += p; st.stars.splice(i, 1);
        st.pops.push({ x: x, y: y, t: 0, p: p });
        if (!reduce) for (var j = 0; j < (s.big ? 12 : 7); j++) { var a = Math.random() * 6.3, v = (40 + Math.random() * 90); st.parts.push({ x: x, y: y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 30, t: 0 }); }
      } else if (s.y > 1.08) st.stars.splice(i, 1);
    }
    for (i = st.parts.length - 1; i >= 0; i--) { var q = st.parts[i]; q.t += dt; q.x += q.vx * dt; q.y += q.vy * dt; q.vy += 120 * dt; if (q.t > .7) st.parts.splice(i, 1); }
    for (i = st.pops.length - 1; i >= 0; i--) { st.pops[i].t += dt; if (st.pops[i].t > .9) st.pops.splice(i, 1); }
  }
  function draw(dt) {
    var u = SPR.u || 1; g.clearRect(0, 0, W, H);
    g.fillStyle = 'rgba(201,168,111,.35)';                         // still gold dust
    for (var d = 0; d < 26; d++) { var dx = ((Math.sin(d * 12.9) * 43758.5) % 1 + 1) % 1 * W, dy = ((Math.sin(d * 78.2) * 12345.6) % 1 + 1) % 1 * H * .8; g.beginPath(); g.arc(dx, dy, 1 + (d % 3) * .5, 0, 7); g.fill(); }
    for (var i = 0; i < st.stars.length; i++) { var s = st.stars[i], sp = s.big ? SPR.b : SPR.s, w = sp.width / dpr;
      g.save(); g.translate(s.x * W, s.y * H); if (!reduce) g.rotate(s.r); g.drawImage(sp, -w / 2, -w / 2, w, w); g.restore(); }
    for (i = 0; i < st.parts.length; i++) { var q = st.parts[i]; g.globalAlpha = 1 - q.t / .7; g.fillStyle = '#C9A86F'; g.beginPath(); g.arc(q.x, q.y, 2.2 * (1 - q.t), 0, 7); g.fill(); }
    g.globalAlpha = 1;
    shoe(st.px * W, H * .86, u * .26, reduce ? 0 : (st.tx - st.px) * 1.2);
    g.textAlign = 'center';
    for (i = 0; i < st.pops.length; i++) { var o = st.pops[i]; g.globalAlpha = 1 - o.t / .9; g.fillStyle = '#857652';
      g.font = 'italic 500 ' + Math.round(u * .075) + 'px "Cormorant Garamond", Georgia, serif'; g.fillText('+' + o.p, o.x, o.y - 30 - o.t * 40); }
    g.globalAlpha = 1;
    if (st.running) {                                              // HUD: stars, time line, level
      g.textAlign = 'left'; g.fillStyle = '#857652'; g.font = '500 ' + Math.round(u * .034) + 'px system-ui, sans-serif';
      g.fillText('NIVEL ' + st.level, 18, 30);
      g.textAlign = 'center'; g.font = 'italic 500 ' + Math.round(u * .085) + 'px "Cormorant Garamond", Georgia, serif'; g.fillStyle = '#3A2E2A';
      g.fillText('✦ ' + st.score, W / 2, 42);
      g.fillStyle = 'rgba(184,150,110,.25)'; g.fillRect(18, H - 14, W - 36, 2); g.fillStyle = '#B8966E'; g.fillRect(18, H - 14, (W - 36) * (1 - st.t / ROUND), 2);
      var b = st.t - st.banner;
      if (b >= 0 && b < 1.4) { var a = reduce ? 1 : Math.min(1, b * 4, (1.4 - b) * 3), sc = reduce ? 1 : .85 + .15 * Math.min(1, b * 4);
        g.save(); g.globalAlpha = a; g.translate(W / 2, H * .42); g.scale(sc, sc); g.font = '700 ' + Math.round(u * .12) + 'px Fredoka, system-ui, sans-serif';
        g.fillStyle = '#B8966E'; g.fillText('¡Nivel ' + st.level + '!', 0, 4); g.fillStyle = '#E2A6B0'; g.fillText('¡Nivel ' + st.level + '!', 0, 0); g.restore(); }
    }
  }

  // input — pointer drag anywhere on the board, arrow keys / A-D, Esc or P pauses
  function toX(e) { var r = cv.getBoundingClientRect(); st.tx = Math.max(.08, Math.min(.92, (e.clientX - r.left) / r.width)); st.vx = 0; }
  cv.addEventListener('pointerdown', function (e) { if (!st.running) return; cv.setPointerCapture(e.pointerId); toX(e); });
  cv.addEventListener('pointermove', function (e) { if (st.running && (e.buttons || e.pointerType === 'touch')) toX(e); });
  play.addEventListener('keydown', function (e) {
    var k = e.key; if (k === 'ArrowLeft' || k === 'a' || k === 'A') { st.keys.l = 1; e.preventDefault(); }
    else if (k === 'ArrowRight' || k === 'd' || k === 'D') { st.keys.r = 1; e.preventDefault(); }
    else if ((k === 'Escape' || k === 'p' || k === 'P') && st.running) { pause(!st.paused); e.preventDefault(); }
  });
  play.addEventListener('keyup', function (e) { var k = e.key; if (k === 'ArrowLeft' || k === 'a' || k === 'A') st.keys.l = 0; if (k === 'ArrowRight' || k === 'd' || k === 'D') st.keys.r = 0; });
  root.addEventListener('click', function (e) { var b = e.target.closest('[data-a]'); if (!b) return; var a = b.getAttribute('data-a'); if (a === 'jugar') start(); else if (a === 'seguir') pause(false); });
  pauseBtn.addEventListener('click', function () { pause(true); });
  document.addEventListener('visibilitychange', function () { if (document.hidden) pause(true); });
  if (window.ResizeObserver) new ResizeObserver(resize).observe(play); else window.addEventListener('resize', resize);
  var bst = best(), bs = cards.inicio.querySelector('.f360k__best'); if (bst) { bs.hidden = false; bs.textContent = 'Tu mejor marca: ' + bst + ' estrellas'; }
  resize();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { if (!st.running) draw(0); });
  // test hook for the QA script only (no effect for visitors)
  root.f360k = { start: start, state: function () { return st; } };
})();
</script>
F360SNIP;
});
