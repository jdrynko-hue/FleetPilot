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
  ) {
    // Internal QA diagnostics contain field NAMES ONLY: never print keys,
    // prefixes, lengths, bodies, Authorization, or secret contents.
    const reasons = [
      enabled !== true ? "feature_opt_in_missing" : null,
      supabaseUrl !== qaUrl ? "qa_project_mismatch" : null,
      !stripeKey || !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey)
        ? "stripe_test_key_invalid_or_missing" : null,
      !signingSecret || !/^whsec_[A-Za-z0-9]+$/.test(signingSecret)
        ? "stripe_signing_secret_invalid_or_missing" : null,
      !serviceKey ? "supabase_service_key_missing" : null,
    ].filter(Boolean);
    console.warn("Garage Sandbox QA configuration NO-GO:", reasons.join(","));
    return async (_request: Request) => reply(503);
  }

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

    const handler = createGaragePaidWebhook({
      ...paidStorage,
      verify: async () => ({
        id: event.id,
        type: event.type,
        created: event.created,
        livemode: event.livemode,
        data: { object: projected },
      }),
      retrieveInvoice: (id) => stripe.invoices.retrieve(id),
      retrieveSubscription: (id) => stripe.subscriptions.retrieve(id),
    });
    return handler(forwarded);
  };
}
