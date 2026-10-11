# Test-Install.ps1 - the clean-profile check: a stranger's install, first run, opt-out and uninstall, then a zip copy, a clone
# that takes over from it, an update and an uninstall, in a temp profile beside the real Tok (TOK_DATA_DIR and CLAUDE_CONFIG_DIR
# point at temp folders; the shortcuts go to temp folders, the Settings > Apps entry to a throwaway registry key).
# The temp Claude folder has one small made-up session, so the first run has a day of work to read.
#   pwsh -NoProfile -File tools\Test-Install.ps1
# Exit code: the number of failed checks.
param([double]$FirstRunSeconds = 20, [double]$OptOutSeconds = 12)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'lib\Transcripts.ps1')
. (Join-Path $root 'lib\Pet.ps1')
. (Join-Path $root 'lib\Lineage.ps1')
. (Join-Path $root 'lib\Setup.ps1')

$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [scriptblock]$Test) {
    try { if (& $Test) { $script:Pass++; Write-Host "ok    $Name"; return }; Write-Host "FAIL  $Name" -ForegroundColor Red; $script:Fail++ }
    catch { Write-Host "ERROR $Name : $_" -ForegroundColor Red; $script:Fail++ }
}

$t = Join-Path ([IO.Path]::GetTempPath()) "tok-install-$PID"
$data = Join-Path $t 'data'; $claude = Join-Path $t 'claude'; $programs = Join-Path $t 'Programs'; $startup = Join-Path $t 'Startup'
$session = Join-Path $claude 'projects\C--Users-x-demo'
$appsRoot = "HKCU:\Software\TokTest-$PID"; $apps = "$appsRoot\Uninstall\Tok"
$null = New-Item -ItemType Directory -Force $session, $programs, $startup

# One made-up session from an hour ago: a prompt and 12 replies, enough for a day to count (Tok hatches on its first day).
$start = [datetime]::UtcNow.AddHours(-1)
$lines = @('{"type":"user","cwd":"C:\\Users\\x\\demo","timestamp":"' + $start.ToString('o') + '","message":{"role":"user","content":"hello"}}')
for ($i = 0; $i -lt 12; $i++) {
    $lines += '{"type":"assistant","cwd":"C:\\Users\\x\\demo","timestamp":"' + $start.AddMinutes($i + 1).ToString('o') + '","message":{"model":"claude-opus-5-5","id":"msg_demo' + $i +
        '","role":"assistant","content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":0,"output_tokens":50}}}'
}
Set-Content (Join-Path $session 'demo.jsonl') $lines
(Get-Item (Join-Path $session 'demo.jsonl')).LastWriteTimeUtc = $start.AddMinutes(13)

# The real Tok, before: its log, its inbox, and whether it is running (it must still be, after).
$realDir = Join-Path $env:LOCALAPPDATA 'tok'
$realLog = Join-Path $realDir 'tok.log'; $realInbox = Join-Path $realDir 'inbox.jsonl'
$realInboxLen = if (Test-Path $realInbox) { (Get-Item $realInbox).Length } else { 0 }
$realLogLen = if (Test-Path $realLog) { (Get-Item $realLog).Length } else { 0 }      # only lines written during the test count (PIDs get reused)
$realFiles = @(Get-ChildItem $realDir -ErrorAction SilentlyContinue | ForEach-Object Name)
$realRunning = Test-TokRunning 'Local\Tok'
$pids = @()

$saved = $env:TOK_DATA_DIR, $env:CLAUDE_CONFIG_DIR
$env:TOK_DATA_DIR = $data; $env:CLAUDE_CONFIG_DIR = $claude
$tok = $null
try {
    $hookCmd = Get-TokHookCommand (Join-Path $root 'notify.ps1')
    # ---- install
    $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Install.ps1') -NoStart -Hook -Skills -StartWithWindows -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1
    $code = $LASTEXITCODE
    Check 'install: exits cleanly and finds the Claude Code sessions' { $code -eq 0 -and ($out -join "`n") -match 'Claude Code: found' }
    Check 'install: a Start menu shortcut and a Startup one, both starting this copy' {
        (Test-TokShortcut (Join-Path $programs 'Tok.lnk') $root) -and (Test-TokShortcut (Join-Path $startup 'Tok.lnk') $root) -and
        (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $programs 'Tok.lnk')).TargetPath -match '\\conhost\.exe$'
    }
    Check 'install: the Notification hook is in the temp Claude settings' {
        $h = @((Get-Content (Join-Path $claude 'settings.json') -Raw | ConvertFrom-Json -AsHashtable).hooks.Notification)
        $h.Count -eq 1 -and $h[0].hooks[0].command -eq $hookCmd
    }
    Check 'install -Skills: the tok-private skill is in the temp Claude folder, pointing at this copy' {
        $sk = Join-Path $claude 'skills\tok-private\SKILL.md'
        (Test-Path $sk) -and (Get-Content $sk -Raw).Contains("'$root\private.ps1'") -and (Get-Content $sk -Raw) -notmatch '\{\{TOK\}\}' -and ($out -join "`n") -match 'tok-private skill\): on'
    }
    Check 'install: Tok is in Settings > Apps (the throwaway key), pointing at this copy''s Uninstall.ps1' {
        $v = Get-ItemProperty -LiteralPath $apps
        $v.DisplayName -eq 'Tok' -and $v.InstallLocation -eq $root -and $v.UninstallString -match [regex]::Escape("$root\Uninstall.ps1") -and ($out -join "`n") -match 'Apps: Tok'
    }
    Check 'install: it ends by saying what is on and off, and how to close Tok' {
        $o = $out -join "`n"
        $o -match 'Exact usage: off \(right-click Tok .{1,3} Settings\)' -and $o -match 'Wave at permission prompts: on\b' -and $o -match 'Start with Windows: on\b' -and $o -match 'Close Tok: right-click it .{1,3} Goodbye'
    }

    # ---- a broken settings.json: -Hook says so and carries on (the file is left as it was)
    $claude2 = Join-Path $t 'claude-broken'; $null = New-Item -ItemType Directory -Force $claude2
    $badRaw = '{ "hooks": { oops'
    [IO.File]::WriteAllText((Join-Path $claude2 'settings.json'), $badRaw)
    $theirs = Join-Path $claude2 'skills\tok-private\SKILL.md'; $null = New-Item -ItemType Directory -Force (Split-Path $theirs); Set-Content $theirs 'their own skill'
    $env:CLAUDE_CONFIG_DIR = $claude2
    try { $out2 = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Install.ps1') -NoStart -Hook -Skills -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1; $code2 = $LASTEXITCODE } finally { $env:CLAUDE_CONFIG_DIR = $claude }
    Check 'install -Hook: a settings.json that is not valid JSON is skipped with one line, left untouched, and Install still finishes (exit 0, the closing lines)' {
        $o2 = $out2 -join "`n"
        $code2 -eq 0 -and $o2 -match [regex]::Escape("Notification hook skipped: settings.json isn't valid JSON. Fix it, then run Install.ps1 -Hook.") -and
        [IO.File]::ReadAllText((Join-Path $claude2 'settings.json')) -ceq $badRaw -and -not (Test-Path (Join-Path $claude2 'settings.json.tok-backup')) -and
        $o2 -match 'Wave at permission prompts: off \(Install\.ps1 -Hook\)' -and $o2 -match 'Close Tok:'
    }
    Check 'install -Skills: a tok-private skill someone else made is left alone, and said so' { ($out2 -join "`n") -match 'Skill skipped' -and (Get-Content $theirs -Raw).Trim() -eq 'their own skill' }

    # ---- first run (no config, no login: Tok can't and doesn't call anything)
    $tok = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-STA', '-NoProfile', '-File', (Join-Path $root 'tok.ps1'), '-X', '20000', '-Y', '20000'
    $pids += $tok.Id
    $log = Join-Path $data 'tok.log'
    $deadline = (Get-Date).AddSeconds($FirstRunSeconds)
    while ((Get-Date) -lt $deadline -and -not ((Test-Path $log) -and (Get-Content $log -Raw) -match 'family tree built')) { Start-Sleep -Milliseconds 500 }
    $logText = if (Test-Path $log) { Get-Content $log -Raw } else { '' }
    Check 'first run: Tok starts in the temp folder, beside the real one (its own mutex)' { $logText -match "started \(pid $($tok.Id)" -and (Test-TokRunning) -and -not $tok.HasExited }
    Check 'first run: it reads the temp Claude folder (the made-up day: 12 replies, one generation, hatched)' {
        $s = Get-Content (Join-Path $data 'state.json') -Raw | ConvertFrom-Json -AsHashtable
        $logText -match 'family tree built' -and $s.Lineage.Versions['5.5'].Replies -eq 12 -and @($s.Lineage.Generations).Count -eq 1 -and (Get-PetStage $s).Name -eq 'hatchling'
    }
    Check 'first run: no errors in its log' { $logText -notmatch 'tick:|failed|error' }

    # ---- the say/needs inbox works for this Tok too
    & pwsh -NoProfile -File (Join-Path $root 'say.ps1') 'Hello from the check' -Silent 3>$null
    Check 'say.ps1: writes to the temp inbox, not the real one' { (Get-Content (Join-Path $data 'inbox.jsonl') -Raw) -match 'Hello from the check' }

    # ---- goodbye, then the default: exact usage is off unless ticked, so with a login present Tok never calls
    Check 'quit: asked through the inbox, it closes on its own' { (Stop-Tok $data 15) -and $tok.WaitForExit(5000) }
    Remove-Item (Join-Path $data 'live.json') -ErrorAction SilentlyContinue
    Check 'default: a stranger''s config has no LiveUsage key (the first run wrote none)' { -not (Test-Path (Join-Path $data 'config.json')) -or -not (Get-Content (Join-Path $data 'config.json') -Raw).Contains('LiveUsage') }
    '{"claudeAiOauth":{"accessToken":"not-a-real-token","expiresAt":' + [DateTimeOffset]::UtcNow.AddDays(1).ToUnixTimeMilliseconds() + '}}' | Set-Content (Join-Path $claude '.credentials.json')
    $tok = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-STA', '-NoProfile', '-File', (Join-Path $root 'tok.ps1'), '-X', '20000', '-Y', '20000'
    $pids += $tok.Id
    Start-Sleep -Seconds $OptOutSeconds
    Check 'default: with exact usage off by default, Tok never asks for it (no live.json), even with a login on disk' { -not $tok.HasExited -and -not (Test-Path (Join-Path $data 'live.json')) }
    Check 'default: quit again' { (Stop-Tok $data 15) -and $tok.WaitForExit(5000) }

    # ---- Install.ps1 -ExactUsage turns it on, keeping any other setting already in config.json
    @{ Chatter = 'quiet' } | ConvertTo-Json | Set-Content (Join-Path $data 'config.json')
    $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Install.ps1') -NoStart -ExactUsage -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1
    $code = $LASTEXITCODE
    Check 'install -ExactUsage: writes LiveUsage: true to the data folder''s config.json and keeps the other keys' {
        $c = Get-Content (Join-Path $data 'config.json') -Raw | ConvertFrom-Json -AsHashtable
        $code -eq 0 -and $c.LiveUsage -eq $true -and $c.Chatter -eq 'quiet' -and $c.Count -eq 2 -and ($out -join "`n") -match 'Exact usage: on\b'
    }

    # ---- uninstall
    $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Uninstall.ps1') -Yes -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1
    $code = $LASTEXITCODE
    Check 'uninstall: exits cleanly' { $code -eq 0 -and ($out -join "`n") -match 'uninstalled' }
    Check 'uninstall -Yes: shortcuts, Settings > Apps entry, hook, skill and data folder gone; the Claude folder and its sessions stay' {
        -not (Test-Path $apps) -and -not (Test-Path (Join-Path $programs 'Tok.lnk')) -and -not (Test-Path (Join-Path $startup 'Tok.lnk')) -and -not (Test-Path $data) -and
        (Get-Content (Join-Path $claude 'settings.json') -Raw) -notmatch 'notify\.ps1' -and (Test-Path (Join-Path $session 'demo.jsonl')) -and
        -not (Test-Path (Join-Path $claude 'skills\tok-private'))
    }

    # ---- copies: a zip copy (every file marked as downloaded), then a git clone that takes over from it
    $copyA = Join-Path $t 'tok-1.0-zip'; $origin = Join-Path $t 'origin'; $copyB = Join-Path $t 'clone\tok'
    function Copy-Tok([string]$To) {
        $null = New-Item -ItemType Directory -Force $To
        Get-ChildItem $root -File | Where-Object Extension -in '.ps1', '.vbs', '.ico' | Copy-Item -Destination $To
        foreach ($d in 'lib', 'skills') { Copy-Item (Join-Path $root $d) $To -Recurse }
    }
    Copy-Tok $copyA
    Get-ChildItem $copyA -Recurse -File | ForEach-Object { Set-Content -LiteralPath $_.FullName -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" }
    Copy-Tok $origin
    $g = @('-c', 'user.name=Tok test', '-c', 'user.email=test@example.invalid')
    $null = & git -C $origin init -q -b main 2>&1; $null = & git -C $origin add -A 2>&1; $null = & git @g -C $origin commit -q -m 'Tok' 2>&1
    $null = & git clone -q $origin $copyB 2>&1
    $null = New-Item -ItemType Directory -Force $data; '{"LiveUsage":true}' | Set-Content (Join-Path $data 'config.json')      # exact usage on from before
    $policyPref = $env:PSExecutionPolicyPreference; $env:PSExecutionPolicyPreference = $null      # a parent's -ExecutionPolicy would carry over
    try {
        $outA0 = & pwsh -NoProfile -File (Join-Path $copyA 'Install.ps1') -NoStart -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1; $codeA0 = $LASTEXITCODE
        $outA = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $copyA 'Install.ps1') -NoStart -Hook -Skills -StartWithWindows -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1; $codeA = $LASTEXITCODE
        $outB = & pwsh -NoProfile -File (Join-Path $copyB 'Install.ps1') -NoStart -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1; $codeB = $LASTEXITCODE
    } finally { $env:PSExecutionPolicyPreference = $policyPref }
    Check 'zip copy: without -ExecutionPolicy Bypass Windows refuses its scripts (the control); with it, Install runs and unblocks them' {
        $codeA0 -ne 0 -and ($outA0 -join "`n") -match 'not digitally signed|cannot be loaded' -and $codeA -eq 0 -and
        -not (Get-Item (Join-Path $copyA 'tok.ps1') -Stream Zone.Identifier -ErrorAction SilentlyContinue)
    }
    Check 'clone: Install runs with no -ExecutionPolicy Bypass (a clone has no download marks)' { $codeB -eq 0 -and ($outB -join "`n") -match 'Claude Code: found' }
    Check 'clone: takes over from the zip copy (Start menu, Startup, hook, skill, Settings > Apps all point at the clone; one Tok hook)' {
        $s = Get-Content (Join-Path $claude 'settings.json') -Raw | ConvertFrom-Json -AsHashtable
        $tokHooks = @(@($s.hooks.Notification) | ForEach-Object { Get-TokHookNotifyPath $_ } | Where-Object { $_ })
        $o = $outB -join "`n"
        (Test-TokShortcut (Join-Path $programs 'Tok.lnk') $copyB) -and (Test-TokShortcut (Join-Path $startup 'Tok.lnk') $copyB) -and
        $tokHooks.Count -eq 1 -and $tokHooks[0] -eq (Join-Path $copyB 'notify.ps1') -and (Get-TokSkillDir (Join-Path $claude 'skills\tok-private\SKILL.md')) -eq $copyB -and
        (Get-ItemProperty -LiteralPath $apps).InstallLocation -eq $copyB -and $o -match 'Start with Windows: moved over' -and $o -match 'Notification hook: moved over' -and
        $o -match 'Skill tok-private: moved over' -and $o -match 'Wave at permission prompts: on\b' -and $o -match 'Start with Windows: on\b' -and $o -match 'Exact usage: on\b'
    }

    # ---- update: a new commit upstream, then Update.ps1 in the clone; a zip copy can't update
    'next' | Set-Content (Join-Path $origin 'NEXT.txt'); $null = & git -C $origin add -A 2>&1; $null = & git @g -C $origin commit -q -m 'Next version' 2>&1
    $head = "$(& git -C $origin rev-parse HEAD)".Trim()
    $outU = & pwsh -NoProfile -File (Join-Path $copyB 'Update.ps1') -NoStart -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1; $codeU = $LASTEXITCODE
    $outU2 = & pwsh -NoProfile -File (Join-Path $copyB 'Update.ps1') -NoStart -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1; $codeU2 = $LASTEXITCODE
    $outZ = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $copyA 'Update.ps1') -NoStart 2>&1; $codeZ = $LASTEXITCODE
    Check 'update: the clone pulls the new commit, says what came in, and keeps its shortcuts, hook and entry' {
        $o = $outU -join "`n"
        $codeU -eq 0 -and "$(& git -C $copyB rev-parse HEAD)".Trim() -eq $head -and (Test-Path (Join-Path $copyB 'NEXT.txt')) -and $o -match 'Updated: \w{7} -> \w{7}' -and $o -match 'Next version' -and
        (Test-TokShortcut (Join-Path $programs 'Tok.lnk') $copyB) -and (Get-ItemProperty -LiteralPath $apps).InstallLocation -eq $copyB
    }
    Check 'update: run again, it is up to date and changes nothing' { $codeU2 -eq 0 -and ($outU2 -join "`n") -match 'up to date' }
    Check 'update: a zip copy says where to get the new version and changes nothing' { $codeZ -eq 1 -and ($outZ -join "`n") -match "can't update itself" }

    # ---- the old zip folder deleted, then uninstall the clone with nowhere to ask: the data stays, everything else goes
    Remove-Item $copyA -Recurse -Force
    $null = New-Item -ItemType Directory -Force $data; '{}' | Set-Content (Join-Path $data 'state.json')
    $outX = '' | & pwsh -NoProfile -File (Join-Path $copyB 'Uninstall.ps1') -ProgramsDir $programs -StartupDir $startup -AppsKey $apps 2>&1; $codeX = $LASTEXITCODE
    Check 'uninstall with no console to ask in: keeps the data folder and says so; shortcuts, entry, hook and skill gone' {
        $codeX -eq 0 -and (Test-Path (Join-Path $data 'state.json')) -and ($outX -join "`n") -match 'Kept: .*Uninstall\.ps1 -Yes' -and -not (Test-Path $apps) -and
        -not (Test-Path (Join-Path $programs 'Tok.lnk')) -and -not (Test-Path (Join-Path $startup 'Tok.lnk')) -and
        (Get-Content (Join-Path $claude 'settings.json') -Raw) -notmatch 'notify\.ps1' -and -not (Test-Path (Join-Path $claude 'skills\tok-private'))
    }
} finally {
    $env:TOK_DATA_DIR, $env:CLAUDE_CONFIG_DIR = $saved
    Remove-Item $appsRoot -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($id in $pids) { $p = Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p) { $p | Stop-Process -Force } }      # only the ones this check started
}

# ---- the real Tok was never touched
Check 'the real Tok: still running if it was, no test lines in its log or inbox, no new files' {
    $newLog = ''
    if (Test-Path $realLog) {
        $fs = [IO.File]::Open($realLog, 'Open', 'Read', 'ReadWrite')
        try { if ($fs.Length -gt $realLogLen) { $null = $fs.Seek($realLogLen, 'Begin'); $newLog = [IO.StreamReader]::new($fs).ReadToEnd() } } finally { $fs.Dispose() }
    }
    $logOk = -not ($pids | Where-Object { $newLog -match "pid $_\b" })
    $inboxNow = if (Test-Path $realInbox) { (Get-Item $realInbox).Length } else { 0 }
    $files = @(Get-ChildItem $realDir -ErrorAction SilentlyContinue | ForEach-Object Name)
    $newFiles = @($files | Where-Object { $_ -notin $realFiles -and $_ -notlike '*.tmp' })
    $running = (Test-TokRunning 'Local\Tok') -eq $realRunning
    if (-not ($logOk -and $inboxNow -eq $realInboxLen -and -not $newFiles -and $running)) {
        Write-Host "      log ok $logOk · inbox $realInboxLen -> $inboxNow · new files '$($newFiles -join ', ')' · running as before $running"
    }
    $logOk -and $inboxNow -eq $realInboxLen -and -not $newFiles -and $running
}
Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "$script:Pass passed, $script:Fail failed"
exit $script:Fail
