// Play the actual onboarding, including genuine recipe/price edits and a live sale.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {devices} from 'playwright';
import {launchWebKit,watchConsole,armReady,waitReady,waitPhase,outDir} from './web_test_lib.mjs';
const url=process.argv[2]||'http://localhost:8080/',out=outDir(process.argv[3]||'/tmp/mashawi-coach');
const browser=await launchWebKit();
try{
 for(const [lang,profile,width,height] of [['en','iPhone SE',667,375],['ar','iPhone 14',844,390]]){
  if(process.argv[4]&&lang!==process.argv[4])continue;
  const context=await browser.newContext({...devices[profile],viewport:{width,height},locale:lang,recordVideo:{dir:out,size:{width:1000,height:562}}});
  const page=await context.newPage(),logs=watchConsole(page);await armReady(page);
  const view=()=>page.evaluate(()=>window.godotPresentation);
  const save=()=>page.evaluate(()=>JSON.parse(localStorage.getItem('mashawi_save')));
  async function boot(){await page.goto(url+'?dev='+encodeURIComponent(`--lang=${lang} --uitest --sim-seed=27`));await page.waitForSelector('#play',{state:'visible',timeout:180000});await page.tap('#play');await waitReady(page,180000)}
  async function hit(id){await page.waitForFunction(()=>!window.godotPresentation?.curtain);await page.waitForFunction(id=>window.godotMenuTargets?.[id]&&!window.godotMenuTargets[id].disabled,id,{timeout:15000});const p=await page.evaluate(id=>window.godotMenuTargets[id],id);assert(p.x>0&&p.x<1&&p.y>0&&p.y<1,id+' on screen');await page.touchscreen.tap(p.x*width,p.y*height);await page.waitForTimeout(450)}
  async function at(topic,done=false){await page.waitForFunction(({topic,done})=>window.godotPresentation?.coach?.topic===topic&&window.godotPresentation.coach.done===done,{topic,done},{timeout:90000});const v=await view();assert(v.coach.fits,topic+' fits');assert(!v.coach.text.startsWith('coach.'),topic+' localized');if(v.coach.visible&&!v.coach.embedded&&v.coach.topic!=='graduate'&&v.coach.topic!=='welcome'&&(await page.evaluate(()=>window.godotState.panel))){assert(v.coach.bottom<=v.menuTop+1,topic+' mentor cannot overlay the menu');}return v}
  try{
   await boot();await waitPhase(page,'title');await hit('new_game');await waitPhase(page,'prep');await at('welcome');await page.waitForFunction(()=>!window.godotPresentation.curtain);
   const initial=await save();assert(!(await view()).guide,'new game starts in the real street');
   await page.screenshot({path:`${out}/${lang}-1-welcome.png`});
   await hit('coach_next');await at('menu');await hit('tab_menu');await at('menu',true);
   await hit('coach_next');await at('dish');await hit('select_chicken_tikka');await at('dish',true);
   await hit('coach_next');await at('recipe');await hit('coach_next');
   assert.equal((await view()).coach.done,false,'opening a dish cannot complete the recipe lesson');
   await page.waitForTimeout(600);await hit('recipe_sauce_up');await at('recipe',true);assert.equal((await save()).menu.chicken_tikka.recipe.sauce,2);
   assert.equal((await save()).money,initial.money,'recipe practice does not spend money');
   await page.screenshot({path:`${out}/${lang}-2-recipe.png`});
   await hit('coach_next');await at('price');await hit('coach_next');await hit('price_up');await at('price',true);
   assert.equal((await save()).menu.chicken_tikka.price,initial.menu.chicken_tikka.price+1);
   // Persistence: a reload must resume a completed lesson, not silently restart.
   await boot();await waitPhase(page,'title');await hit('continue_game');await waitPhase(page,'prep');await at('price',true);
   await hit('graphics_hud');await hit('guide_settings');await page.waitForFunction(()=>window.godotPresentation?.guide);
   await page.waitForFunction(()=>!window.godotPresentation.coach.visible);assert.equal((await view()).portraitCount,1,'reference book frees the small mentor portrait');
   await hit('guide_close');await at('price',true);
   await hit('coach_close');await page.waitForFunction(()=>!window.godotPresentation?.coach);assert.equal((await save()).tutorial.active,false);
   await hit('graphics_hud');await hit('guide_settings');await hit('guide_practice');await at('price',true);
   await hit('coach_next');await at('supplies');
   // Exploring the menu must not strand the stock lesson with its dish switched off.
   await hit('tab_menu');await hit('select_chicken_tikka');await hit('on_sale');
   await hit('tab_supplies');await at('supplies',true);
   await hit('coach_next');await at('stock');await hit('coach_next');
   const cash=(await save()).money;await hit('stock_today');await at('stock',true);assert((await save()).money<cash,'a real stock purchase was made');assert.equal((await save()).menu.chicken_tikka.enabled,false,'the guide accepts the player choosing another food dish');
   await hit('coach_next');await at('open');await hit('open_shop');await waitPhase(page,'day');await at('open',true);
   await hit('coach_next');await at('order',true);await page.screenshot({path:`${out}/${lang}-3-order.png`});
   await hit('coach_next');await at('sale',true);let v=await view();assert(v.service.served>0&&v.service.purchases.every(p=>p.visible&&p.ordered),'mentor waits for real visible purchases');
   await hit('coach_next');await at('finish');await hit('speed_2');await hit('skip_day');await waitPhase(page,'report',120000);await at('report');
   await page.waitForFunction(()=>window.godotPresentation?.coach?.embedded);await page.waitForFunction(()=>!window.godotPresentation?.curtain);await page.waitForTimeout(500);await page.screenshot({path:`${out}/${lang}-4-report.png`});
   assert.equal((await save()).history.length,1);await hit('next_day');await waitPhase(page,'prep');await at('report',true);
   await hit('coach_next');await at('upgrade');await hit('coach_next');await page.screenshot({path:`${out}/${lang}-5-upgrade.png`});
   const beforeUpgrade=await save();await hit('buy_station');await at('upgrade',true);assert((await save()).money<beforeUpgrade.money,'tutorial notices a real upgrade');
   await hit('coach_next');await at('campaign');await hit('coach_next');const noCampaign=await save();await hit('coach_defer');await at('campaign',true);assert.equal((await save()).money,noCampaign.money,'deferring a campaign never spends money');assert.deepEqual((await save()).marketing,{});
   await hit('coach_next');await at('goals');await hit('coach_next');if(await page.evaluate(()=>!!window.godotMenuTargets.claim_goal)){await hit('claim_goal');await hit('dialog_ok')}else{await hit('coach_defer')}await at('goals',true);
   await hit('coach_next');await at('graduate');await page.screenshot({path:`${out}/${lang}-6-ready.png`});await hit('coach_next');await page.waitForFunction(()=>!window.godotPresentation?.coach&&window.godotPresentation?.portraitCount===0);
   assert.equal((await save()).tutorial.completed,true);assert.equal((await save()).tutorial.active,false);
   assert.deepEqual(logs.errors(),[]);fs.writeFileSync(`${out}/${lang}-proof.json`,JSON.stringify({save:await save(),view:await view()},null,2));
   console.log(`${lang}: interactive preparation, real recipe/price/stock changes, reload/resume, real order and sale, report, upgrade, optional promotion, goals and portrait cleanup: PASS`);
  }catch(e){await page.screenshot({path:`${out}/${lang}-failure.png`});fs.writeFileSync(`${out}/${lang}-failure.json`,JSON.stringify(await page.evaluate(()=>({state:window.godotState,view:window.godotPresentation,targets:window.godotMenuTargets})),null,2));console.log(logs.logs.slice(-20));throw e}finally{await context.close()}
 }
}finally{await browser.close()}
