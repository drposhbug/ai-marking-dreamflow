# Markless — Remaining Work

Working doc for the agent team. Each item is tagged (R1.1, R1.2, etc.) so agents can
reference it precisely. Delete anything already done; add anything missing.

**Status key:** `[ ]` not started · `[~]` in progress · `[x]` done

---

## R1 — Marking pipeline

- [ ] **R1.1** Keyed route test — Grade 9–11 math/science test with answer key. Confirm
      cost lands near the keyed estimate, and that "right answer, different method"
      flags actually fire.
- [ ] **R1.2** Diagram handling — physics/math test with a diagram. Amber "?" flag should
      exclude the drawing without breaking the rest of the mark.
- [ ] **R1.3** KTCA categories — Ontario test with Knowledge/Thinking/Communication/
      Application section headers. Check category labels, justifications, and the
      category-average toggle.
- [ ] **R1.4** Keyless language paper — French/Spanish listening or reading comprehension.
      Must return "Requires teacher marking", not a guessed score.
- [ ] **R1.5** Handwriting stress test — real pen handwriting, photographed with the
      camera. Check OCR anchoring holds up.
- [ ] **R1.6** Fleet marking — class set of 5+ keyless PDFs at once. First paper full
      price, rest marked cheap against the learned key.
- [ ] **R1.7** Edge cases — half-finished paper with blanks must score 0 (not skip);
      chemistry answer missing units / wrong sig figs should be a quarter-mark
      deduction, not a Communication comment.
- [ ] **R1.8** Cost routing — objective-question routing to the cheaper model, so the
      per-mark average drops below the current figure.
- [ ] **R1.9** Re-pull usage_log spend numbers after R1.1–R1.8 and confirm real
      cost-per-mark against the pricing assumptions.

---

## R2 — Tier gating / RevenueCat

- [ ] **R2.1** RevenueCat products created and matching the server-side tier rows
      (trial, Starter, Pro, Pro Annual, School).
- [ ] **R2.2** Purchase flow wired end-to-end in app — paywall, purchase, restore.
- [ ] **R2.3** Entitlement sync — RevenueCat entitlement writes back to the Supabase
      tier row so mark-count gates enforce correctly.
- [ ] **R2.4** Trial behaviour — 7-day trial starts, counts down, and hard-stops at the
      mark limit with a clear upgrade prompt.
- [ ] **R2.5** Gate enforcement tested at the boundary (last allowed mark vs. first
      blocked mark).
- [ ] **R2.6** Migrate own account off the manual "Preview" plan once real entitlements
      are live.

---

## R3 — Drive export

- [ ] **R3.1** Consent-first toggle in Settings behaves correctly on first enable.
- [ ] **R3.2** Marked test saves as a Google Doc into the "Markless" folder.
- [ ] **R3.3** Success and failure notifications both fire correctly.
- [ ] **R3.4** Email-only accounts can link Google via the "Connect Google Drive" path
      (Supabase identity linking).
- [ ] **R3.5** Failure handling — expired token, revoked access, no network. Should fail
      gracefully, not lose the marked output.
- [ ] **R3.6** Supabase custom domain (e.g. auth.markless.app) so the OAuth consent
      screen doesn't show the raw supabase.co URL.

---

## R4 — Play Console / closed test prep

> Most of this is manual work on the Play Console website, not code.
> Agents can produce the artifacts; the uploads and forms are done by hand.

**Code / build artifacts (agents can help):**
- [ ] **R4.1** Release signing configured (keystore, key.properties, gitignored).
- [ ] **R4.2** Signed release AAB builds cleanly.
- [x] **R4.3** App icon, app name, and version code/name finalized in pubspec + manifest.
- [~] **R4.4** Privacy policy drafted and hosted at a public URL. Page built at
      `docs/index.html`; still needs GitHub Pages switching on (Settings → Pages →
      main / /docs). See docs/README.md.
- [ ] **R4.5** Store listing copy — title, short description, full description.
- [~] **R4.6** Screenshots and feature graphic produced. Icon done
      (assets/icons/markless_icon_1024.png, replacing the Dreamflow builder logo);
      screenshots still need a running app; feature graphic 1024x500 outstanding.

**Manual on Play Console (do myself):**
- [ ] **R4.7** Store listing filled in and assets uploaded.
- [ ] **R4.8** App content declarations completed (data safety, content rating, target
      audience, ads declaration).
- [ ] **R4.9** AAB uploaded to the closed testing track.
- [x] **R4.10** ~~12 testers recruited and opted in.~~ NOT REQUIRED — the 12-tester /
      14-day closed test applies only to PERSONAL accounts created after 2023-11-13.
      This is an organization account, so it is exempt and can go straight to production.
      PRECONDITION: the org account's D-U-N-S / identity verification must be COMPLETE,
      or nothing can be published at all. Confirm this first.
- [ ] **R4.11** Short internal-testing pass for sanity (hours, not weeks) — optional but
      cheap insurance before production.
- [ ] **R4.12** Production release submitted.

---

## R5 — Shipaton submission

- [ ] **R5.1** Demo video recorded.
- [ ] **R5.2** Submission write-up covering the HAMM, #BuildInPublic, and RevenueCat
      Peace Prize categories.
- [ ] **R5.3** Build-in-public posts collected / linked.
- [ ] **R5.4** Give-back mechanism documented for the Peace Prize category.

---

## Constraints for agents

- Work on a feature branch, never directly on the main branch.
- Do not touch `/android`, `/ios`, `/web`, `pubspec.yaml`, or build config without asking.
- Flutter agent works in `/lib` and `/assets` only.
- Backend agent works in `/supabase` only.
- Report back after each R-item — do not run the whole list unattended.
- Return short summaries, not full histories.
## R6 — Class item analysis (Shipaton demo feature)

- [x] **R6.1** After a class set completes, aggregate per-question results across
      all papers in the batch: % correct, average score, most common wrong answer
      or error pattern.
- [x] **R6.2** Class summary screen showing questions ranked worst→best, with the
      KTCA category and a one-line "what went wrong" per question.
- [x] **R6.3** "Reteach" suggestion per weak question — one short paragraph the
      teacher can use or ignore.
- [x] **R6.4** Per-student view: which questions this student missed that most of
      the class got, and vice versa.
- [x] **R6.5** No new schema tables if avoidable — derive from existing per-mark
      results. If a table is genuinely needed, propose it before creating it.
- [x] **R6.6** Must not add cost per mark — analysis runs once per batch, not per paper.
---

## R7 — Push notifications (OneSignal)

> Product gap first, prize second. Overnight marking is the flagship feature and the
> teacher currently has to reopen the app to find out it finished — every "notification"
> in the code today is an in-app SnackBar, not a push. Also unlocks the OneSignal
> "Keep Them Coming Back" category ($25k, the largest sponsor prize).

- [x] **R7.1** OneSignal Flutter SDK added; Android notification permission requested at
      the right moment (after the first batch is queued, not on first launch).
- [x] **R7.2** External user id set to the teacher id, matching `Purchases.logIn` so
      RevenueCat and OneSignal address the same person.
- [~] **R7.3** "Your class set is marked" — client side done; the SERVER half is
      written (OVERNIGHT-SWEEPER) but NOT DEPLOYED, so no push fires yet.
      Originally: fired server-side from the overnight batch
      completion path, deep-linking straight to the results.
- [x] **R7.4** Trial-ending and approaching-mark-cap nudges. These are the upgrade
      triggers, so they feed the HAMM story as well as retention.
- [x] **R7.5** Weekly "you saved about N hours this week" summary — the re-engagement
      hook that is actually worth receiving.
- [x] **R7.6** Every notification respects a Settings toggle, and none fire for a teacher
      who has never queued a batch.

---

## R8 — Next Gen Award (student category)

> No app store release required for this category — it survives a slipped Play review.
> Verified 2026-08-30: full git history is clean of secrets (only a removed RevenueCat
> sandbox `test_` key, public-by-design; the Supabase anon key is `--dart-define`, not
> baked in). The repo is safe to make public.

- [x] **R8.1** LICENSE file added (MIT or Apache-2.0 — must be machine-detectable).
- [ ] **R8.2** Repo flipped to public.
- [x] **R8.3** README rewritten — it is still the Flutter template. This is the first
      thing a Next Gen judge reads: what it does, the architecture, and how the
      RevenueCat integration works.
- [ ] **R8.4** Confirm active-student status evidence (.edu email) for the submission.

---

## R9 — Make the give-back real

> Today "10% to charities that help kids learn" exists only as copy in
> plans_screen.dart and docs/store-listing.md. As a claim with nothing behind it, it
> reads as a slogan to a Peace Prize judge and is a liability in store review.

- [ ] **R9.1** Name the actual charity and commit to it publicly.
- [x] **R9.2** Settings "Giving" row: dollars generated to date, derived from real
      subscription revenue — not a hardcoded number.
- [~] **R9.3** A public receipt (monthly post or page) so the claim is evidenced.

---

## Critical path — 31 days to 2026-09-30 23:45 PDT

| By | What | Why it gates |
|----|------|--------------|
| Aug 31 | Confirm org account verification complete | Nothing publishes until it is |
| Sep 1 | Play app created; privacy policy hosted (R4.4) | Unblocks the `goog_` key AND the listing |
| Sep 2 | RevenueCat products + Offering + `goog_` key (R2.1, R2.2) | Billing is inert in every build until this lands |
| Sep 5 | Signed AAB + listing + declarations (R4.2–R4.9) | |
| Sep 8 | R7 push notifications shipped | |
| Sep 12 | R6 class item analysis shipped | Best beat in the demo video |
| Sep 15 | **Production release submitted** | Leaves ~2 weeks of review buffer |
| Sep 20 | R8 repo public + README (Next Gen hedge) | |
| Sep 25 | Demo video + submission write-up (R5) | |
| Sep 30 | Submit | Hard deadline |

Build-in-public posting runs daily from now — it is the one category that needs
history rather than engineering, and it cannot be caught up later.

### Notes from the R7 build (2026-08-30)

- **R7.3 is client-side.** Nothing server-side ever learns a batch ended — the
  client polling `batch_status` is what sets `status = 'ended'`, as a side effect
  of asking. Sending from the server needs a NEW scheduled function (cron → walk
  `marking_batches` where `status != 'ended'` → OneSignal REST), not a branch
  inside MARKING-PROCESS. The recipe is written up at `PushService.batchDoneCopy`.
  Until that exists, a teacher who never reopens the app still hears nothing.
- **No `android/` change was needed** — the OneSignal AAR contributes
  `POST_NOTIFICATIONS` and its receivers itself.
- **R7.4/R7.5 ship as OneSignal tags**, not on-device scheduled notifications, so
  the segments are built in the OneSignal dashboard. They will not fire until the
  dashboard Journeys exist.
- **Charity is still a placeholder** — `GivingSummary.charityPlaceholder`. R9.1
  and R9.3 remain open, so the Peace Prize section is not submittable yet.

---

## R10 — Web app (done 2026-08-30)

- [x] **R10.1** Web shell branded: real title/description/OG tags, PWA manifest,
      Markless icons, `theme-color` #2563EB. Was still the Flutter template.
- [x] **R10.2** Splash screen so first load isn't a blank white page. Torn down on
      the engine's `flutter-first-frame`, with a 20s hard timeout so a failed boot
      can never leave a stuck spinner.
- [x] **R10.3** `web/bundle.js` deleted — a dead Passkeys shim, render-blocking in
      `<head>`. Verified: no passkeys web package resolves, and the compiled bundle
      contains no Passkeys reference.
- [x] **R10.4** Redaction honesty (see R11) — the blocker on letting teachers near
      the web build at all.
- [ ] **R10.5** RevenueCat Web Billing. Today `billing_service` tells web users
      "Plans are bought in the phone app", so a teacher on the website cannot pay.
      Worth doing: it is a purchase path that does not depend on Play review
      landing by Sep 30, it satisfies Shipaton's "in-app **or web** purchase" on its
      own, it opens the Funnel Vision (Stripe) category, and since Google's
      2026-06-30 change a web checkout costs 10% rather than Play Billing's 15%.

---

## R11 — Redaction honesty (done 2026-08-30)

- [x] **R11.1** `AnonymizedPage.redacted` actually reaches the teacher — before the
      upload and again on the pilot screen. Nothing read it before.
- [x] **R11.2** Settings toggle no longer reads as ON-and-working in a browser.
- [x] **R11.3** One-per-teacher acknowledgement before any browser upload of student
      work, covering the stack splitter as well as the three pick routes.
- [x] **R11.4** `docs/security-and-compliance.md` corrected: redaction claims scoped
      to iOS/Android, new §3.1 on what differs in a browser.

---

## R12 — Play compliance (found 2026-08-30)

- [x] **R12.1** In-app account deletion — already existed and works.
- [x] **R12.2** Public account-deletion page at `docs/delete-account.html`. Play
      REJECTS new submissions from apps allowing account creation without a URL that
      is reachable without login and links directly to deletion. A section inside
      the privacy policy does not satisfy it.
- [ ] **R12.3** Decide two numbers, then fill them into BOTH the page and the Play
      Data Safety form — they are the same values and neither exists anywhere yet:
      the retention period for the anonymous marking cache, and the turnaround for
      an emailed deletion request. Do not invent them at form-filling time.
- [ ] **R12.4** Switch GitHub Pages on (Settings → Pages → main / /docs) so all three
      URLs resolve. Play needs the privacy and deletion URLs live before submission.
- [ ] **R12.5** Store cut: Play Billing is 10% (first $1M) + 5% = 15%, which is what
      the caps assume — note it now comes from the under-$1M rate, NOT the Small
      Business Program. Web checkout is 10%. Linking out from the app stopped being
      prohibited on 2026-06-30 in US/UK/EEA.

---

## R13 — Robustness pass (2026-08-30)

Done:
- [x] **R13.1** Timeouts on all 25 `functions.invoke` sites (there were none). Slow
      default of 4 min; a timeout becomes a retryable tray job, not a lost paper.
- [x] **R13.2** Marking concurrency capped at 3 (was: all 29 at once from one phone).
- [x] **R13.3** `enqueueBatch` puts the whole set in the tray BEFORE awaiting the
      pilot. Previously a hung pilot left 29 papers as local variables in a
      suspended function — unreachable by any amount of persistence.
- [x] **R13.4** Overnight: per-paper filing + `filedIds` persisted after each paper
      (gradebook was getting duplicates); failed/expired papers kept and named
      instead of silently dropped; failed submit no longer discards held papers;
      page paths stored relative (iOS moves Documents on app update).
- [x] **R13.5** Gallery bulk pick: capped at 60, real progress, Stop button, one bad
      photo no longer discards the pick.
- [x] **R13.6** Paid double-taps closed: Scan Attendance (also fixed roster
      duplication — 30 students became 60), Scan Key.
- [x] **R13.7** `runWithBlockingProgress` — back button no longer dismisses a
      progress dialog and makes the completion pop take the screen underneath.
- [x] **R13.8** Deleted `image_preview_screen` — dead prototype on a LIVE root route
      that assigned `Random().nextInt(students)` as the detected student.

Still open:
- [ ] **R13.9** **Money leak.** `batch_submit` runs `budgetGate` but writes NO
      `usage_log` row — billing happens only on the first poll that sees `ended`
      (index.ts:1953). A teacher who queues an overnight batch and never reopens
      the app means Anthropic bills you and `usage_log` records nothing: invisible
      to the credit meter AND the monthly cap. Fixed by R13.10.
- [ ] **R13.10** **Scheduled sweeper (server).** pg_cron ~15 min, SEPARATE from
      MARKING-PROCESS: select `marking_batches` where `status <> 'ended'` and
      `created_at > now() - 29 days`; retrieve from Anthropic; skip unless
      `processing_status = 'ended'`; bill via
      `UPDATE ... WHERE batch_id = $1 AND status <> 'ended'` and only log usage if
      1 row changed (this also closes a TOCTOU race where two devices polling
      concurrently both bill); then POST OneSignal with
      `include_aliases.external_id`. This is what makes "you can close the app"
      true, what makes push fire at all, and what stops R13.9.
- [ ] **R13.11** `list_batches` action so a reinstall or a new phone can recover a
      night's marking. Today batches are device-local: the row and the Anthropic
      results both still exist but no client can reach them.
- [ ] **R13.12** The home screen says overnight results "land on your dashboard when
      they finish". Until R13.10 they land when the teacher next OPENS the app.
      Either ship R13.10 or reword it.
- [ ] **R13.13** Still-indeterminate progress for countable work: Drive import, and
      "Saving results…" during the CSV import's 30x3 sequential writes.
- [ ] **R13.14** CSV import has no checkpoint — re-running double-charges and
      creates a second submission per student (student dedupe exists; submission
      dedupe does not).
- [ ] **R13.15** `submissions_service._persist()` re-encodes the ENTIRE submission
      history to SharedPreferences on every single mark, on the UI isolate.

---

## R14 — Server-side authorization (found 2026-08-30, PRE-EXISTING)

`MARKING-PROCESS` read actions take `teacherId` from the request body and trust
it. The anon key ships in the APK — the code says so itself — so a `teacherId`
in the payload is a request, not an identity. Anyone holding that key can read
another teacher's rows by passing their id.

`delete_account` already does this correctly, and `list_batches` (added
2026-08-30) was made to match it:

```ts
const claims = jwtClaims(req.headers.get("authorization"));
if (claims?.role !== "authenticated" || String(claims?.sub ?? "") !== teacherId) {
  return json({ error: "..." }, 403);
}
```

- [x] **R14.1** DONE 2026-09-08, wider than planned: ALL 24 teacherId actions
      guarded (reads, writes, billed), deployed, spoof-probed 403 in prod.
      Originally: apply to the remaining read actions. In rough order of
      what they expose: `list_submissions` (marked student work), `get_profile`
      (name, school, email), `list_keys`, `get_collection`, `get_usage`,
      `get_referral`.
- [ ] **R14.2** These need a matching client check — the app already sends the
      Supabase session JWT, so signed-in teachers should be unaffected, but any
      path that calls these WITHOUT a real session (local-only / dev accounts)
      will start getting 403s. Test that before deploying.
- [ ] **R14.3** Worth doing before real teachers with real children's work are on
      it, not after. This is a data-exposure issue, not a hardening nicety.

Also noted while type-checking with `deno check`:
- [ ] **R14.4** `MARKING-PROCESS` has one pre-existing `TS7006` (implicit `any`,
      the `normalized.annotations.map((a) => ...)` call). Deploys fine today;
      left alone deliberately rather than touching the marking path mid-release.

---

## R15 — Feature roadmap (drafted 2026-08-30)

Ranked within each axis by value against effort. In progress this session:
corrections-train-the-preset (better), drag-drop + paste intake (faster).

### Mark BETTER

- [ ] **R15.1 Cross-paper consistency check.** After a class set, flag any two
      papers whose answers to the same question are near-identical but scored
      differently. This is the single biggest trust objection to AI marking —
      "would it mark my two students the same?" — and answering it in the
      product is worth more than any accuracy claim. Nearly free: `class_analysis.dart`
      already aggregates per-question results across a batch, so this is a
      comparison over data on disk, no new marking call. **Best value on this list.**
- [ ] **R15.2 Second opinion, only where it is unsure.** The marker already
      emits confidence/triage flags. Re-mark ONLY the flagged answers with a
      stronger model. Accuracy goes up exactly where it is weak, and the cost is
      a few percent of a class set rather than double.
- [ ] **R15.3 Exemplar-anchored marking.** Teacher marks one answer by hand, or
      tags one as "this is a 4/5", and that anchors the scale for the set.
      Models drift most on essays and open responses; an anchor is the cheapest
      known fix. Extends the pilot-paper flow that already exists.
- [ ] **R15.4 Rubric upload.** Teacher's own rubric document becomes preset
      rules. Most-requested feature in this category, and presets are already
      the right home for it.

### Mark FASTER

- [ ] **R15.5 QR code on printed papers.** `test_stamper.dart` already prints
      identity onto pre-coded copies. A scannable code makes stack splitting and
      student identification exact instead of inferred — it removes name matching,
      the mis-split recovery flow, and the two-Anas problem in one step. ~80% of
      the machinery exists.
- [ ] **R15.6 Share sheet / "Open with Markless".** Receive work from Drive,
      email or Photos via the OS share sheet. Needs `android/` + `ios/` config,
      so it is its own piece of work, but it matches how teachers actually
      receive student work.
- [ ] **R15.7 Reuse an assessment.** A preset + answer key as one reusable
      thing, re-run next term or next year without rebuilding it.

### Mark CHEAPER

- [ ] **R15.8 The two-stage router.** Already the plan of record (see
      [[markless-pricing]]): cheap vision parse, then grading routed by question
      type — objective to a cheap tier, reasoning to mid, essays to Sonnet, with
      low-confidence escalation. Pricing already assumes ~$0.015/mark and
      Sonnet-only runs $0.02-0.04. Blocked only on API keys that do not exist yet.
- [ ] **R15.9 Objective questions should never reach an LLM.** Multiple choice
      matched against the key locally is free. A MC-only quiz should cost
      essentially nothing to mark, which makes the Starter tier much better
      business and is a real marketing line.
- [ ] **R15.10 Re-mark only what changed.** Re-running a paper today re-buys
      every question. Only changed answers need re-marking.

### Different ways to ADD work

- [ ] **R15.11 Student self-submit link.** Teacher shares a link; students upload
      their own work straight into the class. Removes the entire collection step
      — the slowest part of the whole workflow — and every student who opens it
      sees Markless, which is a real growth loop rather than a bolted-on referral.
      Pairs with the web app now that it is a proper product.
- [ ] **R15.12 Google Classroom import.** Pull assignments and submissions
      directly. Biggest workflow unlock available; also the biggest effort
      (OAuth scopes, review). Worth planning once the store release is done.
- [ ] **R15.13 Email-in address.** Forward work to a per-teacher address and it
      appears in the queue. Infra-heavy; listed for completeness.

**If only three get built: R15.1, R15.9, R15.11** — trust, margin, and
distribution, in that order.

---

## R16 — Drag/paste intake: what is verified and what is not (2026-08-30)

Verified in a real Chrome against a debug web build:
- Listeners attach; `types.contains('Files')` detection works.
- The "Drop the pages here" overlay appears on dragenter and clears on drop.
- `preventDefault` fires on dragover AND drop, so the browser will not navigate
  away to the dropped file.
- The affordance line renders on the grading screen.
- 12 unit tests cover the pure logic: filtering, mapping to `PickedPhoto`, the
  60-file cap, paste naming, and PDF page grouping.

- [ ] **R16.1 NOT verified: the last hop.** A synthetic `DragEvent` carrying a
      real `File` reaches the handler (overlay reacts, preventDefault fires) but
      **no acknowledgement dialog appears and nothing enters the pipeline.** A
      plain JS listener on the identical event does see `files.length === 1`, so
      the event is well-formed. The break is somewhere between
      `e.dataTransfer.files` in the Dart drop handler and `onDropped`.
      Note `_readAll` swallows per-file read errors by design, so a FileReader
      failure would look exactly like this — silently nothing.
      **Test with a real OS drag before trusting this feature.** It may well be
      an artifact of synthetic events, which cannot be assumed either way.
- [ ] **R16.2** Paste is untested end to end for the same reason.

---

## R17 — Scaling test findings (2026-09-08, `tool/load_test.mjs`)

Ramped 1 → 5 → 10 → 25 → 50 concurrent simulated teachers against the LIVE
backend (sign-up, two classes, 30 students, links, three saved marked papers,
reads). 1,001 DB requests, **zero failures**; throughput scaled cleanly to
~32 req/s. Then 10 CONCURRENT real `mark_responses` calls: all succeeded,
p50 2.6s. Whole test's AI cost, confirmed via admin_stats: **$0.0011**.

- [x] **R17.1** `profiles.referred_by` had no index, and `paidReferralCount`
      (called by `get_usage` on every app open) seq-scans on it. Added a partial
      index to SETUP-DB — **re-run SETUP-DB to apply it**.
- [ ] **R17.2** `get_usage` is the scaling bottleneck: p50 2.8s / p95 10.3s /
      max 11.2s at 50 teachers, while every other action held p95 ≤ 1.7s. Cause:
      ~6 DB round trips per call — `planFor`, THREE separate `spendSince`
      queries that fetch every usage_log row and sum in JS, and the seq-scan
      count. Fix when next touching MARKING-PROCESS: one SQL aggregate
      (`sum(cost_usd) filter (where created_at > ...)` × day/week/month in a
      single query) instead of three row-fetches, and R17.1's index. This is a
      real morning-rush problem: get_usage runs on app open AND before marking
      choices.
- [ ] **R17.3** **The free-tier Supabase project PAUSES after ~7 days idle.**
      The first smoke run hit a woken-from-pause project: every table came back
      "Could not find the table in the schema cache" for about a minute, then
      recovered. The first teacher after a quiet week gets a broken app.
      Before launch: upgrade the project (or accept and add retry/backoff on
      cold start). This WILL fire during Shipaton judging if judges try the app
      after a quiet spell.
- [ ] **R17.4** Deployed MARKING-PROCESS is the pre-2026-08-30 build: no
      `list_batches`, no IDOR guard (probe returns 400 fall-through, not 403),
      no sweeper. The repo is ~2 weeks ahead of production. Deploy.
- [ ] **R17.5** Cleanup: the test left `loadtest-*` rows. SQL to remove them is
      printed by `tool/load_test.mjs` (delete from submissions_cloud /
      collections_cloud / usage_log / profiles where teacher_id like 'loadtest-%').

---

## R18 — Full performance battery (2026-09-08, `tool/load_test.mjs` modes)

Run against the LIVE deployment (pre-R17 fixes — the get_usage rewrite and
referred_by index were written and committed but the deploy was blocked
pending owner approval, so these numbers are the "before" baseline).

| Test | Result |
|---|---|
| **Load (target 500)** | FAIL at 500. Healthy to ~200 (0-0.6% errors); 250 = 5.4% errors and first BOOT_ERRORs; 500 = 45% errors, get_usage 498/500 timeouts, Cloudflare interstitials. |
| **Stress (ceiling)** | Knee between 250 and 500 concurrent full sessions. Break mode is COLLAPSE, not graceful: throughput plateaus ~31 req/s from 100 up, then goes retrograde (24 req/s at 500) as timeouts cascade. |
| **Spike (50→500)** | Failure is immediate on the jump — BOOT_ERROR (edge autoscale lag), "upstream connect error / connection timeout" (pool exhaustion), 41% errors. Scaled down from the requested 2,000 because steady-state already collapses at 500; a 2k spike would only prove the same thing for 26k invocations. |
| **Soak (4h, 3 VUs)** | Running in background → `tool/soak_results.log`, drift table at the end. |
| **Volume** | PASS. 3,000 papers on one account + a 5,000-student roster: list_submissions p95 670ms vs 582ms on a 1-row account — no degradation; seeding sustained 50-concurrent writes flawlessly. (5M rows is dishonest against a 500MB free-tier DB; this is the worst realistic single account.) Note: a full list_submissions page ≈ 4MB — paginate for mobile data someday. |
| **Scalability** | NOT horizontally scalable on this tier. Throughput is pinned at ~31 req/s regardless of offered load — a fixed shared ceiling (free-tier DB pool + edge concurrency), confirmed by BOOT_ERRORs and upstream connect resets. More client load cannot raise it; only (a) the R17.2 query-count fix (~3× fewer DB round trips on the hottest path) and (b) a paid tier can. |

- [ ] **R18.1** Deploy the R17 fixes, re-run `--mode ramp --stages 100,250,500`,
      and record the after numbers. Expect the knee to move right substantially.
- [ ] **R18.2** "One concurrent full session" ≈ several real teachers (real users
      idle between taps). Rough translation: today's ceiling ≈ low thousands of
      teachers active in the same minute — fine for launch, nowhere near a press
      hit. Decide the paid-tier trigger BEFORE any launch push.
- [ ] **R18.3** Transient `save_profile` 500 "JWT issued at future" seen once at
      100 VUs — edge node clock skew. The client should treat it as retryable.
- [ ] **R18.4** Battery used ~45k of the 500k monthly free edge invocations.

---

## R19 — Getting to thousands of users (2026-09-08)

Shipped and DEPLOYED today (owner authorized): the spendBuckets single-query
rewrite, the referred_by index (SETUP-DB re-run), in-isolate 60s caches for
plan + referral lookups and a 30s display-only cache for get_usage's sums
(budgetGate always sums fresh — the gate is the margin guarantee and is
deliberately uncached), the list_batches IDOR guard (verified 403 in prod).

After-numbers: get_usage at 250 users went 12% timeouts → ZERO failures, p50
15.7s → 7.3s; overall errors at 250: 5.4% → 3.8%. **The ceiling did not
move**: throughput still pins ~33-35 req/s and 500 still collapses. The
ceiling is the free tier's pool + compute, not any query.

- [ ] **R19.1 Upgrade to Supabase Pro ($25/mo). This is THE unlock** — bigger
      pool, more compute, no 7-day pause (kills R17.3), and the margin model
      absorbs it trivially. Owner action; dashboard billing. Re-run the ramp
      after and record the new ceiling.
- [ ] **R19.2** Client resilience (in progress): retry+backoff on transient
      failures for FREE actions only — billed actions never auto-retry, a
      timed-out grade may have billed and a retry would buy it twice — plus a
      45s client cache for get_usage.
- [x] **R19.3** DONE 2026-09-08 (bootstrap_sync, deployed; client falls back on old servers). Next code multiplier once on Pro: a batched `bootstrap_sync`
      action returning profile+usage+keys+collections in ONE invocation.
      App-open cost drops ~5 invocations → 1; at any tier that multiplies the
      user ceiling by the same factor.
- [ ] **R19.4** Keep-warm ping until Pro (Pages/cron hitting get_usage every
      few days) so the first teacher after a quiet week doesn't wake a paused
      project — or just do R19.1, which makes it moot.

### R14/R19.3 deployment notes (2026-09-08)
- Live spoof probes after deploy: get_usage / list_submissions / save_collection /
  mark_responses with a foreign teacherId → all 403.
- POSITIVE path not live-verified from here (signup needs email confirmation, so
  no mintable JWT): **owner smoke test — open the app, mark something, confirm
  cloud sync works — BEFORE making the repo public.** 455 client tests + the
  call-site audit cover it, but the phone is the proof.
- A pending unconfirmed auth user `markless.loadtest.r14@gmail.com` was created
  by the probe attempt; delete in Dashboard → Auth when convenient.
- SOAK remains the one battery item not completed: killed twice by same-day
  deploys (its fleet mode is also now walled off by R14, correctly). Re-run
  post-launch as one signed-in user: `node tool/load_test.mjs --mode soak
  --minutes 240 --vus 3 --jwt <access token>`.

---

## R20 — Web app is BUILT and committed (2026-09-21)

`docs/app/` now exists: release build, keys baked in, base href
`/ai-marking-dreamflow/app/`. Built with `tool/build_web.ps1` after setting
`$env:SUPABASE_ANON_KEY` (note: the script calls `pwsh`, which is not
installed here — run it via `powershell -ExecutionPolicy Bypass -File`).

Verified in a browser at the exact Pages path: boots to login, splash tears
down, zero console errors, dev backdoor absent from the shipped bundle
(grep = 0), and **pdf.js renders a real 2-page PDF** (918x1188, ink on
canvas, text extracted) from the local worker — document upload's hardest
dependency, proven not assumed.

- [ ] **R20.1 THE BLOCKER: the Supabase project is PAUSED.** `status:
      INACTIVE`; its subdomain does not resolve from any DNS (local or
      8.8.8.8); `api-keys` returns an empty list. This is R17.3 arriving
      exactly as predicted — ~13 days idle since the 2026-09-08 session.
      **Only the dashboard's Restore button fixes it** (no CLI subcommand).
      Until then NOTHING that touches the backend works: sign-in, marking,
      sync. **Restore it, then do R19.1 (Pro, $25/mo) so it cannot recur —
      a paused project during judging reads as a broken app.**
- [ ] **R20.2** Not verifiable while paused — the signed-in half of the web
      flow: photo upload → mark → result, and a PDF stack through
      split_stack. The client-side halves are covered by tests
      (bulk_page_processor, dropped_intake, web_upload_gate) and pdf.js is
      proven above. After restoring, walk it once in a browser.
- [ ] **R20.3** Dev-mode sign-in does not complete when the backend is
      unreachable: `_devMode()` awaits profile saves inside its try, so a
      network throw skips the `context.go`. Debug-only, but it is why this
      session could not test the signed-in flows offline. One-line fix:
      move the navigation out of the failure path.
- [ ] **R20.4** Each rebuild commits ~45MB (37MB of it canvaskit's five
      runtime variants). Fine for the hackathon; if the repo gets heavy,
      move the build to a GitHub Action publishing to a `gh-pages` branch.
- [ ] **R20.5** Turn Pages on (Settings → Pages → `main` / `/docs`) and make
      the repo public. Then the three URLs and the app are live together.
