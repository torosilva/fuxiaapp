import { chromium } from '/Users/bullsilva/Documents/GitHub/fuxiaapp/admin-web/node_modules/playwright/index.mjs';
import fs from 'fs';
const [OUT, LOGO] = process.argv.slice(2);
const logo = fs.readFileSync(LOGO, 'utf8').replace(/width="757" height="132"/, 'width="760" height="133"');
const page = (k, t, x) => `<html><head><link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@300;500;700&display=swap" rel="stylesheet"></head>
<body style="margin:0;width:1920px;height:900px;background:#fffdf9;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:34px;font-family:Montserrat">
${logo}<div style="font-weight:700;font-size:26px;letter-spacing:.32em;text-transform:uppercase;color:#83734C">${k}</div>
<div style="font-weight:300;font-size:72px;color:#1d1d1b">${t}</div><div style="font-size:30px;color:#6B6B68">${x}</div></body></html>`;
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1920, height: 900 } });
for (const [f, k, t, x] of [['cover', 'Fuxia 360', 'Cómo funciona por dentro', 'El sistema de Fuxia: inventario, productos, ventas y clientas'], ['end', 'Fuxia 360', 'Todo en un solo lugar', 'Tiendas, bodega, tienda en línea, Hilo y clientas, conectados']]) {
  await p.setContent(page(k, t, x), { waitUntil: 'networkidle' }); await p.evaluate(() => document.fonts.ready);
  await p.screenshot({ path: `${OUT}/${f}.jpg`, type: 'jpeg', quality: 92 }); }
await b.close();
