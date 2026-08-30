# docs/

| File | What it is |
| --- | --- |
| `index.html` | The privacy policy as a self-contained page, for hosting. This is the file GitHub Pages serves. |
| `privacy-policy.md` | The same policy in Markdown. Source of truth — edit this first, then mirror the change into `index.html`. |
| `security-and-compliance.md` | What leaves the device, subprocessors, retention, known gaps. For district review. |
| `store-listing.md` | Google Play and App Store listing copy. |
| `shipaton-submission.md` | Draft of the RevenueCat Shipaton 2026 Devpost submission. |

`index.html` has no external resources — no CDN, no fonts, no scripts — so it
works offline and cannot break because something else went down.

---

## Hosting the privacy policy on GitHub Pages

Google Play will not accept the app without a privacy policy at a public URL
(`REMAINING.md` R4.4). GitHub Pages serves one from this folder for free.

**The repository must be public** for GitHub Pages to work on a free account.

1. Push this folder to the default branch (`main`).
2. On GitHub, go to the repository → **Settings** → **Pages** (left sidebar,
   under "Code and automation").
3. Under **Build and deployment**:
   - **Source:** `Deploy from a branch`
   - **Branch:** `main`, and set the folder dropdown to **`/docs`**
4. Click **Save**. The first build takes a minute or two; the Pages settings
   page shows a green banner with the live URL when it is done.

### The resulting URL

```
https://drposhbug.github.io/ai-marking-dreamflow/
```

`index.html` is the directory index, so that URL is the privacy policy itself —
no filename needed. Paste it into:

- Play Console → App content → **Privacy policy**
- Play Console → Store listing → **Privacy Policy** field
- App Store Connect → App Privacy → **Privacy Policy URL**
- The RevenueCat Shipaton submission, wherever a privacy policy is asked for

The other Markdown files in this folder are also reachable
(`.../ai-marking-dreamflow/security-and-compliance`), which is useful when a
school district asks for the compliance write-up.

### Notes

- Pages rebuilds automatically on every push to `main` that touches `docs/`.
- No Jekyll configuration is needed. If Jekyll ever mangles a file, add an empty
  `.nojekyll` file to this folder to serve it verbatim.
- `TODO:` if `markless.app` (or whatever domain is registered) is set up, add a
  `CNAME` file here containing the bare hostname and point a DNS `CNAME` record
  at `drposhbug.github.io`. The Play Console URL then has to be updated to match.
