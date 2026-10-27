import {recordPaidRejoinEvent} from '../../../server/garage-billing/paid_rejoin.ts';
import Stripe from "stripe";
import { createClient } from "supabase";
import {
  createGaragePaidWebhook,
} from "../../../server/garage-billing/paid_webhook.ts";
import {
  garagePaidWebhookStorage,
} from "../../../server/garage-billing/paid_webhook_storage.ts";
import {
  createGarageTrialWebhook,
} from "../../../server/garage-billing/trial_webhook.ts";
import {
  garageTrialWebhookStorage,
} from "../../../server/garage-billing/trial_webhook_storage.ts";

const qaUrl = "https://fyestmquqvkdebxxbcky.supabase.co";
const trialEvents = new Set([
  "customer.subscription.created",
  "customer.subscription.updated",
]);
const paidEvents = new Set([
  "invoice.paid",
  "invoice.payment_failed",
  "customer.subscription.deleted",
]);
const responseHeaders = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

function reply(status: number) {
  return new Response(JSON.stringify({ received: status === 200 }), {
    status,
    headers: responseHeaders,
  });
}

async function readRawBody(request: Request) {
  const reader = request.body?.getReader();
  if (!reader) return { response: reply(400) };
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.length;
      if (size > 65536) {
        await reader.cancel();
        return { response: reply(413) };
      }
      chunks.push(part.value);
    }
  } catch {
    return { response: reply(400) };
  } finally {
    reader.releaseLock();
  }
  const raw = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    raw.set(chunk, offset);
    offset += chunk.length;
  }
  return { raw };
}

// One source-only Stripe endpoint for the whole Garage Sandbox lifecycle.
// It verifies the original bytes once before routing a request to either
// coordinator. Both coordinators then retrieve current Stripe state and write
// only through private service RPCs; event delivery order is never trusted.
export function createGarageSandboxBillingWebhookRuntime(configuration: {
  enabled?: boolean;
  supabaseUrl: string;
  stripeKey?: string;
  signingSecret?: string;
  serviceKey?: string;
}) {
  const { enabled, supabaseUrl, stripeKey, signingSecret, serviceKey } =
    configuration;
  if (
    enabled !== true || supabaseUrl !== qaUrl ||
    !stripeKey || !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey) ||
    !signingSecret || !/^whsec_[A-Za-z0-9]+$/.test(signingSecret) ||
    !serviceKey
  ) return async (_request: Request) => reply(503);

  const stripe = new Stripe(stripeKey, {
    httpClient: Stripe.createFetchHttpClient(),
    timeout: 12000,
    maxNetworkRetries: 1,
  });
  const cryptoProvider = Stripe.createSubtleCryptoProvider();
  const serviceClient = createClient(qaUrl, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  const trialStorage = garageTrialWebhookStorage(serviceClient);
  const paidStorage = garagePaidWebhookStorage(serviceClient);

  return async (request: Request) => {
    if (request.method !== "POST") return reply(405);
    const signature = request.headers.get("stripe-signature");
    if (!signature || signature.length > 4096) return reply(400);
    const body = await readRawBody(request);
    if (body.response) return body.response;

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        new TextDecoder("utf-8", { fatal: true }).decode(body.raw),
        signature,
        signingSecret,
        300,
        cryptoProvider,
      );
    } catch {
      return reply(400);
    }
    if (event.livemode !== false) return reply(400);
    if (!trialEvents.has(event.type) && !paidEvents.has(event.type)) {
      return reply(200);
    }

    const object = event.data.object;
    const projected = {
      id: "id" in object && typeof object.id === "string" ? object.id : "",
    };
    const forwarded = new Request(request.url, {
      method: "POST",
      headers: { "stripe-signature": signature },
      body: new Blob([body.raw]),
    });
    if (trialEvents.has(event.type)) {
      const handler = createGarageTrialWebhook({
        ...trialStorage,
        verify: async () => ({
          type: event.type,
          livemode: event.livemode,
          data: { object: projected },
        }),
        retrieveSubscription: (id) => stripe.subscriptions.retrieve(id),
      });
      return handler(forwarded);
    }

    // Signed events belonging to a separate paid purchase must never pass
    // through the original trial claim ledger, even during purchase UI pause.
    let routedInvoice: Stripe.Invoice | undefined;
    let routedSub: Stripe.Subscription | undefined;
    try {
      let invoice: Stripe.Invoice | undefined;
      let subId = projected.id;
      if (event.type !== 'customer.subscription.deleted') {
        invoice = await stripe.invoices.retrieve(projected.id);
        subId = invoice.parent?.subscription_details?.subscription as string;
        const legacy = invoice as unknown as {subscription?: string};
        subId = legacy.subscription ?? subId;
      }
      const sub = await stripe.subscriptions.retrieve(subId);
      routedInvoice=invoice; routedSub=sub;
      if (sub.metadata?.purchase_kind === 'paid_rejoin') {
        await recordPaidRejoinEvent({id:event.id,type:event.type,created:event.created,
          livemode:false,data:{object:projected}}, {client:serviceClient,stripe:{
          subscriptions:{retrieve:async id=>id===sub.id?sub:stripe.subscriptions.retrieve(id)},
          invoices:{retrieve:async id=>invoice?.id===id?invoice:stripe.invoices.retrieve(id)},
          checkout:{sessions:{create:async()=>{throw Error('Webhook cannot create Checkout');},
            retrieve:(id,params)=>stripe.checkout.sessions.retrieve(id,params)}},
        }});
        return reply(200);
      }
    } catch { return reply(503); }

    const handler = createGaragePaidWebhook({
      ...paidStorage,
      verify: async () => ({
        id: event.id,
        type: event.type,
        created: event.created,
        livemode: event.livemode,
        data: { object: projected },
      }),
      retrieveInvoice: async (id) => routedInvoice?.id===id?routedInvoice:stripe.invoices.retrieve(id),
      retrieveTestClock: (id) => stripe.testHelpers.testClocks.retrieve(id),
      retrieveSubscription: async (id) => routedSub?.id===id?routedSub:stripe.subscriptions.retrieve(id),
    });
    return handler(forwarded);
  };
}
