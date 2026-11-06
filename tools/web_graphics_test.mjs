// Exercise the real frame limiter, 3D buffers and persisted settings in iPhone-sized WebKit.
import assert from 'node:assert/strict';
import { devices } from 'playwright';
import { launchWebKit, watchConsole, armReady, waitReady, waitPhase, outDir } from './web_test_lib.mjs';

const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/private/tmp/mashawi-graphics');
const browser = await launchWebKit();
try {
  for (const [lang, width, height] of [['en', 844, 390], ['ar', 667, 375]]) {
    const context = await browser.newContext({ ...devices['iPhone 14'], viewport: { width, height }, locale: lang });
    try {
      const page = await context.newPage();
      const logs = watchConsole(page);
      await armReady(page);
      await page.addInitScript(() => {
        window.__renderTargets = [];
        for (const [name, w, h] of [['texStorage2D', 3, 4], ['texImage2D', 3, 4], ['renderbufferStorage', 2, 3], ['renderbufferStorageMultisample', 3, 4]]) {
          const fn = WebGL2RenderingContext.prototype[name];
          if (typeof fn !== 'function') continue;
          WebGL2RenderingContext.prototype[name] = function (...args) {
            if (Number.isInteger(args[w]) && Number.isInteger(args[h])) {
              window.__renderTargets.push([args[w], args[h]]);
            }
            return fn.apply(this, args);
          };
        }
      });
      const base = url + '?dev=' + encodeURIComponent('--uitest --lang=' + lang);
      async function boot(phase) {
        await page.goto(base + (phase === 'prep' ? '%20--phase%3Dprep' : ''));
        await page.waitForSelector('#play', { state: 'visible', timeout: 120000 });
        await page.tap('#play');
        await waitReady(page);
        await page.waitForSelector('#status', { state: 'hidden' });
        await waitPhase(page, phase);
      }
      const graphics = () => page.evaluate(() => window.godotPresentation?.graphics);
      async function hit(id) {
        await page.waitForFunction(id => window.godotMenuTargets?.[id] && !window.godotMenuTargets[id].disabled, id);
        const b = await page.evaluate(id => window.godotMenuTargets[id], id);
        await page.touchscreen.tap(b.x * width, b.y * height);
      }
      async function expectGraphics(cap, choice, applied) {
        await page.waitForFunction(([cap, choice, applied]) => {
          const g = window.godotPresentation?.graphics;
          return g?.cap === cap && g.choice === choice && (applied === null || Math.abs(g.scale - applied) < 0.005);
        }, [cap, choice, applied]);
      }
      await boot('title');
      await expectGraphics(60, 0, null);
      await hit('graphics_title');
      await page.waitForTimeout(500);
      await page.screenshot({ path: out + '/' + lang + '-settings.png' });
      await hit('graphics_fps_30');
      await hit('graphics_scale_100');
      await expectGraphics(30, 100, 1);
      const canvasSize = () => page.locator('#canvas').evaluate(c => [c.width, c.height]);
      const full = await canvasSize();
      await page.evaluate(() => { window.__renderTargets.length = 0; });
      await hit('graphics_scale_50');
      await expectGraphics(30, 50, 0.5);
      await page.waitForTimeout(2100);
      const measured30 = (await graphics()).fps;
      assert(measured30 > 12 && measured30 <= 33, '30 FPS limit holds on the running engine');
      assert.deepEqual(await canvasSize(), full, 'menus stay at full canvas resolution');
      const targets = await page.evaluate(() => window.__renderTargets);
      const half = full.map(value => value / 2);
      assert(targets.some(([w, h]) => Math.abs(w - half[0]) <= 2 && Math.abs(h - half[1]) <= 2),
        'WebGL allocated a half-resolution 3D render target: ' + JSON.stringify({ full, targets: targets.slice(0, 20) }));
      await hit('graphics_fps_60');
      await hit('graphics_scale_65');
      await expectGraphics(60, 65, 0.65);
      await page.waitForTimeout(1800);
      const measured60 = (await graphics()).fps;
      assert.deepEqual(await page.evaluate(() => JSON.parse(localStorage.getItem('mashawi_graphics'))), { fps: 60, scale: 65 });
      await hit('graphics_close');

      await boot('prep');
      await expectGraphics(60, 65, 0.65);
      // The modal's opaque middle should look the same with or without a deck behind it.
      const modalCrop = () => page.screenshot({ scale: 'css', clip: {
        x: Math.round(width * 0.34), y: Math.round(height * 0.40),
        width: Math.round(width * 0.32), height: Math.round(height * 0.21)
      } });
      async function openGraphics() {
        await hit('graphics_hud');
        await page.waitForFunction(() => window.godotPresentation?.graphics?.open);
        await page.waitForTimeout(550);
      }
      async function closeGraphics() {
        await hit('graphics_close');
        await page.waitForFunction(() => window.godotPresentation?.graphics?.open === false);
      }
      await openGraphics();
      const unobstructed = await modalCrop();
      await closeGraphics();
      await hit('tab_menu');
      await page.waitForTimeout(400);
      await hit('category_drink');
      await hit(lang === 'ar' ? 'roll_left' : 'roll_right');
      await page.waitForFunction(() => !!window.godotMenuTargets?.select_soda);
      await openGraphics();
      await page.screenshot({ path: out + '/' + lang + '-over-selection.png' });
      assert((await modalCrop()).equals(unobstructed), 'Graphics fully covers the selection cards');
      await page.mouse.move(width * 0.49, height * 0.54);
      await page.mouse.down();
      await page.mouse.move(width * (lang === 'ar' ? 0.69 : 0.29), height * 0.54, { steps: 12 });
      await page.mouse.up();
      await page.waitForTimeout(380);
      await closeGraphics();
      assert(await page.evaluate(() => !!window.godotMenuTargets?.select_soda), 'a drag in Graphics leaves the drink selection alone');
      await hit(lang === 'ar' ? 'roll_left' : 'roll_right');
      await page.waitForFunction(() => !!window.godotMenuTargets?.select_karak);

      await hit('tab_supplies');
      await page.waitForTimeout(450);
      await hit('stock_today');
      await page.waitForFunction(() => window.godotMenuTargets?.stock_today?.disabled);
      await hit('close_panel');
      await page.waitForTimeout(300);
      await hit('open_shop');
      await waitPhase(page, 'day');
      await page.waitForTimeout(500);
      await page.screenshot({ path: out + '/' + lang + '-hud.png' });
      await hit('graphics_hud');
      await page.waitForFunction(() => window.godotPresentation?.graphics?.open);
      const pausedClock = (await graphics()).clock;
      await page.waitForTimeout(900);
      assert.equal((await graphics()).clock, pausedClock, 'shop clock pauses in Graphics');
      await hit('graphics_scale_80');
      await expectGraphics(60, 80, 0.8);
      await hit('graphics_close');
      await page.waitForFunction(clock => window.godotPresentation?.graphics?.clock > clock, pausedClock);
      assert.deepEqual(logs.errors(), []);
      console.log(lang, 'render scale, crisp HUD, saved settings, and pause/resume passed', { measured30, measured60 });
    } finally {
      await context.close();
    }
  }
} finally {
  await browser.close();
}
