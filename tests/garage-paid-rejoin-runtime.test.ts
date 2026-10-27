import Stripe from 'stripe';
import {createGarageSandboxBillingWebhookRuntime} from '../supabase/functions/flotaryx-garage-test-webhook/billing_webhook_runtime.ts';

Deno.test('signed paid rejoin retrieves completed Checkout through real SDK and uses separate ledger',async()=>{
 const original=globalThis.fetch;
 const attempt='11111111-1111-4111-8111-111111111111',workspace='22222222-2222-4222-8222-222222222222',actor='33333333-3333-4333-8333-333333333333';
 const now=Math.floor(Date.now()/1000),secret='whsec_disposablefixture';
 const metadata={product:'garage',purchase_kind:'paid_rejoin',attempt_id:attempt,workspace_id:workspace,currency:'gbp',billing_interval:'month'};
 const price={id:'price_paid',livemode:false,currency:'gbp',unit_amount:100,recurring:{interval:'month',interval_count:1,usage_type:'licensed'}};
 const calls:string[]=[];
 let record:Record<string,unknown>|undefined;
 const json=(x:unknown)=>new Response(JSON.stringify(x),{headers:{'content-type':'application/json'}});
 const assert=(x:unknown,m:string)=>{if(!x)throw Error(m);};
 globalThis.fetch=async(input,init)=>{
  const u=new URL(input instanceof Request?input.url:String(input));calls.push(u.pathname);
  if(u.hostname==='api.stripe.com'){
   assert(new Headers(init?.headers).get('authorization')==='Bearer rk_test_fixture','wrong Stripe key');
   if(u.pathname==='/v1/invoices/in_paid')return json({id:'in_paid',livemode:false,status:'paid',customer:'cus_paid',currency:'gbp',amount_due:100,amount_paid:100,amount_remaining:0,billing_reason:'subscription_create',parent:{subscription_details:{subscription:'sub_paid'}},status_transitions:{paid_at:now},lines:{has_more:false,data:[{quantity:1,pricing:{price_details:{price:'price_paid'}},period:{start:now,end:now+30*86400}}]}});
   if(u.pathname==='/v1/subscriptions/sub_paid')return json({id:'sub_paid',livemode:false,status:'active',customer:'cus_paid',trial_start:null,trial_end:null,metadata,items:{has_more:false,data:[{quantity:1,price}]}});
   if(u.pathname==='/v1/checkout/sessions/cs_test_paid')return json({id:'cs_test_paid',livemode:false,mode:'subscription',status:'complete',subscription:'sub_paid',customer:'cus_paid',client_reference_id:workspace,metadata,line_items:{has_more:false,data:[{quantity:1,price}]}});
   throw Error('Unexpected Stripe method');
  }
  assert(u.hostname==='fyestmquqvkdebxxbcky.supabase.co','unexpected endpoint');
  assert(new Headers(init?.headers).get('authorization')==='Bearer disposable-service','missing service authorization');
  if(u.pathname==='/rest/v1/rpc/garage_lookup_paid_rejoin')return json({attempt_id:attempt,workspace_id:workspace,owner_user_id:actor,customer_id:'cus_paid',price_id:'price_paid',currency:'gbp',billing_interval:'month',amount_minor:100,state:'ready',session_id:'cs_test_paid',subscription_id:null});
  if(u.pathname==='/rest/v1/rpc/garage_record_paid_rejoin'){record=JSON.parse(String(init?.body)).p_record;return json(true);}
  throw Error('Legacy trial ledger or unexpected write');
 };
 try{
  const h=createGarageSandboxBillingWebhookRuntime({enabled:true,supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',stripeKey:'rk_test_fixture',signingSecret:secret,serviceKey:'disposable-service'});
  const body=JSON.stringify({id:'evt_paid',type:'invoice.paid',created:now,livemode:false,data:{object:{id:'in_paid'}}});
  const signature=await Stripe.webhooks.generateTestHeaderStringAsync({payload:body,timestamp:now,secret,cryptoProvider:Stripe.createSubtleCryptoProvider()});
  const req=(b:string)=>new Request('https://example.test/webhook',{method:'POST',headers:{'stripe-signature':signature},body:b});
  assert((await h(req(body+' '))).status===400,'altered bytes accepted');assert(calls.length===0,'bad signature reached transport');
  assert((await h(req(body))).status===200,'signed paid purchase rejected');
  assert(record?.action==='paid'&&record?.amount_paid===100&&record?.session_id==='cs_test_paid','unsafe or missing grant');
  assert(calls.filter(x=>x==='/v1/invoices/in_paid').length===1,'invoice not freshly cached');
  assert(calls.includes('/v1/checkout/sessions/cs_test_paid'),'completed Checkout binding omitted');
 }finally{globalThis.fetch=original;}
});
