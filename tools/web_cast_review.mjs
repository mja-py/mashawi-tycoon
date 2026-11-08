// Render the approved character family through the production web renderer.
import assert from 'node:assert/strict';
import {launchChrome,watchConsole,armReady,waitReady,outDir} from './web_test_lib.mjs';
const url=process.argv[2]||'http://localhost:8080/';
const out=outDir(process.argv[3]||'/tmp/mashawi-cast');
const browser=await launchChrome();
try {
 const context=await browser.newContext({viewport:{width:1600,height:900},deviceScaleFactor:1});
 const page=await context.newPage(),logs=watchConsole(page);await armReady(page);
 const poses=process.argv[4]==='--poses';
 const cases=poses ? [{name:'family',flags:''}, ...[1,3].flatMap(actor=>['idle','order','collect','line-full','price','angry','sit'].map(clip=>({name:`${actor===1?'woman':'man'}-${clip}`,flags:`--cast-detail=${actor} --cast-clip=${clip} --cast-time=0.8 --cast-bg=264d3e`})))] : [{name:'approved-character-family',flags:process.argv[4]||''}];
 for(const item of cases){
  await page.goto(url+'?dev='+encodeURIComponent('--cast-review --lang=en --scale3d=1 '+item.flags));
  await page.waitForSelector('#play',{state:'visible',timeout:180000});await page.click('#play');await waitReady(page,180000);
  await page.waitForTimeout(500);await page.screenshot({path:out+'/'+item.name+'.png'});
  console.log('Reviewed '+item.name);
 }
 assert.deepEqual(logs.errors(),[]);await context.close();console.log('Approved character family (web renderer): PASS');
} finally {await browser.close()}
