// Verify real buyers, table delivery and clearing, then finish the same day with Skip.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { devices } from 'playwright';
import { launchWebKit, armReady, waitReady, waitPhase, watchConsole, outDir } from './web_test_lib.mjs';

const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/tmp/mashawi-restaurant');
const browser = await launchWebKit();
try {
  const context = await browser.newContext({
    ...devices['iPhone 14'], viewport: { width: 844, height: 390 }, locale: 'en',
    recordVideo: { dir: out, size: { width: 1266, height: 585 } },
  });
  try {
    const page = await context.newPage();
    const logs = watchConsole(page);
    await armReady(page);
    async function boot(flags) {
      await page.goto(url + '?dev=' + encodeURIComponent(flags));
      await page.waitForSelector('#play', { state: 'visible', timeout: 180000 });
      await page.tap('#play');
      await waitReady(page, 180000);
    }
    async function tap(id) {
      await page.waitForFunction(id => window.godotMenuTargets?.[id] && !window.godotMenuTargets[id].disabled, id);
      const point = await page.evaluate(id => window.godotMenuTargets[id], id);
      await page.touchscreen.tap(point.x * 844, point.y * 390);
    }
    await boot('--uitest --lang=en --phase=prep --stage=4 --money=100000 --stations=counter:7,grill:7,karak:4,seating:4,staffroom:1,lights:4');
    await waitPhase(page, 'prep');
    await page.waitForTimeout(800);
    await tap('tab_supplies');
    await tap('stock_today');
    const save = await page.evaluate(() => JSON.parse(localStorage.getItem('mashawi_save')));
    save.popularity = 0.9;
    save.saved_at = Date.now() / 1000 + 1;
    save.plots[save.location].reputation = 0.9;
    save.forecast = save.weather = 'sunny';
    for (const ingredient of Object.keys(save.inventory)) save.inventory[ingredient] = 120;
    for (const [id, item] of Object.entries(save.menu)) item.enabled = ['chicken_tikka', 'soda'].includes(id);
    save.menu.chicken_tikka.level = 3;
    await page.evaluate(save => localStorage.setItem('mashawi_save', JSON.stringify(save)), save);
    await boot('--uitest --lang=en --sim-seed=27');
    await waitPhase(page, 'title');
    await tap('continue_game');
    await waitPhase(page, 'prep');
    await page.waitForTimeout(650);
    await tap('open_shop');
    await waitPhase(page, 'day');
    await page.evaluate(() => {
      window.serviceSamples = [];
      window.serviceTimer = setInterval(() => {
        if (window.godotPresentation?.service) {
          window.serviceSamples.push(JSON.parse(JSON.stringify(window.godotPresentation.service)));
        }
      }, 100);
    });
    await page.waitForFunction(() => window.godotPresentation?.service?.deliveries > 0, null, { timeout: 85000 });
    await page.screenshot({ path: out + '/1-delivered.png' });
    await page.waitForFunction(() => window.godotPresentation?.service?.workers.some(worker => worker.state === 4), null, { timeout: 45000 });
    await page.screenshot({ path: out + '/2-cleaning.png' });
    await page.waitForFunction(() => {
      const service = window.godotPresentation?.service;
      return service?.cleaned > 0 && service.served > service.dineIn;
    }, null, { timeout: 45000 });
    const beforeSkip = await page.evaluate(() => window.godotPresentation.service.served);
    await tap('skip_day');
    await page.waitForFunction(count => window.godotState?.finishing && window.godotPresentation?.service?.served > count, beforeSkip);
    await page.screenshot({ path: out + '/3-skip-purchase.png' });
    await waitPhase(page, 'report', 120000);
    await page.waitForTimeout(600);
    const result = await page.evaluate(() => {
      clearInterval(window.serviceTimer);
      return { service: window.godotPresentation.service, samples: window.serviceSamples,
        save: JSON.parse(localStorage.getItem('mashawi_save')) };
    });
    const { service } = result;
    assert(service.deliveries > 0 && service.cleaned > 0);
    assert.equal(service.served, service.purchases.length, 'every sale has a visible purchase');
    assert.equal(new Set(service.purchases.map(purchase => purchase.customer)).size, service.served, 'each buyer pays once');
    assert(service.purchases.every(purchase => purchase.visible && purchase.ordered), 'all buyers visibly order and collect');
    assert(service.purchases.some(purchase => purchase.dineIn) && service.purchases.some(purchase => !purchase.dineIn));
    assert.equal(service.pending, 0);
    assert.deepEqual(service.dirty, []);
    assert(service.workers.every(worker => worker.state === 0));
    assert.equal(result.save.history.length, 1);
    assert.equal(result.save.history[0].served, service.served);
    assert.deepEqual(logs.errors(), []);
    fs.writeFileSync(out + '/service-proof.json', JSON.stringify(result, null, 2));
    await page.screenshot({ path: out + '/4-report.png' });
    console.log(JSON.stringify({ served: service.served, dineIn: service.dineIn,
      deliveries: service.deliveries, tablesCleaned: service.cleaned, allPurchasesVisible: true }));
    console.log('web_restaurant_test (iPhone WebKit): PASS');
  } catch (error) {
    const page = context.pages()[0];
    if (page) {
      await page.screenshot({ path: out + '/failure.png' });
      console.log('Failed service state', JSON.stringify(await page.evaluate(() => ({
        state: window.godotState, service: window.godotPresentation?.service,
      }))));
    }
    throw error;
  } finally {
    await context.close();
  }
} finally {
  await browser.close();
}
