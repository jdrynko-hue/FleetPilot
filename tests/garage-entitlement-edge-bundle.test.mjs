import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const base='supabase/functions/flotaryx-garage-test-entitlement/';
const read=(path)=>readFileSync(path,'utf8');

test('isolated QA entitlement handler matches reviewed server implementation',()=>{
  assert.equal(read(base+'entitlement_http.ts'),read('server/garage-billing/entitlement_http.ts'));
});

test('QA entitlement adapter matches reviewed SDK adapter with local import only',()=>{
  const source=read('supabase/functions/flotaryx-garage-test-checkout/entitlement_adapter.ts');
  assert.ok(source.includes('../../../server/garage-billing/entitlement_http.ts'));
  assert.equal(read(base+'entitlement_adapter.ts'),
    source.replace('../../../server/garage-billing/entitlement_http.ts','./entitlement_http.ts'));
});

test('entrypoint imports only the locally bundled adapter and is disabled without explicit opt-in',()=>{
  const entry=read(base+'index.ts');
  assert.ok(entry.includes('from "./entitlement_adapter.ts"'));
  assert.ok(!entry.includes('../flotaryx-garage-test-checkout'));
  assert.ok(entry.includes('FLOTARYX_GARAGE_SANDBOX_ENTITLEMENT'));
  assert.ok(entry.includes('=== "true"'));
  const adapter=read(base+'entitlement_adapter.ts');
  assert.ok(adapter.includes('supabaseUrl !== qaUrl'));
  assert.ok(adapter.includes('anonKey === serviceKey'));
  assert.ok(adapter.includes('status: 503'));
  assert.ok(adapter.includes('https://fyestmquqvkdebxxbcky.supabase.co'));
  assert.ok(!adapter.includes('wqhymmtiawfwjikdaujo'));
});
