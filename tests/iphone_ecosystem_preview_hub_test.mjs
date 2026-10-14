// Mobile preview hub acceptance on local file:// only; no live APIs.
import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import {mkdirSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {chromium,webkit} from 'playwright';
const portal=pathToFileURL(resolve('web/demo/portal/index.html')).href;
const roles=['fleet','garage','mechanic','customer'];
const sizes=[{width:320,height:760},{width:390,height:844},{width:1280,height:850}];

async function run(browserEngine,name,size){
 const browser=await browserEngine.launch({headless:true});
 try{
  const context=await browser.newContext({
   viewport:size,isMobile:size.width<500,hasTouch:size.width<500,
   deviceScaleFactor:2,
  });
  const page=await context.newPage();
  const errors=[],network=[],popups=[];
  page.on('pageerror',err=>errors.push(String(err)));
  page.on('request',request=>{
    if(/^https?:\/\//.test(request.url()))network.push(request.url());
  });
  page.on('popup',p=>popups.push(p.url()));
  await page.goto(portal);
  assert.equal(await page.title(),'Flotaryx — podgląd ekosystemu na telefon');
  assert.equal(await page.locator('script').count(),0,'Portal must not load scripts');
  assert.equal(await page.locator('form').count(),0,'Portal must not accept customer data');
  assert.equal(await page.locator('a[href^="../index.html#"]').count(),5,
    'Four roles plus start-flow link expected');
  const w=await page.evaluate(()=>({
    document:document.documentElement.scrollWidth,
    body:document.body.scrollWidth,viewport:window.innerWidth}));
  assert.ok(w.document<=w.viewport+2&&w.body<=w.viewport+2,
    name+' '+size.width+' horizontal overflow '+JSON.stringify(w));
  if(name==='webkit'&&size.width===390){
    mkdirSync('artifacts/iphone-preview',{recursive:true});
    await page.screenshot({path:'artifacts/iphone-preview/00-ecosystem-hub.png',fullPage:true});
  }
  for(const role of roles){
    await page.locator('a[href="../index.html#'+role+'"]').first().click();
    await page.locator('#'+role+'.view.active').waitFor({timeout:10000});
    assert.equal(new URL(page.url()).hash,'#'+role,'role navigation '+role);
    assert.equal(await page.locator('.view.active').count(),1,'single active role panel');
    if(name==='webkit'&&size.width===390){
      await page.screenshot({path:'artifacts/iphone-preview/01-'+role+'.png',fullPage:true});
    }
    await page.goBack();
    await page.locator('#page-heading').waitFor();
  }
  const hp=await page.locator('a').filter({hasText:'Pokaż stronę główną'}).getAttribute('href');
  assert.ok(hp?.startsWith('https://rawcdn.githack.com/jdrynko-hue/FleetPilot/9ba76baa9e6c2796801889bbe909aace029640d3/'));
  assert.deepEqual(errors,[],name+' JS errors');
  assert.deepEqual(network,[],name+' API or other external network calls');
  assert.deepEqual(popups,[],name+' popups');
  console.log('PASS: '+name+' '+size.width+'px portal + four in-page role navigation');
 }finally{await browser.close()}
}
for(const [name,engine] of [['chromium',chromium],['webkit',webkit]])
 for(const size of sizes)await run(engine,name,size);
console.log('PASS: safe iPhone preview hub, all four role windows and no external API calls');
