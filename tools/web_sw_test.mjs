// Checks the PWA service worker: loads the web export twice in one Chrome profile; the 2nd visit must be
// controlled by the worker with the engine files in its cache.   node tools/web_sw_test.mjs http://localhost:8080/
import { launchChrome, watchConsole, armReady, waitReady, check, finish } from './web_test_lib.mjs';
const url = process.argv[2] || 'http://localhost:8080/';
const browser = await launchChrome();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
for (let i = 1; i <= 2; i++) {
  const page = await ctx.newPage();
  const con = watchConsole(page);
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('#play', { state: 'visible', timeout: 120000 });
  const ready = ((Date.now() - t0) / 1000).toFixed(2);
  if (i === 1) { await page.waitForTimeout(4000); } // let the SW finish installing/caching wasm+pck
  const sw = await page.evaluate(async () => {
    const reg = await navigator.serviceWorker.getRegistration();
    const keys = await caches.keys();
    let cached = [];
    for (const k of keys) { const c = await caches.open(k); cached = cached.concat((await c.keys()).map(r => r.url.split('/').pop())); }
    return { active: !!(reg && reg.active), controller: !!navigator.serviceWorker.controller, keys, cached, dpr: window.devicePixelRatio, insets: window.godotSafeInsets() };
  });
  console.log(`visit ${i}: ready in ${ready}s`, JSON.stringify(sw).slice(0, 300));
  check(sw.active, `visit ${i}: service worker active`);
  if (i === 2) {
    // the 40 MB wasm may still be caching during visit 1; by the 2nd visit everything must be there
    check(sw.cached.some(f => f.endsWith('.wasm')) && sw.cached.some(f => f.endsWith('.pck')), 'visit 2: wasm and pck cached');
    check(sw.cached.includes('loading-art.webp'), 'visit 2: loading artwork cached');
    check(sw.controller, 'visit 2: page controlled by the service worker');
    await armReady(page);
    await ctx.setOffline(true);
    await page.reload({ waitUntil: 'load' });
    await page.waitForSelector('#play', { state: 'visible', timeout: 30000 });
    check(await page.locator('#loading-art').evaluate(img => img.complete && img.naturalWidth > 0), 'offline reload: loading artwork displays and Play becomes ready');
    await page.click('#play');
    await waitReady(page, 60000);
    check(await page.evaluate(() => !!window.godotState), 'offline reload: game starts after tapping Play');
    await ctx.setOffline(false);
  }
  check(sw.insets === '0,0,0,0', 'safe insets read as zero on desktop');
  const errs = con.errors();
  check(errs.length === 0, `visit ${i}: no console errors`);
  errs.slice(0, 3).forEach(l => console.log('    ', l.slice(0, 200)));
  await page.close();
}
await browser.close();
finish('web_sw_test');
