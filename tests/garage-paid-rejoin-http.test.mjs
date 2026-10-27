import test from 'node:test';
import assert from 'node:assert/strict';
import {createGarageSandboxCheckoutHandler} from '../server/garage-billing/http_handler.ts';
import {createGarageSandboxEntitlementHandler} from '../server/garage-billing/entitlement_http.ts';
const a='11111111-1111-4111-8111-111111111111',w='22222222-2222-4222-8222-222222222222',attempt='33333333-3333-4333-8333-333333333333';
const url='https://fyestmquqvkdebxxbcky.supabase.co';
const request=(body)=>new Request('https://example.test',{method:'POST',headers:{authorization:'Bearer synthetic','content-type':'application/json'},body:JSON.stringify(body)});
const input={workspace_id:w,plan_code:'pilot',billing_interval:'month',business_purchase_confirmed:true,purchase_kind:'paid_rejoin'};
function fixture(enabled=true){
 const now=Math.floor(Date.now()/1000),calls=[];
 const price={id:'price_paid',livemode:false,active:true,currency:'gbp',unit_amount:100,billing_scheme:'per_unit',metadata:{product:'garage',plan_code:'pilot'},recurring:{interval:'month',interval_count:1,usage_type:'licensed'}};
 const p={attempt_id:attempt,owner_user_id:a,workspace_id:w,price_id:price.id,customer_id:'cus_paid',currency:'gbp',billing_interval:'month',amount_minor:100,state:'prepared',session_id:null,subscription_id:null,expires_at:now+3600};
 const serviceClient={rpc:async(name,args)=>{calls.push(name);let data;
 if(name==='garage_resolve_test_billing_context')data={owner_user_id:a,workspace_id:w,plan_code:'pilot',currency:'gbp',billing_interval:'month',price_id:price.id,amount_minor:100,customer_id:'cus_paid'};
 if(name==='garage_paid_rejoin_context')data={eligible:true,subscription_ids:['sub_old']};
 if(name==='garage_prepare_paid_rejoin')data=p;
 if(name==='garage_save_paid_rejoin')data=true;
 if(name==='garage_resolve_test_workspace_entitlement')data={active:false,source:null,access_ends_at:null,last_payment_state:null};
 if(name==='garage_test_trial_available')data=false;
 return {data,error:null};}};
 const authClient={auth:{getUser:async()=>({data:{user:{id:a}},error:null})}};
 const stripe={prices:{retrieve:async()=>price},customers:{retrieve:async()=>({id:'cus_paid',livemode:false,metadata:{product:'garage',workspace_id:w,owner_user_id:a}})},subscriptions:{retrieve:async()=>({id:'sub_old',customer:'cus_paid',livemode:false,status:'canceled'})},checkout:{sessions:{create:async()=>({id:'cs_test_paid',livemode:false}),retrieve:async()=>({id:'cs_test_paid',livemode:false,mode:'subscription',status:'open',expires_at:now+3600,customer:'cus_paid',client_reference_id:w,metadata:{workspace_id:w,product:'garage',attempt_id:attempt,purchase_kind:'paid_rejoin',currency:'gbp',billing_interval:'month'},line_items:{has_more:false,data:[{quantity:1,price}]},url:'https://checkout.stripe.com/c/pay/cs_test_paid'})}}};
 return {calls,stripe,authClient,serviceClient,handler:createGarageSandboxCheckoutHandler({enabled:true,paidRejoinEnabled:enabled,supabaseUrl:url,stripeKey:'sk_test_synthetic'},{authClient,serviceClient,createStripeClient:()=>stripe,now:()=>now*1000})};
}
test('paid rejoin needs its own default-off server opt-in',async()=>{
 const f=fixture(false);assert.equal((await f.handler(request(input))).status,503);assert.deepEqual(f.calls,[]);
});
test('paid HTTP selection uses server actor/catalog and a separate ledger',async()=>{
 const f=fixture();const r=await f.handler(request(input));assert.equal(r.status,200);assert.equal((await r.json()).trial_days,0);
 assert.equal(f.calls.includes('garage_reserve_test_trial'),false);assert.equal(f.calls.at(-1),'garage_save_paid_rejoin');
});
for(const kind of ['trial','paid',null,1])test('unknown purchase kind rejected '+kind,async()=>{
 const f=fixture();assert.equal((await f.handler(request({...input,purchase_kind:kind}))).status,400);assert.deepEqual(f.calls,[]);
});
for(const enabled of [false,true])test('billing envelope explicitly includes paid hint only when enabled '+enabled,async()=>{
 const f=fixture();const h=createGarageSandboxEntitlementHandler({enabled:true,paidRejoinEnabled:enabled,supabaseUrl:url},f);
 const r=await h(request({workspace_id:w,billing_status:true}));assert.equal(r.status,200);const value=await r.json();
 assert.equal(value.paid_available,enabled?true:undefined);assert.equal(value.trial_available,false);
});
