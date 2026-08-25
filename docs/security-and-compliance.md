# Markless — Security & Compliance

**Last updated: 25 August 2026**

This is the document a school administrator, district privacy officer or
procurement reviewer should be handed. It states what Markless does with
student data, what it will not do, and where the boundaries of that promise
are. Everything below describes behaviour that is implemented in the app, not
intentions — where something is a commitment rather than a control, it says so.

Contact: **oscar.cs.lee@gmail.com**

---

## 1. The two rules that shape the product

### The teacher decides the grade. Always.

Markless produces a **proposed** mark. It is never final and never recorded as
final without a teacher looking at it.

- Every result opens in a review screen showing the score, the per-question
  breakdown, and the reasoning behind each deduction.
- The teacher can change any mark, and an overridden result is flagged as
  such.
- Work the model is not confident about is returned as **"requires teacher
  marking"** rather than a guessed score — hand-drawn diagrams, unreadable
  handwriting, and answers reached by an unexpected method are flagged for a
  human rather than resolved automatically.
- Nothing is transmitted to a gradebook, a student, or a parent by Markless.
  The teacher carries the mark forward themselves.

This matches the direction of state legislation requiring that AI assist with
grading but not be the final decision-maker on it. The pattern Markless
implements is **AI suggests → teacher reviews → teacher confirms**.

### Student identity does not go to the AI.

The marking model grades the work. It is not told, and does not need to know,
whose work it is.

| What | Where it goes |
|---|---|
| The student's name | **Stays on the device.** Read locally, blacked out of the page before upload |
| Page images | Sent for marking, with identity fields redacted, then discarded |
| Typed answers (Form/CSV import) | Sent keyed by **row number**, never by name; known names scrubbed from the text |
| Marks, feedback, scores | Stored on the teacher's account; never sent to a model afterwards |
| Teacher account id | Sent, to meter usage against the right account |

Details in §3.

---

## 2. Legal footing

**FERPA (US).** Student work, names and scores are education records. Markless
is used by the teacher as a school official with a legitimate educational
interest, and acts as a service provider under the school's direction. It does
not disclose student records to anyone outside the marking pipeline described
in §4, and does not sell data or use it for advertising. There is no student
sign-up, no student contact, and no student-facing surface at all.

**Model training.** Markless does not train models. Its subprocessors are used
under API terms that do not train on submitted content (§4) — this is the
requirement California has already legislated, and it is a condition of any
provider Markless routes to. Where a provider's terms do not meet that bar,
that provider is named as such in §4 rather than quietly used.

**Ontario / MFIPPA (and boards generally).** Boards must inventory the
software they use and the personal information disclosed to each vendor, and
give written notice naming the vendor and the data disclosed (O. Reg. 52/26).
§3 and §4 exist to be pasted directly into that inventory. Note that some
boards additionally forbid entering student work into AI for assessment at
all; where that is the local rule, Markless's marking features are not
compliant regardless of the safeguards here, and that is a decision for the
board, not for us to argue around.

**Age.** Markless is licensed to teachers, who are adults. It collects no
information directly from children and shows no ads.

---

## 3. What leaves the device, exactly

### Marking a photographed or scanned paper

1. The page is processed on the device (deskew, contrast, sharpen).
2. **On-device text recognition finds identity fields** — `Name:`, `Student:`,
   `Student ID:` — and reads the value.
3. **Those regions are painted solid black** in the copy that will be
   uploaded. The original, unaltered page stays on the phone so the teacher
   still sees the real paper.
4. The redacted page is sent for marking, along with: grading mode,
   strictness, criteria, grade level, curriculum region, and the teacher's
   account id. **The student's name is not sent** — it was previously included
   as "reference only, never grade on it", and has been removed because it
   served no marking purpose.
5. The name read in step 2 is used **locally** to file the result under the
   right student.

This is controlled by **Settings → Privacy → "Hide student names before
marking"**, on by default.

**Its limits, stated plainly.** Redaction covers name *fields*. It cannot
cover a name written somewhere unexpected, a name inside the body of an essay,
or a signature on artwork; and if the handwriting is unreadable to the
recognizer, the field is not found and the page uploads unredacted (the app
reports when this happened). Handwriting is itself arguably identifying, and
nothing removes that. Markless reduces exposure substantially; it does not
make a scanned page anonymous, and no vendor should claim otherwise.

### Marking an imported Google Form / CSV

Answers are sent **keyed by row number**, never by name. The name column is
never transmitted. Known student names — from the sheet and from the class
roster — are scrubbed out of the answer text itself, so a student who signed
their essay is still anonymous to the model. Multiple-choice questions are
marked entirely on the device and are never transmitted at all.

### Never transmitted

Contacts, location, photo library beyond the pages the teacher picks, device
advertising identifiers, other apps, or any analytics profile. There is no
analytics SDK in the app.

---

## 4. Subprocessors

| Provider | Purpose | Data it receives | Trains on it? |
|---|---|---|---|
| **Anthropic** (Claude) | Primary marking | Redacted page images, marking instructions | No — API data is not used for training |
| **Google** (Gemini) | Fallback marking, page transcription | Redacted page images | No, under paid API terms |
| **DeepSeek** | Cheap route for objective/short answers | Answer **text** only, no images, no names | **Yes — see below** |
| **Supabase** | Database, marking service hosting | Marks, feedback, classes, students, account | No |
| **RevenueCat / Google Play / Apple** | Subscriptions | Purchase records. No payment details reach us | No |
| **Google Drive** | Optional export, teacher-enabled | Only files Markless creates in its own folder | No |

> **DeepSeek, stated honestly.** DeepSeek's published policy stores data on
> servers in the People's Republic of China and permits use of submitted
> content for training. It receives anonymous answer text only — never images,
> never names, never account identifiers beyond the metering id. Even so, it
> does **not** meet the no-training bar this document sets elsewhere, and it
> should be disabled before any deployment where that bar is contractual. The
> route exists to reduce cost and is not required for correct marking; marking
> falls back to Claude when it is off.

Page images are **not retained** by Markless. A one-way hash of each page is
stored so that re-marking an identical page can be served from cache instead
of being processed again; a hash cannot be reversed into the image.

---

## 5. Storage, retention, deletion

- **In transit:** TLS to every endpoint.
- **At rest:** marks, feedback, classes, students and account details are
  stored in the teacher's Supabase project with row-level security enabled.
  Page images are stored **only on the teacher's device**.
- **Credentials:** model API keys live server-side and are never shipped in
  the app. The app carries only a public anon key, which is why no endpoint
  trusts the client for anything that matters — plan entitlements, for
  example, are writable only by the store's webhook, never by the app.
- **Deletion:** Settings → Delete my account erases the profile, every marked
  result, every class and student, answer keys and settings, on the device and
  on the server, then deletes the login itself. It is irreversible, requires
  typing DELETE, and is verified to refuse any request not carrying the
  account holder's own signed-in token. Individual results can be deleted at
  any time and the server copy goes with them.
- **Retention:** data is kept while the account exists. There is no archival
  copy that survives deletion.

---

## 6. Access control

- Accounts are Supabase Auth (email/password, Google, Apple). Passwords are
  never stored by Markless.
- A teacher sees only their own data. Destructive endpoints verify the
  caller's own token rather than trusting an identifier in the request body.
- Server-side spend caps limit what any single account can consume, which also
  bounds the blast radius of a stolen credential.

---

## 7. Known gaps

Listed because a reviewer will find them anyway, and a vendor who hides them
should not be trusted with student work.

1. **Redaction is best-effort**, per §3.
2. **DeepSeek's terms do not meet the no-training standard**, per §4.
3. **No SOC 2 report.** Markless is a small product; there has been no
   third-party security audit.
4. **No signed DPA template yet.** Available on request, negotiated per
   district.
5. **Sub-processor changes** are not currently announced on a schedule. If a
   district requires notice before a new subprocessor is added, that must be
   written into the agreement.

---

## 8. For district review

Provide this document, [privacy-policy.md](privacy-policy.md), and the app's
data-safety declarations. Questions, DPA requests, and security disclosures:
**oscar.cs.lee@gmail.com**.
