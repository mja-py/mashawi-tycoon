// Verify real Retina buffers, capped portrait animation, quality restoration and cleanup.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {devices} from 'playwright';
import {launchWebKit,armReady,waitReady,waitPhase,watchConsole,outDir} from './web_test_lib.mjs';
const url=process.argv[2]||'http://localhost:8080/';
const out=outDir(process.argv[3]||'/tmp/mashawi-portrait');
const browser=await launchWebKit();
try {
 for(const [lang,profile,width,height] of [['en','iPhone SE',667,375],['ar','iPhone 14',844,390]]) {
  const context=await browser.newContext({...devices[profile],viewport:{width,height},locale:lang});
  try {
   const page=await context.newPage(),logs=watchConsole(page); await armReady(page);
   await page.addInitScript(()=>{
    window.__portraitTargets=[];
    for(const [name,w,h] of [['texStorage2D',3,4],['texImage2D',3,4],['renderbufferStorage',2,3],['renderbufferStorageMultisample',3,4]]) {
     const fn=WebGL2RenderingContext.prototype[name]; if(typeof fn!=='function')continue;
     WebGL2RenderingContext.prototype[name]=function(...a){if(Number.isInteger(a[w])&&Number.isInteger(a[h]))window.__portraitTargets.push([a[w],a[h]]);return fn.apply(this,a)};
    }
   });
   await page.goto(url+'?dev='+encodeURIComponent(`--phase=prep --stage=4 --uitest --lang=${lang} --money=100000 --stations=counter:7,grill:7,seating:4`));
   await page.waitForSelector('#play',{state:'visible',timeout:180000}); await page.tap('#play'); await waitReady(page,180000);await waitPhase(page,'prep');
   async function hit(id){await page.waitForFunction(id=>window.godotMenuTargets?.[id]&&!window.godotMenuTargets[id].disabled,id);const p=await page.evaluate(id=>window.godotMenuTargets[id],id);await page.touchscreen.tap(p.x*width,p.y*height);await page.waitForTimeout(500)}
   const view=()=>page.evaluate(()=>window.godotPresentation);
   await page.waitForFunction(()=>window.godotPresentation?.warmedCast?.length>=6);
   assert(!(await view()).warmedCast.includes('souq-woman'),'retired character is absent');
   await hit('graphics_hud'); await hit('graphics_scale_100'); await hit('graphics_close');
   await page.waitForFunction(()=>window.godotPresentation.graphics.scale===1);
   async function openGuide(){await hit('graphics_hud');await hit('guide_settings');await page.waitForFunction(()=>window.godotPresentation?.guide?.portrait?.width>200);await page.waitForTimeout(600)}
   await openGuide();
   const first=await view(),portrait=first.guide.portrait;
   assert.equal(first.portraitCount,1);assert.equal(portrait.scale,1,'host keeps full resolution');assert.equal(portrait.lod,0,'close-up retains the original sculpt');
   assert(portrait.width<=768&&portrait.height<=768,'Retina allocation is capped');
   const canvas=await page.locator('#canvas').evaluate(c=>({width:c.width,height:c.height}));
   const desired=[portrait.bounds.width*canvas.width/first.logicalSize.width*2,portrait.bounds.height*canvas.height/first.logicalSize.height*2];
   const factor=Math.min(1,768/Math.max(...desired));
   assert(Math.abs(portrait.width-desired[0]*factor)<3&&Math.abs(portrait.height-desired[1]*factor)<3,'portrait matches display-pixel density within budget');
   assert((await page.evaluate(()=>window.__portraitTargets)).some(([w,h])=>w===portrait.width&&h===portrait.height),'WebGL allocated the actual sharp portrait buffer');
   assert.equal(first.graphics.scale,0.5,'dim street uses fewer pixels');
   await page.screenshot({path:`${out}/${lang}-sharp-guide.png`});
   const before=portrait.frames,start=Date.now();await page.waitForTimeout(2400);
   const rate=((await view()).guide.portrait.frames-before)/((Date.now()-start)/1000);
   assert(rate>18&&rate<=32,'host animates at a smooth capped rate');
   await hit('guide_close');await page.waitForFunction(()=>!window.godotPresentation.guide&&window.godotPresentation.portraitCount===0&&window.godotPresentation.graphics.scale===1);
   await hit('graphics_hud');await hit('graphics_scale_50');await hit('graphics_fps_30');await hit('graphics_close');
   await openGuide();await hit('guide_close');
   await page.waitForFunction(()=>window.godotPresentation.portraitCount===0&&window.godotPresentation.graphics.scale===0.5&&window.godotPresentation.graphics.cap===30);
   await hit('graphics_hud');await hit('graphics_fps_60');await hit('graphics_close');
   await hit('tab_supplies');await hit('stock_today');await hit('open_shop');await waitPhase(page,'day');
   await hit('speed_4');await openGuide();
   const fast=await view(),fastStart=Date.now();await page.waitForTimeout(2400);const fastEnd=await view();
   const fastRate=(fastEnd.guide.portrait.frames-fast.guide.portrait.frames)/((Date.now()-fastStart)/1000);
   assert(fastRate>18&&fastRate<=32,'4x street speed cannot accelerate the guide animation');
   assert.equal(fastEnd.graphics.clock,fast.graphics.clock,'guide pauses trading');
   await hit('guide_close');await page.waitForFunction(()=>window.godotPresentation.portraitCount===0);
   assert.deepEqual(logs.errors(),[]);
   const proof={lang,canvas,portrait,rate,fastRate,cast:first.warmedCast,streetScaleWhileOpen:first.graphics.scale};
   fs.writeFileSync(`${out}/${lang}-proof.json`,JSON.stringify(proof,null,2));
   console.log(lang,JSON.stringify(proof));
  }catch(e){const p=context.pages()[0];if(p){await p.screenshot({path:`${out}/${lang}-failure.png`});fs.writeFileSync(`${out}/${lang}-failure.json`,JSON.stringify(await p.evaluate(()=>({view:window.godotPresentation,targets:window.godotMenuTargets})),null,2))}throw e}finally{await context.close()}
 }
}finally{await browser.close()}
console.log('Portrait quality and budget (iPhone WebKit): PASS');
