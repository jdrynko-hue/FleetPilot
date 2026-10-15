// Disposable local Auth + browser: no shared JWTs and no external hosts.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {chromium,webkit} from 'playwright';
const api=process.env.SINGLE_SESSION_API_URL?.replace(/\/$/,'');
const key=process.env.SINGLE_SESSION_ANON_KEY;
if(!api||!key||!/^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(api))
 throw Error('Refuse any non-local Supabase');
const html=readFileSync('web/demo/session/index.html','utf8');
const password='TemporaryLocalOnly2026!';
async function register(role){
 const email='single-session-'+role+'-'+randomUUID()+'@example.test';
 const res=await fetch(api+'/auth/v1/signup',{
  method:'POST',headers:{apikey:key,'content-type':'application/json'},
  body:JSON.stringify({email,password})
 });
 const data=await res.json();
 assert.ok(res.ok&&data.access_token,'local Auth registration failed');
 return {email};
}
const accounts={};
for(const role of ['fleet','garage','mechanic','customer'])
 accounts[role]=await register(role);
const empty='00000000-0000-4000-8000-000000000001';
const config={api,anon:key,company:empty,issue:empty,
 shop:empty,bay:empty,mechanicUserId:empty};
const js='window.__FLOTARYX_SINGLE_SESSION_QA__='+JSON.stringify(config)+';';
assert.ok(!js.includes('access_token')&&!js.includes('password'));
const server=createServer((req,res)=>{
 if(!/^127\.0\.0\.1:\d+$/.test(req.headers.host||'')){
  res.writeHead(403);res.end();return;
 }
 if(req.url==='/session-config.js'){
  if(req.headers['sec-fetch-site']==='cross-site'){
   res.writeHead(403);res.end();return;
  }
  res.writeHead(200,{'content-type':'application/javascript',
   'cache-control':'no-store','x-content-type-options':'nosniff',
   'cross-origin-resource-policy':'same-origin'});
  res.end(js);return;
 }
 if(req.url==='/'||req.url==='/index.html'){
  res.writeHead(200,{'content-type':'text/html','cache-control':'no-store',
   'content-security-policy':"default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; connect-src "+api+"; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"});
  res.end(html);return;
 }
 res.writeHead(404);res.end();
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url='http://127.0.0.1:'+server.address().port+'/index.html';
try{
 const denied=await fetch(url.replace('/index.html','/session-config.js'),{
  headers:{'sec-fetch-site':'cross-site'}});
 assert.equal(denied.status,403);
 for(const [name,type] of [['Chromium',chromium],['WebKit',webkit]]){
  const browser=await type.launch();
  try{
   const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
   const page=await context.newPage(),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.goto(url);
   assert.equal(await page.locator('.panel.active').count(),0);
   for(const role of ['fleet','garage','mechanic','customer']){
    await page.locator('[data-role="'+role+'"]').click();
    await page.locator('#loginEmail').fill(accounts[role].email);
    await page.locator('#loginPassword').fill(password);
    await page.locator('#signInButton').click();
    // Auth-only local stack has no role-capability RPC or role membership.
    // Authentication alone must NEVER unlock any Fleet/Garage panel.
    await page.waitForFunction(()=>
      document.querySelector('#loginError').textContent.length>0);
    assert.equal(await page.locator('#accountInfo:visible').count(),0);
    assert.equal(await page.locator('#loginForm:visible').count(),1);
    assert.equal(await page.locator('.panel.active').count(),0);
    assert.equal(await page.locator('[data-act]:not([disabled])').count(),0);
    const storage=await page.evaluate(()=>[localStorage.length,sessionStorage.length]);
    assert.deepEqual(storage,[0,0]);
   }
   assert.deepEqual(errors,[],name+' browser errors');
   console.log('PASS '+name+': valid Auth without verified membership cannot unlock any role, zero bearer persistence');
  }finally{await browser.close();}
 }
}finally{await new Promise(resolve=>server.close(resolve));}
