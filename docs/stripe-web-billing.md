# Web billing with Stripe Checkout

On a phone, plans are bought in the store and RevenueCat tells the server
about it. In a browser there is no store, so a teacher on the web could not
pay at all — the trial dead-ended on the one screen built to sell.

This is the web half. It is deliberately a separate road: **nothing here
touches the phone.** RevenueCat, `purchases_flutter`, the paywall, restore
and the Customer Centre are all exactly as they were.

It is also cheaper. Under Google's 2026 external-payments rules a web
checkout costs 10% where Play Billing costs 15%.

---

## Nothing is configured yet

There is no Stripe account behind this build, and the price ids below do not
exist. **That is a supported state, not a broken one:**

| Where | What a teacher sees |
| --- | --- |
| Plans screen, web, no `STRIPE_SECRET_KEY` | The tier cards, greyed, and *"Card payments aren't switched on yet — you're on the preview allowance. Plans can still be bought in the phone app."* |
| Key set, no `STRIPE_RETURN_ORIGIN` | *"Card payments are half set up (no return address configured), so checkout is switched off for now."* |
| Key and origin set, no price ids | *"No plans are on sale on the web yet — you're on the preview allowance."* |
| One tier priced, others not | Only the priced tiers are buyable. A tier with no price id **disappears from sale** — it is never quietly sold at another tier's price. |
| Checkout function unreachable | *"Couldn't reach the checkout — check your connection and try again."* |

There is never a live button that cannot work. The app asks the server
(`action: "status"`) what is on sale *before* it paints the cards.

---

## The two functions

### `STRIPE-CHECKOUT` — creates the session, grants nothing

Deployed **with** JWT verification (the default): it is called by the
signed-in app.

```
POST {action:"status"}                    → {configured, tiers[], message}
POST {action:"create", teacherId, tier}   → {url}   // the hosted checkout
POST {action:"portal", teacherId}         → {url}   // change card / cancel
```

Two rules do the security work:

1. **Identity** — `requireTeacher()`, the same helper `MARKING-PROCESS`
   puts in front of every action that touches a teacher's account. The
   gateway has already validated the JWT's signature; this checks that the
   caller's `sub` **is** the `teacherId` in the body. Otherwise a teacher
   could open a checkout that credits somebody else's account.
2. **Price** — the client names a **tier** (`"pro"`). The Stripe price id is
   looked up from `TIER_PRICE_ENV`, a server-side map built from secrets.
   The request body is read in exactly three places — `action`, `teacherId`,
   `tier` — so a `price`, an `amount`, a `currency` or a `plan` in the
   request is not rejected so much as **never read**. A tier that is not in
   the map is a `400`.

The session records who is paying, at creation time, in
`client_reference_id`, `metadata[teacher_id]` / `metadata[tier]`, and
`subscription_data[metadata][…]` so that renewals and cancellations months
later still say whose plan they are.

### `STRIPE-WEBHOOK` — the only thing that grants a plan

Deployed **`--no-verify-jwt`**, exactly like `REVENUECAT-WEBHOOK`: Stripe
sends its own signature, not a Supabase JWT.

`profiles.plan` has one writer per payment rail and no others. The Supabase
anon key ships inside the APK and the web bundle, so anything the client can
send a teacher can send with curl — which is why `MARKING-PROCESS` strips
`plan` out of `save_profile`, and why the redirect back from Stripe grants
nothing.

**Signature verification, step by step** (`verifyStripeSignature`):

1. Read the **raw** body as text — not parsed and re-stringified. The
   signature is over the exact bytes Stripe sent; any reserialization
   (key order, spacing, number formatting) breaks it.
2. Parse `Stripe-Signature: t=<unix>,v1=<hex>[,v1=<hex>]`.
3. `signed_payload = "<t>.<rawBody>"`.
4. HMAC-SHA256 it with `STRIPE_WEBHOOK_SECRET`, hex-encoded (Web Crypto).
5. Compare against **every** `v1` in **constant time** (length check, then
   XOR-accumulate over all bytes). Several `v1` values appear while a secret
   is being rolled; any one matching is genuine. A plain `===` would leak,
   byte by byte, how much of a guess was right.
6. Reject any `t` more than **300 seconds** from now, in either direction,
   so a genuine webhook captured off the wire cannot be replayed forever to
   re-grant a plan that has since been cancelled.

**If any step fails: `400`, nothing is read, nothing is written, and the
reason is logged server-side only.** Without this check, anyone who finds
the URL can POST themselves a School plan.

Event semantics mirror the RevenueCat webhook's `GRANTS` / `REVOKES`:

| Stripe event | Effect on `profiles.plan` |
| --- | --- |
| `checkout.session.completed` (`payment_status` paid / no_payment_required) | grant the tier |
| `checkout.session.completed` (unpaid, async method) | ignored — `invoice.paid` follows when it clears |
| `invoice.paid`, `invoice.payment_succeeded` | grant the tier (renewals) |
| `customer.subscription.created` / `.updated` / `.resumed`, status `active`/`trialing`/`past_due` and not `cancel_at_period_end` | grant the tier |
| same, status `canceled`/`unpaid`/`incomplete_expired`/`paused` | `trial` |
| `customer.subscription.deleted` | `trial` |
| `invoice.payment_failed` | `trial` |
| `customer.subscription.paused` | `trial` |
| anything else | acknowledged with `200`, nothing written |

The tier comes from our own metadata first, then from a reverse lookup of
the price id. **If neither identifies a tier, nothing is granted** — better
no plan than a guessed one that hands out an allowance nobody paid for.
Same for a subscription created by hand in the Stripe dashboard: no
`teacher_id`, no write.

A database failure returns `500` on purpose, so Stripe retries and the grant
is not lost. The upsert is idempotent, so retries are harmless.

---

## Secrets to set

```bash
# The Stripe API key. Test mode first.
npx supabase secrets set STRIPE_SECRET_KEY=sk_test_xxx

# The web app's own origin, NO trailing path. Return URLs are built from
# this and never from anything the client sends, so this endpoint cannot be
# turned into an open redirect.
npx supabase secrets set STRIPE_RETURN_ORIGIN=https://markless.app

# One recurring price per tier, created in the Stripe dashboard.
# These MUST match lib/screens/plans/plans_screen.dart and PLAN_CAPS.
npx supabase secrets set STRIPE_PRICE_STARTER=price_xxx      # $6.99  / month
npx supabase secrets set STRIPE_PRICE_PRO=price_xxx          # $14.99 / month
npx supabase secrets set STRIPE_PRICE_PRO_ANNUAL=price_xxx   # $119.99 / year
npx supabase secrets set STRIPE_PRICE_SCHOOL=price_xxx       # $24.99 / month

# The SIGNING secret of the webhook endpoint (starts whsec_, and is NOT the
# API key). Test mode and live mode have different ones.
npx supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_xxx
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are already present in the
edge runtime.

> **The prices are the margin.** `PLAN_CAPS` in `MARKING-PROCESS` derives
> each plan's monthly AI spend cap from its price at 24%. If a Stripe price
> is created at a different number from the table above, the cap no longer
> matches what the teacher pays and the margin guarantee silently stops
> holding. Change a price → re-cut its cap.

### Creating the prices

Stripe dashboard → **Product catalogue** → add a product per tier, each with
one **recurring** price (monthly, except Pro Annual which is yearly), in USD.
Copy each `price_…` id into the secrets above. Nothing in this code creates
products, so the dashboard is the single source of truth for what a plan
costs.

---

## Deploy

```bash
# Called by the signed-in app — JWT verification ON (the default).
npx supabase functions deploy STRIPE-CHECKOUT

# Called by Stripe, which sends its own signature, not a Supabase JWT.
npx supabase functions deploy STRIPE-WEBHOOK --no-verify-jwt
```

The `--no-verify-jwt` is not optional and not a relaxation: without it the
gateway rejects Stripe's calls before the function ever runs. The signature
check inside the function is what replaces it, and it is stricter.

## Point Stripe at the webhook

Stripe dashboard → **Developers → Webhooks → Add endpoint**:

* **URL** — `https://<project-ref>.supabase.co/functions/v1/STRIPE-WEBHOOK`
* **Events** — `checkout.session.completed`, `invoice.paid`,
  `invoice.payment_succeeded`, `invoice.payment_failed`,
  `customer.subscription.created`, `customer.subscription.updated`,
  `customer.subscription.deleted`, `customer.subscription.paused`,
  `customer.subscription.resumed`
* Copy the endpoint's **Signing secret** into `STRIPE_WEBHOOK_SECRET`.

Also enable the **Customer portal** (Settings → Billing → Customer portal)
with cancellation allowed, or the "Manage or cancel subscription" button has
nothing to open.

---

## Testing

### In Stripe test mode

Use `sk_test_…`, test-mode price ids and the test-mode signing secret.
Stripe's test cards:

| Card | What happens |
| --- | --- |
| `4242 4242 4242 4242` | succeeds |
| `4000 0000 0000 9995` | declined (insufficient funds) — no grant |
| `4000 0025 0000 3155` | requires 3-D Secure authentication |
| `4000 0000 0000 0341` | attaches, then fails on the first charge → `invoice.payment_failed` → back to `trial` |

Any future expiry, any CVC, any postcode.

### End to end, for real

1. Sign in to the web app, open **Plans**. The cards should be live — if
   they are greyed, read the message: it names which secret is missing.
2. Choose Pro. The tab goes to `checkout.stripe.com`. Pay with `4242…`.
3. Stripe returns you to `…/#/plans?checkout=success&session_id=cs_…`.
4. Stripe dashboard → Developers → Webhooks → your endpoint: the
   `checkout.session.completed` delivery should be **200**, with a response
   body naming the teacher id and the plan.
5. Supabase → Table editor → `profiles`: that teacher's `plan` is now `pro`.
6. Back in the app the snackbar says *"You're all set"* and the usage meter
   shows the Pro allowance immediately — the 45-second `getUsage` cache is
   invalidated on the grant.

**Prove the redirect grants nothing.** With the webhook endpoint disabled in
Stripe, pay again: the app will say *"Payment received — your new plan is
still being switched on."* and `profiles.plan` will be unchanged. Then, with
no payment at all, paste `…/#/plans?checkout=success` into the address bar:
same message, still no plan. The URL is a breadcrumb; the webhook is the
grant.

**Prove the signature is doing its job.**

```bash
curl -i -X POST https://<project-ref>.supabase.co/functions/v1/STRIPE-WEBHOOK \
  -H 'content-type: application/json' \
  -d '{"type":"invoice.paid","data":{"object":{"metadata":{"teacher_id":"<your-uuid>","tier":"school"}}}}'
# → 400 {"error":"invalid signature"} and profiles.plan is untouched.
```

Then use `stripe listen --forward-to <url>` or the dashboard's **Send test
webhook**, both of which sign properly, and watch the same event land.

### What has NOT been tested

There is no Stripe account behind this repo, so **no call has ever been made
to the real Stripe API, no Checkout Session has been created, and no real
webhook has been received.** What *was* exercised locally, by running both
functions under Deno against a stub database:

* signature verification — valid, missing, malformed, wrong secret, ten
  minutes old, in the future, body tampered after signing, and a rolled
  secret where only the second `v1` matches. Only correctly-signed, fresh
  bodies wrote anything; a tampered body claiming a School plan got `400`.
* every grant and revoke event above, including unknown tier, missing
  `teacher_id`, unpaid checkout, and `cancel_at_period_end` while still paid.
* the checkout guards — another teacher's id, no token, an `anon` token, a
  tier not in the map, a client-supplied price id and amount, a tier with no
  price configured, and a `teacherId` carrying a quote.

The exact field names Stripe uses on `invoice` objects move between API
versions; the tier lookup reads several shapes and falls back to the price
id, but **the first live test-mode payment is still the thing that proves
it**. Check the webhook's delivery log on that first payment.

---

## What the client does

`lib/services/billing_service.dart` — everything under the "Web checkout"
heading is web-only and gated on `onWeb`; the phone path is untouched.

* `loadWebCheckout()` — asks `status`, drives the honest messages above.
* `startWebCheckout(tier, teacherId:)` — sends `{action, teacherId, tier}`
  and nothing else, then hands the tab to Stripe with a full same-tab
  navigation (a popup would be eaten by the blocker, because the URL only
  exists after a round trip and the click is no longer a user gesture).
* `handleCheckoutReturn(teacherId:)` — reads the return URL only to decide
  *whether to ask the server*, then polls `get_profile` for a paid
  `profiles.plan`. On a grant it calls
  `AiGradingService.invalidateUsageCache(teacherId)` so the new allowance
  shows at once instead of 45 seconds later. Until the server says a paid
  plan, the answer is "still being switched on" and nothing changes.
* `openBillingPortal(teacherId:)` — Stripe's own portal, found from the
  subscription metadata (so no new column on `profiles`).

Tests: `test/stripe_web_billing_test.dart`.

## Still to do

* **Mobile ↔ web double billing.** A teacher who subscribes in the phone app
  *and* on the web pays twice, and the two webhooks will fight over
  `profiles.plan`. Neither rail knows about the other. Worth a check in
  `STRIPE-CHECKOUT` (refuse when RevenueCat already has them) before this
  is advertised.
* **Tax.** Stripe Tax is not enabled on the session. Add
  `automatic_tax[enabled]=true` once tax registrations exist.
* **Refunds.** `charge.refunded` is not handled — a refund cancels the
  subscription, which does revoke, but an immediate refund-without-cancel
  leaves the plan until the period ends.
