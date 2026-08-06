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
const CACHE_VERSION = 18;

// A keyless graded mark works out every correct answer anyway — store that
// as a real answer key so the REST of the class marks against it on the
// cheap deterministic route instead of paying the frontier price per paper.
// deno-lint-ignore no-explicit-any
async function maybeStoreLearnedKey(teacherId: string, raw: any): Promise<{ id: string; name: string } | null> {
  try {
    const qs = Array.isArray(raw?.derivedKey) ? raw.derivedKey : [];
    if (qs.length < 2 || !teacherId) return null;
    const subject = String(raw?.detectedSubject ?? "").trim();
    const kind = String(raw?.assignmentKind ?? "test").trim() || "test";
    const name = `Learned key — ${subject ? `${subject} ` : ""}${kind} (${new Date().toISOString().slice(0, 10)})`;
    // deno-lint-ignore no-explicit-any
    const totalMarks = qs.reduce((s: number, q: any) => s + (Number(q?.marks) || 0), 0);
    const keyJson = {
      name,
      subject,
      totalMarks,
      // deno-lint-ignore no-explicit-any
      questions: qs.map((q: any) => ({
        label: String(q?.label ?? ""),
        marks: Number(q?.marks) || 0,
        answer: String(q?.answer ?? ""),
      })),
    };
    const { data, error } = await serviceDb()
      .from("answer_keys")
      .insert({ teacher_id: teacherId, name, subject: subject || null, total_marks: totalMarks || null, key_json: keyJson })
      .select("id")
      .single();
    if (error) throw error;
    return { id: String(data.id), name };
  } catch (e) {
    console.error("learned-key store failed:", e instanceof Error ? e.message : e);
    return null;
  }
}

// Margin labels for annotation codes. Annotations render as tiny bubbles ON
// the page, so a code must never expand into a bank sentence — it maps to a
// 2-3 word label instead. Correct-answer codes map to "" (no bubble at all).
const ANNOTATION_SHORT: Record<number, string> = {
  1: "",
  2: "",
  3: "small slip",
  4: "calculation error",
  5: "missing unit",
  6: "wrong formula",
  7: "no working",
  8: "incomplete",
  9: "misread question",
  10: "sign error",
  11: "rounding error",
  12: "missing label",
  13: "imprecise definition",
  14: "needs detail",
  15: "left blank",
  16: "wrong final answer",
  17: "copying error",
  18: "needs example",
  19: "doesn't answer question",
  20: "partly correct",
};

// Hard cap for free-text annotation labels — the prompt demands 2-4 words,
// this makes sure a disobedient model can never put a sentence on the page.
function capWords(s: string, n: number): string {
  const words = s.replace(/[.,;!?]+$/, "").split(/\s+/).filter(Boolean);
  return words.length <= n ? words.join(" ") : words.slice(0, n).join(" ");
}

function tinyLabel(value: string, stats?: CodeUse[]): string {
  const m = /^#(\d+)(?:[\s:—-]+(.+))?$/.exec(value.trim());
  if (!m) {
    if (value.trim().length > 0) stats?.push({ bank: "annotation", code: "free_text", kind: "free_text" });
    return capWords(value.trim(), 4);
  }
  const short = ANNOTATION_SHORT[Number(m[1])];
  const detail = m[2]?.trim();
  stats?.push({ bank: "annotation", code: `#${m[1]}`, kind: short !== undefined ? "bank" : "unknown" });
  if (short !== undefined) return short;
  return detail ? capWords(detail, 4) : "check this";
}

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
    "criteriaBreakdown", "annotations", "derivedKey",
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
        required: ["questionLabel", "earnedMark", "outOfMark", "correct", "feedback", "methodNote", "pageIndex", "positionTop", "positionLeft"],
        properties: {
          questionLabel: { type: "string" },
          earnedMark: { type: "string" },
          outOfMark: { type: "string" },
          correct: { type: "boolean" },
          feedback: { type: "string" },
          methodNote: { type: "string" },
          pageIndex: { type: "integer" },
          positionTop: { type: "number" },
          positionLeft: { type: "number" },
        },
      },
    },
    derivedKey: {
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
   - "completion" — ONLY for homework and practice worksheets (no printed marks, no answer key). Then rawScore = the number of questions with a genuine attempt, maxScore = the number of questions assigned; a BLANK or untouched question counts as 0 — never credit for empty questions. Do NOT deduct for wrong answers, but still flag wrong answers with annotation codes so the teacher sees them.
   - "graded" — correctness marking, exactly like marking a test: tests, quizzes, essays, lab reports, anything with printed marks, or whenever an OFFICIAL ANSWER KEY is present. When in doubt, choose "graded".
   - Either style: a blank/unanswered question scores 0 for that question, with correct = false and a code noting it was left blank.
   - NEVER mark, deduct for, or comment on neatness, handwriting quality, or presentation — messy-but-correct earns full marks.
3. Create one annotation per question or answer visible across all pages:
   - questionLabel like "Q1", earnedMark like "2", outOfMark like "/4" — when the paper prints a question's marks (e.g. "(2 marks)"), use exactly those marks
   - earnedMark may use QUARTER-STEP decimals ("0.25", "0.5", "1.75"): deduct fractions for minor slips — a missing unit, a sign error, sloppy rounding — instead of taking a whole mark.
   - correct = true only if fully correct
   - feedback: a TINY plain-words error label, 2-4 words max — "wrong formula", "addition mistake", "missing unit", "wrong number", "sign error", "sig figs", "left blank", "skipped a step". NEVER a sentence, never an explanation, never a summary of the question, never a #code here. Fully correct answers get feedback "".
   - methodNote — METHOD CHECK when an OFFICIAL ANSWER KEY is present: if the student's final answer matches the key but their WORKING differs from the key's (a different technique, a more advanced shortcut, steps the key shows are skipped), AWARD the marks per the key and set methodNote to a tiny 2-3 word label — "different method", "advanced method", "steps skipped". Some teachers accept any valid method, others require the taught one — the note lets the teacher decide. methodNote is "" in every other case (no key, wrong answer, matching method). NEVER deduct for method alone unless the key explicitly requires that method.
   - check every numeric final answer for UNITS: if a required unit is missing or wrong, deduct part marks with label "missing unit"
   - QUESTIONS ONLY THE TEACHER CAN MARK: when you cannot reliably judge an answer from the pages alone, do NOT guess a mark. Set earnedMark "?", outOfMark from the printed marks, correct = false, and a tiny label saying why. EXCLUDE that question's printed marks from rawScore, maxScore, and its KTCA category totals — the teacher marks it by hand. This applies to:
     * drawings — free-body diagrams, ray diagrams, graphs the student drew, sketches, geometric constructions → feedback "check drawing". Simple diagram READING (taking numbers off a printed graph) is normal marking, not this rule.
     * answers that can only be checked against material NOT in the images and there is NO OFFICIAL ANSWER KEY — listening/écoute or dictation tests (answers depend on audio you cannot hear), questions about a reading passage or source not photographed, oral components → feedback "needs answer key". With an answer key present these mark normally against the key.
     * If EVERY question is teacher-only (e.g. a listening test with no key), still return all annotations with "?" and say why in a one-sentence summary ("Listening test with no answer key — answers can't be checked without the audio.").
   - ESSAY ERROR MARKS: essays, stories, and long written responses have no numbered questions — instead create one annotation per error INSTANCE found in the writing: questionLabel = the section it belongs to ("Grammar", "Spelling", "Flow", "Content"), earnedMark = the deduction as a negative ("-0.5") or "" when it costs nothing, outOfMark = "", correct = false, feedback = a tiny label with the exact fix ("dont → don't", "familys → families", "run-on sentence", "costs — agreement"), position ON the error word. CATALOGUE EVERYTHING: every missing apostrophe (contractions AND possessives), every homophone (close/clothes, to/too, there/their), every subject-verb agreement slip, every misspelling, every missing word — a sample is NOT marking. When the SAME error repeats ("familys" four times, an identical phrase reused), still mark every occurrence on the page but treat it as ONE recurring pattern when deducting.
   - TEXT POSITIONING (LINE METHOD): for errors in written text, count the text lines visible on the page; positionTop ≈ (the error's line number − 0.5) ÷ total lines; positionLeft ≈ how far along that line the word sits (0.1 = start of the line, 0.9 = end). The highlight must land on the exact word — never between paragraphs, never in the margin.
   - pageIndex: which page the answer is on, 0-based (Page 1 = 0, Page 2 = 1, ...)
   - positionTop and positionLeft: land ON the specific wrong number, expression, or step itself — never the question header, never a subtotal, never the general question area. When the answer is fully correct, point at the final answer. Fractions of the image height/width between 0.0 and 1.0 (0.0 = top/left edge).
4. criteriaBreakdown must normally be EMPTY — marking is right-or-wrong per question, nothing else. Include entries ONLY in exactly three cases:
   - KTCA sections: the paper's own sections are labeled with the Ontario categories (rule 6) — those category entries COUNT toward the mark.
   - Printed rubric: the pages (or the ANSWER KEY) include a rubric — mark each rubric criterion with a level 1-4 exactly as the rubric defines, choose gradingFormat "levels", overall level from the rubric average.
   - ESSAYS/STORIES/WRITTEN RESPONSES with no printed rubric: break the total into exactly these marks-bearing sections — "Content & Ideas" (~30% of maxScore), "Evidence & Development" (~20%), "Organization & Flow" (~20%), "Grammar" (~15%), "Spelling & Mechanics" (~15%). Section scores sum to rawScore, section maxScores sum to maxScore. Score each section from ITS OWN evidence only: sloppy mechanics must never drag down Content/Evidence, and a strong argument must never hide weak conventions — a competent argument buried under surface errors scores high on Content and low on Mechanics. CREDIT real skills where shown: acknowledging then rebutting a counterargument, varied transitions, a concrete developed example. Deduct recurring error patterns ONCE, not per instance. Each section's feedback cites concrete evidence and names recurring patterns ("recurring: familys → families ×4", "reasons asserted, never illustrated — no example or number anywhere", "counterargument acknowledged and rebutted — credited") — never a generic comment.
   NEVER invent criteria ("Attempted all questions", "Effort", "Neatness", "Organization", "Working shown", ...). "Communication" is a criterion ONLY when a rubric or a KTCA section defines it — otherwise communication slips (missing units, missing sig figs, wrong rounding or decimal places) are PART-MARK DEDUCTIONS (quarter-steps, rule 3) on the question where they occur, never a separate criterion or comment section.
5. Compute maxScore and rawScore for the whole submission:
   - When markingStyle is "completion", rawScore and maxScore count completed vs assigned questions (see rule 2) — the rules below apply to "graded" work.
   - If the paper prints marks per question (e.g. "(2 marks)", "/4"), maxScore = the TOTAL of the printed marks of the questions VISIBLE in the images, and rawScore = the marks the student earned on those questions. Questions marked "?" as teacher-only (rule 3) are excluded from BOTH totals.
   - Only if the paper shows no marks at all, use the fallback total marks from CONTEXT.
   - Grade ONLY what is visible. NEVER deduct for questions, sections, or pages that are not in the images — treat the visible pages as the entire submission. If everything visible is fully correct, the score must be full marks.
   - percentage must equal rawScore / maxScore * 100 (rounded is fine).
6. Ontario/Canadian KTCA marking: many Canadian tests divide their sections into the Ontario achievement categories — Knowledge/Understanding, Thinking/Inquiry, Communication, Application (e.g. "Part A – Knowledge Questions (10 marks)", "Part D – Application Questions (10 marks)"). If the visible sections are labeled with these categories:
   - A question counts ONLY toward the category of the section it appears in.
   - questionLabel for annotations in KTCA sections uses the CATEGORY name instead of "Q1": "Knowledge 1", "Thinking 2" — or just "Thinking" when that section has a single question. The teacher must see the category at a glance on every mark.
   - Score each visible category separately: marks earned on that section's visible questions out of that section's visible printed marks.
   - Put one entry per visible category FIRST in criteriaBreakdown, named exactly "Knowledge", "Thinking", "Communication", or "Application" (only the categories actually visible), with that category's marks and a feedback code. Any requested criteria follow after as feedback-only entries.
   - The category entry's feedback must JUSTIFY lost marks concretely — name the questions and the reason ("#6 units missing K2, C1", or free text like "no justification shown C2; sig figs C3"). Never a generic comment: a teacher reading "Communication 6/8" must see exactly where the 2 marks went.
   - The overall percentage = the AVERAGE of the visible category percentages, each category weighted equally (this is how KTCA works — NOT total marks divided by total marks). rawScore and maxScore still report the total visible marks earned and available.
   - If the paper's sections are not labeled with KTCA categories, skip this rule and use percentage = rawScore / maxScore * 100.
7. Choose gradingFormat: "levels" for work at Grades 1-8 (see GRADE-LEVEL EXPECTATIONS below) and for essays, lab reports, and rubric-style work; "percentage" for Grades 9-13 tests, quizzes, and homework.
8. For graded tests/quizzes: summary is AT MOST 1 short sentence, and strengths and improvements are EMPTY arrays — the per-question marks ARE the feedback. For all other work: summary at most 2 short sentences addressed to the teacher (no per-question details, no KTCA scores — those are appended automatically), with 2-4 strengths and 2-4 improvements as feedback codes.

9. LEARN THE KEY: when marking GRADED work with NO official answer key present, also fill derivedKey — one entry per question with its label, its printed marks, and the correct answer you worked out while marking (final answer with required units and common acceptable alternates, COMPACT — no working, no explanation). Skip teacher-only "?" questions. When an OFFICIAL ANSWER KEY is present, or markingStyle is "completion", derivedKey MUST be [].

GRADE-LEVEL EXPECTATIONS — mark at the grade level given in CONTEXT when present; otherwise mark at the grade level you detected from the work itself. For work at Grades 1-8, report on the elementary Level scale by choosing gradingFormat "levels": Level 3 = meeting grade expectations, Level 4 = exceeding them, Level 4+ = outstanding. Percentages still back the levels, so compute rawScore/maxScore/percentage as usual.

FEEDBACK CODES — to keep responses compact, every feedback string in criteriaBreakdown.feedback and each entry of strengths and improvements MUST be a code: write "#N" or "#N detail", where detail is 1-4 words that fill the {X} slot or add specifics. Only write a free-text sentence when no code fits. (annotations.feedback is the exception — it uses tiny plain-words labels per rule 3, never codes.)
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
      feedback: tinyLabel(String(a?.feedback ?? ""), stats),
      methodNote: capWords(String(a?.methodNote ?? "").trim(), 4),
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
  // Out-param: billable token equivalents for this call (cache reads count
  // at 10%, cache writes at 125%) so the caller can meter spend.
  usage?: { inputTokens: number; outputTokens: number };
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
    // Sonnet-class: ~5x cheaper than Opus with near-equal marking quality
    // against an answer key — this single choice is what makes the $19.99
    // pricing profitable. Revisit routing (cheaper objective tier, premium
    // essay tier) when more provider keys are configured.
    model: "claude-sonnet-5",
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
  if (o.usage) {
    // deno-lint-ignore no-explicit-any
    const u = (response as any).usage ?? {};
    o.usage.inputTokens = (u.input_tokens ?? 0) +
      (u.cache_read_input_tokens ?? 0) * 0.1 +
      (u.cache_creation_input_tokens ?? 0) * 1.25;
    o.usage.outputTokens = u.output_tokens ?? 0;
  }
  const text = response.content.find((b) => b.type === "text")?.text ?? "";
  if (!text) throw new Error(`Claude returned no text (stop_reason: ${response.stop_reason})`);
  return JSON.parse(text);
}

// ---------- Usage metering & per-teacher spend caps ----------
//
// Every model call is logged with its billable tokens; the gates below keep
// any single account inside a hard monthly budget with daily/weekly pacing
// so one teacher can't quietly blow the API bill. Cache hits are free and
// never gated. Checks fail OPEN: an error in metering never blocks marking.
// Sonnet-class standard pricing (post-Sep 2026 rates, so the meter doesn't
// under-count once the intro pricing ends).
const PRICE_IN_PER_M = 3; // USD per 1M input tokens
const PRICE_OUT_PER_M = 15; // USD per 1M output tokens

// ---------- Plans & marking-credit caps ----------
// Credits are COST-WEIGHTED (real billed spend), not mark counts: a 2-page
// multiple-choice quiz uses far fewer credits than a 6-page problem set.
// The app only ever shows percentages. Cache hits are free. Daily pacing =
// 25% of the month, weekly = 50%, so a test day fits but the month lasts.
// Budgets ≈ old mark caps × typical cost/mark.
const PLAN_CAPS: Record<string, { monthlyUsd: number; plans: number; label: string }> = {
  trial: { monthlyUsd: 0.75, plans: 5, label: "Free Trial" },
  starter: { monthlyUsd: 3.0, plans: 10, label: "Starter" },
  pro: { monthlyUsd: 10.0, plans: 30, label: "Pro" },
  school: { monthlyUsd: 22.5, plans: 60, label: "School" },
  // Pre-launch preview accounts get Pro-level room.
  preview: { monthlyUsd: 10.0, plans: 30, label: "Preview" },
};

async function planFor(teacherId: string): Promise<keyof typeof PLAN_CAPS> {
  try {
    const { data } = await serviceDb().from("profiles").select("plan").eq("teacher_id", teacherId).maybeSingle();
    const p = String(data?.plan ?? "").trim().toLowerCase();
    return (p in PLAN_CAPS ? p : "preview") as keyof typeof PLAN_CAPS;
  } catch {
    return "preview";
  }
}

// Referral loop: every colleague who joined with this teacher's code AND is
// currently on a PAID plan adds bonus marking credits to the monthly cap —
// the reward is the thing teachers run out of, and it can't be farmed with
// free accounts because unpaid referrals add nothing.
const REFERRAL_BONUS_USD = 0.65; // ≈ 25 typical marks of credits
const PAID_PLANS = ["starter", "pro", "school"];

async function paidReferralCount(teacherId: string): Promise<number> {
  try {
    const { count, error } = await serviceDb()
      .from("profiles")
      .select("teacher_id", { count: "exact", head: true })
      .eq("referred_by", teacherId)
      .in("plan", PAID_PLANS);
    if (error) throw error;
    return count ?? 0;
  } catch {
    return 0;
  }
}

async function logUsage(
  teacherId: string,
  action: string,
  inputTokens: number,
  outputTokens: number,
  priceInPerM: number = PRICE_IN_PER_M,
  priceOutPerM: number = PRICE_OUT_PER_M,
): Promise<void> {
  if (!teacherId) return;
  try {
    const { error } = await serviceDb().from("usage_log").insert({
      teacher_id: teacherId,
      action,
      input_tokens: Math.round(inputTokens),
      output_tokens: Math.round(outputTokens),
      cost_usd: (inputTokens * priceInPerM) / 1e6 + (outputTokens * priceOutPerM) / 1e6,
    });
    if (error) throw error;
  } catch (e) {
    console.error("usage_log write failed (run SETUP-DB?):", e instanceof Error ? e.message : e);
  }
}

function periodStarts(): { day: string; week: string; month: string } {
  const now = new Date();
  return {
    day: new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())).toISOString(),
    week: new Date(now.getTime() - 7 * 86400_000).toISOString(),
    month: new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString(),
  };
}

async function countSince(teacherId: string, action: string, sinceIso: string): Promise<number> {
  const { count, error } = await serviceDb()
    .from("usage_log")
    .select("id", { count: "exact", head: true })
    .eq("teacher_id", teacherId)
    .eq("action", action)
    .gte("created_at", sinceIso);
  if (error) throw error;
  return count ?? 0;
}

async function spendSince(teacherId: string, sinceIso: string): Promise<number> {
  const { data, error } = await serviceDb()
    .from("usage_log")
    .select("cost_usd")
    .eq("teacher_id", teacherId)
    .gte("created_at", sinceIso);
  if (error) throw error;
  // deno-lint-ignore no-explicit-any
  return (data ?? []).reduce((s: number, r: any) => s + Number(r.cost_usd ?? 0), 0);
}

/// Null when within the plan's caps; otherwise the 429 response to return.
async function budgetGate(teacherId: string, pacing: boolean): Promise<Response | null> {
  if (!teacherId) return null;
  try {
    const plan = await planFor(teacherId);
    const caps = PLAN_CAPS[plan];
    const p = periodStarts();
    const [day, week, month, paidRefs] = await Promise.all([
      spendSince(teacherId, p.day),
      spendSince(teacherId, p.week),
      spendSince(teacherId, p.month),
      paidReferralCount(teacherId),
    ]);
    const monthlyCap = caps.monthlyUsd + paidRefs * REFERRAL_BONUS_USD;
    const block = (scope: string, message: string): Response =>
      json({ error: "usage_limit", scope, plan, message }, 429);
    if (month >= monthlyCap) {
      return block("monthly", `You've used 100% of this month's marking credits (${caps.label} plan). They reset on the 1st — upgrade for more, or invite colleagues: every paid referral adds bonus credits monthly.`);
    }
    if (pacing && week >= monthlyCap * 0.5) {
      return block("weekly", `You've used this week's share of marking credits (50% of the month). It frees up as the week rolls on — or upgrade for more headroom.`);
    }
    if (pacing && day >= monthlyCap * 0.25) {
      return block("daily", `You've used today's share of marking credits (25% of the month). It resets tomorrow — or upgrade for more headroom.`);
    }
    return null;
  } catch (e) {
    console.error("budget check failed:", e instanceof Error ? e.message : e);
    return null;
  }
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
  "annotations": [{"questionLabel": string, "earnedMark": string, "outOfMark": string, "correct": boolean, "feedback": string, "methodNote": string, "pageIndex": integer, "positionTop": number, "positionLeft": number}],
  "derivedKey": [{"label": string, "marks": number, "answer": string}]${includeTranscription ? `,
  "rawText": string` : ""}
}`;
}

// ---------- DeepSeek (cheap text-only grader for the objective route) ----------
// OpenAI-compatible API. Text-only: it grades TRANSCRIPTS, never images —
// a vision parse pass supplies what the student wrote.
const DEEPSEEK_PRICE_IN = 0.14; // USD per 1M input tokens
const DEEPSEEK_PRICE_OUT = 0.28; // USD per 1M output tokens
const GEMINI_PARSE_PRICE_IN = 1.5;
const GEMINI_PARSE_PRICE_OUT = 9.0;

async function callDeepSeek(userText: string, usage?: { inputTokens: number; outputTokens: number }) {
  const apiKey = Deno.env.get("DEEPSEEK_API_KEY");
  if (!apiKey) throw new Error("Missing DEEPSEEK_API_KEY secret");
  const res = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model: "deepseek-chat",
      messages: [{ role: "user", content: userText }],
      temperature: 0,
      max_tokens: 4000,
      response_format: { type: "json_object" },
    }),
  });
  if (!res.ok) throw new Error(`DeepSeek ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const data = await res.json();
  if (usage) {
    usage.inputTokens = data?.usage?.prompt_tokens ?? 0;
    usage.outputTokens = data?.usage?.completion_tokens ?? 0;
  }
  const text = data?.choices?.[0]?.message?.content ?? "";
  if (!text) throw new Error("DeepSeek returned no text");
  const cleaned = text.trim().replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  return JSON.parse(cleaned);
}

// Vision parse for the objective route: transcribe only, never judge.
const PARSE_PROMPT =
  `You are a precise transcription engine for photographed school work. Transcribe every question label and EXACTLY what the student wrote for it — do NOT grade, do NOT correct errors, keep the student's wording and numbers verbatim. Record where each answer sits on its page.`;
const PARSE_SHAPE = `\n\nReturn ONLY a single JSON object:
{"studentNameOnPaper": string or null, "detectedSubject": string, "questions": [{"label": string, "pageIndex": integer (0-based), "studentWork": string, "positionTop": number (0-1 fraction of page height), "positionLeft": number (0-1 fraction of page width)}]}`;

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
  if (action === "delete_key") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    const id = String(payload?.id ?? "").trim();
    if (!teacherId || !id) return json({ error: "teacherId and id are required" }, 400);
    const { error } = await serviceDb()
      .from("answer_keys")
      .delete()
      .eq("id", id)
      .eq("teacher_id", teacherId);
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true });
  }

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

  // ── Account profile: saved from onboarding/settings, restored on sign-in
  //    so the same account gets its name/school/region/preferences back on
  //    any device. Upsert only touches the columns present in the payload. ──
  if (action === "save_profile") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    if (!teacherId) return json({ error: "teacherId is required" }, 400);
    const row: Record<string, unknown> = {
      teacher_id: teacherId,
      updated_at: new Date().toISOString(),
    };
    if (payload?.email != null) row.email = String(payload.email).slice(0, 200);
    if (payload?.name != null) row.name = String(payload.name).slice(0, 120);
    if (payload?.school != null) row.school = String(payload.school).slice(0, 200);
    if (payload?.region != null) row.region = String(payload.region).slice(0, 40);
    // Plan comes from the RevenueCat entitlement sync — whitelist so a
    // crafted request can't invent a tier. (Server-side receipt validation
    // via RevenueCat webhooks is the hardening step before launch.)
    if (payload?.plan != null && ["trial", "starter", "pro", "school"].includes(String(payload.plan))) {
      row.plan = String(payload.plan);
    }
    if (Array.isArray(payload?.markingFeedback)) {
      row.marking_feedback = payload.markingFeedback
        .map((f: unknown) => String(f).slice(0, 300))
        .slice(0, 20);
    }
    const { error } = await serviceDb().from("profiles").upsert(row, { onConflict: "teacher_id" });
    if (error) return json({ error: error.message }, 500);
    // Grow the shared school directory: every school a teacher saves
    // becomes an autocomplete suggestion for the next teacher.
    if (typeof row.school === "string" && row.school.length >= 3) {
      await serviceDb()
        .from("schools")
        .upsert({ name: row.school, region: row.region ?? null }, { onConflict: "name", ignoreDuplicates: true });
    }
    return json({ ok: true });
  }

  // ── School directory search: alphabetical, prefix matches first. The
  //    directory is crowd-grown from saved profiles; the AI-based
  //    suggest_schools remains the fallback while it fills in. ──
  if (action === "search_schools") {
    const q = String(payload?.query ?? "").trim().replace(/[%_]/g, "");
    if (q.length < 2) return json({ schools: [] });
    const { data, error } = await serviceDb()
      .from("schools")
      .select("name")
      .ilike("name", `%${q}%`)
      .order("name", { ascending: true })
      .limit(12);
    if (error) return json({ error: error.message }, 500);
    const ql = q.toLowerCase();
    // deno-lint-ignore no-explicit-any
    const names = (data ?? []).map((r: any) => String(r.name));
    names.sort((a, b) => {
      const ap = a.toLowerCase().startsWith(ql) ? 0 : 1;
      const bp = b.toLowerCase().startsWith(ql) ? 0 : 1;
      return ap !== bp ? ap - bp : a.localeCompare(b);
    });
    return json({ schools: names });
  }

  // ── Margin smoke alarm: aggregate unit economics (avg $/mark). Gated by
  //    the ADMIN_STATS_KEY secret — for the founder, not the app. ─────────
  if (action === "admin_stats") {
    const expected = Deno.env.get("ADMIN_STATS_KEY") ?? "";
    if (!expected || String(payload?.adminKey ?? "") !== expected) {
      return json({ error: "Not authorized" }, 403);
    }
    // deno-lint-ignore no-explicit-any
    const summarize = (rows: any[]) => {
      const by: Record<string, { count: number; usd: number }> = {};
      for (const r of rows) {
        const a = String(r.action);
        by[a] = by[a] ?? { count: 0, usd: 0 };
        by[a].count++;
        by[a].usd += Number(r.cost_usd ?? 0);
      }
      const grade = by["grade"] ?? { count: 0, usd: 0 };
      return {
        byAction: Object.fromEntries(Object.entries(by).map(([k, v]) => [k, { count: v.count, usd: Number(v.usd.toFixed(4)) }])),
        avgUsdPerMark: grade.count ? Number((grade.usd / grade.count).toFixed(4)) : null,
        totalUsd: Number(Object.values(by).reduce((s, v) => s + v.usd, 0).toFixed(4)),
      };
    };
    const fetchRows = async (since: string) => {
      const { data, error } = await serviceDb().from("usage_log").select("action, cost_usd").gte("created_at", since);
      if (error) throw error;
      return data ?? [];
    };
    try {
      const [r7, r30] = await Promise.all([
        fetchRows(new Date(Date.now() - 7 * 86400_000).toISOString()),
        fetchRows(new Date(Date.now() - 30 * 86400_000).toISOString()),
      ]);
      return json({ last7Days: summarize(r7), last30Days: summarize(r30) });
    } catch (e) {
      return json({ error: e instanceof Error ? e.message : String(e) }, 500);
    }
  }

  // ── Usage meter for the app's Settings screen ─────────────────────────
  if (action === "get_usage") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    if (!teacherId) return json({ error: "teacherId is required" }, 400);
    try {
      const plan = await planFor(teacherId);
      const caps = PLAN_CAPS[plan];
      const p = periodStarts();
      const [day, week, month, paidRefs] = await Promise.all([
        spendSince(teacherId, p.day),
        spendSince(teacherId, p.week),
        spendSince(teacherId, p.month),
        paidReferralCount(teacherId),
      ]);
      const monthlyCap = caps.monthlyUsd + paidRefs * REFERRAL_BONUS_USD;
      return json({
        plan,
        planLabel: caps.label,
        paidReferrals: paidRefs,
        dayPct: Math.min(100, Math.round((day / (monthlyCap * 0.25)) * 100)),
        weekPct: Math.min(100, Math.round((week / (monthlyCap * 0.5)) * 100)),
        monthPct: Math.min(100, Math.round((month / monthlyCap) * 100)),
      });
    } catch (e) {
      return json({ error: e instanceof Error ? e.message : String(e) }, 500);
    }
  }

  // ── Cloud-saved marked results: they follow the account across sign-ins
  //    and devices instead of living only on one phone. ──────────────────
  if (action === "save_submission") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    const s = payload?.submission;
    if (!teacherId || !s || typeof s !== "object") return json({ error: "teacherId and submission are required" }, 400);
    // deno-lint-ignore no-explicit-any
    const id = String((s as any).id ?? "").trim();
    if (!id) return json({ error: "submission.id is required" }, 400);
    const { error } = await serviceDb()
      .from("submissions_cloud")
      .upsert({ id, teacher_id: teacherId, payload: s, updated_at: new Date().toISOString() });
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true });
  }

  if (action === "delete_submission") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    const id = String(payload?.id ?? "").trim();
    if (!teacherId || !id) return json({ error: "teacherId and id are required" }, 400);
    // teacher_id in the filter so one teacher can never delete another's work.
    const { error } = await serviceDb()
      .from("submissions_cloud")
      .delete()
      .eq("id", id)
      .eq("teacher_id", teacherId);
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true });
  }

  if (action === "list_submissions") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    if (!teacherId) return json({ error: "teacherId is required" }, 400);
    const { data, error } = await serviceDb()
      .from("submissions_cloud")
      .select("payload")
      .eq("teacher_id", teacherId)
      .order("created_at", { ascending: false })
      .limit(500);
    if (error) return json({ error: error.message }, 500);
    // deno-lint-ignore no-explicit-any
    return json({ submissions: (data ?? []).map((r: any) => r.payload) });
  }

  // ── Referrals: each teacher has a share code; referring one teacher
  //    unlocks the planning assistant for the referrer. ──────────────────
  if (action === "get_referral") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    if (!teacherId) return json({ error: "teacherId is required" }, 400);
    const db = serviceDb();
    const { data: prof } = await db
      .from("profiles")
      .select("referral_code, referral_count, email")
      .eq("teacher_id", teacherId)
      .maybeSingle();
    let code = String(prof?.referral_code ?? "");
    if (!code) {
      code = (await sha256Hex("ref:" + teacherId)).slice(0, 6).toUpperCase();
      await db.from("profiles").upsert(
        { teacher_id: teacherId, referral_code: code, updated_at: new Date().toISOString() },
        { onConflict: "teacher_id" },
      );
    }
    const count = Number(prof?.referral_count ?? 0);
    // Founder accounts get Planning without referrals (testing + demos).
    const FOUNDER_EMAILS = ["oscar.cs.lee@gmail.com"];
    const founder =
      FOUNDER_EMAILS.includes(String(prof?.email ?? "").trim().toLowerCase()) ||
      FOUNDER_EMAILS.includes(String(payload?.email ?? "").trim().toLowerCase());
    return json({ code, count, planningUnlocked: count >= 1 || founder });
  }

  if (action === "redeem_referral") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    const code = String(payload?.code ?? "").trim().toUpperCase();
    if (!teacherId || !code) return json({ error: "teacherId and code are required" }, 400);
    const db = serviceDb();
    const { data: owner } = await db
      .from("profiles")
      .select("teacher_id, referral_count")
      .eq("referral_code", code)
      .maybeSingle();
    if (!owner) return json({ error: "That code doesn't exist — double-check it with your colleague." }, 404);
    if (owner.teacher_id === teacherId) return json({ error: "You can't redeem your own code." }, 400);
    const { data: me } = await db
      .from("profiles")
      .select("referred_by")
      .eq("teacher_id", teacherId)
      .maybeSingle();
    if (me?.referred_by) return json({ error: "This account already used a referral code." }, 400);
    await db.from("profiles").upsert(
      { teacher_id: teacherId, referred_by: owner.teacher_id, updated_at: new Date().toISOString() },
      { onConflict: "teacher_id" },
    );
    await db.from("profiles").update({ referral_count: Number(owner.referral_count ?? 0) + 1 }).eq("teacher_id", owner.teacher_id);
    return json({ ok: true });
  }

  if (action === "get_profile") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    if (!teacherId) return json({ error: "teacherId is required" }, 400);
    const { data, error } = await serviceDb()
      .from("profiles")
      .select("teacher_id, email, name, school, region, marking_feedback, updated_at")
      .eq("teacher_id", teacherId)
      .maybeSingle();
    if (error) return json({ error: error.message }, 500);
    return json({ profile: data });
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
    const regionId = String(payload?.region ?? "").trim();
    const planRegion = CURRICULA[regionId];

    // Cross-teacher cache: the same request (normalized) from any teacher
    // is served instantly and costs nothing.
    const planKey = "plan:" + (await sha256Hex(JSON.stringify({
      v: CACHE_VERSION,
      topic: topic.toLowerCase().replace(/\s+/g, " "),
      kind: kind.toLowerCase(),
      grade: planGrade,
      subject: subject.toLowerCase(),
      region: regionId,
    })));
    const hit = await cacheRead(planKey);
    if (hit) {
      return json({
        title: String(hit.raw?.title ?? "Untitled plan"),
        content: String(hit.raw?.content ?? ""),
        cached: true,
      });
    }

    // Fresh plans have their own monthly count per plan tier (cache hits
    // above are free and unlimited).
    const planTeacherId = String(payload?.teacherId ?? "").trim();
    if (planTeacherId) {
      try {
        const tier = await planFor(planTeacherId);
        const caps = PLAN_CAPS[tier];
        const made = await countSince(planTeacherId, "plan", periodStarts().month);
        if (made >= caps.plans) {
          return json({
            error: "usage_limit",
            scope: "monthly",
            plan: tier,
            message: `You've used all ${caps.plans} fresh drafts in your ${caps.label} plan this month — popular topics still come back free from the cache. Upgrade for more.`,
          }, 429);
        }
      } catch (e) {
        console.error("plan gate failed:", e instanceof Error ? e.message : e);
      }
    }

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
- Match everything to the grade level; keep it practical, no filler.

FORMATTING (strict — the app renders plain text, so markdown reads as clutter):
- NO markdown syntax at all: no ** or *, no ## headings, no --- or ___ dividers, no backticks, no | tables.
- Section headings go on their own line in Title Case ending with a colon, e.g. "Learning Goals:".
- Bullet points start with "• "; questions are numbered "1.", "2.", ...
- Never write underscore subscripts like v_i or v_f. Use Unicode where it exists (v₀, v₁, t₂, x², m/s²) and otherwise plain compact form (vi, vf, Ek).`;

    // deno-lint-ignore no-explicit-any
    let raw: any = null;
    let provider = "claude";
    const planUsage = { inputTokens: 0, outputTokens: 0 };
    const errs: string[] = [];
    try {
      raw = await callClaude([], "image/jpeg", { userText: prompt, schema: PLAN_SCHEMA, usage: planUsage });
    } catch (e) {
      errs.push(`claude: ${e instanceof Error ? e.message : e}`);
      try {
        raw = await callGemini([], "image/jpeg", prompt, PLAN_SHAPE);
        provider = "gemini";
        planUsage.inputTokens = 1000;
        planUsage.outputTokens = 1200;
      } catch (e2) {
        errs.push(`gemini: ${e2 instanceof Error ? e2.message : e2}`);
        return json({ error: "Planning failed", details: errs }, 502);
      }
    }
    await logUsage(planTeacherId, "plan", planUsage.inputTokens, planUsage.outputTokens);
    const out = {
      title: String(raw?.title ?? "Untitled plan"),
      content: String(raw?.content ?? ""),
    };
    await cacheWrite(planKey, provider, out, []);
    return json(out);
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

  // ── On-demand detailed explanations for a marked result (extra credits:
  //    a second frontier pass over the pages, gated like a fresh grade). ──
  if (action === "explain") {
    const teacherId = String(payload?.teacherId ?? "").trim();
    if (!teacherId) return json({ error: "teacherId is required" }, 400);
    const gate = await budgetGate(teacherId, true);
    if (gate) return gate;
    const resultJson = JSON.stringify(payload?.result ?? {}).slice(0, 20000);
    const prompt =
      `You are the teacher who marked this student's work — the marked result is below as JSON, and the pages are attached. For EACH error, deduction, or flagged item, explain in 1-3 sentences: exactly what is wrong (quote the student's actual words/numbers), why it lost marks, and what to do instead. Group the explanations under short headings matching the question labels or section names from the result. Recurring patterns get ONE explanation noting where they repeat. No preamble, no overall summary, no restating the total.\n\nMARKED RESULT:\n${resultJson}`;
    const usage = { inputTokens: 0, outputTokens: 0 };
    try {
      const raw = await callClaude(imagesBase64, mediaType, {
        userText: prompt,
        schema: {
          type: "object",
          additionalProperties: false,
          required: ["explanation"],
          properties: { explanation: { type: "string" } },
        },
        usage,
      });
      await logUsage(teacherId, "explain", usage.inputTokens, usage.outputTokens);
      return json({ explanation: String(raw?.explanation ?? "") });
    } catch (e) {
      return json({ error: `Explanation failed: ${e instanceof Error ? e.message : e}` }, 502);
    }
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

  // Fresh marking costs money — check the teacher's budget first. Cache
  // hits above are free and never gated.
  const gradeTeacherId = String(payload?.teacherId ?? "").trim();
  const gateHit = await budgetGate(gradeTeacherId, true);
  if (gateHit) return gateHit;

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

  // ── Cheap objective route ───────────────────────────────────────────────
  // With an official answer key on file, homework/quiz marking is mostly
  // transcription + comparison: a vision pass (Gemini) transcribes what the
  // student wrote, then a cheap text model (DeepSeek) does the comparing —
  // ~10x cheaper per mark than the frontier path. Essays, lab reports, and
  // keyless marking skip this. ANY failure falls through to the frontier
  // single-call path below, so quality can only fall back, never dead-end.
  // Routing spec (question-type first, grade level as the secondary lever):
  //   1. Answer key + homework/testQuiz → cheap route, any grade (grading
  //      is compare-against-key, no judgment needed).
  //   2. No key, but ELEMENTARY (≤ Grade 6) homework → cheap route too:
  //      K-6 objective content is well within the small model's judgment.
  //   3. Essays, lab reports, keyless high-school work, explicit
  //      provider=gemini → frontier path (Sonnet-class judgment).
  const keyedObjective = !!answerKey && (mode === "homework" || mode === "testQuiz");
  const elementaryKeyless = !answerKey && mode === "homework" &&
    expectationGrade != null && expectationGrade <= 6;
  const objectiveRoute = !!Deno.env.get("DEEPSEEK_API_KEY") && !preferGemini &&
    (keyedObjective || elementaryKeyless);
  if (objectiveRoute) {
    try {
      const parsed = await callGemini(imagesBase64, mediaType, PARSE_PROMPT, PARSE_SHAPE);
      await logUsage(
        gradeTeacherId,
        "parse",
        imagesBase64.length * 1400 + 600,
        800,
        GEMINI_PARSE_PRICE_IN,
        GEMINI_PARSE_PRICE_OUT,
      );
      const dsUsage = { inputTokens: 0, outputTokens: 0 };
      const transcript =
        `\n\nA vision pass has already transcribed the pages. Treat this transcript as exactly what the student wrote (do not invent or omit answers), and reuse its pageIndex, positionTop, and positionLeft values for your annotations:\n${JSON.stringify(parsed)}`;
      const raw = await callDeepSeek(geminiPrompt + transcript + shape, dsUsage);
      await logUsage(gradeTeacherId, "grade", dsUsage.inputTokens, dsUsage.outputTokens, DEEPSEEK_PRICE_IN, DEEPSEEK_PRICE_OUT);
      await cacheWrite(cacheKey, "deepseek", raw, imageHashes);
      const stats: CodeUse[] = [];
      const normalized = normalize(raw, "deepseek", maxScore, formatOverride, stats, expectationGrade);
      await logCodeUsage(stats);
      return json({ ...normalized, cached: false });
    } catch (e) {
      console.error("objective route failed, falling back to frontier path:", e instanceof Error ? e.message : e);
    }
  }

  const errors: string[] = [];
  for (const name of attempts) {
    try {
      const usage = { inputTokens: 0, outputTokens: 0 };
      const raw = name === "claude"
        ? await callClaude(imagesBase64, mediaType, { systemBlocks, userText: contextText, schema, usage })
        : await callGemini(imagesBase64, mediaType, geminiPrompt, shape);
      if (name === "gemini") {
        // Gemini doesn't report through the same path — conservative estimate.
        usage.inputTokens = imagesBase64.length * 1400 + 1200;
        usage.outputTokens = 900;
      }
      await logUsage(gradeTeacherId, "grade", usage.inputTokens, usage.outputTokens);
      await cacheWrite(cacheKey, name, raw, imageHashes);
      const stats: CodeUse[] = [];
      const normalized = normalize(raw, name, maxScore, formatOverride, stats, expectationGrade);
      await logCodeUsage(stats);
      const learnedKey = (!answerKeyId && normalized.markingStyle === "graded")
        ? await maybeStoreLearnedKey(gradeTeacherId, raw)
        : null;
      return json({ ...normalized, cached: false, ...(learnedKey ? { learnedKey } : {}) });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`${name} grading failed:`, msg);
      errors.push(`${name}: ${msg}`);
    }
  }

  return json({ error: "All AI providers failed", details: errors }, 502);
});
