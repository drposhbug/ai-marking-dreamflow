/**
 * Screenshots the site at the widths that matter, and walks the pinned
 * sequence so the scroll animation is actually exercised rather than assumed.
 *
 *   node scripts/shots.mjs <url> <outDir> [viewportKeys] [--reduced]
 *
 * viewportKeys is a comma list of: w2557, w1920, w1440, w1280, w390
 *
 * Playwright is deliberately NOT a dependency of this package: the deploy
 * script runs `npm ci`, and a 100MB browser download has no business in a
 * marketing-site build. Install it when you want to run these:
 *
 *   npm install --no-save playwright && npx playwright install chromium
 *
 */
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright';

const URL_ = process.argv[2] ?? 'http://localhost:3100/ai-marking-dreamflow/';
const OUT = process.argv[3] ?? 'shots';
const WHICH = (process.argv[4] ?? 'w2557,w1920,w1440,w1280,w390').split(',');
const REDUCED = process.argv.includes('--reduced');
const DARK = process.argv.includes('--dark');

const VIEWPORTS = {
  w2557: { width: 2557, height: 1300 },
  w1920: { width: 1920, height: 1080 },
  w1440: { width: 1440, height: 900 },
  w1280: { width: 1280, height: 800 },
  w390: { width: 390, height: 844 },
};

const ANCHORS = ['how', 'marking', 'beliefs', 'privacy', 'pricing', 'signin'];

mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();

for (const key of WHICH) {
  const viewport = VIEWPORTS[key];
  if (!viewport) continue;

  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: 1,
    reducedMotion: REDUCED ? 'reduce' : 'no-preference',
    colorScheme: DARK ? 'dark' : 'light',
  });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });

  await page.goto(URL_, { waitUntil: 'networkidle' });
  await page.addStyleTag({ content: 'html { scroll-behavior: auto !important; }' });
  await page.waitForTimeout(900);

  const tag = `${key}${REDUCED ? '-reduced' : ''}${DARK ? '-dark' : ''}`;
  const shot = async (name) => {
    await page.waitForTimeout(320);
    await page.screenshot({ path: join(OUT, `${tag}-${name}.png`) });
  };


  await shot('01-hero');

  // The pinned sequence, walked from before the pin to after the release.
  const track = await page.evaluate(() => {
    const el = document.querySelector('.seq-track');
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { top: r.top + window.scrollY, height: el.offsetHeight, vh: window.innerHeight };
  });

  if (track && track.height > track.vh * 1.5) {
    const travel = track.height - track.vh;
    const points = [
      ['seq-before', -0.06],
      ['seq-p05', 0.05],
      ['seq-p25', 0.25],
      ['seq-p45', 0.45],
      ['seq-p65', 0.65],
      ['seq-p85', 0.85],
      ['seq-p99', 0.99],
      ['seq-after', 1.09],
    ];
    for (const [name, p] of points) {
      await page.evaluate((y) => window.scrollTo(0, y), track.top + p * travel);
      await shot(`02-${name}`);
    }
    // What the rail reports at the end, as a sanity check on the stage maths.
    const state = await page.evaluate(() => {
      const c = document.querySelector('.seq-count');
      const on = [...document.querySelectorAll('.seq-stage')].map((s) =>
        Number(getComputedStyle(s).opacity).toFixed(2),
      );
      return { counter: c ? c.textContent : null, opacities: on };
    });
    console.log(`  ${tag} sequence at p=1.09:`, JSON.stringify(state));
  } else {
    await page.evaluate(() => document.querySelector('#sequence')?.scrollIntoView());
    await shot('02-seq-static');
    await page.evaluate(() => window.scrollBy(0, window.innerHeight * 0.9));
    await shot('02-seq-static-2');
    await page.evaluate(() => window.scrollBy(0, window.innerHeight * 0.9));
    await shot('02-seq-static-3');
  }

  for (const [i, id] of ANCHORS.entries()) {
    await page.evaluate((sel) => {
      const el = document.querySelector(sel);
      if (el) window.scrollTo(0, el.getBoundingClientRect().top + window.scrollY - 70);
    }, `#${id}`);
    await shot(`0${i + 3}-${id}`);
    // Flip cards need a second look further down: by the time the section top
    // is at the top of the screen the cards have not turned yet.
    if (id === 'marking') {
      // Walk the flip: the cards are below the fold showing their answers when
      // the section arrives, and turn as they rise.
      const grid = await page.evaluate(() => {
        const el = document.querySelector('.flip-grid');
        return el ? el.getBoundingClientRect().top + window.scrollY : null;
      });
      if (grid !== null) {
        for (const [name, frac] of [['front', 0.95], ['mid', 0.62], ['back', 0.3]]) {
          await page.evaluate((y) => window.scrollTo(0, y), grid - viewport.height * frac);
          await shot(`0${i + 3}-${id}-${name}`);
        }
      }
    }
  }

  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await shot('09-footer');

  const height = await page.evaluate(() => document.documentElement.scrollHeight);
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  console.log(`${tag}: page ${height}px tall, horizontal overflow ${overflow}px, ${errors.length} console error(s)`);
  errors.slice(0, 5).forEach((e) => console.log('   !', e));

  await context.close();
}

await browser.close();
console.log('done');
