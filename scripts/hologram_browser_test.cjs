const { chromium } = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:412,height:820},deviceScaleFactor:1});
 const errors=[],events=[];page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
 await page.exposeFunction('reportScene',v=>events.push(JSON.parse(v)));
 await page.setContent('<style>body{margin:0}canvas{touch-action:none}</style><script>window.HologramBridge={postMessage:v=>window.reportScene(v)}</script>');
 await page.addScriptTag({content:fs.readFileSync('assets/hologram/scene.bundle.js','utf8')});
 await page.waitForFunction(()=>window.jarvisScene);
 fs.mkdirSync('evidence/hologram',{recursive:true});
 await page.screenshot({path:'evidence/hologram/intro-platform.png'});
 await page.waitForTimeout(3100);
 await page.screenshot({path:'evidence/hologram/intro-assembly.png'});
 await page.waitForTimeout(3800);
 assert.ok(events.some(e=>e.type==='introFinished'));
 for(const theme of ['snake','forest','solar','inferno','apex','mira']){
  await page.evaluate(theme=>window.jarvisScene.update({theme,state:'listening',intro:false}),theme);
  await page.waitForTimeout(180);
  const state=await page.evaluate(()=>window.jarvisScene.snapshot());assert.equal(state.theme,theme);assert.ok(state.triangles>1000);
  await page.screenshot({path:`evidence/hologram/${theme}.png`});
 }
 await page.evaluate(()=>window.jarvisScene.update({state:'speaking',level:.8}));
 await page.waitForTimeout(300);await page.screenshot({path:'evidence/hologram/speaking.png'});
 await page.mouse.move(205,360);await page.mouse.down();await page.mouse.move(300,410,{steps:10});await page.mouse.up();
 await page.screenshot({path:'evidence/hologram/orbit.png'});
 const tapsBefore=events.filter(e=>e.type==='tap').length;await page.mouse.click(205,360);await page.waitForTimeout(100);assert.equal(events.filter(e=>e.type==='tap').length,tapsBefore+1);
 assert.deepEqual(errors,[]);
 const result={status:'PASS',environment:'Headless Chromium / SwiftShader (desktop, not Android device)',events,errors,snapshot:await page.evaluate(()=>window.jarvisScene.snapshot())};
 fs.writeFileSync('evidence/hologram/browser-results.json',JSON.stringify(result,null,2));console.log(JSON.stringify({status:result.status,snapshot:result.snapshot,errors}));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
