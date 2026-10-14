// True local Supabase integration smoke tests: GoTrue + PostgREST + RLS.
// Only run against ephemeral Supabase CLI containers, NEVER linked/hosted.
// No service-role key is used: real test users authorize every API request.
import assert from 'node:assert/strict';

const url = process.env.GARAGE_TEST_API_URL?.replace(/\/$/, '');
const anon = process.env.GARAGE_TEST_ANON_KEY;

if (!url || !anon || !/^https?:\/\/(127\.0\.0\.1|localhost):\d+$/.test(url)) {
  throw new Error('Garage integration tests require loopback-only local Supabase');
}

async function http(path, { jwt, method = 'GET', body, prefer } = {}) {
  const headers = {
    apikey: anon,
    authorization: `Bearer ${jwt ?? anon}`,
    accept: 'application/json',
  };
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (prefer) headers.prefer = prefer;
  const res = await fetch(url + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const raw = await res.text();
  let value;
  try { value = raw ? JSON.parse(raw) : null; } catch { value = raw; }
  return { status: res.status, ok: res.ok, value };
}

function mustPass(response, context) {
  assert.equal(response.ok, true, `${context} failed: HTTP ${response.status}: ${JSON.stringify(response.value).slice(0,260)}`);
  return response.value;
}

function mustDeny(response, context) {
  assert.equal(response.ok, false, `${context} unexpectedly succeeded`);
  assert.ok([400, 401, 403, 404, 409].includes(response.status), `${context}: wrong error ${response.status}`);
}

async function signup(label) {
  const email = `flotaryx-garage-${label}@example.test`;
  const response = mustPass(await http('/auth/v1/signup', {
    method: 'POST',
    body: { email, password: `OnlyLocal-QA-${label}-2026!m9` },
  }), 'local signup ' + label);
  assert.ok(response.user?.id, 'new Auth user must have ID');
  assert.ok(response.access_token, 'local email confirmations must be disabled');
  return { email, id: response.user.id, jwt: response.access_token };
}

async function createWorkspace(owner, name) {
  const result = mustPass(await http('/rest/v1/garage_workspaces?select=id', {
    method: 'POST', jwt: owner.jwt, prefer: 'return=representation',
    body: { owner_user_id: owner.id, name, country: 'GB', currency: 'GBP' },
  }), 'create workshop');
  assert.equal(result.length, 1);
  assert.match(result[0].id, /^[0-9a-f-]{36}$/i);
  return result[0].id;
}

async function rpc(user, name, args) {
  return await http(`/rest/v1/rpc/${name}`, {
    method: 'POST', jwt: user.jwt, body: args,
  });
}

function onlyOne(rows, context) {
  assert.ok(Array.isArray(rows) && rows.length === 1, context);
  return rows[0];
}

const ownerA = await signup('owner-a');
const ownerB = await signup('owner-b');
const mechanic = await signup('mechanic-a');
const outsider = await signup('outsider');

const shopA = await createWorkspace(ownerA, 'Garage E2E Alpha');
const shopB = await createWorkspace(ownerB, 'Garage E2E Beta');
assert.notEqual(shopA, shopB);

const shopsA = mustPass(await http('/rest/v1/garage_workspaces?select=id', {
  jwt: ownerA.jwt,
}), 'owner A workspace read');
assert.equal(onlyOne(shopsA, 'owner A only sees one workspace').id, shopA);
const shopsOutsider = mustPass(await http('/rest/v1/garage_workspaces?select=id', {
  jwt: outsider.jwt,
}), 'outsider workspace read');
assert.deepEqual(shopsOutsider, []);

const customer = onlyOne(mustPass(await http('/rest/v1/garage_customers?select=id', {
  method: 'POST', jwt: ownerA.jwt, prefer: 'return=representation',
  body: { workspace_id: shopA, customer_type: 'individual',
          display_name: 'Local Customer A', email: 'private@example.test' },
}), 'create customer'), 'one customer');

const vehicle = onlyOne(mustPass(await http('/rest/v1/garage_vehicles?select=id', {
  method: 'POST', jwt: ownerA.jwt, prefer: 'return=representation',
  body: { workspace_id: shopA, customer_id: customer.id,
          registration: 'E2E-S1', make: 'Ford', model: 'Focus' },
}), 'create vehicle'), 'one vehicle');

const order = onlyOne(mustPass(await http('/rest/v1/garage_work_orders?select=id', {
  method: 'POST', jwt: ownerA.jwt, prefer: 'return=representation',
  body: { workspace_id: shopA, vehicle_id: vehicle.id,
          complaint: 'Front brake rattle' },
}), 'create work order'), 'one work order');

const inviteToken = mustPass(await rpc(
  ownerA, 'garage_issue_staff_invite',
  { p_workspace_id: shopA, p_email: mechanic.email, p_role: 'mechanic' },
), 'issue mechanic invitation');
assert.match(inviteToken, /^[a-f0-9]{32}$/);

mustDeny(await rpc(
  outsider, 'garage_accept_staff_invite', { p_token: inviteToken },
), 'wrong email cannot accept');
mustDeny(await rpc(
  ownerB, 'garage_assign_mechanic',
  { p_workspace_id: shopA, p_order_id: order.id, p_mechanic_user_id: mechanic.id },
), 'other workshop owner cannot assign');

assert.equal(mustPass(await rpc(
  mechanic, 'garage_accept_staff_invite', { p_token: inviteToken },
), 'mechanic accepts own invitation'), shopA);
mustDeny(await rpc(
  mechanic, 'garage_accept_staff_invite', { p_token: inviteToken },
), 'consumed invitation cannot be reused');

assert.equal(mustPass(await rpc(ownerA, 'garage_assign_mechanic', {
  p_workspace_id: shopA, p_order_id: order.id, p_mechanic_user_id: mechanic.id,
}), 'owner assigns mechanic'), mechanic.id);

const assigned = mustPass(await rpc(mechanic, 'garage_my_assigned_jobs', {
  p_workspace_id: shopA,
}), 'mechanic reads assigned orders');
const job = onlyOne(assigned, 'mechanic must get exactly one assigned work order');
assert.equal(job.id, order.id);
assert.equal(job.registration, 'E2E-S1');
assert.equal(job.status, 'received');
assert.equal(job.make, 'Ford');
assert.ok(!Object.hasOwn(job, 'email') && !Object.hasOwn(job, 'customer_email'),
  'mechanic projection must not include customer contact info');

const otherJobs = mustPass(await rpc(mechanic, 'garage_my_assigned_jobs', {
  p_workspace_id: shopB,
}), 'mechanic tries other garage');
assert.deepEqual(otherJobs, []);
assert.deepEqual(mustPass(await http('/rest/v1/garage_customers?select=*', {
  jwt: mechanic.jwt,
}), 'mechanic customer PII read'), []);
assert.deepEqual(mustPass(await rpc(outsider, 'garage_my_assigned_jobs', {
  p_workspace_id: shopA,
}), 'outsider tries assigned job list'), []);

assert.equal(mustPass(await rpc(mechanic, 'garage_begin_diagnosis', {
  p_workspace_id: shopA, p_order_id: order.id,
}), 'assigned mechanic starts diagnosis'), 'diagnosing');
mustDeny(await rpc(mechanic, 'garage_begin_diagnosis', {
  p_workspace_id: shopA, p_order_id: order.id,
}), 'duplicate diagnosis transition');

const events = mustPass(await http(
  `/rest/v1/garage_order_events?order_id=eq.${order.id}&select=action,previous_status,next_status`,
  { jwt: mechanic.jwt },
), 'mechanic reads own audit events');
assert.equal(events.length, 2, 'assignment + diagnosis event required');
assert.equal(events[0].action, 'assign_mechanic');
assert.equal(events[1].action, 'begin_diagnosis');

const ownerBOrders = mustPass(await http('/rest/v1/garage_work_orders?select=id', {
  jwt: ownerB.jwt,
}), 'owner B sees own orders');
assert.deepEqual(ownerBOrders, [], 'owner B cannot see shop A jobs');
console.log('PASS local Supabase Auth + PostgREST: two garages, four users, invites, RLS, mechanic assignments, diagnosis audit');
