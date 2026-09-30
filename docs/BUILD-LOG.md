# How UMarkless was built

A guided tour of the commit history, for anyone who wants to follow the project
from the first scan to the submission build. There are about 220 commits; these
are the ones that changed the product's direction, grouped into phases. Each
link opens the commit on GitHub.

Commit messages from August on are written as the change a teacher would
notice ("Check the first paper before marking the other twenty-nine"), so the
full log (`git log --reverse`) also reads as a story.

---

## 1. Can a model mark a scanned page at all? (late June – July)

The first month was a prototype: scan a page, send it to a vision model, get
marks back.

- [`41d2fd3`](https://github.com/drposhbug/ai-marking-dreamflow/commit/41d2fd3) — the first Supabase edge function that does the marking
- [`fb3e397`](https://github.com/drposhbug/ai-marking-dreamflow/commit/fb3e397) — multi-page scanning, answer keys stored in the cloud, and the first grading overhaul
- [`de0288b`](https://github.com/drposhbug/ai-marking-dreamflow/commit/de0288b) — real sign-in, page straightening, and curriculum expectations by grade

## 2. Make it cheap enough to sell (early August)

A marking app that loses money on every paper can't be a business, so pricing
and cost shaped the architecture from here on.

- [`23a2b8a`](https://github.com/drposhbug/ai-marking-dreamflow/commit/23a2b8a) — hard spend caps, a usage meter and an upgrade sheet
- [`a5d83aa`](https://github.com/drposhbug/ai-marking-dreamflow/commit/a5d83aa) — the objective marking router: Gemini reads the page, a cheap text model marks against the key, Claude as fallback
- [`8e852dc`](https://github.com/drposhbug/ai-marking-dreamflow/commit/8e852dc) — **learned keys**: the first keyless paper's answers become the key the rest of the class is marked against
- [`87d94e8`](https://github.com/drposhbug/ai-marking-dreamflow/commit/87d94e8) — RevenueCat SDK added
- [`c04f667`](https://github.com/drposhbug/ai-marking-dreamflow/commit/c04f667) — error highlights snapped onto the real words with on-device text recognition

## 3. Close the launch blockers (mid August)

- [`98e812b`](https://github.com/drposhbug/ai-marking-dreamflow/commit/98e812b) — release signing, account deletion, and **plan spoofing**: the plan can no longer be set by the client, only by the RevenueCat webhook
- [`bd324dd`](https://github.com/drposhbug/ai-marking-dreamflow/commit/bd324dd) — a real Plans section

## 4. The four ways to mark (late August)

Most teachers reached for the camera, which is the slowest route. This phase
built the faster ones and put all four on the home screen.

- [`054b0dd`](https://github.com/drposhbug/ai-marking-dreamflow/commit/054b0dd) — import a Google Form / CSV and mark the whole class at once (~2 min)
- [`582acdc`](https://github.com/drposhbug/ai-marking-dreamflow/commit/582acdc) — split one photocopier scan back into one paper per student
- [`775c927`](https://github.com/drposhbug/ai-marking-dreamflow/commit/775c927) — print a per-copy code on every page, so a scanned stack sorts itself
- [`d7d2efb`](https://github.com/drposhbug/ai-marking-dreamflow/commit/d7d2efb) — the four ways to mark on the home screen, with the steps behind them
- [`320c1fa`](https://github.com/drposhbug/ai-marking-dreamflow/commit/320c1fa) — the pilot paper: check the first result before marking the other twenty-nine
- [`4f412a4`](https://github.com/drposhbug/ai-marking-dreamflow/commit/4f412a4) — overnight marking through the Batches API, about five times cheaper per paper

## 5. Privacy and money rules (late August)

- [`b9882dc`](https://github.com/drposhbug/ai-marking-dreamflow/commit/b9882dc) — student names are redacted on the device and never sent to the AI
- [`debffc1`](https://github.com/drposhbug/ai-marking-dreamflow/commit/debffc1) — **the margin rule**: every plan's AI cap is derived from its price so no subscription can lose money
- [`76d120a`](https://github.com/drposhbug/ai-marking-dreamflow/commit/76d120a) / [`e240a04`](https://github.com/drposhbug/ai-marking-dreamflow/commit/e240a04) — the wrong-mark bug: two students with the same name, accents, and refusing to guess
- [`f8f5835`](https://github.com/drposhbug/ai-marking-dreamflow/commit/f8f5835) — class item analysis: what the whole class got wrong, not just each student
- [`9789856`](https://github.com/drposhbug/ai-marking-dreamflow/commit/9789856) — removed a live route that could put a random student's name on a paper

## 6. Hold up under load (September 8)

- [`136bee4`](https://github.com/drposhbug/ai-marking-dreamflow/commit/136bee4) — simulated fifty teachers arriving at once, and wrote down what broke
- [`90c7db6`](https://github.com/drposhbug/ai-marking-dreamflow/commit/90c7db6) — every one of the twenty-four backend actions now checks who is asking

## 7. The web app and one subscription (September 21–26)

- [`9edfee1`](https://github.com/drposhbug/ai-marking-dreamflow/commit/9edfee1) — the Flutter app built for the web
- [`8299162`](https://github.com/drposhbug/ai-marking-dreamflow/commit/8299162) — buying a plan in a browser through Stripe Checkout
- [`6446689`](https://github.com/drposhbug/ai-marking-dreamflow/commit/6446689) — phone and web purchases merged into one subscription per teacher
- [`80d949e`](https://github.com/drposhbug/ai-marking-dreamflow/commit/80d949e) — rebrand to UMarkless; the site moves to umarkless.com

## 8. Submission week (September 29–30)

- [`00a0d63`](https://github.com/drposhbug/ai-marking-dreamflow/commit/00a0d63) — marking on Claude Sonnet 5.5, with the most thinking spent where the class key is solved
- [`70896ed`](https://github.com/drposhbug/ai-marking-dreamflow/commit/70896ed) — RevenueCat Test Store ready; free-trial teachers see an upgrade prompt (no ad network)
- [`f07e348`](https://github.com/drposhbug/ai-marking-dreamflow/commit/f07e348) — README brought up to date with the code

---

For what is finished and what isn't, see [Status](../README.md#status) in the
README. The working checklist is `REMAINING.md`.
