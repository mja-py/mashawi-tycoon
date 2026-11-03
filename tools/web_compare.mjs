// Phone-size screenshots of a web build driven only by taps (no dev flags), so two builds can be
// compared side by side: title, New Game -> prep, then each bottom tab (RTL order), then Close.
//   node tools/web_compare.mjs <url> <outdir> [webkit]
import { devices } from 'playwright';
import { launchChrome, launchWebKit, watchConsole, armReady, waitReady, outDir, tap } from './web_test_lib.mjs';
const url = process.argv[2]; const out = outDir(process.argv[3]); const useWebKit = process.argv[4] === 'webkit';
const browser = useWebKit ? await launchWebKit() : await launchChrome();
const ctx = await browser.newContext({ ...devices['iPhone 14'], viewport: { width: 844, height: 390 }, locale: 'ar', ignoreHTTPSErrors: true });
const page = await ctx.newPage();
const con = watchConsole(page);
await armReady(page);
const t0 = Date.now();
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('#play', { state: 'visible', timeout: 180000 });
console.log('files loaded after', Date.now() - t0, 'ms');
await page.screenshot({ path: `${out}/0_loading.png` });
const t1 = Date.now();
await page.tap('#play');
await waitReady(page, 180000);
console.log('godot-ready after', Date.now() - t1, 'ms');
for (let i = 1; i <= 8; i++) { await page.waitForTimeout(150); await page.screenshot({ path: `${out}/boot_${i}.png` }); }
await page.waitForTimeout(2000);
await page.screenshot({ path: `${out}/1_title.png` });
await tap(page, 422, 220); // New Game
await page.waitForTimeout(2500);
await page.screenshot({ path: `${out}/2_prep.png` });
await tap(page, 141, 349); await tap(page, 259, 279); // the welcome dialog's Let's go button (old / new layout)
await page.waitForTimeout(800);
await page.screenshot({ path: `${out}/2b_prep.png` });
const tabs = [793, 695, 597, 499, 401];
for (let i = 0; i < tabs.length; i++) {
  await tap(page, tabs[i], 360);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${out}/3_tab${i}_x${tabs[i]}.png` });
  await tap(page, 44, 72); // Close
}
await page.waitForTimeout(800);
await page.screenshot({ path: `${out}/4_after_close.png` });
console.log('state', JSON.stringify(await page.evaluate(() => window.godotState || null)));
const errs = con.errors();
console.log('errors', errs.length); errs.slice(0, 5).forEach(l => console.log('   ', l.slice(0, 200)));
await browser.close();
