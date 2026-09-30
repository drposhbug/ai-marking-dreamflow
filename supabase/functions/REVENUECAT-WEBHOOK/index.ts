// supabase/functions/REVENUECAT-WEBHOOK/index.ts
//
// The ONLY thing allowed to grant a plan from a STORE purchase. RevenueCat
// calls this after it has validated the receipt with Google/Apple, so a
// teacher can't grant themselves a paid tier by replaying an app request
// (the anon key ships in the APK — anything the app can send, a teacher can
// send).
//
// It writes profiles.plan_revenuecat and never profiles.plan: the web has its
// own rail (STRIPE-WEBHOOK), and `plan` is derived from both so that a
// cancellation here cannot cancel a subscription bought there. See
// ../_shared/entitlement.ts for why that matters and what it costs.
//
// Setup (RevenueCat dashboard → Project → Integrations → Webhooks):
//   URL:            https://<project-ref>.supabase.co/functions/v1/REVENUECAT-WEBHOOK
//   Authorization:  the value of the REVENUECAT_WEBHOOK_SECRET secret below
//
// Secrets required (`npx supabase secrets set ...`):
//   REVENUECAT_WEBHOOK_SECRET — shared secret, must match the dashboard's
//                               Authorization header exactly
//
// Deploy with --no-verify-jwt: RevenueCat sends its own Authorization header,
// not a Supabase JWT.
import { createClient } from "npm:@supabase/supabase-js@2";
import type { EntitlementRow } from "../_shared/entitlement.ts";

function serviceDb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// Maps a RevenueCat entitlement/product to one of the server's plan rows.
/// Product ids are matched loosely so renaming "markless_pro_monthly" to
/// "pro_monthly" in the store doesn't silently drop teachers to trial.
function planFromEvent(productId: string, entitlementIds: string[]): string {
  const p = productId.toLowerCase();
  const ents = entitlementIds.join(" ").toLowerCase();
  if (p.includes("school") || ents.includes("school")) return "school";
  if (p.includes("starter") || ents.includes("starter")) return "starter";
  // Annual bills $119.99/yr = $10.00/mo, well under the $14.99 monthly
  // price, so it CANNOT carry the monthly Pro allowance — that would be a
  // guaranteed loss on every annual subscriber. It gets its own tier.
  if (p.includes("annual") || p.includes("year") || p.includes("yr") || ents.includes("annual")) return "pro_annual";
  return "pro";
}

// Events that mean "this account is entitled right now" vs "it isn't".
const GRANTS = ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "NON_RENEWING_PURCHASE", "PRODUCT_CHANGE", "SUBSCRIPTION_EXTENDED", "TRANSFER"];
const REVOKES = ["CANCELLATION", "EXPIRATION", "BILLING_ISSUE", "SUBSCRIPTION_PAUSED", "REFUND"];

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  if (!secret) return json({ error: "REVENUECAT_WEBHOOK_SECRET is not set" }, 500);
  // Compare against the raw header and the "Bearer x" form — the dashboard
  // field is free text and both spellings are common.
  const auth = (req.headers.get("authorization") ?? "").trim();
  if (auth !== secret && auth.replace(/^Bearer\s+/i, "") !== secret) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  // deno-lint-ignore no-explicit-any
  const event = (body?.event ?? {}) as any;
  const type = String(event?.type ?? "").toUpperCase();
  // app_user_id is the teacher id: BillingService calls Purchases.logIn with it.
  const teacherId = String(event?.app_user_id ?? "").trim();
  if (!teacherId) return json({ ok: true, ignored: "no app_user_id" });
  // Anonymous RevenueCat ids belong to a device, not an account — a purchase
  // made before sign-in arrives again as TRANSFER once the teacher logs in.
  if (teacherId.startsWith("$RCAnonymousID:")) return json({ ok: true, ignored: "anonymous id" });
  // Sandbox and Test Store purchases cost nothing, and a test_ SDK key is
  // easy to come by, so by default they never change a real teacher's plan.
  // Set REVENUECAT_ACCEPT_SANDBOX=true to let them through while testing.
  const sandbox = String(event?.environment ?? "").toUpperCase() === "SANDBOX" ||
    String(event?.store ?? "").toUpperCase() === "TEST_STORE";
  if (sandbox && Deno.env.get("REVENUECAT_ACCEPT_SANDBOX") !== "true") {
    return json({ ok: true, ignored: "sandbox" });
  }

  let plan: string | null = null;
  if (GRANTS.includes(type)) {
    plan = planFromEvent(String(event?.product_id ?? ""), (event?.entitlement_ids ?? []) as string[]);
  } else if (REVOKES.includes(type)) {
    plan = "trial";
  } else {
    // TEST events and anything RevenueCat adds later: acknowledge, change nothing.
    return json({ ok: true, ignored: type });
  }

  // Writes the STORES' column and nothing else. A teacher who also pays on
  // the web keeps that subscription when this one lapses — before this, an
  // EXPIRATION here set profiles.plan to trial and cancelled a live Stripe
  // subscription the teacher was still being charged for.
  const { data, error } = await serviceDb()
    .rpc("apply_entitlement", { p_teacher: teacherId, p_rail: "revenuecat", p_plan: plan })
    .maybeSingle();
  // A 500 makes RevenueCat retry, which is what we want when the database
  // blinked: the grant is not lost.
  if (error) return json({ error: error.message }, 500);
  const row = data as EntitlementRow | null;

  // `plan` is what this rail now says; `effective` is what the teacher
  // actually gets, which differs whenever the other rail holds something
  // better. Both are logged so a support question has an answer.
  return json({
    ok: true,
    teacherId,
    plan,
    effective: row?.plan ?? plan,
    source: row?.plan_source ?? "revenuecat",
  });
});
