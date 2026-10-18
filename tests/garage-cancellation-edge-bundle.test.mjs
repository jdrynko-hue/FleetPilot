import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const base='supabase/functions/flotaryx-garage-test-trial-cancel/';
const read=p=>readFileSync(p,'utf8');

test('cancellation SQL-facing modules are unchanged from reviewed sources',()=>{
  for(const name of ['trial_cancellation.ts','trial_cancellation_storage.ts','trial_cancellation_http.ts']){
    assert.equal(read(base+name),read('server/garage-billing/'+name),name);
  }
});

test('cancellation adapters match reviewed code except for local imports',()=>{
  const sdk=read('supabase/functions/flotaryx-garage-test-checkout/trial_cancellation_adapter.ts')
    .replaceAll('../../../server/garage-billing/','./');
  const http=read('supabase/functions/flotaryx-garage-test-checkout/trial_cancellation_http_adapter.ts')
    .replace('../../../server/garage-billing/trial_cancellation_http.ts','./trial_cancellation_http.ts');
  assert.equal(read(base+'trial_cancellation_adapter.ts'),sdk);
  assert.equal(read(base+'trial_cancellation_http_adapter.ts'),http);
});

test('cancellation Edge entrypoint stays QA-only, disabled and JWT-protected',()=>{
  const entry=read(base+'index.ts');
  const httpAdapter=read(base+'trial_cancellation_http_adapter.ts');
  assert.ok(entry.includes('from "./trial_cancellation_http_adapter.ts"'));
  assert.ok(entry.includes('FLOTARYX_GARAGE_SANDBOX_TRIAL_CANCELLATION'));
  assert.ok(entry.includes('=== "true"'));
  assert.ok(!entry.includes('../flotaryx-garage-test-checkout/'));
  assert.ok(httpAdapter.includes('enabled !== true'));
  assert.ok(httpAdapter.includes('supabaseUrl !== qaUrl'));
  assert.ok(httpAdapter.includes('anonKey === serviceKey'));
  assert.ok(httpAdapter.includes("status: 503"));
  assert.ok(httpAdapter.includes('https://fyestmquqvkdebxxbcky.supabase.co'));
  assert.ok(!httpAdapter.includes('wqhymmtiawfwjikdaujo'));
});
