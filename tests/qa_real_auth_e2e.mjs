import assert from 'node:assert/strict';

const base = process.env.QA_SUPABASE_URL;
const apiKey = process.env.QA_SUPABASE_PUBLISHABLE_KEY;
const run = process.env.GITHUB_RUN_ID ?? process.env.QA_RUN_ID ?? 'manual';
const qaUrl = 'https://fyestmquqvkdebxxbcky.supabase.co';
if (base !== qaUrl || !apiKey?.startsWith('sb_publishable_')) {
  throw new Error('Require the exact isolated QA endpoint and a QA publishable API key');
}
const email = process.env.QA_TEST_EMAIL;
const password = process.env.QA_TEST_PASSWORD;
if (!email || !password) {
  throw new Error('A pre-verified QA account is required. Supply QA_TEST_EMAIL and QA_TEST_PASSWORD securely at runtime; never commit credentials.');
}
const ids = {
  active: 'f7bda110-837e-4fd6-a956-4bbb7891465c',
  expired: '1b28384a-f868-419e-b501-e933e51e44d2',
  canceled: 'a10d1a37-ef06-4553-af6f-f780c01f9f70',
};
const headers = { apikey: apiKey, 'Content-Type': 'application/json' };
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
console.log('Testing a pre-verified QA account with real Supabase Auth and PostgREST.');
const session = await request('/auth/v1/token?grant_type=password', {
  method: 'POST', body: JSON.stringify({ email, password }),
});
requireStatus(session, 200, 'QA password login');
const accessToken = session.data?.access_token;
assert.ok(typeof accessToken === 'string' && accessToken.length > 40, 'QA login did not return a real access token');
const auth = { Authorization: 'Bearer ' + accessToken };
const user = await request('/auth/v1/user', { headers: auth });
requireStatus(user, 200, 'authenticated user');
assert.match(user.data?.id ?? '', /^[a-f0-9-]{36}$/i, 'QA account has no authenticated user ID');
const memberships = await request('/rest/v1/company_members?select=company_id,role', { headers: auth });
requireStatus(memberships, 200, 'QA fleet membership preflight');
assert.ok(Array.isArray(memberships.data), 'QA memberships response is not an array');
const missing = [ids.active, ids.expired, ids.canceled].filter(id =>
  !memberships.data.some(row => row.company_id === id && row.role === 'owner'));
assert.deepEqual(missing, [], 'QA test user must be explicitly granted owner membership in all synthetic QA fleets before running any write tests');
console.log('Verified JWT and all three synthetic QA owner memberships.');


const anonRead = await request('/rest/v1/drivers?select=id,name&company_id=eq.' + ids.expired);
assert.ok(
  anonRead.status === 401 || anonRead.status === 403 ||
  (anonRead.status === 200 && Array.isArray(anonRead.data) && anonRead.data.length === 0),
  'An unauthenticated request must never access an expired fleet driver record'
);
console.log('Unauthenticated fleet data visibility denied.');
// A fleet owner is deliberately NOT authorized to change Stripe billing status via PostgREST.
const billingTamper = await request('/rest/v1/company_subscriptions?company_id=eq.' + ids.expired, {
  method: 'PATCH',
  headers: { ...auth, Prefer: 'return=representation' },
  body: JSON.stringify({ status: 'active' }),
});
assert.ok(
  billingTamper.status === 401 || billingTamper.status === 403 || billingTamper.status === 405,
  'A normal authenticated fleet owner must not be able to modify company_subscriptions'
);
console.log('Direct subscription tampering denied.');

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

let didChangeActiveFixture = false;
try {
  const activeUpdate=await request('/rest/v1/drivers?id=eq.'+readActive.data[0].id,{
    method:'PATCH',headers:{...auth,Prefer:'return=representation'},
    body:JSON.stringify({notes:'qa-e2e-temporary-'+run}),
  });
  didChangeActiveFixture = activeUpdate.status >= 200 && activeUpdate.status < 300;
  requireStatus(activeUpdate,200,'active fleet UPDATE');
  assert.equal(activeUpdate.data?.length,1);
} finally {
  if (didChangeActiveFixture) {
    const restore=await request('/rest/v1/drivers?id=eq.'+readActive.data[0].id,{
      method:'PATCH',headers:{...auth,Prefer:'return=representation'},
      body:JSON.stringify({notes:readActive.data[0].notes}),
    });
    requireStatus(restore,200,'restore active fleet fixture');
    assert.equal(restore.data?.length,1);
  }
}
console.log('PASS: real JWT login, owner RLS, anonymous data protection, subscription write protection, expired/canceled read-only fleet access, active fleet edit and fixture restoration.');
console.log('QA credentials were supplied only at runtime; the test did not register any user.');
