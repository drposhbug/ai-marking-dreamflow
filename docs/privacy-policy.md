# Markless — Privacy Policy

**Last updated: 16 August 2026**

Markless is a marking assistant for teachers. This policy explains what it
collects, who it is shared with, and how to delete it. Plain language, because
you are handing us other people's children's work.

Contact: **oscar.cs.lee@gmail.com**

---

## What we collect

**Your account**
Your email address, and the name, honorific, school and curriculum region you
enter during setup. Your marking defaults (mode, harshness) are saved so they
follow you to a new phone.

**Student work you scan**
Photos, PDFs and Drive files you choose to mark. These are sent to the AI
provider that marks them (see *Who else sees it*) and the resulting marks,
feedback and annotations are stored on your account so they appear on any phone
you sign into.

**Images are not kept on our servers.** They are passed through for marking and
discarded. What we store is the *result* — scores, comments, question
breakdowns — plus a one-way hash of each image so that re-marking the identical
page can be served from cache instead of being paid for and processed again. A
hash cannot be turned back into the picture.

**Students you enter**
Names, your own student codes, class assignment, and any notes you write. You
type these; the app never sources them from anywhere else.

**Usage**
Which actions ran, token counts and the cost of each marking call. This enforces
your plan's credit allowance and nothing else. No advertising, no profiling, no
tracking across other apps or websites.

## What we do not collect

No location. No contacts. No device advertising ID. No analytics SDK following
you around. Students never have accounts and are never contacted.

## Who else sees it

- **AI providers who do the marking** — Anthropic (Claude), Google (Gemini) and,
  for simple objective questions, DeepSeek. They receive the page images and the
  marking instructions. They process the request and return the marks.
- **Supabase** — hosts the database and the marking service.
- **RevenueCat and your app store** (Google Play / Apple) — handle subscriptions.
  We never see your card details.
- **Google Drive** — only if you switch on Drive export, and only inside the
  "Markless" folder the app creates. The app cannot see the rest of your Drive.

We do not sell your data, and we do not share it with anyone else.

## Your responsibilities as a teacher

You decide what to photograph. Your school or district likely has rules about
sending student work to a third-party service — follow them. Where the law
treats your school as the data controller, Markless acts as a processor on your
instructions.

## Deleting your data

**Any single marked test** — delete it in the app; the copy on our servers goes
with it.

**Your whole account** — Settings → *Delete my account*. This erases, for good:
your profile, every marked result, every class and student, your answer keys,
your saved settings and your sign-in itself, on the phone and on our servers. It
cannot be undone by you or by us. Cancelling a subscription is separate and is
done in the Play Store or App Store.

The only thing that survives is the anonymous marking cache described above:
hashes and model output that carry no name, no email and no account id.

You can also email **oscar.cs.lee@gmail.com** and we will delete your account
for you.

## Keeping it safe

Traffic is encrypted in transit. Marking runs server-side with credentials that
never ship inside the app. Access to the database is restricted to the marking
service.

## Children

Markless is for teachers, not students. It has no student sign-up, sends nothing
to students, and shows no ads. Student work appears only because a teacher
scanned it, and only that teacher can see the result.

## Changes

If this policy changes materially you will be told in the app before the change
takes effect.
