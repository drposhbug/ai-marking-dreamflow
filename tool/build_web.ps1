# Builds the Flutter web app into docs/app/ so GitHub Pages serves the
# marketing site and the app from ONE origin:
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

$out = Join-Path $repo "docs/app"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null
Copy-Item -Path (Join-Path $repo "build/web/*") -Destination $out -Recurse -Force

# Pages serves what is committed, so the build output belongs in the commit.
$size = "{0:N1} MB" -f ((Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "Wrote docs/app ($size). Commit it - GitHub Pages serves the committed files." -ForegroundColor Green
