/**
 * Serves ./out the way GitHub Pages will: mounted under the project's base
 * path, so /ai-marking-dreamflow/ is the home page and /ai-marking-dreamflow/
 * privacy.html is the privacy policy. Checking the export at the root would
 * pass while the real deploy 404s on every asset.
 *
 *   node scripts/serve-export.mjs [port]
 */
import { createServer } from 'node:http';
import { createReadStream, statSync } from 'node:fs';
import { extname, join, normalize, resolve } from 'node:path';

const PORT = Number(process.argv[2] ?? 4321);
const ROOT = resolve(process.cwd(), 'out');
const BASE = (process.env.MARKLESS_BASE_PATH ?? '/ai-marking-dreamflow').replace(/\/$/, '');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

function resolveFile(urlPath) {
  let p = decodeURIComponent(urlPath.split('?')[0]);
  if (BASE && p.startsWith(BASE)) p = p.slice(BASE.length);
  if (!p.startsWith('/')) p = `/${p}`;
  const safe = normalize(p).replace(/^(\.\.[/\\])+/, '');
  let file = join(ROOT, safe);
  try {
    if (statSync(file).isDirectory()) file = join(file, 'index.html');
    statSync(file);
    return file;
  } catch {
    try {
      const html = `${file.replace(/\/$/, '')}.html`;
      statSync(html);
      return html;
    } catch {
      return null;
    }
  }
}

createServer((req, res) => {
  const file = resolveFile(req.url ?? '/');
  if (!file) {
    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end(`404 ${req.url}`);
    return;
  }
  res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' });
  createReadStream(file).pipe(res);
}).listen(PORT, () => {
  console.log(`Serving ./out at http://localhost:${PORT}${BASE}/`);
});
