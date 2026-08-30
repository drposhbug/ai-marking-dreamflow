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
- [ ] **R4.3** App icon, app name, and version code/name finalized in pubspec + manifest.
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

- [ ] **R7.1** OneSignal Flutter SDK added; Android notification permission requested at
      the right moment (after the first batch is queued, not on first launch).
- [ ] **R7.2** External user id set to the teacher id, matching `Purchases.logIn` so
      RevenueCat and OneSignal address the same person.
- [ ] **R7.3** "Your class set is marked" — fired server-side from the overnight batch
      completion path, deep-linking straight to the results.
- [ ] **R7.4** Trial-ending and approaching-mark-cap nudges. These are the upgrade
      triggers, so they feed the HAMM story as well as retention.
- [ ] **R7.5** Weekly "you saved about N hours this week" summary — the re-engagement
      hook that is actually worth receiving.
- [ ] **R7.6** Every notification respects a Settings toggle, and none fire for a teacher
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
- [ ] **R9.2** Settings "Giving" row: dollars generated to date, derived from real
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
