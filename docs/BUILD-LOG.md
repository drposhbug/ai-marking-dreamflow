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

- [`c5b09a4`](https://github.com/drposhbug/ai-marking-dreamflow/commit/c5b09a4) — the first Supabase edge function that does the marking
- [`2825ecb`](https://github.com/drposhbug/ai-marking-dreamflow/commit/2825ecb) — multi-page scanning, answer keys stored in the cloud, and the first grading overhaul
- [`11ca1a0`](https://github.com/drposhbug/ai-marking-dreamflow/commit/11ca1a0) — real sign-in, page straightening, and curriculum expectations by grade

## 2. Make it cheap enough to sell (early August)

A marking app that loses money on every paper can't be a business, so pricing
and cost shaped the architecture from here on.

- [`a6651bc`](https://github.com/drposhbug/ai-marking-dreamflow/commit/a6651bc) — hard spend caps, a usage meter and an upgrade sheet
- [`882e149`](https://github.com/drposhbug/ai-marking-dreamflow/commit/882e149) — the objective marking router: Gemini reads the page, a cheap text model marks against the key, Claude as fallback
- [`743dadf`](https://github.com/drposhbug/ai-marking-dreamflow/commit/743dadf) — **learned keys**: the first keyless paper's answers become the key the rest of the class is marked against
- [`d2e4b19`](https://github.com/drposhbug/ai-marking-dreamflow/commit/d2e4b19) — RevenueCat SDK added
- [`a0d75a1`](https://github.com/drposhbug/ai-marking-dreamflow/commit/a0d75a1) — error highlights snapped onto the real words with on-device text recognition

## 3. Close the launch blockers (mid August)

- [`f77679e`](https://github.com/drposhbug/ai-marking-dreamflow/commit/f77679e) — release signing, account deletion, and **plan spoofing**: the plan can no longer be set by the client, only by the RevenueCat webhook
- [`670e527`](https://github.com/drposhbug/ai-marking-dreamflow/commit/670e527) — a real Plans section

## 4. The four ways to mark (late August)

Most teachers reached for the camera, which is the slowest route. This phase
built the faster ones and put all four on the home screen.

- [`610c03d`](https://github.com/drposhbug/ai-marking-dreamflow/commit/610c03d) — import a Google Form / CSV and mark the whole class at once (~2 min)
- [`8be2cbe`](https://github.com/drposhbug/ai-marking-dreamflow/commit/8be2cbe) — split one photocopier scan back into one paper per student
- [`082b9ff`](https://github.com/drposhbug/ai-marking-dreamflow/commit/082b9ff) — print a per-copy code on every page, so a scanned stack sorts itself
- [`0f89502`](https://github.com/drposhbug/ai-marking-dreamflow/commit/0f89502) — the four ways to mark on the home screen, with the steps behind them
- [`da98d59`](https://github.com/drposhbug/ai-marking-dreamflow/commit/da98d59) — the pilot paper: check the first result before marking the other twenty-nine
- [`076a6f7`](https://github.com/drposhbug/ai-marking-dreamflow/commit/076a6f7) — overnight marking through the Batches API, about five times cheaper per paper

## 5. Privacy and money rules (late August)

- [`34dd5ec`](https://github.com/drposhbug/ai-marking-dreamflow/commit/34dd5ec) — student names are redacted on the device and never sent to the AI
- [`5eb8afb`](https://github.com/drposhbug/ai-marking-dreamflow/commit/5eb8afb) — **the margin rule**: every plan's AI cap is derived from its price so no subscription can lose money
- [`93224b8`](https://github.com/drposhbug/ai-marking-dreamflow/commit/93224b8) / [`2a395e7`](https://github.com/drposhbug/ai-marking-dreamflow/commit/2a395e7) — the wrong-mark bug: two students with the same name, accents, and refusing to guess
- [`0bdfce5`](https://github.com/drposhbug/ai-marking-dreamflow/commit/0bdfce5) — class item analysis: what the whole class got wrong, not just each student
- [`7500a27`](https://github.com/drposhbug/ai-marking-dreamflow/commit/7500a27) — removed a live route that could put a random student's name on a paper

## 6. Hold up under load (September 8)

- [`d6e4796`](https://github.com/drposhbug/ai-marking-dreamflow/commit/d6e4796) — simulated fifty teachers arriving at once, and wrote down what broke
- [`0ab859b`](https://github.com/drposhbug/ai-marking-dreamflow/commit/0ab859b) — every one of the twenty-four backend actions now checks who is asking

## 7. The web app and one subscription (September 21–26)

- [`f3b46ed`](https://github.com/drposhbug/ai-marking-dreamflow/commit/f3b46ed) — the Flutter app built for the web
- [`d04caec`](https://github.com/drposhbug/ai-marking-dreamflow/commit/d04caec) — buying a plan in a browser through Stripe Checkout
- [`3243720`](https://github.com/drposhbug/ai-marking-dreamflow/commit/3243720) — phone and web purchases merged into one subscription per teacher
- [`f670179`](https://github.com/drposhbug/ai-marking-dreamflow/commit/f670179) — rebrand to UMarkless; the site moves to umarkless.com

## 8. Submission week (September 29–30)

- [`9785389`](https://github.com/drposhbug/ai-marking-dreamflow/commit/9785389) — marking on Claude Sonnet 5.5, with the most thinking spent where the class key is solved
- [`991b5b6`](https://github.com/drposhbug/ai-marking-dreamflow/commit/991b5b6) — RevenueCat Test Store ready; free-trial teachers see an upgrade prompt (no ad network)
- [`ccbd5be`](https://github.com/drposhbug/ai-marking-dreamflow/commit/ccbd5be) — README brought up to date with the code

---

For what is finished and what isn't, see [Status](../README.md#status) in the
README. The working checklist is `REMAINING.md`.
