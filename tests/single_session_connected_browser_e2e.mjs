// Real end-to-end Fleet/Garage using distinct GoTrue logins on one-page UI.
// TEST RUNNER holds synthetic account passwords. Browser HTML receives only
// its currently authenticated session, never a map of other people's JWTs.
import assert from 'node:assert/strict';
import {readFileSync,mkdirSync} from 'node:fs';
import {createServer} from 'node:http';
import {chromium,webkit,devices} from 'playwright';
import {createFixture} from './disposable_connected_fixture.mjs';
const ui=readFileSync('web/demo/session/index.html','utf8');
const pwd='LocalBrowserQA2026!Disposable';
const api=process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const key=process.env.GARAGE_TEST_ANON_KEY;
if(!api||!key||!/^http:\/\/(?:localhost|127\.0\.0\.1):\d+$/.test(api))
 throw Error('Must use disposable loopback Supabase');

async function serve(f){
 const cfg={api,anon:key,shop:f.shop,bay:f.bay,company:f.company,
  issue:f.issue,mechanicUserId:f.roles.mechanic.id};
 const cfgText='window.__FLOTARYX_SINGLE_SESSION_QA__='+JSON.stringify(cfg)+';';
 assert.doesNotMatch(cfgText,/access_token|refresh_token|password|jwt|service_role/);
 const server=createServer((req,res)=>{
  if(!/^127\.0\.0\.1:\d+$/.test(req.headers.host||'')){
   res.writeHead(403);res.end();return;
  }
  if(req.url==='/session-config.js'){
   if(req.headers['sec-fetch-site']==='cross-site'){
    res.writeHead(403);res.end();return;
   }
   res.writeHead(200,{'content-type':'application/javascript',
    'cache-control':'no-store','cross-origin-resource-policy':'same-origin',
    'x-content-type-options':'nosniff'});
   res.end(cfgText);return;
  }
  if(req.url==='/'||req.url==='/index.html'){
   res.writeHead(200,{'content-type':'text/html','cache-control':'no-store',
    'referrer-policy':'no-referrer','x-content-type-options':'nosniff',
    'content-security-policy':"default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; connect-src "+api+"; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"});
   res.end(ui);return;
  }
  res.writeHead(404);res.end();
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 return {url:'http://127.0.0.1:'+server.address().port+'/index.html',server};
}
async function runBrowser(name,engine,profile,platform){
 const fixture=await createFixture({realFleet:process.env.UNIFIED_REAL_FLEET==='1'});
 const {url,server}=await serve(fixture);
 const browser=await engine.launch();
 try{
  const context=await browser.newContext({
   ...devices[profile]});
  const page=await context.newPage(),errs=[],external=[];
  page.on('pageerror',e=>errs.push(e.message));
  page.on('request',r=>{
   const u=new URL(r.url());
   if(!['localhost','127.0.0.1'].includes(u.hostname))external.push(u.origin);
  });
  await page.goto(url);
  const move=async(role,requested=role)=>{
   if(await page.locator('#accountInfo:visible').count()){
    await page.locator('#logoutButton').click();
    await page.locator('#loginForm:visible').waitFor();
   }
   await page.locator('[data-role="'+requested+'"]').click();
   await page.locator('#loginEmail').fill(fixture.roles[role].email);
   await page.locator('#loginPassword').fill(pwd);
   await page.locator('#signInButton').click();
   await page.locator('#accountInfo:visible').waitFor();
   await page.locator('#'+role+'.panel.active').waitFor();
  };
  const click=async(key,label)=>{
   await page.locator('[data-act="'+key+'"]:not([disabled])').click();
   await page.waitForFunction(n=>document.querySelector('#notice').textContent.includes(n),key);
   if(label)await page.waitForFunction(n=>
      document.querySelector('#fleetState').textContent===n,label);
  };
  const snap=async(role)=>{
   const dir='artifacts/single-session-connected'+(platform==='android'?'/android':'');
   mkdirSync(dir,{recursive:true});
   await page.screenshot({path:dir+'/'+role+'.png',
    fullPage:true,animations:'disabled'});
  };
  assert.equal(await page.locator('.panel.active').count(),0);
  await move('fleet','garage');
  assert.equal(await page.locator('#garage.panel.active').count(),0);
  await click('send','Wysłana');
  await move('garage');
  await click('accept','Przyjęta');
  await click('quote','Kosztorys');
  await move('fleet');
  await page.waitForFunction(()=>document.querySelector('#estimate').textContent.includes('£108.00'));
  await click('approve','Zatwierdzona');
  await move('mechanic');
  await click('start','Naprawa trwa');
  await move('garage');
  await click('ready','Gotowa');
  await move('fleet');
  await page.waitForFunction(()=>document.querySelectorAll('#history li').length===4);
  await snap('fleet');
  await move('customer','fleet');
  assert.equal(await page.locator('#fleet.panel.active').count(),0);
  await click('request');
  await page.waitForFunction(()=>document.querySelector('#customerState').textContent==='requested');
  await move('garage');
  await click('confirm');
  await snap('garage');
  await move('customer');
  await page.waitForFunction(()=>document.querySelector('#customerState').textContent==='confirmed');
  await snap('customer');
  await move('mechanic');
  await page.waitForFunction(()=>document.querySelectorAll('#jobs li').length===2);
  await snap('mechanic');
  // The active session MUST NOT allow clicking into someone else's screen.
  await page.locator('[data-role="garage"]').click();
  await page.waitForFunction(()=>document.querySelectorAll('.panel.active').length===0);
  assert.equal(await page.locator('.panel.active').count(),0);
  assert.equal(await page.locator('[data-act]:not([disabled])').count(),0);
  await page.locator('#logoutButton').click();
  await page.locator('#loginForm:visible').waitFor();
  assert.deepEqual(await page.evaluate(()=>[localStorage.length,sessionStorage.length]),[0,0]);
  // A failed membership lookup must not fall back to the requested Fleet
  // view, even though the password and access token are valid.
  const lookup='**/rest/v1/company_members?*';
  await page.route(lookup,route=>route.fulfill({status:503,
   contentType:'application/json',body:JSON.stringify({message:'Synthetic outage'})}));
  await page.locator('[data-role="fleet"]').click();
  await page.locator('#loginEmail').fill(fixture.roles.fleet.email);
  await page.locator('#loginPassword').fill(pwd);
  await page.locator('#signInButton').click();
  await page.waitForFunction(()=>document.querySelector('#accountRole').textContent===
   'Nie potwierdzono dostępu do modułów');
  assert.equal(await page.locator('.panel.active').count(),0);
  assert.equal(await page.locator('[data-act]:not([disabled])').count(),0);
  await page.unroute(lookup);
  await page.locator('#logoutButton').click();
  await page.locator('#loginForm:visible').waitFor();
  // Force the access-token deadline through the real password response;
  // refresh itself still reaches local GoTrue and rotates the actual token.
  const passwordGrant='**/auth/v1/token?grant_type=password';
  const refreshGrant='**/auth/v1/token?grant_type=refresh_token';
  let refreshCalls=0;
  page.on('request',request=>{
   if(new URL(request.url()).searchParams.get('grant_type')==='refresh_token')refreshCalls++;
  });
  const nearExpiry=async route=>{
   const response=await route.fetch();
   const data=await response.json();
   data.expires_at=Math.floor(Date.now()/1000)-1;
   await route.fulfill({response,json:data});
  };
  await page.route(passwordGrant,nearExpiry);
  await move('fleet');
  assert.equal(refreshCalls,1,'parallel membership reads must share one real refresh');
  await page.unroute(passwordGrant);
  assert.deepEqual(await page.evaluate(()=>[localStorage.length,sessionStorage.length]),[0,0]);

  // Local logout must leave another session of the same account usable.
  const otherResponse=await fetch(api+'/auth/v1/token?grant_type=password',{
   method:'POST',headers:{apikey:key,'content-type':'application/json'},
   body:JSON.stringify({email:fixture.roles.fleet.email,password:pwd})});
  assert.equal(otherResponse.ok,true);
  const other=await otherResponse.json();
  const loggedOut=page.waitForResponse(r=>r.url().endsWith('/auth/v1/logout?scope=local'));
  await page.locator('#logoutButton').click();
  assert.equal((await loggedOut).status(),204);
  await page.locator('#loginForm:visible').waitFor();
  const otherRefresh=await fetch(api+'/auth/v1/token?grant_type=refresh_token',{
   method:'POST',headers:{apikey:key,'content-type':'application/json'},
   body:JSON.stringify({refresh_token:other.refresh_token})});
  assert.equal(otherRefresh.ok,true,'logout revoked a different device session');

  // Rejected refresh must clear panels/controls and stop, without a loop.
  await page.route(passwordGrant,nearExpiry);
  await page.route(refreshGrant,route=>route.fulfill({status:400,
   contentType:'application/json',body:JSON.stringify({error_code:'refresh_token_not_found'})}));
  await page.locator('#loginEmail').fill(fixture.roles.fleet.email);
  await page.locator('#loginPassword').fill(pwd);
  await page.locator('#signInButton').click();
  await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('Sesja wygasła'));
  assert.equal(await page.locator('.panel.active').count(),0);
  assert.equal(await page.locator('[data-act]:not([disabled])').count(),0);
  assert.equal(refreshCalls,2,'failed refresh was retried');
  await page.unroute(passwordGrant);
  await page.unroute(refreshGrant);

  // An unauthorized write is never replayed after refreshing credentials.
  const guestResponse=await fetch(api+'/auth/v1/signup',{
   method:'POST',headers:{apikey:key,'content-type':'application/json'},
   body:JSON.stringify({email:'lifecycle-'+platform+'-'+Date.now()+'@example.test',password:pwd})});
  assert.equal(guestResponse.ok,true);
  const guest=await guestResponse.json();
  await page.locator('[data-role="customer"]').click();
  await page.locator('#loginEmail').fill(guest.user.email);
  await page.locator('#loginPassword').fill(pwd);
  await page.locator('#signInButton').click();
  await page.locator('#customer.panel.active').waitFor();
  let writes=0;
  const bookingRpc='**/rest/v1/rpc/garage_booking_request';
  await page.route(bookingRpc,route=>{writes++;return route.fulfill({status:401,
   contentType:'application/json',body:JSON.stringify({message:'Synthetic revoked session'})})});
  await page.locator('[data-act="request"]:not([disabled])').click();
  await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('Sesja wygasła'));
  assert.equal(writes,1,'unauthorized booking mutation was retried');
  assert.equal(refreshCalls,2,'401 mutation triggered an unsafe replay refresh');
  assert.equal(await page.locator('.panel.active').count(),0);
  assert.equal(await page.locator('[data-act]:not([disabled])').count(),0);
  assert.equal(await page.locator('#history li').count(),0);
  assert.equal(await page.locator('#jobs li').count(),0);
  await page.unroute(bookingRpc);

  // A browser pagehide clears a pending caller. Its late response must not
  // reopen old Fleet views or overwrite a newly logged-in customer account.
  let release,seen,finished;
  const delayed=new Promise(resolve=>{release=resolve});
  const reached=new Promise(resolve=>{seen=resolve});
  const handled=new Promise(resolve=>{finished=resolve});
  const fleetRead='**/rest/v1/rpc/garage_fleet_requests_for_me';
  await page.route(fleetRead,async route=>{
   const response=await route.fetch();seen();await delayed;await route.fulfill({response});finished();
  });
  await page.locator('[data-role="fleet"]').click();
  await page.locator('#loginEmail').fill(fixture.roles.fleet.email);
  await page.locator('#loginPassword').fill(pwd);
  await page.locator('#signInButton').click();
  await reached;
  await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true})));
  assert.equal(await page.locator('.panel.active').count(),0);
  await move('customer');
  const lateResponse=page.waitForResponse(r=>r.url().endsWith('/rpc/garage_fleet_requests_for_me'));
  release();
  await handled;
  await (await lateResponse).finished();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(resolve)));
  await page.unroute(fleetRead);
  await page.waitForFunction(()=>!document.querySelector('#logoutButton').disabled);
  assert.equal(await page.locator('#customer.panel.active').count(),1);
  assert.equal(await page.locator('#fleet.panel.active').count(),0);
  assert.match(await page.locator('#accountRole').textContent(),/^Dostęp konta: customer/);
  await page.locator('#logoutButton').click();
  await page.locator('#loginForm:visible').waitFor();
  assert.deepEqual(await page.evaluate(()=>[localStorage.length,sessionStorage.length]),[0,0]);
  // Navigating away during the password grant must also invalidate that
  // attempt, before any caller object has been created in the application.
  let releaseLogin,sawLogin,finishedLogin;
  const loginGate=new Promise(resolve=>{releaseLogin=resolve});
  const loginReached=new Promise(resolve=>{sawLogin=resolve});
  const loginHandled=new Promise(resolve=>{finishedLogin=resolve});
  await page.route(passwordGrant,async route=>{
   const response=await route.fetch();sawLogin();await loginGate;
   await route.fulfill({response});finishedLogin();
  });
  await page.locator('#loginEmail').fill(fixture.roles.customer.email);
  await page.locator('#loginPassword').fill(pwd);
  await page.locator('#signInButton').click();
  await loginReached;
  await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true})));
  const lateLogin=page.waitForResponse(r=>r.url().includes('grant_type=password'));
  releaseLogin();await loginHandled;await (await lateLogin).finished();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(resolve)));
  await page.unroute(passwordGrant);
  assert.equal(await page.locator('#accountInfo:visible').count(),0);
  assert.equal(await page.locator('.panel.active').count(),0);
  assert.equal(await page.locator('#signInButton:disabled').count(),0);
  console.log('PASS '+name+' session lifecycle: one real refresh, local-only logout, failed refresh closed, 401 write not replayed, stale pagehide response ignored');
  assert.deepEqual(errs,[]);
  assert.deepEqual(external,[]);
  console.log('PASS '+name+' real local Auth: four sequential accounts, Fleet↔Garage approval, mechanic, private booking, no shared session');
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
}
for(const [name,engine,profile,platform] of [
 ['Android Chrome (emulated Pixel 5)',chromium,'Pixel 5','android'],
 ['iPhone Safari (emulated iPhone 13)',webkit,'iPhone 13','ios']])
 await runBrowser(name,engine,profile,platform);
console.log('PASS: actual connected multi-role flow using only one authenticated browser user at once');
