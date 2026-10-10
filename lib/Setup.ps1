# Setup.ps1 - what Install.ps1 and Uninstall.ps1 share: shortcuts, the Notification hook in Claude Code's settings, and
# seeing whether a Tok is running (by its mutex, Get-TokMutexName in lib\Pet.ps1). Nothing here runs on load.

# A shortcut that starts Tok with no console window (wscript runs Start-Tok.vbs).
function New-TokShortcut([string]$Path, [string]$Launcher) {
    $null = New-Item -ItemType Directory -Force (Split-Path $Path)
    $sh = New-Object -ComObject WScript.Shell
    try {
        $s = $sh.CreateShortcut($Path)
        $s.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $s.Arguments = """$Launcher"""
        $s.WorkingDirectory = Split-Path $Launcher
        $s.Description = 'Tok, a small desktop creature that is Claude'
        $s.Save()
    } finally { $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
}

# Whether a shortcut starts this copy of Tok (so Uninstall never removes another copy's).
function Test-TokShortcut([string]$Path, [string]$Launcher) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $sh = New-Object -ComObject WScript.Shell
    try { $sh.CreateShortcut($Path).Arguments -like "*$Launcher*" } finally { $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
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

# Adds the hook to Claude Code's user settings, once. The file is backed up the first time (settings.json.tok-backup).
# Returns 'added' or 'already'.
function Add-TokHook([string]$SettingsPath, [string]$NotifyPath) {
    $s = Read-ClaudeSettings $SettingsPath
    if (-not $s.Contains('hooks') -or $null -eq $s['hooks']) { $s['hooks'] = [ordered]@{} }
    $list = @($s['hooks']['Notification'] | Where-Object { $_ })
    if (@($list | Where-Object { Test-TokHookEntry $_ $NotifyPath }).Count) { return 'already' }
    if ((Test-Path -LiteralPath $SettingsPath) -and -not (Test-Path -LiteralPath "$SettingsPath.tok-backup")) { Copy-Item -LiteralPath $SettingsPath "$SettingsPath.tok-backup" }
    $list += [ordered]@{ matcher = $script:TokHookMatcher; hooks = @([ordered]@{ type = 'command'; command = (Get-TokHookCommand $NotifyPath) }) }
    $s['hooks']['Notification'] = $list
    Save-ClaudeSettings $s $SettingsPath
    'added'
}

# Takes Tok's hook out again, and nothing else; empty Notification and hooks blocks go too. Returns 'removed' or 'none'.
function Remove-TokHook([string]$SettingsPath, [string]$NotifyPath) {
    if (-not (Test-Path -LiteralPath $SettingsPath)) { return 'none' }
    $s = Read-ClaudeSettings $SettingsPath
    if (-not $s.Contains('hooks') -or -not $s['hooks'] -or -not $s['hooks'].Contains('Notification')) { return 'none' }
    $all = @($s['hooks']['Notification'] | Where-Object { $_ })
    $keep = @($all | Where-Object { -not (Test-TokHookEntry $_ $NotifyPath) })
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
function Add-TokSkill([string]$ClaudeDir, [string]$TokDir) {
    $path = Get-TokSkillPath $ClaudeDir
    $was = Test-Path -LiteralPath $path
    if ($was -and -not (Test-TokSkillOurs $path $TokDir)) { return 'theirs' }
    $text = (Get-Content -LiteralPath (Join-Path $TokDir "skills\$script:TokSkillName\SKILL.md") -Raw).Replace('{{TOK}}', $TokDir)
    $null = New-Item -ItemType Directory -Force (Split-Path $path)
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    if ($was) { 'updated' } else { 'added' }
}
# Takes this copy's skill out again (and its folder, if nothing else is in it). Returns 'removed' or 'none'.
function Remove-TokSkill([string]$ClaudeDir, [string]$TokDir) {
    $path = Get-TokSkillPath $ClaudeDir
    if (-not (Test-TokSkillOurs $path $TokDir)) { return 'none' }
    Remove-Item -LiteralPath $path -Force
    $dir = Split-Path $path
    if (-not @(Get-ChildItem -LiteralPath $dir -Force).Count) { Remove-Item -LiteralPath $dir -Force }
    'removed'
}
