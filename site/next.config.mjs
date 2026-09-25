/**
 * UMarkless marketing site.
 *
 * Static export only. GitHub Pages serves files, not a Node server, so
 * `output: 'export'` is not an optimisation here - it is the deploy target.
 *
 * The site lives at https://drposhbug.github.io/ai-marking-dreamflow/, so every
 * emitted asset URL has to carry that prefix. Set MARKLESS_BASE_PATH=root to
 * build a root-served copy, for a custom domain.
 */
// PowerShell deletes an environment variable rather than setting it to an
// empty string, so a root deploy is spelled 'root' rather than ''.
const raw = process.env.MARKLESS_BASE_PATH;
const basePath = raw === undefined ? '/ai-marking-dreamflow' : raw === 'root' || raw === '/' ? '' : raw;

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  basePath,
  // Pages has no image optimiser behind it.
  images: { unoptimized: true },
  // /section/ rather than /section - harmless for a one-page site, and it keeps
  // any future page working on a plain file server without rewrites.
  trailingSlash: true,
  reactStrictMode: true,
  env: {
    // Read by the client so relative links (icon.png, app/) resolve under the
    // same prefix the exported HTML was built for.
    NEXT_PUBLIC_BASE_PATH: basePath,
  },
};

export default nextConfig;
