# Update.ps1 - brings a git clone of Tok up to the newest version: pulls, closes Tok, runs Install.ps1 again (the shortcuts, hook,
# skill and Settings > Apps entry stay as they were, pointed at this folder), and starts Tok. Your Tok, its family and your
# settings live in %LOCALAPPDATA%\tok and stay.
#   pwsh tok\Update.ps1
# A copy from a zip can't update itself: download the new zip and run its Install.ps1, which takes over from this copy.
# Tok itself never checks for updates; this script is the only thing that fetches anything, and only when you run it.
param(
    [switch]$NoStart,
    [string]$ProgramsDir = [Environment]::GetFolderPath('Programs'),    # these three are passed on to Install.ps1 (the tests use temp ones)
    [string]$StartupDir = [Environment]::GetFolderPath('Startup'),
    [string]$AppsKey = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

if (-not (Test-Path -LiteralPath (Join-Path $here '.git'))) {
    "This copy of Tok came from a zip, so it can't update itself. Download the new zip from Tok's GitHub page (Releases, Latest),"
    "unzip it, and run its Install.ps1: it moves the shortcuts, hook and skill over from this copy. Then delete this folder."
    exit 1
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { 'Update.ps1 needs git, and git is not on your PATH.'; exit 1 }
. (Join-Path $here 'lib\Transcripts.ps1')
. (Join-Path $here 'lib\Pet.ps1')
. (Join-Path $here 'lib\Setup.ps1')

$old = "$(git -C $here rev-parse HEAD)".Trim()
$out = git -C $here pull --ff-only 2>&1
if ($LASTEXITCODE) {
    "Nothing changed: git couldn't update this folder."
    $out | ForEach-Object { "    $_" }
    exit 1
}
$new = "$(git -C $here rev-parse HEAD)".Trim()
if ($new -eq $old) { "Tok is up to date ($(git -C $here log -1 --format='%h %s'))."; exit 0 }
"Updated: $($old.Substring(0, 7)) -> $($new.Substring(0, 7))"
git -C $here log --format='    %h %s' "$old..$new"

if (-not (Stop-Tok $script:DataDir)) {
    "Tok didn't close. Right-click it, choose Goodbye, then run Install.ps1 to finish."
    exit 1
}
$pass = @('-NoProfile', '-File', (Join-Path $here 'Install.ps1'), '-NoStart', '-ProgramsDir', $ProgramsDir, '-StartupDir', $StartupDir)
if ($AppsKey) { $pass += '-AppsKey', $AppsKey }
$inst = & pwsh @pass 2>&1
if ($LASTEXITCODE) {
    'Install.ps1 failed after the update:'
    $inst | ForEach-Object { "    $_" }
    exit 1
}
'Shortcuts, hook, skill and Settings > Apps: pointed at this folder'

if ($NoStart) { return }
Start-Process -FilePath (Join-Path $ProgramsDir 'Tok.lnk')
'Tok is starting.'
