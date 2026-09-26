/**
 * Renders icon.html into every PNG the product shows a logo in, replacing
 * the blue tile from before the palette moved to the marked-paper scheme.
 *
 *   node site/art/render_icon.mjs
 *
 * It verifies its own colour: the centre-left of every tile must be the
 * chalkboard green family, and anything still blue fails the run — that is
 * the whole point of the exercise.
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from '../node_modules/playwright/index.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');
const url = (size, shape) => `${pathToFileURL(join(HERE, 'icon.html')).href}?size=${size}&shape=${shape}`;

/* Every logo file in the product, and the drawing that fills it. */
const OUT = [
  { file: 'web/favicon.png', size: 64, shape: 'tile' },
  { file: 'web/icons/Icon-192.png', size: 192, shape: 'tile' },
  { file: 'web/icons/Icon-512.png', size: 512, shape: 'tile' },
  { file: 'web/icons/Icon-maskable-192.png', size: 192, shape: 'square' },
  { file: 'web/icons/Icon-maskable-512.png', size: 512, shape: 'square' },
  { file: 'docs/icon.png', size: 512, shape: 'tile' },
  { file: 'site/public/icon.png', size: 512, shape: 'tile' },
  { file: 'assets/icons/markless_icon.png', size: 1024, shape: 'square' },
  { file: 'assets/icons/markless_icon_fg.png', size: 1024, shape: 'fg' },
];

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1100, height: 1100 } });
let failed = false;

for (const { file, size, shape } of OUT) {
  await page.goto(url(size, shape), { waitUntil: 'networkidle' });
  await page.waitForSelector('body[data-ready="1"]');
  const dest = join(REPO, file);
  await page.locator('#tile').screenshot({ path: dest, omitBackground: true });

  const check = await page.evaluate(async ({ shape }) => {
    const img = new Image();
    img.src = document.querySelector('svg') ? '' : '';
    // Sample the tile as painted: centre-left avoids the tick's stroke.
    const el = document.getElementById('tile');
    const c = document.createElement('canvas');
    const r = el.getBoundingClientRect();
    c.width = r.width; c.height = r.height;
    // html2canvas-free sampling: read the computed gradient is not possible,
    // so trust geometry and report the stroke colour instead.
    return { shape, w: r.width, h: r.height };
  }, { shape });
  console.log(`wrote ${file} (${check.w}x${check.h}, ${shape})`);
}

await browser.close();

/* Colour proof, off the actual bytes: decode each PNG in a fresh page and
   demand green-family pixels where the board is, transparency where the
   rounded corner is. */
const page2 = await (await chromium.launch()).newPage();
// A blank page has no origin, and an origin-less page may not load file://
// images. Stand on a file:// page first so the icons are same-scheme.
await page2.goto(pathToFileURL(join(HERE, 'icon.html')).href, { waitUntil: 'load' });
for (const { file, size, shape } of OUT) {
  // Bytes as a data: URL, because a file:// image taints the canvas and
  // getImageData is the entire point of this pass.
  const fileUrl = 'data:image/png;base64,' + readFileSync(join(REPO, file)).toString('base64');
  const r = await page2.evaluate(async ({ fileUrl, shape }) => {
    const img = new Image();
    img.src = fileUrl;
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; });
    const c = document.createElement('canvas');
    c.width = img.width; c.height = img.height;
    const ctx = c.getContext('2d');
    ctx.drawImage(img, 0, 0);
    const px = (x, y) => [...ctx.getImageData(Math.round(x), Math.round(y), 1, 1).data];
    const mid = px(img.width * 0.18, img.height * 0.55);
    const corner = px(1, 1);
    return { mid, corner };
  }, { fileUrl, shape });
  const [R, G, B] = r.mid;
  const boardish = shape === 'fg' ? r.mid[3] === 0 : G > R && G > B && B > R * 0.8 && G < 120;
  const cornerOk = shape === 'square' ? true : r.corner[3] === 0 || shape === 'fg';
  const ok = boardish && cornerOk;
  if (!ok) failed = true;
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${file}  mid rgba(${r.mid})  corner a=${r.corner[3]}`);
}

process.exit(failed ? 1 : 0);
