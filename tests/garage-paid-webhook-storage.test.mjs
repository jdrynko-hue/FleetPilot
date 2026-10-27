import assert from 'node:assert/strict';
import { test } from 'node:test';
import { garagePaidWebhookStorage } from '../server/garage-billing/paid_webhook_storage.ts';

const base = { attempt: 'attempt', event: 'evt_fixture', eventType: 'invoice.paid',
  eventCreated: 'event-time',
  invoice: 'in_fixture', subscription: 'sub_fixture', customer: 'cus_fixture',
  price: 'price_fixture', currency: 'gbp', interval: 'month',
  periodStart: 'from', periodEnd: 'to', amountDue: 4900 };

test('paid and failed records map only frozen authoritative fields to RPCs', async () => {
  const calls = [];
  const storage = garagePaidWebhookStorage({ rpc: async (name, args) => {
    calls.push([name, args]); return { data: true, error: null };
  } });
  assert.equal(await storage.recordPaid({ ...base, amountPaid: 4900, paidAt: 'paid-time' }), true);
  assert.equal(await storage.recordFailed({ ...base, attemptCount: 2 }), true);
  assert.equal(calls[0][0], 'garage_record_test_invoice_paid');
  assert.equal(calls[0][1].p_livemode, false);
  assert.equal(calls[0][1].p_event_type, 'invoice.paid');
  assert.equal(calls[0][1].p_amount_paid, 4900);
  assert.equal(calls[1][0], 'garage_record_test_invoice_failed');
  assert.equal(calls[1][1].p_attempt_count, 2);
  assert.equal('owner' in calls[0][1], false);
});

test('subscription end and lookup use narrow service RPCs', async () => {
  const calls = [];
  const claim = { attempt_id: 'attempt' };
  const storage = garagePaidWebhookStorage({ rpc: async (name, args) => {
    calls.push([name, args]); return { data: name.includes('lookup') ? claim : true, error: null };
  } });
  assert.equal(await storage.lookupClaim('attempt'), claim);
  assert.equal(await storage.recordEnded({ attempt: 'attempt', event: 'evt_fixture',
    eventCreated: 'event-time', subscription: 'sub_fixture', customer: 'cus_fixture',
    endedAt: 'ended-time' }), true);
  assert.deepEqual(calls[0], ['garage_lookup_test_trial', { p_attempt: 'attempt' }]);
  assert.equal(calls[1][0], 'garage_record_test_subscription_ended');
  assert.equal(calls[1][1].p_livemode, false);
});

for (const result of [{ data: {}, error: { message: 'private' } }, null])
  test('storage failures remain opaque', async () => {
    const storage = garagePaidWebhookStorage({ rpc: async () => {
      if (result === null) throw Error('private');
      return result;
    } });
    await assert.rejects(storage.lookupClaim('attempt'),
      { message: 'garage_paid_storage_unavailable' });
  });

test('only literal true acknowledges a database write', async () => {
  const storage = garagePaidWebhookStorage({ rpc: async () => ({ data: 'true', error: null }) });
  assert.equal(await storage.recordFailed({ ...base, attemptCount: 1 }), false);
});

test('clock invoice uses separate service RPC without rewriting event creation',async () => {
  const calls=[];
  const storage=garagePaidWebhookStorage({rpc:async (name,args) => {
    calls.push([name,args]);return {data:true,error:null};
  }});
  await storage.recordPaid({...base,amountPaid:4900,paidAt:'virtual-paid',testClockTime:'virtual-now'});
  assert.equal(calls[0][0],'garage_record_test_clock_invoice_paid');
  assert.equal(calls[0][1].p_event_created,'event-time');
  assert.equal(calls[0][1].p_test_clock_time,'virtual-now');
});

test('clock subscription end maps virtual time to a separate service RPC', async () => {
  const calls=[];
  const storage=garagePaidWebhookStorage({rpc:async (name,args) => {
    calls.push([name,args]); return {data:true,error:null};
  }});
  await storage.recordEnded({attempt:'attempt',event:'evt_fixture',eventCreated:'real-event',
    subscription:'sub_fixture',customer:'cus_fixture',endedAt:'virtual-end',testClockTime:'virtual-now'});
  assert.deepEqual(calls, [['garage_record_test_clock_subscription_ended', {
    p_attempt:'attempt',p_event:'evt_fixture',p_event_created:'real-event',
    p_subscription:'sub_fixture',p_customer:'cus_fixture',p_ended_at:'virtual-end',
    p_livemode:false,p_test_clock_time:'virtual-now',
  }]]);
});
