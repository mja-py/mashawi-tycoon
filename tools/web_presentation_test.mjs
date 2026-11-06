// Exercises rendered boot, menu bounds, purchases and the closing curtain on short iPhone layouts.
import assert from 'node:assert/strict';
import { devices } from 'playwright';
import { launchWebKit, watchConsole, waitReady, waitPhase, outDir } from './web_test_lib.mjs';

const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/tmp/mashawi-presentation');
const browser = await launchWebKit();
try {
  for (const [lang, width, height] of [['en', 667, 375], ['ar', 740, 300]]) {
    const ctx = await browser.newContext({ ...devices['iPhone SE'], locale: lang, viewport: { width, height } });
    try {
      const page = await ctx.newPage();
      const logs = watchConsole(page);
      await page.addInitScript(delay => {
        window.__godotReady = false;
        let held = false;
        window.addEventListener('godot-ready', event => {
          if (delay && !held) {
            held = true;
            event.stopImmediatePropagation();
            setTimeout(() => window.dispatchEvent(new Event('godot-ready')), 7200);
          } else {
            window.__godotReady = true;
          }
        }, true);
      }, lang === 'en');
      await page.goto(url + '?dev=' + encodeURIComponent('--uitest --phase=prep --weather=sunny --money=5000 --lang=' + lang));
      await page.waitForSelector('#play', { state: 'visible', timeout: 120000 });
      await page.tap('#play');
      if (lang === 'en') {
        await page.waitForTimeout(6250);
        assert.equal(await page.locator('#status').isVisible(), true, 'loading art stays visible while the first frame is withheld');
        assert.equal(await page.locator('#canvas').evaluate(canvas => canvas.classList.contains('on')), false);
      }
      await waitReady(page);
      await page.waitForSelector('#status', { state: 'hidden' });
      await waitPhase(page, 'prep');
      async function hit(id) {
        await page.waitForFunction(id => window.godotMenuTargets?.[id] && !window.godotMenuTargets[id].disabled, id);
        const point = await page.evaluate(id => window.godotMenuTargets[id], id);
        await page.touchscreen.tap(point.x * width, point.y * height);
      }
      async function fits(id) {
        await page.waitForFunction(id => window.godotState?.panel === id, id);
        await page.waitForTimeout(340);
        const view = await page.evaluate(() => window.godotPresentation);
        assert(view.menuBottom < view.tabsTop, id + ' content stays above the navigation bar');
      }
      const shot = name => page.screenshot({ path: out + '/' + lang + '-' + name + '.png' });
      for (const id of ['build', 'promote', 'place', 'goals', 'menu']) {
        await hit('tab_' + id);
        await fits(id);
      }
      await shot('menu');
      await hit('select_chicken_tikka');
      await page.waitForFunction(() => window.godotState?.menuItem === 'chicken_tikka');
      await fits('menu');
      await shot('dish');
      await hit('tab_supplies');
      await fits('supplies');
      await hit('pack_bread_0');
      await page.waitForFunction(() => window.godotPresentation?.purchase > 0.8);
      await shot('purchase');
      await hit('stock_today');
      await page.waitForFunction(() => window.godotMenuTargets?.stock_today?.disabled);
      await hit('close_panel');
      await page.waitForTimeout(300);
      await hit('open_shop');
      await waitPhase(page, 'day');
      await page.waitForTimeout(1100);
      await hit('skip_day');
      await page.waitForFunction(() => window.godotPresentation?.closing > 0);
      await shot('closing');
      await page.waitForFunction(() => window.godotPresentation?.curtain > 0.1);
      await shot('curtain');
      const report = await waitPhase(page, 'report');
      assert.equal(report.day, 2);
      assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('mashawi_save')).history.length), 1);
      await page.waitForFunction(() => window.godotPresentation?.curtain === 0);
      await hit('next_day');
      await waitPhase(page, 'prep');
      assert.deepEqual(logs.errors(), []);
      console.log(lang, 'boot, six panel bounds, purchase stamp, closing curtain, and next day passed');
    } finally {
      await ctx.close();
    }
  }
} finally {
  await browser.close();
}
