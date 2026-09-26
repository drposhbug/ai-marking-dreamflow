/**
 * Renders worksheet.html's three marked quizzes to the PNG textures the
 * Blender scene lays on its sheets, into site/art/textures/.
 *
 *   node site/art/render_textures.mjs
 *
 * It checks its own output instead of trusting it, because a texture that
 * silently fell back to a system font, or had a line of working run off the
 * edge of the page, looks fake in exactly the way real type exists to fix:
 *
 *   - every face any visible text actually uses must have loaded;
 *   - no text may extend past the edge of the sheet.
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

const VARIANTS = [1, 2, 3];

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2000, height: 2800 } });
let failed = false;

for (const v of VARIANTS) {
  const url = `${pathToFileURL(join(HERE, 'worksheet.html')).href}?v=${v}`;
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForSelector('body[data-ready="1"]');

  const report = await page.evaluate(() => {
    const box = document.querySelector('.sheet').getBoundingClientRect();
    const visible = [...document.querySelectorAll('.sheet *')].filter((el) => {
      if (el.childElementCount !== 0 || !el.textContent.trim()) return false;
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden';
    });
    const missing = [...new Set(visible.map((el) => {
      const cs = getComputedStyle(el);
      const family = cs.fontFamily.split(',')[0].trim().replace(/^["']|["']$/g, '');
      return `${cs.fontWeight} 40px "${family}"`;
    }))].filter((f) => !document.fonts.check(f));
    const spills = visible
      .map((el) => ({ text: el.textContent.trim().slice(0, 40), r: el.getBoundingClientRect() }))
      .filter(({ r }) => r.left < box.left - 1 || r.right > box.right + 1 ||
                         r.top < box.top - 1 || r.bottom > box.bottom + 1)
      .map(({ text }) => text);
    return { size: `${Math.round(box.width)}x${Math.round(box.height)}`, missing, spills };
  });

  const ok = report.missing.length === 0 && report.spills.length === 0;
  if (!ok) failed = true;
  const file = `sheet-${v}.png`;
  await page.locator('.sheet').screenshot({ path: join(OUT, file), omitBackground: true });
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${file} ${report.size}` +
    (report.missing.length ? `  fonts missing: ${report.missing.join(', ')}` : '') +
    (report.spills.length ? `  off the page: ${report.spills.join(' | ')}` : ''));
}

await browser.close();
process.exit(failed ? 1 : 0);
