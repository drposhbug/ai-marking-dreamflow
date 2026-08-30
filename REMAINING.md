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
- [x] **R7.3** "Your class set is marked" — fired server-side from the overnight batch
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
