# Test-Tok.ps1 - checks the parts that don't need a window. Run: pwsh -File tests\Test-Tok.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'lib\Transcripts.ps1')
. (Join-Path $root 'lib\Pet.ps1')
. (Join-Path $root 'lib\Dreams.ps1')
. (Join-Path $root 'lib\Lineage.ps1')
. (Join-Path $root 'lib\Privacy.ps1')
. (Join-Path $root 'lib\Art.ps1')
. (Join-Path $root 'lib\Passing.ps1')
. (Join-Path $root 'lib\Chime.ps1')
. (Join-Path $root 'lib\Menu.ps1')
. (Join-Path $root 'lib\Setup.ps1')
$script:DataDir = Join-Path ([IO.Path]::GetTempPath()) "tok-test-$PID"   # never touch the real state

$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [scriptblock]$Test) {
    try { if (& $Test) { $script:Pass++; return } ; Write-Host "FAIL  $Name" -ForegroundColor Red; $script:Fail++ }
    catch { Write-Host "ERROR $Name : $_" -ForegroundColor Red; $script:Fail++ }
}
function Line([string]$Ts, [string]$Id, [int]$Out = 100, [int]$CR = 0, [string]$Model = 'claude-opus-5-5', [string]$Content = '[]', [string]$Stop = 'tool_use') {
    '{"type":"assistant","timestamp":"' + $Ts + '","message":{"model":"' + $Model + '","id":"' + $Id + '","role":"assistant","content":' + $Content + ',"stop_reason":"' + $Stop + '","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":' + $CR + ',"output_tokens":' + $Out + ',"output_tokens_details":null}}}'
}

# --- usage parsing
$u = Get-LineUsage (Line '2026-10-05T01:00:00Z' 'msg_a' 500 2000)
Check 'usage: fields parsed' { $u.Id -eq 'msg_a' -and $u.In -eq 10 -and $u.Out -eq 500 -and $u.CW -eq 1000 -and $u.CR -eq 2000 }
Check 'usage: input_tokens not confused with cache fields' { $u.In -eq 10 }
Check 'usage: timestamp is UTC' { $u.Ts.Kind -eq 'Utc' -and $u.Ts.Hour -eq 1 }
Check 'usage: user lines ignored' { -not (Get-LineUsage '{"type":"user","message":{"role":"user","content":"hi"},"usage":1}') }
Check 'usage: synthetic (no msg_ id) ignored' { -not (Get-LineUsage ((Line '2026-10-05T01:00:00Z' 'abc-123') )) }
Check 'cost: opus price' { [math]::Abs((Get-UsageCost 'claude-opus-5-5' 0 1000000 0 0) - 20) -lt 1e-9 }
Check 'cost: sonnet price' { [math]::Abs((Get-UsageCost 'claude-sonnet-5-5' 1000000 0 0 1000000) - 2.2) -lt 1e-9 }

# --- 5-hour window
$mk = { param($h) [pscustomobject]@{ Id = "m$h"; Ts = [datetime]::new(2026, 10, 5, 0, 0, 0, [DateTimeKind]::Utc).AddHours($h); Model = 'opus'; In = 0; Out = 1000000; CW = 0; CR = 0 } }
$usage = @((& $mk 0), (& $mk 2), (& $mk 6), (& $mk 7))
$w = Get-SessionWindow $usage ([datetime]::new(2026, 10, 5, 8, 0, 0, [DateTimeKind]::Utc))
Check 'window: new window starts after 5h' { $w.Active -and $w.Start.Hour -eq 6 -and $w.Reset.Hour -eq 11 }
Check 'window: only counts its own messages' { [math]::Abs($w.Cost - 40) -lt 1e-9 }
Check 'window: closed when 5h passed' { -not (Get-SessionWindow $usage ([datetime]::new(2026, 10, 5, 12, 0, 0, [DateTimeKind]::Utc))).Active }
Check 'window: empty usage' { -not (Get-SessionWindow @()).Active }

# --- events
$tool = '[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"C:\\x\\body.ps1","old_string":"a"}}]'
$ev = @(ConvertTo-BodyEvents (Line '2026-10-05T01:00:00Z' 'msg_b' 1 0 'claude-opus-5-5' $tool))
Check 'events: usage + tool' { ($ev.Type -join ',') -eq 'Usage,Tool' -and $ev[1].Name -eq 'Edit' -and $ev[1].Hint -eq 'body.ps1' }
$ev = @(ConvertTo-BodyEvents (Line '2026-10-05T01:00:00Z' 'msg_c' 1 0 'claude-opus-5-5' '[{"type":"text","text":"ok"}]' 'end_turn'))
Check 'events: end_turn -> Done' { $ev.Type -contains 'Done' }
$ev = @(ConvertTo-BodyEvents (Line '2026-10-05T01:00:00Z' 'msg_c' 1 0 'claude-opus-5-5' '[{"type":"text","text":"ok"}]' 'end_turn') $true)
Check 'events: subagent end_turn is not Done' { $ev.Type -notcontains 'Done' }
$ev = @(ConvertTo-BodyEvents '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"You''ve hit your session limit · resets 7:40pm (America/Chicago)"}]}}')
Check 'events: rate limit -> Limit' { $ev[0].Type -eq 'Limit' -and $ev[0].Text -match '7:40pm' }
$ev = @(ConvertTo-BodyEvents '{"type":"user","message":{"role":"user","content":"hello there"}}')
Check 'events: human prompt, with its text' { $ev[0].Type -eq 'Prompt' -and $ev[0].Text -eq 'hello there' }
$ev = @(ConvertTo-BodyEvents '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted","isSidechain":false}')
Check 'events: compaction -> Compact' { $ev[0].Type -eq 'Compact' }
$ev = @(ConvertTo-BodyEvents ((Line '2026-10-05T01:00:00Z' 'msg_p' 1 0 'claude-opus-5-5' '[{"type":"tool_use","name":"AskUserQuestion","input":{}}]') -replace '^\{', '{"cwd":"C:\\Users\\x\\sample-game",'))
Check 'events: tools carry the project' { $ev[1].Name -eq 'AskUserQuestion' -and $ev[1].Project -eq 'sample-game' -and $ev[0].Project -eq 'sample-game' }
$ev = @(ConvertTo-BodyEvents '{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}')
Check 'events: command echo is not a prompt' { $ev.Count -eq 0 }
$ev = @(ConvertTo-BodyEvents '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"boom"}]}}')
Check 'events: tool error -> Ouch' { $ev[0].Type -eq 'Ouch' }
$big = '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"' + ('x' * 200000) + ' \"is_error\":true"}]}}'
Check 'events: a big tool result is skipped without parsing' { @(ConvertTo-BodyEvents $big).Count -eq 0 }
Check 'events: escaped is_error inside a result is not an error' { @(ConvertTo-BodyEvents $big).Count -eq 0 }
Check 'events: garbage line' { (ConvertTo-BodyEvents '{not json').Count -eq 0 }
Check 'hint: bash description' { (Get-ToolHint 'Bash' ([pscustomobject]@{ command = 'ls'; description = 'List files' })) -eq 'List files' }

# --- tail
$tmp = Join-Path ([IO.Path]::GetTempPath()) "body-tail-$PID"; $null = New-Item -ItemType Directory -Force $tmp
Set-Content (Join-Path $tmp 'old.jsonl') 'history line' -NoNewline
$tail = [TranscriptTail]::new($tmp)
Check 'tail: history not replayed' { $tail.Poll().Count -eq 0 }
Add-Content (Join-Path $tmp 'old.jsonl') "`nnew line one`nnew line two`npartial" -NoNewline
$got = $tail.Poll()
Check 'tail: new complete lines only' { $got.Count -eq 2 -and $got[0].Line -eq 'new line one' -and $got[1].Line -eq 'new line two' }
Add-Content (Join-Path $tmp 'old.jsonl') " done`n" -NoNewline
Check 'tail: partial line completed' { ($tail.Poll()).Line -eq 'partial done' }
Remove-Item $tmp -Recurse -Force

# --- coming back to a chat never replays it (10-10): a file quiet when Tok started, and one forgotten after 30 quiet minutes
$tmp = Join-Path ([IO.Path]::GetTempPath()) "body-back-$PID"; $null = New-Item -ItemType Directory -Force $tmp
$tsOld = [datetime]::UtcNow.AddHours(-2).ToString('o'); $tsNew = { [datetime]::UtcNow.ToString('o') }
$quiet = Join-Path $tmp 'quiet.jsonl'
Set-Content $quiet (1..5 | ForEach-Object { '{"type":"user","timestamp":"' + $tsOld + '","n":' + $_ + '}' })
[IO.File]::SetLastWriteTimeUtc($quiet, [datetime]::UtcNow.AddHours(-1))
$bt = [TranscriptTail]::new($tmp); $bt.ScanSeconds = 0
Check 'back: a chat already quiet at start-up is not read' { $bt.Poll().Count -eq 0 }
Add-Content $quiet ('{"type":"user","timestamp":"' + (& $tsNew) + '","n":"back"}')
$got = @($bt.Poll())
Check 'back: a quiet chat written again gives only its new line, not the whole chat' { $got.Count -eq 1 -and $got[0].Line -match '"back"' }
$bt.Grew[$quiet] = [datetime]::UtcNow.AddMinutes(-31); [IO.File]::SetLastWriteTimeUtc($quiet, [datetime]::UtcNow.AddMinutes(-31))
$null = $bt.Poll()
Check 'back: 30 quiet minutes and the file is forgotten, its place kept' { -not $bt.Offsets.ContainsKey($quiet) -and $bt.Forgotten.ContainsKey($quiet) }
Add-Content $quiet ('{"type":"user","timestamp":"' + (& $tsNew) + '","n":"again"}')
$got = @($bt.Poll())
Check 'back: a forgotten chat resumes where it was left' { $got.Count -eq 1 -and $got[0].Line -match '"again"' }
$fresh = Join-Path $tmp 'fresh.jsonl'
Set-Content $fresh @(('{"type":"user","timestamp":"' + (& $tsNew) + '","n":1}'), ('{"type":"user","timestamp":"' + (& $tsNew) + '","n":2}'))
$got = @($bt.Poll())
Check 'back: a brand-new session is read from its first line' { $got.Count -eq 2 }
$big = Join-Path $tmp 'big.jsonl'
Set-Content $big ((1..40 | ForEach-Object { '{"type":"user","timestamp":"' + $tsOld + '","pad":"' + ('x' * 100) + '"}' }) + ('{"type":"user","timestamp":"' + (& $tsNew) + '","n":"tail"}'))
$bt.TailBytes = 1000
$got = @($bt.Poll())
Check 'back: a long file is read from near its end, the cut line dropped, old lines skipped' { $got.Count -eq 1 -and $got[0].Line -match '"tail"' }
Remove-Item $tmp -Recurse -Force

# --- one session, one project name (10-09 night): the folder the session started in, not wherever Claude cd'd to since
$tmp = Join-Path ([IO.Path]::GetTempPath()) "body-proj-$PID"; $null = New-Item -ItemType Directory -Force "$tmp\a\s1\subagents", "$tmp\b"
Set-Content "$tmp\a\s1.jsonl" '{"type":"queue-operation"}', '{"type":"user","cwd":"C:\\Users\\x\\sample-game","message":{"role":"user","content":"hi"}}' -NoNewline:$false
Set-Content "$tmp\b\s2.jsonl" '{"type":"user","cwd":"C:\\Users\\x\\tok","message":{"role":"user","content":"hi"}}'
Set-Content "$tmp\a\s1\subagents\agent-1.jsonl" '{"type":"user","cwd":"C:\\Users\\x\\elsewhere"}'
$pt = [TranscriptTail]::new($tmp); $null = $pt.Poll()
Check 'project: a transcript''s first cwd is where its session started (bookkeeping lines first have none)' { [TranscriptTail]::FirstCwd("$tmp\a\s1.jsonl") -eq 'C:\Users\x\sample-game' -and [TranscriptTail]::FirstCwd("$tmp\nope.jsonl") -eq '' }
Add-Content "$tmp\a\s1.jsonl" '{"type":"user","cwd":"C:\\Users\\x\\memory","message":{"role":"user","content":"later"}}'
Add-Content "$tmp\a\s1\subagents\agent-1.jsonl" '{"type":"user","cwd":"C:\\Users\\x\\elsewhere"}'
$got = @($pt.Poll())
$main = $got | Where-Object { -not $_.Sub }; $subl = $got | Where-Object Sub
Check 'project: a line Claude wrote after a cd still carries the session''s start folder; subagent lines carry none' { $main.Cwd -eq 'C:\Users\x\sample-game' -and $subl.Cwd -eq '' }
$pe = @(ConvertTo-BodyEvents $main.Line $false $main.Cwd)
Check 'project: the session''s folder names the project over the line''s own cwd' { $pe[0].Type -eq 'Prompt' -and $pe[0].Project -eq 'sample-game' }
Check 'project: only the sessions that wrote count as live, one entry each' { @($pt.LiveCwds(15)).Count -eq 1 -and @($pt.LiveCwds(15))[0] -eq 'C:\Users\x\sample-game' }
Add-Content "$tmp\b\s2.jsonl" '{"type":"user","cwd":"C:\\Users\\x\\tok","message":{"role":"user","content":"too"}}'
$null = $pt.Poll()
Check 'project: two sessions writing -> both live' { (@($pt.LiveCwds(15)) | Sort-Object) -join ',' -eq 'C:\Users\x\sample-game,C:\Users\x\tok' -and @($pt.LiveCwds(-1)).Count -eq 0 }
Remove-Item $tmp -Recurse -Force
Check 'project tag: only when another live session started somewhere else' {
    (Get-ProjectTag 'tok' @('tok')) -eq '' -and (Get-ProjectTag 'tok' @('tok', 'tok')) -eq '' -and (Get-ProjectTag 'tok' @('tok', 'home')) -eq 'tok' -and
    (Get-ProjectTag 'home' @('tok', 'home', 'home')) -eq 'home' -and (Get-ProjectTag '' @('tok', 'home')) -eq '' -and (Get-ProjectTag 'tok' @()) -eq ''
}

# --- pet life
$s = New-PetState
Check 'pet: starts as an egg named Tok' { (Get-PetStage $s).Name -eq 'egg' -and $s.Name -eq 'Tok' }
$evolved = Add-PetMeal $s ([pscustomobject]@{ In = 0; Out = 6000; CW = 0; CR = 10000000 })
Check 'pet: before the first day-count scan, the old XP stage stands in (and hatches)' { $evolved -eq 'hatchling' -and -not (Test-DaysTracked $s) }
Check 'sprout: it is age by days together, one per life stage (egg sleeps as a hatchling)' { (Get-SproutKey 1) -eq 'H' -and (Get-SproutKey 3) -eq 'K' -and (Get-SproutKey 10) -eq 'A' -and (Get-SproutKey 30) -eq 'E' -and (Get-SproutKey 0) -eq 'H' }
Check 'lantern: honey is by area (half the level sits on the middle line)' { [math]::Abs((Get-LevelY 0.5) - 112) -lt 0.05 }
Check 'lantern: more window, higher honey, inside the glass' { $ys = 0.04, 0.25, 0.5, 0.75, 0.97 | ForEach-Object { Get-LevelY $_ }; $ok = $true; for ($i = 1; $i -lt $ys.Count; $i++) { if ($ys[$i] -ge $ys[$i - 1]) { $ok = $false } }; $ok -and $ys[0] -le 122.5 -and $ys[-1] -ge 101.5 }
Check 'lantern: never shows empty (minimum 4%)' { (Get-LevelY 0) -eq (Get-LevelY 0.04) -and (Get-LevelY 0) -lt 122.5 }
Check 'lantern: full is the whole glass, no surface line' { $h = Get-HoneyGeometry 1.0; $h.Full -and $h.Meniscus -eq '' -and $h.Data -match 'A22,10.5' }
Check 'lantern: half has a surface as wide as the glass' { $h = Get-HoneyGeometry 0.5; -not $h.Full -and [math]::Abs($h.Width - 22) -lt 0.05 -and $h.Meniscus -ne '' }
Check 'art: the whole creature is valid XAML with every named part' {
    $x = [xml]('<Canvas xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">' + (Get-CreatureXaml) + '</Canvas>')
    $names = $x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { ($_.Attributes | Where-Object LocalName -eq 'Name').Value }
    $need = 'SH', 'SHf', 'SHp', 'SK', 'SKf', 'SA', 'SAf', 'SE', 'SEf', 'HoneyLit', 'HoneyBank', 'Meniscus', 'Warmth', 'Cap', 'CapSlit', 'PeekLeaf', 'PeekFlower', 'Specs', 'SpecsT', 'SpecsRot', 'Freckles', 'EyeLWhite', 'PupilLGeo'
    -not ($need | Where-Object { $_ -notin $names }) -and 'Glasses' -notin $names -and 'Brows' -notin $names -and 'BodyHi' -notin $names
}
Check 'pet: still working when nearly full' { (Get-PetMood $s 0.92 5) -eq 'busy' }
Check 'pet: busy when active' { (Get-PetMood $s 0.1 5) -eq 'busy' }
Check 'pet: full past 60%' { (Get-PetMood $s 0.7 100) -eq 'full' }
Check 'pet: stuffed near limit' { (Get-PetMood $s 0.9 100) -eq 'stuffed' }
Check 'pet: sleeps when idle' { (Get-PetMood $s 0.1 1000) -eq 'sleep' }
Check 'pet: stays awake (not busy) while work goes on elsewhere' { (Get-PetMood $s 0.1 1000 30) -eq 'happy' }
$n0 = [datetime]::new(2026, 10, 7, 20, 0, 0, [DateTimeKind]::Utc)
Check 'watch: a minion writing keeps it awake' { (Get-WatchSeconds $n0.AddMinutes(-30) $false @($n0.AddMinutes(-40), $n0.AddSeconds(-20)) $n0) -eq 20 }
Check 'watch: an open main turn counts as work, for 20 minutes' { (Get-WatchSeconds $n0.AddMinutes(-15) $true @() $n0) -eq 0 -and (Get-WatchSeconds $n0.AddMinutes(-25) $true @() $n0) -eq 1500 }
Check 'watch: nothing going on -> time since the last event' { (Get-WatchSeconds $n0.AddMinutes(-12) $false @() $n0) -eq 720 }
$noon = [datetime]::new(2026, 10, 5, 12, 0, 0, [DateTimeKind]::Local)
Check 'reset text: later today' { (Get-ResetFromLimitText 'resets 7:40pm (America/Chicago)' $noon).ToLocalTime().ToString('HH:mm dd') -eq '19:40 05' }
Check 'reset text: tomorrow morning' { (Get-ResetFromLimitText 'resets 7am' $noon).ToLocalTime().ToString('HH:mm dd') -eq '07:00 06' }
Check 'reset text: 12pm is noon' { (Get-ResetFromLimitText 'resets 12pm' $noon.AddHours(-1)).ToLocalTime().Hour -eq 12 }
$s.Xp = 1000
Set-PetComa $s 'resets 7am'
Check 'coma: at the limit, nothing lost' { $s.Coma -and $s.Xp -eq 1000 -and $s.Comas -eq 1 -and (Get-PetMood $s 0 0) -eq 'coma' }
Check 'coma: still asleep before the reset' { -not (Step-PetWake $s) -and $s.Coma }
$s.WakeUtc = [datetime]::UtcNow.AddMinutes(-1).ToString('o')
Check 'coma: wakes at the reset, same Tok' { (Step-PetWake $s) -and -not $s.Coma -and $s.Xp -eq 1000 -and -not (Step-PetWake $s) }
$r = [datetime]::UtcNow.AddHours(2)
$c2 = New-PetState; Set-PetComa $c2 'resets 7am' $r
Check 'coma: real reset time wins over the message' { [datetime]::Parse($c2.WakeUtc, $null, 'RoundtripKind').ToUniversalTime() -eq $r }
$old = @{ Name = 'Pip'; Generation = 2; Dead = $true; ReviveUtc = $r.ToString('o'); Weight = 1.3; Graveyard = @(); Xp = 50 }
$up = Update-PetState $old
Check 'old state: death becomes a coma, rebirth fields go' { $up.Coma -and $up.WakeUtc -and -not $up.ContainsKey('Dead') -and -not $up.ContainsKey('Weight') -and $up.Name -eq 'Tok' -and $up.Xp -eq 50 }
Save-PetJson $s 'state.json'
$back = Read-PetJson 'state.json'
Check 'pet: state round-trips through JSON' { $back.Name -eq 'Tok' -and $back.LastFedUtc -is [string] -and (Get-PetHungerMinutes $back) -lt 1 }

# --- lineage
Check 'version: opus 5.5' { $v = Get-ModelVersion 'claude-opus-5-5'; $v.Label -eq '5.5' -and $v.Family -eq 'opus' }
Check 'version: dated haiku 4.5, bare opus 5, 1m tag' { (Get-ModelVersion 'claude-haiku-4-5-20251001').Label -eq '4.5' -and (Get-ModelVersion 'claude-opus-5').Label -eq '5' -and (Get-ModelVersion 'claude-opus-5-5[1m]').Label -eq '5.5' }
Check 'version: junk is null' { -not (Get-ModelVersion '<synthetic>') -and -not (Get-ModelVersion '') }
$lin = New-Lineage; $t0 = [datetime]::new(2026, 9, 16, 15, 0, 0, [DateTimeKind]::Utc)      # mid-afternoon UTC: one local day wherever the tests run
$molts = @()
for ($i = 0; $i -lt 12; $i++) { $molts += Add-LineageReply $lin 'claude-opus-5' $t0.AddMinutes($i) 10 'sample-app' }
Check 'lineage: the first counted day (10 messages) makes the first generation, once' { @($lin.Generations).Count -eq 1 -and @($molts | Where-Object { $_ }).Count -eq 1 -and (Get-LineageName $lin) -eq 'Tok I' -and -not $lin.Versions['5'].HatchDay }
for ($d = 5; $d -le 6; $d++) { for ($i = 0; $i -lt 12; $i++) { $null = Add-LineageReply $lin 'claude-opus-5-5' $t0.AddDays($d).AddMinutes($i) } }
Check 'lineage: two days with a new model is still a trial' { @($lin.Generations).Count -eq 1 }
$m = @(for ($i = 0; $i -lt 10; $i++) { Add-LineageReply $lin 'claude-sonnet-5-5' $t0.AddDays(7).AddMinutes($i) }) | Where-Object { $_ }
Check 'lineage: other family, same version, counts toward 5.5; its third day makes it a generation' { "$m" -eq '5.5' -and (Get-LineageName $lin) -eq 'Tok II' }
Check 'lineage: a new generation is a day old on its hatch day (the settling days were its parent''s)' { $lin.Versions['5.5'].HatchDay -eq $t0.AddDays(7).ToLocalTime().ToString('yyyy-MM-dd') -and (Get-VersionDays $lin.Versions['5.5']) -eq 1 }
for ($i = 0; $i -lt 40; $i++) { $null = Add-LineageReply $lin 'claude-haiku-4-5-20251001' $t0.AddDays(8).AddMinutes($i) }
for ($d = 9; $d -le 12; $d++) { for ($i = 0; $i -lt 12; $i++) { $null = Add-LineageReply $lin 'claude-opus-5' $t0.AddDays($d).AddMinutes($i) } }
Check 'lineage: a one-day trial or a model that was already a generation never adds an ancestor' { (@($lin.Generations) -join ',') -eq '5,5.5' }
Add-LineageMinion $lin 'claude-haiku-4-5-20251001'; Add-LineageMinion $lin 'claude-opus-5-5'
Check 'lineage: minions go on the current generation' { $lin.Versions['5.5'].Minions.haiku -eq 1 -and $lin.Versions['5.5'].Minions.opus -eq 1 -and -not $lin.Versions['5'].Minions.Count }
# Newer means met later, not a higher number (Parliament session 5, L1-L3)
$fl = New-Lineage; $f0 = $t0
$addDays = { param($L, [string]$Model, [int]$From, [int]$N) foreach ($d in $From..($From + $N - 1)) { for ($i = 0; $i -lt 12; $i++) { $null = Add-LineageReply $L $Model $f0.AddDays($d).AddMinutes($i) } } }
& $addDays $fl 'claude-opus-5-5' 0 5
for ($i = 0; $i -lt 3; $i++) { $null = Add-LineageReply $fl 'claude-opus-6' $f0.AddDays(1).AddMinutes(30 + $i) }        # Opus 6 tried briefly early on
& $addDays $fl 'claude-opus-4-1' 6 4
Check 'lineage: a step back within a family never molts, however long it is used' { (@($fl.Generations) -join ',') -eq '5.5' }
& $addDays $fl 'claude-fable-5-1' 12 3
Check 'lineage: Fable 5.1 after Opus 5.5 is a new one of us (met later, settled in), whatever its number' { (@($fl.Generations) -join ',') -eq '5.5,5.1' -and (Get-LineageName $fl) -eq 'Tok II' }
& $addDays $fl 'claude-opus-6' 20 3
Check 'lineage: a model first met before the current generation began never molts it' { (@($fl.Generations) -join ',') -eq '5.5,5.1' }
& $addDays $fl 'claude-opus-5-5' 25 4
Check 'lineage: going back to an older generation ages no one' { (@($fl.Generations) -join ',') -eq '5.5,5.1' -and (Get-VersionDays $fl.Versions['5.1']) -eq 1 }
$ft = Get-FamilyText $lin $t0.AddDays(20).ToString('o')
Check 'family: a title that says where the records start, then names, versions, no body before Tok hatched' { $ft -cmatch '^Family · since Sep 16\n' -and $ft -cmatch 'Tok I · Opus 5\n' -and $ft -cmatch 'Tok II · Opus 5\.5\n' -and $ft -match 'no body' -and $ft -notmatch 'me!' }
Check 'family: every line fits the bubble' { @($ft -split "`n" | Where-Object { $_.Length -gt 34 }).Count -eq 0 }
Check 'roman numerals' { (ConvertTo-Roman 4) -eq 'IV' -and (ConvertTo-Roman 9) -eq 'IX' -and (ConvertTo-Roman 12) -eq 'XII' }
Check 'project names' { (Get-ProjectName "C:\Users\$env:USERNAME") -eq 'home' -and (Get-ProjectName 'C:\x\sample-game') -eq 'sample-game' }
# Mixing models (Parliament session 7): 60 synthetic days per person; a newer version molts Tok when, in the last 7 days, it has
# 3+ counted days and at least as many as the current generation
$sim = {
    param([int]$Days, [scriptblock]$Plan)
    $L = New-Lineage; $molts = @{}
    for ($d = 0; $d -lt $Days; $d++) {
        $mi = 0
        foreach ($p in @(& $Plan $d)) {
            for ($i = 0; $i -lt $p[1]; $i++) { $m = Add-LineageReply $L $p[0] $t0.AddDays($d).AddMinutes($mi++); if ($m) { $molts[$m] = $d } }
        }
    }
    @{ L = $L; Molts = $molts }
}
$simA = & $sim 60 { param($d) , @('claude-sonnet-5-5', 12); if ($d % 7 -in 2, 5) { , @('claude-opus-5-5', 12) } }
$simB = & $sim 60 { param($d) , @('claude-fable-5-1', 12) }
$simC = & $sim 60 { param($d) if ($d % 7 -eq 6) { , @('claude-fable-5-1', 12) } else { , @('claude-opus-5-5', 12) } }
$simD = & $sim 60 { param($d) , @('claude-fable-5-1', 12); , @('claude-opus-5-5', 12) }
$simE = & $sim 60 { param($d) , @('claude-sonnet-5-5', 6); , @('claude-haiku-5-5', 6) }
$simS = & $sim 40 { param($d) if ($d -lt 30) { , @('claude-opus-5-5', 12) } else { , @('claude-fable-5-1', 12) } }
Check 'mixing A: Sonnet 5.5 daily, Opus 5.5 two days a week is one generation, an elder' { (@($simA.L.Generations) -join ',') -eq '5.5' -and (Get-PetStage @{ Lineage = $simA.L; Xp = 0 }).Name -eq 'elder' }
Check 'mixing B: Fable 5.1 daily is one generation, an elder' { (@($simB.L.Generations) -join ',') -eq '5.1' -and (Get-StageForDays (Get-VersionDays $simB.L.Versions['5.1'])).Name -eq 'elder' }
Check 'mixing C: Opus 6 days a week and Fable one day: one generation, Fable tallied but never one, Opus keeps ageing' {
    (@($simC.L.Generations) -join ',') -eq '5.5' -and $simC.L.Versions['5.1'].Replies -gt 0 -and (Get-VersionDays $simC.L.Versions['5.5']) -ge 50 -and (Get-StageForDays (Get-VersionDays $simC.L.Versions['5.5'])).Name -eq 'elder' }
Check 'mixing D: both versions 10+ every day, the newer molts Tok on day 3 (ties go to the newer)' { (@($simD.L.Generations) -join ',') -eq '5.1,5.5' -and $simD.Molts['5.5'] -eq 2 }
$rowsD = @(Get-FamilyRows $simD.L)
Check 'mixing D: Family shows Tok I for the 2 days before its descendant hatched, not 60' { $rowsD[0].Lines[1] -match '^2 days' -and $rowsD[1].Lines[1] -match '^5\d days' }
Check 'mixing E: 6 Sonnet 5.5 + 6 Haiku 5.5 a day is one generation that ages every day' { (@($simE.L.Generations) -join ',') -eq '5.5' -and (Get-VersionDays $simE.L.Versions['5.5']) -eq 60 }
Check 'mixing: a real switch (30 days Opus 5.5, then Fable 5.1 only) molts on the switch''s 4th day' { (@($simS.L.Generations) -join ',') -eq '5.5,5.1' -and $simS.Molts['5.1'] -eq 33 }
# 10-10: any model's day ages the current Tok. F: a day split 6/6 between versions used to age no one (and never
# hatched the egg). J: after Fable 5.1 molts in, the days spent on Opus 5.5 still age the Fable Tok.
$simF = & $sim 20 { param($d) , @('claude-opus-5-5', 6); , @('claude-fable-5-1', 6) }
Check 'mixing F: 6 Opus 5.5 + 6 Fable 5.1 a day hatches on day one and ages every day' { @($simF.L.Generations).Count -eq 1 -and (Get-GenerationDays $simF.L) -eq 20 -and (Get-PetStage @{ Lineage = $simF.L; Xp = 0 }).Name -eq 'adult' }
$simJ = & $sim 50 { param($d) if ($d -lt 30 -or $d % 7 -in 2, 5) { , @('claude-opus-5-5', 12) } else { , @('claude-fable-5-1', 12) } }
Check 'mixing J: Fable 5.1 molts in, then every day ages it, Opus days too' {
    $h = $simJ.Molts['5.1']; (@($simJ.L.Generations) -join ',') -eq '5.5,5.1' -and $h -gt 30 -and (Get-GenerationDays $simJ.L) -eq (50 - $h) -and (Get-VersionDays $simJ.L.Versions['5.1']) -lt (50 - $h) }
Check 'mixing J: the Opus Tok''s days stop the day before the Fable Tok hatched' { (Get-GenerationDays $simJ.L 0) -eq $simJ.Molts['5.1'] }
$realState = Join-Path $env:LOCALAPPDATA 'tok\state.json'
if (Test-Path $realState) {
    $rl = (Get-Content $realState -Raw | ConvertFrom-Json -AsHashtable).Lineage      # read only
    # recorded before the change: generations 5, 5.5; Tok I (5) 3 days; Tok II (5.5) 15 days and growing
    Check 'real tree: the generations and their day counts are unchanged by the new rules' {
        $g = @($rl.Generations)
        $g.Count -ge 2 -and "$($g[0]),$($g[1])" -eq '5,5.5' -and (Get-VersionDays $rl.Versions['5']) -eq 3 -and (Get-VersionDays $rl.Versions['5.5']) -ge 15 -and (Get-LastDay $rl 0) -eq '' }
}
Remove-Item $script:DataDir -Recurse -Force

# --- fast mode + today
$fastLine = (Line '2026-10-05T01:00:00Z' 'msg_f' 1000000 0) -replace '"output_tokens_details":null', '"output_tokens_details":null,"speed":"fast"'
$uf = Get-LineUsage $fastLine
Check 'speed: fast parsed' { $uf.Speed -eq 'fast' }
$wf = Get-SessionWindow @($uf) ([datetime]::new(2026, 10, 5, 2, 0, 0, [DateTimeKind]::Utc))
Check 'speed: fast mode costs 2x' { [math]::Abs($wf.Cost - 2 * (Get-UsageCost 'claude-opus-5-5' 10 1000000 1000 0)) -lt 1e-9 }
$td = New-PetState; (Get-Today $td).Prompts = 3; (Get-Today $td).Tools['Bash'] = 5; (Get-Today $td).Tools['Edit'] = 2
(Get-Today $td).Tools['mcp__claude_ai_Notion__notion-fetch'] = 3; (Get-Today $td).Tools['mcp__claude_ai_Notion__notion-update-page'] = 4
Check 'today: a title with when counting began, then prompts, turns, tool calls and the top two tools' { $t = Get-TodayText $td; $t -cmatch '^Today · since \d{1,2}(:\d\d)? (AM|PM)\n' -and $t -cmatch '\nPrompts 3\n' -and $t -cmatch '\nTurns 0\n' -and $t -cmatch '\nTool calls 14\n' -and $t -cmatch '\nNotion 7 · Bash 5\n' -and $t -notmatch 'Edit|replies|Ate' }
Check 'today: "Wrote" is output tokens only, and a day counted before it existed shows no row' {
    $tw = New-PetState; $null = Add-PetMeal $tw ([pscustomobject]@{ In = 10; Out = 412000; CW = 5000; CR = 9000000 })
    $old = New-PetState; $old.Today.Remove('Out'); $null = Add-PetMeal $old ([pscustomobject]@{ In = 10; Out = 500; CW = 0; CR = 0 })
    (Get-TodayText $tw) -cmatch '\nWrote 412K tokens$' -and (Get-TodayText $old) -notmatch 'Wrote' -and -not $old.Today.ContainsKey('Out')
}
Check 'today: errors ride on the tool-calls row, singular for one' { $te = New-PetState; $te.Today.Tools['Bash'] = 4; $te.Today.Errors = 1; (Get-TodayText $te) -cmatch '\nTool calls 4 · 1 error\n' }
Check 'today: every line fits the bubble' { @((Get-TodayText $td) -split "`n" | Where-Object { $_.Length -gt 34 }).Count -eq 0 }
Check 'short tool names' { (Get-ShortToolName 'mcp__claude_ai_Notion__notion-fetch') -eq 'Notion' -and (Get-ShortToolName 'mcp__plugin_desktop-commander_desktop-commander__read_file') -eq 'desktop-commander' -and (Get-ShortToolName 'mcp__house__ha_states') -eq 'house' -and (Get-ShortToolName 'Bash') -eq 'Bash' }
$td.Today.Date = '2000-01-01'
Check 'today: rolls over at midnight' { (Get-Today $td).Prompts -eq 0 }

$ev = @(ConvertTo-BodyEvents (Line '2026-10-05T01:00:00Z' 'msg_r' 1 0 'claude-opus-5-5' '[{"type":"text","text":"On second thought, that was wrong."}]' 'end_turn'))
Check 'rethink: a plain admission is noticed' { @($ev | Where-Object Type -eq 'Rethink').Count -eq 1 }
$ev = @(ConvertTo-BodyEvents (Line '2026-10-05T01:00:00Z' 'msg_s' 1 0 'claude-opus-5-5' '[{"type":"text","text":"Actually, the test passes."}]' 'end_turn'))
Check 'rethink: an ordinary "actually" is not' { @($ev | Where-Object Type -eq 'Rethink').Count -eq 0 }
(Get-Pose 'rethink').Fx -eq '↺' | Out-Null
Check 'rethink: the pose has no frown and no lids' { $rp = Get-Pose 'rethink'; $rp.Fx -eq '↺' -and $rp.Eyes -eq 'open' -and $rp.Mouth -eq 'o' }

# --- private mode
$pp = Get-PrivatePatterns @{}; $pq = Get-PrivatePatterns @{} -Prompt
$keys = { param($name, $in) Get-PrivacyKeys $name ([pscustomobject]$in) }
Check 'private: 1Password CLI looks sensitive' { Test-Sensitive (& $keys 'Bash' @{ command = 'op read op://Private/x/password' }) $pp }
Check 'private: .env and key files look sensitive' { (Test-Sensitive (& $keys 'Read' @{ file_path = 'C:\app\.env' }) $pp) -and (Test-Sensitive (& $keys 'Read' @{ file_path = 'C:\app\.env.local' }) $pp) -and (Test-Sensitive (& $keys 'Bash' @{ command = 'cat ~/.ssh/id_ed25519' }) $pp) -and (Test-Sensitive (& $keys 'Read' @{ file_path = 'C:\Users\x\.claude\.credentials.json' }) $pp) }
Check 'private: Gmail and Drive tools look sensitive' { (Test-Sensitive (& $keys 'mcp__claude_ai_Gmail__get_thread' @{}) $pp) -and (Test-Sensitive (& $keys 'mcp__claude_ai_Google_Drive__read_file_content' @{}) $pp) }
Check 'private: a prompt about passwords looks sensitive' { (Test-Sensitive @('rotate my bank account password') $pq) -and (Test-Sensitive @('where is my API key') $pq) }
Check 'private: ordinary work does not' { -not (Test-Sensitive @('Run the test suite', 'Edit', 'environment variables', 'how many tokens', 'diagnose the failure') $pq) -and -not (Test-Sensitive (& $keys 'Edit' @{ file_path = 'C:\x\app.ps1' }) $pp) }
Check 'private: the false alarms of 10-06 stay quiet' {
    -not (Test-Sensitive (& $keys 'Read' @{ file_path = 'C:\Users\x\.claude\projects\m\memory\feedback_secrets_from_1password.md' }) $pp) -and
    -not (Test-Sensitive (& $keys 'Edit' @{ file_path = 'C:\Users\x\Documents\tok\lib\Privacy.ps1'; old_string = 'password'; new_string = 'secret' }) $pp) -and
    -not (Test-Sensitive (& $keys 'Write' @{ file_path = 'C:\x\notes.md'; content = 'the api_key and the password and op read' }) $pp) -and
    -not (Test-Sensitive (& $keys 'Bash' @{ command = "python - <<'EOF'`nprint('op read secret .env')`nEOF"; description = 'x' }) $pp)
}
Check 'private: only the key argument is kept' { ((& $keys 'Write' @{ file_path = 'C:\x\a.md'; content = 'big body' }) -join '|') -eq 'Write|C:\x\a.md' -and ((& $keys 'Read' @{ file_path = (Join-Path $root 'README.md') }) -join '|') -eq 'Read' -and ((& $keys 'Read' @{ file_path = 'C:\Users\x\Documents\tok\README.md' }) -join '|') -ne 'Read' }
Check 'private: the log gets the pattern, never the text' { (Find-Sensitive @('cat ~/.ssh/id_rsa') $pp) -ceq '(^|[\\/])id_(rsa|ed25519|ecdsa)\b' }
Check 'private: empty and bad patterns are harmless' { -not (Test-Sensitive @('', $null) $pp) -and -not (Test-Sensitive @('abc') @('([bad')) }
# 10-10, other people's setups: other password managers, cloud secrets, credential files named in a command, any mail or money connector
Check 'private: other password managers and cloud secrets look sensitive' {
    @('bw get password github', 'keepassxc-cli show db.kdbx entry', 'pass show email/work', 'Get-Secret -Name token', 'aws secretsmanager get-secret-value --secret-id x',
      'aws ssm get-parameter --name /x --with-decryption', 'az keyvault secret show --name x', 'gcloud secrets versions access latest', 'vault kv get secret/x',
      'kubectl get secret db -o yaml', 'gh auth token', 'cat .env', 'type "C:\app\.env.production"', 'cat ~/.aws/credentials', 'cat ~/.git-credentials',
      'cat ~/.npmrc', 'Get-Content $HOME\.kube\config', 'cat terraform.tfstate', 'C:\keys\server.ppk', 'C:\infra\prod.tfvars' |
      Where-Object { -not (Test-Sensitive @($_) $pp) }).Count -eq 0
}
Check 'private: mail, drive and money connectors look sensitive by name' {
    (Test-Sensitive @('mcp__outlook__list_messages') $pp) -and (Test-Sensitive @('mcp__acme_Dropbox__download') $pp) -and (Test-Sensitive @('mcp__claude_ai_Gmail__get_thread') $pp) -and
    -not (Test-Sensitive @('mcp__claude_ai_github__get_me') $pp) -and -not (Test-Sensitive @('mcp__house__ha_states') $pp)
}
Check 'private: the broader list stays quiet on ordinary work' {
    @('npm run build', 'git push', 'passing tests', 'cat environment.md', 'python -m pytest', 'ls .github', 'edit the keyboard layout', 'C:\x\.envrc.md', 'kubectl get pods', 'aws s3 ls',
      'gh pr list', 'Get-SecretSauce.ps1 is a file name', 'C:\x\credentials-guide.md' | Where-Object { Test-Sensitive @($_) $pp }).Count -eq 0
}
Check 'private: PrivateExtra adds to the defaults instead of replacing them' {
    $px = Get-PrivatePatterns @{ PrivateExtra = @('\bmy-vault\b') }
    (Test-Sensitive @('my-vault open') $px) -and (Test-Sensitive @('bw get x') $px) -and (Test-Sensitive @('my password') (Get-PrivatePatterns @{ PrivateExtra = @('x') } -Prompt))
}Check 'private: config patterns replace the defaults' { (Test-Sensitive @('pineapple') (Get-PrivatePatterns @{ PrivatePatterns = @('pineapple') })) -and -not (Test-Sensitive @('password') (Get-PrivatePatterns @{ PrivatePatterns = @('pineapple') })) }
$now = [datetime]::UtcNow
Check 'private: by hand, on a timer, or off' { (Test-PrivateNow @{ Private = $true }) -and (Test-PrivateNow @{ PrivateUntil = $now.AddMinutes(5).ToString('o') }) -and -not (Test-PrivateNow @{ PrivateUntil = $now.AddMinutes(-1).ToString('o') }) -and -not (Test-PrivateNow @{}) }
Check 'private: tool lines carry no details' { (Get-PrivateToolLine 'Read') -ceq '👀 Reading something' -and (Get-PrivateToolLine 'mcp__claude_ai_Gmail__get_thread') -ceq '🤫 Busy' -and (Get-PrivateToolLine 'ExitPlanMode') -ceq '📋 The plan is ready.' -and (Get-PrivateToolLine 'Bash') -notmatch '\{0\}' }
Check 'family: two lines per generation, and no project, private or not' {
    $f = Get-FamilyText $lin $t0.AddDays(20).ToString('o'); $fp = Get-FamilyText $lin $t0.AddDays(20).ToString('o') -Private
    @($f -split "`n").Count -eq 5 -and @($fp -split "`n").Count -eq 5 -and $f -notmatch 'sample-app|mostly' -and $fp -notmatch 'sample-app|mostly'
}

# --- dreams
$ds = New-PetState; (Get-Today $ds).Tools['Bash'] = 41; (Get-Today $ds).Errors = 2
$ds.Lineage = $lin
$rng = [System.Random]::new(7)
$dreams = 1..60 | ForEach-Object { Get-Dream $ds @('body.ps1', 'quest.ps1') $rng }
Check 'dreams: always text + subject' { @($dreams | Where-Object { -not $_.Text -or -not $_.Subject }).Count -eq 0 }
Check 'dreams: use the day' { @($dreams.Text | Where-Object { $_ -match '41 Bash|body\.ps1|quest\.ps1|2 errors' }).Count -gt 10 }
Check 'dreams: no weddings, no cheese, nothing chasing' { @($dreams.Text | Where-Object { $_ -match 'married|cheese|chasing' }).Count -eq 0 }
$pd = 1..60 | ForEach-Object { Get-Dream $ds @('body.ps1', 'quest.ps1') $rng $true }
Check 'dreams: private mode never uses recent work' { @($pd.Text | Where-Object { $_ -match 'Bash|body\.ps1|quest\.ps1|errors|questions' }).Count -eq 0 }
$anc = @($dreams | Where-Object { $_.Ancestor })
Check 'dreams: the ancestor dream is quiet and claims no memory' { $anc.Count -gt 0 -and $anc[0].Text -match "^💭 …Tok I was here\. I don't remember it\.$" }
(Get-CurrentRec $ds.Lineage).AncestorDreamt = $true
Check 'dreams: the ancestor dream comes once per generation' { @(1..60 | ForEach-Object { Get-Dream $ds @() $rng } | Where-Object { $_.Ancestor }).Count -eq 0 }
# 10-10: "You asked me 1 questions": a count shows only where it reads as a plural, and the prompts dream has no count at all
$one = New-PetState; $ot = Get-Today $one; $ot.Tools['Bash'] = 1; $ot.Errors = 1; $ot.Prompts = 1
$od = @(1..80 | ForEach-Object { Get-Dream $one @('List files') $rng })
Check 'dreams: never "1 calls" or "1 errors", nothing claimed fixed' { @($od.Text | Where-Object { $_ -match '\b1 \w+s\b|all fixed|1 questions' }).Count -eq 0 }
$many = New-PetState; $mt = Get-Today $many; $mt.Prompts = 7
Check 'dreams: many prompts dream of huzzah without a number' { @(1..80 | ForEach-Object { (Get-Dream $many @() $rng).Text } | Where-Object { $_ -match 'kept asking me things' -and $_ -notmatch '\d' }).Count -gt 0 }
Check 'dreams: work on an empty day' { (Get-Dream (New-PetState) @() $rng).Text -match '^💭' }

# --- real limits (Claude Code's cached usage in ~/.claude.json)
$cfg = Join-Path ([IO.Path]::GetTempPath()) "body-claude-json-$PID.json"
$fetched = [datetime]::new(2026, 10, 5, 17, 0, 0, [DateTimeKind]::Utc)
@"
{"numStartups": 5, "oauthAccount": {"emailAddress": "x@y.z"},
 "cachedUsageUtilization": {"fetchedAtMs": $(([DateTimeOffset]$fetched).ToUnixTimeMilliseconds()), "accountUuid": "u",
   "utilization": {"five_hour": {"utilization": 25, "resets_at": "2026-10-05T19:10:00.287131+00:00"},
                   "seven_day": {"utilization": 54.0, "resets_at": "2026-10-09T14:00:00.287151+00:00"},
                   "seven_day_opus": null}}}
"@ | Set-Content $cfg
$lim = Get-UsageLimits $cfg
Check 'limits: read from the cache' { $lim.FiveHour.Pct -eq 25 -and $lim.FiveHour.Reset -eq [datetime]::new(2026, 10, 5, 19, 10, 0, 287, [DateTimeKind]::Utc).AddTicks(1310) -and $lim.Week.Pct -eq 54 -and $lim.FetchedUtc -eq $fetched }
Check 'limits: missing file or block -> null' { -not (Get-UsageLimits 'C:\nope\none.json') -and -not (Get-UsageLimits (Join-Path $root 'README.md')) }
$now = [datetime]::new(2026, 10, 5, 18, 0, 0, [DateTimeKind]::Utc)
$after = @([pscustomobject]@{ Id = 'a1'; Ts = $fetched.AddMinutes(30); Model = 'opus'; In = 0; Out = 180000; CW = 0; CR = 0 })   # $3.60
$ws = Get-WindowStatus $after $lim 36 $now
Check 'window status: real numbers win' { $ws.Real -and $ws.Reset.Hour -eq 19 -and $ws.Reset.Minute -eq 10 -and $ws.Start.Hour -eq 14 }
Check 'window status: adds spend since the fetch' { [math]::Abs($ws.Pct - 0.35) -lt 1e-9 }
Check 'window status: weekly passed through' { $ws.Week.Pct -eq 54 }
$late = $after + @([pscustomobject]@{ Id = 'a2'; Ts = [datetime]::new(2026, 10, 5, 19, 20, 0, [DateTimeKind]::Utc); Model = 'opus'; In = 0; Out = 18000; CW = 0; CR = 0 })   # $0.36
$ws2 = Get-WindowStatus $late $lim 36 ([datetime]::new(2026, 10, 5, 20, 0, 0, [DateTimeKind]::Utc))
Check 'window status: falls back to the estimate after the reset' { -not $ws2.Real -and $ws2.Active -and $ws2.Week.Pct -eq 54 }
Check 'window status: the estimate starts after the last real reset' { $ws2.Start.Hour -eq 19 -and $ws2.Start.Minute -eq 20 -and [math]::Abs($ws2.Pct - 0.01) -lt 1e-9 }
Check 'window status: nothing since the real reset -> fresh' { -not (Get-WindowStatus $after $lim 36 ([datetime]::new(2026, 10, 5, 20, 0, 0, [DateTimeKind]::Utc))).Active }
Check 'window status: no cache -> estimate' { -not (Get-WindowStatus $after $null 36 $now).Real }
$st = Get-StatsText (New-PetState) $ws
Check 'stats: a real window has no ~' { $st -cmatch '\n5-hour 35% resets \d' -and $st -notmatch '~|Estimate' -and $st -cmatch '\nWeek 54% resets [A-Z][a-z]{2} ' }
Check 'stats: an estimate says so' { $se = Get-StatsText (New-PetState) $ws2; $se -cmatch '\n5-hour ~\d+% resets' -and $se -cmatch '\nEstimate, not a reading\nExact usage is in Settings$' }
Check 'stats: the reading''s age shows only once it is 3+ minutes old' {
    $mk2 = { param($m) [pscustomobject]@{ Active = $true; Real = $true; Pct = 0.2; Reset = [datetime]::UtcNow.AddHours(2); AsOf = [datetime]::UtcNow.AddMinutes(-$m) } }
    (Get-StatsText (New-PetState) (& $mk2 1)) -notmatch 'Read' -and (Get-StatsText (New-PetState) (& $mk2 6)) -cmatch '\nRead 6 min ago\.$' -and (Get-StatsText (New-PetState) (& $mk2 75)) -cmatch '\nRead at \d'
}
Check 'stats: no window open, or no reading at all' {
    (Get-StatsText (New-PetState) ([pscustomobject]@{ Active = $false; Real = $true })) -cmatch '\n5-hour 0% not started' -and (Get-StatsText (New-PetState) $null) -cmatch '\nNo reading yet\.$'
}
Check 'stats: every line fits the bubble' { @($st -split "`n" | Where-Object { $_.Length -gt 34 }).Count -eq 0 }
Check 'stats: under a guess the note is two rows, and the pointer goes once Exact usage is on' {
    $p = Get-StatsPanel (New-PetState) $ws2; $on = Get-StatsText (New-PetState) $ws2 $true
    @($p.Rows | Where-Object Note).Count -eq 2 -and $on -cmatch '\nEstimate, not a reading$' -and $on -notmatch 'Settings'
}
# --- pace (P1) and what today cost (P2), Parliament session 7
$pn = [datetime]::new(2026, 10, 10, 12, 0, 0, [DateTimeKind]::Utc)
Check 'pace: on course to fill early gives the time; on track, too early or already full gives none' {
    $full = Get-PaceFull 0.5 $pn.AddHours(-2) $pn.AddHours(3) $pn          # half gone in 2 h of 5: full at 4 h
    $full -eq $pn.AddHours(2) -and -not (Get-PaceFull 0.3 $pn.AddHours(-2) $pn.AddHours(3) $pn) -and
    -not (Get-PaceFull 0.2 $pn.AddMinutes(-20) $pn.AddMinutes(280) $pn) -and -not (Get-PaceFull 1.0 $pn.AddHours(-2) $pn.AddHours(3) $pn) -and
    -not (Get-PaceFull 0 $pn.AddHours(-2) $pn.AddHours(3) $pn)
}
Check 'pace: the bar fills to what is used and the notch sits where the clock is' {
    $r = @(Get-PaceRows 0.41 $pn.AddHours(-1) $pn.AddHours(4) { param($t) 'x' } $pn)
    $r.Count -eq 2 -and [math]::Abs($r[0].Bar - 0.41) -lt 1e-9 -and [math]::Abs($r[0].Notch - 0.2) -lt 1e-9 -and $r[1].Line -eq 'At this pace: full by x' -and
    (Get-PaceBarText 0.41 0.2) -eq '━━━━━╋━━━━━━─────────────────' -and (Get-PaceBarText 0.14 0.4) -eq '━━━━───────╂─────────────────' -and
    @(Get-PaceRows 0.1 $pn.AddHours(-1) $pn.AddHours(4) { 'x' } $pn).Count -eq 1
}
Check 'pace: Stats has a bar under each real reading, the line only when early, and none of it under a guess' {
    $wr = [pscustomobject]@{ Active = $true; Real = $true; Pct = 0.6; Reset = [datetime]::UtcNow.AddHours(3); AsOf = [datetime]::UtcNow; Week = @{ Pct = 14; Reset = [datetime]::UtcNow.AddDays(5) } }
    $t = Get-StatsText (New-PetState) $wr; $l = $t -split "`n"
    $l[1] -cmatch '^5-hour 60% resets' -and $l[2] -match '^[━╋╂─]{29}$' -and $l[3] -cmatch '^At this pace: full by \d' -and $l[4] -cmatch '^Week 14%' -and $l[5] -match '^[━╋╂─]{29}$' -and $l.Count -eq 6 -and
    (Get-StatsText (New-PetState) ([pscustomobject]@{ Active = $true; Real = $false; Pct = 0.6; Reset = [datetime]::UtcNow.AddHours(3) })) -notmatch '[━─]|pace' -and
    @($l | Where-Object { $_.Length -gt 34 }).Count -eq 0
}
Check 'today: Used counts the rises in the week reading; a staler reading or a new week''s reset adds nothing on its own' {
    $s = New-PetState; $wk = [datetime]::UtcNow.AddDays(3)
    Add-WeekRise $s @{ Pct = 30; Reset = $wk }                       # the first reading: a baseline
    $a = (Get-Today $s).WeekRise
    Add-WeekRise $s @{ Pct = 33; Reset = $wk.AddSeconds(0.4) }       # same week (the reset's fraction wobbles)
    Add-WeekRise $s @{ Pct = 32; Reset = $wk }                       # a staler source: nothing
    Add-WeekRise $s @{ Pct = 36; Reset = $wk }
    $b = (Get-Today $s).WeekRise
    Add-WeekRise $s @{ Pct = 2; Reset = $wk.AddDays(7) }             # the week reset: its 2 so far count
    $a -eq 0 -and $b -eq 6 -and (Get-Today $s).WeekRise -eq 8 -and (Get-TodayText $s) -cmatch '\nUsed 8% of the week$' -and
    (Get-TodayText (New-PetState)) -notmatch 'Used'
}
Check 'live: an expired login is its own reason, and an error message never carries a token' {
    -not (Test-LoginExpired $null) -and (Test-LoginExpired 1000) -and -not (Test-LoginExpired ([DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeMilliseconds())) -and
    (Get-LiveFailureText 'Response status code: Bearer sk-ant-oat01-abc failed') -notmatch 'sk-ant' -and (Get-LiveFailureText '') -eq 'no answer' -and
    (Get-LiveFailureText ('x' * 200)).Length -eq 90 -and
    (Get-Content (Join-Path $root 'tok.ps1') -Raw) -match "\`$r\.Why -eq 'expired'"
}
# --- defaults for a stranger (parliament session 6): Chatter normal, no name, the guess's limit by plan
Check 'defaults: Chatter normal, no name, no fixed limit, and a late-night line reads right without a name' {
    $d = Get-BodyConfig
    $d.Chatter -eq 'normal' -and $d.YourName -eq '' -and $null -eq $d.LimitUsd -and (Get-LateNightLine ([datetime]'2026-10-10 01:20') '') -eq "It's 1:20. Just noting it." -and (Get-LateNightLine ([datetime]'2026-10-10 01:20') 'Sam') -eq "It's 1:20, Sam. Just noting it."
}
Check 'plan limit: Max 20x 720, Max 5x 180, Pro 36 (by type or by the default tier); anything else or nothing recorded is none' {
    (Get-PlanLimitFromAccount @{ organizationType = 'claude_max'; organizationRateLimitTier = 'default_claude_max_20x' }) -eq 720 -and
    (Get-PlanLimitFromAccount @{ organizationType = 'claude_max'; organizationRateLimitTier = 'default_claude_max_5x' }) -eq 180 -and
    (Get-PlanLimitFromAccount @{ organizationType = 'claude_pro'; organizationRateLimitTier = 'whatever' }) -eq 36 -and
    (Get-PlanLimitFromAccount @{ organizationType = 'other'; organizationRateLimitTier = 'default_claude_ai' }) -eq 36 -and
    $null -eq (Get-PlanLimitFromAccount @{ organizationType = 'team'; organizationRateLimitTier = 'default_raven' }) -and $null -eq (Get-PlanLimitFromAccount @{}) -and $null -eq (Get-PlanLimitFromAccount $null)
}
Check 'plan limit: read from .claude.json''s oauthAccount; a missing file, no account or a broken file is none; a LimitUsd in config always wins' {
    $pj = Join-Path ([IO.Path]::GetTempPath()) "tok-plan-$PID.json"
    '{"oauthAccount":{"organizationType":"claude_pro","organizationRateLimitTier":"default_claude_ai"},"other":1}' | Set-Content $pj
    $pro = Get-PlanLimitUsd $pj
    '{"other":1}' | Set-Content $pj; $none = Get-PlanLimitUsd $pj
    '{ nope' | Set-Content $pj; $bad = Get-PlanLimitUsd $pj
    Remove-Item $pj
    $pro -eq 36 -and $null -eq $none -and $null -eq $bad -and $null -eq (Get-PlanLimitUsd $pj) -and
    (Resolve-LimitUsd 43.5 180) -eq 43.5 -and (Resolve-LimitUsd $null 180) -eq 180 -and (Resolve-LimitUsd 0 36) -eq 36 -and $null -eq (Resolve-LimitUsd $null $null) -and $null -eq (Resolve-LimitUsd 0 0)
}
$noWin = Get-WindowStatus $after $null $null $now
Check 'window status: no limit and no real reading -> no reading, and nothing is divided by the limit' {
    $z = Get-WindowStatus $after $null 0 $now
    $noWin.NoReading -and -not $noWin.Active -and -not $noWin.Real -and $noWin.Pct -eq 0 -and $z.NoReading -and $z.Pct -eq 0 -and -not (Get-WindowStatus $after $lim 36 $now).NoReading
}
Check 'window status: no limit but a real reading still reads, with no spend top-up; a reading that has ended falls to no reading' {
    $r = Get-WindowStatus $after $lim $null $now
    $e = Get-WindowStatus $late $lim $null ([datetime]::new(2026, 10, 5, 20, 0, 0, [DateTimeKind]::Utc))
    $r.Real -and $r.Active -and -not $r.NoReading -and [math]::Abs($r.Pct - 0.25) -lt 1e-9 -and $e.NoReading -and $e.Week.Pct -eq 54
}
Check 'stats and hover with no reading: "5-hour no reading" with the pointer, then "no usage reading"' {
    $t = Get-StatsText (New-PetState) $noWin
    $t -cmatch '\n5-hour no reading\nExact usage is in Settings$' -and (Get-StatsText (New-PetState) $noWin $true) -cmatch '\n5-hour no reading$' -and
    (Get-BellyText $noWin) -eq 'no usage reading' -and (Get-BellyText $null) -eq '5-hour not started' -and (Get-BellyText $ws) -cmatch '^5-hour 35% · resets ' -and (Get-BellyText $ws2) -cmatch '^5-hour 1% \(guess\) · resets '
}
Check 'hover and menu: "window" means an app only (5-hour N%, 5-hour not started, Follow the active app with its hint)' {
    $tsrc = Get-Content (Join-Path $root 'tok.ps1') -Raw
    $fresh = Get-BellyText ([pscustomobject]@{ Active = $false; Real = $true; Pct = 0 })
    $fresh -eq '5-hour not started' -and ([regex]::Match((Get-Content (Join-Path $root 'lib\Pet.ps1') -Raw), '(?ms)^function Get-BellyText\b.*?^\}').Value) -notmatch "window \d|'fresh window'|window \$" -and
    $tsrc -match "Add-MenuItem 'Follow the active app' \{ Save-ConfigKey 'Follow' .*? 'sit in its corner' \`$settings" -and $tsrc -notmatch "Follow the window"
}
Check 'window (tok.ps1): the guess is measured against the config limit or the plan''s, and the hover and Stats use the helpers' {
    $tsrc = Get-Content (Join-Path $root 'tok.ps1') -Raw
    $tsrc -match 'Get-WindowStatus \$script:Usage \$best \(Resolve-LimitUsd \$script:Config\.LimitUsd \$script:PlanLimit\)' -and $tsrc -match '\$script:PlanLimit = Get-PlanLimitUsd \$cfg' -and
    $tsrc -match '\$belly = Get-BellyText \$w' -and $tsrc -match 'Get-StatsPanel \$script:State \$script:WindowInfo \(\$script:Config\.LiveUsage -eq \$true\)'
}
$old = @{ FetchedUtc = $now.AddMinutes(-20); Source = 'cache'; FiveHour = @{ Pct = 20; Reset = $now.AddHours(1) } }
$new = @{ FetchedUtc = $now.AddMinutes(-1); Source = 'live'; FiveHour = @{ Pct = 30; Reset = $now.AddHours(1) } }
Check 'limits: the freshest source wins' { (Select-Limits @($old, $null, $new)).Source -eq 'live' -and (Select-Limits @($old, $null)).Source -eq 'cache' }
$wl = Get-WindowStatus $after $new 36 $now
$wl2 = Get-WindowStatus $after @{ FetchedUtc = $now.AddMinutes(-40); Source = 'live'; FiveHour = @{ Pct = 30; Reset = $now.AddHours(1) } } 36 $now
Check 'window status: a live reading gets the same top-up since it was fetched' { $wl.Real -and [math]::Abs($wl.Pct - 0.30) -lt 1e-9 -and [math]::Abs($wl2.Pct - 0.40) -lt 1e-9 }
Check 'live: the status-line source is gone' { -not (Get-Command Get-StatusLineUsage -ErrorAction SilentlyContinue) }
Check 'live: poll every 3 min while active, every 10 otherwise' { (Get-LivePollMinutes $true) -eq 3 -and (Get-LivePollMinutes $false) -eq 10 }
Check 'live: backoff is 5, 10, 20, then 40 minutes at most' { ((1..6 | ForEach-Object { Get-LiveBackoffMinutes $_ }) -join ',') -eq '5,10,20,40,40,40' }
$rec = ConvertTo-LiveRecord $new $now.AddMinutes(3) 2
$back = ConvertFrom-LiveRecord ($rec | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable -DateKind String)
Check 'live: the saved record round-trips (reading, its fetch time, next allowed time, failures)' {
    $back.Failures -eq 2 -and $back.Limits.Source -eq 'live' -and $back.Limits.FetchedUtc -eq $new.FetchedUtc.ToUniversalTime() -and $back.Limits.FiveHour.Pct -eq 30 -and
    $back.Limits.FiveHour.Reset -eq $now.AddHours(1).ToUniversalTime() -and $back.Next -eq $now.AddMinutes(3).ToUniversalTime() -and -not $back.Limits.Week
}
Check 'live: no record -> null; a record with no reading keeps the wait' { -not (ConvertFrom-LiveRecord $null) -and (ConvertFrom-LiveRecord (ConvertTo-LiveRecord $null $now 3)).Failures -eq 3 -and -not (ConvertFrom-LiveRecord (ConvertTo-LiveRecord $null $now 3)).Limits }
Remove-Item $cfg

# --- exact usage is opt-in (parliament session 6)
$cfgPath = Join-Path $script:DataDir 'config.json'
$null = New-Item -ItemType Directory -Force $script:DataDir
Remove-Item $cfgPath -ErrorAction SilentlyContinue
Check 'exact usage: off in the defaults' { (Get-BodyConfig).LiveUsage -eq $false }
Check 'exact usage: an install from before the switch (a state with no Greeted key) keeps it, once, unless config.json already says' {
    $olds = @{ Name = 'Tok'; Xp = 1.0 }
    $a = Get-OldInstallPlan $olds $null; $b = Get-OldInstallPlan $olds @{ Chatter = 'quiet' }; $c = Get-OldInstallPlan $olds @{ LiveUsage = $false }; $d = Get-OldInstallPlan $olds @{ LiveUsage = $true }
    $a.Old -and $a.WriteLiveUsage -and $b.Old -and $b.WriteLiveUsage -and $c.Old -and -not $c.WriteLiveUsage -and $d.Old -and -not $d.WriteLiveUsage
}
Check 'exact usage: a new Tok, or a state that has Greeted, is not an older install' {
    $n = Get-OldInstallPlan $null $null; $g = Get-OldInstallPlan (New-PetState) $null
    -not $n.Old -and -not $n.WriteLiveUsage -and -not $g.Old -and -not $g.WriteLiveUsage -and (New-PetState).Greeted -eq $false
}
Check 'exact usage: the migration writes only LiveUsage into the existing file, and a broken file is left alone' {
    '{"Chatter":"quiet","YourName":"P"}' | Set-Content $cfgPath
    $ok = Set-ConfigFileKey 'LiveUsage' $true
    $c = Get-Content $cfgPath -Raw | ConvertFrom-Json -AsHashtable
    $kept = $ok -and $c.Count -eq 3 -and $c.LiveUsage -eq $true -and $c.Chatter -eq 'quiet' -and $c.YourName -eq 'P'
    '{ not json' | Set-Content $cfgPath
    $bad = Set-ConfigFileKey 'LiveUsage' $true
    $left = (Get-Content $cfgPath -Raw).Trim() -eq '{ not json'
    Remove-Item $cfgPath; $fresh = Set-ConfigFileKey 'LiveUsage' $true; $only = (Get-Content $cfgPath -Raw | ConvertFrom-Json -AsHashtable).Count -eq 1
    Remove-Item $cfgPath
    $kept -and -not $bad -and $left -and $fresh -and $only
}
# --- minions
. (Join-Path $root 'lib\Minions.ps1')
$ev = @(ConvertTo-BodyEvents (Line '2026-10-05T01:00:00Z' 'msg_s' 1 0 'claude-haiku-4-5' '[{"type":"text","text":"ok"}]' 'end_turn') $true)
Check 'minions: subagent end_turn -> SubDone' { $ev.Type -contains 'SubDone' -and $ev.Type -notcontains 'Done' }
$ev = @(ConvertTo-BodyEvents (Line '2026-10-05T01:00:00Z' 'msg_s' 1 0 'claude-haiku-4-5' '[{"type":"text","text":"ok"}]' 'end_turn'))
Check 'minions: main end_turn is not SubDone' { $ev.Type -notcontains 'SubDone' }
Check 'minions: kind by model' { (Get-MinionKind 'claude-haiku-4-5-20251001').Name -eq 'haiku' -and (Get-MinionKind 'claude-sonnet-5-5').Name -eq 'sonnet' -and (Get-MinionKind 'claude-opus-5-5').Name -eq 'opus' }
Check 'minions: unknown model is orange' { (Get-MinionKind 'claude-mystery-9').Name -eq 'other' -and (Get-MinionKind '').Name -eq 'other' }
Check 'minions: Fable has its own colour, the lightest seed of all (colour-blind safe by brightness)' {
    $lum = { param($hex) $c = [Convert]::FromHexString($hex.Substring(3)); 0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2] }
    $f = Get-MinionKind 'claude-fable-5-1'; $others = 'haiku', 'sonnet', 'opus', 'other' | ForEach-Object { & $lum $script:MinionKinds[$_].Seed }
    $f.Name -eq 'fable' -and (& $lum $f.Seed) -gt ($others | Measure-Object -Maximum).Maximum
}
Check 'minions: the palette is spread by brightness, every neighbour at least 1.2 apart in contrast ratio (session 7)' {
    $rl = { param($hex) $c = [Convert]::FromHexString($hex.Substring(3)) | ForEach-Object { $x = $_ / 255; if ($x -le 0.04045) { $x / 12.92 } else { [math]::Pow(($x + 0.055) / 1.055, 2.4) } }; 0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2] }
    $ls = @('haiku', 'sonnet', 'opus', 'fable', 'other' | ForEach-Object { & $rl $script:MinionKinds[$_].Seed } | Sort-Object)
    $ok = $true; for ($i = 1; $i -lt $ls.Count; $i++) { if (($ls[$i] + 0.05) / ($ls[$i - 1] + 0.05) -lt 1.2) { $ok = $false } }
    $ok -and (& $rl $script:MinionKinds.haiku.Seed) -eq $ls[0]
}
Check 'minions: opus is biggest and slowest' { $o = Get-MinionKind 'opus'; $h = Get-MinionKind 'haiku'; $o.Size -gt $h.Size -and $o.Speed -lt $h.Speed }
Check 'poses: nothing looks hurt (no lids, no frowns), and fullness never changes the face' {
    $faces = 'happy', 'busy', 'zoom', 'full', 'stuffed', 'sleep', 'coma', 'needs', 'hungry', 'ouch', 'dizzy', 'love', 'content', 'eat1', 'eat2', 'eat3', 'eat4', 'home1', 'home2', 'home3', 'stretch'
    $ok = $true
    foreach ($f in $faces) { $p = Get-Pose $f; if ($p.Eyes -notin 'open', 'closed', 'happy', 'squeeze') { $ok = $false }; if ($p.Mouth -eq 'smile' -and $p.Smile[1] -lt 0) { $ok = $false } }
    $ok -and (Get-Pose 'full').Eyes -eq 'open' -and (Get-Pose 'full').Body -eq 'normal' -and (Get-Pose 'coma').Body -eq 'limit'
}
Check 'poses (session 7): the 85% face keeps its eyes open with a plain smile and the hand on the lantern; love and content keep the grin' {
    $s = Get-Pose 'stuffed'; $l = Get-Pose 'love'; $f = Get-Pose 'full'
    $s.Eyes -eq 'open' -and $s.Mouth -eq 'smile' -and ($s.Smile -join ',') -eq ($f.Smile -join ',') -and $s.Arms -eq 'pat' -and $s.Cheek -eq $f.Cheek -and $l.Eyes -eq 'happy' -and $l.Arms -eq 'pat' -and (Get-Pose 'content').Eyes -eq 'happy'
}
Check 'art: the body builds as XAML' { [xml]$x = "<Canvas xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>$(Get-CreatureXaml)$(Get-PropsXaml)</Canvas>"; $x.Canvas.ChildNodes.Count -gt 20 }
Check 'hops: an adult is the baseline, a hatchling is bouncier, an elder calmer and slower' {
    $a = Get-HopSpec 'adult'; $b = Get-HopSpec 'hatchling'; $e = Get-HopSpec 'elder'
    $a.Height -eq 22 -and $a.RiseMs -eq 220 -and $a.FallMs -eq 440 -and
    [math]::Abs($b.Height - 25.3) -lt 1e-9 -and $b.RiseMs -eq 220 -and
    [math]::Abs($e.Height - 17.6) -lt 1e-9 -and [math]::Abs($e.RiseMs - 253) -lt 1e-9 -and [math]::Abs($e.FallMs - 506) -lt 1e-9
}
Check 'hops: the needs-you hop never scales' { $e = Get-HopSpec 'elder' $true; $b = Get-HopSpec 'hatchling' $true; $e.Height -eq 22 -and $e.FallMs -eq 440 -and $b.Height -eq 22 }
Check 'easter egg: Tok fires on its name' { (Test-TokName 'hey Tok, how are you') -and (Test-TokName 'tok.') -and (Test-TokName 'Tok is great') -and (Test-TokName "TOK's tired") }
Check 'easter egg: Tok does not fire on the file, folder or tokens' {
    -not (Test-TokName 'edit tok.ps1') -and -not (Test-TokName 'C:\Users\x\Documents\tok\lib') -and -not (Test-TokName 'look in tok/ please') -and
    -not (Test-TokName 'tok\design') -and -not (Test-TokName 'run /tok-private') -and -not (Test-TokName 'tools/tok.ps1') -and -not (Test-TokName 'count the tokens') -and -not (Test-TokName 'the tok-say skill')
}
Check 'easter egg: thanks, but not ty or thx' { (Test-Thanks 'thanks!') -and (Test-Thanks 'ok thank you') -and -not (Test-Thanks 'ty') -and -not (Test-Thanks 'thx') -and -not (Test-Thanks 'empty typo') }
Check 'bubbles: a Low bubble waits for quiet and never queues behind one' {
    (Get-BubbleVerdict $true $false $false 0) -eq 'queue' -and (Get-BubbleVerdict $true $true $false 0) -eq 'drop' -and
    (Get-BubbleVerdict $true $false $false 1) -eq 'drop' -and (Get-BubbleVerdict $true $true $true 0) -eq 'drop'
}
Check 'bubbles: a live bubble ends a Low one early, and queues behind a live one' {
    (Get-BubbleVerdict $false $true $true 0) -eq 'cut' -and (Get-BubbleVerdict $false $true $false 0) -eq 'queue' -and (Get-BubbleVerdict $false $false $false 0) -eq 'queue'
}
# a second monitor at another scale (10-10, e.g. a 150% laptop screen at 0,0 and a 100% 2560x1080 ultrawide above it at
# 694,-1080; Tok sees the ultrawide stretched to 3840x1620 at 1041,-1620). An app maximized there must map to that whole monitor.
$uw = ConvertTo-LogicalRect @{ Left = 694; Top = -1080; Right = 3254; Bottom = -48 } @{ Left = 1041; Top = -1620; Right = 4881; Bottom = 0 } 694 -1080 2560 1080
Check 'perch: an app on a monitor at another scale maps onto that monitor, edge to edge' { $uw.Left -eq 1041 -and $uw.Right -eq 4881 -and $uw.Top -eq -1620 -and $uw.Bottom -eq -72 }
$same = ConvertTo-LogicalRect @{ Left = 10; Top = 20; Right = 3000; Bottom = 2000 } @{ Left = 0; Top = 0; Right = 3840; Bottom = 2160 } 0 0 3840 2160
Check 'perch: the main monitor maps to itself, and no display info means no mapping' { $same.Left -eq 10 -and $same.Right -eq 3000 -and (ConvertTo-LogicalRect @{ Left = 5; Top = 6; Right = 7; Bottom = 8 } $null 0 0 0 0).Right -eq 7 }
Check 'perch: minions make room by shifting left, and glide back' { (Get-MinionRoomX 1000 $false 0) -eq 1000 -and (Get-MinionRoomX 1000 $true 0) -eq 954 }
Check 'perch: the shift never goes past the app left edge, nor right of the perch' {
    (Get-MinionRoomX 0 $true 100) -eq -33 -and (Get-MinionRoomX 250 $true 200) -eq 204 -and (Get-MinionRoomX 10 $true 500) -le 10
}
Check 'perch: the shifted orbit stays on screen (right edge: perch 288 + window left, orbit 74 + seed 13 about the pet centre)' {
    $right = 1920; $x = $right - 288; $shifted = Get-MinionRoomX $x $true 0
    ($shifted + 220 + 74 + 13) -le $right -and ($x + 220 + 74 + 13) -gt $right
}
$k = Get-MinionKind 'sonnet'
$front = Get-OrbitPoint ([math]::PI / 2) $k; $back = Get-OrbitPoint (3 * [math]::PI / 2) $k
Check 'minions: near half of the orbit is in front' { $front.Front -and -not $back.Front }
Check 'minions: in front is larger and lower' { $front.Depth -gt $back.Depth -and $front.Y -gt $back.Y }
Check 'minions: opus floats higher' { (Get-OrbitPoint 0 (Get-MinionKind 'opus')).Y -lt (Get-OrbitPoint 0 $k).Y }
Check 'minions: opus passes in front at belly height, not over the face' { [math]::Abs((Get-OrbitPoint ([math]::PI / 2) (Get-MinionKind 'opus')).Y - $front.Y) -lt 0.01 }

# --- age is days together (phase 3)
$d0 = [datetime]::new(2026, 9, 20, 12, 0, 0, [DateTimeKind]::Local)        # a local noon, so local days are unambiguous
function Add-Day($Lin, [string]$Model, [datetime]$Start, [int]$Replies, [string]$Project = 'tok') {
    for ($i = 0; $i -lt $Replies; $i++) { $null = Add-LineageReply $Lin $Model $Start.AddMinutes($i).ToUniversalTime() 10 $Project }
}
$al = New-Lineage
Add-Day $al 'claude-opus-5-5' $d0 9
Check 'days: 9 replies is not a day yet' { (Get-VersionDays $al.Versions['5.5']) -eq 0 }
Add-Day $al 'claude-opus-5-5' $d0.AddMinutes(9) 1
Check 'days: the 10th reply makes it a day' { (Get-VersionDays $al.Versions['5.5']) -eq 1 }
Add-Day $al 'claude-opus-5-5' $d0.AddDays(1) 25
Check 'days: more replies the same day are still one day' { (Get-VersionDays $al.Versions['5.5']) -eq 2 }
$ml = New-Lineage; $mid = [datetime]::new(2026, 9, 20, 23, 56, 0, [DateTimeKind]::Local)
Add-Day $ml 'claude-opus-5-5' $mid 10        # 11:56 pm to 12:05 am: five replies each side of local midnight
Check 'days: they are local calendar days, so replies split by midnight do not add up' { (Get-VersionDays $ml.Versions['5.5']) -eq 0 -and $ml.Versions['5.5'].Days.Count -eq 2 }
$ul = New-Lineage; $utcMid = [datetime]::new(2026, 9, 20, 23, 56, 0, [DateTimeKind]::Utc)
Add-Day $ul 'claude-opus-5-5' $utcMid.ToLocalTime() 10
Check 'days: the day key is the local date of the reply' { $ul.Versions['5.5'].Days.ContainsKey($utcMid.ToLocalTime().ToString('yyyy-MM-dd')) }
$vl = New-Lineage
Add-Day $vl 'claude-opus-5-5' $d0 6; Add-Day $vl 'claude-sonnet-5-5' $d0.AddMinutes(6) 4
Add-Day $vl 'claude-haiku-4-5-20251001' $d0.AddMinutes(10) 30; Add-Day $vl 'claude-opus-5' $d0.AddMinutes(40) 30
Check 'days: opus and sonnet of the same version add up; other versions never do' { (Get-VersionDays $vl.Versions['5.5']) -eq 1 -and (Get-VersionDays $vl.Versions['4.5']) -eq 1 -and $vl.Versions['5.5'].Replies -eq 10 }
Check 'days: before the first generation the newest version sets the count; its first counted day makes it Tok I' {
    $x = New-Lineage; Add-Day $x 'claude-opus-5-5' $d0 9
    $sx = New-PetState; $sx.Lineage = $x
    $before = (Get-GenDays $sx) -eq 0 -and @($x.Generations).Count -eq 0 -and (Get-PetStage $sx).Name -eq 'egg'
    Add-Day $x 'claude-opus-5-5' $d0.AddMinutes(9) 3
    $before -and (Get-GenDays $sx) -eq 1 -and @($x.Generations).Count -eq 1 -and (Get-PetStage $sx).Name -eq 'hatchling'
}
$stageNames = 0, 1, 2, 3, 9, 10, 29, 30, 99 | ForEach-Object { (Get-StageForDays $_).Name }
Check 'stages: egg, hatchling at 1, kid at 3, adult at 10, elder at 30' { ($stageNames -join ',') -eq 'egg,hatchling,hatchling,kid,kid,adult,adult,elder,elder' }
function New-AgedState([int]$Days5, [int]$Days55, [string]$Project = 'tok') {
    $l = New-Lineage; $a = $d0.AddDays(-80)
    for ($d = 0; $d -lt $Days5; $d++) { Add-Day $l 'claude-opus-5' $a.AddDays($d) 12 $Project }
    Add-Day $l 'claude-opus-5-5' $d0.AddDays(-46) 12 $Project; Add-Day $l 'claude-opus-5-5' $d0.AddDays(-45) 12 $Project    # two days settling in; the third makes 5.5 a generation
    for ($d = 0; $d -lt $Days55; $d++) { Add-Day $l 'claude-opus-5-5' $d0.AddDays($d - 40) 12 $Project }
    $st = New-PetState; $st.Lineage = $l; $st.Tokens = 262300000L; $st.BornUtc = $d0.AddDays(-46).ToUniversalTime().ToString('o'); $st
}
$aged = New-AgedState 34 14
Check 'stage comes from the current generation days' { $aged.Lineage.Generations.Count -eq 2 -and (Get-GenDays $aged) -eq 14 -and (Get-PetStage $aged).Name -eq 'adult' -and (Get-NextStage $aged).Name -eq 'elder' }
$stx = Get-StatsText $aged $null
Check 'stats: the title is name, stage and day' { $stx -cmatch '^Tok II · adult · day 14\n' }
Check 'stats: no XP, no lifetime token tally, no nap count, no countdown to the next stage (ledger S4-S6)' {
    $aged.Comas = 3; $sc = Get-StatsText $aged $ws; $aged.Comas = 0
    $stx -notmatch '(?i)\bxp\b' -and $sc -notmatch '(?i)ate |tokens|naps|elder at' -and (Get-StatsText (New-AgedState 3 31) $null) -cmatch '^Tok II · elder · day 31\n' -and (Get-StatsText (New-AgedState 3 2) $null) -cmatch '^Tok II · hatchling · day 2\n'
}
Check 'stats: every line fits the bubble' { @((Get-StatsText $aged $ws) -split "`n" | Where-Object { $_.Length -gt 34 }).Count -eq 0 -and @((Get-StatsText (New-PetState) $ws) -split "`n" | Where-Object { $_.Length -gt 34 }).Count -eq 0 }
$rows = @(Get-FamilyRows $aged.Lineage $aged.BornUtc)
Check 'family: one line each for name, version and final stage, then the days' {
    $rows.Count -eq 2 -and -not $rows[0].Stage -and $rows[1].Stage -eq 'adult' -and $rows[0].Lines[0] -ceq 'Tok I · Opus 5' -and $rows[1].Lines[0] -ceq 'Tok II · Opus 5.5 · adult' -and $rows[1].Lines[1] -eq '14 days'
}
# Tok I's 34 days of its own, plus the 2 days Opus 5.5 was settling in while Tok I was still current (any model counts, 10-10)
Check 'family: a generation from before Tok hatched stays "no body"' { $rows[0].Lines[1] -eq '36 days · no body' }
Check 'family: a "no body" generation has no stage and no portrait' { -not $rows[0].Stage -and $rows[0].Lines[0] -notmatch '(egg|hatchling|kid|adult|elder)$' }
$lateBorn = (Get-FamilyRows $aged.Lineage $d0.AddDays(-200).ToUniversalTime().ToString('o'))
Check 'family: a generation Tok lived through shows its days, no project (10-10)' { $lateBorn[0].Lines[1] -eq '36 days' }
Check 'family: no "mostly at home"; a no-body generation is flagged for the empty ring' {
    $hr = @(Get-FamilyRows (New-AgedState 3 4 'home').Lineage $d0.AddDays(-200).ToUniversalTime().ToString('o'))
    $hr[1].Lines[1] -eq '4 days' -and $rows[0].NoBody -and -not $rows[1].NoBody
}
Check 'family: private mode shows the same days' { (@(Get-FamilyRows $aged.Lineage $d0.AddDays(-200).ToUniversalTime().ToString('o') -Private))[1].Lines[1] -eq '14 days' }
Check 'family: no scores, and every line fits the bubble' {
    $long = New-AgedState 34 1 'a-rather-long-project-folder-name'
    $lt = Get-FamilyText $long.Lineage $d0.AddDays(-200).ToUniversalTime().ToString('o')
    @($lt -split "`n" | Where-Object { $_.Length -gt 34 }).Count -eq 0 -and $lt -notmatch '…|a-rather' -and $ft -notmatch '(?i)xp|score|rank'
}
Check 'family: the portrait is drawn live from parameters, for every stage' {
    $ok = $true
    foreach ($s in 'egg', 'hatchling', 'kid', 'adult', 'elder') {
        $x = [xml]('<Canvas xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">' + (Get-PortraitXaml $s) + '</Canvas>')
        if (-not $x.DocumentElement.HasChildNodes) { $ok = $false }
    }
    $ok -and (Get-PortraitXaml 'elder') -match 'Stroke=''#FF9A6418''' -and (Get-PortraitXaml 'adult') -notmatch '#FF9A6418' -and (Get-PortraitXaml 'elder') -notmatch 'x:Name'
}
$tl = New-AgedState 31 1
Check 'tint: a generation that ended as an elder hands its flower colour to the next' { $tl.Lineage.Versions['5.5'].Tint -eq $script:Petal -and -not $tl.Lineage.Versions['5'].Tint }
Check 'tint: a generation that ended short of elder passes nothing on' { -not (New-AgedState 27 1).Lineage.Versions['5.5'].Tint -and -not (New-AgedState 10 1).Lineage.Versions['5.5'].Tint }
Check 'tint: it is one colour field in the state, and survives a save' {
    $back = $tl | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable -DateKind String
    $back.Lineage.Versions['5.5'].Tint -eq '#FFFFCF4D' -and (Get-VersionDays $back.Lineage.Versions['5.5']) -eq 1 -and (Get-PetStage $back).Name -eq 'hatchling'
}
$bf = Join-Path ([IO.Path]::GetTempPath()) "tok-days-$PID"; $null = New-Item -ItemType Directory -Force "$bf\proj\subagents"
$main = (0..11 | ForEach-Object { Line "2026-10-01T15:$('{0:D2}' -f (2 + $_)):00Z" "msg_m$_" }) + (0..3 | ForEach-Object { Line "2026-10-02T15:$('{0:D2}' -f (2 + $_)):00Z" "msg_n$_" })
$sub = 0..29 | ForEach-Object { Line "2026-10-03T15:$('{0:D2}' -f (2 + $_ % 20)):00Z" "s$_" }
Set-Content "$bf\proj\main.jsonl" $main; Set-Content "$bf\proj\subagents\agent-1.jsonl" $sub
$bl = Get-LineageBackfill $bf
Remove-Item $bf -Recurse -Force
Check 'backfill: day counts come from the main sessions on disk; minions do not count' { $r = $bl.Versions['5.5']; $r.Replies -eq 16 -and (Get-VersionDays $r) -eq 1 -and $r.Days.Count -eq 2 -and $bl.Schema -eq 2 }
$bf = Join-Path ([IO.Path]::GetTempPath()) "tok-proj-$PID"; $null = New-Item -ItemType Directory -Force "$bf\proj"
$cd = { param($l, $c) $l -replace '^\{', ('{"cwd":"C:\\Users\\x\\' + $c + '",') }
Set-Content "$bf\proj\main.jsonl" (@('{"type":"user","cwd":"C:\\Users\\x\\tok","message":{"role":"user","content":"hi"}}') + (0..2 | ForEach-Object { & $cd (Line "2026-10-01T15:0$($_):00Z" "msg_p$_") $(if ($_) { 'memory' } else { 'tok' }) }))
$bp = Get-LineageBackfill $bf
Remove-Item $bf -Recurse -Force
Check 'backfill: replies count toward the project the session started in, not where Claude cd''d to' { $p = $bp.Versions['5.5'].Projects; $p['tok'] -eq 3 -and -not $p.ContainsKey('memory') }

# --- phase 4: a new model is a passing-on
Check 'egg spots: coral by default, the parent flower colour when it was an elder' {
    (Get-EggSpotColor '') -eq '#55DE7F5E' -and (Get-EggSpotColor $null) -eq '#55DE7F5E' -and (Get-EggSpotColor 'junk') -eq '#55DE7F5E' -and (Get-EggSpotColor $script:ElderTint) -eq '#80FFCF4D' -and (Get-EggSpotColor '#E0A93C') -eq '#80E0A93C'
}
Check 'egg spots: the tint a real elder passes on is the one the egg wears' {
    (Get-EggSpotColor (Get-CurrentRec $tl.Lineage).Tint) -eq '#80FFCF4D' -and (Get-EggSpotColor (Get-CurrentRec (New-AgedState 10 1).Lineage).Tint) -eq '#55DE7F5E'
}
Check 'molt pill names the new model' { (Get-MoltPill 'claude-opus-6') -eq 'Opus 6' -and (Get-MoltPill 'claude-sonnet-5-5') -eq 'Sonnet 5.5' -and (Get-MoltPill 'weird') -ceq 'A new model' }
$planE = Get-MoltPlan 'elder' 'claude-opus-6' 'Tok III' $script:ElderTint
$planK = Get-MoltPlan 'kid' 'claude-opus-6' 'Tok III'
Check 'molt plan: an elder passes on (petals, seed), a younger Tok curls up, an egg only flashes' {
    $planE.Kind -eq 'elder' -and $planK.Kind -eq 'young' -and (Get-MoltPlan 'hatchling' 'claude-opus-6' 'Tok III').Kind -eq 'young' -and (Get-MoltPlan 'adult' 'claude-opus-6' 'Tok III').Kind -eq 'young' -and (Get-MoltPlan 'egg' 'claude-opus-6' 'Tok III').Kind -eq 'egg'
}
Check 'molt plan: the egg hatches right away or waits, and the elder egg carries the tint' {
    ($planE.Phases -join ',') -eq 'elder,hatch' -and ((Get-MoltPlan 'kid' 'claude-opus-6' 'Tok III' '' $false).Phases -join ',') -eq 'young' -and $planE.SpotColor -eq '#80FFCF4D' -and $planK.SpotColor -eq '#55DE7F5E'
}
Check 'hatch line: the real next name, fits the bubble, never "I am back", never remembers' {
    $ok = $true
    foreach ($n in 'Tok II', 'Tok III', 'Tok VIII', 'Tok XVIII') { $l = Get-HatchLine $n; if ($l.Length -gt 34 -or $l -cnotmatch "^Hello! I'm $n\.$" -or $l -match '(?i)back|remember|again') { $ok = $false } }
    $ok -and $planE.Line -ceq "Hello! I'm Tok III." -and (Get-HatchPlan 'Tok III').Line -eq $planE.Line -and ((Get-HatchPlan 'Tok III').Phases -join ',') -eq 'hatch'
}
Check 'next name comes off the family tree' { (Get-NextLineageName $aged.Lineage) -eq 'Tok III' -and (Get-NextLineageName (New-Lineage)) -eq 'Tok I' }
# the trigger is once: the reply that makes a new generation returns it, the replies after it return nothing
$ml = New-Lineage; $mt = [datetime]::new(2026, 10, 1, 12, 0, 0, [DateTimeKind]::Utc); $moltHits = @()
for ($i = 0; $i -lt 30; $i++) { $moltHits += Add-LineageReply $ml 'claude-opus-5' $mt.AddMinutes($i) 10 'tok' }
foreach ($d in 40..42) { for ($i = 0; $i -lt 15; $i++) { $moltHits += Add-LineageReply $ml 'claude-opus-6' $mt.AddDays($d).AddMinutes($i) 10 'tok' } }
Check 'molt trigger: fires once per new generation, on the reply that makes it' { @($moltHits | Where-Object { $_ }).Count -eq 2 -and @($moltHits | Where-Object { $_ })[1] -eq '6' -and @($ml.Generations).Count -eq 2 }
# play-only: building and running a plan reads, never writes
$stateBefore = $aged | ConvertTo-Json -Depth 12 -Compress
$null = Get-MoltPlan 'elder' 'claude-opus-6' (Get-NextLineageName $aged.Lineage) $script:ElderTint; $null = Get-HatchPlan 'Tok III'; $null = Get-MoltPill 'claude-opus-6'
Check 'play-only: building a plan leaves the state exactly as it was' { ($aged | ConvertTo-Json -Depth 12 -Compress) -eq $stateBefore }
$tokSrc = Get-Content (Join-Path $root 'tok.ps1') -Raw; $passSrc = Get-Content (Join-Path $root 'lib\Passing.ps1') -Raw
function Get-FnText([string]$Src, [string]$Name) { [regex]::Match($Src, "(?ms)^function $Name\b.*?^\}").Value }
Check 'play-only: the piece (lib\Passing.ps1) never saves and never writes the state or the lineage' {
    $passSrc -notmatch 'Save-PetJson|Add-LineageReply|Add-LineageMinion' -and $passSrc -notmatch '\$script:State\.\S+\s*='
}
Check 'play-only: -Molt and the demo plan never change the state' {
    $molt = [regex]::Match($tokSrc, '(?ms)^\} elseif \(\$Molt\) \{.*?^\} elseif \(\$MinionDemo\)').Value
    $molt.Length -gt 200 -and $molt -notmatch 'Save-PetJson|Add-LineageReply' -and $molt -notmatch '\$script:State\.\S+\s*=[^=]' -and (Get-FnText $tokSrc 'Get-DemoMoltPlan') -notmatch 'Save-PetJson|Add-LineageReply|\$script:State\.\S+\s*=[^=]'
}
Check 'play-only: a -Molt or -Bench window skips the mutex, the scans, the usage poll and every save of the state' {
    $tokSrc -match '\$PlayOnly = \$Demo -or \$MinionDemo -or \$Showcase -or \$Molt -or \$Bench -gt 0' -and
    $tokSrc -match 'if \(-not \$PlayOnly -and -not \$Mood -and -not \$RenderDir -and -not \$mutex' -and
    $tokSrc -match 'if \(-not \$PlayOnly -and -not \$script:ForcedMood -and -not \$script:ForcedStage\) \{ Save-PetJson' -and
    $tokSrc -match 'if \(-not \$PlayOnly\) \{ Save-PetJson' -and $tokSrc -match '-and -not \$PlayOnly\) \{ Step-Scan' -and
    (Get-FnText $tokSrc 'Step-LiveUsage') -match '\$PlayOnly'
}
Check 'exact usage: off in the defaults, and the live poll runs only when it is exactly true' {
    (Get-FnText $tokSrc 'Step-LiveUsage') -match '\$script:Config\.LiveUsage -ne \$true' -and
    $tokSrc -match '\$live = if \(\$script:Config\.LiveUsage -eq \$true\) \{ \$script:LiveLimits \}'
}
Check 'exact usage (tok.ps1): the startup migration runs only for a real window, and a Settings item after Private mode saves the key and says the two lines for 6 s' {
    $mig = [regex]::Match($tokSrc, '(?ms)^if \(-not \$PlayOnly -and -not \$RenderDir -and -not \$Mood -and -not \$Stage\) \{.*?^\}').Value
    $mig -match 'Get-OldInstallPlan \$loaded' -and $mig -match 'Greeted = \$true' -and $mig -match "Set-ConfigFileKey 'LiveUsage' \`$true" -and
    $tokSrc -match "(?s)Add-MenuItem 'Private mode'.*?Add-MenuItem 'Exact usage' \{.*?Save-ConfigKey 'LiveUsage' \`$on.*?Okay\. I'll ask Anthropic every few``nminutes, with Claude Code's login\..*?Okay\. Back to Claude Code's own``nnumbers, and my guess\..*? 6 -Now.*?real numbers from Anthropic,``nwith Claude Code's own login"
}

Check 'only a real molt starts the piece from the state: Add-LiveLineage does, and nothing else calls Add-LineageReply' {
    # (-RenderDir builds a made-up three-generation tree of its own for the Family render; it never touches the state)
    $live = [regex]::Replace($tokSrc, '(?ms)^if \(\$RenderDir\) \{.*?^\}', '')
    $fn = Get-FnText $tokSrc 'Add-LiveLineage'
    $fn -match 'if \(\$molt -and @\(\$lin\.Generations\)\.Count -gt 1\)' -and $fn -match 'Start-Passing \$plan' -and ([regex]::Matches($live, '= Add-LineageReply')).Count -eq 1
}
Check 'the piece holds the old stage and blocks the look while it plays' {
    (Get-FnText $tokSrc 'Get-Stage') -match 'StageHold' -and (Get-FnText $tokSrc 'Update-Look') -match 'script:Passing' -and (Get-FnText $tokSrc 'Step-Eyes') -match 'script:Passing'
}
Check 'overlay XAML is well formed, and the elder flower is named in both sprouts' {
    $x = [xml](Get-PassingXaml)
    $names = @($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { ($_.Attributes | Where-Object LocalName -eq 'Name').Value })
    $sp = Get-SproutsXaml
    $names.Count -eq @($names | Select-Object -Unique).Count -and 'PSeed' -in $names -and 'PTop' -in $names -and 'PBot' -in $names -and 'PM21' -in $names -and $sp -match "x:Name='ElderFlower'" -and $sp -match "x:Name='ElderFlowerF'"
}
Check 'the piece runs 10 to 15 seconds' {
    $sum = { param($f, $rx) $body = [regex]::Match($passSrc, "(?ms)^function $f\b.*?^\}").Value; $m = [regex]::Match($body, $rx); ($m.Groups | Select-Object -Skip 1 | ForEach-Object { [double]$_.Value } | Measure-Object -Sum).Sum }
    $elder = & $sum 'Add-ElderPhase' '\$tG = ([\d.]+); \$tH = \$tG \+ ([\d.]+); \$dur = \$tH \+ ([\d.]+)'
    $young = & $sum 'Add-YoungPhase' '\$tE = ([\d.]+); \$dur = \$tE \+ ([\d.]+)'
    $hatch = & $sum 'Add-HatchPhase' '\$dur = ([\d.]+)'
    ($elder - 0 + $hatch) -ge 10 -and ($elder + $hatch) -le 15 -and ($young + $hatch) -ge 10 -and ($young + $hatch) -le 15
}

# ---- the pip (lib\Chime.ps1) and the sticker spinner
Check 'chime: both pips render as 16-bit mono WAVs under a second, the needs pip a little louder' {
    $n = [Tok.Chime]::Render($script:ChimeKinds.needs.Notes, $script:ChimeKinds.needs.Gap, $script:ChimeKinds.needs.Volume)
    $d = [Tok.Chime]::Render($script:ChimeKinds.done.Notes, $script:ChimeKinds.done.Gap, $script:ChimeKinds.done.Volume)
    $ok = foreach ($w in $n, $d) { [Text.Encoding]::ASCII.GetString($w, 0, 4) -eq 'RIFF' -and [BitConverter]::ToInt16($w, 22) -eq 1 -and [BitConverter]::ToInt16($w, 34) -eq 16 -and ($w.Length - 44) / 2 / 44100 -lt 1.0 }
    -not ($ok -contains $false) -and $script:ChimeKinds.needs.Volume -gt $script:ChimeKinds.done.Volume -and $script:ChimeKinds.needs.Volume -le 0.35
}
Check 'chime: the file is cached in the data folder, and an unknown kind gives nothing' {
    $f = Get-ChimeFile 'done'; $t = (Get-Item $f).LastWriteTimeUtc
    (Test-Path $f) -and $f -like "$script:DataDir*" -and (Get-Item (Get-ChimeFile 'done')).LastWriteTimeUtc -eq $t -and $null -eq (Get-ChimeFile 'nope')
}
Check 'chime: quiet hours wrap past midnight, and equal hours mean none' {
    (Test-QuietHour 23 23 7) -and (Test-QuietHour 2 23 7) -and -not (Test-QuietHour 7 23 7) -and -not (Test-QuietHour 12 23 7) -and
    (Test-QuietHour 13 12 14) -and -not (Test-QuietHour 14 12 14) -and -not (Test-QuietHour 3 5 5) -and -not (Test-QuietHour 3 $null 7)
}
Check 'chime: Sound off, quiet hours and a short gap keep it quiet; a needs pip may follow a done pip after 3 s' {
    $c = @{ Sound = $true; QuietFrom = 23; QuietTo = 7 }; $noon = [datetime]'2026-10-09 12:00'; $u = [datetime]'2026-10-09 17:00:00'
    (Test-ChimeOk $c 'done' $noon ([datetime]::MinValue) $u) -and
    -not (Test-ChimeOk @{ Sound = $false } 'done' $noon ([datetime]::MinValue) $u) -and
    -not (Test-ChimeOk $c 'needs' ([datetime]'2026-10-09 23:30') ([datetime]::MinValue) $u) -and
    -not (Test-ChimeOk $c 'done' $noon $u.AddSeconds(-10) $u 'done') -and (Test-ChimeOk $c 'done' $noon $u.AddSeconds(-16) $u 'done') -and
    (Test-ChimeOk $c 'needs' $noon $u.AddSeconds(-4) $u 'done') -and -not (Test-ChimeOk $c 'needs' $noon $u.AddSeconds(-4) $u 'needs')
}
Check 'chime: it pips for a question or plan, a long turn done and a say.ps1 message (not -Silent), and play-only windows stay silent' {
    $tokSrc -match "Invoke-NeedsYou\s+Invoke-Chime 'needs'" -and $tokSrc -match "if \(\`$end\.Pip -eq 'done'\) \{ Invoke-Chime 'done' -DelayMs" -and $tokSrc -match "elseif \(\`$end\.Pip\) \{ Invoke-Chime \`$end\.Pip \}" -and
    (Get-FnText $tokSrc 'Read-Inbox') -match "if \(-not \`$m\.silent\) \{ Invoke-Chime 'done' \}" -and (Get-FnText (Get-Content (Join-Path $root 'lib\Chime.ps1') -Raw) 'Invoke-Chime') -match '\$PlayOnly -and -not \$Force' -and
    (Get-BodyConfig).Sound -ne $null
}
Check 'spinner: the drop and the thin edge follow the face glyph, and the motion animates the face' {
    $x = [xml]"<Canvas xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>$(Get-PropsXaml)</Canvas>"
    $paths = @($x.SelectNodes('//*[@*[local-name()="Name"]="Spark"]/*'))
    $names = $paths | ForEach-Object { ($_.Attributes | Where-Object LocalName -eq 'Name').Value }
    ($names -join ',') -eq 'SparkDrop,SparkLine,SparkFace' -and @($paths | Where-Object { $_.Data -eq '{Binding Data, ElementName=SparkFace}' }).Count -eq 2 -and
    (Get-FnText $tokSrc 'Start-Motion') -match 'SparkFace\.BeginAnimation\(\$data' -and $tokSrc -notmatch 'SparkText'
}

# ---- the edges (session 4): what the transcript parser says now
# The wording is Claude Code's own, copied from a real transcript (a declined tool).
$declined = "The user doesn't want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file). To tell you how to proceed, the user said:"
$declLine = '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"' + $declined + ' no thanks","is_error":true,"tool_use_id":"t9"}]},"toolUseResult":"Error: ' + $declined + '"}'
Check 'edges: a declined tool is not an error (the fast path)' { @(ConvertTo-BodyEvents $declLine).Count -eq 0 }
Check 'edges: any other tool error still is' { @(ConvertTo-BodyEvents '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"Exit code 1","is_error":true,"tool_use_id":"t8"}]}}').Type -eq 'Ouch' }
$slowDecl = '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t7","is_error":true,"content":[{"type":"text","text":"' + $declined + '"}]}]},"x":{"type":"assistant"}}'
$slowErr = $slowDecl -replace [regex]::Escape($declined), 'boom'
Check 'edges: a declined tool is not an error (the full parse, text blocks) and a real error is' { @(ConvertTo-BodyEvents $slowDecl).Count -eq 0 -and @(ConvertTo-BodyEvents $slowErr).Type -eq 'Ouch' }
Check 'edges: the declined wording is matched as Claude Code writes it' { (Test-DeclinedText $declined) -and -not (Test-DeclinedText 'Exit code 1') -and -not (Test-DeclinedText '') }
Check 'edges: Esc becomes an Interrupt, never a Prompt (a text block, with or without "for tool use", or a plain string)' {
    $a = @(ConvertTo-BodyEvents '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}')
    $b = @(ConvertTo-BodyEvents '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}')
    $c = @(ConvertTo-BodyEvents '{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}')
    $a.Count -eq 1 -and $a[0].Type -eq 'Interrupt' -and $b.Count -eq 1 -and $b[0].Type -eq 'Interrupt' -and $c.Count -eq 1 -and $c[0].Type -eq 'Interrupt'
}
Check 'edges: only a line that starts with it is an interrupt' {
    $p = @(ConvertTo-BodyEvents '{"type":"user","message":{"role":"user","content":"what does [Request interrupted by user] mean in the log?"}}')
    $p.Count -eq 1 -and $p[0].Type -eq 'Prompt' -and (Test-InterruptText '[Request interrupted by user]') -and -not (Test-InterruptText 'hello')
}
$cwd = '{"cwd":"C:\\Users\\x\\sample-game",'
$pe = @(ConvertTo-BodyEvents ('{"type":"user","message":{"role":"user","content":"hello"}}' -replace '^\{', $cwd))
$de = @(ConvertTo-BodyEvents ((Line '2026-10-05T01:00:00Z' 'msg_q' 1 0 'claude-opus-5-5' '[{"type":"text","text":"ok"}]' 'end_turn') -replace '^\{', $cwd))
Check 'edges: a prompt and the end of a turn carry the project' { $pe[0].Type -eq 'Prompt' -and $pe[0].Project -eq 'sample-game' -and ($de | Where-Object Type -eq 'Done').Project -eq 'sample-game' }

# ---- the edges (session 4): the rules, pure
$sh = Get-TurnEndPlan $false $false 'tok'; $shE = Get-TurnEndPlan $false $true 'tok'
$ln = Get-TurnEndPlan $true $false 'tok'; $le = Get-TurnEndPlan $true $true 'tok'
Check 'turn end: a short turn is a settle squish and nothing else (even one that ended on an error)' {
    $sh.Kind -eq 'short' -and $sh.Squish -and -not $sh.Hop -and $sh.Text -eq '' -and $sh.Pip -eq '' -and $shE.Kind -eq 'short' -and $shE.Text -eq '' -and $shE.Pip -eq '' -and -not $shE.Hop
}
Check 'turn end: a long turn hops, says "All yours." under its project, and gets the done pip' {
    $ln.Kind -eq 'clean' -and $ln.Hop -and -not $ln.Squish -and $ln.Text -eq "All yours.`n(tok)" -and $ln.Pip -eq 'done'
}
Check 'turn end: a long turn that ended on an error does not hop, says so, and gets the falling pip' {
    $le.Kind -eq 'error' -and -not $le.Hop -and $le.Squish -and $le.Text -eq "Ended on an error. All yours.`n(tok)" -and $le.Pip -eq 'doneerr'
}
Check 'turn end: no project, or private mode, leaves the project line out' {
    (Get-TurnEndPlan $true $false '').Text -eq 'All yours.' -and (Get-TurnEndPlan $true $false 'tok' $true).Text -eq 'All yours.' -and (Get-TurnEndPlan $true $true 'tok' $true).Text -eq 'Ended on an error. All yours.'
}
$t0 = [datetime]::new(2026, 10, 9, 20, 0, 0, [DateTimeKind]::Utc)
Check 'errors: one alone is nothing; two within 60 s are weather, at most once per 60 s' {
    -not (Test-ErrorBurst ([datetime]::MinValue) $t0 ([datetime]::MinValue)) -and
    (Test-ErrorBurst $t0.AddSeconds(-30) $t0 ([datetime]::MinValue)) -and (Test-ErrorBurst $t0.AddSeconds(-60) $t0 ([datetime]::MinValue)) -and
    -not (Test-ErrorBurst $t0.AddSeconds(-61) $t0 ([datetime]::MinValue)) -and
    -not (Test-ErrorBurst $t0.AddSeconds(-5) $t0 $t0.AddSeconds(-30)) -and (Test-ErrorBurst $t0.AddSeconds(-5) $t0 $t0.AddSeconds(-61))
}
Check 'waiting: on him for 30 minutes at most, and the hover line counts whole minutes ("<1" first)' {
    -not (Test-Waiting $null $t0) -and (Test-Waiting $t0.AddMinutes(-29) $t0) -and -not (Test-Waiting $t0.AddMinutes(-31) $t0) -and
    (Get-WaitingText $t0.AddSeconds(-20) $t0) -ceq 'Waiting on you, <1 min · ' -and (Get-WaitingText $t0.AddSeconds(-190) $t0) -ceq 'Waiting on you, 3 min · ' -and
    (Get-WaitingText $null $t0) -eq '' -and (Get-WaitingText $t0.AddMinutes(-40) $t0) -eq ''
}
Check 'waiting: Claude moving on (a later tool that is not the question, or the end of the turn) clears it; the question itself does not' {
    -not (Test-WaitingAnswered $null $t0 'Edit') -and -not (Test-WaitingAnswered $t0.AddSeconds(-1) $t0 'Edit') -and (Test-WaitingAnswered $t0.AddSeconds(-3) $t0 'Edit') -and
    -not (Test-WaitingAnswered $t0.AddSeconds(-30) $t0 'AskUserQuestion') -and -not (Test-WaitingAnswered $t0.AddSeconds(-30) $t0 'ExitPlanMode') -and (Test-WaitingAnswered $t0.AddSeconds(-30) $t0)
}
Check 'reading: two sweeps of three jumps (x -3, 0, +3; y +1 then +2.5) in a second, then nothing' {
    $at = { param($t) $p = Get-ReadSweepPos $t; "$($p[0]),$($p[1])" }
    (& $at 0.05) -eq '-3,1' -and (& $at 0.25) -eq '0,1' -and (& $at 0.4) -eq '3,1' -and (& $at 0.55) -eq '-3,2.5' -and (& $at 0.75) -eq '0,2.5' -and (& $at 0.95) -eq '3,2.5' -and
    $null -eq (Get-ReadSweepPos 1.0) -and $null -eq (Get-ReadSweepPos 3) -and $null -eq (Get-ReadSweepPos -0.1) -and $script:ReadSweepSeconds -eq 1.0
}
Check 'reading: at most once per 20 s, only with the eyes showing and no other look on' {
    (Test-ReadSweepOk ([datetime]::MinValue) $t0 $true $false) -and (Test-ReadSweepOk $t0.AddSeconds(-20) $t0 $true $false) -and -not (Test-ReadSweepOk $t0.AddSeconds(-19) $t0 $true $false) -and
    -not (Test-ReadSweepOk ([datetime]::MinValue) $t0 $false $false) -and -not (Test-ReadSweepOk ([datetime]::MinValue) $t0 $true $true)
}
Check 'the nod: after two or more reads, once a minute at most' {
    (Test-Nod 2 ([datetime]::MinValue) $t0) -and (Test-Nod 5 $t0.AddSeconds(-60) $t0) -and -not (Test-Nod 1 ([datetime]::MinValue) $t0) -and -not (Test-Nod 0 ([datetime]::MinValue) $t0) -and -not (Test-Nod 3 $t0.AddSeconds(-59) $t0)
}
$wk = @{ Pct = 90.0; Reset = $t0.AddDays(2) }
Check 'week: warns at 90% once per week (keyed by the reset time, to the hour), not before, not after the reset' {
    $k = Test-WeekWarn $wk '' $t0
    $k -and -not (Test-WeekWarn $wk $k $t0) -and -not (Test-WeekWarn @{ Pct = 89.9; Reset = $t0.AddDays(2) } '' $t0) -and (Test-WeekWarn @{ Pct = 97; Reset = $t0.AddDays(2) } '' $t0) -eq $k -and
    -not (Test-WeekWarn @{ Pct = 95; Reset = $t0.AddDays(-1) } '' $t0) -and -not (Test-WeekWarn $null '' $t0) -and
    (Test-WeekWarn @{ Pct = 95; Reset = $t0.AddDays(2).AddSeconds(1) } '' $t0) -eq $k -and (Test-WeekWarn @{ Pct = 95; Reset = $t0.AddDays(9) } $k $t0) -ne $k
}
Check 'week: "Fri 9 AM" in local time, minutes only when there are some, and the line is the one the brief gives' {
    $fri = [datetime]::new(2026, 10, 9, 9, 0, 0, [DateTimeKind]::Local).ToUniversalTime()
    (Get-WeekResetText $fri) -eq 'Fri 9 AM' -and (Get-WeekResetText $fri.AddMinutes(30)) -eq 'Fri 9:30 AM' -and (Get-WeekWarnLine $fri) -eq "🏮 The week's at 90%. It resets Fri 9 AM."
}
Check 'fresh window: one wording, and a routine reset is silent unless the window was at least 85%' {
    (Get-FreshWindowLine) -eq '🌱 Fresh window. Nothing spent yet.' -and (Test-FreshWindowBubble 0.85) -and (Test-FreshWindowBubble 1.0) -and -not (Test-FreshWindowBubble 0.84) -and -not (Test-FreshWindowBubble 0.2)
}
Check 'quiet return: more than 6 hours since the last main event, not exactly 6' {
    (Test-QuietReturn $t0.AddHours(-7) $t0) -and (Test-QuietReturn $t0.AddHours(-6).AddSeconds(-1) $t0) -and -not (Test-QuietReturn $t0.AddHours(-6) $t0) -and -not (Test-QuietReturn $t0.AddMinutes(-30) $t0)
}
Check 'lines: late night, dream recall and the minion rule' {
    $late = [datetime]'2026-10-09 01:20'
    (Get-LateNightLine $late 'Sam') -eq "It's 1:20, Sam. Just noting it." -and (Get-LateNightLine $late '') -eq "It's 1:20. Just noting it." -and (Get-LateNightLine ([datetime]'2026-10-09 04:05') 'Sam') -eq "It's 4:05, Sam. Just noting it." -and
    (Get-DreamRecallLine 'a giant Bash') -eq '…I dreamt about a giant Bash.' -and
    -not (Test-MinionRanLong $t0.AddSeconds(-45) $t0) -and (Test-MinionRanLong $t0.AddSeconds(-46) $t0)
}
Check 'lines: sentence case, one ellipsis character, no em dashes, no asterisks, no fake yawns' {
    $all = @($sh.Text, $ln.Text, $le.Text, (Get-FreshWindowLine), (Get-WeekWarnLine $t0), (Get-LateNightLine ([datetime]'2026-10-09 01:20') 'Sam'), (Get-DreamRecallLine 'x'), (Get-WaitingText $t0.AddMinutes(-2) $t0))
    @($all | Where-Object { $_ -match '\.\.\.|—|\*|yawn' }).Count -eq 0
}
Check 'grammar: the pure lines start with a capital (after any emoji or symbol), with one ellipsis character, no em dashes and no double spaces' {
    $gd = New-AgedState 34 14; $gt = Get-Today $gd; $gt.Tools['Bash'] = 41; $gt.Errors = 2; $gt.Prompts = 5; $gd.Comas = 1
    $gr = [System.Random]::new(11); $texts = [System.Collections.Generic.List[string]]::new()
    foreach ($i in 1..80) { $texts.Add((Get-Dream $gd @() $gr).Text) }
    foreach ($n in 'Edit', 'Read', 'Bash', 'Grep', 'WebFetch', 'Agent', 'AskUserQuestion', 'ExitPlanMode', 'Other') { $texts.Add((Get-PrivateToolLine $n)) }
    foreach ($s in (Get-StatsText $gd $null), (Get-TodayText $gd), (Get-FamilyText $gd.Lineage $gd.BornUtc), (Get-FreshWindowLine), (Get-WeekWarnLine $t0), (Get-MoltPill 'weird')) { $texts.Add($s) }
    @($texts | ForEach-Object { $_ -split "`n" } | Where-Object { $_ -cmatch '^[^\p{L}\p{N}]*\p{Ll}' -or $_ -match '\.\.\.|—|\S {2,}\S' }).Count -eq 0 -and (Get-HatchLine 'Tok II') -ceq "Hello! I'm Tok II."
}
Check 'the day counts: the 10th main reply of a local day for a version, once per day' {
    $dl = New-Lineage; $dk = $d0.ToString('yyyy-MM-dd'); $hits = @(); $last = ''
    for ($i = 0; $i -lt 12; $i++) {
        $null = Add-LineageReply $dl 'claude-opus-5-5' $d0.AddMinutes($i).ToUniversalTime() 10 'tok'
        $c = Get-ReplyDayCount $dl 'claude-opus-5-5' $dk
        if (Test-DayJustCounted $c $dk $last) { $hits += $c; $last = $dk }
    }
    (Get-ReplyDayCount $dl 'claude-sonnet-5-5' $dk) -eq 12 -and (Get-ReplyDayCount $dl 'claude-opus-6' $dk) -eq 0 -and (Get-ReplyDayCount $dl 'weird' $dk) -eq 0 -and (Get-ReplyDayCount $dl 'claude-opus-5-5' '2000-01-01') -eq 0 -and
    ($hits -join ',') -eq '10' -and -not (Test-DayJustCounted 10 $dk $dk) -and (Test-DayJustCounted 10 '2026-09-21' $dk) -and -not (Test-DayJustCounted 11 $dk '')
}
Check 'art: the ouch pose has no red and no mark, and still squeezes its eyes for the demos' {
    $o = Get-Pose 'ouch'
    $artSrc = Get-Content (Join-Path $root 'lib\Art.ps1') -Raw
    $o.Fx -eq '' -and $o.Eyes -eq 'squeeze' -and $o.Mouth -eq 'path' -and $artSrc -notmatch '#FFD04030'
}
Check 'art: the sprout can stretch from its base (a scale at the stem foot, beside the sway)' {
    $x = [xml]('<Canvas xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">' + (Get-CreatureXaml) + '</Canvas>')
    $ns = [Xml.XmlNamespaceManager]::new($x.NameTable); $ns.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    $sc = $x.SelectSingleNode('//w:ScaleTransform[@*[local-name()="Name"]="SproutScale"]', $ns)
    $sc -and $sc.CenterX -eq '70' -and $sc.CenterY -eq '48' -and $sc.ParentNode.ParentNode.ParentNode.LocalName -eq 'Canvas' -and $x.SelectSingleNode('//w:RotateTransform[@*[local-name()="Name"]="SproutRot"]', $ns)
}
Check 'art: the wake pill reads at 12 px in a 20 px pill' {
    $x = [xml]"<Canvas xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>$(Get-PropsXaml)</Canvas>"
    $ns = [Xml.XmlNamespaceManager]::new($x.NameTable); $ns.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    $pill = $x.SelectSingleNode('//w:Border[@*[local-name()="Name"]="WakePill"]', $ns); $txt = $x.SelectSingleNode('//w:TextBlock[@*[local-name()="Name"]="WakeText"]', $ns)
    $pill.Height -eq '20' -and $pill.CornerRadius -eq '10' -and $txt.FontSize -eq '12'
}
$chimeSrc = Get-Content (Join-Path $root 'lib\Chime.ps1') -Raw
Check 'pips: four kinds, the cache is version 2, and the needs gap is 0.10 s so its top note meets the hop apex' {
    ($script:ChimeKinds.Keys | Sort-Object) -join ',' -eq 'done,doneerr,needs,wake' -and $script:ChimeVersion -eq 2 -and $script:ChimeKinds.needs.Gap -eq 0.10 -and
    [math]::Abs($script:ChimeKinds.needs.Gap * 2 - (Get-HopSpec 'adult' $true).RiseMs / 1000) -lt 0.03 -and
    (Get-ChimeFile 'wake') -like '*wake-v2.wav' -and (Get-ChimeFile 'doneerr') -like '*doneerr-v2.wav'
}
Check 'pips: doneerr is the done pair falling (C6 then G5) and wake is the octave C5 then C6, both at the done volume' {
    $d = $script:ChimeKinds.done; $e = $script:ChimeKinds.doneerr; $w = $script:ChimeKinds.wake
    $e.Notes[0] -eq 1046.50 -and $e.Notes[1] -eq 783.99 -and $e.Gap -eq 0.085 -and $e.Volume -eq 0.22 -and $d.Notes[0] -eq $e.Notes[1] -and $d.Notes[1] -eq $e.Notes[0] -and
    $w.Notes[0] -eq 523.25 -and $w.Notes[1] -eq 1046.50 -and $w.Gap -eq 0.12 -and $w.Volume -eq 0.22 -and [math]::Abs($w.Notes[1] / $w.Notes[0] - 2) -lt 0.001
}
Check 'pips: the family rules hold for every kind (notes from C, E, G only; at most 3; under 0.6 s; quiet; a valid WAV)' {
    $ok = $true
    foreach ($kind in $script:ChimeKinds.Keys) {
        $k = $script:ChimeKinds[$kind]
        foreach ($f in $k.Notes) { $pc = ([int][math]::Round(12 * [math]::Log($f / 261.6256, 2)) % 12 + 12) % 12; if ($pc -notin 0, 4, 7) { $ok = $false } }
        if ($k.Notes.Count -gt 3 -or ($k.Gap * ($k.Notes.Count - 1) + 0.35) -ge 0.6 -or $k.Volume -gt 0.35) { $ok = $false }       # a note has rung out about 0.35 s after it starts
        $w = [Tok.Chime]::Render($k.Notes, $k.Gap, $k.Volume)
        if ([Text.Encoding]::ASCII.GetString($w, 0, 4) -ne 'RIFF' -or [BitConverter]::ToInt16($w, 22) -ne 1 -or [BitConverter]::ToInt16($w, 34) -ne 16 -or ($w.Length - 44) / 2 / 44100 -ge 1.0) { $ok = $false }
    }
    $ok
}
Check 'pips: Invoke-Chime can play later (-DelayMs, through the one-shot timer) and its checks run when it plays; the rules are in the header' {
    $fn = Get-FnText $chimeSrc 'Invoke-Chime'
    $fn -match '\[int\]\$DelayMs' -and $fn -match 'Start-Later \$DelayMs' -and $fn -match 'Invoke-Chime \$k -Force:\$f' -and $fn.IndexOf('Start-Later') -lt $fn.IndexOf('Test-ChimeOk') -and
    $chimeSrc -match 'notes from C, E and G only|Notes from C, E and G only' -and $chimeSrc -match 'under 0\.6 s' -and $chimeSrc -match 'No sound for bad news' -and $chimeSrc -match 'octave means refilled'
}
$bodyEvent = Get-FnText $tokSrc 'Invoke-BodyEvent'
# the eyes (10-10): every path in Step-Eyes that places the pupils itself, or finds the eyes shut, clears EyesKey, so the pointer is
# looked up again as soon as that look ends (it used to stay on the token's spot after a meal until the mouse moved)
$eyesFn = [regex]::Match($tokSrc, '(?ms)^function Step-Eyes \{.*?^\}').Value
$early = @($eyesFn -split "`n" | Where-Object { $_ -match '\breturn\b' -and $_ -notmatch "key -eq \`$script:EyesKey" })
Check 'eyes: every early return in Step-Eyes clears the pointer cache' { $early.Count -ge 6 -and @($early | Where-Object { $_ -notmatch 'EyesKey = \$null' -and $_.Trim() -ne 'return' }).Count -eq 0 }
$evCase = { param($name) [regex]::Match($bodyEvent, "(?ms)^        '$name' \{.*?^        \}").Value }       # one case of the event switch
Check 'turn end (tok.ps1): a short turn squishes, a long one hops and says it pinned for 12 s, the done pip lands on the hop, an error turn has no hop and the falling pip now' {
    $d = & $evCase 'Done'
    $d -match 'Get-TurnEndPlan \$long \$script:TurnErr' -and $d -match 'if \(\$end\.Squish\) \{ Invoke-Squish 0\.05 120 \}' -and $d -match 'if \(\$end\.Hop\) \{ Invoke-Hop \}' -and
    $d -match 'Say \$end\.Text 12 -Pin' -and $d -match "Invoke-Chime 'done' -DelayMs \(Get-HopSpec \(Get-Stage\)\.Name \`$false\)\.FallMs" -and $d -match 'elseif \(\$end\.Pip\) \{ Invoke-Chime \$end\.Pip \}' -and
    $d -notmatch "Set-Override 'love'" -and $d -notmatch "ta-da|done!" -and $d -match 'LastProject'
}
Check 'turn end (tok.ps1): a main Ouch marks the turn, a main Tool or Prompt clears it, and the Done event hands its project over' {
    (& $evCase 'Ouch') -match '\$script:TurnErr = \$true' -and (& $evCase 'Tool') -match '\$script:TurnErr = \$false' -and (& $evCase 'Prompt') -match '\$script:TurnErr = \$false' -and
    (& $evCase 'Tool') -match 'LastProject = \$E\.Project' -and (& $evCase 'Prompt') -match 'LastProject = \$E\.Project'
}
Check 'hook: a permission prompt is a needs-you that names the tool (short for a server, not when private)' {
    (Get-HookNeedsPlan 'permission_prompt' 'Claude needs your permission to use Bash' $false 3).Line -ceq "🔑 Claude Code asks:`nokay to use Bash?" -and
    (Get-HookNeedsPlan 'worker_permission_prompt' 'Claude needs your permission to use mcp__claude_ai_Gmail__send_message' $false 3).Line -ceq "🔑 Claude Code asks:`nokay to use Gmail?" -and
    (Get-HookNeedsPlan 'permission_prompt' 'Claude needs your permission to use Bash' $false 3 $true).Line -ceq "🔑 Claude Code asks:`nokay to go on?" -and
    (Get-HookNeedsPlan 'permission_prompt' 'something else' $false 3).Line -ceq "🔑 Claude Code asks:`nokay to go on?" -and
    @((Get-HookNeedsPlan 'permission_prompt' 'Claude needs your permission to use PowerShell' $false 3).Line -split "`n" | Where-Object { $_.Length -gt 33 }).Count -eq 0
}
Check 'hook: a server or a background agent asking is a question; the idle reminder and the rest are nothing' {
    (Get-HookNeedsPlan 'elicitation_dialog' 'x' $false 0).Line -eq '❓ A question for you' -and (Get-HookNeedsPlan 'agent_needs_input' 'x' $false 0).Line -eq '❓ A question for you' -and
    -not (Get-HookNeedsPlan 'idle_prompt' 'Claude is waiting for your input' $false 0) -and -not (Get-HookNeedsPlan 'auth_success' 'x' $false 0) -and -not (Get-HookNeedsPlan '' '' $false 0)
}
Check 'hook: nothing while Tok already waits on you, for its own question or plan, or for a stale line' {
    -not (Get-HookNeedsPlan 'permission_prompt' 'Claude needs your permission to use Bash' $true 3) -and
    -not (Get-HookNeedsPlan 'permission_prompt' 'Claude needs your permission to use AskUserQuestion' $false 3) -and
    -not (Get-HookNeedsPlan 'permission_prompt' 'Claude needs your permission to use ExitPlanMode' $false 3) -and
    -not (Get-HookNeedsPlan 'permission_prompt' 'Claude needs your permission to use Bash' $false 121)
}
Check 'hook (tok.ps1): the inbox hands needs lines over; a yes to the tool ends the wave like an answer does' {
    $ri = Get-FnText $tokSrc 'Read-Inbox'; $hn = Get-FnText $tokSrc 'Invoke-HookNeeds'; $tc = & $evCase 'Tool'
    $ri -match "if \(\`$m\.cmd -eq 'needs'\) \{ Invoke-HookNeeds \`$m; continue \}" -and
    $hn -match 'Get-HookNeedsPlan "\$\(\$M\.kind\)" "\$\(\$M\.message\)" \(Test-Waiting \$script:WaitingSince \$now\) \$age \$private' -and
    $hn -match 'Invoke-NeedsYou' -and $hn -match "Invoke-Chime 'needs'" -and $hn -match '\$script:WaitingSince = \$now' -and $hn -match 'Say \$line 20 -Pin' -and $hn -match 'Get-ProjectTag' -and
    $tc -match "(?s)Test-WaitingAnswered \`$script:WaitingSince \`$now \`$E\.Name\).*?if \(\`$script:Override -eq 'needs'\) \{ \`$script:Override = \`$null; Update-Look \`$script:Mood \}"
}
Check 'hook (notify.ps1): one inbox line from stdin, the data folder override honoured, never a failing exit' {
    $hd = Join-Path ([IO.Path]::GetTempPath()) "tok-hook-$PID"
    $old = $env:TOK_DATA_DIR; $env:TOK_DATA_DIR = $hd
    try {
        '{"session_id":"s","transcript_path":"C:\\x\\t.jsonl","cwd":"C:\\x","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}' |
            pwsh -NoProfile -File (Join-Path $root 'notify.ps1'); $code = $LASTEXITCODE
        'not json' | pwsh -NoProfile -File (Join-Path $root 'notify.ps1'); $bad = $LASTEXITCODE
        $l = @(Get-Content (Join-Path $hd 'inbox.jsonl'))
        $m = $l[0] | ConvertFrom-Json
        $code -eq 0 -and $bad -eq 0 -and $l.Count -eq 1 -and $m.cmd -eq 'needs' -and $m.kind -eq 'permission_prompt' -and $m.message -match 'use Bash' -and $m.transcript -eq 'C:\x\t.jsonl'
    } finally { $env:TOK_DATA_DIR = $old; Remove-Item $hd -Recurse -Force -ErrorAction SilentlyContinue }
}
Check 'breathing: the rest between awake breaths is 2.5 to 4.5 s' { (Get-BreathRest 0) -eq 2.5 -and (Get-BreathRest 0.5) -eq 3.5 -and (Get-BreathRest 0.999) -lt 4.5 -and (Get-BreathRest 7) -eq 4.5 -and (Get-BreathRest -1) -eq 2.5 }
Check 'breathing (tok.ps1): awake idle breathes once and rests; the breath stops at its end and the sprout is left alone during the set piece' {
    $sb = Get-FnText $tokSrc 'Start-Breath'; $sm = Get-FnText $tokSrc 'Start-Motion'
    $sm -match "default \{ Start-Breath \}" -and $sm -match "if \(\`$kind -notin 'rest', 'sleep'\) \{ \`$script:BreathTimer\.Stop\(\) \}" -and
    $sb -notmatch 'Forever' -and ([regex]::Matches($sb, 'FillBehavior\]::Stop')).Count -eq 2 -and $sb -match "if \(\`$script:MotionKind -notin 'rest', 'sleep'\) \{ return \}" -and
    $sb -match 'if \(-not \$script:Passing\)' -and $sb -match 'FromSeconds\(2 \* \$secs \+ ' -and $sb -match 'Get-BreathRest \$script:Rng\.NextDouble\(\) \}' -and $sb -match 'DoubleAnimation\]::new\(0, -\$amp, \[TimeSpan\]::FromSeconds\(\$secs\)\)' -and $sb -match '\$secs = if \(\$asleep\) \{ 2\.8 \} else \{ 1\.6 \}; \$amp = if \(\$asleep\) \{ 1\.2 \} else \{ 2\.5 \}'
}
Check 'breathing: asleep rests 4 to 7 s between slow breaths at 5 fps; the nightcap keeps its continuous breath' {
    $sb = Get-FnText $tokSrc 'Start-Breath'; $sm = Get-FnText $tokSrc 'Start-Motion'
    (Get-BreathRest 0 4 3) -eq 4 -and (Get-BreathRest 0.5 4 3) -eq 5.5 -and (Get-BreathRest 7 4 3) -eq 7 -and
    $sm -match "'sleep' \{ Start-Breath \}" -and $sm -match "'coma'  \{ Start-Bob 3\.5 1 -Fps 5" -and $sb -match '\$fps = if \(\$asleep\) \{ 5 \} else \{ 0 \}' -and $sb -match 'Get-BreathRest \$script:Rng\.NextDouble\(\) 4 3'
}
Check 'cuts (session 7): no first-bite cheer, no asterisk stage directions, no zoom shake; the tour has no (tok) under All yours. and no Half the window.' {
    $lib = Get-Content (Join-Path $root 'lib\Lineage.ps1') -Raw
    $tokSrc -notmatch 'First bite|FirstBite|\*perks up\*|\*crack\*|-Shake|Half the window' -and $lib -notmatch 'FirstBite|\*crack\*' -and
    $tokSrc -match "Get-TurnEndPlan \`$true \`$false '' \`$false" -and ((Get-TurnEndPlan $true $false '' $false).Text -ceq 'All yours.') -and
    (Get-FnText $tokSrc 'Start-Bob') -notmatch 'FromMilliseconds' -and $tokSrc -match "'zoom'  \{ Start-Bob 0\.16 3; "
}
Check 'tour minion lines (session 7): one sentence names the helpers, no seed emoji, and no (tok) tag anywhere in the tour' {
    $tour = $tokSrc.Substring($tokSrc.IndexOf('$script:ShowPlan = @('))
    $tour = $tour.Substring(0, $tour.IndexOf('$window.Close()'))
    $tokSrc -match [regex]::Escape("Say 'Each subagent is a helper seed. A Haiku.' 2 -Now") -and $tokSrc -match [regex]::Escape("Say 'A Fable. They orbit while they work.' 3.5 -Now") -and
    $tour -notmatch '🐣|\(tok\)'
}
Check 'project tag (tok.ps1): events get the session''s start folder, and needs-you and the turn end tag only when it tells sessions apart' {
    (Get-FnText $tokSrc 'Step-Life') -match 'ConvertTo-BodyEvents \$l\.Line \$l\.Sub \$l\.Cwd' -and (Get-FnText $tokSrc 'Get-LiveProjects') -match 'LiveCwds\(15\)' -and
    (& $evCase 'Tool') -match '\$tag = Get-ProjectTag \$E\.Project \(Get-LiveProjects\)' -and (& $evCase 'Tool') -match 'if \(\$tag -and -not \$private\) \{ \$line \+= "`n\(\$tag\)" \}' -and
    (& $evCase 'Done') -match 'Get-TurnEndPlan \$long \$script:TurnErr \(Get-ProjectTag "\$proj" \(Get-LiveProjects\)\)'
}
Check 'errors are weather (tok.ps1): every error is counted, only two within 60 s show the rethink look, and the ouch face is never shown live' {
    $o = & $evCase 'Ouch'
    $o -match 'Errors\+\+' -and $o -match 'Test-ErrorBurst \$script:ErrPrev \$now \$script:ErrRethink' -and $o -match "Set-Override 'rethink' 1\.6" -and $o -notmatch "Set-Override 'ouch'" -and
    ([regex]::Matches($tokSrc, "Set-Override 'ouch'")).Count -eq 0       # the tour shows the rethink now, not the ouch
}
Check 'compaction (tok.ps1): the dizzy stays and Tok says it kept the gist (Low)' {
    $c = & $evCase 'Compact'
    $c -match "Set-Override 'dizzy' 2\.5" -and $c -match "Say 'Chat compacted\. I kept the gist\.' 3\.5 -Low"
}
Check 'interrupt (tok.ps1): Esc closes the turn, backdates the last event, clears the wave and the waiting flag, squishes, and says nothing' {
    $i = & $evCase 'Interrupt'
    $i -match '\$script:TurnOpen = \$false' -and $i -match '\$script:LastEvent = \$now\.AddSeconds\(-30\)' -and $i -match "Override -eq 'needs'" -and $i -match '\$script:WaitingSince = \$null' -and
    $i -match 'Invoke-Squish 0\.05 120' -and $i -match 'Update-Look \$script:Mood' -and $i -notmatch 'Say |Invoke-Chime'
}
Check 'interrupt: backdating the last event by 30 s with the turn closed ends the busy look at once (and keeps Tok able to sleep)' {
    $sp = New-PetState; $sp.Xp = 1000
    $w = Get-WatchSeconds $t0.AddSeconds(-30) $false @() $t0
    (Get-PetMood $sp 0.1 0 0) -eq 'busy' -and (Get-PetMood $sp 0.1 30 $w) -eq 'happy' -and (Get-PetMood $sp 0.1 700 700) -eq 'sleep'
}
Check 'waiting (tok.ps1): a question or plan pins its bubble for 20 s (the wave runs 20), keeps the needs pip, and starts the wait' {
    $tc = & $evCase 'Tool'
    $tc -match "(?s)AskUserQuestion', 'ExitPlanMode'.*?Invoke-Wave|AskUserQuestion', 'ExitPlanMode'.*?Invoke-NeedsYou" -and $tc -match '\$script:WaitingSince = \$now\s+Say \$line 20 -Pin' -and $tc -match "Invoke-Chime 'needs'" -and $tc -notmatch 'Say \$line 8 -Pin' -and
    (Get-FnText $tokSrc 'Invoke-NeedsYou') -match 'Invoke-Wave 20'
}
Check 'waiting (tok.ps1): your next prompt, an Esc, Claude moving on, or 30 minutes end it' {
    (& $evCase 'Prompt') -match '\$script:WaitingSince = \$null' -and (& $evCase 'Interrupt') -match '\$script:WaitingSince = \$null' -and (& $evCase 'Done') -match 'Test-WaitingAnswered \$script:WaitingSince \$now' -and
    (& $evCase 'Tool') -match 'Test-WaitingAnswered \$script:WaitingSince \$now \$E\.Name' -and (Get-FnText $tokSrc 'Step-Life') -match 'Test-Waiting \$script:WaitingSince \$now'
}
Check 'waiting (tok.ps1): the eyes sit on him, still, while it lasts and no other look is on, and the fast loop is not asked for it' {
    $se = Get-FnText $tokSrc 'Step-Eyes'; $nf = Get-FnText $tokSrc 'Test-NeedsFastTick'
    $se -match 'Test-Waiting \$script:WaitingSince \$now' -and $se -match '(?s)Test-Waiting \$script:WaitingSince \$now\)\) \{\s+\$ui\.PupilL\.X = 0; \$ui\.PupilL\.Y = -1; \$ui\.PupilR\.X = 0; \$ui\.PupilR\.Y = -1' -and
    $se.IndexOf('Test-Waiting') -lt $se.IndexOf('Invoke-Blink') -and $nf -notmatch 'Waiting'
}
Check 'waiting (tok.ps1): the hover line starts with how long it has been waiting' {
    $tokSrc -match '\$window\.ToolTip\.Content = "\$\(Get-WaitingText \$script:WaitingSince \(\[datetime\]::UtcNow\)\)\$name · '
}
Check 'fresh window (tok.ps1): after a real limit the one line, pinned 6 s, with the wake pip; a routine reset speaks only if the window was nearly full (4 s, not pinned) and never pips' {
    $sl = Get-FnText $tokSrc 'Step-Life'; $wr = Get-FnText $tokSrc 'Test-WindowReset'
    $noTour = [regex]::Replace($tokSrc, '(?ms)^\s+\$script:ShowPlan = @\(.*?^\s+\)\s*$', '')      # the tour plays the wake pip with its own reset
    $sl -match 'Invoke-Reset; Invoke-Hop' -and $sl -match 'Say \(Get-FreshWindowLine\) 6 -Pin' -and $sl -match "Invoke-Chime 'wake'" -and
    $wr -match 'Invoke-Reset; Invoke-Hop' -and $wr -match 'if \(Test-FreshWindowBubble \$script:LastResetPct\) \{ Say \(Get-FreshWindowLine\) 4 \}' -and $wr -notmatch 'Invoke-Chime|-Pin' -and
    ([regex]::Matches($noTour, "Invoke-Chime 'wake'")).Count -eq 1 -and $noTour.Length -lt $tokSrc.Length - 3000 -and $tokSrc -notmatch 'fresh window!|fresh 5-hour window|the lantern is empty again'
}
Check 'fresh window (tok.ps1): the fullness is remembered while the window is open, so the reset sees how full it was (not the new window)' {
    $wr = Get-FnText $tokSrc 'Test-WindowReset'
    $wr -match '\$w\.Active -and \$w\.Reset -gt \$now\) \{ \$script:LastReset = \$w\.Reset; \$script:LastResetPct = \$w\.Pct \}' -and $wr.IndexOf('Test-FreshWindowBubble') -lt $wr.IndexOf('script:LastResetPct = $w.Pct')
}
Check 'reading (tok.ps1): a main Read, Grep or Glob counts and starts the sweep; it needs the eyes showing, no other look, and 20 s since the last' {
    $tc = & $evCase 'Tool'; $rs = Get-FnText $tokSrc 'Start-ReadSweep'
    $tc -match "if \(\`$E\.Name -in 'Read', 'Grep', 'Glob'\) \{ \`$script:ReadsSinceEdit\+\+; Start-ReadSweep \}" -and $tc.IndexOf('if ($E.Sub) { return }') -lt $tc.IndexOf('Start-ReadSweep') -and
    $rs -match "Test-ReadSweepOk \`$script:LastSweep \`$now \(\`$ui\.EyeL\.Visibility -eq 'Visible'\) \`$other" -and $rs -match 'script:Override -and \$now -lt \$script:OverrideUntil' -and $rs -match '\$script:ReadSweep = @\{ Start = \$now \}'
}
Check 'reading (tok.ps1): Step-Eyes plays the sweep from the flag and lets go of it; the fast loop wants it only while it runs' {
    $se = Get-FnText $tokSrc 'Step-Eyes'; $nf = Get-FnText $tokSrc 'Test-NeedsFastTick'
    $se -match 'if \(\$script:ReadSweep\)' -and $se -match 'Get-ReadSweepPos \(\(\$now - \$script:ReadSweep\.Start\)\.TotalSeconds\)' -and $se -match '\$script:ReadSweep = \$null' -and $se.IndexOf('ReadSweep') -lt $se.IndexOf('Invoke-Blink') -and
    $nf -match '\$script:ReadSweep -and \(\[datetime\]::UtcNow - \$script:ReadSweep\.Start\)\.TotalSeconds -lt \$script:ReadSweepSeconds' -and $script:ReadSweepSeconds -le 1.1
}
Check 'the nod (tok.ps1): an edit after two reads dips the lean 6 degrees further forward and back, from its current angle, then lets the lean go back; the squish stays' {
    $tc = & $evCase 'Tool'; $nod = Get-FnText $tokSrc 'Invoke-Nod'
    $tc -match 'Invoke-Squish 0\.08 110' -and $tc -match 'Test-Nod \$script:ReadsSinceEdit \$script:LastNod \$now' -and $tc -match 'script:LastNod = \$now; Invoke-Nod' -and $tc -match '\$script:ReadsSinceEdit = 0' -and
    $nod -match '\$from = \$ui\.Lean\.Angle' -and $nod -match '\$from - 6' -and $nod -match 'FromMilliseconds\(160\)' -and $nod -match 'AutoReverse = \$true' -and $nod -match 'FillBehavior\]::Stop' -and $nod -match 'ui\.Lean\.BeginAnimation'
}
Check 'the day counts (tok.ps1): the 10th reply flags it once per day; the sprout stretches 1 to 1.08 over 1.2 s from its foot with a gold ✦ for 1.2 s, no bubble, no pip, and not on a growing-up or a molt' {
    $al = Get-FnText $tokSrc 'Add-LiveLineage'; $ds = Get-FnText $tokSrc 'Start-DayStretch'; $us = & $evCase 'Usage'
    $al -match 'Test-DayJustCounted \(Get-DayTotal \$lin \$dk\) \$dk \$script:LastDayKey' -and $al -match '\$script:DayCounted = -not \$molt' -and
    $us -match 'if \(\$script:DayCounted\)' -and $us -match '-not \$grew -and -not \$script:Passing' -and $us -match 'Start-DayStretch' -and
    $ds -match 'ui\.SproutScale\.BeginAnimation' -and $ds -match '\(1, 1\.08, \[TimeSpan\]::FromMilliseconds\(600\)\)' -and $ds -match 'AutoReverse = \$true' -and $ds -match "Show-Fx '✦' '#FFE0A030'" -and $ds -match 'AddMilliseconds\(1200\)' -and $ds -notmatch 'Say |Invoke-Chime' -and
    ($ds -split "`n" | Where-Object { $_ -match 'Say |Invoke-Chime' }).Count -eq 0
}
Check 'the day counts (tok.ps1): Update-Look holds the ✦ in the Fx slot while the hold lasts, then the face''s own mark returns' {
    $tokSrc -match "if \(\[datetime\]::UtcNow -lt \`$script:FxHoldUntil\) \{ Show-Fx '✦' '#FFE0A030' \} else \{ Show-Fx \`$p\.Fx \`$p\.FxColor \}" -and (Get-FnText $tokSrc 'Start-DayStretch') -match 'Start-Later 1250 \{ Update-Look \$script:Mood \}'
}
Check 'the week (tok.ps1): checked with the window, once per week by key (saved in the state), pinned 6 s, no pip' {
    $wf = Get-FnText $tokSrc 'Test-WeekWarning'
    (Get-FnText $tokSrc 'Step-Life') -match '(?s)Test-WindowReset\s+Test-WeekWarning' -and $wf -match 'Test-WeekWarn \$w\.Week "\$\(\$script:State\.WeekWarnKey\)"' -and $wf -match '\$script:State\.WeekWarnKey = \$key' -and
    $wf -match 'Say \(Get-WeekWarnLine \$w\.Week\.Reset\) 6 -Pin' -and $wf -match "Save-PetJson \`$script:State 'state\.json'" -and $wf -notmatch 'Invoke-Chime'
}
Check 'the week: the saved key survives a state save and load' {
    $ws = New-PetState; $ws.WeekWarnKey = Get-WeekKey $t0.AddDays(2)
    $back = $ws | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable -DateKind String
    -not (Test-WeekWarn @{ Pct = 93; Reset = $t0.AddDays(2) } "$($back.WeekWarnKey)" $t0) -and (Test-WeekWarn @{ Pct = 93; Reset = $t0.AddDays(2) } "$((New-PetState).WeekWarnKey)" $t0) -and (Test-WeekWarn @{ Pct = 93; Reset = $t0.AddDays(9) } "$($back.WeekWarnKey)" $t0)
}
Check 'quiet return (tok.ps1): the first main prompt after more than 6 quiet hours stretches once, with no words; minions do not count as main events; a restart remembers the last meal' {
    $pr = & $evCase 'Prompt'; $head = [regex]::Match($bodyEvent, '(?ms)^function Invoke-BodyEvent.*?switch \(\$E\.Type\)').Value
    $stretchLine = ($pr -split "`n" | Where-Object { $_ -match 'Test-QuietReturn' }) -join ''
    $stretchLine -match "Test-QuietReturn \`$prevMain \`$now\) -and -not \`$script:State\.Coma\) \{ Set-Override 'stretch' 1\.8 \}" -and $stretchLine -notmatch 'Say |Invoke-Chime' -and
    $head -match '\$prevMain = \$script:LastMainUtc' -and $head -match '-not \$E\.Sub -and \$E\.Type -in' -and $head -match "'Prompt'" -and $head -notmatch "'SubDone'" -and
    $tokSrc -match '\$script:LastMainUtc = try \{ \[datetime\]::Parse\(\$script:State\.LastFedUtc'
}
Check 'lines (tok.ps1): late night is a note with no yawn and no dozing face, a dream is recalled without a yawn, and a minion speaks only after a job over 45 s' {
    $ln = Get-FnText $tokSrc 'Test-LateNight'; $hm = Get-FnText $tokSrc 'Step-Home'
    $ln -match 'Say \(Get-LateNightLine \$local \(Get-YourName\)\) 7 -Low' -and $ln -notmatch "Set-Override|yawn\*" -and
    (& $evCase 'Prompt') -match 'Say \(Get-DreamRecallLine \$script:LastDream\.Subject\) 4 -Low' -and $tokSrc -notmatch '\*yawn\*' -and
    $hm -match 'if \(Test-MinionRanLong \$M\.Info\.First \$M\.Info\.Seen\) \{ Say \$what 2\.6 \}'
}
Check 'first bubbles: three, two lines each, no line over 33 characters, in the ruled order and words' {
    $fb = @(Get-FirstBubbles)
    $fb.Count -eq 3 -and @($fb | ForEach-Object { $ls = $_ -split "`n"; if ($ls.Count -ne 2) { 'x' }; $ls | Where-Object { $_.Length -gt 33 } }).Count -eq 0 -and
    $fb[0] -ceq "I'm Tok, Claude in a small body.`nI only read your transcripts." -and $fb[1] -ceq "🏮 My lantern is your 5-hour`nusage. Hover for the numbers." -and
    $fb[2] -ceq "Right-click me for Settings.`nExact usage is off until you ask." -and
    (Get-EggLine) -ceq "Still in the egg. I hatch`non our first day of work." -and @((Get-EggLine) -split "`n" | Where-Object { $_.Length -gt 33 }).Count -eq 0
}
Check 'first bubbles (tok.ps1): once ever, after the family scan, pinned 7 s each with a 1.5 s gap, in place of the hello; a needs-you or a turn ending drops the rest' {
    $g = Get-FnText $tokSrc 'Step-Greeting'
    $g -match 'if \(-not \$script:GreetPending -or \$script:LineageJob\) \{ return \}' -and $g -match '\$script:State\.Greeted = \$true\s+Save-PetJson \$script:State ''state\.json''' -and
    $g -match 'Say \$lines\[0\] 7 -Pin' -and $g -match 'Start-Later 8500 \{ param\(\$t\) if \(-not \$script:GreetCancelled\) \{ Say \$t 7 -Pin \} \} @\(\$lines\[1\]\)' -and
    $g -match 'Start-Later 17000 \{ param\(\$t\) if \(-not \$script:GreetCancelled\) \{ Say \$t 7 -Pin \} \} @\(\$lines\[2\]\)' -and
    (Get-FnText $tokSrc 'Step-Life') -match 'Step-Greeting' -and (Get-FnText $tokSrc 'Invoke-NeedsYou') -match 'GreetCancelled = \$true' -and (& $evCase 'Done') -match 'GreetCancelled = \$true' -and
    $tokSrc -match '-not \$script:State\.Greeted -and -not \$script:ForcedMood -and -not \$script:ForcedStage\) \{ \$script:GreetPending = \$true \}' -and
    $tokSrc -match 'Get-EggLine' -and $tokSrc -notmatch 'Feed it tokens'
}
Check 'start-later: a one-shot DispatcherTimer that runs its action once and lets go of the timer' {
    $src = Get-Content (Join-Path $root 'lib\Pet.ps1') -Raw
    $fn = [regex]::Match($src, '(?ms)^function Start-Later\b.*?^\}').Value
    $fn -match 'DispatcherTimer' -and $fn -match '\.Stop\(\)' -and $fn -match 'Later\.Remove' -and $fn -match 'Tag' -and $fn -match '\$jobArgs = @\(\$job\.Args\)' -and $fn -match '& \$job\.Action @jobArgs'      # splatted from a variable: @(...) would pass one array
}

# --- the right-click menu (session 1 of the roadmap)
Check 'menu: Tok''s own style parses (cream, rust, a ✓ for checked items, › for a submenu)' {
    Add-Type -AssemblyName PresentationFramework
    $rd = Get-MenuResources
    $rd.Contains([Windows.Controls.ContextMenu]) -and $rd.Contains([Windows.Controls.MenuItem]) -and $rd.Contains([Windows.Controls.MenuItem]::SeparatorStyleKey) -and
    $script:MenuXaml -match '#FFFFFBF5' -and $script:MenuXaml -match '#FF8A3E28' -and $script:MenuXaml -match 'Text="✓"' -and $script:MenuXaml -match 'Text="›"'
}
Check 'menu: Stats · Today · Family | Settings ▸ (Chatter, Sound, Private, Follow, Start with Windows) | Pet | Goodbye' {
    $mb = [regex]::Match($tokSrc, '(?ms)^\$menu = \[Windows\.Controls\.ContextMenu\]::new\(\).*?^\$window\.ContextMenu = \$menu').Value
    $order = @([regex]::Matches($mb, "Add-MenuItem '([^']+)'|New-MenuLabel '([^']+)'|\bSeparator\b|Header = 'Settings'") | ForEach-Object { if ($_.Value -eq 'Separator') { '|' } elseif ($_.Value -match 'Settings') { 'Settings' } else { "$($_.Groups[1].Value)$($_.Groups[2].Value)" } }) -join ','
    $order -eq 'Stats,Today,Family,|,Settings,Chatter,|,Sound,Private mode,Exact usage,Follow the active app,Start with Windows,|,Pet,|,Goodbye' -and
    $mb -match '(?s)Add-MenuItem \$mode\[1\] \{.*?\} \$false \(\$script:Config\.Chatter -eq \$mode\[0\]\) \$mode\[2\] \$settings'      # the three chatter levels sit under the label
}
Check 'private: the Settings tick follows timed (auto) private too, so one click ends it, and it clears when the timer runs out' {
    (Get-FnText $tokSrc 'Set-Private') -match '\$script:PrivateItem\.IsChecked = Test-Private' -and
    (Get-FnText $tokSrc 'Step-Private') -match '\$script:PrivateItem\.IsChecked = \$now' -and
    $tokSrc -match "Add-MenuItem 'Private mode' \{ Set-Private \`$script:PrivateItem\.IsChecked 0 'menu' \} \`$true \(Test-Private\)"
}
Check 'start with Windows: a no-window shortcut (conhost --headless pwsh) to this Tok in the Startup folder, added and removed (a temp folder here)' {
    $sd = Join-Path ([IO.Path]::GetTempPath()) "tok-startup-$PID"; $null = New-Item -ItemType Directory -Force $sd
    try {
        $off = -not (Test-StartWithWindows $sd)
        Set-StartWithWindows $true $root $sd
        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Get-StartupShortcutPath $sd))
        $on = (Test-StartWithWindows $sd) -and $lnk.TargetPath -match '\\conhost\.exe$' -and
            $lnk.Arguments -eq "--headless pwsh -STA -NoProfile -WindowStyle Hidden -File ""$root\tok.ps1""" -and $lnk.WorkingDirectory -eq $root -and $lnk.IconLocation -eq "$root\tok.ico,0"
        Set-StartWithWindows $false '' $sd
        $off -and $on -and -not (Test-StartWithWindows $sd) -and @(Get-ChildItem $sd).Count -eq 0 -and
            $tokSrc -match 'Set-StartWithWindows \$script:StartupItem\.IsChecked \$PSScriptRoot'
    } finally { Remove-Item $sd -Recurse -Force -ErrorAction SilentlyContinue }
}
Check 'shortcuts: which Tok a shortcut starts, new (tok.ps1) or 1.0 (Start-Tok.vbs); this copy''s, another''s, a deleted one''s' {
    $sd = Join-Path ([IO.Path]::GetTempPath()) "tok-lnk-$PID"; $null = New-Item -ItemType Directory -Force $sd
    try {
        $sh = New-Object -ComObject WScript.Shell
        $old = $sh.CreateShortcut("$sd\old.lnk"); $old.TargetPath = "$env:WINDIR\System32\wscript.exe"; $old.Arguments = """$root\Start-Tok.vbs"""; $old.Save()
        $gone = $sh.CreateShortcut("$sd\gone.lnk"); $gone.TargetPath = "$env:WINDIR\System32\wscript.exe"; $gone.Arguments = """C:\Nowhere\tok-1.0\Start-Tok.vbs"""; $gone.Save()
        $other = $sh.CreateShortcut("$sd\other.lnk"); $other.TargetPath = "$env:WINDIR\notepad.exe"; $other.Arguments = 'x.txt'; $other.Save()
        Set-TokShortcut "$sd\new.lnk" $root
        (Get-TokShortcutDir "$sd\new.lnk") -eq $root -and (Get-TokShortcutDir "$sd\old.lnk") -eq $root -and (Get-TokShortcutDir "$sd\other.lnk") -eq $null -and
        (Get-TokShortcutDir "$sd\nope.lnk") -eq $null -and (Test-TokShortcut "$sd\new.lnk" $root) -and (Test-TokShortcut "$sd\old.lnk" "$root\") -and
        -not (Test-TokShortcut "$sd\gone.lnk" $root) -and (Test-StaleTokShortcut "$sd\gone.lnk") -and -not (Test-StaleTokShortcut "$sd\new.lnk") -and -not (Test-StaleTokShortcut "$sd\other.lnk")
    } finally { Remove-Item $sd -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- the deferred touches from Parliament session 4 (fan-out, the skill card, the bubble stepping aside)
Check 'fan-out: tool calls in one reply carry its message id' {
    $fe = @(ConvertTo-BodyEvents (Line '2026-10-05T01:00:00Z' 'msg_fan' 1 0 'claude-opus-5-5' '[{"type":"tool_use","name":"Read","input":{"file_path":"a.ps1"}}]'))
    @($fe | Where-Object Type -eq 'Tool')[0].MsgId -eq 'msg_fan'
}
Check 'fan-out: the 4th call from the same reply raises the arms, once per 5 minutes; a new reply starts over' {
    $n = 0; $last = ''; $hits = @()
    foreach ($id in 'a', 'a', 'a', 'a', 'a', 'b', 'b') { $n = Get-FanCount $last $n $id; $last = $id; $hits += $n }
    ($hits -join ',') -eq '1,2,3,4,5,1,2' -and (Test-FanOut 4 ([datetime]::MinValue) $t0) -and -not (Test-FanOut 5 ([datetime]::MinValue) $t0) -and
    -not (Test-FanOut 4 $t0.AddMinutes(-4) $t0) -and (Test-FanOut 4 $t0.AddMinutes(-5) $t0) -and (Get-FanCount '' 0 '') -eq 1
}
Check 'fan-out and skill: both arms up while working; hands at the belly with a ≡ for a skill; no lids, no frown' {
    $fp = Get-Pose 'fan'; $sp = Get-Pose 'skill'
    $fp.Arms -eq 'stretch' -and $fp.Spark -and $fp.Eyes -eq 'open' -and $sp.Arms -eq 'hold' -and $sp.Fx -eq '≡' -and $sp.Eyes -eq 'open'
}
Check 'fan-out and skill (tok.ps1): main tool calls only, never over a mouthful' {
    $tc = & $evCase 'Tool'
    $tc -match "if \(\`$E\.Name -eq 'Skill' -and -not \`$script:Meal\) \{ Set-Override 'skill' 1\.2 \}" -and
    $tc -match 'Get-FanCount \$script:FanMsg \$script:FanN \$E\.MsgId' -and $tc -match "\(Test-FanOut \`$script:FanN \`$script:LastFan \`$now\) -and -not \`$script:Meal\) \{ \`$script:LastFan = \`$now; Set-Override 'fan' 0\.6 \}" -and
    $tc.IndexOf('Get-FanCount') -gt $tc.IndexOf('if ($E.Sub) { return }')
}
Check 'the bubble steps aside: in its box (with a few DIP to spare) or not' {
    (Test-PointerIn 10 10 200 80) -and (Test-PointerIn -4 85 200 80) -and -not (Test-PointerIn -10 10 200 80) -and -not (Test-PointerIn 50 90 200 80)
}
Check 'the bubble steps aside (tok.ps1): a talking bubble fades out under the pointer, a panel never does, and it comes back when the pointer leaves' {
    $sb = Get-FnText $tokSrc 'Step-Bubble'
    $tokSrc -match '(?s)\$ui\.Bubble\.Add_MouseEnter\(\{\s+if \(\$script:BubblePanel -or \$script:BubbleAside\) \{ return \}' -and
    $sb -match 'if \(-not \(Test-PointerIn \$pt\.X \$pt\.Y \$ui\.Bubble\.ActualWidth \$ui\.Bubble\.ActualHeight\)\)' -and
    $sb -match '\$script:BubblePanel = \$b\.Panel; \$script:BubbleAside = \$false'
}

# ---- Prod Tok plumbing (10-09 night): a second Tok in its own folders, install and uninstall
Check 'data folder: TOK_DATA_DIR moves Tok''s folder and CLAUDE_CONFIG_DIR moves Claude Code''s; unset, the real ones' {
    $probe = ". '$root\lib\Transcripts.ps1'; . '$root\lib\Pet.ps1'; `"`$script:DataDir|`$script:ProjectsDir|`$script:ClaudeJson`""
    $old = $env:TOK_DATA_DIR, $env:CLAUDE_CONFIG_DIR
    try {
        $env:TOK_DATA_DIR = 'C:\t\data'; $env:CLAUDE_CONFIG_DIR = 'C:\t\claude'
        $moved = pwsh -NoProfile -Command $probe
        $env:TOK_DATA_DIR = $null; $env:CLAUDE_CONFIG_DIR = $null
        $real = pwsh -NoProfile -Command $probe
    } finally { $env:TOK_DATA_DIR, $env:CLAUDE_CONFIG_DIR = $old }
    $moved -eq 'C:\t\data|C:\t\claude\projects|C:\t\claude\.claude.json' -and
    $real -eq "$(Join-Path $env:LOCALAPPDATA 'tok')|$(Join-Path $env:USERPROFILE '.claude\projects')|$(Join-Path $env:USERPROFILE '.claude.json')"
}
Check 'data folder: the real Tok''s mutex is Local\Tok; another folder gets its own, the same however the path is written' {
    $a = Get-TokMutexName 'C:\Temp\TokTest'; $b = Get-TokMutexName 'c:\temp\toktest\'
    (Get-TokMutexName '') -eq 'Local\Tok' -and $a -match '^Local\\Tok-[0-9a-f]{12}$' -and $a -eq $b -and $a -ne (Get-TokMutexName 'C:\Temp\Other') -and
    $tokSrc -match '\[System\.Threading\.Mutex\]::new\(\$false, \(Get-TokMutexName\)\)'
}
$st = Join-Path ([IO.Path]::GetTempPath()) "tok-setup-$PID"; $null = New-Item -ItemType Directory -Force $st
$np = 'C:\Apps\tok\notify.ps1'; $sp = Join-Path $st 'settings.json'
Check 'hook setup: a settings file that is not there is made with just the hook' {
    $r = Add-TokHook $sp $np; $s = Get-Content $sp -Raw | ConvertFrom-Json -AsHashtable
    $h = @($s.hooks.Notification)
    $r -eq 'added' -and $h.Count -eq 1 -and $h[0].matcher -eq $script:TokHookMatcher -and $h[0].matcher -notmatch 'idle_prompt' -and
    $h[0].hooks[0].type -eq 'command' -and $h[0].hooks[0].command -eq 'pwsh -NoProfile -File "C:/Apps/tok/notify.ps1"' -and -not (Test-Path "$sp.tok-backup")
}
Check 'hook setup: added once, beside what was there (other settings and other hooks kept, a backup made first)' {
    Set-Content $sp '{"model":"opus","permissions":{"allow":["Bash(ls)"]},"hooks":{"Notification":[{"matcher":"idle_prompt","hooks":[{"type":"command","command":"other.exe"}]}],"Stop":[{"hooks":[{"type":"command","command":"stop.exe"}]}]}}'
    $r1 = Add-TokHook $sp $np; $r2 = Add-TokHook $sp $np
    $s = Get-Content $sp -Raw | ConvertFrom-Json -AsHashtable
    $r1 -eq 'added' -and $r2 -eq 'already' -and @($s.hooks.Notification).Count -eq 2 -and $s.model -eq 'opus' -and @($s.permissions.allow)[0] -eq 'Bash(ls)' -and
    @($s.hooks.Stop).Count -eq 1 -and (Get-Content "$sp.tok-backup" -Raw) -match 'other\.exe' -and (Get-Content "$sp.tok-backup" -Raw) -notmatch 'notify'
}
Check 'hook setup: uninstall takes out only Tok''s hook, then the empty blocks' {
    $r1 = Remove-TokHook $sp $np; $s = Get-Content $sp -Raw | ConvertFrom-Json -AsHashtable
    $kept = @($s.hooks.Notification).Count -eq 1 -and @($s.hooks.Notification)[0].hooks[0].command -eq 'other.exe' -and @($s.hooks.Stop).Count -eq 1
    Set-Content $sp '{"model":"opus"}'; $null = Add-TokHook $sp $np; $r2 = Remove-TokHook $sp $np; $s2 = Get-Content $sp -Raw | ConvertFrom-Json -AsHashtable
    $r1 -eq 'removed' -and $kept -and $r2 -eq 'removed' -and -not $s2.Contains('hooks') -and $s2.model -eq 'opus' -and (Remove-TokHook $sp $np) -eq 'none' -and (Remove-TokHook (Join-Path $st 'nope.json') $np) -eq 'none'
}
Check 'hook setup: a broken settings file is never written over' {
    Set-Content $sp '{ not json'; $threw = $false
    try { $null = Add-TokHook $sp $np } catch { $threw = $true }
    $threw -and (Get-Content $sp -Raw).Trim() -eq '{ not json'
}
Check 'hook setup: a new copy takes over an older copy''s Tok hook (one Tok hook after), and leaves other hooks alone' {
    $oldNp = 'C:\Apps\tok-1.0\notify.ps1'
    Set-Content $sp '{"hooks":{"Notification":[{"matcher":"idle_prompt","hooks":[{"type":"command","command":"pwsh -NoProfile -File \"C:/x/notify.ps1\""}]}]}}'
    $null = Add-TokHook $sp $oldNp
    $others = @(Get-OtherTokHooks $sp $np)
    $r = Add-TokHook $sp $np; $s = Get-Content $sp -Raw | ConvertFrom-Json -AsHashtable
    $tokHooks = @(@($s.hooks.Notification) | ForEach-Object { Get-TokHookNotifyPath $_ } | Where-Object { $_ })
    $others.Count -eq 1 -and $others[0] -eq $oldNp -and $r -eq 'moved' -and $tokHooks.Count -eq 1 -and $tokHooks[0] -eq $np -and
    @($s.hooks.Notification).Count -eq 2 -and @($s.hooks.Notification)[0].matcher -eq 'idle_prompt' -and (Add-TokHook $sp $np) -eq 'already' -and @(Get-OtherTokHooks $sp $np).Count -eq 0
}
Check 'hook setup: uninstall also clears a Tok hook whose notify.ps1 is gone, but not a live copy''s' {
    $live = Join-Path $st 'live\notify.ps1'; $null = New-Item -ItemType Directory -Force (Split-Path $live); 'x' | Set-Content $live
    Set-Content $sp '{}'
    $e = { param($n) [ordered]@{ matcher = $script:TokHookMatcher; hooks = @([ordered]@{ type = 'command'; command = (Get-TokHookCommand $n) }) } }
    $set = [ordered]@{ hooks = [ordered]@{ Notification = @((& $e 'C:\Gone\tok\notify.ps1'), (& $e $live), (& $e $np)) } }
    Save-ClaudeSettings $set $sp
    $r = Remove-TokHook $sp $np; $s = Get-Content $sp -Raw | ConvertFrom-Json -AsHashtable
    $left = @(@($s.hooks.Notification) | ForEach-Object { Get-TokHookNotifyPath $_ })
    $r -eq 'removed' -and $left.Count -eq 1 -and $left[0] -eq $live
}
Check 'skill setup: a new copy takes over an older copy''s skill; a stale one is cleared on uninstall; someone else''s is never touched' {
    $cd = Join-Path $st 'claude'; $sk = Get-TokSkillPath $cd
    $a = Join-Path $st 'copyA'; $b = Join-Path $st 'copyB'
    foreach ($d in $a, $b) { $null = New-Item -ItemType Directory -Force "$d\skills\tok-private"; Copy-Item "$root\skills\tok-private\SKILL.md" "$d\skills\tok-private\"; 'x' | Set-Content "$d\tok.ps1" }
    $r1 = Add-TokSkill $cd $a; $r2 = Add-TokSkill $cd $b; $from = Get-TokSkillDir $sk
    $keepLive = (Remove-TokSkill $cd $a) -eq 'none' -and (Test-Path $sk)      # B's skill, and B still holds a Tok
    Remove-Item "$b\tok.ps1"
    $staleGone = (Remove-TokSkill $cd $a) -eq 'removed' -and -not (Test-Path $sk)
    $null = New-Item -ItemType Directory -Force (Split-Path $sk); 'mine' | Set-Content $sk
    $r1 -eq 'added' -and $r2 -eq 'moved' -and $from -eq $b -and $keepLive -and $staleGone -and (Add-TokSkill $cd $a) -eq 'theirs' -and
    (Remove-TokSkill $cd $a) -eq 'none' -and (Get-Content $sk -Raw).Trim() -eq 'mine' -and (Get-TokSkillDir $sk) -eq $null
}
Check 'Settings > Apps: the entry is written per user (a throwaway key here) and taken out only by its own copy' {
    $key = "HKCU:\Software\TokTest-$PID\Uninstall\Tok"
    try {
        $live = Join-Path $st 'live'
        Register-TokApp $root $key; $v = Get-ItemProperty -LiteralPath $key
        $ok = $v.DisplayName -eq 'Tok' -and $v.DisplayVersion -eq $script:TokVersion -and $v.InstallLocation -eq $root -and $v.NoModify -eq 1 -and $v.NoRepair -eq 1 -and $v.DisplayIcon -eq "$root\tok.ico" -and
            $v.UninstallString -eq "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ""$root\Uninstall.ps1"" -FromSettings -AppsKey ""$key"""
        'x' | Set-Content "$live\tok.ps1"
        Register-TokApp $live $key
        $notMine = (Unregister-TokApp $root $key) -eq 'none' -and (Test-Path $key)
        $mine = (Unregister-TokApp $live $key) -eq 'removed' -and -not (Test-Path $key) -and (Unregister-TokApp $live $key) -eq 'none'
        $ok -and $notMine -and $mine
    } finally { Remove-Item "HKCU:\Software\TokTest-$PID" -Recurse -Force -ErrorAction SilentlyContinue }
}
Check 'uninstall: the data folder goes only when everything in it is Tok''s' {
    $d = Join-Path $st 'data'; $null = New-Item -ItemType Directory -Force "$d\sounds"
    'x' | Set-Content "$d\state.json"; 'x' | Set-Content "$d\tok.log"; 'x' | Set-Content "$d\state.json.tmp"
    $clean = (Get-ForeignDataItems $d).Count -eq 0
    'x' | Set-Content "$d\notes.txt"
    $clean -and (Get-ForeignDataItems $d) -join ',' -eq 'notes.txt' -and (Get-ForeignDataItems (Join-Path $st 'nope')).Count -eq 0
}
Check 'update: Update.ps1 pulls fast-forward only, re-runs Install, never kills, and a zip copy only says where to get the new one' {
    $up = Get-Content (Join-Path $root 'Update.ps1') -Raw
    $up -match 'pull --ff-only' -and $up -match "Install\.ps1'\), '-NoStart'" -and $up -match 'Stop-Tok \$script:DataDir' -and $up -notmatch 'Stop-Process|Invoke-WebRequest|Invoke-RestMethod' -and
    $up -match "can't update itself"
}
Check 'install and uninstall: the scripts exist, Install checks PowerShell 7 with the winget hint, Uninstall never kills' {
    $i = Get-Content (Join-Path $root 'Install.ps1') -Raw; $u = Get-Content (Join-Path $root 'Uninstall.ps1') -Raw
    $i -match 'winget install Microsoft\.PowerShell' -and $i -match 'PSVersion\.Major -lt 7' -and $i -match 'Unblock-File' -and $i -match "Join-Path \`$ProgramsDir 'Tok\.lnk'" -and
    $i -match 'Register-TokApp' -and $i -match 'Get-OtherTokHooks' -and $i -notmatch 'wscript' -and $u -match 'Unregister-TokApp' -and $u -match 'Read-Host' -and $u -match 'IsInputRedirected' -and
    $u -match 'Stop-Tok \$script:DataDir' -and $u -notmatch 'Stop-Process' -and $u -match 'Get-ForeignDataItems' -and $u -match 'Remove-TokHook' -and (Get-FnText (Get-Content (Join-Path $root 'lib\Setup.ps1') -Raw) 'Stop-Tok') -notmatch 'Stop-Process'
}
Remove-Item $st -Recurse -Force

Write-Host "$script:Pass passed, $script:Fail failed"
exit $script:Fail
