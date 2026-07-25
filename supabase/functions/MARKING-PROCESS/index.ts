// supabase/functions/MARKING-PROCESS/index.ts
//
// Grades a scanned page of student work with AI vision.
// Primary grader: Claude (Anthropic). Fallback: Gemini (Google).
//
// Secrets required (Dashboard → Edge Functions → Secrets, or `npx supabase secrets set`):
//   ANTHROPIC_API_KEY  — from https://platform.claude.com
//   GEMINI_API_KEY     — from https://aistudio.google.com/apikey
//
// Request body (sent by the Flutter app's AiGradingService.grade):
//   { imagesBase64: string[] (or legacy imageBase64), mediaType, mode, maxScore,
//     criteria: [{name}], harshness, studentName?, studentGrade?,
//     formatOverride?, provider? }
//
// Response body matches AiGradingService._parseResponse exactly.

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

// ---------- Output schema (enforced on Claude via structured outputs) ----------

const nullableInt = { anyOf: [{ type: "integer" }, { type: "null" }] };
const nullableString = { anyOf: [{ type: "string" }, { type: "null" }] };

const GRADE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "detectedSubject", "detectedGrade", "studentNameOnPaper", "gradingFormat", "rawScore", "maxScore",
    "percentage", "summary", "strengths", "improvements",
    "criteriaBreakdown", "annotations", "rawText",
  ],
  properties: {
    detectedSubject: { type: "string" },
    detectedGrade: nullableInt,
    studentNameOnPaper: nullableString,
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
    rawText: { type: "string" },
  },
} as const;

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

// ---------- Prompt ----------

function strictnessWord(h: number): string {
  if (h <= 3) return "lenient — give the benefit of the doubt and generous partial credit";
  if (h <= 6) return "balanced — fair partial credit, deduct for real errors";
  return "strict — deduct for any imprecision, missing work, or sloppy reasoning";
}

function buildPrompt(p: {
  mode: string;
  maxScore: number;
  harshness: number;
  criteria: string[];
  studentName?: string;
  studentGrade?: number | null;
  pageCount: number;
  // deno-lint-ignore no-explicit-any
  answerKey?: any;
}): string {
  const pages = p.pageCount === 1 ? "one scanned page" : `${p.pageCount} scanned pages`;
  const keySection = p.answerKey
    ? `

OFFICIAL ANSWER KEY — mark STRICTLY against this key. Marks per question come from the key. An answer is correct if it matches the key's answer or is mathematically/scientifically equivalent. Do not re-derive your own answers when the key provides one.
${JSON.stringify(p.answerKey)}
`
    : "";
  return `You are an expert teacher marking ${pages} of a single student's work. The pages are provided in order and labeled Page 1 to Page ${p.pageCount}. Grade the ENTIRE piece of work as one submission, based ONLY on what is visible in the images.${keySection}

Context:
- Grading mode: ${p.mode}
- Fallback total marks: ${p.maxScore} (use ONLY if the paper does not show its own marks — see rule 5)
- Strictness: ${p.harshness}/10 (${strictnessWord(p.harshness)})
- Criteria to grade on: ${p.criteria.length ? p.criteria.join(", ") : "overall quality"}
- Student name (reference only, never grade on it): ${p.studentName || "unknown"}
- Student grade level: ${p.studentGrade ?? "unknown — detect it from the work if possible"}

Do all of the following:
1. Transcribe the student's visible work from ALL pages into rawText, keeping question numbers/labels and marking page boundaries like "--- Page 2 ---".
2. Detect the subject, and the student's school grade level 1-12 (null if unclear). Also read the student's name if it is written on the paper into studentNameOnPaper (null if none visible).
3. Create one annotation per question or answer visible across all pages:
   - questionLabel like "Q1", earnedMark like "2", outOfMark like "/4" — when the paper prints a question's marks (e.g. "(2 marks)"), use exactly those marks
   - correct = true only if fully correct
   - feedback: one short note (max 12 words)
   - check every numeric final answer for UNITS: if a required unit is missing or wrong, say so in that question's feedback and deduct part marks for it
   - pageIndex: which page the answer is on, 0-based (Page 1 = 0, Page 2 = 1, ...)
   - positionTop and positionLeft: where the answer sits on THAT page, as fractions of the image height/width between 0.0 and 1.0 (0.0 = top/left edge).
4. Score each grading criterion in criteriaBreakdown with a per-criterion score and maxScore, a level 1-4 (or null), and one sentence of feedback — considering all pages together. criteriaBreakdown is diagnostic feedback ONLY — it must NOT determine the overall score. If a criterion does not apply to this work (e.g. "Diagrams labeled" when no diagrams are required), give it full marks and note it is not applicable — never deduct for inapplicable criteria.
5. Compute maxScore and rawScore for the whole submission:
   - If the paper prints marks per question (e.g. "(2 marks)", "/4"), maxScore = the TOTAL of the printed marks of the questions VISIBLE in the images, and rawScore = the marks the student earned on those questions.
   - Only if the paper shows no marks at all, use maxScore = ${p.maxScore}.
   - Grade ONLY what is visible. NEVER deduct for questions, sections, or pages that are not in the images — treat the visible pages as the entire submission. If everything visible is fully correct, the score must be full marks.
   - percentage must equal rawScore / maxScore * 100 (rounded is fine).
6. Ontario/Canadian KTCA marking: many Canadian tests divide their sections into the Ontario achievement categories — Knowledge/Understanding, Thinking/Inquiry, Communication, Application (e.g. "Part A – Knowledge Questions (10 marks)", "Part D – Application Questions (10 marks)"). If the visible sections are labeled with these categories:
   - A question counts ONLY toward the category of the section it appears in.
   - Score each visible category separately: marks earned on that section's visible questions out of that section's visible printed marks.
   - Put one entry per visible category FIRST in criteriaBreakdown, named exactly "Knowledge", "Thinking", "Communication", or "Application" (only the categories actually visible), with that category's marks and one-sentence feedback. Any requested criteria follow after as feedback-only entries.
   - The overall percentage = the AVERAGE of the visible category percentages, each category weighted equally (this is how KTCA works — NOT total marks divided by total marks). rawScore and maxScore still report the total visible marks earned and available.
   - If the paper's sections are not labeled with KTCA categories, skip this rule and use percentage = rawScore / maxScore * 100.
7. Choose gradingFormat: "levels" for essays, lab reports, and rubric-style work; "percentage" for tests, quizzes, and homework.
8. Write summary (2-3 sentences addressed to the teacher), 2-4 strengths, and 2-4 improvements — specific to this student's actual work across the whole submission. When KTCA categories were used, state each category's result in the summary (e.g. "Communication 8/8, Application 9.5/10").

If the pages are blank, unreadable, or not student work, give a score of 0, an empty annotations list, and explain the problem in summary.`;
}

// ---------- Normalization (shared by both providers) ----------

function clamp(n: unknown, min: number, max: number, fallback: number): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  return Math.max(min, Math.min(max, v));
}

function levelFromPercentage(pct: number): { level: number | null; levelDisplay: string } {
  if (pct >= 80) return { level: 4, levelDisplay: "Level 4 (80–100%)" };
  if (pct >= 70) return { level: 3, levelDisplay: "Level 3 (70–79%)" };
  if (pct >= 60) return { level: 2, levelDisplay: "Level 2 (60–69%)" };
  if (pct >= 50) return { level: 1, levelDisplay: "Level 1 (50–59%)" };
  return { level: null, levelDisplay: "Below Level 1 (<50%)" };
}

// deno-lint-ignore no-explicit-any
function normalize(obj: any, provider: string, maxScoreDefault: number, formatOverride?: string) {
  const maxScore = clamp(obj?.maxScore, 1, 10000, maxScoreDefault);
  const rawScore = clamp(obj?.rawScore, 0, maxScore, 0);
  const percentage = clamp(obj?.percentage, 0, 100, Math.round((rawScore / maxScore) * 100));
  const { level, levelDisplay } = levelFromPercentage(percentage);

  const gradingFormat = formatOverride === "levels" || formatOverride === "percentage"
    ? formatOverride
    : (obj?.gradingFormat === "levels" ? "levels" : "percentage");

  // deno-lint-ignore no-explicit-any
  const asStringArray = (v: unknown) => (Array.isArray(v) ? v.filter((x: any) => typeof x === "string") : []);

  return {
    provider,
    detectedSubject: String(obj?.detectedSubject ?? ""),
    detectedGrade: Number.isFinite(Number(obj?.detectedGrade)) ? Math.round(Number(obj.detectedGrade)) : null,
    studentNameOnPaper: typeof obj?.studentNameOnPaper === "string" && obj.studentNameOnPaper.trim().length > 0
      ? obj.studentNameOnPaper.trim()
      : null,
    gradingFormat,
    rawScore,
    maxScore,
    percentage,
    percentageDisplay: `${Math.round(percentage)}%`,
    level,
    levelDisplay,
    summary: String(obj?.summary ?? ""),
    strengths: asStringArray(obj?.strengths),
    improvements: asStringArray(obj?.improvements),
    // deno-lint-ignore no-explicit-any
    criteriaBreakdown: (Array.isArray(obj?.criteriaBreakdown) ? obj.criteriaBreakdown : []).map((c: any) => ({
      name: String(c?.name ?? ""),
      score: clamp(c?.score, 0, 10000, 0),
      maxScore: clamp(c?.maxScore, 1, 10000, 10),
      level: Number.isFinite(Number(c?.level)) ? Math.round(Number(c.level)) : null,
      feedback: String(c?.feedback ?? ""),
    })),
    // deno-lint-ignore no-explicit-any
    annotations: (Array.isArray(obj?.annotations) ? obj.annotations : []).map((a: any) => ({
      questionLabel: String(a?.questionLabel ?? ""),
      earnedMark: String(a?.earnedMark ?? ""),
      outOfMark: String(a?.outOfMark ?? ""),
      correct: a?.correct === true,
      feedback: String(a?.feedback ?? ""),
      pageIndex: Math.round(clamp(a?.pageIndex, 0, 999, 0)),
      positionTop: clamp(a?.positionTop, 0, 1, 0.1),
      positionLeft: clamp(a?.positionLeft, 0, 1, 0.1),
    })),
    rawText: String(obj?.rawText ?? ""),
  };
}

// ---------- Providers ----------

// deno-lint-ignore no-explicit-any
async function gradeWithClaude(imagesBase64: string[], mediaType: string, prompt: string, schema: any = GRADE_SCHEMA) {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("Missing ANTHROPIC_API_KEY secret");

  // deno-lint-ignore no-explicit-any
  const content: any[] = [];
  imagesBase64.forEach((img, i) => {
    content.push({ type: "text", text: `Page ${i + 1} of ${imagesBase64.length}:` });
    content.push({ type: "image", source: { type: "base64", media_type: mediaType, data: img } });
  });
  content.push({ type: "text", text: prompt });

  const anthropic = new Anthropic({ apiKey });
  const response = await anthropic.messages.create({
    model: "claude-opus-4-8",
    max_tokens: 16000,
    thinking: { type: "adaptive" },
    // "medium" keeps grading well inside the edge-function time limit;
    // raise to "high" if you can tolerate slower, deeper marking.
    output_config: {
      effort: "medium",
      format: { type: "json_schema", schema },
    },
    messages: [{ role: "user", content }],
  });

  if (response.stop_reason === "refusal") {
    throw new Error("Claude declined to grade this image");
  }
  const text = response.content.find((b) => b.type === "text")?.text ?? "";
  if (!text) throw new Error(`Claude returned no text (stop_reason: ${response.stop_reason})`);
  return JSON.parse(text);
}

const GRADE_SHAPE = `\n\nReturn ONLY a single JSON object with exactly these fields and no others:
{
  "detectedSubject": string,
  "detectedGrade": integer or null,
  "studentNameOnPaper": string or null,
  "gradingFormat": "percentage" or "levels",
  "rawScore": number,
  "maxScore": number,
  "percentage": number,
  "summary": string,
  "strengths": string[],
  "improvements": string[],
  "criteriaBreakdown": [{"name": string, "score": number, "maxScore": number, "level": integer or null, "feedback": string}],
  "annotations": [{"questionLabel": string, "earnedMark": string, "outOfMark": string, "correct": boolean, "feedback": string, "pageIndex": integer, "positionTop": number, "positionLeft": number}],
  "rawText": string
}`;

async function gradeWithGemini(imagesBase64: string[], mediaType: string, prompt: string, jsonInstruction: string = GRADE_SHAPE) {
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
      raw = await gradeWithClaude(imagesBase64, mediaType, KEY_PROMPT, KEY_SCHEMA);
    } catch (e) {
      errs.push(`claude: ${e instanceof Error ? e.message : e}`);
      try {
        raw = await gradeWithGemini(imagesBase64, mediaType, KEY_PROMPT, KEY_SHAPE);
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
  const mode = String(payload?.mode || "homework");
  const maxScore = Math.round(clamp(payload?.maxScore, 1, 10000, 100));
  const harshness = Math.round(clamp(payload?.harshness, 1, 10, 5));
  // deno-lint-ignore no-explicit-any
  const criteria = (Array.isArray(payload?.criteria) ? payload.criteria : [])
    .map((c: any) => String(c?.name ?? c ?? "").trim())
    .filter((s: string) => s.length > 0);
  const formatOverride = payload?.formatOverride ? String(payload.formatOverride) : undefined;

  // Pull the stored answer key when one was chosen — the key was analyzed
  // once at save time, so grading only pays for its compact text.
  // deno-lint-ignore no-explicit-any
  let answerKey: any = null;
  const answerKeyId = String(payload?.answerKeyId ?? "").trim();
  if (answerKeyId) {
    const { data } = await serviceDb()
      .from("answer_keys")
      .select("key_json")
      .eq("id", answerKeyId)
      .maybeSingle();
    answerKey = data?.key_json ?? null;
  }

  const prompt = buildPrompt({
    mode,
    maxScore,
    harshness,
    criteria,
    studentName: payload?.studentName ? String(payload.studentName) : undefined,
    studentGrade: Number.isFinite(Number(payload?.studentGrade)) ? Number(payload.studentGrade) : null,
    pageCount: imagesBase64.length,
    answerKey,
  });

  // Claude grades by default; Gemini is the fallback (or primary when
  // the request asks for it with "provider": "gemini").
  const preferGemini = String(payload?.provider ?? "").toLowerCase() === "gemini";
  const attempts: Array<["claude" | "gemini", (i: string[], m: string, p: string) => Promise<unknown>]> =
    preferGemini
      ? [["gemini", gradeWithGemini], ["claude", gradeWithClaude]]
      : [["claude", gradeWithClaude], ["gemini", gradeWithGemini]];

  const errors: string[] = [];
  for (const [name, fn] of attempts) {
    try {
      const raw = await fn(imagesBase64, mediaType, prompt);
      return json(normalize(raw, name, maxScore, formatOverride));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`${name} grading failed:`, msg);
      errors.push(`${name}: ${msg}`);
    }
  }

  return json({ error: "All AI providers failed", details: errors }, 502);
});
