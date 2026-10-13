import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';

const base = process.env.QA_SUPABASE_URL;
const apiKey = process.env.QA_SUPABASE_PUBLISHABLE_KEY;
const run = process.env.GITHUB_RUN_ID;
if (!base?.startsWith('https://fyestmquqvkdebxxbcky.supabase.co') || !apiKey?.startsWith('sb_publishable_') || !/^\d+$/.test(run ?? '')) {
  throw new Error('QA endpoint, public API key or Actions run ID is invalid');
}

const email = `flotaryx-qa-e2e-${run}@example.com`;
const password = randomBytes(28).toString('hex');
const ids = {
  active: 'f7bda110-837e-4fd6-a956-4bbb7891465c',
  expired: '1b28384a-f868-419e-b501-e933e51e44d2',
  canceled: 'a10d1a37-ef06-4553-af6f-f780c01f9f70',
};
const headers = { apikey: apiKey, 'Content-Type': 'application/json' };
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
async function request(path, options = {}) {
  const res = await fetch(new URL(path, base), {
    ...options, headers: { ...headers, ...options.headers },
    signal: AbortSignal.timeout(15000),
  });
  let data;
  const value = await res.text();
  try { data = JSON.parse(value); } catch { data = value; }
  return { status: res.status, ok: res.ok, data };
}
function requireStatus(result, code, label) {
  assert.equal(result.status, code, `${label} returned HTTP ${result.status}: ${JSON.stringify(result.data).slice(0, 250)}`);
}
function requireInactive(result, label) {
  assert.ok(result.status >= 400 && result.status < 500, `${label}: expected HTTP denial, got ${result.status}`);
  assert.match(JSON.stringify(result.data), /Fleet subscription is inactive/i, `${label}: wrong denial reason`);
}
console.log('Isolated QA JWT/PostgREST test. User email: ' + email);
const signup = await request('/auth/v1/signup', {
  method: 'POST', body: JSON.stringify({ email, password, data: { qa_run: run } }),
});
if (!signup.ok) {
  console.error('Signup unavailable: HTTP ' + signup.status + ' - ' + JSON.stringify(signup.data).slice(0, 250));
  process.exit(2);
}
const userId = signup.data?.user?.id ?? signup.data?.id;
assert.match(userId ?? '', /^[a-f0-9-]{36}$/, 'Auth signup did not create a test user');
console.log('Created synthetic QA Auth user ' + userId + '. Waiting for email confirmation and QA memberships.');
const deadline = Date.now() + 9 * 60_000;
let accessToken = signup.data?.session?.access_token ?? signup.data?.access_token;
while (!accessToken && Date.now() < deadline) {
  const token = await request('/auth/v1/token?grant_type=password', {
    method:'POST', body: JSON.stringify({email,password}),
  });
  if (token.ok && token.data?.access_token) {
    accessToken = token.data.access_token;
    break;
  }
  await wait(10000);
}
if (!accessToken) throw new Error('Test user not email-verified within 9 minutes; stop without modifying fleet data');
const auth = {Authorization:'Bearer ' + accessToken};
console.log('Real access JWT issued. Checking fleet memberships without printing tokens.');
let memberships;
while (Date.now() < deadline) {
  memberships=await request('/rest/v1/company_members?select=company_id,role', {headers:auth});
  if (memberships.ok && Array.isArray(memberships.data)
      && [ids.active,ids.expired,ids.canceled].every(id =>
         memberships.data.some(row=>row.company_id===id && row.role==='owner'))) break;
  await wait(8000);
}
assert.ok(memberships?.ok && memberships.data?.length >= 3, 'QA memberships were not granted before timeout');
const user=await request('/auth/v1/user',{headers:auth});
requireStatus(user,200,'auth user');
assert.equal(user.data?.id,userId,'Session belongs to wrong user');
console.log('Authenticated QA owner memberships verified.');

const readExpired=await request('/rest/v1/drivers?select=id,name,notes&company_id=eq.'+ids.expired,{headers:auth});
requireStatus(readExpired,200,'read expired fleet');
assert.equal(readExpired.data?.length,1,'Read of expired fleet should remain available');
const readActive=await request('/rest/v1/drivers?select=id,name,notes&company_id=eq.'+ids.active,{headers:auth});
requireStatus(readActive,200,'read active fleet');
assert.equal(readActive.data?.length,1,'Active fleet driver must be readable');

const expireInsert=await request('/rest/v1/drivers',{
  method:'POST',headers:{...auth, Prefer:'return=representation'},
  body:JSON.stringify({company_id:ids.expired,name:'QA HTTP must reject'}),
});
requireInactive(expireInsert,'expired fleet INSERT');

const expireUpdate=await request('/rest/v1/drivers?id=eq.'+readExpired.data[0].id,{
  method:'PATCH',headers:{...auth,Prefer:'return=representation'},
  body:JSON.stringify({notes:'QA HTTP must reject'}),
});
requireInactive(expireUpdate,'expired fleet UPDATE');

const canceledGarages=await request('/rest/v1/garages?select=id,notes&company_id=eq.'+ids.canceled,{headers:auth});
requireStatus(canceledGarages,200,'read canceled garages');
assert.equal(canceledGarages.data?.length,1,'Canceled garage must be readable');
const canceledUpdate=await request('/rest/v1/garages?id=eq.'+canceledGarages.data[0].id,{
  method:'PATCH',headers:{...auth,Prefer:'return=representation'},
  body:JSON.stringify({notes:'QA HTTP must reject'}),
});
requireInactive(canceledUpdate,'canceled fleet UPDATE');

const activeUpdate=await request('/rest/v1/drivers?id=eq.'+readActive.data[0].id,{
  method:'PATCH',headers:{...auth,Prefer:'return=representation'},
  body:JSON.stringify({notes:'qa-e2e-temporary-'+run}),
});
requireStatus(activeUpdate,200,'active fleet UPDATE');
assert.equal(activeUpdate.data?.length,1);
const restore=await request('/rest/v1/drivers?id=eq.'+readActive.data[0].id,{
  method:'PATCH',headers:{...auth,Prefer:'return=representation'},
  body:JSON.stringify({notes:readActive.data[0].notes}),
});
requireStatus(restore,200,'restore active fleet fixture');
assert.equal(restore.data?.length,1);
console.log('PASS: real login/JWT, owner RLS, expired read, active read, expired insert, expired update, canceled read/update, active edit, fixture restoration.');
console.log('Synthetic QA user can now be deleted via admin tooling; no production credentials involved.');
