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
const html=readFileSync(new URL('../web/demo/connected/index.html',import.meta.url),'utf8');
assert.match(html,/<meta name="robots" content="noindex,nofollow"/);
assert.doesNotMatch(html,/supabase\.co|stripe\.com|localStorage|sessionStorage/);
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
 const config='window.__FLOTARYX_LOCAL_QA__='+JSON.stringify(fixture)+';';
 const server=createServer((req,res)=>{
  const host=req.headers.host||'';
  if(!/^127\.0\.0\.1:\d+$/.test(host)){res.writeHead(403);res.end();return;}
  if(req.url==='/qa-config.js'){
   // Cross-origin <script> tags otherwise reveal bearer tokens even without CORS!
   const site=req.headers['sec-fetch-site'];
   if(site&&site!=='same-origin'){res.writeHead(403);res.end();return;}
   res.writeHead(200,{'content-type':'application/javascript; charset=utf-8',
    'cache-control':'no-store','x-content-type-options':'nosniff',
    'cross-origin-resource-policy':'same-origin',
    'referrer-policy':'no-referrer'});
   res.end(config);
  }else if(req.url==='/'||req.url==='/index.html'){
   res.writeHead(200,{'content-type':'text/html; charset=utf-8',
    'cache-control':'no-store','x-content-type-options':'nosniff',
    'referrer-policy':'no-referrer',
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
 // A simulated third-party origin must not be given token-bearing JS.
 const malicious=await fetch(url.replace('/index.html','/qa-config.js'),{
  headers:{'sec-fetch-site':'cross-site'}
 });
 assert.equal(malicious.status,403,'no cross-site token-bearing script');
 const browser=await browserType.launch({headless:true});
 const ctx=await browser.newContext({
  viewport:{width:390,height:844},isMobile:true,
  hasTouch:true,deviceScaleFactor:2
 });
 const page=await ctx.newPage();
 const errors=[],unexpected=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('request',r=>{
  const u=new URL(r.url());
  if(!['127.0.0.1','localhost'].includes(u.hostname))unexpected.push(u.origin);
 });
 const role=async(r)=>{
  await page.locator('[data-role="'+r+'"]').click();
  await page.locator('#'+r+'.active').waitFor();
 };
 const click=async(act,next)=>{
  await page.locator('[data-act="'+act+'"]:not([disabled])').click();
  await page.waitForFunction(expected=>document.querySelector('#notice').textContent.includes(expected),act);
  if(next)await page.waitForFunction(expected=>document.querySelector('#fleetState').textContent===expected,next);
 };
 try{
  await page.goto(url);
  await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('Połączono'));
  await role('fleet');
  await click('send','Wysłana');
  await role('garage');
  await click('accept','Przyjęta');
  await click('quote','Kosztorys');
  await role('fleet');
  await page.waitForFunction(()=>document.querySelector('#estimate').textContent.includes('£108.00'));
  await click('approve','Zatwierdzona');
  await role('mechanic');
  await click('start','Naprawa trwa');
  await role('garage');
  await click('ready','Gotowa');
  await role('fleet');
  await page.waitForFunction(()=>document.querySelectorAll('#history li').length===4);
  assert.equal(await page.locator('#approval').innerText(),'Zatwierdzony');
  await role('customer');
  await click('request');
  await page.waitForFunction(()=>document.querySelector('#customerState').textContent==='requested');
  await role('garage');
  await click('confirm');
  await role('customer');
  await page.waitForFunction(()=>document.querySelector('#customerState').textContent==='confirmed');
  await role('mechanic');
  await page.waitForFunction(()=>document.querySelectorAll('#jobs li').length===2);
  const size=await page.evaluate(()=>({page:document.documentElement.scrollWidth,window:innerWidth}));
  assert.ok(size.page<=size.window+2,'horizontal overflow '+JSON.stringify(size));
  assert.deepEqual(errors,[],label+' JS errors');
  assert.deepEqual(unexpected,[],label+' unexpectedly contacted remote network');
  if(label==='WebKit'){
   // Actual API-backed browser results with *synthetic* records only.
   // Screenshots do not include the token-bearing config script or network logs.
   const dir='artifacts/connected-iphone-qa';
   mkdirSync(dir,{recursive:true});
   for(const [roleName,index] of [['fleet','01'],['garage','02'],
                                  ['mechanic','03'],['customer','04']]){
    await role(roleName);
    await page.screenshot({
     path:dir+'/'+index+'-'+roleName+'-connected.png',fullPage:true,
     animations:'disabled'
    });
   }
   console.log('PASS WebKit: captured four real API-connected fictional iPhone screens');
  }
  console.log('PASS '+label+' real localhost Supabase, 4 roles, quote approval, repair history, consumer booking, RLS');
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
}
for(const [name,engine] of [['Chromium',chromium],['WebKit',webkit]])await checkBrowser(engine,name);
console.log('PASS all connected Flotaryx QA browser tests (disposable localhost only)');
