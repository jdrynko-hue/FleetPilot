// FleetPilot: daily email test worker. No bulk sending before domain verification.
// Hosted on Supabase Edge Functions with verify_jwt=false because cron supplies
// a high-entropy private challenge; the challenge is checked against Postgres.

const reply = (code: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status: code,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

const base = Deno.env.get("SUPABASE_URL");
const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const serviceKey = legacy ?? (() => {
  try {
    return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}")["default"];
  } catch { return undefined; }
})();

async function rpc(name: string, params: Record<string, unknown> = {}): Promise<unknown> {
  if (!base || !serviceKey) throw new Error("Missing internal configuration");
  const result = await fetch(`${base}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
    body: JSON.stringify(params),
  });
  if (!result.ok) {
    console.error(`FleetPilot RPC ${name} failed with HTTP ${result.status}`);
    throw new Error(`Database operation ${name} failed`);
  }
  return await result.json();
}

async function checkSecret(provided: string | null): Promise<boolean> {
  if (!base || !serviceKey || !provided || provided.length > 128) return false;
  const answer = await fetch(
    `${base}/rest/v1/fleetpilot_scheduler_config?select=secret&id=eq.1`,
    {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
    },
  );
  if (!answer.ok) return false;
  const rows = await answer.json();
  const expected = rows?.[0]?.secret;
  if (typeof expected !== "string") return false;
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  let difference = 0;
  const a = new Uint8Array(left), b = new Uint8Array(right);
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

type Notification = {
  notification_id: string;
  recipient_email: string;
  notification_kind: string;
  vehicle_registration: string;
  deadline_date: string | null;
  deadline_mileage: number | null;
  reminder_stage: number;
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return reply(405, { error: "POST required" });
  try {
    if (!(await checkSecret(req.headers.get("x-fleetpilot-cron-key")))) {
      return reply(401, { error: "Unauthorized" });
    }
  } catch {
    return reply(503, { error: "Authentication unavailable" });
  }

  const resendKey = Deno.env.get("RESEND_API_KEY");
  const ownEmail = Deno.env.get("RESEND_TEST_EMAIL")?.trim();
  if (!resendKey || !ownEmail) return reply(503, { error: "Email is not configured" });

  try {
    const created = await rpc("fleetpilot_generate_notifications");
    const list = await rpc("fleetpilot_claim_test_email_alerts", {
      _test_email: ownEmail,
      _batch_size: 10,
    });
    if (!Array.isArray(list)) throw new Error("Unexpected queue response");
    let sent = 0, failed = 0;
    for (const item of list as Notification[]) {
      const subject = `FleetPilot: ${item.vehicle_registration} — service reminder`;
      const target = item.deadline_date
        ? `Due date: ${item.deadline_date}`
        : `Mileage target: ${item.deadline_mileage ?? "unknown"} mi`;
      // Text-only content avoids HTML injection from user-supplied registration.
      const body = {
        from: "FleetPilot <onboarding@resend.dev>",
        to: [ownEmail],
        subject,
        text: `FleetPilot vehicle reminder\nVehicle: ${item.vehicle_registration}\nType: ${item.notification_kind}\n${target}\nReminder stage: ${item.reminder_stage}\n\nOpen FleetPilot to review and update the vehicle.`,
      };
      let delivered = false, reason = "provider error";
      try {
        const send = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${resendKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": `fleetpilot-notification-${item.notification_id}`,
          },
          body: JSON.stringify(body),
        });
        delivered = send.ok;
        if (!send.ok) reason = `HTTP ${send.status}`;
      } catch {
        reason = "network error";
      }
      await rpc("fleetpilot_complete_email_alert", {
        _notification_id: item.notification_id,
        _delivered: delivered,
        _error: delivered ? null : reason,
      });
      if (delivered) sent++; else failed++;
      // Deliberate throttle for Resend API limits.
      await new Promise((resolve) => setTimeout(resolve, 600));
    }
    return reply(200, { ok: true, notifications_generated: created, processed: list.length, sent, failed });
  } catch (error) {
    console.error("FleetPilot reminder worker failure", String(error).slice(0, 160));
    return reply(500, { error: "Reminder process failed" });
  }
});
