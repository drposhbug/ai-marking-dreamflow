# Markless

Marking eats teachers' evenings. Markless takes the first pass.

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
2026**. It is not yet released on any app store; see [Status](#status) for what
is and is not wired up.

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
Flutter client (Android / iOS)
  ├─ on-device: OCR, name redaction, stack splitting, MC marking, PDF stamping
  └─ Supabase Edge Functions (Deno)
       ├─ MARKING-PROCESS     marking, batching, usage metering, profiles, export data
       ├─ REVENUECAT-WEBHOOK  the only writer of profiles.plan
       └─ SETUP-DB            idempotent schema bootstrap
             └─ Postgres: profiles, answer_keys, grade_cache, marking_batches,
                usage_log, submissions, classes, students, schools
```

### Client

Flutter with Material 3, `go_router` for navigation and `provider` for state.
Services live in `lib/services/`; screens in `lib/screens/`. The client holds no
API keys for any AI provider — every model call is made server-side.

### MARKING-PROCESS

One edge function with an `action` field, covering marking (`grade`,
`batch_submit`, `batch_status`, `mark_responses`), answer keys (`extract_key`,
`list_keys`), account data (`save_profile`, `get_profile`, `delete_account`),
usage (`get_usage`, `plan`), and helpers like roster extraction and report
comments.

The marking pipeline:

- **Primary grader:** Claude Sonnet (`claude-sonnet-5`) with vision.
- **Fallback:** Gemini 2.5 Flash, when the primary path fails.
- **Cheap objective route:** for *keyed* marking of objective questions, a
  cheaper text model (DeepSeek) marks against the key deterministically at
  roughly a tenth of the frontier cost. Essays, lab reports and keyless marking
  skip it, and any failure falls through to the frontier path.
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
devices and reinstalls, `restorePurchases()`, the remotely-configured
`presentPaywallIfNeeded` paywall, and RevenueCat's Customer Center for
cancel/restore/refund.

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

So `profiles.plan` has exactly one writer: the `REVENUECAT-WEBHOOK` edge
function, which RevenueCat calls **after** it has validated the receipt with
Google or Apple. The webhook:

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
store (Apple/Google Small Business Program), 10% to the give-back, 1% to
RevenueCat, and 50% is target profit — leaving **24% for AI spend**.

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

Requires the Flutter SDK (Dart `^3.6.0`).

```bash
flutter pub get

flutter run \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=REVENUECAT_ANDROID_KEY=goog_...
```

**No keys are committed to this repository, by design.** They are supplied at
build time with `--dart-define` and default to empty:

| Define | Used by | Behaviour when absent |
| --- | --- | --- |
| `SUPABASE_ANON_KEY` | `lib/main.dart` | App runs local-only; nothing is marked |
| `SUPABASE_URL` | `lib/main.dart` | Falls back to the project's own URL |
| `REVENUECAT_ANDROID_KEY` (`goog_…`) | `lib/services/billing_service.dart` | Billing stays disabled — no `configure` call, no store contact, and the Plans screen says so in plain English |
| `REVENUECAT_IOS_KEY` (`appl_…`) | `lib/services/billing_service.dart` | As above, on iOS |
| `ONESIGNAL_APP_ID` | push notifications (`REMAINING.md` R7) | Push stays disabled; the app falls back to in-app messages |

Both RevenueCat SDK keys are public-by-design once set and safe to ship inside
the binary; they are kept out of the repo because a wrong key crashed the app on
device, not because they are secret. The same is true of the OneSignal app id.

> `TODO:` OneSignal (R7) is being wired up as this is written — the
> `onesignal_flutter` dependency is in `pubspec.yaml` but the send paths are not
> finished, and every "notification" in the app today is still an in-app
> SnackBar. Confirm the `ONESIGNAL_APP_ID` row above against the finished code
> before publishing this README.

### Backend

Edge functions are deployed with the Supabase CLI. `REVENUECAT-WEBHOOK` must be
deployed with `--no-verify-jwt`. Run `SETUP-DB` once after deploying to create
the tables; it is safe to run repeatedly.

Server-side secrets (set with `npx supabase secrets set`, never in the repo):

| Secret | Purpose |
| --- | --- |
| `ANTHROPIC_API_KEY` | Primary marking model |
| `GEMINI_API_KEY` | Fallback marking model |
| `DEEPSEEK_API_KEY` | Optional. Without it, keyed marking pays frontier prices instead of taking the cheap objective route |
| `REVENUECAT_WEBHOOK_SECRET` | Must match the Authorization header configured in the RevenueCat dashboard webhook |
| `SUPABASE_SERVICE_ROLE_KEY` | Provided by the platform; used by both functions |

RevenueCat webhook URL:
`https://<project-ref>.supabase.co/functions/v1/REVENUECAT-WEBHOOK`

### iOS

`.github/workflows/ios-build.yml` builds an unsigned `.ipa` on GitHub's macOS
runners, since the project is developed on Windows.

---

## Status

Honest state as of 2026-08-30. The working checklist is `REMAINING.md`.

**Working:** the four marking routes, the marking pipeline with keys, learned
keys and overnight batching, on-device OCR anchoring and name redaction, plan
metering and the budget gate, gradebook CSV export, Google Drive export, report
comments, class and student management.

**Not done yet:**

- RevenueCat products are not created in the dashboard, so no Offering exists
  and billing is inert in every current build. The code paths are written and
  the webhook is deployed; the purchase flow has not been exercised end to end
  (`REMAINING.md` R2.1–R2.6).
- No app store release. Play Console listing, declarations and signed release
  build are outstanding (R4).
- Push notifications (R7) and class item analysis (R6) are in progress, not
  shipped. Overnight marking still requires reopening the app to see that it
  finished.
- The 10% give-back is currently copy in the Plans screen and the store listing
  with no named charity and no public receipt behind it (R9).

---

## Documentation

- `docs/privacy-policy.md` — privacy policy (rendered for hosting as
  `docs/index.html`)
- `docs/security-and-compliance.md` — what leaves the device, subprocessors,
  retention, known gaps
- `docs/store-listing.md` — store listing copy
- `docs/shipaton-submission.md` — hackathon submission draft
- `REMAINING.md` — the working checklist

## License

MIT — see [LICENSE](LICENSE).
