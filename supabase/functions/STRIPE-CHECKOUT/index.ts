// supabase/functions/STRIPE-CHECKOUT/index.ts
//
// Sells a plan to a teacher in a browser. On a phone the store does this and
// RevenueCat reports it; a browser has no store, so a teacher on the web
// could not pay at all — the trial simply dead-ended.
//
// This function creates a Stripe Checkout Session and hands back its URL.
// It GRANTS NOTHING. Card details never touch this code (Stripe hosts the
// page), and profiles.plan is written only by STRIPE-WEBHOOK, after Stripe
// has signed for the payment. See that file.
//
// Two rules do the security work here:
//   1. IDENTITY — requireTeacher(): the caller's JWT `sub` must BE the
//      teacherId in the body. Otherwise a teacher could open a checkout that
//      credits somebody else's account (or bills their own card to another).
//   2. PRICE — the client names a TIER ("pro"). The Stripe price id is
//      looked up from a server-side map built out of secrets. A request that
//      carries a price id, an amount, a currency or a plan name is refused;
//      a tier that isn't in the map is a 400. So the worst a teacher can do
//      by editing the request is choose which of four published prices to
//      be charged — and the webhook grants exactly the tier that was paid.
//
// Actions (POST JSON):
//   {action:"status"}                       → {configured, tiers[]} — the
//        honest-message probe. Costs nothing, needs no identity, and is what
//        lets the app show "card payments aren't switched on" instead of a
//        button that cannot work.
//   {action:"create", teacherId, tier}      → {url} — the hosted checkout.
//   {action:"portal", teacherId}            → {url} — Stripe's billing
//        portal, where a teacher changes the card or cancels.
//
// Secrets required (`npx supabase secrets set ...`):
//   STRIPE_SECRET_KEY      — sk_test_… / sk_live_… from the Stripe dashboard.
//   STRIPE_RETURN_ORIGIN   — the web app's own origin, e.g.
//                            https://markless.app (NO trailing slash). The
//                            return URLs are built from this and never from
//                            anything the client sends, so this endpoint can
//                            not be turned into an open redirect.
//   STRIPE_PRICE_STARTER      — price_… for Starter   $6.99/mo
//   STRIPE_PRICE_PRO          — price_… for Pro       $14.99/mo
//   STRIPE_PRICE_PRO_ANNUAL   — price_… for Pro Annual $119.99/yr
//   STRIPE_PRICE_SCHOOL       — price_… for School    $24.99/mo
//
// Every one of these is optional in the sense that the function still runs
// without them: it reports configured:false with a plain-English reason and
// refuses to create anything. A missing price id removes that ONE tier from
// sale — it never silently sells it at another tier's price.
//
// Deploy (JWT verification ON — this one is called by the signed-in app):
//   npx supabase functions deploy STRIPE-CHECKOUT
//
// No SDK: like every other function here, Stripe is called with plain fetch.

import { createClient } from "npm:@supabase/supabase-js@2";

function serviceDb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

/// Claims out of the caller's bearer token. Signature checking is the
/// gateway's job (verify_jwt = true), so this only decodes — never trust it
/// for anything the gateway hasn't already validated.
// deno-lint-ignore no-explicit-any
function jwtClaims(authHeader: string | null): Record<string, any> | null {
  try {
    const token = String(authHeader ?? "").replace(/^Bearer\s+/i, "").trim();
    const body = token.split(".")[1];
    if (!body) return null;
    const pad = body.length % 4 === 0 ? body : body + "=".repeat(4 - (body.length % 4));
    return JSON.parse(atob(pad.replace(/-/g, "+").replace(/_/g, "/")));
  } catch {
    return null;
  }
}

/// The same guard MARKING-PROCESS puts in front of every action that reads,
/// writes or spends a teacher's account. The anon key ships in the APK and
/// in the web bundle, so a teacherId in a request body is a request, not an
/// identity: the gateway has validated the token's signature, and this
/// checks that the signed-in account IS that teacherId.
function requireTeacher(req: Request, teacherId: string, message = "Sign in again to buy a plan."): Response | null {
  const claims = jwtClaims(req.headers.get("authorization"));
  if (claims?.role !== "authenticated" || String(claims?.sub ?? "") !== teacherId) {
    return json({ error: message }, 403);
  }
  return null;
}

// ---------- The price map. The ONLY place a tier becomes money. ----------
//
// Keys are the plan names profiles.plan holds and PLAN_CAPS meters — so what
// a teacher buys, what the webhook writes and what the marking budget
// allows are the same four words. A tier that is not a key here cannot be
// bought, whatever the request says.
const TIER_PRICE_ENV: Record<string, string> = {
  starter: "STRIPE_PRICE_STARTER",
  pro: "STRIPE_PRICE_PRO",
  pro_annual: "STRIPE_PRICE_PRO_ANNUAL",
  school: "STRIPE_PRICE_SCHOOL",
};

/// The configured Stripe price for a tier, or null when that tier has no
/// price id set (not on sale) or the tier isn't one of ours.
function priceFor(tier: string): string | null {
  const envName = TIER_PRICE_ENV[tier];
  if (!envName) return null;
  const price = (Deno.env.get(envName) ?? "").trim();
  return price.startsWith("price_") ? price : null;
}

/// Tiers the server can actually sell right now.
function sellableTiers(): string[] {
  return Object.keys(TIER_PRICE_ENV).filter((t) => priceFor(t) !== null);
}

/// Everything the owner has to set before a teacher can pay, and what to say
/// when it isn't set. Honest messages beat a broken button.
function configuration(): { ok: boolean; message: string; tiers: string[] } {
  const key = (Deno.env.get("STRIPE_SECRET_KEY") ?? "").trim();
  const origin = returnOrigin();
  const tiers = sellableTiers();
  if (!key) {
    return { ok: false, tiers: [], message: "Card payments aren't switched on yet — you're on the preview allowance. Plans can still be bought in the phone app." };
  }
  if (!origin) {
    return { ok: false, tiers: [], message: "Card payments are half set up (no return address configured), so checkout is switched off for now." };
  }
  if (tiers.length === 0) {
    return { ok: false, tiers: [], message: "No plans are on sale on the web yet — you're on the preview allowance." };
  }
  return { ok: true, tiers, message: "" };
}

/// Where Stripe sends the teacher back to. Read from a secret, never from
/// the request: a client-supplied return URL would make this an open
/// redirect with a Stripe-branded page in front of it.
function returnOrigin(): string {
  const origin = (Deno.env.get("STRIPE_RETURN_ORIGIN") ?? "").trim().replace(/\/+$/, "");
  return /^https?:\/\/[^\s"'<>]+$/.test(origin) ? origin : "";
}

// ---------- Stripe REST, with fetch ----------

async function stripe(
  path: string,
  init: { method: "GET" | "POST"; form?: URLSearchParams },
  // deno-lint-ignore no-explicit-any
): Promise<{ ok: boolean; status: number; body: any }> {
  const key = (Deno.env.get("STRIPE_SECRET_KEY") ?? "").trim();
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: init.method,
    headers: {
      authorization: `Bearer ${key}`,
      ...(init.form ? { "content-type": "application/x-www-form-urlencoded" } : {}),
    },
    body: init.form ? init.form.toString() : undefined,
  });
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return { ok: res.ok, status: res.status, body };
}

/// A teacher id is a Supabase uuid. Checked before it goes anywhere near a
/// Stripe search query, so it can't carry quotes into one.
function safeId(id: string): boolean {
  return /^[A-Za-z0-9._@-]{1,64}$/.test(id);
}

/// The Stripe customer behind this teacher's subscription, if there is one.
///
/// Found by searching the metadata the checkout stamped on the subscription
/// — so the link between a teacher and a Stripe customer lives in Stripe,
/// and needs no new column on profiles. Best effort: a teacher who has never
/// subscribed simply has none.
async function customerFor(teacherId: string): Promise<string | null> {
  if (!safeId(teacherId)) return null;
  try {
    const q = new URLSearchParams({ query: `metadata['teacher_id']:'${teacherId}'`, limit: "1" });
    const res = await stripe(`subscriptions/search?${q.toString()}`, { method: "GET" });
    const sub = res.ok ? res.body?.data?.[0] : null;
    const customer = sub?.customer;
    return typeof customer === "string" && customer.startsWith("cus_") ? customer : null;
  } catch (e) {
    console.error("customerFor failed:", e instanceof Error ? e.message : e);
    return null;
  }
}

/// The teacher's email, only so Stripe can prefill the checkout and send a
/// receipt. Read with the service role from the row we already own.
async function emailFor(teacherId: string): Promise<string> {
  try {
    const { data } = await serviceDb().from("profiles").select("email").eq("teacher_id", teacherId).maybeSingle();
    const email = String(data?.email ?? "").trim();
    return email.includes("@") ? email : "";
  } catch {
    return "";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // deno-lint-ignore no-explicit-any
  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  const action = String(payload?.action ?? "").trim();
  const config = configuration();

  // ── status: can a teacher pay here at all? ─────────────────────────────
  // No identity needed — it reveals nothing but whether the owner has
  // connected Stripe, and the app needs the answer before it paints buttons.
  if (action === "status") {
    return json({ configured: config.ok, tiers: config.tiers, message: config.message });
  }

  if (action !== "create" && action !== "portal") {
    return json({ error: `unknown action: ${action}` }, 400);
  }

  const teacherId = String(payload?.teacherId ?? "").trim();
  if (!teacherId) return json({ error: "teacherId is required" }, 400);
  if (!safeId(teacherId)) return json({ error: "teacherId is not a valid account id" }, 400);
  // Identity first, before anything is created against an account.
  const guard = requireTeacher(req, teacherId);
  if (guard) return guard;

  if (!config.ok) return json({ error: "not_configured", message: config.message }, 503);

  // ── portal: change the card, or cancel ────────────────────────────────
  if (action === "portal") {
    const customer = await customerFor(teacherId);
    if (!customer) {
      return json({ error: "no_subscription", message: "No web subscription found on this account." }, 404);
    }
    const form = new URLSearchParams({
      customer,
      return_url: `${returnOrigin()}/#/plans`,
    });
    const res = await stripe("billing_portal/sessions", { method: "POST", form });
    if (!res.ok || !res.body?.url) {
      console.error("portal session failed:", res.status, JSON.stringify(res.body?.error ?? res.body));
      return json({ error: "stripe_error", message: "Couldn't open the billing page." }, 502);
    }
    return json({ url: String(res.body.url) });
  }

  // ── create: the checkout session ──────────────────────────────────────
  const tier = String(payload?.tier ?? "").trim().toLowerCase();
  const price = priceFor(tier);
  if (!price) {
    // Covers all three of: a tier that doesn't exist, a tier with no price
    // configured, and a client that tried to send its own price or amount
    // (those fields are simply never read).
    return json({ error: "unknown_tier", message: `"${tier}" isn't a plan that's on sale.` }, 400);
  }

  const origin = returnOrigin();
  const form = new URLSearchParams({
    mode: "subscription",
    "line_items[0][price]": price,
    "line_items[0][quantity]": "1",
    // ?checkout=success is a breadcrumb for the app, NOT a grant: landing on
    // it only makes the app ask the server what the webhook wrote.
    success_url: `${origin}/#/plans?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${origin}/#/plans?checkout=cancelled`,
    // Who is paying, recorded by the server at session creation. The webhook
    // reads the plan's owner from here and from nowhere the client can reach
    // at redemption time.
    client_reference_id: teacherId,
    "metadata[teacher_id]": teacherId,
    "metadata[tier]": tier,
    // Carried onto the subscription so renewals, cancellations and payment
    // failures — which arrive months later with no session attached — still
    // say whose plan they are.
    "subscription_data[metadata][teacher_id]": teacherId,
    "subscription_data[metadata][tier]": tier,
    allow_promotion_codes: "true",
  });

  const existing = await customerFor(teacherId);
  if (existing) {
    form.set("customer", existing);
  } else {
    const email = await emailFor(teacherId);
    if (email) form.set("customer_email", email);
  }

  const res = await stripe("checkout/sessions", { method: "POST", form });
  if (!res.ok || !res.body?.url) {
    console.error("checkout session failed:", res.status, JSON.stringify(res.body?.error ?? res.body));
    return json({ error: "stripe_error", message: "Couldn't start the checkout. Nothing was charged." }, 502);
  }
  return json({ url: String(res.body.url), tier });
});
