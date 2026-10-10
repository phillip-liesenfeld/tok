# Uninstall.ps1 - undoes Install.ps1: closes Tok, removes its shortcuts and its Notification hook, and deletes its data folder
# (%LOCALAPPDATA%\tok: its state, family tree, settings and log).
#   pwsh -ExecutionPolicy Bypass -File Uninstall.ps1              all of it
#   pwsh -ExecutionPolicy Bypass -File Uninstall.ps1 -KeepData    keep the data folder (a later install picks the same Tok up)
# This folder stays; delete it yourself afterwards. Claude Code's own files are never touched, apart from taking Tok's hook
# back out of its settings.json.
param(
    [switch]$KeepData,
    [string]$ProgramsDir = [Environment]::GetFolderPath('Programs'),
    [string]$StartupDir = [Environment]::GetFolderPath('Startup')
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'lib\Transcripts.ps1')
. (Join-Path $here 'lib\Pet.ps1')
. (Join-Path $here 'lib\Menu.ps1')
. (Join-Path $here 'lib\Setup.ps1')
$launcher = Join-Path $here 'Start-Tok.vbs'

if (-not (Stop-Tok $script:DataDir)) {
    Write-Host 'Tok is still running and did not close. Right-click it, choose Goodbye, then run this again.'
    exit 1
}
'Tok: closed'

foreach ($lnk in (Join-Path $ProgramsDir 'Tok.lnk'), (Get-StartupShortcutPath $StartupDir)) {
    if (Test-TokShortcut $lnk $launcher) { Remove-Item -LiteralPath $lnk -Force; "Removed: $lnk" }
}

$settings = Join-Path $script:ClaudeDir 'settings.json'
if ((Remove-TokHook $settings (Join-Path $here 'notify.ps1')) -eq 'removed') { "Notification hook: removed ($settings)" }

if ($KeepData) { "Kept: $script:DataDir" }
elseif (Test-Path -LiteralPath $script:DataDir) {
    $foreign = Get-ForeignDataItems $script:DataDir
    if ($foreign.Count) {
        Write-Warning "Left $script:DataDir alone: it holds files Tok didn't make ($($foreign -join ', '))."
    } else {
        Remove-Item -LiteralPath $script:DataDir -Recurse -Force
        "Removed: $script:DataDir"
    }
}
"Tok is uninstalled. This folder ($here) is yours to delete."
