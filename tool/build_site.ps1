# Builds the Next.js marketing site (site/) into docs/, which is what GitHub
# Pages serves.
#
#   https://drposhbug.github.io/ai-marking-dreamflow/                    -> docs/index.html
#   https://drposhbug.github.io/ai-marking-dreamflow/privacy.html        -> docs/privacy.html
#   https://drposhbug.github.io/ai-marking-dreamflow/delete-account.html -> docs/delete-account.html
#   https://drposhbug.github.io/ai-marking-dreamflow/app/                -> docs/app/index.html
#
# The last of those is built by the OTHER script, tool/build_web.ps1, and this
# one must never touch it. Play Console compliance depends on the privacy and
# delete-account URLs resolving, and the sign-in handoff depends on /app/.
#
# WHAT THIS SCRIPT DELETES
#   Only the files a previous run of this script wrote. Every run records what
#   it copied in docs/.site-files.txt and the next run removes exactly that set
#   before copying the new one, so a page that stops being generated does not
#   linger. Anything else in docs/ is left alone, and three things are refused
#   outright even if they somehow appear in that list:
#     - docs/app/**        the built Flutter web app
#     - docs/*.md          the Markdown docs
#     - docs/CNAME         a custom domain, if one is ever configured
#
# Usage, from the repo root:
#   pwsh tool/build_site.ps1                       # build and publish into docs/
#   pwsh tool/build_site.ps1 -BasePath ''          # custom domain served at /
#   pwsh tool/build_site.ps1 -OutDir path/to/dir   # publish somewhere else (a dry run)
#   pwsh tool/build_site.ps1 -SkipInstall          # node_modules is already good

param(
  # URL path the site is served from, with NO trailing slash. '' means the root.
  [string]$BasePath = '/ai-marking-dreamflow',
  # Where to publish. Defaults to docs/ next to this repo.
  [string]$OutDir = '',
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$site = Join-Path $repo 'site'
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $repo 'docs' }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)

if ($BasePath.EndsWith('/') -and $BasePath.Length -gt 1) {
  throw "BasePath must not end with a slash. Use '/ai-marking-dreamflow' or ''."
}
if (-not (Test-Path (Join-Path $site 'package.json'))) {
  throw "No site/package.json at $site - run this from the repository."
}

# ---------------------------------------------------------------------------
# 1. docs/ is the source of truth for the two compliance pages and the icon.
#    Mirror them into site/public first, so the export cannot drift from what
#    is deployed today and Play never sees a changed privacy policy it did not
#    expect.
# ---------------------------------------------------------------------------
$public = Join-Path $site 'public'
foreach ($name in @('privacy.html', 'delete-account.html', 'icon.png')) {
  $src = Join-Path $OutDir $name
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $public $name) -Force
  } elseif (-not (Test-Path (Join-Path $public $name))) {
    throw "$name is in neither $OutDir nor site/public - refusing to publish a site without it."
  }
}

# ---------------------------------------------------------------------------
# 2. Build the static export.
# ---------------------------------------------------------------------------
Push-Location $site
try {
  if (-not $SkipInstall) {
    Write-Host 'Installing site dependencies...' -ForegroundColor Cyan
    if (Test-Path (Join-Path $site 'package-lock.json')) { & npm ci --no-audit --no-fund }
    else { & npm install --no-audit --no-fund }
    if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }
  }

  Write-Host "Building the site with base path '$BasePath'..." -ForegroundColor Cyan
  # PowerShell deletes an environment variable rather than setting it empty,
  # so a root deploy is spelled 'root'; next.config.mjs maps it back to ''.
  if ([string]::IsNullOrEmpty($BasePath)) { $env:MARKLESS_BASE_PATH = 'root' }
  else { $env:MARKLESS_BASE_PATH = $BasePath }
  & npm run build
  if ($LASTEXITCODE -ne 0) { throw 'next build failed' }
} finally {
  Pop-Location
  Remove-Item Env:\MARKLESS_BASE_PATH -ErrorAction SilentlyContinue
}

$export = Join-Path $site 'out'
if (-not (Test-Path (Join-Path $export 'index.html'))) {
  throw "next build produced no $export/index.html"
}

# ---------------------------------------------------------------------------
# 3. Remove what the previous run of this script wrote, and nothing else.
# ---------------------------------------------------------------------------
function Test-Protected([string]$relative) {
  $r = $relative -replace '\\', '/'
  if ($r -eq 'app' -or $r.StartsWith('app/')) { return $true }
  if ($r -like '*.md') { return $true }
  if ($r -eq 'CNAME') { return $true }
  return $false
}

$manifestPath = Join-Path $OutDir '.site-files.txt'
$appBefore = Test-Path (Join-Path $OutDir 'app')

if (Test-Path $manifestPath) {
  $previous = Get-Content $manifestPath | Where-Object { $_ -and -not $_.StartsWith('#') }
  $removed = 0
  foreach ($rel in $previous) {
    if (Test-Protected $rel) {
      Write-Warning "Refusing to delete protected path from the manifest: $rel"
      continue
    }
    $path = Join-Path $OutDir $rel
    if (Test-Path $path) { Remove-Item $path -Force -Recurse; $removed++ }
  }
  # Directories the old export owned are empty now; take them with it.
  $dirs = $previous |
    ForEach-Object { Split-Path $_ -Parent } |
    Where-Object { $_ } |
    Sort-Object -Unique -Descending
  foreach ($d in $dirs) {
    if (Test-Protected $d) { continue }
    $path = Join-Path $OutDir $d
    if ((Test-Path $path) -and -not (Get-ChildItem $path -Force)) { Remove-Item $path -Force }
  }
  Write-Host "Removed $removed file(s) from the previous site build." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 4. Copy the export in, recording every relative path as we go.
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$written = New-Object System.Collections.Generic.List[string]

foreach ($file in Get-ChildItem $export -Recurse -File -Force) {
  $rel = $file.FullName.Substring($export.Length).TrimStart('\', '/')
  if (Test-Protected $rel) {
    throw "The export contains $rel, which collides with a protected path in docs/. Refusing."
  }
  $dest = Join-Path $OutDir $rel
  $destDir = Split-Path $dest -Parent
  if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
  Copy-Item $file.FullName $dest -Force
  $written.Add(($rel -replace '\\', '/'))
}

# GitHub Pages runs Jekyll, which drops any directory whose name starts with an
# underscore. Next puts every asset in _next/. Without this file the deployed
# site loads with no CSS and no JavaScript.
$noJekyll = Join-Path $OutDir '.nojekyll'
if (-not (Test-Path $noJekyll)) {
  New-Item -ItemType File -Path $noJekyll | Out-Null
  $written.Add('.nojekyll')
}

@(
  '# Written by tool/build_site.ps1. Every path here is deleted and rewritten',
  '# by the next run. Do not add anything by hand.'
) + $written | Set-Content $manifestPath -Encoding utf8

# ---------------------------------------------------------------------------
# 5. Prove the three URLs Play depends on are still there.
# ---------------------------------------------------------------------------
$required = @('index.html', 'privacy.html', 'delete-account.html', 'icon.png', '.nojekyll')
foreach ($name in $required) {
  if (-not (Test-Path (Join-Path $OutDir $name))) { throw "Missing after publish: $name" }
}
if ($appBefore -and -not (Test-Path (Join-Path $OutDir 'app'))) {
  throw 'docs/app went missing during publish. This is a bug - do not commit.'
}

$size = '{0:N1} MB' -f ((Get-ChildItem $OutDir -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1MB)
Write-Host ''
Write-Host "Published $($written.Count) file(s) into $OutDir ($size)." -ForegroundColor Green
if ($appBefore) { Write-Host 'docs/app/ is untouched.' -ForegroundColor Green }
else { Write-Host 'docs/app/ does not exist yet - build it with tool/build_web.ps1.' -ForegroundColor Yellow }
Write-Host 'Commit the result. GitHub Pages serves the files that are committed.' -ForegroundColor Green
