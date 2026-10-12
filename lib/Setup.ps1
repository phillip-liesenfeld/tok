# Setup.ps1 - what Install.ps1, Update.ps1 and Uninstall.ps1 share: shortcuts (Set-TokShortcut is in lib\Menu.ps1), the
# Notification hook in Claude Code's settings, the skill, the Settings › Apps entry, and seeing whether a Tok is running (by its mutex, Get-TokMutexName in lib\Pet.ps1). Nothing here runs on load.

# The version Install writes to Settings › Apps.
$script:TokVersion = '1.1.1'

# Which Tok folder a shortcut starts: Set-TokShortcut's (…\tok.ps1) or a 1.0 one's (wscript …\Start-Tok.vbs). $null for any
# other shortcut.
function Get-TokShortcutDir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $sh = New-Object -ComObject WScript.Shell
    try { $a = $sh.CreateShortcut($Path).Arguments } finally { $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
    if ($a -match '"([^"]+)\\(?:tok\.ps1|Start-Tok\.vbs)"') { return $Matches[1] }
    $null
}

# Whether a shortcut starts this copy of Tok (so Uninstall never removes another copy's).
function Test-TokShortcut([string]$Path, [string]$TokDir) {
    $d = Get-TokShortcutDir $Path
    $null -ne $d -and $d.TrimEnd('\') -eq $TokDir.TrimEnd('\')
}

# A Tok shortcut whose folder no longer holds a Tok: an older copy that was deleted. Uninstall clears those too.
function Test-StaleTokShortcut([string]$Path) {
    $d = Get-TokShortcutDir $Path
    $null -ne $d -and -not (Test-Path -LiteralPath (Join-Path $d 'tok.ps1'))
}

# Is the Tok for this data folder running? It holds its mutex for as long as it lives.
function Test-TokRunning([string]$Name = (Get-TokMutexName)) {
    $m = $null
    try {
        $m = [Threading.Mutex]::OpenExisting($Name)
        if ($m.WaitOne(0)) { $m.ReleaseMutex(); return $false }
        return $true
    } catch [Threading.AbandonedMutexException] { try { $m.ReleaseMutex() } catch { }; return $false }
    catch { return $false }      # no such mutex: nothing running
    finally { if ($m) { $m.Dispose() } }
}

# Asks the Tok for this data folder to close (the quit line in its inbox) and waits for it, up to $Seconds. Never kills.
function Stop-Tok([string]$DataDir, [double]$Seconds = 10) {
    if (-not (Test-TokRunning)) { return $true }
    $msg = [ordered]@{ cmd = 'quit'; why = 'uninstall'; at = [datetime]::UtcNow.ToString('o') }
    Add-Content -LiteralPath (Join-Path $DataDir 'inbox.jsonl') -Value ($msg | ConvertTo-Json -Compress) -Encoding utf8
    $deadline = [datetime]::UtcNow.AddSeconds($Seconds)
    while ([datetime]::UtcNow -lt $deadline) { if (-not (Test-TokRunning)) { return $true }; Start-Sleep -Milliseconds 250 }
    -not (Test-TokRunning)
}

# The Notification hook (notify.ps1): Claude Code tells Tok when it needs you and the transcript can't (a permission prompt,
# a server asking for input). Only those kinds start it, so the hook costs nothing the rest of the time.
$script:TokHookMatcher = 'permission_prompt|worker_permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input'
function Get-TokHookCommand([string]$NotifyPath) { "pwsh -NoProfile -File `"$($NotifyPath -replace '\\', '/')`"" }

function Read-ClaudeSettings([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [ordered]@{} }
    $raw = Get-Content -LiteralPath $Path -Raw
    if (-not $raw.Trim()) { return [ordered]@{} }
    $raw | ConvertFrom-Json -AsHashtable      # throws on a broken file: better than writing over it
}
function Save-ClaudeSettings($Settings, [string]$Path) {
    $null = New-Item -ItemType Directory -Force (Split-Path $Path)
    [IO.File]::WriteAllText($Path, ($Settings | ConvertTo-Json -Depth 64) + "`n", [Text.UTF8Encoding]::new($false))
}
function Test-TokHookEntry($Entry, [string]$NotifyPath) {
    $p = $NotifyPath -replace '\\', '/'
    @($Entry.hooks | Where-Object { "$($_.command)" -replace '\\', '/' -like "*$p*" }).Count -gt 0
}
# The notify.ps1 a Tok hook runs, from any copy: the exact shape Add-TokHook writes (Tok's matcher, one pwsh command). $null for
# any other hook.
function Get-TokHookNotifyPath($Entry) {
    if ("$($Entry.matcher)" -ne $script:TokHookMatcher) { return $null }
    foreach ($h in @($Entry.hooks)) { if ("$($h.command)" -match '^pwsh -NoProfile -File "(.+/notify\.ps1)"$') { return $Matches[1] -replace '/', '\' } }
    $null
}
# The notify.ps1 paths of the Tok hooks other copies added (an older version unzipped somewhere else). Throws on a broken file.
function Get-OtherTokHooks([string]$SettingsPath, [string]$NotifyPath) {
    $s = Read-ClaudeSettings $SettingsPath
    if (-not $s.Contains('hooks') -or -not $s['hooks'] -or -not $s['hooks'].Contains('Notification')) { return @() }
    @($s['hooks']['Notification'] | Where-Object { $_ } | ForEach-Object { Get-TokHookNotifyPath $_ } | Where-Object { $_ -and $_ -ne $NotifyPath })
}

# Adds the hook to Claude Code's user settings, once, and takes over from any other copy's Tok hook (so a new version in a new
# folder doesn't leave a second hook behind, pointing at a folder that may be deleted). The file is backed up the first time
# (settings.json.tok-backup). Returns 'added', 'moved' (another copy's hook replaced) or 'already'.
function Add-TokHook([string]$SettingsPath, [string]$NotifyPath) {
    $s = Read-ClaudeSettings $SettingsPath
    if (-not $s.Contains('hooks') -or $null -eq $s['hooks']) { $s['hooks'] = [ordered]@{} }
    $all = @($s['hooks']['Notification'] | Where-Object { $_ })
    $list = @($all | Where-Object { $p = Get-TokHookNotifyPath $_; -not $p -or $p -eq $NotifyPath })
    $moved = $list.Count -lt $all.Count
    $have = @($list | Where-Object { Test-TokHookEntry $_ $NotifyPath }).Count -gt 0
    if (-not $moved -and $have) { return 'already' }
    if ((Test-Path -LiteralPath $SettingsPath) -and -not (Test-Path -LiteralPath "$SettingsPath.tok-backup")) { Copy-Item -LiteralPath $SettingsPath "$SettingsPath.tok-backup" }
    if (-not $have) { $list += [ordered]@{ matcher = $script:TokHookMatcher; hooks = @([ordered]@{ type = 'command'; command = (Get-TokHookCommand $NotifyPath) }) } }
    $s['hooks']['Notification'] = $list
    Save-ClaudeSettings $s $SettingsPath
    if ($moved) { 'moved' } else { 'added' }
}

# Takes Tok's hook out again, and nothing else; empty Notification and hooks blocks go too. A Tok hook whose notify.ps1 is gone
# (a deleted older copy) goes with it. Returns 'removed' or 'none'.
function Remove-TokHook([string]$SettingsPath, [string]$NotifyPath) {
    if (-not (Test-Path -LiteralPath $SettingsPath)) { return 'none' }
    $s = Read-ClaudeSettings $SettingsPath
    if (-not $s.Contains('hooks') -or -not $s['hooks'] -or -not $s['hooks'].Contains('Notification')) { return 'none' }
    $all = @($s['hooks']['Notification'] | Where-Object { $_ })
    $keep = @($all | Where-Object {
        $p = Get-TokHookNotifyPath $_
        -not (Test-TokHookEntry $_ $NotifyPath) -and -not ($p -and -not (Test-Path -LiteralPath $p))
    })
    if ($keep.Count -eq $all.Count) { return 'none' }
    if ($keep.Count) { $s['hooks']['Notification'] = $keep } else { $s['hooks'].Remove('Notification') }
    if (-not $s['hooks'].Count) { $s.Remove('hooks') }
    Save-ClaudeSettings $s $SettingsPath
    'removed'
}

# What Tok keeps in its data folder. Uninstall deletes the folder only when nothing else is in it, so a TOK_DATA_DIR pointed
# at the wrong place can't take anything with it.
$script:TokDataNames = 'state.json', 'config.json', 'tok.log', 'inbox.jsonl', 'live.json', 'record.json', 'sounds'
function Get-ForeignDataItems([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    @(Get-ChildItem -LiteralPath $Dir -Force | Where-Object { $_.Name -notin $script:TokDataNames -and $_.Name -notlike '*.tmp' } | ForEach-Object Name)
}

# The tok-private skill (skills\tok-private\SKILL.md, this copy's path filled in): lets Claude put Tok in private mode by itself
# before sensitive work. Installed only on request (Install.ps1 -Skills), into Claude Code's skills folder, and never over a
# skill of that name that some other copy or the user made. Returns 'added', 'updated' or 'theirs'.
$script:TokSkillName = 'tok-private'
function Get-TokSkillPath([string]$ClaudeDir) { Join-Path $ClaudeDir "skills\$script:TokSkillName\SKILL.md" }
function Test-TokSkillOurs([string]$Path, [string]$TokDir) {
    (Test-Path -LiteralPath $Path) -and (Get-Content -LiteralPath $Path -Raw).Contains("<!-- installed by Tok from $TokDir;")
}
# The Tok folder that installed the skill (any copy, from its marker comment); $null when it isn't Tok's.
function Get-TokSkillDir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if ((Get-Content -LiteralPath $Path -Raw) -match '<!-- installed by Tok from (.+?); ') { return $Matches[1] }
    $null
}
# Writes the skill with this copy's path. Another copy's Tok skill is taken over; anyone else's is left alone.
# Returns 'added', 'updated', 'moved' or 'theirs'.
function Add-TokSkill([string]$ClaudeDir, [string]$TokDir) {
    $path = Get-TokSkillPath $ClaudeDir
    $was = Test-Path -LiteralPath $path
    $from = Get-TokSkillDir $path
    if ($was -and -not $from) { return 'theirs' }
    $text = (Get-Content -LiteralPath (Join-Path $TokDir "skills\$script:TokSkillName\SKILL.md") -Raw).Replace('{{TOK}}', $TokDir)
    $null = New-Item -ItemType Directory -Force (Split-Path $path)
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    if (-not $was) { 'added' } elseif ($from -ne $TokDir) { 'moved' } else { 'updated' }
}
# Takes this copy's skill out again, or a Tok skill whose folder no longer holds a Tok (and its folder, if nothing else is in
# it). Returns 'removed' or 'none'.
function Remove-TokSkill([string]$ClaudeDir, [string]$TokDir) {
    $path = Get-TokSkillPath $ClaudeDir
    $from = Get-TokSkillDir $path
    if (-not $from -or ($from -ne $TokDir -and (Test-Path -LiteralPath (Join-Path $from 'tok.ps1')))) { return 'none' }
    Remove-Item -LiteralPath $path -Force
    $dir = Split-Path $path
    if (-not @(Get-ChildItem -LiteralPath $dir -Force).Count) { Remove-Item -LiteralPath $dir -Force }
    'removed'
}

# Settings › Apps › Installed apps: Tok's entry, per user (no admin). Its Uninstall runs this copy's Uninstall.ps1, which asks
# before deleting the data folder and waits for Enter at the end. One entry: the newest Install writes it. $Key is for the tests.
$script:TokAppsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Tok'
function Register-TokApp([string]$TokDir, [string]$Key = $script:TokAppsKey) {
    if (-not (Test-Path -LiteralPath $Key)) { $null = New-Item -Path $Key -Force }
    $keyArg = if ($Key -ne $script:TokAppsKey) { ' -AppsKey "' + $Key + '"' } else { '' }      # another key (a test's): its own Uninstall finds it
    $values = [ordered]@{
        DisplayName     = 'Tok'
        DisplayVersion  = $script:TokVersion
        Comments        = 'A small desktop creature that stands for Claude and shows your Claude Code usage'
        InstallLocation = $TokDir
        DisplayIcon     = Join-Path $TokDir 'tok.ico'
        UninstallString = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ""$(Join-Path $TokDir 'Uninstall.ps1')"" -FromSettings$keyArg"
    }
    foreach ($k in $values.Keys) { $null = New-ItemProperty -LiteralPath $Key -Name $k -Value $values[$k] -PropertyType String -Force }
    foreach ($k in 'NoModify', 'NoRepair') { $null = New-ItemProperty -LiteralPath $Key -Name $k -Value 1 -PropertyType DWord -Force }
}
# Takes the entry out if it is this copy's (or its copy is gone). Returns 'removed' or 'none'.
function Unregister-TokApp([string]$TokDir, [string]$Key = $script:TokAppsKey) {
    if (-not (Test-Path -LiteralPath $Key)) { return 'none' }
    $at = (Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue).InstallLocation
    if ($at -and $at -ne $TokDir -and (Test-Path -LiteralPath (Join-Path $at 'tok.ps1'))) { return 'none' }
    Remove-Item -LiteralPath $Key -Recurse -Force
    'removed'
}
