const {chromium}=require('playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
(async()=>{
 let browser,page;const errors=[],events=[];fs.mkdirSync('evidence/hologram',{recursive:true});
 try {
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  page=await browser.newPage({viewport:{width:412,height:820},deviceScaleFactor:1,recordVideo:{dir:'evidence/hologram/video',size:{width:412,height:820}}});
  page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  await page.exposeFunction('reportScene',v=>events.push(JSON.parse(v)));
  await page.setContent('<style>body{margin:0}canvas{touch-action:none}</style><script>window.HologramBridge={postMessage:v=>window.reportScene(v)}</script>');
  await page.addScriptTag({content:fs.readFileSync('assets/hologram/scene.bundle.js','utf8')});
  const snapshot=()=>page.evaluate(()=>window.jarvisScene.snapshot());
  const waitFrames=async(n=1)=>{const before=(await snapshot()).frame;await page.waitForFunction(({before,n})=>window.jarvisScene.snapshot().frame>=before+n,{before,n},{timeout:25000});};
  await page.waitForFunction(()=>window.jarvisScene?.snapshot().frame>0);
  await page.screenshot({path:'evidence/hologram/intro-platform.png'});
  await page.waitForFunction(()=>window.jarvisScene.snapshot().introStage==='armour',null,{timeout:30000});
  await page.screenshot({path:'evidence/hologram/intro-assembly.png'});
  await page.waitForFunction(()=>window.jarvisScene.snapshot().intro==='done',null,{timeout:45000});
  assert.ok(events.some(e=>e.type==='introFinished'));
  assert.deepEqual(events.filter(e=>e.type==='introStage').map(e=>e.stage),['platform','convergence','skeleton','armour','reactor','eyes','serpent','approach','idle']);
  for(const theme of ['snake','forest','solar','inferno','apex','mira']){
   await page.evaluate(theme=>window.jarvisScene.update({theme,state:'listening',intro:false}),theme);await waitFrames();
   const s=await snapshot();assert.equal(s.theme,theme);assert.ok(s.triangles>1000);
   assert.ok(s.snakeHeadBounds.min.every(v=>v>-1)&&s.snakeHeadBounds.max.every(v=>v<1),'full serpent head fits default portrait');
   await page.screenshot({path:`evidence/hologram/${theme}.png`});
  }
  const before=await snapshot();
  await page.waitForFunction(before=>{const s=window.jarvisScene.snapshot();return s.frame>=before.frame+2&&JSON.stringify(s.humanoidHead)!==JSON.stringify(before.humanoidHead)&&JSON.stringify(s.snakeHead)!==JSON.stringify(before.snakeHead);},before,{timeout:25000});
  const after=await snapshot();assert.notDeepEqual(before.humanoidHead,after.humanoidHead);assert.notDeepEqual(before.snakeHead,after.snakeHead);assert.ok(after.armourPlates>150);assert.equal(after.materials,4);
  for(const quality of ['battery','balanced','high','ultra']){await page.evaluate(quality=>window.jarvisScene.update({quality}),quality);await waitFrames();assert.equal((await snapshot()).quality,quality);}
  await page.evaluate(()=>window.jarvisScene.update({quality:'balanced'}));
  for(const state of ['idle','listening','thinking','processing','speaking','completed','error','disconnected']){await page.evaluate(state=>window.jarvisScene.update({state}),state);await waitFrames();assert.equal((await snapshot()).state,state);}
  await page.evaluate(()=>window.jarvisScene.pause(true));const frozen=await snapshot();await page.waitForTimeout(250);assert.deepEqual((await snapshot()).humanoidHead,frozen.humanoidHead);await page.evaluate(()=>window.jarvisScene.pause(false));
  await page.setViewportSize({width:820,height:412});await waitFrames();await page.screenshot({path:'evidence/hologram/landscape.png'});await page.setViewportSize({width:412,height:820});
  await page.evaluate(()=>window.jarvisScene.update({state:'speaking',level:.8}));await waitFrames();await page.screenshot({path:'evidence/hologram/speaking.png'});
  await page.mouse.move(205,360);await page.mouse.down();await page.mouse.move(300,410,{steps:10});await page.mouse.up();await waitFrames();await page.screenshot({path:'evidence/hologram/orbit.png'});
  const taps=events.filter(e=>e.type==='tap').length;await page.mouse.click(205,360);await waitFrames();assert.equal(events.filter(e=>e.type==='tap').length,taps+1);
  await page.evaluate(()=>{window.loss=document.querySelector('canvas').getContext('webgl2').getExtension('WEBGL_lose_context');window.loss.loseContext();});await page.waitForFunction(()=>window.jarvisScene.snapshot().contextLost);
  await page.evaluate(()=>window.loss.restoreContext());await page.waitForFunction(()=>!window.jarvisScene.snapshot().contextLost);await waitFrames();await page.screenshot({path:'evidence/hologram/context-restored.png'});
  assert.deepEqual(errors,[]);const finalSnapshot=await snapshot();
  const skip=await browser.newPage({viewport:{width:412,height:820}});await skip.setContent('<style>body{margin:0}</style>');await skip.addScriptTag({content:fs.readFileSync('assets/hologram/scene.bundle.js','utf8')});await skip.waitForFunction(()=>window.jarvisScene);
  const beforeSkip=await skip.evaluate(()=>window.jarvisScene.snapshot().frame);await skip.evaluate(()=>window.jarvisScene.skipIntro());await skip.waitForFunction(n=>window.jarvisScene.snapshot().introStage==='idle'&&window.jarvisScene.snapshot().frame>n,beforeSkip);assert.equal((await skip.evaluate(()=>window.jarvisScene.snapshot())).intro,'done');
  const beforeReduce=await skip.evaluate(()=>window.jarvisScene.snapshot().frame);await skip.evaluate(()=>window.jarvisScene.update({reduceMotion:true}));await skip.waitForFunction(n=>window.jarvisScene.snapshot().frame>n,beforeReduce);const still=await skip.evaluate(()=>window.jarvisScene.snapshot());await skip.waitForFunction(n=>window.jarvisScene.snapshot().frame>=n+2,still.frame);assert.deepEqual((await skip.evaluate(()=>window.jarvisScene.snapshot())).humanoidHead,still.humanoidHead);
  fs.writeFileSync('evidence/hologram/browser-results.json',JSON.stringify({status:'PASS',environment:'Headless Chromium / SwiftShader (desktop, not Android device)',events,errors,motion:{before,after},snapshot:finalSnapshot},null,2));
  console.log(JSON.stringify({status:'PASS',snapshot:finalSnapshot,errors}));
 }catch(e){fs.writeFileSync('evidence/hologram/browser-results.json',JSON.stringify({status:'FAIL',error:String(e),events,errors},null,2));throw e;}
 finally{if(browser)await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
