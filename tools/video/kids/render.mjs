// Fuxia Kids · lanzamiento (maqueta): renders lanzamiento.html frame by frame (30 fps) into <out>/shots/<t>.jpg.
// Then: swiftc -O tools/video/frames-to-mp4.swift -o /tmp/enc && /tmp/enc <out>/shots <salida>.mp4
// Usage: node tools/video/kids/render.mjs <out> [--stills]   (--stills: only 6 preview frames)
import { chromium } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs';
import path from 'path';
const OUT = process.argv[2];
const stills = process.argv.includes('--stills');
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })).newPage();
await p.goto('file://' + path.resolve(path.dirname(new URL(import.meta.url).pathname), 'lanzamiento.html'));
await p.evaluate(() => document.fonts.ready);
const dir = OUT + '/shots';
fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
const dur = await p.evaluate(() => window.DURATION);
const times = stills ? [1.5, 5, 9.5, 15.4, 19.8, 23] : Array.from({ length: Math.round(dur * 30) }, (_, i) => i / 30);
for (const t of times) {
  await p.evaluate((t) => window.render(t), t);
  fs.writeFileSync(`${dir}/${(100 + t).toFixed(3)}.jpg`, await p.screenshot({ type: 'jpeg', quality: 90 }));
}
await b.close();
console.log('frames', times.length, '→', dir);
