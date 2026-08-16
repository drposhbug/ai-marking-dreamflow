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
- [ ] **R4.4** Privacy policy drafted and hosted at a public URL.
- [ ] **R4.5** Store listing copy — title, short description, full description.
- [ ] **R4.6** Screenshots and feature graphic produced.

**Manual on Play Console (do myself):**
- [ ] **R4.7** Store listing filled in and assets uploaded.
- [ ] **R4.8** App content declarations completed (data safety, content rating, target
      audience, ads declaration).
- [ ] **R4.9** AAB uploaded to the closed testing track.
- [ ] **R4.10** 12 testers recruited and opted in.
- [ ] **R4.11** 14-day continuous closed test run to completion.
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
