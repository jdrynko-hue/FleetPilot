import {buildGarageSandboxTrial} from './trial_policy.ts';
type Context = Omit<Parameters<typeof buildGarageSandboxTrial>[0], 'history'> & {
 actorId: string; planCode: string;
};
type Rpc = {rpc(name:string,args:Record<string,unknown>):PromiseLike<{data:unknown;error:unknown}>};
type Stripe = {
 subscriptions:{retrieve(id:string):Promise<unknown>};
 checkout:{sessions:{create(params:Record<string,unknown>,options:{idempotencyKey:string}):Promise<unknown>;
 retrieve(id:string,params?:{expand:string[]}):Promise<unknown>}};
};
export type PaidPurchase = {attempt_id:string;workspace_id:string;owner_user_id:string;price_id:string;
 customer_id:string;currency:string;billing_interval:string;amount_minor:number;state:string;
 session_id:string|null;subscription_id:string|null;expires_at?:number};
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const id=(v:unknown,prefix:string):v is string=>typeof v==='string'&&new RegExp(`^${prefix}_[A-Za-z0-9]+$`).test(v);
const object=(v:unknown):Record<string,any>=>{
 if(!v||typeof v!=='object'||Array.isArray(v))throw Error('garage_paid_rejoin_unavailable');
 return v as Record<string,any>;
};
export async function paidRpc(client:Rpc,name:string,args:Record<string,unknown>){
 const r=await client.rpc(name,args);if(r.error)throw Error('garage_paid_rejoin_unavailable');return r.data;
}
export function purchase(value:unknown):PaidPurchase {
 const p=object(value);
 if(!uuid.test(p.attempt_id)||!uuid.test(p.workspace_id)||!uuid.test(p.owner_user_id)||
 !id(p.price_id,'price')||!id(p.customer_id,'cus')||!['gbp','eur','pln'].includes(p.currency)||
 !['month','year'].includes(p.billing_interval)||!Number.isSafeInteger(p.amount_minor)||p.amount_minor<=0||
 !['prepared','ready','subscribed','ended'].includes(p.state)||
 !(p.session_id===null||id(p.session_id,'cs_test'))||!(p.subscription_id===null||id(p.subscription_id,'sub')))
 throw Error('garage_paid_rejoin_unavailable');return p as PaidPurchase;
}
export async function startGaragePaidRejoin(context:Context,deps:{stripe:Stripe;client:Rpc;now?:()=>number}){
 // Reuse validated catalog policy, then REMOVE trial fields from the paid flow.
 // Durable trial history is never changed or reused as a new reservation.
 if(!uuid.test(context.actorId))throw Error('garage_paid_rejoin_unavailable');
 const trial=buildGarageSandboxTrial({...context,history:{trialUsed:false,subscriptionExists:false,checkoutPending:false}});
 const state=object(await paidRpc(deps.client,'garage_paid_rejoin_context',{
 p_actor:context.actorId,p_workspace:context.workspaceId}));
 if(state.eligible!==true||!Array.isArray(state.subscription_ids)||!state.subscription_ids.length||
 state.subscription_ids.length>100||state.subscription_ids.some((s:unknown)=>!id(s,'sub'))||
 new Set(state.subscription_ids).size!==state.subscription_ids.length)throw Error('garage_paid_rejoin_unavailable');
 // A failed collection or stale DB ending must never create a parallel sub.
 for(const prior of state.subscription_ids){
  const sub=object(await deps.stripe.subscriptions.retrieve(prior));
  if(sub.id!==prior||sub.livemode!==false||sub.customer!==context.customer.id||
   sub.status!=='canceled'||sub.test_clock!=null)throw Error('garage_paid_rejoin_reconciliation');
 }
 const p=purchase(await paidRpc(deps.client,'garage_prepare_paid_rejoin',{
 p_actor:context.actorId,p_workspace:context.workspaceId,p_plan:context.planCode,
 p_interval:context.price.recurring.interval,p_predecessors:state.subscription_ids}));
 if(p.owner_user_id!==context.actorId||p.workspace_id!==context.workspaceId||p.price_id!==context.price.id||
 p.customer_id!==context.customer.id||p.currency!==context.currency||p.billing_interval!==context.price.recurring.interval||
 p.amount_minor!==context.price.unit_amount||!['prepared','ready'].includes(p.state)||!Number.isSafeInteger(p.expires_at))
 throw Error('garage_paid_rejoin_reconciliation');
 const now=Math.floor((deps.now?.()??Date.now())/1000);
 if(p.expires_at!<=now||p.expires_at!>now+3600||
  (p.state==='prepared'&&p.expires_at!<now+40*60))throw Error('garage_paid_rejoin_reconciliation');
 const metadata={...trial.metadata,attempt_id:p.attempt_id,purchase_kind:'paid_rejoin',
 currency:p.currency,billing_interval:p.billing_interval};
 let session=p.session_id;
 if(p.state==='prepared'){
  const result=object(await deps.stripe.checkout.sessions.create({...trial,metadata,
   subscription_data:{metadata},expires_at:p.expires_at,
   integration_identifier:'flotaryx_paid_'+p.attempt_id.replaceAll('-','').slice(0,8).replace(/[0-9a-f]/g,c=>'abcdefghijklmnop'[parseInt(c,16)]),
   success_url:'https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/?portal=garage&garage_checkout=success',
   cancel_url:'https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/?portal=garage&garage_checkout=cancel',
  },{idempotencyKey:'flotaryx:garage:paid:'+p.attempt_id}));
  if(result.livemode!==false||!id(result.id,'cs_test'))throw Error('garage_paid_rejoin_reconciliation');session=result.id;
 }
 if(!session)throw Error('garage_paid_rejoin_reconciliation');
 const s=object(await deps.stripe.checkout.sessions.retrieve(session,{expand:['line_items']}));
 validatePaidSession(s,p,'open');
 if(s.id!==session)throw Error('garage_paid_rejoin_reconciliation');
 if(s.expires_at!==p.expires_at)throw Error('garage_paid_rejoin_reconciliation');
 const url=new URL(s.url);
 if(url.protocol!=='https:'||url.hostname!=='checkout.stripe.com'||url.port||url.username||url.password||
 url.pathname!==`/c/pay/${session}`)throw Error('garage_paid_rejoin_reconciliation');
 if(await paidRpc(deps.client,'garage_save_paid_rejoin',{p_actor:context.actorId,p_attempt:p.attempt_id,p_session:session})!==true)
 throw Error('garage_paid_rejoin_reconciliation');
 return {mode:'test',session_id:session,url:s.url,trial_days:0};
}
function validatePaidSession(s:Record<string,any>,p:PaidPurchase,status:string){
 const lines=s.line_items;
 if(s.id!==p.session_id&&p.session_id!==null||!id(s.id,'cs_test')||s.livemode!==false||s.mode!=='subscription'||
 s.status!==status||s.customer!==p.customer_id||s.client_reference_id!==p.workspace_id||
 s.metadata?.attempt_id!==p.attempt_id||s.metadata?.workspace_id!==p.workspace_id||s.metadata?.product!=='garage'||
 s.metadata?.purchase_kind!=='paid_rejoin'||s.metadata?.currency!==p.currency||s.metadata?.billing_interval!==p.billing_interval||
 lines?.has_more!==false||!Array.isArray(lines.data)||lines.data.length!==1||lines.data[0].quantity!==1||
 lines.data[0].price?.id!==p.price_id)throw Error('garage_paid_rejoin_reconciliation');
}

export type PaidEvent={id:string;type:string;created:number;livemode:boolean;data:{object:{id:string}}};
// Receives only a signature-verified, real-time event from the runtime; never
// exported as an HTTP endpoint. Fresh objects decide the action, not delivery order.
export async function recordPaidRejoinEvent(event:PaidEvent,deps:{client:Rpc;stripe:Stripe&{
 invoices:{retrieve(id:string):Promise<unknown>}}}){
 if(event.livemode!==false||!id(event.id,'evt')||!Number.isSafeInteger(event.created)||event.created<=0)
 throw Error('garage_paid_rejoin_receipt');
 const ended=event.type==='customer.subscription.deleted';
 if(!ended&&!['invoice.paid','invoice.payment_failed'].includes(event.type))throw Error('garage_paid_rejoin_receipt');
 let invoice:Record<string,any>|undefined;
 let subscription=event.data.object.id;
 if(!ended){
  if(!id(subscription,'in'))throw Error('garage_paid_rejoin_receipt');
  invoice=object(await deps.stripe.invoices.retrieve(subscription));
  if(invoice.id!==event.data.object.id||invoice.livemode!==false||invoice.test_clock!=null)throw Error('garage_paid_rejoin_receipt');
  subscription=invoice.subscription??invoice.parent?.subscription_details?.subscription;
 }
 if(!id(subscription,'sub'))throw Error('garage_paid_rejoin_receipt');
 const sub=object(await deps.stripe.subscriptions.retrieve(subscription));
 if(sub.id!==subscription||sub.livemode!==false||sub.test_clock!=null||sub.metadata?.purchase_kind!=='paid_rejoin'||
 !uuid.test(sub.metadata.attempt_id)||sub.trial_start!=null||sub.trial_end!=null)throw Error('garage_paid_rejoin_receipt');
 const p=purchase(await paidRpc(deps.client,'garage_lookup_paid_rejoin',{p_attempt:sub.metadata.attempt_id}));
 if(sub.customer!==p.customer_id||sub.metadata.workspace_id!==p.workspace_id||sub.metadata.product!=='garage'||
 sub.metadata.currency!==p.currency||sub.metadata.billing_interval!==p.billing_interval||!p.session_id||
 (p.subscription_id!==null&&p.subscription_id!==sub.id)||sub.items?.has_more!==false||
 sub.items.data?.length!==1||sub.items.data[0].quantity!==1)throw Error('garage_paid_rejoin_receipt');
 const price=sub.items.data[0].price;
 if(price?.id!==p.price_id||price.livemode!==false||price.currency!==p.currency||price.unit_amount!==p.amount_minor||
 price.recurring?.interval!==p.billing_interval||price.recurring.interval_count!==1||price.recurring.usage_type!=='licensed')
 throw Error('garage_paid_rejoin_receipt');
 const session=object(await deps.stripe.checkout.sessions.retrieve(p.session_id,{expand:['line_items']}));
 validatePaidSession(session,p,'complete');
 if(session.subscription!==sub.id)throw Error('garage_paid_rejoin_receipt');
 if(!['active','past_due','unpaid','incomplete','canceled'].includes(sub.status))throw Error('garage_paid_rejoin_receipt');
 // canceled_at can be the earlier stop-renewal request; only ended_at caps access.
 if(sub.status==='canceled'&&(!Number.isSafeInteger(sub.ended_at)||sub.ended_at<=0))throw Error('garage_paid_rejoin_receipt');
 const record:Record<string,unknown>={attempt_id:p.attempt_id,session_id:p.session_id,workspace_id:p.workspace_id,
 subscription_id:sub.id,customer_id:p.customer_id,livemode:false,test_clock:'none',
 event_id:event.id,event_created_at:new Date(event.created*1000).toISOString(),event_type:event.type,object_id:event.data.object.id};
 if(ended){
  if(sub.status!=='canceled')throw Error('garage_paid_rejoin_receipt');
  Object.assign(record,{action:'ended',ended_at:new Date(sub.ended_at*1000).toISOString()});
 }else{
  const i=invoice!;const line=i.lines?.data?.[0];
  if(i.customer!==p.customer_id||!['subscription_create','subscription_cycle'].includes(i.billing_reason)||
   i.currency!==p.currency||i.amount_due!==p.amount_minor||i.lines?.has_more!==false||i.lines.data.length!==1||
   line?.quantity!==1||(line.price?.id??line.pricing?.price_details?.price)!==p.price_id||
   !Number.isSafeInteger(line.period?.start)||!Number.isSafeInteger(line.period?.end)||line.period.start<=0||line.period.end<=line.period.start)
   throw Error('garage_paid_rejoin_receipt');
  const paid=i.status==='paid'&&(i.paid===undefined||i.paid===true)&&i.amount_paid===p.amount_minor&&i.amount_remaining===0&&Number.isSafeInteger(i.status_transitions?.paid_at)&&i.status_transitions.paid_at>0;
  if(!paid&&(event.type!=='invoice.payment_failed'||i.status!=='open'||i.amount_paid!==0||i.amount_remaining!==p.amount_minor||!Number.isSafeInteger(i.attempt_count)||i.attempt_count<1))
   throw Error('garage_paid_rejoin_receipt');
  Object.assign(record,{action:paid?'paid':'failed',price_id:p.price_id,currency:p.currency,billing_interval:p.billing_interval,
  period_start:new Date(line.period.start*1000).toISOString(),period_end:new Date(line.period.end*1000).toISOString(),
  subscription_ended_at:sub.status==='canceled'?new Date(sub.ended_at*1000).toISOString():null,
  billing_reason:i.billing_reason,amount_due:i.amount_due,amount_paid:i.amount_paid,
  paid_at:paid?new Date(i.status_transitions.paid_at*1000).toISOString():null});
 }
 if(await paidRpc(deps.client,'garage_record_paid_rejoin',{p_record:record})!==true)throw Error('garage_paid_rejoin_receipt');
}
