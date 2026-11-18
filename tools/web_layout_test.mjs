// Phone layout: every prep tab must be usable with the guide on and off, on a notched
// iPhone 14 and an iPhone SE, in both languages. Fails on a clipped panel, a shrunken card,
// hidden roll arrows, a small navigation target, or a guide that takes too much room.
// Usage: node tools/web_layout_test.mjs <url> <out dir>
import { devices } from 'playwright';
import { launchWebKit, watchConsole, armReady, waitReady, waitPhase, outDir, check, finish } from './web_test_lib.mjs';

const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/tmp/mashawi-layout');
// Smallest tap target, in CSS points, for the controls a player navigates with.
const MIN_POINT = 38;
const MIN_CARD_SCALE = 0.9;
// Safe-area insets in logical px (top,right,bottom,left): an iPhone 14 in landscape.
const NOTCH = '0,69,31,69';
const NAV = /^(close_panel|back_cards|back_dishes|roll_left|roll_right|category_|build_group_|tab_|open_shop|stock_today|stock_outlook|coach_next|coach_close|price_up|price_down|recipe_)/;
const CASES = [
  ['en', 'iPhone 14', 844, 390, NOTCH],
  ['ar', 'iPhone 14', 844, 390, NOTCH],
  ['en', 'iPhone SE', 667, 375, ''],
  ['ar', 'iPhone SE', 667, 375, ''],
];
// [panel, guide step shown over it, extra flags, name]
const VIEWS = [
  ['supplies', 'stock', '', 'supplies'],
  ['menu', 'dish', '', 'menu'],
  ['menu', 'recipe', '--dish=chicken_tikka', 'dish'],
  ['place', 'supplies', '', 'place'],
  ['build', 'upgrade', '', 'build'],
  ['build', 'upgrade', '--detail=counter', 'station'],
  ['promote', 'campaign', '', 'promote'],
  ['goals', 'goals', '', 'goals'],
  // A restaurant pays wages: the top bar carries its longest set of chips.
  ['menu', 'dish', '--stage=4 --stations=counter:7,grill:7,seating:4', 'restaurant'],
];

const browser = await launchWebKit();
try {
  for (const [lang, device, width, height, safe] of CASES) {
    const ctx = await browser.newContext({ ...devices[device], locale: lang, viewport: { width, height } });
    const tag = `${lang}/${device}`;
    try {
      for (const guide of [false, true]) {
        for (const [panel, step, extra, name] of VIEWS) {
          const page = await ctx.newPage();
          const logs = watchConsole(page);
          await armReady(page);
          const flags = ['--uitest', '--phase=prep', '--weather=sunny', '--money=100000', '--lang=' + lang, '--panel=' + panel];
          if (extra) flags.push(extra);
          if (guide) flags.push('--coach=' + step);
          if (safe) flags.push('--safe=' + safe);
          await page.goto(url + '?dev=' + encodeURIComponent(flags.join(' ')));
          await page.waitForSelector('#play', { state: 'visible', timeout: 180000 });
          await page.tap('#play');
          await waitReady(page, 180000);
          await waitPhase(page, 'prep');
          await page.waitForFunction(p => window.godotState?.panel === p && window.godotMenuTargets?.close_panel, panel, { timeout: 30000 });
          await page.waitForTimeout(1200); // opening slide and the guide's fold have settled
          const view = await page.evaluate(() => window.godotPresentation);
          const targets = await page.evaluate(() => window.godotMenuTargets);
          const label = `${tag} ${name}${guide ? ' + guide' : ''}`;
          const point = width / view.logicalSize.width; // CSS points per logical px
          check(!view.panelClipped, `${label}: the panel fits between the bars`);
          check(view.menuBottom <= view.tabsTop + 0.002, `${label}: the panel stays above the tabs`);
          if (view.roll && view.roll.count > 0) {
            check(view.roll.fit >= MIN_CARD_SCALE, `${label}: cards at ${Math.round(view.roll.fit * 100)}% size (>= ${MIN_CARD_SCALE * 100}%)`);
            check(view.roll.count < 2 || (view.roll.arrows && view.roll.arrowsInside), `${label}: roll arrows are on screen`);
          }
          const small = Object.entries(targets).filter(([id, t]) => NAV.test(id) && Math.min(t.w, t.h) * point < MIN_POINT)
            .map(([id, t]) => `${id} ${Math.round(Math.min(t.w, t.h) * point)}pt`);
          check(small.length === 0, `${label}: navigation targets >= ${MIN_POINT}pt${small.length ? ' (' + small.join(', ') + ')' : ''}`);
          const off = Object.entries(targets).filter(([, t]) => t.x <= 0 || t.x >= 1 || t.y <= 0 || t.y >= 1).map(([id]) => id);
          check(off.length === 0, `${label}: every published control is on screen${off.length ? ' (' + off.join(', ') + ')' : ''}`);
          check(!!targets.graphics_hud && !!targets.reputation, `${label}: Settings and Reputation stay in the top bar`);
          if (guide) {
            check(view.coach?.visible && view.coach.compact, `${label}: the guide folds to its strip over a menu`);
            check(view.coach.reserve <= 96, `${label}: the guide strip takes ${Math.round(view.coach?.reserve)} px (<= 96)`);
            check(view.coach.bottom <= view.menuTop + 1, `${label}: the guide does not cover the menu`);
          }
          check(logs.errors().length === 0, `${label}: no console errors${logs.errors().length ? ' ' + logs.errors()[0] : ''}`);
          await page.screenshot({ path: `${out}/${lang}-${device.replace(/ /g, '')}-${name}${guide ? '-guide' : ''}.png` });
          await page.close();
        }
      }
    } finally {
      await ctx.close();
    }
  }
} finally {
  await browser.close();
}
finish('web_layout_test');
