// Mock HTTP integration tests; no network, Stripe charges, or secrets.
import assert from 'node:assert/strict';
const cid='ee2d4de9-395e-4bb1-b21c-1c82f365ed75';
const uid='0d0ad4bb-6be3-4769-b7c0-69227b430a61';
const now=1791717544;
let handler; let adminRole='owner'; let lastStripePost;
globalThis.Deno = {
  env:{get:n=>({STRIPE_SECRET_KEY:'sk_test_mock_not_real',SUPABASE_URL:'https://demo.supabase.co',SUPABASE_ANON_KEY:'mock_anon'}[n])},
  serve: fn => {handler=fn;},
};
const asResponse=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
globalThis.fetch=async(input, options={})=>{
  const url=new URL(String(input));
  if(url.pathname==='/auth/v1/user')return asResponse({id:uid});
  if(url.pathname.endsWith('/company_members'))return asResponse([{role:adminRole}]);
  if(url.pathname.endsWith('/companies'))return asResponse([{country:'GB'}]);
  if(url.pathname.endsWith('/company_subscriptions'))return asResponse([{
    billing_provider:'stripe',stripe_customer_id:'cus_mock123',stripe_subscription_id:'sub_mock123',status:'active',
  }]);
  if(url.pathname.endsWith('/flotaryx_billing_prices'))return asResponse([{
    stripe_price_id:'price_mockpro',included_vehicles:10,max_vehicles:25,
  }]);
  if(url.pathname.endsWith('/vehicles'))return asResponse([{id:'v1'}]);
  if(url.pathname.endsWith('/subscriptions/sub_mock123')){
    if(options.method==='POST'){
      lastStripePost=options.body.toString();
      return asResponse({id:'sub_mock123',cancel_at_period_end:lastStripePost.includes('cancel_at_period_end=true')});
    }
    return asResponse({id:'sub_mock123',livemode:false,customer:'cus_mock123',metadata:{company_id:cid},
      status:'active',currency:'gbp',cancel_at_period_end:false,items:{data:[{
        id:'si_mock123',price:{id:'price_mockstarter'},quantity:1,current_period_end:now+30*86400,
      }]}});
  }
  if(url.pathname.endsWith('/invoices'))return asResponse({data:[{id:'in_mock1',number:'TEST-001',status:'paid',total:3480,
    currency:'gbp',created:now,hosted_invoice_url:'https://invoice.stripe.com/i/mock'}]});
  throw Error('unexpected request: '+url.toString());
};
await import('../supabase/functions/flotaryx-billing-manage/index.ts');
assert.equal(typeof handler,'function');
const request=(body,headers={})=>new Request('https://demo.supabase.co/functions/v1/flotaryx-billing-manage',{
  method:'POST',headers:{'Content-Type':'application/json',origin:'https://flotaryx.com',Authorization:'Bearer mock',...headers},body:JSON.stringify(body),
});
let result=await handler(request({company_id:cid,action:'status'},{Authorization:''}));
assert.equal(result.status,401);
result=await handler(request({company_id:cid,action:'status'},{origin:'https://evil.invalid'}));
assert.equal(result.status,403);
adminRole='driver';
result=await handler(request({company_id:cid,action:'status'}));
assert.equal(result.status,403);
adminRole='owner';
result=await handler(request({company_id:cid,action:'invoices'}));
assert.equal(result.status,200);
assert.equal((await result.json()).invoices[0].total,3480);
result=await handler(request({company_id:cid,action:'change',plan_code:'pro',billing_interval:'month',vehicle_count:2}));
assert.equal(result.status,400);
result=await handler(request({company_id:cid,action:'change',plan_code:'pro',billing_interval:'month',vehicle_count:11}));
assert.equal(result.status,200);
assert.match(lastStripePost, /items%5B0%5D%5Bquantity%5D=11/);
assert.match(lastStripePost, /proration_behavior=create_prorations/);
result=await handler(request({company_id:cid,action:'cancel'}));
assert.equal(result.status,200);
assert.match(lastStripePost, /cancel_at_period_end=true/);
result=await handler(request({company_id:cid,action:'resume'}));
assert.equal(result.status,200);
assert.match(lastStripePost, /cancel_at_period_end=false/);
console.log('Passed: JWT, CORS, role, invoices, fleet limit, plan change, cancel, resume');
