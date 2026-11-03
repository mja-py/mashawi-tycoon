// iPhone validation of the web export in Playwright's WebKit (Safari's engine) with the iPhone 14
// profile (UA, 3x, touch): the install guide in portrait and landscape, the game booting, the save
// surviving a reload. Pass "chrome" as the 4th arg to run the same emulation in Chrome instead.
//   node tools/web_iphone_test.mjs http://localhost:8080/ /tmp/out [chrome]
import { devices } from 'playwright';
import { launchChrome, launchWebKit, watchConsole, armReady, waitReady, waitPhase, state, check, finish, outDir, tap } from './web_test_lib.mjs';
const url = process.argv[2] || 'http://localhost:8080/'; const out = outDir(process.argv[3] || '/tmp/web_iphone'); const useChrome = process.argv[4] === 'chrome';
const device = devices['iPhone 14'];
const browser = useChrome ? await launchChrome() : await launchWebKit();
const ctx = await browser.newContext({ ...device, locale: 'ar', ignoreHTTPSErrors: true }); // self-signed LAN cert
const page = await ctx.newPage();
const con = watchConsole(page);
await armReady(page);
const dev = '?dev=' + encodeURIComponent('--phase=prep');

// ---- 1. portrait: the install guide is the main content of the "rotate" screen
await page.goto(url + dev, { waitUntil: 'load' });
await page.waitForSelector('#play', { state: 'visible', timeout: 180000 });
check(await page.evaluate(() => window.godotInstallGuide === true), 'iPhone Safari outside the installed app gets the install guide');
const css = (sel) => page.evaluate(s => { const e = document.querySelector(s); return e ? getComputedStyle(e).display : 'missing'; }, sel);
check(await css('#rotate') === 'flex', 'portrait shows the rotate screen');
check(await page.evaluate(() => document.getElementById('install').closest('#rotate-slot') !== null), 'install guide sits on the rotate screen in portrait');
check(await css('#install') === 'flex', 'install guide visible in portrait');
check(await css('#arrow') === 'block', 'arrow points at Safari\'s share button in portrait');
check((await page.textContent('#where')).includes('سفاري'), 'Safari wording for the share button');
await page.screenshot({ path: `${out}/1_portrait_install.png` });

// ---- 2. landscape: guide under the Play button, dismissable, recallable
await page.setViewportSize({ width: 844, height: 390 });
await page.waitForTimeout(800);
check(await css('#rotate') === 'none', 'landscape hides the rotate screen');
check(await page.evaluate(() => document.getElementById('install').closest('#install-slot') !== null), 'install guide moves under Play in landscape');
check(await css('#install') === 'flex' && await css('#arrow') === 'none', 'guide visible, arrow hidden in landscape');
await page.screenshot({ path: `${out}/2_landscape_install.png` });
await page.tap('#later');
await page.waitForTimeout(400);
check(await css('#install') === 'none' && await css('#installmini') !== 'none', 'Later hides the guide and leaves a small link');
check(await page.evaluate(() => localStorage.getItem('installHintSeen') === '1'), 'dismissal remembered');
await page.tap('#installmini');
await page.waitForTimeout(400);
check(await css('#install') === 'flex', 'the link brings the guide back');
await page.tap('#later');

// ---- 3. boot straight into prep (dev flag) and make sure it saved
await page.tap('#play');
await waitReady(page, 180000);
const prep = await waitPhase(page, 'prep', 60000);
check(prep && prep.money === 1500 && prep.hasSave === true, `game runs on WebKit and saved on entering prep (${JSON.stringify(prep)})`);
check(await css('#install') === 'none' && await css('#installmini') === 'none', 'guide gone once the game runs');
check(await page.evaluate(() => { const s = localStorage.getItem('mashawi_save'); return !!s && JSON.parse(s).version === 3; }), 'localStorage backup copy of the save (version 3)');
await page.waitForTimeout(2500);
await page.screenshot({ path: `${out}/3_prep.png` });
await tap(page, 695, 360); // menu tab (RTL: 2nd from the right)
await page.waitForTimeout(1200);
await page.screenshot({ path: `${out}/4_menu.png` });
await tap(page, 793, 360); // supplies tab
await page.waitForTimeout(1200);
await page.screenshot({ path: `${out}/5_supplies.png` });

// ---- 4. reload without the dev flag: the title must offer Continue
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('#play', { state: 'visible', timeout: 180000 });
await page.tap('#play');
await waitReady(page, 180000);
const title = await waitPhase(page, 'title', 60000);
check(title && title.hasSave === true, `save survives a reload (${JSON.stringify(title)})`);
await page.waitForTimeout(2500);
await page.screenshot({ path: `${out}/6_title_continue.png` });
await tap(page, 422, 190); // New Game with a save present: a confirm dialog, not a wipe
await page.waitForTimeout(1200);
const after = await state(page);
check(after && after.phase === 'title' && after.hasSave === true, `New Game asks first when a save exists (${JSON.stringify(after)})`);
await page.screenshot({ path: `${out}/7_new_game_confirm.png` });
const errs = con.errors();
check(errs.length === 0, `no console errors (${errs.length})`);
errs.slice(0, 8).forEach(l => console.log('    ', l.slice(0, 220)));
await browser.close();
finish('web_iphone_test' + (useChrome ? ' (chrome)' : ' (webkit)'));
