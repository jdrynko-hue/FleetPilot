import { randomUUID } from 'node:crypto';
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
const privateCustomer = await signup('private-customer');

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
          display_name: 'Local Customer A', email: privateCustomer.email },
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
// Workshop creates quote revision 1, but cannot self-authorize the repair.
const quote1 = [{
  type: 'labour', description: 'Brake diagnostics, two hours',
  quantity: 2, unit_price_minor: 3000, tax_minor: 1200,
}];
assert.equal(mustPass(await rpc(ownerA, 'garage_publish_quote', {
  p_workspace_id: shopA, p_order_id: order.id, p_lines: quote1,
}), 'publish first quote'), 1);
mustDeny(await rpc(mechanic, 'garage_start_approved_repair', {
  p_workspace_id: shopA, p_order_id: order.id,
}), 'cannot start repair without verified customer approval');
mustDeny(await rpc(ownerA, 'garage_customer_approve_quote', {
  p_workspace_id: shopA, p_order_id: order.id, p_revision: 1,
}), 'workshop cannot self-approve');

const privateQuote = mustPass(await rpc(
  privateCustomer, 'garage_customer_current_quote',
  { p_workspace_id: shopA, p_order_id: order.id },
), 'verified private customer reads quote');
assert.equal(privateQuote.revision, 1);
assert.equal(privateQuote.currency, 'GBP');
assert.equal(privateQuote.total_minor, 7200);
assert.equal(privateQuote.approved, false);
assert.equal(privateQuote.lines.length, 1);
mustDeny(await rpc(outsider, 'garage_customer_current_quote', {
  p_workspace_id: shopA, p_order_id: order.id,
}), 'unrelated email cannot view quote');
mustDeny(await rpc(ownerB, 'garage_customer_current_quote', {
  p_workspace_id: shopA, p_order_id: order.id,
}), 'other garage cannot read private quote');
assert.deepEqual(mustPass(await http('/rest/v1/garage_quote_revisions?select=*', {
  jwt: mechanic.jwt,
}), 'mechanic cannot see pricing'), []);

assert.equal(mustPass(await rpc(privateCustomer, 'garage_customer_approve_quote', {
  p_workspace_id: shopA, p_order_id: order.id, p_revision: 1,
}), 'private customer approves first estimate'), 1);
mustDeny(await rpc(privateCustomer, 'garage_customer_approve_quote', {
  p_workspace_id: shopA, p_order_id: order.id, p_revision: 1,
}), 'approval is single-use for each revision');

const quote2 = [{
  type: 'part', description: 'Replacement brake discs',
  quantity: 1, unit_price_minor: 8500, tax_minor: 1700,
}];
assert.equal(mustPass(await rpc(ownerA, 'garage_publish_quote', {
  p_workspace_id: shopA, p_order_id: order.id, p_lines: quote2,
}), 'publish second revision'), 2);
mustDeny(await rpc(mechanic, 'garage_start_approved_repair', {
  p_workspace_id: shopA, p_order_id: order.id,
}), 'old approval does not authorize a new revision');
mustDeny(await rpc(privateCustomer, 'garage_customer_approve_quote', {
  p_workspace_id: shopA, p_order_id: order.id, p_revision: 1,
}), 'stale approval revision rejected');
mustDeny(await http(`/rest/v1/garage_customers?id=eq.${customer.id}`, {
  method: 'PATCH', jwt: ownerA.jwt,
  body: { email: ownerA.email },
}), 'cannot redirect established approval to workshop email');
const updatedQuote = mustPass(await rpc(
  privateCustomer, 'garage_customer_current_quote',
  { p_workspace_id: shopA, p_order_id: order.id },
), 'customer reads revised quote');
assert.equal(updatedQuote.revision, 2);
assert.equal(updatedQuote.total_minor, 10200);
assert.equal(updatedQuote.approved, false);

assert.equal(mustPass(await rpc(privateCustomer, 'garage_customer_approve_quote', {
  p_workspace_id: shopA, p_order_id: order.id, p_revision: 2,
}), 'approve exact revision 2'), 2);
assert.equal(mustPass(await rpc(mechanic, 'garage_start_approved_repair', {
  p_workspace_id: shopA, p_order_id: order.id,
}), 'assigned mechanic begins approved work'), 'in_progress');
mustDeny(await rpc(mechanic, 'garage_start_approved_repair', {
  p_workspace_id: shopA, p_order_id: order.id,
}), 'cannot start repair twice');
const updatedOrders = mustPass(await http(
  `/rest/v1/garage_work_orders?id=eq.${order.id}&select=id,status`,
  { jwt: ownerA.jwt },
), 'work order after quote approval');
assert.equal(onlyOne(updatedOrders, 'approved work order').status, 'in_progress');

const approvalAudit = mustPass(await http(
  `/rest/v1/garage_order_events?order_id=eq.${order.id}&select=action`,
  { jwt: ownerA.jwt },
), 'approval event audit');
assert.equal(approvalAudit.filter(x => x.action === 'publish_quote').length, 2);
assert.equal(approvalAudit.filter(x => x.action === 'customer_approve_quote').length, 2);
assert.equal(approvalAudit.filter(x => x.action === 'start_approved_repair').length, 1);
assert.deepEqual(mustPass(await http('/rest/v1/garage_quote_approvals?select=*', {
  jwt: outsider.jwt,
}), 'outsider cannot query raw approved estimates'), []);

const overseasJob = onlyOne(mustPass(await http(
  '/rest/v1/garage_work_orders?select=id', {
    method:'POST',jwt:ownerA.jwt,prefer:'return=representation',
    body:{
      workspace_id:shopA,vehicle_id:vehicle.id,
      assigned_user_id:mechanic.id,
      complaint:'International customer brake inspection'
    },
  }
), 'create foreign-currency work order'), 'one foreign-currency job');
assert.equal(mustPass(await rpc(mechanic,'garage_begin_diagnosis',{
  p_workspace_id:shopA,p_order_id:overseasJob.id,
}), 'diagnosis for foreign-currency job'), 'diagnosing');
assert.equal(mustPass(await rpc(ownerA,'garage_publish_quote',{
  p_workspace_id:shopA,p_order_id:overseasJob.id,
  p_lines:[{
    type:'labour',description:'Overseas brake service',
    quantity:1,unit_price_minor:12000,tax_minor:0,
  }],
  p_currency:'JPY',
}), 'JPY quote override'),1);
const yenEstimate=mustPass(await rpc(
  privateCustomer,'garage_customer_current_quote',{
    p_workspace_id:shopA,p_order_id:overseasJob.id,
  }),
  'customer sees chosen JPY currency');
assert.equal(yenEstimate.currency,'JPY');
assert.equal(yenEstimate.total_minor,12000);
assert.equal(mustPass(await rpc(ownerA,'garage_publish_quote',{
  p_workspace_id:shopA,p_order_id:overseasJob.id,
  p_lines:[{
    type:'labour',description:'Overseas service revision',
    quantity:1,unit_price_minor:13000,tax_minor:0,
  }],
  p_currency:'JPY',
}), 'same JPY currency on second quote revision'),2);
mustDeny(await rpc(ownerA,'garage_publish_quote',{
  p_workspace_id:shopA,p_order_id:overseasJob.id,
  p_lines:[{
    type:'labour',description:'Unsupported currency switch',
    quantity:1,unit_price_minor:13000,tax_minor:0,
  }],
  p_currency:'KWD',
}), 'cannot change currency in existing approved quote series');
mustDeny(await rpc(ownerA,'garage_publish_quote',{
  p_workspace_id:shopA,p_order_id:overseasJob.id,
  p_lines:[{
    type:'labour',description:'Invalid arbitrary currency',
    quantity:1,unit_price_minor:13000,tax_minor:0,
  }],
  p_currency:'XXX',
}), 'invalid ISO currency code rejected');
console.log('PASS local garage quote currency override, customer visibility and revision consistency');

console.log('PASS local Supabase Auth + PostgREST: two garages, five users, invites, RLS, mechanic assignment, verified quote revisions and repair-start approval');

// Actual Storage endpoints, not direct database writes. JWT roles exercise
// Storage's underlying storage.objects RLS and dedicated private bucket.
const mediaBucket = 'flotaryx-garage-private';
const mediaFolder = shopA + '/' + order.id + '/';
const photoPath = mediaFolder + 'photos/' + randomUUID() + '.png';
const documentPath = mediaFolder + 'documents/' + randomUUID() + '.pdf';
const onePixelPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
  'base64',
);
const documentBytes = Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF');

async function storageCall(user, path, options = {}) {
  const headers = {
    apikey: anon,
    authorization: 'Bearer ' + user.jwt,
    ...(options.mime ? {'content-type': options.mime} : {}),
    ...(options.headers ?? {}),
  };
  const response = await fetch(url + '/storage/v1/' + path, {
    method: options.method ?? 'GET',
    headers,
    body: options.body,
  });
  const data = await response.text();
  let value = data;
  try { value = data ? JSON.parse(data) : null; } catch {}
  return { status: response.status, ok: response.ok, value };
}
function storageDenied(response, scenario) {
  assert.equal(response.ok, false, scenario + ' should be denied');
  assert.ok([400,401,403,404,409,413,415,422].includes(response.status),
    scenario + ': HTTP ' + response.status);
}
function upload(user, path, bytes, mime = 'image/png', headers) {
  return storageCall(user, 'object/' + mediaBucket + '/' + path, {
    method: 'POST', body: bytes, mime, headers,
  });
}
function download(user, path, isPublic = false) {
  return storageCall(user,
    'object/' + (isPublic ? 'public/' : 'authenticated/') + mediaBucket + '/' + path);
}
function listStorage(user, prefix) {
  return storageCall(user, 'object/list/' + mediaBucket, {
    method: 'POST', mime: 'application/json',
    body: JSON.stringify({ prefix, limit: 100, offset: 0 }),
  });
}

mustPass(await upload(mechanic, photoPath, onePixelPng),
  'assigned mechanic can upload photo');
mustPass(await upload(ownerA, documentPath, documentBytes, 'application/pdf'),
  'owner uploads invoice PDF');
mustPass(await download(mechanic, photoPath),
  'assigned mechanic reads photo');
mustPass(await download(ownerA, documentPath),
  'owner reads workshop document');
storageDenied(await storageCall(ownerA,
  'object/sign/' + mediaBucket + '/' + photoPath, {
    method: 'POST', mime: 'application/json',
    body: JSON.stringify({expiresIn: 3600}),
  }),
  'workshop staff must not issue signed evidence URLs');
storageDenied(await storageCall(mechanic,
  'object/sign/' + mediaBucket + '/' + photoPath, {
    method: 'POST', mime: 'application/json',
    body: JSON.stringify({expiresIn: 3600}),
  }),
  'assigned mechanic must not issue signed evidence URLs');
storageDenied(await download(mechanic, documentPath),
  'mechanic cannot read financial PDF');
storageDenied(await download(ownerB, documentPath),
  'other garage cannot read document');
storageDenied(await download(outsider, photoPath),
  'outsider cannot read photo');
storageDenied(await download(privateCustomer, photoPath),
  'customer cannot read internal repair evidence');
storageDenied(await download(ownerA, photoPath, true),
  'private bucket is never publicly downloadable');
storageDenied(await upload(ownerB, mediaFolder + 'photos/' + randomUUID() + '.png', onePixelPng),
  'other garage cannot upload to Garage A');
storageDenied(await upload(outsider, mediaFolder + 'photos/' + randomUUID() + '.png', onePixelPng),
  'stranger cannot upload repair photo');
storageDenied(await upload(mechanic, mediaFolder + 'documents/' + randomUUID() + '.pdf',
  documentBytes, 'application/pdf'), 'mechanic cannot upload financial PDF');
storageDenied(await upload(ownerA, mediaFolder + 'photos/hack.png', onePixelPng),
  'non-random filenames rejected');
storageDenied(await upload(ownerA, mediaFolder + 'photos/' + randomUUID() + '.svg',
  Buffer.from('<svg/>'), 'image/svg+xml'), 'SVG type rejected');
storageDenied(await upload(ownerA, mediaFolder + 'documents/' + randomUUID() + '.html',
  Buffer.from('<script/>'), 'text/html'), 'HTML type rejected');
storageDenied(await upload(ownerA, mediaFolder + 'photos/' + randomUUID() + '.png',
  Buffer.alloc(5242881), 'image/png'), '5 MB limit enforced');
storageDenied(await upload(ownerA, photoPath, onePixelPng),
  'existing evidence cannot be overwritten');
storageDenied(await upload(ownerA, photoPath, onePixelPng,
  'image/png', {'x-upsert':'true'}), 'upsert requires forbidden update privilege');

const photosOwner = mustPass(await listStorage(ownerA, mediaFolder + 'photos/'),
  'owner lists garage photos');
assert.equal(photosOwner.length,1);
const photosMechanic = mustPass(await listStorage(mechanic, mediaFolder + 'photos/'),
  'mechanic lists only assigned photos');
assert.equal(photosMechanic.length,1);
const financeMechanic = await listStorage(mechanic, mediaFolder + 'documents/');
if (financeMechanic.ok) assert.equal(financeMechanic.value.length,0);
else storageDenied(financeMechanic,'mechanic lists financial documents');
const anotherGaragePhotos = await listStorage(ownerB, mediaFolder + 'photos/');
if (anotherGaragePhotos.ok) assert.equal(anotherGaragePhotos.value.length,0);
else storageDenied(anotherGaragePhotos,'other garage lists photos');

const replacement = await signup('replacement-mechanic');
const tokenReplacement = mustPass(await rpc(ownerA, 'garage_issue_staff_invite', {
  p_workspace_id: shopA, p_email: replacement.email, p_role: 'mechanic',
}), 'invite replacement mechanic');
assert.equal(mustPass(await rpc(replacement, 'garage_accept_staff_invite', {
  p_token:tokenReplacement,
}), 'replacement accepts invite'),shopA);
assert.equal(mustPass(await rpc(ownerA, 'garage_assign_mechanic', {
  p_workspace_id: shopA, p_order_id: order.id,
  p_mechanic_user_id: replacement.id,
}), 'transfer repair job to replacement'),replacement.id);
storageDenied(await download(mechanic, photoPath),
  'previous mechanic immediately loses repair photo access');
const oldMechanicListing = await listStorage(mechanic, mediaFolder + 'photos/');
if (oldMechanicListing.ok) assert.equal(oldMechanicListing.value.length, 0);
else storageDenied(oldMechanicListing, 'prior mechanic cannot list transferred images');
mustPass(await download(replacement, photoPath),
  'replacement mechanic can view assigned repair photo');
storageDenied(await download(replacement, documentPath),
  'replacement mechanic cannot view financial document');

console.log('PASS Garage private Storage access, tenant separation, evidence integrity and mechanic reassignment');


