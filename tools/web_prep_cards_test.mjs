// Play the preparation loop using real canvas taps in both layout directions.
import assert from 'node:assert/strict';
import { devices } from 'playwright';
import { launchWebKit, watchConsole, armReady, waitReady, waitPhase, outDir } from './web_test_lib.mjs';

const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/tmp/mashawi-prep-cards');
const browser = await launchWebKit();
try {
  for (const [lang, device, width, height] of [['en', 'iPhone SE', 667, 375], ['ar', 'iPhone 14', 844, 390]]) {
    const ctx = await browser.newContext({ ...devices[device], locale: lang, viewport: { width, height } });
    try {
      const page = await ctx.newPage();
      const logs = watchConsole(page);
      await armReady(page);
      await page.goto(url + '?dev=' + encodeURIComponent('--uitest --phase=prep --weather=sunny --money=100000 --lang=' + lang));
      await page.waitForSelector('#play', { state: 'visible', timeout: 120000 });
      await page.tap('#play');
      await waitReady(page);
      await waitPhase(page, 'prep');
      const saved = () => page.evaluate(() => JSON.parse(localStorage.getItem('mashawi_save')));
      const peek = id => page.evaluate(id => window.godotMenuTargets?.[id], id);
      const next = lang === 'ar' ? 'roll_left' : 'roll_right';
      async function hit(id) {
        await page.waitForFunction(id => !!window.godotMenuTargets?.[id], id, { timeout: 10000 });
        const b = await peek(id);
        assert(!b.disabled, id + ' should be enabled');
        await page.touchscreen.tap(b.x * width, b.y * height);
        await page.waitForTimeout(430);
      }
      async function rollTo(id) {
        for (let i = 0; i < 15; i++) {
          if (await peek(id)) return;
          await hit(next);
        }
        throw Error('could not reach ' + id);
      }
      const snapshot = name => page.screenshot({ path: out + '/' + lang + '-' + name + '.png' });

      await hit('tab_supplies');
      await snapshot('ingredients');
      const initial = await saved();
      for (const i of [0, 1, 2]) await hit('pack_bread_' + i);
      const bought = await saved();
      assert.equal(bought.inventory.bread - initial.inventory.bread, 420);
      assert.equal(initial.money - bought.money, 162);
      await hit('stock_outlook');
      await hit('back_cards');
      await hit(next);
      assert(await peek('pack_chicken_0'));
      await hit('stock_today');
      assert((await saved()).inventory.chicken > 0);
      assert((await peek('stock_today')).disabled);
      console.log(lang, 'all three pack buttons, stock outlook, and daily stock passed');

      await hit('tab_promote');
      await snapshot('promote');
      const campaigns = { fliers: [150, 1], posters: [450, 3], social: [750, 7], radio: [1300, 5] };
      for (const [id, [cost, days]] of Object.entries(campaigns)) {
        await rollTo('inspect_' + id);
        const before = await saved();
        await hit('inspect_' + id);
        assert.equal((await saved()).money, before.money);
        await hit('start_promo');
        const after = await saved();
        assert.equal(after.marketing[id], days);
        assert.equal(before.money - after.money, cost);
        assert((await peek('start_promo')).disabled);
        await hit('back_cards');
      }
      console.log(lang, 'all four promotions spend once and show active state');

      await hit('tab_build');
      await snapshot('build');
      await hit('inspect_stage');
      await hit('buy_stage');
      assert.equal((await saved()).rig.stage, 'stall');
      await hit('buy_stage');
      assert.equal((await saved()).rig.stage, 'truck');
      await hit('back_cards');
      await hit('build_group_kitchen');
      for (const id of ['doner', 'fryer', 'sweets']) {
        await rollTo('inspect_' + id);
        await hit('inspect_' + id);
        await hit('buy_station');
        assert.equal((await saved()).rig.stations[id], 1);
        await hit('back_cards');
      }
      await hit('tab_menu');
      await hit('category_side');
      await rollTo('select_fries');
      await hit('select_fries');
      await hit('unlock');
      assert((await saved()).menu.fries.unlocked);
      await hit('back_dishes');
      await hit('category_sweet');
      await hit('select_saffron_cake');
      await hit('unlock');
      assert((await saved()).menu.saffron_cake.unlocked);
      console.log(lang, 'stall, truck, doner, fryer and sweets install and reveal dishes');
      await hit('tab_place');
      await rollTo('move_creek');
      await hit('move_creek');
      assert.equal((await saved()).location, 'creek');
      assert((await peek('move_creek')).disabled);
      assert.deepEqual(logs.errors(), []);
      console.log(lang, 'relocation succeeds and the browser reports no errors');
    } finally {
      await ctx.close();
    }
  }
} finally {
  await browser.close();
}
