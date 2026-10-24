// Fuxia Kids videos (maqueta): renders <page>.html frame by frame (30 fps) into <out>/shots/<100+t>.jpg.
// Then: swiftc -O tools/video/frames-to-mp4.swift -o <bin> && <bin> <out>/shots <video>.mp4, and add the music with con-musica.swift.
// Usage: node tools/video/kids/render.mjs <juego.html|coleccion.html> <out> [--stills]   (--stills: the page's preview frames)
import { chromium } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs';
import path from 'path';
const [page, OUT] = process.argv.slice(2);
const stills = process.argv.includes('--stills');
const b = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })).newPage();
await p.goto('file://' + path.resolve(path.dirname(new URL(import.meta.url).pathname), page));
await p.evaluate(async () => { await document.fonts.ready; });
const dir = OUT + '/shots';
fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
const { dur, still } = await p.evaluate(() => ({ dur: window.DURATION, still: window.STILLS }));
const times = stills ? still : Array.from({ length: Math.round(dur * 30) }, (_, i) => i / 30);
for (const t of times) {
  await p.evaluate((t) => window.render(t), t);
  await p.evaluate(() => Promise.all([...document.images].map((i) => i.complete || new Promise((r) => { i.onload = i.onerror = r; }))));
  fs.writeFileSync(`${dir}/${(100 + t).toFixed(3)}.jpg`, await p.screenshot({ type: 'jpeg', quality: 90 }));
}
await b.close();
console.log('frames', times.length, '→', dir);
