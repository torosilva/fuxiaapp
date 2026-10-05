// Renders inversionistas.html frame by frame (deterministic timeline) → JPGs named by time, for frames-to-mp4.swift.
import { chromium } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs';
const [OUT, FPS = '25', ONLY, SPEED = '1'] = process.argv.slice(2);   // SPEED > 1 plays the timeline faster; SPEED = map.json follows a narration
// map.json: [[videoSeconds, timelineSeconds], …] — piecewise-linear, so each scene starts when the narrator starts it
const MAP = /\.json$/.test(SPEED) ? JSON.parse(fs.readFileSync(SPEED, 'utf8')) : null;
const toTimeline = (v) => { if (!MAP) return v * Number(SPEED); for (let i = 1; i < MAP.length; i++) if (v <= MAP[i][0]) { const [a, b] = [MAP[i - 1], MAP[i]]; return a[1] + (v - a[0]) * (b[1] - a[1]) / (b[0] - a[0]); } return MAP[MAP.length - 1][1]; };
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1080, height: 1920 } });
await p.goto('file://' + new URL('./inversionistas.html', import.meta.url).pathname, { waitUntil: 'networkidle' });
await p.evaluate(() => document.fonts.ready);
fs.mkdirSync(OUT, { recursive: true });
const dur = await p.evaluate(() => window.DUR);
const vDur = MAP ? MAP[MAP.length - 1][0] : dur / Number(SPEED);
const times = ONLY ? ONLY.split(',').map(Number) : Array.from({ length: Math.round(vDur * FPS) }, (_, i) => i / FPS);
for (const t of times) {
  await p.evaluate((t) => window.render(t), toTimeline(t));
  await p.screenshot({ path: `${OUT}/${(1000 + t).toFixed(3)}.jpg`, type: 'jpeg', quality: 88 });
}
await b.close(); console.log('frames', times.length);
