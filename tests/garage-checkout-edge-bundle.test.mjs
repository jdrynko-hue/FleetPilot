import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const root='supabase/functions/flotaryx-garage-test-checkout/';
const load=p=>readFileSync(p,'utf8');

test('packaged Checkout modules exactly match reviewed server policy',()=>{
  for(const file of ['trial_policy.ts','checkout.ts','http_handler.ts']){
    assert.equal(load(root+file),load('server/garage-billing/'+file),file);
  }
});

test('Checkout import graph is fully local to function directory',()=>{
  const entry=load(root+'index.ts');
  assert.ok(entry.includes("from './http_handler.ts'"));
  assert.ok(!entry.includes('../../../server/'));
  assert.ok(load(root+'http_handler.ts').includes("from './checkout.ts'"));
  assert.ok(load(root+'checkout.ts').includes("from './trial_policy.ts'"));
});

test('Checkout remains disabled unless exact QA and test Stripe configuration opt in',()=>{
  const entry=load(root+'index.ts');
  assert.ok(entry.includes("Deno.env.get('FLOTARYX_GARAGE_SANDBOX_CHECKOUT') === 'true'"));
  assert.ok(entry.includes("url !== qaUrl"));
  assert.ok(entry.includes("anonKey === serviceKey"));
  assert.ok(entry.includes("/^(sk|rk)_test_"));
  assert.ok(entry.includes("status: 503"));
  assert.ok(entry.includes('https://fyestmquqvkdebxxbcky.supabase.co'));
  assert.ok(!entry.includes('wqhymmtiawfwjikdaujo'));
  assert.ok(!entry.includes('sk_live_'));
});
