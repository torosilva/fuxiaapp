// Renders the caption PNGs (transparent) and the closing-card frames (24 fps) at 1080x1920. Usage: node capas.mjs <out> [cierre|cierreClaro]
import { chromium } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs'; import path from 'path';
const OUT = process.argv[2], FN = process.argv[3] || 'cierre'; fs.mkdirSync(OUT + '/cierre', { recursive: true });
const b = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const p = await (await b.newContext({ viewport: { width: 405, height: 720 }, deviceScaleFactor: 1080 / 405 })).newPage();
await p.goto('file://' + path.resolve(path.dirname(new URL(import.meta.url).pathname), 'capas.html')); await p.evaluate(() => document.fonts.ready);
const caps = [['cap1', 'Capítulo I', 'Una tarde, con mamá…'], ['cap2', 'Capítulo II', 'Entre todas, una brilla para ella'], ['cap3', 'Capítulo III', '…y por primera vez, se vio bailarina']];
for (const [f, l, t] of caps) { await p.evaluate(([l, t]) => window.caption(l, t), [l, t]); await p.screenshot({ path: `${OUT}/${f}.png`, omitBackground: true }); }
for (let i = 0; i < 24 * 5.5; i++) { await p.evaluate(([t, fn]) => window[fn](t), [i / 24, FN]); await p.waitForFunction(() => [...document.images].every((x) => x.complete));
  await p.screenshot({ path: `${OUT}/cierre/${(100 + i / 24).toFixed(3)}.jpg`, type: 'jpeg', quality: 92 }); }
await b.close(); console.log('ok', OUT);
