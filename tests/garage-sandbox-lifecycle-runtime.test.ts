import Stripe from "stripe";
import { createGarageSandboxBillingWebhookRuntime } from "../supabase/functions/flotaryx-garage-test-checkout/billing_webhook_runtime.ts";
import { createGarageSandboxEntitlementRuntime } from "../supabase/functions/flotaryx-garage-test-checkout/entitlement_adapter.ts";
import { createGarageSandboxTrialCancellationRuntime } from "../supabase/functions/flotaryx-garage-test-checkout/trial_cancellation_http_adapter.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test(
  "shared real-SDK transport preserves Garage access across trial, cancellation and paid replay",
  async () => {
    const originalFetch = globalThis.fetch;
    const qaUrl = "https://fyestmquqvkdebxxbcky.supabase.co";
    const actor = "00000000-0000-4000-8000-000000000721";
    const workspace = "00000000-0000-4000-8000-000000000821";
    const attempt = "11111111-1111-4111-8111-111111111121";
    const customer = "cus_cyclefixture";
    const subscription = "sub_cyclefixture";
    const price = "price_cyclefixture";
    const invoice = "in_cyclefixture";
    const stripeKey = "rk_test_cyclefixture";
    const signingSecret = "whsec_cyclefixture";
    const publishableKey = "disposable-cycle-publishable";
    const serviceKey = "disposable-cycle-service";
    const userToken = "cycle-user-token";
    const now = Math.floor(Date.now() / 1000);
    const trialStart = now - 60;
    const trialEnd = trialStart + 7 * 86400;
    const periodStart = trialEnd;
    const periodEnd = periodStart + 31 * 86400;

    type State = {
      trialAccess: boolean;
      canceled: boolean;
      canceledAt: number | null;
      paidAccess: boolean;
      ended: boolean;
      lastPayment: "failed" | "paid" | null;
      invoiceState: "failed" | "paid";
      subscriptionStatus: "trialing" | "active" | "canceled";
      confirms: number;
      deletes: number;
      paidWrites: number;
      failedWrites: number;
      endedWrites: number;
    };
    const initial = (): State => ({
      trialAccess: false,
      canceled: false,
      canceledAt: null,
      paidAccess: false,
      ended: false,
      lastPayment: null,
      invoiceState: "failed",
      subscriptionStatus: "trialing",
      confirms: 0,
      deletes: 0,
      paidWrites: 0,
      failedWrites: 0,
      endedWrites: 0,
    });
    let state = initial();
    const transport: string[] = [];

    const claim = () => ({
      attempt_id: attempt,
      workspace_id: workspace,
      customer_id: customer,
      price_id: price,
      currency: "gbp",
      billing_interval: "month",
    });
    const subscriptionObject = () => ({
      id: subscription,
      livemode: false,
      status: state.subscriptionStatus,
      customer,
      trial_start: trialStart,
      trial_end: trialEnd,
      canceled_at: state.canceledAt,
      metadata: {
        product: "garage",
        attempt_id: attempt,
        workspace_id: workspace,
        currency: "gbp",
        billing_interval: "month",
      },
      items: {
        has_more: false,
        data: [
          {
            quantity: 1,
            price: {
              id: price,
              livemode: false,
              currency: "gbp",
              recurring: {
                interval: "month",
                interval_count: 1,
                usage_type: "licensed",
              },
            },
          },
        ],
      },
    });
    const invoiceObject = () => ({
      id: invoice,
      livemode: false,
      status: state.invoiceState === "paid" ? "paid" : "open",
      paid: state.invoiceState === "paid",
      customer,
      currency: "gbp",
      parent: { subscription_details: { subscription } },
      billing_reason: "subscription_cycle",
      amount_due: 5900,
      amount_paid: state.invoiceState === "paid" ? 5900 : 0,
      amount_remaining: state.invoiceState === "paid" ? 0 : 5900,
      attempt_count: 1,
      status_transitions: {
        paid_at: state.invoiceState === "paid" ? periodStart + 30 : null,
      },
      lines: {
        has_more: false,
        data: [
          {
            quantity: 1,
            period: { start: periodStart, end: periodEnd },
            pricing: { price_details: { price } },
          },
        ],
      },
    });
    const entitlement = () => {
      if (state.ended || state.canceled) {
        return {
          active: false,
          source: null,
          access_ends_at: null,
          last_payment_state: state.lastPayment,
        };
      }
      if (state.paidAccess) {
        return {
          active: true,
          source: "paid",
          access_ends_at: new Date(periodEnd * 1000).toISOString(),
          last_payment_state: "paid",
        };
      }
      if (state.trialAccess) {
        return {
          active: true,
          source: "trial",
          access_ends_at: new Date(trialEnd * 1000).toISOString(),
          last_payment_state: state.lastPayment,
        };
      }
      return {
        active: false,
        source: null,
        access_ends_at: null,
        last_payment_state: state.lastPayment,
      };
    };

    globalThis.fetch = async (input, init) => {
      const request =
        input instanceof Request ? input : new Request(input, init);
      const url = new URL(request.url);
      const body = request.body ? await request.clone().text() : "";
      transport.push(`${request.method} ${url.hostname}${url.pathname}`);
      const json = (value: unknown) =>
        new Response(JSON.stringify(value), {
          status: 200,
          headers: {
            "content-type": "application/json",
            "request-id": "req_cycle_fixture",
          },
        });

      if (url.hostname === "api.stripe.com") {
        assert(
          request.headers.get("authorization") === `Bearer ${stripeKey}`,
          "Stripe request crossed the test-key boundary",
        );
        if (url.pathname === `/v1/invoices/${invoice}`) {
          return json(invoiceObject());
        }
        assert(
          url.pathname === `/v1/subscriptions/${subscription}`,
          "Unexpected Stripe lifecycle path",
        );
        if (request.method === "DELETE") {
          const form = new URLSearchParams(body || url.search);
          assert(
            request.headers.get("idempotency-key") ===
              `flotaryx:garage:sandbox:cancel:${attempt}` &&
              form.get("invoice_now") === "false" &&
              form.get("prorate") === "false",
            "Trial cancellation lost its charge-free idempotent terms",
          );
          state.deletes++;
          state.subscriptionStatus = "canceled";
          state.canceledAt = now;
        }
        return json(subscriptionObject());
      }

      assert(
        url.hostname === "fyestmquqvkdebxxbcky.supabase.co",
        "Lifecycle transport reached a non-QA Supabase host",
      );
      if (url.pathname === "/auth/v1/user") {
        assert(
          request.headers.get("authorization") === `Bearer ${userToken}` &&
            request.headers.get("apikey") === publishableKey,
          "User token or publishable key crossed the Auth boundary",
        );
        return json({ id: actor, is_anonymous: false });
      }
      assert(
        request.headers.get("authorization") === `Bearer ${serviceKey}` &&
          request.headers.get("apikey") === serviceKey,
        "Private billing RPC did not use the isolated service credential",
      );
      const args = body ? JSON.parse(body) : {};
      const rpc = url.pathname.split("/").at(-1);
      if (rpc === "garage_lookup_test_trial") return json(claim());
      if (rpc === "garage_confirm_test_trial") {
        assert(
          args.p_attempt === attempt &&
            args.p_subscription === subscription &&
            args.p_livemode === false,
          "Trial confirmation identity changed",
        );
        state.confirms++;
        if (!state.canceled) state.trialAccess = true;
        return json(true);
      }
      if (rpc === "garage_resolve_test_workspace_entitlement") {
        assert(
          args.p_actor === actor && args.p_workspace === workspace,
          "Entitlement was not bound to verified membership",
        );
        return json(entitlement());
      }
      if (rpc === "garage_prepare_test_trial_cancellation") {
        assert(
          args.p_actor === actor && args.p_workspace === workspace,
          "Cancellation was not bound to the verified owner",
        );
        return json({
          state: state.canceled ? "trial_canceled" : "cancel_pending",
          ...claim(),
          subscription_id: subscription,
          trial_started_at: new Date(trialStart * 1000).toISOString(),
          trial_ends_at: new Date(trialEnd * 1000).toISOString(),
          canceled_at:
            state.canceled && state.canceledAt
              ? new Date(state.canceledAt * 1000).toISOString()
              : null,
        });
      }
      if (rpc === "garage_confirm_test_trial_cancellation") {
        assert(
          args.p_actor === actor &&
            args.p_workspace === workspace &&
            args.p_attempt === attempt &&
            args.p_subscription === subscription &&
            args.p_livemode === false,
          "Cancellation confirmation identity changed",
        );
        state.canceled = true;
        state.trialAccess = false;
        return json(true);
      }
      if (rpc === "garage_record_test_invoice_failed") {
        assert(
          args.p_attempt === attempt &&
            args.p_invoice === invoice &&
            args.p_subscription === subscription &&
            args.p_livemode === false,
          "Failed invoice write lost its frozen identity",
        );
        state.failedWrites++;
        if (!state.paidAccess) state.lastPayment = "failed";
        return json(true);
      }
      if (rpc === "garage_record_test_invoice_paid") {
        assert(
          args.p_attempt === attempt &&
            args.p_invoice === invoice &&
            args.p_subscription === subscription &&
            args.p_amount_due === 5900 &&
            args.p_amount_paid === 5900 &&
            args.p_livemode === false,
          "Paid invoice write lost its authoritative amount or identity",
        );
        state.paidWrites++;
        state.lastPayment = "paid";
        state.paidAccess = true;
        return json(true);
      }
      if (rpc === "garage_record_test_subscription_ended") {
        assert(
          args.p_attempt === attempt &&
            args.p_subscription === subscription &&
            args.p_customer === customer &&
            args.p_livemode === false,
          "Subscription end write lost its frozen identity",
        );
        state.endedWrites++;
        state.ended = true;
        state.paidAccess = false;
        state.trialAccess = false;
        return json(true);
      }
      throw new Error(`Unexpected lifecycle RPC ${rpc}`);
    };

    const webhook = createGarageSandboxBillingWebhookRuntime({
      enabled: true,
      supabaseUrl: qaUrl,
      stripeKey,
      signingSecret,
      serviceKey,
    });
    const access = createGarageSandboxEntitlementRuntime({
      enabled: true,
      supabaseUrl: qaUrl,
      anonKey: publishableKey,
      serviceKey,
    });
    const cancel = createGarageSandboxTrialCancellationRuntime({
      enabled: true,
      supabaseUrl: qaUrl,
      anonKey: publishableKey,
      serviceKey,
      stripeKey,
    });
    const provider = Stripe.createSubtleCryptoProvider();

    const callAccess = async () => {
      const response = await access(
        new Request("https://qa.example.test/entitlement", {
          method: "POST",
          headers: {
            authorization: `Bearer ${userToken}`,
            "content-type": "application/json",
            origin: "https://flotaryx-qa-preview.fairdrake9.chatgpt.site",
          },
          body: JSON.stringify({ workspace_id: workspace }),
        }),
      );
      assert(
        response.status === 200,
        `Entitlement returned ${response.status}`,
      );
      return response.json();
    };
    const callWebhook = async (event: {
      id: string;
      type: string;
      object: string;
    }) => {
      const payload = JSON.stringify({
        id: event.id,
        type: event.type,
        created: now,
        livemode: false,
        data: { object: { id: event.object } },
      });
      const signature = await Stripe.webhooks.generateTestHeaderStringAsync({
        payload,
        secret: signingSecret,
        timestamp: now,
        cryptoProvider: provider,
      });
      return webhook(
        new Request("https://qa.example.test/webhook", {
          method: "POST",
          headers: { "stripe-signature": signature },
          body: payload,
        }),
      );
    };
    const callCancel = () =>
      cancel(
        new Request("https://qa.example.test/trial-cancel", {
          method: "POST",
          headers: {
            authorization: `Bearer ${userToken}`,
            "content-type": "application/json",
            origin: "https://flotaryx-qa-preview.fairdrake9.chatgpt.site",
          },
          body: JSON.stringify({ workspace_id: workspace }),
        }),
      );

    try {
      // A Checkout success or saved session alone has no access. Only the signed
      // subscription event plus current Stripe state confirms the trial.
      assert(
        (await callAccess()).active === false,
        "Unconfirmed Checkout granted access",
      );
      assert(
        (
          await callWebhook({
            id: "evt_cycletrial",
            type: "customer.subscription.created",
            object: subscription,
          })
        ).status === 200,
        "Signed trial confirmation failed",
      );
      const trial = await callAccess();
      assert(
        trial.active === true &&
          trial.source === "trial" &&
          state.confirms === 1,
        "Confirmed seven-day trial did not grant trial access",
      );

      const canceled = await callCancel();
      assert(
        canceled.status === 200,
        "Owner could not cancel before first charge",
      );
      const canceledBody = await canceled.json();
      assert(
        canceledBody.status === "canceled" &&
          canceledBody.subscription_id === undefined &&
          state.deletes === 1,
        "Cancellation leaked billing identity or skipped Stripe DELETE",
      );
      assert(
        (await callAccess()).active === false,
        "Canceled trial retained access",
      );

      // A delayed subscription update and an HTTP retry cannot restore access or
      // issue a second DELETE after the durable cancellation is recorded.
      assert(
        (
          await callWebhook({
            id: "evt_cyclelate",
            type: "customer.subscription.updated",
            object: subscription,
          })
        ).status === 200,
        "Late trial webhook was not acknowledged safely",
      );
      assert(state.confirms === 1, "Late webhook restored a canceled trial");
      assert(
        (await callCancel()).status === 200,
        "Cancellation retry was not idempotent",
      );
      assert(
        state.deletes === 1,
        "Cancellation retry issued another Stripe DELETE",
      );
      assert(
        (await callAccess()).active === false,
        "Replay restored canceled access",
      );

      // Separate paid path: a failed first cycle grants nothing; authoritative
      // payment can transition it to paid, and a delayed failure/replay observes
      // the current paid invoice instead of revoking access.
      state = initial();
      state.subscriptionStatus = "active";
      assert(
        (
          await callWebhook({
            id: "evt_cyclefailed",
            type: "invoice.payment_failed",
            object: invoice,
          })
        ).status === 200,
        "Failed invoice event was not reconciled",
      );
      const failed = await callAccess();
      assert(
        failed.active === false &&
          failed.last_payment_state === "failed" &&
          state.failedWrites === 1,
        "Failed invoice granted paid access",
      );

      state.invoiceState = "paid";
      assert(
        (
          await callWebhook({
            id: "evt_cyclepaid",
            type: "invoice.paid",
            object: invoice,
          })
        ).status === 200,
        "Paid invoice event was not reconciled",
      );
      const paid = await callAccess();
      assert(
        paid.active === true &&
          paid.source === "paid" &&
          paid.last_payment_state === "paid" &&
          state.paidWrites === 1,
        "Fully paid cycle did not grant bounded paid access",
      );

      assert(
        (
          await callWebhook({
            id: "evt_cyclelatefailure",
            type: "invoice.payment_failed",
            object: invoice,
          })
        ).status === 200,
        "Delayed failure was not reconciled from the current paid invoice",
      );
      assert(
        (await callAccess()).source === "paid" &&
          state.failedWrites === 1 &&
          Number(state.paidWrites) === 2,
        "Delayed failure downgraded paid access",
      );

      state.subscriptionStatus = "canceled";
      state.canceledAt = periodStart + 3600;
      assert(
        (
          await callWebhook({
            id: "evt_cycleended",
            type: "customer.subscription.deleted",
            object: subscription,
          })
        ).status === 200,
        "Subscription deletion was not reconciled",
      );
      const ended = await callAccess();
      assert(
        ended.active === false &&
          ended.source === null &&
          ended.last_payment_state === "paid" &&
          state.endedWrites === 1,
        "Ended subscription retained paid access",
      );

      assert(
        transport.every(
          (entry) =>
            entry.includes("fyestmquqvkdebxxbcky.supabase.co") ||
            entry.includes("api.stripe.com"),
        ),
        "Lifecycle escaped the trapped QA/Stripe transport",
      );
    } finally {
      globalThis.fetch = originalFetch;
    }
  },
);
