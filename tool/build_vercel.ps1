# Builds the marketing site AND the Flutter app into one directory shaped for
# Vercel, served from the root of a domain:
#
#   https://<deployment>/          -> the marketing site
#   https://<deployment>/app/      -> the Flutter web app
#
# WHY THIS IS A SEPARATE BUILD FROM docs/
# GitHub Pages serves a project site under the repository name, so everything
# there is built for /ai-marking-dreamflow/. Vercel serves from the root of a
# domain. The prefix is baked into the HTML at build time — Next.js bakes it
# into every asset URL, Flutter bakes it into <base href> — so the same files
# cannot serve both. This writes a second, differently-based copy and never
# touches docs/, which stays exactly as GitHub Pages needs it.
#
# The output is deliberately NOT committed (see .gitignore): it is a build
# artifact of the same source, and a 56 MB duplicate of docs/ in every commit
# buys nothing.
#
# Usage, from the repo root:
#   $env:SUPABASE_ANON_KEY = '...'
#   powershell -ExecutionPolicy Bypass -File tool/build_vercel.ps1
#
# Then deploy the directory it names. See docs/vercel-hosting.md.

param(
  # Where to assemble the deployable tree.
  [string]$OutDir = ".vercel-out",
  # The absolute URL this build will be served from. Canonical links and
  # link-preview images are absolute and cannot be worked out at runtime, so
  # a build that does not know its own address advertises the wrong one.
  # Defaults to the production domain; pass another to build for a preview.
  [string]$SiteUrl = "https://app.umarkless.com",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$out = [System.IO.Path]::GetFullPath((Join-Path $repo $OutDir))
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null

# ---------------------------------------------------------------------------
# 1. The marketing site, at the root. BasePath '' is the whole difference
#    from the Pages build.
# ---------------------------------------------------------------------------
Write-Host "`n=== Marketing site -> $OutDir ===" -ForegroundColor Cyan
if ($SiteUrl) {
  $env:MARKLESS_SITE_URL = $SiteUrl
  Write-Host "Canonical and link-preview URLs: $SiteUrl" -ForegroundColor Cyan
} else {
  Remove-Item Env:\MARKLESS_SITE_URL -ErrorAction SilentlyContinue
  Write-Warning "-SiteUrl is empty: canonical and og: URLs fall back to https://app.umarkless.com/."
}
# Called in this session rather than through `powershell -File`, which drops
# an empty-string argument — and an empty -BasePath is exactly the point of
# this build. Losing it would silently produce the Pages-prefixed site again.
& (Join-Path $PSScriptRoot "build_site.ps1") -BasePath '' -OutDir $out -SkipInstall:$SkipInstall
Set-Location $repo

# ---------------------------------------------------------------------------
# 2. The app, at /app/. Built second so it lands inside the site's output
#    rather than being swept by it.
# ---------------------------------------------------------------------------
Write-Host "`n=== Flutter app -> $OutDir/app ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "build_web.ps1") -BasePath "/app/" -OutDir (Join-Path $OutDir "app")
Set-Location $repo

# ---------------------------------------------------------------------------
# 3. Hosting config, written here rather than committed at the repo root so
#    it cannot be mistaken for configuration of the repository itself.
#
#    Deliberately NOT set: `cleanUrls`, which would redirect /privacy.html to
#    /privacy. That URL is registered with the Play Console and must resolve
#    exactly as it is written there. `trailingSlash` is left alone too, so
#    /app/ serves the app rather than bouncing through a redirect first.
# ---------------------------------------------------------------------------
$vercelJson = @'
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "headers": [
    {
      "source": "/app/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=0, must-revalidate"
        }
      ]
    },
    {
      "source": "/app/(canvaskit|pdfjs|tesseract)/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    },
    {
      "source": "/_next/static/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    }
  ]
}
'@
# Written without a byte-order mark: Windows PowerShell's -Encoding utf8 adds
# one, and Vercel's JSON parser rejects the file outright when it does.
[System.IO.File]::WriteAllText(
  (Join-Path $out "vercel.json"),
  $vercelJson,
  (New-Object System.Text.UTF8Encoding $false)
)

$size = "{0:N1} MB" -f ((Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "`nReady: $out ($size)" -ForegroundColor Green
Write-Host "  site at /        app at /app/" -ForegroundColor Green
Write-Host "  npx vercel deploy --prod $OutDir" -ForegroundColor Green
