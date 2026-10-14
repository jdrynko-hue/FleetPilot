// Genuine local-only Supabase Auth + PostgREST + private Storage E2E.
// No hosted project URLs, service keys, Stripe or real customer records.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const root=process.env.FLEET_STORAGE_TEST_API_URL?.replace(/\/$/,'');
const anon=process.env.FLEET_STORAGE_TEST_ANON_KEY;
if(!root||!anon||!/^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/.test(root))
  throw Error('Refusing non-loopback API; require disposable local Supabase');

async function call(path,{jwt,method='GET',body,mime,prefer,headers={}}={}){
  const h={apikey:anon,authorization:'Bearer '+(jwt??anon),accept:'application/json',...headers};
  if(mime)h['content-type']=mime;
  if(prefer)h.prefer=prefer;
  const r=await fetch(root+path,{method,headers:h,body:body===undefined?undefined:
    (Buffer.isBuffer(body)||typeof body==='string'?body:JSON.stringify(body))});
  let raw=await r.text(),value=raw;
  try{value=raw?JSON.parse(raw):null}catch{}
  return {ok:r.ok,status:r.status,value};
}
function pass(r,what){
 assert.equal(r.ok,true,what+' HTTP '+r.status+' '+JSON.stringify(r.value).slice(0,300));
 return r.value;
}
function deny(r,what){
 assert.equal(r.ok,false,what+' was allowed');
 assert.ok([400,401,403,404,409,413,415,422].includes(r.status),what+' HTTP '+r.status);
}
async function signup(label){
 const x=pass(await call('/auth/v1/signup',{method:'POST',mime:'application/json',
 body:{email:'fleet-storage-'+label+'-'+randomUUID()+'@example.test',
 password:'Disposable-QA-2026-Only!pass'}}),'signup '+label);
 assert.ok(x.user?.id&&x.access_token,'Local GoTrue must issue JWT');
 return {id:x.user.id,jwt:x.access_token};
}
async function insert(u,table,data){
 const x=pass(await call('/rest/v1/'+table+'?select=*',{jwt:u.jwt,method:'POST',
 mime:'application/json',prefer:'return=representation',body:data}),'insert '+table);
 assert.equal(x.length,1);return x[0];
}
async function fleet(u,title){
 const x=pass(await call('/rest/v1/rpc/create_company_for_current_user',{jwt:u.jwt,
 method:'POST',mime:'application/json',body:{_name:title,_country:'GB',_currency:'GBP'}}),
 'create Fleet '+title);
 assert.match(x,/^[a-f\d-]{36}$/i);return x;
}
const bucket='fleetpilot-documents';
const s=(u,path,opts)=>call('/storage/v1/'+path,{jwt:u?.jwt,...opts});
const upload=(u,path,bytes=Buffer.from('%PDF-1.4\n%%EOF\n'),mime='application/pdf',headers)=>
 s(u,'object/'+bucket+'/'+path,{method:'POST',body:bytes,mime,headers});
const download=(u,path,pub=false)=>s(u,'object/'+(pub?'public/':'authenticated/')+bucket+'/'+path,{});
const sign=(u,path)=>s(u,'object/sign/'+bucket+'/'+path,{
 method:'POST',mime:'application/json',body:{expiresIn:120}});
const list=(u,prefix)=>s(u,'object/list/'+bucket,{
 method:'POST',mime:'application/json',body:{prefix,limit:100,offset:0}});
const remove=(u,path)=>s(u,'object/'+bucket,{
 method:'DELETE',mime:'application/json',body:{prefixes:[path]}});
const file=(company,vehicle,extension='pdf')=>company+'/'+vehicle+'/'+
 String(Date.now()*1000+Math.floor(Math.random()*1000))+'.'+extension;

const a=await signup('owner-a'),b=await signup('owner-b');
const viewer=await signup('viewer-a'),outsider=await signup('outsider');
const ca=await fleet(a,'Disposable Fleet A'),cb=await fleet(b,'Disposable Fleet B');
const va=await insert(a,'vehicles',{company_id:ca,registration:'QA-A-'+randomUUID()});
const vb=await insert(b,'vehicles',{company_id:cb,registration:'QA-B-'+randomUUID()});
await insert(a,'company_members',{company_id:ca,user_id:viewer.id,role:'viewer'});
const pa=file(ca,va.id),pb=file(cb,vb.id);
const pdf=Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\n%%EOF\n');
pass(await upload(a,pa,pdf),'A uploads own PDF');
pass(await upload(b,pb,pdf),'B uploads own PDF');
const da=await insert(a,'fleet_documents',{company_id:ca,vehicle_id:va.id,
 title:'Synthetic MOT',category:'mot',original_filename:'test.pdf',
 mime_type:'application/pdf',size_bytes:pdf.length,storage_path:pa});
await insert(b,'fleet_documents',{company_id:cb,vehicle_id:vb.id,
 title:'Synthetic B doc',category:'mot',original_filename:'test.pdf',
 mime_type:'application/pdf',size_bytes:pdf.length,storage_path:pb});

pass(await download(a,pa),'A downloads A');
pass(await download(b,pb),'B downloads B');
pass(await download(viewer,pa),'viewer downloads A');
deny(await download(b,pa),'B cannot download A');
deny(await download(a,pb),'A cannot download B');
deny(await download(outsider,pa),'outsider cannot download');
deny(await download(null,pa),'anon cannot download');
deny(await download(null,pa,true),'no public object URL');
const signed=pass(await sign(viewer,pa),'viewer signs 120s URL');
assert.ok(signed.signedURL||signed.signedUrl,'Expected signed Storage URL');
const relativeSign=String(signed.signedURL||signed.signedUrl);
const resolvedSign=relativeSign.startsWith('http')?new URL(relativeSign):
  new URL((relativeSign.startsWith('/storage/v1/')?'':'/storage/v1')+
    (relativeSign.startsWith('/')?'':'/')+relativeSign,root);
assert.equal(resolvedSign.origin,new URL(root).origin,
 'Signed URL must point to ephemeral local Storage only');
const signedDownload=await fetch(resolvedSign);
assert.equal(signedDownload.status,200,'Signed URL must serve authenticated PDF');
assert.deepEqual(Buffer.from(await signedDownload.arrayBuffer()),pdf,
 'Signed URL returns the same uploaded PDF');
deny(await sign(b,pa),'B cannot sign A URL');
deny(await sign(outsider,pa),'outsider cannot sign');
deny(await sign(null,pa),'anon cannot sign');
const listA=pass(await list(a,ca+'/'+va.id+'/'),'A lists own vehicle files');
assert.ok(listA.some(x=>x.name===pa.split('/').at(-1)),'A file missing from listing');
const listB=await list(b,ca+'/'+va.id+'/');
if(listB.ok)assert.deepEqual(listB.value,[]);
else deny(listB,'B cannot list A');
const docsB=pass(await call('/rest/v1/fleet_documents?select=id',{jwt:b.jwt}),
 'B metadata');assert.equal(docsB.length,1);
const docsViewer=pass(await call('/rest/v1/fleet_documents?select=id',{jwt:viewer.jwt}),
 'viewer metadata');assert.equal(docsViewer.length,1);
const docsOutsider=pass(await call('/rest/v1/fleet_documents?select=id',{jwt:outsider.jwt}),
 'outsider metadata');assert.deepEqual(docsOutsider,[]);

deny(await upload(b,file(ca,va.id)),'B upload into A');
deny(await upload(viewer,file(ca,va.id)),'viewer upload');
deny(await upload(outsider,file(ca,va.id)),'outsider upload');
deny(await upload(null,file(ca,va.id)),'anonymous upload');
deny(await upload(a,file(ca,vb.id)),'foreign vehicle attached to A');
deny(await upload(a,ca+'/'+va.id+'/name.pdf'),'freeform filename');
deny(await upload(a,file(ca,va.id,'html'),Buffer.from('<script>evil</script>'),'text/html'),
 'HTML blocked');
deny(await upload(a,file(ca,va.id),Buffer.alloc(15728641),'application/pdf'),
 'file size greater than 15MB');
deny(await upload(a,pa,pdf),'duplicate upload');
deny(await upload(a,pa,pdf,'application/pdf',{'x-upsert':'true'}),'no upsert');
const viewerDelete=await remove(viewer,pa);
if(viewerDelete.ok)assert.deepEqual(viewerDelete.value,[], 'viewer must not remove object');
else deny(viewerDelete,'viewer cannot delete Storage');
await call('/rest/v1/fleet_documents?id=eq.'+da.id,{
 jwt:viewer.jwt,method:'DELETE'});
const stillPresent=pass(await call('/rest/v1/fleet_documents?id=eq.'+da.id+
 '&select=id',{jwt:a.jwt}),'metadata retained after viewer delete');
assert.equal(stillPresent.length,1);
pass(await download(a,pa),'object remains after viewer delete');
const crossDelete=await remove(b,pa);
if(crossDelete.ok)assert.deepEqual(crossDelete.value,[],
 'Foreign Fleet cannot remove original owner's Storage object');
else deny(crossDelete,'foreign Fleet cannot delete Storage');
pass(await download(a,pa),'object remains after foreign Fleet delete');
pass(await remove(a,pa),'owner deletes object');
deny(await download(a,pa),'deleted object cannot be read');
console.log('PASS real local Supabase Auth/PostgREST/Storage with 2 synthetic fleets, viewer, anon, outsider, tenant isolation, 120s URL and upload/delete');
