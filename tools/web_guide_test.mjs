// Real new-game conversation, menu handoffs, replay and pause in Safari's engine.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { devices } from 'playwright';
import { launchWebKit, watchConsole, armReady, waitReady, waitPhase, outDir } from './web_test_lib.mjs';
const url = process.argv[2] || 'http://localhost:8080/';
const out = outDir(process.argv[3] || '/tmp/mashawi-guide');
const browser = await launchWebKit();
try {
  for (const [lang, profile, width, height] of [['en','iPhone SE',667,375],['ar','iPhone 14',844,390]]) {
    const context = await browser.newContext({...devices[profile], viewport:{width,height}, locale:lang,
      recordVideo:{dir:out,size:{width:1000,height:562}}});
    try {
      const page = await context.newPage();
      const logs = watchConsole(page);
      await armReady(page);
      await page.goto(url + '?dev=' + encodeURIComponent(`--lang=${lang} --uitest`));
      assert.equal(await page.locator('.copyright').count(),0,'copyright badge removed from loader');
      await page.waitForSelector('#play',{state:'visible',timeout:180000});
      await page.tap('#play');
      await waitReady(page,180000);
      await waitPhase(page,'title');
      async function hit(id) {
        await page.waitForFunction(id => window.godotMenuTargets?.[id] && !window.godotMenuTargets[id].disabled,id);
        const p = await page.evaluate(id=>window.godotMenuTargets[id],id);
        assert(p.x > 0 && p.x < 1 && p.y > 0 && p.y < 1,`${id} is on screen`);
        await page.touchscreen.tap(p.x * width, p.y * height);
        await page.waitForTimeout(500);
      }
      const guide = () => page.evaluate(()=>window.godotPresentation?.guide);
      await hit('credits_title');
      await page.screenshot({path:`${out}/${lang}-credits.png`});
      // Close a regular dialog using its exposed canvas target.
      await hit('dialog_ok');
      await hit('new_game');
      await waitPhase(page,'prep');
      await page.waitForFunction(()=>window.godotPresentation?.guide?.step===0);
      await page.waitForTimeout(700);
      const before = await page.evaluate(()=>JSON.parse(localStorage.getItem('mashawi_save')));
      for(let i=0;i<8;i++) {
        const g = await guide();
        assert.equal(g.step,i);
        assert(g.fits,`${lang} chapter ${i} fits safe viewport`);
        assert(g.dialogue.length>40 && !g.dialogue.startsWith('guide.'),'localized dialogue');
        if(i===0 || i===2 || i===4 || i===6) await page.screenshot({path:`${out}/${lang}-${i}-${g.topic}.png`});
        if(g.scrollNeeded) {
          await page.mouse.move(width*.56,height*.74); await page.mouse.down();
          for(let j=1;j<=12;j++) {
            await page.mouse.move(width*.56,height*(.74-j*.028)); await page.waitForTimeout(20);
          }
          await page.waitForTimeout(180); await page.mouse.up(); await page.waitForTimeout(300);
          assert((await guide()).scroll>0,`${lang} chapter ${i}: the extra advice is reachable by swiping`);
          if(i===2 || i===6) await page.screenshot({path:`${out}/${lang}-${i}-more-tips.png`});
        }
        await hit('guide_next');
      }
      await page.waitForFunction(()=>!window.godotPresentation?.guide && window.godotState?.panel==='supplies');
      assert.equal((await page.evaluate(()=>JSON.parse(localStorage.getItem('mashawi_save')))).money,before.money,'reading tutorial never spends money');
      // Handoff every actionable chapter to its real menu, then replay from settings.
      for (const [i,panel,dish] of [[1,'supplies',''],[2,'menu','chicken_tikka'],[3,'menu','chicken_tikka'],[4,'build',''],[5,'promote',''],[6,'goals','']]) {
        await hit('graphics_hud'); await hit('guide_settings'); await hit(`guide_step_${i}`); await hit('guide_try');
        await page.waitForFunction(({panel,dish})=>!window.godotPresentation?.guide && window.godotState?.panel===panel && (!dish || window.godotState.menuItem===dish),{panel,dish});
        await page.screenshot({path:`${out}/${lang}-handoff-${i}.png`});
      }
      assert.equal((await page.evaluate(()=>JSON.parse(localStorage.getItem('mashawi_save')))).money,before.money,'opening all guided menus does not buy anything');
      await hit('graphics_hud'); await hit('guide_settings');
      assert.equal((await guide()).step,6,'settings resumes the last chapter');
      await hit('guide_back'); assert.equal((await guide()).step,5,'back navigation works');
      await hit('guide_close');
      await page.waitForFunction(()=>!window.godotPresentation?.guide && !window.godotPresentation?.graphics.open);
      await hit('tab_supplies'); await hit('stock_today'); await hit('open_shop');
      await waitPhase(page,'day');
      await hit('graphics_hud'); await hit('guide_settings');
      const clock = await page.evaluate(()=>window.godotPresentation.graphics.clock);
      await page.waitForTimeout(1200);
      assert.equal(await page.evaluate(()=>window.godotPresentation.graphics.clock),clock,'guide pauses active service');
      await page.setViewportSize({width:height,height:width});
      await page.waitForFunction(()=>window.godotState?.paused);
      await page.setViewportSize({width,height});
      await page.waitForFunction(()=>window.godotState?.paused===false);
      assert.equal(await page.evaluate(()=>window.godotPresentation.graphics.clock),clock,'rotation keeps the guide pause intact');
      await hit('guide_close');
      await page.waitForFunction(clock=>window.godotPresentation.graphics.clock>clock,clock);
      const errors=logs.errors(); fs.writeFileSync(`${out}/${lang}-console.json`,JSON.stringify(logs.logs,null,2));
      assert.deepEqual(errors,[],`no game or browser errors: ${errors.join('\n')}`);
      console.log(`${lang}: 8 localized chapters, first-new-game launch, safe layout, all 6 real-menu handoffs, replay, back, close, credits, active-day pause and rotation: PASS`);
    } finally {await context.close();}
  }
} finally {await browser.close();}
