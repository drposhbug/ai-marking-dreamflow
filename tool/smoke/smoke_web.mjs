// Smoke test of the live web app as a judge would use it: open it on a phone-
// sized Chrome, tap "Try it as a guest", and wait for the four sample papers
// to come back marked. Exits non-zero on any failure.
//
//   cd tool/smoke && npm install && node smoke_web.mjs [url]
//
// Each run creates one guest account; its sample marks come from the cache.
import { chromium, devices } from 'playwright-core';
import os from 'node:os';
import path from 'node:path';

const URL = process.argv[2] ?? 'https://umarkless.com/app';
const SHOT = path.join(os.tmpdir(), 'umarkless-smoke.png');
const problems = [];
let marked = 0;

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await (await browser.newContext({ ...devices['Pixel 7'] })).newPage();
page.on('pageerror', (e) => problems.push(`page error: ${String(e).slice(0, 200)}`));
page.on('response', async (r) => {
  const u = r.url();
  if (!u.includes('supabase.co') || u.includes('STRIPE-CHECKOUT')) return;
  const body = await r.text().catch(() => '');
  // A grade is the one MARKING-PROCESS call with no "action".
  if (u.includes('MARKING-PROCESS') && r.status() === 200 && !/"action"/.test(r.request().postData() ?? '')) marked++;
  // The first call after sign-in can hit a clock blip the app retries.
  if (r.status() >= 400 && !body.includes('JWT issued at future')) problems.push(`HTTP ${r.status()} ${u.split('?')[0]}: ${body.slice(0, 160)}`);
});

try {
  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForTimeout(9000);
  // Flutter draws to a canvas; its accessibility tree has the real labels.
  await page.locator('flt-semantics-placeholder').click({ force: true }).catch(() => {});
  await page.getByText(/try it as a guest/i).first().click({ force: true, timeout: 15000 });
  for (let s = 0; s < 60 && marked < 4; s++) await page.waitForTimeout(1000);
  if (marked < 4) problems.push(`only ${marked} of 4 sample papers came back marked within 60 s`);
} catch (e) {
  problems.push(String(e).split('\n')[0]);
} finally {
  await page.screenshot({ path: SHOT }).catch(() => {});
  await browser.close();
}

console.log(`sample papers marked: ${marked}/4   screenshot: ${SHOT}`);
for (const p of problems) console.log(`FAIL ${p}`);
process.exit(problems.length ? 1 : 0);
