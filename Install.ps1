# Install.ps1 - sets Tok up for this Windows user: checks what it needs, adds a Start menu shortcut and a Settings > Apps entry,
# and starts it. Run it from a git clone (pwsh tok\Install.ps1) or from an unzipped release (see below).
#   pwsh -File Install.ps1                     check, shortcut, Settings > Apps entry, start Tok
#   pwsh -File Install.ps1 -StartWithWindows   ...and start it when you sign in
#   pwsh -File Install.ps1 -Hook               ...and let Claude Code tell Tok when it needs your OK
#                                              (a Notification hook in ~\.claude\settings.json)
#   pwsh -File Install.ps1 -Skills             ...and teach Claude Code to put Tok in private mode before sensitive work
#                                              (the tok-private skill in ~\.claude\skills)
#   pwsh -File Install.ps1 -ExactUsage         ...and let Tok ask Anthropic for your exact 5-hour usage, with Claude Code's
#                                              own login (writes LiveUsage: true to config.json; off unless you ask, here
#                                              or in right-click > Settings > Exact usage)
# From a downloaded zip, add -ExecutionPolicy Bypass after pwsh for this one run: Windows marks every file in the zip as
# downloaded, and PowerShell won't run marked scripts until Install unblocks them. A git clone has no marks.
# Nothing is copied: Tok runs from this folder and keeps its own files in %LOCALAPPDATA%\tok. If another copy of Tok was
# installed before (an older version in another folder), this one takes over its shortcuts, hook and skill. Update.ps1 updates
# a clone; Uninstall.ps1 undoes it all.
# Written so Windows PowerShell 5.1 can read it far enough to say what's missing.
param(
    [switch]$StartWithWindows,
    [switch]$Hook,
    [switch]$Skills,
    [switch]$ExactUsage,
    [switch]$NoStart,
    [string]$ProgramsDir = [Environment]::GetFolderPath('Programs'),    # the Start menu (tools\Test-Install.ps1 uses a temp folder)
    [string]$StartupDir = [Environment]::GetFolderPath('Startup'),
    [string]$AppsKey = ''                                                # the Settings > Apps entry (the tests use a throwaway key)
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

if ($env:OS -ne 'Windows_NT') { Write-Host 'Tok only runs on Windows for now (it is drawn with WPF).'; exit 1 }

# PowerShell 7: Tok needs it. Started from Windows PowerShell, hand over to pwsh if it's there.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Host 'Tok needs PowerShell 7. Install it, then run this again:'
        Write-Host '    winget install Microsoft.PowerShell'
        exit 1
    }
    $pass = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v) { $pass += "-$k" } } else { $pass += "-$k"; $pass += "$v" }
    }
    & $pwsh.Source @pass
    exit $LASTEXITCODE
}
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Host 'PowerShell 7 is running but "pwsh" is not on your PATH, and Tok''s shortcut needs it. Reinstall it with:'
    Write-Host '    winget install Microsoft.PowerShell'
    exit 1
}

. (Join-Path $here 'lib\Transcripts.ps1')
. (Join-Path $here 'lib\Pet.ps1')
. (Join-Path $here 'lib\Menu.ps1')
. (Join-Path $here 'lib\Setup.ps1')
if (-not $AppsKey) { $AppsKey = $script:TokAppsKey }
$then = [string][char]0x203A      # "›", spelled as a code point so Windows PowerShell 5.1, reading this file as ANSI, still prints it right

# Claude Code: Tok reads its session transcripts. None yet is fine; Tok waits as an egg.
if (Test-Path -LiteralPath $script:ProjectsDir) { "Claude Code: found ($script:ProjectsDir)" }
else { Write-Warning "No Claude Code sessions in $script:ProjectsDir yet. Tok will wait as an egg until Claude Code writes one." }

# A zip from the internet marks every file as downloaded, and PowerShell then refuses to run the scripts. These are Tok's own.
Get-ChildItem -LiteralPath $here -Recurse -File -Include *.ps1, *.vbs | Unblock-File

$lnk = Join-Path $ProgramsDir 'Tok.lnk'
Set-TokShortcut $lnk $here
"Start menu: $lnk"

# Start with Windows: on when asked, and an existing Tok shortcut in the Startup folder (this copy's from 1.0, or another
# copy's) is pointed at this one.
$startLnk = Get-StartupShortcutPath $StartupDir
$startFrom = Get-TokShortcutDir $startLnk
if ($StartWithWindows -or $startFrom) {
    Set-StartWithWindows $true $here $StartupDir
    if ($startFrom -and $startFrom -ne $here) { "Start with Windows: moved over from $startFrom" }
}

$settings = Join-Path $script:ClaudeDir 'settings.json'
$notify = Join-Path $here 'notify.ps1'
$hookOn = $false
# a settings.json that isn't valid JSON is left untouched (Read-ClaudeSettings throws before anything is written): say so and go on
try {
    $others = @(Get-OtherTokHooks $settings $notify)
    if ($Hook -or $others.Count) {
        $r = Add-TokHook $settings $notify
        if ($r -eq 'moved') { "Notification hook: moved over from $(($others | ForEach-Object { Split-Path $_ }) -join ', ') ($settings)" }
        else { "Notification hook: $r ($settings). New Claude Code sessions pick it up." }
    }
    $s = Read-ClaudeSettings $settings
    if ($s.Contains('hooks') -and $s['hooks'] -and $s['hooks'].Contains('Notification')) {
        $hookOn = [bool]@(@($s['hooks']['Notification']) | Where-Object { $_ -and (Test-TokHookEntry $_ $notify) }).Count
    }
} catch { if ($Hook) { "Notification hook skipped: settings.json isn't valid JSON. Fix it, then run Install.ps1 -Hook." } }

$skillOn = $false
$skillFrom = Get-TokSkillDir (Get-TokSkillPath $script:ClaudeDir)
if ($Skills -or ($skillFrom -and $skillFrom -ne $here)) {
    $r = Add-TokSkill $script:ClaudeDir $here
    if ($r -eq 'theirs') { "Skill skipped: $(Get-TokSkillPath $script:ClaudeDir) is already there and isn't this Tok's." }
    elseif ($r -eq 'moved') { "Skill tok-private: moved over from $skillFrom ($(Get-TokSkillPath $script:ClaudeDir))"; $skillOn = $true }
    else { "Skill tok-private: $r ($(Get-TokSkillPath $script:ClaudeDir)). New Claude Code sessions pick it up."; $skillOn = $true }
} elseif ($skillFrom -eq $here) { $skillOn = $true }

$exactOn = $false
if ($ExactUsage) {
    if (Set-ConfigFileKey 'LiveUsage' $true) { $exactOn = $true }
    else { 'Exact usage skipped: config.json isn''t valid JSON. Fix it, then run Install.ps1 -ExactUsage.' }
}
if (-not $exactOn) {      # already on from before (a re-install, an update): say so
    try { $exactOn = (Get-Content (Join-Path $script:DataDir 'config.json') -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable).LiveUsage -eq $true } catch { }
}

Register-TokApp $here $AppsKey
"Settings $then Apps: Tok $script:TokVersion (uninstall it from there, or with Uninstall.ps1)"

# What is on and what is off, and where to change it (parliament session 6: Install asks nothing, so it says).
"Exact usage: $(if ($exactOn) { 'on' } else { "off (right-click Tok $then Settings)" })"
"Wave at permission prompts: $(if ($hookOn) { 'on' } else { 'off (Install.ps1 -Hook)' })"
$skillTheirs = -not $skillOn -and (Test-Path -LiteralPath (Get-TokSkillPath $script:ClaudeDir)) -and -not (Get-TokSkillDir (Get-TokSkillPath $script:ClaudeDir))
"Private mode by Claude (tok-private skill): $(if ($skillOn) { 'on' } elseif ($skillTheirs) { 'your own skill of that name, left as it is' } else { 'off (Install.ps1 -Skills)' })"
"Start with Windows: $(if (Test-StartWithWindows $StartupDir) { 'on' } else { "off (right-click Tok $then Settings)" })"
"Close Tok: right-click it $then Goodbye"

if ($NoStart) { return }
if (Test-TokRunning) { 'Tok is already running. To run this version, right-click it, choose Goodbye, and start it from the Start menu.'; return }
Start-Process -FilePath $lnk
'Tok is starting (bottom-right of your screen).'
