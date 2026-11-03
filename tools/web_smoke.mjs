// Smoke-tests the web export in the installed Google Chrome (desktop size), exit 1 on failure:
//   node tools/web_smoke.mjs http://localhost:8080/ /tmp/out
import { launchChrome, watchConsole, armReady, waitReady, waitPhase, check, finish, outDir, tap } from './web_test_lib.mjs';
const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/tmp/web_smoke');
const browser = await launchChrome();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 }, locale: 'ar' });
const page = await ctx.newPage();
const con = watchConsole(page);
await armReady(page);
const t0 = Date.now();
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('#play', { state: 'visible', timeout: 120000 });
console.log('download+init ready in', ((Date.now() - t0) / 1000).toFixed(1), 's');
check(await page.evaluate(() => window.godotInstallGuide === false), 'no install guide on desktop Chrome');
check(await page.evaluate(() => document.getElementById('install') === null), 'install card not rendered on desktop');
await page.screenshot({ path: `${out}/1_loading.png` });
await page.click('#play');
await waitReady(page);
console.log('godot-ready after', ((Date.now() - t0) / 1000).toFixed(1), 's');
const title = await waitPhase(page, 'title');
check(title && title.hasSave === false, 'fresh profile has no save');
await page.waitForTimeout(2500);
await page.screenshot({ path: `${out}/2_title.png` });
// New Game button sits mid-screen; click by canvas coordinates (title layout centred)
await tap(page, 640, 390, false);
const prep = await waitPhase(page, 'prep');
check(prep && prep.day === 1 && prep.money === 1500, `new game starts day 1 with AED 1500 (${JSON.stringify(prep)})`);
check(prep && prep.hasSave === true, 'new game is saved straight away');
await page.waitForTimeout(1500);
await page.screenshot({ path: `${out}/3_prep.png` });
// portrait check
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(800);
check(await page.evaluate(() => getComputedStyle(document.getElementById('rotate')).display) === 'flex', 'rotate overlay shows in portrait');
await page.screenshot({ path: `${out}/4_portrait.png` });
await page.setViewportSize({ width: 844, height: 390 });
await page.waitForTimeout(800);
check(await page.evaluate(() => getComputedStyle(document.getElementById('rotate')).display) === 'none', 'rotate overlay hidden in landscape');
await page.screenshot({ path: `${out}/5_phone_landscape.png` });
const errors = con.errors();
check(errors.length === 0, `no console errors (${errors.length})`);
errors.slice(0, 10).forEach(l => console.log('    ', l.slice(0, 200)));
await browser.close();
finish('web_smoke');
