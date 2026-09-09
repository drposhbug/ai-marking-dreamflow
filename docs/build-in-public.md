# Build-in-public kit — RevenueCat Shipaton 2026

The #BuildInPublic award ($30k first place) judges three things, per the rules:
**how often you share, how you engage with people who reply, and whether the
app visibly improved because of feedback.** It rewards the messy middle, not
polish. Every draft below is a real artifact from this repo's history — nothing
is invented, no metrics are made up, and that is the voice: the same honesty
the app itself uses.

## One-time setup (15 minutes, today)

- [ ] X account (personal is fine — judges follow people, not logos). Bio line:
      `Building Markless — an AI marking assistant for teachers. Mark less,
      teach more. Shipping in public for @RevenueCat's #Shipaton.`
- [ ] Check the Shipaton page/Discord for the required hashtag or tagging
      convention (the submission doc has a TODO for this — some years it is
      #Shipaton2026 + tagging @RevenueCat). Use it on EVERY post.
- [ ] Pin your first post (draft 1 below).
- [ ] Follow and turn on notifications for @RevenueCat and 10–20 accounts
      posting under the hashtag. Reply to two of them today — engagement is a
      judged criterion, not garnish.

## Voice rules (match the product)

Plain sentences. Real numbers or no numbers. Say what broke. No "🚀 excited to
announce", no "game-changer", no invented stats — if a judge checks a claim,
it must hold. Screenshots and graphs beat adjectives.

## Cadence

3–5 posts/week through Sep 30. Batch drafts Sunday, post live on real events
(a deploy, a bug, a review verdict). 15 min/day replying — comments count.

---

## Ready-to-post drafts (in rough order)

Each has a suggested visual you can screenshot in two minutes.

**1 — the pin.** (post today)
> Teachers mark a class set at 9pm after planning all evening. I'm building
> Markless so the marking is done before they sit down: photograph the stack,
> get question-by-question marks with a written reason for every deduction,
> override anything. Building it in public for @RevenueCat's #Shipaton. 0
> users, 22 days to launch. Follow along.
Visual: the landing page hero, or the marked-paper illustration.

**2 — the load test collapse.** (strongest engineering post; thread)
> I load-tested my app before launch. 100 concurrent teachers: fine. 250:
> wobbling. 500: total collapse — 45% errors, my usage endpoint timing out
> 498 times out of 500.
>
> The culprit: one endpoint making SIX database round trips per call, three
> of them fetching every row to sum in JavaScript.
>
> Fixed it to one query. Re-ran: 12% timeouts → zero. And the ceiling didn't
> move, because the ceiling was never the query — it's the free tier's
> connection pool. Some limits are code. Some are $25/month.
Visual: the before/after stage tables from REMAINING.md R18/R19.

**3 — the backdoor.**
> Found a "Developer mode — skip sign-in" button sitting on my login screen
> in RELEASE builds. No debug gate, nothing. Anyone could walk past sign-up.
> I only caught it by actually loading the production build in a browser
> instead of reading the code. Test the artifact you ship, not the code you
> wrote.
Visual: the old login screenshot with the dev-mode line visible.

**4 — the paywall lie (git archaeology).**
> My paywall promised Starter users "40 papers marked on the spot." The
> server has refused instant marking for Starter since August — deliberately,
> per a commit message I wrote and forgot. The copy was stale, not the code.
> A $6.99 subscriber would have been promised a feature and refused it.
> Audit your paywall against your server, not your memory.
Visual: the commit message of 8ca775e next to the old tier card.

**5 — corrections that teach the marker.**
> New feature: if a teacher overrides the same thing on 3 different papers —
> not 3 questions on one weird paper, 3 papers — Markless asks: "want me to
> mark it your way from now on?" Shows the exact rule in an editable box.
> Never silent, capped at 8 rules per scheme, two "no"s mutes it forever.
> An AI marker that quietly changes how it marks is exactly what teachers
> should distrust.
Visual: the offer dialog.

**6 — the billing leak.**
> Found a money leak in my own backend: overnight marking batches only got
> billed when the client polled for results. Teacher never reopens the app →
> Anthropic bills me, my spend meter records nothing. Wrote a sweeper that
> settles batches server-side — and bills on a conditional UPDATE so two
> concurrent pollers can't both charge. Exactly-once billing is a WHERE clause.
Visual: the sweeper's conditional-update snippet.

**7 — the redesign.** (before/after does the work)
> Redesigned the site out of startup-blue. The palette is now a teacher's
> desk: exam-booklet paper, print ink, chalkboard green — and the red pen
> demoted to what red pens do: deductions. One rule I love: red never writes
> on the board. A pen doesn't write on slate, so on green the accent switches
> to yellow chalk.
Visual: old hero vs new hero, side by side.

**8 — quarter marks.**
> Real teachers give 3¾ out of 5. Most marking software thinks in integers.
> Markless marks in quarters because that's how marking actually works — and
> the model must write a reason for every deduction, so 3¾ comes with "right
> method, arithmetic slip in the last line."
Visual: the marked-paper card with 3¾ and the red note.

**9 — one paper, not thirty.**
> Design rule in Markless: the first paper of a class set is ALWAYS marked
> alone and shown to the teacher before the other 29 go anywhere. Wrong
> answer key? You find out on paper one, for the cost of one paper. On every
> plan, including free. Safety checks shouldn't be premium features.
Visual: pilot screen or the site's green promise strip.

**10 — what leaves the phone.**
> Privacy decision: student names are read ON the device and blacked out
> before a page uploads. And where that isn't possible (browsers have no
> on-device text recognition) the app says so out loud and makes you
> acknowledge it before a page of a child's work goes anywhere. The docs
> state plainly what redaction can't do. "Trust us" is not a privacy policy.
Visual: the redaction illustration from the site.

**11 — the arithmetic bug.**
> My annual plan advertised "two months free vs monthly." $119.99 vs
> $14.99×12 is four months free. I was UNDERSELLING my own discount. A
> paywall that can't do its own arithmetic is not one to defend — fixed, and
> now it just says what it is: every Pro feature, ~$10/month, fewer marks
> than monthly Pro. Tradeoffs stated beat tradeoffs hidden.
Visual: old vs new Pro Annual card.

**12 — scaling test cost.**
> Ran a 6-part performance battery against my real backend yesterday: load,
> stress, spike, soak, volume, scalability. 30,000+ requests. Total AI spend:
> $0.0011 — because the harness defaults to zero AI calls and the one real
> marking probe is opt-in and hard-capped. Load tests shouldn't cost more
> than the outage they prevent.
Visual: the battery results table.

## Weekly rhythm after the drafts run out

Mon: what shipped last week (screenshot). Wed: one bug or decision, honestly
told. Fri: one thing teachers taught you / one metric that moved. Post live
on real events: Play submission day, first review verdict, launch day.

## Do not post

Revenue or user numbers you don't have (say "0 users" proudly instead), any
security issue not yet fixed AND deployed, student data of any kind, the
anon key or any secret, screenshots with a real person's name (the demo
account's fake names are fine).
