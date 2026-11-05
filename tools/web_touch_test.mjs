// Drag-to-browse regression for supplies (touch via CDP, or mouse with the "mouse" arg).
// Swipe directly from a pack button. The next card should appear without a purchase.
//   node tools/web_touch_test.mjs http://localhost:8080/ /tmp/out [mouse]
import { launchChrome, watchConsole, armReady, waitReady, waitPhase, state, check, finish, outDir } from './web_test_lib.mjs';
const url = process.argv[2] || 'http://localhost:8080/'; const out = outDir(process.argv[3] || '/tmp/web_touch'); const useMouse = process.argv[4] === 'mouse';
const browser = await launchChrome();
const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, hasTouch: true, isMobile: !useMouse, locale: 'ar' });
const page = await ctx.newPage();
const con = watchConsole(page);
await armReady(page);
await page.goto(url + '?dev=' + encodeURIComponent('--phase=prep --panel=supplies --uitest --lang=ar'), { waitUntil: 'load' });
await page.waitForSelector('#play', { state: 'visible', timeout: 120000 });
await page.tap('#play');
await waitReady(page);
await waitPhase(page, 'prep');
await page.waitForTimeout(2500);
const cdp = await ctx.newCDPSession(page);
async function touch(type, x, y) { await cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y, id: 1 }] }); }
async function tap(x, y) { if (useMouse) { await page.mouse.move(x, y); await page.mouse.down(); await page.waitForTimeout(80); await page.mouse.up(); } else { await touch('touchStart', x, y); await page.waitForTimeout(80); await touch('touchEnd', x, y); } await page.waitForTimeout(1200); }
async function drag(x, y, distance) {
  if (useMouse) {
    await page.mouse.move(x, y);
    await page.mouse.down();
  } else {
    await touch('touchStart', x, y);
  }
  for (let i = 1; i <= 12; i++) {
    const step = x + distance * i / 12;
    if (useMouse) await page.mouse.move(step, y);
    else await touch('touchMove', step, y);
    await page.waitForTimeout(40);
  }
  if (useMouse) await page.mouse.up();
  else await touch('touchEnd');
  await page.waitForTimeout(550);
}
async function target(id) {
  await page.waitForFunction(id => !!window.godotMenuTargets?.[id], id, { timeout: 10000 });
  const t = await page.evaluate(id => window.godotMenuTargets[id], id);
  return { x: t.x * 844, y: t.y * 390 };
}
async function hit(id) {
  const t = await target(id);
  await tap(t.x, t.y);
}
await page.screenshot({ path: `${out}/3_supplies.png` });
check((await state(page)).money === 1500, 'starts with AED 1500');
await hit('pack_bread_0');
check((await state(page)).money === 1490, 'a tap purchases one bread pack');
const bread = await target('pack_bread_0');
await drag(bread.x, bread.y, 165);
await target('pack_chicken_0');
check((await state(page)).money === 1490, 'dragging from a buy button advances the carousel without a purchase');
await page.screenshot({ path: `${out}/4_swiped.png` });
const chicken = await target('pack_chicken_2');
await drag(chicken.x, chicken.y, -165);
await target('pack_bread_0');
check((await state(page)).money === 1490, 'reverse swipe returns to bread without a purchase');
await hit('tab_menu');
await hit('select_chicken_tikka');
for (let i = 0; i < 6; i++) {
  await page.mouse.move(422, 200);
  await page.mouse.wheel(0, 240);
  await page.waitForTimeout(60);
}
await page.mouse.wheel(0, -2000);
await page.waitForTimeout(600);
check((await state(page)).menuItem === 'chicken_tikka', 'wheel scrolling keeps the recipe sheet open');
await hit('close_panel');
check((await state(page)).panel === '', 'Close dismisses the panel');
const errs = con.errors();
check(errs.length === 0, `no console errors (${errs.length})`);
errs.slice(0, 5).forEach(l => console.log('    ', l.slice(0, 200)));
await browser.close();
finish('web_touch_test' + (useMouse ? ' (mouse)' : ''));
