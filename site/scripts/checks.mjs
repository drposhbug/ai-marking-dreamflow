/**
 * Behaviour checks against a running copy of the site. Everything here is
 * something a screenshot cannot tell you: whether the tabs answer the keyboard,
 * whether focus is visible, whether the pinned section really releases, and
 * whether the reduced-motion layout is genuinely static.
 *
 *   node scripts/checks.mjs [url]
 *
 * Playwright is deliberately NOT a dependency of this package: the deploy
 * script runs `npm ci`, and a 100MB browser download has no business in a
 * marketing-site build. Install it when you want to run these:
 *
 *   npm install --no-save playwright && npx playwright install chromium
 *
 */
import { chromium } from 'playwright';

const URL_ = process.argv[2] ?? 'http://localhost:4321/ai-marking-dreamflow/';
const browser = await chromium.launch();
let failures = 0;

const ok = (name, pass, detail = '') => {
  if (!pass) failures += 1;
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
};

/* ---------------------------------------------------------------- normal */
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(URL_, { waitUntil: 'networkidle' });
  await page.addStyleTag({ content: 'html{scroll-behavior:auto !important}' });
  await page.waitForTimeout(600);

  // --- headings and landmarks
  const structure = await page.evaluate(() => ({
    h1: document.querySelectorAll('h1').length,
    h1text: document.querySelector('h1')?.textContent?.trim().slice(0, 40),
    main: !!document.querySelector('main#main'),
    skip: !!document.querySelector('a.skip'),
    imgsWithoutAlt: [...document.querySelectorAll('img')].filter((i) => !i.alt).length,
    figuresWithoutCaption: [...document.querySelectorAll('figure.illo')].filter(
      (f) => !f.querySelector('figcaption'),
    ).length,
    illustrationCaptions: [...document.querySelectorAll('figure.illo figcaption')].map((c) =>
      c.textContent.toLowerCase(),
    ),
    roleImgWithoutLabel: [...document.querySelectorAll('[role="img"]')].filter(
      (e) => !e.getAttribute('aria-label'),
    ).length,
  }));
  ok('exactly one h1', structure.h1 === 1, structure.h1text);
  ok('main landmark and skip link', structure.main && structure.skip);
  ok('every img has alt text', structure.imgsWithoutAlt === 0);
  ok('every illustration figure has a caption', structure.figuresWithoutCaption === 0);
  ok('every role="img" has a label', structure.roleImgWithoutLabel === 0);
  const captionsSayIllustration = structure.illustrationCaptions.every(
    (c) => c.includes('illustration') || c.includes('not a screenshot') || c.includes('not screenshots'),
  );
  ok(
    'every product visual is captioned as an illustration',
    captionsSayIllustration,
    `${structure.illustrationCaptions.length} captions`,
  );

  // --- no invented statistics
  const body = await page.evaluate(() => document.body.innerText);
  const banned = [/\d+%\s+of\s+(teachers|organi|schools|users)/i, /\bsaves? (you )?\d+\s*(hours|hrs)/i,
    /\b\d[\d,]*\+?\s+(teachers|schools|users|downloads)\b/i, /\b\d(\.\d)?\s*(stars|\/\s*5 stars)/i];
  const hits = banned.filter((r) => r.test(body)).map(String);
  ok('no invented statistics or social proof', hits.length === 0, hits.join(' '));
  ok('says it is not on an app store', /not on any app store yet/i.test(body));
  ok('carries the browser redaction caveat', /in a browser/i.test(body) && /blackout does not run|nothing is blacked out/i.test(body));
  ok('Limits panel says redaction is best-effort on name fields', /Redaction covers name\s*fields/i.test(body));

  // --- tabs answer the keyboard
  await page.locator('[role="tab"]').first().focus();
  const before = await page.locator('[role="tab"][aria-selected="true"]').textContent();
  await page.keyboard.press('ArrowRight');
  await page.waitForTimeout(250);
  const after = await page.locator('[role="tab"][aria-selected="true"]').textContent();
  ok('ArrowRight moves the route tabs', before !== after, `${before} -> ${after}`);
  await page.keyboard.press('End');
  await page.waitForTimeout(250);
  const last = await page.locator('[role="tab"][aria-selected="true"]').textContent();
  ok('End jumps to the last route tab', /Photograph/.test(last ?? ''), last?.trim());
  const panelText = await page.locator('[role="tabpanel"]').innerText();
  ok('the panel follows the tab', /Prop the phone/i.test(panelText));

  // --- focus is visible
  const focusRing = await page.evaluate(() => {
    const a = document.querySelector('.site-nav a');
    a.focus();
    const cs = getComputedStyle(a);
    return { width: cs.outlineWidth, style: cs.outlineStyle };
  });
  ok('focused links show an outline', focusRing.style !== 'none' && parseFloat(focusRing.width) >= 2,
    `${focusRing.style} ${focusRing.width}`);

  // --- the pin: engages, advances, and releases
  const seq = await page.evaluate(async () => {
    const track = document.querySelector('.seq-track');
    const sticky = document.querySelector('.seq-sticky');
    const top = track.getBoundingClientRect().top + window.scrollY;
    const travel = track.offsetHeight - window.innerHeight;
    const sample = async (p) => {
      window.scrollTo(0, top + p * travel);
      await new Promise((r) => setTimeout(r, 260));
      return {
        stickyTop: Math.round(sticky.getBoundingClientRect().top),
        counter: document.querySelector('.seq-count').textContent.trim(),
        visible: [...document.querySelectorAll('.seq-stage')]
          .map((s, i) => (Number(getComputedStyle(s).opacity) > 0.5 ? i : -1))
          .filter((i) => i >= 0),
      };
    };
    const out = {};
    for (const p of [0.02, 0.3, 0.5, 0.7, 0.98]) out[p] = await sample(p);
    // Past the end the sticky must have let go and be scrolling away.
    window.scrollTo(0, top + travel + window.innerHeight * 0.6);
    await new Promise((r) => setTimeout(r, 260));
    out.released = Math.round(sticky.getBoundingClientRect().top);
    out.headerH = Math.round(document.querySelector('.site-header').getBoundingClientRect().height);
    return out;
  });
  const pinned = [0.02, 0.3, 0.5, 0.7, 0.98].every(
    (p) => Math.abs(seq[p].stickyTop - seq.headerH) <= 2,
  );
  ok('the section stays pinned under the header while scrolling', pinned,
    [0.02, 0.3, 0.5, 0.7, 0.98].map((p) => seq[p].stickyTop).join(','));
  const counters = [0.02, 0.3, 0.5, 0.7, 0.98].map((p) => seq[p].counter);
  ok('the stage advances 01 -> 05', counters.join('|') === '01 / 05|02 / 05|03 / 05|04 / 05|05 / 05',
    counters.join(' '));
  const oneAtATime = [0.02, 0.3, 0.5, 0.7, 0.98].every((p) => seq[p].visible.length === 1);
  ok('exactly one stage is visible at each dwell point', oneAtATime,
    JSON.stringify([0.02, 0.3, 0.5, 0.7, 0.98].map((p) => seq[p].visible)));
  ok('the pin releases at the end', seq.released < 0, `sticky top ${seq.released}px`);

  // --- the rail jumps to a stage
  await page.locator('.seq-rail button', { hasText: 'Export' }).click();
  await page.waitForTimeout(700);
  const afterJump = await page.locator('.seq-count').textContent();
  ok('a rail button jumps to its stage', /05 \/ 05/.test(afterJump ?? ''), afterJump?.trim());

  // --- flip cards actually turn
  const flip = await page.evaluate(async () => {
    const grid = document.querySelector('.flip-grid');
    const top = grid.getBoundingClientRect().top + window.scrollY;
    const at = async (frac) => {
      window.scrollTo(0, top - window.innerHeight * frac);
      await new Promise((r) => setTimeout(r, 300));
      const m = getComputedStyle(document.querySelector('.flip-inner')).transform;
      return m;
    };
    return { front: await at(0.98), back: await at(0.1) };
  });
  ok('a flip card is unrotated as it arrives', flip.front === 'none' || flip.front.includes('matrix(1, 0, 0, 1'), flip.front.slice(0, 40));
  ok('a flip card has turned once it is up the page', flip.back !== flip.front, flip.back.slice(0, 40));

  ok('no page errors', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

/* -------------------------------------------------------- reduced motion */
{
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    reducedMotion: 'reduce',
  });
  const page = await ctx.newPage();
  await page.goto(URL_, { waitUntil: 'networkidle' });
  await page.waitForTimeout(600);

  const r = await page.evaluate(() => {
    const sticky = getComputedStyle(document.querySelector('.seq-sticky'));
    const stages = [...document.querySelectorAll('.seq-stage')];
    const faces = [...document.querySelectorAll('.flip-face--back')];
    return {
      stickyPosition: sticky.position,
      trackHeight: document.querySelector('.seq-track').offsetHeight,
      viewport: window.innerHeight,
      stageOpacities: stages.map((s) => Number(getComputedStyle(s).opacity)),
      stagePositions: stages.map((s) => getComputedStyle(s).position),
      // Stacked, not overlapping: each stage starts below the previous one.
      inOrder: stages.every((s, i) =>
        i === 0 ? true : s.getBoundingClientRect().top > stages[i - 1].getBoundingClientRect().top + 50),
      backFacesUpright: faces.every((f) => {
        const t = getComputedStyle(f).transform;
        return t === 'none' || t.startsWith('matrix(1, 0, 0, 1');
      }),
      railHidden: getComputedStyle(document.querySelector('.seq-rail')).display === 'none',
      htmlScroll: getComputedStyle(document.documentElement).scrollBehavior,
    };
  });
  ok('reduced motion: the sequence is not pinned', r.stickyPosition === 'static', r.stickyPosition);
  ok('reduced motion: the track is no taller than its content', r.trackHeight < r.viewport * 5,
    `${r.trackHeight}px`);
  ok('reduced motion: every stage is fully visible', r.stageOpacities.every((o) => o === 1),
    r.stageOpacities.join(','));
  ok('reduced motion: stages are in flow', r.stagePositions.every((p) => p === 'static') && r.inOrder);
  ok('reduced motion: flip cards are not rotated', r.backFacesUpright);
  ok('reduced motion: the scrub rail is hidden', r.railHidden);
  ok('reduced motion: smooth scrolling is off', r.htmlScroll === 'auto', r.htmlScroll);
  await ctx.close();
}

await browser.close();
console.log(failures === 0 ? '\nall checks passed' : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
