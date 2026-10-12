# Pet.ps1 - Tok's life: state, growth, mood, and the food coma at the session limit.
# Pure functions over a hashtable, so tests can drive them without a window.

# Tok's own folder: %LOCALAPPDATA%\tok, or wherever TOK_DATA_DIR points (a second, separate Tok: the clean-profile check,
# tools\Test-Install.ps1, runs a first life there without touching the real one).
$script:DataDir = if ($env:TOK_DATA_DIR) { $env:TOK_DATA_DIR } else { Join-Path $env:LOCALAPPDATA 'tok' }

# One Tok per data folder: the real one holds Local\Tok, and a Tok with its own TOK_DATA_DIR a name of its own, so a test can
# run beside the real one. Install and Uninstall use it to see whether that Tok is running.
function Get-TokMutexName([string]$Dir = $env:TOK_DATA_DIR) {
    if (-not $Dir) { return 'Local\Tok' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Dir).TrimEnd('\').ToLowerInvariant())) } finally { $sha.Dispose() }
    'Local\Tok-' + (($h[0..5] | ForEach-Object { $_.ToString('x2') }) -join '')
}

# Tok used to live in %LOCALAPPDATA%\claude-body. Copy it over once so nothing is lost (the old folder stays as a backup).
function Move-OldTokHome {
    if ($env:TOK_DATA_DIR) { return }      # only the real Tok has a past
    $old = Join-Path $env:LOCALAPPDATA 'claude-body'
    if ((Test-Path $old) -and -not (Test-Path (Join-Path $script:DataDir 'state.json'))) {
        $null = New-Item -ItemType Directory -Force $script:DataDir
        Get-ChildItem $old -File | Where-Object Name -in 'state.json', 'config.json' | Copy-Item -Destination $script:DataDir
    }
}

# Age is days worked together (Get-GenerationDays in Lineage.ps1): an egg until the first day with 10+ replies, then
# hatchling, kid at 3 days, adult at 10, elder at 30, counted per generation. LegacyXp is only the stopgap used until
# the first day-count scan lands (an older state.json has no per-day counts yet); nothing shows XP any more.
$script:Stages = @(
    @{ Name = 'egg';       MinDays = 0;  LegacyXp = 0;    Scale = 0.80 }
    @{ Name = 'hatchling'; MinDays = 1;  LegacyXp = 5;    Scale = 0.70 }
    @{ Name = 'kid';       MinDays = 3;  LegacyXp = 150;  Scale = 0.85 }
    @{ Name = 'adult';     MinDays = 10; LegacyXp = 900;  Scale = 1.00 }
    @{ Name = 'elder';     MinDays = 30; LegacyXp = 4000; Scale = 1.08 }
)

function New-PetState {
    @{
        Name        = 'Tok'
        BornUtc     = [datetime]::UtcNow.ToString('o')
        Xp          = 0.0
        LastFedUtc  = [datetime]::UtcNow.ToString('o')
        Tokens      = 0L
        Meals       = 0
        Coma        = $false     # stuffed at the session limit: sleeps it off until WakeUtc
        ComaUtc     = $null
        WakeUtc     = $null
        Comas       = 0
        Lineage     = $null      # see Lineage.ps1; filled by the first background scan
        Today       = (New-TodayStats)
        NudgedDate  = $null
        Greeted     = $false     # the first bubbles have been said (once ever); a state from disk without this key is an install from before them
    }
}

# Older state files: a death becomes a food coma, and the rebirth fields go.
function Update-PetState($State) {
    if ($State.Dead) { $State.Coma = $true; $State.WakeUtc = $State.ReviveUtc }
    foreach ($k in 'Dead', 'DiedUtc', 'ReviveUtc', 'Epitaph', 'Graveyard', 'Generation', 'Weight') { $State.Remove($k) }
    if ($null -eq $State.Coma) { $State.Coma = $false }
    if ($null -eq $State.Comas) { $State.Comas = 0 }
    $State.Name = 'Tok'
    $State
}

# Since: when Tok started counting this day (it only counts while it runs). Out: output tokens, the "Wrote" row.
function New-TodayStats { @{ Date = (Get-Date).ToString('yyyy-MM-dd'); Since = [datetime]::UtcNow.ToString('o'); Prompts = 0; Tools = @{}; Errors = 0; Tokens = 0L; Out = 0L; Done = 0 } }

# Rolls the daily counters over at local midnight; returns the current day's table.
function Get-Today($State) {
    $d = (Get-Date).ToString('yyyy-MM-dd')
    if (-not $State.Today -or $State.Today.Date -ne $d) { $State.Today = New-TodayStats }
    if ($State.Today.Tools -isnot [hashtable]) { $State.Today.Tools = @{} }
    $State.Today
}

# A tool name short enough for a bubble: MCP tools go by their server
# (mcp__claude_ai_Notion__notion-fetch -> Notion, mcp__plugin_x_desktop-commander__read_file -> desktop-commander).
function Get-ShortToolName([string]$Name) {
    if ($Name -notmatch '^mcp__(.+?)__') { return $Name }
    $server = $Matches[1] -replace '^claude_ai_', ''
    if ($server -like 'plugin_*') { $server = ($server -split '_')[-1] }
    $server
}

# ---------------------------------------------------------------- the right-click panels (ledger verdict, session 5)
# Each panel is a title and a few rows. A row is @{ L = label; V = value; D = detail } (the bubble draws them as a grid:
# the label muted, the value right-aligned so the % signs stack, the detail after it), or @{ Note = '...' } for one muted
# line under the grid.
# Get-*Text flattens a panel to plain lines (tests, the log, and the bubble before the grid existed).
function Get-PanelTime([datetime]$Utc) {
    $l = $Utc.ToLocalTime()
    $l.ToString($(if ($l.Minute) { 'h:mm tt' } else { 'h tt' }), [cultureinfo]::InvariantCulture)
}
function Get-PanelText($Panel) {
    $lines = @($Panel.Title)
    foreach ($r in $Panel.Rows) {
        $lines += if ($r.Note) { $r.Note } elseif ($r.Line) { $r.Line } elseif ($r.ContainsKey('Bar')) { Get-PaceBarText $r.Bar $r.Notch }
                  else { (@($r.L, $r.V, $r.D) | Where-Object { $_ }) -join ' ' }
    }
    $lines -join "`n"
}
# How much taller than the room above Tok (156 DIP from the window's top to the bubble's base) a bubble is, plus a 4 DIP margin.
function Get-BubbleOverflow([double]$Height) { if ($Height -le 152) { 0.0 } else { [math]::Ceiling($Height - 152) } }

# 1234 -> 1.2K, 412000 -> 412K, 1234567 -> 1.2M
function Format-Count([double]$N) {
    if ($N -ge 1e6) { return '{0}M' -f [math]::Round($N / 1e6, $(if ($N -ge 1e7) { 0 } else { 1 })) }
    if ($N -ge 1e3) { return '{0}K' -f [math]::Round($N / 1e3, $(if ($N -ge 1e4) { 0 } else { 1 })) }
    "$([math]::Round($N))"
}

# Pace (P1, Parliament session 7). Under a real reading: a bar filled to the share used, with a
# notch where the clock stands in that window (fill past the notch means faster than time), and the line "At this pace:
# full by …" only when spending at the rate so far would fill the window before it resets. No line in a window's first
# tenth (30 minutes of five hours, about 17 hours of a week): too little time to call a pace. Used is 0..1.
function Get-PaceFull([double]$Used, [datetime]$Start, [datetime]$Reset, [datetime]$Now = [datetime]::UtcNow) {
    $span = ($Reset - $Start).TotalMinutes; $gone = ($Now - $Start).TotalMinutes
    if ($span -le 0 -or $gone -lt $span / 10 -or $Used -le 0 -or $Used -ge 1) { return $null }
    $full = $Start.AddMinutes($gone / $Used)
    if ($full -lt $Reset) { $full } else { $null }
}
function Get-PaceRows([double]$Used, [datetime]$Start, [datetime]$Reset, [scriptblock]$Format, [datetime]$Now = [datetime]::UtcNow) {
    $span = ($Reset - $Start).TotalMinutes
    $clock = if ($span -gt 0) { [math]::Min(1.0, [math]::Max(0.0, ($Now - $Start).TotalMinutes / $span)) } else { 0.0 }
    @{ Bar = [math]::Min(1.0, [math]::Max(0.0, $Used)); Notch = $clock }
    $full = Get-PaceFull $Used $Start $Reset $Now
    if ($full) { @{ Line = "At this pace: full by $(& $Format $full)" } }
}
# The bar as text (tests, the log): 29 cells, heavy where used, light after, the notch as a cross.
function Get-PaceBarText([double]$Bar, [double]$Notch) {
    $n = 29; $fill = [int][math]::Round($Bar * $n); $at = [math]::Min($n - 1, [int][math]::Floor($Notch * $n))
    -join (0..($n - 1) | ForEach-Object { if ($_ -eq $at) { if ($_ -lt $fill) { '╋' } else { '╂' } } elseif ($_ -lt $fill) { '━' } else { '─' } })
}

# Stats, the token monitor: who and which day, then the 5-hour window and the week with their resets, then how old the
# reading is (only when it is 3+ minutes old). No lifetime token tally, no nap count, no countdown to the next stage.
function Get-StatsPanel($State, $Window, [bool]$LiveUsage = $false) {
    $name = if ($State.Lineage) { Get-LineageName $State.Lineage } else { $State.Name }
    $days = Get-GenDays $State
    $title = "$name · $((Get-PetStage $State).Name)$(if ($days -ge 1) { " · day $days" })"
    $rows = @()
    if (-not $Window) { return @{ Title = $title; Rows = @(@{ Note = 'No reading yet.' }) } }
    $est = if ($Window.Real) { '' } else { '~' }
    $rows += if ($Window.NoReading) { @{ L = '5-hour'; V = 'no reading' } }
             elseif ($Window.Active) { @{ L = '5-hour'; V = "$est$([math]::Round($Window.Pct * 100))%"; D = "resets $(Get-PanelTime $Window.Reset)" } }
             else { @{ L = '5-hour'; V = '0%'; D = 'not started' } }
    # pace (P1): a bar and a notch under each real reading, and a line only when it is on course to fill before its reset
    if ($Window.Real -and $Window.Active -and $Window.Reset) { $rows += @(Get-PaceRows $Window.Pct $Window.Reset.AddHours(-5) $Window.Reset { param($t) Get-PanelTime $t }) }
    if ($Window.Week) {
        $rows += @{ L = 'Week'; V = "$([math]::Round($Window.Week.Pct))%"; D = "resets $(Get-WeekResetText $Window.Week.Reset)" }
        $rows += @(Get-PaceRows ($Window.Week.Pct / 100) $Window.Week.Reset.AddDays(-7) $Window.Week.Reset { param($t) Get-WeekResetText $t })
    }
    # under a guess, or with nothing to go on, a pointer to the switch (not once Exact usage is already on)
    if ($Window.NoReading) { if (-not $LiveUsage) { $rows += @{ Note = 'Exact usage is in Settings' } } }
    elseif ($Window.Active -and -not $Window.Real) {
        $rows += @{ Note = 'Estimate, not a reading' }
        if (-not $LiveUsage) { $rows += @{ Note = 'Exact usage is in Settings' } }
    }
    elseif ($Window.Real -and $Window.AsOf) {
        $age = [math]::Floor(([datetime]::UtcNow - $Window.AsOf).TotalMinutes)
        if ($age -ge 60) { $rows += @{ Note = "Read at $(Get-PanelTime $Window.AsOf)." } }
        elseif ($age -ge 3) { $rows += @{ Note = "Read $age min ago." } }
    }
    @{ Title = $title; Rows = $rows }
}
function Get-StatsText($State, $Window, [bool]$LiveUsage = $false) { Get-PanelText (Get-StatsPanel $State $Window $LiveUsage) }

# The hover's last part: the 5-hour usage in a few words ("5-hour 42% (guess) · resets 3:10 PM"), or that it has not started, or that
# there is nothing to read (no plan known and no real reading, so no guess either). "Window" never names usage here: it is the
# Stats row's own label, and a window is an app on the screen.
function Get-BellyText($W) {
    if ($W -and $W.NoReading) { return 'no usage reading' }
    if ($W -and $W.Active) { return "5-hour $([math]::Round($W.Pct * 100))%$(if (-not $W.Real) { ' (guess)' }) · resets $($W.Reset.ToLocalTime().ToString('h:mm tt'))" }
    '5-hour not started'
}

# The limit the guess is measured against: a LimitUsd in config.json always wins (calibrate.ps1 writes one), else the plan's
# (Get-PlanLimitUsd), else none ($null: Tok makes no guess).
function Resolve-LimitUsd($ConfigLimit, $PlanLimit) {
    if ($null -ne $ConfigLimit -and [double]$ConfigLimit -gt 0) { return [double]$ConfigLimit }
    if ($null -ne $PlanLimit -and [double]$PlanLimit -gt 0) { return [double]$PlanLimit }
    $null
}

# Today: what this day has been, counted while Tok runs (the title says since when). Turns are Claude finishing a reply
# (end_turn). "Wrote" is output tokens only, Claude's own work; a day that began before it was counted shows no row.
function Get-TodayPanel($State) {
    $t = Get-Today $State
    $calls = 0; $byName = @{}
    foreach ($e in $t.Tools.GetEnumerator()) { $calls += [int]$e.Value; $n = Get-ShortToolName $e.Key; $byName[$n] = [int]$byName[$n] + [int]$e.Value }
    $since = if ($t.Since) { " · since $(Get-PanelTime ([datetime]::Parse($t.Since, $null, 'RoundtripKind').ToUniversalTime()))" } else { '' }
    $rows = @(
        @{ L = 'Prompts'; V = "$([int]$t.Prompts)" }
        @{ L = 'Turns'; V = "$([int]$t.Done)" }
        @{ L = 'Tool calls'; V = "$calls"; D = $(if ($t.Errors) { "· $($t.Errors) $(if ($t.Errors -eq 1) { 'error' } else { 'errors' })" }) }
    )
    $top = @($byName.GetEnumerator() | Sort-Object @{ e = { $_.Value }; Descending = $true }, @{ e = { $_.Key } } | Select-Object -First 2 | ForEach-Object {
        $k = "$($_.Key)"; if ($k.Length -gt 10) { $k = $k.Substring(0, 9) + '…' }; "$k $($_.Value)" })
    if ($top.Count) { $rows += @{ L = ''; V = ''; D = ($top -join ' · ') } }      # under the errors, in the same column
    if ($t.ContainsKey('Out')) { $rows += @{ L = 'Wrote'; V = (Format-Count $t.Out); D = 'tokens' } }
    if ($t.ContainsKey('WeekRise')) { $rows += @{ L = 'Used'; V = "$([math]::Round([double]$t.WeekRise))%"; D = 'of the week' } }
    @{ Title = "Today$since"; Rows = $rows }
}

# What today cost (P2, Parliament session 7): the sum of today's rises in the week reading, in
# whole points. WeekMark is the highest reading seen this week. A lower reading with the same reset is a staler source and
# changes nothing; a reset more than an hour later is a new week, and its reading so far counts (a reset adds nothing on
# its own). The row appears once a week reading has been seen today.
function Add-WeekRise($State, $Week) {
    if (-not $Week -or $null -eq $Week.Pct -or -not $Week.Reset) { return }
    $t = Get-Today $State
    if (-not $t.ContainsKey('WeekRise')) { $t.WeekRise = 0.0 }
    $pct = [double]$Week.Pct; $reset = ([datetime]$Week.Reset).ToUniversalTime()
    $m = $State.WeekMark
    $mReset = if ($m -and $m.Reset -is [datetime]) { $m.Reset.ToUniversalTime() } elseif ($m -and $m.Reset) { try { [datetime]::Parse("$($m.Reset)", [cultureinfo]::InvariantCulture, 'RoundtripKind').ToUniversalTime() } catch { $null } }
    if (-not $mReset) { $State.WeekMark = @{ Pct = $pct; Reset = $reset.ToString('o') }; return }
    if ($reset -gt $mReset.AddHours(1)) { $t.WeekRise += $pct; $State.WeekMark = @{ Pct = $pct; Reset = $reset.ToString('o') }; return }
    if ($reset -lt $mReset.AddHours(-1)) { return }
    if ($pct -gt [double]$m.Pct) { $t.WeekRise += $pct - [double]$m.Pct; $State.WeekMark = @{ Pct = $pct; Reset = $m.Reset } }
}
function Get-TodayText($State) { Get-PanelText (Get-TodayPanel $State) }

# Days worked together with the current generation (0 until the per-day counts exist).
function Get-GenDays($State) { if ($State.Lineage) { Get-GenerationDays $State.Lineage } else { 0 } }

function Get-StageForDays([int]$Days) {
    $stage = $script:Stages[0]
    foreach ($s in $script:Stages) { if ($Days -ge $s.MinDays) { $stage = $s } }
    $stage
}

# True once the family tree carries per-day reply counts (Lineage Schema 2).
function Test-DaysTracked($State) { [bool]($State.Lineage -and $State.Lineage.Schema -ge 2) }

function Get-PetStage($State) {
    if (Test-DaysTracked $State) { return Get-StageForDays (Get-GenDays $State) }
    $stage = $script:Stages[0]
    foreach ($s in $script:Stages) { if ($State.Xp -ge $s.LegacyXp) { $stage = $s } }
    $stage
}

function Get-NextStage($State) {
    $days = Get-GenDays $State
    foreach ($s in $script:Stages) { if ($days -lt $s.MinDays) { return $s } }
    $null
}

# How high and how fast Tok hops, by age: a hatchling is bouncier (1.15x as high), an elder calmer (0.8x as high,
# 15% slower). The needs-you hop is Plain: it never scales, so it always reads the same.
function Get-HopSpec([string]$StageName, [bool]$Plain = $false) {
    $h = 1.0; $t = 1.0
    if (-not $Plain) {
        if ($StageName -eq 'hatchling') { $h = 1.15 }
        elseif ($StageName -eq 'elder') { $h = 0.8; $t = 1.15 }
    }
    @{ Height = 22.0 * $h; RiseMs = 220.0 * $t; FallMs = 440.0 * $t }
}

# While any minion is out, Tok makes room: the perch shifts left so the orbit's right half (Pet centre + 74 + a seed's
# half-width) stays on screen and inside the app. It never goes past the app's left edge (the orbit's left edge stays
# inside), and it glides back when the last minion is home. $X is the perch's window Left; $AppLeft the app's left edge.
$script:MinionRoom = 46.0
function Get-MinionRoomX([double]$X, [bool]$Out, [double]$AppLeft) {
    if (-not $Out) { return $X }
    [math]::Max($X - $script:MinionRoom, [math]::Min($X, $AppLeft - 133))
}

# An app's frame comes from DWM in physical pixels, but Tok (system-DPI aware) lives in Windows' virtualized coordinates, where a
# monitor at a different scale from the main one is stretched to the main one's scale. This maps the frame onto its monitor:
# $Mon is the monitor's rect as Tok sees it; Px, Py, Pw, Ph its physical position and size. Pw or Ph 0: no mapping.
function ConvertTo-LogicalRect($R, $Mon, [double]$Px, [double]$Py, [double]$Pw, [double]$Ph) {
    if ($Pw -le 0 -or $Ph -le 0) { return @{ Left = $R.Left; Top = $R.Top; Right = $R.Right; Bottom = $R.Bottom } }
    $sx = ($Mon.Right - $Mon.Left) / $Pw; $sy = ($Mon.Bottom - $Mon.Top) / $Ph
    @{ Left = $Mon.Left + ($R.Left - $Px) * $sx; Top = $Mon.Top + ($R.Top - $Py) * $sy
       Right = $Mon.Left + ($R.Right - $Px) * $sx; Bottom = $Mon.Top + ($R.Bottom - $Py) * $sy }
}

# Easter eggs in a prompt. Saying "Tok" perks it up, but not the file or folder (tok.ps1, tok\, tok/, tools/tok-x).
function Test-TokName([string]$Text) { $Text -match '(?i)(?<![\w./\\:-])tok(?![\w\\/-]|\.\w)' }
function Test-Thanks([string]$Text) { $Text -match '(?i)\b(thanks|thank you)\b' }

# One bubble at a time. Dreams and easter eggs are Low: they are dropped if anything is showing or waiting,
# and a live bubble ends a Low one early. Returns 'drop', 'queue' or 'cut' (end the Low bubble now, then show this).
function Get-BubbleVerdict([bool]$Low, [bool]$Showing, [bool]$ShowingLow, [int]$Queued) {
    if ($Low) { if ($Showing -or $Queued -gt 0) { return 'drop' } return 'queue' }
    if ($Showing -and $ShowingLow) { return 'cut' }
    'queue'
}

# A meal is one assistant message's usage. Output and cache writes are growth (XP).
# How far the sprout has bloomed comes from the 5-hour window instead (Get-SproutStage in Art.ps1).
function Add-PetMeal($State, $Usage) {
    $before = (Get-PetStage $State).Name
    $State.Xp += $Usage.Out / 1000.0 + $Usage.CW / 20000.0
    $State.Tokens += $Usage.In + $Usage.Out + $Usage.CW + $Usage.CR
    $State.Meals++
    $t = Get-Today $State
    $t.Tokens += $Usage.In + $Usage.Out + $Usage.CW + $Usage.CR
    if ($t.ContainsKey('Out')) { $t.Out += $Usage.Out }      # a day that began before Out was counted gets no partial row
    $State.LastFedUtc = [datetime]::UtcNow.ToString('o')
    $after = (Get-PetStage $State).Name
    if ($after -ne $before) { return $after }   # evolved
    $null
}

function Get-PetHungerMinutes($State) {
    ([datetime]::UtcNow - [datetime]::Parse($State.LastFedUtc, $null, 'RoundtripKind').ToUniversalTime()).TotalMinutes
}

# Parses "resets 7:40pm (America/Chicago)" into the next matching local time, as UTC.
function Get-ResetFromLimitText([string]$Text, [datetime]$NowLocal = (Get-Date)) {
    $m = [regex]::Match($Text, 'resets\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)', 'IgnoreCase')
    if (-not $m.Success) { return $NowLocal.ToUniversalTime().AddHours(5) }
    $h = [int]$m.Groups[1].Value % 12
    if ($m.Groups[3].Value -ieq 'pm') { $h += 12 }
    $min = if ($m.Groups[2].Success) { [int]$m.Groups[2].Value } else { 0 }
    $t = $NowLocal.Date.AddHours($h).AddMinutes($min)
    if ($t -le $NowLocal) { $t = $t.AddDays(1) }
    $t.ToUniversalTime()
}

# Hitting the session limit isn't a death: Tok ate too much and sleeps it off until the reset.
# Nothing is lost. $ResetUtc (from the real usage numbers) wins over the time parsed from the message.
function Set-PetComa($State, [string]$LimitText, $ResetUtc = $null) {
    if ($State.Coma) { return }
    $State.Coma = $true
    $State.Comas = 1 + [int]$State.Comas
    $State.ComaUtc = [datetime]::UtcNow.ToString('o')
    $wake = if ($ResetUtc -and $ResetUtc -gt [datetime]::UtcNow) { $ResetUtc } else { Get-ResetFromLimitText $LimitText }
    $State.WakeUtc = $wake.ToString('o')
}

# True once, when the reset time passes and Tok wakes up.
function Step-PetWake($State) {
    if (-not $State.Coma -or -not $State.WakeUtc) { return $false }
    if ([datetime]::UtcNow -lt [datetime]::Parse($State.WakeUtc, $null, 'RoundtripKind').ToUniversalTime()) { return $false }
    $State.Coma = $false; $State.ComaUtc = $null; $State.WakeUtc = $null
    $true
}

# Picks the mood the body should show. $Pct is the estimated share of the 5-hour
# window used (0..1+); $IdleSeconds is time since the last transcript event.
# $WatchSeconds: how long since anything at all was going on (a main turn still open, or a minion writing). Tok never
# sleeps while work is going on somewhere; it only looks busy for the main session's own activity ($IdleSeconds).
function Get-PetMood($State, [double]$Pct, [double]$IdleSeconds, [double]$WatchSeconds = $IdleSeconds) {
    if ($State.Coma) { return 'coma' }
    if ((Get-PetStage $State).Name -eq 'egg') { return 'egg' }
    if ($IdleSeconds -lt 25) { return 'busy' }      # working shows at any fullness; the sprout carries the meter
    if ($Pct -ge 0.85) { return 'stuffed' }
    if ($Pct -ge 0.60) { return 'full' }
    if ($IdleSeconds -gt 600 -and $WatchSeconds -gt 600) { return 'sleep' }
    if ((Get-PetHungerMinutes $State) -gt 90) { return 'hungry' }
    'happy'
}

# Seconds since work was last going on anywhere: the main session's last event, a main turn still open (a prompt or a
# tool call with no reply yet, for up to 20 minutes, so a turn that died mid-way can't keep Tok up all night), or the
# newest line from any minion.
function Get-WatchSeconds([datetime]$LastEvent, [bool]$TurnOpen, [datetime[]]$SubSeen, [datetime]$Now) {
    $last = $LastEvent
    if ($TurnOpen -and ($Now - $LastEvent).TotalMinutes -lt 20) { return 0.0 }
    foreach ($t in $SubSeen) { if ($t -gt $last) { $last = $t } }
    [math]::Max(0.0, ($Now - $last).TotalSeconds)
}

# ---------------------------------------------------------------- the edges (parliament session 4)
# The rules behind the quieter, truer signals (design\parliament\edges\VERDICT.md). Pure, so the tests can drive them;
# tok.ps1 does the drawing.

# How a turn ends. Short (no prompt, or 45 s or less since it): a small settle squish and nothing else. Long and clean: a hop,
# "All yours." and the done pip (timed by the caller to the hop's touchdown). Long and it ended on an error: no hop, an honest
# line and the falling pip. The project goes under the line when it is known and Tok is not private.
function Get-TurnEndPlan([bool]$Long, [bool]$Err, [string]$Project = '', [bool]$Private = $false) {
    $proj = if ($Project -and -not $Private) { "`n($Project)" } else { '' }
    if (-not $Long) { return @{ Kind = 'short'; Hop = $false; Squish = $true; Text = ''; Pip = '' } }
    if ($Err) { return @{ Kind = 'error'; Hop = $false; Squish = $true; Text = "Ended on an error. All yours.$proj"; Pip = 'doneerr' } }
    @{ Kind = 'clean'; Hop = $true; Squish = $false; Text = "All yours.$proj"; Pip = 'done' }
}

# Claude Code's Notification hook (notify.ps1 drops it in the inbox): what Tok does with one. A permission prompt, or a
# server or background agent asking for input, is a needs-you, the same as a question. Anything else (the 60-second idle
# reminder, a login that worked, ...) is nothing: "All yours." already handed the turn over. Also nothing when Tok is
# already waiting on you (Claude Code also reports its own question and plan as permission prompts), and for a line more than
# 2 minutes old. The tool's name is left out in private mode.
function Get-HookNeedsPlan([string]$Kind, [string]$Message, [bool]$Waiting, [double]$AgeSeconds, [bool]$Private = $false) {
    if ($Waiting -or $AgeSeconds -gt 120) { return $null }
    switch ($Kind) {
        { $_ -in 'permission_prompt', 'worker_permission_prompt' } {
            $tool = if ($Message -match 'permission to use (\S+)') { $Matches[1] } else { '' }
            if ($tool -in 'AskUserQuestion', 'ExitPlanMode') { return $null }
            $what = if ($tool -and -not $Private) { Get-ShortToolName $tool } else { '' }
            # Claude Code is the one asking, and the answer goes to it: the bubble says so (parliament session 6, the stranger's veto)
            return @{ Line = "🔑 Claude Code asks:`n$(if ($what) { "okay to use $($what)?" } else { 'okay to go on?' })" }
        }
        { $_ -in 'elicitation_dialog', 'elicitation_url_dialog', 'agent_needs_input' } { return @{ Line = '❓ A question for you' } }
    }
    $null
}

# The still moment between two awake breaths (Start-Breath): 2.5 to 4.5 s, from a uniform draw in [0, 1), so the rhythm never
# ticks like a metronome. Asleep rests longer: 4 to 7 s (Get-BreathRest $U 4 3).
function Get-BreathRest([double]$U, [double]$Min = 2.5, [double]$Span = 2) { $Min + $Span * [math]::Min(1.0, [math]::Max(0.0, $U)) }

# Which session a bubble is about, only when that tells two apart: the project goes under the line when another session that
# wrote in the last 15 minutes (LiveCwds) started somewhere else. One session, or two from the same folder: no tag, since it
# would say nothing.
function Get-ProjectTag([string]$Project, [string[]]$Live) {
    if (-not $Project) { return '' }
    if (@($Live | Where-Object { $_ -and $_ -ne $Project }).Count) { $Project } else { '' }
}

# Fan-out: tool calls in one reply share its message id. The 4th in a row from the same message raises both arms, at most once
# per 5 minutes. Get-FanCount is the running count for the message a tool call came from.
function Get-FanCount([string]$LastMsg, [int]$LastN, [string]$MsgId) { if ($MsgId -and $MsgId -eq $LastMsg) { $LastN + 1 } else { 1 } }
function Test-FanOut([int]$N, [datetime]$LastFan, [datetime]$Now) { $N -eq 4 -and ($Now - $LastFan).TotalMinutes -ge 5 }

# The bubble steps aside: when the pointer reaches a talking bubble it fades out (a transparent pixel lets clicks through to the
# window below) and comes back once the pointer has left its box. Panels stay put: he is reading them.
function Test-PointerIn([double]$X, [double]$Y, [double]$W, [double]$H, [double]$Pad = 6) { $X -ge -$Pad -and $Y -ge -$Pad -and $X -le $W + $Pad -and $Y -le $H + $Pad }

# Errors are weather: each one is counted; two within 60 s make the orange rethink look, at most once per 60 s.
function Test-ErrorBurst([datetime]$Prev, [datetime]$Now, [datetime]$LastShown) {
    ($Now - $Prev).TotalSeconds -le 60 -and ($Now - $LastShown).TotalSeconds -ge 60
}

# Claude waiting on the user (an AskUserQuestion or a plan): the eyes stay on them, still, for up to 30 minutes or until they answer.
$script:WaitingMinutes = 30
function Test-Waiting($Since, [datetime]$Now) { $null -ne $Since -and ($Now - [datetime]$Since).TotalMinutes -lt $script:WaitingMinutes }
function Get-WaitingText($Since, [datetime]$Now) {
    if (-not (Test-Waiting $Since $Now)) { return '' }
    $m = [int][math]::Floor(($Now - [datetime]$Since).TotalMinutes)
    "Waiting on you, $(if ($m -lt 1) { '<1' } else { $m }) min · "
}
# Claude has moved on once a main tool call other than the asking tools (or the end of the turn) comes more than 2 s after the
# question: the answer reaches the transcript as a tool result, which is not a prompt, so the prompt alone would never clear it.
function Test-WaitingAnswered($Since, [datetime]$Now, [string]$ToolName = '') {
    $null -ne $Since -and $ToolName -notin 'AskUserQuestion', 'ExitPlanMode' -and ($Now - [datetime]$Since).TotalSeconds -ge 2
}

# Reading: on a main Read, Grep or Glob the pupils make two left-to-right sweeps, three jumps each (x -3, 0, +3 DIP; y +1 for the
# first line, +2.5 for the second), a second in all. Returns the pupil offset T seconds in, or $null once it is over.
$script:ReadSweepSeconds = 1.0
function Get-ReadSweepPos([double]$T) {
    if ($T -lt 0 -or $T -ge $script:ReadSweepSeconds) { return $null }
    $i = [int][math]::Floor($T / ($script:ReadSweepSeconds / 6))      # the six jumps, 0..5
    $x = @(-3.0, 0.0, 3.0)[$i % 3]
    $y = if ($i -lt 3) { 1.0 } else { 2.5 }
    @($x, $y)
}
# At most once per 20 s, and only when the eyes are showing and no other look is on.
function Test-ReadSweepOk([datetime]$Last, [datetime]$Now, [bool]$EyesVisible, [bool]$OverrideOn) {
    $EyesVisible -and -not $OverrideOn -and ($Now - $Last).TotalSeconds -ge 20
}

# The nod: the first Edit or Write after two or more Read/Grep/Glob since the last Edit/Write, at most once a minute.
function Test-Nod([int]$Reads, [datetime]$Last, [datetime]$Now) { $Reads -ge 2 -and ($Now - $Last).TotalSeconds -ge 60 }

# The week running low: once per week, the first time the week's seven-day use reaches 90%. The week is keyed by its reset time
# (rounded to the hour, so a reading that jitters by a second is still the same week) and the key is kept in the state.
function Get-WeekKey([datetime]$ResetUtc) { $ResetUtc.ToUniversalTime().AddMinutes(30).ToString('yyyyMMddHH', [cultureinfo]::InvariantCulture) }
function Test-WeekWarn($Week, [string]$SavedKey, [datetime]$NowUtc) {
    if (-not $Week -or $null -eq $Week.Pct -or -not $Week.Reset) { return $null }
    if ($Week.Reset -le $NowUtc -or [double]$Week.Pct -lt 90) { return $null }
    $k = Get-WeekKey $Week.Reset
    if ($k -eq $SavedKey) { return $null }
    $k
}
# "Fri 9 AM", in local time.
function Get-WeekResetText([datetime]$ResetUtc) {
    $l = $ResetUtc.ToLocalTime()
    $l.ToString($(if ($l.Minute) { 'ddd h:mm tt' } else { 'ddd h tt' }), [cultureinfo]::InvariantCulture)
}
function Get-WeekWarnLine([datetime]$ResetUtc) { "🏮 The week's at 90%. It resets $(Get-WeekResetText $ResetUtc)." }

# A fresh window has one wording. After a routine reset (every ~5 hours of use) Tok is silent unless the window was nearly full.
function Get-FreshWindowLine { '🌱 Fresh window. Nothing spent yet.' }
function Test-FreshWindowBubble([double]$PctBefore) { $PctBefore -ge 0.85 }

# The window filling up: one word per window at 85% and one at 100%, keyed by the window's reset time (Get-WeekKey) and kept in
# the state. It said "100% of the window. Nearly full." on 10-10 and again after every turn end, since every return to the stuffed
# look said it. The level goes by the shown (rounded) percent; a jump straight past 100% says only the full line, and a guess
# says its number with "~" rather than "full". Asleep (the nightcap) still waits for Claude Code's own limit message.
function Get-FullWarn([double]$Pct, [bool]$Real, $ResetUtc, [string]$SavedKey) {
    $shown = [math]::Round($Pct * 100)
    if (-not $ResetUtc -or $shown -lt 85) { return $null }
    $level = if ($shown -ge 100) { 100 } else { 85 }
    $wk = Get-WeekKey ([datetime]$ResetUtc)
    if ($SavedKey -in "$wk/100", "$wk/$level") { return $null }
    $line = if ($level -eq 100 -and $Real) { "🏮 The window's full.`nThe nightcap's next." }
            elseif ($level -eq 100) { "🏮 ~$shown% of the window.`nThe nightcap's next." }
            else { "🏮 $(if (-not $Real) { '~' })$shown% of the window.`nNearly full." }
    @{ Key = "$wk/$level"; Line = $line }
}
# An easter egg (10-11): now and then a needs-you bubble opens with Navi's line from Ocarina of Time. One in 20, from
# a uniform draw in [0, 1); the usual line stays under it, so the bubble still says what Claude wants.
$script:ListenOdds = 20
function Get-NeedsLine([string]$Line, [double]$U) { if ($U -lt 1.0 / $script:ListenOdds) { "Hey! Listen!`n$Line" } else { $Line } }

# The hover's word for the stuffed look: "full" once the shown percent reaches 100.
function Get-StuffedText([double]$Pct) { if ([math]::Round($Pct * 100) -ge 100) { 'full' } else { 'nearly full' } }

# Minions sent out in the background (an Agent call with run_in_background): Claude Code ends the main turn at once and wakes it
# with a task notification as each one finishes, so a turn end while one is still out is not the hand-over ("All yours." with
# three of them working, take 2 on 10-10). $Out: agent id -> @{ Session; At }, from the launch to its notification. One counts
# while it is young (10 minutes) or its transcript wrote in the last 3 minutes ($Seen: agent id -> last write), so one that died
# quietly stops holding turns; those are dropped from $Out. True when one of $Session's is still out.
function Test-AgentsOut([hashtable]$Out, [string]$Session, [hashtable]$Seen, [datetime]$Now) {
    $held = $false
    foreach ($id in @($Out.Keys)) {
        $a = $Out[$id]
        $live = ($Now - [datetime]$a.At).TotalMinutes -lt 10 -or ($Seen -and $Seen[$id] -and ($Now - [datetime]$Seen[$id]).TotalSeconds -lt 180)
        if (-not $live) { $Out.Remove($id); continue }
        if ($a.Session -eq $Session) { $held = $true }
    }
    $held
}

# The first prompt after more than 6 quiet hours gets one stretch and no words.
function Test-QuietReturn([datetime]$LastMainUtc, [datetime]$NowUtc) { ($NowUtc - $LastMainUtc).TotalHours -gt 6 }

# The first bubbles ever (parliament session 6, the stranger): who Tok is and what it reads, what the lantern is, where the
# switch lives and what it is set to. Said once, in order, 7 s each (tok.ps1 Step-Greeting). Two lines of at most 33 characters.
function Get-FirstBubbles {
    @(
        "I'm Tok, Claude in a small body.`nI only read your transcripts."
        "🏮 My lantern is your 5-hour`nusage. Hover for the numbers."
        "Right-click me for Settings.`nExact usage is off until you ask."
    )
}
# The egg's line: what it is waiting for, said at startup and in the render.
function Get-EggLine { "Still in the egg. I hatch`non our first day of work." }

# Lines. Sentence case, one ellipsis character, no fake yawns.
function Get-LateNightLine([datetime]$Local, [string]$Name) { "It's $($Local.ToString('h:mm', [cultureinfo]::InvariantCulture))$(if ($Name) { ", $Name" }). Just noting it." }
function Get-DreamRecallLine([string]$Subject) { "…I dreamt about $Subject." }
# A minion's "is done" line only when its subagent ran over 45 s; the honey pour says the rest.
function Test-MinionRanLong([datetime]$First, [datetime]$Seen) { ($Seen - $First).TotalSeconds -gt 45 }

# A one-shot DispatcherTimer: runs $Action (with $ArgList) once, $Ms from now. The timers are kept here until they fire so none is collected early.
$script:Later = [System.Collections.Generic.List[object]]::new()
function Start-Later([int]$Ms, [scriptblock]$Action, [object[]]$ArgList = @()) {
    $t = [Windows.Threading.DispatcherTimer]::new()
    $t.Interval = [TimeSpan]::FromMilliseconds([math]::Max(1, $Ms))
    $t.Tag = @{ Action = $Action; Args = $ArgList }
    $t.Add_Tick({
        param($tm, $e)
        $tm.Stop(); $null = $script:Later.Remove($tm)
        $job = $tm.Tag; $jobArgs = @($job.Args)
        try { & $job.Action @jobArgs } catch { try { Write-BodyLog "later: $_" } catch { } }
    })
    $script:Later.Add($t)
    $t.Start()
}

function Save-PetJson($Object, [string]$Name) {
    $null = New-Item -ItemType Directory -Force $script:DataDir
    $path = Join-Path $script:DataDir $Name
    $tmp = "$path.tmp"
    $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding utf8
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Read-PetJson([string]$Name) {
    $path = Join-Path $script:DataDir $Name
    if (-not (Test-Path $path)) { return $null }
    try { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -DateKind String } catch { $null }
}

function Get-BodyConfig {
    $defaults = @{
        LimitUsd   = $null       # API-equivalent $ in one 5-hour window for the guess; null = by plan (Get-PlanLimitUsd), calibrate.ps1 sets it
        LiveUsage  = $false      # ask Anthropic for the exact 5-hour numbers, with Claude Code's login (right-click > Settings > Exact usage)
        Follow     = $true       # perch on the active window
        BubbleFontSize = 16      # speech bubble text size
        Chatter    = 'normal'    # chatty: every tool call | normal: tasks, questions, done | quiet: only when it needs you
        YourName   = ''          # what Tok calls you; empty = no name
        Private    = $false      # private mode by hand: no details in bubbles, sunglasses on (right-click or private.ps1)
        PrivateUntil = $null     # private mode on a timer (ISO UTC); set by private.ps1 -Minutes or the auto check
        PrivateMinutes = 15      # how long the auto check keeps Tok private after something sensitive-looking
        PrivatePatterns = $null  # regexes that count as sensitive; null = the defaults in lib\Privacy.ps1
        Sound      = $true       # a small pip when Claude needs you or a long turn is done (right-click → Sound)
        QuietFrom  = 23          # no pips from this hour...
        QuietTo    = 7           # ...until this one (local time)
    }
    $c = Read-PetJson 'config.json'
    if ($c) { foreach ($k in $c.Keys) { $defaults[$k] = $c[$k] } }
    $defaults
}

# Writes one key into config.json and nothing else of the defaults: the file's own content plus this key. A file that exists but
# does not parse is left alone (returns false).
function Set-ConfigFileKey([string]$Key, $Value) {
    $path = Join-Path $script:DataDir 'config.json'
    $c = if (Test-Path -LiteralPath $path) { Read-PetJson 'config.json' } else { @{} }
    if ($null -eq $c) { return $false }
    $c[$Key] = $Value
    Save-PetJson $c 'config.json'
    $true
}

# An install from before the exact-usage switch (parliament session 6) has a state.json with no Greeted key. Its owner already
# had the live call on, so it keeps it: Greeted is set (no first bubbles for someone who has lived with Tok) and LiveUsage: true
# is written once if config.json has no LiveUsage key. $State is the state as loaded from disk (null for a brand-new Tok);
# $FileConfig is config.json's own content, not merged with defaults (null when there is none).
function Get-OldInstallPlan($State, $FileConfig) {
    $old = [bool]($State -and -not $State.ContainsKey('Greeted'))
    @{ Old = $old; WriteLiveUsage = ($old -and -not ($FileConfig -and $FileConfig.ContainsKey('LiveUsage'))) }
}