# Transcripts.ps1 - reads Claude Code session logs (~/.claude/projects/**/*.jsonl).
# Read-only. Two jobs: work out how much of the 5-hour window is spent, and turn
# newly written transcript lines into events the creature can react to.

# Where Claude Code keeps its files: ~\.claude, or wherever CLAUDE_CONFIG_DIR points (Claude Code's own setting, which the
# clean-profile check, tools\Test-Install.ps1, also uses). Its usage cache, .claude.json, sits beside ~\.claude by default and
# inside the folder when it is moved.
$script:ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$script:ClaudeJson = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json' } else { Join-Path $env:USERPROFILE '.claude.json' }
$script:ProjectsDir = Join-Path $script:ClaudeDir 'projects'

# API list prices, $ per million tokens. Cache writes use the 1-hour rate,
# which is what Claude Code uses.
$script:Prices = @{
    fable  = @{ in = 10.0; out = 50.0; cw = 20.0; cr = 0.25 }
    opus   = @{ in = 4.0;  out = 20.0; cw = 8.0;  cr = 0.20 }
    sonnet = @{ in = 2.0;  out = 10.0; cw = 4.0;  cr = 0.20 }
    haiku  = @{ in = 1.0;  out = 5.0;  cw = 2.0;  cr = 0.10 }
}

function Get-ModelPrice([string]$Model) {
    foreach ($family in 'fable', 'mythos', 'opus', 'sonnet', 'haiku') {
        if ($Model -like "*$family*") {
            if ($family -eq 'mythos') { return $script:Prices.fable }
            return $script:Prices[$family]
        }
    }
    $script:Prices.opus
}

function Get-UsageCost($Model, [long]$In, [long]$Out, [long]$CacheWrite, [long]$CacheRead) {
    $p = Get-ModelPrice $Model
    ($In * $p.in + $Out * $p.out + $CacheWrite * $p.cw + $CacheRead * $p.cr) / 1e6
}

# Fast regex pass over one transcript line. Returns usage for assistant lines
# that carry it, else $null. Avoids ConvertFrom-Json so the startup scan is quick.
function Get-LineUsage([string]$Line) {
    if ($Line.IndexOf('"role":"assistant"') -lt 0 -or $Line.IndexOf('"usage"') -lt 0) { return $null }
    $id = [regex]::Match($Line, '"id":"(msg_[^"]+)"')
    if (-not $id.Success) { return $null }   # synthetic messages have no msg_ id and no usage
    $ts = [regex]::Match($Line, '"timestamp":"([^"]+)"')
    if (-not $ts.Success) { return $null }
    $num = { param($name) $m = [regex]::Match($Line, """$name"":(\d+)"); if ($m.Success) { [long]$m.Groups[1].Value } else { 0L } }
    [pscustomobject]@{
        Id    = $id.Groups[1].Value
        Ts    = [datetimeoffset]::Parse($ts.Groups[1].Value, [cultureinfo]::InvariantCulture).UtcDateTime
        Model = [regex]::Match($Line, '"model":"([^"]+)"').Groups[1].Value
        In    = & $num 'input_tokens'
        Out   = & $num 'output_tokens'
        CW    = & $num 'cache_creation_input_tokens'
        CR    = & $num 'cache_read_input_tokens'
        Speed = [regex]::Match($Line, '"speed":"(\w+)"').Groups[1].Value
    }
}

# Usage entries from every transcript touched in the last $Hours hours, de-duplicated
# (Claude Code writes one line per content block, each repeating the message usage).
function Get-RecentUsage([double]$Hours = 10, [string]$Root = $script:ProjectsDir) {
    $since = [datetime]::UtcNow.AddHours(-$Hours)
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $out = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path $Root)) { return $out }
    Get-ChildItem $Root -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -gt $since } | ForEach-Object {
            foreach ($line in (Read-SharedLines $_.FullName)) {
                $u = Get-LineUsage $line
                if ($u -and $u.Ts -gt $since -and $seen.Add($u.Id)) { $out.Add($u) }
            }
        }
    $out
}

function Read-SharedLines([string]$Path) {
    try {
        $fs = [System.IO.FileStream]::new($Path, 'Open', 'Read', 'ReadWrite,Delete')
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        try { $sr.ReadToEnd() -split "`n" } finally { $sr.Dispose() }
    } catch { @() }
}

# API-equivalent spend of the usage at or after $SinceUtc.
function Get-UsageSpend($Usage, [datetime]$SinceUtc) {
    $cost = 0.0; $tokens = 0L
    foreach ($u in $Usage) {
        if ($u.Ts -ge $SinceUtc) {
            $mult = if ($u.Speed -eq 'fast') { 2.0 } else { 1.0 }   # fast mode is billed at 2x
            $cost += $mult * (Get-UsageCost $u.Model $u.In $u.Out $u.CW $u.CR)
            $tokens += $u.In + $u.Out + $u.CW
        }
    }
    [pscustomobject]@{ Cost = $cost; Tokens = $tokens }
}

# ESTIMATE, from this machine's transcripts only: the 5-hour window starts with the first
# message after the previous window ends. Usage from claude.ai, the phone or other machines
# is invisible here, which is why Get-UsageLimits (the real numbers) wins when available.
# Returns start, reset time and API-equivalent spend for the window active at $Now,
# or Active=$false when no window is open.
function Get-SessionWindow($Usage, [datetime]$Now = [datetime]::UtcNow, [double]$WindowHours = 5) {
    $start = $null
    foreach ($u in ($Usage | Sort-Object Ts)) {
        if ($null -eq $start -or $u.Ts -ge $start.AddHours($WindowHours)) { $start = $u.Ts }
    }
    if ($null -eq $start -or $Now -ge $start.AddHours($WindowHours)) {
        return [pscustomobject]@{ Active = $false; Start = $null; Reset = $null; Cost = 0.0; Tokens = 0L; Real = $false }
    }
    $s = Get-UsageSpend $Usage $start
    [pscustomobject]@{ Active = $true; Start = $start; Reset = $start.AddHours($WindowHours); Cost = $s.Cost; Tokens = $s.Tokens; Real = $false }
}

# REAL limits: Claude Code fetches your plan's usage (the same numbers as its usage panel)
# and caches them in ~/.claude.json under cachedUsageUtilization. Only that block is read;
# nothing is called and no credentials are touched. Returns $null if it isn't there.
#   @{ FetchedUtc; FiveHour = @{ Pct; Reset }; Week = @{ Pct; Reset } }   (Pct is 0-100)
function Get-UsageLimits([string]$Path = $script:ClaudeJson) {
    try {
        if (-not (Test-Path $Path)) { return $null }
        $c = (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -DateKind String).cachedUsageUtilization
        if (-not $c -or -not $c.utilization) { return $null }
        $read = {
            param($w)
            if (-not $w -or $null -eq $w.utilization -or -not $w.resets_at) { return $null }
            @{ Pct = [double]$w.utilization; Reset = [datetimeoffset]::Parse($w.resets_at, [cultureinfo]::InvariantCulture).UtcDateTime }
        }
        @{
            FetchedUtc = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$c.fetchedAtMs).UtcDateTime
            Source     = 'cache'
            FiveHour   = & $read $c.utilization.five_hour
            Week       = & $read $c.utilization.seven_day
        }
    } catch { $null }
}

# The API-equivalent $ a 5-hour window holds on the plan Claude Code records in ~/.claude.json (oauthAccount.organizationType and
# organizationRateLimitTier; no secrets in those fields): Max 20x 720, Max 5x 180, Pro 36 (measured 2026-10-05; Max as sold,
# 5x and 20x Pro). Anything else or nothing recorded: $null, and Tok makes no guess.
function Get-PlanLimitFromAccount($Account) {
    if (-not $Account) { return $null }
    $tier = "$($Account.organizationRateLimitTier)"; $type = "$($Account.organizationType)"
    if ($tier -match 'max_20x') { return 720.0 }
    if ($tier -match 'max_5x') { return 180.0 }
    if ($type -eq 'claude_pro' -or $tier -eq 'default_claude_ai') { return 36.0 }
    $null
}
function Get-PlanLimitUsd([string]$Path = $script:ClaudeJson) {
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        Get-PlanLimitFromAccount (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -DateKind String).oauthAccount
    } catch { $null }
}

# LIVE limits (exact, the same numbers as Claude Code's usage panel): Tok asks Anthropic's usage endpoint
# itself, with the login Claude Code already stored in ~/.claude/.credentials.json. Only while Exact usage is on
# (off unless the user ticks it). The token is read at call time, sent
# only to api.anthropic.com, and never stored, logged or shown. One GET per poll; the caller paces it (3 minutes
# while Claude is active, 10 otherwise, and exponential backoff after an error or a 429).
# Returns the same shape as Get-UsageLimits, or @{ Failed = $true; Status = <HTTP code, 0 if none> }.
# Why = 'no login' (no file or no token), 'expired' (Claude Code renews it the next time it runs; not a failure), or the
# error's own message for anything else. The token never appears in it.
function Get-LiveUsage([string]$CredPath = (Join-Path $script:ClaudeDir '.credentials.json'), [int]$TimeoutSec = 10) {
    $status = 0
    try {
        if (-not (Test-Path $CredPath)) { return @{ Failed = $true; Status = 0; Why = 'no login' } }
        $o = (Get-Content -LiteralPath $CredPath -Raw | ConvertFrom-Json).claudeAiOauth
        if (-not $o -or -not $o.accessToken) { return @{ Failed = $true; Status = 0; Why = 'no login' } }
        if (Test-LoginExpired $o.expiresAt) { return @{ Failed = $true; Status = 0; Why = 'expired' } }
        $r = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec $TimeoutSec `
            -Headers @{ Authorization = "Bearer $($o.accessToken)"; 'anthropic-beta' = 'oauth-2025-04-20' }
        $o = $null
        $read = {
            param($w)
            if (-not $w -or $null -eq $w.utilization -or -not $w.resets_at) { return $null }
            $reset = if ($w.resets_at -is [datetime]) { $w.resets_at.ToUniversalTime() } else { [datetimeoffset]::Parse("$($w.resets_at)", [cultureinfo]::InvariantCulture).UtcDateTime }
            @{ Pct = [double]$w.utilization; Reset = $reset }
        }
        @{ FetchedUtc = [datetime]::UtcNow; Source = 'live'; FiveHour = & $read $r.five_hour; Week = & $read $r.seven_day }
    } catch {
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        @{ Failed = $true; Status = $status; Why = (Get-LiveFailureText $_.Exception.Message) }
    }
}
# True when the stored login's expiresAt (Unix ms) has passed.
function Test-LoginExpired($ExpiresAt) { [bool]($ExpiresAt -and [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ExpiresAt) -lt [DateTimeOffset]::UtcNow) }
# An error message short enough for one log line, with anything that looks like a credential cut out.
function Get-LiveFailureText([string]$Message) {
    $m = ($Message -replace '\s+', ' ' -replace '(?i)(bearer|token|authorization)\S*\s*\S+', '$1 [cut]').Trim()
    if (-not $m) { return 'no answer' }
    if ($m.Length -gt 90) { $m = $m.Substring(0, 89) + '…' }
    $m
}

# How often to ask: every 3 minutes while Claude is active, every 10 otherwise.
function Get-LivePollMinutes([bool]$Active) { if ($Active) { 3 } else { 10 } }
# After an error or a 429: wait 5, 10, 20, then 40 minutes (the cap), by how many failures in a row.
function Get-LiveBackoffMinutes([int]$Failures) { [math]::Min(40.0, 5.0 * [math]::Pow(2, [math]::Max(0, $Failures - 1))) }

# The last live reading and when we may ask again, as saved in %LOCALAPPDATA%\tok\live.json, so a restart reuses
# the reading (with its FetchedUtc) and does not call again before it is allowed to.
function ConvertTo-LiveRecord($Limits, [datetime]$Next, [int]$Failures) {
    $win = { param($w) if ($w) { @{ Pct = $w.Pct; ResetUtc = $w.Reset.ToUniversalTime().ToString('o') } } else { $null } }
    @{
        FetchedUtc = if ($Limits) { $Limits.FetchedUtc.ToUniversalTime().ToString('o') } else { $null }
        FiveHour = if ($Limits) { & $win $Limits.FiveHour } else { $null }
        Week = if ($Limits) { & $win $Limits.Week } else { $null }
        NextUtc = $Next.ToUniversalTime().ToString('o'); Failures = $Failures
    }
}
function ConvertFrom-LiveRecord($Rec) {
    if (-not $Rec) { return $null }
    try {
        $dt = { param($t) [datetime]::Parse("$t", [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
        $win = { param($w) if ($w -and $w.ResetUtc) { @{ Pct = [double]$w.Pct; Reset = (& $dt $w.ResetUtc) } } else { $null } }
        $limits = if ($Rec.FetchedUtc -and $Rec.FiveHour) { @{ FetchedUtc = (& $dt $Rec.FetchedUtc); Source = 'live'; FiveHour = (& $win $Rec.FiveHour); Week = (& $win $Rec.Week) } } else { $null }
        @{ Limits = $limits; Next = $(if ($Rec.NextUtc) { & $dt $Rec.NextUtc } else { [datetime]::MinValue }); Failures = [int]($Rec.Failures ?? 0) }
    } catch { $null }
}

# The freshest of the sources that has a 5-hour reading.
function Select-Limits([object[]]$Candidates) {
    $best = $null
    foreach ($c in $Candidates) { if ($c -and $c.FiveHour -and (-not $best -or $c.FetchedUtc -gt $best.FetchedUtc)) { $best = $c } }
    $best
}

# The window Tok shows: the real numbers when Claude Code has cached them for the current
# window, plus this machine's spend since they were fetched (so it stays live between fetches);
# otherwise the estimate. Pct is 0..1. With no limit ($null or 0: no plan known and no LimitUsd) there is nothing to measure a
# guess against: a real reading still works (without the spend top-up), anything else is NoReading with Pct 0.
function Get-WindowStatus($Usage, $Limits, [double]$LimitUsd, [datetime]$Now = [datetime]::UtcNow) {
    $f = if ($Limits) { $Limits.FiveHour }
    if ($f -and $f.Reset -gt $Now) {
        # a live reading and the cache both get this machine's spend since they were fetched, so the number keeps moving
        $since = Get-UsageSpend $Usage $Limits.FetchedUtc
        $pct = $f.Pct / 100 + $(if ($LimitUsd -gt 0) { $since.Cost / $LimitUsd } else { 0.0 })
        return [pscustomobject]@{ Active = $true; Real = $true; NoReading = $false; AsOf = $Limits.FetchedUtc; Start = $f.Reset.AddHours(-5); Reset = $f.Reset; Pct = $pct; Cost = $since.Cost; Week = $Limits.Week }
    }
    # a real reading whose window has ended still says when the next one could start at the earliest, so the estimate
    # never counts spend from before that reset (on 10-07 it said 96% for half an hour when the real window was at 2%)
    if ($f) { $Usage = @($Usage | Where-Object { $_.Ts -ge $f.Reset }) }
    $week = if ($Limits -and $Limits.Week -and $Limits.Week.Reset -gt $Now) { $Limits.Week }
    if ($LimitUsd -le 0) { return [pscustomobject]@{ Active = $false; Real = $false; NoReading = $true; Start = $null; Reset = $null; Pct = 0.0; Cost = 0.0; Week = $week } }
    $w = Get-SessionWindow $Usage $Now
    $pct = if ($w.Active) { $w.Cost / $LimitUsd } else { 0.0 }
    [pscustomobject]@{ Active = $w.Active; Real = $false; NoReading = $false; Start = $w.Start; Reset = $w.Reset; Pct = $pct; Cost = $w.Cost; Week = $week }
}

# ---- live events -----------------------------------------------------------

function Get-ToolHint([string]$Name, $InputObj) {
    if (-not $InputObj) { return '' }
    $leaf = { param($p) if ($p) { Split-Path $p -Leaf } else { '' } }
    switch -Regex ($Name) {
        '^(Edit|Write|Read|NotebookEdit)$' { return & $leaf $InputObj.file_path }
        '^(Bash|PowerShell)$'              { return "$($InputObj.description)" }
        '^(Grep|Glob)$'                    { return "$($InputObj.pattern)" }
        '^WebSearch$'                      { return "$($InputObj.query)" }
        '^WebFetch$'                       { return ([uri]"$($InputObj.url)").Host }
        '^Agent$'                          { return "$($InputObj.description)" }
        '^Skill$'                          { return "$($InputObj.skill)" }
        default                            { return '' }
    }
}

# A tool result that says the user declined the tool ("The user doesn't want to proceed with this tool use. The tool use was
# rejected ..." in Claude Code's real transcripts). The tool never ran, so it is not an error and Tok does not count it.
function Test-DeclinedText([string]$Text) { $Text.IndexOf("doesn't want to proceed", [StringComparison]::Ordinal) -ge 0 }

# The user line Claude Code writes when he presses Esc: "[Request interrupted by user]" or "[Request interrupted by user for
# tool use]". It is not a prompt.
function Test-InterruptText([string]$Text) { "$Text" -match '^\s*\[Request interrupted by user' }

# The text of a tool_result block (a string, or a list of text blocks).
function Get-ResultText($Content) {
    if ($Content -is [string]) { return $Content }
    (@($Content) | ForEach-Object { "$($_.text)" }) -join ' '
}

# Turns one parsed transcript line into zero or more events:
#   @{ Type = Usage|Tool|Done|SubDone|Prompt|Interrupt|Ouch|Limit|Compact; ... }
# $FromSubagent marks lines from subagents/ transcripts. $SessionCwd is the folder the session started in (the tail reads it once
# per transcript): it names the project, so one session keeps one name. A line's own "cwd" follows Claude's cd's (tok -> memory
# -> ledger in one evening) and is only the fallback.
function ConvertTo-BodyEvents([string]$Line, [bool]$FromSubagent = $false, [string]$SessionCwd = '') {
    $events = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($Line)) { return $events }
    # Tool results are most of the bytes (file reads, images) and all Tok needs from them is is_error,
    # so they skip the JSON parse. Inside a result's own text the quotes are escaped, so this can't misfire.
    if ($Line.IndexOf('"type":"tool_result"') -ge 0 -and $Line.IndexOf('"type":"assistant"') -lt 0) {
        # (a declined tool is not an error: the tool never ran, the user said no)
        if (-not $FromSubagent -and $Line.IndexOf('"is_error":true') -ge 0 -and $Line.IndexOf('"isMeta":true') -lt 0 -and -not (Test-DeclinedText $Line)) { $events.Add(@{ Type = 'Ouch' }) }
        return $events
    }
    try { $j = $Line | ConvertFrom-Json -Depth 64 } catch { return $events }
    if ($j.type -eq 'system' -and $j.subtype -eq 'compact_boundary' -and -not $FromSubagent) {
        $events.Add(@{ Type = 'Compact' })
        return $events
    }
    $msg = $j.message
    if (-not $msg) { return $events }
    $project = if ($FromSubagent) { '' } elseif ($SessionCwd) { Get-ProjectName $SessionCwd } else { Get-ProjectName "$($j.cwd)" }

    if ($j.isApiErrorMessage -and $j.error -eq 'rate_limit') {
        $text = ($msg.content | Where-Object type -eq 'text' | Select-Object -First 1).text
        $events.Add(@{ Type = 'Limit'; Text = "$text" })
        return $events
    }

    if ($j.type -eq 'assistant') {
        $u = Get-LineUsage $Line
        if ($u) { $events.Add(@{ Type = 'Usage'; Usage = $u; Sub = ($FromSubagent -or [bool]$j.isSidechain); Project = $project }) }
        foreach ($b in @($msg.content)) {
            if ($b.type -eq 'tool_use') {
                # Keys: the tool's name and key argument, only for the private-mode check (Get-PrivacyKeys); never shown
                $events.Add(@{ Type = 'Tool'; Name = "$($b.name)"; Hint = (Get-ToolHint $b.name $b.input); Keys = (Get-PrivacyKeys $b.name $b.input); Sub = $FromSubagent; Project = $project; MsgId = "$($msg.id)" })
            }
        }
        # Claude correcting itself out loud (WHO.md row 2: "I change my mind when I'm wrong"): only plain admissions, not
        # every "actually"
        if (-not $FromSubagent -and -not $j.isSidechain) {
            foreach ($b in @($msg.content)) {
                if ($b.type -eq 'text' -and $b.text -match '(?i)\b(I was wrong|my mistake|I made a mistake|let me reconsider|on second thought|I misread|that was wrong|I stand corrected)\b') { $events.Add(@{ Type = 'Rethink' }); break }
            }
        }
        if ($msg.stop_reason -eq 'end_turn' -and -not $FromSubagent -and -not $j.isSidechain) {
            $events.Add(@{ Type = 'Done'; Project = $project })
        } elseif ($msg.stop_reason -eq 'end_turn' -and $FromSubagent) {
            $events.Add(@{ Type = 'SubDone' })
        }
    }
    elseif ($j.type -eq 'user' -and -not $j.isMeta -and -not $FromSubagent) {
        if ($msg.content -is [string]) {
            if (Test-InterruptText $msg.content) { $events.Add(@{ Type = 'Interrupt' }) }
            elseif ($msg.content -notmatch '^\s*<') { $events.Add(@{ Type = 'Prompt'; Text = $msg.content; Project = $project }) }
        } else {
            foreach ($b in @($msg.content)) {
                if ($b.type -eq 'tool_result' -and $b.is_error) { if (-not (Test-DeclinedText (Get-ResultText $b.content))) { $events.Add(@{ Type = 'Ouch' }) }; break }
                if ($b.type -eq 'text' -and (Test-InterruptText $b.text)) { $events.Add(@{ Type = 'Interrupt' }); break }
                if ($b.type -eq 'text' -and $b.text -notmatch '^\s*<') { $events.Add(@{ Type = 'Prompt'; Text = "$($b.text)"; Project = $project }); break }
            }
        }
    }
    $events
}

# Tails every transcript written recently. Starts at end-of-file for files that
# already exist, so history is never replayed as live events.
# Each main transcript is one session: Cwd holds the folder it started in, Spoke when it last wrote a line (LiveCwds).
class TranscriptTail {
    [string]$Root
    [hashtable]$Offsets = @{}
    [hashtable]$Partial = @{}
    [hashtable]$Grew = @{}
    [hashtable]$Cwd = @{}
    [hashtable]$Spoke = @{}
    [datetime]$LastScan = [datetime]::MinValue
    [double]$ScanSeconds = 15
    [bool]$Primed = $false

    TranscriptTail([string]$root) { $this.Root = $root }

    # The folder a session started in: the first "cwd" near the top of its transcript ('' until one is written). Claude Code
    # starts a transcript with a few bookkeeping lines that have none; the first prompt has it.
    static [string] FirstCwd([string]$path) {
        try {
            $fs = [System.IO.FileStream]::new($path, 'Open', 'Read', 'ReadWrite,Delete')
            try {
                $sr = [System.IO.StreamReader]::new($fs)
                for ($i = 0; $i -lt 400; $i++) {
                    $line = $sr.ReadLine()
                    if ($null -eq $line) { break }
                    $m = [regex]::Match($line, '"cwd":"((?:[^"\\]|\\.)*)"')
                    if ($m.Success) { return $m.Groups[1].Value.Replace('\\', '\') }
                }
            } finally { $fs.Dispose() }
        } catch { }
        return ''
    }

    # The start folders of the main sessions that wrote a line in the last $Minutes, one entry per session (two sessions in
    # one folder give its name twice).
    [string[]] LiveCwds([double]$Minutes) {
        $cut = [datetime]::UtcNow.AddMinutes(-$Minutes)
        $live = foreach ($p in @($this.Spoke.Keys)) { if ($this.Spoke[$p] -ge $cut -and $this.Cwd[$p]) { $this.Cwd[$p] } }
        return @($live)
    }

    [System.Collections.Generic.List[object]] Poll() {
        $lines = [System.Collections.Generic.List[object]]::new()
        $now = [datetime]::UtcNow
        if (($now - $this.LastScan).TotalSeconds -ge $this.ScanSeconds) {
            $this.LastScan = $now
            foreach ($old in @($this.Grew.Keys)) {
                if (($now - $this.Grew[$old]).TotalMinutes -gt 30) { $this.Offsets.Remove($old); $this.Partial.Remove($old); $this.Grew.Remove($old); $this.Cwd.Remove($old); $this.Spoke.Remove($old) }
            }
            $cut = $now.AddMinutes(-20)
            foreach ($f in (Get-ChildItem $this.Root -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue)) {
                if ($f.LastWriteTimeUtc -lt $cut -or $this.Offsets.ContainsKey($f.FullName)) { continue }
                # Files found on the first scan start at their end; files that appear
                # later are new sessions and are read from the top.
                $this.Offsets[$f.FullName] = if ($this.Primed) { 0L } else { $f.Length }
                $this.Partial[$f.FullName] = ''
                $this.Grew[$f.FullName] = $now
            }
            $this.Primed = $true
        }
        foreach ($path in @($this.Offsets.Keys)) {
            [byte[]]$buf = $null
            [int]$read = 0
            try {
                $fs =[System.IO.FileStream]::new($path, 'Open', 'Read', 'ReadWrite,Delete')
                try {
                    if ($fs.Length -lt $this.Offsets[$path]) { $this.Offsets[$path] = 0L }
                    if ($fs.Length -eq $this.Offsets[$path]) { continue }
                    $null = $fs.Seek($this.Offsets[$path], 'Begin')
                    $buf = [byte[]]::new($fs.Length - $this.Offsets[$path])
                    $read = $fs.Read($buf, 0, $buf.Length)
                    $this.Offsets[$path] += $read
                    $this.Grew[$path] = $now
                } finally { $fs.Dispose() }
                $text = $this.Partial[$path] + [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
                $parts = $text -split "`n"
                $this.Partial[$path] = $parts[-1]
                $sub = $path -match '\\subagents\\'
                $start = ''
                if (-not $sub -and $parts.Count -gt 1) {
                    $this.Spoke[$path] = $now
                    if (-not $this.Cwd[$path]) { $this.Cwd[$path] = [TranscriptTail]::FirstCwd($path) }
                    $start = "$($this.Cwd[$path])"
                }
                for ($i = 0; $i -lt $parts.Count - 1; $i++) {
                    if ([string]::IsNullOrWhiteSpace($parts[$i])) { continue }
                    $lines.Add([pscustomobject]@{ Line = $parts[$i]; Sub = $sub; Path = $path; Cwd = $start })
                }
            } catch { }
        }
        return $lines
    }
}
