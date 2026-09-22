// supabase/functions/STRIPE-WEBHOOK/index.ts
//
// The ONLY thing that grants a plan from a web purchase — the Stripe half of
// what REVENUECAT-WEBHOOK does for the stores. Nothing else in the system
// writes profiles.plan, and that is load-bearing: the Supabase anon key
// ships inside the APK and the web bundle, so anything the client can send,
// a teacher can send with curl. MARKING-PROCESS strips `plan` out of
// save_profile for exactly this reason.
//
// ── THE SIGNATURE IS THE WHOLE SECURITY MODEL ────────────────────────────
// This endpoint is public (it has to be — Stripe calls it, and Stripe has no
// Supabase JWT). So the question "is this really Stripe?" is answered by the
// Stripe-Signature header and by nothing else:
//
//   Stripe-Signature: t=1740000000,v1=5257a869e7ec…,v1=<older secret>
//
//   1. Read the RAW body as text. Not JSON.parse'd and re-stringified — the
//      signature is over the exact bytes Stripe sent, so any reserialization
//      (key order, spacing, number formatting) breaks it.
//   2. signed_payload = `${t}.${rawBody}`.
//   3. HMAC-SHA256 it with STRIPE_WEBHOOK_SECRET (whsec_…), hex-encoded.
//   4. Compare against every v1 in the header in CONSTANT TIME. A plain ===
//      leaks, byte by byte, how much of a guess was right, which is enough
//      to forge a signature given enough tries.
//   5. Reject a timestamp older (or newer) than TOLERANCE_SECONDS, so a
//      genuine webhook captured off the wire can't be replayed forever to
//      re-grant a plan that has since been cancelled.
//
// If ANY of that fails the answer is 400 and NOTHING is written. Not a log
// line's worth of doubt: without this check, anyone who finds the URL can
// POST themselves a School plan.
//
// Secrets required (`npx supabase secrets set ...`):
//   STRIPE_WEBHOOK_SECRET — the signing secret of the endpoint you created
//                           in Stripe (Developers → Webhooks → your endpoint
//                           → Signing secret). It starts with whsec_ and is
//                           DIFFERENT from the API key. Test mode and live
//                           mode have different ones.
//
// Deploy with --no-verify-jwt — Stripe sends its own signature, not a
// Supabase JWT, exactly as REVENUECAT-WEBHOOK does:
//   npx supabase functions deploy STRIPE-WEBHOOK --no-verify-jwt
import { createClient } from "npm:@supabase/supabase-js@2";

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

/// How far out of date a signature may be. Stripe's own libraries use five
/// minutes; longer is a wider replay window for no benefit.
const TOLERANCE_SECONDS = 300;

/// Compares two strings without giving away where they first differ.
function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function toHex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("HMAC", key, enc.encode(message)));
}

/// Is this request really from Stripe? See the header comment — every branch
/// that returns false means nothing gets written.
async function verifyStripeSignature(
  header: string | null,
  rawBody: string,
  secret: string,
  nowSeconds: number,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  if (!header) return { ok: false, reason: "no Stripe-Signature header" };

  let timestamp = "";
  const signatures: string[] = [];
  for (const part of header.split(",")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    const k = part.slice(0, eq).trim();
    const v = part.slice(eq + 1).trim();
    if (k === "t") timestamp = v;
    // v1 is the current scheme. Several can appear while a secret is being
    // rolled — any one matching is a genuine Stripe request.
    else if (k === "v1") signatures.push(v);
  }
  if (!timestamp || signatures.length === 0) return { ok: false, reason: "malformed Stripe-Signature header" };

  const sent = Number(timestamp);
  if (!Number.isFinite(sent)) return { ok: false, reason: "bad timestamp" };
  // Replay guard. Also catches a clock that has run away from Stripe's.
  if (Math.abs(nowSeconds - sent) > TOLERANCE_SECONDS) return { ok: false, reason: "timestamp outside tolerance" };

  const expected = await hmacHex(secret, `${timestamp}.${rawBody}`);
  for (const candidate of signatures) {
    if (constantTimeEquals(expected, candidate)) return { ok: true };
  }
  return { ok: false, reason: "signature mismatch" };
}

// ---------- What each event means ----------
//
// Mirrors REVENUECAT-WEBHOOK's GRANTS / REVOKES lists, in Stripe's
// vocabulary. Everything not listed is acknowledged and changes nothing.
const GRANTS = [
  // The teacher finished paying on Stripe's hosted page.
  "checkout.session.completed",
  // Renewals, and the first invoice of a subscription.
  "invoice.paid",
  "invoice.payment_succeeded",
];
const REVOKES = [
  // Cancelled and the period has run out, or cancelled immediately.
  "customer.subscription.deleted",
  // The card failed. Same posture as RevenueCat's BILLING_ISSUE.
  "invoice.payment_failed",
  "customer.subscription.paused",
];
// Handled on its own, because the same event can mean either: an updated
// subscription is a grant while it is live and a revoke once it isn't.
const LIFECYCLE = ["customer.subscription.updated", "customer.subscription.created", "customer.subscription.resumed"];

/// Subscription statuses that mean "entitled right now".
const LIVE_STATUSES = ["active", "trialing", "past_due"];

/// The plans a web purchase may grant. The same four words PLAN_CAPS meters
/// in MARKING-PROCESS and STRIPE-CHECKOUT sells — an event carrying anything
/// else grants nothing rather than guessing a tier.
const SELLABLE_TIERS = ["starter", "pro", "pro_annual", "school"];

/// Reverse of STRIPE-CHECKOUT's price map: which tier a price id belongs to.
/// Used when an event arrives without our metadata (an old subscription, or
/// one created by hand in the dashboard).
function tierForPrice(priceId: string): string | null {
  if (!priceId) return null;
  const map: Record<string, string> = {
    starter: "STRIPE_PRICE_STARTER",
    pro: "STRIPE_PRICE_PRO",
    pro_annual: "STRIPE_PRICE_PRO_ANNUAL",
    school: "STRIPE_PRICE_SCHOOL",
  };
  for (const [tier, envName] of Object.entries(map)) {
    if ((Deno.env.get(envName) ?? "").trim() === priceId) return tier;
  }
  return null;
}

/// Pulls the teacher id out of wherever this kind of event carries it.
///
/// Always OUR metadata, stamped by STRIPE-CHECKOUT when the session was
/// created and copied onto the subscription — never an email, never a
/// customer name, never anything the payer typed into Stripe's page. A
/// teacher filling in a different email at checkout still gets the plan on
/// the account that started the checkout, and on no other.
// deno-lint-ignore no-explicit-any
function teacherIdFrom(object: any): string {
  const candidates = [
    object?.metadata?.teacher_id,
    object?.client_reference_id,
    object?.subscription_details?.metadata?.teacher_id,
    object?.parent?.subscription_details?.metadata?.teacher_id,
    object?.lines?.data?.[0]?.metadata?.teacher_id,
  ];
  for (const c of candidates) {
    const id = String(c ?? "").trim();
    if (id) return id;
  }
  return "";
}

/// The tier this event is about: our metadata first, then the price id.
// deno-lint-ignore no-explicit-any
function tierFrom(object: any): string | null {
  const stamped = String(
    object?.metadata?.tier ??
      object?.subscription_details?.metadata?.tier ??
      object?.parent?.subscription_details?.metadata?.tier ??
      object?.lines?.data?.[0]?.metadata?.tier ??
      "",
  ).trim().toLowerCase();
  if (SELLABLE_TIERS.includes(stamped)) return stamped;

  const priceIds = [
    object?.items?.data?.[0]?.price?.id,
    object?.lines?.data?.[0]?.price?.id,
    object?.lines?.data?.[0]?.pricing?.price_details?.price,
    object?.plan?.id,
  ];
  for (const p of priceIds) {
    const tier = tierForPrice(String(p ?? "").trim());
    if (tier) return tier;
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const secret = (Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "").trim();
  // No secret means no way to tell Stripe from anyone else. Refusing is the
  // only safe answer: a webhook that trusts an unsigned body is a free
  // School plan for whoever finds the URL.
  if (!secret) return json({ error: "STRIPE_WEBHOOK_SECRET is not set" }, 500);

  // RAW text, before any parsing — the signature is over these exact bytes.
  const rawBody = await req.text();
  const verdict = await verifyStripeSignature(
    req.headers.get("stripe-signature"),
    rawBody,
    secret,
    Math.floor(Date.now() / 1000),
  );
  if (!verdict.ok) {
    // 400, no detail to the caller, nothing written, nothing read.
    console.error("rejected unsigned/invalid Stripe webhook:", verdict.reason);
    return json({ error: "invalid signature" }, 400);
  }

  // deno-lint-ignore no-explicit-any
  let event: any;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  const type = String(event?.type ?? "");
  const object = event?.data?.object ?? {};

  let plan: string | null = null;
  if (GRANTS.includes(type)) {
    // A checkout session that hasn't actually been paid yet (async payment
    // methods) is not a grant — invoice.paid will follow when it clears.
    const paid = type !== "checkout.session.completed" ||
      ["paid", "no_payment_required"].includes(String(object?.payment_status ?? ""));
    if (!paid) return json({ ok: true, ignored: `${type} (unpaid)` });
    plan = tierFrom(object);
    if (!plan) {
      // Better to grant nothing than to guess a tier and hand out an
      // allowance nobody paid for.
      console.error("grant event with no recognisable tier:", type, JSON.stringify(object?.metadata ?? {}));
      return json({ ok: true, ignored: `${type} (unknown tier)` });
    }
  } else if (REVOKES.includes(type)) {
    plan = "trial";
  } else if (LIFECYCLE.includes(type)) {
    const status = String(object?.status ?? "");
    const live = LIVE_STATUSES.includes(status) && object?.cancel_at_period_end !== true;
    if (live) {
      plan = tierFrom(object);
      if (!plan) return json({ ok: true, ignored: `${type} (unknown tier)` });
    } else if (["canceled", "unpaid", "incomplete_expired", "paused"].includes(status)) {
      plan = "trial";
    } else {
      // incomplete, or cancel_at_period_end while still paid up: the teacher
      // keeps what they have until it actually lapses, and the deleted event
      // will say so.
      return json({ ok: true, ignored: `${type} (${status})` });
    }
  } else {
    // Everything else Stripe sends — and everything it adds later.
    // Acknowledge (a non-2xx makes Stripe retry for days) and change nothing.
    return json({ ok: true, ignored: type });
  }

  const teacherId = teacherIdFrom(object);
  if (!teacherId) {
    // A subscription made by hand in the Stripe dashboard has no teacher on
    // it. There is nothing safe to do with it here.
    console.error("no teacher_id on", type, "— nothing written");
    return json({ ok: true, ignored: `${type} (no teacher_id)` });
  }

  const { error } = await serviceDb()
    .from("profiles")
    .upsert({ teacher_id: teacherId, plan, updated_at: new Date().toISOString() }, { onConflict: "teacher_id" });
  if (error) {
    // A 500 makes Stripe retry, which is what we want when the database
    // blinked: the grant is not lost.
    console.error("profiles upsert failed:", error.message);
    return json({ error: error.message }, 500);
  }

  return json({ ok: true, teacherId, plan, type });
});
