// Local-only browser acceptance against disposable Supabase Auth/PostgREST.
// No hosted Supabase, production data, Stripe, credentials in code or screenshots.
import assert from 'node:assert/strict';
import {readFileSync, mkdirSync} from 'node:fs';
import {createServer} from 'node:http';
import {randomUUID} from 'node:crypto';
import {chromium,webkit} from 'playwright';

const api=process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const anon=process.env.GARAGE_TEST_ANON_KEY;
if(!api||!anon||!/^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/.test(api))
 throw Error('Refusing any Supabase other than disposable loopback HTTP');
const html=readFileSync(new URL('../web/demo/session/index.html',import.meta.url),'utf8');
assert.match(html,/<meta name="robots" content="noindex,nofollow"/);
assert.doesNotMatch(html,/supabase\.co|stripe\.com|localStorage\s*\.|sessionStorage\s*\./);
for(const name of ['fleet','garage','mechanic','customer'])
 assert.match(html,new RegExp('id="'+name+'" class="panel'));

async function http(path,actor,body,method='POST',prefer){
 const headers={apikey:anon,authorization:'Bearer '+(actor?.jwt||anon),accept:'application/json'};
 if(body!==undefined)headers['content-type']='application/json';
 if(prefer)headers.prefer=prefer;
 const res=await fetch(api+path,{
  method,headers,body:body===undefined?undefined:JSON.stringify(body)
 });
 const raw=await res.text();let data;
 try{data=raw?JSON.parse(raw):null}catch{data=raw}
 return {ok:res.ok,status:res.status,data};
}
const rpc=(actor,fn,body={})=>http('/rest/v1/rpc/'+fn,actor,body);
function valid(res,context){
 assert.equal(res.ok,true,context+' HTTP '+res.status+' '+JSON.stringify(res.data).slice(0,250));
 return res.data;
}
async function signup(role){
 const email='connected-'+role+'-'+randomUUID()+'@example.test';
 const s=valid(await http('/auth/v1/signup',null,
  {email,password:'LocalBrowserQA2026!Disposable'}),'signup '+role);
 assert.ok(s.access_token);
 return {id:s.user.id,email,jwt:s.access_token};
}
async function createFixture(){
 const fleet=await signup('fleet');
 const garage=await signup('garage');
 const mechanic=await signup('mechanic');
 const customer=await signup('customer');
 const sh=valid(await http('/rest/v1/garage_workspaces?select=id',garage,
  {owner_user_id:garage.id,name:'Local Connected Garage',country:'GB',currency:'GBP'},
  'POST','return=representation'),'create garage')[0].id;
 valid(await rpc(garage,'garage_booking_configure',{
  p_workspace:sh,p_city:'Dunstable',p_time_zone:'Europe/London',
  p_services:['brakes'],p_duration:60,p_listed:true
 }),'configure booking');
 for(let day=1;day<=7;day++)
  valid(await rpc(garage,'garage_booking_set_hours',{
   p_shop:sh,p_day:day,p_opens:'08:00:00',p_closes:'18:00:00',p_enabled:true
  }),'set hours');
 const token=valid(await rpc(garage,'garage_issue_staff_invite',{
  p_workspace_id:sh,p_email:mechanic.email,p_role:'mechanic'
 }),'invite mechanic');
 valid(await rpc(mechanic,'garage_accept_staff_invite',{p_token:token}),'join garage');
 const bay=valid(await rpc(garage,'garage_booking_add_resource',{
  p_shop:sh,p_label:'Brake inspection bay',p_mechanic:mechanic.id
 }),'add workshop bay');
 const company=valid(await rpc(fleet,'repairbridge_test_create_fleet',{
  p_registration:'QA-FLEET-001',p_title:'Brake failure test'
 }),'create disposable fleet');
 valid(await rpc(fleet,'garage_fleet_request_connection',{
  p_company:company.company_id,p_shop:sh
 }),'request Fleet↔Garage consent');
 valid(await rpc(garage,'garage_fleet_accept_connection',{
  p_company:company.company_id,p_shop:sh
 }),'grant Fleet↔Garage consent');
 return {api,anon,shop:sh,bay,company:company.company_id,issue:company.issue_id,
  roles:{fleet,garage,mechanic,customer}};
}

async function serve(fixture) {
 const safe={api:fixture.api,anon:fixture.anon,shop:fixture.shop,
   bay:fixture.bay,company:fixture.company,issue:fixture.issue,
   mechanicUserId:fixture.roles.mechanic.id};
 const config='window.__FLOTARYX_SINGLE_SESSION_QA__='+JSON.stringify(safe)+';';
 assert.ok(!config.includes(fixture.roles.fleet.jwt),'Fleet JWT in config');
 assert.ok(!config.includes(fixture.roles.garage.jwt),'Garage JWT in config');
 assert.ok(!config.includes(fixture.roles.mechanic.jwt),'Mechanic JWT in config');
 assert.ok(!config.includes(fixture.roles.customer.jwt),'Customer JWT in config');
 assert.ok(!/["']roles["']\s*:/.test(config),'Shared JWT role map detected');
 const server=createServer((req,res)=>{
  const host=req.headers.host||'';
  if(!/^127\.0\.0\.1:\d+$/.test(host)){res.writeHead(403);res.end();return}
  const headers={'cache-control':'no-store','x-content-type-options':'nosniff',
    'cross-origin-resource-policy':'same-origin','referrer-policy':'no-referrer'};
  if(req.url==='/session-config.js'){
   const site=req.headers['sec-fetch-site'];
   if(site&&site!=='same-origin'){res.writeHead(403);res.end();return}
   res.writeHead(200,{...headers,'content-type':'application/javascript; charset=utf-8'});
   res.end(config);
  }else if(req.url==='/'||req.url==='/index.html'){
   res.writeHead(200,{...headers,'content-type':'text/html; charset=utf-8',
    'content-security-policy':"default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; connect-src "+api+"; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"});
   res.end(html);
  }else{res.writeHead(404);res.end();}
 });
 await new Promise((ok,fail)=>server.once('error',fail).listen(0,'127.0.0.1',ok));
 return {server,url:'http://127.0.0.1:'+server.address().port+'/index.html'};
}
async function checkBrowser(browserType,label){
 const fixture=await createFixture();
 const {server,url}=await serve(fixture);
 const bad=await fetch(url.replace('/index.html','/session-config.js'),
  {headers:{'sec-fetch-site':'cross-site'}});
 assert.equal(bad.status,403,'cross-site JS fetch blocked');
 const browser=await browserType.launch({headless:true});
 const context=await browser.newContext({viewport:{width:390,height:844},
  isMobile:true,hasTouch:true,deviceScaleFactor:2});
 const page=await context.newPage();
 const errors=[],external=[],consoleSecrets=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('request',r=>{
  const origin=new URL(r.url());
  if(!['127.0.0.1','localhost'].includes(origin.hostname))
   external.push(origin.origin);
 });
 page.on('console',msg=>{
  if(msg.type()==='error')consoleSecrets.push(msg.text());
 });
 async function choose(role){
  await page.locator('[data-role="'+role+'"]').click();
  await page.waitForFunction(r=>document.querySelector(
   '[data-role="'+r+'"]').getAttribute('aria-current')==='page',role);
 }
 async function login(role){
  await choose(role);
  await page.locator('#loginEmail').fill(fixture.roles[role].email);
  await page.locator('#loginPassword').fill('LocalBrowserQA2026!Disposable');
  await page.locator('#signInButton').click();
  await page.locator('#accountInfo:not([hidden])').waitFor();
  await page.locator('#'+role+'.panel.active').waitFor();
  assert.equal(await page.locator('#accountRole').innerText(),
   'Dostęp konta: '+role+' — uprawnienia z członkostwa');
 }
 async function logout(){
  await page.locator('#logoutButton').click();
  await page.locator('#loginForm:not([hidden])').waitFor();
  assert.equal(await page.locator('#accountEmail').innerText(),'');
  assert.equal(await page.locator('.panel.active').count(),0,'private role panel remains visible');
 }
 async function action(name,expected){
  await page.locator('[data-act="'+name+'"]:not([disabled])').click();
  await page.waitForFunction(v=>
   document.querySelector('#notice').textContent.includes('API potwierdziło operację: '+v),
   name,{timeout:12000});
  if(expected)
   await page.waitForFunction(v=>
    document.querySelector('#fleetState').textContent===v,expected);
 }
 try{
  await page.goto(url);
  await page.locator('#loginForm:not([hidden])').waitFor();
  assert.equal(await page.locator('.panel.active').count(),0);
  assert.equal(await page.locator('script[src="/qa-config.js"]').count(),0);
  assert.equal(await page.locator('script[src="/session-config.js"]').count(),1);
  assert.equal(await page.evaluate(()=>
   Object.keys(window.__FLOTARYX_SINGLE_SESSION_QA__).includes('roles')),false);
  await login('fleet');
  // Changing the displayed tab NEVER changes Auth identity or grants another role.
  await choose('garage');
  assert.equal(await page.locator('.panel.active').count(),0);
  assert.equal(await page.locator('[data-act="quote"]').isDisabled(),true);
  await choose('fleet');
  await action('send','Wysłana');
  await logout();

  await login('garage');
  await page.waitForFunction(()=>document.querySelector('#garageState').textContent==='Wysłana');
  await action('accept','Przyjęta');
  await action('quote','Kosztorys');
  await logout();

  await login('fleet');
  await page.waitForFunction(()=>document.querySelector('#estimate').textContent.includes('£108.00'));
  await action('approve','Zatwierdzona');
  await logout();

  await login('mechanic');
  await page.locator('#jobs li').first().waitFor();
  await action('start','Naprawa trwa');
  await logout();

  await login('garage');
  await action('ready','Gotowa');
  await logout();

  await login('customer');
  await action('request');
  await page.waitForFunction(()=>
   document.querySelector('#customerState').textContent==='requested');
  await logout();

  await login('garage');
  await page.waitForFunction(()=>
   document.querySelector('#garageBooking').textContent==='requested');
  await action('confirm');
  await logout();

  await login('customer');
  await page.waitForFunction(()=>
   document.querySelector('#customerState').textContent==='confirmed');
  await logout();

  const runtime=await page.evaluate(()=>({
   localKeys:Object.keys(localStorage),
   sessionKeys:Object.keys(sessionStorage),
   width:document.documentElement.scrollWidth,viewport:innerWidth
  }));
  assert.deepEqual(runtime.localKeys,[],'stored local session');
  assert.deepEqual(runtime.sessionKeys,[],'stored browser session');
  assert.ok(runtime.width<=runtime.viewport+2,'mobile horizontal overflow');
  assert.deepEqual(external,[],'test contacted remote network');
  assert.deepEqual(errors,[],'browser JavaScript errors');
  console.log('PASS '+label+' real Supabase four separately authenticated accounts, role isolation, logouts, repairs and booking');
 }finally{
  await browser.close();await new Promise(resolve=>server.close(resolve));
 }
}
for(const [name,engine] of [['Chromium',chromium],['WebKit',webkit]])
 await checkBrowser(engine,name);
console.log('PASS connected single-session Flotaryx QA on disposable localhost only');
