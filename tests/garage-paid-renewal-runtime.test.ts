import {createPaidRenewalRuntime} from '../supabase/functions/flotaryx-garage-test-paid-renewal/runtime.ts';
import Stripe from 'stripe';
import {createGarageSandboxBillingWebhookRuntime} from '../supabase/functions/flotaryx-garage-test-webhook/billing_webhook_runtime.ts';
const assert=(v:unknown,m:string)=>{if(!v)throw Error(m);};
const qa='https://fyestmquqvkdebxxbcky.supabase.co';
const owner='11111111-1111-4111-8111-111111111111',shop='22222222-2222-4222-8222-222222222222';
const attempt='33333333-3333-4333-8333-333333333333';
Deno.test('paid renewal real SDK isolates Auth/RPC keys and schedules no immediate cancellation',async()=>{
 const original=globalThis.fetch,now=Math.floor(Date.now()/1000),end=now+30*86400;
 const context={kind:'paid_rejoin',owner_user_id:owner,workspace_id:shop,attempt_id:attempt,subscription_id:'sub_fixture',customer_id:'cus_fixture',
 price_id:'price_fixture',currency:'gbp',billing_interval:'month',amount_minor:100,access_ends_at:new Date(end*1000).toISOString()};
 let stopping=false,writes=0,reads=0;
 const json=(data:unknown)=>new Response(JSON.stringify(data),{headers:{'content-type':'application/json'}});
 globalThis.fetch=async(input,init)=>{
  const u=new URL(input instanceof Request?input.url:String(input)),headers=new Headers(init?.headers);
  if(u.pathname==='/auth/v1/user'){
   assert(headers.get('authorization')==='Bearer owner-fixture-token','Auth token boundary');
   assert(headers.get('apikey')==='publishable-fixture','Auth key boundary');return json({id:owner,is_anonymous:false});
  }
  if(u.pathname==='/rest/v1/rpc/garage_paid_renewal_context'){
   assert(headers.get('authorization')==='Bearer service-fixture','RPC key boundary');
   assert(JSON.parse(String(init?.body)).p_actor===owner,'derived Auth actor');return json(context);
  }
  assert(u.hostname==='api.stripe.com'&&u.pathname==='/v1/subscriptions/sub_fixture','Unexpected SDK request');
  assert(headers.get('authorization')==='Bearer rk_test_fixture','Stripe test key');
  if(init?.method==='POST'){
   writes++;const params=new URLSearchParams(String(init.body));
   assert(params.get('cancel_at_period_end')==='true'&&params.get('proration_behavior')==='none'&&[...params.keys()].length===2,'safe scheduled stop only');
   assert(headers.get('idempotency-key')?.startsWith('flotaryx:garage:stop-renewal:')===true,'stable mutation identity');stopping=true;
  }else reads++;
  return json({id:'sub_fixture',livemode:false,customer:'cus_fixture',status:'active',test_clock:null,trial_end:null,pause_collection:null,schedule:null,
   cancel_at_period_end:stopping,cancel_at:stopping?end:null,metadata:{product:'garage',purchase_kind:'paid_rejoin',attempt_id:attempt,workspace_id:shop,currency:'gbp',billing_interval:'month'},
   items:{has_more:false,data:[{quantity:1,current_period_start:now-10,current_period_end:end,
    price:{id:'price_fixture',livemode:false,currency:'gbp',unit_amount:100,recurring:{interval:'month',interval_count:1,usage_type:'licensed'}}}]}});
 };
 try{
  const handler=createPaidRenewalRuntime({enabled:true,supabaseUrl:qa,anonKey:'publishable-fixture',serviceKey:'service-fixture',stripeKey:'rk_test_fixture'});
  const response=await handler(new Request(qa+'/functions/v1/renewal',{method:'POST',headers:{authorization:'Bearer owner-fixture-token','content-type':'application/json'},body:JSON.stringify({workspace_id:shop,action:'stop'})}));
  assert(response.status===200,'status '+response.status);const body=await response.json();
  assert(body.status==='stopping'&&Object.keys(body).length===2,'minimal response');assert(writes===1&&reads===2,'fresh GET verification');
 }finally{globalThis.fetch=original;}
});
Deno.test('disabled or Live runtime has no external requests',async()=>{
 const original=globalThis.fetch;let calls=0;globalThis.fetch=()=>{calls++;throw Error('Unexpected request');};
 try{for(const change of [{enabled:false},{stripeKey:'sk_live_forbidden'},{supabaseUrl:'https://production.example.test'},{serviceKey:'publishable-fixture'}]){
  const handler=createPaidRenewalRuntime({enabled:true,supabaseUrl:qa,anonKey:'publishable-fixture',serviceKey:'service-fixture',stripeKey:'rk_test_fixture',...change});
  assert((await handler(new Request(qa))).status===503,'unsafe config');
 }assert(calls===0,'no external requests');}finally{globalThis.fetch=original;}
});
Deno.test('paid renewal deploy bundle equals canonical reviewed modules',async()=>{
 for(const file of ['paid_renewal.ts','paid_renewal_http.ts'])assert(
  await Deno.readTextFile('server/garage-billing/'+file)===await Deno.readTextFile('supabase/functions/flotaryx-garage-test-paid-renewal/'+file),'bundle '+file);
});
Deno.test('signed paid renewal update is acknowledged without touching trial history or granting access',async()=>{
 const original=globalThis.fetch,now=Math.floor(Date.now()/1000),secret='whsec_renewalfixture';let reads=0;
 globalThis.fetch=async(input)=>{
  const u=new URL(input instanceof Request?input.url:String(input));
  assert(u.hostname==='api.stripe.com'&&u.pathname==='/v1/subscriptions/sub_fixture','no legacy ledger read or write');reads++;
  return new Response(JSON.stringify({id:'sub_fixture',livemode:false,status:'active',metadata:{product:'garage',purchase_kind:'paid_rejoin'}}),{headers:{'content-type':'application/json'}});
 };
 try{
  const handler=createGarageSandboxBillingWebhookRuntime({enabled:true,supabaseUrl:qa,stripeKey:'rk_test_fixture',signingSecret:secret,serviceKey:'service-fixture'});
  const body=JSON.stringify({id:'evt_fixture',type:'customer.subscription.updated',created:now,livemode:false,data:{object:{id:'sub_fixture'}}});
  const signature=await Stripe.webhooks.generateTestHeaderStringAsync({payload:body,timestamp:now,secret,cryptoProvider:Stripe.createSubtleCryptoProvider()});
  assert((await handler(new Request(qa+'/functions/v1/webhook',{method:'POST',headers:{'stripe-signature':signature},body}))).status===200,'ack signed update');
  assert(reads===1,'fresh subscription lookup only');
 }finally{globalThis.fetch=original;}
});
