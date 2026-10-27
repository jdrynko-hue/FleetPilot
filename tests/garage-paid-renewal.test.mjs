import assert from 'node:assert/strict';
import {test} from 'node:test';
import {managePaidRenewal} from '../server/garage-billing/paid_renewal.ts';
import {createPaidRenewalHandler} from '../server/garage-billing/paid_renewal_http.ts';
const actor='00000000-0000-4000-8000-000000000101',workspace='00000000-0000-4000-8000-000000000201';
function fixture(){
 const now=Date.parse('2026-10-15T12:00:00Z'),end=Date.parse('2026-11-01T00:00:00Z')/1000;
 const b={kind:'paid_rejoin',owner_user_id:actor,workspace_id:workspace,attempt_id:'00000000-0000-4000-8000-000000000301',
 subscription_id:'sub_paid',customer_id:'cus_paid',price_id:'price_paid',currency:'gbp',billing_interval:'month',amount_minor:100,
 access_ends_at:new Date(end*1000).toISOString()};
 const sub={id:b.subscription_id,customer:b.customer_id,livemode:false,status:'active',test_clock:null,pause_collection:null,schedule:null,
 trial_end:null,cancel_at_period_end:false,cancel_at:null,metadata:{product:'garage',attempt_id:b.attempt_id,workspace_id:workspace,
 currency:'gbp',billing_interval:'month',purchase_kind:'paid_rejoin'},items:{has_more:false,data:[{quantity:1,
 current_period_start:Date.parse('2026-10-01T00:00:00Z')/1000,current_period_end:end,
 price:{id:b.price_id,livemode:false,currency:'gbp',unit_amount:100,recurring:{interval:'month',interval_count:1,usage_type:'licensed'}}}]}};
 const calls={loads:0,reads:0,writes:[]};let mutate=()=>{};
 const deps={now:()=>now,async load(){calls.loads++;return structuredClone(b);},stripe:{subscriptions:{
 async retrieve(){calls.reads++;return structuredClone(sub);},async update(...args){calls.writes.push(args);mutate();
 sub.cancel_at_period_end=true;sub.cancel_at=end;return structuredClone(sub);}}}};
 return {b,sub,calls,deps,context:{actorId:actor,workspaceId:workspace},setUpdate(fn){deps.stripe.subscriptions.update=fn;},setMutate(fn){mutate=fn;}};
}
test('status reads never mutate Stripe or change paid access',async()=>{
 const f=fixture();assert.equal((await managePaidRenewal(f.context,'status',f.deps)).status,'renewing');
 assert.equal(f.calls.loads,2);assert.equal(f.calls.writes.length,0);
});
test('stop schedules only period-end cancellation, then fresh GET verifies success',async()=>{
 const f=fixture();const r=await managePaidRenewal(f.context,'stop',f.deps);
 assert.deepEqual(r,{status:'stopping',access_ends_at:f.b.access_ends_at});
 assert.deepEqual(f.calls.writes[0],['sub_paid',{cancel_at_period_end:true,proration_behavior:'none'},
 {idempotencyKey:'flotaryx:garage:stop-renewal:'+f.b.attempt_id+':1793491200'}]);
 assert.equal(f.calls.reads,2);assert.equal(f.sub.status,'active');
 await managePaidRenewal(f.context,'stop',f.deps);assert.equal(f.calls.writes.length,1);
});
test('legacy paid subscription is supported after its original trial ended',async()=>{
 const f=fixture();f.b.kind='legacy';delete f.sub.metadata.purchase_kind;f.sub.trial_end=f.deps.now()/1000-100;
 assert.equal((await managePaidRenewal(f.context,'stop',f.deps)).status,'stopping');
});
for(const [name,change] of [
 ['foreign owner',f=>f.b.owner_user_id=workspace],['foreign workspace',f=>f.b.workspace_id=actor],
 ['expired paid period',f=>f.b.access_ends_at=new Date(f.deps.now()).toISOString()],
 ['Live',f=>f.sub.livemode=true],['clock',f=>f.sub.test_clock='clock_synthetic'],
 ['trial',f=>f.sub.trial_end=f.deps.now()/1000+60],['paused collection',f=>f.sub.pause_collection={}],
 ['schedule',f=>f.sub.schedule='sub_sched_other'],['wrong customer',f=>f.sub.customer='cus_other'],
 ['wrong metadata',f=>f.sub.metadata.attempt_id=actor],['wrong price',f=>f.sub.items.data[0].price.id='price_other'],
 ['different amount',f=>f.sub.items.data[0].price.unit_amount=101],
 ['period differs from paid ledger',f=>f.sub.items.data[0].current_period_end++],
 ['future start',f=>f.sub.items.data[0].current_period_start=f.deps.now()/1000+1],
 ['pending renewal with explicit cancel date',f=>f.sub.cancel_at=f.deps.now()/1000+30],
 ['extra item',f=>f.sub.items.data.push(structuredClone(f.sub.items.data[0]))],
 ['paginated items',f=>f.sub.items.has_more=true],['unknown binding fields',f=>f.b.owner='forged'],
 ...['trialing','past_due','unpaid','incomplete','paused','canceled'].map(s=>[s,f=>f.sub.status=s])
])test(name+' cannot schedule cancellation',async()=>{
 const f=fixture();change(f);await assert.rejects(managePaidRenewal(f.context,'stop',f.deps));assert.equal(f.calls.writes.length,0);
});
test('ownership change after first Stripe read blocks mutation',async()=>{
 const f=fixture();f.deps.load=async()=>{if(++f.calls.loads===2)throw Error('No owner');return f.b;};
 await assert.rejects(managePaidRenewal(f.context,'stop',f.deps));assert.equal(f.calls.writes.length,0);
});
test('changed paid boundary after read blocks mutation',async()=>{
 const f=fixture();f.deps.load=async()=>{f.calls.loads++;return {...f.b,amount_minor:f.calls.loads===1?100:101};};
 await assert.rejects(managePaidRenewal(f.context,'stop',f.deps));assert.equal(f.calls.writes.length,0);
});
for(const reached of [true,false])test('unknown update reconciles authoritative state: '+reached,async()=>{
 const f=fixture();f.setUpdate(async()=>{if(reached){f.sub.cancel_at_period_end=true;f.sub.cancel_at=f.sub.items.data[0].current_period_end;}throw Error('Transport');});
 if(reached)assert.equal((await managePaidRenewal(f.context,'stop',f.deps)).status,'stopping');
 else await assert.rejects(managePaidRenewal(f.context,'stop',f.deps));
});
test('successful-looking update response alone is not confirmation',async()=>{
 const f=fixture();f.setUpdate(async()=>({...f.sub,cancel_at_period_end:true}));
 await assert.rejects(managePaidRenewal(f.context,'stop',f.deps));
});
function http(){
 const f=fixture(),calls=[];const config={enabled:true,supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co'};
 const user={id:actor,is_anonymous:false,user_metadata:{role:'owner'}};
 const deps={auth:{async getUser(){return {data:{user},error:null};}},async manage(c,a){calls.push({c,a});return {status:'stopping',access_ends_at:f.b.access_ends_at};}};
 const request=(body={workspace_id:workspace,action:'stop'},headers={})=>new Request('https://qa.example.test/renewal',{
 method:'POST',headers:{authorization:'Bearer fixture-token','content-type':'application/json',...headers},body:JSON.stringify(body)});
 return {...f,config,user,calls,deps,request,handler:()=>createPaidRenewalHandler(config,deps)};
}
test('HTTP uses only Auth identity and returns no Stripe IDs',async()=>{
 const f=http(),r=await f.handler()(f.request());assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');
 assert.deepEqual(await r.json(),{status:'stopping',access_ends_at:f.b.access_ends_at});
 assert.deepEqual(f.calls,[{c:f.context,a:'stop'}]);
});
for(const field of ['actor_id','customer_id','subscription_id','price_id','cancel_at','invoice_now','return_url'])test('HTTP rejects injected '+field,async()=>{
 const f=http();assert.equal((await f.handler()(f.request({workspace_id:workspace,action:'stop',[field]:'forged'}))).status,400);assert.equal(f.calls.length,0);
});
test('HTTP disabled/production/anonymous paths fail closed',async()=>{
 for(const change of [f=>f.config.enabled=false,f=>f.config.supabaseUrl='https://production.example.test',f=>f.user.is_anonymous=true]){
 const f=http();change(f);assert.notEqual((await f.handler()(f.request())).status,200);assert.equal(f.calls.length,0);}
});
test('HTTP rejects foreign origin, malformed or oversized requests',async()=>{
 const f=http();assert.equal((await f.handler()(f.request(undefined,{origin:'https://evil.example'}))).status,403);
 assert.equal((await f.handler()(f.request({workspace_id:workspace,action:'stop',padding:'x'.repeat(1100)}))).status,400);
 assert.equal((await f.handler()(f.request({workspace_id:workspace,action:'resume'}))).status,400);
 assert.equal(f.calls.length,0);
});
