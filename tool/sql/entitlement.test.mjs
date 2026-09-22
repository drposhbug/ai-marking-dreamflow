/**
 * Runs the REAL SQL out of SETUP-DB/index.ts against Postgres-compiled-to-WASM,
 * so the entitlement rules are executed rather than reasoned about.
 *
 * The statements are extracted from the source file, not copied here: a copy
 * would pass forever after the original changed.
 */
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const SRC = new URL('../../supabase/functions/SETUP-DB/index.ts', import.meta.url);
const source = readFileSync(SRC, 'utf8');

// Every `await sql`...`` block, in file order. `sql.end()` has no backtick
// after `sql`, so it is not picked up.
const statements = [...source.matchAll(/await sql`([\s\S]*?)`/g)].map((m) => m[1].trim());
if (statements.length < 20) throw new Error(`only found ${statements.length} statements — extraction broke`);

const db = new PGlite();
let failures = 0;
const ok = (name, pass, detail = '') => {
  if (!pass) failures += 1;
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
};

// ---- build the schema exactly as SETUP-DB does ----------------------------
let ran = 0;
const skipped = [];
for (const stmt of statements) {
  try {
    await db.exec(stmt);
    ran += 1;
  } catch (e) {
    // Some of the wider schema may lean on things PGlite lacks. Anything
    // touching entitlement MUST run, so that is asserted separately below.
    skipped.push({ stmt: stmt.slice(0, 70).replace(/\s+/g, ' '), error: String(e.message ?? e) });
  }
}
console.log(`ran ${ran}/${statements.length} SETUP-DB statements`);
for (const s of skipped) console.log(`  skipped: ${s.stmt} … (${s.error.split('\n')[0]})`);

const entitlementBits = ['plan_rank', 'best_plan', 'best_plan_rail', 'apply_entitlement', 'plan_revenuecat'];
const skippedEntitlement = skipped.filter((s) => entitlementBits.some((b) => s.stmt.includes(b)));
ok('every entitlement statement ran', skippedEntitlement.length === 0, JSON.stringify(skippedEntitlement));

const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const apply = (teacher, rail, plan) => q('select * from public.apply_entitlement($1,$2,$3)', [teacher, rail, plan]);
const row = async (teacher) =>
  (await q('select plan, plan_source, plan_revenuecat, plan_stripe from public.profiles where teacher_id=$1', [teacher]))[0];

// ---- the ranking ----------------------------------------------------------
{
  const r = async (p) => (await q('select public.plan_rank($1) as n', [p]))[0].n;
  ok('school outranks pro', (await r('school')) > (await r('pro')));
  // pro_annual bills $10.00/mo against Pro's $14.99, so it must NOT win a tie
  // with Pro — that would hand out an allowance nobody paid for.
  ok('pro outranks pro_annual', (await r('pro')) > (await r('pro_annual')));
  ok('pro_annual outranks starter', (await r('pro_annual')) > (await r('starter')));
  ok('trial and nonsense rank zero', (await r('trial')) === 0 && (await r('nope')) === 0 && (await r(null)) === 0);
}

// ---- THE BUG THIS EXISTS TO FIX ------------------------------------------
{
  const t = 'teacher-both-rails';
  await apply(t, 'revenuecat', 'pro');   // Monday: subscribes on the phone
  await apply(t, 'stripe', 'pro');       // Tuesday: subscribes on the web too
  const before = await row(t);
  ok('paying on both rails is still one plan', before.plan === 'pro', JSON.stringify(before));

  await apply(t, 'revenuecat', 'trial'); // March: the phone subscription lapses
  const after = await row(t);
  // Before this change, that EXPIRATION set plan='trial' and cancelled a
  // subscription the teacher was still being charged for by Stripe.
  ok('a store cancellation does not cancel the web subscription',
    after.plan === 'pro' && after.plan_source === 'stripe', JSON.stringify(after));
  ok('the lapsed rail is recorded as lapsed', after.plan_revenuecat === 'trial', JSON.stringify(after));
}

// ---- the mirror image -----------------------------------------------------
{
  const t = 'teacher-web-then-store';
  await apply(t, 'stripe', 'starter');
  await apply(t, 'revenuecat', 'school');
  ok('the more generous rail wins', (await row(t)).plan === 'school');
  ok('and the app is told which shop to send them to', (await row(t)).plan_source === 'revenuecat');
  await apply(t, 'stripe', 'trial');   // cancels the web one
  const after = await row(t);
  ok('cancelling the weaker rail changes nothing they can see',
    after.plan === 'school' && after.plan_source === 'revenuecat', JSON.stringify(after));
}

// ---- losing everything ----------------------------------------------------
{
  const t = 'teacher-all-gone';
  await apply(t, 'revenuecat', 'pro');
  await apply(t, 'revenuecat', 'trial');
  const after = await row(t);
  ok('with nothing left they are on trial with no shop named',
    after.plan === 'trial' && after.plan_source === null, JSON.stringify(after));
}

// ---- a tie ----------------------------------------------------------------
{
  const t = 'teacher-tie';
  await apply(t, 'stripe', 'pro');
  await apply(t, 'revenuecat', 'pro');
  ok('a tie goes to the stores', (await row(t)).plan_source === 'revenuecat');
}

// ---- an unknown rail is refused, not silently applied ---------------------
{
  let threw = false;
  try { await apply('teacher-bad-rail', 'paypal', 'pro'); } catch { threw = true; }
  ok('an unknown billing rail is refused', threw);
  const r = await row('teacher-bad-rail');
  ok('and writes nothing at all', r === undefined, JSON.stringify(r));
}

// ---- the teacher does not have to exist first -----------------------------
{
  const t = 'teacher-brand-new';
  await apply(t, 'stripe', 'pro');
  ok('a first purchase creates the profile', (await row(t)).plan === 'pro');
}

// ---- the backfill of everyone who already had a plan ----------------------
{
  // A teacher as they exist today: plan set by the old RevenueCat webhook,
  // neither rail column written, because neither column existed.
  await q(`insert into public.profiles (teacher_id, plan) values ('teacher-legacy','pro')`);
  await q(`update public.profiles set plan_revenuecat=null, plan_stripe=null, plan_source=null where teacher_id='teacher-legacy'`);
  const backfills = statements.filter((s) => s.includes('plan_revenuecat = plan') || s.includes('best_plan(plan_revenuecat'));
  ok('both backfill statements were found in SETUP-DB', backfills.length === 2, `${backfills.length}`);
  for (const b of backfills) await db.exec(b);
  const after = await row('teacher-legacy');
  ok('an existing plan is credited to the stores, where it was actually bought',
    after.plan === 'pro' && after.plan_revenuecat === 'pro' && after.plan_source === 'revenuecat', JSON.stringify(after));

  // Someone mid-trial must not be handed a paid rail by the backfill.
  await q(`insert into public.profiles (teacher_id, plan) values ('teacher-trial','trial')`);
  for (const b of backfills) await db.exec(b);
  const t2 = await row('teacher-trial');
  ok('a teacher on trial is not credited with a subscription', t2.plan_revenuecat === null, JSON.stringify(t2));
}

// ---- running SETUP-DB twice must be safe ----------------------------------
{
  for (const stmt of statements) { try { await db.exec(stmt); } catch { /* same skips as above */ } }
  const after = await row('teacher-both-rails');
  ok('re-running SETUP-DB does not disturb a live account',
    after.plan === 'pro' && after.plan_source === 'stripe', JSON.stringify(after));
}

console.log(failures === 0 ? '\nall entitlement checks passed' : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
