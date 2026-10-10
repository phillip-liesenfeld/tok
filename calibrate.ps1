# calibrate.ps1 - tell the body what % your usage panel shows right now, so its
# "% of the 5-hour window" estimate matches. Example: .\calibrate.ps1 18
param([Parameter(Mandatory)][double]$Percent)
. (Join-Path $PSScriptRoot 'lib\Transcripts.ps1')
. (Join-Path $PSScriptRoot 'lib\Pet.ps1')
$w = Get-SessionWindow (Get-RecentUsage 24)
if (-not $w.Active -or $Percent -le 0) { throw 'No 5-hour window is open right now (or percent is 0); try again mid-session.' }
$c = Get-BodyConfig
$c.LimitUsd = [math]::Round($w.Cost / ($Percent / 100), 2)
Save-PetJson $c 'config.json'
"Window so far: `${0:N2} API-equivalent = {1}% -> full window ~ `${2:N2}. Saved; the body picks it up within 30s." -f $w.Cost, $Percent, $c.LimitUsd
