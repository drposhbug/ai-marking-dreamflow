/**
 * Measures whether the teacher's red marks land on top of the printed or
 * handwritten text on the sheet — the thing a screenshot would show at a
 * glance and a font check cannot.
 *
 *   node site/art/check_layout.mjs
 *
 * A mark overlapping the page's own printing reads as a rendering bug, not
 * as a teacher's pen. Ticks and crosses are allowed to sit beside an answer;
 * they are not allowed to sit on one.
 */
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from '../node_modules/playwright/index.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2000, height: 2800 } });
// The marked layer draws the sheet at half size inside a phone; the plain
// sheet with its marks switched on is the true-size one to measure.
await page.goto(`${pathToFileURL(join(HERE, 'worksheet.html')).href}?layer=paper`, { waitUntil: 'networkidle' });
await page.waitForSelector('body[data-ready="1"]');
await page.evaluate(() => document.querySelector('.sheet').classList.remove('unmarked'));

const clashes = await page.evaluate(() => {
  const r = (el) => el.getBoundingClientRect();
  const hit = (a, b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
  const label = (el) => (el.className || el.tagName) + ': ' + (el.textContent.trim().slice(0, 30) || '(shape)');

  const marks = [...document.querySelectorAll('.pen, .tick, .cross')];
  // Everything that is the page's own content: printed type and the pencil.
  const content = [...document.querySelectorAll('.sheet h1, .total, .prompt span, .prompt b, .field, .line .hand')];
  const out = [];
  for (const m of marks) for (const c of content) {
    if (m.contains(c) || c.contains(m)) continue;
    if (hit(r(m), r(c))) out.push(`${label(m)}  ON  ${label(c)}`);
  }
  // Marks on each other: two notes written over one another.
  for (let i = 0; i < marks.length; i++) for (let j = i + 1; j < marks.length; j++) {
    if (hit(r(marks[i]), r(marks[j]))) out.push(`${label(marks[i])}  ON  ${label(marks[j])}`);
  }
  return out;
});

await browser.close();
if (clashes.length) {
  console.log(`FAIL  ${clashes.length} mark(s) land on something:`);
  for (const c of clashes) console.log('   ' + c);
  process.exit(1);
}
console.log('OK   no red mark lands on the printing, the pencil, or another mark');
