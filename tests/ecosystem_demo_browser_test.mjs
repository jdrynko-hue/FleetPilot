// Real mobile-browser acceptance of the standalone in-memory Fleet/Garage demo.
// Runs in public GitHub Actions with local file:// content, never real APIs.
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { mkdirSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { chromium, webkit } from 'playwright';

const demo = pathToFileURL(resolve('web/demo/index.html')).href;
const roles = ['fleet','garage','mechanic','customer'];
const viewports = [
  {width:320,height:760,mobile:true},
  {width:390,height:844,mobile:true},
  {width:1280,height:850,mobile:false},
];

async function checkNoHorizontalOverflow(page, tag) {
  const metrics=await page.evaluate(()=>({
    body:document.body.scrollWidth,root:document.documentElement.scrollWidth,
    width:window.innerWidth,
  }));
  assert.ok(metrics.body<=metrics.width+2 && metrics.root<=metrics.width+2,
    tag+' horizontal overflow '+JSON.stringify(metrics));
}
async function browserTest(engine,name,viewport) {
  const browser=await engine.launch({headless:true});
  const context=await browser.newContext({
    viewport:{width:viewport.width,height:viewport.height},
    isMobile:viewport.mobile,
    hasTouch:viewport.mobile,
    deviceScaleFactor:viewport.mobile?2:1,
  });
  const page=await context.newPage();
  const errors=[],external=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('request',r=>{
    if(/^https?:\/\//.test(r.url()))external.push(r.url());
  });
  const tag=name+' '+viewport.width;
  const snapshots=name==='webkit' && viewport.width===390;
  if(snapshots)mkdirSync('artifacts/demo-mobile',{recursive:true});
  try{
    await page.goto(demo);
    await page.locator('body.js').waitFor({timeout:15000});
    await checkNoHorizontalOverflow(page,tag+' load');
    for(const role of roles){
      await page.locator('[data-role="'+role+'"]').click();
      await page.locator('#'+role+'.view.active').waitFor();
      assert.equal(new URL(page.url()).hash,'#'+role,tag+' hash '+role);
      assert.equal(await page.locator('.view.active').count(),1,tag+' active view');
      await checkNoHorizontalOverflow(page,tag+' '+role);
    }
    await page.locator('[data-role="fleet"]').click();
    assert.equal((await page.locator('#fleetStatus').innerText()).trim(),'Nowa usterka');
    assert.equal((await page.locator('#demoGuideStep').innerText()).trim(),'Krok 1 z 7');
    assert.equal(await page.locator('#demoGuideProgress').evaluate(node=>String(node.value)),'0');
    if(snapshots)await page.screenshot({path:'artifacts/demo-mobile/01-fleet.png',fullPage:true});
    assert.equal(await page.locator('[data-action="approve"]').isHidden(),true);
    await page.locator('[data-action="send"]').click();
    assert.equal((await page.locator('#fleetStatus').innerText()).trim(),'Przekazano do Garage');
    assert.equal((await page.locator('#demoGuideTitle').innerText()).trim(),
      'Przygotuj kosztorys w Garage');
    await page.locator('#demoGuideGo').click();
    await page.locator('#garage.view.active').waitFor();
    await page.locator('#estimate').fill('240.50');
    await page.locator('[data-action="quote"]').click();
    if(snapshots)await page.screenshot({path:'artifacts/demo-mobile/02-garage.png',fullPage:true});
    assert.equal((await page.locator('#demoGuideTitle').innerText()).trim(),'Zatwierdź kosztorys');
    await page.locator('#demoGuideGo').click();
    await page.locator('#fleet.view.active').waitFor();
    assert.equal((await page.locator('#fleetStatus').innerText()).trim(),'Kosztorys wysłany');
    assert.match(await page.locator('[data-action="approve"]').innerText(),/240\.50/);
    await page.locator('[data-action="approve"]').click();
    assert.equal((await page.locator('#demoGuideTitle').innerText()).trim(),'Rozpocznij naprawę');
    await page.locator('#demoGuideGo').click();
    await page.locator('#mechanic.view.active').waitFor();
    await page.locator('[data-action="start"]').click();
    assert.equal((await page.locator('#mechanicStatus').innerText()).trim(),'Naprawa trwa');
    if(snapshots)await page.screenshot({path:'artifacts/demo-mobile/03-mechanic.png',fullPage:true});
    await page.locator('[data-action="complete"]').click();
    await page.locator('[data-role="fleet"]').click();
    assert.match(await page.locator('#historyList').innerText(),/240\.50/);
    assert.equal((await page.locator('#fleetIssueCount').innerText()).trim(),'0');
    assert.equal((await page.locator('#demoGuideTitle').innerText()).trim(),
      'Wyślij zapytanie jako klient');
    await page.locator('#demoGuideGo').click();
    await page.locator('#customer.view.active').waitFor();
    await page.locator('[data-action="request"]').click();
    assert.equal((await page.locator('#customerStatus').innerText()).trim(),'Oczekuje');
    assert.equal((await page.locator('#demoGuideTitle').innerText()).trim(),
      'Potwierdź wizytę w Garage');
    await page.locator('#demoGuideGo').click();
    await page.locator('#garage.view.active').waitFor();
    await page.locator('[data-action="confirm"]').click();
    await page.locator('[data-role="customer"]').click();
    assert.equal((await page.locator('#customerStatus').innerText()).trim(),'Potwierdzona');
    assert.equal((await page.locator('#demoGuideStep').innerText()).trim(),'Gotowe');
    assert.equal(await page.locator('#demoGuideProgress').evaluate(node=>String(node.value)),'7');
    if(snapshots)await page.screenshot({path:'artifacts/demo-mobile/04-customer.png',fullPage:true});
    await page.locator('[data-role="mechanic"]').click();
    assert.equal((await page.locator('#mechanicJobCount').innerText()).trim(),'2');
    await page.locator('#reset').click();
    assert.equal((await page.locator('#demoGuideStep').innerText()).trim(),'Krok 1 z 7');
    await page.locator('[data-role="fleet"]').click();
    assert.equal((await page.locator('#fleetStatus').innerText()).trim(),'Nowa usterka');
    await page.locator('[data-role="customer"]').click();
    assert.equal((await page.locator('#customerStatus').innerText()).trim(),'Nie wysłano');
    assert.deepEqual(errors,[],tag+' JavaScript errors');
    assert.deepEqual(external,[],tag+' unexpected HTTP requests');
    await checkNoHorizontalOverflow(page,tag+' end');
    console.log('PASS '+tag+' all actions, reset, safe local data, responsive layout');
  }finally{await browser.close();}
}
async function noJavaScriptFallback(engine,name){
  const browser=await engine.launch({headless:true});
  try{
    const context=await browser.newContext({
      viewport:{width:390,height:844},isMobile:true,
      hasTouch:true,javaScriptEnabled:false,
    });
    const page=await context.newPage();
    await page.goto(demo);
    for(const role of roles){
      await page.locator('[data-role="'+role+'"]').click();
      assert.equal(await page.locator('#'+role).isVisible(),true,
        name+' no-JS fallback '+role);
      assert.equal(new URL(page.url()).hash,'#'+role);
      await checkNoHorizontalOverflow(page,name+' noJS '+role);
    }
    console.log('PASS '+name+' no-JavaScript role links on mobile');
  }finally{await browser.close();}
}
for(const [name,engine] of [['chromium',chromium],['webkit',webkit]]){
  for(const viewport of viewports)await browserTest(engine,name,viewport);
  await noJavaScriptFallback(engine,name);
}
console.log('PASS all real-browser Flotaryx ecosystem demo acceptance cases');
