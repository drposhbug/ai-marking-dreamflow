// Scaling test for the Markless backend: simulates teachers signing up,
// building classrooms, saving marked work and reading it back, at increasing
// levels of concurrency, against the real MARKING-PROCESS edge function.
//
//   node tool/load_test.mjs                        # stages 1,5,10,25,50 — zero AI spend
//   node tool/load_test.mjs --stages 5,20          # custom ramp
//   node tool/load_test.mjs --loops 3              # each teacher repeats their session
//   node tool/load_test.mjs --marking 10           # ALSO make 10 real mark_responses calls
//
// COST: the default run makes NO AI-billable calls — every action in the
// session is a database read or write (save_profile, save_collection,
// save_submission, list_*, get_usage, search_schools). The --marking probe is
// the one exception: each call really marks two short answers (~$0.001-0.005).
// It is capped at 200 calls and the script prints the estimate and refuses
// past the cap. Simulated teachers land on the trial plan, so budgetGate also
// caps each of them server-side.
//
// IDENTITY: every simulated teacher id starts with "loadtest-" so the rows
// are easy to find and delete. The script prints the cleanup SQL at the end;
// it cannot delete them itself, because delete_account (correctly) requires a
// real signed-in JWT for the account being deleted.
//
// The anon key is read from markless-keys/supa_anon.txt or SUPABASE_ANON_KEY.
// It is never printed.

import { readFileSync } from "node:fs";

const FN_URL = "https://zxikjizraeqejbsncqpg.supabase.co/functions/v1/MARKING-PROCESS";
const KEY_FILE = "C:/Users/tyler/OneDrive/markless-keys/supa_anon.txt";
const REQUEST_TIMEOUT_MS = 30_000;
const MARKING_HARD_CAP = 200;

// ── args ─────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
function argOf(name, fallback) {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
}
const STAGES = String(argOf("stages", "1,5,10,25,50")).split(",").map((s) => parseInt(s, 10)).filter((n) => n > 0);
const LOOPS = parseInt(argOf("loops", "1"), 10);
const MARKING_CALLS = parseInt(argOf("marking", "0"), 10);

if (MARKING_CALLS > MARKING_HARD_CAP) {
  console.error(`--marking ${MARKING_CALLS} refused: hard cap is ${MARKING_HARD_CAP} (~$${(MARKING_HARD_CAP * 0.005).toFixed(2)} worst case).`);
  process.exit(1);
}

let anonKey = process.env.SUPABASE_ANON_KEY ?? "";
if (!anonKey) {
  try { anonKey = readFileSync(KEY_FILE, "utf8").trim(); } catch { /* fall through */ }
}
if (!anonKey) {
  console.error(`No anon key: set SUPABASE_ANON_KEY or put it in ${KEY_FILE}`);
  process.exit(1);
}

const RUN = `loadtest-${new Date().toISOString().slice(5, 16).replace(/[-T:]/g, "")}`;
console.log(`run id prefix: ${RUN}-u<N>   stages: ${STAGES.join(" → ")} teachers   loops: ${LOOPS}   marking probes: ${MARKING_CALLS}`);
if (MARKING_CALLS > 0) {
  console.log(`marking probes are REAL AI calls: estimated cost $${(MARKING_CALLS * 0.001).toFixed(3)}–$${(MARKING_CALLS * 0.005).toFixed(3)}`);
}

// ── one measured request ─────────────────────────────────────────────────
const stats = new Map(); // action -> { times: [], ok, errs: Map(status -> n), sampleErr }
function rec(action, ms, status, ok, errBody) {
  let s = stats.get(action);
  if (!s) { s = { times: [], ok: 0, errs: new Map(), sampleErr: null }; stats.set(action, s); }
  s.times.push(ms);
  if (ok) s.ok++;
  else {
    s.errs.set(status, (s.errs.get(status) ?? 0) + 1);
    if (!s.sampleErr && errBody) s.sampleErr = String(errBody).slice(0, 140);
  }
}

async function call(action, payload, { expectStatus } = {}) {
  const t0 = performance.now();
  let status = 0, ok = false, body = null;
  try {
    const res = await fetch(FN_URL, {
      method: "POST",
      headers: {
        authorization: `Bearer ${anonKey}`,
        apikey: anonKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({ action, ...payload }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    status = res.status;
    body = await res.text();
    // Most actions succeed as 200 with either data or {error}. An {error}
    // body on a 200 still counts as a failure for our purposes — the app
    // would show the teacher an error.
    if (expectStatus !== undefined) {
      ok = status === expectStatus;
    } else {
      ok = status === 200 && !(body.startsWith("{") && JSON.parse(body).error);
    }
  } catch (e) {
    status = -1; // timeout / network
    body = String(e?.message ?? e);
  }
  rec(action, performance.now() - t0, status, ok, ok ? null : body);
  return { status, body };
}

const jitter = (max = 60) => new Promise((r) => setTimeout(r, Math.random() * max));

// ── the simulated teacher session (all DB-path, no AI) ───────────────────
const FIRST = ["Amara", "Ben", "Chloe", "Deven", "Elif", "Farah", "Gus", "Hana", "Ines", "Jae", "Kofi", "Lena", "Marc", "Nia", "Omar", "Priya", "Quinn", "Rosa", "Sam", "Tessa", "Uma", "Vik", "Wren", "Xiu", "Yara", "Zane"];
function fakeSubmission(teacher, n) {
  // Sized like a real marked paper: annotations plus a rawText blob, ~8KB.
  return {
    id: `${teacher}-sub-${n}`,
    studentName: `${FIRST[n % FIRST.length]} ${FIRST[(n + 7) % FIRST.length]}`,
    subject: "Science",
    score: 17.5, outOf: 20,
    resultJson: {
      overall: "17.5/20",
      annotations: Array.from({ length: 8 }, (_, q) => ({
        questionLabel: `Knowledge ${q + 1}`,
        earnedMark: q === 2 ? "3.75" : "5",
        outOfMark: "5",
        correct: q !== 2,
        feedback: "Right method — arithmetic slip in the last line. Show the substitution next time.",
      })),
      rawText: "x".repeat(6000),
    },
    createdAt: new Date().toISOString(),
  };
}

async function teacherSession(u) {
  const id = `${RUN}-u${u}`;
  await call("save_profile", { teacherId: id, name: `Load Teacher ${u}`, school: "Scaling Test HS", region: "ca-on" });
  await jitter();
  await call("save_collection", {
    teacherId: id, kind: "classes",
    items: [{ id: `${id}-c1`, name: "SNC2D Period 1" }, { id: `${id}-c2`, name: "SNC2D Period 4" }],
  });
  await call("save_collection", {
    teacherId: id, kind: "students",
    items: Array.from({ length: 30 }, (_, n) => ({ id: `${id}-s${n}`, name: `${FIRST[n % FIRST.length]} ${FIRST[(n + 3) % FIRST.length]}`, studentId: `LT${n}` })),
  });
  await call("save_collection", {
    teacherId: id, kind: "student_class_links",
    items: Array.from({ length: 30 }, (_, n) => ({ studentId: `${id}-s${n}`, classId: `${id}-c${(n % 2) + 1}` })),
  });
  await jitter();
  await call("get_usage", { teacherId: id });
  await call("list_keys", { teacherId: id });
  for (let n = 0; n < 3; n++) {
    await call("save_submission", { teacherId: id, submission: fakeSubmission(id, n) });
  }
  await call("list_submissions", { teacherId: id });
  await call("get_collection", { teacherId: id, kind: "classes" });
  await call("search_schools", { query: "north" });
}

// The one real marking call, when asked for: two short typed answers, the
// same route the Google Form import uses.
async function markingProbe(u) {
  const id = `${RUN}-u${u}`;
  await call("mark_responses", {
    teacherId: id, harshness: 5, subject: "Science", gradeLevel: 10,
    questions: [
      { prompt: "State Newton's second law.", maxMarks: 2, keyAnswer: "F = ma (force equals mass times acceleration)",
        answers: [{ i: 0, text: "F = ma" }, { i: 1, text: "Force equals mass times acceleration" }] },
      { prompt: "What is the SI unit of force?", maxMarks: 1, keyAnswer: "The newton (N)",
        answers: [{ i: 0, text: "The newton" }, { i: 1, text: "kg" }] },
    ],
  });
}

// The IDOR guard must hold under load: list_batches with a teacherId the
// anon JWT does not carry has to come back 403, every time.
async function guardProbe() {
  await call("list_batches", { teacherId: `${RUN}-someone-else` }, { expectStatus: 403 });
}

// ── ramp ─────────────────────────────────────────────────────────────────
const pct = (arr, p) => {
  if (!arr.length) return 0;
  const a = [...arr].sort((x, y) => x - y);
  return a[Math.min(a.length - 1, Math.floor((p / 100) * a.length))];
};

let markingDone = 0;
for (const users of STAGES) {
  const before = new Map([...stats].map(([k, v]) => [k, v.times.length]));
  const t0 = performance.now();
  const work = [];
  for (let u = 0; u < users; u++) {
    work.push((async () => {
      for (let l = 0; l < LOOPS; l++) await teacherSession(u);
      if (markingDone < MARKING_CALLS) { markingDone++; await markingProbe(u); }
    })());
  }
  work.push(guardProbe());
  await Promise.all(work);
  const secs = (performance.now() - t0) / 1000;

  let reqs = 0, errs = 0;
  for (const [k, v] of stats) {
    const newCount = v.times.length - (before.get(k) ?? 0);
    reqs += newCount;
    // errors since stage start are not tracked per-stage per-status; keep it simple:
  }
  for (const v of stats.values()) for (const n of v.errs.values()) errs += n;
  console.log(`stage ${String(users).padStart(3)} teachers: ${reqs} requests in ${secs.toFixed(1)}s  (${(reqs / secs).toFixed(1)} req/s)  cumulative errors: ${errs}`);
  if (reqs > 0 && errs / (reqs || 1) > 0.5) {
    console.error("over half the requests are failing — stopping the ramp rather than hammering a struggling backend");
    break;
  }
}

// ── report ───────────────────────────────────────────────────────────────
console.log("\naction                 calls   ok      p50ms   p95ms    max   errors");
for (const [k, v] of [...stats].sort()) {
  const errTotal = [...v.errs.values()].reduce((a, b) => a + b, 0);
  const errStr = errTotal ? [...v.errs].map(([st, n]) => `${n}×${st === -1 ? "timeout" : st}`).join(",") : "-";
  console.log(
    `${k.padEnd(22)} ${String(v.times.length).padStart(5)} ${String(v.ok).padStart(5)} ${String(Math.round(pct(v.times, 50))).padStart(8)} ${String(Math.round(pct(v.times, 95))).padStart(7)} ${String(Math.round(Math.max(...v.times))).padStart(6)}   ${errStr}`,
  );
  if (v.sampleErr) console.log(`   └ first error: ${v.sampleErr}`);
}

console.log(`\ncleanup (run in the Supabase SQL editor — the script cannot do this itself):
  delete from submissions_cloud where teacher_id like 'loadtest-%';
  delete from collections_cloud where teacher_id like 'loadtest-%';
  delete from usage_log         where teacher_id like 'loadtest-%';
  delete from profiles          where teacher_id like 'loadtest-%';`);
