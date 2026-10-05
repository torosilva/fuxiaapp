// Renders historia.html frame by frame. Recordings come in as image sequences:
//   node render.mjs <out> <tienda-frames-dir> <admin-frames-dir> [only-times]
import { chromium } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs';
const [OUT, TIENDA, ADMIN, ONLY] = process.argv.slice(2);
const list = (dir, absolute) => { const f = fs.readdirSync(dir).filter((x) => x.endsWith('.jpg')).sort(); const t0 = absolute ? Number(f[0].slice(0, -4)) : 1000;
  return f.map((x) => [Number(x.slice(0, -4)) - t0, 'file://' + dir + '/' + x]); };
const SEQ = { tienda: list(TIENDA, true), admin: list(ADMIN, false) };
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
await p.addInitScript((s) => { window.SEQ = s; }, SEQ);
await p.goto('file://' + new URL('./historia.html', import.meta.url).pathname, { waitUntil: 'networkidle' });
await p.evaluate(() => document.fonts.ready);
fs.mkdirSync(OUT, { recursive: true });
const dur = await p.evaluate(() => window.DUR);
const times = ONLY ? ONLY.split(',').map(Number) : Array.from({ length: Math.round(dur * 25) }, (_, i) => i / 25);
for (const t of times) { await p.evaluate((t) => window.render(t), t); await p.screenshot({ path: `${OUT}/${(1000 + t).toFixed(3)}.jpg`, type: 'jpeg', quality: 86 }); }
await b.close(); console.log('frames', times.length);
