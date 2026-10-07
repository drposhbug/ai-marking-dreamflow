// Marking accuracy check: marks real exam pages through the LIVE marking
// service, exactly as the app does, and scores the result against the exam
// board's official marks.
//
//   node tool/eval/run_eval.mjs [--score-only <run-folder>] [--pages 01,05]
//
// The pages live outside the repo (they belong to the exam boards), in
// EVAL_DIR (default %USERPROFILE%\markless-eval):
//   pages/NN.png + pages/NN.json   the page and its source / official marks
//   expected.json                  { "NN": { pct, drawing, shortAnswer? } }
//   runs/<date-time>/NN.json       what the app returned, per run
//   history.jsonl                  one line per run, to compare over time
//
// Each run signs up guest accounts (a free trial covers about 8 marks) and
// costs about $0.04 a page.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execSync } from 'node:child_process';

const EVAL = process.env.EVAL_DIR ?? path.join(os.homedir(), 'markless-eval');
const B = 'https://zxikjizraeqejbsncqpg.supabase.co';
const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };
const expected = JSON.parse(fs.readFileSync(path.join(EVAL, 'expected.json'), 'utf8'));
const only = opt('pages')?.split(',');
const pages = Object.keys(expected).filter((k) => !k.startsWith('_') && (!only || only.includes(k))).sort();

async function markAll(runDir) {
  const anon = (process.env.SUPABASE_ANON_KEY ??
    fs.readFileSync(path.join(os.homedir(), 'OneDrive', 'markless-keys', 'supa_anon.txt'), 'utf8')).split(/\r?\n/)[0].trim();
  let guest = null;
  let used = 0;
  const newGuest = async () => {
    const s = await (await fetch(`${B}/auth/v1/signup`, { method: 'POST', headers: { apikey: anon, 'content-type': 'application/json' }, body: '{}' })).json();
    if (!s.access_token) throw new Error(`guest sign-up failed: ${JSON.stringify(s).slice(0, 200)}`);
    await new Promise((r) => setTimeout(r, 3000)); // auth and functions clocks differ by a second or two
    guest = { token: s.access_token, id: s.user.id };
    used = 0;
  };
  for (const n of pages) {
    const img = ['png', 'jpg', 'jpeg'].map((x) => path.join(EVAL, 'pages', `${n}.${x}`)).find((p) => fs.existsSync(p));
    const meta = JSON.parse(fs.readFileSync(path.join(EVAL, 'pages', `${n}.json`), 'utf8'));
    if (!guest || used >= 6) await newGuest();
    for (let attempt = 1; attempt <= 2; attempt++) {
      // The same body AiGradingService.grade sends for a test with no key.
      const body = {
        teacherId: guest.id,
        imagesBase64: [fs.readFileSync(img).toString('base64')],
        mediaType: img.endsWith('.png') ? 'image/png' : 'image/jpeg',
        mode: 'testQuiz', maxScore: 25, criteria: [], harshness: 5, studentGrade: null,
        ...(meta.grade_level ? { expectationGrade: meta.grade_level } : {}),
        region: 'ca-on',
      };
      const r = await fetch(`${B}/functions/v1/MARKING-PROCESS`, {
        method: 'POST',
        headers: { apikey: anon, authorization: `Bearer ${guest.token}`, 'content-type': 'application/json' },
        body: JSON.stringify(body),
      });
      const result = await r.json().catch(() => ({}));
      if (r.status === 429 && attempt === 1) { await newGuest(); continue; }
      used++;
      fs.writeFileSync(path.join(runDir, `${n}.json`), JSON.stringify({ status: r.status, result }, null, 2));
      process.stdout.write(`${n} `);
      break;
    }
  }
  process.stdout.write('\n');
}

/** How one page's result compares with the official marks. */
export function scorePage(result, exp) {
  const notes = result?.annotations ?? [];
  const appPct = result?.percentageDisplay === 'Teacher to mark' || !(result?.maxScore > 0)
    ? null
    : (result.rawScore / result.maxScore) * 100;
  const flaggedDrawing = notes.some((a) => a.teacherCheck === true);
  const essayMarks = notes.filter((a) => /^(grammar|spelling|flow)/i.test(a.questionLabel ?? '')).length;
  return {
    appPct,
    error: appPct == null ? null : Math.abs(appPct - exp.pct),
    drawingOk: exp.drawing ? flaggedDrawing : !flaggedDrawing,
    shortAnswerOk: exp.shortAnswer ? essayMarks === 0 : true,
    // A single question carrying the whole fallback total is the old scale bug.
    scaleOk: !notes.some((a) => a.outOfMark === '/25'),
  };
}

const runDir = opt('score-only') ?? path.join(EVAL, 'runs', new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-'));
if (!opt('score-only')) {
  fs.mkdirSync(runDir, { recursive: true });
  await markAll(runDir);
}

const rows = pages.map((n) => {
  const file = path.join(runDir, `${n}.json`);
  if (!fs.existsSync(file)) return null;
  const saved = JSON.parse(fs.readFileSync(file, 'utf8'));
  return { n, ...scorePage(saved.result, expected[n]), want: expected[n].pct };
}).filter(Boolean);

const fmt = (v) => (v == null ? '  —' : `${Math.round(v)}`.padStart(3));
console.log(`\nPage  official  app  off by  drawing  short-ans  scale   (${path.basename(runDir)})`);
for (const r of rows) {
  console.log(`${r.n}       ${fmt(r.want)}%  ${fmt(r.appPct)}%   ${fmt(r.error)}    ${r.drawingOk ? ' ok ' : 'MISS'}      ${r.shortAnswerOk ? ' ok ' : 'ESSAY'}     ${r.scaleOk ? 'ok' : '/25'}`);
}
const scored = rows.filter((r) => r.error != null);
const summary = {
  run: path.basename(runDir),
  commit: (() => { try { return execSync('git rev-parse --short HEAD').toString().trim(); } catch { return ''; } })(),
  pages: rows.length,
  meanError: scored.length ? +(scored.reduce((s, r) => s + r.error, 0) / scored.length).toFixed(1) : null,
  within10: scored.filter((r) => r.error <= 10).length,
  drawingOk: rows.filter((r) => r.drawingOk).length,
  shortAnswerOk: rows.filter((r) => r.shortAnswerOk).length,
  scaleOk: rows.filter((r) => r.scaleOk).length,
};
console.log(`\nMean error ${summary.meanError} points · within 10 points ${summary.within10}/${scored.length} · drawings ${summary.drawingOk}/${rows.length} · short answers ${summary.shortAnswerOk}/${rows.length} · scale ${summary.scaleOk}/${rows.length}`);
fs.appendFileSync(path.join(EVAL, 'history.jsonl'), JSON.stringify(summary) + '\n');
