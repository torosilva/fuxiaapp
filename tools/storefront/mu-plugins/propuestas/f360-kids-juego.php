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
.f360k__kids{margin:0;font-family:Fredoka,system-ui,sans-serif;font-weight:700;font-size:72px;line-height:.95;letter-spacing:.03em;color:var(--rosa);
  text-shadow:0 1px 0 #fff,0 4px 0 var(--oro),0 14px 26px rgba(133,118,82,.25)}
.f360k__sub{margin:18px auto 22px;max-width:380px;font-family:"Cormorant Garamond",Georgia,serif;font-style:italic;font-size:21px;line-height:1.3;color:var(--tinta)}
.f360k__play{position:relative;width:min(100%,calc((100vh - 240px) * .75));aspect-ratio:3/4;margin:0 auto;scroll-margin:130px 0 96px;border-radius:22px;overflow:hidden;outline:none;
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
    show(null); pauseBtn.hidden = false; play.focus({ preventScroll: true }); play.scrollIntoView({ block: 'end', behavior: reduce ? 'auto' : 'smooth' }); last = 0; requestAnimationFrame(loop); say('Empieza el juego. Nivel 1.');
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
    var rate = [1.3, 1.9, 2.6][lv - 1], speed = [.24, .32, .42][lv - 1];
    st.spawn += dt * rate;
    while (st.spawn >= 1) { st.spawn -= 1; var big = Math.random() < .1;
      st.stars.push({ x: .08 + Math.random() * .84, y: -.06, v: speed * (.85 + Math.random() * .3), r: Math.random() * 6.3, w: (Math.random() - .5) * 1.4, big: big }); }
    var sx = st.px * W, sy = H * .8, sw = u * .26;
    for (var i = st.stars.length - 1; i >= 0; i--) {
      var s = st.stars[i]; s.y += s.v * dt; s.r += s.w * dt;
      var x = s.x * W, y = s.y * H, rr = (s.big ? .07 : .045) * u;
      if (y > sy - sw * .38 && y < sy + sw * .25 && Math.abs(x - sx) < sw * .6 + rr * .6) {
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
    for (var d = 0; d < 26; d++) { var dx = ((d * 97.13) % 1) * 0 + ((Math.sin(d * 12.9) * 43758.5) % 1 + 1) % 1 * W, dy = ((Math.sin(d * 78.2) * 12345.6) % 1 + 1) % 1 * H * .8; g.beginPath(); g.arc(dx, dy, 1 + (d % 3) * .5, 0, 7); g.fill(); }
    for (var i = 0; i < st.stars.length; i++) { var s = st.stars[i], sp = s.big ? SPR.b : SPR.s, w = sp.width / dpr;
      g.save(); g.translate(s.x * W, s.y * H); if (!reduce) g.rotate(s.r); g.drawImage(sp, -w / 2, -w / 2, w, w); g.restore(); }
    for (i = 0; i < st.parts.length; i++) { var q = st.parts[i]; g.globalAlpha = 1 - q.t / .7; g.fillStyle = '#C9A86F'; g.beginPath(); g.arc(q.x, q.y, 2.2 * (1 - q.t), 0, 7); g.fill(); }
    g.globalAlpha = 1;
    shoe(st.px * W, H * .8, u * .26, reduce ? 0 : (st.tx - st.px) * 1.2);
    g.textAlign = 'center';
    for (i = 0; i < st.pops.length; i++) { var o = st.pops[i]; g.globalAlpha = 1 - o.t / .9; g.fillStyle = '#857652';
      g.font = 'italic 500 ' + Math.round(u * .075) + 'px "Cormorant Garamond", Georgia, serif'; g.fillText('+' + o.p, o.x, o.y - 30 - o.t * 40); }
    g.globalAlpha = 1;
    if (st.running) {                                              // HUD: stars, time line, level
      g.textAlign = 'left'; g.fillStyle = '#857652'; g.font = '500 ' + Math.round(u * .034) + 'px system-ui, sans-serif';
      g.fillText('NIVEL ' + st.level, 18, 30);
      g.textAlign = 'center'; g.font = 'italic 500 ' + Math.round(u * .085) + 'px "Cormorant Garamond", Georgia, serif'; g.fillStyle = '#3A2E2A';
      var sc = String(st.score), tw = g.measureText(sc).width; g.fillText(sc, W / 2 + u * .03, 42); g.fillStyle = '#B8966E'; g.fillText('✦', W / 2 - tw / 2 - u * .03, 42);
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
