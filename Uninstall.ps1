# Uninstall.ps1 - undoes Install.ps1: closes Tok, removes its shortcuts, its Settings > Apps entry, its Notification hook and its
# skill, then asks before deleting its data folder (%LOCALAPPDATA%\tok: your Tok, its family tree, settings and log).
#   pwsh -File Uninstall.ps1              all of it; asks about the data folder
#   pwsh -File Uninstall.ps1 -KeepData    keep the data folder without asking (a later install picks the same Tok up)
#   pwsh -File Uninstall.ps1 -Yes         delete the data folder without asking
# With nowhere to ask (no console), the data folder stays. Settings > Apps runs this with -FromSettings, which waits for Enter
# at the end so the window doesn't vanish. This folder stays; delete it yourself afterwards. Claude Code's own files are never
# touched, apart from taking Tok's hook back out of its settings.json and its skill out of its skills folder. Shortcuts, a hook
# or a skill left by an older copy of Tok whose folder is gone are cleared too.
param(
    [switch]$KeepData,
    [switch]$Yes,
    [switch]$FromSettings,
    [string]$ProgramsDir = [Environment]::GetFolderPath('Programs'),
    [string]$StartupDir = [Environment]::GetFolderPath('Startup'),
    [string]$AppsKey = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'lib\Transcripts.ps1')
. (Join-Path $here 'lib\Pet.ps1')
. (Join-Path $here 'lib\Menu.ps1')
. (Join-Path $here 'lib\Setup.ps1')
if (-not $AppsKey) { $AppsKey = $script:TokAppsKey }
function Exit-Uninstall([int]$Code) {
    if ($FromSettings) { $null = Read-Host 'Press Enter to close' }
    exit $Code
}

if (-not (Stop-Tok $script:DataDir)) {
    Write-Host 'Tok is still running and did not close. Right-click it, choose Goodbye, then run this again.'
    Exit-Uninstall 1
}
'Tok: closed'

foreach ($lnk in (Join-Path $ProgramsDir 'Tok.lnk'), (Get-StartupShortcutPath $StartupDir)) {
    if ((Test-TokShortcut $lnk $here) -or (Test-StaleTokShortcut $lnk)) { Remove-Item -LiteralPath $lnk -Force; "Removed: $lnk" }
}
if ((Unregister-TokApp $here $AppsKey) -eq 'removed') { "Removed: Tok from Settings > Apps" }

$settings = Join-Path $script:ClaudeDir 'settings.json'
try { if ((Remove-TokHook $settings (Join-Path $here 'notify.ps1')) -eq 'removed') { "Notification hook: removed ($settings)" } }
catch { Write-Warning "Left $settings alone: it isn't valid JSON. Take out the hook that runs notify.ps1 yourself." }
if ((Remove-TokSkill $script:ClaudeDir $here) -eq 'removed') { "Skill tok-private: removed ($(Get-TokSkillPath $script:ClaudeDir))" }

if ($KeepData) { "Kept: $script:DataDir" }
elseif (Test-Path -LiteralPath $script:DataDir) {
    $foreign = Get-ForeignDataItems $script:DataDir
    if ($foreign.Count) {
        Write-Warning "Left $script:DataDir alone: it holds files Tok didn't make ($($foreign -join ', '))."
    } else {
        $delete = [bool]$Yes
        if (-not $Yes) {
            if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
                "Kept: $script:DataDir (your Tok and its family). Delete it yourself, or run Uninstall.ps1 -Yes."
            } else {
                $a = Read-Host "Delete your Tok and its family too ($script:DataDir)? [y/N]"
                $delete = $a -match '^\s*y(es)?\s*$'
                if (-not $delete) { "Kept: $script:DataDir (a later install picks the same Tok up)" }
            }
        }
        if ($delete) {
            Remove-Item -LiteralPath $script:DataDir -Recurse -Force
            "Removed: $script:DataDir"
        }
    }
}
"Tok is uninstalled. This folder ($here) is yours to delete."
Exit-Uninstall 0
