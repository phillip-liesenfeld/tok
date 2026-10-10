# Install.ps1 - sets Tok up for this Windows user: checks what it needs, adds a Start menu shortcut, and starts it.
#   pwsh -ExecutionPolicy Bypass -File Install.ps1                     check, shortcut, start Tok
#   pwsh -ExecutionPolicy Bypass -File Install.ps1 -StartWithWindows   ...and start it when you sign in
#   pwsh -ExecutionPolicy Bypass -File Install.ps1 -Hook               ...and let Claude Code tell Tok when it needs your OK
#                                                                      (a Notification hook in ~\.claude\settings.json)
#   pwsh -ExecutionPolicy Bypass -File Install.ps1 -ExactUsage         ...and let Tok ask Anthropic for your exact 5-hour usage, with
#                                                                      Claude Code's own login (writes LiveUsage: true to config.json;
#                                                                      off unless you ask, here or in right-click > Settings > Exact usage)
# Nothing is copied: Tok runs from this folder and keeps its own files in %LOCALAPPDATA%\tok. Uninstall.ps1 undoes it all.
# Written so Windows PowerShell 5.1 can read it far enough to say what's missing.
param(
    [switch]$StartWithWindows,
    [switch]$Hook,
    [switch]$ExactUsage,
    [switch]$NoStart,
    [string]$ProgramsDir = [Environment]::GetFolderPath('Programs'),    # the Start menu (tools\Test-Install.ps1 uses a temp folder)
    [string]$StartupDir = [Environment]::GetFolderPath('Startup')
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
    Write-Host 'PowerShell 7 is running but "pwsh" is not on your PATH, and Start-Tok.vbs needs it. Reinstall it with:'
    Write-Host '    winget install Microsoft.PowerShell'
    exit 1
}

. (Join-Path $here 'lib\Transcripts.ps1')
. (Join-Path $here 'lib\Pet.ps1')
. (Join-Path $here 'lib\Menu.ps1')
. (Join-Path $here 'lib\Setup.ps1')
$launcher = Join-Path $here 'Start-Tok.vbs'

# Claude Code: Tok reads its session transcripts. None yet is fine; Tok waits as an egg.
if (Test-Path -LiteralPath $script:ProjectsDir) { "Claude Code: found ($script:ProjectsDir)" }
else { Write-Warning "No Claude Code sessions in $script:ProjectsDir yet. Tok will wait as an egg until Claude Code writes one." }

# A zip from the internet marks every file as downloaded, and PowerShell then refuses to run the scripts. These are Tok's own.
Get-ChildItem -LiteralPath $here -Recurse -File -Include *.ps1, *.vbs | Unblock-File

$lnk = Join-Path $ProgramsDir 'Tok.lnk'
New-TokShortcut $lnk $launcher
"Start menu: $lnk"
if ($StartWithWindows) { Set-StartWithWindows $true $launcher $StartupDir; "Starts with Windows: $(Get-StartupShortcutPath $StartupDir)" }
$hookOn = $false
if ($Hook) {
    # a settings.json that isn't valid JSON is left untouched (Read-ClaudeSettings throws before anything is written): say so and go on
    try {
        $settings = Join-Path $script:ClaudeDir 'settings.json'
        $r = Add-TokHook $settings (Join-Path $here 'notify.ps1')
        "Notification hook: $r ($settings). New Claude Code sessions pick it up."
        $hookOn = $true
    } catch { "Notification hook skipped: settings.json isn't valid JSON. Fix it, then run Install.ps1 -Hook." }
}

$exactOn = $false
if ($ExactUsage) {
    if (Set-ConfigFileKey 'LiveUsage' $true) { $exactOn = $true }
    else { 'Exact usage skipped: config.json isn''t valid JSON. Fix it, then run Install.ps1 -ExactUsage.' }
}

# What is on and what is off, and where to change it (parliament session 6: Install asks nothing, so it says). "›" is spelled as
# a code point so Windows PowerShell 5.1, reading this file as ANSI, still prints it right.
$then = [string][char]0x203A
"Exact usage: $(if ($exactOn) { 'on' } else { "off (right-click Tok $then Settings)" })"
"Wave at permission prompts: $(if ($hookOn) { 'on' } else { 'off (Install.ps1 -Hook)' })"
"Start with Windows: $(if ($StartWithWindows) { 'on' } else { "off (right-click Tok $then Settings)" })"
"Close Tok: right-click it $then Goodbye"

if ($NoStart) { return }
if (Test-TokRunning) { 'Tok is already running.'; return }
Start-Process (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList """$launcher"""
'Tok is starting (bottom-right of your screen).'
