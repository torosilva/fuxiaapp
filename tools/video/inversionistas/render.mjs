// Renders inversionistas.html frame by frame (deterministic timeline) → JPGs named by time, for frames-to-mp4.swift.
import { chromium } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs';
const [OUT, FPS = '25', ONLY] = process.argv.slice(2);
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1080, height: 1920 } });
await p.goto('file://' + new URL('./inversionistas.html', import.meta.url).pathname, { waitUntil: 'networkidle' });
await p.evaluate(() => document.fonts.ready);
fs.mkdirSync(OUT, { recursive: true });
const dur = await p.evaluate(() => window.DUR);
const times = ONLY ? ONLY.split(',').map(Number) : Array.from({ length: Math.round(dur * FPS) }, (_, i) => i / FPS);
for (const t of times) {
  await p.evaluate((t) => window.render(t), t);
  await p.screenshot({ path: `${OUT}/${(1000 + t).toFixed(3)}.jpg`, type: 'jpeg', quality: 88 });
}
await b.close(); console.log('frames', times.length);
