/**
 * Every fact on this site, in one file, next to the source it came from.
 *
 * RULE: no number appears on this page that is not in this file, and no number
 * enters this file without a source in the repository. UMarkless has no adoption
 * statistics, no satisfaction scores, no user counts and no testimonials, so
 * the site has none either.
 *
 * Sources:
 *   README.md ........................... the four routes and their timings,
 *                                         the pilot paper, overnight batching
 *   docs/store-listing.md ............... route copy, the 10% give-back
 *   docs/security-and-compliance.md ..... redaction, its limits, subprocessors
 *   lib/screens/plans/plans_screen.dart . tier names, prices, credits, perks
 */

export const APP_URL = 'app/';
export const REPO_URL = 'https://github.com/drposhbug/ai-marking-dreamflow';
export const COMPLIANCE_URL = `${REPO_URL}/blob/main/docs/security-and-compliance.md`;
export const README_URL = `${REPO_URL}#readme`;
export const CONTACT = 'oscar.cs.lee@gmail.com';
// TODO: replace with the Google Play listing URL once the app is live.
export const LAUNCH_MAILTO = `mailto:${CONTACT}?subject=UMarkless%20launch`;

/* ------------------------------------------------------------------ routes */
/* README.md, "The four ways to mark". Times are for a class of thirty. */

export type Route = {
  id: string;
  tab: string;
  minutes: string;
  title: string;
  bestFor: string;
  how: string;
  /** The three things that actually happen, in order. */
  steps: string[];
  /** What this route does for free, because it happens on the device. */
  onDevice: string;
};

export const ROUTES: Route[] = [
  {
    id: 'form',
    tab: 'Google Form',
    minutes: '~2',
    title: 'Google Form or spreadsheet',
    bestFor: 'Quizzes, and anything students type.',
    how:
      'Export the Form responses to a CSV and import it. Confirm the detected columns, tap the correct option for each multiple-choice question, and the class comes back marked. Every student’s answer to a written question is marked together in one pass, so the whole class is judged against the same standard.',
    steps: ['Export the responses CSV', 'Confirm columns and MC keys', 'One pass per question'],
    onDevice: 'Multiple choice is marked on the device for free — no API call, no credits.',
  },
  {
    id: 'stamped',
    tab: 'Print stamped',
    minutes: '~6',
    title: 'Print it stamped, then scan the stack',
    bestFor: 'Real tests on paper. The one route that cannot mix students up.',
    how:
      'Upload the test file, pick a copy count, and print the single PDF it makes: every copy is stamped in the footer of every page with its own code — mk-7F3A-01, mk-7F3A-02. Feed the stack through the copier as one PDF and pages sharing a code reassemble, shuffled, creased or out of order.',
    steps: ['Print the stamped copies', 'Feed the stack as one PDF', 'Codes reassemble the papers'],
    onDevice: 'Stamping runs entirely on the device — no API cost.',
  },
  {
    id: 'stack',
    tab: 'Scan a stack',
    minutes: '~6',
    title: 'Scan a stack you already printed',
    bestFor: 'A test printed and written on the ordinary way.',
    how:
      'Scan the stack to one PDF. It splits back into papers on the device, either by fixed page length or by spotting cover-page signals — a “Name:” field near the top, a “Page 1 of 4”. You see the split before anything is marked. Say how many students to expect and it catches a page the feeder swallowed.',
    steps: ['One scanned PDF', 'Split found on the device', 'You confirm before marking'],
    onDevice: 'Detection uploads nothing — the boundaries are found on the phone.',
  },
  {
    id: 'photo',
    tab: 'Photograph',
    minutes: '~15',
    title: 'Photograph each paper',
    bestFor: 'A few papers, a late submission, or no copier in reach.',
    how:
      'Prop the phone up and slide each page underneath. It shoots on its own and makes a sound or a buzz to say the page has landed and it is time for the next one.',
    steps: ['Prop the phone up', 'Slide a page underneath', 'It shoots on its own'],
    onDevice: 'The name is read and blacked out on the device before the page is uploaded.',
  },
];

/* ---------------------------------------------------------- the sequence */
/* The life of one class set, from the copier to the gradebook. Every line is
   from README.md or docs/security-and-compliance.md. */

export type Stage = {
  id: string;
  label: string;
  n: string;
  title: string;
  body: string;
  note: string;
};

export const STAGES: Stage[] = [
  {
    id: 'scan',
    label: 'Scan',
    n: '01',
    title: 'A stack goes through the copier once.',
    body:
      'Thirty papers, one document feeder, one PDF. Nothing is sorted, nothing is renamed, no page is photographed twice. The name field is read on your own device and painted solid black in the copy that gets uploaded — the unaltered page never leaves it.',
    note: 'In a browser it covers the printed “Name:” line, not the handwriting.',
  },
  {
    id: 'split',
    label: 'Split',
    n: '02',
    title: 'It splits back into papers before anything is uploaded.',
    body:
      'Boundaries are found on the phone — a printed code in the footer, a “Name:” field near the top, a “Page 1 of 4”. The split is shown to you and only what you confirm is marked. Tell it how many students to expect and it catches the page the feeder swallowed.',
    note: 'Detection uploads nothing at all.',
  },
  {
    id: 'mark',
    label: 'Mark',
    n: '03',
    title: 'The first paper is marked alone, and shown to you.',
    body:
      'One paper, marked and handed back before the other twenty-nine go anywhere. If the answer key is wrong you find out on paper one. Then the set runs: question-by-question scores, half and quarter marks, and a written reason for every deduction.',
    note: 'On every plan, including free.',
  },
  {
    id: 'review',
    label: 'Review',
    n: '04',
    title: 'You change anything you disagree with.',
    body:
      'Every result opens on a review screen with the score, the per-question breakdown and the reasoning behind each deduction. Change a mark and the override is recorded. A hand-drawn diagram, or an answer reached an unexpected way, comes back flagged for you rather than scored on a hunch.',
    note: 'The teacher decides the grade. Always.',
  },
  {
    id: 'export',
    label: 'Export',
    n: '05',
    title: 'Marks leave as a CSV, or a document in Drive.',
    body:
      'A gradebook CSV, or a Google Doc written into the folder UMarkless made. That is the whole handoff. UMarkless sends nothing to a gradebook, a student or a parent — you carry the mark forward yourself.',
    note: 'Nothing is sent on your behalf.',
  },
];

/* -------------------------------------------------------------- flip cards */
/* Illustrations of a marked answer. Front: what the student wrote. Back: what
   came back — the mark, the quarter mark, the reason. */

export type FlipCard = {
  id: string;
  subject: string;
  question: string;
  answer: string[];
  mark: string;
  outOf: string;
  reason: string;
  feedback: string;
  tone: 'cut' | 'good' | 'ask';
};

/* Six cards, six subjects, because a marking assistant that only ever shows
   algebra looks like a maths tool. Every card's marking is genuinely right
   in its own discipline — the French card cites the actual rule — since a
   teacher of that subject will read exactly that card hardest. */
export const FLIP_CARDS: FlipCard[] = [
  {
    id: 'q2',
    subject: 'Maths',
    question: 'Q2 · Solve 3x + 7 = 25',
    answer: ['3x + 7 = 25', '3x = 32', 'x = 10.67'],
    mark: '3¾',
    outOf: '/5',
    reason: 'Method correct throughout. Arithmetic slip on line two: 25 − 7 is 18, not 32.',
    feedback: 'Write the subtraction on its own line before you divide.',
    tone: 'cut',
  },
  {
    id: 'q1',
    subject: 'English',
    question: 'Q1 · What does the fog in the opening suggest?',
    answer: ['The fog shows that no one can see', 'what is really going on, and it', 'follows the lawyers around.'],
    mark: '5',
    outOf: '/5',
    reason: 'Reads the fog as concealment and ties it to a named group in the text. Full marks.',
    feedback: 'Quote four words of it next time and the point lands harder.',
    tone: 'good',
  },
  {
    id: 'q3',
    subject: 'French',
    question: 'Q3 · Mettez au passé composé : « Je vais au cinéma. »',
    answer: ['J’ai allé au cinéma.'],
    mark: '2½',
    outOf: '/4',
    reason:
      'Right tense, wrong auxiliary: « aller » takes être, and the participle agrees — « je suis allé », or « allée ».',
    feedback: 'Aller is a VANDERTRAMP verb. Say the sentence once with « suis » and it will stick.',
    tone: 'cut',
  },
  {
    id: 'q4',
    subject: 'Science',
    question: 'Q4 · Why does the reaction slow down over time?',
    answer: ['Because there is less stuff', 'left to react so it goes slower'],
    mark: '1½',
    outOf: '/3',
    reason:
      'The idea is right but untermed — no mention of concentration, of collisions, or of the reactant being used up.',
    feedback: 'Name the quantity that changes, then say what it does to collisions.',
    tone: 'cut',
  },
  {
    id: 'q5',
    subject: 'History',
    question: 'Q5 · Give one cause of the 1929 crash and explain it',
    answer: ['People borrowed money to buy shares,', 'so when prices fell they had to sell,', 'and selling pushed prices down further.'],
    mark: '4',
    outOf: '/4',
    reason: 'Names a real cause — buying on margin — and runs the mechanism in both directions. Full marks.',
    feedback: 'Use the term “buying on margin” and the same answer earns its keep in the exam.',
    tone: 'good',
  },
  {
    id: 'q7',
    subject: 'Physics',
    question: 'Q7 · Sketch the forces on the block',
    answer: ['[ hand-drawn free-body diagram ]'],
    mark: 'Asks you',
    outOf: '',
    reason: 'A hand-drawn diagram. Not scored on a hunch — handed back for a teacher to mark.',
    feedback: 'Flagged as “requires teacher marking”.',
    tone: 'ask',
  },
];

/* ------------------------------------------------------- what we believe */

export type Belief = { n: string; title: string; body: string };

export const BELIEFS: Belief[] = [
  {
    n: '01',
    title: 'AI suggests. The teacher confirms.',
    body:
      'UMarkless produces a proposed mark. It is never final, and never recorded as final without a teacher looking at it. An overridden result is flagged as overridden. There is no setting that removes the middle step.',
  },
  {
    n: '02',
    title: 'Student identity does not go to the AI.',
    body:
      'The model grades the work. It is not told, and does not need to know, whose work it is. The name is read on your own device, blacked out of the uploaded copy, and kept there — on a phone it reads the handwriting itself, in a browser it covers the printed “Name:” line. Imported answers go up keyed by row number.',
  },
  {
    n: '03',
    title: 'The first paper of a set is marked alone.',
    body:
      'The pilot paper is marked on its own and shown to you before the other twenty-nine go ahead. Approving the first result is a safety check, not a premium feature, so it happens on every plan including free.',
  },
  {
    n: '04',
    title: 'A wrong answer key costs one paper, not thirty.',
    body:
      'That is the whole reason the first paper goes alone. A key that reads the wrong option, a mark scheme out of step with the test — you find out once, on one page, and fix it before the set runs.',
  },
  {
    n: '05',
    title: 'It refuses to guess.',
    body:
      'A hand-drawn diagram, an unreadable page, a right answer reached an unexpected way: it says so, and hands that question back, rather than inventing a score. A confident wrong mark is worse than an admitted gap.',
  },
  {
    n: '06',
    title: 'Marks are metered, never “unlimited”.',
    body:
      'Plans are credit-based, and credits are weighted by what a paper actually costs to mark. A short multiple-choice quiz costs a fraction of a six-page problem set, and re-marking the same paper is free. Nobody is promised infinity and then quietly throttled.',
  },
  {
    n: '07',
    title: 'The limits are written down.',
    body:
      'Redaction is best-effort on name fields, and weaker in a browser than on a phone. There is no SOC 2 report and no signed DPA template yet. One cheap route uses a provider whose terms permit training. All of it is listed, because a reviewer will find it anyway.',
  },
];

/* ---------------------------------------------------------------- plans */
/* lib/screens/plans/plans_screen.dart: the fallback price strings, the credit
   lines and the perks, exactly as the app states them. */

export type Plan = {
  id: string;
  name: string;
  price: string;
  period: string;
  credits: string;
  perks: string[];
  highlight?: boolean;
};

export const PLANS: Plan[] = [
  {
    id: 'starter',
    name: 'Starter',
    price: '$6.99',
    period: '/month',
    credits: 'About 200 papers a month, marked overnight',
    perks: ['Marking on every subject', 'Answer keys and learned keys', 'Google Drive export'],
  },
  {
    id: 'pro',
    name: 'Pro',
    price: '$14.99',
    period: '/month',
    credits: 'About 450 papers a month marked overnight, or 90 on the spot',
    perks: [
      'Everything in Starter',
      'Mark a whole class set on the spot',
      'Lesson planning assistant',
      'Priority marking queue',
    ],
    highlight: true,
  },
  {
    id: 'pro_annual',
    name: 'Pro Annual',
    price: '$119.99',
    period: '/year',
    credits: 'About 300 papers a month, marked overnight',
    perks: ['Every Pro feature', 'Works out about $10 a month', 'Fewer marks a month than monthly Pro'],
  },
  {
    id: 'school',
    name: 'School',
    price: '$24.99',
    period: '/month',
    credits: 'About 760 papers a month marked overnight, or 150 on the spot',
    perks: ['Everything in Pro', 'Built for a full teaching load', 'Department invoicing on request'],
  },
];

/* -------------------------------------------------------------- privacy */

export const PRIVACY_CLAIMS = [
  {
    title: 'The name is blacked out before upload',
    body:
      'On iOS and Android, on-device text recognition finds identity fields — Name:, Student:, Student ID: — and paints them solid black in the uploaded copy. The unaltered page stays on your phone, and the name files the result under the right student.',
  },
  {
    title: 'Imported answers go up keyed by row number',
    body:
      'Never by name. The name column is never transmitted, known student names are scrubbed out of the answer text, and multiple-choice questions never leave the device at all.',
  },
  {
    title: 'Pages are not kept, and nothing is tracked',
    body:
      'Images are marked and discarded; what is stored is the result. No ads, no analytics SDK, no student accounts. Delete your account in the app and every result, class and key goes with it, irreversibly.',
  },
];

/** Split so the one emphasised word can be a real <em> without any raw HTML. */
export type Limit = { before: string; em?: string; after?: string };

export const LIMITS: Limit[] = [
  {
    before: 'Redaction covers name ',
    em: 'fields',
    after:
      '. A name inside an essay, a signature on artwork, or handwriting the recognizer cannot read gets through — and the app reports when that happened.',
  },
  {
    before:
      'It is weaker in a browser: the reader there works off the printed “Name:” label rather than the handwriting, so it blacks out that whole line instead of the name exactly — and on a page with no printed label nothing is covered, which the app tells you. The phone apps read the handwriting itself. The Form and CSV route is unaffected either way.',
  },
  {
    before:
      'One cheap route for objective and short answers goes to a provider whose terms permit training on submitted content and store data in the People’s Republic of China. Answer text only — never images, never names — and it can be switched off.',
  },
  {
    before:
      'No SOC 2 report, no third-party security audit, and no signed DPA template yet; one is available on request.',
  },
];
