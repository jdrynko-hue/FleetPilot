import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const base='supabase/functions/flotaryx-garage-test-webhook/';
const read=p=>readFileSync(p,'utf8');

test('webhook billing coordinators and storage are exact reviewed copies',()=>{
  for(const file of ['paid_webhook.ts','paid_webhook_storage.ts','trial_webhook.ts','trial_webhook_storage.ts']){
    assert.equal(read(base+file),read('server/garage-billing/'+file),file);
  }
});

test('webhook runtime source matches reviewed implementation with local imports only',()=>{
  const reviewed=read('supabase/functions/flotaryx-garage-test-checkout/billing_webhook_runtime.ts');
  assert.ok(reviewed.includes('../../../server/garage-billing/'));
  assert.equal(read(base+'billing_webhook_runtime.ts'),reviewed.replaceAll('../../../server/garage-billing/','./'));
  assert.ok(!read(base+'billing_webhook_runtime.ts').includes('../../../server/'));
});

test('webhook stays disabled without exact QA, test key and Stripe signature secret',()=>{
  const entry=read(base+'index.ts');
  const runtime=read(base+'billing_webhook_runtime.ts');
  assert.ok(entry.includes('from "./billing_webhook_runtime.ts"'));
  assert.ok(entry.includes('FLOTARYX_GARAGE_SANDBOX_WEBHOOK'));
  assert.ok(entry.includes('=== "true"'));
  assert.ok(!entry.includes('../flotaryx-garage-test-checkout/'));
  assert.ok(runtime.includes('enabled !== true || supabaseUrl !== qaUrl'));
  assert.ok(runtime.includes('^(sk|rk)_test_'));
  assert.ok(runtime.includes('^whsec_'));
  assert.ok(runtime.includes('constructEventAsync('));
  assert.ok(runtime.includes('readRawBody(request)'));
  assert.ok(runtime.includes('reply(503)'));
  assert.ok(!runtime.includes('wqhymmtiawfwjikdaujo'));
});
