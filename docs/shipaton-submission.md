# Markless — RevenueCat Shipaton 2026 submission (working draft)

Deadline: **2026-09-30, 23:45 PDT**. This is a drafting document, not the final
copy — every `TODO:` below is a gap that must be filled or the claim removed
before submitting. A confident wrong number in a judged document is worse than
a blank.

Target categories: **HAMM**, **Next Gen Award**, **RevenueCat Peace Prize**,
**#BuildInPublic**, **OneSignal "Keep Them Coming Back"**.

---

## The one-paragraph pitch

Marking eats teachers' evenings. Markless takes the first pass: a teacher points
their phone at a class set — a Google Form export, a stack scanned on the
staffroom photocopier, or photographs of individual papers — and gets back
question-by-question marks with half and quarter marks, a written justification
for every deduction, and feedback short enough that a fourteen-year-old will
actually read it. The teacher overrides anything they disagree with. Marks leave
as a gradebook CSV or a Google Doc in Drive. Student names are read and blacked
out on the device, so the marking model never learns whose paper it is.

Repo: https://github.com/drposhbug/ai-marking-dreamflow (MIT)

`TODO:` demo video URL
`TODO:` app store URL (see the asset checklist at the bottom)

---

## HAMM — Help Apps Make Money

The argument: Markless cannot sell a subscription that loses money, and that is
enforced in code rather than hoped for in a spreadsheet.

### 1. The margin rule

Every plan's AI spend cap is derived from its price by one formula. Of the gross
subscription price:

| Slice | Share | Why |
| --- | --- | --- |
| App store commission | 15% | Apple/Google Small Business Program rate |
| Charity give-back | 10% | Comes off the top, not off profit |
| RevenueCat | 1% | Free under $2.5k/mo, 1% after |
| Target profit | 50% | |
| **Left for AI** | **24%** | |

```
monthlyUsd = price × 0.24
```

Implemented as `PLAN_CAPS` in
`supabase/functions/MARKING-PROCESS/index.ts`:

| Plan | Price | × 0.24 | Cap in code | Roughly |
| --- | --- | --- | --- | --- |
| Free trial | — | — | $0.40 | The only row allowed to lose money; capped tight on purpose |
| Starter | $6.99/mo | $1.68 | $1.65 | ~210 papers/mo overnight |
| Pro | $14.99/mo | $3.60 | $3.55 | ~455 papers/mo overnight |
| Pro Annual | $119.99/yr | $2.40 | $2.35 | ~300 papers/mo overnight |
| School | $24.99/mo | $6.00 | $5.95 | ~760 papers/mo overnight |

The interesting part is the enforcement. `budgetGate()` reads real billed spend
out of `usage_log` and **refuses to start marking** once the account is past its
cap. So the cap is not a fair-use guideline — it *is* the profit guarantee. The
worst possible subscriber, the one who burns every cent of their allowance on
the 1st of the month, still returns the target margin. There is no tail risk
because there is no path to the tail.

Pro Annual is the rule catching a real mistake before launch. $119.99/yr is
$10.00/mo, so it cannot carry the $14.99 monthly Pro cap — that would have been
a guaranteed loss on every annual subscriber, the customers you most want. It
became its own server-side tier with its own derived cap.

The rule also names its own dependency: the 24% assumes enrolment in the app
store Small Business Program. If that is ever lost, the AI share drops from 24%
to 9% and every cap has to be recut. That is written into the code comment so
the next person cannot miss it.

### 2. Mark-metered tiers, not "unlimited"

Four paid tiers, all metered, none advertised as unlimited. Two design choices
make the meter fair enough that teachers accept it:

- **Credits are cost-weighted, not counted.** The meter is real billed token
  spend, so a two-page multiple-choice quiz costs a fraction of a six-page
  problem set. Nobody is charged a "paper" for a quiz.
- **Re-marking is free.** A `grade_cache` table keyed on sorted image hashes
  plus settings serves an identical re-mark with zero AI tokens. Changing the
  display format or fixing a misread student name is excluded from the cache
  key, so those are free too.
- **Pacing sub-limits** (25% of the month in one day, 50% in one week) stop a
  single test day from consuming the month, so the plan lasts the way the
  teacher expected it to.

The app only ever shows percentages, never dollars — the teacher sees "you've
used 40% of this month", not the unit economics.

### 3. The cost levers that make the margin comfortable

- **Learned keys.** Marking the first paper of a keyless class set works out the
  correct answers anyway, so that derived key is stored as a real answer key and
  the remaining 29 papers are marked against it on a cheap deterministic route —
  roughly a tenth of the frontier cost per paper. Multiple-choice keys store the
  *position* of the correct option, so the rest of the class is marked by
  comparing two digits instead of re-reading four printed options on every page.
- **Overnight batching.** A class set submitted to the Anthropic Message Batches
  API costs about five times less per paper than marking on the spot (measured
  ~$0.008 vs ~$0.039). This is also the upsell: *instant* marking is gated to
  Pro, Pro Annual and School (`INSTANT_MARKING_PLANS`), so trial and Starter
  mark overnight. The one carve-out is deliberate — the pilot paper of every set
  marks live on every plan, free included, because approving the first result
  before the other 29 go out is a safety check, not a premium feature.

  > `TODO:` the Starter card in `lib/screens/plans/plans_screen.dart` advertises
  > "About 200 papers a month marked overnight, **or 40 on the spot**", but
  > `INSTANT_MARKING_PLANS` on the server excludes `starter`. One of the two is
  > wrong. Resolve before a judge or a subscriber finds it.
- **Free on-device work.** Multiple-choice marking from a Google Form CSV, PDF
  copy stamping, stack splitting and OCR anchoring all run on the phone. Zero
  marginal cost, and stamping in particular removes the credits a mis-split
  stack would otherwise burn.
- **Prompt caching and feedback banks.** Static marking rules and the answer key
  are cached with a 1h TTL; the model returns short codes (`#5`) that the server
  expands into full sentences, so feedback prose costs no output tokens.

### 4. RevenueCat doing monetisation work

- Prices are never hard-coded. The Plans screen renders `priceString` from the
  current Offering, so a price change or a price experiment ships from the
  dashboard with no app update and no store review.
- One entitlement, `markless Pro`. Which of the four tiers a teacher is on is
  resolved server-side from the product id, so the tier ladder can be
  restructured without touching the client's gating logic.
- A referral loop pays in the currency teachers actually run out of: every
  colleague who joins with a teacher's code **and is on a paid plan** adds
  bonus marking credits to the monthly cap. Free referrals add nothing, so it
  cannot be farmed with throwaway accounts, and the bonus is sized against
  measured cost ($0.20 each, capped at $1.00 total) so it comes out of the 50%
  margin without eating it.

### 5. Metrics

`TODO:` MRR at submission
`TODO:` paying subscribers / trial-to-paid conversion rate
`TODO:` measured average cost per mark from `admin_stats` after the R1.1–R1.9
test pass — the $0.008 / $0.039 figures are from 2026-08-25 and must be re-pulled
`TODO:` realised gross margin vs the 50% target

Do not submit an invented number in any of these fields. If a metric is not
measurable by the deadline, say so.

---

## Next Gen Award (student category)

No app store release is required for this category, which makes it the hedge
against a slipped Play review. It requires a public repository with a
machine-detectable open-source licence, a demo video, and a meaningful
RevenueCat integration.

**Eligibility:** `TODO:` attach active-student evidence (.edu email or
enrolment letter) — `REMAINING.md` R8.4.

### App clarity

The product decision worth showing a judge is the **Ways to Mark** screen. Left
alone, most teachers reach for the camera — the slowest of the four routes at
about 15 minutes for a class of thirty — decide the app is slow, and never find
out the same job takes about two minutes through a Google Form export. So the
four routes sit on the home screen with honest times and the actual steps, not
buried in a help section:

1. **Google Form or spreadsheet** — ~2 min. Nothing to scan.
2. **Prepare, print, then scan the stack** — ~6 min. The app stamps a per-copy
   code into the footer of every page before printing, so the scanned stack
   sorts itself out and cannot mix two students up.
3. **Scan a stack you already printed** — ~6 min. Split by fixed length or by
   on-device detection of cover pages.
4. **Photograph each paper** — ~15 min. For a handful, or a late submission.

The guide is the difference between the product being fast and merely being
capable of being fast.

### Technical implementation

- **OCR anchoring.** A vision model can say roughly where an error is but never
  precisely; its coordinates drift by a line or two, which reads as sloppy
  marking. Google ML Kit runs on the device to get exact word rectangles, and
  the model's coordinates are downgraded to a hint that only picks *which
  occurrence* of a repeated word the annotation belongs to.
- **Identity never reaches the model.** The student name is read on the phone,
  blacked out of the image, and kept locally as the link between the result and
  the right student. Only the anonymised page is uploaded.
- **Model routing.** Claude Sonnet for judgment, Gemini 2.5 Flash as fallback, a
  cheap text model for keyed objective questions, with any failure falling
  through to the frontier path rather than returning a worse mark.
- **Refusing to guess.** A diagram, an unreadable page, a right answer reached
  by an unusual method, or a language comprehension paper with no key returns a
  flag for the teacher, not a fabricated score.
- **Everything expensive is cached or batched**: grade cache, prompt cache,
  learned keys, overnight batches.

### Meaningful RevenueCat integration

The strongest technical detail in the project is a security one. The Supabase
anon key ships inside the APK — it has to, because the client needs it to reach
the edge function at all. So anything the app is allowed to send, a teacher can
send by hand with `curl`. If plan assignment were a client request, every
teacher would have a free School plan the day the app went public.

`profiles.plan` therefore has exactly one writer: the `REVENUECAT-WEBHOOK` edge
function, which RevenueCat calls only after validating the receipt with Google
or Apple. It authenticates with a shared secret, maps grant and revoke events to
plan rows with loose product-id matching, ignores anonymous app user ids, and
writes with the service role key that never leaves the server.

The inbound side enforces the same rule from the other direction: the
`save_profile` action accepts name, school, region and marking defaults, and
deliberately drops `plan` even when the client sends it. A whitelist would only
have limited a teacher to picking "pro", which is not a defence.

Result: entitlement, plan row and marking budget cannot diverge in the
subscriber's favour. `isPro` on the client is presentation only; the server
re-reads the plan on every marking call.

---

## RevenueCat Peace Prize

> **Do not submit this section as written.** The give-back is currently
> marketing copy — a line in `lib/screens/plans/plans_screen.dart` and in
> `docs/store-listing.md` saying "Every paid plan gives 10% to charities that
> help kids learn", with no named charity, no accounting, and no public receipt
> behind it. To a Peace Prize judge that reads as a slogan, and in store review
> it is a liability. `REMAINING.md` R9 tracks making it real. Either R9.1–R9.3
> land before the deadline, or this section is cut and the claim is removed from
> the app and the store listing too.

### The honest part of the story

Teacher workload is the reason people leave teaching. Marking is the part that
follows them home — it is not the lesson, it is the two hours after dinner with
a stack of thirty papers. Markless is aimed squarely at that: a class set that
took an evening takes minutes, and what comes back is not just a number but
per-question feedback the student can act on, which is the part teachers cut
first when they are tired.

Two design decisions are ethical positions rather than features, and both cost
something:

- **Student identity does not go to the AI.** Names are read and redacted on the
  device. This is real work — on-device OCR, image compositing — done so that a
  school board's rules about third-party processing are satisfiable.
- **The model refuses to guess.** Where it cannot mark honestly it flags the
  question for the teacher instead of producing a plausible score. That costs
  the "fully automated" pitch, deliberately.

### The give-back, once it is real

`TODO:` name the charity and commit to it publicly (R9.1)
`TODO:` Settings "Giving" row showing dollars generated to date, derived from
real subscription revenue rather than a hardcoded number (R9.2)
`TODO:` a public receipt — a monthly post or page — so the claim is evidenced
(R9.3)
`TODO:` dollars given at submission time

The one thing already true and worth saying: the 10% is in the margin rule as a
first-class slice, taken off gross price before profit. It is not funded out of
whatever is left over at the end of the year.

---

## #BuildInPublic

Skeleton for the development-journey narrative. This is the category that needs
history rather than engineering, and it cannot be caught up in the last week —
posting runs daily from now.

**The arc:** a student building the tool a teacher asked for, in public, against
a hard deadline, with the unit economics worked out loud rather than hidden.

Beats worth telling, each of which is a real commit:

1. **"Put the four ways to mark on the home screen."** Realising the fastest
   route was the one nobody was finding, and that the fix was product copy, not
   a faster model.
2. **"Print the identity onto the paper so students never write it twice."**
   Solving the scanned-stack mixing problem with a printed code instead of
   handwriting matching — on-device, free, and it removes the credits a
   mis-split would burn.
3. **"Stop two Anas swapping marks."** The wrong-mark bug, accents included, and
   the decision to refuse to guess rather than pick the likelier student.
4. **The margin rule.** Working out that Pro Annual at $10.00/mo could not carry
   the monthly Pro cap, and that the fix was to make the spend cap the profit
   guarantee.
5. **"The anon key is in the APK."** Why `profiles.plan` had to move to a
   webhook, and why a whitelist would not have been a defence.
6. **Making the give-back real** (or publicly deciding not to claim it).

`TODO:` post links — X/Twitter thread URLs
`TODO:` post links — LinkedIn / Bluesky / dev.to, wherever the posts actually live
`TODO:` any post that got meaningful engagement, called out specifically
`TODO:` confirm the required hashtag and tagging convention for the category

---

## OneSignal — "Keep Them Coming Back"

> **In progress, not shipped.** `REMAINING.md` R7 is unchecked. The
> `onesignal_flutter` dependency has just been added to `pubspec.yaml`, but the
> send paths are not finished and every "notification" in the app today is still
> an in-app SnackBar. This section describes the intended integration and must
> be rewritten in the past tense — or dropped — depending on what actually ships
> by the deadline.

The product gap comes first and the prize second. Overnight marking is the
flagship feature and the whole point of it is that the teacher closes the app
and goes to bed. Today they have to reopen the app to find out it finished,
which is the worst possible ending for the best feature.

Planned notifications:

- **"Your class set is marked."** Fired server-side from the overnight batch
  completion path, deep-linking straight to the results. This is the one that
  makes overnight marking work as a product.
- **Trial ending, and approaching the mark cap.** These are the upgrade
  triggers, so they feed the HAMM story as well as retention.
- **Weekly "you saved about N hours this week."** The re-engagement hook that is
  actually worth receiving, because it reports something the teacher cares
  about rather than asking for attention.

Design rules that come with it: the Android notification permission is requested
after the first batch is queued, not on first launch; the OneSignal external
user id is the teacher id, matching `Purchases.logIn`, so RevenueCat and
OneSignal address the same person; every notification respects a Settings
toggle; and nothing fires for a teacher who has never queued a batch.

`TODO:` rewrite once R7.1–R7.6 land
`TODO:` delivery / open-rate numbers, if there is enough data by the deadline

---

## Submission assets still needed

| Asset | Spec | Status |
| --- | --- | --- |
| Demo video | ~2 minutes | `TODO:` not recorded (R5.1) |
| App icon | 1024×1024 | `assets/icons/markless_icon_1024.png` exists; `TODO:` confirm it is the final art and that `pubspec.yaml`'s `flutter_launcher_icons.image_path` points at it, not at `dreamflow_icon.jpg` (R4.3) |
| Screenshot | 1179×2556 | `TODO:` not produced (R4.6) |
| Judge access | Promo code or free trial | `TODO:` decide which; a promo code needs the app live on a store track |
| App store URL | Play listing | `TODO:` blocked on R4.7–R4.12 |
| Public repo | MIT licensed | Licence added; `TODO:` flip the repo to public (R8.2) |
| Privacy policy URL | Public | `docs/index.html` is ready; `TODO:` switch on GitHub Pages (see `docs/README.md`) |
| Student evidence | For Next Gen | `TODO:` .edu email or enrolment letter (R8.4) |
| Build-in-public post links | | `TODO:` collect (R5.3) |

### Demo video running order (draft)

Two minutes is not much. Suggested cuts:

1. The problem, in one line, over a stack of paper. (10s)
2. Google Form route end to end — the two-minute path, shown in real time. (25s)
3. Paper route — stamped copies printed, stack fed through the scanner, split,
   pilot paper approved, class marked. (40s)
4. The result: per-question marks with justifications, a flagged question the
   app refused to guess, export to gradebook. (25s)
5. Plans screen and the honest meter — the monetisation beat. (10s)
6. Close on the repo and the licence. (10s)

`TODO:` decide whether the class item analysis screen (R6) makes the cut — it is
the best single beat in the demo if it ships, and cutting it is fine if it does
not.
