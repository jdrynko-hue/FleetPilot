import test from 'node:test';
import assert from 'node:assert/strict';
import {startGaragePaidRejoin,recordPaidRejoinEvent} from '../server/garage-billing/paid_rejoin.ts';
const a='11111111-1111-4111-8111-111111111111',w='22222222-2222-4222-8222-222222222222',attempt='33333333-3333-4333-8333-333333333333';
function fixture(){
 const now=Math.floor(Date.now()/1000),calls=[],created=[];
 const price={id:'price_paid',livemode:false,active:true,currency:'pln',unit_amount:100,billing_scheme:'per_unit',recurring:{interval:'month',interval_count:1,usage_type:'licensed'}};
 const context={actorId:a,planCode:'rejoin',workspaceId:w,ownerVerified:true,currency:'pln',customer:{id:'cus_paid',livemode:false},price};
 const p={attempt_id:attempt,owner_user_id:a,workspace_id:w,price_id:price.id,customer_id:'cus_paid',currency:'pln',billing_interval:'month',amount_minor:100,state:'prepared',session_id:null,subscription_id:null,expires_at:now+3600};
 const metadata={product:'garage',workspace_id:w,attempt_id:attempt,purchase_kind:'paid_rejoin',currency:'pln',billing_interval:'month'};
 const session={id:'cs_test_paid',livemode:false,mode:'subscription',status:'open',customer:'cus_paid',client_reference_id:w,metadata,expires_at:now+3600,url:'https://checkout.stripe.com/c/pay/cs_test_paid#private',line_items:{has_more:false,data:[{quantity:1,price}]},subscription:'sub_new'};
 const prior={id:'sub_old',livemode:false,status:'canceled',customer:'cus_paid'};
 const sub={id:'sub_new',livemode:false,status:'active',customer:'cus_paid',metadata,trial_start:null,trial_end:null,test_clock:null,items:{has_more:false,data:[{quantity:1,price}]}};
 const invoice={id:'in_paid',livemode:false,customer:'cus_paid',parent:{subscription_details:{subscription:'sub_new'}},currency:'pln',billing_reason:'subscription_create',status:'paid',amount_due:100,amount_paid:100,amount_remaining:0,status_transitions:{paid_at:now},lines:{has_more:false,data:[{quantity:1,pricing:{price_details:{price:price.id}},period:{start:now,end:now+30*86400}}]}};
 const state={eligible:true,subscription_ids:['sub_old']};
 const client={rpc:async(name,args)=>{
 calls.push([name,args]);let data;
 if(name==='garage_paid_rejoin_context')data=state;
 if(name==='garage_prepare_paid_rejoin'||name==='garage_lookup_paid_rejoin')data=p;
 if(name==='garage_save_paid_rejoin'||name==='garage_record_paid_rejoin')data=true;
 return {data,error:null};}};
 const stripe={subscriptions:{retrieve:async id=>id==='sub_old'?prior:sub},invoices:{retrieve:async()=>invoice},checkout:{sessions:{create:async(params,opts)=>{created.push([params,opts]);return {id:'cs_test_paid',livemode:false}},retrieve:async()=>session}}};
 const event={id:'evt_paid',type:'invoice.paid',created:now,livemode:false,data:{object:{id:'in_paid'}}};
 return {context,p,session,prior,sub,invoice,state,client,stripe,event,calls,created,now};
}
const start=f=>startGaragePaidRejoin(f.context,{client:f.client,stripe:f.stripe,now:()=>f.now*1000});
const hook=f=>{f.p.state='ready';f.p.session_id='cs_test_paid';f.session.status='complete';return recordPaidRejoinEvent(f.event,{client:f.client,stripe:f.stripe});};
test('paid Checkout has no trial fields and stable attempt idempotency',async()=>{
 const f=fixture();const result=await start(f);assert.equal(result.trial_days,0);const [params,opts]=f.created[0];
 assert.deepEqual(params.subscription_data,{metadata:params.metadata});assert.equal(JSON.stringify(params).includes('trial_period'),false);
 assert.equal(params.adaptive_pricing.enabled,false);assert.equal(opts.idempotencyKey,'flotaryx:garage:paid:'+attempt);
 await start(f);assert.deepEqual(f.created[0],f.created[1]);assert.equal(f.calls.at(-1)[0],'garage_save_paid_rejoin');
});
for(const status of ['active','trialing','past_due','unpaid','incomplete','paused','incomplete_expired',undefined])test('no duplicate subscription for prior '+status,async()=>{
 const f=fixture();f.prior.status=status;await assert.rejects(()=>start(f));assert.equal(f.created.length,0);assert.equal(f.calls.length,1);
});
for(const mutate of [f=>f.state.eligible=false,f=>f.state.subscription_ids=[],f=>f.prior.livemode=true,f=>f.prior.customer='cus_other',f=>f.prior.test_clock='clock_old',f=>f.prior.id='sub_other',f=>f.context.ownerVerified=false])test('predecessor/catalog failure before create '+mutate,async()=>{
 const f=fixture();mutate(f);await assert.rejects(()=>start(f));assert.equal(f.created.length,0);
});
for(const mutate of [f=>f.p.price_id='price_other',f=>f.p.workspace_id=a,f=>f.p.expires_at=f.now-1,f=>f.p.state='subscribed',f=>f.p.amount_minor=900])test('reservation identity failure '+mutate,async()=>{
 const f=fixture();mutate(f);await assert.rejects(()=>start(f));assert.equal(f.created.length,0);
});
for(const mutate of [f=>f.session.id='cs_test_other',f=>f.session.url='https://example.test/c/pay/cs_test_paid',f=>f.session.status='complete',f=>f.session.line_items.data.push(f.session.line_items.data[0]),f=>f.session.metadata.purchase_kind='trial',f=>f.session.expires_at++])test('ambiguous session is never saved '+mutate,async()=>{
 const f=fixture();mutate(f);await assert.rejects(()=>start(f));assert.equal(f.calls.some(c=>c[0]==='garage_save_paid_rejoin'),false);
});
test('ready session retry retrieves existing session without another create',async()=>{
 const f=fixture();f.p.state='ready';f.p.session_id='cs_test_paid';await start(f);assert.equal(f.created.length,0);
});
test('fresh completed paid initial invoice records a paid purchase, never a trial grant',async()=>{
 const f=fixture();await hook(f);const [name,args]=f.calls.at(-1);assert.equal(name,'garage_record_paid_rejoin');
 assert.equal(args.p_record.action,'paid');assert.equal(args.p_record.billing_reason,'subscription_create');assert.equal(args.p_record.amount_paid,100);
});
test('same failed invoice may recover under original signed failure receipt',async()=>{
 const f=fixture();f.event.type='invoice.payment_failed';await hook(f);assert.equal(f.calls.at(-1)[1].p_record.action,'paid');
});
test('decline records no paid access',async()=>{
 const f=fixture();Object.assign(f.invoice,{status:'open',amount_paid:0,amount_remaining:100,attempt_count:1});f.event.type='invoice.payment_failed';f.sub.status='incomplete';
 await hook(f);assert.equal(f.calls.at(-1)[1].p_record.action,'failed');assert.equal(f.calls.at(-1)[1].p_record.paid_at,null);
});
for(const mutate of [f=>f.sub.customer='cus_other',f=>f.sub.test_clock='clock_new',f=>f.sub.trial_end=f.now+604800,f=>f.invoice.amount_due=0,f=>f.invoice.amount_remaining=1,f=>f.invoice.currency='gbp',f=>f.session.subscription='sub_other',f=>f.invoice.lines.has_more=true,f=>f.invoice.billing_reason='manual',f=>f.sub.metadata.workspace_id=a])test('unverified paid object never grants '+mutate,async()=>{
 const f=fixture();mutate(f);await assert.rejects(()=>hook(f));assert.equal(f.calls.some(c=>c[0]==='garage_record_paid_rejoin'),false);
});
test('fresh cancellation caps a late paid event atomically',async()=>{
 const f=fixture();Object.assign(f.sub,{status:'canceled',canceled_at:f.now});await hook(f);
 assert.equal(f.calls.at(-1)[1].p_record.subscription_ended_at,new Date(f.now*1000).toISOString());
});
for(const currency of ['gbp','pln','eur'])for(const interval of ['month','year'])test('exact server market '+currency+interval,async()=>{
 const f=fixture();f.context.currency=f.context.price.currency=f.p.currency=f.session.metadata.currency=currency;
 f.context.price.recurring.interval=f.p.billing_interval=f.session.metadata.billing_interval=interval;
 await start(f);assert.deepEqual(f.created[0][0].line_items,[{quantity:1,price:'price_paid'}]);
});
