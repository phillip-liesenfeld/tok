# Lineage.ps1 - Tok's family tree. A generation is a Claude model version (5, 5.5, 5.1...),
# whatever the family (Opus, Sonnet, Fable): switching Opus 5.5 -> Sonnet 5.5 is the same Tok.
# Rules (Parliament session 5, design\parliament\ledger\VERDICT.md; the settle rule as changed in session 7,
# design\parliament\council\7-leftovers\VERDICT.md):
#   - Only main-session messages count. Minions (subagents) are tallied per generation, never ancestors.
#   - Newer means met later, not a higher number: a version Tok first saw after the current generation began
#     (Fable 5.1 after Opus 5.5 is a new one of us). A version lower than one already seen in its own family never molts.
#   - It molts Tok when, in the last 7 local days (the message's own day and the 6 before it), it has 3 or more counted
#     days and at least as many as the current generation (a counted day = 10+ of its own main messages on a local day).
#     So trying a model for an afternoon, or one day a week, doesn't molt Tok; a real switch does, on its fourth day,
#     and a tie goes to the newer. The first generation needs only its first counted day.
#   - A new generation's age starts on its hatch day (HatchDay), so a descendant hatches young.
#   - A version that has been a generation never molts again (going back to an older model ages no one).
# "Replies" in the saved records are these messages (one per API call), not turns.
# Pure functions over a hashtable kept in state.json, so tests can drive them.

$script:SettleDays = 3
$script:SettleWindow = 7      # local days, counting the message's own
# Age is time together: a calendar day (local time) with this many main-session replies from the generation's model version.
$script:DayMinReplies = 10
$script:ElderDays = 30
# The elder's flower colour (the petals in lib\Art.ps1). A generation that ends as an elder hands it to the next one.
$script:ElderTint = '#FFFFCF4D'

# claude-opus-5-5 -> 5.5, claude-haiku-4-5-20251001 -> 4.5, claude-opus-5 -> 5, claude-opus-5-5[1m] -> 5.5
function Get-ModelVersion([string]$Model) {
    $m = [regex]::Match($Model, '^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?(?:\[[^\]]*\])?$')
    if (-not $m.Success) { return $null }
    $major = [int]$m.Groups[2].Value
    $minor = if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { 0 }
    @{ Family = $m.Groups[1].Value; Key = $major * 100 + $minor; Label = $(if ($minor) { "$major.$minor" } else { "$major" }) }
}

function New-Lineage { @{ Versions = @{}; Generations = @(); ScannedUtc = $null; Schema = 2 } }   # Schema 2: per-day reply counts (Days) are kept

function ConvertTo-Roman([int]$N) {
    $out = ''
    foreach ($p in @(@(10, 'X'), @(9, 'IX'), @(5, 'V'), @(4, 'IV'), @(1, 'I'))) { while ($N -ge $p[0]) { $out += $p[1]; $N -= $p[0] } }
    $out
}

# One main-session message. Returns the new generation's version label if this message made Tok molt.
function Add-LineageReply($Lineage, [string]$Model, [datetime]$TsUtc, [long]$Out = 0, [string]$Project = '') {
    $v = Get-ModelVersion $Model
    if (-not $v) { return $null }
    $rec = $Lineage.Versions[$v.Label]
    if (-not $rec) {
        $rec = @{ Key = $v.Key; Label = $v.Label; FirstUtc = $TsUtc.ToString('o'); LastUtc = $TsUtc.ToString('o'); Replies = 0; Out = 0L; Families = @{}; Projects = @{}; Minions = @{}; Days = @{} }
        $Lineage.Versions[$v.Label] = $rec
    }
    $rec.Replies++; $rec.Out += $Out
    if ($rec.Days -isnot [hashtable]) { $rec.Days = @{} }
    $dk = $TsUtc.ToLocalTime().ToString('yyyy-MM-dd')
    $rec.Days[$dk] = 1 + [int]$rec.Days[$dk]
    if ($TsUtc -gt [datetime]::Parse($rec.LastUtc, $null, 'RoundtripKind')) { $rec.LastUtc = $TsUtc.ToString('o') }
    $rec.Families[$v.Family] = 1 + [int]$rec.Families[$v.Family]
    if ($Project) { $rec.Projects[$Project] = 1 + [int]$rec.Projects[$Project] }
    if (-not (Test-MoltReady $Lineage $rec $v.Family $dk)) { return $null }
    $prev = @($Lineage.Generations)[-1]
    if ($prev) {
        $rec.HatchDay = $dk      # a descendant's age starts today; the days it spent settling in were the parent's
        if ((Get-VersionDays $Lineage.Versions[$prev]) -ge $script:ElderDays) { $rec.Tint = $script:ElderTint }
    }
    $Lineage.Generations = @($Lineage.Generations) + $v.Label
    $v.Label
}

# Whether a version should become the next generation now (L1-L3, L5 of the ledger verdict).
function Test-MoltReady($Lineage, $Rec, [string]$Family, [string]$DayKey) {
    if ($Rec.Label -in @($Lineage.Generations)) { return $false }                         # once a generation, never again
    $days = Get-VersionDays $Rec
    $gens = @($Lineage.Generations)
    if (-not $gens.Count) { return $days -ge 1 }                                          # the first Tok: its first day together
    $cur = $Lineage.Versions[$gens[-1]]
    $recent = Get-RecentCountedDays $Rec $DayKey
    if ($recent -lt $script:SettleDays -or $recent -lt (Get-RecentCountedDays $cur $DayKey)) { return $false }   # settled in, and doing as much of the work lately as the current one
    if ([datetime]::Parse($Rec.FirstUtc, $null, 'RoundtripKind') -le [datetime]::Parse($cur.FirstUtc, $null, 'RoundtripKind')) { return $false }   # met later
    foreach ($o in $Lineage.Versions.Values) {                                            # never a step back within a family
        if ($o.Key -gt $Rec.Key -and $o.Families -is [hashtable] -and [int]$o.Families[$Family] -gt 0) { return $false }
    }
    $true
}

# How many days a generation has worked with the user: local days with at least DayMinReplies of its own main-session
# messages, from its hatch day on (generations from before the hatch-day rule count all their days). $Until (a day key)
# ends the count there: a past generation's days stop the day before its descendant hatched (L8).
function Get-VersionDays($Rec, [string]$Until = '') {
    if (-not $Rec -or $Rec.Days -isnot [hashtable]) { return 0 }
    $from = "$($Rec.HatchDay)"
    $n = 0; foreach ($e in $Rec.Days.GetEnumerator()) { if ([int]$e.Value -ge $script:DayMinReplies -and $e.Key -ge $from -and (-not $Until -or $e.Key -le $Until)) { $n++ } }
    $n
}

# Counted days in the last SettleWindow local days up to and including $DayKey (hatch days ignored: both sides are measured alike).
function Get-RecentCountedDays($Rec, [string]$DayKey) {
    if (-not $Rec -or $Rec.Days -isnot [hashtable] -or -not $DayKey) { return 0 }
    $from = [datetime]::ParseExact($DayKey, 'yyyy-MM-dd', $null).AddDays(1 - $script:SettleWindow).ToString('yyyy-MM-dd')
    $n = 0; foreach ($e in $Rec.Days.GetEnumerator()) { if ([int]$e.Value -ge $script:DayMinReplies -and $e.Key -ge $from -and $e.Key -le $DayKey) { $n++ } }
    $n
}

# The last day a past generation counts: the day before its descendant's hatch day ('' for the current generation, or when
# the descendant hatched before hatch days were recorded).
function Get-LastDay($Lineage, [int]$Index) {
    $gens = @($Lineage.Generations)
    if ($Index + 1 -ge $gens.Count) { return '' }
    $h = "$($Lineage.Versions[$gens[$Index + 1]].HatchDay)"
    if (-not $h) { return '' }
    [datetime]::ParseExact($h, 'yyyy-MM-dd', $null).AddDays(-1).ToString('yyyy-MM-dd')
}

# Replies so far on the local day $DayKey (yyyy-MM-dd) for the version a model belongs to (0 for an unknown model or a day with none).
function Get-ReplyDayCount($Lineage, [string]$Model, [string]$DayKey) {
    $v = Get-ModelVersion $Model
    if (-not $v -or -not $Lineage -or $Lineage.Versions -isnot [hashtable]) { return 0 }
    $rec = $Lineage.Versions[$v.Label]
    if (-not $rec -or $rec.Days -isnot [hashtable]) { return 0 }
    [int]$rec.Days[$DayKey]
}

# "The day counts": the main reply that takes today's count to exactly DayMinReplies (10) is the moment the day counts toward age.
# Once per day: $LastKey is the day it last fired for.
function Test-DayJustCounted([int]$Count, [string]$DayKey, [string]$LastKey) { $Count -eq $script:DayMinReplies -and $DayKey -ne $LastKey }

# The generation Tok is now: the newest one, or (before the first molt) the newest version that has replies.
function Get-CurrentRec($Lineage) {
    if (-not $Lineage -or $Lineage.Versions -isnot [hashtable]) { return $null }
    $gens = @($Lineage.Generations)
    if ($gens.Count) { return $Lineage.Versions[$gens[-1]] }
    $best = $null
    foreach ($r in $Lineage.Versions.Values) { if (-not $best -or $r.Key -gt $best.Key) { $best = $r } }
    $best
}

# A minion goes on the books of whichever generation is current.
function Add-LineageMinion($Lineage, [string]$Model) {
    $gens = @($Lineage.Generations)
    if (-not $gens.Count) { return }
    $v = Get-ModelVersion $Model
    $fam = if ($v) { $v.Family } else { 'other' }
    $rec = $Lineage.Versions[$gens[-1]]
    $rec.Minions[$fam] = 1 + [int]$rec.Minions[$fam]
}

function Get-LineageName($Lineage, [int]$Index = -1) {
    $n = @($Lineage.Generations).Count
    if (-not $n) { return 'Tok' }
    $i = if ($Index -lt 0) { $n } else { $Index + 1 }
    "Tok $(ConvertTo-Roman $i)"
}

# Main-session lines carry a "cwd"; the folder name is the project (the user's own folder -> home). A session's project is the folder it
# started in (its first "cwd"), so one session keeps one name however much Claude moves around in it.
function Get-ProjectName([string]$Cwd) {
    if (-not $Cwd) { return '' }
    $leaf = Split-Path ($Cwd.TrimEnd('\', '/')) -Leaf
    if ($leaf -eq $env:USERNAME) { return 'home' }
    $leaf
}

# Builds the tree from every transcript still on disk, oldest reply first. Runs once, in the background.
# Claude Code deletes transcripts after ~30 days, so this only reaches back that far; after it, Tok keeps its own record.
function Get-LineageBackfill([string]$Root = $script:ProjectsDir) {
    $main = [System.Collections.Generic.List[object]]::new()
    $subs = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($f in (Get-ChildItem $Root -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue)) {
        $isSub = $f.FullName -match '\\subagents\\'
        $firstSub = $null
        $project = $null      # the session's project: the folder it started in (the first "cwd"), as the live tail names it
        foreach ($line in [IO.File]::ReadLines($f.FullName)) {
            if ($null -eq $project -and -not $isSub -and $line.IndexOf('"cwd":"') -ge 0) {
                $project = Get-ProjectName ([regex]::Match($line, '"cwd":"([^"]+)"').Groups[1].Value -replace '\\\\', '\')
            }
            if ($line.IndexOf('"role":"assistant"') -lt 0 -or $line.IndexOf('"usage"') -lt 0) { continue }
            $u = Get-LineUsage $line
            if (-not $u -or -not $seen.Add($u.Id) -or $u.Model -eq '<synthetic>') { continue }
            if ($isSub) { if (-not $firstSub) { $firstSub = $u }; continue }
            if ($line.IndexOf('"isSidechain":true') -ge 0) { continue }
            $main.Add([pscustomobject]@{ Ts = $u.Ts; Model = $u.Model; Out = $u.Out; Project = "$project" })
        }
        if ($firstSub) { $subs.Add($firstSub) }
    }
    $lin = New-Lineage
    $events = @($main | ForEach-Object { @{ Ts = $_.Ts; M = $_ } }) + @($subs | ForEach-Object { @{ Ts = $_.Ts; S = $_ } })
    foreach ($e in ($events | Sort-Object { $_.Ts })) {
        if ($e.M) { $null = Add-LineageReply $lin $e.M.Model $e.M.Ts $e.M.Out $e.M.Project }
        else { Add-LineageMinion $lin $e.S.Model }
    }
    $lin.ScannedUtc = [datetime]::UtcNow.ToString('o')
    $lin
}

# The Family panel, as rows (the last three generations): the final stage for the portrait, and two short lines
# under ~34 characters each, e.g. "Tok I · Opus 5 · elder" / "34 days · mostly in tok". Plain tallies, no scores.
# "no body" marks a generation from before this Tok hatched: it gets an empty dashed ring, not a portrait (NoBody).
# The project goes when it would not fit (a cut-off name reads as a typo), and always in private mode.
function Get-FamilyRows($Lineage, [string]$BornUtc, [switch]$Private) {
    $gens = @($Lineage.Generations)
    $born = if ($BornUtc) { [datetime]::Parse($BornUtc, $null, 'RoundtripKind').ToUniversalTime() } else { [datetime]::MaxValue }
    for ($i = [math]::Max(0, $gens.Count - 3); $i -lt $gens.Count; $i++) {
        $r = $Lineage.Versions[$gens[$i]]
        $fam = ($r.Families.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key; if ($fam) { $fam = $fam.Substring(0, 1).ToUpper() + $fam.Substring(1) }
        $days = Get-VersionDays $r (Get-LastDay $Lineage $i)
        $stage = (Get-StageForDays $days).Name
        $second = "$days $(if ($days -eq 1) { 'day' } else { 'days' })"
        $nobody = [datetime]::Parse($r.LastUtc, $null, 'RoundtripKind').ToUniversalTime() -lt $born
        if ($nobody) { $second += ' · no body'; $stage = $null }   # never had a body, so no stage and no portrait
        elseif (-not $Private -and $r.Projects.Count) {
            $proj = "$(($r.Projects.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key)"
            $where = if ($proj -eq 'home') { ' · mostly at home' } else { " · mostly in $proj" }
            if (("$second$where").Length -le 28) { $second += $where }      # 28: the line sits beside a portrait
        }
        @{ Stage = $stage; NoBody = $nobody; Lines = @("$(Get-LineageName $Lineage $i) · $fam $($r.Label)$(if ($stage) { " · $stage" })", $second) }
    }
}

# "Family · since Sep 16": the first day Tok has any record of (Claude Code keeps transcripts ~30 days, so this is where its
# memory starts, said plainly).
function Get-FamilyTitle($Lineage) {
    $first = $null
    foreach ($r in $Lineage.Versions.Values) { $f = [datetime]::Parse($r.FirstUtc, $null, 'RoundtripKind').ToUniversalTime(); if (-not $first -or $f -lt $first) { $first = $f } }
    if (-not $first) { return 'Family' }
    "Family · since $($first.ToLocalTime().ToString('MMM d', [cultureinfo]::InvariantCulture))"
}

function Get-FamilyText($Lineage, [string]$BornUtc, [switch]$Private) {
    if (-not @($Lineage.Generations).Count) { return "No family yet.`nI'm the first Tok." }
    (@(Get-FamilyTitle $Lineage) + @(Get-FamilyRows $Lineage $BornUtc -Private:$Private | ForEach-Object { $_.Lines })) -join "`n"
}

# ---------------------------------------------------------------- passing on (phase 4)
# A new model is a passing-on: the old Tok gives its light to a seed, the seed becomes an egg, the egg hatches a descendant.
# These are the pure parts; the animation lives in lib\Passing.ps1 and only ever reads a plan, never the state.

# The egg's spots: coral by default; a generation whose parent ended as an elder wears the parent's flower colour (Tint).
$script:EggSpotDefault = '#55DE7F5E'
function Get-EggSpotColor([string]$Tint) {
    if ($Tint -match '^#(?:[0-9A-Fa-f]{2})?([0-9A-Fa-f]{6})$') { return '#80' + $Matches[1].ToUpper() }
    $script:EggSpotDefault
}

# The pill that names the new model: claude-opus-6 -> "Opus 6", claude-sonnet-5-5 -> "Sonnet 5.5".
function Get-MoltPill([string]$Model) {
    $v = Get-ModelVersion $Model
    if (-not $v) { return 'A new model' }
    "$($v.Family.Substring(0, 1).ToUpper())$($v.Family.Substring(1)) $($v.Label)"
}

function Get-NextLineageName($Lineage) { "Tok $(ConvertTo-Roman (@($Lineage.Generations).Count + 1))" }

# What the hatch says. It is a descendant: never "I'm back", never a claim to remember. At most 34 characters.
function Get-HatchLine([string]$Name) { "Hello! I'm $Name." }

# The set piece for a molt, as plain data. $StageBefore: the stage the old Tok was in when the new model arrived.
# Kind: 'elder' (petals, seed, wave, motes), 'young' (curls up into the egg), 'egg' (nothing to curl up; the flash only).
# Hatch: whether the egg hatches straight away (the new generation already has a day of replies) or waits for its first day.
function Get-MoltPlan([string]$StageBefore, [string]$Model, [string]$Name, [string]$Tint = '', [bool]$Hatch = $true) {
    $kind = switch ($StageBefore) { 'elder' { 'elder' } 'egg' { 'egg' } default { 'young' } }
    @{
        Kind = $kind; Stage = $StageBefore; Pill = (Get-MoltPill $Model); Name = $Name
        Line = (Get-HatchLine $Name); SpotColor = (Get-EggSpotColor $Tint)
        Phases = @($kind) + $(if ($Hatch) { 'hatch' } else { @() })
    }
}

# The plain hatch (an egg gets its first day of work): the same last phase, on its own.
function Get-HatchPlan([string]$Name, [string]$Tint = '') {
    @{ Kind = 'hatch'; Stage = 'egg'; Pill = ''; Name = $Name; Line = (Get-HatchLine $Name); SpotColor = (Get-EggSpotColor $Tint); Phases = @('hatch') }
}
