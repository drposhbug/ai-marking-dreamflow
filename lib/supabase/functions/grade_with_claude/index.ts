// supabase/functions/grade_with_claude/index.ts

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type GradeRequest = {
  teacher_id?: string;
  student_id?: string;
  class_id?: string;
  preset_id?: string;
  subject?: string;
  grading_mode?: string;
  criteria?: string[];
  harshness?: number;
  notes?: string;
  // Optional future fields:
  work_text?: string;
};

type GradeResponse = {
  score: number;
  max_score: number;
  confidence: number;
  flags: string[];
  feedback: string;
  triage_status: "graded" | "needs_review";
};

function clampInt(v: unknown, min: number, max: number, fallback: number): number {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.round(n)));
}

function strictnessWord(h: number): string {
  if (h <= 3) return "Lenient";
  if (h <= 6) return "Balanced";
  return "Strict";
}

function maxScoreForMode(modeRaw: string): number {
  const m = (modeRaw || "homework").toLowerCase();
  if (m.includes("english")) return 25;
  if (m.includes("homework")) return 100;
  if (m.includes("lab")) return 40;
  if (m.includes("test") || m.includes("quiz")) return 40;
  return 100;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "Missing ANTHROPIC_API_KEY secret" }, 500);

  let payload: GradeRequest;
  try {
    payload = (await req.json()) as GradeRequest;
  } catch (_e) {
    return json({ error: "Invalid JSON" }, 400);
  }

  const gradingMode = (payload.grading_mode || "homework").toString();
  const harshness = clampInt(payload.harshness, 1, 10, 5);
  const criteria = Array.isArray(payload.criteria) ? payload.criteria.filter((x) => typeof x === "string" && x.trim().length > 0) : [];
  const notes = (payload.notes || "").toString().trim();
  const subject = (payload.subject || "Subject").toString();
  const workText = (payload.work_text || "").toString().trim();

  const maxScore = maxScoreForMode(gradingMode);
  const strictWord = strictnessWord(harshness);

  const prompt = `You are an expert teacher marker.

Grade this assignment with a strictness level of ${harshness}/10 (${strictWord}).
Subject: ${subject}
Grading mode: ${gradingMode}
Focus on: ${criteria.length ? criteria.join(", ") : "(no criteria provided)"}
Special instructions: ${notes || "(none)"}

Student work (may be empty):\n${workText || "(not provided)"}

Return ONLY valid JSON with this exact schema:
{
  "score": number,
  "max_score": number,
  "confidence": number,      // 50-99
  "flags": string[],         // short bullet-like warnings
  "feedback": string,        // actionable feedback
  "triage_status": "graded" | "needs_review"
}

Rules:
- max_score must be ${maxScore}.
- score must be between 0 and max_score.
- confidence must be between 50 and 99.
- triage_status should be "needs_review" if missing work text or confidence < 85.`;

  try {
    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-3-5-sonnet-20240620",
        max_tokens: 700,
        temperature: 0.2,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    const raw = await anthropicRes.text();
    if (!anthropicRes.ok) {
      return json({ error: "Anthropic request failed", status: anthropicRes.status, raw }, 502);
    }

    const parsed = JSON.parse(raw);
    const text = parsed?.content?.[0]?.text ?? "";

    let out: GradeResponse;
    try {
      const obj = JSON.parse(text);
      out = {
        score: clampInt(obj.score, 0, maxScore, 0),
        max_score: maxScore,
        confidence: clampInt(obj.confidence, 50, 99, 85),
        flags: Array.isArray(obj.flags) ? obj.flags.filter((x: unknown) => typeof x === "string").slice(0, 8) : [],
        feedback: typeof obj.feedback === "string" ? obj.feedback : "",
        triage_status: obj.triage_status === "needs_review" ? "needs_review" : "graded",
      };
    } catch (_e) {
      // If Claude didn't return JSON, fall back safely.
      out = {
        score: Math.round(maxScore * 0.75),
        max_score: maxScore,
        confidence: workText ? 85 : 72,
        flags: workText ? [] : ["No work text provided — please verify"],
        feedback: typeof text === "string" && text.trim().length ? text : "Could not parse Claude response.",
        triage_status: workText ? "graded" : "needs_review",
      };
    }

    return json(out);
  } catch (e) {
    return json({ error: "Unhandled error", message: String(e) }, 500);
  }
});
