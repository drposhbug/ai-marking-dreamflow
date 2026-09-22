# Builds the Flutter web app into docs/app/.
#
# This is one of TWO scripts that write into docs/, and they do not overlap:
#   tool/build_web.ps1   (this file) -> docs/app/    the Flutter web app
#   tool/build_site.ps1              -> docs/*       the marketing site
# build_site.ps1 refuses to touch docs/app/, and this one only ever replaces
# docs/app/. Run them in either order; both outputs must be committed.
#
# The app lives under docs/ so GitHub Pages serves the marketing site and the
# app from ONE origin:
#
#   https://drposhbug.github.io/ai-marking-dreamflow/       -> docs/index.html
#   https://drposhbug.github.io/ai-marking-dreamflow/app/   -> docs/app/index.html
#
# That is what makes the site's "Sign in" hand off to the app with a plain
# relative link. Hosting the app on a different origin means changing the app
# URL constant at the top of docs/index.html to the absolute address.
#
# Usage, from the repo root:
#   pwsh tool/build_web.ps1                      # project Pages URL
#   pwsh tool/build_web.ps1 -BasePath /app/      # custom domain (markless.app)
#
# Secrets are passed at build time and are NOT in the repo. The Supabase anon
# key and the RevenueCat key are public by design once shipped -- RLS and the
# REVENUECAT-WEBHOOK are what actually protect the data -- but they still live
# outside version control so they can be rotated without a commit.

param(
  # Where the app will be served from, as a URL path. Must start and end with /.
  [string]$BasePath = "/ai-marking-dreamflow/app/",
  # Where to write the built app. Defaults to docs/app, which is what GitHub
  # Pages serves. Point it somewhere else to build for a different host —
  # Vercel wants the app at /app/ off the domain root, not under a repo name,
  # and that is a different -BasePath and so a different build.
  [string]$OutDir = "",
  [string]$SupabaseAnonKey = $env:SUPABASE_ANON_KEY,
  [string]$RevenueCatAndroidKey = $env:REVENUECAT_ANDROID_KEY,
  [string]$OneSignalAppId = $env:ONESIGNAL_APP_ID
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

if (-not $BasePath.StartsWith("/") -or -not $BasePath.EndsWith("/")) {
  throw "BasePath must start and end with a slash, e.g. /ai-marking-dreamflow/app/"
}

# An empty key is a working state on purpose: the app runs local-only and the
# billing and push services disable themselves cleanly. It is still worth
# saying so out loud, because a release built this way cannot mark anything.
if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  Write-Warning "SUPABASE_ANON_KEY is empty - this build will run in local-only mode and no marking will work."
}

$defines = @()
if ($SupabaseAnonKey)      { $defines += "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey" }
if ($RevenueCatAndroidKey) { $defines += "--dart-define=REVENUECAT_ANDROID_KEY=$RevenueCatAndroidKey" }
if ($OneSignalAppId)       { $defines += "--dart-define=ONESIGNAL_APP_ID=$OneSignalAppId" }

Write-Host "Building web app with base href $BasePath" -ForegroundColor Cyan
& flutter build web --release --base-href $BasePath @defines
if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }

$out = if ([string]::IsNullOrWhiteSpace($OutDir)) { Join-Path $repo "docs/app" } else { [System.IO.Path]::GetFullPath((Join-Path $repo $OutDir)) }
# Deleting the destination is safe for docs/app, which this script owns
# outright. Anywhere else, refuse to delete a directory that holds something
# other than a previous build of this app — a mistyped -OutDir must not take
# the repository with it.
if (Test-Path $out) {
  $looksLikeABuild = (Test-Path (Join-Path $out "main.dart.js")) -or -not (Get-ChildItem $out -Force | Select-Object -First 1)
  if ($out -ne (Join-Path $repo "docs/app") -and -not $looksLikeABuild) {
    throw "$out is not empty and does not look like a previous build of the app. Refusing to delete it."
  }
  Remove-Item $out -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
Copy-Item -Path (Join-Path $repo "build/web/*") -Destination $out -Recurse -Force

# Pages serves what is committed, so the build output belongs in the commit.
$size = "{0:N1} MB" -f ((Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
$shown = $out.Replace($repo, "").TrimStart("\", "/")
Write-Host "Wrote $shown ($size) with base href $BasePath." -ForegroundColor Green
