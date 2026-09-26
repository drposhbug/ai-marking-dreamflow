/**
 * Renders worksheet.html's three layers to the PNG textures the Blender scene
 * uses, into site/art/textures/.
 *
 *   node site/art/render_textures.mjs
 *
 * It checks its own output instead of trusting it, because a texture that
 * silently fell back to a system font, or had a line of working run off the
 * edge of the page, looks fake in exactly the way this exists to fix:
 *
 *   - every web font the sheet uses must have actually loaded;
 *   - no text may extend past the edge of the sheet or the phone screen.
 *
 * Needs Playwright, which the site deliberately does not depend on:
 *   cd site && npm install --no-save playwright && npx playwright install chromium
 */
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from '../node_modules/playwright/index.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, 'textures');
mkdirSync(OUT, { recursive: true });

const LAYERS = [
  { layer: 'paper', selector: '.sheet', file: 'sheet.png' },
  { layer: 'scan', selector: '.phone', file: 'phone-scan.png' },
  { layer: 'marked', selector: '.phone', file: 'phone-marked.png' },
];

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2000, height: 2800 } });
let failed = false;

for (const { layer, selector, file } of LAYERS) {
  const url = `${pathToFileURL(join(HERE, 'worksheet.html')).href}?layer=${layer}`;
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForSelector('body[data-ready="1"]');

  const report = await page.evaluate(({ selector }) => {
    const box = document.querySelector(selector).getBoundingClientRect();
    // Checked against what is actually drawn, not a fixed list: a face a
    // layer never uses is never loaded, and reporting it missing is noise.
    // What matters is whether any VISIBLE text fell back to a system font.
    const visible = [...document.querySelectorAll(`${selector} *`)].filter((el) => {
      if (el.childElementCount !== 0 || !el.textContent.trim()) return false;
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden';
    });
    const missing = [...new Set(visible.map((el) => {
      const cs = getComputedStyle(el);
      const family = cs.fontFamily.split(',')[0].trim().replace(/^["']|["']$/g, '');
      return `${cs.fontWeight} 40px "${family}"`;
    }))].filter((f) => !document.fonts.check(f));
    // Anything with text in it that reaches outside the thing it is printed on.
    const spills = [...document.querySelectorAll(`${selector} *`)]
      .filter((el) => el.childElementCount === 0 && el.textContent.trim())
      .map((el) => ({ text: el.textContent.trim().slice(0, 40), r: el.getBoundingClientRect() }))
      .filter(({ r }) => r.width && (r.left < box.left - 1 || r.right > box.right + 1 ||
                                     r.top < box.top - 1 || r.bottom > box.bottom + 1))
      .map(({ text }) => text);
    // In the viewfinder the whole page and its detected edge must be on the
    // screen — "page found" over a page with a corner cut off is a lie.
    const frame = document.querySelector(`${selector} .frame`);
    const clipped = [];
    if (frame) {
      for (const el of frame.querySelectorAll('.edge, .bracket')) {
        const r = el.getBoundingClientRect();
        if (r.left < box.left || r.right > box.right || r.top < box.top || r.bottom > box.bottom) {
          clipped.push(el.className);
        }
      }
    }
    return { size: `${Math.round(box.width)}x${Math.round(box.height)}`, missing, spills, clipped };
  }, { selector });

  // The phone layers draw a scaled copy of the sheet that is meant to run
  // past the screen's edge, like a real viewfinder; only the sheet itself
  // has to fit.
  const spills = layer === 'paper' ? report.spills : [];
  const clipped = report.clipped || [];
  const ok = report.missing.length === 0 && spills.length === 0 && clipped.length === 0;
  if (!ok) failed = true;
  await page.locator(selector).screenshot({ path: join(OUT, file), omitBackground: true });
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${file} ${report.size}` +
    (report.missing.length ? `  fonts missing: ${report.missing.join(', ')}` : '') +
    (spills.length ? `  off the page: ${spills.join(' | ')}` : '') +
    (clipped.length ? `  viewfinder clips: ${clipped.join(', ')}` : ''));
}

await browser.close();
process.exit(failed ? 1 : 0);
