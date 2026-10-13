// Renders bienvenida.html frame by frame (25 fps, 1080×1920) as <out>/<1000+t>.jpg, the same convention as tools/video/historia.
//   node render.mjs <out-dir> <img-dir> [only-times]      img-dir = folder with <CODE>.jpg (public store photos, downloaded locally)
import { chromium } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs';
const [OUT, IMGDIR, ONLY] = process.argv.slice(2);
const IMG = Object.fromEntries(fs.readdirSync(IMGDIR).filter((f) => f.endsWith('.jpg')).map((f) => [f.slice(0, -4), 'file://' + IMGDIR + '/' + f]));
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1080, height: 1920 } });
await p.addInitScript((x) => { window.IMG = x; }, IMG);
await p.goto('file://' + new URL('./bienvenida.html', import.meta.url).pathname, { waitUntil: 'networkidle' });
await p.evaluate(() => document.fonts.ready);
fs.mkdirSync(OUT, { recursive: true });
const dur = await p.evaluate(() => window.DUR);
const times = ONLY ? ONLY.split(',').map(Number) : Array.from({ length: Math.round(dur * 25) }, (_, i) => i / 25);
for (const t of times) { await p.evaluate((t) => window.render(t), t); await p.screenshot({ path: `${OUT}/${(1000 + t).toFixed(3)}.jpg`, type: 'jpeg', quality: 88 }); }
await b.close(); console.log('frames', times.length);
