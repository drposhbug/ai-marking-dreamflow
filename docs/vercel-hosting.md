# Hosting Markless on Vercel

The repository can stay **private**. Vercel authenticates against GitHub, so
nothing has to be made public to deploy — which is the reason this exists
alongside the GitHub Pages setup rather than replacing it.

## Why this is a separate build from `docs/`

GitHub Pages serves a project site under the repository name; Vercel serves
from the root of a domain. That prefix is baked into the HTML **at build
time** — Next.js writes it into every asset URL, Flutter writes it into
`<base href>` — so one set of files cannot serve both.

| | GitHub Pages | Vercel |
|---|---|---|
| site | `/ai-marking-dreamflow/` | `/` |
| app | `/ai-marking-dreamflow/app/` | `/app/` |
| built by | `build_site.ps1` + `build_web.ps1` | `build_vercel.ps1` |
| committed? | yes, `docs/` | no, `.vercel-out/` is ignored |

`tool/build_vercel.ps1` never touches `docs/`, so switching between the two
hosts needs no undo.

## Deploying

```powershell
$env:SUPABASE_ANON_KEY = '<the anon key>'
powershell -ExecutionPolicy Bypass -File tool/build_vercel.ps1
npx vercel deploy --prod .vercel-out
```

Without a Vercel login, `npx vercel deploy --temporary .vercel-out` puts it on
a URL immediately and prints a claim link. **An unclaimed deployment expires in
an hour** — claiming it is what makes it permanent and gives it a real domain.

### Once you have a real domain

Canonical URLs and link-preview images are absolute and cannot be worked out at
runtime, so the build has to be told its own address. Until it is, they point
at the GitHub Pages URL, and a share card pointing at a host the site is not on
is a 404 in someone else's timeline.

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_vercel.ps1 -SiteUrl 'https://markless.app'
npx vercel deploy --prod .vercel-out
```

### Also update, or web payments break

`STRIPE_RETURN_ORIGIN` is where Stripe sends a teacher back to after checkout.
It must be the origin the app is actually served from, or they return to a dead
page holding a receipt:

```
npx supabase secrets set STRIPE_RETURN_ORIGIN=https://<your-vercel-domain>
```

## What the hosting config does, and what it deliberately does not

`vercel.json` is written into the output directory by the build rather than
committed at the repo root, so it cannot be mistaken for configuration of the
repository itself. It sets cache headers — a year on the CanvasKit, pdf.js and
Tesseract payloads, which are content-addressed and never change; no caching on
`main.dart.js`, so a deploy is picked up immediately.

Two options are deliberately **not** set:

- **`cleanUrls`** would redirect `/privacy.html` to `/privacy`. That exact URL
  is registered with the Play Console and must resolve as written.
- **`trailingSlash`** would bounce `/app/` through a redirect before serving
  the app.

Both were on in the first deployment and both showed up as `308`s on exactly
those paths.

## Connecting the private repo instead of deploying by hand

A git-connected project would need to run `build_vercel.ps1` on Vercel's
builders, and they have no Flutter SDK. Either commit `.vercel-out/` (56 MB per
deploy — the reason it is ignored), or keep deploying the prebuilt directory
from a machine that has Flutter. The CLI route above is the simpler of the two.
