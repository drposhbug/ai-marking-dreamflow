# docs/

This folder is the public website. GitHub Pages serves it at
`https://drposhbug.github.io/ai-marking-dreamflow/`.

| File | What it is |
| --- | --- |
| `index.html` | **The landing page.** What Markless does, the four ways to mark, the privacy story, plans. Served at the site root. |
| `privacy.html` | The privacy policy as a self-contained page. This is the URL both stores want. |
| `delete-account.html` | Standalone account-deletion instructions. Google Play requires this as its own URL — a section inside the privacy policy does not satisfy it. |
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

## The three public URLs

```
https://drposhbug.github.io/ai-marking-dreamflow/                      ← landing page
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
