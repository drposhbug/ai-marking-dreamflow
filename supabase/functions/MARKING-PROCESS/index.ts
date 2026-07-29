// supabase/functions/MARKING-PROCESS/index.ts
//
// Grades a scanned page of student work with AI vision.
// Primary grader: Claude (Anthropic). Fallback: Gemini (Google).
//
// Token optimizations (all invisible to the Flutter app — response shape is unchanged):
//   1. Feedback banks — the model returns short codes ("#5", "#1 algebra") that
//      this function expands into full pre-written sentences before responding.
//   2. rawText transcription is skipped unless the request sends
//      includeTranscription: true (nothing in the app displays it).
//   3. Anthropic prompt caching — the static marking rules and the answer key
//      are cached with a 1h TTL, so repeat grades pay ~10% for that prefix.
//   4. grade_cache table — identical submissions (same images + settings) are
//      served from the database with zero AI tokens. formatOverride and
//      studentName are excluded from the cache key, so format toggles and
//      name corrections re-use the stored model output for free. Image hashes
//      are sorted in the key (same pages in any order hit) and annotation
//      pageIndex values are remapped to the request's page order on a hit.
//      Bump CACHE_VERSION whenever the prompt, banks, or schema change.
//   5. feedback_code_usage table — every fresh grade records which sentence
//      codes were used (plus unknown codes and free-text escapes) so you can
//      see which banks need more options.
//
// Secrets required (Dashboard → Edge Functions → Secrets, or `npx supabase secrets set`):
//   ANTHROPIC_API_KEY  — from https://platform.claude.com
//   GEMINI_API_KEY     — from https://aistudio.google.com/apikey
//
// Run SETUP-DB once after deploying to create the grade_cache table.
//
// Request body (sent by the Flutter app's AiGradingService.grade):
//   { imagesBase64: string[] (or legacy imageBase64), mediaType, mode, maxScore,
//     criteria: [{name}], harshness, studentName?, studentGrade?,
//     formatOverride?, provider?, answerKeyId?, includeTranscription? }
//
// Response body matches AiGradingService._parseResponse exactly (plus `cached`).

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

function serviceDb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

// ---------- Feedback banks (preloaded sentences the model refers to by code) ----------
//
// The model writes "#N" or "#N detail" instead of a sentence. expandFeedback()
// swaps the code for the full sentence below; "detail" fills the {X} slot (or
// is appended in parentheses when the sentence has no slot). Free text passes
// through untouched, so the model always has an escape hatch.

const ANNOTATION_BANK: Record<number, string> = {
  1: "Correct — well done",
  2: "Correct with clear working",
  3: "Right idea, small slip",
  4: "Calculation error",
  5: "Missing or wrong units",
  6: "Wrong formula used",
  7: "No working shown",
  8: "Incomplete answer",
  9: "Misread the question",
  10: "Sign error",
  11: "Rounding error",
  12: "Missing label(s)",
  13: "Definition imprecise",
  14: "Explanation lacks detail",
  15: "Left blank",
  16: "Correct method, wrong final answer",
  17: "Copying/transcription error",
  18: "Needs a supporting example",
  19: "Does not answer the question asked",
  20: "Partially correct — {X}",
};

const CRITERIA_BANK: Record<number, string> = {
  1: "Excellent — consistently strong across the paper.",
  2: "Good overall with a few minor slips.",
  3: "Adequate but inconsistent; see the marked questions.",
  4: "Weak in this area; targeted review needed.",
  5: "Not applicable to this work; full marks given.",
  6: "Strong on {X} but weaker elsewhere.",
};

const STRENGTH_BANK: Record<number, string> = {
  1: "Strong understanding of {X}.",
  2: "Clear, well-organized working shown throughout.",
  3: "Correct use of units and notation.",
  4: "Accurate calculations across the paper.",
  5: "Explanations are clear and well reasoned.",
  6: "Diagrams are neat and properly labeled.",
  7: "Applied {X} correctly to new problems.",
  8: "Good recall of key definitions and facts.",
};

const IMPROVEMENT_BANK: Record<number, string> = {
  1: "Review {X}.",
  2: "Show working for every step, even quick ones.",
  3: "Always include units in final answers.",
  4: "Double-check calculations before moving on.",
  5: "Read each question carefully before answering.",
  6: "Practice more problems on {X}.",
  7: "Write fuller explanations — one sentence is rarely enough.",
  8: "Label all diagrams completely.",
  9: "Attempt every question, even when unsure.",
  10: "Memorize the key formulas for {X}.",
};

// Bump this whenever STATIC_SYSTEM, a sentence bank, or the output schema
// changes — it is part of the grade_cache key, so bumping it stops stale
// cached grades (written under the old prompt/banks) from being served.
const CACHE_VERSION = 8;

// Shown instead of an unknown code that has no detail text — a teacher must
// never see a raw "#37" on screen.
const DEFAULT_FEEDBACK: Record<string, string> = {
  annotation: "See summary feedback",
  criteria: "See the marked questions for details.",
  strength: "Shows solid work in places across the paper.",
  improvement: "Review the questions marked incorrect.",
};

type CodeUse = { bank: string; code: string; kind: "bank" | "unknown" | "free_text" };

function expandFeedback(
  value: string,
  bankName: string,
  bank: Record<number, string>,
  stats?: CodeUse[],
): string {
  const m = /^#(\d+)(?:[\s:—-]+(.+))?$/.exec(value.trim());
  if (!m) {
    if (value.trim().length > 0) stats?.push({ bank: bankName, code: "free_text", kind: "free_text" });
    return value;
  }
  const template = bank[Number(m[1])];
  const detail = m[2]?.trim();
  if (!template) {
    // Unknown code: fall back to the model's detail text when it wrote any,
    // otherwise to the bank's default sentence.
    stats?.push({ bank: bankName, code: `#${m[1]}`, kind: "unknown" });
    return detail && detail.length > 0 ? detail : (DEFAULT_FEEDBACK[bankName] ?? "See feedback");
  }
  stats?.push({ bank: bankName, code: `#${m[1]}`, kind: "bank" });
  if (template.includes("{X}")) return template.replace("{X}", detail || "this topic");
  return detail ? `${template} (${detail})` : template;
}

function bankLegend(title: string, bank: Record<number, string>): string {
  return `${title}: ` + Object.entries(bank).map(([n, t]) => `#${n}=${t}`).join("; ");
}

// ---------- Curriculum regions ----------
//
// Marking expectations per region — selected by the teacher (onboarding /
// settings), sent as `region` on grade requests, and injected as a cached
// system block so the AI anchors grade-level expectations to the right
// curriculum. KEEP IN SYNC with lib/data/curriculum_regions.dart (ids must
// match; the Flutter side holds only id + display label).

const US_LETTER_SCALE = "Letter grading on the standard 10-point scale: A 90–100, B 80–89, C 70–79, D 60–69, F below 60.";

const CURRICULA: Record<string, { label: string; notes: string }> = {
  // Canada
  "ca-on": {
    label: "Ontario, Canada",
    notes: "Ontario Curriculum. Report using the Ontario achievement categories — Knowledge/Understanding, Thinking, Communication, Application (KTCA) — and Levels 1–4, where Level 3 (70–79%) is the provincial standard and Level 4 (80–100%) exceeds it; 50% is a pass. Open-response questions expect full solutions with justification, in the style of EQAO assessments.",
  },
  "ca-qc": {
    label: "Quebec, Canada",
    notes: "Québec Education Program (QEP), competency-based. Percentage grades with 60% as the pass mark. Evaluation emphasizes applying competencies over recall — situational problems in mathematics, extended structured responses in languages.",
  },
  "ca-bc": {
    label: "British Columbia, Canada",
    notes: "BC curriculum (Know-Do-Understand model with Core and Curricular Competencies). K–9 uses the provincial proficiency scale — Emerging, Developing, Proficient, Extending — where Proficient is the expected standard; Grades 10–12 use percentages with 50% as a pass. Reward big-idea understanding and demonstrated competencies, not just content recall.",
  },
  "ca-ab": {
    label: "Alberta, Canada",
    notes: "Alberta Programs of Study, outcomes-based. Percentage grading with 50% as a pass. Mark in the style of Provincial Achievement Tests and diploma exams: precise terminology, complete solutions, and correct units earn the marks.",
  },
  "ca-sk": {
    label: "Saskatchewan, Canada",
    notes: "Saskatchewan curriculum, outcomes-and-indicators based. Percentage grading with 50% pass; tie marks to how fully each curriculum outcome is demonstrated.",
  },
  "ca-mb": {
    label: "Manitoba, Canada",
    notes: "Manitoba curriculum frameworks. Percentage grading with 50% pass; provincial reporting emphasizes knowledge, reasoning, and communication — expect complete explanations and shown work.",
  },
  "ca-ns": {
    label: "Nova Scotia, Canada",
    notes: "Nova Scotia streamlined curriculum. Percentage grading with 50% pass; assessment focuses on essential outcomes per grade with strong literacy and numeracy foundations.",
  },
  "ca-nb": {
    label: "New Brunswick, Canada",
    notes: "New Brunswick curriculum aligned to provincial achievement standards. Percentage grading with 50–60% pass depending on level; emphasis on literacy and numeracy benchmarks.",
  },
  "ca-nl": {
    label: "Newfoundland and Labrador, Canada",
    notes: "Newfoundland and Labrador curriculum, outcomes-based (Atlantic Canada framework). Percentage grading with 50% pass; organize judgments around specific curriculum outcomes.",
  },
  "ca-pe": {
    label: "Prince Edward Island, Canada",
    notes: "PEI curriculum, outcomes-based (Atlantic Canada framework). Percentage grading with 50% pass.",
  },
  "ca-other": {
    label: "Canada (other province/territory)",
    notes: "Canadian provincial curriculum conventions: outcomes-based expectations, percentage grading with 50% as the typical pass mark, and emphasis on complete shown work.",
  },
  // United States
  "us-ca": {
    label: "California, USA",
    notes: `California Common Core State Standards plus NGSS science. ${US_LETTER_SCALE} SBAC/CAASPP-style tasks reward multi-step reasoning, mathematical modeling, and cited text evidence.`,
  },
  "us-tx": {
    label: "Texas, USA",
    notes: "Texas Essential Knowledge and Skills (TEKS) — Texas does not use Common Core. Passing is 70: A 90–100, B 80–89, C 70–79, F below 70. Mark in the style of STAAR: exact numeric answers in math, evidence-based short responses in reading.",
  },
  "us-fl": {
    label: "Florida, USA",
    notes: `Florida B.E.S.T. Standards (Benchmarks for Excellent Student Thinking) — Florida does not use Common Core. ${US_LETTER_SCALE} Math emphasizes procedural fluency and real-world application; ELA emphasizes text evidence, in the style of FAST assessments.`,
  },
  "us-ny": {
    label: "New York, USA",
    notes: "New York Next Generation Learning Standards. Passing is 65; Regents-style constructed responses require full work shown and justification to earn credit.",
  },
  "us-il": {
    label: "Illinois, USA",
    notes: `Illinois Learning Standards (Common Core-aligned) plus NGSS. ${US_LETTER_SCALE} Expect reasoning shown in math and evidence-based ELA responses.`,
  },
  "us-pa": {
    label: "Pennsylvania, USA",
    notes: `Pennsylvania Core Standards. ${US_LETTER_SCALE} PSSA/Keystone-style scoring rewards complete explanations and text evidence.`,
  },
  "us-oh": {
    label: "Ohio, USA",
    notes: `Ohio's Learning Standards. ${US_LETTER_SCALE} Ohio State Test-style items expect shown work and short constructed responses.`,
  },
  "us-ga": {
    label: "Georgia, USA",
    notes: `Georgia Standards of Excellence (GSE). ${US_LETTER_SCALE} Georgia Milestones-style scoring emphasizes constructed responses with supporting evidence.`,
  },
  "us-mi": {
    label: "Michigan, USA",
    notes: `Michigan K–12 Standards (Common Core-aligned). ${US_LETTER_SCALE} M-STEP-style tasks reward multi-step reasoning and evidence.`,
  },
  "us-nc": {
    label: "North Carolina, USA",
    notes: `North Carolina Standard Course of Study. ${US_LETTER_SCALE} EOG/EOC-style items emphasize precise answers and supported reasoning.`,
  },
  "us-nj": {
    label: "New Jersey, USA",
    notes: `New Jersey Student Learning Standards. ${US_LETTER_SCALE} NJSLA-style scoring rewards modeling, reasoning, and cited evidence.`,
  },
  "us-va": {
    label: "Virginia, USA",
    notes: `Virginia Standards of Learning (SOL) — Virginia does not use Common Core. ${US_LETTER_SCALE} SOL-style assessment favors precise factual answers and clearly organized responses.`,
  },
  "us-wa": {
    label: "Washington, USA",
    notes: `Washington State Learning Standards (Common Core + NGSS). ${US_LETTER_SCALE} SBAC-style tasks reward multi-step reasoning and evidence.`,
  },
  "us-ma": {
    label: "Massachusetts, USA",
    notes: `Massachusetts Curriculum Frameworks — among the most rigorous US standards. ${US_LETTER_SCALE} MCAS-style scoring expects thorough constructed responses with full justification.`,
  },
  "us-az": {
    label: "Arizona, USA",
    notes: `Arizona's K–12 academic standards (state-adapted, not branded Common Core). ${US_LETTER_SCALE} AASA-style items emphasize fluency and applied problem solving.`,
  },
  "us-co": {
    label: "Colorado, USA",
    notes: `Colorado Academic Standards. ${US_LETTER_SCALE} CMAS-style tasks reward reasoning and evidence-based writing.`,
  },
  "us-tn": {
    label: "Tennessee, USA",
    notes: `Tennessee Academic Standards. ${US_LETTER_SCALE} TCAP-style scoring emphasizes shown work and text evidence.`,
  },
  "us-in": {
    label: "Indiana, USA",
    notes: `Indiana Academic Standards — Indiana does not use Common Core. ${US_LETTER_SCALE} ILEARN-style items emphasize applied problem solving and evidence.`,
  },
  "us-mo": {
    label: "Missouri, USA",
    notes: `Missouri Learning Standards. ${US_LETTER_SCALE} MAP-style scoring rewards complete solutions and supported responses.`,
  },
  "us-md": {
    label: "Maryland, USA",
    notes: `Maryland College and Career-Ready Standards. ${US_LETTER_SCALE} MCAP-style tasks reward reasoning, modeling, and cited evidence.`,
  },
  "us-mn": {
    label: "Minnesota, USA",
    notes: `Minnesota Academic Standards (state math standards; Common Core ELA). ${US_LETTER_SCALE} MCA-style items expect precise answers and shown reasoning.`,
  },
  "us-wi": {
    label: "Wisconsin, USA",
    notes: `Wisconsin Academic Standards. ${US_LETTER_SCALE} Forward Exam-style scoring emphasizes reasoning and evidence.`,
  },
  "us-cc": {
    label: "United States (Common Core, general)",
    notes: `Common Core State Standards for ELA and Math (plus NGSS-style science where adopted). ${US_LETTER_SCALE} Math expects reasoning shown per the Standards for Mathematical Practice; ELA expects evidence-based responses citing the text.`,
  },
  // Mexico
  "mx": {
    label: "Mexico",
    notes: "SEP national curriculum (Nueva Escuela Mexicana). Numeric grading 5–10 where 6 is the minimum pass; assessment leans formative with projects and open responses.",
  },
};

function regionBlock(regionId: string): string | null {
  const c = CURRICULA[regionId];
  if (!c) return null;
  return `CURRICULUM REGION — ${c.label}.
${c.notes}
Anchor every grade-level expectation, terminology choice, and grading convention to this curriculum. When choosing gradingFormat and writing feedback, use this region's conventions.`;
}

// ---------- Output schema (enforced on Claude via structured outputs) ----------

const nullableInt = { anyOf: [{ type: "integer" }, { type: "null" }] };
const nullableString = { anyOf: [{ type: "string" }, { type: "null" }] };

// deno-lint-ignore no-explicit-any
function gradeSchema(includeTranscription: boolean): any {
  const required = [
    "detectedSubject", "detectedGrade", "studentNameOnPaper", "assignmentKind", "markingStyle",
    "gradingFormat", "rawScore", "maxScore",
    "percentage", "summary", "strengths", "improvements",
    "criteriaBreakdown", "annotations",
  ];
  // deno-lint-ignore no-explicit-any
  const properties: any = {
    detectedSubject: { type: "string" },
    detectedGrade: nullableInt,
    studentNameOnPaper: nullableString,
    assignmentKind: { type: "string" },
    markingStyle: { type: "string", enum: ["completion", "graded"] },
    gradingFormat: { type: "string", enum: ["percentage", "levels"] },
    rawScore: { type: "number" },
    maxScore: { type: "number" },
    percentage: { type: "number" },
    summary: { type: "string" },
    strengths: { type: "array", items: { type: "string" } },
    improvements: { type: "array", items: { type: "string" } },
    criteriaBreakdown: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "score", "maxScore", "level", "feedback"],
        properties: {
          name: { type: "string" },
          score: { type: "number" },
          maxScore: { type: "number" },
          level: nullableInt,
          feedback: { type: "string" },
        },
      },
    },
    annotations: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["questionLabel", "earnedMark", "outOfMark", "correct", "feedback", "pageIndex", "positionTop", "positionLeft"],
        properties: {
          questionLabel: { type: "string" },
          earnedMark: { type: "string" },
          outOfMark: { type: "string" },
          correct: { type: "boolean" },
          feedback: { type: "string" },
          pageIndex: { type: "integer" },
          positionTop: { type: "number" },
          positionLeft: { type: "number" },
        },
      },
    },
  };
  if (includeTranscription) {
    properties.rawText = { type: "string" };
    required.push("rawText");
  }
  return { type: "object", additionalProperties: false, required, properties };
}

// Schema for one-time answer key extraction (stored in the DB, reused on
// every grade so the key images never need re-analysis).
const KEY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["name", "subject", "totalMarks", "questions"],
  properties: {
    name: { type: "string" },
    subject: { type: "string" },
    totalMarks: { type: "number" },
    questions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["label", "marks", "answer"],
        properties: {
          label: { type: "string" },
          marks: { type: "number" },
          answer: { type: "string" },
        },
      },
    },
  },
} as const;

const KEY_PROMPT = `These images are a teacher's ANSWER KEY for a test (in page order). Transcribe it into structured form:
- name: a short title for this test (e.g. "Solubility Unit Test") — infer from headers.
- subject: the school subject.
- totalMarks: total marks of the whole test.
- questions: one entry per question with its label (e.g. "Q3b"), its marks, and the correct answer — include accepted working, units, and alternate acceptable answers in the answer text.
Transcribe every question visible. Do not invent questions that are not shown.`;

const KEY_SHAPE = `\n\nReturn ONLY a single JSON object with exactly these fields:
{"name": string, "subject": string, "totalMarks": number, "questions": [{"label": string, "marks": number, "answer": string}]}`;

// Schema for one-time roster extraction (onboarding: photo of an attendance
// sheet → student list to auto-populate a class).
const ROSTER_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["students"],
  properties: {
    students: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "studentId"],
        properties: {
          name: { type: "string" },
          studentId: nullableString,
        },
      },
    },
  },
} as const;

const ROSTER_PROMPT = `These images show a teacher's class attendance sheet, register, or student roster (in page order). Extract every student into structured form:
- name: the student's full name in "First Last" order (convert "Last, First" if needed), with clean capitalization.
- studentId: the student's ID/number if a column shows one, else null.
Read ALL student names visible across all pages. Do not invent names, do not include the teacher's name, and skip header/total rows.`;

const ROSTER_SHAPE = `\n\nReturn ONLY a single JSON object with exactly these fields:
{"students": [{"name": string, "studentId": string or null}]}`;

// Schema for the planning assistant (text-only): lesson plans, assignments,
// quizzes, and worksheets generated on demand from the Planning screen.
const PLAN_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["title", "content"],
  properties: {
    title: { type: "string" },
    content: { type: "string" },
  },
} as const;

const PLAN_SHAPE = `\n\nReturn ONLY a single JSON object with exactly these fields:
{"title": string, "content": string}`;

// Schema for school-name autocomplete while the teacher types (text-only).
const SCHOOL_SUGGEST_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["schools"],
  properties: {
    schools: { type: "array", items: { type: "string" } },
  },
} as const;

// Schema for inferring the curriculum region from a school name (text-only).
const REGION_INFER_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["candidates"],
  properties: {
    candidates: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["regionId", "place"],
        properties: {
          regionId: { type: "string", enum: [...Object.keys(CURRICULA), "other"] },
          place: { type: "string" },
        },
      },
    },
  },
};

// ---------- Prompt ----------

function strictnessWord(h: number): string {
  if (h <= 3) return "lenient — give the benefit of the doubt and generous partial credit";
  if (h <= 6) return "balanced — fair partial credit, deduct for real errors";
  return "strict — deduct for any imprecision, missing work, or sloppy reasoning";
}

// Static marking rules. This string must stay byte-identical across requests —
// it is the Anthropic prompt-cache prefix. Anything per-request belongs in
// buildContext() below, never here.
const STATIC_SYSTEM = `You are an expert teacher marking scanned pages of ONE student's work. The images arrive in page order, labeled "Page 1", "Page 2", and so on. After the images comes a CONTEXT section with this submission's settings. When an OFFICIAL ANSWER KEY section is present, mark STRICTLY against it — marks per question come from the key, an answer is correct if it matches the key's answer or is mathematically/scientifically equivalent, and you must not re-derive your own answers when the key provides one. Grade the ENTIRE piece of work as one submission, based ONLY on what is visible in the images.

Do all of the following:
1. Detect the subject, and the student's school grade level 1-13 (null if unclear). Also read the student's name if it is written on the paper into studentNameOnPaper (null if none visible).
2. Identify the assignment itself: set assignmentKind to a short label ("test", "quiz", "homework", "worksheet", "lab report", "essay", ...) based on what the pages look like, and choose markingStyle:
   - "completion" — practice work that should be checked for being DONE, not for correctness (typical homework and practice worksheets with no printed marks and no answer key). Then rawScore = the number of questions with a genuine attempt, maxScore = the number of questions assigned; do NOT deduct for wrong answers, but still flag wrong answers with annotation codes so the teacher sees them.
   - "graded" — correctness marking (tests, quizzes, essays, lab reports, anything with printed marks, or whenever an OFFICIAL ANSWER KEY is present).
3. Create one annotation per question or answer visible across all pages:
   - questionLabel like "Q1", earnedMark like "2", outOfMark like "/4" — when the paper prints a question's marks (e.g. "(2 marks)"), use exactly those marks
   - correct = true only if fully correct
   - feedback: one code from ANNOTATION CODES (see FEEDBACK CODES below)
   - check every numeric final answer for UNITS: if a required unit is missing or wrong, deduct part marks and use code #5
   - pageIndex: which page the answer is on, 0-based (Page 1 = 0, Page 2 = 1, ...)
   - positionTop and positionLeft: where the answer sits on THAT page, as fractions of the image height/width between 0.0 and 1.0 (0.0 = top/left edge).
4. Score each grading criterion listed in CONTEXT in criteriaBreakdown with a per-criterion score and maxScore, a level 1-4 (or null), and a feedback code — considering all pages together. criteriaBreakdown is diagnostic feedback ONLY — it must NOT determine the overall score. If a criterion does not apply to this work (e.g. "Diagrams labeled" when no diagrams are required), give it full marks and use criteria code #5 — never deduct for inapplicable criteria.
5. Compute maxScore and rawScore for the whole submission:
   - When markingStyle is "completion", rawScore and maxScore count completed vs assigned questions (see rule 2) — the rules below apply to "graded" work.
   - If the paper prints marks per question (e.g. "(2 marks)", "/4"), maxScore = the TOTAL of the printed marks of the questions VISIBLE in the images, and rawScore = the marks the student earned on those questions.
   - Only if the paper shows no marks at all, use the fallback total marks from CONTEXT.
   - Grade ONLY what is visible. NEVER deduct for questions, sections, or pages that are not in the images — treat the visible pages as the entire submission. If everything visible is fully correct, the score must be full marks.
   - percentage must equal rawScore / maxScore * 100 (rounded is fine).
6. Ontario/Canadian KTCA marking: many Canadian tests divide their sections into the Ontario achievement categories — Knowledge/Understanding, Thinking/Inquiry, Communication, Application (e.g. "Part A – Knowledge Questions (10 marks)", "Part D – Application Questions (10 marks)"). If the visible sections are labeled with these categories:
   - A question counts ONLY toward the category of the section it appears in.
   - Score each visible category separately: marks earned on that section's visible questions out of that section's visible printed marks.
   - Put one entry per visible category FIRST in criteriaBreakdown, named exactly "Knowledge", "Thinking", "Communication", or "Application" (only the categories actually visible), with that category's marks and a feedback code. Any requested criteria follow after as feedback-only entries.
   - The overall percentage = the AVERAGE of the visible category percentages, each category weighted equally (this is how KTCA works — NOT total marks divided by total marks). rawScore and maxScore still report the total visible marks earned and available.
   - If the paper's sections are not labeled with KTCA categories, skip this rule and use percentage = rawScore / maxScore * 100.
7. Choose gradingFormat: "levels" for work at Grades 1-8 (see GRADE-LEVEL EXPECTATIONS below) and for essays, lab reports, and rubric-style work; "percentage" for Grades 9-13 tests, quizzes, and homework.
8. Write summary as AT MOST 2 short sentences addressed to the teacher about this student's overall performance. Do not repeat per-question details, and do NOT list KTCA category scores — those are appended automatically. Give 2-4 strengths and 2-4 improvements, each as a feedback code.

GRADE-LEVEL EXPECTATIONS — mark at the grade level given in CONTEXT when present; otherwise mark at the grade level you detected from the work itself. For work at Grades 1-8, report on the elementary Level scale by choosing gradingFormat "levels": Level 3 = meeting grade expectations, Level 4 = exceeding them, Level 4+ = outstanding. Percentages still back the levels, so compute rawScore/maxScore/percentage as usual.

FEEDBACK CODES — to keep responses compact, every feedback string (annotations.feedback, criteriaBreakdown.feedback, and each entry of strengths and improvements) MUST be a code: write "#N" or "#N detail", where detail is 1-4 words that fill the {X} slot or add specifics. Only write a free-text sentence when no code fits.
${bankLegend("ANNOTATION CODES", ANNOTATION_BANK)}
${bankLegend("CRITERIA CODES", CRITERIA_BANK)}
${bankLegend("STRENGTH CODES", STRENGTH_BANK)}
${bankLegend("IMPROVEMENT CODES", IMPROVEMENT_BANK)}

If the pages are blank, unreadable, or not student work, give a score of 0, an empty annotations list, and explain the problem in summary.`;

function buildContext(p: {
  mode: string;
  maxScore: number;
  harshness: number;
  criteria: string[];
  studentName?: string;
  studentGrade?: number | null;
  expectationGrade?: number | null;
  pageCount: number;
  includeTranscription: boolean;
}): string {
  const lines = [
    "CONTEXT:",
    `- Pages in this submission: ${p.pageCount}`,
    `- Grading mode: ${p.mode}`,
    `- Fallback total marks: ${p.maxScore} (use ONLY if the paper does not show its own marks — see rule 5)`,
    `- Strictness: ${p.harshness}/10 (${strictnessWord(p.harshness)})`,
    `- Criteria to grade on: ${p.criteria.length ? p.criteria.join(", ") : "overall quality"}`,
    `- Student name (reference only, never grade on it): ${p.studentName || "unknown"}`,
    `- Student grade level: ${p.studentGrade ?? "unknown — detect it from the work if possible"}`,
  ];
  if (p.expectationGrade) {
    lines.push(
      `- MARK AT GRADE ${p.expectationGrade} EXPECTATIONS: judge correctness, depth, vocabulary, and communication against what a typical Grade ${p.expectationGrade} student is expected to produce. Give full credit for work that meets the Grade ${p.expectationGrade} bar and deduct when it falls below it — do not demand more than that grade's curriculum expects, and do not give a pass for work well below it.`,
    );
  }
  if (p.includeTranscription) {
    lines.push(`- Transcribe the student's visible work from ALL pages into rawText, keeping question numbers/labels and marking page boundaries like "--- Page 2 ---".`);
  }
  return lines.join("\n");
}

// ---------- Normalization (shared by both providers) ----------

function clamp(n: unknown, min: number, max: number, fallback: number): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  return Math.max(min, Math.min(max, v));
}

function levelFromPercentage(pct: number): { level: number | null; levelDisplay: string } {
  if (pct >= 95) return { level: 4, levelDisplay: "Level 4+ (95–100%)" };
  if (pct >= 80) return { level: 4, levelDisplay: "Level 4 (80–94%)" };
  if (pct >= 70) return { level: 3, levelDisplay: "Level 3 (70–79%)" };
  if (pct >= 60) return { level: 2, levelDisplay: "Level 2 (60–69%)" };
  if (pct >= 50) return { level: 1, levelDisplay: "Level 1 (50–59%)" };
  return { level: null, levelDisplay: "Below Level 1 (<50%)" };
}

const KTCA_NAMES = ["Knowledge", "Thinking", "Communication", "Application"];

// deno-lint-ignore no-explicit-any
function normalize(obj: any, provider: string, maxScoreDefault: number, formatOverride?: string, stats?: CodeUse[], expectationGrade?: number | null) {
  const maxScore = clamp(obj?.maxScore, 1, 10000, maxScoreDefault);
  const rawScore = clamp(obj?.rawScore, 0, maxScore, 0);
  const percentage = clamp(obj?.percentage, 0, 100, Math.round((rawScore / maxScore) * 100));
  const { level, levelDisplay } = levelFromPercentage(percentage);

  const detectedGrade = Number.isFinite(Number(obj?.detectedGrade)) ? Math.round(Number(obj.detectedGrade)) : null;
  // Grades 1–8 always report on the Level 1–4(+) scale (teacher override wins).
  const effectiveGrade = expectationGrade ?? detectedGrade;
  const forceLevels = effectiveGrade != null && effectiveGrade >= 1 && effectiveGrade <= 8;
  const gradingFormat = formatOverride === "levels" || formatOverride === "percentage"
    ? formatOverride
    : (forceLevels || obj?.gradingFormat === "levels" ? "levels" : "percentage");

  // deno-lint-ignore no-explicit-any
  const asStringArray = (v: unknown) => (Array.isArray(v) ? v.filter((x: any) => typeof x === "string") : []);

  // deno-lint-ignore no-explicit-any
  const criteriaBreakdown = (Array.isArray(obj?.criteriaBreakdown) ? obj.criteriaBreakdown : []).map((c: any) => ({
    name: String(c?.name ?? ""),
    score: clamp(c?.score, 0, 10000, 0),
    maxScore: clamp(c?.maxScore, 1, 10000, 10),
    level: Number.isFinite(Number(c?.level)) ? Math.round(Number(c.level)) : null,
    feedback: expandFeedback(String(c?.feedback ?? ""), "criteria", CRITERIA_BANK, stats),
  }));

  // The KTCA category line is built here from the structured scores instead of
  // being written (and paid for) as model output.
  let summary = String(obj?.summary ?? "");
  // deno-lint-ignore no-explicit-any
  const ktca = criteriaBreakdown.filter((c: any) => KTCA_NAMES.includes(c.name));
  if (ktca.length > 0) {
    // deno-lint-ignore no-explicit-any
    const line = ktca.map((c: any) => `${c.name} ${c.score}/${c.maxScore}`).join(", ");
    summary = summary ? `${summary.replace(/\s+$/, "")} ${line}.` : `${line}.`;
  }

  return {
    provider,
    detectedSubject: String(obj?.detectedSubject ?? ""),
    detectedGrade,
    studentNameOnPaper: typeof obj?.studentNameOnPaper === "string" && obj.studentNameOnPaper.trim().length > 0
      ? obj.studentNameOnPaper.trim()
      : null,
    assignmentKind: String(obj?.assignmentKind ?? ""),
    markingStyle: obj?.markingStyle === "completion" ? "completion" : "graded",
    gradingFormat,
    rawScore,
    maxScore,
    percentage,
    percentageDisplay: `${Math.round(percentage)}%`,
    level,
    levelDisplay,
    summary,
    strengths: asStringArray(obj?.strengths).map((s: string) => expandFeedback(s, "strength", STRENGTH_BANK, stats)),
    improvements: asStringArray(obj?.improvements).map((s: string) => expandFeedback(s, "improvement", IMPROVEMENT_BANK, stats)),
    criteriaBreakdown,
    // deno-lint-ignore no-explicit-any
    annotations: (Array.isArray(obj?.annotations) ? obj.annotations : []).map((a: any) => ({
      questionLabel: String(a?.questionLabel ?? ""),
      earnedMark: String(a?.earnedMark ?? ""),
      outOfMark: String(a?.outOfMark ?? ""),
      correct: a?.correct === true,
      feedback: expandFeedback(String(a?.feedback ?? ""), "annotation", ANNOTATION_BANK, stats),
      pageIndex: Math.round(clamp(a?.pageIndex, 0, 999, 0)),
      positionTop: clamp(a?.positionTop, 0, 1, 0.1),
      positionLeft: clamp(a?.positionLeft, 0, 1, 0.1),
    })),
    rawText: String(obj?.rawText ?? ""),
  };
}

// ---------- Response cache (zero-token repeat grades) ----------

async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function contentHash(obj: unknown): Promise<string> {
  return sha256Hex(JSON.stringify(obj));
}

// deno-lint-ignore no-explicit-any
async function cacheRead(hash: string): Promise<{ provider: string; raw: any; image_hashes?: unknown } | null> {
  try {
    const { data, error } = await serviceDb()
      .from("grade_cache")
      .select("provider, raw, image_hashes")
      .eq("content_hash", hash)
      .maybeSingle();
    if (error) throw error;
    return data ?? null;
  } catch (e) {
    console.error("grade_cache read failed (run SETUP-DB?):", e instanceof Error ? e.message : e);
    return null;
  }
}

// deno-lint-ignore no-explicit-any
async function cacheWrite(hash: string, provider: string, raw: any, imageHashes: string[]): Promise<void> {
  try {
    const { error } = await serviceDb()
      .from("grade_cache")
      .upsert({ content_hash: hash, provider, raw, image_hashes: imageHashes });
    if (error) throw error;
  } catch (e) {
    console.error("grade_cache write failed (run SETUP-DB?):", e instanceof Error ? e.message : e);
  }
}

// The cache key uses SORTED per-image hashes, so the same pages scanned in a
// different order still hit. But page order matters to the result (each
// annotation carries a pageIndex), so on a hit we translate the cached
// submission's page order into this request's order. Returns null when the
// orders already agree or a clean bijection can't be built (then the cache
// entry is only usable as-is when the order matched, which the key guarantees
// for identical multisets — a null from mismatched lengths means legacy data).
function pageIndexMap(cachedHashes: string[], currentHashes: string[]): Record<number, number> | null {
  if (cachedHashes.length !== currentHashes.length || cachedHashes.length === 0) return null;
  const unused = currentHashes.map((h, i) => ({ h, i }));
  const map: Record<number, number> = {};
  let identity = true;
  for (let old = 0; old < cachedHashes.length; old++) {
    const slot = unused.findIndex((u) => u.h === cachedHashes[old]);
    if (slot === -1) return null;
    map[old] = unused[slot].i;
    if (unused[slot].i !== old) identity = false;
    unused.splice(slot, 1);
  }
  return identity ? null : map;
}

// ---------- Feedback code analytics ----------
//
// Every fresh grade logs which sentence codes the model used (and any unknown
// codes or free-text escapes). Query it to see which banks need more options:
//   select bank, code, kind, count(*) from feedback_code_usage
//   group by 1, 2, 3 order by count desc;
// Codes that never appear in the table are dead weight and can be reworded.
async function logCodeUsage(stats: CodeUse[]): Promise<void> {
  if (stats.length === 0) return;
  const counts = new Map<string, number>();
  for (const s of stats) {
    const k = `${s.bank} ${s.code}`;
    counts.set(k, (counts.get(k) ?? 0) + 1);
  }
  console.log("feedback code usage:", [...counts.entries()].map(([k, n]) => `${k}×${n}`).join(", "));
  try {
    const { error } = await serviceDb()
      .from("feedback_code_usage")
      .insert(stats.map((s) => ({ bank: s.bank, code: s.code, kind: s.kind })));
    if (error) throw error;
  } catch (e) {
    console.error("feedback_code_usage write failed (run SETUP-DB?):", e instanceof Error ? e.message : e);
  }
}

// ---------- Providers ----------

async function callClaude(imagesBase64: string[], mediaType: string, o: {
  // deno-lint-ignore no-explicit-any
  systemBlocks?: any[];
  userText: string;
  // deno-lint-ignore no-explicit-any
  schema: any;
}) {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("Missing ANTHROPIC_API_KEY secret");

  // deno-lint-ignore no-explicit-any
  const content: any[] = [];
  imagesBase64.forEach((img, i) => {
    content.push({ type: "text", text: `Page ${i + 1} of ${imagesBase64.length}:` });
    content.push({ type: "image", source: { type: "base64", media_type: mediaType, data: img } });
  });
  content.push({ type: "text", text: o.userText });

  const anthropic = new Anthropic({ apiKey });
  const response = await anthropic.messages.create({
    model: "claude-opus-4-8",
    max_tokens: 16000,
    thinking: { type: "adaptive" },
    // "medium" keeps grading well inside the edge-function time limit;
    // raise to "high" if you can tolerate slower, deeper marking.
    output_config: {
      effort: "medium",
      format: { type: "json_schema", schema: o.schema },
    },
    ...(o.systemBlocks ? { system: o.systemBlocks } : {}),
    messages: [{ role: "user", content }],
    // deno-lint-ignore no-explicit-any
  } as any);

  if (response.stop_reason === "refusal") {
    throw new Error("Claude declined to grade this image");
  }
  const text = response.content.find((b) => b.type === "text")?.text ?? "";
  if (!text) throw new Error(`Claude returned no text (stop_reason: ${response.stop_reason})`);
  return JSON.parse(text);
}

function gradeShape(includeTranscription: boolean): string {
  return `\n\nReturn ONLY a single JSON object with exactly these fields and no others:
{
  "detectedSubject": string,
  "detectedGrade": integer or null,
  "studentNameOnPaper": string or null,
  "assignmentKind": string,
  "markingStyle": "completion" or "graded",
  "gradingFormat": "percentage" or "levels",
  "rawScore": number,
  "maxScore": number,
  "percentage": number,
  "summary": string,
  "strengths": string[],
  "improvements": string[],
  "criteriaBreakdown": [{"name": string, "score": number, "maxScore": number, "level": integer or null, "feedback": string}],
  "annotations": [{"questionLabel": string, "earnedMark": string, "outOfMark": string, "correct": boolean, "feedback": string, "pageIndex": integer, "positionTop": number, "positionLeft": number}]${includeTranscription ? `,
  "rawText": string` : ""}
}`;
}

async function callGemini(imagesBase64: string[], mediaType: string, prompt: string, jsonInstruction: string) {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("Missing GEMINI_API_KEY secret");

  // deno-lint-ignore no-explicit-any
  const parts: any[] = [];
  imagesBase64.forEach((img, i) => {
    parts.push({ text: `Page ${i + 1} of ${imagesBase64.length}:` });
    parts.push({ inlineData: { mimeType: mediaType, data: img } });
  });
  parts.push({ text: prompt + jsonInstruction });

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts }],
        generationConfig: {
          responseMimeType: "application/json",
          temperature: 0.2,
          maxOutputTokens: 16384,
        },
      }),
    },
  );

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Gemini request failed (${res.status}): ${body.slice(0, 300)}`);
  }
  const data = await res.json();
  // deno-lint-ignore no-explicit-any
  const text = (data?.candidates?.[0]?.content?.parts ?? [])
    .map((p: any) => p?.text ?? "")
    .join("");
  if (!text) throw new Error("Gemini returned no text");
  // Strip markdown fences if the model added them despite the JSON mime type.
  const cleaned = text.trim().replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  return JSON.parse(cleaned);
}

// ---------- Handler ----------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // deno-lint-ignore no-explicit-any
  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const action = String(payload?.action ?? "grade");

  // ── List saved answer keys ─────────────────────────────────────────
  if (action === "list_keys") {
    const teacherId = String(payload?.teacherId ?? "");
    const { data, error } = await serviceDb()
      .from("answer_keys")
      .select("id, name, subject, total_marks, created_at")
      .eq("teacher_id", teacherId)
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) return json({ error: error.message }, 500);
    return json({ keys: data ?? [] });
  }

  // ── Planning assistant: generate a lesson plan / assignment / quiz ──────
  if (action === "plan") {
    const topic = String(payload?.topic ?? "").trim().slice(0, 600);
    if (!topic) return json({ error: "topic is required" }, 400);
    const kind = String(payload?.kind ?? "lesson plan").trim().slice(0, 40);
    const planGrade = Number.isFinite(Number(payload?.gradeLevel))
      ? Math.round(clamp(payload.gradeLevel, 1, 13, 6))
      : null;
    const subject = String(payload?.subject ?? "").trim().slice(0, 80);
    const planRegion = CURRICULA[String(payload?.region ?? "").trim()];

    const prompt = `You are an expert teacher's planning assistant. Create a ${kind} for the request below — complete and classroom-ready, so the teacher can use it as-is.
${planGrade ? `Grade level: ${planGrade} — target that grade's expectations and difficulty.` : ""}
${subject ? `Subject: ${subject}.` : ""}
${planRegion ? `Curriculum: ${planRegion.label}. ${planRegion.notes}` : ""}

Request: ${topic}

Rules:
- title: short and specific.
- content: the full ${kind} with clear section headings.
- Lesson plans include: learning goals, materials, a timed flow (minds-on, action, consolidation), differentiation, and a quick check for understanding.
- Assignments, quizzes, and worksheets include: numbered questions with marks per question, the total marks, and a complete ANSWER KEY section at the end.
- Match everything to the grade level; keep it practical, no filler.`;

    // deno-lint-ignore no-explicit-any
    let raw: any = null;
    const errs: string[] = [];
    try {
      raw = await callClaude([], "image/jpeg", { userText: prompt, schema: PLAN_SCHEMA });
    } catch (e) {
      errs.push(`claude: ${e instanceof Error ? e.message : e}`);
      try {
        raw = await callGemini([], "image/jpeg", prompt, PLAN_SHAPE);
      } catch (e2) {
        errs.push(`gemini: ${e2 instanceof Error ? e2.message : e2}`);
        return json({ error: "Planning failed", details: errs }, 502);
      }
    }
    return json({
      title: String(raw?.title ?? "Untitled plan"),
      content: String(raw?.content ?? ""),
    });
  }

  // ── School-name autocomplete while typing (text-only, no images) ───────
  if (action === "suggest_schools") {
    const query = String(payload?.query ?? "").trim().slice(0, 80);
    if (query.length < 3) return json({ schools: [] });
    const prompt = `A teacher is typing their school's name into a form. The text so far: "${query}".
List up to 5 plausible FULL names of real North American K-12 schools that start with or contain that text (e.g. "Riverdale High School", "Riverside Secondary School"). Prefer common/well-known school names; return fewer (or none) rather than inventing improbable ones. Names only.`;
    try {
      const raw = await callClaude([], "image/jpeg", { userText: prompt, schema: SCHOOL_SUGGEST_SCHEMA });
      const schools = (Array.isArray(raw?.schools) ? raw.schools : [])
        // deno-lint-ignore no-explicit-any
        .map((s: any) => String(s ?? "").trim())
        .filter((s: string) => s.length > 0)
        .slice(0, 5);
      return json({ schools });
    } catch (e) {
      console.error("suggest_schools failed:", e instanceof Error ? e.message : e);
      return json({ schools: [] });
    }
  }

  // ── Infer curriculum region from the school name (text-only, no images) ──
  // Returns one candidate when confident; several when schools with that
  // name exist in multiple regions (the app shows the place in brackets).
  if (action === "infer_region") {
    const school = String(payload?.school ?? "").trim().slice(0, 120);
    if (!school) return json({ error: "school is required" }, 400);
    const prompt = `A teacher teaches at a school named "${school}" somewhere in North America. From the school's name (including any city, district, or board words in it), decide which province or state it is most likely in. Return ONE candidate when reasonably confident; return up to 3 candidates when schools with this name plausibly exist in multiple regions. Each candidate needs regionId (a curriculum region code) and place (a short human label like "Toronto, Ontario" or "Miami, Florida").
Region codes: ${Object.entries(CURRICULA).map(([id, c]) => `${id}=${c.label}`).join("; ")}; other=unknown or outside North America.`;
    try {
      const raw = await callClaude([], "image/jpeg", { userText: prompt, schema: REGION_INFER_SCHEMA });
      const candidates = (Array.isArray(raw?.candidates) ? raw.candidates : [])
        // deno-lint-ignore no-explicit-any
        .map((c: any) => ({ regionId: String(c?.regionId ?? ""), place: String(c?.place ?? "") }))
        // deno-lint-ignore no-explicit-any
        .filter((c: any) => c.regionId === "other" || CURRICULA[c.regionId])
        .slice(0, 3)
        // deno-lint-ignore no-explicit-any
        .map((c: any) => ({
          ...c,
          label: c.regionId === "other" ? "Other / International" : CURRICULA[c.regionId].label,
        }));
      return json({ candidates });
    } catch (e) {
      return json({ error: `Region inference failed: ${e instanceof Error ? e.message : e}` }, 502);
    }
  }

  // deno-lint-ignore no-explicit-any
  const imagesBase64: string[] = (Array.isArray(payload?.imagesBase64) ? payload.imagesBase64 : [])
    .map((s: any) => String(s ?? ""))
    .filter((s: string) => s.length > 0);
  if (imagesBase64.length === 0) {
    const single = String(payload?.imageBase64 ?? "");
    if (single) imagesBase64.push(single);
  }
  if (imagesBase64.length === 0) return json({ error: "imagesBase64 (or imageBase64) is required" }, 400);
  const mediaType = String(payload?.mediaType || "image/jpeg");

  // ── One-time answer key extraction (stored, then reused on grades) ──
  if (action === "extract_key") {
    const teacherId = String(payload?.teacherId ?? "");
    // deno-lint-ignore no-explicit-any
    let raw: any = null;
    const errs: string[] = [];
    try {
      raw = await callClaude(imagesBase64, mediaType, { userText: KEY_PROMPT, schema: KEY_SCHEMA });
    } catch (e) {
      errs.push(`claude: ${e instanceof Error ? e.message : e}`);
      try {
        raw = await callGemini(imagesBase64, mediaType, KEY_PROMPT, KEY_SHAPE);
      } catch (e2) {
        errs.push(`gemini: ${e2 instanceof Error ? e2.message : e2}`);
        return json({ error: "Answer key extraction failed", details: errs }, 502);
      }
    }
    const keyName = String(raw?.name ?? "Answer key");
    const questions = Array.isArray(raw?.questions) ? raw.questions : [];
    const { data, error } = await serviceDb()
      .from("answer_keys")
      .insert({
        teacher_id: teacherId,
        name: keyName,
        subject: raw?.subject ? String(raw.subject) : null,
        total_marks: Number.isFinite(Number(raw?.totalMarks)) ? Number(raw.totalMarks) : null,
        key_json: raw,
      })
      .select("id")
      .single();
    if (error) return json({ error: `Could not save key: ${error.message}` }, 500);
    return json({
      id: data.id,
      name: keyName,
      subject: raw?.subject ?? null,
      totalMarks: raw?.totalMarks ?? null,
      questionCount: questions.length,
    });
  }

  // ── Roster extraction (onboarding: attendance photo → student names) ──
  if (action === "extract_roster") {
    // deno-lint-ignore no-explicit-any
    let raw: any = null;
    const errs: string[] = [];
    try {
      raw = await callClaude(imagesBase64, mediaType, { userText: ROSTER_PROMPT, schema: ROSTER_SCHEMA });
    } catch (e) {
      errs.push(`claude: ${e instanceof Error ? e.message : e}`);
      try {
        raw = await callGemini(imagesBase64, mediaType, ROSTER_PROMPT, ROSTER_SHAPE);
      } catch (e2) {
        errs.push(`gemini: ${e2 instanceof Error ? e2.message : e2}`);
        return json({ error: "Roster extraction failed", details: errs }, 502);
      }
    }
    // deno-lint-ignore no-explicit-any
    const students = (Array.isArray(raw?.students) ? raw.students : [])
      // deno-lint-ignore no-explicit-any
      .map((s: any) => ({
        name: String(s?.name ?? "").trim(),
        studentId: typeof s?.studentId === "string" && s.studentId.trim().length > 0 ? s.studentId.trim() : null,
      }))
      // deno-lint-ignore no-explicit-any
      .filter((s: any) => s.name.length > 0);
    return json({ students });
  }

  const mode = String(payload?.mode || "homework");
  const maxScore = Math.round(clamp(payload?.maxScore, 1, 10000, 100));
  const harshness = Math.round(clamp(payload?.harshness, 1, 10, 5));
  // deno-lint-ignore no-explicit-any
  const criteria = (Array.isArray(payload?.criteria) ? payload.criteria : [])
    .map((c: any) => String(c?.name ?? c ?? "").trim())
    .filter((s: string) => s.length > 0);
  const formatOverride = payload?.formatOverride ? String(payload.formatOverride) : undefined;
  const includeTranscription = payload?.includeTranscription === true;
  const studentGrade = Number.isFinite(Number(payload?.studentGrade)) ? Number(payload.studentGrade) : null;
  // Grade level (1–12) whose curriculum expectations the work is marked against.
  const expectationGrade = Number.isFinite(Number(payload?.expectationGrade))
    ? Math.round(clamp(payload.expectationGrade, 1, 13, 6))
    : null;
  // Curriculum region (e.g. "ca-on", "us-fl") — anchors expectations to the
  // teacher's provincial/state curriculum.
  const region = String(payload?.region ?? "").trim();
  const regionText = region ? regionBlock(region) : null;
  // "Teach the AI" — standing corrections this teacher has saved about how
  // to mark. Capped so a runaway list can't blow up the prompt.
  const teacherFeedback: string[] = (Array.isArray(payload?.teacherFeedback) ? payload.teacherFeedback : [])
    // deno-lint-ignore no-explicit-any
    .map((s: any) => String(s ?? "").trim())
    .filter((s: string) => s.length > 0)
    .map((s: string) => s.slice(0, 300))
    .slice(0, 20);
  const feedbackText = teacherFeedback.length > 0
    ? `TEACHER MARKING PREFERENCES — standing corrections this teacher has given about how to mark. Follow each one whenever it applies; they override default marking style but NEVER override the OFFICIAL ANSWER KEY:\n${teacherFeedback.map((s) => `- ${s}`).join("\n")}`
    : null;

  // ── Response cache: same images + same grading settings → stored result.
  // formatOverride is applied in normalize(), and studentName never affects
  // the marks, so both are left out of the key — a format toggle or a name
  // correction re-uses the cached model output at zero AI cost. Image hashes
  // are sorted so the same pages scanned in a different order still hit;
  // pageIndexMap() then fixes up annotation pages on the way out.
  const answerKeyId = String(payload?.answerKeyId ?? "").trim();
  const imageHashes = await Promise.all(imagesBase64.map(sha256Hex));
  const cacheKey = await contentHash({
    v: CACHE_VERSION,
    sortedImageHashes: [...imageHashes].sort(),
    mediaType,
    mode,
    maxScore,
    harshness,
    criteria,
    answerKeyId,
    studentGrade,
    expectationGrade,
    region,
    teacherFeedback,
    includeTranscription,
  });
  const hit = await cacheRead(cacheKey);
  if (hit) {
    const normalized = normalize(hit.raw, hit.provider, maxScore, formatOverride, undefined, expectationGrade);
    const cachedOrder = Array.isArray(hit.image_hashes) ? hit.image_hashes.map(String) : [];
    const map = pageIndexMap(cachedOrder, imageHashes);
    if (map) {
      normalized.annotations = normalized.annotations.map((a) => ({
        ...a,
        pageIndex: map[a.pageIndex] ?? a.pageIndex,
      }));
    }
    return json({ ...normalized, cached: true });
  }

  // Pull the stored answer key when one was chosen — the key was analyzed
  // once at save time, so grading only pays for its compact text.
  // deno-lint-ignore no-explicit-any
  let answerKey: any = null;
  if (answerKeyId) {
    const { data } = await serviceDb()
      .from("answer_keys")
      .select("key_json")
      .eq("id", answerKeyId)
      .maybeSingle();
    answerKey = data?.key_json ?? null;
  }

  const contextText = buildContext({
    mode,
    maxScore,
    harshness,
    criteria,
    studentName: payload?.studentName ? String(payload.studentName) : undefined,
    studentGrade,
    expectationGrade,
    pageCount: imagesBase64.length,
    includeTranscription,
  });
  const keyText = answerKey ? `OFFICIAL ANSWER KEY:\n${JSON.stringify(answerKey)}` : null;

  // Static rules, the region's curriculum expectations, and the answer key go
  // in the system prompt with cache breakpoints (rules → region → key, from
  // most-shared to least-shared): every grade re-reads them at ~10% input
  // cost, and grading a whole class against one key shares all three.
  // deno-lint-ignore no-explicit-any
  const systemBlocks: any[] = [
    { type: "text", text: STATIC_SYSTEM, cache_control: { type: "ephemeral", ttl: "1h" } },
  ];
  if (regionText) {
    systemBlocks.push({ type: "text", text: regionText, cache_control: { type: "ephemeral", ttl: "1h" } });
  }
  if (feedbackText) {
    systemBlocks.push({ type: "text", text: feedbackText, cache_control: { type: "ephemeral", ttl: "1h" } });
  }
  // Max 4 cache breakpoints per request — rules + region + feedback + key is
  // exactly 4. Don't add a fifth cached block without merging two of these.
  if (keyText) {
    systemBlocks.push({ type: "text", text: keyText, cache_control: { type: "ephemeral", ttl: "1h" } });
  }

  const schema = gradeSchema(includeTranscription);
  const shape = gradeShape(includeTranscription);
  const geminiPrompt = STATIC_SYSTEM +
    (regionText ? `\n\n${regionText}` : "") +
    (feedbackText ? `\n\n${feedbackText}` : "") +
    (keyText ? `\n\n${keyText}` : "") +
    "\n\n" + contextText;

  // Claude grades by default; Gemini is the fallback (or primary when
  // the request asks for it with "provider": "gemini").
  const preferGemini = String(payload?.provider ?? "").toLowerCase() === "gemini";
  const attempts: Array<"claude" | "gemini"> = preferGemini ? ["gemini", "claude"] : ["claude", "gemini"];

  const errors: string[] = [];
  for (const name of attempts) {
    try {
      const raw = name === "claude"
        ? await callClaude(imagesBase64, mediaType, { systemBlocks, userText: contextText, schema })
        : await callGemini(imagesBase64, mediaType, geminiPrompt, shape);
      await cacheWrite(cacheKey, name, raw, imageHashes);
      const stats: CodeUse[] = [];
      const normalized = normalize(raw, name, maxScore, formatOverride, stats, expectationGrade);
      await logCodeUsage(stats);
      return json({ ...normalized, cached: false });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`${name} grading failed:`, msg);
      errors.push(`${name}: ${msg}`);
    }
  }

  return json({ error: "All AI providers failed", details: errors }, 502);
});
