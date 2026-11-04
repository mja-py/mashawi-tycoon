// Real canvas taps using dev-only button geometry: independent of language and phone size.
import { devices } from 'playwright';
import { launchWebKit, watchConsole, armReady, waitReady, waitPhase, state, check, finish, outDir, tap } from './web_test_lib.mjs';
const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/tmp/web_menu');
const browser = await launchWebKit();
try {
  for (const [lang, profile, viewport, nested] of [
    ['ar', 'iPhone 14', { width: 844, height: 390 }, false],
    ['en', 'iPhone SE', { width: 667, height: 375 }, true],
  ]) {
    const ctx = await browser.newContext({ ...devices[profile], viewport, locale: lang, ignoreHTTPSErrors: true, serviceWorkers: nested ? 'block' : 'allow' });
    let entry = url;
    if (nested) {
      // Serve the same static files under a project prefix, as GitHub Pages does.
      // Blocking SW in this context lets routing mount files without changing the server.
      entry = new URL('mashawi-check/', url).href;
      await ctx.route(entry + '**', async route => {
        const relative = route.request().url().slice(entry.length);
        const response = await route.fetch({ url: new URL(relative || './', url).href });
        await route.fulfill({ response });
      });
    }
    const page = await ctx.newPage();
    const con = watchConsole(page);
    await armReady(page);
    await page.goto(entry + '?dev=' + encodeURIComponent(`--phase=prep --panel=menu --weather=sunny --lang=${lang} --uitest`), { waitUntil: 'load' });
    await page.waitForSelector('#play', { state: 'visible', timeout: 180000 });
    await page.screenshot({ path: `${out}/${lang}_1_loading.png` });
    await page.tap('#play');
    await waitReady(page, 180000);
    await waitPhase(page, 'prep');
    await page.waitForTimeout(1200);
    const saved = () => page.evaluate(() => JSON.parse(localStorage.getItem('mashawi_save')));
    async function target(id) {
      await page.waitForFunction(k => !!window.godotMenuTargets?.[k], id, { timeout: 10000 });
      return page.evaluate(k => window.godotMenuTargets[k], id);
    }
    async function hit(id) {
      const t = await target(id);
      await tap(page, t.x * viewport.width, t.y * viewport.height);
    }
    async function scrollTo(id) {
      for (let i = 0; i < 6; i++) {
        if (await page.evaluate(k => !!window.godotMenuTargets?.[k], id)) return;
        const x = viewport.width / 2, y = viewport.height * .74;
        await page.mouse.move(x, y);
        await page.mouse.down();
        for (let step = 1; step <= 10; step++) {
          await page.mouse.move(x, y - step * 7);
          await page.waitForTimeout(20);
        }
        await page.waitForTimeout(180); // Stop the list before lifting the pointer.
        await page.mouse.up();
        await page.waitForTimeout(400);
      }
      await target(id);
    }
    check((await state(page)).menuItem === '', `${lang}: menu opens as dish selection`);
    await page.screenshot({ path: `${out}/${lang}_2_dishes.png` });
    await hit('select_chicken_tikka');
    check((await state(page)).menuItem === 'chicken_tikka', `${lang}: selecting chicken opens its sheet`);
    await target('price_up'); // Must be visible immediately, without scrolling.
    await page.screenshot({ path: `${out}/${lang}_3_dish_detail.png` });
    const before = await saved();
    await hit('price_up');
    const after = await saved();
    check(after.menu.chicken_tikka.price === before.menu.chicken_tikka.price + 1, `${lang}: price control edits the selected dish`);
    check(after.menu.soda.price === before.menu.soda.price, `${lang}: other dishes keep their price`);
    await hit('on_sale');
    check((await saved()).menu.chicken_tikka.enabled === false, `${lang}: removing a dish from today's menu is saved`);
    await hit('on_sale');
    await scrollTo('recipe_meat_up');
    await hit('recipe_meat_up');
    check((await saved()).menu.chicken_tikka.recipe.meat === 3, `${lang}: recipe control edits the selected dish`);
    check((await target('recipe_meat_up')).disabled === true, `${lang}: recipe maximum disables further increments`);
    await page.screenshot({ path: `${out}/${lang}_4_recipe.png` });
    await hit('back_dishes');
    await hit('select_mutton_tikka');
    check((await saved()).money === before.money, `${lang}: viewing a new dish does not purchase it`);
    await hit('unlock');
    const unlocked = await saved();
    check(unlocked.menu.mutton_tikka.unlocked && unlocked.money === before.money - 450, `${lang}: explicit unlock purchases the chosen dish`);
    await hit('back_dishes');
    await hit('category_drink');
    await hit('select_soda');
    check((await state(page)).menuItem === 'soda', `${lang}: category selection shows the correct dishes`);
    await page.screenshot({ path: `${out}/${lang}_5_drink.png` });
    if (nested) check(new URL(page.url()).pathname.includes('/mashawi-check/'), 'game boots and edits work beneath a GitHub Pages-style project path');
    const errors = con.errors();
    check(errors.length === 0, `${lang}: no browser or game errors (${errors.length})`);
    errors.slice(0, 6).forEach(e => console.log(e));
    await ctx.close();
  }
} finally {
  await browser.close();
}
finish('web_menu_test (webkit)');
