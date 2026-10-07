# Ships the web app in one go: tests, push, build, deploy, verify, smoke test.
#
#   powershell -ExecutionPolicy Bypass -File tool/ship.ps1 [-SkipTests] [-SkipSmoke]
#
# It does not commit: what goes in a commit, and its message, is a judgement
# call. It refuses to run while app code is uncommitted, because the build
# would ship code that is not on main.

param([switch]$SkipTests, [switch]$SkipSmoke)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

Step "Uncommitted app code"
$dirty = git status --porcelain -- lib web site assets pubspec.yaml pubspec.lock
if ($dirty) { Write-Host $dirty; throw "Commit or stash these first." }

if (-not $SkipTests) {
  Step "Tests"
  flutter test
  if ($LASTEXITCODE) { throw "Tests failed." }
}

Step "Push to main"
git push origin HEAD:main
if ($LASTEXITCODE) { throw "Push failed (is this branch behind main?)." }

Step "Build"
if (-not $env:SUPABASE_ANON_KEY) {
  $env:SUPABASE_ANON_KEY = (Get-Content "$env:USERPROFILE\OneDrive\markless-keys\supa_anon.txt" -TotalCount 1).Trim()
}
# Without the key the web app silently runs local-only and marks nothing.
if ($env:SUPABASE_ANON_KEY.Length -lt 100) { throw "No Supabase anon key." }
# build_vercel.ps1 deletes .vercel-out, which holds the Vercel project link.
$link = Join-Path $env:TEMP "umarkless-vercel-link"
if (Test-Path .vercel-out\.vercel) {
  if (Test-Path $link) { Remove-Item $link -Recurse -Force }
  Copy-Item .vercel-out\.vercel $link -Recurse
}
if (-not (Test-Path $link)) { throw "No Vercel project link: run 'npx vercel link' in .vercel-out once." }
& (Join-Path $PSScriptRoot "build_vercel.ps1") -SkipInstall
Set-Location $repo
if (-not (Test-Path .vercel-out\app\main.dart.js)) { throw "The build produced no web app." }
Copy-Item $link .vercel-out\.vercel -Recurse

Step "Deploy"
# Vercel refuses deploys from inside the repo (the commit author is not on
# the Vercel team), so deploy a copy. It also says "Not authorized" now and
# then; an immediate retry goes through.
$out = Join-Path $env:TEMP "umarkless-deploy"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
Copy-Item .vercel-out $out -Recurse
Push-Location $out
try {
  $ok = $false
  for ($i = 1; $i -le 3 -and -not $ok; $i++) {
    npx -y vercel deploy --prod --yes
    $ok = $LASTEXITCODE -eq 0
    if (-not $ok) { Write-Warning "Deploy attempt $i failed; retrying."; Start-Sleep 5 }
  }
} finally { Pop-Location }
if (-not $ok) { throw "Deploy failed three times." }

Step "Verify"
# The same bytes on every domain as were just built, not just a 200.
$want = (Get-FileHash .vercel-out\app\main.dart.js -Algorithm SHA256).Hash
$live = Join-Path $env:TEMP "umarkless-live.js"
foreach ($d in "umarkless.com", "www.umarkless.com", "app.umarkless.com") {
  $same = $false
  for ($i = 1; $i -le 6 -and -not $same; $i++) {
    Invoke-WebRequest "https://$d/app/main.dart.js" -OutFile $live -UseBasicParsing -Headers @{ "Cache-Control" = "no-cache" }
    $same = (Get-FileHash $live -Algorithm SHA256).Hash -eq $want
    if (-not $same) { Start-Sleep 10 }
  }
  if (-not $same) { throw "$d is not serving this build." }
  Write-Host "$d serves this build"
}

if (-not $SkipSmoke) {
  Step "Smoke test: guest mode in Chrome"
  Push-Location (Join-Path $PSScriptRoot "smoke")
  try {
    if (-not (Test-Path node_modules)) { npm install --silent }
    node smoke_web.mjs
    if ($LASTEXITCODE) { throw "Smoke test failed." }
  } finally { Pop-Location }
}

Step "Shipped $(git rev-parse --short HEAD)"
