// Smoke-tests the web export in the installed Google Chrome:
//   node tools/web_smoke.mjs http://localhost:8080/ /tmp/out
import { chromium } from 'playwright';
import fs from 'node:fs';
const url = process.argv[2] || 'http://localhost:8080/';
const out = process.argv[3] || '/tmp/web_smoke';
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 }, locale: 'ar' });
const page = await ctx.newPage();
const logs = [];
page.on('console', m => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', e => logs.push(`[pageerror] ${e.message}`));
await page.addInitScript(() => { window.__godotReady = false; window.addEventListener('godot-ready', () => { window.__godotReady = true; }); });
const t0 = Date.now();
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('#play', { state: 'visible', timeout: 120000 });
console.log('download+init ready in', ((Date.now() - t0) / 1000).toFixed(1), 's');
await page.screenshot({ path: `${out}/1_loading.png` });
await page.click('#play');
await page.waitForFunction(() => window.__godotReady === true, null, { timeout: 120000 });
console.log('godot-ready after', ((Date.now() - t0) / 1000).toFixed(1), 's');
await page.waitForTimeout(4000);
await page.screenshot({ path: `${out}/2_title.png` });
// New Game button sits mid-screen; click by canvas coordinates (title layout centred)
await page.mouse.move(640, 390);
await page.mouse.down(); await page.waitForTimeout(120); await page.mouse.up();
await page.waitForTimeout(2500);
await page.screenshot({ path: `${out}/3_prep.png` });
// Supplies tab (bottom-right in RTL)
await page.mouse.move(1180, 665);
await page.mouse.down(); await page.waitForTimeout(120); await page.mouse.up();
await page.waitForTimeout(2500);
await page.screenshot({ path: `${out}/3b_supplies.png` });
// portrait check
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(1000);
const rot = await page.evaluate(() => getComputedStyle(document.getElementById('rotate')).display);
console.log('rotate overlay in portrait:', rot);
await page.screenshot({ path: `${out}/4_portrait.png` });
await page.setViewportSize({ width: 844, height: 390 });
await page.waitForTimeout(1000);
console.log('rotate overlay in landscape:', await page.evaluate(() => getComputedStyle(document.getElementById('rotate')).display));
await page.screenshot({ path: `${out}/5_phone_landscape.png` });
const errors = logs.filter(l => /error|exception/i.test(l) && !/favicon/i.test(l));
console.log('console lines:', logs.length, 'errors:', errors.length);
errors.slice(0, 10).forEach(l => console.log('  ', l.slice(0, 200)));
await browser.close();
