// Shared helpers for the web-export tests (Playwright). Every test exits non-zero on a failed check.
import { chromium, webkit } from 'playwright';
import fs from 'node:fs';

export const CHROME_ARGS = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'];

let failures = 0;
export function check(cond, msg) {
  console.log((cond ? '  ok   ' : '  FAIL ') + msg);
  if (!cond) { failures += 1; }
}
export function finish(name) {
  console.log(`${name}: ${failures === 0 ? 'PASS' : failures + ' failed'}`);
  process.exit(failures === 0 ? 0 : 1);
}

export function outDir(path) { fs.mkdirSync(path, { recursive: true }); return path; }

export async function launchChrome(opts = {}) {
  return chromium.launch({ channel: 'chrome', headless: true, args: CHROME_ARGS, ...opts });
}
export async function launchWebKit(opts = {}) {
  return webkit.launch({ headless: true, ...opts });
}

/** Collects console lines and page errors; `errors()` returns the ones that matter. */
export function watchConsole(page) {
  const logs = [];
  page.on('console', m => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', e => logs.push(`[pageerror] ${e.message}`));
  return {
    logs,
    errors: () => logs.filter(l => /error|exception/i.test(l) && !/favicon|service ?worker|SSL certificate/i.test(l)),
  };
}

/** Marks godot-ready on the window before the page's own scripts run. */
export async function armReady(page) {
  await page.addInitScript(() => { window.__godotReady = false; window.addEventListener('godot-ready', () => { window.__godotReady = true; }); });
}

export async function waitReady(page, timeout = 120000) {
  await page.waitForFunction(() => window.__godotReady === true, null, { timeout });
}

/** window.godotState as published by scripts/main.gd ({phase, hasSave, day, money}). */
export async function state(page) {
  return page.evaluate(() => window.godotState || null);
}
export async function waitPhase(page, phase, timeout = 30000) {
  await page.waitForFunction(p => window.godotState && window.godotState.phase === p, phase, { timeout });
  return state(page);
}

export async function tap(page, x, y, touch = true) {
  if (touch) {
    await page.touchscreen.tap(x, y);
  } else {
    await page.mouse.move(x, y); await page.mouse.down(); await page.waitForTimeout(80); await page.mouse.up();
  }
  await page.waitForTimeout(900);
}
