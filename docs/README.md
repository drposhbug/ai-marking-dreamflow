# docs/

This folder is the public website. GitHub Pages serves it at
`https://drposhbug.github.io/ai-marking-dreamflow/`.

| File | What it is |
| --- | --- |
| `index.html` | **The landing page.** What Markless does, the four ways to mark, the privacy story, plans. Served at the site root. |
| `privacy.html` | The privacy policy as a self-contained page. This is the URL both stores want. |
| `delete-account.html` | Standalone account-deletion instructions. Google Play requires this as its own URL — a section inside the privacy policy does not satisfy it. |
| `app/` | **The built web app.** Produced by `tool/build_web.ps1`; served at `/app/` so the landing page can sign a teacher straight in. Committed on purpose — Pages serves what is committed. |
| `icon.png` | Copy of `assets/icons/markless_icon_1024.png`. Backs the favicon and the Open Graph / Twitter card image. |
| `privacy-policy.md` | The policy in Markdown. Source of truth — edit this first, then mirror the change into `privacy.html`. |
| `security-and-compliance.md` | What leaves the device, subprocessors, retention, known gaps. For district review. |
| `store-listing.md` | Google Play and App Store listing copy. |
| `shipaton-submission.md` | Draft of the RevenueCat Shipaton 2026 Devpost submission. |

Every page is a single self-contained HTML file with no external resources — no
CDN, no web fonts, no scripts, no analytics — so the site works offline, loads
instantly, and cannot break because something else went down. Each supports
light and dark via `prefers-color-scheme`.

---

## The public URLs

```
https://drposhbug.github.io/ai-marking-dreamflow/                      ← landing page
https://drposhbug.github.io/ai-marking-dreamflow/app/                  ← the web app
https://drposhbug.github.io/ai-marking-dreamflow/privacy.html          ← privacy policy
https://drposhbug.github.io/ai-marking-dreamflow/delete-account.html   ← account deletion
```

Where each one goes:

| URL | Paste into |
| --- | --- |
| Landing page | Play Console → Store listing → **Website**; App Store Connect → **Marketing URL**; the RevenueCat Shipaton submission; build-in-public posts |
| `privacy.html` | Play Console → App content → **Privacy policy**; Play Console → Store listing → **Privacy Policy**; App Store Connect → App Privacy → **Privacy Policy URL**; the Shipaton submission wherever a privacy policy is asked for |
| `delete-account.html` | Play Console → App content → Data safety → **account deletion URL** (the "Provide a URL where users can request account deletion" field). It must be reachable without signing in, which it is. |

The Markdown files in this folder are copied verbatim by Pages (they carry no
YAML front matter, so Jekyll does not render them to HTML). They are reachable
at e.g. `.../ai-marking-dreamflow/security-and-compliance.md`, but a browser
will show raw Markdown or download it — so when linking the compliance write-up
to a school district, link the rendered GitHub view instead:
`https://github.com/drposhbug/ai-marking-dreamflow/blob/main/docs/security-and-compliance.md`.
That is what `index.html` links to.

---

## The app, served from the same origin

`docs/app/` is the built Flutter web app. It lives here on purpose: Pages then
serves the site and the app from one origin, which is what lets the landing
page's **Sign in** hand off with a plain relative `app/` link and no CORS, no
second host, and no second deploy.

Build it with:

```powershell
pwsh tool/build_web.ps1
```

That runs `flutter build web --release` with `--base-href /ai-marking-dreamflow/app/`
and copies the output into `docs/app/`. **Commit the result** — Pages serves the
files that are committed, so an uncommitted build changes nothing.

Keys are passed at build time, never committed. The script reads
`SUPABASE_ANON_KEY`, `REVENUECAT_ANDROID_KEY` and `ONESIGNAL_APP_ID` from the
environment (or from parameters) and warns if the Supabase key is missing,
because a build without it runs local-only and cannot mark anything.

On a custom domain the app sits at the root instead, so build with
`pwsh tool/build_web.ps1 -BasePath /app/` and update the app-URL constant at the
top of `index.html`.

---

## Switching Pages on

**The repository must be public** for GitHub Pages to work on a free account.

1. Push this folder to the default branch (`main`).
2. On GitHub, go to the repository → **Settings** → **Pages** (left sidebar,
   under "Code and automation").
3. Under **Build and deployment**:
   - **Source:** `Deploy from a branch`
   - **Branch:** `main`, and set the folder dropdown to **`/docs`**
4. Click **Save**. The first build takes a minute or two; the Pages settings
   page shows a green banner with the live URL when it is done.

### Notes

- Pages rebuilds automatically on every push to `main` that touches `docs/`.
- No Jekyll configuration is needed. If Jekyll ever mangles a file, add an empty
  `.nojekyll` file to this folder to serve everything verbatim.
- `TODO:` the landing page's primary call to action is a `mailto:` link, because
  there is no store URL yet. When the Play listing is live, replace both
  occurrences in `index.html` (each is marked with a `TODO:` comment) with a
  real store button.
- `TODO:` `delete-account.html` carries two `TODO:` markers — the retention
  period for the anonymous marking cache, and the turnaround for emailed
  deletion requests. Neither is stated anywhere in `privacy-policy.md` or
  `security-and-compliance.md`. Both must be decided and filled in before
  submitting to Play, and the same numbers go in the Data safety form.
- `TODO:` `index.html` says every paid plan gives 10% to charities that help
  kids learn, with no charity named (`REMAINING.md` R9). The claim is marked
  with a `TODO:` comment in the file.
- `TODO:` if `markless.app` (or whatever domain is registered) is set up, add a
  `CNAME` file here containing the bare hostname and point a DNS `CNAME` record
  at `drposhbug.github.io`. Every URL above then has to be updated to match, in
  the Play Console, in App Store Connect, and in the `canonical` / `og:url` tags
  of all three HTML pages.
