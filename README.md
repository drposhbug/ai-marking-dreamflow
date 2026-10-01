# UMarkless

Marking eats teachers' evenings. UMarkless takes the first pass.

A teacher points the app at a class set — a Google Form export, a scanned stack
from the photocopier, or photographs of individual papers — and gets back
question-by-question marks with half and quarter marks, a written justification
for every deduction, and feedback short enough that a fourteen-year-old will
read it. The teacher overrides anything they disagree with; the app never has
the last word on a grade. Marks then leave as a gradebook CSV or as a Google Doc
in Drive.

Two rules shape the whole product:

- **The teacher decides the grade.** Where the model cannot mark something
  honestly — a diagram, an unreadable page, a right answer reached by an unusual
  method, a language comprehension paper with no key — it says so and flags the
  question for the teacher instead of guessing a score.
- **Student identity does not go to the AI.** The name is read off the page on
  the device, blacked out of the image, and kept on the phone. Only the
  anonymised page is uploaded (`lib/services/anonymizer.dart`).

This is an active hackathon project, submitted to the **RevenueCat Shipaton
2026**. The same Flutter app runs on Android, iOS and the web; the web build is
live at [umarkless.com](https://umarkless.com). It is not yet released on any
app store; see [Status](#status) for what is and is not wired up.

## For judges

1. **Watch the 2-minute demo video:** https://www.youtube.com/watch?v=uCEYYs5QZyY
2. **Try it in your browser:** https://umarkless.com/app → tap **"Try it as a guest"** to mark real sample papers, no sign-up needed.
3. **See how RevenueCat is used:** [How RevenueCat is used](#how-revenuecat-is-used).
4. **Run it yourself:** [Build and run](#build-and-run).

## Demo

- **Demo video:** https://www.youtube.com/watch?v=uCEYYs5QZyY
- **Try it:** [umarkless.com](https://umarkless.com) runs the web build.
  Continue as a guest to mark the built-in sample papers, with no sign-up.

---

## The four ways to mark

These are the four routes the app actually supports, surfaced on the home screen
rather than buried in help — the fastest route is the one nobody guesses. Times
are for a class of thirty. Source of truth:
`lib/screens/grading/ways_to_mark_screen.dart`.

### 1. Google Form or spreadsheet — about 2 minutes

Best for quizzes and anything students type. Nothing to scan at all. The teacher
exports the Form responses to a CSV, imports it, confirms the detected columns
and taps the correct option for each multiple-choice question.

Multiple choice is marked **on the device for free** — no API call, no credits.
Only written answers go to the model, and every student's answer to a single
question is marked together in one pass, so the whole class is judged against
the same standard.

### 2. Prepare, print, then scan the stack — about 6 minutes

The fastest paper route, and the only one that cannot mix students up. The
teacher uploads their test file and picks a copy count; the app generates a
single print-ready PDF containing every copy, each stamped in the footer of
**every page** with its own code (`mk-7F3A-01`, `mk-7F3A-02`, …). Stamping runs
entirely on the device (`lib/services/test_stamper.dart`) — no API cost.

Papers come back, go through the copier's document feeder as one PDF, and pages
sharing a code reassemble into one student's paper. Printed text is
machine-clean, so shuffled, creased or out-of-order pages still land correctly.

### 3. Scan a stack you already printed — about 6 minutes

For a test that has already been written on and printed the ordinary way. The
stack is scanned to one PDF and split back into papers
(`lib/services/pdf_splitter.dart`), either by fixed page length or by
**on-device detection** of cover-page signals (a "Name:" field near the top, a
"Page 1 of 4"). Detection uploads nothing — the boundaries are found on the
phone, the split is shown to the teacher, and only what they confirm is marked.
Telling the app how many students to expect catches a page the feeder swallowed.

### 4. Photograph each paper — about 15 minutes

For a handful of papers, a late submission, or anywhere without a copier. The
phone is propped up, pages are slid underneath, and it shoots automatically with
a sound or a buzz to say the page landed.

### Common to all four

The **pilot paper** of a set is always marked on its own and shown to the
teacher before the other twenty-nine go ahead. A wrong answer key costs one
paper, never thirty. This holds on every plan, including free — approving the
first result is a safety check, not a premium feature.

---

## Architecture

```
Flutter client (Android / iOS / web)
  ├─ on-device: OCR, name redaction, stack splitting, MC marking, PDF stamping
  └─ Supabase Edge Functions (Deno)
       ├─ MARKING-PROCESS     marking, batching, usage metering, profiles, export data
       ├─ OVERNIGHT-SWEEPER   settles overnight batches, sends the "marked" push
       ├─ REVENUECAT-WEBHOOK  store purchases  ─┐ the only writers of a plan,
       ├─ STRIPE-WEBHOOK      web purchases    ─┘ via apply_entitlement()
       ├─ STRIPE-CHECKOUT     creates hosted Checkout / billing portal sessions
       └─ SETUP-DB            idempotent schema bootstrap
             └─ Postgres: profiles, answer_keys, grade_cache, marking_batches,
                usage_log, submissions_cloud, collections_cloud (classes,
                students), schools, presets, feedback_code_usage

Next.js marketing site (site/) + Flutter web build, served by Vercel at umarkless.com
```

### Client

Flutter with Material 3, `go_router` for navigation and `provider` for state.
Services live in `lib/services/`; screens in `lib/screens/`. The client holds no
API keys for any AI provider — every model call is made server-side.

The web build is the same app. Where a browser cannot do what the phone does
(ML Kit, the native purchase sheet), it falls back: Tesseract and pdf.js for
reading pages. Buying a plan in a browser uses an experimental Stripe Checkout,
which is switched off, so for now plans are bought in the mobile app. The
marketing site in `site/` is a separate Next.js static export.

### MARKING-PROCESS

One edge function with an `action` field, covering marking (`grade`,
`batch_submit`, `batch_status`, `mark_responses`), answer keys (`extract_key`,
`list_keys`), account data (`save_profile`, `get_profile`, `delete_account`),
usage (`get_usage`, `plan`), and helpers like roster extraction and report
comments.

The marking pipeline:

- **Primary grader:** Claude Sonnet 5.5 (`claude-sonnet-5-5`) with vision and
  adaptive thinking. Thinking depth follows the job: `low` when marking against
  a key (the model is comparing, not deducing), `medium` for reading a key or
  grouping pages, and `high` for keyless marking.
- **Fallback:** Gemini 2.5 Flash (`gemini-2.5-flash`), when the primary path
  fails.
- **Keyless marking:** with no answer key the model has to work the answers out
  itself, and those answers become the class's learned key (below). One wrong
  answer there is thirty wrong marks, and it runs once per class set, so it
  gets Claude at `high` effort. Kimi K2.6 instant can be put in front with
  `KIMI_KEYLESS=true`, but stays off until it has been measured against Claude
  on real keyless papers.
- **Cheap objective route:** for *keyed* marking of objective questions (and
  keyless homework at grade 6 and below), Gemini transcribes the page and a
  cheaper text model (DeepSeek) marks against the key at roughly a tenth of the
  frontier cost. Essays and lab reports skip it, and any failure falls through
  to the frontier path.
- **Data residency:** the open-weight models (Kimi, DeepSeek) run on DeepInfra
  in US data centres with zero retention. The vendors' own PRC-hosted APIs are
  used only when no DeepInfra key is set, and Moonshot's additionally needs an
  explicit `KIMI_ALLOW_MOONSHOT=true`.
- **Overnight batching:** a class set can be submitted to the Anthropic Message
  Batches API and collected later, which is about five times cheaper per paper
  than marking on the spot (measured ~$0.008/paper overnight vs ~$0.039 live).
- **Learned keys:** marking a keyless paper works out the correct answers
  anyway, so the first paper's derived key is stored as a real answer key and
  the rest of the class is marked against it on the cheap route
  (`maybeStoreLearnedKey`). Multiple-choice keys store the *position* of the
  right option, so the rest of the class is marked by comparing two digits
  rather than re-reading four printed options on every paper.
- **Cost controls:** feedback sentence banks (the model returns `#5`, the
  function expands it), Anthropic prompt caching on the static rules and the
  answer key, and a `grade_cache` table keyed on sorted image hashes plus
  settings so an identical re-mark costs nothing. Re-marking the same paper is
  free.
- **Metering:** every call writes real token cost to `usage_log`, and
  `budgetGate()` refuses to start work once the account is past its cap. See
  [The margin rule](#the-margin-rule).

### On-device OCR anchoring

A vision model can say roughly where an error is, but never precisely — its
coordinates drift by a line or two, which reads as sloppy marking. So the app
runs Google ML Kit text recognition on the device
(`lib/services/word_locator.dart`), gets exact word rectangles, and **downgrades
the model's coordinates to a hint** that only decides *which occurrence* of a
repeated word the annotation belongs to. When recognition is unavailable (web,
unreadable handwriting, missing model) it falls back to the model's estimate.

The same on-device text recognition does three other jobs that would otherwise
cost money or privacy: reading the student name so it can be redacted before
upload, finding paper boundaries in a scanned stack, and reading the printed
`mk-` codes off stamped copies.

---

## RevenueCat integration

Subscriptions run through RevenueCat (`purchases_flutter` /
`purchases_ui_flutter`). Implementation:
`lib/services/billing_service.dart`, `lib/screens/plans/plans_screen.dart`,
`supabase/functions/REVENUECAT-WEBHOOK/index.ts`.

### How RevenueCat is used

| What | Where |
| --- | --- |
| SDK setup: `Purchases.configure`, the customer-info listener, and `Purchases.logIn(teacherId)` so a plan follows the account | [`billing_service.dart`](lib/services/billing_service.dart#L249) (configure), [`#L327`](lib/services/billing_service.dart#L327) (logIn) |
| Plans screen: loads the current Offering and renders store prices; purchase, restore | [`plans_screen.dart`](lib/screens/plans/plans_screen.dart), [`BillingService` offerings and purchase](lib/services/billing_service.dart#L272) |
| Customer Center: cancel, restore, refund requests | [`presentCustomerCenter`](lib/services/billing_service.dart#L453), opened from the [Plans screen](lib/screens/plans/plans_screen.dart#L328) |
| Entitlement check: the single `markless Pro` entitlement drives `isPro` in the app | [`entitlementId` and `_onCustomerInfo`](lib/services/billing_service.dart#L351) |
| Webhook: the only path that grants or revokes a plan, via `apply_entitlement` | [`REVENUECAT-WEBHOOK`](supabase/functions/REVENUECAT-WEBHOOK/index.ts) |
| Test purchases are ignored: events from the `SANDBOX` environment or the `TEST_STORE` are acknowledged without changing a plan, unless `REVENUECAT_ACCEPT_SANDBOX=true` | [`REVENUECAT-WEBHOOK/index.ts#L91`](supabase/functions/REVENUECAT-WEBHOOK/index.ts#L91) |

All subscriptions in the mobile app run through RevenueCat. The repo also contains an experimental Stripe checkout for the web version, which is switched off; the plan is to move web payments to RevenueCat Web Billing so every subscription lives in RevenueCat.

### Offerings drive pricing, so prices change without an app update

The app hard-codes no prices. `BillingService.loadOfferings()` pulls the current
Offering and the Plans screen renders `storeProduct.priceString` straight from
the store, so a teacher in Canada sees CAD and a price experiment ships from the
RevenueCat dashboard rather than through a store review.

The tier cards in `plans_screen.dart` carry a *fallback* price string used only
until the Offering arrives, and match themselves to a store package by substring
hints on the product id plus `PackageType`, so renaming
`markless_pro_monthly` → `pro_monthly` in the store does not silently unmatch a
tier. A tier with no published product renders as unavailable with a plain
explanation instead of a dead button.

Also wired: `Purchases.logIn(teacherId)` so entitlements follow a teacher across
devices and reinstalls, `restorePurchases()`, and RevenueCat's Customer Center
for cancel/restore/refund. A remotely-configured paywall
(`presentPaywallIfNeeded`) is implemented in `BillingService.presentPaywall()`
but not yet shown from any screen; the Plans screen is the purchase surface.

### One subscription, two shops

*Experimental, and switched off: no Stripe keys are set, so web checkout is
unavailable. Web payments are planned to move to RevenueCat Web Billing.*

The design: a teacher who marks on a laptop should not need a phone to pay. In
a browser, the Plans screen would send them to a hosted Stripe Checkout
(`BillingService.startWebCheckout` → `STRIPE-CHECKOUT`); on Android and iOS it
uses the store through RevenueCat. Either way it is one plan on one account:
each webhook records its own rail (`plan_revenuecat`, `plan_stripe`) and the
SQL function `apply_entitlement` sets `profiles.plan` to the better of the two.
A teacher already subscribed on one rail is refused a second subscription on
the other (`409 already_subscribed`). Runbook: `docs/stripe-web-billing.md`.

### One entitlement

A single entitlement, `markless Pro`, gates the paid experience
(`BillingService.entitlementId`). Everything else — which of the four tiers a
teacher is on, and therefore how much marking they get — is resolved
server-side from the product id.

### profiles.plan is written by the server, never by the client

This is the part worth reading the code for.

The Supabase **anon key ships inside the APK**. It has to: the client needs it
to call the edge function at all. That means anything the app is allowed to
send, a teacher can send by hand with `curl`. If plan assignment were a request
the client makes, every teacher would have a free School plan the day the app
went public.

So `profiles.plan` is only ever written through `apply_entitlement`, and only
two callers reach it: the `REVENUECAT-WEBHOOK` edge function, which RevenueCat
calls **after** it has validated the receipt with Google or Apple, and the
`STRIPE-WEBHOOK` function, which verifies Stripe's signature
(`STRIPE_WEBHOOK_SECRET`) before trusting an event. The RevenueCat webhook:

- authenticates with a shared `REVENUECAT_WEBHOOK_SECRET`, accepting both the
  raw header and the `Bearer x` form, and rejects anything else with 401;
- is deployed `--no-verify-jwt`, because RevenueCat sends its own Authorization
  header, not a Supabase JWT;
- maps the event to a plan row (`starter` / `pro` / `pro_annual` / `school`)
  with loose product-id matching, so renaming a store product does not silently
  drop paying teachers to trial;
- treats `INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION`,
  `NON_RENEWING_PURCHASE`, `PRODUCT_CHANGE`, `SUBSCRIPTION_EXTENDED` and
  `TRANSFER` as grants, and `CANCELLATION`, `EXPIRATION`, `BILLING_ISSUE`,
  `SUBSCRIPTION_PAUSED` and `REFUND` as revocations back to `trial`;
- acknowledges anything else (test events, future event types) without changing
  a row;
- ignores `$RCAnonymousID:` app user ids, since a purchase made before sign-in
  belongs to a device, not an account — it arrives again as `TRANSFER` once the
  teacher logs in;
- writes with the service role key, which never leaves the server.

The other half of the rule is enforced on the inbound side. `MARKING-PROCESS`'s
`save_profile` action accepts name, school, region and marking defaults, and
**deliberately drops `plan` even when the client sends it**:

```ts
// `plan` is deliberately NOT writable here. The anon key ships inside
// the APK, so anything this endpoint accepts, any teacher can set for
// themselves — a whitelist only limited them to picking "pro". Plans are
// written by the REVENUECAT-WEBHOOK function against a store receipt.
```

The result is that the entitlement, the plan row and the marking budget cannot
diverge in the teacher's favour. The client's view of `isPro` is presentation
only; the server re-reads `profiles.plan` on every marking call.

### The margin rule

Plan caps are derived, not guessed. Of a plan's gross price: 15% goes to the app
store (the reduced small-developer rate), 10% is set aside for the give-back, 1%
to RevenueCat, and 50% is target profit — leaving **24% for AI spend**. Web
purchases through Stripe cost less than the store cut and use the same caps, so
the rule is conservative there.

```
monthlyUsd = price × 0.24
```

Credits are cost-weighted real billed spend, not mark counts, so a two-page
multiple-choice quiz costs a fraction of a six-page problem set. `budgetGate()`
refuses to start marking past the cap, which means the cap *is* the profit
guarantee: even a subscriber who burns their whole allowance still returns the
target margin. Pacing sub-limits (25% of the month in a day, 50% in a week) stop
one test day from consuming the month.

The rule is why Pro Annual is a separate server-side tier: $119.99/yr is
$10.00/mo, so it cannot carry the $14.99 monthly Pro cap without being a
guaranteed loss on every annual subscriber.

---

## Build and run

### Prerequisites

- **Flutter 3.44.x stable** (tested on 3.44.4; Dart 3.12 or later). Older
  Flutter versions fail at `flutter pub get`.
- Android Studio for Android, Xcode for iOS, or Chrome for the web build.
- Node.js, for the Supabase CLI (`npx supabase`) and the SQL tests.
- A Supabase project.
- Keys: Anthropic and Google Gemini (required). RevenueCat for store billing.
  Stripe, OneSignal and DeepInfra are optional.

Without any keys the app still builds and runs in local-only mode, but nothing
is marked.

### 1. Backend (Supabase)

```bash
# Link the CLI to your project
npx supabase login
npx supabase link --project-ref <ref>

# Server secrets: fill in a copy of the template, then upload it
cp supabase/functions/.env.example supabase/functions/.env
npx supabase secrets set --env-file supabase/functions/.env --project-ref <ref>

# Deploy the functions. The two webhooks skip JWT checks because each provider
# sends its own credentials instead of a Supabase JWT.
npx supabase functions deploy MARKING-PROCESS    --project-ref <ref>
npx supabase functions deploy SETUP-DB           --project-ref <ref>
npx supabase functions deploy STRIPE-CHECKOUT    --project-ref <ref>
npx supabase functions deploy OVERNIGHT-SWEEPER  --project-ref <ref>
npx supabase functions deploy REVENUECAT-WEBHOOK --project-ref <ref> --no-verify-jwt
npx supabase functions deploy STRIPE-WEBHOOK     --project-ref <ref> --no-verify-jwt

# Create the schema. Safe to run again after any update. SETUP-DB only accepts
# the service role key (Dashboard → Project Settings → API keys).
curl -X POST https://<ref>.supabase.co/functions/v1/SETUP-DB \
  -H "Authorization: Bearer <service role key>"
```

There is no `supabase/migrations` folder: `SETUP-DB` is the schema. Every table
has row level security on and no policies, so the anon key cannot read or
write any table directly. The app reaches its data only through the edge
functions.

**Schedule the overnight job (optional).** `OVERNIGHT-SWEEPER` collects
overnight batches and sends the "your class set is marked" push. It runs on a
schedule, and **pg_cron and pg_net must be enabled first** (they are off on a
new project). In the SQL editor:

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Keep the service role key in Vault, not in plain text inside the job.
select vault.create_secret('<service role key>', 'sweeper_service_key');

select cron.schedule('overnight-sweeper', '*/15 * * * *', $$
  select net.http_post(
    url     := 'https://<ref>.supabase.co/functions/v1/OVERNIGHT-SWEEPER',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets
                                      where name = 'sweeper_service_key')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 120000);
$$);
```

Stop it with `select cron.unschedule('overnight-sweeper');`.

### 2. Sign-in providers

In the Supabase dashboard under **Authentication → Providers**, enable
**Email**, and optionally **Google**, **Azure** (shown as Microsoft) and
**Apple**, each with its own OAuth client from that provider. Google sign-in
also asks for the `drive.file` scope, which is used for exporting marks to
Google Docs.

Under **Authentication → URL Configuration**, add these redirect URLs:

- `com.markless.app://login-callback`, for the Android and iOS apps
- your web origin, e.g. `http://localhost:<port>/` for `flutter run -d chrome`,
  or the deployed site's URL. The web build redirects back to the page it was
  opened from.

### 3. RevenueCat

1. Create a project with a Google Play app (and an App Store app for iOS),
   and copy the public SDK keys (`goog_…`, `appl_…`) into `.env`.
2. Create one entitlement, **`markless Pro`**, exactly as written.
3. Create the store products and attach them to `markless Pro`. Put them in the
   **current Offering**. The app matches tiers by product id, so each id should
   contain `starter`, `pro`, `pro_annual` or `school`.
4. Add a webhook pointing at
   `https://<ref>.supabase.co/functions/v1/REVENUECAT-WEBHOOK`, with the
   Authorization header set to the same value as `REVENUECAT_WEBHOOK_SECRET`.

Sandbox and Test Store purchases are ignored by the webhook unless
`REVENUECAT_ACCEPT_SANDBOX=true` is set, so testing never grants a real plan.

### 4. Run the app

```bash
cp .env.example .env      # fill in
flutter pub get
flutter run --dart-define-from-file=.env
```

**`SUPABASE_URL` must be set when you use your own Supabase project.** When it
is missing, the app falls back to the original UMarkless project, so a fresh
clone would quietly talk to someone else's backend.

**No secret keys are committed to this repository.** The only key included
is the Supabase **anon** key, inside the compiled web build under `docs/app/`.
That is by design: the anon key ships in every copy of the app, and row level
security plus the edge functions' own checks decide what it can reach. Every
other value is supplied at build time with `--dart-define` and defaults to
empty:

| Define | Used by | Behaviour when absent |
| --- | --- | --- |
| `SUPABASE_ANON_KEY` | `lib/main.dart` | App runs local-only; nothing is marked |
| `SUPABASE_URL` | `lib/main.dart` | Falls back to the original UMarkless project. Set it for your own |
| `REVENUECAT_ANDROID_KEY` (`goog_…`) | `lib/services/billing_service.dart` | Billing stays disabled — no `configure` call, no store contact, and the Plans screen says so in plain English |
| `REVENUECAT_IOS_KEY` (`appl_…`) | `lib/services/billing_service.dart` | As above, on iOS |
| `ONESIGNAL_APP_ID` | `lib/services/push_service.dart` | Push stays disabled; the app falls back to in-app messages |

Both RevenueCat SDK keys are public-by-design once set and safe to ship inside
the binary; they are kept out of the repo because a wrong key crashed the app on
device, not because they are secret. The same is true of the OneSignal app id.

The web build is produced with `tool/build_vercel.ps1` (Flutter web app plus the
Next.js site in `site/`); see `docs/vercel-hosting.md`.

### Server-side secrets

Set with `npx supabase secrets set` (see `supabase/functions/.env.example`),
never committed. **Stripe web checkout and OneSignal push are optional and not
configured by default:** without their secrets, `STRIPE-CHECKOUT` answers
`not_configured` and the web Plans screen reports checkout as unavailable, and
overnight results show up in the app instead of as a push.

| Secret | Purpose |
| --- | --- |
| `ANTHROPIC_API_KEY` | Primary marking model and overnight batches |
| `GEMINI_API_KEY` | Fallback marking model; page transcription for the cheap route |
| `DEEPINFRA_API_KEY` | Optional. Serves the cheap objective route (DeepSeek) and, if enabled, keyless Kimi marking. Without it, that work goes to Claude |
| `KIMI_KEYLESS` | Optional. `true` puts Kimi K2.6 ahead of Claude for keyless marking; off by default |
| `DEEPSEEK_API_KEY` | Optional, older alternative for the cheap route, used only when `DEEPINFRA_API_KEY` is unset |
| `DEEPINFRA_MODEL`, `KIMI_MODEL` | Optional model id overrides |
| `MOONSHOT_API_KEY`, `KIMI_ALLOW_MOONSHOT` | Optional. Kimi via Moonshot's own API, only when explicitly allowed |
| `REVENUECAT_WEBHOOK_SECRET` | Must match the Authorization header configured in the RevenueCat dashboard webhook |
| `REVENUECAT_ACCEPT_SANDBOX` | Optional. `true` lets sandbox and Test Store purchases change a plan; by default they are ignored, since test purchases are free |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | Optional, not configured by default. Web checkout and its signed webhook. Setup: `docs/stripe-web-billing.md` |
| `STRIPE_PRICE_STARTER`, `STRIPE_PRICE_PRO`, `STRIPE_PRICE_PRO_ANNUAL`, `STRIPE_PRICE_SCHOOL` | Optional. Stripe price ids for each tier |
| `STRIPE_RETURN_ORIGIN` | Optional. Where Checkout sends the teacher back, e.g. `https://umarkless.com` |
| `ONESIGNAL_APP_ID`, `ONESIGNAL_REST_API_KEY` | Optional, not configured by default. "Your class set is marked" push from `OVERNIGHT-SWEEPER` |
| `FOUNDER_EMAILS`, `FOUNDER_TEACHER_IDS` | Optional. Comma-separated accounts that get the internal `preview` plan for testing. Empty means nobody |
| `ADMIN_STATS_KEY` | Guards the `admin_stats` action |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL` | Provided by the platform |

### iOS

`.github/workflows/ios-build.yml` builds an unsigned `.ipa` on GitHub's macOS
runners, since the project is developed on Windows. It is run by hand from the
Actions tab for now: the build has failed since late September and the cause
is not yet diagnosed. Android and the web build are the tested targets.

---

## Status

Honest state as of 2026-09-30.

**Working:** the four marking routes, the marking pipeline with keys, learned
keys and overnight batching, on-device OCR anchoring and name redaction, plan
metering and the budget gate, gradebook CSV export, Google Drive export, report
comments, class and student management, class item analysis
(`lib/screens/classes/class_analysis_screen.dart`), and the web app at
umarkless.com.

**Not done yet:**

- Subscriptions are configured in RevenueCat and tested in sandbox; the
  Android app is in the process of being submitted to Google Play. The Plans
  screen reads its tiers
  and prices from the current RevenueCat Offering, and debug builds buy
  through RevenueCat's Test Store (a `test_` SDK key). The webhook ignores
  Test Store and sandbox purchases unless `REVENUECAT_ACCEPT_SANDBOX=true`, so
  a test purchase unlocks Pro in the app without changing the server-side
  plan. Real Google Play billing uses the `goog_` key in a release build and
  goes live with the Play release.
- The experimental Stripe checkout for the web version is switched off (no
  Stripe keys are set). Web payments are planned to move to RevenueCat Web
  Billing.
- No App Store release yet; the iOS build is not working (see [iOS](#ios)).
- Push notifications are wired in the app, but the server half that sends
  "your class set is marked", `OVERNIGHT-SWEEPER`, is not deployed yet, so
  overnight marking still needs the app reopened to see that it finished.
- The 10% give-back is built into the margin rule and shown in the app and on
  the site, but no charity is named yet and there is no public receipt.

---

## Documentation

- `docs/privacy-policy.md` — privacy policy (rendered for hosting as
  `docs/index.html`)
- `docs/security-and-compliance.md` — what leaves the device, subprocessors,
  retention, known gaps
- `docs/store-listing.md` — store listing copy
- `docs/stripe-web-billing.md` — web checkout setup
- `docs/vercel-hosting.md` — how umarkless.com is built and served

## Development timeline

- **Jun 26, 2026:** First version of the app, built in Dreamflow.
- **Jun 30:** Live camera scanning, and the first edge function that marks a paper with AI.
- **Jul 25–28:** Multi-page scanning, answer keys saved to the cloud, and real accounts with Google and Apple sign-in.
- **Aug 4:** Cost routing (cheaper models mark objective questions, with Claude as the fallback), spending caps per plan, and Google Drive export with optional auto-save.
- **Aug 5–6:** RevenueCat added, PDF batches marked in one go, answer keys learned from the first paper, and mistakes pinned to the exact words with on-device text recognition.
- **Aug 16:** Release groundwork: app signing, account deletion, and plans that only the server can change.
- **Aug 24–27:** The four ways to mark: Google Form or CSV import, splitting a photocopier scan into papers, overnight batches, and printed copies stamped with a code for each student.
- **Aug 30:** A website, and the same app running in a browser.
- **Sep 21–25:** The rename to UMarkless at umarkless.com, and groundwork for paying from the web version.
- **Sep 30 – Oct 1:** RevenueCat Test Store purchases, a guest mode with sample papers for judges, the AGPL-3.0 license, and a security review before the public release.

## Project history

I started the project in [Dreamflow](https://dreamflow.app), a Flutter app
builder, working on my dad's account. That is why the first few commits
(June 26 – July 1, 2026) carry his company's name and email: Dreamflow pushed
them from his account. They hold the first version of the app, the first
live-scan screen and the first edge-function test, which I built.

Everything after that was built in my own GitHub account, with
[Claude Code](https://claude.com/claude-code) as a coding assistant.

## License

GNU Affero General Public License v3.0 (AGPL-3.0) — see [LICENSE](LICENSE). Anyone who runs a modified version as a service must publish their source too.

```
UMarkless
Copyright (C) 2026 Tyler Lee

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
