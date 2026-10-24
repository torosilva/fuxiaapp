// Fuxia Kids · helpers shared by juego.html and coleccion.html. Everything is a pure function of t (seconds).
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const prog = (t, a, b) => clamp((t - a) / (b - a));
const ease = (x) => 1 - Math.pow(1 - x, 3);
const inout = (x) => (x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const back = (x) => { const c = 1.5; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };
const rnd = (i) => { const x = Math.sin(i * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
const fadeIO = (t, a, b, f = .5) => Math.min(prog(t, a, a + f), 1 - prog(t, b - f, b));
const LOGO = '../inversionistas/logo-fuxia.svg';
const FOTO = (n) => `fotos-muestra/${n}.jpg`;

function starPath(g, x, y, r, rot = 0) {
  g.beginPath(); for (let k = 0; k < 10; k++) { const a = rot + k * Math.PI / 5 - Math.PI / 2, rr = k % 2 ? r * .42 : r; g.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr); } g.closePath();
}
// Ivory → blush paper with drifting gold dust; `rosa` 0..1 warms the bottom.
function fondo(t, rosa = .5) {
  const c = document.getElementById('sky'), g = c.getContext('2d'); g.setTransform(2, 0, 0, 2, 0, 0);
  const grd = g.createLinearGradient(0, 0, 0, 844);
  grd.addColorStop(0, '#FBF6F1'); grd.addColorStop(.6, '#F8EBE8'); grd.addColorStop(1, `rgba(${243},${218 - 20 * rosa},${219 - 18 * rosa},1)`);
  g.fillStyle = grd; g.fillRect(0, 0, 390, 844);
  for (let i = 0; i < 46; i++) {                       // gold dust, slowly rising
    const x = (rnd(i) * 390 + Math.sin(t * .4 + i) * 10), y = 844 - ((t * (8 + rnd(i + 9) * 16) + rnd(i + 3) * 844) % 880);
    g.globalAlpha = .25 + .5 * Math.abs(Math.sin(t * (.8 + rnd(i + 5)) + i)); g.fillStyle = '#C9A86F';
    g.beginPath(); g.arc(x, y, .6 + rnd(i + 2) * 1.6, 0, 7); g.fill();
  }
  g.globalAlpha = 1;
}
function estrellasDoradas(t, a, b, n = 14) {          // thin gold stars falling (game scene)
  if (t < a || t > b) return;
  const g = document.getElementById('sky').getContext('2d');
  for (let i = 0; i < n; i++) {
    const sp = 90 + rnd(i) * 90, x = 30 + rnd(i + 40) * 330, y = ((t - a) * sp + rnd(i + 80) * 900) % 900 - 60;
    g.globalAlpha = .9; g.strokeStyle = '#B8966E'; g.lineWidth = 1.4; g.fillStyle = 'rgba(232,206,150,.55)';
    starPath(g, x, y, 9 + rnd(i + 5) * 7, t * .8 + i); g.fill(); g.stroke();
  }
  g.globalAlpha = 1;
}
function destello(t, x, y, a, n = 8) {                // small gold sparkle burst
  const p = prog(t, a, a + 1.1); if (!p || p >= 1) return '';
  let s = ''; for (let i = 0; i < n; i++) { const ang = i / n * 6.283 + .3, d = ease(p) * 56;
    s += `<div style="position:absolute;left:${x + Math.cos(ang) * d}px;top:${y + Math.sin(ang) * d}px;font-size:${14 - p * 8}px;color:#B8966E;opacity:${1 - p}">✦</div>`; }
  return s;
}
function kidsTitle(t, a, size = 92) {                 // the KIDS lettering Mario liked, with a gentle entrance and float
  const s = back(prog(t, a, a + .9)), bob = Math.sin(t * 1.6) * 3;
  return `<div class="kids" style="font-size:${size}px;transform:scale(${s}) translateY(${bob}px)">KIDS</div>`;
}
