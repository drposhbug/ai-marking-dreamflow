// Performance test battery for the UMarkless backend, against the REAL
// MARKING-PROCESS edge function. One file, four modes:
//
//   node tool/load_test.mjs --mode ramp  --stages 100,250,500     # load / stress
//   node tool/load_test.mjs --mode spike --from 50 --to 2000      # cold-start & pool exhaustion
//   node tool/load_test.mjs --mode soak  --minutes 240 --vus 5    # leaks & slow drift
//   node tool/load_test.mjs --mode volume --rows 3000             # data volume, not traffic
//   (legacy: --stages a,b,c with no --mode == ramp; --marking N adds real AI probes)
//
// R14 — THE BACKEND NOW CHECKS IDENTITY. Every teacherId-carrying action is
// refused with 403 unless the caller's JWT is a signed-in user whose sub IS
// that teacherId. With only the anon key, a wall of 403s is the guard
// WORKING, not the backend failing. Two ways to run against it:
//   --jwt <access token>   run as ONE real signed-in user: the token is sent
//                          as the bearer and the teacherId for every session
//                          is derived from its sub. Traffic shape is intact;
//                          all rows land on that one account (volume mode's
//                          hot/cold comparison collapses to one identity).
//   no --jwt               the classic fleet-of-fake-teachers ("loadtest-*")
//                          only works against a PRE-R14 deployment, or with a
//                          service-role key in SUPABASE_ANON_KEY's place.
//                          Do NOT weaken the guard to make this mode pass.
//
// COST: every session action is a DB read or write — zero AI calls unless
// --marking is passed (capped at 200; each real call ~$0.001-0.005; the
// simulated teachers are on the trial plan so budgetGate caps them anyway).
//
// IDENTITY & CLEANUP: every simulated teacher id starts with "loadtest-".
// The cleanup SQL is printed at the end. The script cannot delete the rows
// itself: delete_account (correctly) demands a signed-in JWT for the account.
//
// The anon key comes from SUPABASE_ANON_KEY, or from the file named by
// SUPABASE_ANON_KEY_FILE, and is never printed.
//
// A session upserts stable ids, so soak loops do not grow the database;
// spike/ramp rows are bounded (~8KB per submission) and all match the
// cleanup prefix. Each request counts against the free tier's monthly edge
// invocation budget — a full battery is roughly 120k of the 500k allowance.

import { readFileSync, appendFileSync } from "node:fs";

const FN_URL = "https://zxikjizraeqejbsncqpg.supabase.co/functions/v1/MARKING-PROCESS";
const KEY_FILE = process.env.SUPABASE_ANON_KEY_FILE ?? "";
const REQUEST_TIMEOUT_MS = 30_000;
const MARKING_HARD_CAP = 200;

const args = process.argv.slice(2);
const argOf = (name, fb) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fb;
};
const MODE = String(argOf("mode", args.includes("--stages") ? "ramp" : "ramp"));
const STAGES = String(argOf("stages", "1,5,10,25,50")).split(",").map((n) => parseInt(n, 10)).filter((n) => n > 0);
const LOOPS = parseInt(argOf("loops", "1"), 10);
const MARKING_CALLS = parseInt(argOf("marking", "0"), 10);
const SPIKE_FROM = parseInt(argOf("from", "50"), 10);
const SPIKE_TO = parseInt(argOf("to", "2000"), 10);
const SOAK_MINUTES = parseInt(argOf("minutes", "240"), 10);
const SOAK_VUS = parseInt(argOf("vus", "5"), 10);
const VOLUME_ROWS = parseInt(argOf("rows", "3000"), 10);
const LOG_FILE = argOf("log", null);

if (MARKING_CALLS > MARKING_HARD_CAP) {
  console.error(`--marking ${MARKING_CALLS} refused: hard cap ${MARKING_HARD_CAP}.`);
  process.exit(1);
}
let anonKey = process.env.SUPABASE_ANON_KEY ?? "";
if (!anonKey && KEY_FILE) { try { anonKey = readFileSync(KEY_FILE, "utf8").trim(); } catch { /* */ } }
if (!anonKey) { console.error("No anon key: set SUPABASE_ANON_KEY or SUPABASE_ANON_KEY_FILE"); process.exit(1); }

// --jwt: a real user's access token. Sent as the bearer, and its sub becomes
// the teacherId for every simulated session (the R14 guard accepts nothing
// else). Without it the fake-teacher fleet needs a pre-R14 backend.
const JWT = argOf("jwt", null);
const bearer = JWT ?? anonKey;
const jwtSub = (() => {
  if (!JWT) return null;
  try {
    const body = JWT.split(".")[1];
    const sub = JSON.parse(Buffer.from(body, "base64url").toString())?.sub;
    if (!sub) throw new Error("no sub claim");
    return String(sub);
  } catch (e) {
    console.error(`--jwt token could not be decoded (${e?.message ?? e})`);
    process.exit(1);
  }
})();
if (jwtSub) console.log(`running as signed-in user ${jwtSub} (from --jwt)`);

const RUN = `loadtest-${new Date().toISOString().slice(5, 16).replace(/[-T:]/g, "")}`;
// The teacherId a session sends: the real user's sub when --jwt is given,
// else the cleanup-friendly fake id.
const tid = (fake) => jwtSub ?? fake;
const out = (line) => {
  console.log(line);
  if (LOG_FILE) { try { appendFileSync(LOG_FILE, line + "\n"); } catch { /* */ } }
};

// ── measured request, stats keyed by phase ───────────────────────────────
let PHASE = "start";
const phases = new Map(); // phase -> Map(action -> {times, ok, errs Map, sampleErr})
function rec(action, ms, status, ok, errBody) {
  let ph = phases.get(PHASE);
  if (!ph) { ph = new Map(); phases.set(PHASE, ph); }
  let s = ph.get(action);
  if (!s) { s = { times: [], ok: 0, errs: new Map(), sampleErr: null }; ph.set(action, s); }
  s.times.push(ms);
  if (ok) s.ok++;
  else {
    s.errs.set(status, (s.errs.get(status) ?? 0) + 1);
    if (!s.sampleErr && errBody) s.sampleErr = String(errBody).slice(0, 130);
  }
}
async function call(action, payload, { expectStatus } = {}) {
  const t0 = performance.now();
  let status = 0, ok = false, body = null;
  try {
    const res = await fetch(FN_URL, {
      method: "POST",
      headers: { authorization: `Bearer ${bearer}`, apikey: anonKey, "content-type": "application/json" },
      body: JSON.stringify({ action, ...payload }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    status = res.status;
    body = await res.text();
    ok = expectStatus !== undefined
      ? status === expectStatus
      : status === 200 && !(body.startsWith("{") && JSON.parse(body).error);
  } catch (e) {
    status = -1;
    body = String(e?.message ?? e);
  }
  rec(action, performance.now() - t0, status, ok, ok ? null : body);
  return { status, body };
}
const pct = (arr, p) => {
  if (!arr.length) return 0;
  const a = [...arr].sort((x, y) => x - y);
  return a[Math.min(a.length - 1, Math.floor((p / 100) * a.length))];
};
function phaseReport(phase) {
  const ph = phases.get(phase);
  if (!ph) return { reqs: 0, errs: 0 };
  let reqs = 0, errs = 0;
  out(`\n[${phase}] action        calls    ok    p50ms   p95ms    max   errors`);
  for (const [k, v] of [...ph].sort()) {
    const e = [...v.errs.values()].reduce((a, b) => a + b, 0);
    reqs += v.times.length; errs += e;
    const errStr = e ? [...v.errs].map(([st, n]) => `${n}×${st === -1 ? "t/o" : st}`).join(",") : "-";
    out(`${k.padEnd(20)} ${String(v.times.length).padStart(6)} ${String(v.ok).padStart(5)} ${String(Math.round(pct(v.times, 50))).padStart(8)} ${String(Math.round(pct(v.times, 95))).padStart(7)} ${String(Math.round(Math.max(0, ...v.times))).padStart(6)}   ${errStr}`);
    if (v.sampleErr) out(`   └ ${v.sampleErr}`);
  }
  return { reqs, errs };
}
const jitter = (max = 60) => new Promise((r) => setTimeout(r, Math.random() * max));

// ── the simulated teacher session (DB-only) ──────────────────────────────
const FIRST = ["Amara", "Ben", "Chloe", "Deven", "Elif", "Farah", "Gus", "Hana", "Ines", "Jae", "Kofi", "Lena", "Marc", "Nia", "Omar", "Priya", "Quinn", "Rosa", "Sam", "Tessa", "Uma", "Vik", "Wren", "Xiu", "Yara", "Zane"];
function fakeSubmission(teacher, n, big = false) {
  return {
    id: `${teacher}-sub-${n}`,
    studentName: `${FIRST[n % 26]} ${FIRST[(n + 7) % 26]}`,
    subject: "Science", score: 17.5, outOf: 20,
    resultJson: {
      overall: "17.5/20",
      annotations: Array.from({ length: 8 }, (_, q) => ({
        questionLabel: `Knowledge ${q + 1}`, earnedMark: q === 2 ? "3.75" : "5", outOfMark: "5",
        correct: q !== 2, feedback: "Right method — arithmetic slip in the last line. Show the substitution next time.",
      })),
      rawText: "x".repeat(big ? 6000 : 6000),
    },
    createdAt: new Date().toISOString(),
  };
}
async function teacherSession(uid) {
  const id = tid(`${RUN}-u${uid}`);
  await call("save_profile", { teacherId: id, name: `Load Teacher ${uid}`, school: "Scaling Test HS", region: "ca-on" });
  await jitter();
  await call("save_collection", { teacherId: id, kind: "classes", items: [{ id: `${id}-c1`, name: "SNC2D P1" }, { id: `${id}-c2`, name: "SNC2D P4" }] });
  await call("save_collection", { teacherId: id, kind: "students", items: Array.from({ length: 30 }, (_, n) => ({ id: `${id}-s${n}`, name: `${FIRST[n % 26]} ${FIRST[(n + 3) % 26]}`, studentId: `LT${n}` })) });
  await call("save_collection", { teacherId: id, kind: "student_class_links", items: Array.from({ length: 30 }, (_, n) => ({ studentId: `${id}-s${n}`, classId: `${id}-c${(n % 2) + 1}` })) });
  await jitter();
  await call("get_usage", { teacherId: id });
  await call("list_keys", { teacherId: id });
  for (let n = 0; n < 3; n++) await call("save_submission", { teacherId: id, submission: fakeSubmission(id, n) });
  await call("list_submissions", { teacherId: id });
  await call("get_collection", { teacherId: id, kind: "classes" });
  await call("search_schools", { query: "north" });
}
async function markingProbe(uid) {
  await call("mark_responses", {
    teacherId: tid(`${RUN}-u${uid}`), harshness: 5, subject: "Science", gradeLevel: 10,
    questions: [
      { prompt: "State Newton's second law.", maxMarks: 2, keyAnswer: "F = ma", answers: [{ i: 0, text: "F = ma" }, { i: 1, text: "Force equals mass times acceleration" }] },
      { prompt: "What is the SI unit of force?", maxMarks: 1, keyAnswer: "The newton (N)", answers: [{ i: 0, text: "The newton" }, { i: 1, text: "kg" }] },
    ],
  });
}
const guardProbe = () => call("list_batches", { teacherId: `${RUN}-someone-else` }, { expectStatus: 403 });

// ── modes ────────────────────────────────────────────────────────────────
async function runStage(label, users, { loops = LOOPS, markBudget = 0 } = {}) {
  PHASE = label;
  let marked = 0;
  const t0 = performance.now();
  const work = [];
  for (let u = 0; u < users; u++) {
    work.push((async () => {
      for (let l = 0; l < loops; l++) await teacherSession(u);
      if (marked < markBudget) { marked++; await markingProbe(u); }
    })());
  }
  work.push(guardProbe());
  await Promise.all(work);
  const secs = (performance.now() - t0) / 1000;
  const { reqs, errs } = phaseReport(label);
  out(`[${label}] ${users} teachers → ${reqs} requests in ${secs.toFixed(1)}s (${(reqs / secs).toFixed(1)} req/s), errors ${errs} (${((errs / (reqs || 1)) * 100).toFixed(1)}%)`);
  return { reqs, errs, secs };
}

async function modeRamp() {
  out(`RAMP ${RUN}: stages ${STAGES.join(" → ")}, loops ${LOOPS}, marking ${MARKING_CALLS}`);
  let markLeft = MARKING_CALLS;
  for (const users of STAGES) {
    const budget = Math.min(markLeft, users); markLeft -= budget;
    const { reqs, errs } = await runStage(`ramp-${users}`, users, { markBudget: budget });
    if (reqs > 0 && errs / reqs > 0.5) { out("over half failing — stopping the ramp rather than hammering a struggling backend"); break; }
    await new Promise((r) => setTimeout(r, 3000));
  }
}

async function modeSpike() {
  out(`SPIKE ${RUN}: steady ${SPIKE_FROM} → jump to ${SPIKE_TO}`);
  await runStage(`spike-steady-${SPIKE_FROM}`, SPIKE_FROM);
  out("…jumping now…");
  await runStage(`spike-jump-${SPIKE_TO}`, SPIKE_TO);
}

async function modeSoak() {
  out(`SOAK ${RUN}: ${SOAK_VUS} teachers looping for ${SOAK_MINUTES} minutes`);
  const end = Date.now() + SOAK_MINUTES * 60_000;
  let window = 0;
  while (Date.now() < end) {
    PHASE = `soak-w${String(window).padStart(3, "0")}`;
    const wEnd = Math.min(end, Date.now() + 5 * 60_000);
    const runners = Array.from({ length: SOAK_VUS }, (_, u) => (async () => {
      while (Date.now() < wEnd) { await teacherSession(u); await jitter(400); }
    })());
    await Promise.all(runners);
    const { reqs, errs } = phaseReport(PHASE);
    out(`[${PHASE}] ${new Date().toISOString()} window done: ${reqs} reqs, ${errs} errs`);
    window++;
  }
  // Drift summary: first full window vs last full window, per action p95.
  const keys = [...phases.keys()].filter((k) => k.startsWith("soak-w"));
  if (keys.length >= 2) {
    const a = phases.get(keys[0]), b = phases.get(keys[keys.length - 1]);
    out("\nDRIFT first window → last window (p95 ms):");
    for (const k of [...a.keys()].sort()) {
      const p1 = Math.round(pct(a.get(k)?.times ?? [], 95));
      const p2 = Math.round(pct(b.get(k)?.times ?? [], 95));
      out(`  ${k.padEnd(20)} ${String(p1).padStart(6)} → ${String(p2).padStart(6)}  ${p2 > p1 * 1.5 ? "⚠ drifting" : "stable"}`);
    }
  }
}

async function modeVolume() {
  // With --jwt both identities collapse onto the token's account (the guard
  // permits no other), so the hot/cold comparison loses meaning there.
  const hot = tid(`${RUN}-volume-hot`), cold = tid(`${RUN}-volume-cold`);
  out(`VOLUME ${RUN}: seeding ${VOLUME_ROWS} submissions (~${Math.round(VOLUME_ROWS * 8 / 1024)}MB) onto one account, plus a roster at the 5000-item cap`);
  out(`(5M rows is not honest against a 500MB free-tier database — this is the worst realistic single account instead)`);
  PHASE = "volume-baseline";
  await call("save_profile", { teacherId: cold, name: "Cold Teacher", school: "Volume Test HS", region: "ca-on" });
  await call("save_submission", { teacherId: cold, submission: fakeSubmission(cold, 0) });
  for (let i = 0; i < 10; i++) await call("list_submissions", { teacherId: cold });
  phaseReport("volume-baseline");

  PHASE = "volume-seed";
  await call("save_profile", { teacherId: hot, name: "Hot Teacher", school: "Volume Test HS", region: "ca-on" });
  const t0 = performance.now();
  for (let start = 0; start < VOLUME_ROWS; start += 50) {
    await Promise.all(Array.from({ length: Math.min(50, VOLUME_ROWS - start) }, (_, j) =>
      call("save_submission", { teacherId: hot, submission: fakeSubmission(hot, start + j) })));
    if ((start / 50) % 10 === 0) out(`  seeded ${start}/${VOLUME_ROWS}…`);
  }
  out(`  seeding took ${((performance.now() - t0) / 1000).toFixed(0)}s`);
  await call("save_collection", { teacherId: hot, kind: "students", items: Array.from({ length: 5000 }, (_, n) => ({ id: `${hot}-s${n}`, name: `Student ${n}`, studentId: `V${n}` })) });
  phaseReport("volume-seed");

  PHASE = "volume-hot-reads";
  for (let i = 0; i < 10; i++) await call("list_submissions", { teacherId: hot });
  for (let i = 0; i < 5; i++) await call("get_collection", { teacherId: hot, kind: "students" });
  await call("save_submission", { teacherId: hot, submission: fakeSubmission(hot, VOLUME_ROWS + 1) });
  await call("get_usage", { teacherId: hot });
  phaseReport("volume-hot-reads");
  out("\ncompare [volume-baseline] list_submissions (1 row) against [volume-hot-reads] (500-row page of ~8KB payloads).");
}

// ── run ──────────────────────────────────────────────────────────────────
const t0 = performance.now();
if (MODE === "ramp") await modeRamp();
else if (MODE === "spike") await modeSpike();
else if (MODE === "soak") await modeSoak();
else if (MODE === "volume") await modeVolume();
else { console.error(`unknown --mode ${MODE}`); process.exit(1); }
out(`\ntotal wall time ${((performance.now() - t0) / 1000 / 60).toFixed(1)} min`);
out(`cleanup (Supabase SQL editor):
  delete from submissions_cloud where teacher_id like 'loadtest-%';
  delete from collections_cloud where teacher_id like 'loadtest-%';
  delete from usage_log         where teacher_id like 'loadtest-%';
  delete from profiles          where teacher_id like 'loadtest-%';`);
