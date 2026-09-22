# Markless — Security & Compliance

**Last updated: 21 September 2026**

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
| The student's name | **Stays on the device.** The name line is read and blacked out of the page before upload, on every platform. A browser reads the printed label only and covers the whole line; it reads no name at all. See §3.1 |
| Page images | Sent for marking, with identity fields redacted first — or reported as not redacted — then discarded |
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
   uploaded. The original, unaltered page stays on the teacher's device so they
   still see the real paper.
4. The redacted page is sent for marking, along with: grading mode,
   strictness, criteria, grade level, curriculum region, and the teacher's
   account id. **The student's name is not sent** — it was previously included
   as "reference only, never grade on it", and has been removed because it
   served no marking purpose.
5. The name read in step 2 is used **locally** to file the result under the
   right student.

This is controlled by **Settings → Privacy → "Hide student names before
marking"**, on by default. It is live on every platform Markless ships on,
but a browser reads a page less well than a phone does and behaves
differently as a result — §3.1 sets out exactly how.

**Its limits, stated plainly.** Redaction covers name *fields*. It cannot
cover a name written somewhere unexpected, a name inside the body of an essay,
or a signature on artwork; and if the handwriting is unreadable to the
recognizer, the field is not found and the page uploads unredacted. The app
reports that: before the teacher sends a paper it says whether names will be
hidden, and on the check-the-first-one screen for a class set it says whether
the name on that paper was actually covered — because that screen is where the
teacher decides whether the other twenty-nine go the same way. Handwriting is
itself arguably identifying, and nothing removes that. Markless reduces
exposure substantially; it does not make a scanned page anonymous, and no
vendor should claim otherwise.

### 3.1 What is different in a browser

Redaction runs in a browser too, and it runs **on the teacher's own machine**:
a Tesseract build compiled to WebAssembly, served from Markless's own origin
(no CDN, no third-party script), reading the page in a worker. The page is not
sent anywhere to be read. The network is not involved in this step on any
platform.

What differs is **how well it reads**, and that changes what the app is
allowed to conclude:

- **A browser reads printed text, not handwriting.** The `Name:` /
  `Student:` / `Student ID:` label on a school test template is printed, so
  it is found; the child's handwriting beside it is not read.
- **Because of that, the whole line is blacked out, edge to edge.** On iOS
  and Android the recogniser can see where the handwritten name ends and the
  black box is drawn to fit it. In a browser it cannot, so the box runs the
  full width of the page across that line. This redacts more of the page, not
  less — it may also cover a `Date:` or `Class:` field sharing the line. That
  is deliberate: covering the label and leaving the name visible beside it,
  while reporting success, is the one failure mode this design refuses.
- **No name is read off the page in a browser.** On mobile the name is read
  locally and used to file the result under the right student. In a browser
  the app does not report a name at all, because anything it made of the
  handwriting would be a guess, and a guessed name misfiles a result
  silently. The teacher assigns the paper themselves, as they already did on
  the web.
- **When no label is found, nothing is covered — and the app says so.**
  Browser OCR fails more often than the phone's: a poor photo, a skewed
  scan, a faint photocopy, an unusual template, or a `Name` field with no
  printed label at all. In every one of those cases the page is sent exactly
  as the teacher picked it, and `redacted` is reported false: the grading
  screen shows "Name not hidden on this paper" before sending and the
  check-the-first-one screen shows it for a class set. **There is no state in
  which the app reports a name as hidden without a black box having been
  painted over that line in the uploaded bytes.**
- **The engine downloads once.** 7.1 MB, measured: a 3.9 MB WebAssembly core,
  a 3.0 MB English model, and 0.2 MB of loader. It is fetched the first time
  a teacher uploads student work in a browser — not on app open, so a teacher
  who only imports Google Forms never downloads it — and is then held in the
  browser's cache and IndexedDB. Reading one page takes roughly a second on
  a desktop after that.
- **The first time a teacher uploads student work in a browser, the app
  states these limits and requires an explicit acknowledgement** before the
  page goes anywhere, remembered per teacher. Teachers who acknowledged the
  earlier version of this notice — which said names could not be hidden in a
  browser at all — are asked again, because what they agreed to is no longer
  what happens.
- **The Settings toggle "Hide student names before marking" is live in a
  browser** and describes the weaker behaviour rather than the phone's.
- **The Google Form / CSV route is unaffected and remains the strongest route
  on the web.** It is pure Dart, needs no recognition at all, sends answers
  keyed by row number, and never transmits the name column.

**For a district that requires redaction before transmission.** The browser
version now performs that redaction, on the teacher's machine, before any
upload. It is less reliable at finding the field than the mobile apps, and
when it does not find one it says so rather than proceeding quietly. A
district that requires redaction to be *guaranteed* rather than *attempted
and reported* is not served by any of the three platforms — the mobile
limits in §3 apply there too — and should use the Form/CSV route for
identified work. A district choosing between the browser and the apps for
photographed work should prefer the apps.

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
| **Anthropic** (Claude) | Primary marking | Page images — identity fields redacted first on every platform, or reported as not redacted (§3.1) — and marking instructions | No — API data is not used for training |
| **Google** (Gemini) | Fallback marking, page transcription | Page images, on the same terms as the row above | No, under paid API terms |
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
2. **Redaction in a browser is weaker than on a phone**, per §3.1. It finds
   the printed label and covers the whole line, it does not read handwriting,
   it fails to find a field more often, and it reads no student name at all.
   When it finds nothing it says so and uploads the page unredacted. The app
   states this and asks the teacher to acknowledge it before their first
   browser upload, but saying so is not the same as the field being found,
   and this remains a real difference between platforms.
3. **DeepSeek's terms do not meet the no-training standard**, per §4.
4. **No SOC 2 report.** Markless is a small product; there has been no
   third-party security audit.
5. **No signed DPA template yet.** Available on request, negotiated per
   district.
6. **Sub-processor changes** are not currently announced on a schedule. If a
   district requires notice before a new subprocessor is added, that must be
   written into the agreement.

---

## 8. For district review

Provide this document, [privacy-policy.md](privacy-policy.md), and the app's
data-safety declarations. Questions, DPA requests, and security disclosures:
**oscar.cs.lee@gmail.com**.
