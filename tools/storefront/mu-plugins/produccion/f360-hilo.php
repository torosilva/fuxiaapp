<?php
/**
 * Plugin Name: Fuxia 360 · Hilo (producción)
 * Description: Botón "Hilo" en todo el sitio (asesora HiloLabs + WhatsApp + casos a la Bandeja de Fuxia 360). Reemplaza a Joinchat.
 *              GENERADO por scripts/f360/build_prod_storefront_mu.mjs desde tools/storefront/f360-hilo-global.html — no editar a mano.
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only
// Hilo replaces Joinchat (one button bottom-right).
add_filter('joinchat_show', '__return_false', 99);
// SiteGround "AI Studio" floating button (shown to admins only, no API key): hidden so it doesn't overlap Hilo.
add_action('wp_head', function () { echo "<style>#wp-ai-studio-container{display:none!important}</style>\n"; }, 99);
add_action('wp_footer', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST)) return;
  echo <<<'F360SNIP'
<!--
  Fuxia 360 · Hilo en TODO el sitio (Mario 2026-10-04). Reemplaza a Joinchat: un solo botón abajo a la derecha que abre
  "Pregúntale a Hilo" (agente HiloLabs, el mismo de la app) o "WhatsApp con el equipo" (número del país, mensaje con el
  zapato que está viendo). Si Hilo pide una persona, la clienta deja nombre y WhatsApp y el caso queda en Fuxia 360
  (Bandeja de clientas) + correo a info@. "A la medida" en páginas de producto.
  Instalar: WPCode → nuevo fragmento HTML → "Todo el sitio · pie de página". En producción: desactivar Joinchat.
  PRODUCCIÓN: generado por scripts/f360/build_prod_storefront_mu.mjs.
-->
<div id="fh-root">
  <button type="button" class="fh-btn" aria-label="Pregúntale a Hilo, tu asesora Fuxia" aria-expanded="false">
    <svg viewBox="26 25 31 34" aria-hidden="true"><path fill="currentColor" d="M 35.417969 28.21875 C 34.332031 29.796875 32.085938 33.59375 32.6875 37.207031 C 32.960938 38.851562 33.808594 40.289062 35.207031 41.484375 C 35.460938 41.027344 35.875 40.519531 36.410156 39.875 C 37.683594 38.332031 39.429688 36.226562 39.300781 33.703125 C 39.144531 30.660156 36.433594 28.808594 35.417969 28.21875 M 47.410156 28.21875 C 46.394531 28.808594 43.683594 30.664062 43.527344 33.703125 C 43.398438 36.226562 45.144531 38.335938 46.421875 39.875 C 46.953125 40.519531 47.367188 41.027344 47.621094 41.484375 C 49.019531 40.289062 49.867188 38.851562 50.140625 37.207031 C 50.742188 33.59375 48.496094 29.796875 47.410156 28.21875 M 42.050781 47.210938 C 42.925781 48.4375 43.453125 49.710938 43.621094 51 C 43.863281 52.871094 43.320312 54.421875 42.722656 55.492188 C 50.101562 52.097656 53.972656 46.738281 53.925781 39.964844 L 53.925781 39.800781 C 53.925781 36.191406 51.910156 32.90625 49.941406 30.558594 C 50.808594 32.449219 51.539062 34.910156 51.132812 37.371094 C 50.738281 39.738281 49.347656 41.703125 46.992188 43.203125 C 44.851562 44.480469 43.191406 45.828125 42.050781 47.210938 M 32.886719 30.558594 C 30.917969 32.90625 28.902344 36.191406 28.902344 39.800781 L 28.902344 39.964844 C 28.855469 46.738281 32.726562 52.097656 40.105469 55.492188 C 39.511719 54.421875 38.964844 52.871094 39.207031 51 C 39.375 49.710938 39.90625 48.4375 40.78125 47.210938 C 39.636719 45.824219 37.976562 44.480469 35.839844 43.207031 C 33.484375 41.703125 32.089844 39.738281 31.695312 37.371094 C 31.289062 34.910156 32.019531 32.449219 32.886719 30.558594 M 41.414062 48.0625 C 40.746094 49.066406 40.339844 50.09375 40.207031 51.121094 C 39.9375 53.171875 40.792969 54.800781 41.414062 55.675781 C 42.035156 54.800781 42.890625 53.175781 42.621094 51.121094 C 42.488281 50.09375 42.082031 49.066406 41.414062 48.0625 M 41.386719 57.167969 L 41.378906 57.171875 L 41.296875 57.097656 L 41.148438 57.046875 C 32.550781 53.585938 27.84375 47.519531 27.898438 39.960938 L 27.898438 39.800781 C 27.898438 32.71875 34.699219 27.183594 34.992188 26.953125 L 35.070312 26.886719 L 35.488281 27.109375 C 35.546875 27.140625 35.667969 27.199219 35.828125 27.292969 C 37.136719 28.03125 40.121094 30.085938 40.304688 33.652344 C 40.453125 36.566406 38.5625 38.847656 37.183594 40.515625 C 36.726562 41.066406 36.214844 41.683594 36.019531 42.109375 L 36.03125 42.117188 C 36.140625 42.195312 36.25 42.277344 36.367188 42.351562 C 38.507812 43.625 40.207031 44.988281 41.414062 46.398438 C 42.621094 44.988281 44.320312 43.625 46.464844 42.347656 C 46.578125 42.277344 46.683594 42.199219 46.792969 42.125 L 46.808594 42.109375 C 46.632812 41.71875 46.191406 41.175781 45.648438 40.515625 C 44.265625 38.847656 42.375 36.566406 42.523438 33.652344 C 42.707031 30.085938 45.691406 28.027344 46.964844 27.308594 C 47.164062 27.199219 47.28125 27.140625 47.34375 27.109375 L 47.757812 26.886719 L 47.839844 26.953125 C 48.128906 27.183594 54.929688 32.726562 54.929688 39.800781 L 54.929688 39.960938 C 54.984375 47.519531 50.277344 53.585938 41.679688 57.046875 L 41.488281 57.125 L 41.414062 57.203125 Z M 41.386719 57.167969"/></svg>
    <span class="fh-btn-t">Hilo</span>
  </button>
  <div class="fh-teaser" hidden><button type="button" class="fh-teaser-x" aria-label="Cerrar">×</button><span></span></div>
  <div class="fh-panel" hidden role="dialog" aria-label="Hilo, tu asesora Fuxia">
    <div class="fh-top">
      <div class="fh-top-id"><span class="fh-ava"><svg viewBox="26 25 31 34" aria-hidden="true"><path fill="currentColor" d="M 35.417969 28.21875 C 34.332031 29.796875 32.085938 33.59375 32.6875 37.207031 C 32.960938 38.851562 33.808594 40.289062 35.207031 41.484375 C 35.460938 41.027344 35.875 40.519531 36.410156 39.875 C 37.683594 38.332031 39.429688 36.226562 39.300781 33.703125 C 39.144531 30.660156 36.433594 28.808594 35.417969 28.21875 M 47.410156 28.21875 C 46.394531 28.808594 43.683594 30.664062 43.527344 33.703125 C 43.398438 36.226562 45.144531 38.335938 46.421875 39.875 C 46.953125 40.519531 47.367188 41.027344 47.621094 41.484375 C 49.019531 40.289062 49.867188 38.851562 50.140625 37.207031 C 50.742188 33.59375 48.496094 29.796875 47.410156 28.21875 M 42.050781 47.210938 C 42.925781 48.4375 43.453125 49.710938 43.621094 51 C 43.863281 52.871094 43.320312 54.421875 42.722656 55.492188 C 50.101562 52.097656 53.972656 46.738281 53.925781 39.964844 L 53.925781 39.800781 C 53.925781 36.191406 51.910156 32.90625 49.941406 30.558594 C 50.808594 32.449219 51.539062 34.910156 51.132812 37.371094 C 50.738281 39.738281 49.347656 41.703125 46.992188 43.203125 C 44.851562 44.480469 43.191406 45.828125 42.050781 47.210938 M 32.886719 30.558594 C 30.917969 32.90625 28.902344 36.191406 28.902344 39.800781 L 28.902344 39.964844 C 28.855469 46.738281 32.726562 52.097656 40.105469 55.492188 C 39.511719 54.421875 38.964844 52.871094 39.207031 51 C 39.375 49.710938 39.90625 48.4375 40.78125 47.210938 C 39.636719 45.824219 37.976562 44.480469 35.839844 43.207031 C 33.484375 41.703125 32.089844 39.738281 31.695312 37.371094 C 31.289062 34.910156 32.019531 32.449219 32.886719 30.558594 M 41.414062 48.0625 C 40.746094 49.066406 40.339844 50.09375 40.207031 51.121094 C 39.9375 53.171875 40.792969 54.800781 41.414062 55.675781 C 42.035156 54.800781 42.890625 53.175781 42.621094 51.121094 C 42.488281 50.09375 42.082031 49.066406 41.414062 48.0625 M 41.386719 57.167969 L 41.378906 57.171875 L 41.296875 57.097656 L 41.148438 57.046875 C 32.550781 53.585938 27.84375 47.519531 27.898438 39.960938 L 27.898438 39.800781 C 27.898438 32.71875 34.699219 27.183594 34.992188 26.953125 L 35.070312 26.886719 L 35.488281 27.109375 C 35.546875 27.140625 35.667969 27.199219 35.828125 27.292969 C 37.136719 28.03125 40.121094 30.085938 40.304688 33.652344 C 40.453125 36.566406 38.5625 38.847656 37.183594 40.515625 C 36.726562 41.066406 36.214844 41.683594 36.019531 42.109375 L 36.03125 42.117188 C 36.140625 42.195312 36.25 42.277344 36.367188 42.351562 C 38.507812 43.625 40.207031 44.988281 41.414062 46.398438 C 42.621094 44.988281 44.320312 43.625 46.464844 42.347656 C 46.578125 42.277344 46.683594 42.199219 46.792969 42.125 L 46.808594 42.109375 C 46.632812 41.71875 46.191406 41.175781 45.648438 40.515625 C 44.265625 38.847656 42.375 36.566406 42.523438 33.652344 C 42.707031 30.085938 45.691406 28.027344 46.964844 27.308594 C 47.164062 27.199219 47.28125 27.140625 47.34375 27.109375 L 47.757812 26.886719 L 47.839844 26.953125 C 48.128906 27.183594 54.929688 32.726562 54.929688 39.800781 L 54.929688 39.960938 C 54.984375 47.519531 50.277344 53.585938 41.679688 57.046875 L 41.488281 57.125 L 41.414062 57.203125 Z M 41.386719 57.167969"/></svg></span>
        <span><b>Hilo</b><small>tu asesora Fuxia · responde al instante</small></span></div>
      <div class="fh-top-act">
        <button type="button" class="fh-wa" aria-label="WhatsApp con el equipo" title="WhatsApp con el equipo"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18a8 8 0 0 1-4.1-1.1l-.3-.2-3.1.8.8-3-.2-.3A8 8 0 1 1 12 20zm4.4-6c-.2-.1-1.4-.7-1.7-.8-.2-.1-.4-.1-.5.1l-.8.9c-.1.2-.3.2-.5.1a6.6 6.6 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.5-.4h-.5a1 1 0 0 0-.7.3 2.9 2.9 0 0 0-.9 2.2 5 5 0 0 0 1.1 2.7 11.5 11.5 0 0 0 4.4 3.9c1.6.7 2.3.8 3.1.6.5-.1 1.4-.6 1.6-1.2.2-.6.2-1 .1-1.2l-.6-.3z"/></svg></button>
        <button type="button" class="fh-x" aria-label="Cerrar">×</button>
      </div>
    </div>
    <div class="fh-log" aria-live="polite"></div>
    <div class="fh-chips"></div>
    <form class="fh-in"><input type="text" autocomplete="off" aria-label="Tu mensaje" placeholder="Escribe tu pregunta"><input type="text" name="website" tabindex="-1" autocomplete="off" class="fh-hp" aria-hidden="true"><button type="submit" aria-label="Enviar">➤</button></form>
  </div>
</div>
<style>
#fh-root { --fh-gold: #B8966E; --fh-ink: #242424; font-family: inherit; }
#fh-root [hidden] { display: none !important; }
.joinchat, .joinchat__button, #joinchat { display: none !important; }   /* Hilo reemplaza a Joinchat */
.fh-btn { position: fixed; right: 18px; bottom: calc(18px + var(--fh-lift, 0px)); z-index: 99990; display: flex; align-items: center; gap: 8px; height: 58px; padding: 0 18px 0 14px;
  border: 0; border-radius: 29px; background: var(--fh-gold); color: #fff; cursor: pointer; box-shadow: 0 8px 24px rgba(0,0,0,.22); transition: transform .2s ease, bottom .25s ease; }
.fh-btn:hover { transform: translateY(-2px); }
.fh-btn svg { width: 30px; height: 30px; }
.fh-btn-t { font-size: 15px; font-weight: 600; letter-spacing: .04em; }
.fh-teaser { position: fixed; right: 18px; bottom: calc(88px + var(--fh-lift, 0px)); z-index: 99990; max-width: 240px; padding: 12px 32px 12px 14px; background: #fff; color: var(--fh-ink);
  border-radius: 14px; box-shadow: 0 8px 24px rgba(0,0,0,.16); font-size: 14px; line-height: 1.35; cursor: pointer; animation: fh-in .3s ease; }
.fh-teaser-x { position: absolute; top: 4px; right: 6px; border: 0; background: none; font-size: 18px; color: #9A9A96; cursor: pointer; }
.fh-panel { position: fixed; right: 18px; bottom: calc(88px + var(--fh-lift, 0px)); z-index: 99991; width: min(370px, calc(100vw - 24px)); height: min(560px, calc(100vh - 120px));
  display: flex; flex-direction: column; background: #fffdf9; border-radius: 18px; box-shadow: 0 16px 48px rgba(0,0,0,.24); overflow: hidden; animation: fh-in .25s ease; }
@keyframes fh-in { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
.fh-top { display: flex; justify-content: space-between; align-items: center; padding: 14px 16px; background: var(--fh-gold); color: #fff; }
.fh-top-id { display: flex; align-items: center; gap: 10px; }
.fh-top-id b { display: block; font-size: 16px; } .fh-top-id small { font-size: 12px; opacity: .9; }
.fh-ava { width: 36px; height: 36px; border-radius: 50%; background: rgba(255,255,255,.18); display: grid; place-items: center; }
.fh-ava svg { width: 22px; height: 22px; }
.fh-x { border: 0; background: none; color: #fff; font-size: 26px; line-height: 1; cursor: pointer; }
.fh-log { flex: 1; overflow-y: auto; padding: 14px; display: flex; flex-direction: column; gap: 8px; }
.fh-log p { margin: 0; padding: 9px 12px; border-radius: 14px; font-size: 14px; line-height: 1.4; max-width: 86%; white-space: pre-line; }
.fh-log .h { background: #f3ece1; color: #3b342c; align-self: flex-start; border-bottom-left-radius: 4px; }
.fh-log .c { background: var(--fh-gold); color: #fff; align-self: flex-end; border-bottom-right-radius: 4px; }
.fh-log .t { color: #9A9A96; font-style: italic; background: none; padding: 2px 4px; }
.fh-log a { color: #8c6414; text-decoration: underline; word-break: break-word; }
.fh-chips { display: flex; flex-wrap: wrap; gap: 6px; padding: 0 14px 10px; }
.fh-chips button { padding: 8px 12px; border: 1px solid var(--fh-gold); border-radius: 18px; background: #fff; color: #8c6414; font-size: 13px; cursor: pointer; font-family: inherit; }
.fh-chips .fh-big { flex: 1 1 100%; padding: 13px 14px; font-size: 15px; text-align: left; border-radius: 12px; }
.fh-chips .fh-big.wa { border-color: #25D366; color: #128C4A; }
.fh-top-act { display: flex; align-items: center; gap: 4px; }
.fh-wa { width: 34px; height: 34px; border: 0; border-radius: 50%; background: #fff; color: #25D366; cursor: pointer; display: grid; place-items: center; }
.fh-wa svg { width: 20px; height: 20px; }
.fh-chips { flex-wrap: nowrap !important; overflow-x: auto; scrollbar-width: none; padding: 2px 14px 8px !important; }
.fh-chips::-webkit-scrollbar { display: none; }
.fh-chips button { flex: 0 0 auto; padding: 7px 11px !important; font-size: 12.5px !important; white-space: nowrap; }
.fh-log > * { flex-shrink: 0; }
.fh-cards { flex: 0 0 auto; display: flex; gap: 8px; overflow-x: auto; padding: 2px 0 4px; align-self: stretch; scrollbar-width: none; }
.fh-cards::-webkit-scrollbar { display: none; }
.fh-card, .fh-card * { text-decoration: none !important; }
.fh-card { flex: 0 0 132px; border: 1px solid #ece4d6; border-radius: 12px; background: #fff; overflow: hidden; text-decoration: none; color: #242424; display: flex; flex-direction: column; }
.fh-card img { width: 100%; height: 120px; object-fit: cover; background: #f5f2ec; display: block; }
.fh-card img.fh-sinfoto { background: #f5f2ec url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M12 21c-4-3-6-7-6-11 2 1 4 3 6 6 2-3 4-5 6-6 0 4-2 8-6 11z' fill='none' stroke='%23B8966E' stroke-width='1.2'/%3E%3C/svg%3E") center / 40px no-repeat; }
.fh-card b { font-size: 12.5px; font-weight: 600; padding: 7px 8px 0; line-height: 1.25; }
.fh-card span { font-size: 12px; color: #6B6B68; padding: 2px 8px 0; }
.fh-card i { font-style: normal; margin: 6px 8px 8px; padding: 6px 0; border-radius: 8px; background: #B8966E; color: #fff; text-align: center; font-size: 12px; font-weight: 600; }
.fh-in { display: flex; gap: 8px; padding: 10px 12px 12px; border-top: 1px solid #eee5d8; }
.fh-in input { flex: 1; height: 42px; padding: 0 12px; border: 1px solid #d9d2c5; border-radius: 21px; font-size: 16px; font-family: inherit; }
.fh-in button { width: 42px; height: 42px; border: 0; border-radius: 50%; background: var(--fh-ink); color: #fff; cursor: pointer; }
.fh-hp { position: absolute !important; left: -9999px !important; width: 1px !important; height: 1px !important; opacity: 0 !important; }
@media (max-width: 640px) {
  .fh-btn { right: 12px; height: 54px; padding: 0 16px 0 12px; }
  .fh-panel { right: 8px; left: 8px; width: auto; bottom: calc(80px + var(--fh-lift, 0px)); height: min(70vh, calc(100vh - 110px)); }
  .fh-teaser { right: 12px; }
}
</style>
<script>
/* Fuxia 360 · Hilo global. PRODUCCIÓN. Fuente: tools/storefront/f360-hilo-global.html */
(function () {
  if (window.FuxiaHilo) return;
  var HILO_URL = 'https://web-production-8cc5a.up.railway.app/api/v1/chat/web';
  var F360 = 'https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-store-reserve';   // PRODUCCIÓN
  var WA = { mx: '525567914188', co: '573166912433' };
  var root = document.getElementById('fh-root'); if (!root) return;
  document.body.appendChild(root);
  var q = function (s) { return root.querySelector(s); };
  var btn = q('.fh-btn'), panel = q('.fh-panel'), log = q('.fh-log'), chips = q('.fh-chips'), form = q('.fh-in'), input = q('.fh-in input'), teaser = q('.fh-teaser');
  var path = location.pathname, pais = (path.match(/^\/([a-z]{2})\//) || [0, 'mx'])[1];
  var mexico = pais === 'mx' || !/^\/[a-z]{2}\//.test(path);
  var checkout = /finalizar-compra|checkout/.test(path), producto = !!document.querySelector('form.variations_form');
  var store = function (k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } };
  var sess = function (k, v) { try { if (v === undefined) return sessionStorage.getItem(k); sessionStorage.setItem(k, v); } catch (e) { return null; } };
  var uid = store('f360_hilo_uid'); if (!uid) { uid = 'web-' + Math.random().toString(36).slice(2) + Date.now().toString(36); store('f360_hilo_uid', uid); }
  var convId = null, ocupado = false, iniciado = false, modo = 'chat', paso = 0, d = {}, proposito = 'contacto';
  function api(body) {
    return fetch(F360, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.error || 'No se pudo.'); return j; }); });
  }
  function contexto() {
    var h1 = document.querySelector('h1'), c = document.querySelector('.f360-color.selected'), t = document.querySelector('.fuxia-talla.selected');
    return { producto: producto && h1 ? h1.textContent.trim() : null, color: c ? c.dataset.nombre : null, talla_mx: t && mexico ? t.textContent.trim() : null,
             talla_tienda: t ? t.dataset.co : null, pais: pais, pagina: producto ? 'producto' : (/tienda|categoria-producto/.test(path) ? 'tienda' : (/carrito|cart/.test(path) ? 'carrito' : (checkout ? 'pago' : 'otra'))),
             url: location.href.split('?')[0] };
  }
  // history of this visit (kept across pages in sessionStorage; Hilo also remembers on its side by user id)
  var hist = []; try { hist = JSON.parse(sess('fh_hist') || '[]') || []; } catch (e) { hist = []; }
  convId = sess('fh_conv') || null;
  function guardar() { try { sess('fh_hist', JSON.stringify(hist.slice(-40))); if (convId) sess('fh_conv', convId); } catch (e) {} }
  var URLP = /https?:\/\/(?:www\.)?fuxiaballerinas\.com\/(?:[a-z]{2}\/)?producto\/([a-z0-9-]+)\/?/gi;
  function slugsDe(t) { var out = [], m; URLP.lastIndex = 0; while ((m = URLP.exec(t))) if (out.indexOf(m[1]) < 0) out.push(m[1]); return out; }
  function pintar(t, quien, slugs) {
    var p = document.createElement('p'); p.className = quien || 'h';
    var limpio = slugs && slugs.length ? String(t).replace(URLP, '').replace(/\n{3,}/g, '\n\n').trim() : String(t);
    limpio.split(/(https?:\/\/[^\s)]+)/).forEach(function (parte, i) {
      if (i % 2) { var a = document.createElement('a'); a.href = parte; a.target = '_blank'; a.rel = 'noopener'; a.textContent = parte.replace(/^https?:\/\/(www\.)?/, '').replace(/\/$/, ''); p.appendChild(a); }
      else parte.split(/\*\*?([^*]+)\*\*?/).forEach(function (s2, k) { if (k % 2) { var b = document.createElement('b'); b.textContent = s2; p.appendChild(b); } else p.appendChild(document.createTextNode(s2)); });
    });
    log.appendChild(p);
    if (slugs && slugs.length) tarjetas(slugs);
    log.scrollTop = log.scrollHeight; return p;
  }
  function decir(t, quien, slugs) { hist.push({ q: quien || 'h', t: String(t), s: slugs || null }); guardar(); return pintar(t, quien, slugs); }
  // product cards from the store's own catalogue (photo, name, price, link on THIS site and country)
  var cache = {};
  function tarjetas(slugs) {
    var row = document.createElement('div'); row.className = 'fh-cards'; log.appendChild(row);
    var base = location.origin + '/' + (/^\/[a-z]{2}\//.test(path) ? pais + '/' : '');
    slugs.slice(0, 6).forEach(function (sl) {
      (cache[sl] || (cache[sl] = fetch(base + 'wp-json/wc/store/v1/products?slug=' + encodeURIComponent(sl)).then(function (r) { return r.json(); }).then(function (a) { return a && a[0]; }).catch(function () { return null; })))
        .then(function (pr) {
          var a = document.createElement('a'); a.className = 'fh-card';
          if (pr) {
            a.href = pr.permalink; var img = document.createElement('img'); img.alt = pr.name; var im0 = (pr.images && pr.images[0]) || {};
            // no lazy-loading (inside a sideways row some phones never load it); thumbnail → full image → leaf placeholder
            img.onerror = function () { if (im0.src && img.src !== im0.src) img.src = im0.src; else { img.onerror = null; img.removeAttribute('src'); img.className = 'fh-sinfoto'; } };
            if (im0.thumbnail || im0.src) img.src = im0.thumbnail || im0.src; else img.className = 'fh-sinfoto'; a.appendChild(img);
            var b = document.createElement('b'); b.textContent = pr.name.replace(/&amp;/g, '&'); a.appendChild(b);
            var pz = pr.prices || {}, dec = pz.currency_minor_unit || 0, sp = document.createElement('span');
            sp.textContent = (pz.currency_prefix || '$') + Number(pz.price / Math.pow(10, dec)).toLocaleString('es-MX') + (pz.currency_suffix || ''); a.appendChild(sp);
          } else { a.href = base + 'producto/' + sl + '/'; var b2 = document.createElement('b'); b2.textContent = sl.replace(/-/g, ' '); a.appendChild(b2); }
          var go = document.createElement('i'); go.textContent = 'Ver'; a.appendChild(go); row.appendChild(a); log.scrollTop = log.scrollHeight;
        });
    });
  }
  // Recommendations come from the real catalogue (Fuxia 360: sales in every channel, category, new), not from the
  // model: instant, always real products of this site. Hilo keeps the free conversation.
  var catalogo = null;
  function cat() { return catalogo || (catalogo = api({ action: 'catalog' }).then(function (j) { return j.items || []; }).catch(function () { catalogo = null; return []; })); }
  var nrm = function (x) { return String(x || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, ''); };
  function mostrarModelos(texto, items, siguientes) {
    var vistos = {}, ids = [];
    items.forEach(function (it) { if (it.woo_product_id && !vistos[it.woo_product_id] && ids.length < 6) { vistos[it.woo_product_id] = 1; ids.push(it.woo_product_id); } });
    if (!ids.length) return false;
    var base = location.origin + '/' + (/^\/[a-z]{2}\//.test(path) ? pais + '/' : '');
    return fetch(base + 'wp-json/wc/store/v1/products?per_page=' + ids.length + '&include=' + ids.join(','))
      .then(function (r) { return r.json(); })
      .then(function (prods) {
        var por = {}; (prods || []).forEach(function (pr) { por[pr.id] = pr; });
        var slugs = ids.map(function (id) { return por[id]; }).filter(Boolean).map(function (pr) { cache[pr.slug] = Promise.resolve(pr); return pr.slug; });
        if (!slugs.length) return false;
        decir(texto, 'h', slugs); opciones(siguientes || sugerencias()); return true;
      }).catch(function () { return false; });
  }
  // one card per model: the legacy one-product-per-colour models ("Paula leopardo", "Paula vino"…) would fill the row
  var GENERICO = /^(sandalias?|tacon|tac[oó]n|botas?|ballerinas?|mule|wedge|slingback|plataforma|peep|loafer|suecos?|flats?|mafalda)$/;
  function variados(xs) {
    var vistos = {};
    return xs.filter(function (it) { var w = nrm(it.name).split(/\s+/); var k = GENERICO.test(w[0]) ? w.slice(0, 2).join(' ') : w[0]; if (vistos[k]) return false; vistos[k] = 1; return true; });
  }
  var CATS = [{ t: 'Ballerinas', c: 'ballerinas' }, { t: 'Sandalias planas', c: 'sandalia-plana' }, { t: 'Sandalias altas', c: 'sandalia-alta' }, { t: 'Botas', c: 'botas' }, { t: 'Lo nuevo', c: '*nuevo' }];
  function recomendar() {
    decir('¿Qué estás buscando? 💛'); opciones(CATS.map(function (k) { return { t: k.t, f: function () { decir(k.t, 'c'); porCategoria(k); } }; }));
  }
  function porCategoria(k) {
    opciones([]); var esc = pintar('Buscando…', 't');
    cat().then(function (items) {
      var xs = variados(items.filter(function (it) { return k.c === '*nuevo' ? it.is_new : it.category === k.c; }).sort(function (a, b) { return (b.sold || 0) - (a.sold || 0); }));
      return mostrarModelos(k.c === '*nuevo' ? 'Lo nuevo de Fuxia ✨ Toca uno para ver colores y tallas:' : 'Estas ' + k.t.toLowerCase() + ' son de las favoritas de nuestras clientas. Toca una para ver colores y tallas:', xs,
        ['¿Qué talla pido?', 'Ver otra categoría', 'Lo más vendido', '¿Cuándo me llega?']);
    }).then(function (ok) { esc.remove(); if (!ok) preguntarHilo('Recomiéndame ' + k.t.toLowerCase()); });
  }
  function masVendido() {
    opciones([]); var esc = pintar('Buscando…', 't');
    cat().then(function (items) {
      return mostrarModelos('Lo más vendido en Fuxia ahora mismo 🔥 (tiendas y en línea):', variados(items.slice().sort(function (a, b) { return (b.sold || 0) - (a.sold || 0); })),
        ['¿Qué talla pido?', 'Recomiéndame un modelo', '¿Cuándo me llega?']);
    }).then(function (ok) { esc.remove(); if (!ok) preguntarHilo('¿Qué es lo más vendido?'); });
  }
  // a model name typed alone ("paula", "mafalda", "botas largas") shows those models instead of being taken as her name
  function buscarModelo(t) {
    var q = nrm(t).replace(/[^a-z0-9ñ ]/g, ' ').trim();
    if (!q || /\?/.test(t) || q.split(/\s+/).length > 4) return Promise.resolve(false);
    var pal = q.split(/\s+/).filter(function (w) { return w.length >= 3; });
    if (!pal.length) return Promise.resolve(false);
    return cat().then(function (items) {
      var xs = items.filter(function (it) { var n = nrm(it.name); return pal.every(function (w) { return n.indexOf(w) >= 0; }); })
        .sort(function (a, b) { return (b.sold || 0) - (a.sold || 0); });
      if (!xs.length) return false;
      return mostrarModelos(xs.length === 1 ? '¡Este es! Toca para ver colores y tallas:' : 'Estos son los modelos «' + t.charAt(0).toUpperCase() + t.slice(1) + '». Toca uno para ver colores y tallas:', xs,
        ['¿Qué talla pido?', '¿Cuándo me llega?', 'Recomiéndame un modelo']);
    });
  }
  function opciones(xs) {
    chips.innerHTML = '';
    (xs || []).forEach(function (x) { var b = document.createElement('button'); b.type = 'button'; b.textContent = x.t || x; b.onclick = function () { x.f ? x.f() : responder(x.t || x); }; chips.appendChild(b); });
    chips.scrollLeft = 0;
  }
  function abrirWhatsApp() {
    var c = contexto(), num = WA[pais] || WA.mx;
    var txt = 'Hola, ' + (c.producto ? 'estoy viendo ' + c.producto + (c.color ? ' color ' + c.color : '') + (c.talla_mx ? ' talla ' + c.talla_mx + ' MX' : (c.talla_tienda ? ' talla ' + c.talla_tienda : '')) + '. ' : 'tengo una pregunta. ') + c.url;
    window.open('https://wa.me/' + num + '?text=' + encodeURIComponent(txt), '_blank', 'noopener');
  }
  function sugerencias() {
    return producto ? ['¿Qué talla me queda?', '¿Lo tienen en otro color?', '¿Con qué combina?', '¿Cuándo me llega?', 'Lo quiero a la medida']
                    : ['Recomiéndame un modelo', 'Lo más vendido', '¿Qué talla pido?', '¿Cuándo me llega?', '¿Cómo funcionan los cambios?'];
  }
  function inicio() {
    iniciado = true;
    if (hist.length) { hist.forEach(function (h) { pintar(h.t, h.q, h.s); }); }
    else decir(producto ? '¿Te ayudo con tus ' + contexto().producto + '? Pregúntame de tallas, colores o entrega. 💛' : '¿Buscas algo en especial? Te recomiendo modelos, te ayudo con tu talla y te digo cuándo te llegan. 💛');
    opciones(sugerencias());
  }
  function preguntarHilo(texto) {
    if (ocupado) return; ocupado = true;
    var c = contexto(), msg = texto;
    if (!convId) msg = '[' + (c.producto ? 'Estoy viendo ' + c.producto + (c.color ? ' · color ' + c.color : '') + (c.talla_mx ? ' · talla ' + c.talla_mx + ' MX' : '') : 'Página: ' + c.pagina) + ' · tienda ' + pais.toUpperCase() + '] ' + texto;
    var esc = pintar('Hilo está escribiendo…', 't'); opciones([]);
    var ctl = window.AbortController ? new AbortController() : null, tm = setTimeout(function () { if (ctl) ctl.abort(); }, 60000);
    fetch(HILO_URL, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-App-Platform': 'web' }, signal: ctl ? ctl.signal : undefined,
      body: JSON.stringify({ user_id: uid, message: msg.slice(0, 3900), metadata: { source: 'web_pdp', page: c } }) })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (j) {
        esc.remove(); var txt = j.response || '…'; if (j.conversation_id) convId = j.conversation_id;
        decir(txt, 'h', slugsDe(txt));
        if (j.escalate) { decir('Para que una persona del equipo te escriba, déjame tu nombre y WhatsApp.'); proposito = convId ? 'contacto' : 'medida'; formulario(3); }
        else opciones(sugerencias().filter(function (o) { return o !== texto; }));
      })
      .catch(function () { esc.remove(); decir('Ahorita no puedo responder. Escríbenos por WhatsApp y te atendemos.'); opciones([{ t: 'WhatsApp con el equipo', f: abrirWhatsApp }]); })
      .then(function () { clearTimeout(tm); ocupado = false; });
  }
  var PASOS = [
    function () { decir('¡Va! Te lo hacemos a la medida. ¿Qué color te gustaría?'); opciones([]); input.placeholder = 'Ej. verde olivo'; },
    function () { decir('¿Qué talla usas' + (mexico ? ' (talla mexicana)' : '') + '? Si no la sabes, mide tu pie en centímetros.'); opciones((mexico ? ['22', '23', '24', '25', '26', '27'] : ['35', '36', '37', '38', '39', '40']).concat(['Mido mi pie'])); input.placeholder = mexico ? 'Ej. 24' : 'Ej. 37'; },
    function () { decir('¿Cuántos centímetros mide tu pie, del talón a la punta del dedo más largo?'); opciones([]); input.placeholder = 'Ej. 24.5'; },
    function () { decir('¿Cómo te llamas?'); opciones([]); input.placeholder = 'Tu nombre'; },
    function () { decir('¿A qué WhatsApp te escribimos?'); opciones([]); input.placeholder = '55 1234 5678'; input.type = 'tel'; },
    function () { decir('¿Algo más que quieras contarnos? (tacón, ocasión, fecha…)'); opciones(['No, así está bien']); input.placeholder = 'Opcional'; input.type = 'text'; }
  ];
  function siguiente(n) { paso = n; PASOS[n](); input.value = ''; input.focus(); }
  function formulario(desde) { modo = 'form'; var c = contexto(); if (desde >= 3) { d.color = d.color || c.color || 'por definir'; if (c.talla_mx || c.talla_tienda) d.size = c.talla_mx || c.talla_tienda; } siguiente(desde); }
  function volverAlChat(t) { decir(t); modo = 'chat'; proposito = 'contacto'; input.type = 'text'; input.placeholder = 'Escribe tu pregunta'; opciones(sugerencias()); }
  function enviar() {
    opciones([]); decir('Un momento…'); var c = contexto(), hp = q('.fh-hp').value;
    if (proposito === 'contacto') {
      api({ action: 'contacto', conversation_id: convId, name: d.name, phone: d.phone, product_name: c.producto || '', color: c.color || '',
            size: c.talla_mx ? c.talla_mx + ' MX' : (c.talla_tienda || ''), country: pais, page_url: c.url, website: hp })
        .then(function () { volverAlChat('¡Gracias, ' + d.name + '! Alguien del equipo te escribe por WhatsApp muy pronto. 💛'); })
        .catch(function (e) { decir(e.message); siguiente(4); });
      return;
    }
    var form0 = document.querySelector('form.variations_form');
    var tt = d.size && mexico ? String(Number(d.size) + 13) : d.size;
    api({ action: 'a_la_medida', phone: d.phone, name: d.name, color: d.color, size: d.size ? d.size + (mexico ? ' MX' : '') : '', store_size: tt && /^(3[5-9]|40)$/.test(tt) ? tt : '',
          foot_cm: d.foot || '', note: d.note || '', woo_product_id: form0 ? form0.getAttribute('data-product_id') : '', product_name: c.producto || '', country: pais, website: hp })
      .then(function () { volverAlChat('¡Listo, ' + d.name + '! El equipo te escribe por WhatsApp con precio y tiempo. 💛'); })
      .catch(function (e) { decir(e.message); siguiente(4); });
  }
  function responder(t) {
    t = String(t || '').trim();
    if (modo === 'chat') {
      if (!t) return; decir(t, 'c'); input.value = '';
      if (/a la medida/i.test(t)) { proposito = 'medida'; formulario(0); return; }
      if (/^recomi[eé]ndame un modelo$|^ver otra categor[ií]a$/i.test(t)) { recomendar(); return; }
      if (/^lo m[aá]s vendido$/i.test(t)) { masVendido(); return; }
      if (ocupado) return;
      ocupado = true;
      buscarModelo(t).then(function (ok) { ocupado = false; if (!ok) preguntarHilo(t); }, function () { ocupado = false; preguntarHilo(t); });
      return;
    }
    if (!t && paso !== 5) return; decir(t || '—', 'c');
    if (paso === 0) { d.color = t; siguiente(1); }
    else if (paso === 1) { if (/mid/i.test(t)) siguiente(2); else { d.size = t.replace(/[^0-9.]/g, ''); siguiente(3); } }
    else if (paso === 2) { d.foot = t.replace(',', '.').replace(/[^0-9.]/g, ''); siguiente(3); }
    else if (paso === 3) { d.name = t; siguiente(4); }
    else if (paso === 4) { if (t.replace(/\D/g, '').length < 10) { decir('¿Me lo pasas a 10 dígitos?'); return; } d.phone = t; if (proposito === 'contacto') enviar(); else siguiente(5); }
    else if (paso === 5) { d.note = /^no, así está bien$/i.test(t) ? '' : t; enviar(); }
  }
  function abrir(opts) {
    teaser.hidden = true; panel.hidden = false; btn.setAttribute('aria-expanded', 'true'); sess('fh_teaser', '1');
    if (!iniciado) inicio();
    if (opts && opts.chat) input.focus();
  }
  function cerrar() { panel.hidden = true; btn.setAttribute('aria-expanded', 'false'); }
  btn.addEventListener('click', function () { panel.hidden ? abrir() : cerrar(); });
  q('.fh-x').addEventListener('click', cerrar);
  q('.fh-wa').addEventListener('click', abrirWhatsApp);
  form.addEventListener('submit', function (e) { e.preventDefault(); responder(input.value); });
  teaser.addEventListener('click', function (e) { if (e.target.classList.contains('fh-teaser-x')) { teaser.hidden = true; sess('fh_teaser', '1'); return; } abrir({ chat: true }); });
  // one small hint per visit (product pages and home), never on checkout, never opens by itself
  if (!checkout && !sess('fh_teaser') && (producto || path === '/' || path === '/mx/' || path === '/co/')) {
    setTimeout(function () { if (panel.hidden && !sess('fh_teaser')) { teaser.querySelector('span').textContent = producto ? '¿Dudas con tu talla? Pregúntame 💛' : '¿Buscas tu par perfecto? Pregúntame 💛'; teaser.hidden = false; } }, 25000);
  }
  // stay above other things fixed at the bottom on the right half (cart reminder, cookie bars…); hide while a site popup is open
  function acomodar() {
    var lift = 0, W = window.innerWidth, H = window.innerHeight, br = btn.getBoundingClientRect();
    document.querySelectorAll('body > *, body > * > *').forEach(function (e) {   // fixed bars/toasts live near the top of the tree
      if (root.contains(e) || e.offsetParent === null && getComputedStyle(e).position !== 'fixed') return;
      var cs = getComputedStyle(e); if (cs.position !== 'fixed' || cs.display === 'none' || cs.visibility === 'hidden') return;
      var r = e.getBoundingClientRect(); if (r.height < 20 || r.height > H * 0.5 || r.bottom < H - 140 || r.right < W - 120 || r.width > W * 0.98 && r.height > 200) return;
      if (r.left < br.right && r.right > br.left - 20) lift = Math.max(lift, H - r.top + 4 - 18);
    });
    root.style.setProperty('--fh-lift', Math.max(0, lift) + 'px');
    var pop = document.querySelector('#fx-pop-overlay.fx-visible'); btn.style.visibility = pop ? 'hidden' : '';
  }
  setInterval(acomodar, 1500); acomodar();
  window.FuxiaHilo = { open: function (o) { abrir(o || { chat: true }); } };
})();
</script>
F360SNIP;
  echo "\n";
}, 99);
