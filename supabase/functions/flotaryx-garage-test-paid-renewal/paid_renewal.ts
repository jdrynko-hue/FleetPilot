// Internal ordinary-Sandbox management. HTTP Auth supplies actor; private SQL
// binds the paid period. Scheduling renewal stop never grants or revokes time.
export type RenewalContext={actorId:string;workspaceId:string};
export type RenewalStatus={status:'renewing'|'stopping';access_ends_at:string};
type Binding={kind:string;owner_user_id:string;workspace_id:string;attempt_id:string;
 subscription_id:string;customer_id:string;price_id:string;currency:string;
 billing_interval:string;amount_minor:number;access_ends_at:string};
export type RenewalDeps={load(context:RenewalContext):Promise<unknown>;now?:()=>number;
 stripe:{subscriptions:{retrieve(id:string):Promise<unknown>;
 update(id:string,params:{cancel_at_period_end:true;proration_behavior:'none'},
 options:{idempotencyKey:string}):Promise<unknown>}}};
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const fail=()=>{throw Error('garage_paid_renewal_unavailable');};
function binding(value:unknown,context:RenewalContext,now:number):Binding {
 const b=value as Binding;
 if(!uuid.test(context.actorId)||!uuid.test(context.workspaceId)||!b||Object.keys(b).length!==11||
 b.owner_user_id!==context.actorId||b.workspace_id!==context.workspaceId||!uuid.test(b.attempt_id)||
 !['legacy','paid_rejoin'].includes(b.kind)||!/^sub_[A-Za-z0-9]+$/.test(b.subscription_id)||
 !/^cus_[A-Za-z0-9]+$/.test(b.customer_id)||!/^price_[A-Za-z0-9]+$/.test(b.price_id)||
 !['gbp','eur','pln'].includes(b.currency)||!['month','year'].includes(b.billing_interval)||
 !Number.isSafeInteger(b.amount_minor)||b.amount_minor<=0||typeof b.access_ends_at!=='string'||
 !Number.isSafeInteger(Date.parse(b.access_ends_at))||Date.parse(b.access_ends_at)<=now)fail();
 return b;
}
function subscription(value:unknown,b:Binding,now:number):RenewalStatus {
 const s=value as any;const line=s?.items?.data?.[0];const price=line?.price;
 const end=Date.parse(b.access_ends_at)/1000;
 if(!s||s.id!==b.subscription_id||s.customer!==b.customer_id||s.livemode!==false||
 s.test_clock!=null||s.status!=='active'||s.pause_collection!=null||s.schedule!=null||
 s.metadata?.product!=='garage'||s.metadata?.attempt_id!==b.attempt_id||
 s.metadata?.workspace_id!==b.workspace_id||s.metadata?.currency!==b.currency||
 s.metadata?.billing_interval!==b.billing_interval||
 (b.kind==='paid_rejoin'&&s.metadata?.purchase_kind!=='paid_rejoin')||
 s.items?.has_more!==false||!Array.isArray(s.items.data)||s.items.data.length!==1||
 line.quantity!==1||price?.id!==b.price_id||price.livemode!==false||
 price.currency!==b.currency||price.unit_amount!==b.amount_minor||
 price.recurring?.interval!==b.billing_interval||price.recurring.interval_count!==1||
 price.recurring.usage_type!=='licensed'||line.current_period_end!==end||
 !Number.isSafeInteger(line.current_period_start)||line.current_period_start*1000>now||
 line.current_period_start>=end||!Number.isSafeInteger(end)||
 (s.trial_end!=null&&(!Number.isSafeInteger(s.trial_end)||s.trial_end*1000>now))||
 typeof s.cancel_at_period_end!=='boolean'||
 (s.cancel_at_period_end ? s.cancel_at!==end : s.cancel_at!=null))fail();
 return {status:s.cancel_at_period_end?'stopping':'renewing',access_ends_at:new Date(end*1000).toISOString()};
}
function same(a:Binding,b:Binding){
 return ['kind','owner_user_id','workspace_id','attempt_id','subscription_id','customer_id',
 'price_id','currency','billing_interval','amount_minor','access_ends_at']
 .every(k=>a[k as keyof Binding]===b[k as keyof Binding]);
}
export async function managePaidRenewal(context:RenewalContext,action:'status'|'stop',deps:RenewalDeps):Promise<RenewalStatus>{
 const now=()=>deps.now?.()??Date.now();
 if(!['status','stop'].includes(action))fail();
 const b=binding(await deps.load(context),context,now());
 let result=subscription(await deps.stripe.subscriptions.retrieve(b.subscription_id),b,now());
 // Ownership and paid period may change during the external read. Never issue
 // a mutation or return a usable result from a stale binding.
 const current=binding(await deps.load(context),context,now());
 if(!same(b,current))fail();
 if(action==='status'||result.status==='stopping')return result;
 try{
  await deps.stripe.subscriptions.update(b.subscription_id,
   {cancel_at_period_end:true,proration_behavior:'none'},
   {idempotencyKey:`flotaryx:garage:stop-renewal:${b.attempt_id}:${Date.parse(b.access_ends_at)/1000}`});
 }catch{
  // Transport uncertainty is reconciled through one authoritative GET below.
 }
 result=subscription(await deps.stripe.subscriptions.retrieve(b.subscription_id),b,now());
 if(result.status!=='stopping')fail();
 if(!same(b,binding(await deps.load(context),context,now())))fail();
 return result;
}
