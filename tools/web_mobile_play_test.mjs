// One-thumb daily loop and interruption recovery in Safari's engine.
// node tools/web_mobile_play_test.mjs http://localhost:8080/ /tmp/mobile_play
import { devices } from 'playwright';
import { launchWebKit, watchConsole, armReady, waitReady, waitPhase, state, check, finish, outDir, tap } from './web_test_lib.mjs';

const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/tmp/mobile_play');
const browser = await launchWebKit();
try {
  const ctx = await browser.newContext({ ...devices['iPhone 14'], viewport: { width: 844, height: 390 }, locale: 'ar', ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  const con = watchConsole(page);
  await armReady(page);
  await page.goto(url + '?dev=' + encodeURIComponent('--phase=prep --weather=sunny --uitest'), { waitUntil: 'load' });
  await page.waitForSelector('#play', { state: 'visible', timeout: 180000 });
  await page.tap('#play');
  await waitReady(page, 180000);
  await waitPhase(page, 'prep');
  await page.waitForTimeout(1200);
  await tap(page, 793, 360);
  check((await state(page)).panel === 'supplies', 'supplies opens with a thumb tap');
  await tap(page, 170, 80); // Stock today in the RTL panel header
  const stocked = await state(page);
  check(stocked.money < 1500 && stocked.money > 0, 'daily supply shortcut purchases supplies');
  const save = await page.evaluate(() => JSON.parse(localStorage.getItem('mashawi_save')));
  check(save.inventory.chicken > 0 && save.inventory.bread > 0 && save.inventory.charcoal > 0, 'one tap stocks a playable menu and saves it');
  await tap(page, 170, 80);
  check((await state(page)).money === stocked.money, 'second tap cannot buy surplus');
  await page.screenshot({ path: `${out}/1_stocked.png` });
  await tap(page, 44, 80); // Close
  await tap(page, 85, 360); // Open stand
  await waitPhase(page, 'day');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${out}/2_day.png` });

  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(() => window.godotState?.paused === true);
  check((await state(page)).paused === true, 'rotating to portrait pauses the day behind the guard');
  await page.setViewportSize({ width: 844, height: 390 });
  await page.waitForFunction(() => window.godotState?.paused === false);
  check((await state(page)).phase === 'day', 'landscape resumes the same day');

  // Exercise the same visibility event Safari sends on app switching.
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, value: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await page.waitForFunction(() => window.godotState?.paused === true);
  check((await state(page)).paused === true, 'app switching pauses gameplay');
  await page.evaluate(() => {
    delete document.hidden;
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await page.waitForFunction(() => window.godotState?.paused === false);

  await tap(page, 610, 360); // Skip to closing (RTL day controls)
  await page.waitForFunction(() => window.godotState?.finishing === true);
  await tap(page, 610, 360); // An extra tap must not restart closing or settle twice.
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(() => window.godotState?.paused === true);
  check((await state(page)).finishing === true, 'Skip pauses behind the portrait guard');
  await page.setViewportSize({ width: 844, height: 390 });
  await page.waitForFunction(() => window.godotState?.finishing && window.godotPresentation?.closing >= 0 && window.godotPresentation?.sale.includes('+'));
  check((await state(page)).finishing, 'a real purchase plays during Skip before the report');
  await page.screenshot({ path: `${out}/3_skip_pickup.png` });
  const firstPurchase = await page.evaluate(() => window.godotPresentation.service.purchases[0]);
  const opening = await page.evaluate(() => JSON.parse(localStorage.getItem('mashawi_save')));
  check(opening.weather_day === opening.day && opening.day_seed > 0, 'the opening weather and customer seed are committed');
  check(opening.money === save.money && opening.total_served === 0, 'unfinished trading cannot persist free cash or goal progress');
  await page.goto(url + '?dev=' + encodeURIComponent('--lang=ar --uitest'));
  await page.waitForSelector('#play', { state: 'visible', timeout: 180000 });await page.tap('#play');await waitReady(page,180000);await waitPhase(page,'title');
  await page.waitForFunction(()=>window.godotMenuTargets?.continue_game);
  const resume = await page.evaluate(()=>window.godotMenuTargets.continue_game);
  await tap(page,resume.x*844,resume.y*390);await waitPhase(page,'prep');
  await page.waitForFunction(()=>!window.godotPresentation.curtain);
  const retry = await page.evaluate(()=>JSON.parse(localStorage.getItem('mashawi_save')));
  check(retry.money === opening.money && JSON.stringify(retry.inventory) === JSON.stringify(opening.inventory), 'reload restores the opening cash and inventory checkpoint');
  check(retry.day_seed === opening.day_seed && retry.weather === opening.weather, 'reload cannot reroll the weather or customer stream');
  await tap(page,85,360);await waitPhase(page,'day');await tap(page,610,360);
  await page.waitForFunction(()=>window.godotPresentation?.service?.purchases.length>0);
  const replayPurchase = await page.evaluate(()=>window.godotPresentation.service.purchases[0]);
  check(replayPurchase.item === firstPurchase.item && replayPurchase.dineIn === firstPurchase.dineIn, 'the replay starts with the same actual customer purchase');
  const report = await waitPhase(page, 'report', 60000);
  const closed = await page.evaluate(() => JSON.parse(localStorage.getItem('mashawi_save')));
  check(report.hasSave && !report.finishing && report.day === 2 && closed.history.length === 1, 'Skip settles the current day exactly once');
  check(closed.history[0].served > 0 && report.money > stocked.money && closed.inventory.chicken < save.inventory.chicken, 'skipped trading earns money and consumes ingredients');
  await page.waitForTimeout(1000);
  await page.screenshot({ path: `${out}/4_report.png` });
  const errors = con.errors();
  check(errors.length === 0, `no browser or game errors (${errors.length})`);
  errors.slice(0, 8).forEach(e => console.log(e));
  await ctx.close();

  // A short, narrow landscape screen must still reach the daily actions.
  const small = await browser.newContext({ ...devices['iPhone SE'], viewport: { width: 667, height: 375 }, locale: 'ar', ignoreHTTPSErrors: true });
  const smallPage = await small.newPage();
  const smallCon = watchConsole(smallPage);
  await armReady(smallPage);
  await smallPage.goto(url + '?dev=' + encodeURIComponent('--phase=prep --weather=sunny'), { waitUntil: 'load' });
  await smallPage.waitForSelector('#play', { state: 'visible', timeout: 180000 });
  await smallPage.tap('#play');
  await waitReady(smallPage, 180000);
  await waitPhase(smallPage, 'prep');
  await smallPage.waitForTimeout(1000);
  await tap(smallPage, 630, 345);
  check((await state(smallPage)).panel === 'supplies', 'iPhone SE size can reach the supplies tab');
  await tap(smallPage, 160, 80);
  check((await state(smallPage)).money < 1500, 'iPhone SE size can reach the daily supply shortcut');
  await smallPage.screenshot({ path: `${out}/5_small_phone_supplies.png` });
  await tap(smallPage, 44, 80);
  await tap(smallPage, 70, 345);
  await waitPhase(smallPage, 'day');
  check((await state(smallPage)).phase === 'day', 'iPhone SE size can open the stand');
  check(smallCon.errors().length === 0, 'no errors on the small phone layout');
  await small.close();
} finally {
  await browser.close();
}
finish('web_mobile_play_test (webkit)');
