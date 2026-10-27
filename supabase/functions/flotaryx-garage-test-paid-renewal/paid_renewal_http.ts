import {type RenewalContext,type RenewalStatus} from './paid_renewal.ts';
const qa='https://fyestmquqvkdebxxbcky.supabase.co';
const origin='https://flotaryx-qa-preview.fairdrake9.chatgpt.site';
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
export function createPaidRenewalHandler(config:{enabled?:boolean;supabaseUrl:string},deps:{
 auth:{getUser(token:string):Promise<{data:{user:{id:string;is_anonymous?:boolean}|null};error:unknown}>};
 manage(context:RenewalContext,action:'status'|'stop'):Promise<RenewalStatus>;
}){
 const headers={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',
 'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST, OPTIONS',
 'Access-Control-Allow-Headers':'authorization, apikey, x-client-info, content-type','Vary':'Origin'};
 const reply=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers});
 return async(request:Request)=>{
  if(request.headers.get('origin')&&request.headers.get('origin')!==origin)return reply(403,{error:'Origin not allowed'});
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return reply(405,{error:'POST required'});
  if(config.enabled!==true||config.supabaseUrl!==qa)return reply(503,{error:'Paid renewal unavailable'});
  const authorization=request.headers.get('authorization')??'';
  if(!/^Bearer \S+$/.test(authorization)||authorization.length>4096)return reply(401,{error:'Sign-in required'});
  if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')return reply(415,{error:'JSON required'});
  let raw:any;
  try{
   const reader=request.body?.getReader();if(!reader)throw Error();
   const chunks:Uint8Array[]=[];let size=0;
   try{while(true){const r=await reader.read();if(r.done)break;
    size+=r.value.length;if(size>1024){await reader.cancel();throw Error();}chunks.push(r.value);
   }}finally{reader.releaseLock();}
   const bytes=new Uint8Array(size);let at=0;for(const c of chunks){bytes.set(c,at);at+=c.length;}
   raw=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
   if(!raw||Array.isArray(raw)||Object.keys(raw).sort().join(',')!=='action,workspace_id'||
    typeof raw.workspace_id!=='string'||!uuid.test(raw.workspace_id)||!['status','stop'].includes(raw.action))throw Error();
  }catch{return reply(400,{error:'Invalid request'});}
  try{
   const verified=await deps.auth.getUser(authorization.slice(7));const user=verified.data.user;
   if(verified.error||!user||user.is_anonymous===true||!uuid.test(user.id))return reply(401,{error:'Sign-in required'});
   const result=await deps.manage({actorId:user.id,workspaceId:raw.workspace_id},raw.action);
   if(!result||Object.keys(result).sort().join(',')!=='access_ends_at,status'||
    !['renewing','stopping'].includes(result.status)||typeof result.access_ends_at!=='string'||
    !Number.isSafeInteger(Date.parse(result.access_ends_at))||
    (raw.action==='stop'&&result.status!=='stopping'))throw Error();
   return reply(200,result);
  }catch{return reply(503,{error:'Paid renewal could not be confirmed'});}
 };
}
