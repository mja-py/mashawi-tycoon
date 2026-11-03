// Drag-to-scroll regression test for the web export (touch via CDP, or mouse with the "mouse" arg).
// Opens the supplies panel directly (?dev=--phase=prep --panel=supplies), taps the first pack button
// (money 1500 -> 1490), then drags starting on that same button: the list must scroll, nothing must be bought.
//   node tools/web_touch_test.mjs http://localhost:8080/ /tmp/out [mouse]
import { launchChrome, watchConsole, armReady, waitReady, waitPhase, state, check, finish, outDir } from './web_test_lib.mjs';
const url = process.argv[2] || 'http://localhost:8080/'; const out = outDir(process.argv[3] || '/tmp/web_touch'); const useMouse = process.argv[4] === 'mouse';
const browser = await launchChrome();
const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, hasTouch: true, isMobile: !useMouse, locale: 'ar' });
const page = await ctx.newPage();
const con = watchConsole(page);
await armReady(page);
await page.goto(url + '?dev=' + encodeURIComponent('--phase=prep --panel=supplies'), { waitUntil: 'load' });
await page.waitForSelector('#play', { state: 'visible', timeout: 120000 });
await page.tap('#play');
await waitReady(page);
await waitPhase(page, 'prep');
await page.waitForTimeout(2500);
const cdp = await ctx.newCDPSession(page);
async function touch(type, x, y) { await cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y, id: 1 }] }); }
async function tap(x, y) { if (useMouse) { await page.mouse.move(x, y); await page.mouse.down(); await page.waitForTimeout(80); await page.mouse.up(); } else { await touch('touchStart', x, y); await page.waitForTimeout(80); await touch('touchEnd', x, y); } await page.waitForTimeout(1200); }
async function drag(x, y0, y1, steps, ms) {
  if (useMouse) { await page.mouse.move(x, y0); await page.mouse.down(); for (let i = 1; i <= steps; i++) { await page.mouse.move(x, y0 + (y1 - y0) * i / steps); await page.waitForTimeout(ms); } await page.mouse.up(); return; }
  await touch('touchStart', x, y0);
  for (let i = 1; i <= steps; i++) { await touch('touchMove', x, y0 + (y1 - y0) * i / steps); await page.waitForTimeout(ms); }
  await touch('touchEnd', x, y1);
}
await page.screenshot({ path: `${out}/3_supplies.png` });
const s0 = await state(page);
check(s0 && s0.money === 1500, `starts with AED 1500 (${JSON.stringify(s0)})`);
// bread card is the first card (top-right in RTL); its "+20 · 10" button is the right-most of its row
const BTN = { x: 760, y: 258 };
await tap(BTN.x, BTN.y);
const s1 = await state(page);
check(s1 && s1.money === 1490, `tapping a pack button buys it: 1500 -> 1490 (${JSON.stringify(s1)})`);
await page.screenshot({ path: `${out}/4_bought.png` });
await drag(BTN.x, BTN.y, 90, 12, 40); // drag that STARTS on the buy button: must scroll, must not buy
await page.waitForTimeout(1500);
const s2 = await state(page);
check(s2 && s2.money === 1490, `drag starting on a button does not buy (${JSON.stringify(s2)})`);
await page.screenshot({ path: `${out}/5_dragged_from_button.png` });
await drag(422, 150, 330, 10, 40); // drag back down over text
await page.waitForTimeout(1500);
await page.screenshot({ path: `${out}/6_dragged_back.png` });
// mouse-wheel / trackpad scrolling over an open panel must scroll it, never close it (the wheel
// event bubbles through the panel to the backdrop, which used to close on any button press)
await tap(695, 360); // menu tab
const s3 = await state(page);
check(s3 && s3.panel === 'menu', `menu tab opens the menu panel (${JSON.stringify(s3)})`);
for (let i = 0; i < 6; i++) { await page.mouse.move(422, 200); await page.mouse.wheel(0, 240); await page.waitForTimeout(60); }
await page.mouse.wheel(0, -2000);
await page.waitForTimeout(600);
const s4 = await state(page);
check(s4 && s4.panel === 'menu', `wheel scrolling keeps the menu open (${JSON.stringify(s4)})`);
await page.screenshot({ path: `${out}/7_menu_after_wheel.png` });
await tap(44, 72); // the Close button (top-left of the panel in RTL)
const s5 = await state(page);
check(s5 && s5.panel === '', `Close button closes the panel (${JSON.stringify(s5)})`);
const errs = con.errors();
check(errs.length === 0, `no console errors (${errs.length})`);
errs.slice(0, 5).forEach(l => console.log('    ', l.slice(0, 200)));
await browser.close();
finish('web_touch_test' + (useMouse ? ' (mouse)' : ''));
