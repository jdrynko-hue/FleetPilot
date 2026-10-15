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
assert.doesNotMatch(html,/supabase\.co|stripe\.com|localStorage|sessionStorage/);
for(const name of ['fleet','garage','mechanic','customer'])
 assert.match(html,new RegExp('id="'+name+'" class="panel'));
assert.match(html,/__FLOTARYX_SINGLE_SESSION_QA__/);
assert.doesNotMatch(html,/__FLOTARYX_LOCAL_QA__|localStorage|sessionStorage\s*\[|window\.open\(/);

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
 const {api,anon,shop,bay,company,issue}=fixture;
 // Never place actor credentials or password in the served configuration.
 const config='window.__FLOTARYX_SINGLE_SESSION_QA__='+JSON.stringify({
  api,anon,shop,bay,company,issue,mechanicUserId:fixture.roles.mechanic.id
 })+';';
 for(const actor of Object.values(fixture.roles))
   assert.ok(!config.includes(actor.jwt),'A role JWT reached public config');
 const server=createServer((req,res)=>{
  if(!/^127\.0\.0\.1:\d+$/.test(req.headers.host||'')){res.writeHead(403);res.end();return;}
  const common={
   'cache-control':'no-store','x-content-type-options':'nosniff',
   'referrer-policy':'no-referrer','cross-origin-resource-policy':'same-origin'
  };
  if(req.url==='/session-config.js'){
   if(req.headers['sec-fetch-site'] &&
      req.headers['sec-fetch-site']!=='same-origin'){
     res.writeHead(403);res.end();return;
   }
   res.writeHead(200,{'content-type':'application/javascript; charset=utf-8',...common});
   res.end(config);
  }else if(req.url==='/'||req.url==='/index.html'){
   res.writeHead(200,{
    'content-type':'text/html; charset=utf-8',
    'content-security-policy':"default-src 'none'; script-src 'self' 'unsafe-inline'; "+
       "style-src 'unsafe-inline'; connect-src "+api+"; "+
       "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    ...common
   });res.end(html);
  }else{res.writeHead(404);res.end();}
 });
 await new Promise((ok,fail)=>server.once('error',fail).listen(0,'127.0.0.1',ok));
 return {server,url:'http://127.0.0.1:'+server.address().port+'/index.html'};
}
async function checkBrowser(browserType,label){
 const fixture=await createFixture();
 const {server,url}=await serve(fixture);
 const configUrl=url.replace('/index.html','/session-config.js');
 const publicConfig=await (await fetch(configUrl)).text();
 assert.ok(publicConfig.includes('mechanicUserId'));
 for(const actor of Object.values(fixture.roles)){
  assert.ok(!publicConfig.includes(actor.jwt));
  assert.ok(!publicConfig.includes(actor.email));
 }
 const cross=await fetch(configUrl,{headers:{'sec-fetch-site':'cross-site'}});
 assert.equal(cross.status,403,'third parties must not load local JS configuration');
 const browser=await browserType.launch({headless:true});
 const ctx=await browser.newContext({
  viewport:{width:390,height:844},isMobile:true,hasTouch:true,deviceScaleFactor:2
 });
 const page=await ctx.newPage();
 const errors=[],unexpected=[],popups=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('popup',p=>popups.push(p.url()));
 page.on('request',r=>{
  const u=new URL(r.url());
  if(!['127.0.0.1','localhost'].includes(u.hostname))unexpected.push(u.origin);
 });
 const role=async(r)=>{
  await page.locator('[data-role="'+r+'"]').click();
  await page.waitForFunction(x=>location.hash==='#'+x,r);
 };
 const login=async(r)=>{
  await role(r);
  const a=fixture.roles[r];
  await page.locator('#loginEmail').fill(a.email);
  await page.locator('#loginPassword').fill('LocalBrowserQA2026!Disposable');
  await page.locator('#signInButton').click();
  await page.waitForFunction(()=>document.querySelector('#accountInfo').hidden===false);
  await page.locator('#'+r+'.panel.active').waitFor();
  const tokenLeak=await page.evaluate(()=>({
    localStorage:localStorage.length,
    sessionStorage:sessionStorage.length,
    cookies:document.cookie,
    password:document.getElementById('loginPassword').value
  }));
  assert.deepEqual(tokenLeak,{localStorage:0,sessionStorage:0,cookies:'',password:''},
   'Single-session browser must not persist credentials');
 };
 const logout=async()=>{
  await page.locator('#logoutButton').click();
  await page.waitForFunction(()=>document.querySelector('#accountInfo').hidden===true);
  assert.equal(await page.locator('.panel.active').count(),0,'No active module after logout');
  const disabled=await page.locator('[data-act]:not([disabled])').count();
  assert.equal(disabled,0,'No operations available after logout');
 };
 const click=async(act,next)=>{
  await page.locator('[data-act="'+act+'"]:not([disabled])').click();
  await page.waitForFunction(expected=>
    document.querySelector('#notice').textContent.includes(expected),
    'API potwierdziło operację: '+act);
  if(next)await page.waitForFunction(expected=>
    document.querySelector('#fleetState').textContent===expected,next);
 };
 async function screenshot(roleName,index){
  if(label!=='WebKit')return;
  const path='artifacts/session-iphone-qa';
  mkdirSync(path,{recursive:true});
  await page.screenshot({path:path+'/'+index+'-'+roleName+'.png',
    fullPage:true,animations:'disabled'});
 }
 try{
  await page.goto(url);
  await page.locator('#loginForm').waitFor();
  assert.equal(await page.locator('[data-act]:not([disabled])').count(),0);
  assert.equal(await page.locator('.panel.active').count(),0);
  await login('fleet');
  await role('garage');
  assert.equal(await page.locator('#garage.panel.active').count(),0,
   'Role switch without fresh account authentication forbidden');
  await page.locator('#roleLock').getByText(/Wyloguj się/).waitFor();
  await role('fleet');
  await click('send','Wysłana');await logout();
  await login('garage');
  await click('accept','Przyjęta');
  await click('quote','Kosztorys');await logout();
  await login('fleet');
  await page.waitForFunction(()=>
   document.querySelector('#estimate').textContent.includes('£108.00'));
  await click('approve','Zatwierdzona');await logout();
  await login('mechanic');
  await click('start','Naprawa trwa');await logout();
  await login('garage');
  await click('ready','Gotowa');await logout();
  await login('fleet');
  await page.waitForFunction(()=>
   document.querySelectorAll('#history li').length>=4);
  assert.equal(await page.locator('#approval').innerText(),'Zatwierdzony');
  await screenshot('fleet','01');await logout();
  await login('customer');
  await click('request');await logout();
  await login('garage');
  await click('confirm');
  await screenshot('garage','02');await logout();
  await login('customer');
  await page.waitForFunction(()=>
   document.querySelector('#customerState').textContent==='confirmed');
  await screenshot('customer','04');await logout();
  await login('mechanic');
  await page.waitForFunction(()=>
   document.querySelectorAll('#jobs li').length>=2);
  await screenshot('mechanic','03');await logout();
  const sizing=await page.evaluate(()=>({
   documentWidth:document.documentElement.scrollWidth,windowWidth:innerWidth}));
  assert.ok(sizing.documentWidth<=sizing.windowWidth+2,
    'iPhone viewport horizontal overflow');
  await page.reload();
  assert.equal(await page.locator('#accountInfo').isHidden(),true);
  assert.equal(await page.locator('.panel.active').count(),0);
  assert.deepEqual(errors,[],label+' JS errors');
  assert.deepEqual(unexpected,[],label+' unwanted remote calls');
  assert.deepEqual(popups,[],label+' unexpected browser popups');
  console.log('PASS '+label+
   ': distinct single-account GoTrue login, no shared JWT, 4 actual API-backed roles, no client storage');
 }finally{
  await browser.close();
  await new Promise(resolve=>server.close(resolve));
 }
}
for(const [name,engine] of [['Chromium',chromium],['WebKit',webkit]])
 await checkBrowser(engine,name);
console.log('PASS isolated single-session staging UI; no hosted QA, no paid services');
