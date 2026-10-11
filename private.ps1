# private.ps1 - private mode for Tok: it keeps living, but bubbles stop showing file names, commands,
# searches, task names and projects, it stops dreaming about them, and it won't record. It wears sunglasses.
#   .\private.ps1                 on, until you turn it off
#   .\private.ps1 -Minutes 30     on for 30 minutes
#   .\private.ps1 -Off            back to normal
#   .\private.ps1 -Quit           close Tok entirely (start it again from the Start menu)
#   .\private.ps1 -Status         is it private right now?
param(
    [double]$Minutes = 0,
    [switch]$Off,
    [switch]$Quit,
    [switch]$Status,
    [string]$Why = 'private.ps1'
)
$dir = if ($env:TOK_DATA_DIR) { $env:TOK_DATA_DIR } else { Join-Path $env:LOCALAPPDATA 'tok' }      # TOK_DATA_DIR: a second, separate Tok
$null = New-Item -ItemType Directory -Force $dir
$inbox = Join-Path $dir 'inbox.jsonl'
$running = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -like '*tok.ps1*' -and $_.CommandLine -notmatch '-(Demo|MinionDemo|Showcase|Molt|Bench|RenderDir|Mood|Stage)\b' })

if ($Status) {
    . (Join-Path $PSScriptRoot 'lib\Pet.ps1'); . (Join-Path $PSScriptRoot 'lib\Privacy.ps1')
    $c = Get-BodyConfig
    $state = if (-not $running) { 'not running' } elseif (Test-PrivateNow $c) { if ($c.Private) { 'private (until turned off)' } else { "private until $([datetime]::Parse($c.PrivateUntil, $null, 'RoundtripKind').ToLocalTime().ToString('h:mm tt'))" } } else { 'normal' }
    "Tok: $state"
    return
}

if ($Quit) {
    if (-not $running) { 'Tok is not running.'; return }
    $msg = [ordered]@{ cmd = 'quit'; why = $Why; at = [datetime]::UtcNow.ToString('o') }
    Add-Content -LiteralPath $inbox -Value ($msg | ConvertTo-Json -Compress) -Encoding utf8
    # Tok checks its inbox every ~0.75 s; if it hasn't closed in 5 s, stop it.
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline -and (Get-Process -Id $running.ProcessId -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 250 }
    $left = Get-Process -Id $running.ProcessId -ErrorAction SilentlyContinue
    if ($left) { $left | Stop-Process -Force; 'Tok stopped (forced).' } else { 'Tok closed.' }
    return
}

# On/off is written to the config too, so it holds even if Tok isn't running or restarts.
. (Join-Path $PSScriptRoot 'lib\Pet.ps1')
$c = Get-BodyConfig
if ($Off) { $c.Private = $false; $c.PrivateUntil = $null }
elseif ($Minutes -gt 0) { $c.PrivateUntil = [datetime]::UtcNow.AddMinutes($Minutes).ToString('o') }
else { $c.Private = $true }
Save-PetJson $c 'config.json'
$msg = [ordered]@{ cmd = 'private'; on = (-not $Off); minutes = $Minutes; why = $Why; at = [datetime]::UtcNow.ToString('o') }
Add-Content -LiteralPath $inbox -Value ($msg | ConvertTo-Json -Compress) -Encoding utf8
if ($Off) { 'Tok: back to normal.' } elseif ($Minutes -gt 0) { "Tok: private for $Minutes minutes." } else { 'Tok: private until you turn it off (.\private.ps1 -Off).' }
if (-not $running) { '(Tok is not running; the setting is saved for when it starts.)' }
