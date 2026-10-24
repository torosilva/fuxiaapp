// Fuxia 360 · QA: the product video really plays on a phone (headless Google Chrome, iPhone 13 viewport; Playwright's own
// Chromium has no H.264). Usage: node tools/qa/video-en-ficha.mjs <url de la ficha> [captura.png]
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../admin-web/package.json', import.meta.url));
const { chromium, devices } = require('@playwright/test');

const [url, shot] = process.argv.slice(2);
if (!url) throw new Error('uso: node tools/qa/video-en-ficha.mjs <url de la ficha> [captura.png]');
const { defaultBrowserType, ...phone } = devices['iPhone 13'];
const browser = await chromium.launch({ channel: 'chrome' });
const page = await (await browser.newContext(phone)).newPage();
await page.goto(url, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('.f360-video', { state: 'attached', timeout: 20000 });
await page.locator('.f360-video').scrollIntoViewIfNeeded();
await page.waitForTimeout(4000);
const r = await page.evaluate(() => {
  const v = document.querySelector('.f360-video video');
  return { visible: !v.closest('.f360-video').hidden, ready: v.readyState, time: v.currentTime, width: v.videoWidth, height: v.videoHeight, paused: v.paused, error: v.error && v.error.code };
});
if (shot) await page.screenshot({ path: shot });
await browser.close();
console.log(JSON.stringify(r));
const ok = r.visible && r.ready >= 2 && r.time > 0 && !r.paused && !r.error;
console.log(ok ? 'OK: el video se ve y se reproduce' : 'FALLA: el video no se reproduce');
process.exit(ok ? 0 : 1);
