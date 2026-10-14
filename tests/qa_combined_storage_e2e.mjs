// BOTH private buckets in ONE ephemeral local Supabase. No hosted credentials.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const base=process.env.COMBINED_LOCAL_URL?.replace(/\/$/,'');
const key=process.env.COMBINED_LOCAL_KEY;
if(!base||!key||!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(base))
 throw Error('Combined E2E requires loopback-only Supabase');
async function call(path,u,method='GET',body,mime,prefer){
 const headers={apikey:key,authorization:'Bearer '+(u?.jwt??key)};
 if(mime)headers['content-type']=mime;if(prefer)headers.prefer=prefer;
 const r=await fetch(base+path,{method,headers,body:body===undefined?undefined:
  (Buffer.isBuffer(body)?body:JSON.stringify(body))});
 const raw=await r.text();let data=raw;try{data=JSON.parse(raw)}catch{}
 return {ok:r.ok,status:r.status,data};
}
function yes(r,label){assert.ok(r.ok,label+' HTTP '+r.status+' '+JSON.stringify(r.data).slice(0,180));return r.data}
function no(r,label){assert.equal(r.ok,false,label+' should fail')}
async function signup(label){
 const x=yes(await call('/auth/v1/signup',null,'POST',{
  email:'combined-'+label+'-'+randomUUID()+'@example.test',password:'LocalOnlyPass!2026'
 },'application/json'),'signup '+label);
 return {id:x.user.id,jwt:x.access_token};
}
async function row(u,table,body){
 const x=yes(await call('/rest/v1/'+table+'?select=id',u,'POST',body,
  'application/json','return=representation'),'insert '+table);
 assert.equal(x.length,1);return x[0].id;
}
async function fleet(u){
 return yes(await call('/rest/v1/rpc/create_company_for_current_user',u,'POST',
  {_name:'Local Fleet',_country:'GB',_currency:'GBP'},'application/json'),'create Fleet');
}
async function workshop(u){
 const id=await row(u,'garage_workspaces',{owner_user_id:u.id,
  name:'Local Workshop',country:'GB',currency:'GBP'});
 const cust=await row(u,'garage_customers',{workspace_id:id,
  customer_type:'individual',display_name:'Synthetic Customer'});
 const vehicle=await row(u,'garage_vehicles',{workspace_id:id,
  customer_id:cust,registration:'LOCAL',make:'Ford',model:'Focus'});
 const job=await row(u,'garage_work_orders',{workspace_id:id,
  vehicle_id:vehicle,complaint:'Synthetic brake inspection'});
 return {id,job};
}
const f=await signup('fleet'),g=await signup('garage'),dual=await signup('dual');
const outsider=await signup('outsider');
const fa=await fleet(f),fd=await fleet(dual);
const va=await row(f,'vehicles',{company_id:fa,registration:'FA-'+randomUUID()});
const vd=await row(dual,'vehicles',{company_id:fd,registration:'FD-'+randomUUID()});
const ga=await workshop(g),gd=await workshop(dual);
const pf=fa+'/'+va+'/'+String(Date.now()*1000)+'.pdf';
const pd=fd+'/'+vd+'/'+String(Date.now()*1000+111)+'.pdf';
const pg=ga.id+'/'+ga.job+'/photos/'+randomUUID()+'.png';
const pdual=gd.id+'/'+gd.job+'/photos/'+randomUUID()+'.png';
const pdf=Buffer.from('%PDF-1.4\n%%EOF\n');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==','base64');
const sb='fleetpilot-documents',gb='flotaryx-garage-private';
const upload=(u,b,p,bytes,mime)=>call('/storage/v1/object/'+b+'/'+p,u,'POST',bytes,mime);
const read=(u,b,p)=>call('/storage/v1/object/authenticated/'+b+'/'+p,u);
const signed=(u,b,p)=>call('/storage/v1/object/sign/'+b+'/'+p,u,'POST',{expiresIn:120},'application/json');
yes(await upload(f,sb,pf,pdf,'application/pdf'),'Fleet upload');
yes(await upload(dual,sb,pd,pdf,'application/pdf'),'Dual Fleet upload');
yes(await upload(g,gb,pg,png,'image/png'),'Garage upload');
yes(await upload(dual,gb,pdual,png,'image/png'),'Dual Garage upload');
yes(await read(f,sb,pf),'Fleet own read');
yes(await read(g,gb,pg),'Garage own read');
yes(await read(dual,sb,pd),'Dual Fleet read');
yes(await read(dual,gb,pdual),'Dual Garage read');
no(await read(g,sb,pf),'Garage to Fleet read denied');
no(await read(f,gb,pg),'Fleet to Garage read denied');
no(await read(dual,sb,pf),'Dual to foreign Fleet denied');
no(await read(dual,gb,pg),'Dual to foreign Garage denied');
no(await read(outsider,sb,pf),'Outsider Fleet denied');
no(await read(outsider,gb,pg),'Outsider Garage denied');
no(await read(null,sb,pf),'Anonymous Fleet denied');
no(await read(null,gb,pg),'Anonymous Garage denied');
no(await upload(g,sb,fa+'/'+va+'/'+String(Date.now()*1000+222)+'.pdf',pdf,'application/pdf'),
 'Garage to Fleet upload denied');
no(await upload(f,gb,ga.id+'/'+ga.job+'/photos/'+randomUUID()+'.png',png,'image/png'),
 'Fleet to Garage upload denied');
yes(await signed(f,sb,pf),'Fleet signed URL allowed');
no(await signed(g,gb,pg),'Garage signed URL forbidden');
no(await signed(f,gb,pg),'Fleet cannot sign Garage object');
no(await signed(g,sb,pf),'Garage cannot sign Fleet object');
const gFleet=yes(await call('/rest/v1/vehicles?select=id',g),'Garage user Fleet table read');
assert.deepEqual(gFleet,[]);
const fGarage=yes(await call('/rest/v1/garage_work_orders?select=id',f),
 'Fleet user Garage table read');
assert.deepEqual(fGarage,[]);
console.log('PASS: real one-Supabase Fleet/Garage private Storage isolation, dual-role access and cross-bucket denial');
