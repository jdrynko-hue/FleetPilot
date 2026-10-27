import Stripe from 'stripe';
import {createClient} from 'supabase';
import {managePaidRenewal} from './paid_renewal.ts';
import {createPaidRenewalHandler} from './paid_renewal_http.ts';
export function createPaidRenewalRuntime(config:{enabled?:boolean;supabaseUrl:string;
 anonKey?:string;serviceKey?:string;stripeKey?:string}){
 const {enabled,supabaseUrl,anonKey,serviceKey,stripeKey}=config;
 if(enabled!==true||supabaseUrl!=='https://fyestmquqvkdebxxbcky.supabase.co'||
 !anonKey||!serviceKey||anonKey===serviceKey||!stripeKey||!/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey))
  return async(_r:Request)=>new Response(JSON.stringify({error:'Paid renewal unavailable'}),
   {status:503,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
 const options={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
 const auth=createClient(supabaseUrl,anonKey,options).auth;
 const service=createClient(supabaseUrl,serviceKey,options);
 const stripe=new Stripe(stripeKey,{httpClient:Stripe.createFetchHttpClient(),timeout:12000,maxNetworkRetries:0});
 return createPaidRenewalHandler({enabled:true,supabaseUrl},{auth,
  manage:(context,action)=>managePaidRenewal(context,action,{
   async load(c){const r=await service.rpc('garage_paid_renewal_context',{p_actor:c.actorId,p_workspace:c.workspaceId});
    if(r.error)throw Error('Unavailable');return r.data;},
   stripe:{subscriptions:{retrieve:id=>stripe.subscriptions.retrieve(id),
    update:(id,params,options)=>stripe.subscriptions.update(id,params,options)}}
  })});
}
